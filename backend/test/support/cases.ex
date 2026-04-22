defmodule Chat.DataCase do
  @moduledoc """
  Base case for context/schema tests.
  Sets up the Ecto sandbox for transaction rollback between tests.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      alias Chat.Repo
      import Ecto.Query
      import Chat.DataCase
    end
  end

  setup tags do
    Chat.DataCase.setup_sandbox(tags)
    :ok
  end

  def setup_sandbox(tags) do
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(Chat.Repo, shared: not tags[:async])
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
  end

  @doc "Extracts changeset errors as a map of field => [message]."
  def errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end

defmodule ChatWeb.ConnCase do
  @moduledoc "Base case for controller/HTTP tests."

  use ExUnit.CaseTemplate

  using do
    quote do
      use Phoenix.ConnTest
      alias ChatWeb.Router.Helpers, as: Routes
      import Chat.DataCase, only: [errors_on: 1]
      @endpoint ChatWeb.Endpoint
    end
  end

  setup tags do
    Chat.DataCase.setup_sandbox(tags)
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end
end

defmodule ChatWeb.ChannelCase do
  @moduledoc "Base case for Phoenix Channel tests."

  use ExUnit.CaseTemplate

  using do
    quote do
      use Phoenix.ChannelTest
      import Chat.DataCase, only: [errors_on: 1]
      @endpoint ChatWeb.Endpoint
    end
  end

  setup tags do
    Chat.DataCase.setup_sandbox(tags)
    :ok
  end
end
