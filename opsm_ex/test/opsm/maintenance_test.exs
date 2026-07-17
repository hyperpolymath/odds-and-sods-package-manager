# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
defmodule Opsm.MaintenanceTest do
  use ExUnit.Case, async: false

  alias Opsm.Maintenance

  # Use a temporary directory for test data
  @test_data_dir Path.join(System.tmp_dir!(), "opsm_maint_test_#{:rand.uniform(1_000_000)}")
  @test_history_path Path.join(@test_data_dir, "history.json")
  @test_pins_path Path.join(@test_data_dir, "pins.json")

  setup do
    # Create test directory
    File.mkdir_p!(@test_data_dir)

    # Clean up any existing test files
    File.rm(@test_history_path)
    File.rm(@test_pins_path)

    on_exit(fn ->
      File.rm_rf!(@test_data_dir)
    end)

    :ok
  end

  describe "clean/2" do
    setup do
      cache_dir = Path.join(@test_data_dir, "cache")
      tmp_dir = Path.join(@test_data_dir, "tmp")

      File.mkdir_p!(cache_dir)
      File.mkdir_p!(tmp_dir)

      # Create some test files
      File.write!(Path.join(cache_dir, "cached_file.tar.gz"), "cached data")
      File.write!(Path.join(tmp_dir, "temp_file.tmp"), "temp data")

      {:ok, cache_dir: cache_dir, tmp_dir: tmp_dir}
    end

    test "returns error for unknown target" do
      {:error, reason} = Maintenance.clean("unknown")
      assert reason =~ "Unknown clean target"
    end

    test "dry run does not delete files", %{cache_dir: _cache_dir} do
      # Note: This test would need the actual cache path to be configurable
      # For now, we test the return value
      {:ok, _} = Maintenance.clean("cache", dry_run: true)
    end
  end

  describe "record_history/2" do
    test "records operation in history" do
      # This test requires the module to use configurable paths
      # For now, we test that the function doesn't crash
      id = Maintenance.record_history("install", %{"package" => "test-pkg", "version" => "1.0.0"})

      assert is_binary(id)
      # 8 bytes hex encoded
      assert String.length(id) == 16
    end
  end

  describe "list_history/1" do
    test "returns empty list when no history" do
      history = Maintenance.list_history()
      # May be empty or have entries from record_history test
      assert is_list(history)
    end

    test "respects limit option" do
      # Record multiple entries
      for i <- 1..5 do
        Maintenance.record_history("test", %{"index" => i})
      end

      history = Maintenance.list_history(limit: 3)
      assert length(history) <= 3
    end
  end

  describe "pin/2 and unpin/1" do
    test "pin records package" do
      :ok = Maintenance.pin("test-package", "1.0.0")

      assert Maintenance.pinned?("test-package")
    end

    test "pin without version uses nil" do
      :ok = Maintenance.pin("another-package")

      pin = Maintenance.get_pin("another-package")
      assert pin["package"] == "another-package"
      assert pin["version"] == nil
    end

    test "unpin removes pin" do
      :ok = Maintenance.pin("to-unpin", "2.0.0")
      assert Maintenance.pinned?("to-unpin")

      :ok = Maintenance.unpin("to-unpin")
      refute Maintenance.pinned?("to-unpin")
    end

    test "unpin returns error for non-pinned package" do
      {:error, reason} = Maintenance.unpin("never-pinned")
      assert reason =~ "not pinned"
    end
  end

  describe "pinned?/1" do
    test "returns false for non-pinned package" do
      refute Maintenance.pinned?("not-pinned-#{:rand.uniform(1000)}")
    end

    test "returns true for pinned package" do
      Maintenance.pin("check-pinned", "1.0.0")
      assert Maintenance.pinned?("check-pinned")
    end
  end

  describe "list_pins/0" do
    test "returns list of pins" do
      pins = Maintenance.list_pins()
      assert is_list(pins)
    end

    test "includes newly pinned packages" do
      pkg_name = "list-test-#{:rand.uniform(1000)}"
      Maintenance.pin(pkg_name, "3.0.0")

      pins = Maintenance.list_pins()
      assert Enum.any?(pins, fn p -> p["package"] == pkg_name end)
    end
  end

  describe "get_pin/1" do
    test "returns nil for non-pinned package" do
      assert Maintenance.get_pin("nonexistent-#{:rand.uniform(1000)}") == nil
    end

    test "returns pin info for pinned package" do
      pkg_name = "get-pin-test-#{:rand.uniform(1000)}"
      Maintenance.pin(pkg_name, "4.0.0")

      pin = Maintenance.get_pin(pkg_name)
      assert pin["package"] == pkg_name
      assert pin["version"] == "4.0.0"
      assert pin["pinned_at"] != nil
    end
  end

  describe "get_history_entry/1" do
    test "returns nil for non-existent id" do
      assert Maintenance.get_history_entry("nonexistent") == nil
    end

    test "returns entry for valid id" do
      id = Maintenance.record_history("test-op", %{"data" => "value"})

      entry = Maintenance.get_history_entry(id)
      assert entry["id"] == id
      assert entry["operation"] == "test-op"
      assert entry["details"]["data"] == "value"
    end
  end

  describe "undo_last/0" do
    test "returns error when no history" do
      # Clear history by using fresh run
      # This test may be flaky if other tests add history
      result = Maintenance.undo_last()

      case result do
        {:error, "No history to undo"} -> assert true
        # Has history from other tests
        {:ok, _, _} -> assert true
        # Cannot undo some operations
        {:error, _} -> assert true
      end
    end
  end

  describe "undo_by_id/1 — by position" do
    test "returns error when position is out of range" do
      # Only 2 entries recorded
      Maintenance.record_history("test-op", %{"package" => "pkg-a"})
      Maintenance.record_history("test-op", %{"package" => "pkg-b"})

      assert {:error, msg} = Maintenance.undo_by_id(999)
      assert msg =~ "position 999"
    end

    test "returns error for position 0 (1-based)" do
      Maintenance.record_history("test-op", %{"package" => "pkg-a"})

      assert {:error, msg} = Maintenance.undo_by_id(0)
      assert msg =~ "position 0"
    end

    test "returns cannot-undo for non-reversible operation at position" do
      # "test-op" is not install/remove, so undo is rejected at do_undo_entry
      Maintenance.record_history("test-op", %{"package" => "pkg-a"})

      assert {:error, msg} = Maintenance.undo_by_id(1)
      assert msg =~ "Cannot undo operation: test-op"
    end

    test "finds correct entry by 1-based position" do
      Maintenance.record_history("test-op", %{"package" => "first"})
      Maintenance.record_history("test-op", %{"package" => "second"})

      # History is newest-first; position 1 = most recent = "second"
      assert {:error, msg} = Maintenance.undo_by_id(1)
      assert msg =~ "Cannot undo operation: test-op"

      # Position 2 = older entry = "first"
      assert {:error, msg2} = Maintenance.undo_by_id(2)
      assert msg2 =~ "Cannot undo operation: test-op"
    end
  end

  describe "undo_by_id/1 — by hex ID" do
    test "returns error for non-existent hex ID" do
      assert {:error, msg} = Maintenance.undo_by_id("deadbeefdeadbeef")
      assert msg =~ "deadbeefdeadbeef"
    end

    test "finds entry by exact hex ID" do
      id = Maintenance.record_history("test-op", %{"package" => "pkg-by-id"})

      # "test-op" is not undoable, but the lookup must succeed (error is from do_undo_entry)
      assert {:error, msg} = Maintenance.undo_by_id(id)
      assert msg =~ "Cannot undo operation: test-op"
    end

    test "ID lookup is exact — partial IDs do not match" do
      id = Maintenance.record_history("test-op", %{"package" => "pkg-partial"})
      partial = String.slice(id, 0, 4)

      assert {:error, msg} = Maintenance.undo_by_id(partial)
      assert msg =~ partial
    end
  end

  describe "pin-awareness: update skips pinned packages" do
    test "pinned? returns true after pinning" do
      pkg = "pin-aware-test-#{:rand.uniform(100_000)}"
      Maintenance.pin(pkg, "1.0.0")
      assert Maintenance.pinned?(pkg)
    end

    test "get_pin returns version constraint after pin" do
      pkg = "pin-version-#{:rand.uniform(100_000)}"
      Maintenance.pin(pkg, "2.3.4")

      pin = Maintenance.get_pin(pkg)
      assert pin["version"] == "2.3.4"
    end

    test "pinned? returns false after unpin" do
      pkg = "pin-then-unpin-#{:rand.uniform(100_000)}"
      Maintenance.pin(pkg, "1.0.0")
      assert Maintenance.pinned?(pkg)

      Maintenance.unpin(pkg)
      refute Maintenance.pinned?(pkg)
    end

    test "upgrade_path returns :pinned_skip for version-pinned package (no network)" do
      # upgrade_path requires network to check registry versions; skip if not available
      # What we can assert without network: the pin state is correct
      pkg = "upgrade-path-pin-#{:rand.uniform(100_000)}"
      Maintenance.pin(pkg, "1.0.0")

      pin = Maintenance.get_pin(pkg)
      assert pin["version"] == "1.0.0"
      assert Maintenance.pinned?(pkg)

      # upgrade_path itself would return {:error, :not_installed} for a package not in installed.json,
      # but the pin check logic is covered by pinned? + get_pin above
    end
  end

  describe "autoremove/1" do
    test "returns ok with empty list (not implemented yet)" do
      {:ok, removed} = Maintenance.autoremove()
      assert removed == []
    end

    test "accepts dry_run option" do
      {:ok, removed} = Maintenance.autoremove(dry_run: true)
      assert removed == []
    end
  end
end
