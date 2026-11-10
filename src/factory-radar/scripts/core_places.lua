-- Factory Radar: places: planet and zone keys, surfaces, icons, names
local C = require("scripts.core_base")
local SE = C.SE

function C.gps(pos, surface)
  return "[gps=" .. math.floor(pos.x) .. "," .. math.floor(pos.y) .. "," .. surface.name .. "]"
end

-- Key of a real planet or moon: regular planet/SA or an SE zone of type planet/moon.
-- nil for orbits, belts, fields and ships: they are not counted as a "planet" in statistics.
function C.key(surface)
  if not (surface and surface.valid) then return nil end
  if surface.planet then
    local pr = surface.planet.prototype
    if pr and not pr.hidden then return pr.name end
    return nil
  end
  return SE.surface_key(surface, SE.SOLID)
end

-- Key of any habitable place: planet, moon, orbit, asteroid belt/field, anomaly.
-- Needed by item search, science and power grids, where a base can stand outside a planet too.
function C.location_key(surface)
  if not (surface and surface.valid) then return nil end
  if surface.planet then
    local pr = surface.planet.prototype
    if pr and not pr.hidden then return pr.name end
    return nil
  end
  return SE.surface_key(surface, SE.ANY)
end

-- a real visible planet (mods can create hidden ones)
function C.RP(surface)
  local key = C.key(surface)
  return key ~= nil and not C.ignored(key)
end

-- any habitable place, including SE orbits and asteroid zones
function C.LOC(surface)
  local key = C.location_key(surface)
  return key ~= nil and not C.ignored(key)
end

-- surface by planet/zone key: regular planets, then surfaces by name, then an SE zone
function C.surface(key)
  if not key then return nil end
  local pl = game.planets and game.planets[key]
  ---@diagnostic disable-next-line: undefined-field
  local s = pl and pl.surface
  ---@diagnostic disable-next-line: undefined-field
  if s and s.valid then return s end
  s = game.surfaces[key]
  if s and s.valid then return s end
  return SE.surface(key)
end

-- all visible planets of the game: regular planets plus known SE planets and moons
function C.planets_list(include_ignored)
  local out, seen = {}, {}
  for name, pl in pairs(game.planets or {}) do
    if not pl.prototype.hidden and (include_ignored or not C.ignored(name)) then
      out[#out + 1] = name
      seen[name] = true
    end
  end
  if SE.active() then
    for _, key in ipairs(SE.known_keys(true)) do
      if not seen[key] and (include_ignored or not C.ignored(key)) then
        out[#out + 1] = key
        seen[key] = true
      end
    end
  end
  table.sort(out)
  return out
end

-- all known places for filters: planets, moons, orbits, belt/fields
function C.locations_list(include_ignored)
  local out, seen = {}, {}
  for name, pl in pairs(game.planets or {}) do
    if not pl.prototype.hidden and (include_ignored or not C.ignored(name)) then
      out[#out + 1] = name
      seen[name] = true
    end
  end
  if SE.active() then
    for _, key in ipairs(SE.known_keys(false)) do
      if not seen[key] and (include_ignored or not C.ignored(key)) then
        out[#out + 1] = key
        seen[key] = true
      end
    end
  end
  table.sort(out)
  return out
end

-- all planets of the world (including undiscovered) only for stable title names
function C.all_planet_keys()
  local out, seen = {}, {}
  for name, pl in pairs(game.planets or {}) do
    if not pl.prototype.hidden then out[#out + 1] = name; seen[name] = true end
  end
  if SE.active() then
    for _, key in ipairs(SE.all_solid_keys()) do
      if not seen[key] then out[#out + 1] = key; seen[key] = true end
    end
  end
  table.sort(out)
  return out
end

-- icon path of a place for the GUI: a real space-location, otherwise the SE zone icon
function C.place_icon(key)
  local path = "space-location/" .. key
  if helpers.is_valid_sprite_path(path) then return path end
  return SE.place_icon(key)
end

function C.planet_ls(key)
  if C.SE.active() then
    local se = SE.place_ls(key)
    if se then return se end
  end
  local pl = prototypes.space_location and prototypes.space_location[key]
  local path = "space-location/" .. key
  local icon = helpers.is_valid_sprite_path(path) and ("[img=" .. path .. "] ") or ""
  if pl then return {"", icon, pl.localised_name} end
  return {"", icon, key}
end

-- Players write platform names with icons ([item=..], [planet=..]). In chat such tags show
-- as words in brackets, so they are turned into [img=..]; a tag with no picture is dropped
local TAG_SPRITE = {item = "item", entity = "entity", planet = "space-location", ["space-location"] = "space-location",
  ["virtual-signal"] = "virtual-signal", fluid = "fluid", recipe = "recipe", technology = "technology", tech = "technology",
  quality = "quality"}
function C.chat_rich(s)
  if type(s) ~= "string" then return s end
  return (s:gsub("%[([%w%-]+)=([^%],]+)[^%]]*%]", function(tag, name)
    local prefix = TAG_SPRITE[tag]
    if not prefix then return nil end
    local path = prefix .. "/" .. name
    if helpers.is_valid_sprite_path(path) then return "[img=" .. path .. "]" end
    return ""
  end))
end

function C.place(surface)
  if surface.platform then
    return {"", "[img=item/space-platform-starter-pack] «", C.chat_rich(surface.platform.name), "»"}
  end
  if surface.planet then return C.planet_ls(surface.planet.prototype.name) end
  -- SE zones and ships: the game already stores a proper localised surface name
  return surface.localised_name or surface.name
end

return C
