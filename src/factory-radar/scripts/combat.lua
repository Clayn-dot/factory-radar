-- Factory Radar: бой (убийства по оружию, планетам, врагам) и эволюция
local C = require("scripts.core")
local M = {}

local TURRETS = {["turret"] = true, ["ammo-turret"] = true, ["electric-turret"] = true, ["fluid-turret"] = true,
  ["artillery-turret"] = true}
local VEHICLES = {["car"] = true, ["spider-vehicle"] = true, ["locomotive"] = true, ["cargo-wagon"] = true,
  ["fluid-wagon"] = true, ["artillery-wagon"] = true}

---------------------------------------------------------------- чья сила считается врагом
-- работает и с модовыми врагами (свои силы), не только с ванильным enemy
-- кэш пересобирается из состояния игры, на мультиплеер не влияет
local cache = {}
function M.reset_cache() cache = {} end
function M.is_enemy_force(force)
  if not (force and force.valid) then return false end
  local v = cache[force.name]
  if v == nil then
    local me = game.forces.player
    v = force.name ~= "neutral" and force ~= me and #force.players == 0 and me.is_enemy(force)
    cache[force.name] = v
  end
  return v
end
local function player_force(force) return force and force.valid and (force.name == "player" or #force.players > 0) end

function M.enemy_forces()
  local out = {}
  for _, f in pairs(game.forces) do if M.is_enemy_force(f) then out[#out + 1] = f end end
  return out
end

---------------------------------------------------------------- хранилище
local function S()
  local c = C.D().combat
  for _, k in pairs({"weap", "weap_shift", "planets", "enemies", "enemies_shift", "pweap", "evo_snap", "evo_hist"}) do c[k] = c[k] or {} end
  c.total = c.total or 0
  c.shift = c.shift or 0
  return c
end
M.S = S

local function inc(t, k, n) t[k] = (t[k] or 0) + (n or 1) end

---------------------------------------------------------------- чем убили
-- возвращает оружие, игрока-убийцу и владельца защиты (турель, мина)
function M.weapon(e)
  local c = e.cause
  if c and c.valid then
    local t = c.type
    if t == "character" then
      local key = "character"
      pcall(function()
        local gun = c.get_inventory(defines.inventory.character_guns)[c.selected_gun_index]
        if gun and gun.valid_for_read then key = gun.name end
      end)
      return key, c.player, nil
    end
    if TURRETS[t] or t == "land-mine" then
      local u = c.last_user
      return c.name, nil, (u and u.valid) and u or nil
    end
    if t == "combat-robot" then
      local owner = c.combat_robot_owner
      return c.name, (owner and owner.valid) and owner.player or nil, nil
    end
    if VEHICLES[t] then
      local d = c.get_driver and c.get_driver()
      if d and d.object_name == "LuaEntity" then d = d.player end
      if not C.S("tr-track-vehicles") then return c.name, nil, nil end
      return c.name, (d and d.object_name == "LuaPlayer") and d or nil, nil
    end
    return c.name, nil, nil
  end
  if e.damage_type then return "damage:" .. e.damage_type.name, nil, nil end
  return "unknown", nil, nil
end

-- на каждого убитого врага (уже отфильтрованного); возвращает убийцу или nil
function M.on_enemy_died(e, ent)
  if not player_force(e.force) then return nil end
  local w, killer, owner = M.weapon(e)
  local s = S()
  s.total = s.total + 1
  s.shift = s.shift + 1
  inc(s.weap, w)
  inc(s.weap_shift, w)
  if C.RP(ent.surface) then
    local key = ent.surface.planet.prototype.name
    local pl = s.planets[key] or {kills = 0, kills_shift = 0, weap = {}}
    s.planets[key] = pl
    pl.kills = pl.kills + 1
    if pl.kills == 1 then C.titles_changed() end   -- планета теперь с врагами (имена защитников)
    pl.kills_shift = pl.kills_shift + 1
    inc(pl.weap, w)
    if killer then
      local pk = C.D().pkills
      pk[killer.name] = pk[killer.name] or {}
      inc(pk[killer.name], key)
      if pk[killer.name][key] % 50 == 0 then C.check_titles(killer) end
    end
  end
  local en = s.enemies[ent.name] or {n = 0, w = {}}
  s.enemies[ent.name] = en
  en.n = en.n + 1
  inc(en.w, w)
  local es = s.enemies_shift[ent.name] or {n = 0, w = {}}
  s.enemies_shift[ent.name] = es
  es.n = es.n + 1
  inc(es.w, w)
  if owner and not C.S("tr-track-defense") then owner = nil end
  local who = killer or owner
  if who and string.find(ent.name, "pentapod", 1, true) then
    C.pstat_add(who.name, "pentapod", 1)
    if C.pstat(who.name, "pentapod") % 20 == 0 then C.check_titles(who) end
  end
  if who then
    s.pweap[who.name] = s.pweap[who.name] or {}
    inc(s.pweap[who.name], w)
  end
  if owner then
    C.add(owner.name, "defense", 1)
    if C.D().total[owner.name].defense % 500 == 0 then C.check_titles(owner) end
  end
  return killer
end

---------------------------------------------------------------- для окна, команд и сводки
function M.top(t, count)
  local arr = {}
  for k, v in pairs(t or {}) do arr[#arr + 1] = {k, v} end
  table.sort(arr, function(a, b) if a[2] ~= b[2] then return a[2] > b[2] end return a[1] < b[1] end)
  local out = {}
  for i = 1, math.min(count or #arr, #arr) do out[i] = arr[i] end
  return out, #arr
end
function M.best(t)
  local a = M.top(t, 1)[1]
  if a then return a[1], a[2] end
  return nil, 0
end

---------------------------------------------------------------- эволюция
function M.evolution(surface)
  local best = 0
  for _, f in ipairs(M.enemy_forces()) do
    local ok, v = pcall(f.get_evolution_factor, surface)
    if ok and v and v > best then best = v end
  end
  return best
end
-- эволюция каждой вражеской фракции на поверхности (для подсказок)
function M.evolution_by_force(surface)
  local out = {}
  for _, f in ipairs(M.enemy_forces()) do
    local ok, v = pcall(f.get_evolution_factor, surface)
    if ok and v then out[#out + 1] = {name = f.name, v = v} end
  end
  table.sort(out, function(a, b) return a.v > b.v end)
  return out
end
function M.pct(v) return string.format("%.1f%%", (v or 0) * 100) end
function M.pct2(v) return string.format("%.2f%%", (v or 0) * 100) end     -- за смену часто меняется на сотые
function M.dpct(v)
  v = (v or 0) * 100
  return (v >= 0 and "+" or "") .. string.format("%.2f%%", v)
end

-- эволюция по планетам с изменением с начала смены
function M.evo_rows()
  local s = S()
  local rows = {}
  for _, surf in pairs(game.surfaces) do
    if C.RP(surf) then
      local key = surf.planet.prototype.name
      local now = M.evolution(surf)
      if s.evo_snap[key] == nil then s.evo_snap[key] = now end
      -- active = тут живут враги (эволюция > 0 или кого-то убили)
      local active = now > 0 or (s.planets[key] and s.planets[key].kills > 0) or false
      rows[#rows + 1] = {key = key, s = surf, now = now, delta = now - s.evo_snap[key], hist = s.evo_hist[key],
        active = active}
    end
  end
  table.sort(rows, function(a, b) return a.now > b.now end)
  return rows
end
function M.active_evo_rows()
  local out = {}
  for _, r in ipairs(M.evo_rows()) do if r.active then out[#out + 1] = r end end
  return out
end

function M.init()
  local s = S()
  for _, surf in pairs(game.surfaces) do
    if C.RP(surf) then
      local key = surf.planet.prototype.name
      if s.evo_snap[key] == nil then s.evo_snap[key] = M.evolution(surf) end
    end
  end
end

-- конец смены: строки для сводки, потом сброс счётчиков
function M.close_shift()
  local s = S()
  local lines = {}
  if s.shift > 0 then
    local bp, bn = nil, 0
    for key, pl in pairs(s.planets) do if pl.kills_shift > bn then bp, bn = key, pl.kills_shift end end
    local w, wn = M.best(s.weap_shift)
    lines[#lines + 1] = {"", "\n  ", {"tr-msg.shift-combat", C.n(s.shift),
      bp and {"tr-msg.shift-combat-planet", C.planet_ls(bp), C.n(bn)} or "",
      w and {"tr-msg.shift-combat-weapon", C.weapon_chat(w), C.n(wn), math.floor(wn / s.shift * 100 + 0.5)} or ""}}
  end
  local evo = {}
  for _, r in ipairs(M.evo_rows()) do
    if r.delta >= 0.0005 then evo[#evo + 1] = r end
    s.evo_hist[r.key] = s.evo_hist[r.key] or {}
    local h = s.evo_hist[r.key]
    h[#h + 1] = r.now
    while #h > C.S("tr-s-history") do table.remove(h, 1) end
  end
  table.sort(evo, function(a, b) return a.delta > b.delta end)
  if #evo > 0 then
    local parts = {}
    for i = 1, math.min(4, #evo) do
      parts[#parts + 1] = {"", C.planet_ls(evo[i].key), " ", M.pct(evo[i].now), " (", M.dpct(evo[i].delta), ")"}
    end
    lines[#lines + 1] = {"", "\n  ", {"tr-msg.shift-evo", C.join(parts, ", ")}}
  end
  -- сброс
  s.shift = 0
  s.weap_shift = {}
  s.enemies_shift = {}
  for _, pl in pairs(s.planets) do pl.kills_shift = 0 end
  for _, surf in pairs(game.surfaces) do
    if C.RP(surf) then s.evo_snap[surf.planet.prototype.name] = M.evolution(surf) end
  end
  if #lines == 0 then return nil end
  return C.join(lines, "")
end

return M
