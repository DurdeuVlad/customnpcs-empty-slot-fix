# Runs with @s = one customnpcs:customnpc entity that hasn't been checked yet.
#
# Root cause (confirmed live on rustic-craft-2 staging, 2026-09-20): CustomNPCs-Unofficial
# NeoForge-1.21.1.20251230 writes ArmorItems as a fixed 4-element list, using a bare empty
# compound `{}` (no "id" key) for every unequipped slot - the legacy pre-1.20.5 vanilla
# convention. Something in CustomNPCs' own equipment sync/tick path re-parses that tag
# through the modern *required* ItemStack codec instead of the optional one, which does not
# tolerate a keyless compound and logs, per malformed slot:
#   [Server thread/ERROR] [minecraft/ItemStack]: Tried to load invalid item: 'No key id in MapLike[{}]'
# every time the entity is loaded/ticked - unlike vanilla mobs, whose identical-looking
# ArmorItems the vanilla read path checks for emptiness before ever invoking that codec.
#
# Fix: if all 4 slots are bare (no real armor at all - confirmed the case for all 23 sampled
# NPCs on staging: Romica, Sile, Armurierul Gigi, Colectionarul, and 19 more), drop the whole
# ArmorItems tag. Equipment CustomNPCs actually renders/uses lives in the separate "Armor"
# list, so this does not touch any player-visible gear - it only removes vestigial vanilla
# LivingEntity persistence baggage CustomNPCs never populates for these entities.
#
# If any slot DOES contain a real item, don't guess at a transform - leave it alone and
# flag it so a human checks whether this NPC is a legitimate exception to the above.
tag @s add cnpc_slot_fix_checked

execute unless data entity @s ArmorItems[0].id unless data entity @s ArmorItems[1].id unless data entity @s ArmorItems[2].id unless data entity @s ArmorItems[3].id if data entity @s ArmorItems run data remove entity @s ArmorItems

execute if data entity @s ArmorItems[0].id run say [cnpc-slot-fix] WARNING: customnpcs:customnpc has real armor in ArmorItems[0] - left untouched, verify manually
execute if data entity @s ArmorItems[1].id run say [cnpc-slot-fix] WARNING: customnpcs:customnpc has real armor in ArmorItems[1] - left untouched, verify manually
execute if data entity @s ArmorItems[2].id run say [cnpc-slot-fix] WARNING: customnpcs:customnpc has real armor in ArmorItems[2] - left untouched, verify manually
execute if data entity @s ArmorItems[3].id run say [cnpc-slot-fix] WARNING: customnpcs:customnpc has real armor in ArmorItems[3] - left untouched, verify manually
