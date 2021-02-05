# Changelog

## [0.5.3] - 2021-02-01
  - Fixes bug related to the edgecase where `TYPE` is in the environment variable
    name. For example: Environment variable `SOMETHING_TYPE` should be readable
    using the map `%{something: %{type: %{type: :string}}}`.

## [0.5.2] - 2020-06-18
  - Ensures project is compiled before the mix `show_vars` task runs.
