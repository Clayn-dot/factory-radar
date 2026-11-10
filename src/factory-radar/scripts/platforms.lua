-- Factory Radar: space platforms: where they are, where they fly, cargo, trips, asteroids, losses
local C = require("scripts.core")
local P = require("scripts.planets")
local M = {}

local STATE_NAME = {}
for k, v in pairs(defines.space_platform_state) do STATE_NAME[v] = k end
M.STATE_NAME = STATE_NAME

local function S()
  local d = C.D()
  d.plat = d.plat or {}
  d.plat_lost = d.plat_lost or {}
  return d
end

function M.stat(pl)
  local d = S()
  local st = d.plat[pl.index]
  if not st then st = {trips = 0, asteroids = {}, ast = 0, since = game.tick}; d.plat[pl.index] = st end
  st.name = pl.name
  return st
end

-- a platform arrived somewhere = one trip
function M.on_state(e)
  local pl = e.platform
  if not (pl and pl.valid) or pl.force.name ~= "player" then return end
  local st = M.stat(pl)
  local ds = defines.space_platform_state
  if pl.state == ds.waiting_at_station and e.old_state == ds.on_the_path then
    st.trips = st.trips + 1
    st.last_arrival = game.tick
    st.last_place = pl.space_location and pl.space_location.name or nil
  end
end

local function loc_of(pl)
  if pl.space_location then return {at = pl.space_location.name} end
  if pl.space_connection then return {from = pl.space_connection.from.name, to = pl.space_connection.to.name} end
  return {}
end

-- smashed asteroids and destroyed platforms
function M.on_died(e, ent)
  local s = ent.surface
  if not (s and s.valid and s.platform) then return end
  local pl = s.platform
  if pl.force.name ~= "player" then return end
  if ent.type == "asteroid" then
    local st = M.stat(pl)
    st.asteroids[ent.name] = (st.asteroids[ent.name] or 0) + 1
    st.ast = st.ast + 1
  elseif ent.type == "space-platform-hub" then
    local d = S()
    local st = M.stat(pl)
    local l = loc_of(pl)
    local cause = (e.cause and e.cause.valid) and e.cause.name or nil
    table.insert(d.plat_lost, 1, {name = pl.name, tick = game.tick, at = l.at, from = l.from, to = l.to,
      cause = cause, damage = e.damage_type and e.damage_type.name or nil, trips = st.trips, ast = st.ast})
    d.plat_lost_n = (d.plat_lost_n or #d.plat_lost - 1) + 1
    while #d.plat_lost > 50 do table.remove(d.plat_lost) end
    local where = l.at and C.planet_ls(l.at) or (l.from and {"", C.planet_ls(l.from), " → ", C.planet_ls(l.to)} or "?")
    local cause_ls = {"tr-plat.cause-unknown"}
    if cause then
      local cp = prototypes.entity[cause]
      cause_ls = {"", helpers.is_valid_sprite_path("entity/" .. cause) and ("[img=entity/" .. cause .. "] ") or "", cp and cp.localised_name or cause}
    end
    C.send("platform-lost", {"tr-msg.platform-lost", C.chat_rich(pl.name), where, cause_ls},
      {platform = pl.name, where = where}, {1, 0.6, 0.5})
  end
end

-- everything the window needs about each platform
-- one platform: where it is, the current jump (turned along the flight), schedule, cargo, hull
function M.row(pl)
  local st = M.stat(pl)
  local l = loc_of(pl)
  local sched = pl.schedule
  local stops, target, interrupt = {}, nil, false
  if sched and sched.records then
    -- interrupts added by the platform itself are temporary: they are where it flies now, not part of the route
    local cur = sched.records[sched.current]
    interrupt = (cur and (cur.temporary or cur.created_by_interrupt)) and true or false
    for i, r in ipairs(sched.records) do
      if r.station and not (r.temporary or r.created_by_interrupt) then
        stops[#stops + 1] = {name = r.station, current = (i == sched.current)}
      end
      if i == sched.current then target = r.station end
    end
  end
  -- how long it stands still (schedule timer; fallback is the arrival tick)
  local idle = nil
  if pl.space_location and not pl.space_connection then
    local ok, v = pcall(function() return pl.get_schedule().ticks_in_station end)
    if ok and type(v) == "number" and v >= 0 then idle = v
    elseif st.last_arrival then idle = game.tick - st.last_arrival end
  end
  -- distance goes 0..1 from connection.from to connection.to. A link can be flown in either direction,
  -- and the target may be several jumps away, so the direction is taken from how distance moves
  -- (remembered per platform); on a new link the first guess is the target
  local from, to, dist = l.from, l.to, pl.distance or 0
  local oriented = false
  if from then
    local key = from .. ">" .. to
    local dir = st.dir
    if not dir or dir.key ~= key then
      -- the planet just left decides from which end of the link we fly
      local prev = st.fl and st.fl.cur and st.fl.cur.to
      if not prev then
        local ok, lv = pcall(function() return pl.last_visited_space_location.name end)
        prev = ok and lv or nil
      end
      local rev, sure = nil, true
      if prev and prev == to and prev ~= from then rev = true
      elseif prev and prev == from then rev = false
      else rev = (target == from and target ~= to) or false; sure = false end   -- a guess until distance moves
      dir = {key = key, rev = rev, last = dist, sure = sure}
      st.dir = dir
    elseif dist ~= dir.last then
      dir.rev = dist < dir.last
      dir.last = dist
      dir.sure = true
    end
    oriented = dir.sure
    if dir.rev then from, to, dist = to, from, 1 - dist end
  else
    st.dir = nil
  end
  return {pl = pl, st = st, state = STATE_NAME[pl.state] or "?", at = l.at, from = from, to = to,
    distance = dist, target = target, stops = stops, paused = pl.paused, interrupt = interrupt, idle = idle,
    fl = st.fl, history = st.history or {}, oriented = oriented}
end

-- short fingerprint: if it changed, the card must be redrawn (otherwise only bars move)
function M.sig(r)
  local cur = 0
  for i, s in ipairs(r.stops) do if s.current then cur = i end end
  local passing = r.fl and not r.from and r.state == "on_the_path"
  return table.concat({r.state, passing and "pass" or (r.at or ""), r.from or "", r.to or "", r.target or "", #r.stops, cur,
    r.interrupt and 1 or 0}, "|")
end

-- The game flies a platform along links, so the path between two schedule stops may go through other
-- planets. The graph is static prototype data (cache); the path is the shortest by link length through planets
-- open to the force. This is an estimate: the game does not say which way it will go
local edges = nil
local function graph()
  if edges then return edges end
  edges = {}
  for _, c in pairs(prototypes.space_connection) do
    local a, b = c.from.name, c.to.name
    edges[a] = edges[a] or {}
    edges[b] = edges[b] or {}
    local function add(x, y)
      for _, e in ipairs(edges[x]) do
        if e.to == y then
          if c.length < e.len then e.len = c.length end
          return
        end
      end
      edges[x][#edges[x] + 1] = {to = y, len = c.length}
    end
    if a ~= b then add(a, b); add(b, a) end
  end
  return edges
end

-- warm-up: the link graph is computed in advance (prototypes only)
function M.warm() graph() end

local path_cache = {}
local raw_path
function M.path(a, b)
  local key = a .. ">" .. b
  local hit = path_cache[key]
  if hit and game.tick >= hit.tick and game.tick - hit.tick < 3600 then return hit.path end
  local path = raw_path(a, b)
  path_cache[key] = {tick = game.tick, path = path}
  return path
end

function raw_path(a, b)
  if a == b then return {a} end
  local g = graph()
  if not (g[a] and g[b]) then return nil end
  local force = game.forces.player
  local dist, prev, done = {[a] = 0}, {}, {}
  while true do
    local u, best
    for n, d in pairs(dist) do
      if not done[n] and (not best or d < best or (d == best and n < u)) then u, best = n, d end
    end
    if not u then return nil end
    if u == b then break end
    done[u] = true
    for _, e in ipairs(g[u]) do
      local open = e.to == b
      if not open then
        local ok, v = pcall(force.is_space_location_unlocked, e.to)
        open = (not ok) or v
      end
      if open then
        local nd = best + e.len
        if not dist[e.to] or nd < dist[e.to] then dist[e.to] = nd; prev[e.to] = u end
      end
    end
  end
  local out, n = {}, b
  while n do table.insert(out, 1, n); n = prev[n] end
  return out
end

-- link length between neighbouring planets (km), nil if they are not neighbours
function M.conn_len(a, b)
  for _, e in ipairs(graph()[a] or {}) do if e.to == b then return e.len end end
  return nil
end

-- whole minutes of idle time, only from two minutes (nil while flying, paused or just arrived)
function M.idle_mins(r)
  if not r.idle or r.paused or r.from then return nil end
  if r.idle < 2 * 3600 then return nil end
  return math.floor(r.idle / 3600)
end

-- cargo by item kind, from prototypes only (no mod names): science, modules, ammo (what shoots or
-- is thrown: ammo, weapons, armor, combat capsules), buildings, logistics (belts, inserters, robots, pipes),
-- food (what spoils or is eaten), fuel, raw, intermediates, other
M.CARGO_ORDER = {"science", "intermediate", "raw", "logistics", "buildings", "equipment", "modules", "ammo", "food", "fuel", "other"}
local LOGISTICS = {["transport-belt"] = true, ["underground-belt"] = true, splitter = true, loader = true, ["loader-1x1"] = true,
  ["linked-belt"] = true, inserter = true, ["logistic-robot"] = true, ["construction-robot"] = true,
  pipe = true, ["pipe-to-ground"] = true, pump = true}
function M.cargo_category(name)
  local it = prototypes.item[name]
  if not it then return "other" end
  local sub = it.subgroup and it.subgroup.name or ""
  local group = it.group and it.group.name or ""
  if P.is_science(name) then return "science" end     -- what labs accept
  if it.type == "module" then return "modules" end
  -- a capsule is not always a weapon (some are food): only the combat group counts as ammo
  if it.type == "ammo" or it.type == "gun" or it.type == "armor" or (it.type == "capsule" and group == "combat") then return "ammo" end
  local pr = it.place_result
  -- seeds are placed too, but they are organic, not buildings
  if pr and pr.type == "plant" then return "food" end
  if pr then return LOGISTICS[pr.type] and "logistics" or "buildings" end
  -- what goes into armor (batteries, shields, exoskeletons...) is equipment, not a building
  if it.place_as_equipment_result then return "equipment" end
  if it.place_as_tile_result then return "buildings" end
  -- what spoils or is eaten goes before fuel (some food burns)
  local spoils = false
  pcall(function() spoils = it.spoil_result ~= nil or (it.get_spoil_ticks() or 0) > 0 end)
  -- fuel category: one (fuel_category) in 2.0, a list (fuel_categories) in 2.1
  local food_fuel = false
  local okc, fcs = pcall(function() return it.fuel_categories end)
  if okc then
    for _, c in pairs(fcs or {}) do if c == "food" then food_fuel = true end end
  else
    pcall(function() food_fuel = it.fuel_category == "food" end)
  end
  if spoils or food_fuel then return "food" end
  if (it.fuel_value or 0) > 0 then return "fuel" end
  if sub == "raw-resource" or sub == "space-material" or name:find("-ore$") then return "raw" end
  if group == "intermediate-products" then return "intermediate" end
  return "other"
end
function M.cargo_groups(cargo)
  local by = {}
  for _, it in ipairs(cargo) do
    local c = M.cargo_category(it.name)
    by[c] = by[c] or {cat = c, items = {}, total = 0}
    local g = by[c]
    g.items[#g.items + 1] = it
    g.total = g.total + it.count
  end
  local out = {}
  for _, c in ipairs(M.CARGO_ORDER) do if by[c] then out[#out + 1] = by[c] end end
  return out
end

function M.rows(hidden)
  local rows = {}
  for _, pl in pairs(game.forces.player.platforms) do
    if pl.valid and not (hidden and hidden[pl.index]) then
      local r = M.row(pl)
      local cargo = {}
      pcall(function()
        local inv = pl.hub and pl.hub.valid and pl.hub.get_inventory(defines.inventory.hub_main)
        if inv then
          -- every quality on its own line
          for _, it in pairs(inv.get_contents()) do cargo[#cargo + 1] = {name = it.name, count = it.count, quality = it.quality} end
        end
      end)
      -- better quality first, then larger amount (categories keep this order)
      local function level(q)
        local lv = 0
        pcall(function() lv = prototypes.quality[q or "normal"].level end)
        return lv
      end
      table.sort(cargo, function(a, b)
        local la, lb = level(a.quality), level(b.quality)
        if la ~= lb then return la > lb end
        if a.count ~= b.count then return a.count > b.count end
        return a.name < b.name
      end)
      local hp = 1
      pcall(function() if pl.hub and pl.hub.valid and pl.hub.max_health and pl.hub.max_health > 0 then hp = pl.hub.health / pl.hub.max_health end end)
      r.cargo, r.hp = cargo, hp
      rows[#rows + 1] = r
    end
  end
  table.sort(rows, function(a, b) return a.pl.name < b.pl.name end)
  return rows
end

-- asteroids by size: {tier = huge|big|medium|small|other, n, hp}, big first
local TIERS = {"huge", "big", "medium", "small"}
function M.tier_of(name)
  for _, t in ipairs(TIERS) do
    if name:find("^" .. t .. "%-") or name:find("%-" .. t .. "%-") then return t end
  end
  return "other"
end
function M.asteroid_tiers(asteroids)
  local by, list = {}, {}
  for name, n in pairs(asteroids or {}) do
    local t = M.tier_of(name)
    by[t] = (by[t] or 0) + n
    local proto = prototypes.entity[name]
    local hp = 0
    if proto then
      local ok, h = pcall(function() return proto.get_max_health() end)
      if ok and h then hp = h end
    end
    list[#list + 1] = {name = name, n = n, hp = hp}
  end
  table.sort(list, function(a, b) if a.hp ~= b.hp then return a.hp > b.hp end return a.name < b.name end)
  local tiers = {}
  for _, t in ipairs(TIERS) do if by[t] then tiers[#tiers + 1] = {tier = t, n = by[t]} end end
  if by.other then tiers[#tiers + 1] = {tier = "other", n = by.other} end
  return tiers, list
end

-- every few seconds: look where each platform flies and keep the current flight record:
-- when it left, each jump (planet-planet) with its start and distance covered. A jump closes
-- when the platform goes on along the next link or parks; a finished flight is stored as "last"
local function conn_len(pl)
  local ok, v = pcall(function() return pl.space_connection.length end)
  return ok and v or nil
end

function M.leg_km(l, dist)
  return math.max(0, (dist or l.dist or 0) - (l.d0 or 0)) * (l.len or 0)
end
local leg_km = M.leg_km

local function speed_of(km, ticks)
  if ticks >= 600 and km > 0 then return km / (ticks / 60) end
  return nil
end
M.speed_of = speed_of

local function last_visited(pl)
  local ok, v = pcall(function() return pl.last_visited_space_location.name end)
  return ok and v or nil
end

-- close a flight in the record and keep it as one of the last three
local function finish_flight(st, fl, place, now)
  if fl.cur then fl.cur.t1 = now; fl.cur.dist = 1; fl.legs[#fl.legs + 1] = fl.cur; fl.cur = nil end
  if fl.nodes[#fl.nodes] ~= place then fl.nodes[#fl.nodes + 1] = place end
  -- whole path: lengths of all covered links; speed from the distance actually covered
  local km, covered = 0, 0
  for _, l in ipairs(fl.legs) do km = km + (l.len or 0); covered = covered + leg_km(l) end
  st.history = st.history or {}
  table.insert(st.history, 1, {from = fl.origin, to = place, nodes = fl.nodes, ticks = now - fl.start, km = km,
    speed = speed_of(covered, now - fl.start), tick = now})
  while #st.history > 3 do table.remove(st.history) end
  st.fl = nil
end

-- Current flight record in storage: when it left, planets in order (`nodes`, so the whole path is known),
-- each jump with its start and distance covered. A jump closes when the platform goes along the next link.
-- A flight ends when the platform stopped (not just passes a planet) or, if it never stops,
-- when the target changed after the old one was reached; kept as one of the last three
function M.track()
  local now = game.tick
  for _, pl in pairs(game.forces.player.platforms) do
    if pl.valid and (pl.space_connection or pl.space_location) then
      local r = M.row(pl)
      local st = r.st
      local fl = st.fl
      if fl and r.target then
        if not fl.target then
          fl.target = r.target
        elseif r.target ~= fl.target then
          local last_to = (fl.cur and fl.cur.to) or (#fl.legs > 0 and fl.legs[#fl.legs].to) or nil
          if last_to == fl.target then
            finish_flight(st, fl, fl.target, now)     -- target reached, flies on without a stop
            fl = nil
          else
            fl.target = r.target                      -- redirected on the way (interrupt)
          end
        end
      end
      if r.from and r.from ~= r.to and r.oriented then   -- an unsure direction waits for the next sample
        if not fl then
          local lv = last_visited(pl)
          local origin = (lv == r.from or lv == r.to) and lv or r.from
          fl = {start = now, legs = {}, nodes = {origin}, origin = origin, target = r.target}
          st.fl = fl
        end
        local key = r.from .. ">" .. r.to
        if not fl.cur or fl.cur.key ~= key then
          if fl.cur then fl.cur.t1 = now; fl.cur.dist = 1; fl.legs[#fl.legs + 1] = fl.cur end
          if fl.nodes[#fl.nodes] ~= r.from then fl.nodes[#fl.nodes + 1] = r.from end
          fl.cur = {key = key, from = r.from, to = r.to, t0 = now, d0 = r.distance, len = conn_len(pl)}
          while #fl.legs > 30 do table.remove(fl.legs, 1) end
          while #fl.nodes > 31 do table.remove(fl.nodes, 1) end
        end
      elseif fl and pl.space_location and r.state ~= "on_the_path" then   -- passing a planet on the way is not the end
        finish_flight(st, fl, pl.space_location.name, now)
      end
    end
  end
end

-- a flight goes from departure to a stop; at a planet on the way the platform has no link for a moment, which must not
-- look like an end
local function in_flight(r)
  return r.fl and (r.from or r.state == "on_the_path")
end

-- current flight: time, km covered, average speed (km/s of link lengths), jumps made (`legs`),
-- the current one (`cur`, nil while the platform is at a planet on the way) and where the platform is (`pos`)
function M.flight(r)
  local fl = r.fl
  if not (fl and in_flight(r)) then return nil end
  local now = game.tick
  local km, legs, cur, pos = 0, {}, nil, nil
  local function add_leg(l, t1)
    local k = leg_km(l, 1)
    km = km + k
    legs[#legs + 1] = {from = l.from, to = l.to, ticks = t1 - l.t0, len = l.len, speed = speed_of(k, t1 - l.t0)}
  end
  for _, l in ipairs(fl.legs) do
    local k = leg_km(l)
    km = km + k
    legs[#legs + 1] = {from = l.from, to = l.to, ticks = l.t1 - l.t0, len = l.len, speed = speed_of(k, l.t1 - l.t0)}
  end
  local route_km = 0
  for _, l in ipairs(fl.legs) do route_km = route_km + (l.len or 0) end
  local c = fl.cur
  local key = r.from and (r.from .. ">" .. r.to) or nil
  if c and r.from and c.key ~= key then
    -- the platform is already on the next jump, the record catches up at the next sample: the old jump is done
    add_leg(c, now)
    route_km = route_km + (c.len or 0)
    if r.from ~= r.to then
      local len = M.conn_len(r.from, r.to)
      cur = {from = r.from, to = r.to, ticks = 0, len = len}
      route_km = route_km + (len or 0)
      pos = r.to
    else
      pos = c.to
    end
  elseif c then
    route_km = route_km + (c.len or 0)
    if r.from then
      local k = leg_km(c, r.distance)
      km = km + k
      cur = {from = c.from, to = c.to, ticks = now - c.t0, len = c.len, speed = speed_of(k, now - c.t0)}
    else
      add_leg(c, now)       -- at a planet on the way: the last jump is done
    end
    pos = c.to
  end
  local el = now - fl.start
  return {elapsed = el, km = km, route_km = route_km, speed = speed_of(km, el), legs = legs, cur = cur, origin = fl.origin,
    pos = pos, nodes = fl.nodes}
end

-- approximate time of the whole route: length / average speed of this flight (or of the last one while there is none);
-- nil if the speed is unknown
function M.eta_ticks(r, total_km)
  if not total_km or total_km <= 0 then return nil end
  local f = M.flight(r)
  local v = f and f.speed
  if not v and r.history and r.history[1] then v = r.history[1].speed end
  if not v or v <= 0 then return nil end
  return math.floor(total_km / v * 60)
end

-- platform path to the current target (named by the schedule or an interrupt): covered jumps of this
-- flight, the current one and planets ahead (shortest path by link length).
-- jumps: {from, to, len, kind = done | cur | next, ticks, speed}
function M.route(r)
  local target = r.target
  if not target then return nil end
  local hops = {}
  local function next_hops(from)
    if from == target then return end
    local path = M.path(from, target) or {from, target}
    for k = 2, #path do
      if path[k - 1] ~= path[k] then
        hops[#hops + 1] = {from = path[k - 1], to = path[k], len = M.conn_len(path[k - 1], path[k]), kind = "next"}
      end
    end
  end
  local f = M.flight(r)
  if f then
    for _, l in ipairs(f.legs) do
      if l.from ~= l.to then
        hops[#hops + 1] = {from = l.from, to = l.to, len = l.len, kind = "done", ticks = l.ticks, speed = l.speed}
      end
    end
    if f.cur and f.cur.from ~= f.cur.to then
      hops[#hops + 1] = {from = f.cur.from, to = f.cur.to, len = f.cur.len or M.conn_len(f.cur.from, f.cur.to), kind = "cur",
        ticks = f.cur.ticks, speed = f.cur.speed}
    end
    next_hops(f.pos or r.at or r.to or target)
  elseif r.from and r.from ~= r.to then
    -- a flight not in the record yet (first seconds): only this jump and the rest
    hops[#hops + 1] = {from = r.from, to = r.to, len = M.conn_len(r.from, r.to), kind = "cur"}
    next_hops(r.to)
  elseif r.at and r.at ~= target then
    next_hops(r.at)
  else
    return nil
  end
  if #hops == 0 then return nil end
  return hops
end

function M.lost() return S().plat_lost end
-- how many platforms were lost in all time (the list keeps the last 50)
function M.lost_total() local d = S(); return math.max(d.plat_lost_n or 0, #d.plat_lost) end

return M
