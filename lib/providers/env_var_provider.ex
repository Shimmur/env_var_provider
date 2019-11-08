defmodule EnvVar.Provider do
  @moduledoc """
  This provider loads a configuration from a map and uses that to set
  Application environment configuration with the values found in
  system environment variables. These variable names are constructed
  from the field names directly, following a convention.
  """

  @behaviour Config.Provider

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
  @impl true
  def init(opts) do
    env_map =
      case Keyword.fetch!(opts, :env_map) do
        map when is_map(map) -> map
        other -> raise ArgumentError, ":env_map should be a map, got: #{inspect(other)}"
      end

    prefix =
      case Keyword.fetch!(opts, :prefix) do
        atom when is_atom(atom) -> atom
        binary when is_binary(binary) -> String.to_atom(binary)
        other -> raise ArgumentError, ":prefix should be atom or string, got: #{inspect(other)}"
      end

    enforce? =
      case Keyword.get(opts, :enforce, true) do
        bool when is_boolean(bool) -> bool
        other -> raise ArgumentError, ":enforce should be a boolean, got: #{inspect(other)}"
      end

    _state = %{env_map: env_map, prefix: prefix, enforce?: enforce?}
  end

  @impl true
  def load(config, %{env_map: env_map, prefix: prefix, enforce?: enforce?}) do
    config_from_env = read_config_from_env(env_map, prefix, enforce?)
    Config.Reader.merge(config, config_from_env)
  end

  @doc false
  def show_vars(opts) do
    prefix = opts |> Keyword.fetch!(:prefix) |> String.to_atom()
    env_map = Keyword.fetch!(opts, :env_map)

    for {app, app_config} <- env_map do
      for {key, key_config} <- app_config do
        show_vars(prefix, [app, key], key_config)
      end
    end
  end

  defp show_vars(prefix, path, %{type: _}) do
    IO.puts(lookup_key_for([prefix | path]))
  end

  defp show_vars(prefix, path, config) do
    for {key, nested_config} <- config do
      show_vars(prefix, path ++ [key], nested_config)
    end
  end

  defp read_config_from_env(env_map, prefix, enforce) do
    for {app, app_config} <- env_map do
      parsed_app_config =
        for {key, key_config} <- app_config do
          parsed_config = process_and_merge_config(prefix, enforce, app, key, key_config)
          {key, parsed_config}
        end

      {app, parsed_app_config}
    end
  end

  defp process_and_merge_config(prefix, enforce, app, key, key_config) do
    case key_config do
      %{type: _} ->
        parse_config(prefix, enforce, [app, key], key_config)

      _other ->
        parse_config(prefix, enforce, [app, key], key_config)
    end
  end

  defp parse_config(prefix, enforce, path, %{type: _} = schema) do
    env_var_name = lookup_key_for([prefix | path])

    env_var_name
    |> get_env_value(schema)
    |> validate(env_var_name, enforce)
  end

  defp parse_config(prefix, enforce, path, nested_schema) do
    for {key, schema} <- nested_schema do
      {key, parse_config(prefix, enforce, path ++ [key], schema)}
    end
  end

  defp get_env_value(key, config) do
    value = System.get_env(key) || config[:default]
    convert(value, config[:type])
  end

  # Make sure we have a value set of some kind, and then either
  # log an error, or abort if we're configured to do that.
  defp validate(value, env_var_name, enforce) do
    if (is_nil(value) or value == "") && enforce do
      raise RuntimeError, message: "Config enforcement on and missing value for #{env_var_name} so crashing"
    end

    value
  end

  def convert(env_value, _) when is_nil(env_value) do
    nil
  end

  def convert(env_value, :float) do
    case Float.parse(env_value) do
      {value, ""} -> value
      _other -> raise ArgumentError, "expected float, got: #{inspect(env_value)}"
    end
  end

  def convert(env_value, :integer) do
    case Integer.parse(env_value) do
      {value, ""} -> value
      _other -> raise ArgumentError, "expected integer, got: #{inspect(env_value)}"
    end
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
