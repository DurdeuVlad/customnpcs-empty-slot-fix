# Investigation log — 2026-09-20

Full evidence trail for both disproven fix attempts, so a future attempt
doesn't repeat either dead end. All commands run against `mc-staging-server`
on home-server-1, woken via the handshake-probe method (see `TESTING.md`)
while idle (`Exited (255) 28 hours ago`, Non-Intrusive Mode).

## Attempt 1: datapack NBT repair — disproven

Deployed `data/cnpc_slot_fix/` (strip `ArmorItems` when all 4 slots are
bare), confirmed it loaded (`datapack list` showed
`[file/customnpcs-empty-slot-fix (world)]`), confirmed it ran (Romica got
tagged `cnpc_slot_fix_checked`) - but:

```
$ docker exec mc-staging-server rcon-cli --port 25575 --password "$PW" \
    "execute as @e[type=customnpcs:customnpc,name=Romica] at @s run data remove entity @s ArmorItems"
Modified entity data of Romica

$ docker exec mc-staging-server rcon-cli --port 25575 --password "$PW" \
    "execute as @e[type=customnpcs:customnpc,name=Romica] at @s run data get entity @s ArmorItems"
Romica has the following entity data: [{}, {}, {}, {}]
```

Removed successfully, reappeared identically within 3 seconds (reproduced
twice: once via the deployed function, once via a direct manual command).
CustomNPCs is actively re-writing this tag from its own live state on some
short interval independent of my datapack. Crucially, **the rewrite itself
does not re-trigger the error** (checked logs immediately after, no new
`Tried to load invalid item` line) — meaning presence of the bad shape in
memory is harmless; the error only fires at the actual disk→memory
deserialization step when a chunk loads. Since CustomNPCs will have already
regenerated the broken shape again before the *next* chunk save regardless
of anything a datapack does mid-session, the persisted data going into the
next load is guaranteed broken again. A datapack cannot intercept the save
step (no such hook exists) or reliably win a per-tick race against the
mod's own rewrite. Conclusion: not fixable at the data layer with a pure
datapack.

## Attempt 2: `-Dlog4j2.configurationFile` override — disproven

Goal: suppress just the console line via a composite log4j2 config
(`classpath:log4j2.xml,/data/log4j2-suppress-itemstack.xml`, later
corrected to an exact jar path) merging in
`<Logger name="net.minecraft.world.item.ItemStack" level="FATAL"/>`.

- First try used `JVM_DD_OPTS` — wrong tool: it mangles the `:` in
  `classpath:log4j2.xml` into `=` when it re-splits the value on both `,`
  and `:`/`=` as if flattening a properties list. Confirmed via
  `docker exec mc-staging-server cat /data/user_jvm_args.txt` showing
  `-Dlog4j2.configurationFile=classpath=log4j2.xml,/data/...` (broken).
  Switched to `JVM_OPTS` (raw args, no re-splitting) - fixed that specific
  corruption.
- Second try: `classpath:log4j2.xml` is ambiguous. **Four** different jars
  on the classpath ship a same-named `log4j2.xml`
  (`com.mojang:logging`, `cpw.mods:modlauncher`,
  `net.neoforged.fancymodloader:loader`, presumably `neoforge` itself), and
  plain `getResource()`-style classpath resolution grabbed the wrong one
  silently (no error, just used a different, incomplete config - confirmed
  by extracting all three found candidates and diffing against the actual
  log format in use; only `fancymodloader/loader-4.0.43.jar`'s copy matches
  our real logs, e.g. the `[minecraft/%logger{1}]` pattern and `debug.log`
  definition). This exact class of bug is a known historical Forge issue:
  [`MinecraftForge/MinecraftForge#8274`](https://github.com/MinecraftForge/MinecraftForge/issues/8274)
  (`ModuleClassLoader`'s unordered `resolvedRoots` map picking the wrong
  same-named resource; fixed for old Forge in 1.18.2-40.0.2, apparently not
  applicable/relevant here since we're overriding explicitly, not relying
  on default resolution).
- Fixed the ambiguity with an exact `jar:file:...!/log4j2.xml` reference to
  the correct jar. **Still didn't suppress the error.**
- Diagnosed with `-Dlog4j2.debug=true` (the correct tool per the Forge issue
  above) and read the StatusLogger trace directly:
  ```
  DEBUG StatusLogger Started configuration ... CompositeConfiguration ...
    configurations=[XmlConfiguration[location=jar:file:.../loader-4.0.43.jar!/log4j2.xml],
                    XmlConfiguration[location=/data/log4j2-suppress-itemstack.xml]] ...
  ...
  DEBUG StatusLogger Loaded configuration from union:/data/libraries/.../loader-4.0.43.jar%2359!/log4j2.xml
  DEBUG StatusLogger Apache Log4j Core 2.22 initializing configuration
    XmlConfiguration[location=union:/data/libraries/.../loader-4.0.43.jar%2359!/log4j2.xml]
  ```
  My composite config genuinely loads and starts successfully — then
  **FancyModLoader reconfigures log4j2 a second time**, later in boot,
  loading *only* its own bundled config via a `union:` URI (FML/JPMS's own
  module-union resource scheme, the `%2359` being an internal module
  session id) and discarding the composite entirely. This is FML
  deliberately reasserting its own logging config after early bootstrap,
  not a config mistake on our end. Any JVM-property-driven external
  override is structurally defeated by this — confirmed the actual error
  still reproduces after this second reconfiguration, on the same live
  server, via the same forceload test as attempt 1.

**Next candidate, not yet tried**: FML's `union:` resource scheme strongly
suggests it aggregates `log4j2.xml` across *all* discovered mod jars (the
same union-filesystem mechanism `MinecraftForge#8274` describes for
regular classpath resources) as part of its own native reconfiguration -
meaning a tiny companion mod jar (empty `mods.toml` + a `log4j2.xml`
fragment) dropped in `mods/` might get picked up automatically by FML's own
merge, since that merge is what's currently winning over any external `-D`
override rather than being bypassable by one. Unverified.

## Reproduction procedure used both times

```bash
PW=$(grep -oP '(?<=^rcon.password=).*' /mnt/raid-storage/mc-staging/data/server.properties)
MARKER=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
docker exec mc-staging-server rcon-cli --port 25575 --password "$PW" \
  "forceload add 3202 -410 3426 -186"   # 225 chunks around world spawn (3314, -298), under the 256 cap
sleep 8
docker logs --since "$MARKER" mc-staging-server 2>&1 | grep -i "invalid item"
docker exec mc-staging-server rcon-cli --port 25575 --password "$PW" "forceload remove all"
```
