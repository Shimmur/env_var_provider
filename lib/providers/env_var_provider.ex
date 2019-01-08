defmodule EnvVar.Provider do
  use Mix.Releases.Config.Provider

  require Logger

  def init(prefix: prefix, env_map: env_map) do
    persist(env_map, prefix)
  end

  defp persist(env_map, prefix) do
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
    |> Enum.map(&Atom.to_string/1)
    |> Enum.map(&String.upcase/1)
    |> Enum.join("_")
  end
end
