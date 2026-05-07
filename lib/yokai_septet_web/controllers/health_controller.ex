defmodule YokaiSeptetWeb.HealthController do
  use YokaiSeptetWeb, :controller

  def live(conn, _params) do
    json(conn, %{status: "ok"})
  end

  def ready(conn, _params) do
    checks = [
      {:endpoint, Process.whereis(YokaiSeptetWeb.Endpoint)},
      {:pubsub, Process.whereis(YokaiSeptet.PubSub)}
    ]

    failed =
      checks
      |> Enum.filter(fn {_name, pid} -> is_nil(pid) or not Process.alive?(pid) end)
      |> Enum.map(fn {name, _pid} -> Atom.to_string(name) end)

    if failed == [] do
      json(conn, %{status: "ready"})
    else
      conn
      |> put_status(:service_unavailable)
      |> json(%{status: "not_ready", failed_checks: failed})
    end
  end
end
