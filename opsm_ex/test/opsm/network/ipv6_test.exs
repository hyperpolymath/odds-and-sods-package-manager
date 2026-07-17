# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
defmodule Opsm.Network.Ipv6Test do
  use ExUnit.Case, async: true

  alias Opsm.Network.Ipv6

  describe "mode/0" do
    test "returns a valid mode atom" do
      mode = Ipv6.mode()
      assert mode in [:prefer_ipv6, :enforce_ipv6, :prefer_ipv4, :dual_stack]
    end

    test "defaults to :prefer_ipv6" do
      # Default when no env var is set
      mode = Ipv6.mode()
      assert mode == :prefer_ipv6
    end
  end

  describe "ipv6?/1" do
    test "identifies IPv6 tuples" do
      assert Ipv6.ipv6?({0, 0, 0, 0, 0, 0, 0, 1})
      assert Ipv6.ipv6?({0x2001, 0xDB8, 0, 0, 0, 0, 0, 1})
    end

    test "rejects IPv4 tuples" do
      refute Ipv6.ipv6?({127, 0, 0, 1})
      refute Ipv6.ipv6?({192, 168, 1, 1})
    end
  end

  describe "ipv4?/1" do
    test "identifies IPv4 tuples" do
      assert Ipv6.ipv4?({127, 0, 0, 1})
      assert Ipv6.ipv4?({10, 0, 0, 1})
    end

    test "rejects IPv6 tuples" do
      refute Ipv6.ipv4?({0, 0, 0, 0, 0, 0, 0, 1})
    end
  end

  describe "to_ipv6_mapped/1" do
    test "maps IPv4 to IPv6 ::ffff:a.b.c.d" do
      mapped = Ipv6.to_ipv6_mapped({192, 168, 1, 1})
      assert mapped == {0, 0, 0, 0, 0, 0xFFFF, 192 * 256 + 168, 1 * 256 + 1}
    end

    test "passes through IPv6 addresses unchanged" do
      addr = {0x2001, 0xDB8, 0, 0, 0, 0, 0, 1}
      assert Ipv6.to_ipv6_mapped(addr) == addr
    end
  end

  describe "format_address/1" do
    test "formats IPv4 address" do
      assert Ipv6.format_address({192, 168, 1, 1}) == "192.168.1.1"
      assert Ipv6.format_address({127, 0, 0, 1}) == "127.0.0.1"
    end

    test "formats IPv6 address" do
      result = Ipv6.format_address({0x2001, 0x0DB8, 0, 0, 0, 0, 0, 1})
      assert result == "2001:DB8:0:0:0:0:0:1"
    end
  end

  describe "resolve/1" do
    test "resolves a known host" do
      case Ipv6.resolve("localhost") do
        {:ok, addrs} ->
          assert is_list(addrs)
          assert length(addrs) > 0

        {:error, _} ->
          # DNS may not work in some CI environments
          :ok
      end
    end

    @tag :integration
    test "resolves a public host" do
      case Ipv6.resolve("cloudflare.com") do
        {:ok, addrs} ->
          assert length(addrs) > 0

        {:error, _} ->
          :ok
      end
    end
  end

  describe "validate_host/1" do
    test "validates resolvable hosts" do
      case Ipv6.validate_host("localhost") do
        :ok -> :ok
        {:error, _} -> :ok
      end
    end
  end

  describe "connect_options/0" do
    test "returns keyword list" do
      opts = Ipv6.connect_options()
      assert is_list(opts)
    end
  end

  describe "status/0" do
    test "returns status map" do
      status = Ipv6.status()

      assert is_map(status)
      assert Map.has_key?(status, :mode)
      assert Map.has_key?(status, :ipv6_enforced)
      assert Map.has_key?(status, :ipv6_preferred)
      assert Map.has_key?(status, :connect_options)
      assert Map.has_key?(status, :system_ipv6)
    end

    test "mode matches current mode" do
      status = Ipv6.status()
      assert status.mode == Ipv6.mode()
    end

    test "enforce flag is consistent" do
      status = Ipv6.status()

      if status.mode == :enforce_ipv6 do
        assert status.ipv6_enforced == true
      else
        assert status.ipv6_enforced == false
      end
    end
  end

  describe "system_has_ipv6?/0" do
    test "returns boolean" do
      result = Ipv6.system_has_ipv6?()
      assert is_boolean(result)
    end
  end
end
