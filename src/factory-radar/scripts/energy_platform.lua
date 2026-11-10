-- Factory Radar: power grids: space platform sampling
local C = require("scripts.core")
local U = require("scripts.energy_log")
local M = U.M
local HIST, LOG, LOG_MAX, MERGE_GAP, SOURCE_TYPES, close_entry, open_entry = U.HIST, U.LOG, U.LOG_MAX, U.MERGE_GAP, U.SOURCE_TYPES, U.close_entry, U.open_entry
local function fuel_energy(...) return U.fuel_energy(...) end
local function pass(...) return U.pass(...) end
local function plat_solar(...) return U.plat_solar(...) end
local function push_long(...) return U.push_long(...) end
local function slope(...) return U.slope(...) end
local function solar_factor(...) return U.solar_factor(...) end

---------------------------------------------------------------- space platforms
-- A platform has its own small net: solar panels, accumulators, machines. Measured about every 20 s (two bad checks in a row make
-- a journal entry). Red: machines lack power or have none, accumulators are empty and sources do not keep up, no sources,
-- working machines may draw more than the sources give. Yellow: charge running out, consumption near the limit
local PCONS = {"assembling-machine", "furnace", "lab", "inserter", "roboport", "radar", "lamp", "beacon", "mining-drill",
  "electric-turret", "asteroid-collector"}
local PCHECK = {["assembling-machine"] = true, furnace = true, lab = true, ["mining-drill"] = true}

function M.plat_data()
  local d = C.D()
  d.energy_plat = d.energy_plat or {}
  return d.energy_plat
end

local function plat_track(pe, key, kind, why, h)
  local now = game.tick
  local open = open_entry(key, "red")
  if kind then
    pe.ok = 0
    pe.bad = (pe.bad or 0) + 1
    pe.bad_since = pe.bad_since or now
    if open then
      local dt = math.min(now - (open.prev_t or now), 3000)
      if (open.prev_k or kind) == "none" then open.t_none = (open.t_none or 0) + dt else open.t_low = (open.t_low or 0) + dt end
      open.prev_t, open.prev_k = now, kind
      open.last, open.kind, open.why, open.plat = now, kind, why, pe.name
      open.cons, open.prod = h.cons, h.prod
      open.share = math.max(open.share or 0, h.share or 0)
    elseif pe.bad >= ((kind == "low") and 3 or 2) then
      local log = LOG()
      local again = nil
      for i, e in ipairs(log) do
        if e.key == key and e.done and (e.level or "red") == "red" and now - (e.last or 0) < MERGE_GAP then again = i; break end
      end
      if again then
        local e = table.remove(log, again)
        e.done, e.n, e.run, e.last = false, (e.n or 1) + 1, pe.bad_since, now
        e.prev_t, e.prev_k, e.kind, e.why, e.plat = nil, nil, kind, why, pe.name
        table.insert(log, 1, e)
      else
        table.insert(log, 1, {key = key, plat = pe.name, level = "red", start = pe.bad_since, run = pe.bad_since, last = now,
          kind = kind, why = why, n = 1, total = 0, done = false, t_none = 0, t_low = 0, share = h.share, cons = h.cons, prod = h.prod})
        while #log > LOG_MAX do table.remove(log) end
      end
      if now - (pe.warned or -1e9) > 30 * 3600 then
        pe.warned = now
        C.journal({"tr-msg.power-plat-" .. kind, pe.name})
      end
    end
  else
    pe.bad, pe.bad_since = 0, nil
    if open then
      pe.ok = (pe.ok or 0) + 1
      if pe.ok >= 2 then close_entry(open); pe.ok = 0 end
    end
  end
end

local function source_power(s, pl, srcs, pe)
  local sfac = {}
  local function sf(prop) prop = prop or "solar-power"; if not sfac[prop] then sfac[prop] = solar_factor(s, prop) end; return sfac[prop] end
  local maxp = 0
  local space_sun = plat_solar(pl)
  pe.sun = space_sun
  local non_solar = 0
  for _, e in ipairs(srcs) do
    if e.valid then
      local q = "normal"
      pcall(function() q = e.quality.name end)
      local p = pass(e.name, q)
      if p and p.maxp > 0 then
        local k = 1
        if p.type == "solar-panel" then
          if p.prop and p.prop ~= "solar-power" then k = sf(p.prop) else k = space_sun or sf(p.prop) end
        end
        maxp = maxp + p.maxp * k
        if p.type ~= "solar-panel" then non_solar = non_solar + 1 end
      end
    end
  end
  return maxp, non_solar
end

local function consumption_est(cons, st)
  local maxc, use = 0, 0
  local good, n_none, n_low = 0, 0, 0
  for _, e in ipairs(cons) do
    if e.valid then
      local q = "normal"
      pcall(function() q = e.quality.name end)
      local p = pass(e.name, q)
      local okst, status = pcall(function() return e.status end)
      local active = (not okst) or status == nil or status == st.working or status == st.low_power or status == st.no_power or status == st.normal
      if p then
        if active then maxc = maxc + p.maxc; use = use + p.maxc else use = use + (p.drain or p.maxc / 30) end
      end
      if PCHECK[e.type] and okst then
        good = good + 1
        if status == st.no_power then n_none = n_none + 1 elseif status == st.low_power then n_low = n_low + 1 end
      end
    end
  end
  local kind_hint = (good > 0 and (n_none + n_low) >= 1 and (n_none + n_low) * 4 >= good) or false
  return maxc, use, good, n_none, n_low, kind_hint
end

local function burner_miss(burners, st)
  local fuel_n, fuel_miss = 0, 0
  for _, e in ipairs(burners) do
    if e.valid then
      fuel_n = fuel_n + 1
      local okb, stb = pcall(function() return e.status end)
      if okb and stb == st.no_fuel then fuel_miss = fuel_miss + 1 end
    end
  end
  return fuel_n, fuel_miss
end

local function plat_state(c)
  local pe, srcs, cons, stored, cap, maxp, use = c.pe, c.srcs, c.cons, c.stored, c.cap, c.maxp, c.use
  local fill, ssl, fuel_n, fuel_miss, good, n_none, n_low = c.fill, c.ssl, c.fuel_n, c.fuel_miss, c.good, c.n_none, c.n_low
  local kind = nil
  local share = good > 0 and (n_none + n_low) / good or 0
  if good > 0 and n_none * 2 >= good and n_none > 0 then kind = "none"
  elseif good > 0 and (n_none + n_low) >= 1 and (n_none + n_low) * 4 >= good then kind = "low" end
  local reasons, score, notes = {}, 0, {}
  local function add(line, sc) reasons[#reasons + 1] = line; if sc > score then score = sc end end
  local pct = cap > 0 and math.floor(stored / cap * 100) or nil
  if kind == "none" then add({"tr-en.plat-why-none"}, 3) elseif kind == "low" then add({"tr-en.plat-why-low"}, 2) end
  local log_kind = kind
  local is_empty = false
  if cap > 0 and stored / cap < 0.02 and (maxp <= 0 or use >= maxp * 0.98) then
    add({"tr-en.plat-why-empty", pct}, 2)
    log_kind = log_kind or "empty"
    is_empty = true
  end
  if #srcs == 0 and #cons > 0 and use > 0 then add({"tr-en.plat-why-nosrc"}, 2) end
  if fuel_miss > 0 and (kind or use > maxp * 0.98) and fuel_miss * 2 >= fuel_n then
    add({"tr-en.why-nofuel", fuel_miss, fuel_n}, kind and 2 or 1)
  end
  if cap > 0 and stored / cap < 0.15 and use > maxp and not is_empty then add({"tr-en.plat-why-acc-low", pct}, 1) end
  if maxp > 0 and use >= maxp * 0.9 and score < 2 and not (fill and fill >= 0.995) then add({"tr-en.plat-why-limit", M.power(use), M.power(maxp)}, 1) end
  if ssl and ssl < 0 and stored > 0 and #pe.hist >= 8 and score < 2 then
    local eta = stored / -ssl
    if eta < 600 then add({"tr-en.why-acc-drain", math.max(1, math.floor(eta / 60 + 0.5)), M.power(-ssl)}, 1) end
  end
  pcall(M.series, pe.hist, pe.long, maxp, add, notes)
  return reasons, score, notes, log_kind, share
end

function M.sample_platform(pl)
  local s = pl.surface
  if not (s and s.valid) then return end
  local pd = M.plat_data()
  local pe = pd[pl.index]
  if not pe then pe = {}; pd[pl.index] = pe end
  pe.hist = pe.hist or {}
  local key = "pf" .. pl.index
  pe.name, pe.tick = pl.name, game.tick
  local force = game.forces.player
  local function find(f) local ok, r = pcall(s.find_entities_filtered, f); return ok and r or {} end
  -- poles are not needed on a platform: all electric buildings are in one net, and a net with no pole has no statistics
  local accs = find{type = "accumulator", force = force}
  local srcs = find{type = SOURCE_TYPES, force = force}
  local cons = find{type = PCONS, force = force}
  local burners = find{type = {"reactor", "boiler", "fusion-reactor", "burner-generator"}, force = force}
  if #accs == 0 and #srcs == 0 and #cons == 0 then
    pe.empty, pe.h, pe.reasons, pe.score, pe.cur, pe.notes = true, nil, nil, 0, nil, nil
    plat_track(pe, key, nil, nil, {})
    return
  end
  pe.empty = nil
  local now = game.tick
  local st = defines.entity_status
  -- charge
  local stored, cap = 0, 0
  for _, a in ipairs(accs) do
    if a.valid then stored = stored + a.energy; cap = cap + a.electric_buffer_size end
  end
  -- what the sources can give: each has its own quality, solar panels get the "space" sun where the platform is now
  local maxp, non_solar = source_power(s, pl, srcs, pe)
  -- consumption is estimated from machine states: a working one draws the maximum, an idle one only its idle draw
  local maxc, use, good, n_none, n_low, kind_hint = consumption_est(cons, st)
  -- fuel of reactors and boilers, if any
  local fuel_n, fuel_miss = burner_miss(burners, st)
  -- history: an hour in 20 second steps, a day in 5 minute steps. Output is estimated from the charge: what is spent plus what goes into accumulators
  local entry = {tick = now, cons = use, stored = stored, cap = cap, fuel = fuel_energy(burners), prod = use}
  table.insert(pe.hist, entry)
  while #pe.hist > HIST do table.remove(pe.hist, 1) end
  local ssl = slope(pe.hist, "stored", 12)
  -- an estimate by machine maxima is an upper bound (the game counts "possible maximum" while they usually run lower). Refine:
  -- * only solar panels and accumulators charge or discharge: then consumption = panel output minus charge per second;
  -- * machines do not complain of a shortage: consumption cannot exceed what the sources give
  local fill = cap > 0 and stored / cap or nil
  if ssl and fill and fill > 0.005 and fill < 0.995 and maxp > 0 and non_solar == 0 then
    use = math.max(0, maxp - ssl)
  elseif maxp > 0 and use > maxp and not kind_hint then
    use = maxp
  end
  local prod_w = use
  if ssl and cap > 0 then prod_w = math.max(0, math.min(maxp > 0 and maxp or math.huge, use + ssl)) end
  entry.cons, entry.prod = use, prod_w
  push_long(pe, now, prod_w, use, stored)
  -- state: red only on facts, yellow on stock and trend
  local reasons, score, notes, log_kind, share = plat_state({pe = pe, srcs = srcs, cons = cons, stored = stored, cap = cap,
    maxp = maxp, use = use, fill = fill, ssl = ssl, fuel_n = fuel_n, fuel_miss = fuel_miss, good = good, n_none = n_none, n_low = n_low})
  pe.h = {prod = prod_w, cons = use, capw = maxp, maxc = maxc, stored = stored, cap = cap, acc_n = #accs,
    acc_in = (ssl and ssl > 0) and ssl or 0, acc_out = (ssl and ssl < 0) and -ssl or 0, src_n = #srcs, short = log_kind, share = share, est = true}
  pe.reasons, pe.score, pe.cur, pe.notes = reasons, score, log_kind, notes
  plat_track(pe, key, log_kind, reasons, pe.h)
end

-- platforms for the window: worst first
function M.plat_rows()
  local rows = {}
  local pd = M.plat_data()
  for _, pl in pairs(game.forces.player.platforms) do
    if pl.valid then
      local pe = pd[pl.index]
      if pe and not pe.empty and pe.h then
        rows[#rows + 1] = {name = pl.name, h = pe.h, reasons = pe.reasons or {}, notes = pe.notes or {}, score = pe.score or 0, kind = pe.cur, cur = pe.cur, cur_known = true}
      end
    end
  end
  table.sort(rows, function(a, b)
    if a.score ~= b.score then return a.score > b.score end
    return a.name < b.name
  end)
  return rows
end
