defmodule JsonldEx.MixProject do
  use Mix.Project

  def project do
    [
      app: :jsonld_ex,
      version: "0.1.0",
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:rustler, "~> 0.34.0", runtime: false},
      {:jason, "~> 1.2"}
    ]
  end
end
