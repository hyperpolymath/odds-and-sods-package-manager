# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
defmodule Opsm.HarQueue do
  @moduledoc """
  Manages task queue for HAR (hybrid-automation-router) integration.

  This module handles:
  - Submitting tasks to the HAR queue directory
  - Waiting for agent results
  - Cleaning up completed tasks

  Task files are written to /tmp/opsm-har-ingest/ where HAR agents
  watch for new tasks and process them.
  """

  require Logger

  alias Opsm.Verified.Json

  @queue_dir "/tmp/opsm-har-ingest"
  # 1 second
  @default_poll_interval 1000
  # 5 minutes
  @cleanup_after 300_000

  @doc """
  Submit a task to the HAR queue.

  Writes a JSON file to the queue directory that HAR agents will pick up.

  ## Examples

      iex> task = %{task_id: "123", task_type: "package_fetch", ...}
      iex> HarQueue.submit(task)
      {:ok, "/tmp/opsm-har-ingest/123.json"}
  """
  @spec submit(map()) :: {:ok, String.t()} | {:error, term()}
  def submit(task) do
    ensure_queue_dir()

    task_id = task.task_id
    task_file = task_path(task_id)

    Logger.debug("Submitting HAR task to #{task_file}")

    # Use Verified.Json for safe encoding
    case Json.encode(task) do
      {:ok, json} ->
        case File.write(task_file, json) do
          :ok ->
            Logger.info("HAR task submitted: #{task_id}")
            {:ok, task_file}

          {:error, reason} ->
            Logger.error("Failed to write HAR task file: #{inspect(reason)}")
            {:error, "Failed to write task file: #{inspect(reason)}"}
        end

      {:error, reason} ->
        Logger.error("Failed to encode HAR task as JSON: #{inspect(reason)}")
        {:error, "Invalid task format: #{inspect(reason)}"}
    end
  end

  @doc """
  Wait for a HAR task result.

  Polls the queue directory for a result file, then reads and returns it.

  ## Options

  - `:timeout` - Maximum time to wait in milliseconds (default: 300_000 / 5 min)
  - `:poll_interval` - Time between polls in milliseconds (default: 1000)

  ## Examples

      iex> HarQueue.await_result("123", timeout: 60_000)
      {:ok, %{"status" => "success", ...}}

      iex> HarQueue.await_result("456", timeout: 5_000)
      {:error, :timeout}
  """
  @spec await_result(String.t(), keyword()) ::
          {:ok, map()} | {:error, :timeout | term()}
  def await_result(task_id, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 300_000)
    poll_interval = Keyword.get(opts, :poll_interval, @default_poll_interval)
    result_file = result_path(task_id)

    Logger.debug("Waiting for HAR result: #{result_file} (timeout: #{timeout}ms)")

    start_time = System.monotonic_time(:millisecond)
    end_time = start_time + timeout

    case poll_for_result(result_file, end_time, poll_interval) do
      {:ok, result} ->
        Logger.info("HAR task completed: #{task_id}")
        cleanup_task(task_id)
        {:ok, result}

      {:error, :timeout} ->
        Logger.warning("HAR task timed out: #{task_id} after #{timeout}ms")
        cleanup_task(task_id)
        {:error, :timeout}

      {:error, reason} = error ->
        Logger.error("HAR task failed: #{task_id} - #{inspect(reason)}")
        cleanup_task(task_id)
        error
    end
  end

  @doc """
  Cancel a pending HAR task.

  Removes the task file from the queue so agents won't process it.
  """
  @spec cancel(String.t()) :: :ok
  def cancel(task_id) do
    task_file = task_path(task_id)

    if File.exists?(task_file) do
      File.rm(task_file)
      Logger.info("HAR task cancelled: #{task_id}")
    end

    :ok
  end

  @doc """
  List all pending HAR tasks in the queue.
  """
  @spec list_pending() :: [String.t()]
  def list_pending do
    ensure_queue_dir()

    Path.wildcard(Path.join(@queue_dir, "*.json"))
    |> Enum.reject(&String.ends_with?(&1, ".result.json"))
    |> Enum.map(&Path.basename(&1, ".json"))
  end

  @doc """
  Clean up old task and result files.

  Removes files older than the specified age.
  """
  @spec cleanup_old(non_neg_integer()) :: {:ok, non_neg_integer()}
  def cleanup_old(max_age_ms \\ @cleanup_after) do
    ensure_queue_dir()

    cutoff_time = System.os_time(:millisecond) - max_age_ms

    files = Path.wildcard(Path.join(@queue_dir, "*"))

    removed =
      Enum.count(files, fn file ->
        stat = File.stat!(file)
        gregorian = stat.mtime |> NaiveDateTime.to_gregorian_seconds()
        file_time = elem(gregorian, 0) * 1000

        if file_time < cutoff_time do
          File.rm(file)
          true
        else
          false
        end
      end)

    Logger.debug("Cleaned up #{removed} old HAR queue files")
    {:ok, removed}
  end

  # Private functions

  defp ensure_queue_dir do
    unless File.dir?(@queue_dir) do
      File.mkdir_p!(@queue_dir)
      Logger.debug("Created HAR queue directory: #{@queue_dir}")
    end
  end

  defp task_path(task_id), do: Path.join(@queue_dir, "#{task_id}.json")
  defp result_path(task_id), do: Path.join(@queue_dir, "#{task_id}.result.json")

  defp poll_for_result(result_file, end_time, poll_interval) do
    current_time = System.monotonic_time(:millisecond)

    cond do
      current_time >= end_time ->
        {:error, :timeout}

      File.exists?(result_file) ->
        read_result(result_file)

      true ->
        Process.sleep(poll_interval)
        poll_for_result(result_file, end_time, poll_interval)
    end
  end

  defp read_result(result_file) do
    case File.read(result_file) do
      {:ok, content} ->
        # Use Verified.Json for safe decoding (prevents DoS via deeply nested JSON)
        case Json.decode(content) do
          {:ok, result} ->
            {:ok, result}

          {:error, reason} ->
            Logger.error("Invalid JSON in HAR result file: #{inspect(reason)}")
            {:error, "Invalid JSON in result: #{inspect(reason)}"}
        end

      {:error, reason} ->
        Logger.error("Failed to read HAR result file: #{inspect(reason)}")
        {:error, "Failed to read result: #{inspect(reason)}"}
    end
  end

  defp cleanup_task(task_id) do
    # Remove both task and result files
    task_file = task_path(task_id)
    result_file = result_path(task_id)

    File.rm(task_file)
    File.rm(result_file)

    Logger.debug("Cleaned up HAR task files for #{task_id}")
  end
end
