defmodule Atree.MixProject do
  use Mix.Project

  def project do
    [
      app:             :exatree,
      version:         "0.1.1",
      elixir:          "~> 1.14",
      start_permanent: Mix.env() == :prod,
      elixirc_paths:   elixirc_paths(Mix.env()),
      deps:            deps(),
      docs:            docs(),
      package:         package(),
      test_coverage:   [
        output:         ".cover",
        ignore_modules: [Atree],
        # allow_failure: true,
        summary:        [threshold: 90]
      ]
    ]
  end

  defp elixirc_paths(:prod), do: ["lib"]
  defp elixirc_paths(_), do: ["lib", "examples"]

  def application do
    [
      mod:                {Atree.App, []},
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:ex_doc,  "~> 0.30", only: :dev, runtime: false},
      {:exalign, "~> 0.1",  only: :dev, runtime: false}
    ]
  end

  defp docs do
    [
      main:       "readme",
      extras:     ["README.md", "LICENSE"],
      source_url: "https://github.com/user/atree-nif"
    ]
  end

  defp package do
    [
      description: "Efficient A-Tree pattern matching via NIF",
      licenses:    ["MIT"],
      links:       %{"GitHub" => "https://github.com/user/atree-nif"}
    ]
  end
end
