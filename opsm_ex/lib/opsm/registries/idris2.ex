# SPDX-License-Identifier: MPL-2.0
defmodule Opsm.Registries.Idris2 do
  @moduledoc """
  Idris2 package adapter.

  Idris2 has no central registry. Packages are distributed via git
  repositories. This adapter maintains a curated list of known packages
  and can delegate to the generic Git adapter or Agentic adapter for
  package resolution.

  Package format: .ipkg files (Idris Package)
  Build system: idris2 --build
  Standard library location: Included with compiler
  """

  alias Opsm.Registries.{Git, Agentic}
  alias Opsm.Types.{ResolvedPackage, ManifestFormat}

  # Curated list of well-known Idris2 packages
  # Based on https://github.com/idris-lang/Idris2 and community packages
  @known_packages [
    %{
      name: "prelude",
      url: "https://github.com/idris-lang/Idris2",
      path: "libs/prelude",
      description: "Idris2 standard prelude"
    },
    %{
      name: "base",
      url: "https://github.com/idris-lang/Idris2",
      path: "libs/base",
      description: "Base library for Idris2"
    },
    %{
      name: "contrib",
      url: "https://github.com/idris-lang/Idris2",
      path: "libs/contrib",
      description: "Contributed libraries for Idris2"
    },
    %{
      name: "linear",
      url: "https://github.com/idris-lang/Idris2",
      path: "libs/linear",
      description: "Linear types library"
    },
    %{
      name: "network",
      url: "https://github.com/idris-lang/Idris2",
      path: "libs/network",
      description: "Network programming library"
    },
    %{
      name: "test",
      url: "https://github.com/idris-lang/Idris2",
      path: "libs/test",
      description: "Testing framework for Idris2"
    },
    %{
      name: "pack",
      url: "https://github.com/stefan-hoeck/idris2-pack",
      description: "Package manager for Idris2 with curated package collection"
    },
    %{
      name: "elab-util",
      url: "https://github.com/stefan-hoeck/idris2-elab-util",
      description: "Utilities for elaborator reflection"
    },
    %{
      name: "sop",
      url: "https://github.com/stefan-hoeck/idris2-sop",
      description: "Sum of products for generic programming"
    },
    %{
      name: "collie",
      url: "https://github.com/ohad/collie",
      description: "Collie - Idris2 HTTP library"
    },
    %{
      name: "json",
      url: "https://github.com/stefan-hoeck/idris2-json",
      description: "JSON parsing and generation"
    },
    %{
      name: "dom",
      url: "https://github.com/stefan-hoeck/idris2-dom",
      description: "DOM bindings for browser programming"
    },
    %{
      name: "parser",
      url: "https://github.com/stefan-hoeck/idris2-parser",
      description: "Parser combinator library"
    },
    %{
      name: "rhone",
      url: "https://github.com/stefan-hoeck/idris2-rhone",
      description: "Reactive HTML library"
    },
    %{
      name: "refined",
      url: "https://github.com/stefan-hoeck/idris2-refined",
      description: "Refinement types library"
    }
  ]

  @doc """
  Fetch package metadata from curated list or via agentic discovery.

  ## Examples

      iex> Idris2.fetch_package("prelude", "latest")
      {:ok, %ResolvedPackage{name: "prelude", ...}}

      iex> Idris2.fetch_package("unknown-package")
      {:error, :not_found}
  """
  def fetch_package(name, version \\ "latest") do
    case find_known_package(name) do
      {:ok, pkg_info} ->
        # Use git adapter for known packages
        fetch_from_git(pkg_info, version)

      :not_found ->
        # Fallback to agentic search for unknown packages
        fetch_via_agentic(name, version)
    end
  end

  @doc """
  Search curated package list.

  ## Examples

      iex> Idris2.search("json")
      {:ok, [%ResolvedPackage{name: "json", ...}]}
  """
  def search(query, _opts \\ []) do
    query_lower = String.downcase(query)

    results =
      Enum.filter(@known_packages, fn pkg ->
        searchable = String.downcase("#{pkg.name} #{pkg.description}")
        String.contains?(searchable, query_lower)
      end)

    packages =
      Enum.map(results, fn pkg ->
        manifest = %ManifestFormat{
          name: pkg.name,
          version: "latest",
          description: pkg.description,
          repository: pkg.url,
          source_forth: :idris2,
          license: nil,
          dependencies: %{},
          dev_dependencies: %{},
          raw_manifest: %{
            "registry" => "idris2-curated",
            "language" => "idris2",
            "manifest_format" => "ipkg",
            "build_system" => "idris2"
          }
        }

        %ResolvedPackage{
          package: pkg.name,
          version: "latest",
          forth: :idris2,
          registry_url: pkg.url,
          tarball_url: "#{pkg.url}/archive/main.tar.gz",
          checksum: nil,
          checksum_algo: :sha256,
          manifest: manifest,
          attestations: [],
          resolved_deps: []
        }
      end)

    {:ok, packages}
  end

  @doc """
  Check if package exists in curated list.

  ## Examples

      iex> Idris2.exists?("prelude")
      true

      iex> Idris2.exists?("nonexistent")
      false
  """
  def exists?(name) do
    case find_known_package(name) do
      {:ok, _} -> true
      :not_found -> false
    end
  end

  @doc """
  List available versions for a package.

  For git-based packages, this returns git tags.

  ## Examples

      iex> Idris2.versions("pack")
      {:ok, ["v0.3.0", "v0.2.1", "v0.2.0"]}
  """
  def versions(name) do
    case find_known_package(name) do
      {:ok, pkg_info} ->
        # Delegate to git adapter to list tags
        Git.list_tags(pkg_info.url)

      :not_found ->
        {:error, :not_found}
    end
  end

  # Private functions

  defp find_known_package(name) do
    case Enum.find(@known_packages, fn pkg -> pkg.name == name end) do
      nil -> :not_found
      pkg -> {:ok, pkg}
    end
  end

  defp fetch_from_git(pkg_info, version) do
    opts = if Map.has_key?(pkg_info, :path) do
      [subpath: pkg_info.path]
    else
      []
    end

    case Git.fetch_package(pkg_info.url, version, opts) do
      {:ok, git_pkg} ->
        # Enhance with Idris2-specific metadata
        enhanced = %{git_pkg |
          metadata: Map.merge(git_pkg.metadata, %{
            "registry" => "idris2-curated",
            "language" => "idris2",
            "manifest_format" => "ipkg",
            "build_system" => "idris2",
            "subpath" => Map.get(pkg_info, :path)
          })
        }
        {:ok, enhanced}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp fetch_via_agentic(name, version) do
    # Fallback to agentic search for packages not in curated list
    Agentic.fetch_package(name, %{
      language: "idris2",
      ecosystem: "functional-programming",
      version: version,
      search_hints: [
        "idris2 #{name}",
        "idris2-#{name}",
        "#{name} idris library",
        "#{name} ipkg"
      ],
      common_domains: [
        "github.com/idris-lang",
        "github.com/stefan-hoeck",
        "github.com/ohad",
        "gitlab.com"
      ],
      file_patterns: ["*.ipkg"],
      build_commands: ["idris2 --build #{name}.ipkg"]
    })
  end
end
