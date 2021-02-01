defmodule EnvVar.ProviderTest do
  use ExUnit.Case
  doctest EnvVar.Provider

  setup do
    Application.put_env(:mycluster, :cluster_options,
      ssl: [
        verify_flags: 0
      ],
      credentials: {"user", "password"},
      contact_points: "127.0.0.1",
      port: 9042,
      latency_aware_routing: true,
      token_aware_routing: true,
      number_threads_io: 4,
      queue_size_io: 128_000,
      max_connections_host: 5,
      tcp_nodelay: true,
      tcp_keepalive: {true, 1800},
      default_consistency_level: 6
    )

    complex_config = %{
      mycluster: %{
        cluster_options: %{
          credentials: %{type: {:tuple, :string}, default: "user,pass"},
          contact_points: %{type: :string, default: "127.0.0.1"},
          port: %{type: :integer, default: "9042"},
          list_key: %{type: {:list, :integer}, default: "1,2,3"}
        }
      }
    }

    simple_config = %{
      the_system: %{
        service_name: %{type: :string, default: "envoygw"},
        feature_flag_enabled: %{type: :boolean, default: "false"}
      },
      mycluster: %{
        server_count: %{type: :integer, default: "123"},
        name: %{type: :string, default: "grendel"},
        settings: %{type: {:list, :string}, default: "swarthy,hairy"},
        keys: %{type: {:tuple, :float}, default: "1.1,2.3,3.4"}
      }
    }

    elixir_module_config = %{
      app: %{
        :"Elixir.EnvVar.Provider" => %{type: :string, default: "result"}
      }
    }

    deep_merged_config = %{
      mycluster: %{
        sys_logger: %{
          metadata: %{
            environment: %{type: :string},
            deeper: %{
              port: %{type: :integer}
            }
          }
        }
      }
    }

    # This is for the case where type is part of the env name
    overlapping_property_and_name_config = %{
      mycluster: %{
        logger: %{
          type: %{type: :string}
        }
      }
    }

    on_exit(fn ->
      System.delete_env("BEOWULF_MYCLUSTER_CLUSTER_OPTIONS_CREDENTIALS")
      System.delete_env("BEOWULF_MYCLUSTER_CLUSTER_OPTIONS_PORT")
      System.delete_env("BEOWULF_MYCLUSTER_CLUSTER_OPTIONS_LIST_KEY")
      System.delete_env("BEOWULF_MYCLUSTER_SERVER_COUNT")
      System.delete_env("BEOWULF_MYCLUSTER_NAME")
      System.delete_env("BEOWULF_MYCLUSTER_SETTINGS")
      System.delete_env("BEOWULF_MYCLUSTER_KEYS")
      System.delete_env("BEOWULF_MYCLUSTER_LOGGER_TYPE")
      System.delete_env("BEOWULF_APP_ENVVAR_PROVIDER")
      System.delete_env("BEOWULF_THE_SYSTEM_FEATURE_FLAG_ENABLED")
      :ok
    end)

    state = [
      complex: complex_config,
      simple: simple_config,
      elixir_mod: elixir_module_config,
      deep_merged: deep_merged_config,
      overlapping_property_and_name_config: overlapping_property_and_name_config
    ]

    {:ok, state}
  end

  describe "when the value is a Keyword list" do
    test "it correctly defaults values for numbers, strings, lists, tuples", state do
      config = init_and_load([], prefix: "beowulf", env_map: state[:complex], enforce: false)

      conf = config[:mycluster][:cluster_options]
      assert Keyword.get(conf, :port) == 9042
      assert Keyword.get(conf, :credentials) == {"user", "pass"}
      assert Keyword.get(conf, :contact_points) == "127.0.0.1"
      assert Keyword.get(conf, :list_key) == [1, 2, 3]
    end

    test "it pulls in the right env var values", state do
      System.put_env("BEOWULF_MYCLUSTER_CLUSTER_OPTIONS_CREDENTIALS", "myuser,mypass")
      System.put_env("BEOWULF_MYCLUSTER_CLUSTER_OPTIONS_PORT", "11121")
      System.put_env("BEOWULF_MYCLUSTER_CLUSTER_OPTIONS_LIST_KEY", "6,7,8")

      config = init_and_load([], prefix: "beowulf", env_map: state[:complex], enforce: false)
      conf = config[:mycluster][:cluster_options]

      assert Keyword.get(conf, :port) == 11121
      assert Keyword.get(conf, :credentials) == {"myuser", "mypass"}
      assert Keyword.get(conf, :list_key) == [6, 7, 8]
    end

    test "it reads deeply merged config", state do
      System.put_env("BEOWULF_MYCLUSTER_SYS_LOGGER_METADATA_ENVIRONMENT", "dev")
      System.put_env("BEOWULF_MYCLUSTER_SYS_LOGGER_METADATA_DEEPER_PORT", "9090")

      config = init_and_load([], prefix: "beowulf", env_map: state[:deep_merged], enforce: false)
      config = config[:mycluster][:sys_logger]

      assert config[:metadata][:environment] == "dev"
      assert config[:metadata][:deeper][:port] == 9090
    after
      System.delete_env("BEOWULF_MYCLUSTER_SYS_LOGGER_METADATA_ENVIRONMENT")
      System.delete_env("BEOWULF_MYCLUSTER_SYS_LOGGER_METADATA_DEEPER_PORT")
    end

    test "it performs deep merging", state do
      System.put_env("BEOWULF_MYCLUSTER_SYS_LOGGER_METADATA_ENVIRONMENT", "prod")
      System.put_env("BEOWULF_MYCLUSTER_SYS_LOGGER_METADATA_DEEPER_PORT", "9090")

      starting_config = [
        mycluster: [
          sys_logger: [metadata: [environment: "dev", name: "foo", deeper: [address: "localhost"]]]
        ]
      ]

      config = init_and_load(starting_config, prefix: "beowulf", env_map: state[:deep_merged], enforce: false)

      sys_logger_config = config[:mycluster][:sys_logger]

      assert sys_logger_config[:metadata][:environment] == "prod"
      assert sys_logger_config[:metadata][:name] == "foo"
      assert sys_logger_config[:metadata][:deeper][:address] == "localhost"
      assert sys_logger_config[:metadata][:deeper][:port] == 9090
    after
      System.delete_env("BEOWULF_MYCLUSTER_SYS_LOGGER_METADATA_ENVIRONMENT")
      System.delete_env("BEOWULF_MYCLUSTER_SYS_LOGGER_METADATA_DEEPER_PORT")
    end

    test "it doesn't overwrite values with nil when deep merging", state do
      System.delete_env("BEOWULF_MYCLUSTER_SYS_LOGGER_METADATA_ENVIRONMENT")

      starting_config = [metadata: [environment: "dev"]]
      Application.put_env(:mycluster, :sys_logger, starting_config)

      EnvVar.Provider.init(prefix: "beowulf", env_map: state[:deep_merged], enforce: false)

      config = Application.get_env(:mycluster, :sys_logger)

      assert config[:metadata][:environment] == "dev"
    after
      System.delete_env("BEOWULF_MYCLUSTER_SYS_LOGGER_METADATA_ENVIRONMENT")
    end
  end

  describe "option validation in init/1" do
    test "validates :prefix" do
      assert_raise ArgumentError, ~r/:prefix should be/, fn ->
        EnvVar.Provider.init(prefix: 44, env_map: %{})
      end

      assert_raise KeyError, ~r/key :prefix not found/, fn ->
        EnvVar.Provider.init(env_map: %{})
      end
    end

    test "validates :env_map" do
      assert_raise ArgumentError, ~r/:env_map should be/, fn ->
        EnvVar.Provider.init(prefix: "beowulf", env_map: :not_a_map)
      end

      assert_raise KeyError, ~r/key :env_map not found/, fn ->
        EnvVar.Provider.init(prefix: "beowulf")
      end
    end

    test "validates :enforce" do
      assert_raise ArgumentError, ~r/:enforce should be/, fn ->
        EnvVar.Provider.init(prefix: "beowulf", env_map: %{}, enforce: "not a boolean")
      end
    end
  end

  describe "when converting typed values" do
    test "integers", state do
      System.put_env("BEOWULF_MYCLUSTER_SERVER_COUNT", "44")

      config = init_and_load([], prefix: "beowulf", env_map: state[:simple], enforce: false)

      assert config[:mycluster][:server_count] == 44

      System.put_env("BEOWULF_MYCLUSTER_SERVER_COUNT", "not an integer")

      assert_raise ArgumentError, ~r/expected integer/, fn ->
        init_and_load([], prefix: "beowulf", env_map: state[:simple], enforce: false)
      end
    after
      System.delete_env("BEOWULF_MYCLUSTER_SERVER_COUNT")
    end

    test "floats", state do
      System.put_env("BEOWULF_MYCLUSTER_KEYS", "3.14,6.28")
      config = init_and_load([], prefix: "beowulf", env_map: state[:simple], enforce: false)

      assert config[:mycluster][:keys] == {3.14, 6.28}

      System.put_env("BEOWULF_MYCLUSTER_KEYS", "3.14,notafloat")

      assert_raise ArgumentError, ~r/expected float/, fn ->
        init_and_load([], prefix: "beowulf", env_map: state[:simple], enforce: false)
      end
    after
      System.delete_env("BEOWULF_MYCLUSTER_KEYS")
    end

    test "booleans", state do
      for {text, expected} <- [{"false", false}, {"true", true}, {"0", false}, {"1", true}] do
        System.put_env("BEOWULF_THE_SYSTEM_FEATURE_FLAG_ENABLED", text)
        config = init_and_load([], prefix: "beowulf", env_map: state[:simple], enforce: false)
        assert config[:the_system][:feature_flag_enabled] == expected
      end

      System.put_env("BEOWULF_THE_SYSTEM_FEATURE_FLAG_ENABLED", "not a boolean")

      assert_raise ArgumentError, ~r/expected boolean/, fn ->
        init_and_load([], prefix: "beowulf", env_map: state[:simple], enforce: false)
      end
    end
  end

  describe "when dealing with simple values" do
    test "it handles empty prefix", state do
      System.put_env("MYCLUSTER_SERVER_COUNT", "67")
      config = init_and_load([], prefix: "", env_map: state[:simple], enforce: false)

      assert config[:mycluster][:server_count] == 67
    end

    test "it correctly defaults values for numbers, strings, lists, tuples", state do
      config = init_and_load([], prefix: "beowulf", env_map: state[:simple], enforce: false)

      assert config[:mycluster][:server_count] == 123
      assert config[:mycluster][:name] == "grendel"
      assert config[:mycluster][:settings] == ["swarthy", "hairy"]
      assert config[:mycluster][:keys] == {1.1, 2.3, 3.4}
    end

    test "it pulls in the right env var values", state do
      System.put_env("BEOWULF_MYCLUSTER_SERVER_COUNT", "67")
      System.put_env("BEOWULF_MYCLUSTER_NAME", "hrothgar")
      System.put_env("BEOWULF_MYCLUSTER_SETTINGS", "good,tall")
      System.put_env("BEOWULF_MYCLUSTER_KEYS", "3.2,5.6,7.8")

      config = init_and_load([], prefix: "beowulf", env_map: state[:simple], enforce: false)

      assert config[:mycluster][:name] == "hrothgar"
      assert config[:mycluster][:settings] == ["good", "tall"]
      assert config[:mycluster][:keys] == {3.2, 5.6, 7.8}
    end

    test "creates new values with defaults that didn't already exist", state do
      config = init_and_load([], prefix: "beowulf", env_map: state[:simple], enforce: false)

      assert "envoygw" == config[:the_system][:service_name]
    end
  end

  describe "when dealing with Elixir module atom keys" do
    test "it handles Elixir modules as keys cleanly", state do
      System.put_env("BEOWULF_APP_ENVVAR_PROVIDER", "different")

      config = init_and_load([], prefix: "beowulf", env_map: state[:elixir_mod], enforce: false)

      assert config[:app][EnvVar.Provider] == "different"
    end
  end

  describe "when there is no default value" do
    test "it defaults to what is in the config already", state do
      Application.put_env(:app, EnvVar.Provider, "original")
      map = state[:elixir_mod]
      map = update_in(map, [:app, EnvVar.Provider], &Map.delete(&1, :default))

      EnvVar.Provider.init(prefix: "beowulf", env_map: map, enforce: false)

      assert Application.get_env(:app, EnvVar.Provider) == "original"
    end
  end

  describe "handling conditions that only occur in a release" do
    test "convert can handle nil" do
      EnvVar.Provider.convert(nil, :integer)
    end
  end

  describe "when handling enforcement" do
    test "requires everything when enforce is true and there are no defaults" do
      env_map = %{
        the_system: %{
          service_name: %{type: :string}
        }
      }

      assert_raise(RuntimeError, fn ->
        init_and_load([], prefix: "beowulf", env_map: env_map, enforce: true)
      end)
    end

    test "requires everything when enforce is true and there are no defaults for list entries" do
      env_map = %{
        the_system: %{
          service_name: %{
            something: %{type: :string}
          }
        }
      }

      assert_raise(RuntimeError, fn ->
        init_and_load([], prefix: "beowulf", env_map: env_map, enforce: true)
      end)
    end

    test "does not raise when defaults are present and keys are missing" do
      env_map = %{
        the_system: %{
          service_name: %{type: :string, default: "beowulf"}
        }
      }

      # Should not raise
      init_and_load([], prefix: "beowulf", env_map: env_map, enforce: true)
    end
  end

  describe "using {mod, fun, args} as the env_map" do
    test "mod.fun(args...) is called to get the env map" do
      System.put_env("BEOWULF_THE_SYSTEM_PORT", "5049")

      config =
        init_and_load([], prefix: "beowulf", enforce: true, env_map: {__MODULE__, :__test_env_map__, [:the_system]})

      assert config[:the_system][:port] == 5049
    end
  end

  describe "when dealing with overlapping property name and env name" do
    test "correctly pulls the right envs", state do
      expected_type = "test_logger_type"
      System.put_env("BEOWULF_MYCLUSTER_LOGGER_TYPE", expected_type)

      config =
        init_and_load(
          [],
          prefix: "beowulf",
          env_map: state[:overlapping_property_and_name_config],
          enforce: false
        )

      type = config[:mycluster][:logger][:type]

      assert type == expected_type
    end
  end

  def __test_env_map__(main_name) do
    %{
      main_name => %{
        port: %{type: :integer}
      }
    }
  end

  defp init_and_load(existing_config, options) do
    options = EnvVar.Provider.init(options)
    EnvVar.Provider.load(existing_config, options)
  end
end
