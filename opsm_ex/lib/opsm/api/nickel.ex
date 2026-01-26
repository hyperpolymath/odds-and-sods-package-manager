# SPDX-License-Identifier: PMPL-1.0
defmodule Opsm.Api.Nickel do
  @moduledoc """
  Nickel decoding support for API payloads.
  """

  def decode(body) when is_binary(body) do
    case System.find_executable("nickel") do
      nil ->
        {:error, "nickel is not installed; send JSON or install nickel"}

      _ ->
        path = write_temp(body)

        case System.cmd("nickel", ["export", "--format", "json", path], stderr_to_stdout: true) do
          {output, 0} ->
            Jason.decode(output)

          {error, _code} ->
            {:error, "nickel export failed: #{String.trim(error)}"}
        end
    end
  end

  defp write_temp(body) do
    name = "opsm_api_#{System.system_time(:millisecond)}.ncl"
    path = Path.join(System.tmp_dir!(), name)
    File.write!(path, body)
    path
  end
end
