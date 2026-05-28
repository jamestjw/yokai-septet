defmodule YokaiSeptetWeb.Plugs.GuestId do
  @moduledoc """
  Ensures the session has a stable `:player_id` so the GameRoom can
  recognize a returning player and let them reclaim their seat.
  """
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    case get_session(conn, :player_id) do
      nil ->
        id =
          :crypto.strong_rand_bytes(12)
          |> Base.url_encode64(padding: false)

        put_session(conn, :player_id, id)

      _ ->
        conn
    end
  end
end
