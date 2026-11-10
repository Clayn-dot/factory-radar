-- Factory Radar: research progress, levels of infinite technologies and science milestones
local C = require("scripts.core")
local P = require("scripts.planets")
local M = {}

local INF = 4000000000

local function is_infinite(tech) return tech.prototype.max_level and tech.prototype.max_level >= INF end

function M.progress()
  local done, total = 0, 0
  for _, tech in pairs(game.forces.player.technologies) do
    if tech.enabled and not tech.prototype.hidden and not is_infinite(tech) then
      total = total + 1
      if tech.researched then done = done + 1 end
    end
  end
  return done, total
end

local function R()
  local r = C.D().research
  r.inf = r.inf or {}
  r.levels_by = r.levels_by or {}
  r.shift_levels = r.shift_levels or 0
  r.total_levels = r.total_levels or 0
  r.spent_total = r.spent_total or {}
  r.spent_shift = r.spent_shift or {}
  return r
end

-- how many levels of this infinite technology are researched (worker-robots-speed-7 starts at level 7)
local function completed_level(tech)
  -- tech.level is the level being researched now
  return math.max(0, tech.level - (tech.prototype.level or 1))
end

function M.init()
  local r = R()
  for name, tech in pairs(game.forces.player.technologies) do
    if is_infinite(tech) and not r.inf[name] then
      r.inf[name] = {seen = completed_level(tech), total = 0, shift = 0, packs = {}, packs_shift = {}}
    end
  end
  r.spent_total = r.spent_total or {}
  r.spent_shift = r.spent_shift or {}
end

-- Packs that labs really spent. Item statistics also count packs that went into recyclers
-- or were destroyed, so they say nothing about research. Here we count from the research itself, once
-- a minute: progress made x technology units x pack amount / (1 + lab productivity)
function M.sample()
  local ok = pcall(function()
    local r = R()
    local f = game.forces.player
    local lab = r.lab or {hist = {}}
    r.lab = lab
    local cur = f.current_research
    local prod = 1 + (f.laboratory_productivity_bonus or 0)
    local delta = {}
    local function add(tech, units)
      if units <= 0 then return end
      for _, ing in ipairs(tech.research_unit_ingredients) do delta[ing.name] = (delta[ing.name] or 0) + units * ing.amount end
    end
    local progress = f.research_progress or 0
    if lab.tech then
      local old = f.technologies[lab.tech]
      if old and old.valid then
        if cur and cur.name == lab.tech then
          local du = progress - lab.prog
          if du < 0 then du = du + 1 end                    -- the level ended and the next one began
          add(old, math.min(1, du) * old.research_unit_count / prod)
        elseif old.researched then
          add(old, (1 - lab.prog) * old.research_unit_count / prod)   -- finished since the last look
          if cur then add(cur, progress * cur.research_unit_count / prod) end
        end
      end
    end
    lab.tech, lab.prog = cur and cur.name or nil, progress
    local any = false
    for name, v in pairs(delta) do
      any = true
      r.spent_total[name] = (r.spent_total[name] or 0) + v
      r.spent_shift[name] = (r.spent_shift[name] or 0) + v
    end
    if any then
      table.insert(lab.hist, {tick = game.tick, d = delta})
      while #lab.hist > 20 do table.remove(lab.hist, 1) end
    end
  end)
  return ok
end
function M.on_research_started() end

function M.on_research_finished(e)
  local tech = e.research
  if not (tech and tech.valid) or tech.force.name ~= "player" then return end
  -- rocket silo or space platform: space tabs open
  for _, name in ipairs(C.space_techs()) do
    if tech.name == name and C.hooks.space_unlocked then
      C.mark_start_crew()
      C.broadcast({"tr-msg.space-unlocked", tech.localised_name}, {0.75, 0.9, 1})
      C.hooks.space_unlocked()
    end
  end
  local r = R()
  r.cur = nil
  if is_infinite(tech) then
    local st = r.inf[tech.name] or {seen = 0, total = 0, shift = 0, packs = {}, packs_shift = {}}
    r.inf[tech.name] = st
    local now = completed_level(tech)
    local gained = math.max(1, now - st.seen)
    st.seen = now
    st.total = st.total + gained
    st.shift = st.shift + gained
    r.total_levels = r.total_levels + gained
    r.shift_levels = r.shift_levels + gained
    for _, p in pairs(game.connected_players) do
      r.levels_by[p.name] = (r.levels_by[p.name] or 0) + gained
      C.check_titles(p)
    end
    C.team_add("infinite", gained)
  else
    local done, total = M.progress()
    if total > 0 then C.team_check("research", math.floor(done / total * 100), false) end
  end
end

---------------------------------------------------------------- science milestones (1st, 1 000th ... 1 000 000 000th pack)
M.MILESTONES = {1, 1000, 10000, 100000, 1000000, 1000000000}

-- packs produced by type, sum over all surfaces; and where the most was made
local function produced()
  local tot, where = {}, {}
  local f = game.forces.player
  for _, s in pairs(game.surfaces) do
    if s.valid then
      local ok, stats = pcall(f.get_item_production_statistics, s)
      if ok and stats then
        for _, name in ipairs(P.science_names()) do
          local ok2, n = pcall(stats.get_input_count, name)
          if ok2 and n and n > 0 then
            tot[name] = (tot[name] or 0) + n
            if not where[name] or n > where[name].n then where[name] = {n = n, s = s} end
          end
        end
      end
    end
  end
  return tot, where
end

-- once a minute; silent = the first run after install (what already happened is marked "before install")
function M.science_tick(silent)
  local r = R()
  r.ms = r.ms or {}
  if not r.ms_ready then silent = true; r.ms_ready = true end
  local tot, where = produced()
  for name, n in pairs(tot) do
    local m = r.ms[name] or {}
    r.ms[name] = m
    for _, th in ipairs(M.MILESTONES) do
      if n >= th and not m[th] then
        if silent then
          m[th] = {before = true}
        else
          local s = where[name].s
          local place, plat
          if s.platform then place, plat = s.platform.name, true
          else place = C.location_key(s) end
          m[th] = {tick = game.tick, place = place, plat = plat}
          if C.S("tr-science-milestones") then
            local place = C.place(s)
            -- in chat [item=...] already shows the item name, a second one is not needed
            local icon = "[item=" .. name .. "]"
            if th == 1 then
              C.send("science-first", {"tr-msg.science-first", icon, place}, {icon = icon, pack = icon, place = place},
                {0.75, 0.9, 1})
            else
              C.send("science-milestone", {"tr-msg.science-milestone", C.big(th), icon, place, C.time(game.tick)},
                {icon = icon, pack = icon, count = C.big(th), place = place, time = C.time(game.tick)}, {0.75, 0.9, 1})
            end
          end
        end
      end
    end
  end
end

-- science really made and really spent per minute (over 10 minutes), from the item statistics of each planet
-- and platform: statistics input = made, output = spent (by labs). where = where the most is spent
function M.consumption()
  local out = {}
  local idx = defines.flow_precision_index.ten_minutes
  local f = game.forces.player
  local now = game.tick
  -- spent by labs over 10 minutes, per minute
  local spent, oldest = {}, now
  local lab = R().lab
  for _, e in ipairs(lab and lab.hist or {}) do
    if now - e.tick <= 36000 then
      for name, v in pairs(e.d) do spent[name] = (spent[name] or 0) + v end
      if e.tick < oldest then oldest = e.tick end
    end
  end
  local minutes = math.min(10, math.max(1, (now - (oldest - 3600)) / 3600))
  for _, name in ipairs(P.science_names()) do
    local made, where, wbest, wplat = 0, nil, 0, false
    for _, s in pairs(game.surfaces) do
      if s.valid and (C.LOC(s) or s.platform) then
        local ok, st = pcall(f.get_item_production_statistics, s)
        if ok and st then
          local okm, m = pcall(st.get_flow_count, {name = name, category = "input", precision_index = idx})
          if okm and m then
            made = made + m
            if m > wbest then
              wbest = m
              if s.platform then where, wplat = s.platform.name, true
              else where, wplat = C.location_key(s), false end
            end
          end
        end
      end
    end
    local sp = (spent[name] or 0) / minutes
    if made > 0.05 or sp > 0.05 then
      out[#out + 1] = {name = name, made = made, spent = sp, where = where, platform = wplat}
    end
  end
  table.sort(out, function(a, b) return a.spent > b.spent end)
  return out
end

-- all science packs made per minute on each planet and platform (over 10 minutes), for the team achievement
function M.spm()
  local total = 0
  for _, r in ipairs(M.consumption()) do total = total + (r.made or 0) end
  return total
end

function M.milestone_rows()
  local r = R()
  local rows = {}
  for name, m in pairs(r.ms or {}) do
    if prototypes.item[name] then rows[#rows + 1] = {name = name, m = m, first = m[1] and (m[1].tick or -1) or math.huge} end
  end
  table.sort(rows, function(a, b) if a.first ~= b.first then return a.first < b.first end return a.name < b.name end)
  return rows
end

-- infinite technologies with levels, by level
function M.infinite_rows()
  local r = R()
  local rows = {}
  for name, tech in pairs(game.forces.player.technologies) do
    if is_infinite(tech) and tech.enabled and not tech.prototype.hidden then
      local st = r.inf[name] or {total = 0, shift = 0, packs = {}, packs_shift = {}}
      if completed_level(tech) > 0 or st.total > 0 then
        rows[#rows + 1] = {tech = tech, level = tech.level - 1, total = st.total, shift = st.shift, packs = st.packs,
          packs_shift = st.packs_shift}
      end
    end
  end
  table.sort(rows, function(a, b) if a.shift ~= b.shift then return a.shift > b.shift end return a.level > b.level end)
  return rows
end

-- closes the research shift; returns a line for the summary (or nil)
function M.close_shift()
  local r = R()
  local line = nil
  if r.shift_levels > 0 then
    local top, top_n = nil, 0
    for name, st in pairs(r.inf) do if st.shift > top_n then top, top_n = name, st.shift end end
    line = {"", "\n  ", {"tr-msg.shift-research", r.shift_levels,
      top and {"tr-msg.shift-research-top", "[technology=" .. top .. "]", top_n} or ""}}
  end
  for _, st in pairs(r.inf) do st.shift = 0; st.packs_shift = {} end
  r.shift_levels = 0
  return line
end

return M
