# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
defmodule Opsm.Package.TransactionTest do
  use ExUnit.Case, async: true

  alias Opsm.Package.Transaction

  describe "new/1" do
    test "creates a new transaction with package name" do
      txn = Transaction.new("my-package")

      assert txn.package_name == "my-package"
      assert txn.directories == []
      assert txn.files == []
      assert txn.symlinks == []
      assert txn.db_entries == []
      assert txn.completed == false
      assert %DateTime{} = txn.started_at
    end
  end

  describe "record_directory/2" do
    test "adds directory to transaction" do
      txn = Transaction.new("pkg")
      txn = Transaction.record_directory(txn, "/tmp/test-dir")

      assert "/tmp/test-dir" in txn.directories
    end

    test "accumulates multiple directories" do
      txn =
        Transaction.new("pkg")
        |> Transaction.record_directory("/tmp/dir1")
        |> Transaction.record_directory("/tmp/dir2")

      assert length(txn.directories) == 2
    end
  end

  describe "record_file/2" do
    test "adds file to transaction" do
      txn = Transaction.new("pkg")
      txn = Transaction.record_file(txn, "/tmp/test-file.txt")

      assert "/tmp/test-file.txt" in txn.files
    end
  end

  describe "record_symlink/2" do
    test "adds symlink to transaction" do
      txn = Transaction.new("pkg")
      txn = Transaction.record_symlink(txn, "/tmp/link")

      assert "/tmp/link" in txn.symlinks
    end
  end

  describe "mark_completed/1" do
    test "marks transaction as completed" do
      txn =
        Transaction.new("pkg")
        |> Transaction.complete()

      assert txn.completed == true
    end
  end

  describe "safe_symlink/3" do
    setup do
      # Create a temp directory for testing
      tmp_dir = Path.join(System.tmp_dir!(), "opsm_test_#{:rand.uniform(1_000_000)}")
      File.mkdir_p!(tmp_dir)

      on_exit(fn -> File.rm_rf!(tmp_dir) end)

      {:ok, tmp_dir: tmp_dir}
    end

    test "creates symlink when target doesn't exist", %{tmp_dir: tmp_dir} do
      txn = Transaction.new("pkg")
      source = Path.join(tmp_dir, "source_file")
      target = Path.join(tmp_dir, "link")

      # Create source file
      File.write!(source, "content")

      {:ok, txn} = Transaction.safe_symlink(txn, source, target)

      assert File.exists?(target)
      assert {:ok, %{type: :symlink}} = File.lstat(target)
      assert target in txn.symlinks
    end

    test "returns error when target already exists as file", %{tmp_dir: tmp_dir} do
      txn = Transaction.new("pkg")
      source = Path.join(tmp_dir, "source")
      target = Path.join(tmp_dir, "existing_file")

      File.write!(source, "source")
      File.write!(target, "existing")

      {:error, reason} = Transaction.safe_symlink(txn, source, target)

      assert reason =~ "already exists"
    end

    test "returns error when target already exists as directory", %{tmp_dir: tmp_dir} do
      txn = Transaction.new("pkg")
      source = Path.join(tmp_dir, "source")
      target = Path.join(tmp_dir, "existing_dir")

      File.write!(source, "source")
      File.mkdir_p!(target)

      {:error, reason} = Transaction.safe_symlink(txn, source, target)

      assert reason =~ "already exists"
    end
  end

  describe "rollback/1" do
    setup do
      tmp_dir = Path.join(System.tmp_dir!(), "opsm_rollback_#{:rand.uniform(1_000_000)}")
      File.mkdir_p!(tmp_dir)

      on_exit(fn -> File.rm_rf!(tmp_dir) end)

      {:ok, tmp_dir: tmp_dir}
    end

    test "removes files created during transaction", %{tmp_dir: tmp_dir} do
      file_path = Path.join(tmp_dir, "created_file.txt")
      File.write!(file_path, "content")

      txn =
        Transaction.new("pkg")
        |> Transaction.record_file(file_path)

      assert File.exists?(file_path)

      Transaction.rollback(txn)

      refute File.exists?(file_path)
    end

    test "removes symlinks created during transaction", %{tmp_dir: tmp_dir} do
      source = Path.join(tmp_dir, "source")
      link = Path.join(tmp_dir, "link")

      File.write!(source, "content")
      File.ln_s!(source, link)

      txn =
        Transaction.new("pkg")
        |> Transaction.record_symlink(link)

      assert File.exists?(link)

      Transaction.rollback(txn)

      refute File.exists?(link)
      # Source should still exist
      assert File.exists?(source)
    end

    test "removes directories created during transaction", %{tmp_dir: tmp_dir} do
      dir_path = Path.join(tmp_dir, "created_dir")
      File.mkdir_p!(dir_path)

      txn =
        Transaction.new("pkg")
        |> Transaction.record_directory(dir_path)

      assert File.dir?(dir_path)

      Transaction.rollback(txn)

      refute File.exists?(dir_path)
    end

    test "does not rollback completed transactions", %{tmp_dir: tmp_dir} do
      file_path = Path.join(tmp_dir, "keep_file.txt")
      File.write!(file_path, "content")

      txn =
        Transaction.new("pkg")
        |> Transaction.record_file(file_path)
        |> Transaction.complete()

      Transaction.rollback(txn)

      # File should still exist because transaction was completed
      assert File.exists?(file_path)
    end
  end
end
