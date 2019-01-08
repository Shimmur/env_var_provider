EnvVarProvider
==============

Installation
------------

Add `env_var_provider` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:env_var_provider, "~> 0.1.0", github: "Shimmur/env_var_provider"}
  ]
end
```


Configuration
-------------

You need to add this to your `rel/config.exs` like so:

```elixir
release :my_release do
  set version: current_version(:hermes)
  set applications: [
    :runtime_tools
  ]

  # Environment variables to process as overrides using the
  # EnvVar.Provider
  env_config = %{
    erlcass: %{
      cluster_options: %{
        credentials: %{type: {:tuple, :string}, default: "user,pass"},
        contact_points: %{type: :string, default: "127.0.0.1"},
        port: %{type: :integer, default: "9042"}
      }
    }
  }

  set(
    # Use the EnvVar provider to handle config overrides
    config_providers: [
      {EnvVar.Provider, [prefix: "my_release", env_map: env_config]}
    ]
  )
end
```

You may need to call the provider multiple times for different applications
and you can just specify it repeatedly. The `prefix` will prefix all env
vars. So "prefix" will before "PREFIX_", etc.

Defaults must all be specified as strings and will have the same type
conversion applied that the env var would.
