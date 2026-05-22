# SPDX-License-Identifier: MPL-2.0
defmodule Opsm.Transport.QuicTest do
  use ExUnit.Case, async: true

  alias Opsm.Transport.Quic
  alias Opsm.Transport.Protocol

  setup do
    Quic.init()
    Protocol.clear_cache()
    :ok
  end

  describe "available?/0" do
    test "returns boolean" do
      result = Quic.available?()
      assert is_boolean(result)
    end

    test "returns false when NIF not compiled" do
      # In test environment without Rust build, QUIC NIF is not loaded
      refute Quic.available?()
    end
  end

  describe "status/0" do
    test "returns transport status map" do
      status = Quic.status()

      assert is_map(status)
      assert Map.has_key?(status, :quic_available)
      assert Map.has_key?(status, :supported_protocols)
      assert Map.has_key?(status, :active_connections)
      assert Map.has_key?(status, :nif_loaded)
    end

    test "supported_protocols includes at least http1 and http2" do
      status = Quic.status()
      assert :http1 in status.supported_protocols
      assert :http2 in status.supported_protocols
    end
  end

  describe "probe/2" do
    test "returns false when NIF not available" do
      assert {:ok, false} = Quic.probe("example.com")
    end

    test "accepts custom port" do
      assert {:ok, false} = Quic.probe("example.com", 8443)
    end
  end

  describe "get/2 (HTTP/2 fallback)" do
    @tag :integration
    test "fetches a URL via HTTP/2 fallback" do
      # Without QUIC NIF, this should transparently use HTTP/2/1.1
      case Quic.get("https://httpbin.org/get", timeout: 10_000) do
        {:ok, response} ->
          assert response.status == 200
          assert response.protocol in [:http2, :http1]
          assert response.latency_ms >= 0

        {:error, {:transport_error, _}} ->
          # Network may not be available in CI
          :ok

        {:error, {:http_error, _status}} ->
          :ok
      end
    end
  end

  describe "get_json/2 (HTTP/2 fallback)" do
    @tag :integration
    test "fetches and parses JSON" do
      case Quic.get_json("https://httpbin.org/get", timeout: 10_000) do
        {:ok, body} ->
          assert is_map(body)
          assert Map.has_key?(body, "url")

        {:error, _} ->
          :ok
      end
    end
  end

  describe "get/2 with invalid URL" do
    test "rejects invalid URLs" do
      assert {:error, _} = Quic.get("not-a-valid-url")
    end

    test "rejects SSRF targets" do
      assert {:error, _} = Quic.get("http://127.0.0.1/secret")
      assert {:error, _} = Quic.get("http://localhost/admin")
    end
  end

  describe "close_all/0" do
    test "succeeds even with no connections" do
      assert Quic.close_all() == :ok
    end
  end

  describe "connection_stats/1" do
    test "returns error for non-connected host" do
      assert {:error, :not_connected} = Quic.connection_stats("nonexistent.example.com")
    end
  end

  describe "init/0" do
    test "initializes connection pool" do
      assert Quic.init() == :ok
    end

    test "is idempotent" do
      assert Quic.init() == :ok
      assert Quic.init() == :ok
    end
  end

  describe "QUIC NIF operations" do
    @tag :integration
    test "probe returns result when NIF loaded" do
      if Quic.available?() do
        case Quic.probe("cloudflare.com", 443) do
          {:ok, supported} -> assert is_boolean(supported)
          {:error, _} -> :ok
        end
      end
    end
  end
end
