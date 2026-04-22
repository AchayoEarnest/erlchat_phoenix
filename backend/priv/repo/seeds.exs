# priv/repo/seeds.exs
# Run with: mix run priv/repo/seeds.exs

alias Chat.{Repo, Auth, Rooms}
alias Chat.Accounts.User

IO.puts("🌱 Seeding database...")

# ── Admin user ────────────────────────────────────────────────
{:ok, %{user: admin}} =
  Auth.register(%{
    "username" => "admin",
    "email"    => "admin@erlchat.io",
    "password" => "Admin@1234!",
    "role"     => "admin"
  })

IO.puts("✓ Admin user: admin@erlchat.io / Admin@1234!")

# ── Demo users ────────────────────────────────────────────────
{:ok, %{user: alice}} =
  Auth.register(%{
    "username" => "alice",
    "email"    => "alice@erlchat.io",
    "password" => "Password1!",
    "role"     => "user"
  })

{:ok, %{user: bob}} =
  Auth.register(%{
    "username" => "bob",
    "email"    => "bob@erlchat.io",
    "password" => "Password1!",
    "role"     => "user"
  })

IO.puts("✓ Demo users: alice, bob (password: Password1!)")

# ── Default rooms ─────────────────────────────────────────────
{:ok, general} =
  Rooms.create_room(
    %{"name" => "general", "type" => "public", "description" => "General discussion for everyone"},
    admin.id
  )

{:ok, random} =
  Rooms.create_room(
    %{"name" => "random", "type" => "public", "description" => "Off-topic and fun stuff"},
    admin.id
  )

{:ok, _announcements} =
  Rooms.create_room(
    %{"name" => "announcements", "type" => "private", "description" => "Important announcements"},
    admin.id
  )

IO.puts("✓ Default rooms: #general, #random, #announcements")

# ── Join demo users to public rooms ───────────────────────────
Rooms.join_room(general.id, alice.id)
Rooms.join_room(general.id, bob.id)
Rooms.join_room(random.id, alice.id)
Rooms.join_room(random.id, bob.id)

IO.puts("✓ alice and bob joined #general and #random")

# ── Seed messages ─────────────────────────────────────────────
{:ok, msg1} =
  Chat.Messages.create_message(%{
    room_id:   general.id,
    sender_id: admin.id,
    content:   "Welcome to ErlChat! 🎉 This is built with Phoenix + Elixir.",
    msg_type:  "text"
  })

{:ok, _msg2} =
  Chat.Messages.create_message(%{
    room_id:   general.id,
    sender_id: alice.id,
    content:   "Hey everyone! Glad to be here.",
    msg_type:  "text"
  })

{:ok, reply} =
  Chat.Messages.create_message(%{
    room_id:   general.id,
    sender_id: bob.id,
    content:   "This real-time chat is incredibly fast! 🚀",
    msg_type:  "text",
    thread_id: msg1.id
  })

IO.puts("✓ Seeded example messages with a thread reply")

IO.puts("\n✅ Seed complete! Open http://localhost:8080/health to verify.")
