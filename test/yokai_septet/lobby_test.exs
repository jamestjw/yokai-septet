defmodule YokaiSeptet.LobbyTest do
  use ExUnit.Case, async: false

  alias YokaiSeptet.{Cards, GameRoom, Lobby}

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

  test "2p setup is not auto-confirmed during lobby-to-table navigation disconnect" do
    {:ok, code} = Lobby.create_room("2p", "host-id", "Host")
    cleanup_room(code)

    assert {:ok, 1} = GameRoom.join(code, "guest-id", "Guest")

    view_pid =
      start_supervised!(
        Supervisor.child_spec({Agent, fn -> nil end}, id: :host_view, restart: :temporary)
      )

    assert :ok = GameRoom.register_view(code, "host-id", view_pid)
    ref = Process.monitor(view_pid)

    assert :ok = GameRoom.start_game(code, "host-id")
    Agent.stop(view_pid)
    assert_receive {:DOWN, ^ref, :process, ^view_pid, :normal}

    {:ok, room_pid} = Lobby.lookup(code)
    _ = :sys.get_state(room_pid)

    assert {:ok, snap} = GameRoom.snapshot(code)
    assert snap.game.phase == :swapping
    assert snap.game.setup_confirmed == %{}
    assert Enum.at(snap.seats, 0) == {:human, "host-id", "Host", :disconnected}
  end

  test "2p multiplayer setup can hide a face-up boss in the straw pile" do
    {:ok, code} = Lobby.create_room("2p", "host-id", "Host")
    cleanup_room(code)

    assert {:ok, 1} = GameRoom.join(code, "guest-id", "Guest")
    assert :ok = GameRoom.start_game(code, "host-id")
    assert {:ok, room_pid} = Lobby.lookup(code)

    host_discard = non_boss(:earth, 2)
    guest_discard = non_boss(:mist, 3)
    up_boss = boss(:forest)
    hidden_card = non_boss(:river, 4)

    host_straw = %{
      downs: [
        %{card: hidden_card, revealed?: false} | List.duplicate(%{card: nil, revealed?: false}, 6)
      ],
      ups: [up_boss | List.duplicate(nil, 5)]
    }

    :sys.replace_state(room_pid, fn state ->
      game = %{
        state.game
        | phase: :swapping,
          hands: [[host_discard], [guest_discard]],
          straw: [host_straw, empty_straw()],
          setup_discards: %{},
          setup_swap_decisions: %{},
          setup_confirmed: %{}
      }

      %{state | game: game}
    end)

    assert :ok = GameRoom.set_discard(code, "host-id", host_discard.id)
    assert :ok = GameRoom.set_swap(code, "host-id", 0, :left)
    assert :ok = GameRoom.confirm_setup(code, "host-id")

    assert {:ok, snap} = GameRoom.snapshot(code)
    assert snap.game.phase == :swapping

    assert :ok = GameRoom.set_discard(code, "guest-id", guest_discard.id)
    assert :ok = GameRoom.confirm_setup(code, "guest-id")

    assert {:ok, snap} = GameRoom.snapshot(code)
    assert snap.game.phase == :playing

    assert snap.game.straw |> Enum.at(0) |> Map.fetch!(:ups) |> hd() |> Map.get(:id) ==
             hidden_card.id

    assert snap.game.straw
           |> Enum.at(0)
           |> Map.fetch!(:downs)
           |> hd()
           |> Map.fetch!(:card)
           |> Map.get(:id) == up_boss.id
  end

  defp cleanup_room(code) do
    on_exit(fn ->
      with {:ok, pid} <- Lobby.lookup(code) do
        DynamicSupervisor.terminate_child(YokaiSeptet.RoomSupervisor, pid)
      end
    end)
  end

  defp boss(suit) do
    Cards.build_deck() |> Enum.find(&(&1.suit == suit and &1.is_boss))
  end

  defp non_boss(suit, rank) do
    Cards.build_deck() |> Enum.find(&(&1.suit == suit and &1.rank == rank))
  end

  defp empty_straw do
    %{downs: List.duplicate(%{card: nil, revealed?: false}, 7), ups: List.duplicate(nil, 6)}
  end
end
