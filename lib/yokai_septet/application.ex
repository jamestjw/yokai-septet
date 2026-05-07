defmodule YokaiSeptet.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      YokaiSeptetWeb.Telemetry,
      {DNSCluster, query: Application.get_env(:yokai_septet, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: YokaiSeptet.PubSub},
      # Start a worker by calling: YokaiSeptet.Worker.start_link(arg)
      # {YokaiSeptet.Worker, arg},
      # Start to serve requests, typically the last entry
      YokaiSeptetWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: YokaiSeptet.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    YokaiSeptetWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
