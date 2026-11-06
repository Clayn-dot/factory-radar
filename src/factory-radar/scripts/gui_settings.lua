-- Factory Radar: вкладки «Настройки» и «Справка»
-- личные настройки хранятся по игроку; серверные (функции, что считаем, чат, звания,
-- исключённые планеты) меняют админы, и они действуют для всех
local C = require("scripts.core")
local TG = require("scripts.tags")
local PL = require("scripts.planets")
local CEN = require("scripts.census")
local M = {}

local W = 1000
M.TAB_NAMES = {"summary", "where", "players", "titles", "achievements", "records", "planets", "platforms", "combat", "destruction", "research", "quality", "energy", "journal"}

---------------------------------------------------------------- помощники
local function wrap(label, width)
  label.style.single_line = false
  label.style.maximal_width = width or (W - 110)
  return label
end
local function muted(parent, caption)
  local l = wrap(parent.add{type = "label", caption = caption})
  l.style.font_color = {0.65, 0.65, 0.65}
  l.style.bottom_margin = 3
  return l
end
local function heading(parent, caption)
  local l = parent.add{type = "label", caption = caption, style = "caption_label"}
  l.style.top_margin = 10
  l.style.bottom_margin = 4
  return l
end
-- карточка с заголовком; содержимое в тёмной рамке внутри (возвращается она)
local function section(parent, caption)
  local f = parent.add{type = "frame", direction = "vertical", style = "inside_shallow_frame_with_padding"}
  f.style.horizontally_stretchable = true
  f.style.top_margin = 2
  f.style.bottom_margin = 8
  local l = f.add{type = "label", caption = caption, style = "caption_label"}
  l.style.bottom_margin = 6
  local inner = f.add{type = "frame", direction = "vertical", style = "inside_deep_frame"}
  inner.style.horizontally_stretchable = true
  inner.style.padding = 10
  return inner
end
local function check(parent, caption, state, tags, tooltip, enabled)
  local c = parent.add{type = "checkbox", caption = caption, state = state and true or false, tags = tags, tooltip = tooltip}
  c.enabled = enabled ~= false
  c.style.bottom_margin = 4
  pcall(function() c.style.maximal_width = W - 130; c.style.single_line = false end)     -- длинная подпись переносится
  return c
end
-- строка «имя .... элемент»: у имени фиксированная ширина, чтобы элементы выстроились, сверху и снизу отступ
local function setting_row(parent, caption, tooltip)
  local row = parent.add{type = "flow", direction = "horizontal"}
  row.style.vertical_align = "center"
  row.style.top_margin = 4
  row.style.bottom_margin = 6
  local l = row.add{type = "label", caption = caption, tooltip = tooltip}
  l.style.minimal_width = 250
  return row
end
local function button(parent, caption, tags, enabled, tooltip)
  local b = parent.add{type = "button", caption = caption, tags = tags, tooltip = tooltip}
  b.enabled = enabled ~= false
  return b
end

local function is_admin(p) return p.admin end

local KM = {walk = true, ride = true}
local function shown_n(t) return KM[t.key] and t.n / 1000 or t.n end
local function stored_n(key, v) return KM[key] and v * 1000 or v end

---------------------------------------------------------------- вкладка настроек
function M.fill_settings(p, pane, gs)
  pane.clear()
  local admin = is_admin(p)

  -- личное
  local me = section(pane, {"tr-cfg.personal"})
  muted(me, {"tr-cfg.personal-hint"})
  check(me, {"tr-cfg.p-button"}, C.P(p, "button"), {tr = "pcfg", key = "button"}, {"tr-cfg.p-button-tip"})
  check(me, {"tr-gui.tag-color"}, C.P(p, "tag-color"), {tr = "pcfg", key = "tag-color", retag = true}, {"tr-gui.tip-tag-color"})
  check(me, {"tr-cfg.p-greet"}, C.P(p, "greet"), {tr = "pcfg", key = "greet"}, {"tr-cfg.p-greet-tip"})
  check(me, {"tr-cfg.p-intro"}, C.P(p, "intro"), {tr = "pcfg", key = "intro"}, {"tr-cfg.p-intro-tip"})
  check(me, {"tr-cfg.p-know"}, C.P(p, "know"), {tr = "pcfg", key = "know"}, {"tr-cfg.p-know-tip"})
  check(me, {"tr-cfg.p-tips"}, C.P(p, "tips"), {tr = "pcfg", key = "tips"}, {"tr-cfg.p-tips-tip"})
  heading(me, {"tr-cfg.p-window-head"})
  local ar = setting_row(me, {"tr-cfg.p-autorefresh"}, {"tr-cfg.p-autorefresh-tip"})
  local cur = C.P(p, "autorefresh") or 0
  local sl = ar.add{type = "slider", minimum_value = 0, maximum_value = 60, value_step = 5, value = cur, discrete_slider = true,
    tags = {tr = "pcfg_ar_slider"}, tooltip = {"tr-cfg.p-autorefresh-tip"}}
  sl.style.width = 220
  local av = ar.add{type = "label", caption = cur == 0 and {"tr-cfg.ar-off"} or {"tr-cfg.ar-sec", cur}, tags = {tr = "ar_val"}}
  av.style.left_margin = 10
  av.style.minimal_width = 90
  local row = setting_row(me, {"tr-cfg.p-open-tab"}, {"tr-cfg.p-open-tab-tip"})
  local opts, sel = {"last"}, 1
  for _, n in ipairs(M.TAB_NAMES) do opts[#opts + 1] = n end
  local items = {}
  for i, n in ipairs(opts) do
    items[i] = n == "last" and {"tr-cfg.tab-last"} or {"tr-gui.tab-" .. n}
    if n == C.P(p, "open-tab") then sel = i end
  end
  row.add{type = "drop-down", items = items, selected_index = sel, tags = {tr = "pcfg_tab", opts = opts}}

  heading(me, {"tr-cfg.p-messages"})
  local mt = me.add{type = "table", column_count = 2}
  mt.style.horizontal_spacing = 24
  for _, c in ipairs(C.PCFG) do
    if c.group == "msg" then check(mt, {"tr-cfg.p-" .. c.key}, C.P(p, c.key), {tr = "pcfg", key = c.key}) end
  end

  heading(me, {"tr-cfg.p-tabs"})
  local tt = me.add{type = "table", column_count = 5}
  tt.style.horizontal_spacing = 18
  for _, n in ipairs(M.TAB_NAMES) do
    check(tt, {"tr-gui.tab-" .. n}, C.P(p, "tab-" .. n), {tr = "pcfg", key = "tab-" .. n, rebuild = true})
  end

  -- сервер
  local sv = section(pane, {"tr-cfg.server"})
  muted(sv, admin and {"tr-cfg.server-hint"} or {"tr-cfg.server-locked"})

  heading(sv, {"tr-cfg.features"})
  for _, c in ipairs(C.CFG) do
    if c.group == "features" then
      check(sv, {"tr-cfg." .. c.key}, C.S(c.key), {tr = "cfg", key = c.key}, {"tr-cfg." .. c.key .. "-tip"}, admin)
    end
  end
  heading(sv, {"tr-cfg.tracking"})
  for _, c in ipairs(C.CFG) do
    if c.group == "tracking" then
      check(sv, {"tr-cfg." .. c.key}, C.S(c.key), {tr = "cfg", key = c.key}, {"tr-cfg." .. c.key .. "-tip"}, admin)
    end
  end

  -- сообщения в чат
  heading(sv, {"tr-cfg.messages"})
  muted(sv, {"tr-cfg.messages-hint"})
  local t = sv.add{type = "table", column_count = 4}
  t.style.horizontal_spacing = 10
  t.style.vertical_spacing = 4
  for _, h in ipairs({"col-msg", "col-aud", "col-tpl", "col-reset"}) do t.add{type = "label", caption = {"tr-cfg." .. h}, style = "caption_label"} end
  for _, m in ipairs(C.MSGS) do
    local mc = C.msgcfg(m.kind)
    wrap(t.add{type = "label", caption = {"tr-cfg.msg-" .. m.kind}, tooltip = {"tr-cfg.msg-" .. m.kind .. "-tip"}}, 240)
    local auds = m.self and {"all", "self", "none"} or {"all", "none"}
    local ai, aitems = 1, {}
    for i, a in ipairs(auds) do
      aitems[i] = {"tr-cfg.aud-" .. a}
      if a == (mc.aud or "all") then ai = i end
    end
    local dd = t.add{type = "drop-down", items = aitems, selected_index = ai, tags = {tr = "cfg_aud", kind = m.kind, auds = auds}}
    dd.enabled = admin
    if m.params then
      local names = {}
      for _, n in ipairs(m.params) do names[#names + 1] = "{" .. n .. "}" end
      local tf = t.add{type = "textfield", text = mc.tpl or "", tags = {tr = "cfg_tpl", kind = m.kind},
        tooltip = {"tr-cfg.tpl-tip", table.concat(names, " ")}}
      tf.style.width = 250
      tf.enabled = admin
    else
      t.add{type = "label", caption = {"tr-cfg.tpl-none"}}.style.font_color = {0.55, 0.55, 0.55}
    end
    button(t, {"tr-cfg.reset"}, {tr = "cfg_msg_reset", kind = m.kind}, admin)
  end
  muted(sv, {"tr-cfg.tpl-example"})

  -- звания
  heading(sv, {"tr-cfg.titles"})
  local trow = sv.add{type = "flow", direction = "horizontal"}
  button(trow, gs.title_editor and {"tr-cfg.titles-close"} or {"tr-cfg.titles-open"}, {tr = "cfg_title_editor"})
  button(trow, {"tr-cfg.titles-reset"}, {tr = "cfg_titles_reset"}, admin, {"tr-cfg.titles-reset-tip"})
  if gs.title_editor then M.title_editor(p, sv, gs, admin) end

  -- планеты вне статистики
  -- родная наука планеты (автоопределение можно переопределить)
  heading(sv, {"tr-cfg.native"})
  muted(sv, {"tr-cfg.native-hint"})
  local packs = PL.science_names()
  local planets = {}
  -- все планеты игры, не только те, где уже есть поверхность
  for name, pl in pairs(game.planets) do
    if not pl.prototype.hidden and not C.ignored(name) then planets[#planets + 1] = name end
  end
  table.sort(planets)
  for _, key in ipairs(planets) do
    local list, manual = PL.native(key)
    local on = {}
    for _, pk in ipairs(list) do on[pk] = true end
    local row = sv.add{type = "flow", direction = "horizontal"}
    row.style.vertical_align = "center"
    local ic = row.add{type = "sprite", sprite = "space-location/" .. key, tooltip = game.planets[key].prototype.localised_name}
    ic.style.width = 28
    ic.style.height = 28
    ic.style.stretch_image_to_widget_size = true
    local lb = row.add{type = "label", caption = manual and {"tr-cfg.native-manual"} or {"tr-cfg.native-auto"}}
    lb.style.width = 70
    local grid = row.add{type = "table", column_count = 16}
    grid.style.horizontal_spacing = 0
    grid.style.vertical_spacing = 0
    for _, pk in ipairs(packs) do
      local it = prototypes.item[pk]
      local b = grid.add{type = "sprite-button", sprite = "item/" .. pk, style = "slot_button", toggled = on[pk] or false,
        tags = {tr = "cfg_native", planet = key, pack = pk}, tooltip = it and it.localised_name or pk}
      b.style.width = 28
      b.style.height = 28
      b.enabled = admin
    end
    if manual then button(row, {"tr-cfg.native-reset"}, {tr = "cfg_native_auto", planet = key}, admin) end
  end

  heading(sv, {"tr-cfg.ignore"})
  muted(sv, {"tr-cfg.ignore-hint"})
  local pr = sv.add{type = "table", column_count = 20}      -- много планет: строки, а не одна длинная линия
  pr.style.horizontal_spacing = 2
  pr.style.vertical_spacing = 2
  local ign = C.D().cfg.ignore or {}
  local keys = {}
  for name, pl in pairs(game.planets) do if not pl.prototype.hidden then keys[#keys + 1] = name end end
  table.sort(keys)
  for _, k in ipairs(keys) do
    local b = pr.add{type = "sprite-button", sprite = "space-location/" .. k, style = "slot_button",
      toggled = not ign[k], tags = {tr = "cfg_ignore", planet = k},
      tooltip = {"", game.planets[k].prototype.localised_name, "\n", {ign[k] and "tr-cfg.ignore-off" or "tr-cfg.ignore-on"}}}
    b.style.width = 28
    b.style.height = 28
    b.enabled = admin
  end

  -- числа в игре: кулдауны молнии и викторины
  heading(sv, {"tr-cfg.cooldowns"})
  for _, k in ipairs({"tr-s-zap-cooldown", "tr-s-roulette-cooldown", "tr-s-roulette-fail"}) do
    local rg = C.NUM_RANGE[k]
    local row = sv.add{type = "flow", direction = "horizontal"}
    row.style.vertical_align = "center"
    local nl = wrap(row.add{type = "label", caption = {"mod-setting-name." .. k}}, 300)
    nl.style.minimal_width = 300
    local cur = C.S(k)
    local sl = row.add{type = "slider", minimum_value = rg[1], maximum_value = rg[2], value_step = 1, value = cur,
      discrete_slider = true, tags = {tr = "cfg_num", key = k}, tooltip = {"mod-setting-description." .. k}}
    sl.style.width = 220
    sl.enabled = admin
    local vl = row.add{type = "label", caption = (cur == 0) and {"tr-cfg.num-off"} or {"tr-cfg.num-" .. rg[3], cur}, tags = {tr = "cfg_num_val", key = k}}
    vl.style.left_margin = 10
  end

  -- стартовые значения (главное меню)
  heading(sv, {"tr-cfg.startup"})
  local st = sv.add{type = "table", column_count = 2}
  st.style.horizontal_spacing = 16
  for _, k in ipairs({"tr-s-shift-hours", "tr-s-afk-minutes", "tr-s-death-limit", "tr-s-journal", "tr-s-history",
                      "tr-s-idle-percent", "tr-s-min-output", "tr-s-mvp-reminder", "tr-s-zap-percent",
                      "tr-s-roulette", "tr-s-roulette-join"}) do
    wrap(st.add{type = "label", caption = {"mod-setting-name." .. k}}, 560)
    st.add{type = "label", caption = {"", "[font=default-bold]", tostring(settings.startup[k].value), "[/font]"}}
  end
  local d = C.D()
  muted(sv, {"tr-cfg.startup-hint"})

  -- подсчёт, кто что построил (один раз сам; тут можно запустить снова)
  heading(sv, {"tr-cfg.census"}).tooltip = {"tr-cfg.census-tip"}
  local cst, ckey, cleft = CEN.status()
  local cr = sv.add{type = "flow", direction = "horizontal"}
  cr.style.vertical_align = "center"
  cr.style.horizontal_spacing = 10
  button(cr, {"tr-cfg.census-run"}, {tr = "cfg_census"}, admin and cst ~= "run", {"tr-cfg.census-tip"})
  wrap(cr.add{type = "label", caption = cst == "run" and {"tr-cfg.census-now", ckey and C.planet_ls(ckey) or "…", cleft} or {"tr-cfg.census-idle"}}, 520)

  local rr = sv.add{type = "flow", direction = "horizontal"}
  rr.style.top_margin = 8
  button(rr, {"tr-cfg.reset-all"}, {tr = "cfg_reset_all"}, admin, {"tr-cfg.reset-all-tip"})
end

---------------------------------------------------------------- редактор званий
function M.title_editor(p, parent, gs, admin)
  local cfg = C.D().cfg
  cfg.title_over = cfg.title_over or {}
  cfg.titles_custom = cfg.titles_custom or {}
  muted(parent, {"tr-cfg.titles-hint"})
  check(parent, {"tr-cfg.planet-titles"}, not cfg.planet_titles_off, {tr = "cfg_planet_titles"}, {"tr-cfg.planet-titles-tip"}, admin)
  local t = parent.add{type = "table", column_count = 5}
  t.style.horizontal_spacing = 10
  for _, h in ipairs({"col-on", "col-title", "col-rename", "col-stat", "col-n"}) do
    t.add{type = "label", caption = {"tr-cfg." .. h}, style = "caption_label"}
  end
  for _, b in ipairs(C.BASE_TITLES) do
    local o = cfg.title_over[b.id] or {}
    local c = t.add{type = "checkbox", state = not o.off, tags = {tr = "title_on", id = b.id}}
    c.enabled = admin
    wrap(t.add{type = "label", caption = {"tr-title." .. b.id}}, 190)
    local tf = t.add{type = "textfield", text = o.name or "", tags = {tr = "title_name", id = b.id}}
    tf.style.width = 150
    tf.enabled = admin
    wrap(t.add{type = "label", caption = {"tr-why." .. b.key, "…"}}, 200)
    local nf = t.add{type = "textfield", text = tostring(o.n and shown_n({key = b.key, n = o.n}) or shown_n(b)),
      numeric = true, allow_decimal = true, tags = {tr = "title_n", id = b.id, key = b.key}}
    nf.style.width = 80
    nf.enabled = admin
  end
  for i, ct in ipairs(cfg.titles_custom) do
    local c = t.add{type = "checkbox", state = not ct.off, tags = {tr = "ctitle_on", i = i}}
    c.enabled = admin
    local del = t.add{type = "flow", direction = "horizontal"}
    del.add{type = "label", caption = {"tr-cfg.custom-mark"}}
    local db = del.add{type = "sprite-button", sprite = "utility/trash", style = "mini_button", tags = {tr = "ctitle_del", i = i},
      tooltip = {"tr-cfg.delete"}}
    db.enabled = admin
    local tf = t.add{type = "textfield", text = ct.name or "", tags = {tr = "ctitle_name", i = i}}
    tf.style.width = 150
    tf.enabled = admin
    wrap(t.add{type = "label", caption = {"tr-why." .. ct.key, "…"}}, 200)
    local nf = t.add{type = "textfield", text = tostring(shown_n(ct)), numeric = true, allow_decimal = true,
      tags = {tr = "ctitle_n", i = i, key = ct.key}}
    nf.style.width = 80
    nf.enabled = admin
  end

  -- новое звание
  heading(parent, {"tr-cfg.new-title"})
  gs.new_title = gs.new_title or {name = "", key = "kills", n = 100}
  local nr = parent.add{type = "flow", direction = "horizontal"}
  nr.style.vertical_align = "center"
  local nf = nr.add{type = "textfield", text = gs.new_title.name, tags = {tr = "new_title_name"}}
  nf.style.width = 200
  nf.enabled = admin
  local items, sel = {}, 1
  for i, k in ipairs(C.TITLE_KEYS) do
    items[i] = {"tr-why." .. k, "…"}
    if k == gs.new_title.key then sel = i end
  end
  local dd = nr.add{type = "drop-down", items = items, selected_index = sel, tags = {tr = "new_title_key"}}
  dd.enabled = admin
  local n = nr.add{type = "textfield", text = tostring(gs.new_title.n), numeric = true, allow_decimal = true, tags = {tr = "new_title_n"}}
  n.style.width = 80
  n.enabled = admin
  button(nr, {"tr-cfg.add"}, {tr = "new_title_add"}, admin)
end

---------------------------------------------------------------- вкладка справки
local CMDS = {
  {"tr-where", false}, {"tr-now", false}, {"tr-top", false}, {"tr-me", false}, {"tr-vs", false},
  {"tr-planets", false}, {"tr-research", false}, {"tr-combat", false}, {"tr-log", false}, {"tr-mvp", false},
  {"tr-zap", false}, {"tr-roulette", false}, {"tr-in", false}, {"tr-zap-lift", true}, {"tr-shift-now", true}, {"tr-census", true},
}

local function cmd_table(parent, rows)
  local t = parent.add{type = "table", column_count = 3}
  t.style.horizontal_spacing = 14
  t.style.vertical_spacing = 4
  for _, h in ipairs({"col-cmd", "col-who", "col-what"}) do t.add{type = "label", caption = {"tr-help." .. h}, style = "caption_label"} end
  for _, r in ipairs(rows) do
    local c = t.add{type = "label", caption = "[font=default-bold]/" .. r.name .. "[/font]"}
    c.style.minimal_width = 170
    local w = t.add{type = "label", caption = r.admin and {"tr-help.admin"} or {"tr-help.everyone"}}
    w.style.font_color = r.admin and {1, 0.7, 0.4} or {0.6, 1, 0.6}
    wrap(t.add{type = "label", caption = r.what}, 420)
  end
end

function M.fill_help(p, pane)
  pane.clear()
  local a = section(pane, {"tr-help.how"})
  for i = 1, 6 do wrap(a.add{type = "label", caption = {"tr-help.how-" .. i}}) end

  local b = section(pane, {"tr-help.commands"})
  muted(b, {"tr-help.commands-hint"})
  local rows = {}
  for _, c in ipairs(CMDS) do rows[#rows + 1] = {name = c[1], admin = c[2], what = {"tr-help." .. c[1]}} end
  cmd_table(b, rows)

  local f = section(pane, {"tr-help.faq"})
  for _, i in ipairs({1, 2, 3, 4, 6, 7, 8, 9, 10}) do wrap(f.add{type = "label", caption = {"tr-help.faq-" .. i}}) end
end

---------------------------------------------------------------- события
local function refresh_titles_everywhere() C.titles_changed() end

-- "rebuild" — окно надо пересобрать целиком, true — достаточно обновить
function M.on_click(p, el, gs)
  local tag = el.tags.tr
  local admin = is_admin(p)
  local cfg = C.D().cfg
  if tag == "cfg_title_editor" then gs.title_editor = not gs.title_editor; return true end
  if not admin then return false end
  if tag == "cfg_native" or tag == "cfg_native_auto" then
      cfg.native_override = cfg.native_override or {}
    local key = el.tags.planet
    if tag == "cfg_native_auto" then cfg.native_override[key] = nil
    else
      local ov = cfg.native_override[key]
      if not ov then
        ov = {}
        for _, pk in ipairs((PL.native(key))) do ov[pk] = true end
        cfg.native_override[key] = ov
      end
      ov[el.tags.pack] = (not ov[el.tags.pack]) or nil
    end
    for _, s in pairs(game.surfaces) do if C.RP(s) and s.planet.prototype.name == key then PL.check(s, true) end end
    return true
  elseif tag == "cfg_census" then
    p.print(CEN.start() and {"tr-msg.census-started"} or {"tr-msg.census-running"})
    return true
  elseif tag == "cfg_msg_reset" then
    cfg.msg = cfg.msg or {}
    cfg.msg[el.tags.kind] = nil
    return true
  elseif tag == "cfg_titles_reset" then
    cfg.title_over, cfg.titles_custom = {}, {}
    refresh_titles_everywhere()
    TG.apply_all()
    return true
  elseif tag == "cfg_reset_all" then
    for k in pairs(cfg) do cfg[k] = nil end
    refresh_titles_everywhere()
    TG.apply_all()
    return true
  elseif tag == "cfg_ignore" then
    cfg.ignore = cfg.ignore or {}
    local k = el.tags.planet
    cfg.ignore[k] = (not cfg.ignore[k]) or nil
    return true
  elseif tag == "ctitle_del" then
    table.remove(cfg.titles_custom or {}, el.tags.i)
    refresh_titles_everywhere()
    return true
  elseif tag == "new_title_add" then
    local nt = gs.new_title or {}
    if not nt.name or nt.name == "" or not tonumber(nt.n) or tonumber(nt.n) <= 0 then
      p.print({"tr-cfg.new-title-bad"}, {color = {1, 0.6, 0.4}})
      return false
    end
    cfg.titles_custom = cfg.titles_custom or {}
    cfg.title_seq = (cfg.title_seq or 0) + 1
    table.insert(cfg.titles_custom, {id = "custom-" .. cfg.title_seq, name = nt.name, key = nt.key or "kills",
      n = stored_n(nt.key or "kills", tonumber(nt.n))})
    gs.new_title = nil
    refresh_titles_everywhere()
    for _, pl in pairs(game.connected_players) do C.check_titles(pl) end
    return true
  end
  return false
end

function M.on_checked(p, el, gs)
  local tag = el.tags.tr
  if tag == "pcfg" then
    C.pset(p, el.tags.key, el.state)
    if el.tags.retag then TG.apply(p); return true end
    if el.tags.key == "button" then return "button" end
    return el.tags.rebuild and "rebuild" or false
  end
  if not is_admin(p) then return true end
  local cfg = C.D().cfg
  if tag == "cfg" then
    C.set(el.tags.key, el.state)
    if el.tags.key == "tr-chat-titles" then TG.apply_all() end
    if el.tags.key == "tr-space-gate" and C.hooks.space_unlocked then C.hooks.space_unlocked() end
    return false
  elseif tag == "cfg_planet_titles" then
    cfg.planet_titles_off = (not el.state) or nil
    refresh_titles_everywhere()
    return false
  elseif tag == "title_on" then
    cfg.title_over = cfg.title_over or {}
    cfg.title_over[el.tags.id] = cfg.title_over[el.tags.id] or {}
    cfg.title_over[el.tags.id].off = (not el.state) or nil
    refresh_titles_everywhere()
    return false
  elseif tag == "ctitle_on" then
    local ct = (cfg.titles_custom or {})[el.tags.i]
    if ct then ct.off = (not el.state) or nil end
    refresh_titles_everywhere()
    return false
  end
  return false
end

function M.on_selection(p, el, gs)
  local tag = el.tags.tr
  if tag == "pcfg_ar" then
    C.pset(p, "autorefresh", el.tags.values[el.selected_index] or 0)
    return false
  elseif tag == "pcfg_tab" then
    C.pset(p, "open-tab", el.tags.opts[el.selected_index] or "last")
    return false
  elseif tag == "new_title_key" then
    gs.new_title = gs.new_title or {name = "", n = 100}
    gs.new_title.key = C.TITLE_KEYS[el.selected_index] or "kills"
    return false
  end
  if not is_admin(p) then return true end
  if tag == "cfg_aud" then
    local mc = C.msgcfg(el.tags.kind)
    local a = el.tags.auds[el.selected_index] or "all"
    mc.aud = a ~= "all" and a or nil
    return false
  end
  return false
end

function M.on_text(p, el, gs)
  local tag = el.tags.tr
  if tag == "new_title_name" then
    gs.new_title = gs.new_title or {key = "kills", n = 100}
    gs.new_title.name = el.text
    return
  elseif tag == "new_title_n" then
    gs.new_title = gs.new_title or {key = "kills", name = ""}
    gs.new_title.n = tonumber(el.text) or 0
    return
  end
  if not is_admin(p) then return end
  local cfg = C.D().cfg
  if tag == "cfg_tpl" then
    local mc = C.msgcfg(el.tags.kind)
    mc.tpl = el.text ~= "" and el.text or nil
  elseif tag == "title_name" or tag == "title_n" then
    cfg.title_over = cfg.title_over or {}
    local o = cfg.title_over[el.tags.id] or {}
    cfg.title_over[el.tags.id] = o
    if tag == "title_name" then o.name = el.text ~= "" and el.text or nil
    else
      local v = tonumber(el.text)
      o.n = (v and v > 0) and stored_n(el.tags.key, v) or nil
    end
    refresh_titles_everywhere()
  elseif tag == "ctitle_name" or tag == "ctitle_n" then
    local ct = (cfg.titles_custom or {})[el.tags.i]
    if not ct then return end
    if tag == "ctitle_name" then ct.name = el.text
    else
      local v = tonumber(el.text)
      if v and v > 0 then ct.n = stored_n(el.tags.key, v) end
    end
    refresh_titles_everywhere()
  end
end

return M
