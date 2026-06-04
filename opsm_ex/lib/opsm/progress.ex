# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
defmodule Opsm.Progress do
  @moduledoc """
  Progress indicators for long-running operations.

  Provides:
  - Download progress bars
  - Spinner for indeterminate operations
  - Step counters for multi-step tasks
  """

  @bar_width 30
  @spinner_frames ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]

  @doc """
  Create a new progress bar state.
  """
  def new_bar(total, opts \\ []) do
    %{
      total: total,
      current: 0,
      label: Keyword.get(opts, :label, "Progress"),
      started_at: System.monotonic_time(:millisecond),
      last_update: 0
    }
  end

  @doc """
  Update progress bar with new current value.
  Returns updated state. Clamps value between 0 and total.
  """
  def update_bar(state, current) do
    clamped = current |> max(0) |> min(state.total)
    state = %{state | current: clamped}
    now = System.monotonic_time(:millisecond)

    # Throttle updates to max 10/second
    if now - state.last_update > 100 do
      render_bar(state)
      %{state | last_update: now}
    else
      state
    end
  end

  @doc """
  Complete the progress bar (fill to 100%).
  """
  def complete_bar(state) do
    state = %{state | current: state.total}
    render_bar(state)
    IO.write("\n")
    state
  end

  @doc """
  Render progress bar to terminal. Returns the formatted string.
  """
  def render_bar(state) do
    percent = if state.total > 0, do: state.current / state.total, else: 0
    percent_int = round(percent * 100)
    filled = round(percent * @bar_width)
    empty = @bar_width - filled

    bar = String.duplicate("█", filled) <> String.duplicate("░", empty)

    # Calculate speed and ETA
    elapsed_ms = System.monotonic_time(:millisecond) - state.started_at
    speed = if elapsed_ms > 0, do: state.current / (elapsed_ms / 1000), else: 0
    eta = if speed > 0, do: (state.total - state.current) / speed, else: 0

    size_str = format_size(state.current)
    total_str = format_size(state.total)
    speed_str = format_speed(speed)
    eta_str = format_eta(eta)

    output = "#{state.label}: [#{bar}] #{percent_int}% #{size_str}/#{total_str} #{speed_str} #{eta_str}"
    IO.write("\r  #{output}  ")
    output
  end

  @doc """
  Create a spinner state.
  """
  def new_spinner(label \\ "Working") do
    %{
      label: label,
      frame: 0,
      started_at: System.monotonic_time(:millisecond)
    }
  end

  @doc """
  Update and render spinner.
  """
  def spin(state) do
    frame_char = Enum.at(@spinner_frames, rem(state.frame, length(@spinner_frames)))
    IO.write("\r  #{frame_char} #{state.label}...")
    %{state | frame: state.frame + 1}
  end

  @doc """
  Complete spinner with success message. Returns the formatted message.
  """
  def complete_spinner(_state, message \\ "Done") do
    output = "✓ #{message}"
    IO.write("\r  #{output}                    \n")
    output
  end

  @doc """
  Complete spinner with failure message.
  """
  def fail_spinner(state, message \\ "Failed") do
    IO.write("\r  ✗ #{message}                    \n")
    state
  end

  @doc """
  Create a step counter.
  """
  def new_steps(total, opts \\ []) do
    %{
      total: total,
      current: 0,
      label: Keyword.get(opts, :label, "Step")
    }
  end

  @doc """
  Advance to next step. Clamps at total.
  """
  def next_step(state, description \\ nil) do
    new_current = min(state.current + 1, state.total)
    state = %{state | current: new_current}
    if description do
      IO.puts("  [#{state.current}/#{state.total}] #{description}")
    else
      IO.puts("  [#{state.current}/#{state.total}] #{state.label} #{state.current}")
    end
    state
  end

  @doc """
  Print a simple progress message.
  """
  def status(message) do
    IO.puts("  #{message}")
  end

  @doc """
  Print a success message.
  """
  def success(message) do
    IO.puts("  ✓ #{message}")
  end

  @doc """
  Print a warning message.
  """
  def warning(message) do
    IO.puts("  ⚠ #{message}")
  end

  @doc """
  Print an error message.
  """
  def error(message) do
    IO.puts(:stderr, "  ✗ #{message}")
  end

  # ============================================
  # Public Formatting Helpers
  # ============================================

  @doc """
  Format bytes as human-readable string (B, KB, MB, GB).
  """
  def format_bytes(bytes) when bytes < 1024, do: "#{bytes} B"
  def format_bytes(bytes) when bytes < 1024 * 1024 do
    "#{Float.round(bytes / 1024, 1)} KB"
  end
  def format_bytes(bytes) when bytes < 1024 * 1024 * 1024 do
    "#{Float.round(bytes / (1024 * 1024), 2)} MB"
  end
  def format_bytes(bytes) do
    "#{Float.round(bytes / (1024 * 1024 * 1024), 2)} GB"
  end

  @doc """
  Format duration in seconds as human-readable string.
  """
  def format_duration(seconds) when seconds < 60 do
    "#{round(seconds)}s"
  end
  def format_duration(seconds) when seconds < 3600 do
    mins = div(round(seconds), 60)
    secs = rem(round(seconds), 60)
    "#{mins}m #{secs}s"
  end
  def format_duration(seconds) do
    hours = div(round(seconds), 3600)
    mins = rem(div(round(seconds), 60), 60)
    "#{hours}h #{mins}m"
  end

  # ============================================
  # Private Formatting Helpers
  # ============================================

  defp format_size(bytes), do: format_bytes(bytes) |> String.replace(" ", "")

  defp format_speed(bytes_per_sec) when bytes_per_sec < 1024 do
    "#{round(bytes_per_sec)}B/s"
  end
  defp format_speed(bytes_per_sec) when bytes_per_sec < 1024 * 1024 do
    "#{Float.round(bytes_per_sec / 1024, 1)}KB/s"
  end
  defp format_speed(bytes_per_sec) do
    "#{Float.round(bytes_per_sec / (1024 * 1024), 2)}MB/s"
  end

  defp format_eta(seconds) when seconds < 1, do: ""
  defp format_eta(seconds) when seconds < 60 do
    "ETA: #{round(seconds)}s"
  end
  defp format_eta(seconds) when seconds < 3600 do
    mins = div(round(seconds), 60)
    secs = rem(round(seconds), 60)
    "ETA: #{mins}m#{secs}s"
  end
  defp format_eta(seconds) do
    hours = div(round(seconds), 3600)
    mins = rem(div(round(seconds), 60), 60)
    "ETA: #{hours}h#{mins}m"
  end
end
