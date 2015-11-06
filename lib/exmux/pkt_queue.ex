defmodule ExMux.Pkt do
  defstruct data: <<>>,
            size: 0,
            t: 0 # send time
end

defmodule ExMux.PktQueue do
  use GenServer

  def start do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def put(pkt) do
    GenServer.cast(__MODULE__, {:put, pkt})
  end

  def pop_with_time(t) do
    GenServer.call(__MODULE__, {:pop_with_time, t})
  end

  def init(:ok) do
    {:ok, :queue.new}
  end

  def handle_cast({:put, pkt}, q) do
    {:noreply, :queue.in(pkt, q)}
  end

  def handle_call({:pop_with_time, t}, _from, q) do
    {pkts, q2} = get_pkt_with_time(t, q)
    {:reply, pkts, q2}
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
