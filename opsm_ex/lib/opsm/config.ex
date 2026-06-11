# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
defmodule Opsm.Config do
  @moduledoc """
  Configuration loading with TOML support.

  Config search order:
  1. $OPSM_CONFIG environment variable
  2. ./opsm.toml (local directory)
  3. ~/.config/opsm/opsm.toml (user config)
  """

  alias Opsm.Types.{HttpConfig, ServiceConfig, OpsmConfig}

  @default_http_config %HttpConfig{
    timeout_ms: 3000,
    retries: 2,
    backoff_ms: 200
  }

  @default_ports %{
    claim_forge: 7001,
    checky_monkey: 7002,
    palimpsest_license: 7003,
    cicd_hyper_a: 7004,
    oikos: 7005
  }

  @doc """
  Load configuration from file or return example config.
  """
  def load_config_or_example do
    case load_config() do
      {:ok, config} -> config
      {:error, _} -> example_config()
    end
  end

  @doc """
  Load configuration from available sources.
  """
  def load_config do
    with {:error, _} <- load_from_env(),
         {:error, _} <- load_from_local(),
         {:error, _} <- load_from_user() do
      {:error, "opsm config not found"}
    end
  end

  @doc """
  Return example/default configuration.
  """
  def example_config do
    %OpsmConfig{
      http: @default_http_config,
      claim_forge: default_service_config(7001),
      checky_monkey: default_service_config(7002),
      palimpsest_license: default_service_config(7003),
      cicd_hyper_a: default_service_config(7004),
      oikos: default_service_config(7005)
    }
  end

  # Private functions

  defp load_from_env do
    case System.get_env("OPSM_CONFIG") do
      nil -> {:error, "OPSM_CONFIG not set"}
      path -> load_config_from(path)
    end
  end

  defp load_from_local do
    path = "opsm.toml"
    if File.exists?(path) do
      load_config_from(path)
    else
      {:error, "local config not found"}
    end
  end

  defp load_from_user do
    case System.get_env("HOME") do
      nil -> {:error, "HOME not set"}
      home ->
        path = Path.join([home, ".config", "opsm", "opsm.toml"])
        if File.exists?(path) do
          load_config_from(path)
        else
          {:error, "user config not found"}
        end
    end
  end

  defp load_config_from(path) do
    with {:ok, content} <- File.read(path),
         {:ok, raw} <- Toml.decode(content) do
      parse_config(raw)
    else
      {:error, reason} -> {:error, format_config_error(path, reason)}
    end
  end

  # D7: User-friendly config parse error messages
  defp format_config_error(path, reason) do
    case reason do
      :enoent ->
        """
        Config file not found: #{path}

        Create a config file with:
          mkdir -p ~/.config/opsm
          touch ~/.config/opsm/opsm.toml

        Or set OPSM_CONFIG environment variable to your config path.
        """

      :eacces ->
        """
        Permission denied reading config: #{path}

        Check file permissions with: ls -la #{path}
        Fix with: chmod 644 #{path}
        """

      :eisdir ->
        """
        Config path is a directory: #{path}

        Expected a file, not a directory.
        """

      {:invalid_toml, message} ->
        format_toml_error(path, message)

      %Toml.Error{} = err ->
        format_toml_error(path, Exception.message(err))

      other when is_binary(other) ->
        format_toml_error(path, other)

      other ->
        """
        Failed to load config: #{path}

        Error: #{inspect(other)}

        Run 'opsm config example' to see valid config format.
        """
    end
  end

  defp format_toml_error(path, message) do
    # Extract line number if present in message
    line_info = case Regex.run(~r/line (\d+)/i, to_string(message)) do
      [_, line] -> " at line #{line}"
      _ -> ""
    end

    """
    TOML syntax error in #{path}#{line_info}

    #{message}

    Common issues:
    - Missing quotes around string values
    - Unclosed brackets [ ] or braces { }
    - Invalid characters in key names
    - Missing = between key and value

    Validate your TOML at: https://www.toml-lint.com/
    Or run: opsm config example > example.toml
    """
  end

  defp parse_config(raw) do
    http = parse_http_config(raw["http"])

    with {:ok, claim_forge} <- parse_service_config(raw["claim_forge"], :claim_forge),
         {:ok, checky_monkey} <- parse_service_config(raw["checky_monkey"], :checky_monkey),
         {:ok, palimpsest_license} <- parse_service_config(raw["palimpsest_license"], :palimpsest_license),
         {:ok, cicd_hyper_a} <- parse_service_config(raw["cicd_hyper_a"], :cicd_hyper_a),
         {:ok, oikos} <- parse_service_config(raw["oikos"], :oikos) do
      {:ok, %OpsmConfig{
        http: http,
        claim_forge: claim_forge,
        checky_monkey: checky_monkey,
        palimpsest_license: palimpsest_license,
        cicd_hyper_a: cicd_hyper_a,
        oikos: oikos
      }}
    end
  end

  defp parse_http_config(nil), do: @default_http_config
  defp parse_http_config(raw) do
    %HttpConfig{
      timeout_ms: Map.get(raw, "timeout_ms", @default_http_config.timeout_ms),
      retries: Map.get(raw, "retries", @default_http_config.retries),
      backoff_ms: Map.get(raw, "backoff_ms", @default_http_config.backoff_ms)
    }
  end

  defp parse_service_config(nil, service_key) do
    {:ok, default_service_config(@default_ports[service_key])}
  end

  defp parse_service_config(raw, service_key) do
    default_port = @default_ports[service_key]
    base_url = Map.get(raw, "base_url", "http://127.0.0.1:#{default_port}")

    case validate_url(base_url) do
      :ok ->
        {:ok, %ServiceConfig{
          base_url: base_url,
          token: Map.get(raw, "token")
        }}
      {:error, reason} ->
        {:error, "Invalid URL for #{service_key}: #{reason}"}
    end
  end

  defp default_service_config(port) do
    %ServiceConfig{
      base_url: "http://127.0.0.1:#{port}",
      token: nil
    }
  end

  defp validate_url(url) do
    case URI.parse(url) do
      %URI{scheme: scheme, host: host} when scheme in ["http", "https"] and not is_nil(host) ->
        :ok
      _ ->
        {:error, "invalid URL format"}
    end
  end
end
