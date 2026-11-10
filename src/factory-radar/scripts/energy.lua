-- Factory Radar: power grids. Planet sampling, fast check and the window summary; the rest is in energy_*.lua
local C = require("scripts.core")
local U = require("scripts.energy_log")
local M = U.M
require("scripts.energy_scan")
require("scripts.energy_calc")
require("scripts.energy_platform")
local COUNT_CALLS, COUNT_EVERY, E, HIST, LOG, REDISCOVER, SAMPLE_GAP, open_entry = U.COUNT_CALLS, U.COUNT_EVERY, U.E, U.HIST, U.LOG, U.REDISCOVER, U.SAMPLE_GAP, U.open_entry
local track = U.track
local function capacity_of(...) return U.capacity_of(...) end
local function count_q(...) return U.count_q(...) end
local function fuel_energy(...) return U.fuel_energy(...) end
local function push_long(...) return U.push_long(...) end
local function scan(...) return U.scan(...) end
local function shortage_kind(...) return U.shortage_kind(...) end
local function sum(...) return U.sum(...) end

local function is_stale(pe)
      local stale = not pe.scanned or game.tick - pe.scanned > REDISCOVER
        or (pe.dirty and game.tick - pe.scanned > 10 * 3600)
        or (pe.refs_bad and game.tick - pe.scanned > 3 * 3600)
        or (next(pe.nets) and pe.refs_v ~= 2)
      if not stale then for _, pole in pairs(pe.nets) do if not pole.valid then stale = true break end end end
  return stale
end

local function net_sums(pe)
      local prod, cons = {}, {}
      pe.net_sum, pe.recent = pe.net_sum or {}, pe.recent or {}
      for id, pole in pairs(pe.nets) do
        if pole.valid then
          local fs = pole.electric_network_statistics
          local made = 0
          for name, j in pairs(fs.output_counts) do prod[name] = (prod[name] or 0) + j; made = made + j end
          for name, j in pairs(fs.input_counts) do cons[name] = (cons[name] or 0) + j end
          if pe.net_sum[id] and made > pe.net_sum[id] then pe.recent[id] = game.tick end     -- the net gives power right now
          pe.net_sum[id] = made
        end
      end
  return prod, cons
end

local function acc_totals(pe, short_ids)
      local stored, cap, acc_n, acc_short = 0, 0, 0, 0
      for _, a in ipairs(pe.acc) do
        if a.valid then
          stored = stored + a.energy; cap = cap + a.electric_buffer_size; acc_n = acc_n + 1
          if short_ids then
            local oka, aid = pcall(function() return a.electric_network_id end)
            if oka and short_ids[aid] then acc_short = acc_short + 1 end
          end
        end
      end
  return stored, cap, acc_n, acc_short
end

local function top_counts(s, pe, by_prod, by_cons, heavy)
  pe.cnt, pe.cntq, pe.cnt_t = pe.cnt or {}, pe.cntq or {}, pe.cnt_t or {}
  local cnt = pe.cnt
  -- on a big planet one count per sample and no qualities: each costs tens of milliseconds
  local budget = heavy and 0 or (pe.big and 1 or COUNT_CALLS)
  local function count_top(by, limit, need_q)
    local arr = {}
    for name, w in pairs(by) do arr[#arr + 1] = {name, w} end
    table.sort(arr, function(a, b) return a[2] > b[2] end)
    for i = 1, math.min(limit, #arr) do
      local name = arr[i][1]
      if (cnt[name] == nil or game.tick - (pe.cnt_t[name] or 0) > COUNT_EVERY) and budget > 0 then
        local per, total, calls = count_q(s, name, need_q)
        budget = budget - calls
        cnt[name] = total > 0 and total or false
        pe.cntq[name] = per
        pe.cnt_t[name] = game.tick
      end
    end
  end
  count_top(by_prod, 30, not pe.big)      -- all sources: the maximum depends on them (with quality)
  count_top(by_cons, 5, false)
  return cnt
end

local function source_capacity(pe, by_prod, s)
  local capw = 0
  for name, w in pairs(by_prod) do
    local per = pe.cntq[name]
    local c = per and capacity_of(per, name, s) or 0
    if c > 0 then capw = capw + c else capw = capw + w end
  end
  local made = sum(by_prod)
  if capw < made then capw = made end
  return capw
end

local function nosun_output(by_prod)
  local prod_ns = 0
  for name, w in pairs(by_prod) do
    local pr = prototypes.entity[name]
    if not (pr and pr.type == "solar-panel") then prod_ns = prod_ns + w end
  end
  return prod_ns
end

local function burner_stats(pe, st)
  local bc = pe.bcache
  if not bc or game.tick - bc.tick >= 6000 then
    local fn, fm = 0, 0
    for _, e in ipairs(pe.burners or {}) do
      if e.valid then
        fn = fn + 1
        local okb, stb = pcall(function() return e.status end)
        if okb and stb == st.no_fuel then fm = fm + 1 end
      end
    end
    bc = {tick = game.tick, n = fn, miss = fm, fuel = fuel_energy(pe.burners)}
    pe.bcache = bc
  end
  return bc
end

local function gen_stats(pe, st)
  local g_nofuel, g_nofluid, solar = 0, 0, false
  for _, list in pairs(pe.gens or {}) do
    for _, e in ipairs(list) do
      if e.valid then
        if e.type == "solar-panel" then solar = true end
        local okg, stg = pcall(function() return e.status end)
        if okg then
          if stg == st.no_fuel then g_nofuel = g_nofuel + 1
          elseif stg == st.no_input_fluid then g_nofluid = g_nofluid + 1 end
        end
      end
    end
  end
  return g_nofuel, g_nofluid, solar
end

-- sample a planet (called from sample_due)
function M.sample(only)
  local st = defines.entity_status
  for _, s in pairs(only and {only} or game.surfaces) do
    if C.LOC(s) then
      local key = C.location_key(s)
      local pe = M.planet(key)
      -- after building rescan in 10 minutes, on a big planet too: a new outpost must not wait half an hour
      local stale = is_stale(pe)
      local heavy = stale or pe.scan_job ~= nil          -- this sample already had a building search step: counts wait for the next one
      if heavy then scan(s, pe, not pe.scanned) end
      -- sums (joules since the net was created) by source and consumer names
      local prod, cons = net_sums(pe)
      -- outage check on a few machines of each net
      local short, short_ids = shortage_kind(pe)
      local stored, cap, acc_n, acc_short = acc_totals(pe, short_ids)
      local now = {tick = game.tick, prod = prod, cons = cons}
      local last = pe.last
      if last and now.tick > last.tick then
        local sec = (now.tick - last.tick) / 60
        local by_prod, by_cons = {}, {}
        for name, j in pairs(prod) do local dj = j - ((last.prod or {})[name] or 0); if dj > 0 then by_prod[name] = dj / sec end end
        for name, j in pairs(cons) do local dj = j - ((last.cons or {})[name] or 0); if dj > 0 then by_cons[name] = dj / sec end end
        local acc_out, acc_in = 0, 0
        for name, w in pairs(by_prod) do if prototypes.entity[name] and prototypes.entity[name].type == "accumulator" then acc_out = acc_out + w; by_prod[name] = nil end end
        for name, w in pairs(by_cons) do if prototypes.entity[name] and prototypes.entity[name].type == "accumulator" then acc_in = acc_in + w; by_cons[name] = nil end end
        -- how many top sources and consumers stand on the planet (all qualities together)
        -- counting is expensive on big bases: a name is recounted at most once in 10 minutes
        -- counts are expensive on a big base: a few names per sample at most, each refreshed once in 10 minutes
        local cnt = top_counts(s, pe, by_prod, by_cons, heavy)
        -- the most the sources can give: how many stand times what one gives at best
        -- (current output is often lower, which is what is needed)
        -- with each building's quality and this planet's sun multiplier
        local capw = source_capacity(pe, by_prod, s)
        -- output without sun (at night accumulators only cover what is above it) and a census of fuel and sources
        local prod_ns = nosun_output(by_prod)
        -- reactors and boilers: statuses and fuel stock are read about every 100 seconds (up to 400 of them)
        local bc = burner_stats(pe, st)
        local fuel_n, fuel_miss = bc.n, bc.miss
        local g_nofuel, g_nofluid, solar = gen_stats(pe, st)
        table.insert(pe.hist, {tick = now.tick, cnt = cnt, prod = sum(by_prod), capw = capw, cons = sum(by_cons), acc_in = acc_in, acc_out = acc_out,
          stored = stored, cap = cap, short = short, by_prod = by_prod, by_cons = by_cons, acc_n = acc_n, acc_short = acc_short,
          acc_iso = pe.acc_iso or 0, fuel = bc.fuel, prod_ns = prod_ns, fuel_n = fuel_n, fuel_miss = fuel_miss, g_nofuel = g_nofuel, g_nofluid = g_nofluid,
          solar = solar})
        while #pe.hist > HIST do table.remove(pe.hist, 1) end
        local hh = pe.hist[#pe.hist]
        push_long(pe, now.tick, hh.prod, hh.cons, hh.stored)
        local an = M.analyze({h = pe.hist[#pe.hist], hist = pe.hist, long = pe.long, cur = short, cur_known = true, s = s})
        -- an open outage gets fresh causes (the fast check creates the record itself)
        local open = short and open_entry(key, "red")
        if open then
          if #an.reasons > 0 then open.why = an.reasons end
          open.cons, open.prod = pe.hist[#pe.hist].cons, pe.hist[#pe.hist].prod
        end
        M.warn_track(pe, key, an, short)
      end
      pe.last = now
    end
  end
end

-- spread over time: at most one planet with a stale sample every 2 seconds
-- (not all planets in one tick)
function M.sample_due()
  local best, best_t = nil, nil
  for _, s in pairs(game.surfaces) do
    if C.LOC(s) then
      local pe = M.planet(C.location_key(s))
      local t = pe.last and pe.last.tick or -1
      -- with a net about every 20 s, without one now and then (a new pole marks it "dirty")
      local gap = next(pe.nets) and SAMPLE_GAP or 3600
      if pe.scan_job and not pe.scanned then gap = 62 end      -- the first building search goes a step per second, not once a minute
      if game.tick - t >= gap and (not best_t or t < best_t) then best, best_t = s, t end
    end
  end
  if best then M.sample(best) end
  -- platforms: one per call, the one measured longest ago
  local pbest, pt = nil, nil
  local pd = M.plat_data()
  for _, pl in pairs(game.forces.player.platforms) do
    if pl.valid and pl.surface and pl.surface.valid then
      local t = pd[pl.index] and pd[pl.index].tick or -1
      if game.tick - t >= SAMPLE_GAP and (not pt or t < pt) then pbest, pt = pl, t end
    end
  end
  if pbest then pcall(M.sample_platform, pbest) end
end

-- fast outage check. The load is shared dynamically: a call polls at most FAST_BUDGET machines, planets that waited
-- longest go first; a big planet is checked less often (every 1-5 s), a small one every second. So an outage on any
-- planet is noticed within seconds however many planets and machines there are, and the red entry still waits 10 s
local FAST_BUDGET = 800
function M.fast()
  local due = {}
  for key, pe in pairs(E()) do
    if pe.refs and (next(pe.refs) or pe.cur or pe.pending or open_entry(key, "red") or open_entry(key, "warn")) then
      local n = pe.nrefs or 0
      local gap = math.min(300, 60 * math.max(1, math.ceil(n / 100)))
      local t = pe.fast_t or -1
      if game.tick - t >= gap - 1 then due[#due + 1] = {key = key, pe = pe, t = t, n = n} end
    end
  end
  table.sort(due, function(a, b) if a.t ~= b.t then return a.t < b.t end return a.key < b.key end)
  local budget = FAST_BUDGET
  for i, d in ipairs(due) do
    if i > 1 and budget <= 0 then break end
    budget = budget - d.n
    local pe, key = d.pe, d.key
    pe.fast_t = game.tick
    local s = C.surface(key)
    if s and not s.valid then s = nil end
    local kind, frac = nil, 0
    if next(pe.refs) then
      local ok, k, _, fr = pcall(shortage_kind, pe)
      kind = ok and k or nil
      frac = ok and fr or 0
    end
    track(pe, key, s, kind, frac)
  end
end

-- changes when what the tab shows could have changed (the window is redrawn only then)
function M.sig()
  local parts = {}
  for key, pe in pairs(E()) do if pe.cur then parts[#parts + 1] = key .. ":" .. pe.cur end end
  local npl = 0
  for idx, pe in pairs(M.plat_data()) do
    if pe.cur then parts[#parts + 1] = "pf" .. idx .. ":" .. pe.cur end
    if not pe.empty and pe.h then npl = npl + 1 end
  end
  parts[#parts + 1] = "n" .. npl
  table.sort(parts)
  local log = LOG()
  local top = log[1]
  return table.concat(parts, ",") .. "|" .. #log .. "|" .. (top and (top.start .. ":" .. tostring(top.done) .. ":" .. (top.n or 1)) or "")
end

-- a pole or accumulator was built: rescan the planet on the next sample
function M.on_built(ent)
  if not (ent and ent.valid) then return end
  local t = ent.type
  if t ~= "electric-pole" and t ~= "accumulator" and t ~= "generator" then return end
  if not C.LOC(ent.surface) then return end
  local pe = M.planet(C.location_key(ent.surface))
  pe.dirty = true      -- rescanned on the next sample, at most once in 10 minutes (30 on a big planet)
  if t == "electric-pole" then
    local pos = ent.position
    U.add_pchunk(pe, math.floor(pos.x / 32), math.floor(pos.y / 32))
  end
end

-- summary for the window
function M.rows()
  local rows = {}
  for _, s in pairs(game.surfaces) do
    if C.LOC(s) then
      local key = C.location_key(s)
      local pe = M.planet(key)
      local h = pe.hist[#pe.hist]
      local nets = 0
      for _, pole in pairs(pe.nets) do if pole.valid then nets = nets + 1 end end
      rows[#rows + 1] = {key = key, s = s, h = h, hist = pe.hist, long = pe.long, nets = nets, cur = pe.cur, cur_known = true}
    end
  end
  table.sort(rows, function(a, b) return (a.h and a.h.prod or 0) > (b.h and b.h.prod or 0) end)
  return rows
end

return M
