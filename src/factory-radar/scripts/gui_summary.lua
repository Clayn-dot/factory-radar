-- Factory Radar: window: header, tooltips and the "Summary" tab
local C = require("scripts.core")
local P = require("scripts.planets")
local RS = require("scripts.research")
local SH = require("scripts.shift")
local CB = require("scripts.combat")
local EN = require("scripts.energy")
local RU = require("scripts.roulette")
local U = require("scripts.gui_ui")
local M = U.M
local GS, W, bar, card_frame, deep_frame, heading, muted, scope = U.GS, U.W, U.bar, U.card_frame, U.deep_frame, U.heading, U.muted, U.scope
local sk, total_with_built, wrap = U.sk, U.total_with_built, U.wrap

---------------------------------------------------------------- header
local function fill_header(p, h)
  h.clear()
  local rd, rt = RS.progress()
  local rp = rt > 0 and rd / rt or 0
  local done, open = C.count_mastered()
  local all = C.planets_in_game()
  local row = h.add{type = "flow", direction = "horizontal"}
  row.style.horizontal_spacing = 16
  -- four equal columns with thin dividers: even, and places do not jump with text length
  local COLW = 234
  local function sep()
    local ln = row.add{type = "line", direction = "vertical"}
    ln.style.vertically_stretchable = true
  end
  -- values of each column are in a dark frame under the header, like cards in the summary
  local function boxed(col)
    local b = deep_frame(col)
    b.style.padding = 6
    b.style.vertically_stretchable = true
    return b
  end
  local c1 = row.add{type = "flow", direction = "vertical"}
  c1.style.width = COLW
  c1.add{type = "label", caption = {"tr-gui.header-research"}, style = "caption_label", tooltip = {"tr-gui.tip-header-research"}}
  bar(boxed(c1), rp, {"tr-gui.header-research-val", math.floor(rp * 100), rd, rt}, 90, {"tr-gui.tip-header-research"})
  sep()
  local c2 = row.add{type = "flow", direction = "vertical"}
  c2.style.width = COLW
  c2.add{type = "label", caption = {"tr-gui.header-planets"}, style = "caption_label", tooltip = {"tr-gui.tip-header-planets"}}
  if C.space_unlocked() then
    bar(boxed(c2), all > 0 and done / all or 0, {"tr-gui.header-planets-val", done, all, open}, 90, {"tr-gui.tip-header-planets"})
  else
    muted(boxed(c2), {"tr-gui.header-locked"}).tooltip = {"tr-gui.space-locked"}
  end
  local cs = CB.S()
  sep()
  local c4 = row.add{type = "flow", direction = "vertical"}
  c4.style.width = COLW
  c4.add{type = "label", caption = {"tr-gui.header-combat"}, style = "caption_label", tooltip = {"tr-gui.tip-header-combat"}}
  local top_evo = CB.active_evo_rows()[1]
  local total_scope = scope(p) == "total"
  local kp, kn = nil, 0
  for key, pl in pairs(cs.planets) do
    local n = total_scope and pl.kills or pl.kills_shift
    if n > kn then kp, kn = key, n end
  end
  local ctip = {"", {"tr-gui.tip-header-combat"},
    top_evo and {"", "\n", {"tr-gui.header-evo", CB.pct(top_evo.now), C.planet_ls(top_evo.key)}} or ""}
  -- long planet names wrap in the column instead of widening the header
  wrap(boxed(c4).add{type = "label", caption = {"tr-gui.header-combat-val", C.n(total_scope and cs.total or cs.shift),
    kp and {"tr-gui.header-kills-where", C.planet_ls(kp)} or ""}, tooltip = ctip}, COLW - 36)
  sep()
  local c3 = row.add{type = "flow", direction = "vertical"}
  c3.style.width = COLW
  local online = 0
  for _ in pairs(game.connected_players) do online = online + 1 end
  c3.add{type = "label", caption = {"tr-gui.header-online", online}, style = "caption_label"}
  local b3 = boxed(c3)
  b3.add{type = "label", caption = {"tr-gui.header-shift", SH.minutes_left()},
    tooltip = {"tr-gui.tip-shift-len", string.format("%g", math.floor(C.shift_ticks() / 216000 * 10 + 0.5) / 10)}}
  -- game time: a point in time and in brackets how much has passed (so "13 d 15:04" is clear)
  do
    local mins = math.floor(game.tick / 3600)
    local hours = math.floor(mins / 60)
    -- as in the game itself: hours without a day reset ("327:04"), days and hours in brackets
    b3.add{type = "label", caption = {"tr-gui.header-time", string.format("%d:%02d", hours, mins % 60), {"tr.time-dh", math.floor(hours / 24), hours % 24}},
      tooltip = {"tr-gui.tip-header-time"}}
  end
end

---------------------------------------------------------------- Summary
local LEADERS = {{"kills", C.n}, {"built", C.n}, {"walk", C.km}, {"mined", C.n}, {"deaths", C.n}}

local function mvp_block(p, pane)
  local d = C.D()
  heading(pane, {"tr-gui.mvp-head"})
  local cand = {}
  for _, pl in pairs(game.players) do
    if pl.name ~= p.name and pl.connected then cand[#cand + 1] = pl.name end
  end
  table.sort(cand)
  local votes = 0
  for _ in pairs(d.mvp) do votes = votes + 1 end
  muted(pane, {"tr-gui.mvp-hint", SH.minutes_left(), votes})
  local pk, pw = SH.pick()
  if pk and pk ~= p.name then muted(pane, {"tr-gui.mvp-pick", pk, SH.why_ls(pw)}) end
  if #cand == 0 then muted(pane, {"tr-gui.mvp-nobody"}) return end
  local row = pane.add{type = "flow", direction = "horizontal"}
  row.style.horizontal_spacing = 6
  local mine = d.mvp[p.name]
  for _, name in ipairs(cand) do
    local b = row.add{type = "button", caption = mine == name and {"", "✓ ", name} or name,
      tags = {tr = "mvp_vote", who = name}, tooltip = {"tr-gui.mvp-vote-tip", name}}
    if mine == name then b.style.font = "default-bold" end
  end
  if mine then row.add{type = "button", caption = {"tr-gui.mvp-unvote"}, tags = {tr = "mvp_vote", who = ""}} end
end

-- the first thing a player sees: what a shift is and where to go next
-- a closable guide: what each tab is for (the tabs themselves are right below)
local GUIDE = {"where", "players", "titles", "achievements", "records", "planets", "platforms", "combat", "destruction",
  "research", "quality", "energy", "journal", "settings", "help"}
local function intro(p, pane)
  if not C.P(p, "intro") then return end
  local box = pane.add{type = "frame", direction = "vertical", style = "inside_shallow_frame_with_padding"}
  box.style.horizontally_stretchable = true
  box.style.bottom_margin = 6
  box.add{type = "label", caption = {"tr-gui.intro-head"}, style = "caption_label"}
  wrap(box.add{type = "label", caption = {"tr-gui.intro-scope"}}, W - 60)
  local t = box.add{type = "table", column_count = 2}
  t.style.horizontal_spacing = 10
  t.style.vertical_spacing = 2
  t.style.top_margin = 4
  for _, name in ipairs(GUIDE) do
    local _, _, _, sub = M._find_sub(p, name)
    if sub then
      local nm = t.add{type = "label", caption = {"", sub[3], " [font=default-bold]", {"tr-gui.tab-" .. name}, "[/font]"}}
      nm.style.minimal_width = 150
      wrap(t.add{type = "label", caption = {"tr-gui.guide-" .. name}}, W - 260)
    end
  end
  local hide = box.add{type = "button", caption = {"tr-gui.intro-hide"}, tooltip = {"tr-gui.intro-hide-tip"}, tags = {tr = "pcfg_set", key = "intro", value = false}}
  hide.style.height = 22
  hide.style.minimal_width = 0
  hide.style.padding = {0, 6, 2, 6}
  hide.style.top_margin = 4
end

-- "Good to know" block: main facts in a couple of lines and a tip that changes once a minute
local TIPS = 35
local TIP_PERIOD = 3600
-- the tip is stored per player: the refresh button can change it (then the next auto change comes after half the period) or the timer
local function next_tip(p, manual)
  local gs = GS(p)
  gs.tip_idx = ((gs.tip_idx or math.floor(game.tick / TIP_PERIOD)) % TIPS) + 1
  gs.tip_tick = game.tick - (manual and TIP_PERIOD / 2 or 0)
end
local function fill_tipbar(p, frame)
  local bar = frame and frame.valid and frame.tr_tipbar
  if not (bar and bar.valid) then return end
  bar.visible = C.P(p, "tips") ~= false
  if not bar.visible then return end
  local gs = GS(p)
  if not gs.tip_idx then next_tip(p, false) end
  bar.tr_tiptext.caption = {"", "[img=utility/tip_icon] ", {"tr-tips.t" .. ((gs.tip_idx - 1) % TIPS + 1)}}
end
local function tip_due(p)
  local gs = GS(p)
  return not gs.tip_tick or game.tick - gs.tip_tick >= TIP_PERIOD
end

local function good_to_know(p, pane)
  if not C.P(p, "know") then return end       -- the player hid it (Settings or the button below)
  local box = card_frame(pane, {"tr-gui.know-head"})
  local ar = C.P(p, "autorefresh") or 0
  local hours = string.format("%g", math.floor(C.shift_ticks() / 216000 * 10 + 0.5) / 10)
  local lines = {
    ar > 0 and {"tr-gui.know-window", ar} or {"tr-gui.know-window-off"},
    {"tr-gui.know-live"},
    {"tr-gui.know-shift", hours, SH.minutes_left()},
    {"tr-gui.know-since"},
  }
  for _, l in ipairs(lines) do
    local lb = wrap(box.add{type = "label", caption = {"", "· ", l}}, W - 90)
    lb.style.font_color = {0.8, 0.8, 0.8}
  end
  local hide = box.add{type = "button", caption = {"tr-gui.know-hide"}, tooltip = {"tr-gui.know-hide-tip"}, tags = {tr = "pcfg_set", key = "know", value = false}}
  hide.style.height = 22
  hide.style.minimal_width = 0
  hide.style.padding = {0, 6, 2, 6}
  hide.style.top_margin = 4
end

local function leaders_card(p, pane, tbl)
  local lead = deep_frame(card_frame(pane, {sk(p, "tr-gui.sum-leaders")}))
  local any = false
  for _, c in ipairs(LEADERS) do
    local who, v = C.leader(tbl, c[1])
    if who then
      any = true
      lead.add{type = "label", caption = {"tr-gui.now-leader-" .. c[1], who, c[2](v)}}
    end
  end
  if not any then muted(lead, {sk(p, "tr-gui.why-no-leaders")}) end
end

local function planets_card(p, pane, d, sc)
  local pcard = card_frame(pane, {sk(p, "tr-gui.sum-planets")}, {"tr-gui.tip-output"})
  local pbox = deep_frame(pcard)
  -- planets with no output are not shown
  local all_rows = P.live(sc)
  local rows = {}
  for _, r in ipairs(all_rows) do if r.out > 0 then rows[#rows + 1] = r end end
  if #all_rows == 0 then muted(pbox, {"tr-gui.why-no-planets"}) end
  local best = rows[1] and rows[1].out or 0
  if #rows == 0 and #all_rows > 0 then muted(pbox, {sk(p, "tr-gui.why-no-output")}) end
  local ptab = pbox.add{type = "table", column_count = 4}
  ptab.style.horizontal_spacing = 10
  ptab.style.vertical_spacing = 4
  ptab.style.column_alignments[4] = "right"
  for i = 1, math.min(12, #rows) do
    local r = rows[i]
    local nm = ptab.add{type = "label", caption = C.place(r.s)}
    nm.style.minimal_width = 130
    nm.style.maximal_width = 150
    local share = best > 0 and r.out / best or 0
    local pb = ptab.add{type = "progressbar", value = share,
      tooltip = {"tr-gui.tip-output-bar", math.floor(share * 100 + 0.5)}}
    pb.style.width = 90
    local cap = {"", C.n(r.out)}
    if r.sci > 0 then cap[#cap + 1] = {"tr-gui.now-science", C.n(r.sci)} end
    if r.vs then cap[#cap + 1] = {"tr-gui.now-vs", P.vs_text(r.vs)} end
    local tip
    if sc == "shift" then
      if r.vs then tip = {"tr-gui.tip-vs"}
      elseif r.ticks < 36000 then tip = {"tr-gui.tip-pace-wait"}
      else tip = {"tr-gui.tip-no-prev"} end
    end
    local cl = ptab.add{type = "label", caption = cap, tooltip = tip}
    cl.style.minimal_width = 200
    cl.style.maximal_width = 410
    cl.style.single_line = false
    local bn, bv = nil, 0
    local bsrc = sc == "total" and d.pbuilt[r.key] or (d.pbuilt_shift or {})[r.key]
    for name, v in pairs(bsrc or {}) do if v > bv then bn, bv = name, v end end
    if bn then
      local bl = ptab.add{type = "label", caption = {"tr-gui.sum-builder", bn, C.n(bv)}, tooltip = {"tr-gui.sum-builder-tip"}}
      bl.style.minimal_width = 200
      bl.style.font_color = {0.75, 0.85, 1}
    else
      ptab.add{type = "empty-widget"}
    end
  end
end

local function combat_card(p, pane, d, sc)
  local dcard = card_frame(pane)
  local duo = dcard.add{type = "flow", direction = "horizontal"}
  duo.style.horizontal_spacing = 10
  duo.style.horizontally_stretchable = true
  local cs = CB.S()
  local kills = sc == "total" and cs.total or cs.shift
  -- two equal halves, one line in each
  local first_half = true
  local function duo_card(title)
    if not first_half then
      local ln = duo.add{type = "line", direction = "vertical"}
      ln.style.vertically_stretchable = true
    end
    first_half = false
    local f = duo.add{type = "flow", direction = "vertical"}
    f.style.horizontally_stretchable = true
    f.style.minimal_width = 380
    local l = f.add{type = "label", caption = title, style = "caption_label"}
    l.style.bottom_margin = 6
    local box = deep_frame(f)
    box.style.padding = 8
    return box
  end
  local function one_line(box, caption)
    local l = box.add{type = "label", caption = caption}
    l.style.single_line = true
    return l
  end
  local cc = duo_card({sk(p, "tr-gui.sum-combat")})
  if kills == 0 then muted(cc, {sk(p, "tr-gui.why-no-kills")})
  else
    local w, wn = CB.best(sc == "total" and cs.weap or cs.weap_shift)
    one_line(cc, {"tr-gui.sum-combat-val", C.n(kills), w and {"tr-gui.sum-combat-most", C.weapon_ls(w), C.n(wn)} or ""})
  end
  local lost, lbest, lbn = 0, nil, 0
  for key, n in pairs(sc == "total" and d.plost or d.shift_plost) do
    lost = lost + n
    if n > lbn then lbest, lbn = key, n end
  end
  local cd = duo_card({sk(p, "tr-gui.sum-destruction")})
  if lost == 0 then muted(cd, {sk(p, "tr-gui.why-no-lost")})
  else one_line(cd, {"tr-gui.sum-lost-val", C.n(lost), lbest and {"tr-gui.sum-lost-most", C.planet_ls(lbest), C.n(lbn)} or ""}) end
end

local function state_card(pane)
  local st = deep_frame(card_frame(pane, {"tr-gui.sum-state"}))
  local risk, total = 0, 0
  for _, r in ipairs(EN.rows()) do
    if r.nets > 0 then
      total = total + 1
      if EN.analyze(r).score >= 1 then risk = risk + 1 end
    end
  end
  if total == 0 then muted(st, {"tr-gui.sum-power-none"})
  elseif risk > 0 then
    local prow = st.add{type = "flow", direction = "horizontal"}
    prow.style.vertical_align = "center"
    prow.style.horizontal_spacing = 8
    prow.add{type = "label", caption = {"", "[color=1,0.7,0.4]", {"tr-gui.sum-power-risk", risk, total}, "[/color]"}}
    local gb = prow.add{type = "button", caption = {"tr-gui.sum-go-energy"}, tags = {tr = "goto", sub = "energy"}}
    gb.style.height = 24
    gb.style.minimal_width = 0
    gb.style.padding = {0, 8, 2, 8}
  else
    st.add{type = "label", caption = {"", "[color=0.6,1,0.6]", {"tr-gui.sum-power-ok", total}, "[/color]"}}
  end
  local flying, parked = 0, 0
  for _, pl in pairs(game.forces.player.platforms) do
    if pl.valid then if pl.space_connection then flying = flying + 1 else parked = parked + 1 end end
  end
  if flying + parked > 0 then
    local plrow = st.add{type = "flow", direction = "horizontal"}
    plrow.style.vertical_align = "center"
    plrow.style.horizontal_spacing = 8
    plrow.style.top_margin = 2
    plrow.add{type = "label", caption = {"tr-gui.sum-platforms", flying, parked}}
    local pgb = plrow.add{type = "button", caption = {"tr-gui.sum-go-platforms"}, tags = {tr = "goto", sub = "platforms"}}
    pgb.style.height = 22
    pgb.style.minimal_width = 0
    pgb.style.padding = {0, 8, 2, 8}
  end
end

local function players_card(p, pane)
  local gs = GS(p)
  local pcard = card_frame(pane, {"tr-gui.sum-players"})
  local prow = pcard.add{type = "flow", direction = "horizontal"}
  prow.style.horizontal_spacing = 4
  local pnames = {}
  for _, pl in pairs(game.players) do pnames[#pnames + 1] = pl.name end
  table.sort(pnames)
  for _, name in ipairs(pnames) do
    local b = prow.add{type = "button", caption = name, tags = {tr = "sum_card", who = name}, tooltip = {"tr-gui.open-card"}, toggled = gs.sum_card == name}
    b.style.height = 26
    b.style.minimal_width = 0
    b.style.padding = {0, 8, 2, 8}
  end
  if gs.sum_card then
    local cbox = deep_frame(pcard)
    cbox.style.top_margin = 6
    M.fill_card(p, cbox, gs.sum_card, true)
  end
end

local function quiz_card(pane)
  if C.S("tr-s-roulette") then
    local rbox = deep_frame(card_frame(pane, {"tr-gui.sum-roulette"}, {"tr-gui.rou-tip"}))
    local st, a, b = RU.status()
    local caps = {idle = {"tr-gui.rou-idle"}, join = {"tr-gui.rou-join", a, b}, cooldown = {"tr-gui.rou-cd", a},
      fall = {"tr-gui.rou-fall"}, impact = {"tr-gui.rou-fall"}, settle = {"tr-gui.rou-fall"}}
    wrap(rbox.add{type = "label", caption = caps[st] or caps.idle, tags = {tr = "rou_status", st = st}}, W - 90)
    if st == "idle" or st == "join" then
      local rrow = rbox.add{type = "flow", direction = "horizontal"}
      rrow.style.top_margin = 6
      rrow.style.horizontal_spacing = 6
      local rb = rrow.add{type = "button", caption = {st == "idle" and "tr-gui.rou-start" or "tr-gui.rou-in"},
        tags = {tr = st == "idle" and "rou_start" or "rou_in"}}
      rb.style.height = 26
      rb.style.minimal_width = 0
      rb.style.padding = {0, 10, 2, 10}
    end
  end
end

local function mvp_history(p, pane, d)
  local hist = d.mvp_hist or {}
  local open = GS(p).mvp_hist_open
  local hrow = pane.add{type = "flow", direction = "horizontal"}
  hrow.style.vertical_align = "center"
  hrow.style.top_margin = 6
  local hb = hrow.add{type = "button", caption = open and {"tr-gui.mvp-hist-hide"} or {"tr-gui.mvp-hist-show", #hist},
    tags = {tr = "mvp_hist_toggle"}}
  hb.style.height = 22
  hb.style.minimal_width = 0
  hb.style.padding = {0, 8, 2, 8}
  if open then
    local hbox = deep_frame(card_frame(pane, {"tr-gui.mvp-hist-head"}))
    if #hist == 0 then muted(hbox, {"tr-gui.mvp-hist-none"}) end
    for i = #hist, 1, -1 do
      local e = hist[i]
      local names = e.names or {}
      local res
      if e.auto then res = {"tr-gui.mvp-hist-auto", names[1] or "", SH.why_ls(e.why)}
      elseif #names == 0 then res = {"tr-gui.mvp-hist-novotes"}
      elseif #names > 1 then res = {"tr-gui.mvp-hist-tie", C.join(names, ", "), e.n or 0}
      else res = {"tr-gui.mvp-hist-win", names[1], e.n or 0} end
      hbox.add{type = "label", caption = {"", "[color=0.6,0.8,1]", C.clock(e.tick), "[/color]  ", res}}
    end
  end
end

local function fill_summary(p, pane)
  pane.clear()
  intro(p, pane)
  good_to_know(p, pane)
  local d = C.D()
  local sc = scope(p)
  local tbl = sc == "total" and total_with_built(d) or d.shift

  leaders_card(p, pane, tbl)

  planets_card(p, pane, d, sc)

  combat_card(p, pane, d, sc)

  state_card(pane)

  players_card(p, pane)

  quiz_card(pane)

  mvp_block(p, pane)      -- the vote is for the current shift, so it shows under "All time" too

  mvp_history(p, pane, d)
end
U.fill_summary = fill_summary
U.fill_header = fill_header
U.fill_tipbar = fill_tipbar
U.next_tip = next_tip
U.tip_due = tip_due
