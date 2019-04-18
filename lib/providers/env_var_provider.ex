defmodule EnvVar.Provider do
  @moduledoc """
  This provider loads a configuration from a map and uses that to set
  Application environment configuration with the values found in
  system environment variables. These variable names are constructed
  from the field names directly, following a convention.
  """
  use Mix.Releases.Config.Provider

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
        no_default: %{type: :string}
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

  #### Calling
  `init/1` expects to be passed a Keyword List of the form:
    `init(prefix: "prefix", env_map: map, enforce: false)`

  The `enforce` argument specifies whether values with no default
  are all required. This will prevent any fallbacks to settings
  in the config files for values that are configured in the EnvVar
  Provider.
  """
  def init(prefix: prefix, env_map: env_map, enforce: enforce) when is_atom(prefix) do
    process_config(env_map, prefix, enforce)
  end

  def init(prefix: prefix, env_map: env_map, enforce: enforce) do
    prefix = String.to_atom(prefix)
    process_config(env_map, prefix, enforce)
  end

  def show_vars(prefix: prefix, env_map: env_map) when is_atom(prefix) do
    for {app, app_config} <- env_map do
      for {key, key_config} <- app_config do
        case key_config do
          %{type: _} ->
            IO.puts(lookup_key_for([prefix, app, key]))

          _ ->
            for {list_key, _config} <- key_config do
              IO.puts(lookup_key_for([prefix, app, key, list_key]))
            end
        end
      end
    end
  end

  def show_vars(prefix: prefix, env_map: env_map) do
    show_vars(prefix: String.to_atom(prefix), env_map: env_map)
  end

  defp process_config(env_map, prefix, enforce) do
    for {app, app_config} <- env_map do
      for {key, key_config} <- app_config do
        case key_config do
          %{type: _} ->
            env_var_name = lookup_key_for([prefix, app, key])

            env_var_name
            |> get_env_value(key_config)
            |> validate(app, key, env_var_name, enforce)
            |> set_value(app, key)

          _ ->
            process_list_entry(prefix, app, key, enforce, key_config)
        end
      end
    end
  end

  defp process_list_entry(prefix, app, key, enforce, key_config) do
    for {list_key, config} <- key_config do
      env_var_name = lookup_key_for([prefix, app, key, list_key])

      env_var_name
      |> get_env_value(config)
      |> validate(app, key, env_var_name, enforce)
      |> set_list_value(app, key, list_key)
    end
  end

  defp get_env_value(key, config) do
    key
    |> System.get_env()
    |> set_default(config[:default], key)
    |> convert(config[:type])
  end

  # Make sure we have a value set of some kind, and then either
  # log an error, or abort if we're configured to do that.
  defp validate(value, _app, _key, env_var_name, enforce) do
    if (is_nil(value) || value == "") && enforce do
      raise RuntimeError, message: "Config enforcement on and missing value for #{env_var_name} so crashing"
    end

    value
  end

  defp set_value(value, _app, _key) when is_nil(value) do
  end

  defp set_value(value, app, key) do
    Application.put_env(app, key, value)
  end

  defp set_list_value(value, _app, _key, _list_key) when is_nil(value) do
  end

  defp set_list_value(value, app, key, list_key) do
    keylist = Application.get_env(app, key)
    newlist = Keyword.put(keylist, list_key, value)
    Application.put_env(app, key, newlist)
  end

  def convert({:default, default}, _) do
    default
  end

  def convert({:value, value}, type) do
    convert(value, type)
  end

  def convert(env_value, _) when is_nil(env_value) do
    nil
  end

  def convert(env_value, :float) do
    {val, _extra} = Float.parse(env_value)
    val
  end

  def convert(env_value, :integer) do
    {val, _extra} = Integer.parse(env_value)
    val
  end

  def convert(env_value, :string) do
    env_value
  end

  def convert(env_value, {:tuple, type}) do
    convert(env_value, {:tuple, type, ","})
  end

  def convert(env_value, {:tuple, type, separator}) do
    env_value
    |> String.split(separator)
    |> Enum.map(&convert(&1, type))
    |> List.to_tuple()
  end

  def convert(env_value, {:list, type}) do
    convert(env_value, {:list, type, ","})
  end

  def convert(env_value, {:list, type, separator}) do
    env_value
    |> String.split(separator)
    |> Enum.map(&convert(&1, type))
  end

  defp set_default(value, default, _env_var_name) when is_nil(value) do
    {:default, default}
  end

  defp set_default(value, default, _env_var_name) do
    if String.length(value) < 1 do
      {:default, default}
    else
      {:value, value}
    end
  end

  defp lookup_key_for(fields) do
    fields
    |> Enum.map(fn x ->
      # Handle module Atoms as keys
      x
      |> Atom.to_string()
      |> String.replace("Elixir.", "")
      |> String.replace(".", "_")
    end)
    |> Enum.map(&String.upcase/1)
    |> Enum.join("_")
    |> (fn x -> Regex.replace(~r/^_/, x, "") end).()
  end
end
