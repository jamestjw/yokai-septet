defmodule YokaiSeptetWeb.Router do
  use YokaiSeptetWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {YokaiSeptetWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :health do
    plug :accepts, ["json"]
  end

  scope "/health", YokaiSeptetWeb do
    pipe_through :health

    get "/live", HealthController, :live
    get "/ready", HealthController, :ready
  end

  scope "/", YokaiSeptetWeb do
    pipe_through :browser

    live "/", HomeLive, :home
    live "/rules", HomeLive, :rules
    live "/play/:mode", TableLive, :play
  end
end
