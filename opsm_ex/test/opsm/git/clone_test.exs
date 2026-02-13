# SPDX-License-Identifier: PMPL-1.0
defmodule Opsm.Git.CloneTest do
  use ExUnit.Case, async: true

  alias Opsm.Git.Clone

  describe "clone/2" do
    test "rejects URLs targeting localhost" do
      assert {:error, msg} = Clone.clone("http://localhost/repo.git")
      assert msg =~ "Invalid clone URL"
    end

    test "rejects URLs targeting private IPs" do
      assert {:error, msg} = Clone.clone("http://192.168.1.1/repo.git")
      assert msg =~ "Invalid clone URL"
    end

    test "rejects URLs targeting 127.0.0.1" do
      assert {:error, msg} = Clone.clone("http://127.0.0.1/repo.git")
      assert msg =~ "Invalid clone URL"
    end

    @tag timeout: 120_000
    test "accepts SSH URLs (git@)" do
      # SSH URLs bypass HTTP SSRF validation, so we test they aren't rejected
      # by URL validation. The actual clone will fail (no such host) but should
      # fail at git level, not at URL validation.
      result = Clone.clone("git@127.0.0.1:user/nonexistent-repo.git")
      # Should fail at git clone, not URL validation
      assert {:error, msg} = result
      assert msg =~ "git clone failed"
    end

    test "rejects file:// URLs" do
      assert {:error, msg} = Clone.clone("file:///etc/passwd")
      assert msg =~ "Invalid clone URL"
    end
  end

  describe "cleanup/1" do
    test "removes temporary directory" do
      dir = Path.join(System.tmp_dir!(), "opsm_clone_test_#{:rand.uniform(100_000)}")
      File.mkdir_p!(dir)
      File.write!(Path.join(dir, "test.txt"), "hello")

      assert :ok = Clone.cleanup(dir)
      refute File.exists?(dir)
    end

    test "handles non-existent directory gracefully" do
      assert :ok = Clone.cleanup("/tmp/opsm_nonexistent_dir_#{:rand.uniform(100_000)}")
    end
  end
end
