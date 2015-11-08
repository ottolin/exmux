defmodule ExMux.Pkt do
  defstruct data: <<>>,
            size: 0,
            t: 0 # recv time
end

defmodule ExMux.PktQueue do
  use GenServer

  def start do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def put(pkt) do
    GenServer.cast(__MODULE__, {:put, pkt})
  end

  def consume do
    GenServer.call(__MODULE__, {:consume})
  end

  def info do
    GenServer.call(__MODULE__, :info)
  end

  def init(:ok) do
    :erlang.process_flag(:priority, :max)
    {:ok, :queue.new}
  end

  def handle_call({:consume}, _from, state) do
    {:reply, state, :queue.new}
  end

  def handle_call(:info, _from, state) do
    {:reply, state, state}
  end

  def handle_cast({:put, pkt}, q) do
    {:noreply, :queue.in(pkt, q)}
  end

end
