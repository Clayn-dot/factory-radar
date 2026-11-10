-- Factory Radar: power grids: shared settings, outage journal and event recording
-- Factory Radar: electricity per planet: output, consumption, accumulators, outages
-- in net statistics input = CONSUMERS, output = SOURCES (the opposite of what it seems)
-- nets are searched rarely (pole search is expensive) and read often (cheap)
local C = require("scripts.core")
local M = {}
local U = {M = M}    -- shared table of window parts: each part puts here what the others need

local HIST = 180                -- a sample about every 20 s, so an hour of history
local LONG = 288                -- and 5 minute averages for a day
local SAMPLE_GAP = 1200         -- ticks between two samples of a planet with a net
local REDISCOVER = 60 * 3600    -- ticks between net searches
local COUNT_CALLS = 1           -- count calls per planet sample (each costs time proportional to the number of buildings)
local COUNT_EVERY = 30 * 3600   -- ticks a count of one name is considered fresh
local CHECK_TYPES = {"assembling-machine", "furnace", "lab", "mining-drill"}
local MIN_EVENT = 600           -- "no power" is written when it lasts 10 s (shorter is ignored)
local MIN_EVENT_LOW = 3600      -- "not enough" (machines work below full power) when it lasts a minute
local MERGE_GAP = 10 * 3600     -- outages of one planet closer than this are one entry ("6 times in 40 min")
local CLOSE_AFTER = 2           -- checks in a row without an outage to close it
local LOG_MAX = 20
local WARN_AFTER = 15             -- samples in a row (~5 minutes) with a serious cause for it to become a yellow journal entry

local function E()
  local d = C.D()
  d.energy = d.energy or {}
  return d.energy
end
function M.planet(key)
  local e = E()
  e[key] = e[key] or {nets = {}, acc = {}, refs = {}, hist = {}, scanned = nil, last = nil}
  return e[key]
end

-- outage journal: all planets together, new on top, last LOG_MAX, a new shift does not clear it
local function LOG()
  local d = C.D()
  d.energy_log = d.energy_log or {}
  return d.energy_log
end
function M.log() return LOG() end
-- level: "red" (outage: no power or not enough; old entries have no field) or "warn" (yellow: at the limit, risk)
local function open_entry(key, level)
  for _, e in ipairs(LOG()) do
    if e.key == key and not e.done and (e.level or "red") == (level or "red") then return e end
  end
  return nil
end
-- total outage duration (all runs), in ticks
function M.duration(e)
  return (e.total or 0) + ((not e.done) and math.max(0, (e.last or 0) - (e.run or e.start or 0)) or 0)
end

-- yellow entries: the net works but at the limit or with risk (same causes as in the planet tooltip).
-- An entry appears when it was so for WARN_AFTER samples in a row and closes after two calm samples
-- or when a real outage starts (a red entry)
local function close_entry(e)
  if e.done then return end
  e.done = true
  e.total = (e.total or 0) + math.max(0, (e.last or 0) - (e.run or e.start or 0))
end
function M.warn_track(pe, key, an, red)
  local now = game.tick
  local open = open_entry(key, "warn")
  if red or not an or not an.loggable then
    pe.warn_n = 0
    if open then
      pe.warn_ok = (pe.warn_ok or 0) + 1
      if red or pe.warn_ok >= 3 then close_entry(open); pe.warn_ok = 0 end
    end
    return
  end
  pe.warn_ok = 0
  pe.warn_n = (pe.warn_n or 0) + 1
  local h = pe.hist[#pe.hist]
  if open then
    open.last = now
    if #an.reasons > 0 then open.why = an.reasons end
    open.cons, open.prod = h and h.cons, h and h.prod
  elseif pe.warn_n >= WARN_AFTER then
    local log = LOG()
    local again = nil
    for i, e in ipairs(log) do
      if e.key == key and e.done and (e.level or "red") == "warn" and now - (e.last or 0) < MERGE_GAP then again = i; break end
    end
    local start = now - (WARN_AFTER - 1) * SAMPLE_GAP
    if again then
      local e = table.remove(log, again)
      e.done, e.n, e.run, e.last = false, (e.n or 1) + 1, start, now
      if #an.reasons > 0 then e.why = an.reasons end
      table.insert(log, 1, e)
    else
      table.insert(log, 1, {key = key, level = "warn", start = start, run = start, last = now, kind = "warn", why = an.reasons,
        n = 1, total = 0, done = false, cons = h and h.cons, prod = h and h.prod})
      while #log > LOG_MAX do table.remove(log) end
    end
  end
end

---------------------------------------------------------------- fast check: an outage is written when it happens
-- once a second each net is asked for one machine's status (cheap). A 10 second outage at once
-- becomes a journal entry with fresh causes; two clean checks in a row close it. Outages of one
-- planet closer than 10 minutes are one entry with a repeat counter (otherwise solar nights would flood the journal)
local function commit(pe, key, s, kind)
  local now = game.tick
  local pending = pe.pending
  pe.pending = nil
  -- fresh numbers for the causes
  if s then M.sample(s) end
  local an = M.analyze({h = pe.hist[#pe.hist], hist = pe.hist, long = pe.long, cur = kind, cur_known = true, s = s})
  local log = LOG()
  local again = nil
  for i, e in ipairs(log) do
    if e.key == key and e.done and (e.level or "red") == "red" and now - (e.last or 0) < MERGE_GAP then again = i; break end
  end
  if again then
    local e = table.remove(log, again)
    e.done, e.n, e.run, e.last = false, (e.n or 1) + 1, pending.tick, now
    e.prev_t, e.prev_k = nil, nil
    e.share = math.max(e.share or 0, pending.share or 0)
    if kind == "none" then e.kind = "none" end
    if #an.reasons > 0 then e.why = an.reasons end
    table.insert(log, 1, e)
  else
    local h0 = pe.hist[#pe.hist]
    table.insert(log, 1, {key = key, level = "red", start = pending.tick, run = pending.tick, last = now, kind = kind, why = an.reasons,
      n = 1, total = 0, done = false, t_none = 0, t_low = 0, share = pending.share, cons = h0 and h0.cons, prod = h0 and h0.prod})
    while #log > LOG_MAX do table.remove(log) end
  end
  if now - (pe.warned or -1e9) > 30 * 3600 then
    pe.warned = now
    C.journal({"tr-msg.power-" .. kind, C.planet_ls(key)})
  end
end

local function track(pe, key, s, kind, frac)
  local now = game.tick
  pe.cur = kind
  local open = open_entry(key, "red")
  if kind then
    pe.good = 0
    if open then
      -- how much of this time there was no power at all, and how much it was just short
      local dt = math.min(now - (open.prev_t or now), 300)
      if (open.prev_k or kind) == "none" then open.t_none = (open.t_none or 0) + dt else open.t_low = (open.t_low or 0) + dt end
      open.prev_t, open.prev_k = now, kind
      open.last = now
      open.share = math.max(open.share or 0, frac or 0)
      if kind == "none" then open.kind = "none" end
    else
      if not pe.pending then pe.pending = {tick = now, kind = kind, share = frac or 0}
      else
        if kind == "none" then pe.pending.kind = "none" end
        pe.pending.share = math.max(pe.pending.share or 0, frac or 0)
      end
      if now - pe.pending.tick >= (pe.pending.kind == "none" and MIN_EVENT or MIN_EVENT_LOW) then commit(pe, key, s, pe.pending.kind) end
    end
  else
    pe.pending = nil
    if open then
      pe.good = (pe.good or 0) + 1
      if pe.good >= CLOSE_AFTER then
        open.done = true
        open.total = (open.total or 0) + math.max(0, (open.last or 0) - (open.run or open.start or 0))
        pe.good = 0
      end
    end
  end
end

-- outages since a tick, for shift totals: {{key, count, minutes}} worst first
function M.trouble_since(tick)
  local by = {}
  for _, ev in ipairs(LOG()) do
    if ev.start >= tick and (ev.level or "red") == "red" and not ev.plat then
      local x = by[ev.key] or {key = ev.key, n = 0, mins = 0}
      by[ev.key] = x
      x.n = x.n + (ev.n or 1)
      x.mins = x.mins + math.max(1, math.floor(M.duration(ev) / 3600 + 0.5))
    end
  end
  local out = {}
  for _, x in pairs(by) do out[#out + 1] = x end
  table.sort(out, function(a, b) return a.mins > b.mins end)
  return out
end
U.CHECK_TYPES = CHECK_TYPES
U.LONG = LONG
U.COUNT_CALLS = COUNT_CALLS
U.HIST = HIST
U.REDISCOVER = REDISCOVER
U.open_entry = open_entry
U.COUNT_EVERY = COUNT_EVERY
U.SAMPLE_GAP = SAMPLE_GAP
U.track = track
U.E = E
U.MERGE_GAP = MERGE_GAP
U.LOG = LOG
U.close_entry = close_entry
U.LOG_MAX = LOG_MAX
return U
