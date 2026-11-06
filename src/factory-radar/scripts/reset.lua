-- Factory Radar: «Сбросить» и «Откатить» собранную статистику по разделам (только админы)
-- Сброс хранит одну копию того, что было; откат возвращает её (собранное после сброса теряется)
local C = require("scripts.core")
local RS = require("scripts.research")
local M = {}

-- ключи storage каждого раздела
M.SECTIONS = {
  players = {"total", "shift", "pstat", "pwalk", "pdeaths", "ppipe", "pcraft", "pmine_tree", "pmine_rock", "pturrets", "pbuilt_shift", "psolar", "pbelts", "pacc", "pdrill", "pfact", "novote"},
  records = {"records", "pbest", "mvp_hist"},
  combat = {"combat", "pkills"},
  destruction = {"plost", "shift_plost", "ldest", "ldest_shift", "dest_recent"},
  platforms = {"plat", "plat_lost"},
  quality = {"qual", "qual_base"},
  energy = {"energy", "energy_log", "energy_plat"},
  journal = {"journal"},
  titles = {"titles"},
  achievements = {"team", "team_seen", "ach"},
  research = {"research"},
}

local function copy(v)
  if type(v) ~= "table" then return v end
  local out = {}
  for k, x in pairs(v) do out[k] = copy(x) end
  return out
end

local function U()
  local d = C.D()
  d.undo = d.undo or {}
  return d.undo
end

function M.can_undo(sec) return U()[sec] ~= nil end

-- итоги качества берутся из статистики игры, поэтому при сбросе запоминаем, где они стояли
local function quality_baseline()
  local base = {}
  local quals = {}
  for name, q in pairs(prototypes.quality) do if not q.hidden and q.level > 0 then quals[#quals + 1] = name end end
  for _, s in pairs(game.surfaces) do
    if C.RP(s) then
      local ok, stats = pcall(game.forces.player.get_item_production_statistics, s)
      if ok and stats then
        local b = {}
        for item in pairs(stats.input_counts) do
          for _, qn in ipairs(quals) do
            local ok2, n = pcall(stats.get_input_count, {name = item, quality = qn})
            if ok2 and n and n > 0 then b[item] = b[item] or {}; b[item][qn] = n end
          end
        end
        base[s.planet.prototype.name] = b
      end
    end
  end
  return base
end

function M.reset(sec, who)
  local keys = M.SECTIONS[sec]
  if not keys then return end
  local d = C.D()
  local saved = {}
  for _, k in ipairs(keys) do saved[k] = copy(d[k]) end
  U()[sec] = {data = saved, tick = game.tick, by = who and who.name or nil}
  for _, k in ipairs(keys) do d[k] = nil end
  d._ready = nil
  if sec == "quality" then d.qual_base = quality_baseline() end
  C.D()
  -- исследования: достигнутое считается «до сброса» (вехи не повторяются)
  if sec == "research" then
    RS.init()
    RS.science_tick(true)
  end
  C.broadcast({"tr-msg.reset", who and who.name or "?", {"tr-gui.sec-" .. sec}}, {0.8, 0.8, 0.8})
end

function M.undo(sec, who)
  local u = U()[sec]
  if not u then return end
  local d = C.D()
  for _, k in ipairs(M.SECTIONS[sec]) do d[k] = u.data[k] end
  d._ready = nil
  U()[sec] = nil
  C.D()
  C.broadcast({"tr-msg.undo", who and who.name or "?", {"tr-gui.sec-" .. sec}}, {0.8, 0.8, 0.8})
end

return M
