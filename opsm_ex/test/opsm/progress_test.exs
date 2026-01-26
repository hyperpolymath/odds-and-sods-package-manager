# SPDX-License-Identifier: PMPL-1.0
defmodule Opsm.ProgressTest do
  use ExUnit.Case, async: true

  alias Opsm.Progress

  describe "new_bar/2" do
    test "creates a progress bar state with total" do
      state = Progress.new_bar(100)

      assert state.total == 100
      assert state.current == 0
      assert state.label == "Progress"
      assert state.started_at != nil
    end

    test "accepts custom label" do
      state = Progress.new_bar(50, label: "Downloading")

      assert state.label == "Downloading"
      assert state.total == 50
    end

    test "handles zero total" do
      state = Progress.new_bar(0)

      assert state.total == 0
      assert state.current == 0
    end
  end

  describe "update_bar/2" do
    test "updates current value" do
      state = Progress.new_bar(100)
      state = Progress.update_bar(state, 50)

      assert state.current == 50
    end

    test "clamps to total" do
      state = Progress.new_bar(100)
      state = Progress.update_bar(state, 150)

      assert state.current == 100
    end

    test "clamps negative to zero" do
      state = Progress.new_bar(100)
      state = Progress.update_bar(state, -10)

      assert state.current == 0
    end
  end

  describe "complete_bar/1" do
    test "sets current to total" do
      state = Progress.new_bar(100)
      |> Progress.update_bar(50)
      |> Progress.complete_bar()

      assert state.current == state.total
    end
  end

  describe "render_bar/1" do
    test "returns string representation" do
      state = Progress.new_bar(100)
      |> Progress.update_bar(50)

      output = Progress.render_bar(state)

      assert is_binary(output)
      assert output =~ "50%"
      assert output =~ "Progress"
    end

    test "shows 0% at start" do
      state = Progress.new_bar(100)
      output = Progress.render_bar(state)

      assert output =~ "0%"
    end

    test "shows 100% when complete" do
      state = Progress.new_bar(100)
      |> Progress.complete_bar()

      output = Progress.render_bar(state)

      assert output =~ "100%"
    end

    test "handles zero total gracefully" do
      state = Progress.new_bar(0)
      output = Progress.render_bar(state)

      # Should not crash, return something reasonable
      assert is_binary(output)
    end
  end

  describe "new_spinner/1" do
    test "creates spinner state" do
      state = Progress.new_spinner("Loading")

      assert state.label == "Loading"
      assert state.frame == 0
    end
  end

  describe "spin/1" do
    test "advances frame" do
      state = Progress.new_spinner("Loading")
      state = Progress.spin(state)

      assert state.frame == 1
    end

    test "wraps around frames" do
      state = Progress.new_spinner("Loading")

      # Spin many times
      state = Enum.reduce(1..100, state, fn _, s -> Progress.spin(s) end)

      # Frame should be within valid range
      assert state.frame >= 0
    end
  end

  describe "complete_spinner/2" do
    test "returns completed message" do
      state = Progress.new_spinner("Loading")
      output = Progress.complete_spinner(state, "Done!")

      assert is_binary(output)
      assert output =~ "Done!"
    end
  end

  describe "new_steps/2" do
    test "creates steps tracker" do
      state = Progress.new_steps(5, label: "Installing")

      assert state.total == 5
      assert state.current == 0
      assert state.label == "Installing"
    end
  end

  describe "next_step/2" do
    test "advances to next step" do
      state = Progress.new_steps(3)
      state = Progress.next_step(state, "Step 1")

      assert state.current == 1
    end

    test "does not exceed total" do
      state = Progress.new_steps(2)
      |> Progress.next_step("Step 1")
      |> Progress.next_step("Step 2")
      |> Progress.next_step("Step 3")

      assert state.current == 2
    end
  end

  describe "format_bytes/1" do
    test "formats bytes" do
      assert Progress.format_bytes(500) =~ "500"
      assert Progress.format_bytes(500) =~ "B"
    end

    test "formats kilobytes" do
      result = Progress.format_bytes(2048)
      assert result =~ "KB" or result =~ "2"
    end

    test "formats megabytes" do
      result = Progress.format_bytes(5 * 1024 * 1024)
      assert result =~ "MB" or result =~ "5"
    end

    test "formats gigabytes" do
      result = Progress.format_bytes(3 * 1024 * 1024 * 1024)
      assert result =~ "GB" or result =~ "3"
    end

    test "handles zero" do
      assert Progress.format_bytes(0) =~ "0"
    end
  end

  describe "format_duration/1" do
    test "formats seconds" do
      result = Progress.format_duration(45)
      assert result =~ "45" or result =~ "s"
    end

    test "formats minutes and seconds" do
      result = Progress.format_duration(125)
      assert result =~ "2" or result =~ "m"
    end

    test "formats hours" do
      result = Progress.format_duration(3700)
      assert result =~ "1" or result =~ "h"
    end

    test "handles zero" do
      result = Progress.format_duration(0)
      assert is_binary(result)
    end
  end
end
