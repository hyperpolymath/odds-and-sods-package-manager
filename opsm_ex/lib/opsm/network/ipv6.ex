# SPDX-License-Identifier: MPL-2.0
defmodule Opsm.Network.Ipv6 do
  @moduledoc """
  IPv6-only enforcement for OPSM registry connections.

  Provides DNS resolution controls to prefer or enforce IPv6 (AAAA records)
  for all outbound registry connections. This supports the transition to
  IPv6-only infrastructure and ensures OPSM operates correctly in IPv6-only
  network environments.

  ## Modes

  - `:prefer_ipv6` (default) — Resolve AAAA first, fall back to A records
  - `:enforce_ipv6` — Only use AAAA records, reject IPv4-only hosts
  - `:prefer_ipv4` — Legacy mode, resolve A first then AAAA
  - `:dual_stack` — Use whatever the system resolver provides

  ## Configuration

  Set via environment variable or config:

      # Environment
      export OPSM_IPV6_MODE=enforce

      # config/runtime.exs
      config :opsm, :ipv6_mode, :enforce_ipv6

  ## Usage

      # Check current mode
      Opsm.Network.Ipv6.mode()
      # => :prefer_ipv6

      # Resolve a host respecting the IPv6 policy
      Opsm.Network.Ipv6.resolve("registry.npmjs.org")
      # => {:ok, [{0, 0, 0, 0, 0, 65535, 26880, 18481}]}

      # Validate that a host is reachable under current policy
      Opsm.Network.Ipv6.validate_host("registry.npmjs.org")
      # => :ok
  """

  require Logger

  @type ipv6_mode :: :prefer_ipv6 | :enforce_ipv6 | :prefer_ipv4 | :dual_stack
  @type ip_address :: :inet.ip_address()

  @doc """
  Get the current IPv6 enforcement mode.
  """
  @spec mode() :: ipv6_mode()
  def mode do
    env_mode =
      case System.get_env("OPSM_IPV6_MODE") do
        "enforce" -> :enforce_ipv6
        "prefer" -> :prefer_ipv6
        "prefer_ipv4" -> :prefer_ipv4
        "dual" -> :dual_stack
        _ -> nil
      end

    env_mode || Application.get_env(:opsm, :ipv6_mode, :prefer_ipv6)
  end

  @doc """
  Resolve a hostname to IP addresses respecting the IPv6 policy.

  Returns addresses in preference order based on the current mode.
  """
  @spec resolve(String.t()) :: {:ok, [ip_address()]} | {:error, term()}
  def resolve(host) when is_binary(host) do
    hostname = String.to_charlist(host)

    case mode() do
      :enforce_ipv6 ->
        resolve_ipv6_only(hostname, host)

      :prefer_ipv6 ->
        resolve_prefer_ipv6(hostname)

      :prefer_ipv4 ->
        resolve_prefer_ipv4(hostname)

      :dual_stack ->
        resolve_dual_stack(hostname)
    end
  end

  @doc """
  Validate that a host is reachable under the current IPv6 policy.

  Returns `:ok` if the host has addresses matching the policy, or
  `{:error, reason}` if the host cannot be reached.
  """
  @spec validate_host(String.t()) :: :ok | {:error, term()}
  def validate_host(host) do
    case resolve(host) do
      {:ok, [_ | _]} -> :ok
      {:ok, []} -> {:error, {:no_addresses, host}}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Check if an IP address is IPv6.
  """
  @spec ipv6?(ip_address()) :: boolean()
  def ipv6?({_, _, _, _, _, _, _, _}), do: true
  def ipv6?(_), do: false

  @doc """
  Check if an IP address is IPv4.
  """
  @spec ipv4?(ip_address()) :: boolean()
  def ipv4?({_, _, _, _}), do: true
  def ipv4?(_), do: false

  @doc """
  Convert an IPv4 address to IPv4-mapped IPv6 address.

  Maps `a.b.c.d` to `::ffff:a.b.c.d` (RFC 4291 Section 2.5.5.2).
  """
  @spec to_ipv6_mapped(ip_address()) :: ip_address()
  def to_ipv6_mapped({a, b, c, d}) do
    # ::ffff:a.b.c.d
    high = a * 256 + b
    low = c * 256 + d
    {0, 0, 0, 0, 0, 0xFFFF, high, low}
  end

  def to_ipv6_mapped(addr), do: addr

  @doc """
  Format an IP address as a string.
  """
  @spec format_address(ip_address()) :: String.t()
  def format_address({a, b, c, d}), do: "#{a}.#{b}.#{c}.#{d}"

  def format_address({a, b, c, d, e, f, g, h}) do
    [a, b, c, d, e, f, g, h]
    |> Enum.map(&Integer.to_string(&1, 16))
    |> Enum.join(":")
  end

  @doc """
  Get Req/Finch connect options for the current IPv6 mode.

  Returns keyword options suitable for passing to Req's `:connect_options`.
  """
  @spec connect_options() :: keyword()
  def connect_options do
    case mode() do
      :enforce_ipv6 ->
        [transport_opts: [inet6: true]]

      :prefer_ipv6 ->
        # Prefer IPv6 but allow IPv4 fallback
        [transport_opts: [inet6: true]]

      :prefer_ipv4 ->
        []

      :dual_stack ->
        []
    end
  end

  @doc """
  Returns a summary of the current IPv6 enforcement status.
  """
  @spec status() :: map()
  def status do
    current_mode = mode()

    %{
      mode: current_mode,
      ipv6_enforced: current_mode == :enforce_ipv6,
      ipv6_preferred: current_mode in [:enforce_ipv6, :prefer_ipv6],
      connect_options: connect_options(),
      system_ipv6: system_has_ipv6?()
    }
  end

  @doc """
  Check if the system has IPv6 connectivity.
  """
  @spec system_has_ipv6?() :: boolean()
  def system_has_ipv6? do
    case :inet.getifaddrs() do
      {:ok, interfaces} ->
        Enum.any?(interfaces, fn {_name, props} ->
          props
          |> Keyword.get_values(:addr)
          |> Enum.any?(fn
            {_, _, _, _, _, _, _, _} = addr ->
              # Exclude loopback and link-local
              not loopback_ipv6?(addr) and not link_local_ipv6?(addr)

            _ ->
              false
          end)
        end)

      {:error, _} ->
        false
    end
  end

  # =============================================================================
  # Internal: DNS Resolution
  # =============================================================================

  defp resolve_ipv6_only(hostname, host) do
    case :inet.getaddrs(hostname, :inet6) do
      {:ok, addrs} when addrs != [] ->
        {:ok, addrs}

      _ ->
        Logger.warning("IPv6 enforcement: #{host} has no AAAA records — connection blocked")

        {:error, {:ipv6_required, host,
          "Host #{host} has no IPv6 (AAAA) records. " <>
          "Set OPSM_IPV6_MODE=prefer to allow IPv4 fallback."}}
    end
  end

  defp resolve_prefer_ipv6(hostname) do
    ipv6 =
      case :inet.getaddrs(hostname, :inet6) do
        {:ok, addrs} -> addrs
        _ -> []
      end

    ipv4 =
      case :inet.getaddrs(hostname, :inet) do
        {:ok, addrs} -> addrs
        _ -> []
      end

    all = ipv6 ++ ipv4

    if all == [] do
      {:error, :nxdomain}
    else
      {:ok, all}
    end
  end

  defp resolve_prefer_ipv4(hostname) do
    ipv4 =
      case :inet.getaddrs(hostname, :inet) do
        {:ok, addrs} -> addrs
        _ -> []
      end

    ipv6 =
      case :inet.getaddrs(hostname, :inet6) do
        {:ok, addrs} -> addrs
        _ -> []
      end

    all = ipv4 ++ ipv6

    if all == [] do
      {:error, :nxdomain}
    else
      {:ok, all}
    end
  end

  defp resolve_dual_stack(hostname) do
    case :inet.getaddrs(hostname, :inet) do
      {:ok, addrs} ->
        {:ok, addrs}

      {:error, _} ->
        case :inet.getaddrs(hostname, :inet6) do
          {:ok, addrs} -> {:ok, addrs}
          {:error, reason} -> {:error, reason}
        end
    end
  end

  # =============================================================================
  # Internal: IPv6 Address Classification
  # =============================================================================

  defp loopback_ipv6?({0, 0, 0, 0, 0, 0, 0, 1}), do: true
  defp loopback_ipv6?(_), do: false

  defp link_local_ipv6?({0xFE80, _, _, _, _, _, _, _}), do: true
  defp link_local_ipv6?(_), do: false
end
