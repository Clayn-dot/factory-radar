-- Factory Radar: window icon, quick access button, hotkey
data:extend({
  {type = "sprite", name = "tr-radar-white", filename = "__factory-radar__/graphics/radar-white-64.png",
   size = 64, flags = {"gui-icon"}, mipmap_count = 1},
  {type = "sprite", name = "tr-map-frame", filename = "__factory-radar__/graphics/map-frame-32.png",
   size = 32, flags = {"gui-icon"}, mipmap_count = 2},
  {type = "sprite", name = "tr-win-min-d", filename = "__factory-radar__/graphics/win-min-d-32.png", size = 32, flags = {"gui-icon"}, mipmap_count = 1},
  {type = "sprite", name = "tr-win-max-d", filename = "__factory-radar__/graphics/win-max-d-32.png", size = 32, flags = {"gui-icon"}, mipmap_count = 1},
  {type = "custom-input", name = "tr-toggle", key_sequence = "CONTROL + SHIFT + R", consuming = "none", action = "lua"},
})
if settings.startup["tr-s-shortcut"].value then
  data:extend({
    {type = "shortcut", name = "tr-toggle", action = "lua", associated_control_input = "tr-toggle",
     -- dark grey icon like the game and other mods, 32 and 24 px
     icon = "__factory-radar__/graphics/radar-shortcut-32.png", icon_size = 32,
     small_icon = "__factory-radar__/graphics/radar-shortcut-24.png", small_icon_size = 24,
     order = "t[factory-radar]"},
  })
end

-- lightning for hitting a player: same prototype as on a planet with storms, but no damage and no energy
-- if the prototype is missing, zap.lua draws its own
local storm = data.raw["lightning"] and data.raw["lightning"]["lightning"]
if storm then
  local bolt = table.deepcopy(storm)
  bolt.name = "tr-lightning"
  -- in 2.0 damage is a number, in 2.1 it is a table {amount, type}
  if type(bolt.damage) == "table" then bolt.damage = {amount = 0, type = bolt.damage.type or "electric"} else bolt.damage = 0 end
  bolt.energy = "1J"
  bolt.hidden = true
  bolt.hidden_in_factoriopedia = true
  bolt.factoriopedia_simulation = nil
  data:extend({bolt})
end

-- the quiz rocket is made in data-final-fixes.lua (after all mods)
