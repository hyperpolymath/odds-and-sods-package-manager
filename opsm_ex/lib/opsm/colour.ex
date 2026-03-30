# SPDX-License-Identifier: PMPL-1.0-or-later
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>

defmodule Opsm.Colour do
  @moduledoc """
  ANSI colour helpers for CLI output.

  Respects NO_COLOR environment variable (https://no-color.org/).
  """

  @doc "Green text — success indicators"
  def green(text), do: wrap(text, "\e[32m")

  @doc "Red text — errors"
  def red(text), do: wrap(text, "\e[31m")

  @doc "Yellow text — warnings"
  def yellow(text), do: wrap(text, "\e[33m")

  @doc "Cyan text — package names, emphasis"
  def cyan(text), do: wrap(text, "\e[36m")

  @doc "Bold text — headers, section titles"
  def bold(text), do: wrap(text, "\e[1m")

  @doc "Dim text — secondary information"
  def dim(text), do: wrap(text, "\e[2m")

  @doc "Bold cyan — command names"
  def command(text), do: wrap(text, "\e[1;36m")

  @doc "Green checkmark"
  def ok(text), do: "#{green("✓")} #{text}"

  @doc "Yellow warning"
  def warn(text), do: "#{yellow("⚠")} #{text}"

  @doc "Red error"
  def err(text), do: "#{red("✗")} #{text}"

  defp wrap(text, code) do
    if colour_enabled?() do
      "#{code}#{text}\e[0m"
    else
      text
    end
  end

  defp colour_enabled? do
    is_nil(System.get_env("NO_COLOR")) and IO.ANSI.enabled?()
  end
end
