ExUnit.start()

# Start the token blacklist ETS table used by Chat.Auth
:ets.new(:token_blacklist, [:named_table, :public, :set, read_concurrency: true])

Ecto.Adapters.SQL.Sandbox.mode(Chat.Repo, :manual)
