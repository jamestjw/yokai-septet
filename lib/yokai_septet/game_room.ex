defmodule YokaiSeptet.GameRoom do
  @moduledoc """
  Per-room GenServer that owns the multiplayer game state.

  Seats are indexed 0..num_p-1 and each holds one of:

    * `{:empty}`
    * `{:ai, name}`
    * `{:human, player_id, name, :connected | :disconnected}`

  The GenServer drives AI plays (and AI passing) for `:ai` seats and for
  disconnected human seats. State changes are broadcast on
  `"room:<code>"` via `Phoenix.PubSub`.

  In-memory only: nothing is persisted. A server restart drops all rooms.
  """
  use GenServer

  alias YokaiSeptet.Game

  @ai_delay 750
  @trick_delay 1400
  @grace_ms 120_000

  # --------------- Public API ---------------

  def start_link({code, mode, host_id, host_name}) do
    GenServer.start_link(__MODULE__, {code, mode, host_id, host_name}, name: via(code))
  end

  defp via(code), do: {:via, Registry, {YokaiSeptet.RoomRegistry, code}}

  defp call(code, msg) do
    case Registry.lookup(YokaiSeptet.RoomRegistry, code) do
      [{pid, _}] -> GenServer.call(pid, msg)
      [] -> {:error, :not_found}
    end
  end

  def snapshot(code), do: call(code, :snapshot)
  def join(code, player_id, name), do: call(code, {:join, player_id, name})
  def claim_seat(code, player_id, seat_idx), do: call(code, {:claim_seat, player_id, seat_idx})
  def fill_with_ai(code, player_id), do: call(code, {:fill_with_ai, player_id})
  def kick_ai(code, player_id, seat_idx), do: call(code, {:kick_ai, player_id, seat_idx})
  def start_game(code, player_id), do: call(code, {:start_game, player_id})
  def play_card(code, player_id, card_id), do: call(code, {:play_card, player_id, card_id})

  def submit_pass(code, player_id, card_ids),
    do: call(code, {:submit_pass, player_id, card_ids})

  def next_round(code, player_id), do: call(code, {:next_round, player_id})

  @doc "Register a connected LiveView pid for monitoring (disconnect detection)."
  def register_view(code, player_id, pid), do: call(code, {:register_view, player_id, pid})

  # --------------- GenServer ---------------

  @impl true
  def init({code, mode, host_id, host_name}) when mode in ["4p", "3p"] do
    num_p =
      case mode do
        "4p" -> 4
        "3p" -> 3
      end

    seats =
      Tuple.duplicate({:empty}, num_p)
      |> put_elem(0, {:human, host_id, host_name, :connected})
      |> Tuple.to_list()

    state = %{
      code: code,
      mode: mode,
      num_p: num_p,
      host_id: host_id,
      seats: seats,
      phase: :lobby,
      game: nil,
      monitors: %{},
      grace_timers: %{}
    }

    {:ok, state}
  end

  def init({_code, _mode, _host_id, _host_name}),
    do: {:stop, :unsupported_mode}

  # --------- lobby ---------

  @impl true
  def handle_call(:snapshot, _from, state), do: {:reply, {:ok, public(state)}, state}

  def handle_call({:join, player_id, name}, _from, state) do
    cond do
      state.phase != :lobby ->
        case find_seat_by_player(state.seats, player_id) do
          nil -> {:reply, {:error, :in_progress}, state}
          idx -> {:reply, {:ok, idx}, state}
        end

      true ->
        case find_seat_by_player(state.seats, player_id) do
          idx when is_integer(idx) ->
            {:reply, {:ok, idx}, state}

          nil ->
            case first_empty(state.seats) do
              nil ->
                {:reply, {:error, :full}, state}

              idx ->
                seats = List.replace_at(state.seats, idx, {:human, player_id, name, :connected})
                state = %{state | seats: seats} |> broadcast()
                {:reply, {:ok, idx}, state}
            end
        end
    end
  end

  def handle_call({:claim_seat, player_id, seat_idx}, _from, state) do
    cond do
      state.phase != :lobby ->
        {:reply, {:error, :in_progress}, state}

      seat_idx < 0 or seat_idx >= state.num_p ->
        {:reply, {:error, :invalid_seat}, state}

      true ->
        case Enum.at(state.seats, seat_idx) do
          {:empty} ->
            name = name_for(state.seats, player_id) || "Player"

            seats =
              state.seats
              |> clear_player(player_id)
              |> List.replace_at(seat_idx, {:human, player_id, name, :connected})

            state = %{state | seats: seats} |> broadcast()
            {:reply, :ok, state}

          _ ->
            {:reply, {:error, :taken}, state}
        end
    end
  end

  def handle_call({:fill_with_ai, player_id}, _from, state) do
    if player_id != state.host_id or state.phase != :lobby do
      {:reply, {:error, :forbidden}, state}
    else
      {seats, _} =
        Enum.map_reduce(state.seats, ai_name_pool(), fn
          {:empty}, [name | rest] -> {{:ai, name}, rest}
          seat, pool -> {seat, pool}
        end)

      state = %{state | seats: seats} |> broadcast()
      {:reply, :ok, state}
    end
  end

  def handle_call({:kick_ai, player_id, seat_idx}, _from, state) do
    cond do
      player_id != state.host_id or state.phase != :lobby ->
        {:reply, {:error, :forbidden}, state}

      true ->
        case Enum.at(state.seats, seat_idx) do
          {:ai, _} ->
            seats = List.replace_at(state.seats, seat_idx, {:empty})
            state = %{state | seats: seats} |> broadcast()
            {:reply, :ok, state}

          _ ->
            {:reply, {:error, :not_ai}, state}
        end
    end
  end

  def handle_call({:start_game, player_id}, _from, state) do
    cond do
      player_id != state.host_id ->
        {:reply, {:error, :forbidden}, state}

      state.phase != :lobby ->
        {:reply, {:error, :already_started}, state}

      Enum.any?(state.seats, &match?({:empty}, &1)) ->
        {:reply, {:error, :seats_not_filled}, state}

      true ->
        game =
          Game.new(state.mode)
          |> override_players(state.seats, state.mode)
          |> Game.start_round()

        # For multiplayer: fill AI passes up front; humans submit via UI.
        game = Game.fill_ai_passes(game)

        state =
          %{state | phase: :playing, game: game}
          |> maybe_finalize_passes()
          |> maybe_schedule_ai()
          |> broadcast()

        {:reply, :ok, state}
    end
  end

  # --------- in-game ---------

  def handle_call({:play_card, player_id, card_id}, _from, state) do
    with :playing <- state.phase,
         seat_idx when is_integer(seat_idx) <- find_seat_by_player(state.seats, player_id),
         true <- seat_idx == state.game.current_idx do
      state = do_play_card(state, seat_idx, card_id)
      {:reply, :ok, state}
    else
      _ -> {:reply, {:error, :not_your_turn}, state}
    end
  end

  def handle_call({:submit_pass, player_id, card_ids}, _from, state) do
    with :playing <- state.phase,
         %{phase: :passing} <- state.game,
         seat_idx when is_integer(seat_idx) <- find_seat_by_player(state.seats, player_id),
         3 <- length(card_ids),
         true <- valid_pass?(state.game, seat_idx, card_ids) do
      game = Game.set_pending_pass(state.game, seat_idx, card_ids)
      state = %{state | game: game} |> maybe_finalize_passes() |> broadcast()
      {:reply, :ok, state}
    else
      _ -> {:reply, {:error, :invalid}, state}
    end
  end

  def handle_call({:next_round, player_id}, _from, state) do
    cond do
      player_id != state.host_id ->
        {:reply, {:error, :forbidden}, state}

      state.game && state.game.phase == :round_end ->
        game =
          state.game
          |> Game.next_round()
          |> Game.fill_ai_passes()

        state = %{state | game: game} |> maybe_schedule_ai() |> broadcast()
        {:reply, :ok, state}

      true ->
        {:reply, {:error, :not_ready}, state}
    end
  end

  def handle_call({:register_view, player_id, pid}, _from, state) do
    case find_seat_by_player(state.seats, player_id) do
      nil ->
        {:reply, {:error, :no_seat}, state}

      seat_idx ->
        ref = Process.monitor(pid)
        monitors = Map.put(state.monitors, ref, {player_id, seat_idx, pid})

        # Cancel any grace timer + flip back to connected.
        timers = state.grace_timers

        timers =
          case Map.pop(timers, seat_idx) do
            {nil, t} ->
              t

            {tref, t} ->
              Process.cancel_timer(tref)
              t
          end

        seats =
          case Enum.at(state.seats, seat_idx) do
            {:human, ^player_id, name, _} ->
              List.replace_at(state.seats, seat_idx, {:human, player_id, name, :connected})

            _ ->
              state.seats
          end

        state = %{state | monitors: monitors, grace_timers: timers, seats: seats} |> broadcast()
        {:reply, :ok, state}
    end
  end

  # --------- handle_info ---------

  @impl true
  def handle_info(:ai_play, state) do
    cond do
      state.game == nil ->
        {:noreply, state}

      state.game.phase == :playing and seat_should_be_auto?(state, state.game.current_idx) ->
        idx = state.game.current_idx
        g = state.game

        card_id =
          Game.ai_pick(
            Game.effective_hand(g, idx),
            g.lead_suit,
            g.trump_suit,
            g.trick
          )

        {:noreply, do_play_card(state, idx, card_id) |> broadcast()}

      true ->
        {:noreply, state}
    end
  end

  def handle_info(:resolve_trick, state) do
    if state.game && state.game.phase == :trick_end do
      game = Game.resolve_trick(state.game)
      state = %{state | game: game} |> maybe_schedule_ai() |> broadcast()
      {:noreply, state}
    else
      {:noreply, state}
    end
  end

  def handle_info({:grace_expired, seat_idx}, state) do
    case Enum.at(state.seats, seat_idx) do
      {:human, _pid, name, :disconnected} ->
        seats = List.replace_at(state.seats, seat_idx, {:ai, name})
        timers = Map.delete(state.grace_timers, seat_idx)
        state = %{state | seats: seats, grace_timers: timers} |> broadcast()
        {:noreply, state}

      _ ->
        {:noreply, state}
    end
  end

  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    case Map.pop(state.monitors, ref) do
      {nil, _} ->
        {:noreply, state}

      {{player_id, seat_idx, _pid}, monitors} ->
        seats =
          case Enum.at(state.seats, seat_idx) do
            {:human, ^player_id, name, :connected} ->
              List.replace_at(state.seats, seat_idx, {:human, player_id, name, :disconnected})

            other when not is_nil(other) ->
              state.seats

            _ ->
              state.seats
          end

        tref = Process.send_after(self(), {:grace_expired, seat_idx}, @grace_ms)
        timers = Map.put(state.grace_timers, seat_idx, tref)

        state =
          %{state | monitors: monitors, seats: seats, grace_timers: timers}
          |> maybe_finalize_passes()
          |> maybe_schedule_ai()
          |> broadcast()

        {:noreply, state}
    end
  end

  def handle_info(_, state), do: {:noreply, state}

  # --------- helpers ---------

  defp do_play_card(state, seat_idx, card_id) do
    case Game.play_card(state.game, seat_idx, card_id) do
      {:invalid, _} ->
        state

      {:continue, g2} ->
        %{state | game: g2} |> maybe_schedule_ai() |> broadcast()

      {:trick_complete, g2} ->
        Process.send_after(self(), :resolve_trick, @trick_delay)
        %{state | game: g2} |> broadcast()
    end
  end

  defp maybe_schedule_ai(state) do
    g = state.game

    if (g && g.phase == :playing) and seat_should_be_auto?(state, g.current_idx) do
      Process.send_after(self(), :ai_play, @ai_delay)
    end

    state
  end

  defp maybe_finalize_passes(state) do
    g = state.game

    cond do
      g == nil ->
        state

      g.phase != :passing ->
        state

      true ->
        # Auto-pass for any disconnected human whose pass isn't in yet.
        g =
          Enum.reduce(0..(g.num_p - 1), g, fn idx, g ->
            if Map.has_key?(g.pending_passes, idx) do
              g
            else
              case Enum.at(state.seats, idx) do
                {:human, _, _, :disconnected} ->
                  ids = Game.ai_pick_pass(Enum.at(g.hands, idx), 3)
                  Game.set_pending_pass(g, idx, ids)

                {:ai, _} ->
                  ids = Game.ai_pick_pass(Enum.at(g.hands, idx), 3)
                  Game.set_pending_pass(g, idx, ids)

                _ ->
                  g
              end
            end
          end)

        if map_size(g.pending_passes) == g.num_p do
          g = Game.finalize_passes(g)
          %{state | game: g} |> maybe_schedule_ai()
        else
          %{state | game: g}
        end
    end
  end

  defp seat_should_be_auto?(state, seat_idx) do
    case Enum.at(state.seats, seat_idx) do
      {:ai, _} -> true
      {:human, _, _, :disconnected} -> true
      _ -> false
    end
  end

  defp valid_pass?(game, seat_idx, card_ids) do
    hand_ids = Enum.at(game.hands, seat_idx) |> Enum.map(& &1.id)
    Enum.all?(card_ids, &(&1 in hand_ids))
  end

  defp first_empty(seats), do: Enum.find_index(seats, &match?({:empty}, &1))

  defp find_seat_by_player(seats, player_id) do
    Enum.find_index(seats, fn
      {:human, ^player_id, _, _} -> true
      _ -> false
    end)
  end

  defp name_for(seats, player_id) do
    Enum.find_value(seats, fn
      {:human, ^player_id, name, _} -> name
      _ -> nil
    end)
  end

  defp clear_player(seats, player_id) do
    Enum.map(seats, fn
      {:human, ^player_id, _, _} -> {:empty}
      other -> other
    end)
  end

  defp ai_name_pool, do: ["Akari", "Kenji", "Yumiko", "Hiroshi", "Sora", "Rin"]

  # Replace the default Game.players with seat-derived player metadata.
  defp override_players(game, seats, "4p") do
    players =
      Enum.with_index(seats)
      |> Enum.map(fn {seat, idx} ->
        {name, is_human, player_id} = seat_player(seat, idx)
        team = rem(idx, 2)
        partner = rem(idx + 2, 4)
        %{name: name, team: team, is_human: is_human, partner: partner, player_id: player_id}
      end)

    %{game | players: players}
  end

  defp override_players(game, seats, "3p") do
    players =
      Enum.with_index(seats)
      |> Enum.map(fn {seat, idx} ->
        {name, is_human, player_id} = seat_player(seat, idx)
        %{name: name, team: idx, is_human: is_human, player_id: player_id}
      end)

    %{game | players: players}
  end

  defp seat_player({:human, pid, name, _}, _idx), do: {name, true, pid}
  defp seat_player({:ai, name}, _idx), do: {name, false, nil}
  defp seat_player({:empty}, idx), do: {"Seat #{idx + 1}", false, nil}

  defp broadcast(state) do
    Phoenix.PubSub.broadcast(
      YokaiSeptet.PubSub,
      "room:#{state.code}",
      {:room_updated, public(state)}
    )

    state
  end

  defp public(state) do
    %{
      code: state.code,
      mode: state.mode,
      num_p: state.num_p,
      host_id: state.host_id,
      seats: state.seats,
      phase: state.phase,
      game: state.game
    }
  end
end
