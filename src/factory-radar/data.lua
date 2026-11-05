-- Factory Radar: иконка окна, кнопка быстрого доступа, горячая клавиша
data:extend({
  {type = "sprite", name = "tr-radar-white", filename = "__factory-radar__/graphics/radar-white-64.png",
   size = 64, flags = {"gui-icon"}, mipmap_count = 1},
  {type = "sprite", name = "tr-map-frame", filename = "__factory-radar__/graphics/map-frame-32.png",
   size = 32, flags = {"gui-icon"}, mipmap_count = 2},
  {type = "custom-input", name = "tr-toggle", key_sequence = "CONTROL + SHIFT + R", consuming = "none", action = "lua"},
})
if settings.startup["tr-s-shortcut"].value then
  data:extend({
    {type = "shortcut", name = "tr-toggle", action = "lua", associated_control_input = "tr-toggle",
     -- тёмно-серый значок как у игры и других модов, 32 и 24 px
     icon = "__factory-radar__/graphics/radar-shortcut-32.png", icon_size = 32,
     small_icon = "__factory-radar__/graphics/radar-shortcut-24.png", small_icon_size = 24,
     order = "t[factory-radar]"},
  })
end

-- молния для удара по игроку: тот же прототип, что на планете с грозами, но без урона и энергии
-- если прототипа нет, zap.lua рисует свою
local storm = data.raw["lightning"] and data.raw["lightning"]["lightning"]
if storm then
  local bolt = table.deepcopy(storm)
  bolt.name = "tr-lightning"
  -- в 2.0 урон — число, в 2.1 — таблица {amount, type}
  if type(bolt.damage) == "table" then bolt.damage = {amount = 0, type = bolt.damage.type or "electric"} else bolt.damage = 0 end
  bolt.energy = "1J"
  bolt.hidden = true
  bolt.hidden_in_factoriopedia = true
  bolt.factoriopedia_simulation = nil
  data:extend({bolt})
end

-- ракета викторины делается в data-final-fixes.lua (после всех модов)
