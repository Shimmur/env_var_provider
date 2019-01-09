defmodule EnvVar.Provider do
  @moduledoc """
  This provider loads a configuration from a map and uses that to set
  Application environment configuration with the values found in 
  system environment variables. These variable names are constructed
  from the field names directly, following a convention.
  """
  use Mix.Releases.Config.Provider

  require Logger

  @doc """
  init is called by Distillery when running the provider during boostrap.

  `prefix` is a string that will me capitalized and prepended to all
  environment variables we look at. e.g. `prefix: "beowulf"` translates
  into environment variables starting with `BEOWULF_`. This is used
  to namespace our variables to prevent conflicts.

  `env_map` follows the following format:
  ```
    env_map = %{
      heorot: %{
        location: %{type: :string, default: "land of the Geats"},
      },
      mycluster: %{
        server_count: %{type: :integer, default: "123"},
        name: %{type: :string, default: "grendel"},
        settings: %{type: {:list, :string}, default: "swarthy,hairy"},
        keys: %{type: {:tuple, :float}, default: "1.1,2.3,3.4"}
      }
    }
  ```

  Type conversion uses the defined types to handle the destination
  conversion.

  Supported types:
   * `:string`
   * `:integer`
   * `:float`
   * `{:tuple, <type>}` - Complex type, where the second field is
     one of the simple types above. Currently items in the tuple
     must all be of the same type. A 3rd argument can be passed
     to specify the field separator in the env var. Defaults to
     comma.
   * `{:list, <type>}` - Complex type, following the same rules as
     Tuples above. 

  Default values will overwrite any existing values in the config
  for this environment.
  """
  def init(prefix: prefix, env_map: env_map) do
    process_config(env_map, prefix)
  end

  # process_config will save the environment variables to the Application
  # config, according to the provided configuration map.
  defp process_config(env_map, prefix) do
    env_map
    |> Enum.each(fn {app, top_config} ->
      top_config |> Enum.each(&process_lower_config(&1, prefix, app))
    end)
  end

  defp process_lower_config({key, config}, prefix, app) do
    if Map.has_key?(config, :type) do
      {key, result} = process_bottom_config({key, config}, prefix, app)
      save_result(app, key, result)
    else
      config
      |> Enum.map(&process_bottom_config(&1, prefix, app))
      |> Enum.each(fn result ->
        save_result(app, key, result)
      end)
    end
  end

  defp save_result(app, key, result) do
    existing = Application.get_env(app, key)

    if is_list(existing) and Keyword.keyword?(existing) do
      {k, v} = result

      new_value =
        existing
        |> Keyword.put(k, v)

      Application.put_env(app, key, new_value)
    else
      Application.put_env(app, key, result)
    end
  end

  defp process_bottom_config({env_key, config}, prefix, app) do
    env_value =
      lookup_key_for(env_key, prefix, app)
      |> System.get_env()
      |> set_default(Map.get(config, :default, ""))

    result = convert(config[:type], env_value)
    {env_key, result}
  end

  defp convert(:float, env_value) do
    {val, _extra} = Float.parse(env_value)
    val
  end

  defp convert(:integer, env_value) do
    {val, _extra} = Integer.parse(env_value)
    val
  end

  defp convert(:string, env_value) do
    env_value
  end

  defp convert({:tuple, type}, env_value) do
    convert({:tuple, type, ","}, env_value)
  end

  defp convert({:tuple, type, separator}, env_value) do
    env_value
    |> String.split(separator)
    |> Enum.map(fn val ->
      convert(type, val)
    end)
    |> List.to_tuple()
  end

  defp convert({:list, type}, env_value) do
    convert({:list, type, ","}, env_value)
  end

  defp convert({:list, type, separator}, env_value) do
    env_value
    |> String.split(separator)
    |> Enum.map(fn val ->
      convert(type, val)
    end)
  end

  defp set_default(value, default) when is_nil(value) do
    default
  end

  defp set_default(value, default) do
    if String.length(value) < 1 do
      default
    else
      value
    end
  end

  defp lookup_key_for(key, prefix, app) do
    [String.to_atom(prefix), app, key]
    |> Enum.map(fn x ->
      x
      |> Atom.to_string()
      |> String.replace("Elixir.", "")
      |> String.replace(".", "_")
    end)
    |> Enum.map(&String.upcase/1)
    |> Enum.join("_")
  end
end
