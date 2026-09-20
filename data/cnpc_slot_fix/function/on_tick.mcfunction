# Every 10 ticks (0.5s), repair any not-yet-checked customnpcs:customnpc entity that has
# just entered a loaded chunk (walking into range, chunk regen, /summon, etc.). The
# cnpc_slot_fix_checked tag makes this a one-time-per-entity cost after the initial
# backlog of already-loaded NPCs is processed on the first pass.
execute as @e[type=customnpcs:customnpc,tag=!cnpc_slot_fix_checked] at @s run function cnpc_slot_fix:repair_single

schedule function cnpc_slot_fix:on_tick 10t replace
