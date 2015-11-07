defmodule ExMux.Spooler do
  use GenServer

  @dejitter_buffer 500 # 500ms dejittering buffer
  @null_pkt <<0x47, 0 :: 3, 0x1FFF :: 13, 0 :: 1480>> # 1480 bits => 185 bytes
  @null_pkt7 @null_pkt <> @null_pkt <> @null_pkt <> @null_pkt <> @null_pkt <> @null_pkt <> @null_pkt

  defmodule Config do
    defstruct bitrate: 1000000,
    dst: {239,0,0,1},
    ifaddr: {192,168,11,33},
    dst_port: 25000
  end

  def test do
    ExMux.PktQueue.start
    ExMux.Spooler.start %Config{}
    spawn fn -> test_loop end
  end

  def test_loop do
    ExMux.Spooler.tick({ExMux.Clock.now})
    :timer.sleep(5)
    test_loop
  end

  def start(config) do
    GenServer.start_link(__MODULE__, config, name: __MODULE__)
  end

  # to be moved to other module
  def stream({packet, recv_time}) do
    %ExMux.Pkt{ data: packet, size: length(packet), t: recv_time + @dejitter_buffer}
    |> ExMux.PktQueue.put
  end

  def tick({time}) do
    GenServer.call(__MODULE__, {:tick, time})
  end

  def info do
    GenServer.call(__MODULE__, :info)
  end

  def handle_call({:tick, time}, _from, %{last_tick: :invalid} = state) do
    # just pop from the queue and drop it for initial tick
    ExMux.PktQueue.pop_with_time(time)
    {:reply, :ok, %{state | last_tick: time}}
  end

  def handle_call({:tick, time}, _from, %{config: config, last_tick: last, udp: udp_sock} = state) do
    # calling server to get packets from queue server with send time >= time
    # calculate the number of bytes require to send in current and previous tick
    # compare the bytes we could get and do adjustments
    pkts = ExMux.PktQueue.pop_with_time(time)
    required_bytes = ((time - last) / 27000000 * config.bitrate / 8 ) + state.carry
    rounded = round(required_bytes)

    # TODO: pumping the exact number of rounded bytes to network
    # if pkts total size > rounded, need to stop it anyway and drop remaining,
    # we are overflowing.
    # otherwise, fill null pkts to maintain bitrate
    extra_sent_bytes = flush_pkts(pkts, rounded, state) # extra sent bytes is a negative num

    {:reply, :ok, %{state | last_tick: time, carry: rounded - required_bytes + extra_sent_bytes, last_req_bytes: required_bytes, rounded: rounded}}
  end

  def handle_call(:info, _from, state) do
    {:reply, state, state}
  end

  def init(config) do
    {:ok, udp_sock} = :gen_udp.open(0, [:binary, {:active, false}, {:reuseaddr, true},
                                        {:broadcast, true}, {:add_membership, {config.dst, config.ifaddr}}])
    state = %{
      config: config,
      last_tick: :invalid,
      carry: 0,
      last_req_bytes: 0,
      rounded: 0,
      udp: udp_sock
    }
    {:ok, state}
  end

  defp flush_pkts([], nBytes, state) when nBytes > 0 do
    :gen_udp.send(state.udp, state.config.dst, state.config.dst_port, @null_pkt)
    flush_pkts([], nBytes - 188, state)
  end

  defp flush_pkts([pkt | rem_pkts], nBytes, state) when nBytes > 0 do
    :gen_udp.send(state.udp, state.config.dst, state.config.dst_port, pkt)
    flush_pkts(rem_pkts, nBytes - pkt.size, state)
  end

  defp flush_pkts(_, nBytes, _) do
    # nBytes are done.
    # end of send
    nBytes
  end
end
