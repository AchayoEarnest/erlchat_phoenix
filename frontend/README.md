# ErlChat — Phoenix Edition

Production real-time chat built on **Elixir + Phoenix 1.7** + **Next.js 14**.  
Replaces the manual Erlang OTP plumbing with Phoenix's battle-tested abstractions.

---

## What Changed: Erlang → Phoenix

| Concern | Erlang (v1) | Phoenix (v2) |
|---------|------------|--------------|
| **HTTP server** | Cowboy (manual routes) | Bandit + Phoenix Router |
| **WebSocket** | Custom frame parser in `ws_handler.erl` | Phoenix Channels (heartbeat, ref tracking, reconnect built-in) |
| **Real-time pub/sub** | Manual ETS + `room_worker` gen_server | `Phoenix.PubSub` (PG2 local, Redis multi-node) |
| **Online tracking** | `presence_manager.erl` (ETS) | `Phoenix.Presence` (CRDT, multi-node safe) |
| **Database** | Hand-rolled `db_pool.erl` + raw SQL | Ecto + `DBConnection` pool |
| **Schemas** | Erlang records | Ecto schemas with changesets |
| **Auth** | Manual JOSE JWT | Joken (clean HS256 API) |
| **Migrations** | `schema.sql` run manually | `mix ecto.migrate` / `Chat.Release.migrate()` |
| **JS client** | Custom raw WebSocket class | `phoenix` npm package (official client) |
| **Observability** | `lager` + custom analytics | Phoenix LiveDashboard + Telemetry |

---

## Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│                       Nginx (TLS, rate limits)                   │
└────────────────────┬──────────────────────┬──────────────────────┘
                     │                      │
         ┌───────────▼──────────┐  ┌────────▼─────────────────────┐
         │   Next.js Frontend   │  │   Phoenix Backend (Bandit)   │
         │   (App Router + TS)  │  │                              │
         │   phoenix npm client │  │  /socket  → UserSocket       │
         │                      │  │    room:* → RoomChannel      │
         └──────────────────────┘  │    user:* → UserChannel      │
                                   │                              │
                                   │  Phoenix.PubSub              │
                                   │  Phoenix.Presence (CRDT)     │
                                   │  Ecto Repo (DBConnection)    │
                                   └──────┬───────────────────────┘
                                          │
                           ┌──────────────┼──────────────┐
                           │              │              │
                 ┌──────────▼────┐  ┌─────▼────┐  ┌─────▼──────┐
                 │  PostgreSQL   │  │  Redis   │  │ Local/S3   │
                 │  (Ecto pool)  │  │ (PubSub) │  │  uploads   │
                 └───────────────┘  └──────────┘  └────────────┘
```

### OTP Supervision Tree

```
Chat.Supervisor  (one_for_one)
├── Chat.Repo               — Ecto PostgreSQL pool (DBConnection)
├── Phoenix.PubSub          — PG2 (local) or Redis (multi-node)
├── Chat.Presence           — Phoenix Presence (CRDT online tracking)
├── ChatWeb.Endpoint        — Bandit HTTP + Phoenix WebSocket
├── Chat.RateLimiter        — ETS token bucket (GenServer)
├── Chat.MessageQueue       — Offline buffer (GenServer + ETS)
├── Chat.Analytics          — Metrics aggregator (GenServer)
└── Telemetry.ConsoleReporter
```

---

## Quick Start

### Prerequisites
- Docker 24+ with Compose V2

### 1. Clone and configure

```bash
git clone https://github.com/your-org/erlchat && cd erlchat
cp .env.example .env

# Edit .env — at minimum, set:
#   SECRET_KEY_BASE  (run: mix phx.gen.secret)
#   JWT_SECRET       (run: openssl rand -hex 32)
#   DB_PASS
nano .env
```

### 2. TLS certificate (dev)

```bash
mkdir -p ssl
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout ssl/key.pem -out ssl/cert.pem \
    -subj "/CN=localhost"
```

### 3. Start

```bash
docker compose up -d
docker compose logs -f backend   # watch migrations + startup
```

### 4. Open

- App: https://localhost
- LiveDashboard (dev): http://localhost:8080/dashboard
- Health: http://localhost:8080/health

**Default credentials** (from seeds): `admin@erlchat.io` / `Admin@1234!`

---

## Local Development

### Backend

```bash
cd backend

# Install Elixir 1.16 + OTP 26 (via asdf or mise):
asdf install

# Install deps
mix deps.get

# Set up DB
export DB_HOST=localhost DB_USER=chatuser DB_PASS=chatpass
export JWT_SECRET=dev_secret_min_32_characters_long!!
mix ecto.setup       # create + migrate + seed

# Run dev server (hot reload)
mix phx.server
# → http://localhost:8080
```

### Frontend

```bash
cd frontend
npm install

cat > .env.local << 'EOF'
NEXT_PUBLIC_API_URL=http://localhost:8080
NEXT_PUBLIC_WS_URL=ws://localhost:8080/socket
EOF

npm run dev
# → http://localhost:3000
```

---

## Project Structure

```
erlchat_phoenix/
├── backend/
│   ├── mix.exs
│   ├── Dockerfile
│   ├── config/
│   │   ├── config.exs        # base config
│   │   ├── dev.exs
│   │   ├── test.exs
│   │   └── runtime.exs       # env-var secrets (prod)
│   ├── lib/
│   │   ├── chat/
│   │   │   ├── application.ex          # OTP app + supervisor
│   │   │   ├── repo.ex                 # Ecto Repo
│   │   │   ├── release.ex              # prod migration runner
│   │   │   ├── presence.ex             # Phoenix.Presence
│   │   │   ├── telemetry.ex            # LiveDashboard metrics
│   │   │   ├── support_workers.ex      # RateLimiter, MessageQueue, Analytics
│   │   │   ├── schemas.ex              # All Ecto schemas
│   │   │   ├── accounts/auth.ex        # Auth context (register/login/JWT)
│   │   │   ├── rooms/rooms.ex          # Rooms context
│   │   │   ├── messages/messages.ex    # Messages context
│   │   │   └── files/files.ex          # Files context (local + S3)
│   │   └── chat_web/
│   │       ├── endpoint_router.ex      # Endpoint + Router
│   │       ├── views.ex                # All JSON views
│   │       ├── channels/channels.ex    # UserSocket + RoomChannel + UserChannel
│   │       ├── controllers/controllers.ex  # All 8 controllers + FallbackController
│   │       └── plugs/plugs.ex          # Auth, CORS, RateLimiter, RequireRole
│   ├── priv/repo/
│   │   ├── migrations/                 # Ecto migrations (timestamped)
│   │   └── seeds.exs
│   └── test/
│       ├── chat/contexts_test.exs      # Auth, Rooms, Messages tests
│       ├── chat_web/channels/
│       │   └── room_channel_test.exs   # Phoenix.ChannelTest
│       └── support/cases.ex            # DataCase, ConnCase, ChannelCase
│
├── frontend/
│   ├── services/phoenix-socket.ts     # Phoenix JS client (replaces raw WS)
│   ├── hooks/useWebSocket.ts           # Same interface, Phoenix backend
│   └── components/chat/ChatWindow.tsx  # Channel-based pagination
│
├── docker-compose.yml
├── nginx.conf                          # (same as v1)
├── .env.example
└── .github/workflows/ci-cd.yml
```

---

## Phoenix Channels — WebSocket Protocol

The frontend uses the official `phoenix` npm package. Connection:

```typescript
import { Socket } from 'phoenix';

const socket = new Socket('ws://localhost:8080/socket', {
  params: { token: accessToken }
});
socket.connect();

const channel = socket.channel('room:general', {});
channel.join();
channel.push('send_message', { content: 'Hello!' });
channel.on('new_message', (msg) => console.log(msg));
```

### Room Channel Events

| Direction | Event | Payload |
|-----------|-------|---------|
| client→server | `send_message` | `{content, thread_id?, msg_type?}` |
| client→server | `typing` | `{is_typing: bool}` |
| client→server | `read_receipt` | `{message_id}` |
| client→server | `load_messages` | `{before: iso8601?}` |
| server→client | `new_message` | Full message object |
| server→client | `message_history` | `{messages: [...]}` |
| server→client | `message_edited` | Full message object |
| server→client | `message_deleted` | `{id}` |
| server→client | `typing` | `{user_id, username, is_typing}` |
| server→client | `reaction_updated` | `{message_id, reaction, user_id}` |
| server→client | `user_joined` | `{user_id}` |
| server→client | `user_left` | `{user_id}` |
| server→client | `presence_state` | Full presence map |
| server→client | `presence_diff` | `{joins, leaves}` |
| server→client | `kicked` | `{reason}` |

---

## Running Tests

```bash
cd backend

# All tests
mix test

# With coverage report
mix coveralls.html
open cover/excoveralls.html

# Specific test file
mix test test/chat/contexts_test.exs

# Only channel tests
mix test test/chat_web/channels/

# Static analysis
mix credo --strict
mix dialyzer
```

---

## Key Phoenix Advantages Over Raw Erlang

**Phoenix Presence** eliminates the entire `presence_manager.erl`. It handles:
- Multi-node sync automatically via CRDT
- Heartbeat-based leave detection (no manual `DOWN` monitoring)
- `presence_diff` events pushed to clients with zero extra code

**Phoenix PubSub** replaces the `room_registry` + `room_worker` broadcast loop. A single `Phoenix.PubSub.broadcast/3` call delivers to all subscribers across all nodes.

**Ecto changesets** give you declarative validation, type casting, and constraint handling that replaces dozens of lines of manual SQL validation.

**Phoenix Channels** handle frame parsing, heartbeat, ref-based reply tracking, and reconnection — replacing the entire `ws_handler.erl`.

---

## Scaling to Multiple Nodes

Switch from local PG2 to Redis PubSub in `.env`:

```bash
REDIS_URL=redis://:password@redis:6379
```

The `application.ex` auto-detects `REDIS_URL` and switches the PubSub adapter. Phoenix Presence CRDT syncs automatically across nodes. Scale the backend service:

```bash
docker compose up -d --scale backend=3
```

---

## Future Improvements

| Feature | Notes |
|---------|-------|
| **Phoenix LiveView admin panel** | Real-time admin dashboard with zero JS |
| **Voice/video** | WebRTC signaling via dedicated Phoenix Channel |
| **AI moderation** | `Chat.Messages.create_message/1` → async Claude API check |
| **End-to-end encryption** | Signal Protocol; key exchange on DM room join |
| **Mnesia** | Replace ETS workers with distributed Mnesia for multi-node state |
| **GraphQL** | Absinthe + Absinthe Phoenix for typed API subscriptions |
