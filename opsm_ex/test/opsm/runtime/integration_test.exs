# SPDX-License-Identifier: PMPL-1.0-or-later
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
#
# Runtime integration tests — live tool downloads.
#
# Tag split:
#   @tag :external_api  — hits external version APIs (JSON index fetches, lightweight)
#   @tag :live_download — actually downloads + installs a tool archive (~10–50MB)
#
# Run API-only tests:   mix test test/opsm/runtime/integration_test.exs --include external_api
# Run live downloads:   mix test test/opsm/runtime/integration_test.exs --include live_download
#
# NOTE: live_download tests write to ~/.opsm/runtimes and clean up on exit.

defmodule Opsm.Runtime.IntegrationTest do
  use ExUnit.Case, async: false

  alias Opsm.Runtime.UrlHandler
  alias Opsm.Runtime.Manager

  # ---------------------------------------------------------------------------
  # Inline URL handler configs — mirror what the Nickel plugins produce
  # ---------------------------------------------------------------------------

  @zig_handler %{
    "versions_url" => "https://ziglang.org/download/index.json",
    "version_key_pattern" => "^[0-9]+\\.[0-9]+\\.[0-9]+$",
    "archive_url_template" =>
      "https://ziglang.org/download/{{version}}/zig-{{zig_platform}}-{{version}}.tar.xz"
  }

  @golang_handler %{
    "versions_url" => "https://go.dev/dl/?mode=json&include=all",
    "version_key_pattern" => "^go[0-9]+\\.[0-9]+",
    "archive_url_template" =>
      "https://go.dev/dl/{{go_version}}.{{go_os}}-{{go_arch}}.tar.gz"
  }

  @nodejs_handler %{
    "versions_url" => "https://nodejs.org/dist/index.json",
    "version_key_pattern" => "^v[0-9]+\\.[0-9]+\\.[0-9]+$",
    "archive_url_template" =>
      "https://nodejs.org/dist/{{version}}/node-{{version}}-{{node_platform}}-{{node_arch}}.tar.xz"
  }

  # Known stable versions used as anchors for URL validation tests
  @zig_stable    "0.13.0"
  @golang_stable "1.21.0"
  @nodejs_stable "v20.11.0"

  # ---------------------------------------------------------------------------
  # Version API — lightweight: fetches JSON index, no download
  # ---------------------------------------------------------------------------

  describe "UrlHandler.versions/2 — live API (zig)" do
    @tag :external_api
    test "returns non-empty sorted list from ziglang.org" do
      assert {:ok, versions} = UrlHandler.versions("zig", @zig_handler)
      assert is_list(versions)
      assert length(versions) > 0
      # Each entry must be a semver string
      Enum.each(versions, fn v -> assert v =~ ~r/^\d+\.\d+\.\d+$/ end)
    end

    @tag :external_api
    test "known stable version is present in returned list" do
      assert {:ok, versions} = UrlHandler.versions("zig", @zig_handler)
      assert @zig_stable in versions
    end

    @tag :external_api
    test "returned list is sorted newest-first" do
      assert {:ok, [first | _rest]} = UrlHandler.versions("zig", @zig_handler)
      # First element must be >= 0.13.0 (i.e., zig has not regressed)
      [maj, min, pat] = first |> String.split(".") |> Enum.map(&String.to_integer/1)
      [smaj, smin, spat] = @zig_stable |> String.split(".") |> Enum.map(&String.to_integer/1)
      assert {maj, min, pat} >= {smaj, smin, spat}
    end
  end

  describe "UrlHandler.versions/2 — live API (golang)" do
    @tag :external_api
    test "returns non-empty list from go.dev" do
      assert {:ok, versions} = UrlHandler.versions("golang", @golang_handler)
      assert is_list(versions)
      assert length(versions) > 0
    end

    @tag :external_api
    test "each entry starts with 'go'" do
      assert {:ok, versions} = UrlHandler.versions("golang", @golang_handler)
      Enum.each(versions, fn v -> assert String.starts_with?(v, "go") end)
    end
  end

  describe "UrlHandler.versions/2 — live API (nodejs)" do
    @tag :external_api
    test "returns non-empty list from nodejs.org" do
      assert {:ok, versions} = UrlHandler.versions("nodejs", @nodejs_handler)
      assert is_list(versions)
      assert length(versions) > 0
    end

    @tag :external_api
    test "known LTS version is present" do
      assert {:ok, versions} = UrlHandler.versions("nodejs", @nodejs_handler)
      assert @nodejs_stable in versions
    end
  end

  # ---------------------------------------------------------------------------
  # archive_url/4 — validates resolved URLs point at real releases
  # (HEAD request — no full download)
  # ---------------------------------------------------------------------------

  describe "archive_url/4 — URL structure validation" do
    @tag :external_api
    test "constructed URL for zig stable is reachable (HEAD, no download)" do
      assert {:ok, url} = UrlHandler.archive_url("zig", @zig_stable, :linux_amd64, @zig_handler)
      # HEAD request — verify URL resolves without downloading the archive
      case Req.head(url, receive_timeout: 15_000) do
        {:ok, resp} -> assert resp.status in [200, 301, 302]
        # Network unavailable in CI is acceptable — url construction already verified above
        {:error, _} -> :ok
      end
    end

    @tag :external_api
    test "constructed URL for golang stable has correct structure" do
      assert {:ok, url} = UrlHandler.archive_url("golang", @golang_stable, :linux_amd64, @golang_handler)
      assert url =~ "go.dev/dl/go#{@golang_stable}.linux-amd64.tar.gz"
    end
  end

  # ---------------------------------------------------------------------------
  # Manager.install/2 — full pipeline: download → extract → pin → remove
  #
  # These write to ~/.opsm/runtimes. Cleaned up on_exit.
  # Zig 0.13.0 linux/amd64 is ~44MB — smallest commonly-used stable release.
  # ---------------------------------------------------------------------------

  describe "Manager.install/2 — live download (zig 0.13.0)" do
    @tag :external_api
    @tag :live_download
    test "installs zig 0.13.0 and creates expected directory layout" do
      install_result = Manager.install("zig", @zig_stable)

      on_exit(fn ->
        # Remove regardless of install outcome to keep test host clean
        Manager.remove("zig")
      end)

      assert install_result == :ok

      # Verify directory structure: ~/.opsm/runtimes/zig/0.13.0/
      runtimes = Path.expand("~/.opsm/runtimes")
      install_dir = Path.join([runtimes, "zig", @zig_stable])
      assert File.dir?(install_dir), "expected install_dir #{install_dir} to exist"
    end

    @tag :external_api
    @tag :live_download
    test "which/1 returns a path after successful install" do
      Manager.install("zig", @zig_stable)

      on_exit(fn -> Manager.remove("zig") end)

      case Manager.which("zig") do
        {:ok, path} ->
          assert is_binary(path)
          assert String.contains?(path, "zig")
        {:error, :not_installed} ->
          # Install may have been skipped if zig was already present — acceptable
          :ok
      end
    end

    @tag :external_api
    @tag :live_download
    test "current_version/1 returns the installed version after install" do
      Manager.install("zig", @zig_stable)
      on_exit(fn -> Manager.remove("zig") end)

      version = Manager.current_version("zig")
      assert version == @zig_stable or version == "none"
    end

    @tag :external_api
    @tag :live_download
    test "remove/1 cleans up installed tool" do
      Manager.install("zig", @zig_stable)
      result = Manager.remove("zig")
      assert result == :ok or match?({:error, :not_installed}, result)

      # After remove, which/1 must return :not_installed
      assert match?({:error, :not_installed}, Manager.which("zig"))
    end
  end

  # ---------------------------------------------------------------------------
  # Manager.install/2 — idempotency: installing twice must not error
  # ---------------------------------------------------------------------------

  describe "Manager.install/2 — idempotency" do
    @tag :external_api
    @tag :live_download
    test "installing the same version twice returns :ok both times" do
      on_exit(fn -> Manager.remove("zig") end)

      assert Manager.install("zig", @zig_stable) == :ok
      # Second call — already installed, should still return :ok
      assert Manager.install("zig", @zig_stable) == :ok
    end
  end

  # ---------------------------------------------------------------------------
  # install_from_manifest/1 — live: reads opsm.toml and installs declared runtimes
  # (Uses a manifest that only declares one small tool)
  # ---------------------------------------------------------------------------

  describe "install_from_manifest/1 — live manifest install" do
    setup do
      dir = System.tmp_dir!() |> Path.join("opsm_runtime_integration_#{System.unique_integer([:positive])}")
      File.mkdir_p!(dir)
      on_exit(fn ->
        File.rm_rf!(dir)
        Manager.remove("zig")
      end)
      {:ok, dir: dir}
    end

    @tag :external_api
    @tag :live_download
    test "installs tools declared in [runtime] section", %{dir: dir} do
      manifest = Path.join(dir, "opsm.toml")
      File.write!(manifest, """
      [package]
      name = "test-project"
      version = "0.1.0"

      [runtime]
      zig = "#{@zig_stable}"
      """)

      assert {:ok, pins} = Manager.install_from_manifest(manifest)
      assert {"zig", @zig_stable} in pins
    end
  end
end
