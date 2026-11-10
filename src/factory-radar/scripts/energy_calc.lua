-- Factory Radar: power grids: sample series, forecast and cause analysis
local U = require("scripts.energy_log")
local M = U.M
local LONG = U.LONG

-- slope of a series (units per second) over the last n samples (linear regression) and the mean; nil if there are few samples
local function slope(hist, key, n)
  local m = math.min(#hist, n)
  if m < 6 then return nil end
  local t0 = hist[#hist - m + 1].tick
  local sx, sy, sxx, sxy = 0, 0, 0, 0
  for i = #hist - m + 1, #hist do
    local x = (hist[i].tick - t0) / 60
    local y = hist[i][key] or 0
    sx = sx + x; sy = sy + y; sxx = sxx + x * x; sxy = sxy + x * y
  end
  local den = m * sxx - sx * sx
  if den == 0 then return nil end
  return (m * sxy - sx * sy) / den, sy / m
end

-- what a long series says: consumption grows or falls (over 30 minutes), when it reaches the limit, whether fuel is running out
-- (stock only falls for 10 minutes in a row, no resupply), how consumption changed over the last hours. add(line, score) is a cause,
-- notes are info that does not affect status. cap_eff is the sources' limit power (0 = unknown)
function M.series(hist, long, cap_eff, add, notes)
  local n = #hist
  if n >= 60 then
    local sl, mean = slope(hist, "cons", 90)
    if sl and mean > 1e5 then
      local rel = sl * 3600 / mean
      local now = hist[n].cons
      if rel >= 0.15 then
        local eta = (cap_eff > now and sl > 0) and (cap_eff - now) / sl / 60 or nil
        if eta and eta < 180 then add({"tr-en.why-trend-cap", math.floor(rel * 100 + 0.5), math.max(1, math.floor(eta + 0.5))}, 1)
        else notes[#notes + 1] = {"tr-en.note-trend-up", math.floor(rel * 100 + 0.5)} end
      elseif rel <= -0.15 then
        notes[#notes + 1] = {"tr-en.note-trend-down", math.floor(-rel * 100 + 0.5)}
      end
    end
  end
  if long and #long >= 36 then
    local function avg(a, b) local t = 0; for i = a, b do t = t + long[i].cons end; return t / (b - a + 1) end
    local recent, older = avg(#long - 11, #long), avg(#long - 35, #long - 24)
    if older > 1e5 and math.abs(recent / older - 1) >= 0.3 then
      notes[#notes + 1] = {"tr-en.note-trend-long", math.floor((recent / older - 1) * 100 + 0.5)}
    end
  end
  if n >= 30 and (hist[n].fuel or 0) > 0 then
    local first = hist[n - 29]
    local f0, f1 = first.fuel or 0, hist[n].fuel
    local rises = false
    for i = n - 28, n do
      if (hist[i].fuel or 0) > (hist[i - 1].fuel or 0) * 1.01 + 1e3 then rises = true; break end
    end
    if not rises and f0 > f1 and hist[n].tick > first.tick then
      local rate = (f0 - f1) / ((hist[n].tick - first.tick) / 60)
      if rate > 1e4 then
        local eta = f1 / rate / 60
        if eta < 15 then add({"tr-en.why-fuel-low", math.max(1, math.floor(eta + 0.5))}, 1) end
      end
    end
  end
end

-- five minute averages over a day: consumption and charge
local function push_long(pe, tick, prod, cons, stored)
  pe.long = pe.long or {}
  local a5 = pe.a5 or {n = 0, prod = 0, cons = 0, stored = 0}
  a5.n = a5.n + 1; a5.prod = a5.prod + prod; a5.cons = a5.cons + cons; a5.stored = a5.stored + stored
  if a5.n >= 15 then
    table.insert(pe.long, {tick = tick, prod = a5.prod / a5.n, cons = a5.cons / a5.n, stored = a5.stored / a5.n})
    while #pe.long > LONG do table.remove(pe.long, 1) end
    a5 = nil
  end
  pe.a5 = a5
end

-- does the planet live on lightning (lightning rods among sources in the last hour)?
function M.storm(hist)
  for _, smp in ipairs(hist or {}) do
    for name in pairs(smp.by_prod or {}) do
      local pr = prototypes.entity[name]
      if pr and pr.type == "lightning-attractor" then return true end
    end
  end
  return false
end

local function no_power_causes(c)
  local h, sh, add, out, storm, cap, acc_ok, no_acc = c.h, c.sh, c.add, c.out, c.storm, c.cap, c.acc_ok, c.no_acc
  local nostore = false
  local short_of_prod = h.prod <= 0 or h.prod < (h.cons or 0) * 0.98
  -- fuel: reactors and boilers ran out, generators have no fuel or steam
  if (h.fuel_miss or 0) > 0 and (sh or short_of_prod) and (sh or h.fuel_miss * 2 >= (h.fuel_n or h.fuel_miss)) then
    add({"tr-en.why-nofuel", h.fuel_miss, h.fuel_n or h.fuel_miss}, sh and 2 or 1)
  end
  if (h.g_nofuel or 0) > 0 and (sh or short_of_prod) then add({"tr-en.why-gen-nofuel", h.g_nofuel}, sh and 2 or 1) end
  if (h.g_nofluid or 0) > 0 and (sh or short_of_prod) and (h.fuel_miss or 0) == 0 then
    add({"tr-en.why-gen-nofluid", h.g_nofluid}, sh and 2 or 1)
  end
  local fuel_known = #out.reasons > 0
  if h.prod <= 0 and (h.cons > 0 or sh) then
    if storm and acc_ok then
      -- between storms: fine
    elseif storm then add({"tr-en.why-noprod-storm"}, 2)
    elseif no_acc then add({"tr-en.why-nostore"}, 2); nostore = true       -- produces nothing and stores nothing
    elseif h.cons > 0 then add({"tr-en.why-noprod", M.power(h.cons)}, 2)
    else add({"tr-en.why-noprod0"}, 2) end
  elseif not storm and cap > 0 and h.cons >= cap * 0.92 then
    add({"tr-en.why-demand", M.power(h.cons), M.power(cap)}, 1)
  end
  if (h.cap or 0) > 0 and h.stored / h.cap < 0.15 and (storm and (h.cons or 0) > 1e4 or h.cons > cap * 0.8) then
    if storm then add({"tr-en.why-acc-storm", math.floor(h.stored / h.cap * 100)}, 1)
    else add({"tr-en.why-acc", math.floor(h.stored / h.cap * 100)}, 1) end
  end
  c.fuel_known, c.nostore = fuel_known, nostore
end

local function night_forecast(c)
  local r, h, storm, add = c.r, c.h, c.storm, c.add
  local forecast = false
  if h.solar and not storm and (h.acc_n or 0) > 0 and r.s and r.s.valid then
    local okd, d = pcall(function()
      local sf = r.s
      if sf.freeze_daytime then return nil end
      return {t = sf.daytime, tpd = sf.ticks_per_day, dusk = sf.dusk, evening = sf.evening, morning = sf.morning, dawn = sf.dawn}
    end)
    if okd and d and d.tpd and d.tpd > 0 and d.dusk and d.dawn then
      forecast = true
      local load = math.max(0, (h.cons or 0) - (h.prod_ns or 0))        -- this is what accumulators must give at night
      if load > 1e4 then
        local t = d.t % 1
        local dark_now = t >= d.dusk and t < d.dawn
        local night_ticks
        if dark_now then
          if t < d.morning then night_ticks = (d.morning - t) * d.tpd + (d.dawn - d.morning) * d.tpd / 2
          else night_ticks = (d.dawn - t) * d.tpd / 2 end
        else
          night_ticks = ((d.evening - d.dusk) / 2 + (d.morning - d.evening) + (d.dawn - d.morning) / 2) * d.tpd
        end
        local need = load * night_ticks / 60                           -- J
        local have = dark_now and h.stored or h.cap
        if need > 0 and have < need then
          add({dark_now and "tr-en.why-night-short" or "tr-en.why-night-cap", math.floor(have / load / 60 + 0.5), math.floor(night_ticks / 3600 + 0.5)}, 1)
        end
      end
    end
  end
  c.forecast = forecast
end

local function drain_cause(c)
  local r, h, storm, add, forecast = c.r, c.h, c.storm, c.add, c.forecast
  local drain = h.acc_out or 0
  local ssl = slope(r.hist or {}, "stored", 30)
  if ssl and #(r.hist or {}) >= 8 then drain = math.max(0, -ssl) end
  if not forecast and not (h.solar and not storm) and drain > 1e4 and (h.stored or 0) > 0 and h.prod < h.cons then
    local eta = h.stored / drain
    if eta < 600 then add({"tr-en.why-acc-drain", math.max(1, math.floor(eta / 60 + 0.5)), M.power(drain)}, 1) end
  end
end

local function change_causes(c)
  local r, h, storm, add, fuel_known, acc_ok, no_acc, nostore, forecast = c.r, c.h, c.storm, c.add, c.fuel_known, c.acc_ok, c.no_acc, c.nostore, c.forecast
  local hist = r.hist or {}
  local n, sc, sp = 0, 0, 0
  for i = math.max(1, #hist - 10), #hist - 1 do sc = sc + hist[i].cons; sp = sp + hist[i].prod; n = n + 1 end
  if n >= 3 then
    local ac, ap = sc / n, sp / n
    if ac > 0 and h.cons > ac * 1.3 and h.cons - ac > 5e6 then
      local best, bn = 0, nil
      for name, w in pairs(h.by_cons or {}) do
        local before = 0
        for i = math.max(1, #hist - 10), #hist - 1 do before = before + ((hist[i].by_cons or {})[name] or 0) end
        local grow = w - before / n
        if grow > best then best, bn = grow, name end
      end
      if bn then add({"tr-en.why-jump", math.floor((h.cons / ac - 1) * 100), "[entity=" .. bn .. "]", M.power(best)}, 1)
      else add({"tr-en.why-jump-plain", math.floor((h.cons / ac - 1) * 100)}, 1) end
    end
    if not storm and not fuel_known and ap > 0 and h.prod < ap * 0.7 and ap - h.prod > 5e6 then
      local worst, wn = 0, nil
      for name, w in pairs(hist[#hist - 1].by_prod or {}) do
        local drop = w - ((h.by_prod or {})[name] or 0)
        if drop > worst then worst, wn = drop, name end
      end
      local pr = wn and prototypes.entity[wn]
      local pct = math.floor((1 - h.prod / ap) * 100)
      if pr and pr.type == "lightning-attractor" then
        if not acc_ok then add({"tr-en.why-drop-storm", pct, "[entity=" .. wn .. "]"}, 1) end   -- lull between storms
      elseif pr and pr.type == "solar-panel" then
        -- night is a cause only if something holds the net; without accumulators it is a fault
        if no_acc then
          if not nostore then add({"tr-en.why-solar-nostore", pct, "[entity=" .. wn .. "]"}, 2) end
        elseif not forecast then add({"tr-en.why-drop-solar", pct, "[entity=" .. wn .. "]"}, 1) end
      elseif wn then add({"tr-en.why-drop", pct, "[entity=" .. wn .. "]", M.power(worst)}, 1)
      else add({"tr-en.why-drop-plain", pct}, 1) end
    end
  end
end

-- is electricity doing badly? Why? From the planet's latest samples.
-- score 3 = no power, 2 = not enough, 1 = risk (demand at the limit, accumulators nearly empty or not enough until morning), 0 = fine
-- reasons = cause lines: demand above output, empty accumulators, out of fuel, no steam, demand jump, output drop,
-- night forecast (solar planets: will the charge last until dawn)
-- notes = info, does not affect status (for example accumulators with nothing to power)
-- on a storm planet the output from statistics lies (a lightning strike gives a spike), so we look at consumption and accumulator charge
function M.analyze(r)
  local out = {score = 0, reasons = {}, notes = {}}
  local h = r.h
  if not h then return out end
  -- the fast check (once a second) knows better than a sample (up to ~20 s old)
  local sh = h.short
  if r.cur_known then sh = r.cur end
  if sh == "none" then out.score = 3 elseif sh then out.score = 2 end
  -- only causes that are measured for sure and serious go to the journal (fuel, steam, not enough charge until dawn, fast discharge);
  -- "at the limit", spikes and dips show in the window but do not fill the journal
  local LOGGABLE = {["tr-en.why-nofuel"] = true, ["tr-en.why-gen-nofuel"] = true, ["tr-en.why-gen-nofluid"] = true,
    ["tr-en.why-night-short"] = true, ["tr-en.why-acc-drain"] = true, ["tr-en.why-fuel-low"] = true, ["tr-en.why-acc"] = true, ["tr-en.why-acc-storm"] = true}
  local function add(line, score)
    out.reasons[#out.reasons + 1] = line
    if score > out.score then out.score = score end
    if type(line) == "table" and LOGGABLE[line[1]] then out.loggable = true end
  end
  local storm = M.storm(r.hist)
  -- source limit: nominal with quality and sun, or the peak actually seen in the last hour (whichever is bigger)
  local peak = 0
  if not storm then for _, x in ipairs(r.hist or {}) do if x.prod > peak then peak = x.prod end end end
  local cap = math.max(h.capw or 0, h.prod, peak)
  local acc_ok = (h.cap or 0) > 0 and h.stored / h.cap >= 0.15
  local no_acc = (h.acc_n or 0) == 0 and (h.cap or 0) == 0
  local c = {r = r, h = h, sh = sh, out = out, add = add, storm = storm, cap = cap, acc_ok = acc_ok, no_acc = no_acc}
  no_power_causes(c)
  -- solar planet: will the charge last until dawn (or will capacity last the night). Day and night length come from the planet itself
  night_forecast(c)
  -- accumulators carry the net and will run out soon (where day and night are not counted): how long the charge lasts at the current draw
  -- (the draw is taken from how the charge really fell over the last ~10 minutes, or from net statistics if there are few samples)
  drain_cause(c)
  -- long series: consumption trend, fuel running out
  pcall(M.series, r.hist or {}, r.long, storm and 0 or cap, add, out.notes)
  -- compare with the mean of up to 10 samples before the last
  change_causes(c)
  if storm and sh and #out.reasons == 0 then add({"tr-en.why-short-storm"}, 2) end
  -- charged accumulators give nothing during a shortage: probably not connected to the net
  if sh and (h.cap or 0) > 0 and h.stored / h.cap >= 0.2 and h.acc_short ~= nil then
    if h.acc_short == 0 and (h.acc_n or 0) > 0 then
      add({"tr-en.why-acc-elsewhere", h.acc_n}, 2)
    elseif (h.acc_out or 0) < 1e4 then
      add({"tr-en.why-acc-idle", math.floor(h.stored / h.cap * 100)}, 2)
    end
  end
  -- info: accumulators with nothing to power (does not affect status or journal)
  if (h.acc_iso or 0) > 0 and (h.acc_n or 0) > 0 then out.notes[#out.notes + 1] = {"tr-en.note-acc-iso", h.acc_iso, h.acc_n} end
  -- nothing is produced and nothing is consumed: "enough" cannot be said here
  if out.score == 0 and h.prod <= 0 and (h.cons or 0) <= 0 and not sh then out.idle = true end
  return out
end

function M.power(w)
  w = w or 0
  if w >= 1e9 then return {"tr.power-gw", string.format("%.2f", w / 1e9)} end
  if w >= 1e6 then return {"tr.power-mw", string.format("%.1f", w / 1e6)} end
  return {"tr.power-kw", string.format("%.0f", w / 1e3)}
end
function M.energy(j)
  j = j or 0
  if j >= 1e9 then return {"tr.energy-gj", string.format("%.1f", j / 1e9)} end
  return {"tr.energy-mj", string.format("%.0f", j / 1e6)}
end
U.push_long = push_long
U.slope = slope
