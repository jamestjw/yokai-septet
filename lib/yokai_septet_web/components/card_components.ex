defmodule YokaiSeptetWeb.CardComponents do
  @moduledoc """
  HEEx function components for rendering the Yokai Septet card visuals.
  """
  use Phoenix.Component

  alias YokaiSeptet.Cards

  # ---------- YokaiMark (the suit's central sumi-e symbol) ----------

  attr :suit, :atom, required: true
  attr :size, :integer, default: 40

  def yokai_mark(assigns) do
    s = Cards.suit(assigns.suit)
    sw = assigns.size / 40
    assigns = assign(assigns, sw: sw, color: s.color)

    ~H"""
    <svg width={@size} height={@size} viewBox="0 0 40 40" style={"color: #{@color}"}>
      <%= case @suit do %>
        <% :wind -> %>
          <g fill="none" stroke="currentColor" stroke-width={1.6 * @sw} stroke-linecap="round">
            <path d="M6 14 C14 12 22 16 28 14 C32 13 34 11 34 11" />
            <path d="M6 22 C16 19 26 24 34 21" />
            <path d="M8 30 C16 28 22 31 28 30" />
            <circle cx="32" cy="14" r="1.5" fill="currentColor" />
            <circle cx="32" cy="30" r="1" fill="currentColor" />
          </g>
        <% :earth -> %>
          <g fill="currentColor" stroke="currentColor" stroke-width={1.2 * @sw} stroke-linejoin="round">
            <path d="M6 32 L16 14 L22 22 L26 16 L34 32 Z" />
            <path d="M14 24 L18 20 L20 22" fill="var(--washi-warm)" stroke="var(--washi-warm)" stroke-width={0.6 * @sw} />
          </g>
        <% :mist -> %>
          <g>
            <path d="M20 6 C14 8 10 14 12 20 C14 24 18 22 18 26 C18 30 14 30 14 34 L20 32 L26 34 C26 30 22 30 22 26 C22 22 26 24 28 20 C30 14 26 8 20 6 Z"
                  fill="currentColor" stroke="currentColor" stroke-width={1.2 * @sw} />
            <circle cx="17" cy="16" r="1" fill="var(--washi-warm)" />
            <circle cx="23" cy="16" r="1" fill="var(--washi-warm)" />
          </g>
        <% :river -> %>
          <g>
            <path d="M20 6 C14 14 10 22 14 30 C18 36 22 36 26 30 C30 22 26 14 20 6 Z"
                  fill="currentColor" stroke="currentColor" stroke-width={1.2 * @sw} />
            <ellipse cx="20" cy="14" rx="5" ry="1.5" fill="none" stroke="var(--washi-warm)" stroke-width={0.8 * @sw} />
            <path d="M16 24 C18 22 22 26 24 24" fill="none" stroke="var(--washi-warm)" stroke-width={0.8 * @sw} stroke-linecap="round" />
          </g>
        <% :forest -> %>
          <g fill="none" stroke="currentColor" stroke-width={1.2 * @sw} stroke-linecap="round">
            <path d="M20 4 L20 36" stroke-width={1.4 * @sw} />
            <path d="M20 8 L12 14 M20 8 L28 14" />
            <path d="M20 14 L10 20 M20 14 L30 20" />
            <path d="M20 20 L8 28 M20 20 L32 28" />
            <path d="M20 26 L12 32 M20 26 L28 32" />
          </g>
        <% :flame -> %>
          <g>
            <path d="M20 6 C16 12 12 14 12 22 C12 30 16 34 20 34 C24 34 28 30 28 22 C28 14 24 12 20 6 Z"
                  fill="currentColor" stroke="currentColor" stroke-width={1.2 * @sw} />
            <path d="M20 14 C18 18 17 22 19 28" fill="none" stroke="var(--washi-warm)" stroke-width={0.8 * @sw} stroke-linecap="round"/>
          </g>
        <% :snow -> %>
          <g fill="none" stroke="currentColor" stroke-width={1.4 * @sw} stroke-linecap="round">
            <line x1="20" y1="6" x2="20" y2="34" />
            <line x1="8" y1="13" x2="32" y2="27" />
            <line x1="32" y1="13" x2="8" y2="27" />
            <path d="M20 10 L17 13 M20 10 L23 13" />
            <path d="M20 30 L17 27 M20 30 L23 27" />
            <path d="M10 14 L13 14 M10 14 L11 17" />
            <path d="M30 26 L27 26 M30 26 L29 23" />
            <path d="M30 14 L27 14 M30 14 L29 17" />
            <path d="M10 26 L13 26 M10 26 L11 23" />
            <circle cx="20" cy="20" r="2" fill="currentColor" stroke="none"/>
          </g>
      <% end %>
    </svg>
    """
  end

  # ---------- SuitEmblem ----------

  attr :suit, :atom, required: true
  attr :size, :integer, default: 16

  def suit_emblem(assigns) do
    s = Cards.suit(assigns.suit)
    assigns = assign(assigns, color: s.color, kanji: s.kanji)

    ~H"""
    <span class="kanji" style={"display: inline-flex; align-items: center; justify-content: center; color: #{@color}; font-size: #{@size}px; font-weight: 600; line-height: 1;"}>
      {@kanji}
    </span>
    """
  end

  # ---------- RangeMeter ----------

  attr :suit, :atom, required: true
  attr :rank, :any, required: true
  attr :size, :float, default: 18.0

  def range_meter(assigns) do
    s = Cards.suit(assigns.suit)
    idx = Enum.find_index(s.ranks, &(&1 == assigns.rank)) || 0
    total = length(s.ranks)

    assigns =
      assign(assigns,
        color: s.color,
        idx: idx,
        total: total
      )

    ~H"""
    <svg width={@size * 0.45} height={@size} viewBox="0 0 8 32" style={"color: #{@color}"}>
      <line x1="4" y1="2" x2="4" y2="30" stroke="currentColor" stroke-width="0.6" opacity="0.4" />
      <%= for i <- 0..6 do %>
        <% active? = i == @total - 1 - @idx %>
        <circle
          cx="4"
          cy={4 + i * 4}
          r={if active?, do: 1.6, else: 0.8}
          fill="currentColor"
          opacity={if active?, do: 1, else: 0.3}
        />
      <% end %>
    </svg>
    """
  end

  # ---------- PointPips ----------

  attr :solid, :integer, default: 0
  attr :outline, :integer, default: 0
  attr :size, :float, default: 8.0

  def point_pips(assigns) do
    ~H"""
    <%= if @solid > 0 or @outline > 0 do %>
      <div style="display: flex; gap: 2px; align-items: center;">
        <%= for i <- 1..@solid//1 do %>
          <div style={"width: #{@size}px; height: #{@size}px; background: var(--gold-bright); border-radius: 50%; box-shadow: 0 0 0 1px rgba(0,0,0,0.2);"} data-i={i}></div>
        <% end %>
        <%= for i <- 1..@outline//1 do %>
          <div style={"width: #{@size}px; height: #{@size}px; border: 1.5px solid var(--gold-bright); border-radius: 50%;"} data-i={i}></div>
        <% end %>
      </div>
    <% end %>
    """
  end

  # ---------- YokaiCard ----------

  attr :suit, :atom, required: true
  attr :rank, :any, default: nil
  attr :is_a, :boolean, default: false
  attr :width, :integer, default: 84
  attr :face_down, :boolean, default: false
  attr :selected, :boolean, default: false
  attr :playable, :boolean, default: true
  attr :dimmed, :boolean, default: false
  attr :phx_click, :string, default: nil
  attr :phx_value_id, :any, default: nil
  attr :class, :string, default: ""
  attr :style, :string, default: ""

  def yokai_card(assigns) do
    if assigns.face_down do
      yokai_card_back(assigns)
    else
      yokai_card_face(assigns)
    end
  end

  defp yokai_card_back(assigns) do
    height = assigns.width * 1.42
    assigns = assign(assigns, height: height)

    ~H"""
    <div
      class={"yokai-back #{@class}"}
      style={"width: #{@width}px; height: #{@height}px; #{@style}"}
    >
      <svg width={@width * 0.55} height={@width * 0.55} viewBox="0 0 40 40">
        <circle cx="20" cy="20" r="14" fill="none" stroke="currentColor" stroke-width="0.6" opacity="0.7" />
        <circle cx="20" cy="20" r="9" fill="none" stroke="currentColor" stroke-width="0.4" opacity="0.5" />
        <%= for i <- 0..6 do %>
          <% a = i / 7 * :math.pi() * 2 - :math.pi() / 2 %>
          <circle
            cx={20 + :math.cos(a) * 11}
            cy={20 + :math.sin(a) * 11}
            r="1.4"
            fill="currentColor"
            opacity="0.85"
          />
        <% end %>
        <text x="20" y="24" text-anchor="middle" font-size="9" fill="currentColor" font-family="serif" opacity="0.95">七</text>
      </svg>
    </div>
    """
  end

  defp yokai_card_face(assigns) do
    s = Cards.suit(assigns.suit)
    height = assigns.width * 1.42
    is_boss = assigns.rank == List.last(s.ranks)
    corner_size = assigns.width * 0.18
    mark_size = assigns.width * 0.58
    label = if assigns.is_a, do: "A", else: Cards.rank_label(assigns.rank)
    label_font = if assigns.is_a, do: "var(--serif)", else: "var(--sans)"

    transform = if assigns.selected, do: "translateY(-12px)", else: nil
    cursor = if assigns.playable and assigns.phx_click, do: "pointer", else: "default"
    opacity = if assigns.dimmed, do: 0.45, else: 1

    base_style =
      [
        "width: #{assigns.width}px",
        "height: #{height}px",
        "cursor: #{cursor}",
        "opacity: #{opacity}",
        if(transform, do: "transform: #{transform}", else: nil),
        "transition: transform 200ms cubic-bezier(0.2, 0.8, 0.2, 1), opacity 160ms, box-shadow 160ms",
        "color: #{s.color}",
        assigns.style
      ]
      |> Enum.reject(&is_nil/1)
      |> Enum.join("; ")

    assigns =
      assign(assigns,
        suit_data: s,
        is_boss: is_boss,
        corner_size: corner_size,
        mark_size: mark_size,
        label: label,
        label_font: label_font,
        base_style: base_style,
        click?: assigns.playable and assigns.phx_click
      )

    ~H"""
    <div
      class={"yokai-card #{@class} #{if @selected, do: "selected", else: ""}"}
      style={@base_style}
      phx-click={if @click?, do: @phx_click}
      phx-value-id={if @click?, do: @phx_value_id}
    >
      <div class="frame"></div>

      <%= if @is_boss do %>
        <div style="position: absolute; inset: 3px; border: 1.5px solid var(--gold-bright); border-radius: 4px; pointer-events: none; box-shadow: inset 0 0 12px rgba(212, 175, 55, 0.25);"></div>
      <% end %>

      <%= if @is_a do %>
        <div style="position: absolute; inset: 3px; border: 2px solid var(--shu); border-radius: 4px; pointer-events: none; box-shadow: inset 0 0 14px rgba(200, 72, 60, 0.3);"></div>
      <% end %>

      <div style={"position: absolute; top: #{@width * 0.06}px; left: #{@width * 0.08}px; display: flex; align-items: flex-start; gap: #{@width * 0.04}px;"}>
        <div>
          <div style={"font-family: #{@label_font}; font-size: #{@corner_size}px; font-weight: 700; line-height: 1; letter-spacing: -0.02em;"}>{@label}</div>
          <div class="kanji" style={"font-size: #{@corner_size * 0.55}px; margin-top: 2px; opacity: 0.8; line-height: 1; font-weight: 500;"}>{@suit_data.kanji}</div>
        </div>
        <div style="margin-top: 2px;">
          <.range_meter suit={@suit} rank={@rank} size={@corner_size * 1.4} />
        </div>
      </div>

      <div style={"position: absolute; bottom: #{@width * 0.06}px; right: #{@width * 0.08}px; transform: rotate(180deg); display: flex; align-items: flex-start; gap: #{@width * 0.04}px;"}>
        <div>
          <div style={"font-family: #{@label_font}; font-size: #{@corner_size}px; font-weight: 700; line-height: 1; letter-spacing: -0.02em;"}>{@label}</div>
          <div class="kanji" style={"font-size: #{@corner_size * 0.55}px; margin-top: 2px; opacity: 0.8; line-height: 1; font-weight: 500;"}>{@suit_data.kanji}</div>
        </div>
        <div style="margin-top: 2px;">
          <.range_meter suit={@suit} rank={@rank} size={@corner_size * 1.4} />
        </div>
      </div>

      <div style="position: absolute; inset: 0; display: flex; align-items: center; justify-content: center;">
        <.yokai_mark suit={@suit} size={trunc(@mark_size)} />
      </div>

      <%= if @is_boss and (@suit_data.boss_pts4 > 0 or @suit_data.boss_pts3_extra > 0) do %>
        <div style={"position: absolute; left: 50%; bottom: #{@width * 0.34}px; transform: translateX(-50%); display: flex; flex-direction: column; align-items: center; gap: 3px;"}>
          <.point_pips solid={@suit_data.boss_pts4} outline={@suit_data.boss_pts3_extra} size={@width * 0.09} />
        </div>
      <% end %>

      <%= if @is_boss do %>
        <div class="kanji" style={"position: absolute; left: 50%; top: 50%; transform: translate(-50%, -50%); font-size: #{@width * 0.85}px; color: #{@suit_data.color}; opacity: 0.07; font-weight: 700; pointer-events: none; line-height: 1;"}>七</div>
      <% end %>

      <%= if @is_a do %>
        <div style={"position: absolute; top: 50%; left: 0; right: 0; transform: translateY(-50%); text-align: center; font-family: var(--serif); font-size: #{@width * 0.36}px; color: var(--shu); font-weight: 700; letter-spacing: 0.02em; text-shadow: 0 0 16px rgba(200, 72, 60, 0.35); pointer-events: none;"}>A</div>
      <% end %>
    </div>
    """
  end
end
