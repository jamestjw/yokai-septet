defmodule YokaiSeptetWeb.HealthControllerTest do
  use YokaiSeptetWeb.ConnCase, async: true

  test "GET /health/live", %{conn: conn} do
    conn = get(conn, ~p"/health/live")

    assert json_response(conn, 200) == %{"status" => "ok"}
  end

  test "GET /health/ready", %{conn: conn} do
    conn = get(conn, ~p"/health/ready")

    assert json_response(conn, 200) == %{"status" => "ready"}
  end
end
