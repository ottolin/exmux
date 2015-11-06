defmodule PktQueueTest do
  use ExUnit.Case

  setup_all do
    ExMux.PktQueue.start

    :ok
  end

  test "Put and Get Sanity" do
    pkt = %ExMux.Pkt{data: <<0x47>>, t: 999}
    ExMux.PktQueue.put(pkt)
    pkt = %ExMux.Pkt{data: <<0x47>>, t: 9998}
    ExMux.PktQueue.put(pkt)
    pkt = %ExMux.Pkt{data: <<0x47>>, t: 9999}
    ExMux.PktQueue.put(pkt)

    pkts = ExMux.PktQueue.pop_with_time(998)
    assert pkts == []
    pkts = ExMux.PktQueue.pop_with_time(999)
    assert length(pkts) == 1
    assert hd(pkts).t == 999

    pkts = ExMux.PktQueue.pop_with_time(10000)
    assert length(pkts) == 2
    assert hd(pkts).t == 9998

    pkts = ExMux.PktQueue.pop_with_time(10000)
    assert pkts == []
  end
end
