-- Factory Radar: window: space platforms
local C = require("scripts.core")
local PF = require("scripts.platforms")
local U = require("scripts.gui_ui")
local M = U.M
local FIT, GS, W, bar, card_frame, deep_frame, muted, reset_bar = U.FIT, U.GS, U.W, U.bar, U.card_frame, U.deep_frame, U.muted, U.reset_bar
local short_tab, wrap = U.short_tab, U.wrap
local function filter_button(...) return U.filter_button(...) end

---------------------------------------------------------------- Space: platforms
local STATE_COL = {on_the_path = "0.5,0.85,1", waiting_at_station = "0.6,1,0.6", waiting_for_departure = "0.6,1,0.6",
  paused = "1,0.8,0.4", no_path = "1,0.5,0.4", no_schedule = "0.7,0.7,0.7"}
local function state_chip(state)
  return {"", "[color=" .. (STATE_COL[state] or "0.8,0.8,0.8") .. "]", {"tr-plat.state-" .. state}, "[/color]"}
end
local function item_rich(it)
  local q = it.quality and it.quality ~= "normal" and (",quality=" .. it.quality) or ""
  return "[item=" .. it.name .. q .. "]"
end

-- "3 min 12 s" for short times, hours from one hour
local function dur(ticks)
  local sec = math.floor((ticks or 0) / 60)
  if sec < 60 then return {"tr-plat.dur-s", sec} end
  if sec < 3600 then return {"tr-plat.dur-ms", math.floor(sec / 60), sec % 60} end
  return C.time(ticks)
end
local function speed_txt(v)
  return v and {"tr-plat.speed", string.format(v >= 10 and "%.0f" or "%.1f", v)} or "-"
end
local function km_txt(km)
  return {"tr-plat.km", C.big(math.floor((km or 0) + 0.5))}
end
local function place_icon(name) return "[img=space-location/" .. name .. "]" end
-- the current flight in one line: time, average speed, km covered
local function flight_caption(r)
  local f = PF.flight(r)
  if not f then return nil end
  -- length of the whole path: all links of the route (covered, current, left)
  local total = f.route_km
  local hops = PF.route(r)
  if hops then
    total = 0
    for _, h in ipairs(hops) do total = total + (h.len or 0) end
  end
  return {"tr-plat.fl-now", dur(f.elapsed), speed_txt(f.speed), km_txt(total)}
end
-- tooltip of a route jump: length, and for covered ones time and average speed
local function hop_tip(h)
  local tip = {"", {"tr-plat.hop-name", place_icon(h.from), place_icon(h.to), h.len and km_txt(h.len) or "?"}}
  if h.kind == "done" and h.ticks then
    tip[#tip + 1] = {"", "\n", {"tr-plat.hop-done", dur(h.ticks), speed_txt(h.speed)}}
  elseif h.kind == "cur" and h.ticks then
    tip[#tip + 1] = {"", "\n", {"tr-plat.hop-cur", dur(h.ticks), speed_txt(h.speed)}}
  end
  return tip
end
local function sprite_of(loc)
  local s = "space-location/" .. loc
  if helpers.is_valid_sprite_path(s) then return s end
  return "utility/questionmark"
end
local function stop_icon(parent, loc, current, size)
  local b = parent.add{type = "sprite-button", sprite = sprite_of(loc), style = "slot_button", toggled = current or false,
    tooltip = C.planet_ls(loc)}
  b.style.width = size or 28
  b.style.height = size or 28
  return b
end
-- last flights of a platform (new on top): all planets of the path as icons with a tooltip, then time,
-- average speed and route length
local function add_history(card, r)
  local box = card.add{type = "flow", direction = "vertical"}
  box.style.vertical_spacing = 2
  box.add{type = "label", caption = {"tr-plat.hist-head"}, tooltip = {"tr-plat.tip-hist"}}
  if not r.history or #r.history == 0 then
    box.add{type = "label", caption = {"tr-plat.hist-none"}}
    return
  end
  for _, h in ipairs(r.history) do
    local row = box.add{type = "flow", direction = "horizontal"}
    row.style.vertical_align = "center"
    row.style.horizontal_spacing = 2
    local nodes = h.nodes or {h.from or "nauvis", h.to}
    local shown = {}
    if #nodes > 14 then
      for i = 1, 6 do shown[#shown + 1] = nodes[i] end
      shown[#shown + 1] = false
      for i = #nodes - 6, #nodes do shown[#shown + 1] = nodes[i] end
    else
      shown = nodes
    end
    for k, n in ipairs(shown) do
      if k > 1 then
        local ar = row.add{type = "label", caption = "→"}
        ar.style.font_color = {0.6, 0.6, 0.6}
      end
      if n then stop_icon(row, n, false, 20) else row.add{type = "label", caption = "…"} end
    end
    local st = row.add{type = "label", caption = {"tr-plat.hist-stats", dur(h.ticks), speed_txt(h.speed), km_txt(h.km)}}
    st.style.left_margin = 8
  end
end

local function leg_bar(parent, value, width, tip, tags)
  local pb = parent.add{type = "progressbar", value = math.max(0, math.min(1, value)), tooltip = tip, tags = tags}
  pb.style.width = width
  return pb
end

local function summary_row(p, pane, rows, moving)
  local srow = pane.add{type = "flow", direction = "horizontal"}
  srow.style.vertical_align = "center"
  srow.style.horizontally_stretchable = true
  srow.style.bottom_margin = 4
  srow.add{type = "label", caption = {"tr-plat.summary", #rows, moving, #rows - moving}, style = "caption_label"}
  local lost_n = PF.lost_total()
  if lost_n > 0 then
    local lb = srow.add{type = "button", caption = GS(p).lost_open and {"tr-plat.lost-hide"} or {"tr-plat.lost-btn", lost_n},
      tags = {tr = "plat_lost_toggle"}}
    lb.style.height = 22
    lb.style.minimal_width = 0
    lb.style.padding = {0, 8, 2, 8}
    lb.style.left_margin = 8
  end
  local entries = {}
  for _, pl in pairs(game.forces.player.platforms) do if pl.valid then entries[#entries + 1] = {id = pl.index, caption = pl.name} end end
  table.sort(entries, function(a, b) return a.caption < b.caption end)
  filter_button(p, srow, "pl", entries)
end

local function lost_box(pane)
  local lost = PF.lost()
  local lbox = deep_frame(card_frame(pane, {"tr-plat.lost-head"}))
  for _, l in ipairs(lost) do
    local where = l.at and C.planet_ls(l.at) or (l.from and {"tr-plat.between", C.planet_ls(l.from), C.planet_ls(l.to)} or "?")
    -- what killed: icon and name (asteroid, enemy...), or the damage type if there is no entity
    local cp = l.cause and prototypes.entity[l.cause]
    local cause = l.cause and {"", helpers.is_valid_sprite_path("entity/" .. l.cause) and ("[img=entity/" .. l.cause .. "] ") or "", cp and cp.localised_name or l.cause}
      or (l.damage and C.damage_ls(l.damage)) or {"tr-plat.cause-unknown"}
    wrap(lbox.add{type = "label", caption = {"tr-plat.lost-row", C.clock(l.tick), C.chat_rich(l.name), where, cause, l.trips or 0, C.big(l.ast or 0)}})
end
if #lost < PF.lost_total() then muted(lbox, {"tr-plat.lost-more", PF.lost_total() - #lost}) end
end

local function plat_header(p, card, r, idx)
  local tiers, alist = PF.asteroid_tiers(r.st.asteroids)
  local tparts = {}
  for _, t in ipairs(tiers) do tparts[#tparts + 1] = {"tr-plat.tier", {"tr-plat.tier-" .. t.tier}, C.n(t.n)} end
  local atip = {"", {"tr-plat.tip-ast"}}
  for i, a in ipairs(alist) do
    if i <= 25 then
      atip[#atip + 1] = {"", "\n[entity=" .. a.name .. "] ", prototypes.entity[a.name] and prototypes.entity[a.name].localised_name or a.name,
        " - ", C.big(a.n), " [color=0.6,0.6,0.6](", {"tr-plat.tier-" .. PF.tier_of(a.name)}, ")[/color]"}
      if #atip >= 18 then atip = {"", atip} end
    end
end
local pinned = (GS(p).plat_pins or {})[idx]
if pinned then
  local accent = card.add{type = "progressbar", value = 1}
  accent.style.color = {0.35, 0.8, 0.4}
  accent.style.horizontally_stretchable = true
  accent.style.height = 4
end
local top = card.add{type = "flow", direction = "horizontal"}
top.style.vertical_align = "center"
local nf = top.add{type = "frame", direction = "horizontal", style = "bordered_frame"}
nf.style.padding = 4
nf.style.left_padding = 10
nf.style.right_padding = 10
local head = nf.add{type = "label", caption = {"tr-plat.head", r.pl.name},
  tooltip = {"", {"tr-plat.tip-state-" .. r.state}, "\n\n", {"tr-plat.tip-stats"}, #alist > 0 and {"", "\n\n", atip} or ""}}
head.style.single_line = false
head.style.maximal_width = W - 360
local chipl = top.add{type = "label", caption = state_chip(r.state)}
chipl.style.left_margin = 8
local pfill = top.add{type = "empty-widget"}
pfill.style.horizontally_stretchable = true
local pb = top.add{type = "button", caption = pinned and {"tr-plat.pinned"} or {"tr-plat.pin"},
  tags = {tr = "plat_pin", idx = idx}, tooltip = {"tr-plat.pin-tip"}}
pb.style.height = 22
pb.style.minimal_width = 0
pb.style.padding = {0, 8, 2, 8}
local sub = card.add{type = "label", caption = {"tr-plat.head-sub", r.st.trips, #tparts > 0 and C.join(tparts, " · ") or "0"}}
sub.style.font_color = {0.7, 0.7, 0.7}
end

local function now_line(card, r)
  local now = card.add{type = "flow", direction = "horizontal"}
  now.style.vertical_align = "center"
  now.style.horizontal_spacing = 6
  if r.from then
    local pct = math.floor(r.distance * 100 + 0.5)
    now.add{type = "label", caption = {"tr-plat.now-flying"}}
    stop_icon(now, r.from, false, 28)
    leg_bar(now, r.distance, 170, {"tr-plat.tip-progress2", pct}, {tr = "plat_now"})
    stop_icon(now, r.to, r.to == r.target, 28)
    now.add{type = "label", caption = {"tr-plat.pct", pct}, tags = {tr = "plat_pct"}}
  elseif r.at then
    now.add{type = "label", caption = {"tr-plat.now-at"}}
    stop_icon(now, r.at, false, 28)
    local im = PF.idle_mins(r)
    local il = now.add{type = "label", caption = {"tr-plat.idle", C.time(r.idle or 7200)}, tags = {tr = "plat_idle"}, tooltip = {"tr-plat.tip-idle"}}
    il.style.font_color = {1, 0.8, 0.4}
    il.visible = im ~= nil
  else
    now.add{type = "label", caption = {"tr-plat.now-unknown"}}
end
end

local function route_strip(card, r)
  local hops = PF.route(r)
  if hops and #hops > 0 then
    local PER_ROW = 12
    local strip
    for k = 1, #hops + 1 do
      local node = k == 1 and hops[1].from or hops[k - 1].to
      if (k - 1) % PER_ROW == 0 then
        strip = card.add{type = "flow", direction = "horizontal"}
        strip.style.vertical_align = "center"
        strip.style.horizontal_spacing = 3
        if k == 1 then
          local sl = strip.add{type = "label", caption = {r.interrupt and "tr-plat.route-int" or "tr-plat.route"}, tooltip = {"tr-plat.tip-route"}}
          sl.style.font_color = {0.65, 0.65, 0.65}

        end
      end
      if k > 1 then
        local h = hops[k - 1]
        local v = h.kind == "done" and 1 or (h.kind == "cur" and r.distance or 0)
        leg_bar(strip, v, 22, hop_tip(h), h.kind == "cur" and {tr = "plat_hop"} or nil)
      end
      local last = k == #hops + 1
      stop_icon(strip, node, last, (k == 1 or last) and 24 or 20)
    end
    -- the time of the whole route goes after the route itself
    local total = 0
    for _, h in ipairs(hops) do total = total + (h.len or 0) end
    local eta = PF.eta_ticks(r, total)
    local el = strip.add{type = "label", caption = eta and {"tr-plat.route-eta", dur(eta), km_txt(total)} or {"tr-plat.route-len", km_txt(total)},
      tags = {tr = "plat_eta"}, tooltip = {"tr-plat.tip-eta"}}
    el.style.font_color = {0.8, 0.8, 0.8}
    el.style.left_margin = 8
end
end

local function cargo_box(p, card, r, idx)
  local gs = GS(p)
  local closed = not (gs.cargo_open or {})[idx]
  local box = card.add{type = "frame", direction = "vertical", style = "inside_deep_frame"}
  box.style.horizontally_stretchable = true
  box.style.top_margin = 4
  box.style.padding = 6
  local head = box.add{type = "flow", direction = "horizontal"}
  head.style.vertical_align = "center"
  head.add{type = "label", caption = {"tr-plat.cargo-title"}, style = "caption_label"}
  local fill = head.add{type = "empty-widget"}
  fill.style.horizontally_stretchable = true
  local tb = head.add{type = "button", caption = closed and {"tr-plat.cargo-unfold"} or {"tr-plat.cargo-fold"},
    tags = {tr = "cargo_toggle", idx = idx}, tooltip = {"tr-plat.cargo-tip"}}
  tb.style.height = 22
  tb.style.minimal_width = 0
  tb.style.padding = {0, 8, 2, 8}
  if closed then
    local parts = {}
    for i, it in ipairs(r.cargo) do
      if i <= 8 then parts[#parts + 1] = {"", item_rich(it), C.n(it.count)} end
    end
    if #r.cargo > 8 then parts[#parts + 1] = "+" .. (#r.cargo - 8) end
    box.add{type = "label", caption = C.join(parts, "  ")}
  else
    local t = box.add{type = "table", column_count = 2}
    t.style.horizontal_spacing = 10
    t.style.vertical_spacing = 2
    for _, g in ipairs(PF.cargo_groups(r.cargo)) do
      local nm = t.add{type = "label", caption = {"tr-plat.cargo-cat", {"tr-plat.cat-" .. g.cat}}}
      nm.style.minimal_width = 110
      local items, tip = {}, {""}
      for i, it in ipairs(g.items) do
        if i <= 8 then items[#items + 1] = {"", item_rich(it), C.n(it.count)} end
        if i <= 24 then tip[#tip + 1] = {"", item_rich(it), " ", C.big(it.count), "\n"} end
        if #tip >= 18 then tip = {"", tip} end
      end
      if #g.items > 8 then items[#items + 1] = "+" .. (#g.items - 8) end
      wrap(t.add{type = "label", caption = C.join(items, "  "), tooltip = tip}, W - 190)
    end
end
end

local function fill_platforms(p, pane)
  pane.clear()
  local rows = PF.rows(GS(p).hide_plats)
  local pins = GS(p).plat_pins or {}
  table.sort(rows, function(a, b)       -- pinned first, then by name
    local pa, pb = pins[a.pl.index] and true or false, pins[b.pl.index] and true or false
    if pa ~= pb then return pa end
    return a.pl.name < b.pl.name
  end)
  local moving = 0
  for _, r in ipairs(rows) do if r.from then moving = moving + 1 end end
  short_tab(pane, 120 + 260 * #rows + (GS(p).lost_open and 120 or 0) <= FIT)
  summary_row(p, pane, rows, moving)
  if GS(p).lost_open then
    lost_box(pane)
  end
  if #rows == 0 then muted(pane, {"tr-plat.none"}) end
  for _, r in ipairs(rows) do
    local idx = r.pl.index
    local card = pane.add{type = "frame", direction = "vertical", style = "inside_shallow_frame_with_padding",
      tags = {tr = "plat_card", idx = idx, sig = PF.sig(r)}}
    card.style.horizontally_stretchable = true
    card.style.bottom_margin = 4
    -- 1) name, state, trips and asteroids by size (big first); kinds on hover
    plat_header(p, card, r, idx)
    -- 2) current flight: [from] ====== 63% [to] or "stands at [planet]"
    now_line(card, r)
    -- path to the current target (schedule or interrupt): covered jumps, the current one, planets ahead;
    -- the bar shows the jump length (and time and speed for covered ones)
    route_strip(card, r)
    -- current flight in one line, the last ones below
    local trip = flight_caption(r)
    if trip then
      local tl = card.add{type = "label", caption = trip, tags = {tr = "plat_trip"}, tooltip = {"tr-plat.tip-trip"}}
      tl.style.single_line = false
      tl.style.maximal_width = W - 60
    end
    add_history(card, r)
    -- 4) cargo: its own dark frame, science first; collapsed by default, the button in the top right corner expands it
    if #r.cargo > 0 then
      cargo_box(p, card, r, idx)
    end
    if r.hp < 0.999 then bar(card, r.hp, {"tr-plat.hp", math.floor(r.hp * 100)}, 120) end
  end
  reset_bar(p, pane, "platforms")
end

-- "a b c" from the top N of a {key = count} table
function M.top_list(t, n, fmt)
  local arr = {}
  for k, v in pairs(t or {}) do arr[#arr + 1] = {k, v} end
  table.sort(arr, function(a, b) if a[2] ~= b[2] then return a[2] > b[2] end return tostring(a[1]) < tostring(b[1]) end)
  local parts = {}
  for i = 1, math.min(n, #arr) do parts[#parts + 1] = fmt(arr[i][1], arr[i][2]) end
  if #parts == 0 then return "" end
  return C.join(parts, "   ")
end
U.dur = dur
U.fill_platforms = fill_platforms
U.hop_tip = hop_tip
U.flight_caption = flight_caption
U.km_txt = km_txt
