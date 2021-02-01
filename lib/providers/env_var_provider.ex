defmodule EnvVar.Provider do
  @moduledoc """
  A `Config.Provider` that reads a *configuration schema* from a map and
  reads configuration from environment variables.

  Variable names are constructed from the field names directly,
  following a convention.

  ## Usage

  Define a function that returns a map representing the configuration. For
  example, you can have a module just for that:

      defmodule MyApp.EnvVarConfig do
        def schema do
          %{
            my_app: %{
              port: %{type: :integer}
            }
          }
        end
      end

  Now you can add `EnvVar.Provider` as a config provider in your release configuration:

      def project do
        [
          # ...,
          releases: [
            my_release: [
              config_providers: [
                {EnvVar.Provider,
                 env_map: MyApp.EnvVarConfig.schema(),
                 prefix: "",
                 enforce: true}
              ]
            ]
          ]
        ]

  ## Options

    * `:enforce` - (boolean) if `true`, raise an error if any environment variables are not
      present when reading the configuration. Required.

    * `:prefix` - (string or atom) prepended to the name of system environment variables.
      For example, if you pass `prefix: "BEOWULF_"` and you want to configure `:port` inside
      `:my_app`, the environment variable name will be `BEOWULF_MY_APP_PORT`. Required.

    * `:env_map` - (map or `{module, function, args}`) the configuration schema. Can be a
      map of configuration or a `{module, function, args}` tuple that returns a map of
      configuration when invoked (as `module.function(args...)`).

  ## Configuration schema

  The configuration schema is a map with applications as the top-level keys and maps
  of configuration as their values. The schema for each configuration option is a map
  with at least the `:type` key.

      %{
        my_app: %{
          port: %{type: :integer}
        }
      }

  The supported schema properties are:

    * `:type` - see below

    * `:default` - the default value if no environment variable is found.
      This value will be parsed just like the environment variable would,
      so it should always be a string.

  The supported types are:

    * simple types - `:string`, `:integer`, `:float`, or `:boolean`

    * `{:tuple, TYPE, SEPARATOR}` - complex type where the second field
    is one of the simple types above. `SEPARATOR` is used as the separator.

    * `{:tuple, TYPE}` - same as `{:tuple, TYPE, ","}`.

    * `{:list, TYPE, SEPARATOR}` and `{:list, TYPE}` - complex type that
      behaves like `{:tuple, ...}` but parsing to a list.

  A note on `boolean` types. The following are supported syntax:

    * "true"
    * "1" -> true
    * "false"
    * "0" -> false

  ## Variable name convention

  `EnvVar.Provider` will look for system environment variables by upcasing configuration names
  and separating with underscores. For example, if you configure the `:port` key of the `:my_app`
  application, it will look for the `MY_APP_PORT` environment variable.
  """

  @behaviour Config.Provider

  @impl true
  def init(opts) do
    env_map =
      case Keyword.fetch!(opts, :env_map) do
        map when is_map(map) -> map
        {mod, fun, args} -> apply(mod, fun, args)
        other -> raise ArgumentError, ":env_map should be a map or {mod, fun, args}, got: #{inspect(other)}"
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

    env_map =
      case Keyword.fetch!(opts, :env_map) do
        map when is_map(map) -> map
        {mod, fun, args} -> apply(mod, fun, args)
      end

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

  defp parse_config(prefix, enforce, path, %{type: type_value} = schema)
       when not is_map(type_value) do
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

  def convert(env_value, :boolean) do
    case env_value do
      "1" -> true
      "0" -> false
      "true" -> true
      "false" -> false
      _other -> raise ArgumentError, "expected boolean ('0', '1', 'true', 'false'), got: #{inspect(env_value)}"
    end
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
