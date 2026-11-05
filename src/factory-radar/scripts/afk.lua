-- Factory Radar: плавающее zZz над теми, кто стоит 10+ минут
local C = require("scripts.core")
local M = {}

local PHRASES = 9          -- tr-afk.phrase-1 .. phrase-9
local LIFE = 150           -- сколько тиков живёт буква
local EVERY = 45           -- пауза между буквами

-- раз в 127 тиков: кто в АФК
function M.update_state()
  local d = C.D()
  for _, p in pairs(game.players) do
    local afk = C.S("tr-afk") and p.connected and p.character and p.character.valid and p.afk_time > C.S("tr-s-afk-minutes") * 3600
    d.afk[p.index] = afk and true or nil
    if afk then d.afk_time[p.name] = (d.afk_time[p.name] or 0) + 127 end
  end
end

local function random_text()
  if math.random() < 0.1 then return {"tr-afk.phrase-" .. math.random(PHRASES)}, true end
  local t = {}
  for i = 1, math.random(1, 6) do t[i] = math.random() < 0.5 and "z" or "Z" end
  return table.concat(t), false
end

-- раз в 6 тиков: анимация (без АФК ничего не делает)
function M.animate()
  local d = C.D()
  if not next(d.afk) then
    if next(d.afk_fx) then
      for _, list in pairs(d.afk_fx) do for _, it in pairs(list) do if it.obj.valid then it.obj.destroy() end end end
      d.afk_fx = {}
    end
    return
  end
  local tick = game.tick
  for index, list in pairs(d.afk_fx) do
    local p = game.get_player(index)
    local alive = d.afk[index] and p and p.character and p.character.valid
    local keep = {}
    for _, it in ipairs(list) do
      local age = tick - it.born
      if not alive or age > LIFE or not it.obj.valid or it.obj.target.entity ~= p.character then
        if it.obj.valid then it.obj.destroy() end
      else
        local k = age / LIFE
        it.obj.target = {entity = p.character, offset = {it.x + math.sin(age / 18 + it.phase) * 0.25, -3.8 - k * 2.6}}
        local a = (1 - k) * 0.9
        it.obj.color = {it.c[1] * a, it.c[2] * a, it.c[3] * a, a}
        keep[#keep + 1] = it
      end
    end
    d.afk_fx[index] = keep
  end
  for index in pairs(d.afk) do
    local p = game.get_player(index)
    if p and p.character and p.character.valid then
      d.afk_fx[index] = d.afk_fx[index] or {}
      local list = d.afk_fx[index]
      local last = list[#list]
      if not last or tick - last.born >= EVERY then
        local text, phrase = random_text()
        local c = phrase and {1, 0.9, 0.7} or {0.65 + math.random() * 0.2, 0.8 + math.random() * 0.15, 1}
        local x = (math.random() - 0.5) * 0.4   -- над головой
        local obj = rendering.draw_text{text = text, surface = p.character.surface,
          target = {entity = p.character, offset = {x, -3.8}}, color = c,
          scale = phrase and 1.3 or (1.3 + math.random() * 1.1), alignment = "center", vertical_alignment = "bottom"}
        list[#list + 1] = {obj = obj, born = tick, x = x, phase = math.random() * 6.28, c = c}
      end
    end
  end
end

return M
