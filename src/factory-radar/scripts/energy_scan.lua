-- Factory Radar: power grids: net building search, source passports and outage causes
local U = require("scripts.energy_log")
local CHECK_TYPES = U.CHECK_TYPES

-- is the net working? An outage counts only on a net that has power (or just had it):
-- * a source stands (generator, panel...; a lone accumulator is not a source) and the net gave power at least once; or
-- * the net gave power in the last 10 minutes (a source was just removed: that is a blackout).
-- An outpost with no power, with accumulators only or with sources removed long ago is not an outage:
-- nobody expects power there
local RECENT = 10 * 3600

local function any_source(pe, id)
  for _, e in ipairs((pe.gens or {})[id] or {}) do if e.valid then return true end end
  return false
end

-- did the net ever give power? "yes" is remembered, "not yet" is asked again after 10 s
local function ever_produced(pe, id)
  pe.ever = pe.ever or {}
  local v = pe.ever[id]
  if v == true then return true end
  if v and game.tick - v < 600 then return false end
  local pole = pe.nets[id]
  local ok = true
  if pole and pole.valid then
    local okc, has = pcall(function() return next(pole.electric_network_statistics.output_counts) ~= nil end)
    ok = (not okc) or has
  end
  pe.ever[id] = ok and true or game.tick
  return ok
end

local function alive(pe, id)
  local r = pe.recent and pe.recent[id]
  if r and game.tick - r < RECENT then return true end
  return any_source(pe, id) and ever_produced(pe, id)
end

-- "none" (no power), "low" (not enough) or nil, and the set of nets with an outage. Up to REFS machines are polled per net
-- (one idle machine will not show an outage). If most of the net's machines are gone, the planet
-- will be rescanned soon
local function shortage_kind(pe)
  local st = defines.entity_status
  local kind, ids = nil, nil
  local frac = 0
  for id, list in pairs(pe.refs) do
    if type(list) == "userdata" then list = {list} end      -- old version format, until the next scan
    if alive(pe, id) then
      local good, n_none, n_low = 0, 0, 0
      for _, m in ipairs(list) do
        if m.valid then
          good = good + 1
          local ok, status = pcall(function() return m.status end)
          if ok then
            if status == st.no_power then n_none = n_none + 1
            elseif status == st.low_power then n_low = n_low + 1 end
          end
        end
      end
      -- "no power" when at least half of the checked machines lack it; "not enough" when at least a quarter work below full
      -- power (one switched off or cut off machine is not an outage)
      local bad = n_none + n_low
      if good > 0 and bad / good > frac then frac = bad / good end
      if good > 0 and n_none * 2 >= good and n_none > 0 then
        kind = "none"; ids = ids or {}; ids[id] = true
      elseif good > 0 and bad >= 1 and bad * 4 >= good then
        if kind ~= "none" then kind = "low" end
        ids = ids or {}; ids[id] = true
      end
      if good * 2 < #list then pe.refs_bad = true end
    end
  end
  return kind, ids, frac
end

local SOURCE_TYPES = {"generator", "burner-generator", "solar-panel", "fusion-generator", "lightning-attractor",
  "electric-energy-interface"}
local REFS = 6          -- machines per net
local SOURCES = 4       -- remembered sources per net

local BIG_POLES = 5000      -- from this many poles a planet is big: counts are rarer and without qualities
local BIG_ENTITIES = 50000  -- from this many buildings a planet is big even with few poles (a conveyor base)
local NETS_CAP = 150        -- nets tracked on a planet (on such a base the rest are small pieces)
local STEP_UNITS = 2500     -- work of one pole search step (a chunk costs CHUNK_COST, a pole 1)
local CHUNK_COST = 5
local FULL_EVERY = 720 * 3600   -- every 12 hours all chunks of a planet are viewed again, between them only chunks with poles

local function chunk_key(x, y) return (x + 32768) * 65536 + (y + 32768) end

-- remember a chunk with a pole (also called when a pole is built, so a far outpost is not lost until the next full pass)
local function add_pchunk(pe, x, y)
  local k = chunk_key(x, y)
  pe.pch_set = pe.pch_set or {}
  pe.pch = pe.pch or {}
  if not pe.pch_set[k] then pe.pch_set[k] = true; pe.pch[#pe.pch + 1] = x; pe.pch[#pe.pch + 1] = y end
  local job = pe.scan_job
  if job and job.full and job.newp then job.newp[#job.newp + 1] = x; job.newp[#job.newp + 1] = y end
end
U.add_pchunk = add_pchunk

local function all_chunks(s)
  local all = {}
  for ch in s.get_chunks() do all[#all + 1] = ch.x; all[#all + 1] = ch.y end
  return all
end

local function scan_poles(s, pe, job, force)
  if not job.chunks then
    local full = not pe.pch or not pe.pch_t or game.tick - pe.pch_t > FULL_EVERY
    job.full, job.newp = full, {}
    job.chunks = full and all_chunks(s) or pe.pch
    job.ci, job.poles, job.nn = 1, 0, 0
  end
  local units, ch = pe.scanned and STEP_UNITS or STEP_UNITS * 3, job.chunks      -- the first scan of a planet uses a bigger step so data appears quickly
  while units > 0 and job.ci <= #ch do
    local x, y = ch[job.ci], ch[job.ci + 1]
    job.ci = job.ci + 2
    units = units - CHUNK_COST
    local okc, list = pcall(s.find_entities_filtered, {area = {{x * 32, y * 32}, {x * 32 + 32, y * 32 + 32}}, type = "electric-pole", force = force})
    if okc and #list > 0 then
      if job.full then job.newp[#job.newp + 1] = x; job.newp[#job.newp + 1] = y end
      for _, pole in ipairs(list) do
        units = units - 1
        job.poles = job.poles + 1
        if job.nn < NETS_CAP then
          local id = pole.electric_network_id
          if id and not job.nets[id] then job.nets[id] = pole; job.nn = job.nn + 1 end
        end
      end
    end
  end
  if job.ci <= #ch then return true end    -- the rest of the chunks go to the next sample
  job.big = job.poles >= BIG_POLES or job.nn >= NETS_CAP
  -- a base can be huge and have no poles: then the planet is big too
  if not job.big and (job.full or not pe.big) then
    local okt, total = pcall(s.count_entities_filtered, {force = force})
    if okt and type(total) == "number" and total >= BIG_ENTITIES then job.big = true end
  end
  if job.full then
    pe.pch, pe.pch_set, pe.pch_t = {}, {}, game.tick
    local np = job.newp
    job.newp = nil
    for i = 1, #np, 2 do add_pchunk(pe, np[i], np[i + 1]) end
  end
  job.chunks, job.newp = nil, nil
end

local function scan_gens(s, job, force)
  -- sources of each net
  local okp, srcs = pcall(s.find_entities_filtered, {type = SOURCE_TYPES, force = force, limit = 5000})
  if okp then
    for _, e in pairs(srcs) do
      local ok, id = pcall(function() return e.electric_network_id end)
      if ok and id then
        local list = job.gens[id] or {}
        job.gens[id] = list
        if #list < SOURCES then list[#list + 1] = e end
      end
    end
  end
end

local function scan_refs(s, job, force)
  -- machines to poll, evenly over the list (it is ordered by place)
  local all = {}
  for _, m in pairs(s.find_entities_filtered{type = CHECK_TYPES, force = force, limit = 600}) do
    local ok, id = pcall(function() return m.electric_network_id end)
    if ok and id and job.nets[id] then all[id] = all[id] or {}; table.insert(all[id], m) end
  end
  for id, list in pairs(all) do
    local pick = {}
    local n = math.min(job.nn > 50 and 3 or REFS, #list)
    for k = 1, n do pick[#pick + 1] = list[math.floor((k - 1) * #list / n) + 1] end
    job.refs[id] = pick
  end
  -- nets whose machines were not among the first found: take machines near their pole
  for id, pole in pairs(job.nets) do
    if not job.refs[id] and pole.valid then
      local okn, near = pcall(s.find_entities_filtered, {position = pole.position, radius = 20, type = CHECK_TYPES, force = force, limit = 12})
      if okn then
        local pick = {}
        for _, m in ipairs(near) do
          local okm, mid = pcall(function() return m.electric_network_id end)
          if okm and mid == id then pick[#pick + 1] = m; if #pick >= (job.nn > 50 and 3 or REFS) then break end end
        end
        if #pick > 0 then job.refs[id] = pick end
      end
    end
  end
end

local function scan_finish(s, pe, job, force)
  -- reactors and boilers: which ran out of fuel
  local burners = {}
  local okf, fl = pcall(s.find_entities_filtered, {type = {"reactor", "boiler", "fusion-reactor", "burner-generator"}, force = force, limit = 400})
  if not okf then okf, fl = pcall(s.find_entities_filtered, {type = {"reactor", "boiler", "burner-generator"}, force = force, limit = 400}) end
  if okf then for _, e in pairs(fl) do burners[#burners + 1] = e end end
  -- accumulators in a net where nobody consumes (or outside a net): nothing to power. Info, not an outage
  local iso = 0
  local has_cons = {}
  for _, a in ipairs(job.acc) do
    local isolated = true
    local oka, aid = pcall(function() return a.electric_network_id end)
    if oka and aid then
      if has_cons[aid] == nil then
        has_cons[aid] = false
        local pole = job.nets[aid]
        if pole and pole.valid then
          local okc, has = pcall(function()
            for name in pairs(pole.electric_network_statistics.input_counts) do
              local pr = prototypes.entity[name]
              if not (pr and pr.type == "accumulator") then return true end
            end
            return false
          end)
          has_cons[aid] = okc and has or false
        end
      end
      if has_cons[aid] then isolated = false end
    end
    if isolated then iso = iso + 1 end
  end
  local nr = 0
  for _, l in pairs(job.refs) do nr = nr + #l end
  pe.nrefs = nr
  pe.nets, pe.refs, pe.acc, pe.gens, pe.burners, pe.acc_iso = job.nets, job.refs, job.acc, job.gens, burners, iso
  pe.ever, pe.recent, pe.net_sum = {}, {}, {}
  pe.refs_v = 2
  pe.scanned = game.tick
  pe.big = job.big or nil
  pe.dirty, pe.refs_bad = nil, nil
  pe.scan_job = nil
end

local function scan(s, pe, sync)
  local job = pe.scan_job
  if not job then
    job = {stage = 1, nets = {}, acc = {}, gens = {}, refs = {}}
    pe.scan_job = job
  end
  local force = game.forces.player
  repeat
    local st = job.stage
    if st == 1 then
      if scan_poles(s, pe, job, force) then return end
    elseif st == 2 then
      for _, a in pairs(s.find_entities_filtered{type = "accumulator", force = force, limit = 3000}) do job.acc[#job.acc + 1] = a end
    elseif st == 3 then
      scan_gens(s, job, force)
    elseif st == 4 then
      scan_refs(s, job, force)
    else
      scan_finish(s, pe, job, force)
      return
    end
    job.stage = st + 1
  until not sync or job.big
end

-- "space" sun where the platform is now: a location has its own value (in percent), in flight between the route's start and end values
-- by the part of the way covered. nil if it could not be found
local function plat_solar(pl)
  local function sip(name)
    local ok, v = pcall(function() return prototypes.space_location[name].solar_power_in_space end)
    return ok and type(v) == "number" and v or nil
  end
  local f = nil
  pcall(function()
    local conn = pl.space_connection
    if pl.space_location then
      f = sip(pl.space_location.name)
    elseif conn then
      local a, b = sip(conn.from.name), sip(conn.to.name)
      if a and b then f = a + (b - a) * math.max(0, math.min(1, pl.distance or 0)) end
    end
  end)
  return f and f / 100 or nil
end

-- sun on a surface: every solar panel has its own surface property ("solar-power" by default: for a planet it is
-- "sun in the atmosphere", for a platform "sun in space" where it flies now), power is divided by the property's default value.
-- Plus the common surface multiplier
local SPROP = {}
local function prop_default(name)
  local d = SPROP[name]
  if d == nil then
    d = false
    pcall(function()
      local v = prototypes.surface_property[name].default_value
      if type(v) == "number" and v > 0 then d = v end
    end)
    SPROP[name] = d
  end
  return d
end
local function solar_factor(s, prop)
  prop = prop or "solar-power"
  local f = 1
  pcall(function() f = (s.solar_power_multiplier or 1) end)
  pcall(function()
    local v = s.get_property(prop)
    local d = prop_default(prop)
    if type(v) == "number" and d then f = f * v / d end
  end)
  return f
end

local function sum(t) local n = 0; for _, v in pairs(t) do n = n + v end; return n end

-- "passport" of a building type: how much it gives and spends at best, with quality. Read from prototypes once
-- and remembered (not world state, recomputed the same for everyone on every load)
local PASS = {}
local function pass(name, quality)
  local q = quality or "normal"
  local k = name .. "|" .. q
  local p = PASS[k]
  if p == nil then
    p = false
    local pr = prototypes.entity[name]
    if pr then
      local okp, mp = pcall(function() return pr.get_max_energy_production(q) end)
      local okc, mc = pcall(function() return pr.get_max_energy_usage(q) end)
      p = {type = pr.type, maxp = (okp and type(mp) == "number") and mp * 60 or 0, maxc = (okc and type(mc) == "number") and mc * 60 or 0}
      if p.type == "solar-panel" then pcall(function() p.prop = pr.solar_panel_solar_coefficient_property.name end) end
      pcall(function()
        local dr = pr.electric_energy_source_prototype.drain
        if type(dr) == "number" then p.drain = dr * 60 end
      end)
    end
    PASS[k] = p
  end
  return p or nil
end

local QUALS = nil
local function quality_names()
  if not QUALS then
    QUALS = {}
    pcall(function()
      for qn, q in pairs(prototypes.quality) do
        local hidden = false
        pcall(function() hidden = q.hidden end)
        if not hidden then QUALS[#QUALS + 1] = qn end
      end
    end)
    table.sort(QUALS)
    if #QUALS == 0 then QUALS = {"normal"} end
  end
  return QUALS
end

-- how many such buildings per quality: {quality = n}, the total, and how many game calls it took.
-- Counting costs time proportional to the number of buildings, so: one total count first, then only the qualities above normal
-- that are already unlocked (normal ones are what remains). need_q = false when only the total is needed
local function count_q(s, name, need_q)
  local force = game.forces.player
  local calls = 1
  local ok, total = pcall(s.count_entities_filtered, {name = name, force = force})
  if not ok or type(total) ~= "number" or total <= 0 then return {}, 0, calls end
  local per = {normal = total}
  if need_q then
    for _, qn in ipairs(quality_names()) do
      local open = false
      if qn ~= "normal" then
        local oku, u = pcall(force.is_quality_unlocked, qn)
        open = oku and u or false
      end
      if open then
        calls = calls + 1
        local okq, n = pcall(s.count_entities_filtered, {name = name, force = force, quality = qn})
        if okq and type(n) == "number" and n > 0 then per[qn] = n; per.normal = per.normal - n end
      end
    end
    if per.normal <= 0 then per.normal = nil end
  end
  return per, total, calls
end

-- maximum of sources of this name by quality; solar panels are multiplied by the surface multiplier
local function capacity_of(per, name, s)
  local c = 0
  for qn, n in pairs(per) do
    local p = pass(name, qn)
    if p and p.maxp > 0 then
      local w = n * p.maxp
      if p.type == "solar-panel" then w = w * solar_factor(s, p.prop) end
      c = c + w
    end
  end
  return c
end

-- how much energy is in the fuel of all burners (reactors, boilers): stock in the inventory and what is burning. Works with any fuel, modded too
local function fuel_energy(list)
  local total = 0
  for _, e in ipairs(list or {}) do
    if e.valid then
      pcall(function()
        local inv = e.get_fuel_inventory()
        if inv then
          for _, c in ipairs(inv.get_contents()) do
            local pr = prototypes.item[c.name]
            if pr and pr.fuel_value then total = total + pr.fuel_value * c.count end
          end
        end
        local b = e.burner
        if b then total = total + (b.remaining_burning_fuel or 0) end
      end)
    end
  end
  return total
end
U.shortage_kind = shortage_kind
U.scan = scan
U.capacity_of = capacity_of
U.sum = sum
U.fuel_energy = fuel_energy
U.count_q = count_q
U.pass = pass
U.SOURCE_TYPES = SOURCE_TYPES
U.solar_factor = solar_factor
U.plat_solar = plat_solar
