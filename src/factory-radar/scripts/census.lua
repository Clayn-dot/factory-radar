-- Factory Radar: who built what, counted from standing buildings (each has last_user).
-- Needed for "all time": the shift counter has no building time.
-- Starts by itself once (a minute after start) and on an admin's request, in small steps,
-- so the game does not hang. A planet's counter is replaced by the result, not added to, otherwise buildings
-- made since the mod was installed would be counted twice.
local C = require("scripts.core")
local ST = require("scripts.stats")
local M = {}

local BUDGET = 1500      -- buildings per step (a step every 2 ticks)
local EMPTY = 5          -- an empty chunk costs something too

local function S()
  local d = C.D()
  d.census = d.census or {state = "idle"}
  return d.census
end

-- what the admin sees: idle | run, planet in work, how many are left, end tick
function M.status()
  local c = S()
  return c.state, c.cur and c.cur.key or nil, c.queue and #c.queue or 0, c.finished
end

function M.start()
  local c = S()
  if c.state == "run" then return false end
  c.state, c.queue, c.cur, c.done = "run", {}, nil, true
  for _, s in pairs(game.surfaces) do
    if C.RP(s) then
      local key = C.key(s)
      if key then c.queue[#c.queue + 1] = key end
    end
  end
  table.sort(c.queue)
  return true
end

local function finish(c)
  c.state, c.queue, c.cur, c.finished = "idle", nil, nil, game.tick
  -- planet titles are granted quietly, otherwise a dozen messages at once
  for _, p in pairs(game.players) do C.check_titles(p, true) end
  C.titles_changed()
  C.journal({"tr-msg.census-done"})
end

-- step: every 2 ticks, does nothing while no count is running
function M.step()
  local c = S()
  if c.state ~= "run" then
    if c.state == "idle" and not c.done and game.tick > 3600 then M.start() end    -- starts by itself the first time
    return
  end
  if not c.cur then
    local key = table.remove(c.queue, 1)
    if not key then finish(c) return end
    local s = C.surface(key)
    if not (s and s.valid) then return end
    local chunks = {}
    for ch in s.get_chunks() do chunks[#chunks + 1] = ch.x; chunks[#chunks + 1] = ch.y end
    c.cur = {key = key, i = 1, chunks = chunks, counts = {}}
    return
  end
  local cur = c.cur
  local s = C.surface(cur.key)
  if not (s and s.valid) then c.cur = nil return end
  local force = game.forces.player
  local skip = ST.NOT_BUILDINGS
  local budget = BUDGET
  local chunks = cur.chunks
  while budget > 0 and cur.i <= #chunks do
    local x, y = chunks[cur.i], chunks[cur.i + 1]
    cur.i = cur.i + 2
    local ok, list = pcall(s.find_entities_filtered, {area = {{x * 32, y * 32}, {x * 32 + 32, y * 32 + 32}}, force = force})
    budget = budget - EMPTY
    if ok then
      for _, e in ipairs(list) do
        budget = budget - 1
        if e.valid and not skip[e.type] then
          local u = e.last_user
          if u and u.valid then cur.counts[u.name] = (cur.counts[u.name] or 0) + 1 end
        end
      end
    end
  end
  if cur.i > #chunks then
    C.D().pbuilt[cur.key] = cur.counts
    c.cur = nil
  end
end

return M
