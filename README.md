# customnpcs-empty-slot-fix

Investigation + attempted fixes for a console-spam bug in
[`CustomNPCs-Unofficial`](https://github.com/BetaZavr/CustomNPCs-Unofficial)
(NeoForge build `1.21.1.20251230`, SHA-1 `E2F3B58CEB5AAC4021D7BFD130E320925581471B`)
on rustic-craft-2 staging.

## Status: not fixed yet

Two approaches were tried and disproven live on 2026-09-20. See
[`INVESTIGATION.md`](INVESTIGATION.md) for the full evidence trail. Short
version:

1. **Datapack NBT repair** (`data/cnpc_slot_fix/`, kept in this repo for
   reference/reuse) — strips the malformed tag from loaded entities. Doesn't
   work: CustomNPCs rewrites the tag back within seconds from its own live
   state, so whatever's on disk at the next chunk save is broken again
   regardless. Confirmed by removing it twice and watching it reappear.
2. **Log4j2 console suppression via `-Dlog4j2.configurationFile`** — doesn't
   work either: NeoForge's FancyModLoader re-initializes log4j2 a second
   time late in boot, loading only its own bundled config via a `union:`
   (JPMS module) URI and discarding any JVM-property-driven override.
   Confirmed via `-Dlog4j2.debug=true` StatusLogger trace.

**Most promising untested next step**: package the log4j2 suppression rule
as a fragment inside a minimal companion mod jar (just `mods.toml` +
`log4j2.xml`, no Java code) dropped in `mods/`, so FML's own union-based
resource merging picks it up natively instead of fighting it via an external
JVM flag. Not yet built or tested — needs verifying NeoForge 21.1.x still
honors per-mod-jar `log4j2.xml` fragments the way older Forge did.

## The bug

Every `customnpcs:customnpc` entity persists a vanilla-style `ArmorItems` NBT
list — a fixed 4-element array (boots/leggings/chestplate/helmet), using a
bare empty compound `{}` (no `id` key) for each unequipped slot. That's the
legacy pre-1.20.5 vanilla convention for "nothing in this slot."

Some code path in this CustomNPCs build re-parses that tag through the modern
*required* `ItemStack` codec instead of the optional one. The required codec
has no concept of "empty" — it needs a real `id` — so it throws, once per
malformed slot, when the entity's chunk loads from disk:

```
[Server thread/ERROR] [minecraft/ItemStack]: Tried to load invalid item: 'No key id in MapLike[{}]'
```

Vanilla mobs have the exact same-looking `ArmorItems: [{},{},{},{}]` and
never hit this — vanilla's own read path checks for emptiness before
invoking the codec. This is specific to whatever CustomNPCs does with the
tag (equipment sync to tracking clients is the leading suspect, unconfirmed
without decompiling the shipped jar) — and, per the datapack experiment
above, CustomNPCs rewrites this tag continuously from its own in-memory
state regardless of what's on disk, so the error is tied to the
disk→memory chunk-load moment specifically, not to the data merely existing.

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
same bug; not yet individually sampled.)

## What's in this repo

- `data/cnpc_slot_fix/` — the datapack from attempt #1. Harmless to deploy
  (it only ever strips already-provably-empty slots or leaves data alone and
  logs a warning), but it does **not** stop the console spam. Kept because
  the tag-based "process each entity once" pattern is reusable if a real
  fix point is ever found.
- `INVESTIGATION.md` — full evidence trail for both disproven approaches,
  so the next attempt doesn't repeat either one.
- `TESTING.md` — the Intrusive / Non-Intrusive mode policy for touching the
  live staging server, and the handshake-based wake procedure used
  throughout this investigation.
