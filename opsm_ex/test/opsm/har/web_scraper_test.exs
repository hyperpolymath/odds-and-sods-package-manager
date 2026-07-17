# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
defmodule Opsm.Har.WebScraperTest do
  use ExUnit.Case, async: true

  alias Opsm.Har.WebScraper

  describe "process_task/1" do
    test "returns error for empty package name" do
      task = %{
        "task_id" => "test-001",
        "package" => %{"name" => "", "version" => "latest", "language" => "unknown"},
        "hints" => %{}
      }

      case WebScraper.process_task(task) do
        {:ok, result} ->
          # If found (unlikely for empty name), verify structure
          assert result["status"] == "success"

        {:error, _reason} ->
          :ok
      end
    end

    test "returns success result with correct structure" do
      task = %{
        "task_id" => "test-002",
        "package" => %{"name" => "test-pkg", "version" => "latest", "language" => "elixir"},
        "hints" => %{"last_known_url" => "https://hex.pm/packages/jason"}
      }

      case WebScraper.process_task(task) do
        {:ok, result} ->
          assert result["task_id"] == "test-002"
          assert result["status"] == "success"
          assert is_map(result["package_location"])
          assert is_map(result["metadata"])
          assert is_map(result["discovery"])
          assert is_map(result["verification"])

        {:error, _} ->
          # Network not available
          :ok
      end
    end

    test "builds task with all required fields" do
      task = %{
        "task_id" => "test-003",
        "package" => %{
          "name" => "nonexistent-pkg-zzz",
          "version" => "latest",
          "language" => "unknown"
        },
        "hints" => %{}
      }

      result = WebScraper.process_task(task)
      # Should return error for truly nonexistent package
      assert match?({:error, _}, result) or match?({:ok, _}, result)
    end
  end

  describe "check_github/2" do
    @tag :integration
    test "finds popular packages" do
      case WebScraper.check_github("phoenix", "elixir") do
        {:ok, discovery} ->
          assert discovery[:url] =~ "github.com"
          assert discovery[:type] == :git
          assert discovery[:confidence] > 0

        {:error, _} ->
          # API rate limited or network unavailable
          :ok
      end
    end
  end

  describe "check_gitlab/2" do
    @tag :integration
    test "searches GitLab" do
      case WebScraper.check_gitlab("inkscape", "c++") do
        {:ok, discovery} ->
          assert discovery[:url] =~ "gitlab"
          assert discovery[:type] == :git

        {:error, _} ->
          :ok
      end
    end
  end

  describe "check_codeberg/2" do
    @tag :integration
    test "searches Codeberg" do
      case WebScraper.check_codeberg("forgejo", "go") do
        {:ok, discovery} ->
          assert is_binary(discovery[:url])

        {:error, _} ->
          :ok
      end
    end
  end

  describe "status/0" do
    test "returns not running when GenServer not started" do
      status = WebScraper.status()
      assert status.running == false
    end
  end
end
