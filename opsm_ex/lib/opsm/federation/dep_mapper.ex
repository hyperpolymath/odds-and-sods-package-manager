# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
defmodule Opsm.Federation.DepMapper do
  @moduledoc """
  Maps package names across ecosystems where equivalents exist.

  Uses a known-mappings database plus heuristic fallbacks
  for common naming patterns (e.g., python3-numpy for numpy in deb).
  """

  @doc """
  Find the equivalent package name in a target ecosystem.

  Returns `{:ok, target_name}` or `{:error, :no_mapping}`.

  ## Examples

      iex> DepMapper.find_equivalent("numpy", :pypi, :deb)
      {:ok, "python3-numpy"}

      iex> DepMapper.find_equivalent("express", :npm, :deb)
      {:ok, "node-express"}
  """
  @spec find_equivalent(String.t(), atom(), atom()) :: {:ok, String.t()} | {:error, :no_mapping}
  def find_equivalent(package_name, source_forth, target_forth) do
    # Direct lookup first
    case lookup_mapping(package_name, source_forth, target_forth) do
      {:ok, _} = result ->
        result

      :not_found ->
        # Try heuristic patterns
        case heuristic_mapping(package_name, source_forth, target_forth) do
          {:ok, _} = result -> result
          :not_found -> {:error, :no_mapping}
        end
    end
  end

  @doc """
  List all known mappings for a package across ecosystems.

  Returns a map of `%{forth => package_name}`.
  """
  @spec list_mappings(String.t(), atom()) :: map()
  def list_mappings(package_name, source_forth) do
    case Map.get(known_mappings(), {String.downcase(package_name), source_forth}) do
      nil -> %{}
      mappings -> mappings
    end
  end

  @doc """
  Suggest possible package names in the target ecosystem.

  Returns a list of candidates to try, in priority order.
  """
  @spec suggest_candidates(String.t(), atom(), atom()) :: [String.t()]
  def suggest_candidates(package_name, source_forth, target_forth) do
    candidates = []

    # Direct mapping
    candidates =
      case find_equivalent(package_name, source_forth, target_forth) do
        {:ok, name} -> [name | candidates]
        _ -> candidates
      end

    # Heuristic candidates
    candidates = candidates ++ heuristic_candidates(package_name, source_forth, target_forth)

    # Original name as fallback
    candidates = candidates ++ [package_name]

    Enum.uniq(candidates)
  end

  # Known cross-ecosystem mappings
  # Key: {lowercase_name, source_forth}
  # Value: %{target_forth => target_name}
  defp known_mappings do
    %{
      # Python packages → system packages
      {"numpy", :pypi} => %{deb: "python3-numpy", rpm: "python3-numpy", pacman: "python-numpy", homebrew: "numpy"},
      {"pandas", :pypi} => %{deb: "python3-pandas", rpm: "python3-pandas", pacman: "python-pandas"},
      {"scipy", :pypi} => %{deb: "python3-scipy", rpm: "python3-scipy", pacman: "python-scipy"},
      {"requests", :pypi} => %{deb: "python3-requests", rpm: "python3-requests", pacman: "python-requests"},
      {"flask", :pypi} => %{deb: "python3-flask", rpm: "python3-flask", pacman: "python-flask"},
      {"django", :pypi} => %{deb: "python3-django", rpm: "python3-django", pacman: "python-django"},
      {"pillow", :pypi} => %{deb: "python3-pil", rpm: "python3-pillow", pacman: "python-pillow"},
      {"cryptography", :pypi} => %{deb: "python3-cryptography", rpm: "python3-cryptography"},
      {"pyyaml", :pypi} => %{deb: "python3-yaml", rpm: "python3-pyyaml", pacman: "python-yaml"},
      {"setuptools", :pypi} => %{deb: "python3-setuptools", rpm: "python3-setuptools"},

      # Node.js packages → system packages
      {"express", :npm} => %{deb: "node-express"},
      {"lodash", :npm} => %{deb: "node-lodash"},
      {"typescript", :npm} => %{deb: "node-typescript", homebrew: "typescript"},
      {"webpack", :npm} => %{deb: "node-webpack"},

      # Ruby gems → system packages
      {"rails", :gem} => %{deb: "ruby-rails", rpm: "rubygem-rails"},
      {"rake", :gem} => %{deb: "rake", rpm: "rubygem-rake"},
      {"bundler", :gem} => %{deb: "bundler", rpm: "rubygem-bundler"},
      {"nokogiri", :gem} => %{deb: "ruby-nokogiri", rpm: "rubygem-nokogiri"},

      # Rust crates → system packages
      {"ripgrep", :cargo} => %{deb: "ripgrep", rpm: "ripgrep", pacman: "ripgrep", homebrew: "ripgrep"},
      {"fd-find", :cargo} => %{deb: "fd-find", pacman: "fd", homebrew: "fd"},
      {"bat", :cargo} => %{deb: "bat", pacman: "bat", homebrew: "bat"},
      {"exa", :cargo} => %{deb: "exa", pacman: "exa", homebrew: "exa"},
      {"tokei", :cargo} => %{deb: "tokei", pacman: "tokei", homebrew: "tokei"},

      # Go modules → system packages
      {"github.com/junegunn/fzf", :go} => %{deb: "fzf", rpm: "fzf", pacman: "fzf", homebrew: "fzf"},
      {"github.com/jesseduffield/lazygit", :go} => %{pacman: "lazygit", homebrew: "lazygit"},

      # Cross-ecosystem equivalents (same function, different ecosystems)
      {"req", :hex} => %{npm: "axios", pypi: "requests", cargo: "reqwest", gem: "httparty", go: "net/http"},
      {"jason", :hex} => %{npm: "json5", pypi: "json", cargo: "serde_json", gem: "json", go: "encoding/json"},
      {"plug", :hex} => %{npm: "express", pypi: "flask", cargo: "actix-web", gem: "rack", go: "net/http"}
    }
  end

  defp lookup_mapping(package_name, source_forth, target_forth) do
    key = {String.downcase(package_name), source_forth}

    case Map.get(known_mappings(), key) do
      nil -> :not_found
      mappings ->
        case Map.get(mappings, target_forth) do
          nil -> :not_found
          name -> {:ok, name}
        end
    end
  end

  # Heuristic naming patterns
  defp heuristic_mapping(package_name, source_forth, target_forth) do
    candidate = heuristic_name(package_name, source_forth, target_forth)
    if candidate, do: {:ok, candidate}, else: :not_found
  end

  defp heuristic_name(name, :pypi, forth) when forth in [:deb, :rpm] do
    "python3-#{String.downcase(name)}"
  end

  defp heuristic_name(name, :npm, :deb) do
    "node-#{String.downcase(name)}"
  end

  defp heuristic_name(name, :gem, :deb) do
    "ruby-#{String.downcase(name)}"
  end

  defp heuristic_name(name, :gem, :rpm) do
    "rubygem-#{String.downcase(name)}"
  end

  defp heuristic_name(name, :hex, :deb) do
    "elixir-#{String.downcase(name)}"
  end

  defp heuristic_name(_name, _source, _target), do: nil

  defp heuristic_candidates(package_name, source_forth, target_forth) do
    base = String.downcase(package_name)

    case {source_forth, target_forth} do
      {:pypi, forth} when forth in [:deb, :rpm] ->
        ["python3-#{base}", "python-#{base}", base]

      {:npm, :deb} ->
        ["node-#{base}", "nodejs-#{base}", base]

      {:gem, :deb} ->
        ["ruby-#{base}", base]

      {:gem, :rpm} ->
        ["rubygem-#{base}", base]

      {:cargo, forth} when forth in [:deb, :rpm, :pacman, :homebrew] ->
        # Rust CLI tools often keep their name
        [base]

      _ ->
        [base]
    end
  end
end
