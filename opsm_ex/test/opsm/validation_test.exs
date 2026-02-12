# SPDX-License-Identifier: PMPL-1.0
defmodule Opsm.ValidationTest do
  use ExUnit.Case, async: true

  alias Opsm.Validation

  describe "validate_package_name/2" do
    test "accepts valid npm package names" do
      assert {:ok, _} = Validation.validate_package_name("lodash", :npm)
      assert {:ok, _} = Validation.validate_package_name("@scope/package", :npm)
      assert {:ok, _} = Validation.validate_package_name("my-package", :npm)
      assert {:ok, _} = Validation.validate_package_name("my_package", :npm)
    end

    test "accepts valid cargo package names" do
      assert {:ok, _} = Validation.validate_package_name("serde", :cargo)
      assert {:ok, _} = Validation.validate_package_name("tokio-runtime", :cargo)
      assert {:ok, _} = Validation.validate_package_name("my_crate", :cargo)
    end

    test "accepts valid hex package names" do
      assert {:ok, _} = Validation.validate_package_name("phoenix", :hex)
      assert {:ok, _} = Validation.validate_package_name("ecto_sql", :hex)
    end

    test "rejects empty package names" do
      assert {:error, _} = Validation.validate_package_name("", :npm)
      assert {:error, _} = Validation.validate_package_name("", :cargo)
    end

    test "rejects package names with shell metacharacters" do
      assert {:error, _} = Validation.validate_package_name("pkg;rm -rf /", :npm)
      assert {:error, _} = Validation.validate_package_name("pkg`echo`", :npm)
      assert {:error, _} = Validation.validate_package_name("pkg$(cmd)", :npm)
      assert {:error, _} = Validation.validate_package_name("pkg|cat", :npm)
      assert {:error, _} = Validation.validate_package_name("pkg&bg", :npm)
    end

    test "rejects package names with path traversal" do
      assert {:error, _} = Validation.validate_package_name("../etc/passwd", :npm)
      assert {:error, _} = Validation.validate_package_name("..\\windows", :npm)
    end

    test "rejects nil package name" do
      assert {:error, _} = Validation.validate_package_name(nil, :npm)
    end
  end

  describe "validate_version/1" do
    test "accepts valid semver versions" do
      assert {:ok, _} = Validation.validate_version("1.0.0")
      assert {:ok, _} = Validation.validate_version("0.1.0")
      assert {:ok, _} = Validation.validate_version("10.20.30")
    end

    test "accepts versions with prerelease" do
      assert {:ok, _} = Validation.validate_version("1.0.0-alpha")
      assert {:ok, _} = Validation.validate_version("1.0.0-beta.1")
      assert {:ok, _} = Validation.validate_version("1.0.0-rc.1")
    end

    test "accepts versions with build metadata" do
      assert {:ok, _} = Validation.validate_version("1.0.0+build")
      assert {:ok, _} = Validation.validate_version("1.0.0+20130313144700")
    end

    test "accepts nil version (latest)" do
      assert {:ok, _} = Validation.validate_version(nil)
    end

    test "rejects invalid versions" do
      assert {:error, _} = Validation.validate_version("not-a-version")
      assert {:error, _} = Validation.validate_version("v1.0.0;echo")
      assert {:error, _} = Validation.validate_version("1.0.0`cmd`")
    end
  end

  describe "validate_url/1" do
    test "accepts valid https URLs" do
      assert {:ok, _} = Validation.validate_url("https://example.com")
      assert {:ok, _} = Validation.validate_url("https://registry.npmjs.org/lodash")
      assert {:ok, _} = Validation.validate_url("https://api.github.com/repos/user/repo")
    end

    test "accepts valid http URLs" do
      assert {:ok, _} = Validation.validate_url("http://example.com")
      assert {:ok, _} = Validation.validate_url("http://registry.npmjs.org/lodash")
    end

    test "rejects localhost and loopback URLs (SSRF prevention)" do
      assert {:error, reason} = Validation.validate_url("http://localhost:8080")
      assert reason =~ "blocked"
      assert {:error, reason} = Validation.validate_url("http://127.0.0.1:3000/api")
      assert reason =~ "blocked"
    end

    test "rejects file:// URLs" do
      assert {:error, reason} = Validation.validate_url("file:///etc/passwd")
      # file:// URLs may fail because they have no host, or because scheme is not allowed
      assert reason =~ "not allowed" or reason =~ "host"
    end

    test "rejects ftp:// URLs" do
      assert {:error, reason} = Validation.validate_url("ftp://ftp.example.com/file")
      assert reason =~ "not allowed" or reason =~ "not supported"
    end

    test "rejects javascript: URLs" do
      assert {:error, reason} = Validation.validate_url("javascript:alert(1)")
      # javascript: URLs have no host, so we get "must have a host" error
      assert reason =~ "host" or reason =~ "not allowed"
    end

    test "rejects data: URLs" do
      assert {:error, reason} = Validation.validate_url("data:text/html,<script>alert(1)</script>")
      # data: URLs have no host, so we get "must have a host" error
      assert reason =~ "host" or reason =~ "not allowed"
    end

    test "rejects URLs without host" do
      assert {:error, _} = Validation.validate_url("https://")
      assert {:error, _} = Validation.validate_url("http://")
    end

    test "rejects URLs without scheme" do
      assert {:error, _} = Validation.validate_url("example.com/path")
      assert {:error, _} = Validation.validate_url("//example.com")
    end

    test "rejects nil URL" do
      assert {:error, _} = Validation.validate_url(nil)
    end

    test "rejects empty URL" do
      assert {:error, _} = Validation.validate_url("")
    end

    test "rejects non-string URL" do
      assert {:error, _} = Validation.validate_url(123)
      assert {:error, _} = Validation.validate_url(%{})
    end
  end

  describe "validate_path/1" do
    test "accepts valid relative paths" do
      assert {:ok, _} = Validation.validate_path("./package")
      assert {:ok, _} = Validation.validate_path("src/lib")
      assert {:ok, _} = Validation.validate_path("file.txt")
    end

    test "accepts valid absolute paths" do
      assert {:ok, _} = Validation.validate_path("/home/user/project")
      assert {:ok, _} = Validation.validate_path("/tmp/opsm")
    end

    test "rejects paths with null bytes" do
      assert {:error, _} = Validation.validate_path("path\x00evil")
    end

    test "rejects empty path" do
      assert {:error, _} = Validation.validate_path("")
    end

    test "rejects nil path" do
      assert {:error, _} = Validation.validate_path(nil)
    end
  end

  describe "sanitize_path/1" do
    test "returns path without traversal" do
      {:ok, path} = Validation.sanitize_path("/home/user/project")
      assert path == "/home/user/project"
    end

    test "removes path traversal attempts" do
      {:ok, path} = Validation.sanitize_path("/home/../etc/passwd")
      refute path =~ ".."
    end

    test "expands relative paths" do
      {:ok, path} = Validation.sanitize_path("./relative")
      assert Path.type(path) == :absolute
    end
  end
end
