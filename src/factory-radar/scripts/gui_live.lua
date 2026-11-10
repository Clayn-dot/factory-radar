-- Factory Radar: window: live updates of open tabs and auto refresh
local C = require("scripts.core")
local WH = require("scripts.where")
local PF = require("scripts.platforms")
local EN = require("scripts.energy")
local ZAP = require("scripts.zap")
local RU = require("scripts.roulette")
local U = require("scripts.gui_ui")
local M = U.M
local FRAME, GS = U.FRAME, U.GS
local function active_sub(...) return U.active_sub(...) end
local function dur(...) return U.dur(...) end
local function fill_tipbar(...) return U.fill_tipbar(...) end
local function flight_caption(...) return U.flight_caption(...) end
local function hop_tip(...) return U.hop_tip(...) end
local function km_txt(...) return U.km_txt(...) end
local function layout(...) return U.layout(...) end
local function next_tip(...) return U.next_tip(...) end
local function pane_of(...) return U.pane_of(...) end
local function tip_due(...) return U.tip_due(...) end

-- once a second: platform bars move in place; a card whose state changed redraws the tab
local function live_platforms(p, frame)
  local gs = GS(p)
  if gs.tab_name ~= "space" then return false end
  local g
  for _, x in ipairs(layout(p)) do if x.id == "space" then g = x end end
  if not g then return false end
  local sub = #g.subs == 1 and g.subs[1][1] or ((gs.sub or {})[g.id] or g.subs[1][1])
  if sub ~= "platforms" then return false end
  local pane = pane_of(frame, g, "platforms")
  if not (pane and pane.valid) then return false end
  local byidx = {}
  for _, pl in pairs(game.forces.player.platforms) do if pl.valid then byidx[pl.index] = pl end end
  local function walk(el, r)
    for _, ch in ipairs(el.children) do
      local t = ch.tags and ch.tags.tr
      if t == "plat_now" then ch.value = math.max(0, math.min(1, r.distance))
      elseif t == "plat_hop" then
        ch.value = math.max(0, math.min(1, r.distance))
        local f = PF.flight(r)
        if f and f.cur then
          ch.tooltip = hop_tip({kind = "cur", from = f.cur.from, to = f.cur.to, len = f.cur.len, ticks = f.cur.ticks, speed = f.cur.speed})
        end
      elseif t == "plat_eta" then
        local hops = PF.route(r)
        local total = 0
        for _, h in ipairs(hops or {}) do total = total + (h.len or 0) end
        local eta = PF.eta_ticks(r, total)
        ch.caption = eta and {"tr-plat.route-eta", dur(eta), km_txt(total)} or {"tr-plat.route-len", km_txt(total)}
      elseif t == "plat_trip" then
        local cap = flight_caption(r)
        if cap then ch.caption = cap end
      elseif t == "plat_pct" then ch.caption = {"tr-plat.pct", math.floor(r.distance * 100 + 0.5)}
      elseif t == "plat_idle" then
        local im = PF.idle_mins(r)
        ch.visible = im ~= nil
        if im then ch.caption = {"tr-plat.idle", C.time(r.idle)} end
      elseif #ch.children > 0 then walk(ch, r) end
    end
  end
  local n = 0
  for _, card in ipairs(pane.children) do
    local t = card.tags
    if t and t.tr == "plat_card" then
      n = n + 1
      local pl = byidx[t.idx]
      if not pl then return true end
      local r = PF.row(pl)
      if PF.sig(r) ~= t.sig then return true end
      walk(card, r)
    end
  end
  local count = 0
  for _ in pairs(byidx) do count = count + 1 end
  return count ~= n
end

-- once a second: "Who is where" updates texts and lightning cooldowns in place (no window redraw)
local function live_where(p, frame)
  local gs = GS(p)
  if gs.tab_name ~= "team" then return false end
  local g
  for _, x in ipairs(layout(p)) do if x.id == "team" then g = x end end
  if not g then return false end
  local sub = #g.subs == 1 and g.subs[1][1] or ((gs.sub or {})[g.id] or g.subs[1][1])
  if sub ~= "where" or gs.card then return false end
  local pane = pane_of(frame, g, "where")
  if not (pane and pane.valid) then return false end
  local rows = WH.rows(p)
  local have = {}
  local function collect(el)
    for _, ch in ipairs(el.children) do
      if ch.tags and ch.tags.tr == "where_row" then have[#have + 1] = ch
      elseif #ch.children > 0 then collect(ch) end
    end
  end
  collect(pane)
  if #have ~= #rows then return true end
  for i, r in ipairs(rows) do
    local row = have[i]
    if row.tags.sig ~= M.where_sig(p, r) then return true end
    local function walk(el)
      for _, ch in ipairs(el.children) do
        local t = ch.tags and ch.tags.tr
        if t == "where_head" then ch.caption = r.head; ch.tooltip = r.head
        elseif t == "where_line" then ch.caption = r.detail; ch.tooltip = r.detail
        elseif t == "where_look" then
          local cap = r.look_caption or ""
          ch.caption = cap; ch.tooltip = cap
        elseif t == "zap" then
          local why = ZAP.blocked(p, r.player)
          ch.enabled = why == nil
          ch.tooltip = why or {"tr-zap.tip", r.player.name, C.S("tr-s-zap-percent"), C.S("tr-s-zap-cooldown")}
        elseif #ch.children > 0 then walk(ch) end
      end
    end
    walk(row)
  end
  return false
end

-- once a second: the quiz line in the summary counts down in place (the tab is redrawn only on a state change)
local function live_summary(p, frame)
  if GS(p).tab_name ~= "summary" or not C.S("tr-s-roulette") then return false end
  local g
  for _, x in ipairs(layout(p)) do if x.id == "summary" then g = x end end
  local pane = g and pane_of(frame, g, "summary")
  if not (pane and pane.valid) then return false end
  local st, a, b = RU.status()
  local redraw = false
  local function walk(el)
    for _, ch in ipairs(el.children) do
      if ch.tags and ch.tags.tr == "rou_status" then
        if ch.tags.st ~= st then redraw = true
        elseif st == "cooldown" then ch.caption = {"tr-gui.rou-cd", a}
        elseif st == "join" then ch.caption = {"tr-gui.rou-join", a, b} end
      elseif #ch.children > 0 then walk(ch) end
    end
  end
  walk(pane)
  return redraw
end

-- once a second: the energy tab is redrawn as soon as an outage starts or ends
local function live_energy(p, frame)
  local gs = GS(p)
  if gs.tab_name ~= "factory" then return false end
  local g
  for _, x in ipairs(layout(p)) do if x.id == "factory" then g = x end end
  if not g then return false end
  local sub = #g.subs == 1 and g.subs[1][1] or ((gs.sub or {})[g.id] or g.subs[1][1])
  if sub ~= "energy" then return false end
  return gs.en_sig ~= EN.sig()
end

-- the game can silently reset opened (for example a jump into remote view); Esc does not work without it, so we restore it
local function keep_opened(p)
  local frame = p.gui.screen[FRAME]
  if frame and frame.valid and p.opened == nil then pcall(function() p.opened = frame end) end
end

local SLOW_TABS = {titles = true, achievements = true, help = true}
function M.autorefresh()
  for _, p in pairs(game.connected_players) do
    keep_opened(p)
    -- nobody looks at an AFK player's window: no redraw until they move
    local frame = p.afk_time <= 5 * 3600 and p.gui.screen[FRAME] or nil
    if frame then
      if tip_due(p) then next_tip(p, false); pcall(fill_tipbar, p, frame) end   -- a new tip once a minute
      if live_platforms(p, frame) or live_where(p, frame) or live_summary(p, frame) or live_energy(p, frame) then M.refresh_active(p) end
      local secs = C.P(p, "autorefresh") or 0
      if secs > 0 then
        -- heavy and rarely changing tabs are redrawn 4 times less often (the refresh button is still instant)
        local _, sub = active_sub(p, frame)
        if sub and SLOW_TABS[sub[1]] then secs = secs * 4 end
        if math.floor(game.tick / 60) % secs == 0 then M.refresh_active(p) end
      end
    end
  end
end
