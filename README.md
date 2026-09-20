# customnpcs-empty-slot-fix

A Minecraft 1.21.1 datapack that silences a console-spam bug in
[`CustomNPCs-Unofficial`](https://github.com/BetaZavr/CustomNPCs-Unofficial)
(NeoForge build `1.21.1.20251230`, SHA-1 `E2F3B58CEB5AAC4021D7BFD130E320925581471B`)
without touching the mod jar.

## The bug

Every `customnpcs:customnpc` entity persists a vanilla-style `ArmorItems` NBT
list — a fixed 4-element array (boots/leggings/chestplate/helmet), using a
bare empty compound `{}` (no `id` key) for each unequipped slot. That's the
legacy pre-1.20.5 vanilla convention for "nothing in this slot."

Some code path in this CustomNPCs build re-parses that tag through the modern
*required* `ItemStack` codec instead of the optional one. The required codec
has no concept of "empty" — it needs a real `id` — so it throws, and the
server logs, once per malformed slot, every time the entity loads or ticks:

```
[Server thread/ERROR] [minecraft/ItemStack]: Tried to load invalid item: 'No key id in MapLike[{}]'
```

Vanilla mobs have the exact same-looking `ArmorItems: [{},{},{},{}]` and never
hit this — vanilla's own read path checks for emptiness before invoking the
codec. This is specific to whatever CustomNPCs does with the tag afterward
(equipment sync to tracking clients is the leading suspect, unconfirmed
without decompiling the shipped jar).

Confirmed known bug *class*, not unique to this pack:
[`TwelveIterations/TrashSlot#133`](https://github.com/TwelveIterations/TrashSlot/issues/133)
hit the identical message from an unrelated mod for the same reason (dense
list with bare-empty placeholders vs. the strict 1.21 item codec).

### Confirmed on rustic-craft-2 staging, 2026-09-20

Live-reproduced by force-loading the spawn/market chunks (world spawn
`3314, 145, -298`) and inspecting raw entity NBT via RCON. **All 23 sampled
`customnpcs:customnpc` entities** near spawn (Romica, Sile, Armurierul Gigi,
Colectionarul, Colectionara, Fiul/Fiica Colectionarului, Fierarul țepar,
Romica Permisivul, Marian, Dodel, Padurarul Gioni, Fernando, Lena, Lenghel,
Bucatareasa Angi, Harwin, Teor, Barmanul Cigan, Ianos, Mexicanu', Rolando,
Moris, Noris) had the identical `ArmorItems: [{}, {}, {}, {}]` shape — this
is a mod-wide default, not specific to any one NPC type. (Straja/demon-tagged
NPCs elsewhere on the map are expected to share the same entity type and the
same bug; not yet individually sampled — see `TESTING.md`.)

## The fix

`data/cnpc_slot_fix/function/repair_single.mcfunction`, driven by a
self-rescheduling `#minecraft:load` → `schedule function ... 10t replace`
loop (see `on_tick.mcfunction`) rather than a one-shot load hook, so it also
catches NPCs in chunks that load later in a session (walking into a new
area), not just what's loaded at server boot:

- If **all 4** `ArmorItems` slots are bare (no `id` key at all): removes the
  whole `ArmorItems` tag from that entity. CustomNPCs' actual equipped-gear
  state lives in a separate `Armor` list it manages itself — `ArmorItems` is
  vestigial vanilla `LivingEntity` persistence baggage CustomNPCs never
  populates for its own entities, so this is a no-op for gameplay/visuals.
- If **any** slot has a real `id`: leaves the entity untouched and broadcasts
  a `[cnpc-slot-fix] WARNING: ... left untouched, verify manually` line (also
  lands in the server console log) instead of guessing at a transform. No
  NPC in the 23 sampled had real armor in this tag, so this path is a safety
  net for a case that hasn't actually been observed yet, not a confirmed
  scenario.
- Each entity is marked with the `cnpc_slot_fix_checked` tag after its first
  pass, so this is a one-time cost per entity (cheap to leave running
  indefinitely — new NPCs get caught automatically going forward too).

## Install

Drop this directory in `/mnt/raid-storage/mc-staging/data/datapacks/` on
home-server-1 (the itzg image syncs `data/datapacks/` into
`world/datapacks/` on container start) and restart/reload the server.
`pack_format: 48` matches this server's other datapacks
(`disable_vanilla_ores`, `rustic-balances`).

## Testing rules for this repo

See [`TESTING.md`](TESTING.md) for the Intrusive / Non-Intrusive mode policy
that governs when this fix (or anything else touching `mc-staging-server`)
may restart the live staging server.
