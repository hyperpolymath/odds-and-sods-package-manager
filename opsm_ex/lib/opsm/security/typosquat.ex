# SPDX-License-Identifier: MPL-2.0
defmodule Opsm.Security.Typosquat do
  @moduledoc """
  Typosquat detection for package names.

  Compares a candidate package name against a curated list of popular packages
  per ecosystem, flagging names that are suspiciously close (edit distance 1 or 2,
  or homoglyph substitution). Complements OSV advisory checks.

  Detection methods:
  - Edit distance 1 (single character insert/delete/substitute/transpose)
  - Edit distance 2 (for longer names ≥ 7 chars)
  - Homoglyph substitution: l↔1, o↔0, rn↔m, plus dash/underscore/dot stripping
  """

  # ---------------------------------------------------------------------------
  # Popular package allowlists per ecosystem
  # (typosquatting is most dangerous in the most-depended-on packages)
  # ---------------------------------------------------------------------------

  @popular_npm ~w[
    lodash express react axios moment underscore async request
    bluebird uuid rxjs jquery typescript tslib chalk commander
    mocha jest eslint prettier webpack babel-core cross-env
    dotenv next vue angular svelte core-js semver glob minimatch
    mime path-to-regexp qs debug yargs
  ]

  @popular_cargo ~w[
    serde tokio rand rayon clap anyhow reqwest hyper async-std
    futures log env_logger thiserror tracing lazy_static once_cell
    syn quote proc-macro2 bytes axum warp actix-web tower regex
    itertools chrono url serde_json
  ]

  @popular_pypi ~w[
    requests numpy pandas matplotlib flask django fastapi pydantic
    pytest click setuptools wheel boto3 sqlalchemy celery redis
    pillow scipy scikit-learn tensorflow torch transformers cryptography
    paramiko urllib3 certifi charset-normalizer idna six attrs
    packaging pyparsing python-dateutil
  ]

  @popular_hex ~w[
    phoenix ecto plug jason cowboy credo dialyxir ex_doc
    mix_test_watch guardian cors_plug comeonin bcrypt_elixir
    httpoison finch req tesla absinthe oban broadway
    timex nimble_parsec decimal gettext
  ]

  @popular_gem ~w[
    rails rack rake bundler puma sinatra minitest rspec
    nokogiri activesupport activerecord faraday httparty
    devise pundit sidekiq redis pg mysql2
  ]

  @popular_go ~w[
    github.com/gin-gonic/gin github.com/gorilla/mux
    github.com/spf13/cobra github.com/spf13/viper
    github.com/sirupsen/logrus github.com/stretchr/testify
    golang.org/x/crypto golang.org/x/net
    github.com/go-sql-driver/mysql github.com/lib/pq
  ]

  @popular %{
    npm:     @popular_npm,
    cargo:   @popular_cargo,
    pypi:    @popular_pypi,
    hex:     @popular_hex,
    gem:     @popular_gem,
    go:      @popular_go
  }

  defmodule Match do
    @moduledoc "A suspected typosquat match against a known-popular package."
    defstruct [:package, :similarity, :flags]

    @type similarity :: :edit_distance_1 | :edit_distance_2 | :homoglyph
    @type t :: %__MODULE__{
      package:    String.t(),
      similarity: similarity(),
      flags:      [atom()]
    }
  end

  @doc """
  Check whether `name` looks like a typosquat of a popular package in `forth`.

  Returns `{:clean}` if no suspicion, or `{:suspicious, [Match.t()]}`.
  """
  @spec check(String.t(), atom()) :: {:clean} | {:suspicious, [Match.t()]}
  def check(name, forth) when is_binary(name) and is_atom(forth) do
    known = Map.get(@popular, forth, [])
    name_lower = String.downcase(name)

    matches =
      known
      |> Enum.reject(fn k -> k == name_lower end)
      |> Enum.flat_map(&suspect_match(name_lower, &1))

    case matches do
      []   -> {:clean}
      hits -> {:suspicious, hits}
    end
  end

  # ---------------------------------------------------------------------------
  # Private
  # ---------------------------------------------------------------------------

  defp suspect_match(name, known) do
    cond do
      homoglyph_match?(name, known) ->
        [%Match{package: known, similarity: :homoglyph, flags: [:homoglyph_substitution]}]

      String.length(name) > 3 and edit_distance(name, known) == 1 ->
        [%Match{package: known, similarity: :edit_distance_1, flags: []}]

      String.length(name) >= 7 and edit_distance(name, known) == 2 ->
        [%Match{package: known, similarity: :edit_distance_2, flags: []}]

      true ->
        []
    end
  end

  defp homoglyph_match?(a, b), do: normalise(a) == normalise(b)

  defp normalise(s) do
    s
    |> String.downcase()
    |> String.replace("1", "l")
    |> String.replace("0", "o")
    |> String.replace("rn", "m")
    |> String.replace(~r/[-_.]/, "")
  end

  # Two-row Levenshtein DP — O(m·n) time, O(n) space.
  # Uses chunk_every/2 to walk prev_row and b_chars in sync,
  # avoiding O(n) Enum.at calls per cell.
  @spec edit_distance(String.t(), String.t()) :: non_neg_integer()
  def edit_distance(a, b) when is_binary(a) and is_binary(b) do
    a_chars = String.graphemes(a)
    b_chars = String.graphemes(b)

    m = length(a_chars)
    n = length(b_chars)

    # Short-circuit: if the lengths differ by more than 3 it can't be
    # an accidental typo — no point computing the full distance.
    if abs(m - n) > 3 do
      99
    else
      # Initial row: edit distance from empty string to each prefix of b.
      row0 = Enum.to_list(0..n)

      a_chars
      |> Enum.with_index(1)
      |> Enum.reduce(row0, fn {a_char, i}, prev_row ->
        # Pairs [prev[j-1], prev[j]] give diagonal and above for each column j.
        diag_above_pairs = Enum.chunk_every(prev_row, 2, 1, :discard)

        {new_rev, _} =
          Enum.zip(b_chars, diag_above_pairs)
          |> Enum.reduce({[], i}, fn {b_char, [diag, above]}, {acc_rev, left} ->
            cost = if a_char == b_char, do: 0, else: 1
            v = Enum.min([left + 1, above + 1, diag + cost])
            {[v | acc_rev], v}
          end)

        [i | Enum.reverse(new_rev)]
      end)
      |> List.last()
    end
  end
end
