defmodule Mix.Tasks.ShowVars do
  @shortdoc "Show the names of the environment variables to use"

  @moduledoc """
  This task will look at the config you have defined
  and return the list of environment variables you will need
  to supply to the release at runtime.
  """

  use Mix.Task

  def run([prefix]) do
    Mix.Task.run("compile")

    Mix.Project.config()
    |> Keyword.fetch!(:releases)
    |> fetch_only_release!()
    |> Keyword.fetch!(:config_providers)
    |> find_env_var_provider_config!()
    |> Keyword.put(:prefix, prefix)
    |> EnvVar.Provider.show_vars()
  end

  def run(_args) do
    Mix.raise("You must specify a single prefix, or '' if you want none")
  end

  defp fetch_only_release!([{_name, config}]), do: config
  defp fetch_only_release!(_other), do: Mix.raise("There are multiple releases defined")

  defp find_env_var_provider_config!(providers) do
    case List.keyfind(providers, EnvVar.Provider, 0) do
      {EnvVar.Provider, env_var_config} ->
        env_var_config

      nil ->
        Mix.raise("There is no EnvVar.Provider config provider in your list of config providers")
    end
  end
end
