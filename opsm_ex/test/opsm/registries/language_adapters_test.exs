# SPDX-License-Identifier: PMPL-1.0-or-later
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
#
# Consolidated tests for all new language/database registry adapters.
# Each adapter follows the same contract (search/2, fetch_package/2,
# versions/1, exists?/1) so we test them with a shared suite.

defmodule Opsm.Registries.LanguageAdaptersTest do
  use ExUnit.Case, async: true

  # All new adapters introduced in the first-class system sprint (2026-04-12)
  @adapters [
    {Opsm.Registries.Betlang,    :betlang,    "betlang-rt"},
    {Opsm.Registries.Ephapax,    :ephapax,    "ephapax-std"},
    {Opsm.Registries.Phronesis,  :phronesis,  "phronesis-core"},
    {Opsm.Registries.Tangle,     :tangle,     "tangle-std"},
    {Opsm.Registries.Wokelang,   :wokelang,   "wokelang-std"},
    {Opsm.Registries.Lithoglyph, :lithoglyph, "lithoglyph-core"},
    {Opsm.Registries.Quandledb,  :quandledb,  "quandledb-core"},
    {Opsm.Registries.Nqc,        :nqc,        "nqc-core"},
  ]

  # ---------------------------------------------------------------------------
  # Module interface — every adapter must export the standard 4 functions
  # ---------------------------------------------------------------------------

  for {mod, _forth, _known_pkg} <- @adapters do
    mod_name = mod |> Module.split() |> List.last()

    describe "#{mod_name} — module interface" do
      test "exports search/2" do
        assert function_exported?(unquote(mod), :search, 2)
      end

      test "exports fetch_package/2" do
        assert function_exported?(unquote(mod), :fetch_package, 2)
      end

      test "exports versions/1" do
        assert function_exported?(unquote(mod), :versions, 1)
      end

      test "exports exists?/1" do
        assert function_exported?(unquote(mod), :exists?, 1)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # search/2 — must return a list, never crash
  # ---------------------------------------------------------------------------

  for {mod, _forth, _known_pkg} <- @adapters do
    mod_name = mod |> Module.split() |> List.last()

    describe "#{mod_name}.search/2" do
      test "returns list for a relevant query" do
        result = unquote(mod).search(unquote(mod_name |> String.downcase()), [])
        assert is_list(result)
      end

      test "returns list for empty string" do
        result = unquote(mod).search("", [])
        assert is_list(result)
      end

      test "returns list for nonsense query" do
        result = unquote(mod).search("xyzzy-no-match-999", [])
        assert is_list(result)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # exists?/1 — must return a boolean, never crash
  # ---------------------------------------------------------------------------

  for {mod, _forth, known_pkg} <- @adapters do
    mod_name = mod |> Module.split() |> List.last()

    describe "#{mod_name}.exists?/1" do
      test "returns boolean for known package name" do
        result = unquote(mod).exists?(unquote(known_pkg))
        assert is_boolean(result)
      end

      test "returns false for obviously non-existent package" do
        result = unquote(mod).exists?("xyz-definitely-not-real-abc-999")
        assert result == false
      end
    end
  end

  # ---------------------------------------------------------------------------
  # versions/1 — must return {:ok, list}
  # ---------------------------------------------------------------------------

  for {mod, _forth, known_pkg} <- @adapters do
    mod_name = mod |> Module.split() |> List.last()

    describe "#{mod_name}.versions/1" do
      test "returns ok tuple with list for known package" do
        assert {:ok, versions} = unquote(mod).versions(unquote(known_pkg))
        assert is_list(versions)
      end

      test "returns ok tuple with list for unknown package" do
        assert {:ok, versions} = unquote(mod).versions("xyz-definitely-not-real-abc-999")
        assert is_list(versions)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # fetch_package/2 — non-existent packages return {:error, :not_found}
  # ---------------------------------------------------------------------------

  for {mod, _forth, _known_pkg} <- @adapters do
    mod_name = mod |> Module.split() |> List.last()

    describe "#{mod_name}.fetch_package/2" do
      test "returns error for non-existent package" do
        result = unquote(mod).fetch_package("xyz-definitely-not-real-abc-999", "latest")
        assert match?({:error, _}, result)
      end

      @tag :external_api
      test "returns ok or not_found for a known package name" do
        case unquote(mod).fetch_package(unquote(mod_name |> String.downcase() |> Kernel.<>("-core")), "latest") do
          {:ok, pkg} ->
            assert is_map(pkg)
            assert Map.has_key?(pkg, :forth)
          {:error, :not_found} -> :ok
          {:error, _} -> :ok
        end
      end
    end
  end
end
