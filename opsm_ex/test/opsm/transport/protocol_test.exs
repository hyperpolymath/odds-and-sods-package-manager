# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
defmodule Opsm.Transport.ProtocolTest do
  use ExUnit.Case, async: true

  alias Opsm.Transport.Protocol

  setup do
    Protocol.init()
    Protocol.clear_cache()
    :ok
  end

  describe "init/0" do
    test "creates the ETS cache table" do
      assert Protocol.init() == :ok
    end

    test "is idempotent" do
      assert Protocol.init() == :ok
      assert Protocol.init() == :ok
    end
  end

  describe "supported_protocols/0" do
    test "includes http2 and http1" do
      protos = Protocol.supported_protocols()
      assert :http2 in protos
      assert :http1 in protos
    end

    test "returns list of atoms" do
      protos = Protocol.supported_protocols()
      assert is_list(protos)
      assert Enum.all?(protos, &is_atom/1)
    end
  end

  describe "negotiate/1" do
    test "returns a valid protocol" do
      proto = Protocol.negotiate("example.com")
      assert proto in [:quic, :http2, :http1]
    end

    test "caches protocol for same host" do
      proto1 = Protocol.negotiate("cached-test.com")
      proto2 = Protocol.negotiate("cached-test.com")
      assert proto1 == proto2
    end
  end

  describe "force_protocol/2" do
    test "overrides negotiated protocol" do
      Protocol.force_protocol("forced.example.com", :http1)
      assert Protocol.negotiate("forced.example.com") == :http1
    end

    test "accepts :quic, :http2, :http1" do
      assert Protocol.force_protocol("test1.com", :quic) == :ok
      assert Protocol.force_protocol("test2.com", :http2) == :ok
      assert Protocol.force_protocol("test3.com", :http1) == :ok
    end
  end

  describe "record_latency/3" do
    test "records latency for a host" do
      Protocol.init()
      assert Protocol.record_latency("latency-host.com", :http2, 42) == :ok
    end

    test "accumulates multiple requests" do
      Protocol.init()
      Protocol.record_latency("multi-host.com", :http2, 100)
      Protocol.record_latency("multi-host.com", :http2, 200)

      stats = Protocol.host_stats("multi-host.com")
      assert stats.requests == 2
      assert stats.avg_latency_ms == 150
    end
  end

  describe "host_stats/1" do
    test "returns default stats for unknown host" do
      stats = Protocol.host_stats("unknown-host-1234.com")
      assert stats.requests == 0
      assert stats.avg_latency_ms == 0
    end
  end

  describe "clear_cache/0" do
    test "clears all cached protocols" do
      Protocol.force_protocol("clear-test.com", :http1)
      Protocol.clear_cache()
      # After clear, host will be re-probed (won't be :http1 forced)
      proto = Protocol.negotiate("clear-test.com")
      assert proto in [:quic, :http2, :http1]
    end
  end

  describe "quic_available?/0" do
    test "returns boolean" do
      result = Protocol.quic_available?()
      assert is_boolean(result)
    end
  end
end
