defmodule YokaiSeptetWeb.LobbyNewLiveTest do
  use YokaiSeptetWeb.ConnCase, async: false

  alias YokaiSeptet.Lobby

  test "name keyup uses the browser event value", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/lobby/new")

    view
    |> element("#new-room-name")
    |> render_keyup(%{"key" => "j", "value" => "j"})

    assert has_element?(view, ~s(#new-room-name[value="j"]))
  end

  test "create validates name and redirects to the new lobby", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/lobby/new")

    view
    |> element("#new-room-form")
    |> render_submit(%{"name" => "   "})

    assert has_element?(view, "#new-room-error")

    view
    |> element("#new-room-form")
    |> render_submit(%{"name" => "Yamato"})

    {path, _flash} = assert_redirect(view)
    assert path =~ ~r|^/lobby/[A-HJ-NP-Z2-9]{6}\?name=Yamato$|

    path
    |> room_code_from_path()
    |> cleanup_room()
  end

  defp room_code_from_path(path) do
    path
    |> URI.parse()
    |> Map.fetch!(:path)
    |> String.split("/", trim: true)
    |> List.last()
  end

  defp cleanup_room(code) do
    with {:ok, pid} <- Lobby.lookup(code) do
      DynamicSupervisor.terminate_child(YokaiSeptet.RoomSupervisor, pid)
    end
  end
end
