-- Factory Radar: window: tab groups, redraw, quick access, open and close
local C = require("scripts.core")
local GSET = require("scripts.gui_settings")
local U = require("scripts.gui_ui")
local M = U.M
local FLT, FLT_TAB, FRAME, GS, PAD_L, PAD_R, PANE_W, W = U.FLT, U.FLT_TAB, U.FRAME, U.GS, U.PAD_L, U.PAD_R, U.PANE_W, U.W
local scope, wrap = U.scope, U.wrap
local function fill_achievements(...) return U.fill_achievements(...) end
local function fill_combat(...) return U.fill_combat(...) end
local function fill_destruction(...) return U.fill_destruction(...) end
local function fill_energy(...) return U.fill_energy(...) end
local function fill_header(...) return U.fill_header(...) end
local function fill_journal(...) return U.fill_journal(...) end
local function fill_planets(...) return U.fill_planets(...) end
local function fill_platforms(...) return U.fill_platforms(...) end
local function fill_players(...) return U.fill_players(...) end
local function fill_quality(...) return U.fill_quality(...) end
local function fill_records(...) return U.fill_records(...) end
local function fill_research(...) return U.fill_research(...) end
local function fill_summary(...) return U.fill_summary(...) end
local function fill_tipbar(...) return U.fill_tipbar(...) end
local function fill_titles(...) return U.fill_titles(...) end
local function fill_where(...) return U.fill_where(...) end
local function filter_entries(...) return U.filter_entries(...) end
local function hidden_set(...) return U.hidden_set(...) end

---------------------------------------------------------------- window layout: groups with sub-tabs
local GROUPS = {
  {id = "summary", icon = "[item=radar]", subs = {{"summary", fill_summary, "[item=radar]"}}},
  {id = "team", icon = "[entity=character]", subs = {
    {"where", fill_where, "[entity=character]"}, {"players", fill_players, "[item=modular-armor]"},
    {"titles", fill_titles, "[item=power-armor-mk2]"}, {"achievements", fill_achievements, "[item=rocket-part]"},
    {"records", fill_records, "[item=uranium-235]"}}},
  {id = "space", icon = "[item=space-platform-starter-pack]", subs = {
    {"planets", fill_planets, "[item=rocket-silo]"}, {"platforms", fill_platforms, "[item=space-platform-starter-pack]"}}},
  {id = "combat", icon = "[item=gun-turret]", subs = {
    {"combat", fill_combat, "[item=gun-turret]"}, {"destruction", fill_destruction, "[item=stone-wall]"}}},
  {id = "factory", icon = "[item=assembling-machine-2]", subs = {
    {"research", fill_research, "[item=lab]"}, {"quality", fill_quality, "[item=quality-module]"},
    {"energy", fill_energy, "[item=steam-turbine]"}}},
  {id = "journal", icon = "[item=programmable-speaker]", subs = {{"journal", fill_journal, "[item=programmable-speaker]"}}},
  {id = "settings", icon = "[item=decider-combinator]", subs = {
    {"settings", function(p, pane) GSET.fill_settings(p, pane, GS(p)) end, "[item=decider-combinator]"},
    {"help", function(p, pane) GSET.fill_help(p, pane) end, "[item=display-panel]"}}},
}
local ALWAYS = {settings = true, help = true}

-- groups and sub-tabs the player wants to see
local function layout(p)
  local out = {}
  local space = C.space_unlocked()
  -- without SA platforms an empty tab is not shown until at least one appears
  local se_no_platforms = C.SE.active() and next(game.forces.player.platforms) == nil
  for _, g in ipairs(GROUPS) do
    local subs = {}
    for _, s in ipairs(g.subs) do
      local hide = se_no_platforms and s[1] == "platforms"
      if not hide and (g.id ~= "space" or space) and (ALWAYS[s[1]] or C.P(p, "tab-" .. s[1])) then
        subs[#subs + 1] = s
      end
    end
    if #subs > 0 then
      local icon = g.icon
      if g.id == "space" and C.SE.active() then icon = "[item=rocket-silo]" end
      out[#out + 1] = {id = g.id, icon = icon, subs = subs}
    end
  end
  return out
end

local function pane_of(frame, g, sub)
  local tabs = frame.tr_tabs
  if #g.subs == 1 then
    local one = tabs["tr_grp_" .. g.id]
    return one and one["tr_pane_" .. sub]
  end
  local holder = tabs["tr_grp_" .. g.id]
  return holder and holder["tr_sub_" .. g.id] and holder["tr_sub_" .. g.id]["tr_pane_" .. sub]
end

-- group and sub-tab open now
local function active_sub(p, frame)
  local g = layout(p)[frame.tr_tabs.selected_tab_index or 1]
  if not g then return nil end
  local sub = g.subs[1]
  if #g.subs > 1 then
    local holder = frame.tr_tabs["tr_grp_" .. g.id]
    local tp = holder and holder["tr_sub_" .. g.id]
    sub = tp and g.subs[tp.selected_tab_index or 1] or sub
  end
  return g, sub
end

local function fill_sub(p, frame, g, sub)
  local pane = pane_of(frame, g, sub[1])
  if not pane then return end
  M.reset_fw()
  pane.vertical_scroll_policy = "auto-and-reserve-space"
  local ok, err = pcall(sub[2], p, pane)
  if not ok then
    log("Factory Radar GUI error in " .. sub[1] .. ": " .. tostring(err))
    pcall(function() pane.clear(); pane.add{type = "label", caption = {"tr-gui.tab-error"}} end)
  end
end

-- selection panel next to the window (see filter_button)
local function sync_filter(p)
  local gs = GS(p)
  local which = gs.flt_open
  local frame = p.gui.screen[FRAME]
  local f = p.gui.screen[FLT]
  local tab_ok = false
  if which and frame then
    local _, sub = active_sub(p, frame)
    tab_ok = sub ~= nil and sub[1] == FLT_TAB[which]
  end
  if not tab_ok then                       -- only while its tab is open
    if f then f.destroy() end
    gs.flt_open = nil
    return
  end
  if f and f.tags.which ~= which then f.destroy(); f = nil end
  if not f then
    -- created once and then only updated: it remembers where it was dragged (by the header)
    f = p.gui.screen.add{type = "frame", name = FLT, direction = "vertical", tags = {which = which}}
    local tb = f.add{type = "flow", direction = "horizontal"}
    tb.drag_target = f
    tb.style.vertical_align = "center"
    tb.add{type = "label", caption = {"tr-gui.flt-title-" .. which}, style = "frame_title", ignored_by_interaction = true}
    local dr = tb.add{type = "empty-widget", style = "draggable_space_header", ignored_by_interaction = true}
    dr.style.horizontally_stretchable = true
    dr.style.height = 24
    tb.add{type = "sprite-button", sprite = "utility/close", style = "frame_action_button", tags = {tr = "flt_close"}}
    f.add{type = "frame", name = "tr_flt_box", direction = "vertical", style = "inside_shallow_frame_with_padding"}
    pcall(function()
      local loc, sc, res = frame.location, p.display_scale, p.display_resolution
      local x = math.min(loc.x + (W + 100) * sc, res.width - 250 * sc)      -- not past the screen edge
      f.location = {x = math.floor(math.max(0, x)), y = math.floor(loc.y + 40 * sc)}
    end)
  end
  local box = f.tr_flt_box
  box.clear()
  box.style.padding = 8
  local entries = filter_entries(which)
  local hidden = hidden_set(p, which)
  local hint = box.add{type = "label", caption = {"tr-gui.flt-hint"}}
  hint.style.single_line = false
  hint.style.maximal_width = 204
  hint.style.font = "default-small"
  hint.style.font_color = {0.65, 0.65, 0.65}
  hint.style.bottom_margin = 4
  local sp = box.add{type = "scroll-pane", direction = "vertical"}
  sp.horizontal_scroll_policy = "never"
  sp.style.maximal_height = 300
  sp.style.minimal_width = 214
  local nh = 0
  for _, e in ipairs(entries) do
    local off = hidden[e.id]
    if off then nh = nh + 1 end
    local b = sp.add{type = "button", caption = e.caption, toggled = not off, tags = {tr = "flt_pick", which = which, id = e.id}}
    b.style.horizontal_align = "left"
    b.style.height = 30
    b.style.width = 200
    b.style.padding = {0, 6, 2, 6}
    b.style.bottom_margin = 1
  end
  local row = box.add{type = "flow", direction = "horizontal"}
  row.style.top_margin = 6
  row.style.horizontal_spacing = 6
  local all = row.add{type = "button", caption = {nh == 0 and "tr-gui.flt-none" or "tr-gui.flt-all"}, tags = {tr = "flt_all", which = which}}
  all.style.height = 22
  all.style.minimal_width = 0
  all.style.padding = {0, 6, 2, 6}
end

-- header and the open tab: the others are not built until opened (building a tab is expensive)
function M.refresh(p)
  local frame = p.gui.screen[FRAME]
  if not frame then return end
  pcall(fill_header, p, frame.tr_header)
  pcall(fill_tipbar, p, frame)
  local g, sub = active_sub(p, frame)
  if g then
    -- the window is as tall as the open tab: tabs that left have no content (a tabbed-pane equals the biggest)
    for _, gg in ipairs(layout(p)) do
      for _, ss in ipairs(gg.subs) do
        if not (gg.id == g.id and ss[1] == sub[1]) then
          local pane = pane_of(frame, gg, ss[1])
          if pane and pane.valid and #pane.children > 0 then pane.clear() end
        end
      end
    end
    fill_sub(p, frame, g, sub)
  end
  sync_filter(p)
end

-- auto refresh: the same, but the settings tab is left alone (an input field must not be redrawn while typing)
function M.refresh_active(p)
  local frame = p.gui.screen[FRAME]
  if not frame then return false end
  local gs = GS(p)
  local g, sub = active_sub(p, frame)
  if not g or g.id == "settings" then return false end
  if gs.card and sub[1] == "players" then return false end
  pcall(fill_header, p, frame.tr_header)
  fill_sub(p, frame, g, sub)
  return true
end

---------------------------------------------------------------- quick access: pinned and recent sub-tabs
local function current_sub(p)
  local gs = GS(p)
  for _, g in ipairs(layout(p)) do
    if g.id == gs.tab_name then
      if #g.subs == 1 then return g.subs[1][1] end
      return (gs.sub or {})[g.id] or g.subs[1][1]
    end
  end
  return nil
end

local function find_sub(p, name)
  for gi, g in ipairs(layout(p)) do
    for si, s in ipairs(g.subs) do if s[1] == name then return gi, si, g, s end end
  end
end

M._find_sub = find_sub

local function fill_quick(p, q)
  q.clear()
  local gs = GS(p)
  local pins = C.P(p, "pins") or {}
  local cur = current_sub(p)
  local shown = {}
  local function btn(name, pinned)
    local _, _, _, s = find_sub(p, name)
    if not s or shown[name] then return end
    shown[name] = true
    -- pinned: icon and name; recent: icon only (name on hover) so the row fits
    local b = q.add{type = "button", caption = pinned and {"", s[3], " ", {"tr-gui.tab-" .. name}} or s[3],
      tags = {tr = "goto", sub = name}, tooltip = {"", {"tr-gui.tab-" .. name}, "\n", {pinned and "tr-gui.quick-pinned" or "tr-gui.quick-recent"}}}
    b.style.height = 28
    b.style.minimal_width = 0
    b.style.padding = {0, 6, 2, 6}
    b.style.font = (name == cur) and "default-bold" or "default"
    if not pinned then b.style.font_color = {0.3, 0.3, 0.3} end
  end
  local lbl = q.add{type = "label", caption = {"tr-gui.quick"}, tooltip = {"tr-gui.quick-tip"}}
  lbl.style.font_color = {0.65, 0.65, 0.65}
  for _, name in ipairs(pins) do btn(name, true) end
  for _, name in ipairs(gs.recent or {}) do btn(name, false) end
  local empty = q.add{type = "empty-widget"}
  empty.style.horizontally_stretchable = true
  local fb = q.add{type = "button", caption = {"", "[img=utility/search_icon] ", {"tr-gui.find-btn"}}, tags = {tr = "find_open"}, tooltip = {"tr-gui.find-tip"}}
  fb.style.height = 28
  fb.style.minimal_width = 0
  fb.style.padding = {0, 6, 2, 6}
  if cur and cur ~= "settings" and cur ~= "help" then
    local is_pinned = false
    for _, n in ipairs(pins) do if n == cur then is_pinned = true end end
    local pb = q.add{type = "button", caption = {is_pinned and "tr-gui.unpin" or "tr-gui.pin"}, tags = {tr = "pin", sub = cur},
      tooltip = {is_pinned and "tr-gui.unpin-tip" or "tr-gui.pin-tip"}}
    pb.style.height = 28
    pb.style.minimal_width = 0
    pb.style.padding = {0, 6, 2, 6}
  end
end

local function remember(p)
  local gs = GS(p)
  local cur = current_sub(p)
  if not cur then return end
  local r = {cur}
  for _, n in ipairs(gs.recent or {}) do if n ~= cur and #r < 4 then r[#r + 1] = n end end
  gs.recent = r
  local frame = p.gui.screen[FRAME]
  if frame and frame.tr_quick then pcall(fill_quick, p, frame.tr_quick) end
end

function M.go_to(p, name)
  local frame = p.gui.screen[FRAME]
  if not frame then return end
  local gi, si, g = find_sub(p, name)
  if not gi then return end
  local gs = GS(p)
  frame.tr_tabs.selected_tab_index = gi
  gs.tab_name = g.id
  if #g.subs > 1 then
    local holder = frame.tr_tabs["tr_grp_" .. g.id]
    if holder and holder["tr_sub_" .. g.id] then holder["tr_sub_" .. g.id].selected_tab_index = si end
    gs.sub = gs.sub or {}
    gs.sub[g.id] = name
  end
  remember(p)
  M.refresh(p)
end

local function new_pane(parent, name)
  local pane = parent.add{type = "scroll-pane", name = name, direction = "vertical"}
  pane.horizontal_scroll_policy = "never"      -- up and down only; everything wraps by width
  pane.vertical_scroll_policy = "auto-and-reserve-space"      -- room for the bar is always reserved, the bar itself only when needed
  pane.style.maximal_height = 470
  pane.style.width = PANE_W
  pane.style.horizontally_stretchable = true
  pane.style.padding = 8
  pane.style.left_padding = PAD_L
  pane.style.right_padding = PAD_R
  return pane
end

local function title_bar(p, frame)
  local title = frame.add{type = "flow", direction = "horizontal"}
  title.drag_target = frame
  title.style.vertical_align = "center"
  title.add{type = "label", caption = {"tr-gui.title"}, style = "frame_title", ignored_by_interaction = true}
  local drag = title.add{type = "empty-widget", style = "draggable_space_header", ignored_by_interaction = true}
  drag.style.horizontally_stretchable = true
  drag.style.height = 24
  title.add{type = "switch", name = "tr_scope", left_label_caption = {"tr-gui.this-shift"},
    right_label_caption = {"tr-gui.all-time"}, switch_state = scope(p) == "total" and "right" or "left",
    left_label_tooltip = {"tr-gui.tip-scope-shift"}, right_label_tooltip = {"tr-gui.tip-scope-total"}}
  -- white icon: black blends into the dark window header
  title.add{type = "sprite-button", sprite = helpers.is_valid_sprite_path("utility/reset_white") and "utility/reset_white" or "utility/refresh", style = "frame_action_button",
    tooltip = {"tr-gui.refresh"}, tags = {tr = "refresh"}}
  title.add{type = "sprite-button", sprite = "utility/close", style = "frame_action_button",
    tooltip = {"tr-gui.close"}, tags = {tr = "close"}}
end

local function build_tabs(p, frame, gs)
  local tabs = frame.add{type = "tabbed-pane", name = "tr_tabs"}
  local lay = layout(p)
  -- which group/sub-tab to open
  local want = C.P(p, "open-tab")
  local gi, si = 1, {}
  for i, g in ipairs(lay) do
    for j, s in ipairs(g.subs) do
      if (want == "last" and gs.tab_name == g.id and (gs.sub or {})[g.id] == s[1]) or want == s[1] then gi = i; si[g.id] = j end
      if want == "last" and gs.tab_name == g.id and not si[g.id] then gi = i end
    end
  end
  for _, g in ipairs(lay) do
    local tab = tabs.add{type = "tab", caption = {"", g.icon .. " ", {"tr-gui.grp-" .. g.id}}}
    local content
    if #g.subs == 1 then
      -- the same frame style the game draws around a nested tab area: tabs without sub-tabs get the same outline
      local holder = tabs.add{type = "frame", name = "tr_grp_" .. g.id, direction = "vertical", style = "tabbed_pane_frame"}
      holder.style.horizontally_stretchable = true
      new_pane(holder, "tr_pane_" .. g.subs[1][1])
      content = holder
    else
      local holder = tabs.add{type = "flow", name = "tr_grp_" .. g.id, direction = "vertical"}
      local sub = holder.add{type = "tabbed-pane", name = "tr_sub_" .. g.id}
      for _, s in ipairs(g.subs) do
        local st = sub.add{type = "tab", caption = {"", s[3] .. " ", {"tr-gui.tab-" .. s[1]}}}
        sub.add_tab(st, new_pane(sub, "tr_pane_" .. s[1]))
      end
      local remembered = (gs.sub or {})[g.id]
      local idx = si[g.id] or 1
      if not si[g.id] and remembered then for j, s in ipairs(g.subs) do if s[1] == remembered then idx = j end end end
      sub.selected_tab_index = idx
      content = holder
    end
    tabs.add_tab(tab, content)
  end
  tabs.selected_tab_index = math.min(gi, #lay)
  if lay[tabs.selected_tab_index] then gs.tab_name = lay[tabs.selected_tab_index].id end
end

local function tip_bar(frame)
  local tipbar = frame.add{type = "frame", name = "tr_tipbar", direction = "horizontal", style = "inside_shallow_frame_with_padding"}
  tipbar.style.horizontally_stretchable = true
  tipbar.style.top_margin = 4
  tipbar.style.padding = {4, 10}
  tipbar.style.vertical_align = "center"
  local tt = tipbar.add{type = "label", name = "tr_tiptext", caption = ""}
  wrap(tt, W + 40)
  tt.style.font_color = {1, 0.9, 0.6}
end

function M.toggle(p)
  if p.gui.screen[FRAME] then M.close(p); return end
  local gs = GS(p)
  local frame = p.gui.screen.add{type = "frame", name = FRAME, direction = "vertical"}
  -- fixed width: the window does not change size with content (hidden intro, long names, many buttons)
  frame.style.minimal_width = W + 90
  frame.style.maximal_width = W + 90
  title_bar(p, frame)
  local header = frame.add{type = "frame", name = "tr_header", direction = "vertical", style = "inside_shallow_frame_with_padding"}
  header.style.horizontally_stretchable = true
  header.style.bottom_margin = 4
  local quick = frame.add{type = "flow", name = "tr_quick", direction = "horizontal"}
  quick.style.vertical_align = "center"
  quick.style.horizontal_spacing = 4
  quick.style.bottom_margin = 4
  build_tabs(p, frame, gs)
  tip_bar(frame)
  pcall(fill_quick, p, quick)
  frame.force_auto_center()
  M.refresh(p)
  p.opened = frame
     -- Esc (or opening another window) closes through on_gui_closed
  pcall(p.set_shortcut_toggled, "tr-toggle", true)
end
U.pane_of = pane_of
U.layout = layout
U.active_sub = active_sub
U.remember = remember
U.fill_quick = fill_quick
