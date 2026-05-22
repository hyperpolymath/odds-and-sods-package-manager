# SPDX-License-Identifier: MPL-2.0
defmodule Opsm.Git.Clone do
  @moduledoc """
  Safe git clone operations with SSRF prevention and ref pinning.
  """

  alias Opsm.Verified.Url

  @clone_timeout_ms 300_000
  @default_opts [
    shallow: false,
    sparse: false,
    ref: nil,
    depth: nil,
    timeout: @clone_timeout_ms
  ]

  @doc """
  Clone a git repository to a temporary directory.

  Validates the URL via `Verified.Url.validate/1` to prevent SSRF.
  Supports ref pinning (tag, branch, commit SHA), shallow clones,
  and sparse checkout.

  Returns `{:ok, %{path: tmp_dir, ref: ref}}` or `{:error, reason}`.
  """
  @spec clone(String.t(), keyword()) :: {:ok, map()} | {:error, String.t()}
  def clone(url, opts \\ []) do
    opts = Keyword.merge(@default_opts, opts)

    with {:ok, _validated} <- validate_clone_url(url),
         {:ok, tmp_dir} <- create_tmp_dir(),
         :ok <- do_clone(url, tmp_dir, opts),
         :ok <- maybe_checkout_ref(tmp_dir, opts[:ref]) do
      {:ok, %{path: tmp_dir, ref: opts[:ref] || "HEAD"}}
    end
  end

  @doc """
  Remove a cloned repository directory.
  """
  @spec cleanup(String.t()) :: :ok | {:error, term()}
  def cleanup(path) do
    case File.rm_rf(path) do
      {:ok, _} -> :ok
      {:error, reason, _} -> {:error, reason}
    end
  end

  # Validate the URL is safe for cloning (SSRF prevention)
  defp validate_clone_url(url) do
    cond do
      String.starts_with?(url, "git@") ->
        # SSH URLs are allowed (not HTTP-based SSRF risk)
        {:ok, url}

      String.starts_with?(url, "ssh://") ->
        {:ok, url}

      true ->
        case Url.validate(url) do
          {:ok, _} -> {:ok, url}
          {:error, reason} -> {:error, "Invalid clone URL: #{inspect(reason)}"}
        end
    end
  end

  defp create_tmp_dir do
    dir = Path.join(System.tmp_dir!(), "opsm_git_#{:rand.uniform(1_000_000)}")

    case File.mkdir_p(dir) do
      :ok -> {:ok, dir}
      {:error, reason} -> {:error, "Failed to create temp dir: #{reason}"}
    end
  end

  defp do_clone(url, dest, opts) do
    args = build_clone_args(url, dest, opts)

    case Opsm.SafeExec.cmd("git", args, stderr_to_stdout: true) do
      {_output, 0} -> :ok
      {error, code} -> {:error, "git clone failed (#{code}): #{String.trim(error)}"}
    end
  end

  defp build_clone_args(url, dest, opts) do
    args = ["clone"]

    args =
      if opts[:shallow] || opts[:depth] do
        depth = opts[:depth] || 1
        args ++ ["--depth", to_string(depth)]
      else
        args
      end

    args =
      if opts[:sparse] do
        args ++ ["--filter=blob:none", "--sparse"]
      else
        args
      end

    args =
      if opts[:ref] && not is_sha?(opts[:ref]) do
        # Branch/tag can be specified at clone time
        args ++ ["--branch", opts[:ref]]
      else
        args
      end

    args ++ [url, dest]
  end

  defp maybe_checkout_ref(_dir, nil), do: :ok

  defp maybe_checkout_ref(dir, ref) do
    if is_sha?(ref) do
      # For commit SHAs, we need to checkout after clone
      case Opsm.SafeExec.cmd("git", ["-C", dir, "checkout", ref], stderr_to_stdout: true) do
        {_output, 0} -> :ok
        {error, code} -> {:error, "git checkout #{ref} failed (#{code}): #{String.trim(error)}"}
      end
    else
      # Branch/tag was already handled in clone args
      :ok
    end
  end

  defp is_sha?(ref) when is_binary(ref) do
    Regex.match?(~r/^[0-9a-f]{7,40}$/i, ref)
  end

  defp is_sha?(_), do: false
end
