-- Factory Radar: item search over logistic networks of all planets and platforms
-- counted only on request (quick access button), nothing runs in the background
local C = require("scripts.core")
local M = {}

-- how much of an item is in an entity and available to the network: containers, platform hold, cargo landing pad, machine output,
-- the player's CHARACTER (what they carry, the network counts it too), roboport (robots and repair packs inside), spider.
-- Inventory numbers match across types, so each type uses its own (otherwise a machine could "find" foreign items).
-- nil means a type we cannot look into
local function count_in(ent, name, quality)
  local t = ent.type
  local it = {name = name, quality = quality or "normal"}
  if t == "container" or t == "logistic-container" then return ent.get_inventory(defines.inventory.chest).get_item_count(it) end
  if t == "space-platform-hub" then return ent.get_inventory(defines.inventory.hub_main).get_item_count(it) end
  if t == "cargo-landing-pad" then return ent.get_inventory(defines.inventory.cargo_landing_pad_main).get_item_count(it) end
  if t == "assembling-machine" or t == "furnace" then return ent.get_output_inventory().get_item_count(it) end
  if t == "character" then return ent.get_item_count(it) end
  if t == "roboport" then
    local n = 0
    for _, idx in ipairs({defines.inventory.roboport_robot, defines.inventory.roboport_material}) do
      local inv = ent.get_inventory(idx)
      if inv then n = n + inv.get_item_count(it) end
    end
    return n
  end
  if t == "spider-vehicle" then return ent.get_inventory(defines.inventory.spider_trunk).get_item_count(it) end
  return nil
end

-- what lies in the network at characters: counted separately ("with players")
local function chars_in(net, name, quality)
  local n = 0
  pcall(function()
    for _, m in ipairs(net.providers or {}) do
      if m.valid and m.type == "character" then n = n + (m.get_item_count{name = name, quality = quality} or 0) end
    end
  end)
  return n
end

-- how much of an item (with quality) is available in logistic networks, by planet and platform, biggest first; zeros are skipped
function M.search(name, quality)
  local rows, total = {}, 0
  if not (name and prototypes.item[name]) then return rows, total end
  local nets = game.forces.player.logistic_networks
  for sname, list in pairs(nets) do
    local s = game.surfaces[sname]
    if s and s.valid then
      local planet = C.LOC(s) and C.location_key(s) or nil
      local plat = s.platform and s.platform.valid and s.platform or nil
      if planet or plat then
        local sum, n = 0, 0
        for _, net in ipairs(list) do
          if net.valid then
            local ok, c = pcall(function() return net.get_item_count{name = name, quality = quality or "normal"} end)
            if ok and type(c) == "number" then c = math.max(0, c - chars_in(net, name, quality or "normal")) end
            if ok and type(c) == "number" and c > 0 then sum = sum + c; n = n + 1 end
          end
        end
        if sum > 0 then
          rows[#rows + 1] = {planet = planet, platform = plat and plat.name or nil, count = sum, nets = n}
          total = total + sum
        end
      end
    end
  end
  -- platforms: cargo lies in the hub hold, and a platform may have no logistic network
  local by_plat = {}
  for _, r in ipairs(rows) do if r.platform then by_plat[r.platform] = r end end
  for _, pl in pairs(game.forces.player.platforms) do
    if pl.valid then
      local hub = pl.hub
      if hub and hub.valid then
        local ok, c = pcall(count_in, hub, name, quality)
        if ok and type(c) == "number" and c > 0 then
          local r = by_plat[pl.name]
          if r then
            if c > r.count then total = total + (c - r.count); r.count = c end
          else
            rows[#rows + 1] = {platform = pl.name, count = c, nets = 0}
            total = total + c
          end
        end
      end
    end
  end
  table.sort(rows, function(a, b)
    if a.count ~= b.count then return a.count > b.count end
    return (a.planet or a.platform or "") < (b.planet or b.platform or "")
  end)
  return rows, total
end

-- how much of an item players carry (character inventory), biggest first, with the place where the player stands
function M.carried(name, quality)
  local out = {}
  if not (name and prototypes.item[name]) then return out end
  for _, pl in pairs(game.players) do
    local ch = pl.character
    if ch and ch.valid then
      local ok, c = pcall(ch.get_item_count, {name = name, quality = quality or "normal"})
      if ok and type(c) == "number" and c > 0 then
        local s = ch.surface
        local planet = C.LOC(s) and C.location_key(s) or nil
        local plat = s.platform and s.platform.valid and s.platform.name or nil
        out[#out + 1] = {player = pl.name, count = c, surface = s.index, planet = planet, platform = plat,
          x = ch.position.x, y = ch.position.y}
      end
    end
  end
  table.sort(out, function(a, b) return a.count > b.count end)
  return out
end

-- containers of surface logistic networks that hold the item, biggest first.
-- The second value is how much of the item is in ALL found containers (not only the shown ones)
function M.chests(s, name, quality, limit)
  local out, seen, sum, unknown = {}, {}, 0, {}
  local function entry(ent, c)
    local box = {ent.position.x - 0.5, ent.position.y - 0.5, ent.position.x + 0.5, ent.position.y + 0.5}
    pcall(function()
      local sb = ent.selection_box
      box = {sb.left_top.x, sb.left_top.y, sb.right_bottom.x, sb.right_bottom.y}
    end)
    local ql = "normal"
    pcall(function() ql = ent.quality.name end)
    return {name = ent.name, count = c, x = ent.position.x, y = ent.position.y, box = box, quality = ql}
  end
  -- platform hub: the hold with cargo (a platform may have no logistic network)
  local hub = s.platform and s.platform.valid and s.platform.hub
  if hub and hub.valid then
    local ok, c = pcall(count_in, hub, name, quality)
    if ok and type(c) == "number" and c > 0 then
      sum = sum + c
      out[#out + 1] = entry(hub, c)
      if hub.unit_number then seen[hub.unit_number] = true end
    end
  end
  local nets = game.forces.player.logistic_networks[s.name] or {}
  for _, net in ipairs(nets) do
    if net.valid then
      -- buffer chests are among requesters and network members, not among providers: take them from there
      local extra = {}
      pcall(function()
        for _, list in ipairs({net.requesters or {}, net.logistic_members or {}}) do
          for _, m in ipairs(list) do
            if m.valid and m.type == "logistic-container" and m.prototype.logistic_mode == "buffer" then extra[#extra + 1] = m end
          end
        end
      end)
      for _, list in ipairs({net.storages or {}, net.providers or {}, extra}) do
        for _, ent in ipairs(list) do
          local mode = nil
          pcall(function() mode = ent.prototype.logistic_mode end)
          -- what lies in a requester chest is not available to the others
          if ent.valid and ent.unit_number and not seen[ent.unit_number] and mode ~= "requester" and ent.type ~= "character" then
            seen[ent.unit_number] = true
            local ok, c = pcall(count_in, ent, name, quality)
            if ok and c == nil then
              -- a type we cannot look into: remembered to show in the window (helps to see where items went)
              unknown[ent.type] = (unknown[ent.type] or 0) + 1
            elseif ok and type(c) == "number" and c > 0 then
              sum = sum + c
              local box = {ent.position.x - 0.5, ent.position.y - 0.5, ent.position.x + 0.5, ent.position.y + 0.5}
              pcall(function()
                local sb = ent.selection_box
                box = {sb.left_top.x, sb.left_top.y, sb.right_bottom.x, sb.right_bottom.y}
              end)
              local ql = "normal"
              pcall(function() ql = ent.quality.name end)
              local who = nil
              if ent.type == "character" then
                pcall(function() who = ent.player and ent.player.name end)
                who = who or false
              end
              out[#out + 1] = {name = ent.name, count = c, x = ent.position.x, y = ent.position.y, box = box, player = who, quality = ql}
            end
          end
        end
      end
    end
  end
  table.sort(out, function(a, b) return a.count > b.count end)
  local n_all = #out
  while #out > (limit or 1000) do table.remove(out) end
  return out, sum, unknown, n_all
end

---------------------------------------------------------------- plain containers outside logistic networks
-- Counted on request and one planet at a time (by timer) so the game does not freeze. State is in storage.
-- machines: what lies inside (ingredients and result, no modules)
local MACHINE_INV = {
  ["assembling-machine"] = {"crafter_input", "crafter_output"},
  furnace = {"furnace_source", "furnace_result"},
  lab = {"lab_input"},
  ["rocket-silo"] = {"rocket_silo_input", "rocket_silo_output"},
}
local function machine_count(ent, name, quality)
  local n = 0
  for _, key in ipairs(MACHINE_INV[ent.type] or {}) do
    local idx = defines.inventory[key]
    local inv = idx and ent.get_inventory(idx)
    if inv then n = n + inv.get_item_count{name = name, quality = quality} end
  end
  return n
end

local function scan_machines(s, name, quality)
  local list, sum, n = {}, 0, 0
  local ents = s.find_entities_filtered{type = {"assembling-machine", "furnace", "lab", "rocket-silo"}, force = game.forces.player}
  for _, ent in ipairs(ents) do
    if ent.valid then
      local ok, c = pcall(machine_count, ent, name, quality)
      if ok and type(c) == "number" and c > 0 then
        n = n + 1
        sum = sum + c
        local box = {ent.position.x - 0.5, ent.position.y - 0.5, ent.position.x + 0.5, ent.position.y + 0.5}
        pcall(function()
          local sb = ent.selection_box
          box = {sb.left_top.x, sb.left_top.y, sb.right_bottom.x, sb.right_bottom.y}
        end)
        local ql = "normal"
        pcall(function() ql = ent.quality.name end)
        list[#list + 1] = {name = ent.name, count = c, x = ent.position.x, y = ent.position.y, box = box, quality = ql}
      end
    end
  end
  table.sort(list, function(a, b) return a.count > b.count end)
  while #list > 1000 do table.remove(list) end
  return {count = sum, chests = n, list = list}
end

local function scan_surface(s, name, quality)
  local list, sum, n = {}, 0, 0
  local ents = s.find_entities_filtered{type = {"container", "logistic-container"}, force = game.forces.player}
  for _, ent in ipairs(ents) do
    if ent.valid then
      local inside = false
      pcall(function() inside = ent.logistic_network ~= nil end)
      if not inside then
        local ok, c = pcall(function()
          local inv = ent.get_inventory(defines.inventory.chest)
          return inv and inv.get_item_count{name = name, quality = quality} or 0
        end)
        if ok and type(c) == "number" and c > 0 then
          n = n + 1
          sum = sum + c
          local box = {ent.position.x - 0.5, ent.position.y - 0.5, ent.position.x + 0.5, ent.position.y + 0.5}
          pcall(function()
            local sb = ent.selection_box
            box = {sb.left_top.x, sb.left_top.y, sb.right_bottom.x, sb.right_bottom.y}
          end)
          local ql = "normal"
          pcall(function() ql = ent.quality.name end)
          list[#list + 1] = {name = ent.name, count = c, x = ent.position.x, y = ent.position.y, box = box, quality = ql}
        end
      end
    end
  end
  table.sort(list, function(a, b) return a.count > b.count end)
  while #list > 1000 do table.remove(list) end
  return {count = sum, chests = n, list = list}
end

function M.scan_start(pi, name, quality, opts)
  local d = C.D()
  d.find_job = d.find_job or {}
  local queue = {}
  for _, s in pairs(game.surfaces) do
    local key = C.LOC(s) and C.location_key(s) or nil
    if key then queue[#queue + 1] = key end
  end
  table.sort(queue)
  d.find_job[pi] = {name = name, quality = quality or "normal", queue = queue, total = #queue, done = {}, mach = {},
    opts = opts or {chests = true}, finished = (#queue == 0)}
end

function M.scan_cancel(pi)
  local d = C.D()
  if d.find_job then d.find_job[pi] = nil end
end

function M.scan_job(pi)
  local d = C.D()
  return d.find_job and d.find_job[pi] or nil
end

-- one step: one planet for each running search; returns the players whose window must be refreshed
function M.scan_step()
  local changed = {}
  local jobs = C.D().find_job
  if not jobs or not next(jobs) then return changed end
  for pi, job in pairs(jobs) do
    if not job.finished then
      local key = table.remove(job.queue, 1)
      if key then
        local s = C.surface(key)
        if s and s.valid then
          if job.opts.chests then job.done[key] = scan_surface(s, job.name, job.quality) end
          if job.opts.machines then job.mach[key] = scan_machines(s, job.name, job.quality) end
        end
        changed[#changed + 1] = pi
      end
      if #job.queue == 0 then job.finished = true end
    end
  end
  return changed
end

return M
