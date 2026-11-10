-- Factory Radar: titles and their colours
local C = require("scripts.core_base")

---------------------------------------------------------------- titles
C.TITLES = {
  {id = "exterminator", key = "kills", n = 100},
  {id = "hive-terror", key = "kills", n = 1000},
  {id = "walking-genocide", key = "kills", n = 5000},
  {id = "food-chain-end", key = "kills", n = 20000},
  {id = "foreman", key = "built", n = 10000},
  {id = "architect", key = "built", n = 100000},
  {id = "factory-wont-build-itself", key = "built", n = 500000},
  {id = "hand-assembler", key = "craft", n = 10000},
  {id = "human-factory", key = "craft", n = 100000},
  {id = "marathoner", key = "walk", n = 100000},
  {id = "forrest-gump", key = "walk", n = 500000},
  {id = "trucker", key = "ride", n = 500000},
  {id = "legend-slayer", key = "kills", n = 100000},
  {id = "legend-builder", key = "built", n = 2000000},
  {id = "legend-crafter", key = "craft", n = 1000000},
  {id = "legend-runner", key = "walk", n = 5000000},
  {id = "legend-regular", key = "online", n = 500},
  {id = "legend-colonizer", key = "colonizer", n = 10},
  {id = "legend-scientist", key = "infinite", n = 100},
  {id = "legend-mvp", key = "mvp_wins", n = 10},
  {id = "legend-shifts", key = "shifts", n = 100},
  {id = "legend-thunder", key = "zaps", n = 200},
  {id = "roulette-loser", key = "roulette_lost", n = 1},
  {id = "roulette-regular", key = "roulette_lost", n = 3},
  {id = "interplanetary-pilot", key = "ride", n = 2000000},
  {id = "immortal-not", key = "deaths", n = 10},
  {id = "professional-corpse", key = "deaths", n = 50},
  {id = "respawn-regular", key = "deaths", n = 150},
  {id = "tourist", key = "planets", n = 5},
  {id = "star-wanderer", key = "planets", n = 10},
  {id = "chief-slacker", key = "mined", n = 1000},
  {id = "demolition-crew", key = "mined", n = 10000},
  {id = "breaking-not-building", key = "mined", n = 50000},
  {id = "butterfingers", key = "ff", n = 10},
  {id = "saboteur", key = "ff", n = 100},
  {id = "keeper-of-ruins", key = "lost", n = 500},
  {id = "building-for-biters", key = "lost", n = 5000},
  {id = "pathfinder", key = "first", n = 3},
  {id = "columbus", key = "first", n = 8},
  {id = "colonizer", key = "colonizer", n = 3},
  {id = "terraformer", key = "colonizer", n = 6},
  {id = "local", key = "hours", n = 10},
  {id = "resident", key = "hours", n = 50},
  {id = "not-a-scratch", key = "streak", n = 500},
  {id = "infinite-scholar", key = "infinite", n = 25},
  -- factory life and memes
  {id = "factory-must-grow", key = "built", n = 50000},
  {id = "spaghetti-chef", key = "belts", n = 2000},
  {id = "main-bus", key = "belts", n = 20000},
  {id = "choo-choo", key = "rails", n = 2000},
  {id = "rail-world", key = "rails", n = 20000},
  {id = "electrician", key = "poles", n = 1000},
  {id = "turret-creep", key = "turrets", n = 100},
  {id = "turret-baron", key = "defense", n = 10000},
  {id = "nest-cleaner", key = "nests", n = 100},
  {id = "pyromaniac", key = "pyro", n = 1000},
  {id = "trains-real-enemy", key = "death_train", n = 3},
  {id = "self-taught-sapper", key = "death_self", n = 3},
  {id = "pedestrian", key = "death_vehicle", n = 3},
  {id = "biter-snack", key = "death_creature", n = 10},
  {id = "veteran", key = "online", n = 100},
  {id = "touch-grass", key = "online", n = 500},
  {id = "tea-break", key = "afk", n = 5},
  -- named
  {id = "pentapod-hunter", key = "pentapod", n = 1000},
  {id = "italian", key = "belts", n = 10000},
  {id = "shy", key = "novote_best", n = 10},
  {id = "unrecognized-genius", key = "genius_missed", n = 1},
  {id = "loser", key = "death_leader", n = 3},
  {id = "burden", key = "afk_end", n = 10},
  {id = "darwin-award", key = "death_self", n = 10},
  {id = "negotiations-over", key = "best_nests", n = 10},
  {id = "heisenberg", key = "nutrients_max", n = 3000},
  -- very hard, with a coloured name
  {id = "belt-emperor", key = "belts", n = 100000},
  {id = "grid-lord", key = "poles", n = 20000},
  {id = "rail-baron", key = "rails", n = 100000},
  {id = "iron-bastion", key = "defense", n = 100000},
  {id = "fire-sovereign", key = "pyro", n = 20000},
  {id = "demolition-titan", key = "mined", n = 250000},
  {id = "server-legend", key = "online", n = 2000},
  {id = "untouchable", key = "streak", n = 5000},
  {id = "nest-breaker", key = "nests", n = 1000},
  {id = "endless-mind", key = "infinite", n = 500},
  {id = "eternal-wanderer", key = "walk", n = 20000000},
  {id = "galaxy-master", key = "planets", n = 20},
  {id = "living-rod", key = "zapped", n = 300},
  {id = "colony-emperor", key = "colonizer", n = 25},
  -- MVP
  {id = "mvp-star", key = "mvp_wins", n = 1},
  {id = "mvp-pillar", key = "mvp_wins", n = 3},
  {id = "mvp-boss", key = "mvp_wins", n = 5},
  {id = "mvp-eternal", key = "mvp_wins", n = 25},
}
C.TITLE_UNIT = {walk = "km", ride = "km", hours = "h", online = "h", afk = "h", best_walk = "km", trait_lava = "h", trait_peace = "h", trait_uranium = "h"}
C.TITLE_HIDDEN_PROGRESS = {roulette_lost = true, deaths = true, lost = true, ff = true, death_train = true, death_self = true,
  death_vehicle = true, death_creature = true, afk = true, death_leader = true, afk_end = true, novote_best = true,
  genius_missed = true}

-- unit of a title (km, h or nil); planet keys look like ptime:vulcanus
function C.unit(key)
  local base = string.match(key, "^([%w_]+):") or key
  if base == "ptime" then return "h" end
  if base == "pwalk" then return "km" end
  return C.TITLE_UNIT[base]
end

-- extra player stats (for achievements): flights, MVP wins, shifts, lightning...
function C.pstat(name, key) local t = C.D().pstat[name]; return t and t[key] or 0 end
function C.pstat_add(name, key, n)
  local d = C.D()
  d.pstat[name] = d.pstat[name] or {}
  d.pstat[name][key] = (d.pstat[name][key] or 0) + (n or 1)
end

local PLAYER_PLANET = {pwalk = true, pdeaths = true, ppipe = true, pcraft = true, pmine_tree = true, pmine_rock = true, pturrets = true,
  psolar = true, pbelts = true, pacc = true, pdrill = true, pfact = true}
-- extra player stats in pstat
local PSTAT = {space = true, mvp_wins = true, shifts = true, zaps = true, zapped = true, roulette_lost = true, pentapod = true,
  novote_best = true, death_leader = true, afk_end = true, nutrients_max = true, genius_missed = true}
function C.title_value(name, key)
  local d = C.D()
  local r = C.rec(d.total, name)
  local base, planet = string.match(key, "^([%w_]+):(.+)$")
  if base == "ptime" then return ((d.ptime[name] or {})[planet] or 0) / 216000 end
  if base == "pbuilt" then return ((d.pbuilt[planet] or {})[name] or 0) end
  if base == "pkills" then return ((d.pkills[name] or {})[planet] or 0) end
  if PLAYER_PLANET[base] then return ((d[base] or {})[name] or {})[planet] or 0 end
  if string.sub(key, 1, 6) == "trait_" then return C.trait_sum(name, string.sub(key, 7)) end
  if string.sub(key, 1, 5) == "best_" then return ((d.pbest[name] or {})[string.sub(key, 6)] or 0) end
  if PSTAT[key] then return C.pstat(name, key) end
  if key == "planets" then return C.planets_visited(name) end
  if key == "first" then
    local n = 0
    for _, v in pairs(d.first) do if v.who == name then n = n + 1 end end
    return n
  end
  if key == "colonizer" then
    local n = 0
    for _, st in pairs(d.planets) do if st.mastered and st.by == name then n = n + 1 end end
    return n
  end
  if key == "hours" then return C.best_planet_time(name) / 216000 end
  if key == "streak" then return (d.records.best_streak or {})[name] or 0 end
  if key == "infinite" then return (d.research.levels_by and d.research.levels_by[name]) or 0 end
  if key == "online" then
    local p = game.get_player(name)
    return p and p.online_time / 216000 or 0
  end
  if key == "afk" then return (d.afk_time[name] or 0) / 216000 end
  if key == "pyro" then
    local n = 0
    for w, c in pairs((d.combat.pweap or {})[name] or {}) do if string.find(w, "flamethrower", 1, true) then n = n + c end end
    return n
  end
  if string.sub(key, 1, 6) == "death_" then return (d.death_kinds[name] or {})[string.sub(key, 7)] or 0 end
  return r[key] or 0
end

function C.title_name(id)
  C.titles()
  local t = C.TITLE_BY_ID[id]
  if t and t.name then return t.name end
  if t and t.lname then return t.lname end
  if t and t.custom then return id end
  local cfg = storage.tr and storage.tr.cfg
  for _, c in ipairs(cfg and cfg.titles_custom or {}) do if c.id == id then return c.name end end
  return {"tr-title." .. id}
end

-- name for the chat tag: without the planet icon
function C.title_tagname(id)
  C.titles()
  local t = C.TITLE_BY_ID[id]
  if t and t.tagname then return t.tagname end
  return C.title_name(id)
end

-- 1234567 -> "1 234 567" (exact, for round thresholds)
function C.big(n)
  local s = tostring(math.floor(n))
  local out = s:reverse():gsub("(%d%d%d)", "%1 "):reverse()
  return (out:gsub("^ ", ""))
end

-- "kills: 100" and the like
function C.fmt_amount(key, n)
  local u = C.unit(key)
  if u == "km" then return {"tr.dist-km", C.big(n / 1000)} end
  if u == "h" then return {"tr.hours", (n == math.floor(n)) and tostring(n) or string.format("%.1f", n)} end
  return C.big(n)
end
function C.title_by_id(id)
  for _, t in ipairs(C.titles()) do if t.id == id then return t end end
  return nil
end

function C.title_reason(t)
  local base, planet = string.match(t.key, "^([%w_]+):(.+)$")
  if base then return {"tr-why." .. base, C.fmt_amount(t.key, t.n), C.planet_ls(planet)} end
  return {"tr-why." .. t.key, C.fmt_amount(t.key, t.n)}
end

---------------------------------------------------------------- title colours
local COLOR_OF = {
  kills = "1,0.45,0.35", streak = "1,0.45,0.35", nests = "1,0.45,0.35", defense = "1,0.55,0.4", pkills = "1,0.45,0.35",
  built = "1,0.72,0.3", belts = "1,0.72,0.3", rails = "1,0.72,0.3", poles = "1,0.8,0.35", turrets = "1,0.6,0.3",
  pbuilt = "1,0.72,0.3", craft = "1,0.9,0.4", walk = "0.45,0.85,1", ride = "0.45,0.85,1",
  planets = "0.78,0.62,1", first = "0.78,0.62,1", colonizer = "0.78,0.62,1", hours = "0.78,0.62,1", ptime = "0.78,0.62,1",
  deaths = "0.72,0.72,0.72", mined = "0.85,0.62,0.45", ff = "1,0.55,0.75", lost = "0.85,0.5,0.45",
  infinite = "0.45,0.72,1", online = "0.6,1,0.6", afk = "0.6,1,0.6", pyro = "1,0.55,0.15",
}
-- every title has its own colour: the theme colour (planet kind or stat group), shifted a bit
-- by the id hash, so two titles of one theme differ
local function str_hash(str)
  local n = 5381
  for i = 1, #str do n = (n * 33 + string.byte(str, i)) % 2147483647 end
  return n
end
local function rgb_to_hsv(r, g, b)
  local mx, mn = math.max(r, g, b), math.min(r, g, b)
  local d = mx - mn
  local h = 0
  if d > 0 then
    if mx == r then h = ((g - b) / d) % 6 elseif mx == g then h = (b - r) / d + 2 else h = (r - g) / d + 4 end
    h = h * 60
  end
  return h, mx > 0 and d / mx or 0, mx
end
local function hsv_to_rgb(h, s, v)
  local c = v * s
  local x = c * (1 - math.abs((h / 60) % 2 - 1))
  local m = v - c
  local r, g, b = 0, 0, 0
  if h < 60 then r, g, b = c, x, 0 elseif h < 120 then r, g, b = x, c, 0 elseif h < 180 then r, g, b = 0, c, x
  elseif h < 240 then r, g, b = 0, x, c elseif h < 300 then r, g, b = x, 0, c else r, g, b = c, 0, x end
  return string.format("%.3f,%.3f,%.3f", r + m, g + m, b + m)
end
local KIND_HUE = {lava = 12, water = 205, oil = 35, ammonia = 175, trees = 118, rocks = 28, uranium = 88, peace = 150,
  veteran = 270, builder = 48, defender = 2}
function C.title_color(id)
  if C.LEGEND[id] then return "1,0.92,0.55" end
  C.titles()
  local t = C.TITLE_BY_ID[id]
  local h = str_hash(id)
  local hue, sat, val
  if t and t.planet then
    local kind = string.match(id, "^pl%-(%a+)%-")
    hue, sat, val = KIND_HUE[kind] or (h % 360), 0.55, 1
  else
    local rgb = "0.95,0.95,0.6"
    if t and not t.custom then
      local base = string.match(t.key, "^([%w_]+):") or t.key
      if string.sub(base, 1, 6) == "death_" then base = "deaths" end
      rgb = COLOR_OF[base] or "1,0.85,0.3"
    end
    local r, g, b = string.match(rgb, "([%d%.]+),([%d%.]+),([%d%.]+)")
    hue, sat, val = rgb_to_hsv(tonumber(r), tonumber(g), tonumber(b))
    sat = math.max(sat, 0.3)
  end
  hue = (hue + (h % 41) - 20) % 360
  val = math.max(0.75, val - (math.floor(h / 41) % 3) * 0.06)
  return hsv_to_rgb(hue, sat, val)
end
-- the name in its own colour (quotes come from the locale text around it)
function C.title_rich(id)
  C.titles()
  if C.LEGEND[id] then
    local t = C.TITLE_BY_ID[id]
    if not (t and t.name) then return {"", {"tr-title." .. id .. "-c"}} end    -- a name set by the admin is painted in one colour
  end
  return {"", "[color=" .. C.title_color(id) .. "]", C.title_name(id), "[/color]"}
end
-- as in chat: no planet icon in the name
function C.title_rich_tag(id)
  C.titles()
  if C.LEGEND[id] then return C.title_rich(id) end
  return {"", "[color=" .. C.title_color(id) .. "]", C.title_tagname(id), "[/color]"}
end
