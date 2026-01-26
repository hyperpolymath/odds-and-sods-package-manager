# SPDX-License-Identifier: PMPL-1.0
defmodule Opsm.VerifiedTest do
  use ExUnit.Case, async: true

  alias Opsm.Verified.{Url, Json, Result}

  describe "Url.validate/1" do
    test "accepts valid HTTPS URLs" do
      assert {:ok, url} = Url.validate("https://registry.npmjs.org/package")
      assert url.scheme == "https"
      assert url.host == "registry.npmjs.org"
      assert url.path == "/package"
    end

    test "accepts valid HTTP URLs" do
      assert {:ok, url} = Url.validate("http://example.com/path")
      assert url.scheme == "http"
      assert url.host == "example.com"
    end

    test "rejects URLs without scheme" do
      assert {:error, :missing_scheme} = Url.validate("example.com/path")
    end

    test "rejects URLs without host" do
      assert {:error, :missing_host} = Url.validate("https:///path")
    end

    test "rejects localhost URLs" do
      assert {:error, :blocked_host} = Url.validate("https://localhost:8080/api")
      assert {:error, :blocked_host} = Url.validate("http://127.0.0.1/api")
    end

    test "rejects private IP addresses" do
      assert {:error, :blocked_host} = Url.validate("http://192.168.1.1/api")
      assert {:error, :blocked_host} = Url.validate("http://10.0.0.1/api")
      assert {:error, :blocked_host} = Url.validate("http://172.16.0.1/api")
    end

    test "rejects non-HTTP(S) schemes" do
      assert {:error, {:invalid_scheme, "ftp"}} = Url.validate("ftp://example.com/file")
      assert {:error, {:invalid_scheme, "file"}} = Url.validate("file:///etc/passwd")
    end

    test "handles URLs with ports" do
      assert {:ok, url} = Url.validate("https://example.com:8443/api")
      assert url.port == 8443
    end

    test "handles URLs with query strings" do
      assert {:ok, url} = Url.validate("https://example.com/search?q=test&limit=10")
      assert url.query == "q=test&limit=10"
    end
  end

  describe "Json.decode/1" do
    test "decodes valid JSON objects" do
      assert {:ok, %{"name" => "test"}} = Json.decode(~s({"name":"test"}))
    end

    test "decodes valid JSON arrays" do
      assert {:ok, [1, 2, 3]} = Json.decode("[1,2,3]")
    end

    test "rejects deeply nested JSON (DoS protection)" do
      # Create deeply nested structure (>20 levels)
      nested = Enum.reduce(1..25, "1", fn _, acc -> ~s({"a":#{acc}}) end)
      assert {:error, :nesting_too_deep} = Json.decode(nested)
    end

    test "rejects excessively large payloads" do
      # Create a 15MB string
      large = String.duplicate("x", 15_000_000)
      assert {:error, :payload_too_large} = Json.decode(large)
    end

    test "handles invalid JSON" do
      assert {:error, {:json_decode_error, _}} = Json.decode("{invalid json")
    end

    test "rejects non-string input" do
      assert {:error, :not_a_string} = Json.decode(123)
      assert {:error, :not_a_string} = Json.decode(%{})
    end
  end

  describe "Json.encode/1" do
    test "encodes maps to JSON" do
      assert {:ok, json} = Json.encode(%{name: "test", value: 42})
      assert json =~ "name"
      assert json =~ "test"
    end

    test "encodes lists to JSON" do
      assert {:ok, "[1,2,3]"} = Json.encode([1, 2, 3])
    end

    test "handles encoding errors gracefully" do
      # PIDs cannot be encoded to JSON
      assert {:error, {:json_encode_error, _}} = Json.encode(self())
    end
  end

  describe "Result.map/2" do
    test "maps over success values" do
      assert {:ok, 10} = Result.map({:ok, 5}, fn x -> x * 2 end)
    end

    test "ignores errors" do
      assert {:error, "failed"} = Result.map({:error, "failed"}, fn x -> x * 2 end)
    end
  end

  describe "Result.and_then/2" do
    test "chains successful operations" do
      result =
        {:ok, 5}
        |> Result.and_then(fn x -> {:ok, x * 2} end)
        |> Result.and_then(fn x -> {:ok, x + 3} end)

      assert result == {:ok, 13}
    end

    test "short-circuits on first error" do
      result =
        {:ok, 5}
        |> Result.and_then(fn x -> {:ok, x * 2} end)
        |> Result.and_then(fn _ -> {:error, "failed"} end)
        |> Result.and_then(fn x -> {:ok, x + 3} end)

      assert result == {:error, "failed"}
    end
  end

  describe "Result.unwrap_or/2" do
    test "returns value on success" do
      assert 5 = Result.unwrap_or({:ok, 5}, 0)
    end

    test "returns default on error" do
      assert 0 = Result.unwrap_or({:error, "failed"}, 0)
    end
  end

  describe "Result.unwrap!/1" do
    test "returns value on success" do
      assert 5 = Result.unwrap!({:ok, 5})
    end

    test "raises on error" do
      assert_raise RuntimeError, fn ->
        Result.unwrap!({:error, "failed"})
      end
    end
  end

  describe "Result predicates" do
    test "is_ok?/1" do
      assert Result.is_ok?({:ok, 5})
      refute Result.is_ok?({:error, "failed"})
    end

    test "is_error?/1" do
      assert Result.is_error?({:error, "failed"})
      refute Result.is_error?({:ok, 5})
    end
  end
end
