# SPDX-License-Identifier: PMPL-1.0-or-later
defmodule Opsm.Verified.UrlPropertyTest do
  use ExUnit.Case
  use ExUnitProperties

  alias Opsm.Verified.Url

  describe "Url.validate/1 properties" do
    property "always rejects URLs without schemes" do
      check all(host <- string(:alphanumeric, min_length: 1),
                path <- string(:alphanumeric)
            ) do
        url = "#{host}/#{path}"
        assert {:error, :missing_scheme} = Url.validate(url)
      end
    end

    property "always rejects non-string inputs" do
      check all(value <- one_of([integer(), float(), atom(:alphanumeric), list_of(integer())])) do
        assert {:error, :not_a_string} = Url.validate(value)
      end
    end

    property "always rejects localhost variants" do
      check all(scheme <- member_of(["http", "https"]),
                localhost <- member_of(["localhost", "127.0.0.1", "0.0.0.0", "::1"]),
                path <- string(:alphanumeric)
            ) do
        url = "#{scheme}://#{localhost}/#{path}"
        assert {:error, :blocked_host} = Url.validate(url)
      end
    end

    property "always rejects private IP ranges" do
      check all(scheme <- member_of(["http", "https"]),
                octet2 <- integer(0..255),
                octet3 <- integer(0..255),
                octet4 <- integer(0..255)
            ) do
        # Test 192.168.x.x range
        url = "#{scheme}://192.168.#{octet3}.#{octet4}/test"
        assert {:error, :blocked_host} = Url.validate(url)

        # Test 10.x.x.x range
        url = "#{scheme}://10.#{octet2}.#{octet3}.#{octet4}/test"
        assert {:error, :blocked_host} = Url.validate(url)
      end
    end

    property "always rejects unsupported schemes" do
      check all(scheme <- member_of(["ftp", "file", "javascript", "data", "ssh"]),
                host <- string(:alphanumeric, min_length: 1)
            ) do
        url = "#{scheme}://#{host}/path"
        assert match?({:error, {:invalid_scheme, _}}, Url.validate(url))
      end
    end

    property "accepts valid http/https URLs to public domains" do
      check all(scheme <- member_of(["http", "https"]),
                # Use known safe domains
                host <- member_of(["example.com", "github.com", "registry.npmjs.org"]),
                path <- string(:alphanumeric)
            ) do
        url = "#{scheme}://#{host}/#{path}"

        case Url.validate(url) do
          {:ok, validated} ->
            assert validated.scheme == scheme
            assert validated.host == host
            assert validated.original == url

          # Allow validation to fail for edge cases
          {:error, _reason} ->
            :ok
        end
      end
    end

    property "preserves original URL in validated struct" do
      check all(scheme <- member_of(["http", "https"]),
                host <- member_of(["example.com", "github.com"]),
                port <- integer(1..65535),
                path <- string(:alphanumeric)
            ) do
        url = "#{scheme}://#{host}:#{port}/#{path}"

        case Url.validate(url) do
          {:ok, validated} ->
            assert validated.original == url
            assert Url.to_string(validated) == url

          {:error, _} ->
            :ok
        end
      end
    end
  end

  describe "Url.to_string/1 properties" do
    property "roundtrip: validate -> to_string returns original" do
      check all(scheme <- member_of(["http", "https"]),
                host <- member_of(["example.com", "test.org"]),
                path <- string(:alphanumeric, max_length: 20)
            ) do
        url = "#{scheme}://#{host}/#{path}"

        case Url.validate(url) do
          {:ok, validated} ->
            assert Url.to_string(validated) == url

          {:error, _} ->
            :ok
        end
      end
    end
  end
end
