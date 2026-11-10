-- Factory Radar: output by quality on planets (what was "gambled" up to rare / epic / legendary...), from game statistics
local C = require("scripts.core")
local M = {}

local QUAL = nil
function M.qualities()
  if QUAL then return QUAL end
  QUAL = {}
  for name, q in pairs(prototypes.quality) do
    if not q.hidden and q.level > 0 then QUAL[#QUAL + 1] = {name = name, level = q.level} end
  end
  table.sort(QUAL, function(a, b) return a.level < b.level end)
  return QUAL
end

-- Everything comes from the game's item statistics: the total ("how much was made in all") and the per-minute rate
-- over 10 minutes (get_flow_count), there are no own samples, data is there right after load
local WINDOWS = {[10] = "ten_minutes", [60] = "one_hour"}   -- minutes -> statistics precision

local cache = {}    -- planet -> {tick, rows}: counting each item x quality is cheap but not free, so once a minute
local CACHE_TICKS = 3600

-- rows per planet: {item, by quality {total, rate}}, minutes covered
function M.planet_rows(key, window)
  window = WINDOWS[window or 10] and (window or 10) or 10
  local ckey = key .. "/" .. window
  local base = (C.D().qual_base or {})[key]
  local hit = cache[ckey]
  if hit and hit.base == base and game.tick - hit.tick < CACHE_TICKS and game.tick >= hit.tick then return hit.rows, window end
  local s = C.surface(key)
  if not (s and s.valid) then return nil, 0 end
  local ok, stats = pcall(function() return game.forces.player.get_item_production_statistics(s) end)
  if not (ok and stats) then return nil, 0 end
  local idx = defines.flow_precision_index[WINDOWS[window]]
  -- after a reset the totals count from the reset
  local base = base or {}
  local quals = M.qualities()
  local rows = {}
  for item in pairs(stats.input_counts) do
    local r = {item = item, q = {}, score = 0}
    local any = false
    for _, ql in ipairs(quals) do
      local ok2, n = pcall(stats.get_input_count, {name = item, quality = ql.name})
      if ok2 and n and n > 0 then
        local rate = 0
        local ok3, v = pcall(stats.get_flow_count, {name = {name = item, quality = ql.name}, category = "input", precision_index = idx})
        if ok3 and v then rate = v end
        local total = n - ((base[item] or {})[ql.name] or 0)
        if total > 0 or rate > 0 then
          any = true
          r.q[ql.name] = {total = math.max(0, total), rate = rate}
          r.score = r.score + rate * 1000 + math.max(0, total)
        end
      end
    end
    if any then rows[#rows + 1] = r end
  end
  table.sort(rows, function(a, b) return a.score > b.score end)
  cache[ckey] = {tick = game.tick, rows = rows, base = (C.D().qual_base or {})[key]}
  return rows, window
end

-- personal filter: category and hidden items
function M.category(item)
  local it = prototypes.item[item]
  if not it then return "other" end
  if it.type == "module" then return "modules" end
  if it.place_result then return "buildings" end
  return "intermediate"
end

return M
