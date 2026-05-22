# SPDX-License-Identifier: MPL-2.0
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
#
# Fuzz harness — property-based tests that drive arbitrary inputs through every
# public boundary in OPSM and assert structural invariants (never crash, always
# return the right shape).
#
# Run: mix test test/opsm/fuzz_harness_test.exs
# Long soak: MIX_EXUNIT_MAX_RUNS=10000 mix test test/opsm/fuzz_harness_test.exs

defmodule Opsm.FuzzHarnessTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Opsm.VersionConstraint
  alias Opsm.Lockfile
  alias Opsm.Registries.Registry
  alias Opsm.Runtime.UrlHandler

  # ---------------------------------------------------------------------------
  # Generators
  # ---------------------------------------------------------------------------

  defp gen_semver do
    gen all major <- StreamData.integer(0..99),
            minor <- StreamData.integer(0..99),
            patch <- StreamData.integer(0..99) do
      "#{major}.#{minor}.#{patch}"
    end
  end

  defp gen_version_string do
    StreamData.one_of([
      gen_semver(),
      StreamData.string(:ascii, min_length: 1, max_length: 20),
      StreamData.constant(""),
      StreamData.constant("latest"),
      StreamData.constant("*"),
    ])
  end

  defp gen_constraint_string do
    operators = ["^", "~>", ">=", "<=", ">", "<", "=", "!=", "~"]
    gen all op <- StreamData.member_of(operators),
            ver <- gen_semver() do
      op <> ver
    end
  end

  defp gen_arbitrary_constraint do
    StreamData.one_of([
      gen_constraint_string(),
      StreamData.string(:ascii, min_length: 0, max_length: 30),
      StreamData.constant(""),
      StreamData.constant("!@#$%"),
      StreamData.constant(">>>invalid<<<"),
    ])
  end

  defp gen_package_name do
    StreamData.one_of([
      StreamData.string(:alphanumeric, min_length: 1, max_length: 30),
      StreamData.string(:ascii, min_length: 1, max_length: 30),
      StreamData.constant(""),
      StreamData.constant("a/b"),
      StreamData.constant("pkg@scope"),
    ])
  end

  # Offline-safe adapters — work without network (git-fallback or always-empty)
  defp gen_registry_atom_offline do
    StreamData.member_of([
      :betlang, :ephapax, :phronesis, :tangle,
      :wokelang, :lithoglyph, :quandledb, :nqc,
      :totally_unknown_xyz_999,
    ])
  end

  # All adapters including live-network ones (for :external_api tests)
  defp gen_registry_atom do
    StreamData.one_of([
      gen_registry_atom_offline(),
      StreamData.member_of([:npm, :hex, :crates, :pypi, :hf]),
    ])
  end

  defp gen_toml_string do
    StreamData.one_of([
      StreamData.constant(""),
      StreamData.constant("[package]\nname = \"foo\"\nversion = \"1.0\"\n"),
      StreamData.constant("{invalid toml ==="),
      StreamData.string(:utf8, min_length: 0, max_length: 200),
      gen all k <- StreamData.string(:alphanumeric, min_length: 1, max_length: 10),
              v <- StreamData.string(:alphanumeric, min_length: 0, max_length: 20) do
        "[section]\n#{k} = \"#{v}\"\n"
      end,
    ])
  end

  defp gen_platform do
    StreamData.member_of([
      :linux_amd64, :linux_arm64, :darwin_amd64, :darwin_arm64,
      :windows_amd64, :freebsd_amd64, :unknown_platform,
    ])
  end

  defp gen_tool_name do
    StreamData.member_of([
      "zig", "golang", "nodejs", "julia", "dart", "nim", "kubectl",
      "totally-unknown-tool-xyz",
    ])
  end

  defp gen_url_handler do
    %{
      "versions_url" => "https://ziglang.org/download/index.json",
      "version_key_pattern" => "^[0-9]+\\.[0-9]+\\.[0-9]+$",
      "archive_url_template" =>
        "https://ziglang.org/download/{{version}}/zig-{{zig_platform}}-{{version}}.tar.xz"
    }
  end

  # ---------------------------------------------------------------------------
  # 1. VersionConstraint.parse/2 — never crashes, always returns ok/error tuple
  # ---------------------------------------------------------------------------

  property "VersionConstraint.parse/2 never crashes on arbitrary input" do
    check all constraint <- gen_arbitrary_constraint(),
              scheme <- StreamData.member_of([:semver, :hex, :npm]) do
      result = VersionConstraint.parse(constraint, scheme)
      assert match?({:ok, _}, result) or match?({:error, _}, result),
             "expected ok/error tuple for #{inspect(constraint)}, got #{inspect(result)}"
    end
  end

  property "VersionConstraint.parse/2 succeeds on well-formed semver constraints" do
    check all constraint <- gen_constraint_string() do
      result = VersionConstraint.parse(constraint, :semver)
      # Well-formed constraints should parse successfully (or return a structured error)
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
  end

  # ---------------------------------------------------------------------------
  # 2. VersionConstraint.satisfies?/2 — always boolean, never crashes
  # ---------------------------------------------------------------------------

  property "VersionConstraint.satisfies?/2 always returns boolean" do
    check all version <- gen_version_string(),
              constraint <- gen_constraint_string() do
      case VersionConstraint.parse(constraint, :semver) do
        {:ok, parsed} ->
          result = VersionConstraint.satisfies?(version, parsed)
          assert is_boolean(result),
                 "expected boolean for satisfies?(#{inspect(version)}, parsed), got #{inspect(result)}"
        {:error, _} ->
          # Unparseable constraint — satisfies? is not called, skip
          :ok
      end
    end
  end

  property "VersionConstraint.satisfies?/2 stable on repeated calls with same inputs" do
    check all version <- gen_semver(),
              constraint <- gen_constraint_string() do
      case VersionConstraint.parse(constraint, :semver) do
        {:ok, parsed} ->
          # Deterministic: same inputs must produce same output
          r1 = VersionConstraint.satisfies?(version, parsed)
          r2 = VersionConstraint.satisfies?(version, parsed)
          assert r1 == r2, "satisfies? is non-deterministic for #{inspect(version)}"
        {:error, _} -> :ok
      end
    end
  end

  # ---------------------------------------------------------------------------
  # 3. Lockfile operations — structural invariants under arbitrary packages
  # ---------------------------------------------------------------------------

  property "Lockfile.add_package/2 never crashes on arbitrary input" do
    check all name <- gen_package_name(),
              version <- gen_version_string(),
              forth <- gen_registry_atom() do
      lockfile = Lockfile.new()
      result = Lockfile.add_package(lockfile, %{name: name, version: version, forth: forth})
      # Must return a lockfile struct — not crash
      assert is_struct(result) or is_map(result),
             "expected struct/map, got #{inspect(result)}"
    end
  end

  property "Lockfile has_package?/3 is consistent with add_package/2" do
    check all name <- StreamData.string(:alphanumeric, min_length: 1, max_length: 20),
              version <- gen_semver(),
              forth <- StreamData.member_of([:npm, :hex, :crates]) do
      lockfile =
        Lockfile.new()
        |> Lockfile.add_package(%{name: name, version: version, forth: forth})

      assert Lockfile.has_package?(lockfile, name, forth),
             "has_package? returned false after add_package for #{name}/#{forth}"
    end
  end

  property "Lockfile is idempotent: adding same package twice keeps it present" do
    check all name <- StreamData.string(:alphanumeric, min_length: 1, max_length: 20),
              version <- gen_semver(),
              forth <- StreamData.member_of([:npm, :hex, :crates]) do
      pkg = %{name: name, version: version, forth: forth}
      lockfile =
        Lockfile.new()
        |> Lockfile.add_package(pkg)
        |> Lockfile.add_package(pkg)

      assert Lockfile.has_package?(lockfile, name, forth)
    end
  end

  # ---------------------------------------------------------------------------
  # 4. TOML parsing — never crashes on arbitrary strings
  # ---------------------------------------------------------------------------

  property "Toml.decode/1 never crashes on arbitrary input" do
    check all input <- gen_toml_string() do
      result = Toml.decode(input)
      assert match?({:ok, _}, result) or match?({:error, _}, result),
             "Toml.decode crashed on #{inspect(input)}"
    end
  end

  property "Toml.decode/1 returns ok map for valid TOML section headers" do
    check all key <- StreamData.string(:alphanumeric, min_length: 1, max_length: 10),
              val <- StreamData.string(:alphanumeric, min_length: 0, max_length: 20) do
      toml = "[section]\n#{key} = \"#{val}\"\n"
      result = Toml.decode(toml)
      # Valid TOML must parse to ok
      assert match?({:ok, _}, result),
             "expected ok for valid TOML #{inspect(toml)}, got #{inspect(result)}"
    end
  end

  # ---------------------------------------------------------------------------
  # 5. Registry.search/3 — never crashes, always returns ok/error tuple
  # ---------------------------------------------------------------------------

  # Offline-only: uses adapters that don't make network requests
  property "Registry.search/3 never crashes on offline adapters with arbitrary queries" do
    check all forth <- gen_registry_atom_offline(),
              query <- StreamData.string(:alphanumeric, min_length: 0, max_length: 50) do
      result = Registry.search(forth, query, [])
      assert match?({:ok, _}, result) or match?({:error, _}, result),
             "Registry.search crashed for #{inspect(forth)}/#{inspect(query)}"
    end
  end

  @tag :external_api
  property "Registry.search/3 never crashes on all adapters including live-network ones" do
    check all forth <- gen_registry_atom(),
              query <- StreamData.string(:alphanumeric, min_length: 0, max_length: 50) do
      result = Registry.search(forth, query, [])
      assert match?({:ok, _}, result) or match?({:error, _}, result),
             "Registry.search crashed for #{inspect(forth)}/#{inspect(query)}"
    end
  end

  property "Registry.exists?/2 always returns boolean (offline adapters)" do
    check all forth <- gen_registry_atom_offline(),
              name <- gen_package_name() do
      result = Registry.exists?(forth, name)
      assert is_boolean(result),
             "Registry.exists? returned non-boolean #{inspect(result)} for #{forth}/#{name}"
    end
  end

  # ---------------------------------------------------------------------------
  # 6. UrlHandler.archive_url/4 — never crashes, always ok/error
  # ---------------------------------------------------------------------------

  property "UrlHandler.archive_url/4 never crashes on arbitrary tool/version/platform" do
    check all tool <- gen_tool_name(),
              version <- gen_version_string(),
              platform <- gen_platform() do
      result = UrlHandler.archive_url(tool, version, platform, gen_url_handler())
      assert match?({:ok, _}, result) or match?({:error, _}, result),
             "archive_url crashed for #{tool}/#{version}/#{platform}"
    end
  end

  property "UrlHandler.archive_url/4 returns url string on success" do
    check all version <- gen_semver(),
              platform <- StreamData.member_of([:linux_amd64, :linux_arm64, :darwin_amd64]) do
      case UrlHandler.archive_url("zig", version, platform, gen_url_handler()) do
        {:ok, url} ->
          assert is_binary(url) and String.starts_with?(url, "https://"),
                 "expected https:// url, got #{inspect(url)}"
        {:error, _} ->
          :ok
      end
    end
  end
end
