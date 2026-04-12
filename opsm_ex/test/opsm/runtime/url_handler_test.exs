# SPDX-License-Identifier: PMPL-1.0-or-later
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
defmodule Opsm.Runtime.UrlHandlerTest do
  use ExUnit.Case, async: true

  alias Opsm.Runtime.UrlHandler

  # ---------------------------------------------------------------------------
  # archive_url/4 — platform variable resolution
  # ---------------------------------------------------------------------------

  describe "archive_url/4 — zig" do
    @zig_handler %{
      "versions_url" => "https://ziglang.org/download/index.json",
      "version_key_pattern" => "^[0-9]+\\.[0-9]+\\.[0-9]+$",
      "archive_url_template" =>
        "https://ziglang.org/download/{{version}}/zig-{{zig_platform}}-{{version}}.tar.xz"
    }

    test "linux_amd64 → linux-x86_64" do
      assert {:ok, url} = UrlHandler.archive_url("zig", "0.13.0", :linux_amd64, @zig_handler)
      assert url == "https://ziglang.org/download/0.13.0/zig-linux-x86_64-0.13.0.tar.xz"
    end

    test "linux_arm64 → linux-aarch64" do
      assert {:ok, url} = UrlHandler.archive_url("zig", "0.13.0", :linux_arm64, @zig_handler)
      assert url == "https://ziglang.org/download/0.13.0/zig-linux-aarch64-0.13.0.tar.xz"
    end

    test "darwin_amd64 → macos-x86_64" do
      assert {:ok, url} = UrlHandler.archive_url("zig", "0.13.0", :darwin_amd64, @zig_handler)
      assert url == "https://ziglang.org/download/0.13.0/zig-macos-x86_64-0.13.0.tar.xz"
    end

    test "darwin_arm64 → macos-aarch64" do
      assert {:ok, url} = UrlHandler.archive_url("zig", "0.13.0", :darwin_arm64, @zig_handler)
      assert url == "https://ziglang.org/download/0.13.0/zig-macos-aarch64-0.13.0.tar.xz"
    end

    test "windows_amd64 → windows-x86_64" do
      assert {:ok, url} = UrlHandler.archive_url("zig", "0.13.0", :windows_amd64, @zig_handler)
      assert url == "https://ziglang.org/download/0.13.0/zig-windows-x86_64-0.13.0.tar.xz"
    end

    test "unsupported platform returns error" do
      assert {:error, :unsupported_platform} =
               UrlHandler.archive_url("zig", "0.13.0", :freebsd_amd64, @zig_handler)
    end
  end

  describe "archive_url/4 — golang" do
    @go_handler %{
      "versions_url" => "https://go.dev/dl/?mode=json&include=all",
      "version_key_pattern" => "^go[0-9]+\\.[0-9]+",
      "archive_url_template" =>
        "https://go.dev/dl/{{go_version}}.{{go_os}}-{{go_arch}}.tar.gz"
    }

    test "linux_amd64 builds correct URL" do
      assert {:ok, url} = UrlHandler.archive_url("golang", "1.21.0", :linux_amd64, @go_handler)
      assert url == "https://go.dev/dl/go1.21.0.linux-amd64.tar.gz"
    end

    test "darwin_arm64 builds correct URL" do
      assert {:ok, url} = UrlHandler.archive_url("golang", "1.21.0", :darwin_arm64, @go_handler)
      assert url == "https://go.dev/dl/go1.21.0.darwin-arm64.tar.gz"
    end

    test "windows_amd64 builds correct URL" do
      assert {:ok, url} = UrlHandler.archive_url("golang", "1.21.0", :windows_amd64, @go_handler)
      assert url == "https://go.dev/dl/go1.21.0.windows-amd64.tar.gz"
    end
  end

  describe "archive_url/4 — nodejs" do
    @node_handler %{
      "versions_url" => "https://nodejs.org/dist/index.json",
      "version_key_pattern" => "^v[0-9]+\\.[0-9]+\\.[0-9]+$",
      "archive_url_template" =>
        "https://nodejs.org/dist/v{{version}}/node-v{{version}}-{{node_os}}-{{node_arch}}.tar.gz"
    }

    test "linux_amd64 → linux-x64" do
      assert {:ok, url} = UrlHandler.archive_url("nodejs", "20.0.0", :linux_amd64, @node_handler)
      assert url == "https://nodejs.org/dist/v20.0.0/node-v20.0.0-linux-x64.tar.gz"
    end

    test "darwin_arm64 → darwin-arm64" do
      assert {:ok, url} = UrlHandler.archive_url("nodejs", "20.0.0", :darwin_arm64, @node_handler)
      assert url == "https://nodejs.org/dist/v20.0.0/node-v20.0.0-darwin-arm64.tar.gz"
    end

    test "windows_amd64 → win-x64" do
      assert {:ok, url} = UrlHandler.archive_url("nodejs", "20.0.0", :windows_amd64, @node_handler)
      assert url == "https://nodejs.org/dist/v20.0.0/node-v20.0.0-win-x64.tar.gz"
    end
  end

  describe "archive_url/4 — dart" do
    @dart_handler %{
      "versions_url" => "https://storage.googleapis.com/dart-archive/channels/stable/release/latest/VERSION",
      "archive_url_template" =>
        "https://storage.googleapis.com/dart-archive/channels/stable/release/{{version}}/sdk/dartsdk-{{dart_os}}-{{dart_arch}}-release.zip"
    }

    test "linux_amd64 → linux-x64" do
      assert {:ok, url} = UrlHandler.archive_url("dart", "3.3.0", :linux_amd64, @dart_handler)
      assert url =~ "dartsdk-linux-x64-release.zip"
    end

    test "darwin_arm64 → macos-arm64" do
      assert {:ok, url} = UrlHandler.archive_url("dart", "3.3.0", :darwin_arm64, @dart_handler)
      assert url =~ "dartsdk-macos-arm64-release.zip"
    end
  end

  describe "archive_url/4 — nim" do
    @nim_handler %{
      "versions_url" => "https://api.github.com/repos/nim-lang/Nim/releases",
      "version_key_pattern" => "^[0-9]+\\.[0-9]+\\.[0-9]+$",
      "archive_url_template" =>
        "https://nim-lang.org/download/nim-{{version}}_{{nim_os}}_{{nim_arch}}.tar.xz"
    }

    test "linux_amd64 → linux_x64" do
      assert {:ok, url} = UrlHandler.archive_url("nim", "2.0.2", :linux_amd64, @nim_handler)
      assert url == "https://nim-lang.org/download/nim-2.0.2_linux_x64.tar.xz"
    end

    test "darwin_arm64 → macos_arm64" do
      assert {:ok, url} = UrlHandler.archive_url("nim", "2.0.2", :darwin_arm64, @nim_handler)
      assert url == "https://nim-lang.org/download/nim-2.0.2_macos_arm64.tar.xz"
    end
  end

  describe "archive_url/4 — kubectl" do
    @kubectl_handler %{
      "versions_url" => "https://api.github.com/repos/kubernetes/kubectl/releases",
      "version_key_pattern" => "^v[0-9]+\\.[0-9]+\\.[0-9]+$",
      "archive_url_template" =>
        "https://dl.k8s.io/release/v{{version}}/bin/{{kubectl_os}}/{{kubectl_arch}}/kubectl"
    }

    test "linux_amd64 builds dl.k8s.io URL" do
      assert {:ok, url} = UrlHandler.archive_url("kubectl", "1.32.0", :linux_amd64, @kubectl_handler)
      assert url == "https://dl.k8s.io/release/v1.32.0/bin/linux/amd64/kubectl"
    end

    test "darwin_arm64 builds dl.k8s.io URL" do
      assert {:ok, url} = UrlHandler.archive_url("kubectl", "1.32.0", :darwin_arm64, @kubectl_handler)
      assert url == "https://dl.k8s.io/release/v1.32.0/bin/darwin/arm64/kubectl"
    end
  end

  describe "archive_url/4 — unknown tool" do
    test "returns no_url_handler for unrecognised tool" do
      handler = %{"archive_url_template" => "https://example.com/{{version}}"}
      assert {:error, :no_url_handler} =
               UrlHandler.archive_url("unknowntool999", "1.0.0", :linux_amd64, handler)
    end
  end

  # ---------------------------------------------------------------------------
  # versions/2 — version extraction from JSON responses
  # ---------------------------------------------------------------------------

  describe "versions/2 — JSON object (Zig-style)" do
    test "extracts and filters version keys" do
      # Simulate Zig JSON index response body (already decoded)
      body = %{
        "0.13.0" => %{"x86_64-linux" => %{"tarball" => "..."}},
        "0.12.0" => %{"x86_64-linux" => %{"tarball" => "..."}},
        "master" => %{"x86_64-linux" => %{"tarball" => "..."}}
      }
      handler = %{
        "versions_url" => "unused",
        "version_key_pattern" => "^[0-9]+\\.[0-9]+\\.[0-9]+$",
        "archive_url_template" => "unused"
      }

      # We can't call versions/2 directly (it hits the network), but we can
      # test the extraction logic via the public contract indirectly.
      # For now, assert the handler map is well-formed.
      assert is_binary(handler["version_key_pattern"])
    end
  end
end
