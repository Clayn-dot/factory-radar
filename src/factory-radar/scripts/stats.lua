-- Factory Radar: event counting (built / mined / lost / kills / deaths / craft / distance / landings)
local C = require("scripts.core")
local CB = require("scripts.combat")
local PF = require("scripts.platforms")
local M = {}

-- what counts as a player's building (not robots, characters, ghosts, items...)
local NOT_BUILDINGS = {["character"] = true, ["combat-robot"] = true, ["construction-robot"] = true,
  ["logistic-robot"] = true, ["capture-robot"] = true, ["land-mine"] = true, ["entity-ghost"] = true,
  ["tile-ghost"] = true, ["item-entity"] = true, ["corpse"] = true, ["character-corpse"] = true,
  ["projectile"] = true, ["asteroid"] = true, ["fire"] = true, ["stream"] = true, ["sticker"] = true,
  ["explosion"] = true, ["smoke-with-trigger"] = true, ["particle-source"] = true}
local ENEMY_KILL_TYPES = {["unit"] = true, ["unit-spawner"] = true, ["turret"] = true, ["ammo-turret"] = true,
  ["electric-turret"] = true, ["fluid-turret"] = true, ["artillery-turret"] = true, ["spider-unit"] = true,
  ["segmented-unit"] = true, ["car"] = true, ["spider-vehicle"] = true}
local TURRET_TYPES = {["turret"] = true, ["ammo-turret"] = true, ["electric-turret"] = true,
  ["fluid-turret"] = true, ["artillery-turret"] = true}
local VEHICLE_TYPES = {["car"] = true, ["spider-vehicle"] = true}
local TRAIN_TYPES = {["locomotive"] = true, ["cargo-wagon"] = true, ["fluid-wagon"] = true, ["artillery-wagon"] = true}
M.VEHICLE_TYPES, M.TRAIN_TYPES = VEHICLE_TYPES, TRAIN_TYPES

M.NOT_BUILDINGS = NOT_BUILDINGS

local function player_force(force) return force and force.valid and (force.name == "player" or #force.players > 0) end

local function killer_player(cause)
  if not (cause and cause.valid) then return nil end
  if cause.type == "character" then return cause.player end
  if VEHICLE_TYPES[cause.type] or TRAIN_TYPES[cause.type] then
    local d = cause.get_driver()
    if d and d.object_name == "LuaEntity" then d = d.player end
    if d and d.object_name == "LuaPlayer" then return d end
  end
  return nil
end
M.killer_player = killer_player

---------------------------------------------------------------- built (by hand only)
local function built_by(p, ent)
  if not (p and p.valid) or not (ent and ent.valid) or NOT_BUILDINGS[ent.type] then return end
  -- one building counts once whatever event reports it (a ghost placed and built, a second event
  -- from another mod): the last few hundred building numbers are remembered for a few minutes
  local un = ent.unit_number
  if un then
    local d0 = C.D()
    d0.bseen = d0.bseen or {}
    local last = d0.bseen[un]
    if last and game.tick - last < 5 * 3600 then return end
    d0.bseen[un] = game.tick
    d0.bseen_n = (d0.bseen_n or 0) + 1
    if d0.bseen_n > 600 then
      d0.bseen_n = 0
      for k, t in pairs(d0.bseen) do if game.tick - t >= 5 * 3600 then d0.bseen[k] = nil else d0.bseen_n = d0.bseen_n + 1 end end
    end
  end
  C.add(p.name, "built", 1)
  C.team_add("built", 1)
  local t = ent.type
  local extra
  if t == "transport-belt" or t == "underground-belt" or t == "splitter" or t == "lane-splitter" then extra = "belts"
  elseif string.find(t, "rail", 1, true) and not string.find(t, "signal", 1, true) and t ~= "rail-support" then extra = "rails"
  elseif t == "electric-pole" then extra = "poles"
  elseif TURRET_TYPES[t] then extra = "turrets" end
  -- per planet counters for titles: solar panels, accumulators, belts
  if t == "solar-panel" then C.pp_add("psolar", p.name, ent.surface, 1)
  elseif t == "accumulator" then C.pp_add("pacc", p.name, ent.surface, 1)
  elseif extra == "belts" then C.pp_add("pbelts", p.name, ent.surface, 1)
  elseif t == "mining-drill" then C.pp_add("pdrill", p.name, ent.surface, 1)
  elseif t == "assembling-machine" or t == "furnace" then C.pp_add("pfact", p.name, ent.surface, 1) end
  if extra then
    C.add(p.name, extra, 1)
    local v = C.D().total[p.name][extra]
    if v % 100 == 0 then C.check_titles(p) end
  end
  local d = C.D()
  if C.RP(ent.surface) then
    local key = C.key(ent.surface)
    if key then
      d.pbuilt[key] = d.pbuilt[key] or {}
      d.pbuilt[key][p.name] = (d.pbuilt[key][p.name] or 0) + 1
      d.pbuilt_shift = d.pbuilt_shift or {}
      d.pbuilt_shift[key] = d.pbuilt_shift[key] or {}
      d.pbuilt_shift[key][p.name] = (d.pbuilt_shift[key][p.name] or 0) + 1
      -- planet stats for titles: oil industry (pipes, pumps, tanks, wells, refineries) and turrets
      if t == "pipe" or t == "pipe-to-ground" or t == "pump" or t == "storage-tank"
        or (ent.name and (string.find(ent.name, "pumpjack", 1, true) or string.find(ent.name, "refinery", 1, true))) then
        C.pp_add("ppipe", p.name, ent.surface, 1)
      elseif TURRET_TYPES[t] then
        C.pp_add("pturrets", p.name, ent.surface, 1)
      end
    end
  end
  if d.total[p.name].built % 500 == 0 then C.check_titles(p) end
end

-- once a minute: the most nutrients a player carried at once (title "chemist")
function M.minute()
  if not prototypes.item["nutrients"] then return end
  for _, p in pairs(game.connected_players) do
    local ok, n = pcall(function() return p.get_item_count("nutrients") end)
    if ok and n and n > C.pstat(p.name, "nutrients_max") then
      C.D().pstat[p.name] = C.D().pstat[p.name] or {}
      C.D().pstat[p.name].nutrients_max = n
      C.check_titles(p)
    end
  end
end

function M.on_built(e)
  if e.player_index then built_by(game.get_player(e.player_index), e.entity) end
end

-- robots: credited to whoever placed the ghost / blueprint (only if the admin turned it on)
function M.on_robot_built(e)
  if not C.S("tr-track-robots") then return end
  local ent = e.entity
  if ent and ent.valid then
    local u = ent.last_user
    if u and u.valid and u.object_name == "LuaPlayer" then built_by(u, ent) end
  end
end

---------------------------------------------------------------- mined (own buildings only)
local function mined_by(p, ent)
  if not (p and p.valid) or not (ent and ent.valid) or NOT_BUILDINGS[ent.type] then return end
  if not player_force(ent.force) or not ent.last_user then return end
  C.add(p.name, "mined", 1)
  C.team_add("mined", 1)
  if C.D().total[p.name].mined % 100 == 0 then C.check_titles(p) end
end

function M.on_mined(e)
  local ent = e.entity
  if ent and ent.valid and e.player_index then
    local t = ent.type
    if t == "tree" then C.pp_add("pmine_tree", game.get_player(e.player_index).name, ent.surface, 1)
    elseif t == "simple-entity" and string.find(ent.name, "rock", 1, true) then
      C.pp_add("pmine_rock", game.get_player(e.player_index).name, ent.surface, 1)
    end
  end
  if e.entity and e.entity.valid and e.entity.unit_number then C.D().decon[e.entity.unit_number] = nil end
  if e.player_index then mined_by(game.get_player(e.player_index), e.entity) end
end

-- robots: we remember who marked for deconstruction and they get credit when a robot deconstructs
function M.on_marked(e)
  local ent = e.entity
  if not (e.player_index and ent and ent.valid and ent.unit_number) then return end
  if NOT_BUILDINGS[ent.type] or not player_force(ent.force) then return end
  C.D().decon[ent.unit_number] = e.player_index
  -- without this the record stays forever if the entity vanished past deconstruction and death (script, replacement, a foreign mod)
  script.register_on_object_destroyed(ent)
end
-- an entity with a mark left the world in any way: the mark record is not needed any more
function M.on_destroyed(e)
  if e.type == defines.target_type.entity and e.useful_id and e.useful_id ~= 0 then C.D().decon[e.useful_id] = nil end
end
function M.on_unmarked(e)
  local ent = e.entity
  if ent and ent.valid and ent.unit_number then C.D().decon[ent.unit_number] = nil end
end
function M.on_robot_mined(e)
  local ent = e.entity
  if not (ent and ent.valid and ent.unit_number) then return end
  local d = C.D()
  local idx = d.decon[ent.unit_number]
  d.decon[ent.unit_number] = nil
  if idx and C.S("tr-track-robot-mined") then mined_by(game.get_player(idx), ent) end
end

---------------------------------------------------------------- entity deaths
function M.on_entity_died(e)
  local ent = e.entity
  if not (ent and ent.valid) then return end
  local d = C.D()
  if ent.unit_number and d.decon[ent.unit_number] then d.decon[ent.unit_number] = nil end
  if ent.type == "asteroid" or ent.type == "space-platform-hub" then PF.on_died(e, ent) end
  if CB.is_enemy_force(ent.force) then
    if not ENEMY_KILL_TYPES[ent.type] then return end
    -- some mods use "enemy" units as mining tokens; they are not real enemies
    if string.find(ent.name, "data-collector", 1, true) == 1 then return end
    local p = CB.on_enemy_died(e, ent)
    if not p then return end
    C.add(p.name, "kills", 1)
    if ent.type == "unit-spawner" then C.add(p.name, "nests", 1) end
    C.team_add("kills", 1)
    local st = (d.streak[p.name] or 0) + 1
    d.streak[p.name] = st
    d.records.best_streak = d.records.best_streak or {}
    if st > (d.records.best_streak[p.name] or 0) then d.records.best_streak[p.name] = st end
    if d.total[p.name].kills % 50 == 0 or ent.type == "unit-spawner" then C.check_titles(p) end
    return
  end
  -- player buildings: only what the player really built (scripts and other mods leave no last_user)
  if not player_force(ent.force) or NOT_BUILDINGS[ent.type] then return end
  local owner = ent.last_user
  if not (owner and owner.valid) then return end
  if e.force and e.force.name == ent.force.name then
    if not C.S("tr-track-ff") then return end
    local p = killer_player(e.cause)
    if p then C.add(p.name, "ff", 1); C.check_titles(p) end
    C.team_add("ff", 1)
    return
  end
  C.add(owner.name, "lost", 1)
  if d.total[owner.name].lost % 50 == 0 then C.check_titles(owner) end
  C.team_add("lost", 1)
  if C.RP(ent.surface) then
    local key = C.key(ent.surface)
    if key then
      d.plost[key] = (d.plost[key] or 0) + 1
      d.shift_plost[key] = (d.shift_plost[key] or 0) + 1
      -- what was destroyed, by whom, whose (for the destruction tab), all time and per shift.
      -- "enemy" = the force that did it (cause or killing force) is hostile; everything else (explosions,
      -- fire, acid, lightning, own vehicles) goes to "other" by damage type
      local cause = (e.cause and e.cause.valid) and e.cause or nil
      local kf = (cause and cause.force) or e.force
      local enemy = kf and CB.is_enemy_force(kf) or false
      local by
      if cause then by = cause.name elseif e.damage_type then by = "damage:" .. e.damage_type.name else by = "unknown" end
      d.ldest = d.ldest or {}
      d.ldest_shift = d.ldest_shift or {}
      for _, store in ipairs({d.ldest, d.ldest_shift}) do
        local ld = store[key] or {what = {}, by = {}, other = {}, whose = {}, n = 0, enemy_n = 0}
        store[key] = ld
        ld.other = ld.other or {}
        ld.what[ent.name] = (ld.what[ent.name] or 0) + 1
        ld.n = (ld.n or 0) + 1
        if enemy then
          ld.enemy_n = (ld.enemy_n or 0) + 1
          ld.by[by] = (ld.by[by] or 0) + 1
        else
          ld.other[by] = (ld.other[by] or 0) + 1
        end
        ld.whose[owner.name] = (ld.whose[owner.name] or 0) + 1
        ld.last = game.tick
      end
      -- latest destruction for the tab (30 items, new on top)
      d.dest_recent = d.dest_recent or {}
      table.insert(d.dest_recent, 1, {tick = game.tick, planet = key, what = ent.name, by = by, enemy = enemy, whose = owner.name})
      while #d.dest_recent > 30 do table.remove(d.dest_recent) end
    end
  end
end

function M.on_crafted(e)
  local p = game.get_player(e.player_index)
  if not p or not e.item_stack or not e.item_stack.valid_for_read then return end
  local n = e.item_stack.count
  C.add(p.name, "craft", n)
  C.pp_add("pcraft", p.name, p.physical_surface, n)
  if C.D().total[p.name].craft % 500 < n then C.check_titles(p) end
end

---------------------------------------------------------------- player deaths with a joke
local LINES = {
  train = 3, enemy_turret = 3, creature = 3, tank = 2, mine = 2, friendly = 2, self = 2, player = 2,
  vehicle = 2, lightning = 2, unknown = 3,
}
local CREATURE_TYPES = {["unit"] = true, ["spider-unit"] = true, ["segmented-unit"] = true, ["unit-spawner"] = true}

local function classify(player, cause)
  if not (cause and cause.valid) then return "unknown" end
  local t, n = cause.type, cause.name
  if string.find(n, "lightning", 1, true) then return "lightning" end
  if t == "character" then
    if cause.player and cause.player.index == player.index then return "self" end
    if cause.player then return "player", cause.player.name end
  end
  if TRAIN_TYPES[t] then return "train" end
  if t == "land-mine" then return "mine" end
  if n == "castra-enemy-tank" then return "tank" end
  if cause.force and player.force and cause.force.name == player.force.name then
    if VEHICLE_TYPES[t] then return "vehicle" end
    return "friendly"
  end
  if TURRET_TYPES[t] then return "enemy_turret" end
  if CREATURE_TYPES[t] then return "creature" end
  if VEHICLE_TYPES[t] then return "tank" end
  return "unknown"
end

function M.on_player_died(e)
  local p = game.get_player(e.player_index)
  if not p then return end
  local d = C.D()
  C.add(p.name, "deaths", 1)
  C.team_add("deaths", 1)
  C.pp_add("pdeaths", p.name, p.physical_surface, 1)
  d.streak[p.name] = 0
  local kind, other = classify(p, e.cause)
  d.death_kinds[p.name] = d.death_kinds[p.name] or {}
  d.death_kinds[p.name][kind] = (d.death_kinds[p.name][kind] or 0) + 1
  C.check_titles(p)
  if C.S("tr-death-tags") and p.character == nil then
    pcall(function() p.force.add_chart_tag(p.physical_surface, {position = p.physical_position, text = "† " .. p.name}) end)
  end
  if not C.S("tr-deaths") then return end

  -- anti-spam: more than 3 deaths of one player per minute are counted but not printed
  local fresh = {}
  for _, t in pairs(d.recent[p.name] or {}) do if game.tick - t < 3600 then fresh[#fresh + 1] = t end end
  fresh[#fresh + 1] = game.tick
  d.recent[p.name] = fresh
  d.muted = d.muted or {}
  if #fresh > C.S("tr-s-death-limit") then d.muted[p.name] = (d.muted[p.name] or 0) + 1; return end

  local variant = (p.index * 7 + d.total[p.name].deaths) % LINES[kind] + 1
  local text = {"tr-death." .. kind .. "-" .. variant, p.name, other or ""}
  local parts = {"", "[img=entity/character] ", text}
  if e.cause and e.cause.valid and kind ~= "self" and kind ~= "unknown" then
    local k = d.killers[p.name] or {}
    d.killers[p.name] = k
    local key = other and ("player:" .. other) or e.cause.name
    k[key] = (k[key] or 0) + 1
    parts[#parts + 1] = {"tr-msg.death-score", other or ("[entity=" .. e.cause.name .. "]"), k[key], p.name}
  end
  if (d.muted[p.name] or 0) > 0 then
    parts[#parts + 1] = {"tr-msg.death-muted", d.muted[p.name]}
    d.muted[p.name] = 0
  end
  local gps = p.character == nil and C.gps(p.physical_position, p.physical_surface) or ""
  if gps ~= "" then parts[#parts + 1] = "  " .. gps end
  local killer = other or (e.cause and e.cause.valid and ("[entity=" .. e.cause.name .. "]")) or "?"
  local cnt = d.total[p.name].deaths
  C.send("death", parts, {player = p.name, joke = text, killer = killer, count = cnt, gps = gps}, {1, 0.75, 0.6}, p,
    {"", "[img=entity/character] ", text})
end

---------------------------------------------------------------- distance and time on planets (every 127 ticks)
function M.track()
  local d = C.D()
  for _, p in pairs(game.connected_players) do
    local s = p.physical_surface
    if s and s.valid and not s.platform then
      local pos = p.physical_position
      local last = d.last_pos[p.index]
      if last and last.s == s.index then
        local dx, dy = pos.x - last.x, pos.y - last.y
        local dist = math.sqrt(dx * dx + dy * dy)
        if dist > 0.5 and dist < 1000 then
          if p.vehicle then C.add(p.name, "ride", dist)
          elseif p.character then C.add(p.name, "walk", dist); C.pp_add("pwalk", p.name, s, dist) end
        end
      end
      d.last_pos[p.index] = {s = s.index, x = pos.x, y = pos.y}
      if C.RP(s) then
        local key = C.key(s)
        if key then
          d.ptime[p.name] = d.ptime[p.name] or {}
          d.ptime[p.name][key] = (d.ptime[p.name][key] or 0) + 127
          if game.tick % (127 * 300) < 127 then C.check_titles(p) end
        end
      end
    else
      d.last_pos[p.index] = nil
    end
  end
end

---------------------------------------------------------------- landings
function M.mark_existing()
  local d = C.D()
  if d.landings_marked then return end
  d.landings_marked = true
  for _, s in pairs(game.surfaces) do
    if C.RP(s) then
      local key = C.key(s)
      if key and not d.first[key] then d.first[key] = {who = "?", tick = 0} end
    end
  end
  for _, p in pairs(game.players) do
    local s = p.physical_surface
    if C.RP(s) then
      local key = C.key(s)
      if key then
        d.visited[p.name] = d.visited[p.name] or {}
        d.visited[p.name][key] = true
      end
    end
  end
end

function M.on_changed_surface(e)
  local p = game.get_player(e.player_index)
  if not p then return end
  local s = p.physical_surface
  if s and s.valid and s.platform and C.pstat(p.name, "space") == 0 then
    C.pstat_add(p.name, "space", 1)
    C.check_ach(p)
  end
  if not C.RP(s) or not p.character then return end
  local key = C.key(s)
  if not key then return end
  local d = C.D()
  d.visited[p.name] = d.visited[p.name] or {}
  local personal_new = not d.visited[p.name][key]
  d.visited[p.name][key] = true
  if not d.first[key] then
    d.first[key] = {who = p.name, tick = game.tick}
    if C.S("tr-first-landing") then
      local gps = C.gps(p.physical_position, s)
      C.send("first-landing", {"tr-msg.first-landing", p.name, C.place(s), gps}, {player = p.name, planet = C.place(s), gps = gps},
        {0.6, 1, 0.75}, p, {"tr-msg.first-landing", p.name, C.place(s), ""})
    end
  elseif personal_new and C.S("tr-first-landing") then
    p.print({"tr-msg.new-planet-personal", C.place(s), C.planets_visited(p.name), C.planets_in_game()}, {color = {0.7, 0.9, 1}})
  end
  if personal_new then C.check_titles(p) end
end

return M
