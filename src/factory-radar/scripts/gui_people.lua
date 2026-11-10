-- Factory Radar: window: "Who is where", players, titles, journal, records, achievements
local C = require("scripts.core")
local WH = require("scripts.where")
local SH = require("scripts.shift")
local CB = require("scripts.combat")
local TG = require("scripts.tags")
local ZAP = require("scripts.zap")
local U = require("scripts.gui_ui")
local M = U.M
local COLS, GS, W, bar, card_frame, deep_frame, heading, muted = U.COLS, U.GS, U.W, U.bar, U.card_frame, U.deep_frame, U.heading, U.muted
local reset_bar, scope, short_tab, sk, smallbtn, total_with_built, wrap = U.reset_bar, U.scope, U.short_tab, U.sk, U.smallbtn, U.total_with_built, U.wrap

---------------------------------------------------------------- Who is where
-- what the row buttons look like: if it changes, the row must be rebuilt (otherwise only texts and cooldowns move)
function M.where_sig(p, r)
  return table.concat({r.player.index, r.body and "b" or "-", r.look and "l" or "-",
    (C.S("tr-zap") and r.player.connected) and "z" or "-"}, ":")
end
local function fill_where(p, pane)
  pane.clear()
  local rows = WH.rows(p)
  short_tab(pane, #rows <= 10)
  if #rows == 0 then muted(pane, {"tr-gui.why-no-players"}) end
  local box = deep_frame(pane)
  box.style.top_margin = 2
  box.style.bottom_margin = 8
  for _, r in ipairs(rows) do
    local row = box.add{type = "flow", direction = "horizontal", tags = {tr = "where_row", who = r.player.index, sig = M.where_sig(p, r)}}
    row.style.vertical_align = "center"
    row.style.bottom_margin = 3
    local btns = row.add{type = "flow", direction = "horizontal"}
    btns.style.vertical_align = "center"
    btns.style.horizontal_spacing = 0
    btns.style.right_margin = 8
    -- three fixed places in one order (lightning, where, watching): no button means an empty place,
    -- so a button does not jump when "watching" appears
    local function slot() local s = btns.add{type = "flow", direction = "horizontal"}; s.style.width = 17; return s end      -- a mini button 16 wide: one pixel between them
    local zs, bs, ls = slot(), slot(), slot()
    if C.S("tr-zap") and r.player.connected then
      local why = ZAP.blocked(p, r.player)
      local b = smallbtn(zs, M.zap_sprite(), why or {"tr-zap.tip", r.player.name, C.S("tr-s-zap-percent"), C.S("tr-s-zap-cooldown")},
        {tr = "zap", who = r.player.index})
      b.enabled = why == nil
    end
    if r.body then
      smallbtn(bs, "utility/map", {"tr-gui.where-body"}, {tr = "jump", who = r.player.index, what = "body"})
    end
    if r.look then
      smallbtn(ls, "utility/search_icon", {"tr-gui.where-look"}, {tr = "jump", who = r.player.index, what = "look"})
    end
    -- one row per player, no wrapping: who | where and what they do | where they look. What does not fit is cut,
    -- the full text is in the tooltip
    local function col(caption, width, tag, color)
      local l = row.add{type = "label", caption = caption, tooltip = caption, tags = {tr = tag}}
      l.style.width = width
      l.style.single_line = true
      if color then l.style.font_color = color end
      return l
    end
    col(r.head, 250, "where_head")
    col(r.detail, 270, "where_line")
    col(r.look_caption or "", 170, "where_look", {0.6, 0.85, 1})
  end
  muted(pane, {"tr-gui.where-hint"})
end
function M.fill_card(p, pane, name, embedded)  -- player card; the summary shows it too
  local d = C.D()
  local r = C.rec(d.total, name)
  local top = pane.add{type = "flow", direction = "horizontal"}
  top.style.vertical_align = "center"
  top.add{type = "button", caption = embedded and {"tr-gui.card-hide"} or {"tr-gui.back"}, tags = {tr = embedded and "sum_card_hide" or "card_back"}}
  local t = C.shown_title(name)
  top.add{type = "label", caption = {"", "[font=default-large-bold]" .. name .. "[/font]",
    t and {"", "  ", C.title_rich(t)} or ""}}

  heading(pane, {"tr-gui.card-stats"}).tooltip = {"tr-gui.tip-card-total"}
  local g = pane.add{type = "table", column_count = 4}
  g.style.horizontal_spacing = 24
  local cells = {
    {"kills", C.n(r.kills)}, {"built", C.n(r.built)}, {"craft", C.n(r.craft)},
    {"walk", C.km(r.walk)}, {"ride", C.km(r.ride)}, {"mined", C.n(r.mined)}, {"lost", C.n(r.lost)},
    {"ff", C.n(r.ff)}, {"deaths", C.n(r.deaths)}, {"streak", C.n(d.streak[name] or 0)},
    {"best-streak", C.n((d.records.best_streak or {})[name] or 0)}, {"nests", C.n(r.nests)},
    {"defense", C.n(r.defense)}, {"belts", C.n(r.belts)}, {"rails", C.n(r.rails)}, {"poles", C.n(r.poles)},
    {"turrets", C.n(r.turrets)},
  }
  for _, c in ipairs(cells) do
    local l = g.add{type = "label", caption = {"tr-gui.stat-" .. c[1]}}
    l.style.font_color = {0.7, 0.7, 0.7}
    g.add{type = "label", caption = {"", "[font=default-bold]", c[2], "[/font]"}}
  end
  local ticks, fav = C.best_planet_time(name)
  if fav then pane.add{type = "label", caption = {"tr-gui.card-favorite", C.planet_ls(fav), C.time(ticks)}} end

  local pw = CB.top((CB.S().pweap or {})[name], 5)
  heading(pane, {"tr-gui.card-weapons"})
  if #pw == 0 then muted(pane, {"tr-gui.why-no-card-weapons"}) else
    local mx = pw[1][2]
    for _, w in ipairs(pw) do bar(pane, w[2] / mx, {"", C.weapon_ls(w[1]), " - ", C.n(w[2])}, 160) end
  end

  heading(pane, {"tr-gui.card-next"})
  for _, n in ipairs(C.next_titles(name, 4)) do
    bar(pane, n.ratio, {"tr-gui.title-left", C.title_rich(n.t.id), C.title_left(n)}, 240)
  end
  local list = C.titles_of(name)
  heading(pane, {"tr-gui.card-titles", #list})
  local names = {}
  for _, x in ipairs(list) do names[#names + 1] = C.title_name(x.id) end
  wrap(pane.add{type = "label", caption = #names > 0 and C.join(names) or {"tr-gui.why-no-titles"}})

  local k = d.killers[name]
  heading(pane, {"tr-gui.card-killers"})
  if not (k and next(k)) then muted(pane, {"tr-gui.why-no-killers"}) end
  if k and next(k) then
    local arr = {}
    for key, c in pairs(k) do arr[#arr + 1] = {key, c} end
    table.sort(arr, function(a, b) return a[2] > b[2] end)
    local parts = {}
    for i = 1, math.min(8, #arr) do
      local key = arr[i][1]
      parts[#parts + 1] = (key:sub(1, 7) == "player:" and key:sub(8) or ("[entity=" .. key .. "]")) .. " " .. arr[i][2]
    end
    wrap(pane.add{type = "label", caption = table.concat(parts, "    ")})
  end
end

local function fill_players(p, pane)
  pane.clear()
  local gs = GS(p)
  if gs.card then M.fill_card(p, pane, gs.card); return end
  local d = C.D()
  local tbl = scope(p) == "total" and total_with_built(d) or d.shift
  short_tab(pane, #game.players <= 6)
  local pcard = card_frame(pane, {sk(p, "tr-gui.players-scope")})
  muted(pcard, {"tr-gui.players-how"})
  if not next(tbl) then muted(pcard, {sk(p, "tr-gui.why-no-leaders")}) end
  local box = deep_frame(pcard)
  local t = box.add{type = "table", column_count = #COLS + 3, draw_horizontal_lines = true}
  t.style.horizontal_spacing = 4
  t.style.vertical_spacing = 4
  local function centered(lbl, width)
    lbl.style.minimal_width = width
    lbl.style.horizontal_align = "center"
    return lbl
  end
  local hp = t.add{type = "label", caption = {"tr-gui.col-player"}, style = "caption_label"}
  hp.style.minimal_width = 130
  -- headers are flat clickable text (like "Titles" and "Awards"); the sorted one is gold with an arrow
  local function header(key, caption, tip, width)
    local on = gs.sort == key
    local b = t.add{type = "button", style = "list_box_item", caption = {"", caption, on and " ▼" or ""},
      tags = {tr = "sort", key = key}, tooltip = {"", {"tr-gui.sort"}, "\n", tip}}
    b.style.font = "default-bold"
    b.style.font_color = on and {1, 0.85, 0.3} or {1, 0.9, 0.75}
    b.style.minimal_width = width
    b.style.horizontal_align = "center"
    b.style.height = 24
    b.style.padding = {0, 2, 2, 2}
  end
  for _, c in ipairs(COLS) do header(c.key, {"tr-gui.col-" .. c.key}, {"tr-gui.tip-col-" .. c.key}, 66) end
  header("titles", {"tr-gui.col-titles"}, {"tr-gui.tip-col-titles"}, 56)
  header("ach", {"tr-gui.col-ach"}, {"tr-gui.tip-col-ach"}, 56)
  local names = {}
  local counts = {}
  if gs.sort == "titles" or gs.sort == "ach" then
    for _, pl in pairs(game.players) do
      local n = 0
      if gs.sort == "titles" then n = #C.titles_of(pl.name) else for _ in pairs(d.ach[pl.name] or {}) do n = n + 1 end end
      counts[pl.name] = n
      names[#names + 1] = pl.name
    end
    table.sort(names, function(a, b) if counts[a] ~= counts[b] then return counts[a] > counts[b] end return a < b end)
  else
    names = C.sorted_names(tbl, gs.sort)
    for _, pl in pairs(game.players) do if not tbl[pl.name] then names[#names + 1] = pl.name end end
  end
  local best = {}
  for _, c in ipairs(COLS) do best[c.key] = C.leader(tbl, c.key) end
  for _, name in ipairs(names) do
    local r = tbl[name] or C.blank()
    local nb = t.add{type = "button", style = "list_box_item", caption = {"", name == p.name and "[color=1,0.85,0.3]" or "", name, name == p.name and "[/color]" or ""},
      tags = {tr = "card", who = name}, tooltip = {"tr-gui.open-card"}}
    nb.style.font = "default-bold"
    nb.style.height = 26
    nb.style.minimal_width = 130
    nb.style.horizontal_align = "left"
    nb.style.padding = {0, 6, 2, 6}
    for _, c in ipairs(COLS) do
      local v = r[c.key] or 0
      local cap = c.f(v)
      if best[c.key] == name and v > 0 then cap = {"", "[color=1,0.85,0.3]", cap, "[/color]"} end
      centered(t.add{type = "label", caption = cap, tooltip = {"tr-gui.tip-col-" .. c.key}}, 66)
    end
    local nt = #C.titles_of(name)
    local na = 0
    for _ in pairs(d.ach[name] or {}) do na = na + 1 end
    centered(t.add{type = "label", caption = C.n(nt)}, 56)
    centered(t.add{type = "label", caption = C.n(na)}, 56)
  end
  reset_bar(p, pane, "players")
end
local function tag_card(p, pane)
  local st = TG.T(p)
  local box = card_frame(pane, {"tr-gui.tag-head"})
  local row = box.add{type = "flow", direction = "horizontal"}
  row.style.vertical_align = "center"
  row.add{type = "checkbox", name = "tr_tag_on", state = st.on, caption = {"tr-gui.tag-on"}}
  local items, ids, sel = {{"tr-gui.tag-auto"}}, {"auto"}, 1
  for _, x in ipairs(C.titles_of(p.name)) do
    items[#items + 1] = C.title_name(x.id)
    ids[#ids + 1] = x.id
    if x.id == st.id then sel = #ids end
  end
  local dd = row.add{type = "drop-down", name = "tr_tag_pick", items = items, selected_index = sel, tags = {ids = ids}}
  dd.style.left_margin = 12
  dd.style.width = 260
  dd.enabled = st.on and #ids > 1
  local cb = box.add{type = "checkbox", state = C.P(p, "tag-color") and true or false, caption = {"tr-gui.tag-color"},
    tooltip = {"tr-gui.tip-tag-color"}, tags = {tr = "pcfg", key = "tag-color", retag = true}}
  cb.style.top_margin = 4
  cb.style.bottom_margin = 6
  local pv = deep_frame(box)
  local cur = TG.current(p)
  muted(pv, cur and {"tr-gui.tag-preview", p.name, C.title_rich_tag(cur)} or {"tr-gui.tag-none"})
  local ct = cur and C.title_by_id(cur)
  if ct then muted(pv, {"tr-gui.title-why", C.title_reason(ct)}) end
  if ct and ct.planet then muted(pv, {"tr-gui.tag-planet-note"}) end
end

local function team_titles(pane)
  local tbox = deep_frame(card_frame(pane, {"tr-gui.titles-team"}))
  local names = {}
  for _, pl in pairs(game.players) do names[#names + 1] = pl.name end
  table.sort(names)
  for _, name in ipairs(names) do
    local list = C.titles_of(name)
    local tt = {}
    local why = {""}
    for _, x in ipairs(list) do
      tt[#tt + 1] = C.title_rich(x.id)
      local t = C.title_by_id(x.id)
      if t then why[#why + 1] = {"", "\n", C.title_rich(x.id), " - ", C.title_reason(t)}; if #why >= 18 then why = {"", why} end end
    end
    local l = wrap(tbox.add{type = "label", caption = {"", "[font=default-bold]" .. name .. "[/font] (" .. #tt .. "): ",
      #tt > 0 and C.join(tt) or {"tr-gui.none"}}, tooltip = #tt > 0 and {"", {"tr-gui.tip-titles-why"}, why} or nil}, W - 90)
    l.style.bottom_margin = 3
  end
end

local function all_titles(p, pane)
  local tlist = C.titles()
  local have = 0
  for _, t in ipairs(tlist) do if (C.D().titles[p.name] or {})[t.id] then have = have + 1 end end
  local got = C.D().titles[p.name] or {}
  local tt = deep_frame(card_frame(pane, {"tr-gui.titles-all", have, #tlist})).add{type = "table", column_count = 2}
  tt.style.horizontal_spacing = 16
  tt.style.vertical_spacing = 3
  for _, t in ipairs(tlist) do
    local ok = got[t.id]
    local a = tt.add{type = "label", caption = ok and {"", "✓ ", C.title_rich(t.id)} or {"", "[color=0.55,0.55,0.55]· ", C.title_name(t.id), "[/color]"}}
    a.style.minimal_width = 230
    local b = wrap(tt.add{type = "label", caption = C.title_reason(t)}, W - 330)
    b.style.font_color = ok and {0.8, 0.8, 0.8} or {0.5, 0.5, 0.5}
  end
end

local function fill_titles(p, pane)
  pane.clear()
  if C.S("tr-chat-titles") then tag_card(p, pane) end
  -- my titles: what they were granted for
  local mine = C.titles_of(p.name)
  local mc = card_frame(pane, {"tr-gui.titles-mine", #mine})
  if #mine == 0 then muted(deep_frame(mc), {"tr-gui.titles-mine-none"}) else
    local mt = deep_frame(mc).add{type = "table", column_count = 2}
    mt.style.horizontal_spacing = 16
    mt.style.vertical_spacing = 4
    for _, x in ipairs(mine) do
      local t = C.title_by_id(x.id)
      local a = mt.add{type = "label", caption = C.title_rich(x.id)}
      a.style.minimal_width = 230
      local b = wrap(mt.add{type = "label", caption = t and C.title_reason(t) or ""}, W - 330)
      b.style.font_color = {0.8, 0.8, 0.8}
    end
  end
  -- team
  team_titles(pane)
  -- closest to being earned
  local nbox = deep_frame(card_frame(pane, {"tr-gui.titles-next"}))
  for _, n in ipairs(C.next_titles(p.name, 5)) do
    local br = bar(nbox, n.ratio, {"tr-gui.title-left", C.title_rich(n.t.id), C.title_left(n)}, 240, C.title_reason(n.t))
    br.style.bottom_margin = 3
  end
  -- all
  all_titles(p, pane)

  reset_bar(p, pane, "titles")
end

local function fill_journal(p, pane)
  pane.clear()
  local j = C.D().journal
  short_tab(pane, #j <= 10)
  if #j == 0 then muted(pane, {"tr-gui.why-no-journal"}); reset_bar(p, pane, "journal") return end
  local t = deep_frame(card_frame(pane, {"tr-gui.tab-journal"})).add{type = "table", column_count = 2}
  t.style.horizontal_spacing = 10
  t.style.vertical_spacing = 3
  for i = #j, math.max(1, #j - 39), -1 do
    local e = j[i]
    local tl = t.add{type = "label", caption = {"", "[color=0.6,0.8,1]", C.clock(e.tick), "[/color]"}}
    tl.style.minimal_width = 52
    tl.style.vertical_align = "top"
    wrap(t.add{type = "label", caption = C.journal_view(e.text)}, W - 130)
  end
  muted(pane, {"tr-gui.journal-hint"})
  reset_bar(p, pane, "journal")
end

local function fill_records(p, pane)
  pane.clear()
  local d = C.D()
  local R = d.records
  local any = false
  local nrec = 0
  for _ in pairs(R) do nrec = nrec + 1 end
  short_tab(pane, nrec <= 6)
  muted(pane, {"tr-gui.rec-intro"})
  local rbox = deep_frame(card_frame(pane, {"tr-gui.tab-records"}))
  local function line(caption)
    any = true
    local l = wrap(rbox.add{type = "label", caption = caption}, W - 90)
    l.style.bottom_margin = 3
  end
  local who, n = nil, 0
  for name, v in pairs(R.best_streak or {}) do if v > n then who, n = name, v end end
  if who then line({"tr-gui.rec-streak", who, C.n(n)}) end
  if R.shift_kills and R.shift_kills.who then line({"tr-gui.rec-shift-kills", R.shift_kills.who, C.n(R.shift_kills.n)}) end
  if R.shift_built and R.shift_built.who then line({"tr-gui.rec-shift-built", R.shift_built.who, C.n(R.shift_built.n)}) end
  if R.shift_deaths and R.shift_deaths.who then line({"tr-gui.rec-shift-deaths", R.shift_deaths.who, R.shift_deaths.n}) end
  if R.shift_lost and R.shift_lost.n > 0 then line({"tr-gui.rec-shift-lost", C.n(R.shift_lost.n)}) end
  if R.planet_shift and R.planet_shift.planet then line({"tr-gui.rec-planet", C.planet_ls(R.planet_shift.planet), C.n(R.planet_shift.n)}) end
  local rs = d.research
  if (rs.total_levels or 0) > 0 then line({"tr-gui.rec-infinite", rs.total_levels}) end
  if not any then muted(rbox, {"tr-gui.why-no-records", SH.minutes_left()}) end
  local lbox = deep_frame(card_frame(pane, {sk(p, "tr-gui.sum-leaders")}))
  local tbl = scope(p) == "total" and d.total or d.shift
  local anyl = false
  for _, c in ipairs({{"kills", C.n}, {"built", C.n}, {"walk", C.km}, {"ride", C.km}, {"mined", C.n}, {"deaths", C.n}}) do
    local w, v = C.leader(tbl, c[1])
    if w then
      anyl = true
      local l = lbox.add{type = "label", caption = {"tr-gui.rec-leader", {"tr-gui.col-" .. c[1]}, w, c[2](v)}}
      l.style.bottom_margin = 3
    end
  end
  if not anyl then muted(lbox, {sk(p, "tr-gui.why-no-leaders")}) end
  reset_bar(p, pane, "records")
end

---------------------------------------------------------------- Team: achievements (personal and team)
local function fill_achievements(p, pane)
  pane.clear()
  local d = C.D()
  local got = d.ach[p.name] or {}
  local n = 0
  for _ in pairs(got) do n = n + 1 end
  muted(pane, {"tr-gui.ach-note"})
  local t = deep_frame(card_frame(pane, {"tr-gui.ach-mine", n, #C.ACH})).add{type = "table", column_count = 3}
  t.style.horizontal_spacing = 16
  t.style.vertical_spacing = 5
  for _, a in ipairs(C.ACH) do
    local ok = got[a.id]
    local l = t.add{type = "label", caption = {"", ok and "[color=0.6,1,0.6]✓ " or "[color=0.55,0.55,0.55]· ", {"tr-ach." .. a.id}, "[/color]"},
      tooltip = {"tr-ach." .. a.id .. "-tip"}}
    l.style.minimal_width = 190
    -- what it was granted for is always visible
    local why = t.add{type = "label", caption = {"tr-ach." .. a.id .. "-tip"}}
    why.style.single_line = false
    why.style.maximal_width = 300
    why.style.font_color = ok and {0.8, 0.8, 0.8} or {0.55, 0.55, 0.55}
    if ok then
      t.add{type = "label", caption = {"tr-gui.ach-when", C.clock(ok)}}.style.font_color = {0.7, 0.7, 0.7}
    else
      local v = C.title_value(p.name, a.key)
      bar(t, math.min(1, v / a.n), {"tr-gui.of", C.fmt_amount(a.key, math.floor(math.min(v, a.n))), C.fmt_amount(a.key, a.n)}, 120,
        {"tr-ach." .. a.id .. "-tip"})
    end
  end
  local obox = deep_frame(card_frame(pane, {"tr-gui.ach-others"}))
  local names = {}
  for _, pl in pairs(game.players) do names[#names + 1] = pl.name end
  table.sort(names)
  for _, name in ipairs(names) do
    local c = 0
    local tip = {"", {"tr-gui.tip-ach-list"}}
    for _, a in ipairs(C.ACH) do
      if (d.ach[name] or {})[a.id] then
        c = c + 1
        tip[#tip + 1] = {"", "\n[color=0.6,1,0.6]✓[/color] ", {"tr-ach." .. a.id}, " - ", {"tr-ach." .. a.id .. "-tip"}}
        if #tip >= 18 then tip = {"", tip} end
      end
    end
    local br = bar(obox, c / #C.ACH, {"", "[font=default-bold]" .. name .. "[/font]  ", {"tr-gui.of", c, #C.ACH}}, 160, c > 0 and tip or nil)
    br.style.bottom_margin = 3
  end
  local tbox = deep_frame(card_frame(pane, {"tr-gui.titles-team"}))
  local tgot = 0
  for _, a in ipairs(C.TEAM) do if d.team_seen[a.key .. a.n] then tgot = tgot + 1 end end
  local tb = bar(tbox, tgot / #C.TEAM, {"tr-gui.of", tgot, #C.TEAM}, 240)
  tb.style.bottom_margin = 6
  for _, a in ipairs(C.TEAM) do
    local ok = d.team_seen[a.key .. a.n]
    local l = wrap(tbox.add{type = "label", caption = {"", ok and "[color=0.6,1,0.6]✓ " or "[color=0.55,0.55,0.55]· ", C.team_text(a), "[/color]"}})
    l.style.bottom_margin = 2
  end
  reset_bar(p, pane, "achievements")
end
U.fill_journal = fill_journal
U.fill_titles = fill_titles
U.fill_where = fill_where
U.fill_achievements = fill_achievements
U.fill_records = fill_records
U.fill_players = fill_players
