require Logger
defmodule ExMux.UdpRecv do
  @udp_size 1316
  defmodule Config do
    defstruct addr: "224.0.0.1",
    port: 1234,
    nic: "192.168.11.33",
    src: "192.168.11.33" #ssm TODO: change to ssm list?
  end

  def start do
    start(%Config{})
  end

  def start(arg) do
    {:ok, addr} = :inet_parse.address(String.to_char_list(arg.addr))
    {:ok, nic} = :inet_parse.address(String.to_char_list(arg.nic))
    {:ok, src} = :inet_parse.address(String.to_char_list(arg.src))
    {:ok, socket} = :gen_udp.open(arg.port, [:binary, {:recbuf, 10240000}, {:reuseaddr, true}, {:active, false}, {:ip, addr}, {:multicast_if, nic}])

    # raw udp for igmpv3 support.
    nicbin = nic |> :erlang.tuple_to_list |> :erlang.list_to_binary
    gpbin = addr |> :erlang.tuple_to_list |> :erlang.list_to_binary
    srcbin = src |> :erlang.tuple_to_list |> :erlang.list_to_binary

    bin = << gpbin::binary, nicbin::binary, srcbin::binary >>
    :inet.setopts(socket, [{:raw, 0, 39, bin}])

    :erlang.process_flag(:priority, :max)
    recv_loop(socket, 0, ExMux.Clock.now)
  end

  defp recv_loop(socket, cnt, t) do
    rv = :gen_udp.recv(socket, @udp_size)
    case rv do
      {:ok, {_addr, _port, pkt}} ->
        {ncnt, now} = notify_recv(pkt, cnt)
        cnt = cnt + 1316
        if (now - t > 27000000) do
          bitrate = (ncnt * 8 ) * ((now - t) / 27000000)
          IO.puts "Bitrate: " <> to_string(bitrate)
          t = now
          cnt = 0
        end
        recv_loop(socket, cnt, t)
      _ -> Logger.error "Failed to recv from socket."
    end
  end

  defp notify_recv(pkt, cnt) do
    s = @udp_size
    %ExMux.Pkt{data: pkt, size: s, t: ExMux.Clock.now}
    |> ExMux.PktQueue.put

    {s + cnt, ExMux.Clock.now}
  end

end
