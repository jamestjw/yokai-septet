defmodule YokaiSeptet.Game do
  @moduledoc """
  Yokai Septet game state and transitions. Pure functions over a state map;
  the LiveView holds the state and schedules timed transitions
  (AI plays, trick resolution) as messages to itself.

  Rule references in this module follow the Pocket Edition rules. Notable
  details that differ from a naive trick-taker:

    * Greed loss: when a team/player exceeds the trick limit, the *opposing*
      side wins, and they collect every still-unplayed Boss Yokai (including
      ones in straw piles for the 2p game) for scoring purposes.
    * 3p scoring counts both solid (★) and outline (⚪) pip values.
    * The "Lead Player card" persists across rounds in 4p/3p — the winner
      of the last trick of round N leads round N+1's first trick. 2p uses a
      dealer-alternation rule instead.
    * 2p uses a straw pile mechanic: 7 face-down + 6 face-up cards per
      player, hand of 11, mandatory discard 1 (non-boss), optional boss swap.
  """

  alias YokaiSeptet.Cards

  @type phase ::
          :idle | :passing | :swapping | :playing | :trick_end | :round_end | :game_end

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
      round_log: [],
      # Persistent leader (4p/3p): holder of the "Lead Player card".
      # nil means round-1 (use A-holder rule). Updates after every trick.
      lead_player_idx: nil,
      # 2p: dealer alternates each round; dealer leads the first trick.
      dealer_idx: 0,
      # 2p straw pile, per player:
      #   %{downs: [%{card: card | nil, revealed?: boolean}], ups: [card | nil]}
      # A face-up card at index i covers face-down cards i and i + 1.
      # nil for non-2p modes.
      straw: nil,
      # 2p: discarded card per player (set aside; not playable).
      discard: [],
      # 2p :swapping state, keyed by player index.
      setup_discards: %{},
      setup_swap_decisions: %{},
      setup_confirmed: %{},
      game_winner_team: nil
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

  # =========================================================================
  # Round start
  # =========================================================================

  @doc "Deal a fresh round; enter the appropriate setup phase."
  def start_round(%{mode: "2p"} = state), do: start_round_2p(state)
  def start_round(state), do: start_round_team(state)

  defp start_round_team(state) do
    {hands, trump_card, trump_suit} = deal_team(state.num_p)
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

    %{state | phase: :passing}
  end

  defp deal_team(num_players) do
    {trump, deck} =
      Cards.build_deck()
      |> Enum.shuffle()
      |> draw_non_boss_trump()

    per_player =
      case num_players do
        4 -> 12
        3 -> 16
      end

    {hands, _rest} =
      Enum.reduce(0..(num_players - 1), {[], deck}, fn _, {acc, remaining} ->
        {hand, tail} = Enum.split(remaining, per_player)
        {[hand | acc], tail}
      end)

    {Enum.reverse(hands), trump, trump.suit}
  end

  defp draw_non_boss_trump(deck) do
    trump = deck |> Enum.reject(& &1.is_boss) |> Enum.random()
    {trump, Enum.reject(deck, &(&1.id == trump.id))}
  end

  # ----- 2p deal -----

  defp start_round_2p(state) do
    {trump_card, deck} =
      Cards.build_deck()
      |> Enum.shuffle()
      |> draw_non_boss_trump()

    # Per player: 7 face-down + 6 face-up + 11 hand = 24. Two players = 48.
    {p0_fd, deck} = Enum.split(deck, 7)
    {p0_fu, deck} = Enum.split(deck, 6)
    {p1_fd, deck} = Enum.split(deck, 7)
    {p1_fu, deck} = Enum.split(deck, 6)
    {p0_hand, p1_hand} = Enum.split(deck, 11)

    straw0 = build_straw(p0_fd, p0_fu)
    straw1 = build_straw(p1_fd, p1_fu)

    %{
      state
      | hands: [Cards.sort_hand(p0_hand), Cards.sort_hand(p1_hand)],
        straw: [straw0, straw1],
        trump_card: trump_card,
        trump_suit: trump_card.suit,
        tricks_won: [0, 0],
        bosses_by_player: [[], []],
        trick: [],
        lead_suit: nil,
        last_trick_info: nil,
        round_log: [],
        discard: [],
        setup_discards: %{},
        setup_swap_decisions: %{},
        setup_confirmed: %{},
        phase: :swapping
    }
  end

  # 7 face-down cards with 6 face-up cards bridging adjacent pairs.
  defp build_straw(face_downs, face_ups) do
    %{
      downs: Enum.map(face_downs, &%{card: &1, revealed?: false}),
      ups: face_ups
    }
  end

  # =========================================================================
  # Lead-player rules
  # =========================================================================

  # Round 1 (no carry-over yet): A holder leads. If the A is the face-up
  # trump card, the rules call for the holder of the highest card overall
  # (Snow's 13) to lead instead.
  defp find_lead_round1(hands, trump_card) do
    if trump_card && trump_card.is_a do
      Enum.find_index(hands, fn h ->
        Enum.any?(h, &(&1.suit == :snow and &1.rank == 13))
      end) || 0
    else
      Enum.find_index(hands, fn h -> Enum.any?(h, & &1.is_a) end) || 0
    end
  end

  # =========================================================================
  # 4p/3p Passing phase
  # =========================================================================

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
    pp =
      Enum.reduce(0..(state.num_p - 1), state.pending_passes, fn i, acc ->
        if not Map.has_key?(acc, i) and not Enum.at(state.players, i).is_human do
          Map.put(acc, i, ai_pick_pass(Enum.at(state.hands, i), 3))
        else
          acc
        end
      end)

    %{state | pending_passes: pp}
  end

  @doc "Multiplayer: set a single seat's pending pass directly (skips the human-selection UI)."
  def set_pending_pass(state, seat_idx, card_ids) when is_list(card_ids) do
    if length(card_ids) == 3 do
      %{state | pending_passes: Map.put(state.pending_passes, seat_idx, card_ids)}
    else
      state
    end
  end

  @doc "Multiplayer: all seats already have pending_passes — apply the swap and start play."
  def finalize_passes(state) do
    if map_size(state.pending_passes) != state.num_p do
      state
    else
      apply_pending_passes(state)
    end
  end

  def confirm_pass(state) do
    if length(state.human_pass_selection) != 3 do
      state
    else
      human_idx = Enum.find_index(state.players, & &1.is_human)

      state = %{
        state
        | pending_passes: Map.put(state.pending_passes, human_idx, state.human_pass_selection)
      }

      apply_pending_passes(state)
    end
  end

  defp apply_pending_passes(state) do
    new_hands =
      Enum.reduce(0..(state.num_p - 1), state.hands, fn from, hands ->
        ids = Map.get(state.pending_passes, from, [])
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
    lead = pick_round_leader(state, sorted)

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

  # Choose the leader for the first trick of a round.
  #   Round 1 (lead_player_idx == nil): A-holder rule (with Wind-trump fallback).
  #   Round 2+ (carry-over): the winner of the last trick of the previous round.
  defp pick_round_leader(state, hands) do
    if state.lead_player_idx == nil do
      find_lead_round1(hands, state.trump_card)
    else
      state.lead_player_idx
    end
  end

  # =========================================================================
  # 2p swap-and-discard phase
  # =========================================================================

  @doc "Toggle the human's pending discard card during 2p :swapping."
  def set_pass_discard(state, card_id) do
    set_setup_discard(state, human_idx(state), card_id)
  end

  @doc "Set a player's pending discard card during 2p :swapping."
  def set_setup_discard(state, player_idx, card_id) do
    if valid_setup_discard?(state, player_idx, card_id) do
      %{state | setup_discards: Map.put(state.setup_discards, player_idx, card_id)}
    else
      state
    end
  end

  def valid_setup_discard?(state, player_idx, card_id) do
    state.hands
    |> Enum.at(player_idx, [])
    |> Enum.any?(&(&1.id == card_id and not &1.is_boss))
  end

  @doc "Choose which covered card a face-up Boss should swap with during 2p setup."
  def set_swap_choice(state, up_index, side) when side in [:left, :right] do
    set_setup_swap_choice(state, human_idx(state), up_index, side)
  end

  @doc "Choose which covered card a face-up Boss should swap with during 2p setup."
  def set_setup_swap_choice(state, player_idx, up_index, side) when side in [:left, :right] do
    if locked_boss_swap?(state, player_idx, up_index) do
      state
    else
      decision = %{side: side, keep: nil}

      swaps =
        Map.update(
          state.setup_swap_decisions,
          player_idx,
          %{up_index => decision},
          fn decisions ->
            Map.put(decisions, up_index, decision)
          end
        )

      %{state | setup_swap_decisions: swaps}
    end
  end

  def clear_swap_choice(state, up_index) do
    clear_setup_swap_choice(state, human_idx(state), up_index)
  end

  def clear_setup_swap_choice(state, player_idx, up_index) do
    if locked_boss_swap?(state, player_idx, up_index) do
      state
    else
      swaps =
        Map.update(state.setup_swap_decisions, player_idx, %{}, fn decisions ->
          Map.delete(decisions, up_index)
        end)

      %{state | setup_swap_decisions: swaps}
    end
  end

  @doc "Choose which Boss remains face-up when a 2p setup swap reveals a Boss under a Boss."
  def set_swap_keep(state, up_index, keep) when keep in [:up, :down] do
    set_setup_swap_keep(state, human_idx(state), up_index, keep)
  end

  @doc "Choose which Boss remains face-up when a 2p setup swap reveals a Boss under a Boss."
  def set_setup_swap_keep(state, player_idx, up_index, keep) when keep in [:up, :down] do
    decisions =
      Map.update(
        state.setup_swap_decisions,
        player_idx,
        %{up_index => %{side: :left, keep: keep}},
        fn decisions ->
          Map.update(decisions, up_index, %{side: :left, keep: keep}, fn decision ->
            Map.put(decision, :keep, keep)
          end)
        end
      )

    %{state | setup_swap_decisions: decisions}
  end

  @doc "Confirm 2p setup for the human; AI auto-decides; advance to :playing."
  def confirm_setup(state) do
    confirm_setup(state, human_idx(state))
  end

  @doc "Confirm 2p setup for a player; starts play once every player is confirmed."
  def confirm_setup(state, player_idx) do
    cond do
      state.mode != "2p" ->
        state

      Map.get(state.setup_discards, player_idx) == nil ->
        state

      true ->
        player_hand = Enum.at(state.hands, player_idx)
        discard_id = Map.fetch!(state.setup_discards, player_idx)
        discard = Enum.find(player_hand, &(&1.id == discard_id))

        cond do
          discard == nil -> state
          discard.is_boss -> state
          unresolved_boss_swap?(state, player_idx) -> state
          true -> maybe_confirm_setup(state, player_idx)
        end
    end
  end

  @doc "Auto-confirm 2p setup for an AI or disconnected player."
  def auto_setup(state, player_idx) do
    hand = Enum.at(state.hands, player_idx)
    discard = Enum.min_by(Enum.reject(hand, & &1.is_boss), & &1.suit_value)

    state
    |> set_setup_discard(player_idx, discard.id)
    |> confirm_setup(player_idx)
  end

  defp unresolved_boss_swap?(state, player_idx) do
    straw = Enum.at(state.straw, player_idx)
    decisions = Map.get(state.setup_swap_decisions, player_idx, %{})

    Enum.any?(decisions, fn {up_index, decision} ->
      up = Enum.at(straw.ups, up_index)
      down = swap_down_card(straw, up_index, decision.side)
      up && down && up.is_boss && down.is_boss && is_nil(decision.keep)
    end)
  end

  defp locked_boss_swap?(state, player_idx, up_index) do
    with %{side: side} <-
           state.setup_swap_decisions |> Map.get(player_idx, %{}) |> Map.get(up_index),
         straw when not is_nil(straw) <- Enum.at(state.straw || [], player_idx),
         down when not is_nil(down) <- swap_down_card(straw, up_index, side) do
      down.is_boss
    else
      _ -> false
    end
  end

  defp maybe_confirm_setup(state, player_idx) do
    state = %{state | setup_confirmed: Map.put(state.setup_confirmed, player_idx, true)}

    state =
      Enum.reduce(0..(state.num_p - 1), state, fn idx, acc ->
        player = Enum.at(acc.players, idx)

        if player.is_human or Map.get(acc.setup_confirmed, idx) do
          acc
        else
          auto_confirm_setup(acc, idx)
        end
      end)

    if map_size(state.setup_confirmed) == state.num_p do
      apply_confirmed_setup(state)
    else
      state
    end
  end

  defp auto_confirm_setup(state, player_idx) do
    hand = Enum.at(state.hands, player_idx)
    discard = Enum.min_by(Enum.reject(hand, & &1.is_boss), & &1.suit_value)

    state
    |> set_setup_discard(player_idx, discard.id)
    |> then(&%{&1 | setup_confirmed: Map.put(&1.setup_confirmed, player_idx, true)})
  end

  defp apply_confirmed_setup(state) do
    discards_by_idx =
      Enum.map(0..(state.num_p - 1), fn idx ->
        discard_id = Map.fetch!(state.setup_discards, idx)
        discard = Enum.find(Enum.at(state.hands, idx), &(&1.id == discard_id))
        {idx, discard}
      end)

    new_hands =
      Enum.reduce(discards_by_idx, state.hands, fn {idx, discard}, hands ->
        hand = Enum.at(hands, idx)
        List.replace_at(hands, idx, Cards.sort_hand(Enum.reject(hand, &(&1.id == discard.id))))
      end)

    new_straw =
      Enum.reduce(0..(state.num_p - 1), state.straw, fn idx, straws ->
        decisions = Map.get(state.setup_swap_decisions, idx, %{})
        List.replace_at(straws, idx, apply_swaps(Enum.at(straws, idx), decisions))
      end)

    discards =
      discards_by_idx
      |> Enum.sort_by(fn {idx, _discard} -> idx end)
      |> Enum.map(fn {_idx, discard} -> discard end)

    leader = pick_round_leader_2p(state, new_hands)

    %{
      state
      | hands: new_hands,
        straw: new_straw,
        discard: discards,
        setup_discards: %{},
        setup_swap_decisions: %{},
        setup_confirmed: %{},
        lead_idx: leader,
        current_idx: leader,
        phase: :playing
    }
  end

  defp human_idx(state), do: Enum.find_index(state.players, & &1.is_human) || 0

  defp apply_swaps(straw, decisions) do
    Enum.reduce(decisions, straw, fn {up_index, decision}, acc ->
      up = Enum.at(acc.ups, up_index)
      down_index = swap_down_index(up_index, decision.side)
      down = Enum.at(acc.downs, down_index)

      cond do
        up == nil ->
          acc

        down == nil or down.card == nil ->
          acc

        down.card.is_boss and decision.keep == :up ->
          acc

        true ->
          new_ups = List.replace_at(acc.ups, up_index, down.card)
          new_downs = List.replace_at(acc.downs, down_index, %{down | card: up, revealed?: false})
          %{acc | ups: new_ups, downs: new_downs}
      end
    end)
  end

  defp swap_down_card(straw, up_index, side) do
    case Enum.at(straw.downs, swap_down_index(up_index, side)) do
      %{card: card} -> card
      _ -> nil
    end
  end

  defp swap_down_index(up_index, :left), do: up_index
  defp swap_down_index(up_index, :right), do: up_index + 1

  # 2p: dealer leads round 1; in subsequent rounds the dealer alternates
  # (already flipped in next_round/1 before start_round/1 runs).
  defp pick_round_leader_2p(state, hands) do
    cond do
      state.lead_player_idx == nil and state.round == 1 ->
        # Round 1: dealer leads (rules say so for 2p).
        state.dealer_idx

      true ->
        # Subsequent rounds: dealer (already alternated in next_round).
        state.dealer_idx
    end
    |> tap_unused(hands)
  end

  defp tap_unused(value, _), do: value

  # =========================================================================
  # Playing
  # =========================================================================

  @doc """
  Apply a card play. Returns `{:continue | :trick_complete | :invalid, state}`.

  In 2p, `card_id` may identify a face-up or revealed face-down straw card.
  """
  def play_card(state, player_idx, card_id) do
    cond do
      state.phase != :playing ->
        {:invalid, state}

      state.current_idx != player_idx ->
        {:invalid, state}

      true ->
        eff_hand = effective_hand(state, player_idx)
        legal = Cards.playable_cards(eff_hand, state.lead_suit)

        case Enum.find(eff_hand, &(&1.id == card_id)) do
          nil ->
            {:invalid, state}

          card ->
            if card_id not in legal do
              {:invalid, state}
            else
              state = remove_played_card(state, player_idx, card)
              new_trick = state.trick ++ [%{player_idx: player_idx, card: card}]
              new_lead_suit = if state.trick == [], do: card.suit, else: state.lead_suit
              new_state = %{state | trick: new_trick, lead_suit: new_lead_suit}

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

  @doc """
  The cards a player may legally play: their actual hand plus any face-up
  cards in their straw pile (2p only).
  """
  def effective_hand(state, player_idx) do
    hand = Enum.at(state.hands, player_idx)

    case state.straw do
      nil ->
        hand

      straws ->
        face_ups =
          straw_cards(Enum.at(straws, player_idx))

        hand ++ face_ups
    end
  end

  defp straw_cards(straw) do
    face_ups = Enum.reject(straw.ups, &is_nil/1)

    revealed_downs =
      straw.downs
      |> Enum.filter(&(&1.revealed? and &1.card != nil))
      |> Enum.map(& &1.card)

    face_ups ++ revealed_downs
  end

  defp remove_played_card(state, player_idx, card) do
    hand = Enum.at(state.hands, player_idx)

    if Enum.any?(hand, &(&1.id == card.id)) do
      new_hand = Enum.reject(hand, &(&1.id == card.id))
      %{state | hands: List.replace_at(state.hands, player_idx, new_hand)}
    else
      # Must be a playable straw card.
      straws = state.straw
      straw = Enum.at(straws, player_idx)

      new_straw = remove_straw_card(straw, card)

      %{state | straw: List.replace_at(straws, player_idx, new_straw)}
    end
  end

  defp remove_straw_card(straw, card) do
    up_index = Enum.find_index(straw.ups, &(&1 && &1.id == card.id))

    if up_index do
      %{straw | ups: List.replace_at(straw.ups, up_index, nil)}
    else
      down_index =
        Enum.find_index(straw.downs, &((&1.revealed? and &1.card) && &1.card.id == card.id))

      if down_index do
        down = Enum.at(straw.downs, down_index)
        %{straw | downs: List.replace_at(straw.downs, down_index, %{down | card: nil})}
      else
        straw
      end
    end
  end

  @doc "Resolve a completed trick (called after the UI delay)."
  def resolve_trick(state) do
    info = state.last_trick_info
    winner = info.winner_idx
    bosses = Enum.filter(info.cards, & &1.is_boss)

    new_tricks = List.update_at(state.tricks_won, winner, &(&1 + 1))

    new_bosses =
      if bosses == [] do
        state.bosses_by_player
      else
        List.update_at(state.bosses_by_player, winner, &(&1 ++ bosses))
      end

    state =
      %{
        state
        | tricks_won: new_tricks,
          bosses_by_player: new_bosses,
          trick: [],
          lead_suit: nil,
          lead_idx: winner,
          current_idx: winner,
          # Lead Player card carry-over (4p/3p).
          lead_player_idx: winner
      }
      |> reveal_uncovered_straws()

    teams = team_totals(state)
    boss_threshold = boss_threshold(state.num_p)
    trick_limit = trick_limit(state.num_p)
    hands_empty = Enum.all?(state.hands, &(&1 == [])) and straw_empty?(state)

    reached = Enum.any?(teams, fn {_, v} -> v.bosses >= boss_threshold end)
    over_tricks = Enum.any?(teams, fn {_, v} -> v.tricks >= trick_limit end)

    if reached or over_tricks or hands_empty do
      score_round(%{state | phase: :round_end})
    else
      %{state | phase: :playing}
    end
  end

  # 2p: after each trick, reveal face-down cards that are no longer covered by
  # adjacent face-up straw cards. Revealed cards stay in the straw pile.
  defp reveal_uncovered_straws(%{straw: nil} = state), do: state

  defp reveal_uncovered_straws(state) do
    %{state | straw: Enum.map(state.straw, &reveal_straw/1)}
  end

  defp reveal_straw(straw) do
    downs =
      straw.downs
      |> Enum.with_index()
      |> Enum.map(fn {down, i} ->
        if down.card && uncovered?(straw, i) do
          %{down | revealed?: true}
        else
          down
        end
      end)

    %{straw | downs: downs}
  end

  defp uncovered?(straw, down_index) do
    left_clear? = down_index == 0 or Enum.at(straw.ups, down_index - 1) == nil
    right_clear? = down_index == 6 or Enum.at(straw.ups, down_index) == nil
    left_clear? and right_clear?
  end

  defp straw_empty?(%{straw: nil}), do: true

  defp straw_empty?(%{straw: straws}) do
    Enum.all?(straws, fn straw ->
      Enum.all?(straw.ups, &is_nil/1) and Enum.all?(straw.downs, &(&1.card == nil))
    end)
  end

  defp boss_threshold(4), do: 4
  defp boss_threshold(3), do: 3
  defp boss_threshold(_), do: 4

  defp trick_limit(4), do: 7
  defp trick_limit(3), do: 7
  defp trick_limit(_), do: 13

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

  # =========================================================================
  # Scoring
  # =========================================================================

  defp score_round(state) do
    teams = team_breakdown(state)

    boss_threshold = boss_threshold(state.num_p)
    trick_limit = trick_limit(state.num_p)

    reached = Enum.find(teams, fn {_, v} -> length(v.bosses) >= boss_threshold end)
    over_tricks = Enum.find(teams, fn {_, v} -> v.tricks >= trick_limit end)

    {winner_team, reason, greed?} =
      cond do
        reached ->
          {tid, _} = reached
          {tid, "Captured #{boss_threshold} Boss Yokai", false}

        over_tricks ->
          {losing_tid, _} = over_tricks
          winners = Enum.reject(teams, fn {tid, _} -> tid == losing_tid end)

          cond do
            length(winners) == 1 ->
              {tid, _} = hd(winners)
              {tid, "Opponents took #{trick_limit} tricks (greed)", true}

            true ->
              # 3p split: both non-loser players each score 3.
              {:split, "Opponents took #{trick_limit} tricks (greed)", true}
          end

        state.last_trick_info ->
          winner = state.last_trick_info.winner_idx
          {Enum.at(state.players, winner).team, "Took the final trick", false}

        true ->
          {nil, "", false}
      end

    # On greed loss, the winning team takes ALL still-unplayed Boss Yokai
    # (in any player's hand and, in 2p, anywhere in their straw piles) and
    # adds them to their captured pile for scoring.
    {teams, redistributed} =
      if greed? and is_integer(winner_team) do
        unplayed = unplayed_bosses(state)

        winner = Map.get(teams, winner_team)
        teams = Map.put(teams, winner_team, %{winner | bosses: winner.bosses ++ unplayed})
        {teams, unplayed}
      else
        {teams, []}
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
          pts = Enum.reduce(won, 0, &(&2 + boss_points(&1, state.mode)))
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
      trump_suit: state.trump_suit,
      redistributed_bosses: redistributed
    }

    state = %{state | scores: new_scores, round_log: [log]}

    if Enum.any?(new_scores, fn {_, v} -> v >= 7 end) do
      %{
        state
        | phase: :game_end,
          game_winner_team: game_winner_team(state, new_scores, over_tricks)
      }
    else
      state
    end
  end

  defp game_winner_team(%{mode: "3p"} = state, scores, over_tricks) do
    top_score = scores |> Map.values() |> Enum.max()
    leaders = scores |> Enum.filter(fn {_, v} -> v == top_score end) |> Enum.map(&elem(&1, 0))

    cond do
      length(leaders) == 1 ->
        hd(leaders)

      over_tricks ->
        {trick_loser, _} = over_tricks
        left_of_loser = rem(trick_loser + 1, state.num_p)

        if left_of_loser in leaders do
          left_of_loser
        else
          hd(leaders)
        end

      true ->
        hd(leaders)
    end
  end

  defp game_winner_team(_state, scores, _over_tricks) do
    scores
    |> Enum.max_by(fn {_, v} -> v end)
    |> elem(0)
  end

  # Per-card scoring: solid pips always count; outline pips count only in 3p.
  defp boss_points(card, "3p"), do: card.pts_solid + card.pts_outline
  defp boss_points(card, _), do: card.pts_solid

  # All Boss Yokai still in play: every player's hand plus any straw cards
  # (face-up or face-down) in 2p.
  defp unplayed_bosses(state) do
    from_hands =
      state.hands
      |> List.flatten()
      |> Enum.filter(& &1.is_boss)

    from_straw =
      case state.straw do
        nil ->
          []

        straws ->
          Enum.flat_map(straws, fn straw ->
            straw.ups ++ Enum.map(straw.downs, & &1.card)
          end)
          |> Enum.reject(&is_nil/1)
          |> Enum.filter(& &1.is_boss)
      end

    from_hands ++ from_straw
  end

  # =========================================================================
  # Round / game progression
  # =========================================================================

  def next_round(state) do
    state =
      if state.mode == "2p" do
        # Alternate dealer.
        %{state | dealer_idx: rem(state.dealer_idx + 1, 2)}
      else
        state
      end

    %{state | round: state.round + 1} |> start_round()
  end

  # =========================================================================
  # AI
  # =========================================================================

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
