# SPDX-License-Identifier: PMPL-1.0
defmodule Opsm.MixProject do
  use Mix.Project

  def project do
    [
      app: :opsm,
      version: "0.1.0",
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      escript: escript(),
      aliases: aliases()
    ]
  end

  def application do
    [
      mod: {Opsm.Application, []},
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:req, "~> 0.5"},
      {:toml, "~> 0.7"},
      {:optimus, "~> 0.5"},
      {:jason, "~> 1.4"},
      {:stream_data, "~> 0.6", only: :test},
      {:plug, "~> 1.15"},
      {:plug_cowboy, "~> 2.7"}
    ]
  end

  defp escript do
    [
      main_module: Opsm.CLI,
      name: :opsm
    ]
  end

  defp aliases do
    [
      build_cli: ["deps.get", "escript.build"]
    ]
  end
end
