defmodule YokaiSeptet.Lobby do
  @moduledoc """
  Thin facade over `YokaiSeptet.GameRoom`. Creates rooms via the
  `YokaiSeptet.RoomSupervisor` and generates collision-free short codes.
  """

  alias YokaiSeptet.GameRoom

  @code_alphabet ~c"ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
  @code_len 6
  @max_attempts 10

  @doc """
  Creates a new room. Returns `{:ok, code}`.

  Modes supported: `"4p"`, `"3p"`, `"2p"`.
  """
  def create_room(mode, host_id, host_name, attempts \\ 0) when mode in ["4p", "3p", "2p"] do
    code = generate_code()

    case DynamicSupervisor.start_child(
           YokaiSeptet.RoomSupervisor,
           {GameRoom, {code, mode, host_id, host_name}}
         ) do
      {:ok, _pid} ->
        {:ok, code}

      {:error, {:already_started, _pid}} when attempts < @max_attempts ->
        create_room(mode, host_id, host_name, attempts + 1)

      {:error, reason} ->
        {:error, reason}
    end
  end

  def lookup(code) do
    case Registry.lookup(YokaiSeptet.RoomRegistry, code) do
      [{pid, _}] -> {:ok, pid}
      [] -> {:error, :not_found}
    end
  end

  defp generate_code do
    1..@code_len
    |> Enum.map(fn _ -> Enum.random(@code_alphabet) end)
    |> List.to_string()
  end
end
