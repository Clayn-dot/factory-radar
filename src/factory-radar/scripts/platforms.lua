-- Factory Radar: космические платформы — где они, куда летят, груз, рейсы, астероиды, потери
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

-- платформа куда-то прибыла = один рейс
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

-- разбитые астероиды и уничтоженные платформы
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

-- для скриншотов (мод-помощник): записать потерянную платформу и написать об этом в чат
function M.demo_lost(name, from, to, cause)
  local d = S()
  table.insert(d.plat_lost, 1, {name = name, tick = game.tick, from = from, to = to, cause = cause, trips = 3, ast = 120})
  d.plat_lost_n = (d.plat_lost_n or #d.plat_lost - 1) + 1
  local where = {"", C.planet_ls(from), " → ", C.planet_ls(to)}
  local cp = prototypes.entity[cause]
  local cause_ls = {"", helpers.is_valid_sprite_path("entity/" .. cause) and ("[img=entity/" .. cause .. "] ") or "", cp and cp.localised_name or cause}
  C.send("platform-lost", {"tr-msg.platform-lost", C.chat_rich(name), where, cause_ls}, {platform = name, where = where}, {1, 0.6, 0.5})
end

-- всё, что нужно окну о каждой платформе
-- одна платформа: где она, текущий прыжок (повёрнутый по ходу полёта), расписание, груз, корпус
function M.row(pl)
  local st = M.stat(pl)
  local l = loc_of(pl)
  local sched = pl.schedule
  local stops, target, interrupt = {}, nil, false
  if sched and sched.records then
    -- прерывания, добавленные самой платформой, временные: это то, куда она летит сейчас, а не часть маршрута
    local cur = sched.records[sched.current]
    interrupt = (cur and (cur.temporary or cur.created_by_interrupt)) and true or false
    for i, r in ipairs(sched.records) do
      if r.station and not (r.temporary or r.created_by_interrupt) then
        stops[#stops + 1] = {name = r.station, current = (i == sched.current)}
      end
      if i == sched.current then target = r.station end
    end
  end
  -- сколько стоит на месте (таймер расписания; запасной вариант — тик прибытия)
  local idle = nil
  if pl.space_location and not pl.space_connection then
    local ok, v = pcall(function() return pl.get_schedule().ticks_in_station end)
    if ok and type(v) == "number" and v >= 0 then idle = v
    elseif st.last_arrival then idle = game.tick - st.last_arrival end
  end
  -- distance идёт 0..1 от connection.from к connection.to. Связь можно лететь в любую сторону,
  -- а цель может быть за несколько прыжков, поэтому направление берём по тому, как движется distance
  -- (запоминается по платформе), на новой связи первое предположение — цель
  local from, to, dist = l.from, l.to, pl.distance or 0
  local oriented = false
  if from then
    local key = from .. ">" .. to
    local dir = st.dir
    if not dir or dir.key ~= key then
      -- планета, которую только что покинули, определяет, с какого конца связи летим
      local prev = st.fl and st.fl.cur and st.fl.cur.to
      if not prev then
        local ok, lv = pcall(function() return pl.last_visited_space_location.name end)
        prev = ok and lv or nil
      end
      local rev, sure = nil, true
      if prev and prev == to and prev ~= from then rev = true
      elseif prev and prev == from then rev = false
      else rev = (target == from and target ~= to) or false; sure = false end   -- догадка, пока distance не сдвинется
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

-- короткий отпечаток: изменился — карточку надо перерисовать (иначе двигаются только полоски)
function M.sig(r)
  local cur = 0
  for i, s in ipairs(r.stops) do if s.current then cur = i end end
  local passing = r.fl and not r.from and r.state == "on_the_path"
  return table.concat({r.state, passing and "pass" or (r.at or ""), r.from or "", r.to or "", r.target or "", #r.stops, cur,
    r.interrupt and 1 or 0}, "|")
end

-- Игра летит платформой по связям, так что путь между двумя остановками расписания может идти через другие
-- планеты. Граф — статические данные прототипов (кэш); путь — кратчайший по длине связей через планеты,
-- открытые силой. Это оценка: игра не говорит, каким путём пойдёт
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

-- прогрев: граф связей считается заранее (только прототипы)
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

-- длина связи между соседними планетами (км), nil если не соседи
function M.conn_len(a, b)
  for _, e in ipairs(graph()[a] or {}) do if e.to == b then return e.len end end
  return nil
end

-- целые минуты простоя, только от двух минут (nil пока летит, на паузе или только прибыла)
function M.idle_mins(r)
  if not r.idle or r.paused or r.from then return nil end
  if r.idle < 2 * 3600 then return nil end
  return math.floor(r.idle / 3600)
end

-- груз по виду предметов, только по прототипам (без имён модов): наука, модули, боеприпасы (что стреляет или
-- бросается: патроны, оружие, броня, боевые капсулы), постройки, логистика (ленты, манипуляторы, роботы, трубы),
-- еда (что портится или едят), топливо, сырьё, промежуточные, прочее
M.CARGO_ORDER = {"science", "intermediate", "raw", "logistics", "buildings", "equipment", "modules", "ammo", "food", "fuel", "other"}
local LOGISTICS = {["transport-belt"] = true, ["underground-belt"] = true, splitter = true, loader = true, ["loader-1x1"] = true,
  ["linked-belt"] = true, inserter = true, ["logistic-robot"] = true, ["construction-robot"] = true,
  pipe = true, ["pipe-to-ground"] = true, pump = true}
function M.cargo_category(name)
  local it = prototypes.item[name]
  if not it then return "other" end
  local sub = it.subgroup and it.subgroup.name or ""
  local group = it.group and it.group.name or ""
  if P.is_science(name) then return "science" end     -- то, что принимают лабы
  if it.type == "module" then return "modules" end
  -- капсула не всегда оружие (бывают едой): боеприпасом считаем только боевую группу
  if it.type == "ammo" or it.type == "gun" or it.type == "armor" or (it.type == "capsule" and group == "combat") then return "ammo" end
  local pr = it.place_result
  -- семена тоже ставятся, но это органика, а не постройки
  if pr and pr.type == "plant" then return "food" end
  if pr then return LOGISTICS[pr.type] and "logistics" or "buildings" end
  -- то, что идёт в броню (батареи, щиты, экзоскелеты...) — оборудование, а не постройка
  if it.place_as_equipment_result then return "equipment" end
  if it.place_as_tile_result then return "buildings" end
  -- что портится или едят — раньше топлива (часть еды горит)
  local spoils = false
  pcall(function() spoils = it.spoil_result ~= nil or (it.get_spoil_ticks() or 0) > 0 end)
  -- топливная категория: в 2.0 одна (fuel_category), в 2.1 список (fuel_categories)
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
          -- каждое качество отдельной строкой
          for _, it in pairs(inv.get_contents()) do cargo[#cargo + 1] = {name = it.name, count = it.count, quality = it.quality} end
        end
      end)
      -- сначала лучшее качество, потом большее количество (категории сохраняют этот порядок)
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

-- астероиды по размеру: {tier = huge|big|medium|small|other, n, hp}, крупные первыми
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

-- раз в несколько секунд: смотрим, куда летит каждая платформа, и ведём учёт текущего полёта:
-- когда вылетела, каждый прыжок (планета-планета) с началом и пройденным расстоянием. Прыжок закрывается,
-- когда платформа идёт дальше по следующей связи или паркуется; законченный полёт хранится как «последний»
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

-- закрыть полёт в учёте и сохранить как один из трёх последних
local function finish_flight(st, fl, place, now)
  if fl.cur then fl.cur.t1 = now; fl.cur.dist = 1; fl.legs[#fl.legs + 1] = fl.cur; fl.cur = nil end
  if fl.nodes[#fl.nodes] ~= place then fl.nodes[#fl.nodes + 1] = place end
  -- весь путь: длины всех пройденных связей; скорость по реально пройденному
  local km, covered = 0, 0
  for _, l in ipairs(fl.legs) do km = km + (l.len or 0); covered = covered + leg_km(l) end
  st.history = st.history or {}
  table.insert(st.history, 1, {from = fl.origin, to = place, nodes = fl.nodes, ticks = now - fl.start, km = km,
    speed = speed_of(covered, now - fl.start), tick = now})
  while #st.history > 3 do table.remove(st.history) end
  st.fl = nil
end

-- Учёт текущего полёта в storage: когда вылетела, планеты по порядку (`nodes`, чтобы был известен весь путь),
-- каждый прыжок с началом и пройденным. Прыжок закрывается, когда платформа идёт по следующей связи.
-- Полёт кончается, когда платформа остановилась (а не просто пролетает планету) или, если не останавливается
-- совсем, когда сменилась цель после достижения старой; сохраняется как один из трёх последних
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
            finish_flight(st, fl, fl.target, now)     -- цель достигнута, летит дальше без остановки
            fl = nil
          else
            fl.target = r.target                      -- перенаправили по пути (прерывание)
          end
        end
      end
      if r.from and r.from ~= r.to and r.oriented then   -- неуверенное направление ждёт следующего замера
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
      elseif fl and pl.space_location and r.state ~= "on_the_path" then   -- пролёт планеты по пути — не конец
        finish_flight(st, fl, pl.space_location.name, now)
      end
    end
  end
end

-- полёт идёт от вылета до остановки; у планеты по пути у платформы на миг нет связи, это не должно
-- выглядеть как конец
local function in_flight(r)
  return r.fl and (r.from or r.state == "on_the_path")
end

-- текущий полёт: время, пройденные км, средняя скорость (км/с длины связей), сделанные прыжки (`legs`),
-- текущий (`cur`, nil пока платформа у планеты по пути) и где платформа (`pos`)
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
    -- платформа уже на следующем прыжке, учёт догонит на следующем замере: старый прыжок закончен
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
      add_leg(c, now)       -- у планеты по пути: последний прыжок закончен
    end
    pos = c.to
  end
  local el = now - fl.start
  return {elapsed = el, km = km, route_km = route_km, speed = speed_of(km, el), legs = legs, cur = cur, origin = fl.origin,
    pos = pos, nodes = fl.nodes}
end

-- примерное время всего маршрута: длина / средняя скорость этого полёта (или, пока её нет, прошлого);
-- nil, если скорость неизвестна
function M.eta_ticks(r, total_km)
  if not total_km or total_km <= 0 then return nil end
  local f = M.flight(r)
  local v = f and f.speed
  if not v and r.history and r.history[1] then v = r.history[1].speed end
  if not v or v <= 0 then return nil end
  return math.floor(total_km / v * 60)
end

-- путь платформы к текущей цели (цель называет расписание или прерывание): пройденные прыжки этого
-- полёта, текущий и планеты впереди (кратчайший путь по длине связей).
-- прыжки: {from, to, len, kind = done | cur | next, ticks, speed}
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
    -- полёт, которого в учёте ещё нет (первые секунды): только этот прыжок и остальное
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
-- сколько платформ потеряно за всё время (список хранит последние 50)
function M.lost_total() local d = S(); return math.max(d.plat_lost_n or 0, #d.plat_lost) end

return M
