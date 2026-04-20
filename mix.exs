defmodule Atree.MixProject do
  use Mix.Project

  def project do
    [
      app:             :atree,
      version:         "0.1.0",
      elixir:          "~> 1.14",
      start_permanent: Mix.env() == :prod,
      elixirc_paths:   ["lib"],
      compilers:       [:elixir_make] ++ Mix.compilers(),
      deps:            deps(),
      docs:            docs(),
      package:         package(),
      make_env:        %{"MIX_ENV" => to_string(Mix.env())}
    ]
  end

  def application do
    [
      mod:                {Atree.App, []},
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:elixir_make, "~> 0.8",  runtime: false},
      {:ex_doc,      "~> 0.30", only: :dev,     runtime: false},
      {:exalign,     "~> 0.1",  only: :dev}
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