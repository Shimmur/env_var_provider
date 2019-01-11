defmodule Mix.Tasks.ShowVars do
  @shortdoc "Show the names of the environment variables to use"

  @moduledoc """
  This taks will look at the EnvVar.Config you have defined
  and return the list of environment variables you will need
  to supply to the release at runtime.
  """

  use Mix.Task

  def run(args) when length(args) < 1 do
    IO.puts "Error: You must specify a prefix, or '' if you want none"
  end

  def run(args) do
    [prefix] = args
    config = EnvVar.Config.config
    EnvVar.Provider.show_vars(prefix: prefix, env_map: config)
  end
end
