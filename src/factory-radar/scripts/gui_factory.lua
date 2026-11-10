-- Factory Radar: window: quality and power grids
local C = require("scripts.core")
local QL = require("scripts.quality")
local EN = require("scripts.energy")
local U = require("scripts.gui_ui")
local GS, W, card_frame, deep_frame, muted, reset_bar, wrap = U.GS, U.W, U.card_frame, U.deep_frame, U.muted, U.reset_bar, U.wrap
local function dur(...) return U.dur(...) end
local function filter_button(...) return U.filter_button(...) end
local function hidden_planets(...) return U.hidden_planets(...) end
local function planet_entries(...) return U.planet_entries(...) end

---------------------------------------------------------------- Factory: quality
local QCATS = {"all", "buildings", "modules", "intermediate"}
local function gs_q_window(p) return GS(p).q_window == 60 and 60 or 10 end
local function quality_filter_row(p, pane, cat, hidden, show_hidden)
  local row = pane.add{type = "flow", direction = "horizontal"}
  row.style.vertical_align = "center"
  row.add{type = "label", caption = {"tr-q.filter"}, tooltip = {"tr-q.hint"}}
  local items, sel = {}, 1
  for i, c in ipairs(QCATS) do items[i] = {"tr-q.cat-" .. c}; if c == cat then sel = i end end
  row.add{type = "drop-down", items = items, selected_index = sel, tags = {tr = "q_cat"}}
  local win = gs_q_window(p)
  local wl = row.add{type = "label", caption = {"tr-q.window-pick"}}
  wl.style.left_margin = 12
  row.add{type = "drop-down", items = {{"tr-q.win-10"}, {"tr-q.win-60"}}, selected_index = win == 60 and 2 or 1, tags = {tr = "q_window"}}
  local nh = 0
  for _ in pairs(hidden) do nh = nh + 1 end
  if nh > 0 then
    row.add{type = "button", caption = show_hidden and {"tr-q.hide-hidden"} or {"tr-q.show-hidden", nh}, tags = {tr = "q_showhidden"}}
  end
  row.style.horizontally_stretchable = true
  filter_button(p, row, "q", planet_entries())
end

local function quality_card(p, pane, s, cat, hidden, show_hidden, quals)
  local key = C.key(s)
  local rows, minutes = nil, 0
  if not hidden_planets(p, "q")[key] then rows, minutes = QL.planet_rows(key, gs_q_window(p)) end
  local shown = {}
  for _, r in ipairs(rows or {}) do
    local hid = hidden[r.item]
    if prototypes.item[r.item] and (cat == "all" or QL.category(r.item) == cat) and (not hid or show_hidden) then shown[#shown + 1] = r end
  end
  if #shown > 0 then
    local card = card_frame(pane, {"", C.planet_ls(key), minutes > 0 and {"tr-q.window", math.floor(minutes + 0.5)} or ""})
    -- the first five; the button under the planet name shows all
    local unfolded = (GS(p).q_lim or {})[key]
    local limit = unfolded and #shown or math.min(5, #shown)
    if #shown > 5 then
      local crow = card.add{type = "flow", direction = "horizontal"}
      crow.style.bottom_margin = 4
      crow.style.vertical_align = "center"
      local cb = crow.add{type = "button", caption = unfolded and {"tr-q.show-5"} or {"tr-q.show-all", #shown},
        tags = {tr = "q_all", planet = key}, tooltip = {"tr-q.show-all-tip"}}
      cb.style.height = 22
      cb.style.minimal_width = 0
      cb.style.padding = {0, 8, 2, 8}
    end
    local t = deep_frame(card).add{type = "table", column_count = 1 + #quals}
    t.style.horizontal_spacing = 8
    for i = 2, 1 + #quals do t.style.column_alignments[i] = "center" end
    local function qcell(lbl) lbl.style.minimal_width = 48; lbl.style.horizontal_align = "center"; return lbl end
    t.add{type = "label", caption = {"tr-q.col-item"}, style = "caption_label"}
    for _, q in ipairs(quals) do
      qcell(t.add{type = "label", caption = "[img=quality/" .. q.name .. "]", tooltip = prototypes.quality[q.name].localised_name})
    end
    for i = 1, limit do
      local r = shown[i]
      local it = prototypes.item[r.item]
      local cell = t.add{type = "flow", direction = "horizontal"}
      cell.style.vertical_align = "center"
      local b = cell.add{type = "sprite-button", sprite = "item/" .. r.item, style = "slot_button",
        tags = {tr = "q_hide", item = r.item}, tooltip = {hidden[r.item] and "tr-q.tip-unhide" or "tr-q.tip-hide"}}
      b.style.width = 28
      b.style.height = 28
      wrap(cell.add{type = "label", caption = it and it.localised_name or r.item}, 190)
      for _, q in ipairs(quals) do
        local v = r.q[q.name]
        if v and (v.rate > 0 or v.total > 0) then
          qcell(t.add{type = "label", caption = v.rate > 0 and {"tr-q.rate", string.format(v.rate >= 10 and "%.0f" or "%.1f", v.rate)} or
            {"", "[color=0.55,0.55,0.55]", C.n(v.total), "[/color]"},
            tooltip = {"tr-q.tip-cell", C.big(v.total), string.format("%.2f", v.rate), math.floor(minutes + 0.5)}})
        else
          qcell(t.add{type = "label", caption = "[color=0.4,0.4,0.4]-[/color]"})
        end
      end
    end
  end
  return #shown > 0
end

-- alarm strip for power grids: red when there is no power or not enough, yellow at the limit or when an outage was
-- recently (up to 5 minutes ago). If all is well there is none. It stands above the sub-tabs of the "Factory" group, so it shows in
-- "Factory" itself and in "Power grids" (and its other tabs)
local function fill_quality(p, pane)
  pane.clear()
  local quals = QL.qualities()
  if #quals == 0 then muted(pane, {"tr-q.no-quality"}) return end
  local cat = C.P(p, "q-cat") or "all"
  local hidden = C.P(p, "q-hide") or {}
  local show_hidden = GS(p).q_show_hidden
  quality_filter_row(p, pane, cat, hidden, show_hidden)
  local any = false
  for _, s in ipairs((function() local o = {} for _, ss in pairs(game.surfaces) do if C.RP(ss) then o[#o + 1] = ss end end table.sort(o, function(a, b) return a.name < b.name end) return o end)()) do
    if quality_card(p, pane, s, cat, hidden, show_hidden, quals) then any = true end
  end
  if not any then muted(pane, {"tr-q.none-anywhere"}) end
  reset_bar(p, pane, "quality")
end

---------------------------------------------------------------- Factory: energy

-- Power grids: each planet with a net in one table (state is the fast check of the last second, numbers are the
-- last sample, up to ~20 s old); below is the journal of the last 10 outages of all planets, new on top, with game
-- time and probable causes. The window is redrawn at once when an outage starts or ends
local function energy_chip(r)
  local h, an = r.h, r.an
  local cur = h and h.short
  if r.cur_known then cur = r.cur end       -- the fast check knows better than a sample
  if not h and not cur then return {"tr-en.chip-wait"}
  elseif cur == "none" then return {"tr-en.chip-out"}
  elseif cur then return {"tr-en.chip-low"}
  elseif an and an.score >= 1 then
    local k = an.reasons[1] and type(an.reasons[1]) == "table" and an.reasons[1][1] or ""
    local chip = (k:find("fuel%-low") and "chip-r-fuellow") or (k:find("nofuel") or k:find("nofluid")) and "chip-r-fuel"
      or (k:find("trend") and "chip-r-trend") or (k:find("night") and "chip-r-night")
      or (k:find("demand") and "chip-r-demand") or (k:find("acc") and "chip-r-acc")
      or (k:find("jump") and "chip-r-jump") or (k:find("drop") and "chip-r-drop") or "chip-risk"
    return {"tr-en." .. chip}
  elseif an and an.idle then return {"tr-en.chip-idle"} end
  return {"tr-en.chip-ok"}
end

local function plat_chip(r)
  if r.kind == "none" then return {"tr-en.chip-out"}
  elseif r.kind == "low" then return {"tr-en.chip-low"}
  elseif r.kind == "empty" then return {"tr-en.chip-empty"} end
  local k = r.reasons[1] and type(r.reasons[1]) == "table" and r.reasons[1][1] or ""
  if r.score >= 2 then return {k:find("nosrc") and "tr-en.chip-nosrc" or "tr-en.chip-low"} end
  if r.score >= 1 then
    return {(k:find("fuel%-low") and "tr-en.chip-r-fuellow") or (k:find("trend") and "tr-en.chip-r-trend")
      or (k:find("acc") and "tr-en.chip-r-acc") or "tr-en.chip-r-demand"}
  end
  return {"tr-en.chip-ok"}
end

local function energy_load(parent, r, width)
  local h = r.h
  if not h then
    parent.add{type = "empty-widget"}
    parent.add{type = "empty-widget"}
    return
  end
  local capw = math.max(h.capw or 0, h.prod)
  local load = capw > 0 and math.min(1, h.cons / capw) or (h.cons > 0 and 1 or 0)
  local lb = parent.add{type = "progressbar", value = load, tooltip = {"tr-en.tip-load", EN.power(h.cons), EN.power(capw), math.floor(load * 100)}}
  lb.style.width = width
  local cur = h.short
  if r.cur_known then cur = r.cur end
  if cur then lb.style.color = {1, 0.45, 0.35} end
  parent.add{type = "label", caption = {"tr-en.flow2", EN.power(h.cons), EN.power(capw)}, tooltip = {"tr-en.tip-flow2", EN.power(h.prod)}}
end

-- accumulator charge as a blue bar with numbers beside it
local function acc_bar(parent, h, width)
  if not h or (h.cap or 0) <= 0 then return nil end
  local pct = math.floor(h.stored / h.cap * 100)
  -- what such a stock gives: how many accumulators and how long the charge lasts at the current consumption
  local runtime = (h.cons or 0) > 1e4 and {"tr-en.acc-runtime", dur(h.stored / h.cons * 60)} or {"tr-en.acc-runtime0"}
  local tip = {"tr-en.tip-acc4", pct, EN.energy(h.stored), EN.energy(h.cap), EN.power(h.acc_in), EN.power(h.acc_out),
    h.acc_n or "?", runtime}
  local row = parent.add{type = "flow", direction = "horizontal"}
  row.style.vertical_align = "center"
  local pb = row.add{type = "progressbar", value = math.max(0, math.min(1, h.stored / h.cap)), tooltip = tip}
  pb.style.width = width or 90
  pb.style.color = {0.4, 0.75, 1}
  local l = row.add{type = "label", caption = {"tr-en.acc3", pct, EN.energy(h.stored), EN.energy(h.cap)}, tooltip = tip}
  l.style.left_margin = 6
  return row
end

-- three biggest sources or consumers of a planet: "icon xN power"
local function energy_top3(h, by, total)
  local arr = {}
  for name, w in pairs(by or {}) do
    if w > 0 and w >= (total or 0) * 0.02 and prototypes.entity[name] then arr[#arr + 1] = {name, w} end
  end
  table.sort(arr, function(a, b) return a[2] > b[2] end)
  local parts = {}
  for i = 1, math.min(3, #arr) do
    local cnt = (h.cnt or {})[arr[i][1]]
    parts[#parts + 1] = {"tr-en.item", "[entity=" .. arr[i][1] .. "]", cnt and C.n(cnt) or "?", EN.power(arr[i][2])}
  end
  if #parts == 0 then return nil end
  return C.join(parts, "    ")
end

-- one journal entry: general on top (status, planet, when, how long), with full the explanation below (what probably happened)
local function energy_entry(parent, e, full)
  local warn = (e.level or "red") == "warn"
  local col = warn and "1,0.8,0.4" or (e.kind == "none" and "1,0.45,0.4" or "1,0.65,0.4")
  local head = {"", "[font=default-bold]", e.plat and {"", "[img=entity/space-platform-hub] ", e.plat} or C.planet_ls(e.key), "[/font]  [color=" .. col .. "]",
    {"tr-en.kindn-" .. e.kind}, "[/color]",
    e.done and {"tr-en.log-ago", dur(game.tick - (e.last or game.tick))} or {"tr-en.log-now"}}
  local hl = wrap(parent.add{type = "label", caption = head}, W - 110)
  hl.style.top_margin = 3
  -- when and how long: exact game time of start and end, duration, repeats
  local when = e.done and {"tr-en.log-when", C.clock_s(e.start), C.clock_s(e.last or e.start), dur(EN.duration(e))}
    or {"tr-en.log-when-now", C.clock_s(e.start), dur(EN.duration(e))}
  local wl = wrap(parent.add{type = "label", caption = {"", when, (e.n or 1) > 1 and {"tr-en.log-repeat", e.n} or ""}}, W - 110)
  wl.style.font_color = {0.8, 0.8, 0.8}
  if not full then return end
  -- what was missing: how long there was no power at all, how long it was just short
  if not warn and ((e.t_none or 0) > 0 or (e.t_low or 0) > 0) then
    local parts = {}
    if (e.t_none or 0) > 0 then parts[#parts + 1] = {"tr-en.log-t-none", dur(e.t_none)} end
    if (e.t_low or 0) > 0 then parts[#parts + 1] = {"tr-en.log-t-low", dur(e.t_low)} end
    local ll = wrap(parent.add{type = "label", caption = C.join(parts, " · ")}, W - 110)
    ll.style.font_color = {0.8, 0.8, 0.8}
  end
  if not warn and (e.share or 0) > 0 then
    local shl = wrap(parent.add{type = "label", caption = {"tr-en.log-share", math.floor(e.share * 100 + 0.5)}}, W - 110)
    shl.style.font_color = {0.8, 0.8, 0.8}
  end
  if e.cons and e.prod then
    local nl = wrap(parent.add{type = "label", caption = {"tr-en.log-load", EN.power(e.cons), EN.power(e.prod)}}, W - 110)
    nl.style.font_color = {0.8, 0.8, 0.8}
  end
  -- explanation
  local sh = parent.add{type = "label", caption = {e.done and "tr-en.log-why-head-past" or "tr-en.log-why-head"}}
  sh.style.font_color = {1, 0.9, 0.6}
  sh.style.top_margin = 2
  if e.why and #e.why > 0 then
    for _, line in ipairs(e.why) do
      -- a finished outage is in past tense: key "key-past"
      local shown = line
      if e.done and type(line) == "table" and type(line[1]) == "string" then
        shown = {line[1] .. "-past"}
        for i = 2, #line do shown[i] = line[i] end
      end
      local wl2 = wrap(parent.add{type = "label", caption = {"", "  · ", shown}}, W - 110)
      wl2.style.font_color = {0.85, 0.85, 0.85}
    end
  else
    local wl3 = wrap(parent.add{type = "label", caption = {"", "  · ", {e.done and "tr-en.why-unknown-past" or "tr-en.why-unknown"}}}, W - 110)
    wl3.style.font_color = {0.65, 0.65, 0.65}
  end
end

local function grids_table(pane, rows)
  local t = deep_frame(card_frame(pane, {"tr-en.grids-head"}, {"tr-en.tip-grids"})).add{type = "table", column_count = 4}
  t.style.horizontal_spacing = 12
  t.style.vertical_spacing = 6
  for _, r in ipairs(rows) do
    local h, an = r.h, r.an
    local tip = nil
    if an.score >= 1 and #an.reasons > 0 then
      tip = {"", {"tr-en.chip-tip-head"}}
      for _, line in ipairs(an.reasons) do tip[#tip + 1] = {"", "\n· ", line} end
    end
    if an.idle then tip = {"", {"tr-en.idle-tip"}} end
    if #(an.notes or {}) > 0 then
      tip = tip or {""}
      for _, note in ipairs(an.notes) do tip[#tip + 1] = {"", "\n", note} end
    end
    if h then
      local prod, cons = energy_top3(h, h.by_prod, h.prod), energy_top3(h, h.by_cons, h.cons)
      if prod or cons then
        tip = tip or {""}
        if prod then tip[#tip + 1] = {"", "\n", {"tr-en.prod3", prod}} end
        if cons then tip[#tip + 1] = {"", "\n", {"tr-en.cons3", cons}} end
      end
    end
    local nl = t.add{type = "label", caption = {"", C.planet_ls(r.key), " ", energy_chip(r)}, tooltip = tip}
    nl.style.minimal_width = 230
    energy_load(t, r, 120)
    if not acc_bar(t, h, 80) then t.add{type = "empty-widget"} end
end
end

local function platform_grids(pane)
  local prows = EN.plat_rows()
  if #prows > 0 then
    local pt = deep_frame(card_frame(pane, {"tr-en.plat-head"}, {"tr-en.plat-tip"})).add{type = "table", column_count = 4}
    pt.style.horizontal_spacing = 12
    pt.style.vertical_spacing = 6
    for _, r in ipairs(prows) do
      local h = r.h
      local tip = {""}
      if #r.reasons > 0 then
        tip[#tip + 1] = {"tr-en.chip-tip-head"}
        for _, line in ipairs(r.reasons) do tip[#tip + 1] = {"", "\n· ", line} end
        tip[#tip + 1] = "\n"
      end
      tip[#tip + 1] = {"tr-en.plat-tip-nums", EN.power(h.capw), EN.power(h.maxc), EN.power(h.cons), h.src_n or 0, h.acc_n or 0}
      for _, note in ipairs(r.notes or {}) do tip[#tip + 1] = {"", "\n", note} end
      local nl = pt.add{type = "label", caption = {"", "[img=entity/space-platform-hub] ", r.name, " ", plat_chip(r)}, tooltip = tip}
      nl.style.minimal_width = 230
      energy_load(pt, r, 120)
      if not acc_bar(pt, h, 80) then pt.add{type = "label", caption = {"tr-en.plat-no-acc"}}.style.font_color = {0.6, 0.6, 0.6} end
    end
  end
end

local function outage_log(pane, gs)
  local log = EN.log()
  local lcard = card_frame(pane, {"tr-en.log-head"}, {"tr-en.tip-log"})
  local lbox = deep_frame(lcard)
  if #log == 0 then muted(lbox, {"tr-en.log-none"}) else
    local open = gs.en_log_open
    -- general on top: how many entries, how many red and yellow, how long in total without normal power
    local nred, nwarn, tred = 0, 0, 0
    for _, e in ipairs(log) do
      if (e.level or "red") == "warn" then nwarn = nwarn + 1 else nred = nred + 1; tred = tred + EN.duration(e) end
    end
    if open then
      local sl = wrap(lbox.add{type = "label", caption = {"tr-en.log-summary", nred, nwarn, dur(tred)}}, W - 110)
      sl.style.font_color = {1, 0.9, 0.6}
      for i, e in ipairs(log) do
        if i > 1 then
          local sep = lbox.add{type = "line", direction = "horizontal"}
          sep.style.top_margin = 6
          sep.style.bottom_margin = 3
        end
        energy_entry(lbox, e, true)
      end
    else
      energy_entry(lbox, log[1], false)
    end
    local tb = lbox.add{type = "button", caption = open and {"tr-en.log-hide"} or {"tr-en.log-show", #log},
      tags = {tr = "en_log_toggle"}}
    tb.style.height = 24
    tb.style.minimal_width = 0
    tb.style.padding = {0, 8, 2, 8}
    tb.style.top_margin = 6
  end
end

local function fill_energy(p, pane)
  pane.clear()
  local gs = GS(p)
  local hrow = pane.add{type = "flow", direction = "horizontal"}
  hrow.style.vertical_align = "center"
  hrow.style.horizontally_stretchable = true
  hrow.style.bottom_margin = 4
  hrow.add{type = "label", caption = {"tr-gui.tab-energy"}, style = "caption_label"}
  filter_button(p, hrow, "e", planet_entries())
  local hid = hidden_planets(p, "e")
  local rows = {}
  for _, r in ipairs(EN.rows()) do
    if r.nets > 0 and not hid[r.key] then
      r.an = EN.analyze(r)
      rows[#rows + 1] = r
    end
  end
  if #rows == 0 then muted(pane, {"tr-en.none-anywhere"}) end
  -- worst first, then the biggest consumers
  table.sort(rows, function(a, b)
    if a.an.score ~= b.an.score then return a.an.score > b.an.score end
    return (a.h and a.h.cons or 0) > (b.h and b.h.cons or 0)
  end)
  if #rows > 0 then
    grids_table(pane, rows)
  end

  -- space platforms: own small net, charge and peak load
  platform_grids(pane)

  -- journal: collapsed is one line, expanded is every entry with causes
  outage_log(pane, gs)
  muted(pane, {"tr-en.hint3"})
  gs.en_sig = EN.sig()
  reset_bar(p, pane, "energy")
end
U.fill_quality = fill_quality
U.fill_energy = fill_energy
U.QCATS = QCATS
