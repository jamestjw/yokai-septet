defmodule YokaiSeptetWeb.RoomLive do
  @moduledoc """
  Waiting room for a multiplayer table. Shows seat assignments and lets the
  host fill empty seats with AI and start the game. Subscribes to
  `"room:<code>"` so all players see updates in real time.
  """
  use YokaiSeptetWeb, :live_view

  alias YokaiSeptet.{GameRoom, Lobby}

  @impl true
  def mount(%{"code" => code} = params, session, socket) do
    code = String.upcase(code)
    player_id = session["player_id"]
    name = String.trim(params["name"] || session["player_name"] || "Player")

    case Lobby.lookup(code) do
      {:error, _} ->
        {:ok,
         socket
         |> put_flash(:error, "No room with code #{code}")
         |> push_navigate(to: ~p"/lobby/join"), layout: false}

      {:ok, _pid} ->
        if connected?(socket) do
          Phoenix.PubSub.subscribe(YokaiSeptet.PubSub, "room:#{code}")

          case GameRoom.join(code, player_id, name) do
            {:ok, _seat} ->
              GameRoom.register_view(code, player_id, self())

            _ ->
              :ok
          end
        end

        {:ok, snap} = GameRoom.snapshot(code)

        # If the game already started, jump to the table.
        socket =
          if snap.phase == :playing do
            push_navigate(socket, to: ~p"/play/room/#{code}")
          else
            socket
          end

        {:ok,
         socket
         |> assign(
           code: code,
           player_id: player_id,
           name: name,
           snap: snap
         ), layout: false}
    end
  end

  @impl true
  def handle_event("fill_ai", _, socket) do
    GameRoom.fill_with_ai(socket.assigns.code, socket.assigns.player_id)
    {:noreply, socket}
  end

  def handle_event("kick_ai", %{"seat" => seat}, socket) do
    GameRoom.kick_ai(socket.assigns.code, socket.assigns.player_id, String.to_integer(seat))
    {:noreply, socket}
  end

  def handle_event("claim", %{"seat" => seat}, socket) do
    GameRoom.claim_seat(socket.assigns.code, socket.assigns.player_id, String.to_integer(seat))
    {:noreply, socket}
  end

  def handle_event("start", _, socket) do
    GameRoom.start_game(socket.assigns.code, socket.assigns.player_id)
    {:noreply, socket}
  end

  def handle_event("nav_home", _, socket),
    do: {:noreply, push_navigate(socket, to: ~p"/")}

  @impl true
  def handle_info({:room_updated, snap}, socket) do
    socket =
      if snap.phase == :playing do
        push_navigate(socket, to: ~p"/play/room/#{socket.assigns.code}")
      else
        socket
      end

    {:noreply, assign(socket, snap: snap)}
  end

  @impl true
  def render(assigns) do
    snap = assigns.snap
    is_host = snap.host_id == assigns.player_id
    has_empty = Enum.any?(snap.seats, &match?({:empty}, &1))
    can_start = is_host and not has_empty

    assigns =
      assign(assigns,
        is_host: is_host,
        has_empty: has_empty,
        can_start: can_start
      )

    ~H"""
    <div
      class="washi-bg"
      style="min-height: 100vh; display: flex; align-items: center; justify-content: center; padding: 40px;"
    >
      <div class="washi-card slide-up" style="max-width: 640px; width: 100%; padding: 40px;">
        <div style="display: flex; justify-content: space-between; align-items: flex-start; margin-bottom: 28px;">
          <div>
            <div class="eyebrow">対局室 · Room</div>
            <h1
              class="kanji"
              style="font-size: 32px; margin: 8px 0 4px; font-weight: 500; color: var(--sumi);"
            >
              {@snap.mode |> String.upcase()} Table
            </h1>
            <p style="color: var(--sumi-mute); font-style: italic; margin: 0;">
              <%= if @is_host do %>
                You are hosting. Share the code below.
              <% else %>
                Waiting for the host to start.
              <% end %>
            </p>
          </div>
          <button phx-click="nav_home" class="btn btn-ghost">Leave</button>
        </div>

        <div style="background: var(--washi-warm); border: 1px solid var(--line); padding: 20px 24px; margin-bottom: 28px; border-radius: 2px;">
          <div class="eyebrow" style="margin-bottom: 6px;">Room code</div>
          <div style="display: flex; align-items: center; justify-content: space-between; gap: 16px;">
            <div
              class="kanji"
              style="font-size: 38px; letter-spacing: 0.3em; color: var(--shu); font-weight: 600;"
            >
              {@code}
            </div>
            <div style="font-size: 12px; color: var(--sumi-mute); font-family: var(--sans); max-width: 260px; text-align: right;">
              Share this code or send the link in your browser's address bar.
            </div>
          </div>
        </div>

        <div class="eyebrow" style="margin-bottom: 12px;">Seats</div>
        <div style="display: grid; gap: 10px; margin-bottom: 28px;">
          <%= for {seat, idx} <- Enum.with_index(@snap.seats) do %>
            <.seat_row seat={seat} idx={idx} is_host={@is_host} player_id={@player_id} />
          <% end %>
        </div>

        <div style="display: flex; gap: 12px; justify-content: flex-end;">
          <%= if @is_host and @has_empty do %>
            <button phx-click="fill_ai" class="btn btn-ghost">
              <span class="kanji">補</span> Fill empty with AI
            </button>
          <% end %>
          <%= if @is_host do %>
            <button
              phx-click="start"
              class="btn btn-shu"
              disabled={not @can_start}
              style={"opacity: #{if @can_start, do: 1, else: 0.4}; cursor: #{if @can_start, do: "pointer", else: "not-allowed"};"}
            >
              <span class="kanji">始</span> Start Game
            </button>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  attr :seat, :any, required: true
  attr :idx, :integer, required: true
  attr :is_host, :boolean, required: true
  attr :player_id, :string, required: true

  defp seat_row(assigns) do
    {label, sub, kind, mine?} =
      case assigns.seat do
        {:empty} ->
          {"Empty", "Waiting…", :empty, false}

        {:ai, name} ->
          {name, "AI", :ai, false}

        {:human, pid, name, status} ->
          {name, if(status == :connected, do: "Connected", else: "Disconnected — AI playing"),
           :human, pid == assigns.player_id}
      end

    assigns = assign(assigns, label: label, sub: sub, kind: kind, mine?: mine?)

    ~H"""
    <div style={
      "display: flex; align-items: center; gap: 16px; padding: 14px 18px;" <>
      " border: 1px solid #{if @mine?, do: "var(--shu)", else: "var(--line)"};" <>
      " background: #{if @mine?, do: "rgba(196, 30, 58, 0.05)", else: "transparent"};" <>
      " border-radius: 2px;"
    }>
      <div style={
        "width: 36px; height: 36px; display: flex; align-items: center; justify-content: center;" <>
        " font-family: var(--kanji); font-size: 18px; font-weight: 600; border-radius: 2px;" <>
        " background: " <> case @kind do
          :empty -> "transparent; border: 1px dashed var(--line-strong); color: var(--sumi-mute)"
          :ai -> "var(--sumi-soft); color: var(--washi)"
          :human -> "var(--shu); color: var(--washi)"
        end <> ";"
      }>
        {String.first(@label)}
      </div>
      <div style="flex: 1;">
        <div style="font-size: 15px; font-weight: 500; color: var(--sumi);">
          {@label} {if @mine?, do: "(you)", else: ""}
        </div>
        <div style="font-size: 12px; color: var(--sumi-mute); font-style: italic;">{@sub}</div>
      </div>
      <div style="font-family: var(--sans); font-size: 11px; letter-spacing: 0.2em; text-transform: uppercase; color: var(--sumi-mute);">
        Seat {@idx + 1}
      </div>
      <%= cond do %>
        <% @kind == :empty -> %>
          <button
            phx-click="claim"
            phx-value-seat={@idx}
            class="btn btn-ghost"
            style="padding: 6px 14px; font-size: 11px;"
          >
            Take seat
          </button>
        <% @kind == :ai and @is_host -> %>
          <button
            phx-click="kick_ai"
            phx-value-seat={@idx}
            class="btn btn-ghost"
            style="padding: 6px 14px; font-size: 11px;"
          >
            Remove
          </button>
        <% true -> %>
          <span></span>
      <% end %>
    </div>
    """
  end
end
