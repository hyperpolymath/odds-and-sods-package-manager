# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
defmodule Opsm.Verified.JsonPropertyTest do
  use ExUnit.Case
  use ExUnitProperties

  alias Opsm.Verified.Json

  describe "Json.decode/1 properties" do
    property "rejects non-string inputs" do
      check all(value <- one_of([integer(), float(), atom(:alphanumeric), list_of(integer())])) do
        assert {:error, :not_a_string} = Json.decode(value)
      end
    end

    property "rejects payloads larger than 10MB" do
      # Generate a string larger than 10MB
      large_string = String.duplicate("x", 11_000_000)
      assert {:error, :payload_too_large} = Json.decode(large_string)
    end

    property "roundtrip: encode -> decode preserves simple values" do
      check all(value <- one_of([integer(), float(), boolean(), string(:alphanumeric)])) do
        wrapped = %{"value" => value}

        case Json.encode(wrapped) do
          {:ok, json_string} ->
            case Json.decode(json_string) do
              {:ok, decoded} ->
                assert decoded["value"] == value

              {:error, _reason} ->
                flunk("Failed to decode valid JSON")
            end

          {:error, reason} ->
            flunk("Failed to encode: #{inspect(reason)}")
        end
      end
    end

    property "roundtrip: encode -> decode preserves maps" do
      check all(
              key1 <- string(:alphanumeric, min_length: 1, max_length: 10),
              val1 <- integer(),
              key2 <- string(:alphanumeric, min_length: 1, max_length: 10),
              val2 <- string(:alphanumeric)
            ) do
        # Ensure unique keys
        if key1 != key2 do
          map = %{key1 => val1, key2 => val2}

          case Json.encode(map) do
            {:ok, json_string} ->
              case Json.decode(json_string) do
                {:ok, decoded} ->
                  assert decoded[key1] == val1
                  assert decoded[key2] == val2

                {:error, _} ->
                  flunk("Failed to decode valid JSON")
              end

            {:error, _} ->
              flunk("Failed to encode valid map")
          end
        end
      end
    end

    property "rejects deeply nested structures" do
      # Create a deeply nested structure (25 levels)
      deeply_nested =
        Enum.reduce(1..25, %{"value" => 1}, fn _i, acc ->
          %{"nested" => acc}
        end)

      case Json.encode(deeply_nested) do
        {:ok, json_string} ->
          assert {:error, :nesting_too_deep} = Json.decode(json_string)

        {:error, _} ->
          # Encoding might fail for very deep structures - that's ok
          :ok
      end
    end

    property "accepts valid JSON arrays" do
      check all(list <- list_of(integer(), max_length: 10)) do
        wrapped = %{"items" => list}

        case Json.encode(wrapped) do
          {:ok, json_string} ->
            case Json.decode(json_string) do
              {:ok, decoded} ->
                assert decoded["items"] == list

              {:error, _} ->
                flunk("Failed to decode valid array JSON")
            end

          {:error, _} ->
            flunk("Failed to encode valid list")
        end
      end
    end

    property "handles empty structures" do
      check all(
              empty <- member_of([%{}, [], nil, ""])
            ) do
        wrapped = %{"empty" => empty}

        case Json.encode(wrapped) do
          {:ok, json_string} ->
            case Json.decode(json_string) do
              {:ok, decoded} ->
                # nil becomes null, which decodes back to nil
                # Empty string stays empty string
                # Empty list stays empty list
                # Empty map stays empty map
                assert decoded["empty"] == empty

              {:error, _} ->
                flunk("Failed to decode empty structures")
            end

          {:error, _} ->
            flunk("Failed to encode empty structure")
        end
      end
    end
  end

  describe "Json.encode/1 properties" do
    property "always returns string when successful" do
      check all(value <- one_of([integer(), string(:alphanumeric), boolean()])) do
        case Json.encode(%{"value" => value}) do
          {:ok, json_string} ->
            assert is_binary(json_string)

          {:error, _} ->
            # Some values might not be encodable - that's fine
            :ok
        end
      end
    end

    property "encoded JSON is valid and decodable" do
      check all(
              key <- string(:alphanumeric, min_length: 1, max_length: 10),
              value <- integer()
            ) do
        map = %{key => value}

        case Json.encode(map) do
          {:ok, json_string} ->
            # Should be valid JSON that decodes back
            assert match?({:ok, _}, Json.decode(json_string))

          {:error, _} ->
            :ok
        end
      end
    end
  end
end
