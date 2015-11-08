defmodule ExMux.Spooler do
  use GenServer

  @dejitter_buffer 500 # 500ms dejittering buffer
  @null_pkt <<0x47, 0 :: 3, 0x1FFF :: 13, 0 :: 1480>> # 1480 bits => 185 bytes
  @null_pkt7 @null_pkt <> @null_pkt <> @null_pkt <> @null_pkt <> @null_pkt <> @null_pkt <> @null_pkt

  defmodule Config do
    defstruct bitrate: 3000000,
    dst: {239,0,0,1},
    ifaddr: {192,168,11,33},
    dst_port: 25000,
    stuff_null: true
  end

  def test do
    ExMux.PktQueue.start
    ExMux.Spooler.start %Config{}
    spawn fn -> ExMux.UdpRecv.start end
    :timer.sleep(1000)
    spawn fn -> run_test_loop end
  end

  def run_test_loop do
    :erlang.process_flag(:priority, :max)
    test_loop
  end

  def test_loop do
    ExMux.Spooler.tick({ExMux.Clock.now})
    :timer.sleep(200)
    test_loop
  end

  def start(config) do
    GenServer.start_link(__MODULE__, config, name: __MODULE__)
  end

  def tick({time}) do
    GenServer.call(__MODULE__, {:tick, time - (27000 * @dejitter_buffer)})
  end

  def info do
    GenServer.call(__MODULE__, :info)
  end

  def handle_call({:tick, time}, _from, %{last_tick: :invalid} = state) do
    # swap the buffer from buffer queue
    # and just pop expired pkts from the queue and mark time for initial tick
    q = ExMux.PktQueue.consume
    #{_, q} = get_pkt_with_time(time, q)
    {:reply, :ok, %{state | last_tick: time, queue: q}}
  end

  def handle_call({:tick, time}, _from, %{config: config, last_tick: last, udp: udp_sock} = state) do
    # calling server to get packets from queue server with send time >= time
    # calculate the number of bytes require to send in current and previous tick
    # compare the bytes we could get and do adjustments
    {pkts, q} = get_pkt_with_time(time, state.queue)
    if (:queue.is_empty q) do
      # We could not swap consume the pkt queue too much as it will interrupt the performance
      q = ExMux.PktQueue.consume
      IO.puts "Swapping"
      {extra_pkts, q} = get_pkt_with_time(time, q)
      pkts = pkts ++ extra_pkts
    end
    required_bytes = ((time - last) / 27000000 * config.bitrate / 8 ) + state.carry
    rounded = round(required_bytes)

    # TODO: pumping the exact number of rounded bytes to network
    # if pkts total size > rounded, need to stop it anyway and drop remaining,
    # we are overflowing.
    # otherwise, fill null pkts to maintain bitrate
    extra_sent_bytes = flush_pkts(pkts, rounded, state) # extra sent bytes is a negative num

    {:reply, :ok, %{state | last_tick: time, carry: rounded - required_bytes + extra_sent_bytes,
                    last_req_bytes: required_bytes, rounded: rounded, queue: q}}
  end

  def handle_call(:info, _from, state) do
    {:reply, state, state}
  end

  def init(config) do
    :erlang.process_flag(:priority, :max)
    {:ok, udp_sock} = :gen_udp.open(0, [:binary, {:active, false}, {:reuseaddr, true},
                                        {:broadcast, true}, {:add_membership, {config.dst, config.ifaddr}}])
    state = %{
      config: config,
      last_tick: :invalid,
      carry: 0,
      last_req_bytes: 0,
      rounded: 0,
      queue: :empty,
      udp: udp_sock
    }
    {:ok, state}
  end

  defp flush_pkts([], nBytes, state) when nBytes >= 188 do
    case state.config.stuff_null do
      true ->
        :gen_udp.send(state.udp, state.config.dst, state.config.dst_port, @null_pkt)
        flush_pkts([], nBytes - 188, state)
      _ -> flush_pkts([], 0, state)
    end
  end

  defp flush_pkts([], nBytes, state) do
    # the last pkt we send is null
    nBytes
  end

  defp flush_pkts([pkt | rem_pkts], nBytes, state) when nBytes > 0 do
    :gen_udp.send(state.udp, state.config.dst, state.config.dst_port, pkt.data)
    flush_pkts(rem_pkts, nBytes - pkt.size, state)
  end

  defp flush_pkts(remain, nBytes, state) do
    # nBytes are done.
    # But we still have 'remain' bytes to send.
    # So it could be input jitter or input stream bitrate is wrong
    if remain != [] do
      IO.puts "Bitrate used up but still having remaing pkts: " <> to_string(length(remain))
      flush_pkts(remain, hd(remain).size, state)
    end
  end

  defp get_pkt_with_time(t, q) do
    get_pkt_with_time(t, q, [])
  end

  defp get_pkt_with_time(t, q, acc) do
    case :queue.out(q) do
      {{:value, %ExMux.Pkt{t: sendtime} = item}, q2} when sendtime <= t
        -> get_pkt_with_time(t, q2, [item | acc])
      _ -> { Enum.reverse(acc) , q}
    end
  end
end
