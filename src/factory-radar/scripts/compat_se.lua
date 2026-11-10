-- Factory Radar: optional Space Exploration compatibility.
-- Works only through SE's official remote interface and never touches another mod's storage.
-- If SE is missing, old or broken, every function just returns nil and the mod works as before.
local M = {}

local SOLID = {planet = true, moon = true}
local ANY = {planet = true, moon = true, orbit = true, ["asteroid-belt"] = true, ["asteroid-field"] = true, anomaly = true}
M.SOLID, M.ANY = SOLID, ANY

local caches = {
  all = nil,             -- {by_name=..., by_index=..., solid=..., ok=bool, tick=...}
  surface = {},          -- [surface.index] = {name=..., zone=...|false}
  known = nil,           -- {tick=..., set={[zone_index]=true}}
  icon = {},             -- [zone.name] = sprite path | false
}
M.caches = caches

function M.reset()
  caches.all = nil
  caches.surface = {}
  caches.known = nil
  caches.icon = {}
end

local function call(name, data)
  if not (remote and remote.call) then return nil end
  local ok, res = pcall(remote.call, "space-exploration", name, data)
  if ok then return res end
  return nil
end

function M.active()
  -- SE is optional: if it is in the game, the regular factory-radar shows SE zones itself.
  -- If SE is missing or its remote interface is unavailable, the layer stays silent.
  if not (script and script.active_mods and script.active_mods["space-exploration"]) then return false end
  local i = remote and remote.interfaces and remote.interfaces["space-exploration"]
  return (i and i.get_zone_from_surface_index and i.get_zone_index) and true or false
end

local function compact(z)
  if type(z) ~= "table" or type(z.name) ~= "string" or type(z.index) ~= "number" then return nil end
  return {
    name = z.name,
    index = z.index,
    type = z.type,
    parent_index = z.parent_index,
    surface_index = z.surface_index,
    is_homeworld = z.is_homeworld,
    radius = z.radius,
  }
end

local function key_of(zone)
  -- Nauvis already comes through surface.planet with key "nauvis"; do not add a zone with the same name twice
  if zone.surface_index == 1 or zone.name == "Nauvis" then return "nauvis" end
  return zone.name
end
M.key_of = key_of

local function load_all()
  local c = caches.all
  if c and c.ok then return c end
  if c and c.tick and game.tick - c.tick < 600 then return c end
  local list = call("get_zone_index", {})
  c = {by_name = {}, by_index = {}, solid = {}, ok = false, tick = game.tick}
  if type(list) == "table" then
    local any = false
    for _, raw in pairs(list) do
      local z = compact(raw)
      if z then
        any = true
        c.by_index[z.index] = z
      end
    end
    if any then
      -- separate, so pairs order affects nothing except sorting
      for _, z in pairs(c.by_index) do
        if not c.by_name[z.name] then c.by_name[z.name] = z end
        if SOLID[z.type] and key_of(z) ~= "nauvis" then c.solid[#c.solid + 1] = key_of(z) end
      end
      table.sort(c.solid)
      c.ok = true
    end
  end
  caches.all = c
  return c
end
M.load_all = load_all

local function zone_surface(zone)
  if not (zone and zone.surface_index) then return nil end
  local s = game.get_surface and game.get_surface(zone.surface_index)
  if s and s.valid then return s end
  return nil
end

function M.zone_from_surface(surface)
  if not (surface and surface.valid) then return nil end
  local hit = caches.surface[surface.index]
  if hit and hit.name == surface.name then return hit.zone or nil end
  local raw = call("get_zone_from_surface_index", {surface_index = surface.index})
  local zone = compact(raw)
  caches.surface[surface.index] = {name = surface.name, zone = zone or false}
  return zone
end

function M.surface_key(surface, allowed)
  if surface and surface.planet then return nil end -- regular planet/SA: the key comes from core
  local zone = M.zone_from_surface(surface)
  if zone and (not allowed or allowed[zone.type]) then return key_of(zone) end
  return nil
end

local function ensure_known()
  local k = caches.known
  if k and game.tick - k.tick < 3600 and game.tick >= k.tick then return k.set end
  local force = game.forces["player"]
  local raw = force and call("get_known_zones", {force_name = force.name})
  local set = {}
  if type(raw) == "table" then
    for index in pairs(raw) do
      if type(index) == "number" then set[index] = true end
    end
  end
  -- at the very start SE does not give the list yet: if zone surfaces already exist, treat them as known
  if next(set) == nil then
    local all = load_all()
    if all.ok then
      for _, z in pairs(all.by_index) do
        if zone_surface(z) then set[z.index] = true end
      end
    end
  end
  caches.known = {tick = game.tick, set = set}
  return set
end

local function zone_known(zone, set, all)
  if set[zone.index] then return true end
  -- an orbit is known together with its parent, as in SE itself
  if zone.type == "orbit" and zone.parent_index and all.by_index[zone.parent_index] then
    return set[zone.parent_index] == true
  end
  return false
end

-- known zones: solid=true is planets and moons only; otherwise all habitable types (orbits, belts, fields)
function M.known_keys(solid)
  if not M.active() then return {} end
  local all = load_all()
  if not all.ok then return {} end
  local set = ensure_known()
  local out = {}
  for _, z in pairs(all.by_index) do
    local allowed = (solid and SOLID[z.type]) or ((not solid) and ANY[z.type])
    if allowed and key_of(z) ~= "nauvis" and zone_known(z, set, all) then out[#out + 1] = key_of(z) end
  end
  table.sort(out)
  return out
end

-- all planets and moons of the world, only for stable title names, not shown in the window
function M.all_solid_keys()
  if not M.active() then return {} end
  local all = load_all()
  if not all.ok then return {} end
  return all.solid
end

function M.zone_by_key(key)
  if not key or not M.active() then return nil end
  local all = load_all()
  if not all.ok then return nil end
  if key == "nauvis" then return all.by_name["Nauvis"] end
  return all.by_name[key]
end

function M.surface(key)
  local zone = M.zone_by_key(key)
  if zone then
    local s = zone_surface(zone)
    if s then return s end
  end
  if not key then return nil end
  local s = game.get_surface and game.get_surface(key)
  if s and s.valid then return s end
  return nil
end

local function fallback_icon(zone, all)
  if zone.type == "orbit" then
    local parent = zone.parent_index and all.by_index[zone.parent_index]
    local pt = parent and parent.type
    if pt == "moon" then return "virtual-signal/se-moon-orbit" end
    if pt == "star" then return "virtual-signal/se-star" end
    return "virtual-signal/se-planet-orbit"
  end
  if zone.type == "planet" then return "virtual-signal/se-planet" end
  if zone.type == "moon" then return "virtual-signal/se-moon" end
  if zone.type == "anomaly" then return "virtual-signal/se-anomaly" end
  if zone.type == "asteroid-belt" then return "virtual-signal/se-asteroid-belt" end
  if zone.type == "asteroid-field" then return "virtual-signal/se-asteroid-field" end
  return nil
end

function M.place_icon(key)
  local zone = M.zone_by_key(key)
  if not zone then return nil end
  local hit = caches.icon[zone.name]
  if hit ~= nil then return hit or nil end
  local all = load_all()
  local icon = call("get_zone_icon", {zone_index = zone.index})
  if type(icon) ~= "string" then icon = fallback_icon(zone, all) end
  if not (icon and helpers and helpers.is_valid_sprite_path and helpers.is_valid_sprite_path(icon)) then icon = nil end
  caches.icon[zone.name] = icon or false
  return icon
end

function M.place_ls(key)
  local zone = M.zone_by_key(key)
  if not zone then return nil end
  local s = zone_surface(zone) or (game.surfaces and game.surfaces[key])
  local name = s and s.localised_name
  if type(name) == "string" then return {"", name} end
  if name then return name end
  local icon = M.place_icon(key)
  if icon then return {"", "[img=" .. icon .. "] ", zone.name} end
  return {"", zone.name}
end

return M
