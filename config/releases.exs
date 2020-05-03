import Config

config :my_app, MyApp.Repo,
  adapter: Ecto.Adapters.Postgres,
  username: System.get_env("RDS_USERNAME"),
  password: System.get_env("RDS_PASSWORD"),
  database: "myapp",
  hostname: System.get_env("RDS_HOSTNAME"),
  port: System.get_env("RDS_PORT") || 5432,
  pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10")

secret_key_base =
  System.get_env("SECRET_KEY_BASE") ||
    raise """
    environment variable SECRET_KEY_BASE is missing.
    You can generate one by calling: mix phx.gen.secret
    """

config :my_app, MyAppWeb.Endpoint,
  http: [:inet6, port: String.to_integer(System.get_env("PORT") || "4000")],
  secret_key_base: secret_key_base

config :my_app, MyAppWeb.Endpoint, server: true