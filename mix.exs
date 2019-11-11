defmodule EnvVarProvider.MixProject do
  use Mix.Project

  def project do
    [
      app: :env_var_provider,
      version: "0.4.2",
      elixir: "~> 1.9",
      start_permanent: Mix.env() == :prod,
      description: description(),
      package: package(),
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
      {:distillery, "~> 2.1.0"},
      {:ex_doc, ">= 0.0.0", only: :dev}
    ]
  end

  defp description do
    """
    Config Provider for Distillery that supports environment variables as a
    configuration source, with configurable type conversion built in.
    """
  end

  defp package do
    [
      files: ["lib", "mix.exs", "README*", "LICENSE*"],
      maintainers: ["Karl Matthias"],
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/Shimmur/env_var_provider"}
    ]
  end
end
