# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
# Stress test: fetch real packages from all 10 registries
# Run: mix run test/stress_test.exs

alias Opsm.Registries.Registry

# Test packages per registry — well-known, stable packages
test_packages = [
  # npm (10 packages)
  {:npm, "express", "4.18.2"},
  {:npm, "lodash", "latest"},
  {:npm, "chalk", "5.3.0"},
  {:npm, "axios", "latest"},
  {:npm, "uuid", "latest"},
  {:npm, "debug", "latest"},
  {:npm, "commander", "latest"},
  {:npm, "minimist", "latest"},
  {:npm, "glob", "latest"},
  {:npm, "semver", "latest"},

  # Hex/Elixir (10 packages)
  {:hex, "jason", "latest"},
  {:hex, "plug", "latest"},
  {:hex, "phoenix", "latest"},
  {:hex, "ecto", "latest"},
  {:hex, "telemetry", "latest"},
  {:hex, "nimble_parsec", "latest"},
  {:hex, "ex_doc", "latest"},
  {:hex, "earmark_parser", "latest"},
  {:hex, "decimal", "latest"},
  {:hex, "mime", "latest"},

  # Cargo/Crates (10 packages)
  {:cargo, "serde", "latest"},
  {:cargo, "tokio", "latest"},
  {:cargo, "rand", "latest"},
  {:cargo, "clap", "latest"},
  {:cargo, "regex", "latest"},
  {:cargo, "log", "latest"},
  {:cargo, "anyhow", "latest"},
  {:cargo, "thiserror", "latest"},
  {:cargo, "chrono", "latest"},
  {:cargo, "reqwest", "latest"},

  # PyPI (10 packages)
  {:pypi, "requests", "latest"},
  {:pypi, "flask", "latest"},
  {:pypi, "numpy", "latest"},
  {:pypi, "pytest", "latest"},
  {:pypi, "click", "latest"},
  {:pypi, "pyyaml", "latest"},
  {:pypi, "six", "latest"},
  {:pypi, "packaging", "latest"},
  {:pypi, "idna", "latest"},
  {:pypi, "certifi", "latest"},

  # RubyGems (10 packages)
  {:gem, "rails", "latest"},
  {:gem, "rake", "latest"},
  {:gem, "bundler", "latest"},
  {:gem, "rspec", "latest"},
  {:gem, "nokogiri", "latest"},
  {:gem, "sinatra", "latest"},
  {:gem, "puma", "latest"},
  {:gem, "redis", "latest"},
  {:gem, "json", "latest"},
  {:gem, "minitest", "latest"},

  # Go Modules (10 packages)
  {:go, "github.com/gin-gonic/gin", "latest"},
  {:go, "github.com/fatih/color", "latest"},
  {:go, "github.com/spf13/cobra", "latest"},
  {:go, "github.com/spf13/viper", "latest"},
  {:go, "github.com/stretchr/testify", "latest"},
  {:go, "github.com/sirupsen/logrus", "latest"},
  {:go, "github.com/gorilla/mux", "latest"},
  {:go, "golang.org/x/text", "latest"},
  {:go, "golang.org/x/net", "latest"},
  {:go, "golang.org/x/sync", "latest"},

  # Pub.dev/Dart (10 packages)
  {:pub, "http", "latest"},
  {:pub, "path", "latest"},
  {:pub, "json_annotation", "latest"},
  {:pub, "provider", "latest"},
  {:pub, "intl", "latest"},
  {:pub, "collection", "latest"},
  {:pub, "meta", "latest"},
  {:pub, "args", "latest"},
  {:pub, "crypto", "latest"},
  {:pub, "async", "latest"},

  # Hackage/Haskell (10 packages)
  {:hackage, "aeson", "latest"},
  {:hackage, "text", "latest"},
  {:hackage, "bytestring", "latest"},
  {:hackage, "containers", "latest"},
  {:hackage, "mtl", "latest"},
  {:hackage, "transformers", "latest"},
  {:hackage, "parsec", "latest"},
  {:hackage, "vector", "latest"},
  {:hackage, "lens", "latest"},
  {:hackage, "attoparsec", "latest"},

  # NuGet/.NET (10 packages)
  {:nuget, "Newtonsoft.Json", "latest"},
  {:nuget, "Serilog", "latest"},
  {:nuget, "AutoMapper", "latest"},
  {:nuget, "Dapper", "latest"},
  {:nuget, "FluentValidation", "latest"},
  {:nuget, "Moq", "latest"},
  {:nuget, "xunit", "latest"},
  {:nuget, "Polly", "latest"},
  {:nuget, "MediatR", "latest"},
  {:nuget, "Swashbuckle.AspNetCore", "latest"},

  # Maven/Java (10 packages)
  {:maven, "com.google.guava:guava", "latest"},
  {:maven, "org.slf4j:slf4j-api", "latest"},
  {:maven, "junit:junit", "latest"},
  {:maven, "com.fasterxml.jackson.core:jackson-databind", "latest"},
  {:maven, "org.apache.commons:commons-lang3", "latest"},
  {:maven, "commons-io:commons-io", "latest"},
  {:maven, "org.projectlombok:lombok", "latest"},
  {:maven, "com.google.code.gson:gson", "latest"},
  {:maven, "org.mockito:mockito-core", "latest"},
  {:maven, "ch.qos.logback:logback-classic", "latest"},
]

IO.puts("=" |> String.duplicate(70))
IO.puts("OPSM Stress Test: #{length(test_packages)} packages across 10 registries")
IO.puts("=" |> String.duplicate(70))
IO.puts("")

# Group by registry
grouped = Enum.group_by(test_packages, fn {forth, _, _} -> forth end)

results = %{ok: 0, error: 0, total: length(test_packages)}
errors = []

{results, errors} =
  Enum.reduce(grouped, {results, errors}, fn {forth, packages}, {res_acc, err_acc} ->
    IO.puts("--- @#{forth} (#{length(packages)} packages) ---")

    {res, errs} =
      Enum.reduce(packages, {res_acc, err_acc}, fn {_forth, name, version}, {r, e} ->
        start = System.monotonic_time(:millisecond)

        case Registry.fetch(forth, name, version) do
          {:ok, pkg} ->
            elapsed = System.monotonic_time(:millisecond) - start
            checksum_status = if pkg.checksum, do: "✓ #{pkg.checksum_algo}", else: "✗ none"
            dep_count = map_size(pkg.manifest.dependencies || %{})
            IO.puts("  ✓ #{name}@#{pkg.version} (#{elapsed}ms, deps: #{dep_count}, checksum: #{checksum_status})")
            {%{r | ok: r.ok + 1}, e}

          {:error, reason} ->
            elapsed = System.monotonic_time(:millisecond) - start
            IO.puts("  ✗ #{name} FAILED (#{elapsed}ms): #{inspect(reason)}")
            {%{r | error: r.error + 1}, [{forth, name, reason} | e]}
        end
      end)

    IO.puts("")
    {res, errs}
  end)

IO.puts("=" |> String.duplicate(70))
IO.puts("RESULTS: #{results.ok}/#{results.total} succeeded, #{results.error} failed")
IO.puts("=" |> String.duplicate(70))

if errors != [] do
  IO.puts("")
  IO.puts("FAILURES:")
  for {forth, name, reason} <- Enum.reverse(errors) do
    IO.puts("  @#{forth}/#{name}: #{inspect(reason)}")
  end
end

# Exit with appropriate code
if results.error > 0 do
  IO.puts("\n⚠ #{results.error} package(s) failed to resolve")
else
  IO.puts("\n✓ All #{results.total} packages resolved successfully!")
end
