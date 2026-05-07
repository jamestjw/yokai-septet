defmodule YokaiSeptetWeb.CustomTelemetry do
  @moduledoc false

  def request_log_level(%Plug.Conn{path_info: ["health" | _]}), do: false
  def request_log_level(_conn), do: :info
end
