EnvVarProvider
==============

Allows _dynamic_ runtime configuration of Elixir releases from system
environment variables, including _type_ _conversion_ to non-string types. Great
for running Elixir applications on modern infrastructure like Docker,
Kubernetes, Mesos.

This requires Distillery 2.0.

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
  set version: current_version(:my_app)
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
    },
    simpler: %{
      service_name: %{type: :string}
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

The above config would source env vars like this:
 * `MY_RELEASE_ERLCASS_CLUSTER_OPTIONS_CREDENTIALS`
 * `MY_RELEASE_ERLCASS_CLUSTER_OPTIONS_CONTACT_POINTS`
 * `MY_RELEASE_ERLCASS_CLUSTER_OPTIONS_PORT`
 * `MY_RELEASE_SIMPLER_SERVICE_NAME`

Note that the `*_ERLCASS_*` keys are assumed to be values in a Keyword list
in this format. Simpler configuration doesn't require the extra layer and
can be one layer flatter like in `:simpler` above.

**You may need to call the provider multiple times for different applications
and you can just specify it repeatedly.**

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
      server_count: %{type: :integer},
      name: %{type: :string, default: "grendel"},
      settings: %{type: {:list, :string}, default: "swarthy,hairy"},
      keys: %{type: {:tuple, :float}, default: "1.1,2.3,3.4"}
    }
  }
```

Type Conversion
---------------

Type conversion allows you to source settings from the environment that
are not strings. It even supports a limited set of complex types like
`List`s and `Tuple`s.

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

Default Values
--------------
You have two choices when dealing with default values:

 1. Leave them off and it will default to what is in the Application
    config already.
 2. Set them in the release configuration. This can provide better
    visibility in one place as to what the fallback will be if the
	variable is not provided.

If you supply default values, they will overwrite any existing values in the
config for this environment.
