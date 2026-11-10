-- Factory Radar: planet titles (for every visited one)
local C = require("scripts.core_base")

---------------------------------------------------------------- planet titles (for every visited one)
-- base planets have their own names; the others (modded) get the form "Planet: Veteran"
C.PLANET_SPECIAL = {nauvis = true, vulcanus = true, fulgora = true, gleba = true, aquilo = true}
-- planet title kinds; needs = what the planet must have (enemies, lava, water, peace = no enemies at all),
-- pool = how many meme names a kind has (only kinds with a pool on every planet).
-- A modded planet gets three titles: from "presence", from "work" (both by planet name, so
-- planets differ) and one by what the planet has (THEME_ORDER). Base planets have their own
-- titles (pl-<kind>-<planet> in locale)
C.PLANET_TITLE_KINDS = {
  -- presence
  {kind = "veteran", key = "ptime", n = 24},                                   -- hours on the planet
  {kind = "wanderer", key = "pwalk", n = 30000},                               -- 30 km on foot
  {kind = "mortal", key = "pdeaths", n = 8},                                   -- died 8 times
  -- work
  {kind = "builder", key = "pbuilt", n = 8000},
  {kind = "handy", key = "pcraft", n = 1000},                                  -- hand crafting
  {kind = "warden", key = "pturrets", n = 100},                                -- turrets placed
  -- what the planet has (a task by the planet's theme)
  {kind = "defender", key = "pkills", n = 2000, needs = "enemies"},
  {kind = "lava", key = "pdeaths", n = 5, needs = "lava"},                     -- die on a lava planet
  {kind = "acid", key = "pbelts", n = 2000, needs = "acid"},                   -- belts next to acid
  {kind = "oil", key = "ppipe", n = 1000, needs = "oil"},                      -- pipes, pumps, tanks, wells on an oil planet
  {kind = "brine", key = "ppipe", n = 1500, needs = "brine"},                  -- same on a brine planet, but more
  {kind = "ammonia", key = "pfact", n = 150, needs = "ammonia"},               -- factories and furnaces on an ammonia planet
  {kind = "goo", key = "pfact", n = 300, needs = "goo"},                       -- factories and furnaces on a goo planet
  {kind = "uranium", key = "pdrill", n = 80, needs = "uranium"},               -- drills on a uranium planet
  {kind = "water", key = "pwalk", n = 40000, needs = "water"},                 -- 40 km on foot on a planet with water
  {kind = "dark", key = "pacc", n = 150, needs = "dark"},                      -- accumulators where there is little sun
  {kind = "bright", key = "psolar", n = 300, needs = "bright"},                -- solar panels where the sun is strong
  {kind = "heavy", key = "pwalk", n = 20000, needs = "heavy"},                 -- 20 km under heavy gravity
  {kind = "light", key = "ptime", n = 20, needs = "light"},                    -- hours under light gravity
  {kind = "vacuum", key = "pbuilt", n = 4000, needs = "vacuum"},               -- built without an atmosphere
  {kind = "trees", key = "pmine_tree", n = 1000, needs = "trees"},             -- trees cut
  {kind = "rocks", key = "pdrill", n = 150, needs = "rocks"},                  -- drills on a rocky planet
  {kind = "peace", key = "ptime", n = 24, needs = "peace"},
}
-- what a planet really has: enemy bases, lava, liquid (water, oceans). Found once from surface
-- settings. Enemies count also when someone was killed there. Stored with a version, not recounted
local FLAGS_V = 4
local function planet_flags(s, key)
  local d = C.D()
  d.pflags = d.pflags or {}
  local f = d.pflags[key]
  if not f or f.v ~= FLAGS_V then
    f = {v = FLAGS_V}
    pcall(function()
      local mgs = s.map_gen_settings
      -- autoplace controls: enemy bases, trees/plants, rocks, uranium
      for name, c in pairs(mgs.autoplace_controls or {}) do
        if (c.size or 0) > 0 then
          if name:find("enemy", 1, true) or name:find("nest", 1, true) then f.nests = true end
          if name:find("tree", 1, true) or name:find("plants", 1, true) then f.trees = true end
          if name:find("rock", 1, true) then f.rocks = true end
          if name:find("uranium", 1, true) then f.uranium = true end
        end
      end
      -- what is placed on the planet: trees, rocks, uranium
      local ent = mgs.autoplace_settings and mgs.autoplace_settings.entity and mgs.autoplace_settings.entity.settings or {}
      for name in pairs(ent) do
        local proto = prototypes.entity[name]
        local t = proto and proto.type
        if t == "tree" then f.trees = true
        elseif t == "simple-entity" and name:find("rock", 1, true) then f.rocks = true
        elseif t == "resource" and name:find("uranium", 1, true) then f.uranium = true end
      end
      -- liquids by type
      local tiles = mgs.autoplace_settings and mgs.autoplace_settings.tile and mgs.autoplace_settings.tile.settings or {}
      for name in pairs(tiles) do
        local proto = prototypes.tile[name]
        local fluid = proto and proto.fluid
        local fname = fluid and fluid.name or ""
        if name:find("lava", 1, true) or fname:find("lava", 1, true) then f.lava = true
        elseif fname:find("oil", 1, true) or fname:find("crude", 1, true) then f.oil = true
        elseif fname:find("ammon", 1, true) then f.ammonia = true
        elseif fname:find("acid", 1, true) or fname:find("sulfur", 1, true) then f.acid = true
        elseif fname:find("brine", 1, true) or fname:find("salt", 1, true) or fname:find("lithium", 1, true) then f.brine = true
        elseif fname:find("slime", 1, true) or fname:find("sludge", 1, true) or fname:find("jelly", 1, true)
          or fname:find("mud", 1, true) or fname:find("tar", 1, true) then f.goo = true
        elseif fname ~= "" then f.water = true end
      end
    end)
    -- surface properties (compared with a standard planet: gravity 10, pressure 1000, sun 100)
    pcall(function()
      local g, pr, sun = s.get_property("gravity"), s.get_property("pressure"), s.get_property("solar-power")
      if g then
        if g >= 15 then f.heavy = true elseif g <= 6 then f.light = true end
      end
      if pr and pr <= 100 then f.vacuum = true end
      if sun then
        if sun <= 40 then f.dark = true elseif sun >= 200 then f.bright = true end
      end
    end)
    d.pflags[key] = f
  end
  local pl = d.combat and d.combat.planets and d.combat.planets[key]
  local enemies = f.nests or (pl and pl.kills or 0) > 0
  return {nests = f.nests, lava = f.lava, water = f.water, oil = f.oil, ammonia = f.ammonia, trees = f.trees, rocks = f.rocks,
    uranium = f.uranium, acid = f.acid, brine = f.brine, goo = f.goo, heavy = f.heavy, light = f.light, vacuum = f.vacuum,
    dark = f.dark, bright = f.bright, enemies = enemies, peace = not enemies}
end

function C.planet_traits(key)
  local s = C.surface(key)
  if not (s and s.valid) then return nil end
  return planet_flags(s, key)
end

-- a player's sum over all planets with a trait: hours (lava, peace, uranium...), buildings (water, oil), kills (nests)
local HOURS_TRAITS = {lava = true, peace = true, uranium = true, ammonia = true, trees = true, rocks = true}
local BUILD_TRAITS = {water = true, oil = true}
function C.trait_sum(name, trait)
  local d = C.D()
  local total = 0
  if HOURS_TRAITS[trait] then
    for planet, ticks in pairs(d.ptime[name] or {}) do
      local f = C.planet_traits(planet)
      if f and f[trait] then total = total + ticks / 216000 end
    end
  elseif BUILD_TRAITS[trait] then
    for planet, by in pairs(d.pbuilt) do
      local f = by[name] and C.planet_traits(planet)
      if f and f[trait] then total = total + by[name] end
    end
  elseif trait == "nests" then
    for planet, n in pairs(d.pkills[name] or {}) do
      local f = C.planet_traits(planet)
      if f and f.nests then total = total + n end
    end
  end
  return total
end

-- titles of the other planets: "adjective noun" (ADJ x NOUN names per kind). Every planet of the game gets
-- its own combination in each kind, taken from the sorted list of ALL planets (seen or not),
-- so a name does not repeat or change when a new planet opens
local ADJ, NOUN = 12, 8
local function hash_name(str)
  local n = 5381
  for i = 1, #str do n = (n * 33 + string.byte(str, i)) % 2147483647 end
  return n
end
local function assign_names(all_names)
  local out = {}
  for _, k in ipairs(C.PLANET_TITLE_KINDS) do
    local used, map = {}, {}
    for _, name in ipairs(all_names) do
      local u = hash_name(k.kind .. "/" .. name) % (ADJ * NOUN)
      local tries = 0
      while used[u] and tries < ADJ * NOUN do u = (u + 1) % (ADJ * NOUN); tries = tries + 1 end
      used[u] = true
      map[name] = u
    end
    out[k.kind] = map
  end
  return out
end

-- a planet has three titles. Base planets have their own (veteran, builder, defender). A modded one gets a
-- "presence" kind, a "work" kind (by name) and one themed: the first from the list that the planet has
-- (enemies, lava, acid, oil, salt, ammonia, goo, uranium, water, no sun, strong sun, no air,
-- heavy and light gravity, trees, rocks), otherwise peaceful. Names as above, no repeats
local THEME_ORDER = {"defender", "lava", "acid", "oil", "brine", "ammonia", "goo", "uranium", "water", "dark", "bright",
  "vacuum", "heavy", "light", "trees", "rocks", "peace"}
local PRESENCE, WORK = {"veteran", "wanderer", "mortal"}, {"builder", "handy", "warden"}
local function planet_titles(list)
  local keys, surf = {}, {}
  for _, s in pairs(game.surfaces) do
    if C.RP(s) then
      local key = C.key(s)
      if key then keys[#keys + 1] = key; surf[key] = s end
    end
  end
  table.sort(keys)
  local all = C.all_planet_keys()
  table.sort(all)
  local names = assign_names(all)
  local by_kind = {}
  for _, k in ipairs(C.PLANET_TITLE_KINDS) do by_kind[k.kind] = k end
  local taken = {}
  for _, p in ipairs(keys) do
    local fl = planet_flags(surf[p], p)
    local kinds
    if C.PLANET_SPECIAL[p] then
      kinds = {"veteran", "builder", "defender"}
    else
      local theme = "peace"
      for _, name in ipairs(THEME_ORDER) do
        local k = by_kind[name]
        if k and (not k.needs or fl[k.needs]) then theme = name break end
      end
      kinds = {PRESENCE[hash_name(p .. "/presence") % #PRESENCE + 1], WORK[hash_name(p .. "/work") % #WORK + 1], theme}
    end
    for _, kind in ipairs(kinds) do
      local k = by_kind[kind]
      local lname, tagname
      if C.PLANET_SPECIAL[p] then
        lname = {"tr-title.pl-" .. kind .. "-" .. p}
        tagname = lname
      else
        local u = names[kind][p] or 0
        taken[kind] = taken[kind] or {}
        local tries = 0
        while taken[kind][u] and tries < ADJ * NOUN do u = (u + 1) % (ADJ * NOUN); tries = tries + 1 end   -- no repeated names
        taken[kind][u] = true
        tagname = {"", {"tr-title.modadj-" .. (u % ADJ + 1)}, " ", {"tr-title.modnoun-" .. kind .. "-" .. (math.floor(u / ADJ) % NOUN + 1)}}
        lname = {"", "[img=space-location/" .. p .. "] ", tagname}     -- in the chat tag it is tagname, without an icon
      end
      list[#list + 1] = {id = "pl-" .. kind .. "-" .. p, key = k.key .. ":" .. p, n = k.n, planet = p, lname = lname, tagname = tagname}
    end
  end
  return #keys
end
C.BASE_TITLES = C.TITLES
C.TITLE_KEYS = {}
do
  local seen = {}
  for _, t in ipairs(C.BASE_TITLES) do if not seen[t.key] then seen[t.key] = true; C.TITLE_KEYS[#C.TITLE_KEYS + 1] = t.key end end
end

-- the list in use: built-in titles with admin edits plus his own
local cache_ver, cache_list = nil, nil
local planets_at, planets_n = -1e9, 0
function C.titles()
  local cfg = storage.tr and storage.tr.cfg or {}
  -- planets are recounted every 10 seconds
  if game.tick < planets_at or game.tick - planets_at >= 600 then
    planets_at, planets_n = game.tick, 0
    for _, s in pairs(game.surfaces) do if C.RP(s) then planets_n = planets_n + 1 end end
  end
  local ver = (storage.tr and storage.tr.titles_ver or 0) .. "/" .. planets_n
  if cache_list and cache_ver == ver then return cache_list end
  local over = cfg.title_over or {}
  local list = {}
  for _, t in ipairs(C.BASE_TITLES) do
    local o = over[t.id] or {}
    if not o.off then
      list[#list + 1] = {id = t.id, key = t.key, n = o.n or t.n, name = (o.name and o.name ~= "") and o.name or nil}
    end
  end
  for _, t in ipairs(cfg.titles_custom or {}) do
    if not t.off then list[#list + 1] = {id = t.id, key = t.key, n = t.n, name = t.name, custom = true} end
  end
  if not cfg.planet_titles_off then planet_titles(list) end
  cache_ver, cache_list = ver, list
  C.TITLE_BY_ID = {}
  for _, t in ipairs(list) do C.TITLE_BY_ID[t.id] = t end
  return list
end
function C.titles_changed()
  local d = C.D()
  d.titles_ver = (d.titles_ver or 0) + 1
end
-- legendary titles (very hard): each syllable in its own colour (palette is the value: fire, gold,
-- ice, rainbow); coloured text is the locale key "<id>-c"
C.LEGEND = {
  ["legend-slayer"] = "fire", ["legend-builder"] = "gold", ["legend-crafter"] = "gold", ["legend-runner"] = "ice",
  ["legend-regular"] = "rainbow", ["legend-colonizer"] = "rainbow", ["legend-scientist"] = "ice",
  ["legend-mvp"] = "rainbow", ["legend-shifts"] = "gold", ["legend-thunder"] = "fire",
  -- serious (hard) titles: gradient by letters
  ["food-chain-end"] = "fire", ["factory-wont-build-itself"] = "gold", ["architect"] = "royal", ["forrest-gump"] = "aurora",
  ["interplanetary-pilot"] = "ice", ["star-wanderer"] = "sunset", ["columbus"] = "sunset", ["terraformer"] = "emerald",
  ["main-bus"] = "toxic", ["rail-world"] = "steel", ["turret-baron"] = "fire", ["breaking-not-building"] = "sunset",
  ["respawn-regular"] = "violet", ["mvp-eternal"] = "rainbow", ["mvp-boss"] = "gold", ["heisenberg"] = "toxic",
  ["italian"] = "italy", ["negotiations-over"] = "fire", ["darwin-award"] = "violet", ["pentapod-hunter"] = "emerald",
  -- even harder: each has its own colouring (gradient, every other letter, by words, capitals only, wave)
  ["belt-emperor"] = "alt", ["grid-lord"] = "alt", ["rail-baron"] = "duo", ["iron-bastion"] = "accent", ["fire-sovereign"] = "grad",
  ["demolition-titan"] = "duo", ["server-legend"] = "wave", ["untouchable"] = "grad", ["nest-breaker"] = "grad", ["endless-mind"] = "grad",
  ["eternal-wanderer"] = "grad", ["galaxy-master"] = "grad", ["living-rod"] = "alt", ["colony-emperor"] = "accent",
}
C.TITLE_BY_ID = {}
C.on_title = nil   -- set by the chat tags module
C.hooks = {}        -- set by the window module: popup(player, kind), popup_close(kind)

-- silent: grant without a chat message (after a recount, when many at once)
function C.check_titles(player, silent)
  if not (player and player.valid) or not C.S("tr-titles") then return end
  local d = C.D()
  local got = d.titles[player.name] or {}
  d.titles[player.name] = got
  for _, t in ipairs(C.titles()) do
    if not got[t.id] and C.title_value(player.name, t.key) >= t.n then
      got[t.id] = game.tick
      if not silent then
        local name, reason = C.title_rich(t.id), C.title_reason(t)
        C.send("title", {"tr-msg.title", player.name, name, reason}, {player = player.name, title = name, reason = reason},
          {0.85, 0.95, 1}, player)
      end
      if C.on_title then C.on_title(player) end
    end
  end
  C.check_ach(player)
end
