# Elastic Beanstalk Elixir

**Part 1:**

Prepare app for release


1. Change `config/prod.secret.exs` to `config/releases.exs` with these contents adjusted to your app:

**config/releases.exs** (comments removed for brevity)
```elixir
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
```

2. Change `config/prod.exs` to look like this:
**my_app/config/prod.exs**
```
use Mix.Config

config :my_app, MyAppWeb.Endpoint,
  http: [port: {:system, "PORT"}, compress: true],
  url: [scheme: "https", host: System.get_env("HOST"), port: 443],
  code_reloader: false,
  cache_static_manifest: "priv/static/manifest.json",
  server: true

config :logger, level: :info
```

3. Create a `release.ex` file inside `lib/my_app_web` directory:

**lib/my_app_web/release.ex**
```elixir
defmodule MyApp.Release do
  @app :my_app

  def migrate do
    Application.ensure_all_started(@app)
    
    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  def rollback(repo, version) do
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  defp repos do
    Application.load(@app)
    Application.fetch_env!(@app, :ecto_repos)
  end
end
```

Now to add the Dockefile

**Dockerfile**
```Dockerfile
FROM elixir:1.10-alpine as build

# install build dependencies
RUN apk add --update git build-base nodejs npm yarn

# prepare build dir
RUN mkdir /app
WORKDIR /app

# install hex + rebar
RUN mix local.hex --force && \
    mix local.rebar --force

# set build ENV
ENV MIX_ENV=prod


# install mix dependencies
COPY mix.exs mix.lock ./
COPY config config
RUN mix deps.get --only prod
RUN MIX_ENV=prod mix deps.compile

# build assets
COPY assets assets
COPY priv priv
RUN cd assets && npm install && npm run deploy
RUN mix phx.digest

# build project
COPY lib lib
RUN mix compile

# copy entry point file over
COPY entrypoint.sh entrypoint.sh

RUN mix release

# prepare release image
FROM alpine:3.9 AS app

RUN apk add --update bash openssl postgresql-client

WORKDIR /app

COPY --from=build /app/_build/prod/rel/my_app ./
COPY --from=build /app/entrypoint.sh entrypoint.sh
RUN chown -R nobody: /app
USER nobody

ENV HOME=/app

# CMD ["./bin/my_app eval", "MyApp.Release.migrate"]
# CMD ["./bin/my_app", "start"]

ENTRYPOINT ["sh", "./entrypoint.sh"]
```

Also don't forget to put in a `.dockerignore` file to cut down on bloat.

**.dockerignore**
```yaml
/deps
/_build
ecl_Crash.dump
/node_modules
/priv/static/*
/uploads/files/*
.git
.gitignore

# Elastic Beanstalk Files
.elasticbeanstalk/*
.git
.gitignore
```

Add an `entrypoint.sh` script.

**entrypoint.sh**
```shell
#!/bin/bash
# Docker entrypoint script.

# Wait until Postgres is ready
while ! pg_isready -q -h "aa2tzxdwb7y3qa5.xxxxxxxxxxxx.us-west-2.rds.amazonaws.com" -p 5432 -U "ebroot"
                          
do
  echo "$(date) - waiting for database to start"
  sleep 2
done

./bin/my_app eval "MyApp.Release.migrate" && \
./bin/my_app start
```

Our final step will be to add the `buildspec.yml` file.

**buildspec.yml**
```yaml
version: 0.2

phases:
  pre_build:
    commands:
      - echo Logging in to Amazon ECR...
      - aws --version
      - $(aws ecr get-login --region $AWS_DEFAULT_REGION --no-include-email)
      - REPOSITORY_URI=xxxxxxxxxxxx.dkr.ecr.us-west-2.amazonaws.com/my-app
      - COMMIT_HASH=$(echo $CODEBUILD_RESOLVED_SOURCE_VERSION | cut -c 1-7)
      - IMAGE_TAG=build-$(echo $CODEBUILD_BUILD_ID | awk -F":" '{print $2}')
  build:
    commands:
      - echo Build started on `date`
      - echo Building the Docker image...
      - docker build -t $REPOSITORY_URI:latest .
      - docker tag $REPOSITORY_URI:latest $REPOSITORY_URI:$IMAGE_TAG
  post_build:
    commands:
      - echo Build completed on `date`
      - echo Pushing the Docker images...
      - docker push $REPOSITORY_URI:latest
      - docker push $REPOSITORY_URI:$IMAGE_TAG 
      - aws s3 sync s3://my-app-artifacts .
artifacts:
  files: 
    - Dockerrun.aws.json
    - proxy/conf.d/*
```


Your app is now ready to be deployed to an Elastic Beanstalk!