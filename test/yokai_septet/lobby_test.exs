defmodule YokaiSeptet.LobbyTest do
  use ExUnit.Case, async: false

  alias YokaiSeptet.{GameRoom, Lobby}

  test "room lifecycle supports joining, filling AI seats, and starting" do
    {:ok, code} = Lobby.create_room("3p", "host-id", "Host")
    cleanup_room(code)

    assert {:ok, snap} = GameRoom.snapshot(code)
    assert snap.phase == :lobby
    assert snap.mode == "3p"
    assert snap.seats == [{:human, "host-id", "Host", :connected}, {:empty}, {:empty}]

    assert {:ok, 1} = GameRoom.join(code, "guest-id", "Guest")
    assert {:error, :forbidden} = GameRoom.fill_with_ai(code, "guest-id")
    assert :ok = GameRoom.fill_with_ai(code, "host-id")

    assert {:ok, snap} = GameRoom.snapshot(code)

    assert [
             {:human, "host-id", "Host", :connected},
             {:human, "guest-id", "Guest", :connected},
             {:ai, _}
           ] = snap.seats

    assert {:error, :forbidden} = GameRoom.start_game(code, "guest-id")
    assert :ok = GameRoom.start_game(code, "host-id")

    assert {:ok, snap} = GameRoom.snapshot(code)
    assert snap.phase == :playing
    assert snap.game.mode == "3p"
    assert Enum.map(snap.game.players, & &1.name) == ["Host", "Guest", "Akari"]
  end

  defp cleanup_room(code) do
    on_exit(fn ->
      with {:ok, pid} <- Lobby.lookup(code) do
        DynamicSupervisor.terminate_child(YokaiSeptet.RoomSupervisor, pid)
      end
    end)
  end
end
