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

  test "2p room waits for both players to confirm setup" do
    {:ok, code} = Lobby.create_room("2p", "host-id", "Host")
    cleanup_room(code)

    assert {:ok, 1} = GameRoom.join(code, "guest-id", "Guest")
    assert :ok = GameRoom.start_game(code, "host-id")

    assert {:ok, snap} = GameRoom.snapshot(code)
    assert snap.phase == :playing
    assert snap.game.mode == "2p"
    assert snap.game.phase == :swapping
    assert Enum.map(snap.game.players, & &1.name) == ["Host", "Guest"]

    host_discard = snap.game.hands |> Enum.at(0) |> Enum.find(&(not &1.is_boss))
    guest_discard = snap.game.hands |> Enum.at(1) |> Enum.find(&(not &1.is_boss))

    assert :ok = GameRoom.set_discard(code, "host-id", host_discard.id)
    assert :ok = GameRoom.confirm_setup(code, "host-id")

    assert {:ok, snap} = GameRoom.snapshot(code)
    assert snap.game.phase == :swapping
    assert snap.game.setup_confirmed == %{0 => true}

    assert :ok = GameRoom.set_discard(code, "guest-id", guest_discard.id)
    assert :ok = GameRoom.confirm_setup(code, "guest-id")

    assert {:ok, snap} = GameRoom.snapshot(code)
    assert snap.game.phase == :playing
    assert Enum.map(snap.game.discard, & &1.id) == [host_discard.id, guest_discard.id]
  end

  defp cleanup_room(code) do
    on_exit(fn ->
      with {:ok, pid} <- Lobby.lookup(code) do
        DynamicSupervisor.terminate_child(YokaiSeptet.RoomSupervisor, pid)
      end
    end)
  end
end
