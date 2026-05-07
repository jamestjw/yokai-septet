defmodule YokaiSeptet.Cards do
  @moduledoc """
  Yokai Septet card system — Pocket Edition rules-accurate.

  7 suits, 7 cards each = 49 total. Each suit's rank range differs.
  The strongest card of each suit is its Boss Yokai. Wind contains the
  special "A" card — the most powerful card in the game.
  """

  @suits [
    %{id: :wind,   kanji: "風", name: "Wind",   strength: 1, color: "#a89878", ranks: ["A", 1, 2, 3, 4, 5, 6],   boss_pts4: 0, boss_pts3_extra: 0, tagline: "Karasu-tengu of the cold gust"},
    %{id: :earth,  kanji: "土", name: "Earth",  strength: 2, color: "#b8893a", ranks: [1, 2, 3, 4, 5, 6, 7],     boss_pts4: 0, boss_pts3_extra: 1, tagline: "Tsuchigumo of the deep cave"},
    %{id: :mist,   kanji: "霧", name: "Mist",   strength: 3, color: "#7a8b94", ranks: [2, 3, 4, 5, 6, 7, 8],     boss_pts4: 1, boss_pts3_extra: 1, tagline: "Yurei of the shrouded lantern"},
    %{id: :river,  kanji: "川", name: "River",  strength: 4, color: "#1f3a5f", ranks: [3, 4, 5, 6, 7, 8, 9],     boss_pts4: 1, boss_pts3_extra: 2, tagline: "Kappa of the still pond"},
    %{id: :forest, kanji: "森", name: "Forest", strength: 5, color: "#2d5d3a", ranks: [4, 5, 6, 7, 8, 9, 10],    boss_pts4: 2, boss_pts3_extra: 2, tagline: "Kodama of the old grove"},
    %{id: :flame,  kanji: "炎", name: "Flame",  strength: 6, color: "#c8483c", ranks: [5, 6, 7, 8, 9, 10, 11],   boss_pts4: 2, boss_pts3_extra: 3, tagline: "Oni of the burning forge"},
    %{id: :snow,   kanji: "雪", name: "Snow",   strength: 7, color: "#5d3a6b", ranks: [6, 7, 8, 9, 10, 11, 12],  boss_pts4: 3, boss_pts3_extra: 3, tagline: "Yuki-onna of the white peak"}
  ]

  @suit_by_id Map.new(@suits, &{&1.id, &1})

  def suits, do: @suits
  def suit(id) when is_atom(id), do: Map.fetch!(@suit_by_id, id)

  @doc "Build the full 49-card deck."
  def build_deck do
    {cards, _} =
      for suit <- @suits, rank <- suit.ranks, reduce: {[], 0} do
        {acc, id} ->
          last = List.last(suit.ranks)
          is_boss = rank == last
          is_a = rank == "A"

          card = %{
            id: id,
            suit: suit.id,
            rank: rank,
            suit_value: if(is_a, do: -1, else: rank),
            is_boss: is_boss,
            is_a: is_a,
            pts_solid: if(is_boss, do: suit.boss_pts4, else: 0),
            pts_outline: if(is_boss, do: suit.boss_pts3_extra, else: 0)
          }

          {[card | acc], id + 1}
      end

    Enum.reverse(cards)
  end

  @doc "Display label for a rank."
  def rank_label("A"), do: "A"
  def rank_label(n), do: Integer.to_string(n)

  @doc "Sort a hand by suit order then descending rank (A last within suit)."
  def sort_hand(hand) do
    order = Enum.with_index(@suits) |> Map.new(fn {s, i} -> {s.id, i} end)

    Enum.sort_by(hand, fn c ->
      {Map.fetch!(order, c.suit), if(c.is_a, do: 1, else: 0), -c.suit_value}
    end)
  end

  @doc "Returns ids of cards from `hand` legal to play given lead suit."
  def playable_cards(hand, nil), do: Enum.map(hand, & &1.id)

  def playable_cards(hand, lead_suit) do
    has_lead = Enum.any?(hand, &(&1.suit == lead_suit))

    if has_lead do
      hand |> Enum.filter(&(&1.suit == lead_suit)) |> Enum.map(& &1.id)
    else
      Enum.map(hand, & &1.id)
    end
  end

  @doc """
  Resolve a trick. trick is list of %{player_idx, card}. Returns winning player_idx.

  A always wins; otherwise highest trump; otherwise highest of lead suit.
  """
  def trick_winner(trick, lead_suit, trump_suit) do
    a_play = Enum.find(trick, & &1.card.is_a)

    cond do
      a_play ->
        a_play.player_idx

      true ->
        trumps = Enum.filter(trick, &(&1.card.suit == trump_suit))

        cond do
          trumps != [] ->
            Enum.max_by(trumps, & &1.card.suit_value).player_idx

          true ->
            trick
            |> Enum.filter(&(&1.card.suit == lead_suit))
            |> Enum.max_by(& &1.card.suit_value)
            |> Map.get(:player_idx)
        end
    end
  end
end
