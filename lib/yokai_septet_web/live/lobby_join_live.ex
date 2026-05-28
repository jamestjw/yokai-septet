defmodule YokaiSeptetWeb.LobbyJoinLive do
  @moduledoc """
  Form to enter a room code and join an existing room.
  """
  use YokaiSeptetWeb, :live_view

  alias YokaiSeptet.Lobby

  @impl true
  def mount(params, session, socket) do
    {:ok,
     assign(socket,
       player_id: session["player_id"],
       name: session["player_name"] || "",
       code: String.upcase(params["code"] || ""),
       error: nil
     ), layout: false}
  end

  @impl true
  def handle_event("join", %{"name" => name, "code" => code}, socket) do
    code = code |> String.trim() |> String.upcase()
    name = String.trim(name)

    cond do
      name == "" ->
        {:noreply, assign(socket, error: "Pick a name first.")}

      code == "" ->
        {:noreply, assign(socket, error: "Enter a room code.")}

      true ->
        case Lobby.lookup(code) do
          {:ok, _pid} ->
            {:noreply, push_navigate(socket, to: ~p"/lobby/#{code}?name=#{name}")}

          {:error, _} ->
            {:noreply, assign(socket, error: "No room with that code.", code: code)}
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
      <div class="washi-card slide-up" style="max-width: 420px; width: 100%; padding: 40px;">
        <div class="eyebrow">参加 · Join a table</div>
        <h1
          class="kanji"
          style="font-size: 36px; margin: 8px 0 24px; font-weight: 500; color: var(--sumi);"
        >
          Join a Room
        </h1>

        <form phx-submit="join">
          <label style="display: block; font-family: var(--sans); font-size: 11px; letter-spacing: 0.2em; text-transform: uppercase; color: var(--sumi-mute); margin-bottom: 8px;">
            Your name
          </label>
          <input
            type="text"
            name="name"
            value={@name}
            placeholder="e.g. Yamato"
            maxlength="20"
            style="width: 100%; padding: 12px 14px; font-size: 16px; border: 1px solid var(--line-strong); background: var(--washi-warm); font-family: inherit; color: var(--sumi); margin-bottom: 20px; border-radius: 2px;"
          />

          <label style="display: block; font-family: var(--sans); font-size: 11px; letter-spacing: 0.2em; text-transform: uppercase; color: var(--sumi-mute); margin-bottom: 8px;">
            Room code
          </label>
          <input
            type="text"
            name="code"
            value={@code}
            placeholder="ABCDEF"
            maxlength="8"
            autocapitalize="characters"
            style="width: 100%; padding: 12px 14px; font-size: 22px; font-family: var(--kanji); letter-spacing: 0.3em; text-transform: uppercase; border: 1px solid var(--line-strong); background: var(--washi-warm); color: var(--sumi); margin-bottom: 24px; border-radius: 2px;"
          />

          <%= if @error do %>
            <p style="color: var(--shu); font-size: 13px; margin-bottom: 16px;">{@error}</p>
          <% end %>

          <div style="display: flex; gap: 12px;">
            <.link navigate={~p"/"} class="btn btn-ghost">Cancel</.link>
            <button type="submit" class="btn btn-shu">
              <span class="kanji">入</span> Join
            </button>
          </div>
        </form>
      </div>
    </div>
    """
  end
end
