defmodule YokaiSeptetWeb.TableLive do
  @moduledoc """
  In-game table view. Holds the full %YokaiSeptet.Game{} state in assigns and
  drives the loop with `Process.send_after/3` for the AI play delay (750 ms)
  and post-trick reveal (1400 ms) — mirroring the original's setTimeout calls.
  """
  use YokaiSeptetWeb, :live_view

  import YokaiSeptetWeb.CardComponents
  alias YokaiSeptet.{Cards, Game}

  @ai_delay 750
  @trick_delay 1400

  @impl true
  def mount(%{"mode" => mode}, _session, socket) do
    mode = if mode in ["4p", "3p", "2p"], do: mode, else: "4p"

    socket =
      socket
      |> assign(game: Game.new(mode) |> Game.start_round())
      |> maybe_schedule_passing()
      |> maybe_schedule_ai()

    {:ok, socket, layout: false}
  end

  # ---------- events ----------

  @impl true
  def handle_event("nav_home", _, socket), do: {:noreply, push_navigate(socket, to: ~p"/")}

  def handle_event("play_card", %{"id" => id}, socket) do
    card_id = String.to_integer(id)
    g = socket.assigns.game
    human = human_idx(g)

    case Game.play_card(g, human, card_id) do
      {:invalid, _} ->
        {:noreply, socket}

      {:continue, g2} ->
        {:noreply, socket |> assign(game: g2) |> maybe_schedule_ai()}

      {:trick_complete, g2} ->
        Process.send_after(self(), :resolve_trick, @trick_delay)
        {:noreply, assign(socket, game: g2)}
    end
  end

  def handle_event("toggle_pass", %{"id" => id}, socket) do
    card_id = String.to_integer(id)
    {:noreply, assign(socket, game: Game.toggle_pass_card(socket.assigns.game, card_id))}
  end

  def handle_event("confirm_pass", _params, socket) do
    g = Game.confirm_pass(socket.assigns.game)
    {:noreply, socket |> assign(game: g) |> maybe_schedule_ai()}
  end

  def handle_event("next_round", _params, socket) do
    g = Game.next_round(socket.assigns.game)

    {:noreply,
     socket
     |> assign(game: g)
     |> maybe_schedule_passing()
     |> maybe_schedule_ai()}
  end

  # ---------- info messages ----------

  @impl true
  def handle_info(:fill_ai_passes, socket) do
    {:noreply, assign(socket, game: Game.fill_ai_passes(socket.assigns.game))}
  end

  def handle_info(:resolve_trick, socket) do
    g = Game.resolve_trick(socket.assigns.game)
    {:noreply, socket |> assign(game: g) |> maybe_schedule_ai()}
  end

  def handle_info(:ai_play, socket) do
    g = socket.assigns.game

    if g.phase == :playing do
      cur = Enum.at(g.players, g.current_idx)

      if not cur.is_human do
        card_id =
          Game.ai_pick(
            Enum.at(g.hands, g.current_idx),
            g.lead_suit,
            g.trump_suit,
            g.trick
          )

        case Game.play_card(g, g.current_idx, card_id) do
          {:invalid, _} ->
            {:noreply, socket}

          {:continue, g2} ->
            {:noreply, socket |> assign(game: g2) |> maybe_schedule_ai()}

          {:trick_complete, g2} ->
            Process.send_after(self(), :resolve_trick, @trick_delay)
            {:noreply, assign(socket, game: g2)}
        end
      else
        {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  # ---------- helpers ----------

  defp maybe_schedule_ai(socket) do
    g = socket.assigns.game

    if g.phase == :playing do
      cur = Enum.at(g.players, g.current_idx)

      if not cur.is_human do
        Process.send_after(self(), :ai_play, @ai_delay)
      end
    end

    socket
  end

  defp maybe_schedule_passing(socket) do
    if socket.assigns.game.phase == :passing do
      send(self(), :fill_ai_passes)
    end

    socket
  end

  defp human_idx(g), do: Enum.find_index(g.players, & &1.is_human)

  # ---------- render ----------

  @impl true
  def render(assigns) do
    g = assigns.game
    h_idx = human_idx(g)
    my_hand = Enum.at(g.hands, h_idx)
    my_legal = Cards.playable_cards(my_hand, g.lead_suit)
    is_my_turn = g.current_idx == h_idx and g.phase == :playing

    seat_positions = seat_positions(g.num_p)
    seat_order = seat_order(g.num_p, h_idx, seat_positions)
    trick_card_positions = trick_card_positions(seat_positions)

    assigns =
      assign(assigns,
        h_idx: h_idx,
        my_hand: my_hand,
        my_legal: my_legal,
        is_my_turn: is_my_turn,
        seat_positions: seat_positions,
        seat_order: seat_order,
        trick_card_positions: trick_card_positions
      )

    ~H"""
    <div class="tatami" style="min-height: 100vh; display: flex; flex-direction: column; color: var(--washi);">
      <header style="display: flex; align-items: center; justify-content: space-between; padding: 16px 32px; border-bottom: 1px solid rgba(244, 236, 216, 0.08);">
        <button phx-click="nav_home" style="background: none; border: none; cursor: pointer; color: var(--washi); display: flex; align-items: center; gap: 12px; font-family: var(--serif); font-size: 14px; opacity: 0.85;">
          <span>←</span>
          <span class="kanji">退室</span>
          <span style="letter-spacing: 0.16em; text-transform: uppercase; font-size: 11px; font-family: var(--sans);">Leave Table</span>
        </button>

        <div style="display: flex; align-items: center; gap: 24px; font-family: var(--sans); font-size: 12px; letter-spacing: 0.2em; text-transform: uppercase; color: rgba(244, 236, 216, 0.7);">
          <span>Round {@game.round}</span>
          <span style="width: 1px; height: 14px; background: rgba(244,236,216,0.2);"></span>
          <span>Trick {trick_count(@game)} / {round_max_tricks(@game.num_p)}</span>
        </div>

        <.score_pill players={@game.players} scores={@game.scores} />
      </header>

      <div style="flex: 1; position: relative; padding: 24px 32px 0;">
        <div style="position: absolute; inset: 16px 32px 0; border-radius: 50%/40%; background: radial-gradient(ellipse at center, #2c4a30 0%, #1f3324 75%); box-shadow: inset 0 0 80px rgba(0,0,0,0.5), 0 0 0 1px rgba(212,175,55,0.15);"></div>

        <div style="position: relative; width: 100%; height: 100%; min-height: 600px;">
          <%= for {p_idx, seat_i} <- Enum.with_index(@seat_order) do %>
            <% pos = Enum.at(@seat_positions, seat_i) %>
            <%= if pos.anchor != :bottom do %>
              <.seat
                player={Enum.at(@game.players, p_idx)}
                hand={Enum.at(@game.hands, p_idx)}
                position={pos}
                is_current={@game.current_idx == p_idx and @game.phase == :playing}
                tricks={Enum.at(@game.tricks_won, p_idx)}
                bosses={Enum.at(@game.bosses_by_player, p_idx)}
                is_lead={@game.lead_idx == p_idx}
              />
            <% end %>
          <% end %>

          <%= if @game.trump_card do %>
            <div style="position: absolute; left: 50%; top: 50%; transform: translate(-50%, -50%); display: flex; align-items: center; gap: 24px;">
              <div style="display: flex; flex-direction: column; align-items: center; gap: 8px; opacity: 0.85;">
                <div class="eyebrow" style="color: rgba(244,236,216,0.55);">切札 Trump</div>
                <div style="transform: rotate(-4deg); filter: drop-shadow(0 6px 12px rgba(0,0,0,0.45));">
                  <.yokai_card suit={@game.trump_card.suit} rank={@game.trump_card.rank} is_a={@game.trump_card.is_a} width={68} />
                </div>
              </div>
            </div>
          <% end %>

          <%= for {t, i} <- Enum.with_index(@game.trick) do %>
            <% seat_i = Enum.find_index(@seat_order, &(&1 == t.player_idx)) %>
            <% tp = Enum.at(@trick_card_positions, seat_i) %>
            <% rot = rem(seat_i * 13, 17) - 8 %>
            <div
              class="draw-in"
              style={
                "position: absolute;" <>
                " left: #{tp.x * 100}%; top: #{tp.y * 100}%;" <>
                " transform: translate(-50%, -50%) rotate(#{rot}deg);" <>
                " filter: drop-shadow(0 8px 16px rgba(0,0,0,0.5));" <>
                " z-index: #{10 + i};"
              }
            >
              <.yokai_card suit={t.card.suit} rank={t.card.rank} is_a={t.card.is_a} width={92} />
            </div>
          <% end %>

          <%= if @game.phase == :trick_end and @game.last_trick_info do %>
            <% seat_i = Enum.find_index(@seat_order, &(&1 == @game.last_trick_info.winner_idx)) %>
            <% pos = Enum.at(@seat_positions, seat_i) %>
            <div class="fade-in" style={
              "position: absolute;" <>
              " left: #{pos.x * 100}%; top: #{pos.y * 100}%;" <>
              " transform: translate(-50%, -50%);" <>
              " background: var(--gold-bright); color: var(--sumi);" <>
              " padding: 8px 16px;" <>
              " font-family: var(--kanji); font-size: 14px; letter-spacing: 0.2em; font-weight: 600;" <>
              " box-shadow: 0 0 0 1px rgba(0,0,0,0.2) inset, 0 4px 16px rgba(0,0,0,0.4);" <>
              " z-index: 20;"
            }>
              勝 · Won the trick
            </div>
          <% end %>
        </div>
      </div>

      <%= if @game.phase == :passing do %>
        <.pass_panel game={@game} my_hand={@my_hand} />
      <% else %>
        <.player_hand
          hand={@my_hand}
          legal={@my_legal}
          is_my_turn={@is_my_turn}
          player_name={Enum.at(@game.players, @h_idx).name}
          tricks={Enum.at(@game.tricks_won, @h_idx)}
          bosses={Enum.at(@game.bosses_by_player, @h_idx)}
          is_lead={@game.lead_idx == @h_idx}
        />
      <% end %>

      <%= if @game.phase == :round_end do %>
        <.round_summary game={@game} />
      <% end %>

      <%= if @game.phase == :game_end do %>
        <.game_over game={@game} />
      <% end %>
    </div>
    """
  end

  # ---------- layout helpers ----------

  defp seat_positions(4),
    do: [
      %{x: 0.5, y: 0.08, anchor: :top},
      %{x: 0.08, y: 0.5, anchor: :left},
      %{x: 0.5, y: 0.86, anchor: :bottom},
      %{x: 0.92, y: 0.5, anchor: :right}
    ]

  defp seat_positions(3),
    do: [
      %{x: 0.5, y: 0.86, anchor: :bottom},
      %{x: 0.18, y: 0.18, anchor: :topleft},
      %{x: 0.82, y: 0.18, anchor: :topright}
    ]

  defp seat_positions(_),
    do: [
      %{x: 0.5, y: 0.86, anchor: :bottom},
      %{x: 0.5, y: 0.10, anchor: :top}
    ]

  defp seat_order(num_p, human_idx, positions) do
    bottom_seat_i = Enum.find_index(positions, &(&1.anchor == :bottom))

    for i <- 0..(num_p - 1) do
      rem(human_idx + (i - bottom_seat_i + num_p), num_p)
    end
  end

  defp trick_card_positions(positions) do
    Enum.map(positions, fn p ->
      dx = (0.5 - p.x) * 0.45
      dy = (0.5 - p.y) * 0.45
      %{x: p.x + dx, y: p.y + dy}
    end)
  end

  defp trick_count(g) do
    sum = Enum.sum(g.tricks_won)
    plus_current = if g.trick == [], do: 0, else: 1
    sum + plus_current
  end

  defp round_max_tricks(4), do: 12
  defp round_max_tricks(3), do: 16
  defp round_max_tricks(_), do: 14

  defp team_color(0), do: "var(--shu)"
  defp team_color(1), do: "var(--asagi)"
  defp team_color(_), do: "var(--kihada)"

  # ---------- subcomponents ----------

  attr :player, :map, required: true
  attr :hand, :list, required: true
  attr :position, :map, required: true
  attr :is_current, :boolean, required: true
  attr :tricks, :integer, required: true
  attr :bosses, :list, required: true
  attr :is_lead, :boolean, required: true

  defp seat(assigns) do
    %{anchor: anchor} = assigns.position
    is_top = anchor in [:top, :topleft, :topright]
    is_left_or_right = anchor in [:left, :right]
    stack_n = min(length(assigns.hand), 7)

    flex_dir =
      cond do
        is_left_or_right -> "column"
        is_top -> "column-reverse"
        true -> "column"
      end

    assigns =
      assign(assigns,
        is_top: is_top,
        is_left_or_right: is_left_or_right,
        stack_n: stack_n,
        flex_dir: flex_dir,
        team_color: team_color(assigns.player.team)
      )

    ~H"""
    <div style={
      "position: absolute;" <>
      " left: #{@position.x * 100}%; top: #{@position.y * 100}%;" <>
      " transform: translate(-50%, -50%);" <>
      " display: flex; flex-direction: #{@flex_dir}; align-items: center; gap: 12px; z-index: 5;"
    }>
      <div style={
        "position: relative;" <>
        " height: #{if @is_left_or_right, do: 80, else: 60}px;" <>
        " width: #{if @is_left_or_right, do: 100, else: 200}px;" <>
        " display: flex; align-items: center; justify-content: center;"
      }>
        <%= for i <- 0..(@stack_n - 1)//1 do %>
          <% offset = i - @stack_n / 2 %>
          <% tx = if @is_left_or_right, do: 0, else: offset * 14 %>
          <% ty = if @is_left_or_right, do: offset * 8, else: 0 %>
          <% rot = if @is_left_or_right, do: 90, else: offset * 3 %>
          <div style={"position: absolute; transform: translate(#{tx}px, #{ty}px) rotate(#{rot}deg); z-index: #{i};"}>
            <div class="yokai-back" style="width: 36px; height: 50px;">
              <span style="font-family: var(--kanji); font-size: 10px; opacity: 0.7;">七</span>
            </div>
          </div>
        <% end %>
      </div>

      <div style={
        "background: rgba(26, 20, 16, 0.85);" <>
        " border: 1px solid #{if @is_current, do: "var(--gold-bright)", else: "rgba(244,236,216,0.15)"};" <>
        " box-shadow: #{if @is_current, do: "0 0 0 2px rgba(212, 175, 55, 0.25), 0 0 24px rgba(212,175,55,0.2)", else: "var(--shadow-md)"};" <>
        " padding: 10px 16px; min-width: 180px; border-radius: 2px; transition: all 200ms;"
      }>
        <div style="display: flex; align-items: center; gap: 10px; margin-bottom: 6px;">
          <div style={
            "width: 28px; height: 28px;" <>
            " background: #{@team_color};" <>
            " color: var(--washi);" <>
            " display: flex; align-items: center; justify-content: center;" <>
            " font-family: var(--kanji); font-size: 14px; font-weight: 600; border-radius: 2px;"
          }>
            {String.first(@player.name)}
          </div>
          <div style="flex: 1;">
            <div style="font-size: 13px; font-weight: 500; color: var(--washi);">{@player.name}</div>
            <div style="font-size: 10px; font-family: var(--sans); letter-spacing: 0.16em; text-transform: uppercase; color: rgba(244,236,216,0.5);">
              {if @is_lead, do: "Lead · ", else: ""}{length(@hand)} cards
            </div>
          </div>
          <%= if @is_current do %>
            <div style="width: 8px; height: 8px; border-radius: 50%; background: var(--gold-bright); animation: pulse 1.4s ease-in-out infinite; box-shadow: 0 0 8px var(--gold-bright);"></div>
          <% end %>
        </div>
        <div style="display: flex; justify-content: space-between; font-size: 11px; font-family: var(--sans); letter-spacing: 0.12em; text-transform: uppercase; color: rgba(244,236,216,0.7);">
          <span>Tricks {@tricks}</span>
          <span style="color: var(--gold-bright);">七 {length(@bosses)}</span>
        </div>
      </div>
    </div>
    """
  end

  attr :players, :list, required: true
  attr :scores, :map, required: true

  defp score_pill(assigns) do
    teams =
      assigns.players
      |> Enum.reduce(%{}, fn p, acc ->
        Map.update(acc, p.team, [p.name], &(&1 ++ [p.name]))
      end)
      |> Enum.sort_by(fn {tid, _} -> tid end)

    assigns = assign(assigns, teams: teams)

    ~H"""
    <div style="display: flex; align-items: center; gap: 16px;">
      <%= for {tid, names} <- @teams do %>
        <div style="display: flex; align-items: center; gap: 8px; padding: 6px 14px; background: rgba(26,20,16,0.6); border: 1px solid rgba(244,236,216,0.12); border-radius: 2px;">
          <div style={"width: 8px; height: 8px; background: #{team_color(tid)};"}></div>
          <span style="font-size: 11px; letter-spacing: 0.16em; text-transform: uppercase; font-family: var(--sans); color: rgba(244,236,216,0.75);">
            {Enum.join(names, " · ")}
          </span>
          <span class="kanji" style="font-size: 18px; color: var(--gold-bright); font-weight: 600;">
            {Map.get(@scores, tid, 0)}
          </span>
        </div>
      <% end %>
    </div>
    """
  end

  attr :hand, :list, required: true
  attr :legal, :list, required: true
  attr :is_my_turn, :boolean, required: true
  attr :player_name, :string, required: true
  attr :tricks, :integer, required: true
  attr :bosses, :list, required: true
  attr :is_lead, :boolean, required: true

  defp player_hand(assigns) do
    ~H"""
    <div style="position: relative; padding: 16px 32px 28px; background: linear-gradient(180deg, transparent, rgba(0,0,0,0.35) 60%);">
      <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 12px; color: var(--washi);">
        <div style="display: flex; align-items: center; gap: 16px;">
          <div style="width: 36px; height: 36px; background: var(--shu); color: var(--washi); display: flex; align-items: center; justify-content: center; font-family: var(--kanji); font-size: 18px; font-weight: 600; border-radius: 2px;">
            {String.first(@player_name || "Y")}
          </div>
          <div>
            <div style="font-size: 15px; font-weight: 500;">
              {@player_name}
              <%= if @is_lead do %>
                <span style="color: var(--gold-bright); font-family: var(--kanji); font-size: 12px; margin-left: 6px;">先 Lead</span>
              <% end %>
            </div>
            <div style="font-size: 11px; font-family: var(--sans); letter-spacing: 0.16em; text-transform: uppercase; color: rgba(244,236,216,0.55);">
              Tricks {@tricks} · Bosses captured {length(@bosses)}
            </div>
          </div>
        </div>

        <div style="display: flex; align-items: center; gap: 12px;">
          <%= if length(@bosses) > 0 do %>
            <div style="display: flex; margin-right: 8px;">
              <%= for {b, i} <- Enum.with_index(Enum.take(@bosses, 4)) do %>
                <div style={"margin-left: #{if i == 0, do: 0, else: -16}px;"}>
                  <.yokai_card suit={b.suit} rank={b.rank} is_a={b.is_a} width={36} />
                </div>
              <% end %>
            </div>
          <% end %>
          <div style={
            "padding: 8px 16px;" <>
            " border: 1px solid #{if @is_my_turn, do: "var(--gold-bright)", else: "rgba(244,236,216,0.2)"};" <>
            " background: #{if @is_my_turn, do: "rgba(212,175,55,0.1)", else: "transparent"};" <>
            " color: #{if @is_my_turn, do: "var(--gold-bright)", else: "rgba(244,236,216,0.55)"};" <>
            " font-size: 11px; letter-spacing: 0.2em; text-transform: uppercase; font-family: var(--sans);" <>
            " transition: all 200ms;"
          }>
            {if @is_my_turn, do: "Your turn", else: "Waiting…"}
          </div>
        </div>
      </div>

      <div style="display: flex; justify-content: center; gap: 4px; min-height: 130px;">
        <%= if @hand == [] do %>
          <div style="color: rgba(244,236,216,0.4); font-style: italic; padding: 40px;">Hand is empty</div>
        <% else %>
          <%= for {c, i} <- Enum.with_index(@hand) do %>
            <% playable = c.id in @legal and @is_my_turn %>
            <div
              style={
                "margin-left: #{if i == 0, do: 0, else: -28}px;" <>
                " transition: transform 200ms cubic-bezier(0.2, 0.8, 0.2, 1);" <>
                " cursor: #{if playable, do: "pointer", else: "not-allowed"};" <>
                " z-index: #{i};"
              }
              class={if playable, do: "hand-card-playable", else: ""}
            >
              <.yokai_card
                suit={c.suit}
                rank={c.rank}
                is_a={c.is_a}
                width={88}
                playable={playable}
                dimmed={not playable}
                phx_click={if playable, do: "play_card"}
                phx_value_id={c.id}
              />
            </div>
          <% end %>
        <% end %>
      </div>
    </div>
    """
  end

  attr :game, :map, required: true
  attr :my_hand, :list, required: true

  defp pass_panel(assigns) do
    sel = assigns.game.human_pass_selection
    can_confirm = length(sel) == 3

    pass_target =
      if assigns.game.num_p == 4 do
        partner = Enum.at(assigns.game.players, 0).partner
        Enum.at(assigns.game.players, partner).name
      else
        Enum.at(assigns.game.players, 1).name
      end

    assigns =
      assign(assigns,
        sel: sel,
        can_confirm: can_confirm,
        pass_target: pass_target
      )

    ~H"""
    <div style="position: relative; padding: 16px 32px 28px; background: linear-gradient(180deg, transparent, rgba(0,0,0,0.35) 60%);">
      <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 12px; color: var(--washi);">
        <div>
          <div class="eyebrow" style="color: rgba(244,236,216,0.55);">Passing phase</div>
          <div style="font-size: 15px; margin-top: 4px;">
            Choose 3 cards to pass to <span style="color: var(--gold-bright); font-family: var(--kanji);">{@pass_target}</span>
          </div>
        </div>
        <button
          class="btn btn-shu"
          phx-click="confirm_pass"
          disabled={not @can_confirm}
          style={"opacity: #{if @can_confirm, do: 1, else: 0.4}; cursor: #{if @can_confirm, do: "pointer", else: "not-allowed"};"}
        >
          <span class="kanji">送</span> Confirm pass ({length(@sel)}/3)
        </button>
      </div>

      <div style="display: flex; justify-content: center; gap: 4px; min-height: 130px;">
        <%= for {c, i} <- Enum.with_index(@my_hand) do %>
          <% selected? = c.id in @sel %>
          <div
            style={
              "margin-left: #{if i == 0, do: 0, else: -28}px;" <>
              " transition: transform 200ms cubic-bezier(0.2, 0.8, 0.2, 1);" <>
              " cursor: pointer; z-index: #{i};"
            }
          >
            <.yokai_card
              suit={c.suit}
              rank={c.rank}
              is_a={c.is_a}
              width={88}
              selected={selected?}
              phx_click="toggle_pass"
              phx_value_id={c.id}
            />
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  attr :game, :map, required: true

  defp round_summary(assigns) do
    g = assigns.game
    log = List.first(g.round_log) || %{}

    teams =
      g.players
      |> Enum.with_index()
      |> Enum.reduce(%{}, fn {p, i}, acc ->
        cur = Map.get(acc, p.team, %{names: [], tricks: 0, bosses: [], idxs: []})

        Map.put(acc, p.team, %{
          names: cur.names ++ [p.name],
          tricks: cur.tricks + Enum.at(g.tricks_won, i),
          bosses: cur.bosses ++ Enum.at(g.bosses_by_player, i),
          idxs: cur.idxs ++ [i]
        })
      end)
      |> Enum.sort_by(fn {tid, _} -> tid end)

    winner_team = Map.get(log, :winner_team)
    reason = Map.get(log, :reason, "")

    win_team_data =
      cond do
        is_integer(winner_team) -> Enum.find(teams, fn {tid, _} -> tid == winner_team end)
        true -> nil
      end

    title =
      cond do
        win_team_data && "You" in elem(win_team_data, 1).names -> "勝利"
        win_team_data -> "敗北"
        true -> "終了"
      end

    subtitle =
      case win_team_data do
        {_, %{names: names}} -> "#{Enum.join(names, " & ")} took the round"
        _ -> "Round complete"
      end

    assigns =
      assign(assigns,
        teams: teams,
        winner_team: winner_team,
        reason: reason,
        title: title,
        subtitle: subtitle
      )

    ~H"""
    <div class="fade-in" style="position: fixed; inset: 0; background: rgba(10, 8, 6, 0.85); backdrop-filter: blur(8px); display: flex; align-items: center; justify-content: center; z-index: 100;">
      <div class="washi-card slide-up" style="max-width: 880px; width: 92%; padding: 48px 56px; position: relative; box-shadow: var(--shadow-lg); border-radius: 4px;">
        <div style="position: absolute; top: 32px; right: 36px; width: 64px; height: 64px; background: var(--shu); color: var(--washi); display: flex; align-items: center; justify-content: center; font-family: var(--kanji); font-size: 28px; font-weight: 600; transform: rotate(-8deg); box-shadow: 0 0 0 1px rgba(0,0,0,0.12) inset;">
          勝
        </div>

        <div class="eyebrow" style="color: var(--sumi-mute);">Round {@game.round} · Result</div>
        <h1 class="kanji" style="font-size: 56px; margin: 12px 0 4px; color: var(--sumi); font-weight: 500;">{@title}</h1>
        <p style="font-size: 18px; color: var(--sumi-soft); margin: 0 0 4px; font-style: italic;">{@subtitle}</p>
        <p style="font-size: 14px; color: var(--sumi-mute); margin: 0; font-family: var(--sans);">{@reason}</p>

        <hr class="hairline" style="margin: 32px 0;" />

        <div style={"display: grid; grid-template-columns: repeat(#{length(@teams)}, 1fr); gap: 32px;"}>
          <%= for {tid, t} <- @teams do %>
            <% is_winner = tid == @winner_team %>
            <div style={
              "padding: 24px;" <>
              " background: #{if is_winner, do: "rgba(212, 175, 55, 0.1)", else: "transparent"};" <>
              " border: 1px solid #{if is_winner, do: "var(--gold)", else: "var(--line)"};" <>
              " border-radius: 2px;"
            }>
              <div class="eyebrow" style={"color: #{if is_winner, do: "var(--shu)", else: "var(--sumi-mute)"}; margin-bottom: 8px;"}>
                {if is_winner, do: "Winner", else: "Team"}
              </div>
              <div style="font-size: 18px; font-weight: 500; margin-bottom: 16px; color: var(--sumi);">{Enum.join(t.names, " & ")}</div>
              <div style="display: flex; gap: 24px; margin-bottom: 16px; font-family: var(--sans); font-size: 12px; letter-spacing: 0.12em; text-transform: uppercase; color: var(--sumi-mute);">
                <div>
                  <div style="font-size: 28px; font-family: var(--kanji); color: var(--sumi);">{t.tricks}</div>
                  Tricks
                </div>
                <div>
                  <div style="font-size: 28px; font-family: var(--kanji); color: var(--shu);">{length(t.bosses)}</div>
                  Bosses
                </div>
              </div>
              <div style="display: flex; gap: 4px; flex-wrap: wrap;">
                <%= for b <- t.bosses do %>
                  <.yokai_card suit={b.suit} rank={b.rank} is_a={b.is_a} width={44} />
                <% end %>
              </div>
            </div>
          <% end %>
        </div>

        <hr class="hairline" style="margin: 32px 0;" />

        <div style="display: flex; justify-content: space-between; align-items: center;">
          <div style="display: flex; gap: 24px; align-items: center;">
            <div class="eyebrow">Score</div>
            <%= for {tid, v} <- Enum.sort_by(@game.scores, &elem(&1, 0)) do %>
              <div style="display: flex; align-items: center; gap: 8px;">
                <div style={"width: 8px; height: 8px; background: #{team_color(tid)};"}></div>
                <span style="font-family: var(--kanji); font-size: 24px; font-weight: 500; color: var(--sumi);">{v}</span>
                <span style="font-size: 11px; font-family: var(--sans); color: var(--sumi-mute); letter-spacing: 0.16em; text-transform: uppercase;">/ 7</span>
              </div>
            <% end %>
          </div>
          <div style="display: flex; gap: 12px;">
            <button class="btn btn-ghost" phx-click="nav_home">Leave table</button>
            <button class="btn btn-shu" phx-click="next_round">
              <span class="kanji">次</span> Next round
            </button>
          </div>
        </div>
      </div>
    </div>
    """
  end

  attr :game, :map, required: true

  defp game_over(assigns) do
    g = assigns.game

    {winner_tid, winner_score} =
      Enum.reduce(g.scores, {0, -1}, fn {k, v}, {bk, bv} ->
        if v > bv, do: {k, v}, else: {bk, bv}
      end)

    teams =
      g.players
      |> Enum.reduce(%{}, fn p, acc ->
        Map.update(acc, p.team, [p.name], &(&1 ++ [p.name]))
      end)
      |> Enum.sort_by(fn {tid, _} -> tid end)

    is_victory =
      case Enum.find(teams, fn {tid, _} -> tid == winner_tid end) do
        {_, names} -> "You" in names
        _ -> false
      end

    winner_names =
      case Enum.find(teams, fn {tid, _} -> tid == winner_tid end) do
        {_, names} -> names
        _ -> []
      end

    assigns =
      assign(assigns,
        winner_tid: winner_tid,
        winner_score: winner_score,
        teams: teams,
        is_victory: is_victory,
        winner_names: winner_names
      )

    ~H"""
    <div class="fade-in" style="position: fixed; inset: 0; background: rgba(10, 8, 6, 0.92); backdrop-filter: blur(12px); display: flex; align-items: center; justify-content: center; z-index: 200;">
      <div class="slide-up" style="max-width: 720px; width: 92%; text-align: center; color: var(--washi);">
        <div class="kanji" style={
          "font-size: 180px; line-height: 1;" <>
          " color: #{if @is_victory, do: "var(--gold-bright)", else: "var(--shu)"};" <>
          " font-weight: 500; margin-bottom: 20px;" <>
          " text-shadow: 0 0 60px rgba(212, 175, 55, 0.3);"
        }>
          {if @is_victory, do: "勝", else: "終"}
        </div>
        <div class="eyebrow" style="color: rgba(244,236,216,0.55);">
          {if @is_victory, do: "Glory to the Onmyoji", else: "The Yokai prevail"}
        </div>
        <h1 style="font-size: 48px; margin: 12px 0 8px; font-family: var(--kanji); font-weight: 500; letter-spacing: 0.04em;">
          {if @is_victory, do: "Victory", else: "Defeat"}
        </h1>
        <p style="font-size: 16px; color: rgba(244,236,216,0.7); max-width: 480px; margin: 0 auto; font-style: italic; line-height: 1.6;">
          {Enum.join(@winner_names, " & ")} captured the seven over {@game.round} round{if @game.round != 1, do: "s", else: ""}.
        </p>

        <hr style="border: none; height: 1px; background: rgba(244,236,216,0.15); margin: 40px auto; width: 200px;" />

        <div style="display: flex; justify-content: center; gap: 32px; margin-bottom: 40px;">
          <%= for {tid, names} <- @teams do %>
            <% is_win = tid == @winner_tid %>
            <div style={
              "padding: 20px 32px;" <>
              " background: #{if is_win, do: "rgba(212, 175, 55, 0.12)", else: "transparent"};" <>
              " border: 1px solid #{if is_win, do: "var(--gold-bright)", else: "rgba(244,236,216,0.18)"};" <>
              " min-width: 200px;"
            }>
              <div style="font-size: 11px; letter-spacing: 0.2em; text-transform: uppercase; color: rgba(244,236,216,0.55); font-family: var(--sans); margin-bottom: 8px;">
                {Enum.join(names, " & ")}
              </div>
              <div class="kanji" style={"font-size: 56px; font-weight: 500; color: #{if is_win, do: "var(--gold-bright)", else: "var(--washi)"};"}>
                {Map.get(@game.scores, tid, 0)}
              </div>
            </div>
          <% end %>
        </div>

        <div style="display: flex; justify-content: center; gap: 16px;">
          <button class="btn btn-ghost" style="border-color: rgba(244,236,216,0.3); color: var(--washi);" phx-click="nav_home">
            Home
          </button>
          <button class="btn btn-shu" phx-click="nav_home">
            <span class="kanji">再</span> Play again
          </button>
        </div>
      </div>
    </div>
    """
  end
end
