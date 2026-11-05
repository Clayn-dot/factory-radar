-- Factory Radar: ракета викторины. Копируем настоящую уже после всех модов, чтобы подхватить их правки
-- урон только по силе запустившего (игроки): враги и природа целы
-- утёсы не трогаем
-- тайлы НЕ меняем: на некоторых планетах настоящая ракета делает лаву, а она сносит всё подряд
local proj = data.raw["projectile"]
if not (proj and proj["atomic-rocket"] and proj["atomic-bomb-wave"] and proj["atomic-bomb-ground-zero-projectile"]) then return end

local names = {["atomic-rocket"] = "tr-atomic-rocket", ["atomic-bomb-wave"] = "tr-atomic-wave",
  ["atomic-bomb-ground-zero-projectile"] = "tr-atomic-ground-zero"}

-- меняет ли этот прототип тайлы в своих эффектах?
local function changes_tiles(v, depth)
  if type(v) ~= "table" or (depth or 0) > 12 then return false end
  if v.type == "set-tile" then return true end
  for _, x in pairs(v) do
    if changes_tiles(x, (depth or 0) + 1) then return true end
  end
  return false
end
local function tile_effect_entity(name)
  if type(name) ~= "string" then return false end
  if name:find("^nuke%-effects%-") then return true end        -- эффекты базы и Space Age
  for _, kind in ipairs({"explosion", "smoke-with-trigger", "fire", "sticker"}) do
    local e = data.raw[kind] and data.raw[kind][name]
    if e and changes_tiles(e) then return true end              -- то же, но под другим именем из чужого мода
  end
  return false
end

local function fix(t)
  if type(t) ~= "table" then return end
  for i = #t, 1, -1 do
    local x = t[i]
    if type(x) == "table" then
      if x.type == "destroy-cliffs" or x.type == "set-tile"
        or (x.type == "create-entity" and tile_effect_entity(x.entity_name)) then
        table.remove(t, i)
      end
    end
  end
  if t.type == "area" or t.type == "direct" then t.force = "same" end
  if type(t.projectile) == "string" and names[t.projectile] then t.projectile = names[t.projectile] end
  for _, v in pairs(t) do fix(v) end
end

local copies = {}
for from, to in pairs(names) do
  local c = table.deepcopy(proj[from])
  c.name = to
  fix(c.action)
  copies[#copies + 1] = c
end
data:extend(copies)
