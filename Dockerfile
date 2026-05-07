FROM hexpm/elixir:1.18.4-erlang-25.3.2.7-debian-bookworm-20260421-slim AS build

RUN apt-get update && \
    apt-get install -y --no-install-recommends build-essential git ca-certificates && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

ENV MIX_ENV=prod

RUN mix local.hex --force && mix local.rebar --force

COPY mix.exs mix.lock ./
COPY config config

RUN mix deps.get --only prod
RUN mix deps.compile

COPY lib lib
COPY priv priv
COPY assets assets

RUN mix compile
RUN mix assets.deploy
RUN mix release

FROM debian:bookworm-slim AS app

RUN apt-get update && \
    apt-get install -y --no-install-recommends libstdc++6 openssl libncurses6 ca-certificates && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

ENV LANG=C.UTF-8
ENV PHX_SERVER=true
ENV MIX_ENV=prod
ENV PORT=4000

COPY --from=build /app/_build/prod/rel/yokai_septet ./

EXPOSE 4000

CMD ["/app/bin/yokai_septet", "start"]
