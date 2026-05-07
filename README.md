# YokaiSeptet

A Phoenix web app for the Yokai Septet card game.

## Credits

The original game is [Yokai Septet](https://boardgamegeek.com/boardgame/251433/yokai-septet3) by Muneyuki Yokouchi (横内宗幸).

## Getting Started

* Run `mix setup` to install dependencies and prepare the app.
* Start the server with `mix phx.server` or `iex -S mix phx.server`.

Then open [`localhost:4000`](http://localhost:4000) in your browser.

## Production

When running a release in production, set these environment variables:

* `SECRET_KEY_BASE` - required
* `PHX_HOST` - required, the public host name for the app
* `PHX_SERVER=true` - required when starting the release server
* `PORT` - optional, defaults to `4000`
* `DNS_CLUSTER_QUERY` - optional, only needed if you use DNS-based clustering

Example:

```bash
PHX_SERVER=true \
SECRET_KEY_BASE=your_secret_key_base \
PHX_HOST=your.domain.com \
PORT=4000 \
bin/yokai_septet start
```
