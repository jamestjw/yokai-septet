defmodule YokaiSeptetWeb.HomeLive do
  @moduledoc """
  Home + Rules screens. The original SPA managed these via a single React tree;
  here we expose two routes (`/` and `/rules`) that both mount this LiveView and
  set a `@screen` assign accordingly.
  """
  use YokaiSeptetWeb, :live_view

  import YokaiSeptetWeb.CardComponents
  alias YokaiSeptet.Cards

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, mode: "4p"), layout: false}
  end

  @impl true
  def handle_params(_params, url, socket) do
    screen =
      cond do
        String.ends_with?(url, "/rules") -> :rules
        true -> :home
      end

    {:noreply, assign(socket, screen: screen)}
  end

  @impl true
  def handle_event("set_mode", %{"mode" => mode}, socket) do
    {:noreply, assign(socket, mode: mode)}
  end

  @impl true
  def handle_event("nav", %{"to" => "home"}, socket),
    do: {:noreply, push_navigate(socket, to: ~p"/")}

  def handle_event("nav", %{"to" => "rules"}, socket),
    do: {:noreply, push_navigate(socket, to: ~p"/rules")}

  def handle_event("nav", %{"to" => "table"}, socket) do
    {:noreply, push_navigate(socket, to: ~p"/play/#{socket.assigns.mode}")}
  end

  def handle_event("start", _params, socket) do
    {:noreply, push_navigate(socket, to: ~p"/play/#{socket.assigns.mode}")}
  end

  # ---------------- render ----------------

  @impl true
  def render(%{screen: :home} = assigns), do: home(assigns)
  def render(%{screen: :rules} = assigns), do: rules(assigns)

  attr :on_nav, :string, default: "nav"
  attr :current, :atom, required: true

  defp top_bar(assigns) do
    ~H"""
    <header style="display: flex; align-items: center; justify-content: space-between; padding: 20px 40px; border-bottom: 1px solid var(--line);">
      <button
        phx-click="nav"
        phx-value-to="home"
        style="background: none; border: none; cursor: pointer; padding: 0;"
      >
        <.logo size={40} />
      </button>
      <nav style="display: flex; gap: 32px; align-items: center; font-family: var(--sans); font-size: 13px;">
        <%= for {id, label} <- [{"home", "Home"}, {"rules", "How to Play"}, {"table", "Table"}] do %>
          <% active? = Atom.to_string(@current) == id %>
          <button
            phx-click="nav"
            phx-value-to={id}
            style={
              "background: none; border: none; cursor: pointer;" <>
              " color: #{if active?, do: "var(--sumi)", else: "var(--sumi-mute)"};" <>
              " font-family: inherit; font-size: inherit; letter-spacing: 0.2em; text-transform: uppercase;" <>
              " padding-bottom: 4px;" <>
              " border-bottom: 1px solid #{if active?, do: "var(--sumi)", else: "transparent"};" <>
              " transition: color 160ms, border-color 160ms;"
            }
          >
            {label}
          </button>
        <% end %>
      </nav>
    </header>
    """
  end

  attr :size, :integer, default: 48

  defp logo(assigns) do
    ~H"""
    <div style="display: flex; align-items: center; gap: 16px;">
      <div style={
        "width: #{@size}px; height: #{@size}px;" <>
        " background: var(--shu); color: var(--washi);" <>
        " display: flex; align-items: center; justify-content: center;" <>
        " font-family: var(--kanji); font-size: #{@size * 0.5}px; font-weight: 600;" <>
        " border-radius: 4px; box-shadow: 0 0 0 1px rgba(0,0,0,0.1) inset, 1px 1px 0 rgba(0,0,0,0.15);" <>
        " position: relative;"
      }>
        <span style="position: relative; z-index: 1;">七</span>
      </div>
      <div>
        <div
          class="kanji"
          style={"font-size: #{@size * 0.5}px; font-weight: 500; line-height: 1; color: var(--sumi);"}
        >
          妖怪七番
        </div>
        <div style="font-size: 11px; letter-spacing: 0.32em; text-transform: uppercase; color: var(--sumi-mute); margin-top: 4px; font-family: var(--sans);">
          Yokai Septet
        </div>
      </div>
    </div>
    """
  end

  defp home(assigns) do
    modes = [
      %{
        id: "4p",
        label: "Four Players",
        sub: "Teams of two",
        kanji: "四",
        detail: "12 cards each · capture 4 Bosses · first to 7 points"
      },
      %{
        id: "3p",
        label: "Three Players",
        sub: "Free for all",
        kanji: "三",
        detail: "16 cards each · capture 3 Bosses · first to 7 points"
      },
      %{
        id: "2p",
        label: "Two Players",
        sub: "Pocket duel",
        kanji: "二",
        detail: "Simplified · capture 4 Bosses to win the round"
      }
    ]

    assigns = assign(assigns, modes: modes)

    ~H"""
    <div class="washi-bg" style="min-height: 100vh; display: flex; flex-direction: column;">
      <.top_bar current={:home} />

      <main style="flex: 1; display: grid; grid-template-columns: 1.1fr 0.9fr; gap: 80px; padding: 60px 80px; max-width: 1440px; margin: 0 auto; width: 100%;">
        <div class="slide-up">
          <div class="eyebrow" style="margin-bottom: 24px;">A trick-taking game of capture</div>
          <h1
            class="kanji"
            style="font-size: 88px; line-height: 0.95; margin: 0; font-weight: 500; color: var(--sumi); letter-spacing: 0.02em;"
          >
            妖怪<br />七番
          </h1>
          <div style="display: flex; align-items: baseline; gap: 16px; margin-top: 12px; margin-bottom: 32px;">
            <span style="font-size: 28px; color: var(--shu); font-family: var(--kanji);">
              Yokai Septet
            </span>
            <span style="color: var(--sumi-mute); font-style: italic;">— Pocket Edition</span>
          </div>

          <p style="max-width: 480px; line-height: 1.7; color: var(--sumi-soft); font-size: 16px;">
            Capture the seven Boss Yokai before your rivals. Each round is a contest of suit, of trump,
            and of restraint — for taking too many tricks is its own defeat.
          </p>

          <div style="margin-top: 44px;">
            <div class="eyebrow" style="margin-bottom: 16px;">Choose your table</div>
            <div style="display: grid; gap: 12px;">
              <%= for m <- @modes do %>
                <% active? = @mode == m.id %>
                <button
                  phx-click="set_mode"
                  phx-value-mode={m.id}
                  style={
                    "display: grid; grid-template-columns: 56px 1fr auto; align-items: center; gap: 20px;" <>
                    " padding: 18px 20px;" <>
                    " background: #{if active?, do: "var(--washi-warm)", else: "transparent"};" <>
                    " border: 1px solid #{if active?, do: "var(--sumi)", else: "var(--line)"};" <>
                    " border-left-width: #{if active?, do: "3px", else: "1px"};" <>
                    " border-left-color: #{if active?, do: "var(--shu)", else: "var(--line)"};" <>
                    " cursor: pointer; text-align: left; font-family: inherit;" <>
                    " transition: all 200ms; border-radius: 2px;"
                  }
                >
                  <div
                    class="kanji"
                    style={"font-size: 40px; color: #{if active?, do: "var(--shu)", else: "var(--sumi-mute)"}; line-height: 1; font-weight: 500;"}
                  >
                    {m.kanji}
                  </div>
                  <div>
                    <div style="font-size: 18px; font-weight: 500; color: var(--sumi); margin-bottom: 2px;">
                      {m.label}
                    </div>
                    <div style="font-size: 13px; color: var(--sumi-mute); font-style: italic;">
                      {m.sub} — {m.detail}
                    </div>
                  </div>
                  <div style={
                    "width: 16px; height: 16px; border-radius: 50%;" <>
                    " border: 1px solid #{if active?, do: "var(--shu)", else: "var(--line-strong)"};" <>
                    " background: #{if active?, do: "var(--shu)", else: "transparent"};"
                  }>
                  </div>
                </button>
              <% end %>
            </div>
          </div>

          <div style="display: flex; gap: 16px; margin-top: 40px; align-items: center;">
            <button
              class="btn btn-shu"
              style="padding: 16px 36px; font-size: 16px; letter-spacing: 0.1em;"
              phx-click="start"
            >
              <span class="kanji" style="font-size: 18px;">始</span> Begin Round
            </button>
            <button class="btn btn-ghost" phx-click="nav" phx-value-to="rules">How to Play</button>
          </div>
        </div>

        <div style="position: relative; display: flex; align-items: center; justify-content: center;">
          <.card_fan />
        </div>
      </main>

      <footer style="padding: 24px 40px; border-top: 1px solid var(--line); display: flex; justify-content: space-between; font-family: var(--sans); font-size: 11px; color: var(--sumi-mute); letter-spacing: 0.16em; text-transform: uppercase;">
        <span>七つの妖怪 · Capture the Seven</span>
        <span>Pocket Edition · v1.0</span>
      </footer>
    </div>
    """
  end

  defp card_fan(assigns) do
    bosses =
      Enum.map(Cards.suits(), fn s ->
        %{suit: s.id, rank: 7}
      end)

    total = length(bosses)
    angle_step = 7

    assigns =
      assign(assigns,
        bosses: Enum.with_index(bosses),
        total: total,
        angle_step: angle_step
      )

    ~H"""
    <div style="position: relative; width: 540px; height: 560px; display: flex; align-items: center; justify-content: center;">
      <svg
        viewBox="0 0 400 400"
        style="position: absolute; inset: 0; width: 100%; height: 100%; opacity: 0.7;"
      >
        <defs>
          <filter id="ink-rough">
            <feTurbulence baseFrequency="0.04" numOctaves="2" seed="3" />
            <feDisplacementMap in="SourceGraphic" scale="6" />
          </filter>
        </defs>
        <circle
          cx="200"
          cy="200"
          r="170"
          fill="none"
          stroke="var(--sumi)"
          stroke-width="3"
          stroke-dasharray="0 12 1000"
          stroke-linecap="round"
          opacity="0.18"
          filter="url(#ink-rough)"
        />
      </svg>

      <div style="position: absolute; top: 30px; right: 20px; width: 70px; height: 70px; background: var(--shu); color: var(--washi); display: flex; align-items: center; justify-content: center; font-family: var(--kanji); font-size: 30px; font-weight: 600; transform: rotate(-6deg); box-shadow: 0 0 0 1px rgba(0,0,0,0.12) inset;">
        七
      </div>

      <%= for {c, i} <- @bosses do %>
        <% offset = i - (@total - 1) / 2 %>
        <% rot = offset * @angle_step %>
        <% ty = abs(offset) * 16 %>
        <div
          class="draw-in"
          style={
            "position: absolute;" <>
            " transform: rotate(#{rot}deg) translateY(#{ty - 80}px);" <>
            " transform-origin: center 320px;" <>
            " --rot: #{rot}deg;" <>
            " animation-delay: #{i * 80}ms;"
          }
        >
          <.yokai_card suit={c.suit} rank={c.rank} width={130} />
        </div>
      <% end %>

      <div style="position: absolute; bottom: 0; left: 0; right: 0; text-align: center;">
        <div class="eyebrow">The seven Boss Yokai</div>
        <div style="margin-top: 6px; font-size: 13px; color: var(--sumi-mute); font-style: italic;">
          One from each suit · capture them all
        </div>
      </div>
    </div>
    """
  end

  defp rules(assigns) do
    sections = [
      %{
        num: "1",
        title: "Suits & Strength",
        body:
          "49 cards in 7 suits, 7 cards each. Wind has the lowest ranks (A,2-7); Snow has the highest (7-13). The small dots in the corner show where the card sits within its suit. Every suit has a card of rank 7 — that is its Boss Yokai.",
        visual: :suits
      },
      %{
        num: "2",
        title: "The A Card",
        body:
          "Wind's lowest card is the A. Despite its low rank, it is the most powerful card in the game — it always wins the trick when played. The player dealt the A leads the first trick.",
        visual: :a_card
      },
      %{
        num: "3",
        title: "The Pass",
        body:
          "After dealing, each player passes 3 cards to their teammate (or to the player on the left, in 3-player). Use this to set up your team — give your partner what they need, dump what hurts you.",
        visual: :pass
      },
      %{
        num: "4",
        title: "Tricks & Trump",
        body:
          "The lead player plays any card. Others must follow suit if they can. Highest card of the lead suit wins — unless trump is played, in which case the highest trump wins. The A always trumps everything.",
        visual: :trick
      },
      %{
        num: "5",
        title: "Greed is a Curse",
        body:
          "If you (or your team) take 7 tricks before capturing enough Bosses, you LOSE the round and your opponents win. Don't grab tricks just to grab them — the only thing that scores is capturing Bosses.",
        visual: nil
      },
      %{
        num: "6",
        title: "Round Ends",
        body:
          "A round ends when (a) one team has captured 4 Bosses (3 in a 3-player game), (b) one team has taken 7 tricks (greed loss), or (c) every card has been played — whoever took the last trick wins.",
        visual: nil
      },
      %{
        num: "7",
        title: "Scoring",
        body:
          "Only the winning team scores. Discard the Boss of the trump suit — it doesn't score. Then count the gold pip on each remaining captured Boss. Wind's Boss has 0 points; Snow's Boss is worth 3.",
        visual: :scoring
      },
      %{
        num: "8",
        title: "Victory",
        body:
          "First team (or player) to 7 points wins the game. A typical game runs several rounds — each round resets, but score persists.",
        visual: nil
      }
    ]

    assigns = assign(assigns, sections: sections)

    ~H"""
    <div class="washi-bg" style="min-height: 100vh;">
      <.top_bar current={:rules} />
      <main style="max-width: 1100px; margin: 0 auto; padding: 60px 80px;">
        <div class="eyebrow">遊び方</div>
        <h1
          class="kanji"
          style="font-size: 56px; font-weight: 500; margin: 8px 0 8px; color: var(--sumi);"
        >
          How to Play
        </h1>
        <p style="color: var(--sumi-mute); font-style: italic; max-width: 600px; line-height: 1.6; margin-bottom: 56px;">
          A trick-taking game of seven suits, seven Bosses, and the curse of greed.
        </p>

        <div style="display: grid; grid-template-columns: 1fr 1fr; gap: 60px;">
          <%= for s <- @sections do %>
            <.rules_section section={s} />
          <% end %>
        </div>

        <div style="margin-top: 60px; text-align: center;">
          <button class="btn btn-shu" style="padding: 14px 32px;" phx-click="nav" phx-value-to="home">
            Begin a round
          </button>
        </div>
      </main>
    </div>
    """
  end

  attr :section, :map, required: true

  defp rules_section(assigns) do
    ~H"""
    <div style="display: grid; grid-template-columns: 60px 1fr; gap: 20px;">
      <div style="font-size: 36px; color: var(--shu); line-height: 1; font-weight: 600; font-family: var(--sans);">
        {@section.num}
      </div>
      <div>
        <h2 style="font-size: 22px; margin: 4px 0 12px; font-weight: 500; color: var(--sumi);">
          {@section.title}
        </h2>
        <p style={"line-height: 1.7; color: var(--sumi-soft); font-size: 15px; margin: 0;" <> if(@section.visual, do: " margin-bottom: 20px;", else: "")}>
          {@section.body}
        </p>
        <%= if @section.visual do %>
          <div style="background: rgba(244, 236, 216, 0.5); border: 1px solid var(--line); padding: 24px; border-radius: 4px;">
            <.rule_visual which={@section.visual} />
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  attr :which, :atom, required: true

  defp rule_visual(%{which: :suits} = assigns) do
    assigns = assign(assigns, suits: Cards.suits())

    ~H"""
    <div style="display: flex; gap: 6px; flex-wrap: wrap; justify-content: center;">
      <%= for s <- @suits do %>
        <div style="display: flex; flex-direction: column; align-items: center; gap: 4px;">
          <.yokai_card suit={s.id} rank={7} width={62} />
          <div style="font-size: 10px; font-family: var(--sans); color: var(--sumi-mute); letter-spacing: 0.2em;">
            {String.upcase(s.name)}
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  defp rule_visual(%{which: :a_card} = assigns) do
    ~H"""
    <div style="display: flex; justify-content: center;">
      <.yokai_card suit={:wind} rank="A" is_a={true} width={90} />
    </div>
    """
  end

  defp rule_visual(%{which: :pass} = assigns) do
    ~H"""
    <div style="display: flex; gap: 4px; align-items: center; justify-content: center;">
      <.yokai_card suit={:forest} rank={6} width={50} />
      <.yokai_card suit={:mist} rank={3} width={50} />
      <.yokai_card suit={:earth} rank={4} width={50} />
      <span style="font-size: 24px; color: var(--shu); margin: 0 12px;">→</span>
      <span class="kanji" style="color: var(--sumi-mute); font-size: 14px;">partner</span>
    </div>
    """
  end

  defp rule_visual(%{which: :trick} = assigns) do
    ~H"""
    <div style="display: flex; gap: 4px; align-items: center; justify-content: center;">
      <.yokai_card suit={:forest} rank={5} width={56} />
      <.yokai_card suit={:forest} rank={9} width={56} />
      <.yokai_card suit={:earth} rank={3} width={56} />
      <div style="width: 1px; height: 60px; background: var(--line-strong); margin: 0 6px;"></div>
      <div style="position: relative;">
        <.yokai_card suit={:flame} rank={7} width={56} />
        <div style="position: absolute; top: -8px; right: -8px; width: 22px; height: 22px; background: var(--gold-bright); border-radius: 50%; display: flex; align-items: center; justify-content: center; font-size: 11px; font-family: var(--kanji); color: var(--sumi); font-weight: 600;">
          勝
        </div>
      </div>
    </div>
    """
  end

  defp rule_visual(%{which: :scoring} = assigns) do
    # Each Boss Yokai is rank 7 of its suit. The third tuple element is the
    # solid-pip score (★) used in 2/4-player games.
    rows = [
      {:wind, 7, 0},
      {:earth, 7, 0},
      {:mist, 7, 1},
      {:river, 7, 1},
      {:forest, 7, 2},
      {:flame, 7, 2},
      {:snow, 7, 3}
    ]

    assigns = assign(assigns, rows: rows)

    ~H"""
    <div style="display: flex; gap: 4px; align-items: center; justify-content: center;">
      <%= for {s, r, p} <- @rows do %>
        <div style="display: flex; flex-direction: column; align-items: center; gap: 4px;">
          <.yokai_card suit={s} rank={r} width={50} />
          <div style="display: flex; gap: 2px;">
            <%= if p > 0 do %>
              <%= for i <- 1..p do %>
                <div
                  style="width: 6px; height: 6px; border-radius: 50%; background: var(--gold-bright);"
                  data-i={i}
                >
                </div>
              <% end %>
            <% else %>
              <span style="font-size: 9px; color: var(--sumi-mute);">—</span>
            <% end %>
          </div>
        </div>
      <% end %>
    </div>
    """
  end
end
