defmodule ExMux.Clock do
  @doc """
  Return current time in 27M
  """
  def now do
    :erlang.monotonic_time 27000000
  end
end
