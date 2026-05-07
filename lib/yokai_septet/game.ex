defmodule YokaiSeptet.Game do
  @moduledoc """
  Yokai Septet game state and transitions. Pure functions over a state map;
  the LiveView holds the state and schedules timed transitions
  (AI plays, trick resolution) as messages to itself.
  """

  alias YokaiSeptet.Cards

  @type phase ::
          :idle | :passing | :playing | :trick_end | :round_end | :game_end

  @doc "Build initial state for a mode (\"4p\" | \"3p\" | \"2p\")."
  def new(mode) when mode in ["4p", "3p", "2p"] do
    players = make_players(mode)
    num_p = length(players)

    %{
      players: players,
      mode: mode,
      num_p: num_p,
      hands: List.duplicate([], num_p),
      trump_card: nil,
      trump_suit: nil,
      lead_idx: 0,
      current_idx: 0,
      trick: [],
      lead_suit: nil,
      tricks_won: List.duplicate(0, num_p),
      bosses_by_player: List.duplicate([], num_p),
      phase: :idle,
      scores: initial_scores(mode, num_p),
      round: 1,
      last_trick_info: nil,
      pending_passes: %{},
      human_pass_selection: [],
      round_log: []
    }
  end

  defp initial_scores("4p", _num_p), do: %{0 => 0, 1 => 0}
  defp initial_scores(_, num_p), do: for(i <- 0..(num_p - 1), into: %{}, do: {i, 0})

  defp make_players("4p") do
    [
      %{name: "You", team: 0, is_human: true, partner: 2},
      %{name: "Akari", team: 1, is_human: false, partner: 3},
      %{name: "Kenji", team: 0, is_human: false, partner: 0},
      %{name: "Yumiko", team: 1, is_human: false, partner: 1}
    ]
  end

  defp make_players("3p") do
    [
      %{name: "You", team: 0, is_human: true},
      %{name: "Akari", team: 1, is_human: false},
      %{name: "Kenji", team: 2, is_human: false}
    ]
  end

  defp make_players("2p") do
    [
      %{name: "You", team: 0, is_human: true},
      %{name: "Akari", team: 1, is_human: false}
    ]
  end

  @doc "Deal a fresh round and either enter passing (3p+) or playing (2p)."
  def start_round(state) do
    {hands, trump_card, trump_suit} = deal(state.num_p)
    sorted = Enum.map(hands, &Cards.sort_hand/1)

    state =
      %{
        state
        | hands: sorted,
          trump_card: trump_card,
          trump_suit: trump_suit,
          tricks_won: List.duplicate(0, state.num_p),
          bosses_by_player: List.duplicate([], state.num_p),
          trick: [],
          lead_suit: nil,
          last_trick_info: nil,
          pending_passes: %{},
          human_pass_selection: [],
          round_log: []
      }

    if state.num_p >= 3 do
      %{state | phase: :passing}
    else
      lead = find_lead(sorted)
      %{state | phase: :playing, lead_idx: lead, current_idx: lead}
    end
  end

  defp find_lead(hands) do
    case Enum.find_index(hands, fn h -> Enum.any?(h, & &1.is_a) end) do
      nil -> 0
      i -> i
    end
  end

  defp deal(num_players) do
    deck = Enum.shuffle(Cards.build_deck())

    per_player =
      case num_players do
        4 -> 12
        3 -> 16
        _ -> 14
      end

    {hands, rest} =
      Enum.reduce(0..(num_players - 1), {[], deck}, fn _, {acc, remaining} ->
        {hand, tail} = Enum.split(remaining, per_player)
        {[hand | acc], tail}
      end)

    [trump | _] = rest
    {Enum.reverse(hands), trump, trump.suit}
  end

  # ----- Passing phase -----

  def toggle_pass_card(state, card_id) do
    sel = state.human_pass_selection

    new_sel =
      cond do
        card_id in sel -> Enum.reject(sel, &(&1 == card_id))
        length(sel) >= 3 -> sel
        true -> sel ++ [card_id]
      end

    %{state | human_pass_selection: new_sel}
  end

  @doc "Auto-fill AI pending passes (idempotent)."
  def fill_ai_passes(state) do
    pp = state.pending_passes

    pp =
      Enum.reduce(0..(state.num_p - 1), pp, fn i, acc ->
        if not Map.has_key?(acc, i) and not Enum.at(state.players, i).is_human do
          Map.put(acc, i, ai_pick_pass(Enum.at(state.hands, i), 3))
        else
          acc
        end
      end)

    %{state | pending_passes: pp}
  end

  def confirm_pass(state) do
    if length(state.human_pass_selection) != 3 do
      state
    else
      human_idx = Enum.find_index(state.players, & &1.is_human)
      all_passes = Map.put(state.pending_passes, human_idx, state.human_pass_selection)

      new_hands =
        Enum.reduce(0..(state.num_p - 1), state.hands, fn from, hands ->
          ids = Map.get(all_passes, from, [])
          src = Enum.at(hands, from)
          passed = Enum.filter(src, &(&1.id in ids))

          to =
            if state.num_p == 4 do
              Enum.at(state.players, from).partner
            else
              rem(from + 1, state.num_p)
            end

          hands
          |> List.replace_at(from, Enum.reject(src, &(&1.id in ids)))
          |> then(fn h -> List.replace_at(h, to, Enum.at(h, to) ++ passed) end)
        end)

      sorted = Enum.map(new_hands, &Cards.sort_hand/1)
      lead = find_lead(sorted)

      %{
        state
        | hands: sorted,
          pending_passes: %{},
          human_pass_selection: [],
          lead_idx: lead,
          current_idx: lead,
          phase: :playing
      }
    end
  end

  # ----- Playing -----

  @doc """
  Apply a card play. Returns `{:ok, state, next_action}` where `next_action`
  is one of:
    * `:continue` — next player should be prompted (caller schedules AI if needed)
    * `:trick_complete` — trick is full; caller should schedule resolution
    * `:invalid` — illegal play attempted, state unchanged
  """
  def play_card(state, player_idx, card_id) do
    cond do
      state.phase != :playing ->
        {:invalid, state}

      state.current_idx != player_idx ->
        {:invalid, state}

      true ->
        hand = Enum.at(state.hands, player_idx)
        legal = Cards.playable_cards(hand, state.lead_suit)

        case Enum.find(hand, &(&1.id == card_id)) do
          nil ->
            {:invalid, state}

          card ->
            if card_id not in legal do
              {:invalid, state}
            else
              new_hand = Enum.reject(hand, &(&1.id == card_id))
              new_hands = List.replace_at(state.hands, player_idx, new_hand)
              new_trick = state.trick ++ [%{player_idx: player_idx, card: card}]
              new_lead_suit = if state.trick == [], do: card.suit, else: state.lead_suit

              new_state = %{
                state
                | hands: new_hands,
                  trick: new_trick,
                  lead_suit: new_lead_suit
              }

              if length(new_trick) == state.num_p do
                {:trick_complete,
                 %{
                   new_state
                   | phase: :trick_end,
                     last_trick_info: %{
                       winner_idx:
                         Cards.trick_winner(new_trick, hd(new_trick).card.suit, state.trump_suit),
                       cards: Enum.map(new_trick, & &1.card),
                       lead_suit: hd(new_trick).card.suit
                     }
                 }}
              else
                {:continue, %{new_state | current_idx: rem(player_idx + 1, state.num_p)}}
              end
            end
        end
    end
  end

  @doc "Resolve a completed trick (called after the UI delay)."
  def resolve_trick(state) do
    info = state.last_trick_info
    winner = info.winner_idx
    bosses = info.cards |> Enum.filter(& &1.is_boss)

    new_tricks =
      List.update_at(state.tricks_won, winner, &(&1 + 1))

    new_bosses =
      if bosses == [] do
        state.bosses_by_player
      else
        List.update_at(state.bosses_by_player, winner, &(&1 ++ bosses))
      end

    state = %{
      state
      | tricks_won: new_tricks,
        bosses_by_player: new_bosses,
        trick: [],
        lead_suit: nil,
        lead_idx: winner,
        current_idx: winner
    }

    hands_empty = Enum.all?(state.hands, &(&1 == []))
    teams = team_totals(state)
    boss_threshold = if state.num_p == 4, do: 4, else: if(state.num_p == 3, do: 3, else: 4)
    trick_limit = if state.num_p == 4, do: 7, else: if(state.num_p == 3, do: 7, else: 13)

    reached = Enum.any?(teams, fn {_, v} -> v.bosses >= boss_threshold end)
    over_tricks = Enum.any?(teams, fn {_, v} -> v.tricks >= trick_limit end)

    if reached or over_tricks or hands_empty do
      score_round(%{state | phase: :round_end})
    else
      %{state | phase: :playing}
    end
  end

  defp team_totals(state) do
    state.players
    |> Enum.with_index()
    |> Enum.reduce(%{}, fn {p, i}, acc ->
      cur = Map.get(acc, p.team, %{tricks: 0, bosses: 0, idxs: []})

      Map.put(acc, p.team, %{
        tricks: cur.tricks + Enum.at(state.tricks_won, i),
        bosses: cur.bosses + length(Enum.at(state.bosses_by_player, i)),
        idxs: cur.idxs ++ [i]
      })
    end)
  end

  defp team_breakdown(state) do
    state.players
    |> Enum.with_index()
    |> Enum.reduce(%{}, fn {p, i}, acc ->
      cur = Map.get(acc, p.team, %{tricks: 0, bosses: [], idxs: []})

      Map.put(acc, p.team, %{
        tricks: cur.tricks + Enum.at(state.tricks_won, i),
        bosses: cur.bosses ++ Enum.at(state.bosses_by_player, i),
        idxs: cur.idxs ++ [i]
      })
    end)
  end

  defp score_round(state) do
    teams = team_breakdown(state)

    boss_threshold = if state.num_p == 4, do: 4, else: if(state.num_p == 3, do: 3, else: 4)
    trick_limit = if state.num_p == 4, do: 7, else: if(state.num_p == 3, do: 7, else: 13)

    reached = Enum.find(teams, fn {_, v} -> length(v.bosses) >= boss_threshold end)
    over_tricks = Enum.find(teams, fn {_, v} -> v.tricks >= trick_limit end)

    {winner_team, reason} =
      cond do
        reached ->
          {tid, _} = reached
          {tid, "Captured #{boss_threshold} Boss Yokai"}

        over_tricks ->
          {losing_tid, _} = over_tricks
          winners = Enum.reject(teams, fn {tid, _} -> tid == losing_tid end)

          cond do
            length(winners) == 1 ->
              {tid, _} = hd(winners)
              {tid, "Opponents took #{trick_limit} tricks (greed)"}

            true ->
              {:split, "Opponents took #{trick_limit} tricks (greed)"}
          end

        state.last_trick_info ->
          winner = state.last_trick_info.winner_idx
          {Enum.at(state.players, winner).team, "Took the final trick"}

        true ->
          {nil, ""}
      end

    points_awarded =
      cond do
        winner_team == :split ->
          {losing_tid, _} = over_tricks

          teams
          |> Enum.reject(fn {tid, _} -> tid == losing_tid end)
          |> Enum.map(fn {tid, _} -> {tid, 3} end)
          |> Map.new()

        is_integer(winner_team) ->
          won = teams[winner_team].bosses |> Enum.reject(&(&1.suit == state.trump_suit))
          pts = Enum.reduce(won, 0, fn b, acc -> acc + b.pts_solid end)
          %{winner_team => max(pts, 0)}

        true ->
          %{}
      end

    new_scores =
      Enum.reduce(points_awarded, state.scores, fn {tid, pts}, acc ->
        Map.update(acc, tid, pts, &(&1 + pts))
      end)

    log = %{
      winner_team: winner_team,
      reason: reason,
      teams: teams,
      points_awarded: points_awarded,
      trump_suit: state.trump_suit
    }

    state = %{state | scores: new_scores, round_log: [log]}

    if Enum.any?(new_scores, fn {_, v} -> v >= 7 end) do
      %{state | phase: :game_end}
    else
      state
    end
  end

  def next_round(state) do
    %{state | round: state.round + 1} |> start_round()
  end

  # ----- AI -----

  @doc "AI: pick 3 cards to pass — dump high non-bosses of weak suits, keep bosses + A."
  def ai_pick_pass(hand, count \\ 3) do
    sorted =
      Enum.sort_by(hand, fn c ->
        keep_priority =
          cond do
            c.is_a -> 3
            c.is_boss -> 2
            true -> 0
          end

        # Lower sort key = passed first.
        # Rank: weak suits + high suit_value = passed first
        suit_strength = Cards.suit(c.suit).strength
        {keep_priority, suit_strength, -c.suit_value}
      end)

    sorted |> Enum.take(count) |> Enum.map(& &1.id)
  end

  @doc "AI: pick a card to play."
  def ai_pick(hand, lead_suit, trump_suit, trick) do
    legal_ids = Cards.playable_cards(hand, lead_suit)
    legal = Enum.filter(hand, &(&1.id in legal_ids))
    trick_has_boss = Enum.any?(trick, & &1.card.is_boss)

    winners =
      if trick_has_boss and lead_suit do
        legal
        |> Enum.filter(fn c ->
          probe = trick ++ [%{player_idx: -1, card: c}]
          Cards.trick_winner(probe, lead_suit, trump_suit) == -1
        end)
        |> Enum.sort_by(& &1.suit_value)
      else
        []
      end

    cond do
      winners != [] ->
        hd(winners).id

      true ->
        non_boss = Enum.reject(legal, &(&1.is_boss or &1.is_a))
        pool = if non_boss == [], do: legal, else: non_boss
        pool |> Enum.min_by(& &1.suit_value) |> Map.get(:id)
    end
  end
end
