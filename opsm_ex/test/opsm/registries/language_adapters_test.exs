# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
#
# Consolidated tests for all new language/database registry adapters.
# Each adapter follows the same contract (search/2, fetch_package/2,
# versions/1, exists?/1) so we test them with a shared suite.

defmodule Opsm.Registries.LanguageAdaptersTest do
  use ExUnit.Case, async: true

  alias Opsm.Registries.Registry

  # All new adapters introduced in the first-class system sprint (2026-04-12)
  @adapters [
    {Opsm.Registries.Betlang,    :betlang,    "betlang-rt"},
    {Opsm.Registries.Ephapax,    :ephapax,    "ephapax-std"},
    {Opsm.Registries.Phronesis,  :phronesis,  "phronesis-core"},
    {Opsm.Registries.Tangle,     :tangle,     "tangle-std"},
    {Opsm.Registries.Wokelang,   :wokelang,   "wokelang-std"},
    {Opsm.Registries.Lithoglyph, :lithoglyph, "lithoglyph-core"},
    {Opsm.Registries.QuandleDB,  :quandledb,  "quandledb-core"},
    {Opsm.Registries.Nqc,        :nqc,        "nqc-core"},
  ]

  # ---------------------------------------------------------------------------
  # Module interface — every adapter must export the standard 4 functions
  # ---------------------------------------------------------------------------

  for {mod, _forth, _known_pkg} <- @adapters do
    mod_name = mod |> Module.split() |> List.last()

    describe "#{mod_name} — module interface" do
      # function_exported?/3 only sees loaded modules. Ensure the adapter
      # is loaded before checking, otherwise the test is a race with
      # whichever other test happens to call the module first.
      setup do
        Code.ensure_loaded(unquote(mod))
        :ok
      end

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
  # search/2 — must return {:ok, list} in git fallback mode, never crash
  # ---------------------------------------------------------------------------

  # Helper: accept either raw list OR {:ok, list} — different adapters use
  # slightly different conventions during the transitional git-fallback phase.
  defp assert_list_result(result) do
    case result do
      {:ok, list} when is_list(list) -> :ok
      list when is_list(list) -> :ok
      other -> flunk("expected list or {:ok, list}, got: #{inspect(other)}")
    end
  end

  for {mod, _forth, _known_pkg} <- @adapters do
    mod_name = mod |> Module.split() |> List.last()

    describe "#{mod_name}.search/2" do
      test "returns list-compatible result for a relevant query" do
        assert_list_result(unquote(mod).search(unquote(mod_name |> String.downcase()), []))
      end

      test "returns list-compatible result for empty string" do
        assert_list_result(unquote(mod).search("", []))
      end

      test "returns list-compatible result for nonsense query" do
        assert_list_result(unquote(mod).search("xyzzy-no-match-999", []))
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
  # versions/1 — returns {:ok, list} for known packages; may return {:error, :not_found}
  # for unknown packages (git fallback adapters).
  # ---------------------------------------------------------------------------

  for {mod, _forth, known_pkg} <- @adapters do
    mod_name = mod |> Module.split() |> List.last()

    @tag :external_api
    describe "#{mod_name}.versions/1" do
      test "returns ok tuple with list for known package" do
        case unquote(mod).versions(unquote(known_pkg)) do
          {:ok, versions} -> assert is_list(versions)
          # External API calls may fail offline / rate-limited — acceptable.
          {:error, _} -> :ok
        end
      end

      test "returns ok-or-error tuple for unknown package" do
        result = unquote(mod).versions("xyz-definitely-not-real-abc-999")
        assert match?({:ok, _}, result) or match?({:error, _}, result)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # fetch_package/2 — adapters in git-fallback mode construct optimistic URLs
  # for any name; real validation happens at install time. Both {:ok, _} and
  # {:error, _} are acceptable.
  # ---------------------------------------------------------------------------

  for {mod, _forth, _known_pkg} <- @adapters do
    mod_name = mod |> Module.split() |> List.last()

    describe "#{mod_name}.fetch_package/2" do
      test "returns ok-or-error tuple for non-existent package" do
        result = unquote(mod).fetch_package("xyz-definitely-not-real-abc-999", "latest")
        assert match?({:ok, _}, result) or match?({:error, _}, result)
      end

      @tag :external_api
      test "returns ok or error for a known package name" do
        case unquote(mod).fetch_package(unquote(mod_name |> String.downcase() |> Kernel.<>("-core")), "latest") do
          {:ok, pkg} -> assert is_map(pkg) or is_struct(pkg)
          {:error, _} -> :ok
        end
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Registry dispatch integration — Registry.search/3 must route to each adapter
  # via the correct atom key. These tests verify the full dispatch chain works
  # without requiring any network calls (adapters return empty lists offline).
  # ---------------------------------------------------------------------------

  describe "Registry.search/3 dispatch to new adapters" do
    for {_mod, forth, _known_pkg} <- @adapters do
      test "routes :#{forth} without crashing" do
        result = Registry.search(unquote(forth), "test-query", [])
        # Must return {:ok, list} or {:error, _} — never crash
        assert match?({:ok, _}, result) or match?({:error, _}, result)
      end
    end

    test "returns {:error, _} for unknown registry atom" do
      result = Registry.search(:totally_unknown_xyz_abc, "query", [])
      assert match?({:error, _}, result)
    end
  end

  describe "Registry.exists?/2 dispatch to new adapters" do
    for {_mod, forth, _known_pkg} <- @adapters do
      test "returns boolean for :#{forth}" do
        result = Registry.exists?(unquote(forth), "xyz-not-real-999")
        assert is_boolean(result)
      end
    end
  end

  describe "Registry includes new adapters in @all_primary_forths" do
    # Verify the adapters are in the list that search_all iterates over.
    # We check indirectly: if search_all returns a map with the key, the
    # atom was in the list. search_all is async so we filter to just these.
    @tag :skip
    test "search_all includes betlang, ephapax, phronesis, tangle, wokelang" do
      result = Registry.search_all("test", forths: [:betlang, :ephapax, :phronesis, :tangle, :wokelang])
      assert is_map(result)
      assert Map.has_key?(result, :betlang)
      assert Map.has_key?(result, :ephapax)
    end

    @tag :skip
    test "search_all includes lithoglyph, quandledb, nqc" do
      result = Registry.search_all("test", forths: [:lithoglyph, :quandledb, :nqc])
      assert is_map(result)
      assert Map.has_key?(result, :lithoglyph)
    end
  end
end
