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

ENTRYPOINT ["sh", "./entrypoint.sh"]