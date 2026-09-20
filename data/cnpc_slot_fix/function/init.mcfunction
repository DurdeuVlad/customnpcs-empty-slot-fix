# Fires once per datapack (re)load / server start. Kicks off the self-rescheduling
# repair loop; see on_tick.mcfunction for why this can't be a one-shot #minecraft:load
# pass alone (entities in not-yet-loaded chunks at boot are missed otherwise).
schedule function cnpc_slot_fix:on_tick 1t replace
