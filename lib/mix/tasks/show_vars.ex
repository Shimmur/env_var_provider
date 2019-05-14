defmodule Mix.Tasks.ShowVars do
  @shortdoc "Show the names of the environment variables to use"

  @moduledoc """
  This taks will look at the EnvVar.Config you have defined
  and return the list of environment variables you will need
  to supply to the release at runtime.
  """

  use Mix.Task

  def run([prefix]) do
    Mix.Task.run("compile")

    # Dynamic module name avoids compilation warnings.
    config_module = EnvVar.Config

    if Code.ensure_compiled?(config_module) do
      config = config_module.config()
      EnvVar.Provider.show_vars(prefix: prefix, env_map: config)
    else
      Mix.raise("""
      You must include a module called EnvVar.Config and supply
      a config/0 function that returns the release config.
      """)
    end
  end

  def run(_args) do
    Mix.raise("You must specify a single prefix, or '' if you want none")
  end
end
