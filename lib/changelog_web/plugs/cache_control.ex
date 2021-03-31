defmodule ChangelogWeb.Plug.CacheControl do
  @moduledoc """
  Manages the adding of cache-control headers to public requests so CDN
  can do some caching
  """
  import Plug.Conn

  def init(opts), do: opts

  def call(conn = %{assigns: %{current_user: user}}, _opts) when not is_nil(user), do: conn

  def call(conn, _opts) do
    conn
    |> put_resp_header("cache-control", "no-store, must-revalidate")
    |> put_resp_header(
      "surrogate-control",
      "max-age=60, stale-while-revalidate=60, stale-if-error=604800"
    )
  end
end
