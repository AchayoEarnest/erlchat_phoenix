defmodule Chat.Repo do
  use Ecto.Repo,
    otp_app: :chat,
    adapter: Ecto.Adapters.Postgres

  @doc """
  Paginate a query using cursor-based pagination.
  Returns {items, next_cursor}.
  """
  def paginate(query, opts \\ []) do
    limit  = Keyword.get(opts, :limit, 50)
    before = Keyword.get(opts, :before, nil)

    import Ecto.Query

    query =
      if before do
        where(query, [m], m.inserted_at < ^before)
      else
        query
      end

    items = query |> limit(^limit) |> all()
    {items, List.last(items)}
  end
end
