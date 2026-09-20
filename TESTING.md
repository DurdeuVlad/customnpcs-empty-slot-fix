# Intrusive / Non-Intrusive testing policy

`mc-staging-server` is a shared friend-facing test server (see
`compose/ARCHITECTURE.md` in `mc-staging`), not a disposable sandbox. Any
work here — this fix or anything else that needs to restart/reload the live
server — follows this rule before touching it.

## Step 1: check who's actually on the server

```bash
docker ps --filter "name=mc-staging-server" --format "{{.Status}}"
```

- `Exited (...)` → nobody has connected recently enough to keep it awake
  (`lazymc.time.sleep_after=300`s of no players). Skip to **Non-Intrusive
  Mode**.
- `Up ...` → someone *may* be on. Confirm with:

```bash
PW=$(grep -oP '(?<=^rcon.password=).*' /mnt/raid-storage/mc-staging/data/server.properties)
docker exec mc-staging-server rcon-cli --port 25575 --password "$PW" "list"
```

  - `0 of a max of N players online` → check how long it's been empty by
    scanning for the last "left the game" line:
    `docker logs mc-staging-server 2>&1 | grep -E "joined the game|left the game" | tail -5`
    — if the last departure was **30+ minutes ago**, treat as idle
    → **Non-Intrusive Mode**. If under 30 minutes, treat as **Intrusive
    Mode** (someone may be tabbed out / about to reconnect).
  - Any real names listed → **Intrusive Mode**.

## Non-Intrusive Mode (nobody online, idle 30+ min)

Free to wake, restart, reload datapacks, or stop the server without asking
first, for this specific task. Still:
- Prefer `/reload` (datapack-only reload) over a full container restart when
  only datapack files changed — it's instant and doesn't cost a ~2-4 minute
  modpack reboot.
- Clean up anything temporary you added (`forceload remove all`, test-only
  scoreboard objectives, etc.) before leaving the server idle again.
- Waking from fully asleep (`Exited`) requires a real Minecraft login
  handshake — `lazymc.join.methods=hold,kick` starts the backend on any
  Login-state connection attempt using a name from `whitelist.json`
  (`/mnt/raid-storage/mc-staging/data/whitelist.json`), checked *before* the
  backend even starts. A raw `docker start mc-staging-server` instead fights
  lazymc's own state machine and gets force-killed unpredictably (0-166s
  observed) — don't use it. See the wake-probe approach used to validate
  this fix (a minimal handshake+login-start packet, `100.86.221.67:25565` or
  `10.0.0.1:25565`, protocol `767`).

## Intrusive Mode (someone online, or left less than 30 min ago)

Do not restart, reload, or otherwise touch the running server silently.
Instead:
1. **Announce first**, with real advance notice, e.g.:
   ```bash
   docker exec mc-staging-server rcon-cli --port 25575 --password "$PW" \
     "say [maintenance] Restarting in 2 minutes to test a CustomNPCs console-spam fix - no world/inventory impact expected. Sorry for the interruption!"
   ```
2. Wait a real grace period (at least ~2 minutes) before proceeding, unless
   the player explicitly says go ahead sooner.
3. If the needed verification doesn't require an actual restart (e.g., just
   reading current NBT via `/data get`, or watching logs for the error
   passively), do that instead and skip the restart entirely.
4. If something needs in-game verification you can't do yourself (walking
   somewhere, confirming a visual, etc.) while a real player is on, add a
   task via the `rustic-test-tasks` KubeJS commands (`testtask add ...`)
   instead of interrupting them — pick it up once they're off or once they
   complete it themselves.

## What this fix's own verification used

2026-09-20: server was `Exited (255) 28 hours ago` (Non-Intrusive) before
this fix was built. Woken via the handshake-probe method above using a
whitelisted name, `/forceload add` around world spawn (`3314 -298`, capped
at 225 chunks — vanilla's `/forceload` errors above 256), sampled NPC NBT via
`/data get entity`, then `forceload remove all` to leave world state clean
before letting the server return to idle.
