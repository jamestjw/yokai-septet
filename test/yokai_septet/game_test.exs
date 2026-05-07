defmodule YokaiSeptet.GameTest do
  use ExUnit.Case, async: true

  alias YokaiSeptet.{Cards, Game}

  # Build a deterministic state for a small unit assertion. We avoid relying on
  # Game.start_round/1's shuffle by constructing the state directly.
  defp boss(suit) do
    Cards.build_deck() |> Enum.find(&(&1.suit == suit and &1.is_boss))
  end

  defp non_boss(suit, rank) do
    Cards.build_deck() |> Enum.find(&(&1.suit == suit and &1.rank == rank))
  end

  # ----- Step 1 (greed loss boss redistribution) -----

  test "4p greed loss redistributes unplayed bosses to the winning team" do
    # Team 0 will be the greed loser (took 7 tricks but only 3 bosses).
    # Team 1 (winner) had 0 captured bosses but the 4 still-unplayed bosses
    # in players' hands should all transfer to them and score.
    base = Game.new("4p")

    captured_bosses_team0 = [boss(:wind), boss(:earth), boss(:mist)]
    unplayed_in_hand_team1 = [boss(:river), boss(:forest), boss(:flame), boss(:snow)]

    state = %{
      base
      | mode: "4p",
        num_p: 4,
        trump_card: non_boss(:earth, 2),
        trump_suit: :earth,
        # Team 0 took 7 tricks (player 0 alone for simplicity).
        tricks_won: [7, 0, 0, 0],
        bosses_by_player: [captured_bosses_team0, [], [], []],
        # The winning team's hand has the four unplayed bosses.
        hands: [[], unplayed_in_hand_team1, [], []],
        last_trick_info: %{winner_idx: 0, cards: [], lead_suit: :wind},
        phase: :round_end
    }

    state = invoke_score_round(state)

    log = hd(state.round_log)
    assert log.winner_team == 1
    assert log.reason =~ "greed"
    # Earth's boss is the trump-suit boss and is discarded; the rest score.
    # river=1, forest=2, flame=2, snow=3, wind boss = 0 (already in team 0's pile)
    # Team 1's redistributed bosses: river+forest+flame+snow = 1+2+2+3 = 8.
    # But Earth boss was on team 0, not redistributed. Team 0 had captured wind+earth+mist
    # — all on the loser, none transferred. Only unplayed (in hands) move.
    # So team 1 gets river(1) + forest(2) + flame(2) + snow(3) = 8 pts.
    assert log.points_awarded[1] == 8
    # Confirm redistributed_bosses contains the four unplayed bosses.
    assert length(log.redistributed_bosses) == 4
  end

  # ----- Step 1 + 2 (3p scoring uses solid+outline pips) -----

  test "3p scoring counts pts_solid + pts_outline" do
    base = Game.new("3p")

    # Player 0 captured all 7 bosses to win the round.
    all_bosses = for s <- Cards.suits(), do: boss(s.id)

    state = %{
      base
      | mode: "3p",
        num_p: 3,
        trump_card: non_boss(:wind, 2),
        trump_suit: :wind,
        tricks_won: [3, 0, 0],
        bosses_by_player: [all_bosses, [], []],
        hands: [[], [], []],
        last_trick_info: %{winner_idx: 0, cards: [], lead_suit: :wind},
        phase: :round_end
    }

    state = invoke_score_round(state)

    log = hd(state.round_log)
    assert log.winner_team == 0

    # Drop Wind boss (trump suit). Remaining bosses' (solid + outline) pip totals:
    #   earth: 0+1=1, mist: 1+1=2, river: 1+2=3, forest: 2+2=4, flame: 2+3=5, snow: 3+3=6
    # Total = 21.
    assert log.points_awarded[0] == 21
  end

  test "4p scoring counts only pts_solid" do
    base = Game.new("4p")
    all_bosses = for s <- Cards.suits(), do: boss(s.id)

    state = %{
      base
      | mode: "4p",
        num_p: 4,
        trump_card: non_boss(:wind, 2),
        trump_suit: :wind,
        tricks_won: [4, 0, 0, 0],
        bosses_by_player: [all_bosses, [], [], []],
        hands: [[], [], [], []],
        last_trick_info: %{winner_idx: 0, cards: [], lead_suit: :wind},
        phase: :round_end
    }

    state = invoke_score_round(state)
    log = hd(state.round_log)
    # 4p ignores outline pips. Drop wind (trump): earth=0, mist=1, river=1,
    # forest=2, flame=2, snow=3 → 9 points.
    assert log.points_awarded[0] == 9
  end

  test "3p game tie after greed loss goes to player left of trick loser" do
    base = Game.new("3p")

    state = %{
      base
      | mode: "3p",
        num_p: 3,
        trump_card: non_boss(:wind, 2),
        trump_suit: :wind,
        tricks_won: [7, 0, 0],
        bosses_by_player: [[boss(:wind), boss(:earth)], [], []],
        hands: [[], [], []],
        scores: %{0 => 0, 1 => 4, 2 => 4},
        last_trick_info: %{winner_idx: 0, cards: [], lead_suit: :wind},
        phase: :round_end
    }

    state = invoke_score_round(state)

    assert state.phase == :game_end
    assert state.scores[1] == 7
    assert state.scores[2] == 7
    assert state.game_winner_team == 1
  end

  # ----- Step 2 (lead-player carry-over across rounds) -----

  test "lead_player_idx is updated to trick winner during resolve_trick" do
    base = Game.new("4p")
    deck = Cards.build_deck()
    # Two cards forming a one-card trick (we'll only test the carry-over field).
    cards = [
      %{player_idx: 0, card: Enum.find(deck, &(&1.suit == :forest and &1.rank == 5))},
      %{player_idx: 1, card: Enum.find(deck, &(&1.suit == :forest and &1.rank == 9))},
      %{player_idx: 2, card: Enum.find(deck, &(&1.suit == :forest and &1.rank == 7))},
      %{player_idx: 3, card: Enum.find(deck, &(&1.suit == :forest and &1.rank == 6))}
    ]

    state = %{
      base
      | num_p: 4,
        trump_card: Enum.find(deck, &(&1.suit == :wind and &1.rank == 2)),
        trump_suit: :wind,
        tricks_won: [0, 0, 0, 0],
        bosses_by_player: [[], [], [], []],
        hands: [[], [], [], []],
        trick: cards,
        lead_suit: :forest,
        phase: :trick_end,
        last_trick_info: %{
          winner_idx: 1,
          cards: Enum.map(cards, & &1.card),
          lead_suit: :forest
        }
    }

    state = Game.resolve_trick(state)
    assert state.lead_player_idx == 1
  end

  # ----- Step 4a (2p straw-pile state) -----

  test "2p start_round produces straw + hand + trump and enters :swapping" do
    state = Game.new("2p") |> Game.start_round()

    assert state.phase == :swapping
    assert length(state.hands) == 2
    assert Enum.all?(state.hands, &(length(&1) == 11))
    assert length(state.straw) == 2

    Enum.each(state.straw, fn slots ->
      assert length(slots) == 7
      face_up = Enum.count(slots, &(&1.face_up != nil))
      face_down = Enum.count(slots, &(&1.face_down != nil))
      assert face_up == 6
      assert face_down == 7
    end)

    # Trump card is the 49th, distinct from any straw or hand card.
    assert state.trump_card != nil

    all_dealt =
      List.flatten(state.hands) ++
        Enum.flat_map(state.straw, fn slots ->
          Enum.flat_map(slots, fn s -> [s.face_down, s.face_up] end)
        end) ++
        [state.trump_card]

    all_dealt = Enum.reject(all_dealt, &is_nil/1)
    ids = Enum.map(all_dealt, & &1.id) |> Enum.uniq()
    assert length(ids) == 49
  end

  test "2p effective_hand combines actual hand and face-up straw cards" do
    state = Game.new("2p") |> Game.start_round()

    eff0 = Game.effective_hand(state, 0)
    actual0 = Enum.at(state.hands, 0)

    fu0 =
      Enum.at(state.straw, 0)
      |> Enum.map(& &1.face_up)
      |> Enum.reject(&is_nil/1)

    assert length(eff0) == length(actual0) + length(fu0)
    # All 6 face-ups present.
    assert length(fu0) == 6
  end

  test "2p greed redistribution includes face-down straw bosses" do
    # Construct a 2p state where player 0 hits 13 tricks with only 3 bosses,
    # and player 1 has the missing boss face-down inside their straw pile.
    base = Game.new("2p")

    captured_p0 = [boss(:wind), boss(:earth), boss(:mist)]
    # Player 1's straw has the Snow boss face-down on slot 0.
    snow_boss = boss(:snow)
    forest_card = non_boss(:forest, 5)
    river_card = non_boss(:river, 4)

    p1_slots = [
      %{face_down: snow_boss, face_up: forest_card},
      %{face_down: river_card, face_up: nil} | List.duplicate(%{face_down: nil, face_up: nil}, 5)
    ]

    state = %{
      base
      | mode: "2p",
        num_p: 2,
        trump_card: non_boss(:earth, 2),
        trump_suit: :earth,
        tricks_won: [13, 0],
        bosses_by_player: [captured_p0, []],
        hands: [[], [boss(:river), boss(:forest), boss(:flame)]],
        straw: [List.duplicate(%{face_down: nil, face_up: nil}, 7), p1_slots],
        last_trick_info: %{winner_idx: 0, cards: [], lead_suit: :wind},
        phase: :round_end
    }

    state = invoke_score_round(state)
    log = hd(state.round_log)
    assert log.winner_team == 1
    # Redistributed bosses: river, forest, flame (in p1 hand) + snow (face-down in straw).
    redistributed_suits = Enum.map(log.redistributed_bosses, & &1.suit) |> Enum.sort()
    assert redistributed_suits == [:flame, :forest, :river, :snow]

    # Score: drop trump-suit (earth) boss; player 0's earth boss isn't transferred.
    # Team 1's bosses for scoring: river(1) + forest(2) + flame(2) + snow(3) = 8.
    assert log.points_awarded[1] == 8
  end

  # ----- helpers -----

  # The Game.score_round/1 function is private; we exercise it indirectly by
  # calling Game.resolve_trick/1 on a phase-prepared state. But our test
  # fixtures pre-set tricks_won/bosses_by_player at the round-end thresholds
  # without going through resolve_trick. To trigger scoring directly, we set
  # an empty trick info and let resolve_trick re-enter score_round via the
  # round-end check. To avoid mutating tricks_won we call resolve_trick with
  # a synthetic last_trick_info that won't add anything.
  defp invoke_score_round(state) do
    # Minimal trick info: a one-card "trick" with player 0 and a non-boss
    # which won't change boss counts. Set tricks_won so adding one more keeps
    # the round-end thresholds true.
    deck = Cards.build_deck()
    dummy = Enum.find(deck, &(not &1.is_boss))

    # Reduce tricks_won[0] by 1 so resolve_trick adds 1 back, putting us at
    # the original test value when score_round runs.
    [t0 | _] = state.tricks_won
    new_tricks = List.replace_at(state.tricks_won, 0, max(t0 - 1, 0))
    # Adjust last_trick_info so winner=0 and no bosses get added.
    info = %{winner_idx: 0, cards: [dummy], lead_suit: dummy.suit}

    %{state | tricks_won: new_tricks, last_trick_info: info, phase: :trick_end}
    |> Game.resolve_trick()
  end
end
