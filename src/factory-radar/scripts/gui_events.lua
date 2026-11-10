-- Factory Radar: window: small choice windows and handlers for clicks and values
local C = require("scripts.core")
local WH = require("scripts.where")
local SH = require("scripts.shift")
local TG = require("scripts.tags")
local GSET = require("scripts.gui_settings")
local ZAP = require("scripts.zap")
local RU = require("scripts.roulette")
local RST = require("scripts.reset")
local U = require("scripts.gui_ui")
local M = U.M
local BTN, FIND, FLT, FRAME, GS, QCATS, muted = U.BTN, U.FIND, U.FLT, U.FRAME, U.GS, U.QCATS, U.muted
local wrap = U.wrap
local function close_find(...) return U.close_find(...) end
local function fill_quick(...) return U.fill_quick(...) end
local function filter_entries(...) return U.filter_entries(...) end
local function find_go(...) return U.find_go(...) end
local function layout(...) return U.layout(...) end
local function next_tip(...) return U.next_tip(...) end
local function remember(...) return U.remember(...) end
local function start_scan(...) return U.start_scan(...) end

---------------------------------------------------------------- small choice windows (MVP vote, quiz sign-up)
-- buttons cannot go into chat, so these two questions are a small window at the top of the screen: one click
local POP = {mvp = "tr_popup_mvp", rou = "tr_popup_rou"}
function M.popup(p, kind)
  if not (p and p.valid and p.connected) then return end
  local name = POP[kind]
  if not name then return end
  if p.gui.screen[name] then p.gui.screen[name].destroy() end
  local f = p.gui.screen.add{type = "frame", name = name, direction = "vertical", caption = {"tr-gui.pop-" .. kind}}
  pcall(function()
    local res, sc = p.display_resolution, p.display_scale
    f.location = {x = math.floor(res.width / 2 - 200 * sc), y = math.floor(70 * sc)}
  end)
  f.style.minimal_width = 400
  local box = f.add{type = "frame", direction = "vertical", style = "inside_shallow_frame_with_padding"}
  box.style.horizontally_stretchable = true
  local row = nil
  if kind == "mvp" then
    wrap(box.add{type = "label", caption = {"tr-gui.pop-mvp-text", SH.minutes_left()}}, 380)
    local pk, pw = SH.pick()
    if pk and pk ~= p.name then
      local pl2 = wrap(box.add{type = "label", caption = {"tr-gui.mvp-pick", pk, SH.why_ls(pw)}}, 380)
      pl2.style.font_color = {0.75, 0.85, 1}
    end
    row = box.add{type = "flow", direction = "horizontal"}
    row.style.top_margin = 8
    row.style.horizontal_spacing = 6
    local mine = C.D().mvp[p.name]
    local any = false
    for _, pl in pairs(game.connected_players) do
      if pl.index ~= p.index then
        any = true
        local b = row.add{type = "button", caption = pl.name, tags = {tr = "mvp_vote", who = pl.name, popup = true}, toggled = mine == pl.name}
        b.style.height = 28
        b.style.minimal_width = 0
        b.style.padding = {0, 10, 2, 10}
      end
    end
    if not any then muted(box, {"tr-gui.mvp-nobody"}) end
  else
    wrap(box.add{type = "label", caption = {"tr-gui.pop-rou-text"}}, 380)
    row = box.add{type = "flow", direction = "horizontal"}
    row.style.top_margin = 8
    row.style.horizontal_spacing = 6
    local yes = row.add{type = "button", caption = {"tr-gui.rou-in"}, tags = {tr = "rou_in", popup = true}}
    yes.style.height = 28
    yes.style.minimal_width = 0
    yes.style.padding = {0, 12, 2, 12}
    local no = row.add{type = "button", caption = {"tr-gui.pop-decline"}, tags = {tr = "pop_close", frame = name}}
    no.style.height = 28
    no.style.minimal_width = 0
    no.style.padding = {0, 12, 2, 12}
  end
  if kind == "mvp" then
    local cl = row.add{type = "button", caption = {"tr-gui.pop-close"}, tags = {tr = "pop_close", frame = name}}
    cl.style.height = 28
    cl.style.minimal_width = 0
    cl.style.padding = {0, 10, 2, 10}
  end
end
function M.popup_close(kind)
  local name = POP[kind]
  for _, pl in pairs(game.players) do
    if pl.valid and name and pl.gui.screen[name] then pl.gui.screen[name].destroy() end
  end
end
C.hooks.popup = M.popup
C.hooks.popup_close = M.popup_close

function M.on_closed(e)
  local el = e.element
  if el and el.valid and el.name == FRAME then M.close(game.get_player(e.player_index)) end
end

-- space opened (or the admin turned the limit on or off): windows are rebuilt with the new tabs
function M.on_unlock()
  for _, p in pairs(game.connected_players) do
    if p.gui.screen[FRAME] then
      M.close(p)
      M.toggle(p)
    end
  end
end
C.hooks.space_unlocked = function() M.on_unlock() end

function M.close(p)
  if p.gui.screen[FLT] then p.gui.screen[FLT].destroy() end
  if p.gui.screen[FRAME] then p.gui.screen[FRAME].destroy() end
  pcall(p.set_shortcut_toggled, "tr-toggle", false)
end

function M.on_tab_changed(e)
  local el = e.element
  if not (el and el.valid) then return end
  local p = game.get_player(e.player_index)
  local gs = GS(p)
  local lay = layout(p)
  if el.name == "tr_tabs" then
    local g = lay[el.selected_tab_index]
    if g then gs.tab_name = g.id end
  else
    local gid = string.match(el.name or "", "^tr_sub_(.+)$")
    if gid then
      for _, g in ipairs(lay) do
        if g.id == gid then
          local s = g.subs[el.selected_tab_index]
          if s then gs.sub = gs.sub or {}; gs.sub[gid] = s[1] end
        end
      end
    end
  end
  remember(p)
  M.refresh(p)     -- a tab that was just opened is filled now
end

local GSET_CLICK = {cfg_title_editor = true, cfg_msg_reset = true, cfg_titles_reset = true, cfg_reset_all = true,
  cfg_ignore = true, ctitle_del = true, new_title_add = true, cfg_native = true, cfg_native_auto = true, cfg_census = true}

local function click_a(tag, p, el, gs)
  if tag == "close" then
    M.close(p)
  elseif tag == "pcfg_set" then
    C.pset(p, el.tags.key, el.tags.value)
    M.refresh(p)
  elseif tag == "reset" or tag == "undo" then
    if p.admin then
      if tag == "reset" then RST.reset(el.tags.sec, p) else RST.undo(el.tags.sec, p) end
      for _, pl in pairs(game.connected_players) do M.refresh(pl) end
    end
  elseif GSET_CLICK[tag] then
    if GSET.on_click(p, el, gs) then M.refresh(p) end
  elseif tag == "goto" then
    M.go_to(p, el.tags.sub)
  elseif tag == "pin" then
    local pins = C.P(p, "pins") or {}
    local out, found = {}, false
    for _, n in ipairs(pins) do if n == el.tags.sub then found = true else out[#out + 1] = n end end
    if not found and #out < 6 then out[#out + 1] = el.tags.sub end
    C.pset(p, "pins", out)
    local frame = p.gui.screen[FRAME]
    if frame and frame.tr_quick then fill_quick(p, frame.tr_quick) end
  else
    return false
  end
  return true
end

local function click_b(tag, p, el, gs)
  if tag == "zap" then
    local to = game.get_player(el.tags.who)
    if to then ZAP.zap(p, to) end
    M.refresh(p)
  elseif tag == "nat_edit" then
    gs.nat_edit = gs.nat_edit or {}
    gs.nat_edit[el.tags.planet] = (not gs.nat_edit[el.tags.planet]) or nil
    M.refresh(p)
  elseif tag == "rou_start" then
    RU.start(p)
    M.refresh(p)
  elseif tag == "rou_in" then
    RU.join(p)
    if p.gui.screen[POP.rou] then p.gui.screen[POP.rou].destroy() end
    M.refresh(p)
  elseif tag == "sum_card" then
    gs.sum_card = (gs.sum_card ~= el.tags.who) and el.tags.who or nil
    M.refresh(p)
  elseif tag == "sum_card_hide" then
    gs.sum_card = nil
    M.refresh(p)
  elseif tag == "plat_pin" then
    gs.plat_pins = gs.plat_pins or {}
    gs.plat_pins[el.tags.idx] = (not gs.plat_pins[el.tags.idx]) or nil
    M.refresh(p)
  elseif tag == "find_open" then M.toggle_find(p)
  elseif tag == "find_close" then
    close_find(p)
  elseif tag == "find_refresh" then M.refresh_find(p)
  elseif tag == "find_go" then find_go(p, el.tags.planet, el.tags.platform)
  elseif tag == "find_min" then
    gs.find_min = (not gs.find_min) or nil
    local f = p.gui.screen[FIND]
    if f and f.valid and f.tr_find_box then f.tr_find_box.visible = not gs.find_min end
    el.tooltip = {gs.find_min and "tr-find.expand-tip" or "tr-find.min-tip"}
    el.sprite = gs.find_min and "tr-win-max-d" or "tr-win-min-d"
  elseif tag == "find_chest" then
    local s = game.surfaces[el.tags.s]
    if s and s.valid then
      pcall(function() p.set_controller{type = defines.controllers.remote, surface = s, position = {x = el.tags.x, y = el.tags.y}} end)
    end
  else
    return false
  end
  return true
end

local function click_c(tag, p, el, gs)
  if tag == "plat_lost_toggle" then
    gs.lost_open = (not gs.lost_open) or nil
    M.refresh(p)
  elseif tag == "cargo_toggle" then
    gs.cargo_open = gs.cargo_open or {}
    gs.cargo_open[el.tags.idx] = (not gs.cargo_open[el.tags.idx]) or nil
    M.refresh(p)
  elseif tag == "q_all" then
    gs.q_lim = gs.q_lim or {}
    gs.q_lim[el.tags.planet] = (not gs.q_lim[el.tags.planet]) or nil
    M.refresh(p)
  elseif tag == "q_showhidden" then
    gs.q_show_hidden = not gs.q_show_hidden
    M.refresh(p)
  elseif tag == "q_hide" then
    local h = C.P(p, "q-hide") or {}
    h[el.tags.item] = (not h[el.tags.item]) or nil
    C.pset(p, "q-hide", h)
    M.refresh(p)
  elseif tag == "flt_open" then
    gs.flt_open = (gs.flt_open ~= el.tags.which) and el.tags.which or nil
    M.refresh(p)
  elseif tag == "flt_pick" then
    local key = el.tags.which == "pl" and "hide_plats" or ("hide_" .. el.tags.which)
    gs[key] = gs[key] or {}
    gs[key][el.tags.id] = (not gs[key][el.tags.id]) or nil
    M.refresh(p)
  elseif tag == "flt_all" then
    local key = el.tags.which == "pl" and "hide_plats" or ("hide_" .. el.tags.which)
    local any_hidden = next(gs[key] or {}) ~= nil
    if any_hidden then gs[key] = nil
    else
      gs[key] = {}
      for _, e in ipairs(filter_entries(el.tags.which)) do gs[key][e.id] = true end
    end
    M.refresh(p)
  elseif tag == "flt_close" then
    gs.flt_open = nil
    M.refresh(p)           -- the tab is redrawn too: the button stops glowing at once
  else
    return false
  end
  return true
end

local function click_d(tag, p, el, gs)
  if tag == "pop_close" then
    local f = p.gui.screen[el.tags.frame]
    if f then f.destroy() end
  elseif tag == "mvp_vote" then
    local who = el.tags.who
    local tp = who ~= "" and game.get_player(who) or nil
    -- you can vote only for those online (an old button of a player who left does nothing)
    if who == "" or (tp and tp.valid and tp.connected and who ~= p.name) then
      C.D().mvp[p.name] = who ~= "" and who or nil
    end
    if p.gui.screen[POP.mvp] then p.gui.screen[POP.mvp].destroy() end
    M.refresh(p)
  elseif tag == "evo_pick" then
    gs.evo_pick = gs.evo_pick or {}
    gs.evo_pick[el.tags.planet] = not el.tags.shown
    M.refresh(p)
  elseif tag == "refresh" then next_tip(p, true); M.refresh(p)
  elseif tag == "mvp_hist_toggle" then
    gs.mvp_hist_open = (not gs.mvp_hist_open) or nil
    M.refresh(p)
  elseif tag == "en_log_toggle" then
    gs.en_log_open = (not gs.en_log_open) or nil
    M.refresh(p)
  elseif tag == "sort" then gs.sort = el.tags.key; M.refresh(p)
  elseif tag == "card" then gs.card = el.tags.who; M.refresh(p)
  elseif tag == "card_back" then gs.card = nil; M.refresh(p)
  elseif tag == "jump" then
    local target = game.get_player(el.tags.who)
    if target then
      if el.tags.what == "look" then
        local look = WH.looking(target)
        WH.jump(p, look or {surface = target.physical_surface, position = target.physical_position})
      else
        WH.jump(p, {surface = target.physical_surface, position = target.physical_position})
      end
    end
  else
    return false
  end
  return true
end

function M.on_click(e)
  local el = e.element
  if not (el and el.valid) then return end
  local p = game.get_player(e.player_index)
  if el.name == BTN then M.toggle(p); return end
  local tag = el.tags and el.tags.tr
  if not tag then return end
  local gs = GS(p)
  if click_a(tag, p, el, gs) or click_b(tag, p, el, gs) or click_c(tag, p, el, gs) or click_d(tag, p, el, gs) then return end
end

local function after_settings(p, r)
  if r == "rebuild" then M.close(p); M.toggle(p)
  elseif r == "button" then M.ensure_button(p)
  elseif r then M.refresh(p) end
end

function M.on_text(e)
  local el = e.element
  if el and el.valid and el.tags and el.tags.tr then
    local p = game.get_player(e.player_index)
    GSET.on_text(p, el, GS(p))
  end
end

function M.on_checked(e)
  local el = e.element
  local ft = el and el.valid and el.tags and el.tags.tr
  if ft == "find_net" or ft == "find_ply" or ft == "find_scan" or ft == "find_mach" then
    local p = game.get_player(e.player_index)
    if ft == "find_net" or ft == "find_ply" then
      GS(p)[ft] = el.state and true or false
    else
      GS(p)[ft] = el.state or nil
      start_scan(p)
    end
    M.refresh_find(p)
    return
  end
  if el and el.valid and el.tags and el.tags.tr then
    local p = game.get_player(e.player_index)
    after_settings(p, GSET.on_checked(p, el, GS(p)))
    return
  end
  if el and el.valid and el.name == "tr_tag_on" then
    local p = game.get_player(e.player_index)
    TG.T(p).on = el.state
    TG.apply(p)
    M.refresh(p)
  end
end

function M.on_selection(e)
  local el = e.element
  if el and el.valid and el.tags and el.tags.tr == "q_window" then
    local p = game.get_player(e.player_index)
    GS(p).q_window = el.selected_index == 2 and 60 or 10
    M.refresh(p)
    return
  end
  if el and el.valid and el.tags and el.tags.tr == "q_cat" then
    local p = game.get_player(e.player_index)
    C.pset(p, "q-cat", QCATS[el.selected_index] or "all")
    M.refresh(p)
    return
  end
  if el and el.valid and el.tags and el.tags.tr then
    local p = game.get_player(e.player_index)
    after_settings(p, GSET.on_selection(p, el, GS(p)))
    return
  end
  if el and el.valid and el.name == "tr_tag_pick" then
    local p = game.get_player(e.player_index)
    local ids = el.tags.ids or {}
    TG.T(p).id = ids[el.selected_index] or "auto"
    TG.apply(p)
    M.refresh(p)
  end
end

function M.on_value(e)
  local el = e.element
  -- a number the admin sets in game (cooldowns)
  if el and el.valid and el.tags and el.tags.tr == "cfg_num" then
    local p = game.get_player(e.player_index)
    local rg = C.NUM_RANGE[el.tags.key]
    if not (p and p.admin and rg) then return end
    local v = math.floor(el.slider_value + 0.5)
    local cfg = C.D().cfg
    cfg.num = cfg.num or {}
    cfg.num[el.tags.key] = v
    for _, ch in ipairs(el.parent.children) do
      if ch.tags and ch.tags.tr == "cfg_num_val" then ch.caption = (v == 0) and {"tr-cfg.num-off"} or {"tr-cfg.num-" .. rg[3], v} end
    end
    return
  end
  if not (el and el.valid and el.tags and el.tags.tr == "pcfg_ar_slider") then return end
  local p = game.get_player(e.player_index)
  local v = math.floor(el.slider_value + 0.5)
  C.pset(p, "autorefresh", v)
  for _, ch in ipairs(el.parent.children) do
    if ch.tags and ch.tags.tr == "ar_val" then ch.caption = v == 0 and {"tr-cfg.ar-off"} or {"tr-cfg.ar-sec", v} end
  end
end

function M.on_switch(e)
  local el = e.element
  if el and el.valid and el.name == "tr_scope" then
    local p = game.get_player(e.player_index)
    GS(p).scope = el.switch_state == "right" and "total" or "shift"
    M.refresh(p)
  end
end
