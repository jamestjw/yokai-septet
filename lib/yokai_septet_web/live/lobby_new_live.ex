defmodule YokaiSeptetWeb.LobbyNewLive do
  @moduledoc """
  Form to create a new multiplayer room. Player picks a display name and
  a game mode; we create the GameRoom and redirect to `/lobby/:code`.
  """
  use YokaiSeptetWeb, :live_view

  alias YokaiSeptet.Lobby

  @impl true
  def mount(_params, session, socket) do
    {:ok,
     assign(socket,
       player_id: session["player_id"],
       name: session["player_name"] || "",
       mode: "4p",
       error: nil
     ), layout: false}
  end

  @impl true
  def handle_event("set_mode", %{"mode" => m}, socket) when m in ["4p", "3p"],
    do: {:noreply, assign(socket, mode: m)}

  def handle_event("update_name", %{"value" => name}, socket),
    do: {:noreply, assign(socket, name: name)}

  def handle_event("create", %{"name" => name}, socket) do
    name = String.trim(name)

    cond do
      name == "" ->
        {:noreply, assign(socket, error: "Pick a name first.")}

      true ->
        case Lobby.create_room(socket.assigns.mode, socket.assigns.player_id, name) do
          {:ok, code} ->
            {:noreply, push_navigate(socket, to: ~p"/lobby/#{code}?name=#{name}")}

          {:error, _} ->
            {:noreply, assign(socket, error: "Could not create the room. Try again.")}
        end
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div
      class="washi-bg"
      style="min-height: 100vh; display: flex; align-items: center; justify-content: center; padding: 40px;"
    >
      <div class="washi-card slide-up" style="max-width: 480px; width: 100%; padding: 40px;">
        <div class="eyebrow">対局室 · Host a table</div>
        <h1
          class="kanji"
          style="font-size: 36px; margin: 8px 0 24px; font-weight: 500; color: var(--sumi);"
        >
          Create a Room
        </h1>

        <form id="new-room-form" phx-submit="create">
          <label style="display: block; font-family: var(--sans); font-size: 11px; letter-spacing: 0.2em; text-transform: uppercase; color: var(--sumi-mute); margin-bottom: 8px;">
            Your name
          </label>
          <input
            id="new-room-name"
            type="text"
            name="name"
            value={@name}
            phx-keyup="update_name"
            placeholder="e.g. Yamato"
            maxlength="20"
            autofocus
            style="width: 100%; padding: 12px 14px; font-size: 16px; border: 1px solid var(--line-strong); background: var(--washi-warm); font-family: inherit; color: var(--sumi); margin-bottom: 24px; border-radius: 2px;"
          />

          <label style="display: block; font-family: var(--sans); font-size: 11px; letter-spacing: 0.2em; text-transform: uppercase; color: var(--sumi-mute); margin-bottom: 8px;">
            Mode
          </label>
          <div style="display: grid; grid-template-columns: 1fr 1fr; gap: 8px; margin-bottom: 28px;">
            <%= for {id, label, sub} <- [{"4p", "Four Players", "Teams of two"}, {"3p", "Three Players", "Free for all"}] do %>
              <button
                type="button"
                phx-click="set_mode"
                phx-value-mode={id}
                style={
                  "padding: 14px 16px; cursor: pointer; text-align: left;" <>
                  " background: #{if @mode == id, do: "var(--washi-warm)", else: "transparent"};" <>
                  " border: 1px solid #{if @mode == id, do: "var(--sumi)", else: "var(--line)"};" <>
                  " border-left: 3px solid #{if @mode == id, do: "var(--shu)", else: "var(--line)"};" <>
                  " font-family: inherit; border-radius: 2px;"
                }
              >
                <div style="font-size: 15px; font-weight: 500; color: var(--sumi);">{label}</div>
                <div style="font-size: 12px; color: var(--sumi-mute); font-style: italic;">{sub}</div>
              </button>
            <% end %>
          </div>

          <p style="font-size: 12px; color: var(--sumi-mute); margin-bottom: 20px; line-height: 1.5;">
            Two-player multiplayer is not supported yet — play the AI mode for that.
          </p>

          <%= if @error do %>
            <p id="new-room-error" style="color: var(--shu); font-size: 13px; margin-bottom: 16px;">
              {@error}
            </p>
          <% end %>

          <div style="display: flex; gap: 12px;">
            <.link navigate={~p"/"} class="btn btn-ghost">Cancel</.link>
            <button type="submit" class="btn btn-shu">
              <span class="kanji">創</span> Create Room
            </button>
          </div>
        </form>
      </div>
    </div>
    """
  end
end
