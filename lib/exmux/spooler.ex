defmodule ExMux.Spooler do
  use GenServer

  @dejitter_buffer 500 # 500ms dejittering buffer

  defmodule Config do
    defstruct bitrate: 1000000
  end

  def stream({packet, recv_time}) do
    %ExMux.Pkt{ data: packet, size: length(packet), t: recv_time + @dejitter_buffer}
    |> ExMux.PktQueue.put
  end

  def tick({time}) do
    # calling server to get packets from queue server with send time >= time
    # calculate the number of bytes require to send in current and previous tick
    # compare the bytes we could get and do adjustments
    pkts = ExMux.PktQueue.pop_with_time(time)
  end

  def init(config) do
    s = %{
      config: config,
      udp: :udp_todo
    }
    {:ok, s}
  end
end
