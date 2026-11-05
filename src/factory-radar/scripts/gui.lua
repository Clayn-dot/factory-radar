-- Factory Radar: окно команды за кнопкой радара
local mod_gui = require("mod-gui")
local C = require("scripts.core")
local P = require("scripts.planets")
local RS = require("scripts.research")
local WH = require("scripts.where")
local SH = require("scripts.shift")
local CB = require("scripts.combat")
local TG = require("scripts.tags")
local GSET = require("scripts.gui_settings")
local PF = require("scripts.platforms")
local QL = require("scripts.quality")
local EN = require("scripts.energy")
local ZAP = require("scripts.zap")
local RU = require("scripts.roulette")
local RST = require("scripts.reset")
local LG = require("scripts.logistics")
local M = {}

local BTN, FRAME, FIND = "tr_button", "tr_frame", "tr_find"
local function icon() return settings.startup["tr-s-white-icon"].value and "tr-radar-white" or "item/radar" end

local W = 1000

local COLS = {
  {key = "kills", f = C.n}, {key = "built", f = C.n}, {key = "craft", f = C.n},
  {key = "walk", f = C.km}, {key = "ride", f = C.km}, {key = "mined", f = C.n}, {key = "lost", f = C.n},
  {key = "deaths", f = C.n},
}
M.COLS = COLS

function M.ensure_button(p)
  if not (p and p.valid) then return end
  local flow = mod_gui.get_button_flow(p)
  if C.P(p, "button") then
    if flow[BTN] and (flow[BTN].sprite ~= icon() or flow[BTN].style.name ~= "slot_button") then flow[BTN].destroy() end
    if not flow[BTN] then
      flow.add{type = "sprite-button", name = BTN, sprite = icon(), style = "slot_button",
        tooltip = {"tr-gui.button-tooltip"}}
    end
  elseif flow[BTN] then
    flow[BTN].destroy()
  end
end

local function GS(p)
  local g = C.D().gui
  g[p.index] = g[p.index] or {scope = "shift", sort = "built"}
  return g[p.index]
end

---------------------------------------------------------------- мелкие блоки
local function wrap(label, width)
  label.style.single_line = false
  label.style.maximal_width = width or (W - 100)
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
  l.style.top_margin = 8
  l.style.bottom_margin = 4
  return l
end
-- рамки верхнего уровня в области прокрутки получают одну и ту же ширину. Без неё они ужимаются до ширины
-- своего содержимого (в области прокрутки stretchable растягивает только до самого широкого элемента),
-- и у коротких вкладок справа остаётся больше места, чем слева
-- Один стандарт для всех вкладок. Область прокрутки занимает всю ширину окна (раньше справа пропадало около 40 px),
-- справа всегда место под полосу прокрутки (BAR), слева такой же запас, поэтому края симметричны с полосой и без неё
local PANE_W, PAD_L, PAD_R, BAR = W + 60, 22, 8, 14
local CARD_W = PANE_W - PAD_L - PAD_R - BAR - 6
local function full_width(f, parent)
  if parent.type == "scroll-pane" then f.style.minimal_width = CARD_W end
end
-- карточка с заголовком (светлее) и тёмная рамка под данные
local function card_frame(parent, title, tip)
  local f = parent.add{type = "frame", direction = "vertical", style = "inside_shallow_frame_with_padding"}
  f.style.horizontally_stretchable = true
  full_width(f, parent)
  f.style.top_margin = 2
  f.style.bottom_margin = 8
  if title then
    local l = f.add{type = "label", caption = title, style = "caption_label"}
    l.tooltip = tip
    l.style.bottom_margin = 6
  end
  return f
end
local function deep_frame(parent)
  local f = parent.add{type = "frame", direction = "vertical", style = "inside_deep_frame"}
  f.style.horizontally_stretchable = true
  full_width(f, parent)
  f.style.padding = 10
  return f
end
-- админам: «Сбросить» / «Откатить» статистику вкладки
local function reset_bar(p, pane, sec)
  if not p.admin then return end
  local row = pane.add{type = "flow", direction = "horizontal"}
  row.style.top_margin = 10
  local b = row.add{type = "button", caption = {"tr-gui.reset"}, tooltip = {"tr-gui.tip-reset"}, tags = {tr = "reset", sec = sec}}
  b.style.height = 24
  b.style.minimal_width = 0
  b.style.padding = {0, 8}
  if RST.can_undo(sec) then
    local u = row.add{type = "button", caption = {"tr-gui.undo"}, tooltip = {"tr-gui.tip-undo"}, tags = {tr = "undo", sec = sec}}
    u.style.height = 24
    u.style.minimal_width = 0
    u.style.padding = {0, 8}
  end
end
local function bar(parent, value, caption, width, tooltip)
  local row = parent.add{type = "flow", direction = "horizontal"}
  row.style.vertical_align = "center"
  local pb = row.add{type = "progressbar", value = math.max(0, math.min(1, value or 0)), tooltip = tooltip}
  pb.style.width = width or 220
  if caption then
    local l = row.add{type = "label", caption = caption, tooltip = tooltip}
    l.style.left_margin = 6
  end
  return row
end
local ZAP_SPRITE = nil
function M.zap_sprite()
  if not ZAP_SPRITE then
    ZAP_SPRITE = "utility/questionmark"
    for _, sp in ipairs({"utility/electricity_icon", "item/lightning-rod", "item/lightning-collector"}) do
      if helpers.is_valid_sprite_path(sp) then ZAP_SPRITE = sp break end
    end
  end
  return ZAP_SPRITE
end
local function smallbtn(parent, sprite, tooltip, tags)
  return parent.add{type = "sprite-button", sprite = sprite, style = "mini_button", tooltip = tooltip, tags = tags}
end

---------------------------------------------------------------- охват: эта смена (по умолчанию) или всё время
local function scope(p) return GS(p).scope == "total" and "total" or "shift" end
local function sk(p, key) return key .. "-" .. scope(p) end   -- ключ локали с суффиксом охвата

-- «построил» за всё время: по стоящим постройкам планет (с роботами), как в «родном» подсчёте планет, но не меньше ручного счётчика.
-- Возвращает копию таблицы игроков за всё время с уточнённым built
local function total_with_built(d)
  local sums = {}
  for _, by in pairs(d.pbuilt or {}) do
    for name, n in pairs(by) do sums[name] = (sums[name] or 0) + n end
  end
  local view = {}
  for name, r in pairs(d.total) do
    local c = {}
    for k, v in pairs(r) do c[k] = v end
    c.built = math.max(sums[name] or 0, r.built or 0)
    view[name] = c
  end
  for name, n in pairs(sums) do
    if not view[name] then
      local c = C.blank()
      c.built = n
      view[name] = c
    end
  end
  return view
end

---------------------------------------------------------------- шапка
local function fill_header(p, h)
  h.clear()
  local rd, rt = RS.progress()
  local rp = rt > 0 and rd / rt or 0
  local done, open = C.count_mastered()
  local all = C.planets_in_game()
  local row = h.add{type = "flow", direction = "horizontal"}
  row.style.horizontal_spacing = 16
  -- четыре одинаковые колонки с тонкими разделителями: ровно и места не прыгают от длины текста
  local COLW = 226
  local function sep()
    local ln = row.add{type = "line", direction = "vertical"}
    ln.style.vertically_stretchable = true
  end
  local c1 = row.add{type = "flow", direction = "vertical"}
  c1.style.width = COLW
  c1.add{type = "label", caption = {"tr-gui.header-research"}, style = "caption_label", tooltip = {"tr-gui.tip-header-research"}}
  bar(c1, rp, {"tr-gui.header-research-val", math.floor(rp * 100), rd, rt}, 90, {"tr-gui.tip-header-research"})
  sep()
  local c2 = row.add{type = "flow", direction = "vertical"}
  c2.style.width = COLW
  c2.add{type = "label", caption = {"tr-gui.header-planets"}, style = "caption_label", tooltip = {"tr-gui.tip-header-planets"}}
  bar(c2, all > 0 and done / all or 0, {"tr-gui.header-planets-val", done, all, open}, 90, {"tr-gui.tip-header-planets"})
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
  -- длинные названия планет переносятся в колонке, а не раздвигают шапку
  wrap(c4.add{type = "label", caption = {"tr-gui.header-combat-val", C.n(total_scope and cs.total or cs.shift),
    kp and {"tr-gui.header-kills-where", C.planet_ls(kp)} or ""}, tooltip = ctip}, COLW - 12)
  sep()
  local c3 = row.add{type = "flow", direction = "vertical"}
  c3.style.width = COLW
  local online = 0
  for _ in pairs(game.connected_players) do online = online + 1 end
  c3.add{type = "label", caption = {"tr-gui.header-online", online}}
  c3.add{type = "label", caption = {"tr-gui.header-shift", SH.minutes_left()},
    tooltip = {"tr-gui.tip-shift-len", string.format("%g", math.floor(C.shift_ticks() / 216000 * 10 + 0.5) / 10)}}
  -- время игры: точкой во времени и в скобках сколько всего прошло (чтобы «13 д 15:04» было понятно)
  do
    local mins = math.floor(game.tick / 3600)
    local hours = math.floor(mins / 60)
    -- как в самой игре: часы без сброса на сутки («327:04»), в скобках дни и часы
    c3.add{type = "label", caption = {"tr-gui.header-time", string.format("%d:%02d", hours, mins % 60), {"tr.time-dh", math.floor(hours / 24), hours % 24}},
      tooltip = {"tr-gui.tip-header-time"}}
  end
end

---------------------------------------------------------------- Сводка
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

-- первое, что видит игрок: что такое смена и куда идти дальше
-- закрываемый гид: для чего каждая вкладка (сами вкладки сразу ниже)
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
  hide.style.padding = {0, 6}
  hide.style.top_margin = 4
end

-- блок «Полезно знать»: главные факты в паре строк и подсказка, которая меняется раз в минуту
local TIPS = 20
local function good_to_know(p, pane)
  if not C.P(p, "know") then return end       -- игрок скрыл (Настройки или кнопка ниже)
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
  local tip = (math.floor(game.tick / 3600) + (GS(p).tip_shift or 0)) % TIPS + 1
  local tl = wrap(box.add{type = "label", caption = {"", "[img=utility/tip_icon] ", {"tr-tips.t" .. tip}}}, W - 90)
  tl.style.top_margin = 6
  tl.style.font_color = {1, 0.9, 0.6}
  local hide = box.add{type = "button", caption = {"tr-gui.know-hide"}, tooltip = {"tr-gui.know-hide-tip"}, tags = {tr = "pcfg_set", key = "know", value = false}}
  hide.style.height = 22
  hide.style.minimal_width = 0
  hide.style.padding = {0, 6}
  hide.style.top_margin = 4
end

local fill_card     -- определена ниже вместе с карточкой игрока (сводка тоже её показывает)

local function fill_summary(p, pane)
  pane.clear()
  intro(p, pane)
  good_to_know(p, pane)
  local d = C.D()
  local sc = scope(p)
  local tbl = sc == "total" and total_with_built(d) or d.shift

  -- лидеры
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

  -- планеты: выпуск за смену
  local pcard = card_frame(pane, {sk(p, "tr-gui.sum-planets")}, {"tr-gui.tip-output"})
  local pbox = deep_frame(pcard)
  -- планеты без выпуска не показываем
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

  -- бой и разрушения: одна общая карточка, между половинами одна линия
  local dcard = card_frame(pane)
  local duo = dcard.add{type = "flow", direction = "horizontal"}
  duo.style.horizontal_spacing = 10
  duo.style.horizontally_stretchable = true
  local cs = CB.S()
  local kills = sc == "total" and cs.total or cs.shift
  -- две одинаковые половины, в каждой одна строка
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

  -- как дела: энергия, платформы
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
    gb.style.height = 22
    gb.style.minimal_width = 0
    gb.style.padding = {0, 8}
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
    pgb.style.padding = {0, 8}
  end

  -- игроки: клик по имени — статистика
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
    b.style.padding = {0, 8}
  end
  if gs.sum_card then
    local cbox = deep_frame(pcard)
    cbox.style.top_margin = 6
    fill_card(p, cbox, gs.sum_card, true)
  end

  -- викторина
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
      rb.style.padding = {0, 10}
    end
  end

  mvp_block(p, pane)      -- голосование идёт за текущую смену, поэтому видно и при «Всё время»

  -- последние 10 выборов MVP, свёрнуто
  local hist = d.mvp_hist or {}
  local open = GS(p).mvp_hist_open
  local hrow = pane.add{type = "flow", direction = "horizontal"}
  hrow.style.vertical_align = "center"
  hrow.style.top_margin = 6
  local hb = hrow.add{type = "button", caption = open and {"tr-gui.mvp-hist-hide"} or {"tr-gui.mvp-hist-show", #hist},
    tags = {tr = "mvp_hist_toggle"}}
  hb.style.height = 22
  hb.style.minimal_width = 0
  hb.style.padding = {0, 8}
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

---------------------------------------------------------------- Кто где
-- как выглядят кнопки строки: если меняется — строку надо пересобрать (иначе двигаются только тексты и кулдауны)
function M.where_sig(p, r)
  return table.concat({r.player.index, r.body and "b" or "-", r.look and "l" or "-",
    (C.S("tr-zap") and r.player.connected) and "z" or "-"}, ":")
end
local function fill_where(p, pane)
  pane.clear()
  local rows = WH.rows(p)
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
    -- три фиксированных места в одном порядке (молния, где, смотрит): нет кнопки — место пустое,
    -- чтобы кнопка не прыгала, когда появляется «смотрит»
    local function slot() local s = btns.add{type = "flow", direction = "horizontal"}; s.style.width = 17; return s end      -- мини-кнопка шириной 16: один пиксель между ними
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
    -- по строке на каждого, без переносов: кто | где и что делает | куда смотрит. Что не влезло — обрезается,
    -- полный текст в подсказке
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
fill_card = function(p, pane, name, embedded)
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
    for _, w in ipairs(pw) do bar(pane, w[2] / mx, {"", C.weapon_ls(w[1]), " — ", C.n(w[2])}, 160) end
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
  if gs.card then fill_card(p, pane, gs.card); return end
  local d = C.D()
  local tbl = scope(p) == "total" and total_with_built(d) or d.shift
  local pcard = card_frame(pane, {sk(p, "tr-gui.players-scope")})
  muted(pcard, {"tr-gui.players-how"})
  if not next(tbl) then muted(pcard, {sk(p, "tr-gui.why-no-leaders")}) end
  local box = deep_frame(pcard)
  local t = box.add{type = "table", column_count = #COLS + 3, draw_horizontal_line_after_headers = true, draw_horizontal_lines = true}
  t.style.horizontal_spacing = 4
  t.style.vertical_spacing = 4
  local function centered(lbl, width)
    lbl.style.minimal_width = width
    lbl.style.horizontal_align = "center"
    return lbl
  end
  local hp = t.add{type = "label", caption = {"tr-gui.col-player"}, style = "caption_label"}
  hp.style.minimal_width = 130
  -- заголовки — плоский кликабельный текст (как «Звания» и «Награды»); отсортированный золотой со стрелкой
  local function header(key, caption, tip, width)
    local on = gs.sort == key
    local b = t.add{type = "button", style = "list_box_item", caption = {"", caption, on and " ▼" or ""},
      tags = {tr = "sort", key = key}, tooltip = {"", {"tr-gui.sort"}, "\n", tip}}
    b.style.font = "default-bold"
    b.style.font_color = on and {1, 0.85, 0.3} or {1, 0.9, 0.75}
    b.style.minimal_width = width
    b.style.horizontal_align = "center"
    b.style.height = 24
    b.style.padding = {0, 2}
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
    nb.style.padding = {0, 6}
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

local function fill_planets(p, pane)
  pane.clear()
  local d = C.D()
  -- все видимые планеты игры, в том числе где ещё никто не был
  local rows = {}
  for key, pl in pairs(game.planets) do
    if not pl.prototype.hidden then
      local surf = pl.surface
      rows[#rows + 1] = {key = key, pl = pl, s = (surf and surf.valid) and surf or nil, st = C.PL(key)}
    end
  end
  local gs = GS(p)
  local frozen = gs.nat_rank or {}
  local function natural_rank(r) if r.st.mastered then return 0 elseif r.s then return 1 end return 2 end
  -- пока редактируется родная наука планеты, она держит своё место (смена может сдвинуть ранг)
  for _, r in ipairs(rows) do
    if (gs.nat_edit or {})[r.key] then
      if frozen[r.key] == nil then frozen[r.key] = natural_rank(r) end
    else
      frozen[r.key] = nil
    end
  end
  gs.nat_rank = frozen
  local function rank(r) return frozen[r.key] or natural_rank(r) end
  table.sort(rows, function(a, b)
    if rank(a) ~= rank(b) then return rank(a) < rank(b) end
    return a.key < b.key
  end)
  local done, open = C.count_mastered()
  local pcard = card_frame(pane, {"tr-gui.tab-planets"})
  local sbar = bar(pcard, #rows > 0 and done / #rows or 0, {"tr-gui.planets-summary", done, open, #rows}, 260)
  sbar.style.bottom_margin = 8
  for _, r in ipairs(rows) do
    local key, st = r.key, r.st
    local card = pcard.add{type = "frame", direction = "horizontal", style = "inside_deep_frame"}
    card.style.horizontally_stretchable = true
    card.style.padding = 8
    card.style.bottom_margin = 6
    -- значок планеты по вертикали посередине карточки
    local ibox = card.add{type = "flow", direction = "vertical"}
    ibox.style.vertically_stretchable = true
    ibox.style.vertical_align = "center"
    local icon = ibox.add{type = "sprite", sprite = "space-location/" .. key}
    icon.style.width = 36
    icon.style.height = 36
    icon.style.stretch_image_to_widget_size = true
    local col = card.add{type = "flow", direction = "vertical"}
    col.style.left_margin = 8
    col.style.horizontally_stretchable = true      -- карточка планеты на всю ширину
    local status
    if st.mastered then status = {"tr-gui.planet-mastered", st.by or {"tr-gui.before-install"}}
    elseif r.s then status = {"tr-gui.planet-in-progress"}
    else status = {"tr-gui.planet-unvisited"} end
    local head = col.add{type = "flow", direction = "horizontal"}
    head.style.vertical_align = "center"
    head.style.horizontally_stretchable = true
    head.add{type = "label", caption = {"", "[font=default-bold]", r.pl.prototype.localised_name, "[/font]  ", status}}
    local hfill = head.add{type = "empty-widget"}
    hfill.style.horizontally_stretchable = true
    local _, hmanual = P.native(key)
    local ned = (gs.nat_edit or {})[key]
    local nbox = head.add{type = "flow", direction = "horizontal"}
    nbox.style.vertical_align = "center"
    nbox.style.horizontal_spacing = 8
    if hmanual then
      local nl = nbox.add{type = "label", caption = {"tr-gui.native-manual"}, tooltip = {"tr-gui.native-tip"}}
      nl.style.font_color = {1, 0.8, 0.4}
      nl.style.font = "default-small"
    end
    local ne = nbox.add{type = "button", caption = ned and {"tr-gui.native-done"} or {"tr-gui.native-edit"},
      tags = {tr = "nat_edit", planet = key}, tooltip = {"tr-gui.native-tip"}}
    ne.style.height = 22
    ne.style.minimal_width = 0
    ne.style.padding = {0, 8}
    if ned then
      local ebox = col.add{type = "frame", direction = "vertical", style = "inside_deep_frame"}
      ebox.style.horizontally_stretchable = true
      ebox.style.padding = 8
      ebox.style.top_margin = 4
      ebox.style.bottom_margin = 4
      muted(ebox, {"tr-gui.native-help"})
      local on = {}
      for _, pk in ipairs((P.native(key))) do on[pk] = true end
      local grid = ebox.add{type = "table", column_count = 16}
      grid.style.horizontal_spacing = 0
      grid.style.vertical_spacing = 0
      for _, pk in ipairs(P.science_names()) do
        local it = prototypes.item[pk]
        local b = grid.add{type = "sprite-button", sprite = "item/" .. pk, style = "slot_button", toggled = on[pk] or false,
          tags = {tr = "cfg_native", planet = key, pack = pk}, tooltip = it and it.localised_name or pk}
        b.style.width = 28
        b.style.height = 28
        b.enabled = p.admin
      end
      if hmanual then
        local rb = ebox.add{type = "button", caption = {"tr-gui.native-reset"}, tags = {tr = "cfg_native_auto", planet = key}}
        rb.style.height = 22
        rb.style.minimal_width = 0
        rb.style.padding = {0, 8}
        rb.style.top_margin = 4
        rb.enabled = p.admin
      end
      if not p.admin then muted(ebox, {"tr-gui.native-admin"}) end
    end
    if r.s then
      local first = d.first[key]
      local sci_ok, list = P.science_state(key)
      local nsteps = 2 + math.max(1, #list)
      local got = (first and 1 or 0) + (st.silo and 1 or 0)
      local packs = {}        -- {предмет, орбитальная?, есть?}
      if #list == 0 then
        local pack = st.pack and prototypes.item[st.pack] and st.pack or "automation-science-pack"
        packs[1] = {pack, false, sci_ok}
        if sci_ok then got = got + 1 end
      else
        for _, x in ipairs(list) do
          packs[#packs + 1] = {x[1], P.is_orbital(key, x[1]), x[2]}
          if x[2] then got = got + 1 end
        end
      end
      local silo = st.silo_name and prototypes.entity[st.silo_name] and st.silo_name or "rocket-silo"
      local _, manual = P.native(key)
      local why = {""}
      for _, x in ipairs(list) do
        local sc = P.why(key, x[1])
        local sig = {""}
        if sc and sc.orbit then sig[#sig + 1] = {"", " ", {"tr-gui.sig-orbit"}} end
        local it = prototypes.item[x[1]]
        why[#why + 1] = {"", "\n[item=" .. x[1] .. "] ", it and it.localised_name or x[1], sig}
        if #why >= 18 then why = {"", why} end
      end
      local tip = #list == 0 and {"tr-gui.tip-native-any"} or {"tr-gui.tip-native", why}
      local brow = col.add{type = "flow", direction = "horizontal"}
      brow.style.vertical_align = "center"
      bar(brow, st.mastered and 1 or got / nsteps, {"tr-gui.planet-steps4", first and "✓" or "✗",
        "[entity=" .. silo .. "]", st.silo and "✓" or "✗"}, 150, tip)
      local pbox = brow.add{type = "flow", direction = "horizontal"}
      pbox.style.vertical_align = "center"
      pbox.style.left_margin = 10
      local pn = pbox.add{type = "label", caption = {"tr-gui.planet-native-head"}, tooltip = tip}
      pn.style.font_color = {0.75, 0.75, 0.75}
      local ptab2 = pbox.add{type = "table", column_count = math.max(1, math.floor((W - 595) / 44))}
      ptab2.style.horizontal_spacing = 4
      ptab2.style.vertical_spacing = 2
      for _, x in ipairs(packs) do
        local orb = x[2] and "[img=item/space-platform-starter-pack]" or ""
        local cl2 = ptab2.add{type = "label", caption = "[item=" .. x[1] .. "]" .. orb .. " " .. (x[3] and "✓" or "✗"), tooltip = tip}
        cl2.style.minimal_width = 40
        cl2.style.single_line = true
        cl2.style.font_color = {0.75, 0.75, 0.75}
      end
      local made = P.made_here(r.s)
      -- только то, что реально сделано здесь (пак с 0 не показываем)
      local native_list = P.native(key)
      if #made > 0 then
        local nat = {}
        for _, pk in ipairs(native_list) do nat[pk] = true end
        local items, nat_packs, other_packs = {}, {}, {}
        for _, m in ipairs(made) do
          if P.is_science(m[1]) then
            if nat[m[1]] then nat_packs[#nat_packs + 1] = m else other_packs[#other_packs + 1] = m end
          else
            items[#items + 1] = m
          end
        end
        -- науки: все виды, что делались здесь; обычные предметы: шесть крупнейших
        local function line(list, limit)
          local parts = {}
          for i, m in ipairs(list) do
            if not limit or i <= limit then parts[#parts + 1] = {"", "[item=" .. m[1] .. "] ", C.n(m[2])} end
          end
          return C.join(parts, "   ")
        end
        if #nat_packs > 0 then
          wrap(col.add{type = "label", caption = {"tr-gui.planet-made-nat", line(nat_packs)}, tooltip = {"tr-gui.planet-made-sci-tip"}}, W - 150)
        end
        if #other_packs > 0 then
          wrap(col.add{type = "label", caption = {"tr-gui.planet-made-other", line(other_packs)}, tooltip = {"tr-gui.planet-made-sci-tip"}}, W - 150)
        end
        if #items > 0 then
          wrap(col.add{type = "label", caption = {"tr-gui.planet-made", line(items, 6)}, tooltip = {"tr-gui.planet-made-tip"}}, W - 150)
        end
      end
      local info = {}
      if first then info[#info + 1] = {"tr-gui.planet-first", first.who == "?" and {"tr-gui.before-install"} or first.who} end
      if st.last then
        info[#info + 1] = {"tr-gui.planet-shift", C.n(st.last.out),
          st.last.vs and {"tr-gui.planet-vs", P.vs_text(st.last.vs)} or ""}
      end
      if (d.plost[key] or 0) > 0 then info[#info + 1] = {"tr-gui.planet-lost", C.n(d.plost[key])} end
      if #info > 0 then
        local l = wrap(col.add{type = "label", caption = C.join(info, " · ")}, W - 150)
        l.style.font_color = {0.75, 0.75, 0.75}
      end
      if st.history and #st.history > 0 then
        -- выпуск за три последние смены числами, старая первой; всегда отдельной строкой у левого края
        local n = #st.history
        local parts = {}
        for i = math.max(1, n - 2), n do parts[#parts + 1] = C.n(st.history[i]) end
        local hl = col.add{type = "label", caption = {"tr-gui.planet-history3", C.join(parts, " → ")}, tooltip = {"tr-gui.planet-history-tip"}}
        hl.style.font_color = {0.6, 0.6, 0.6}
      end
    else
      local nat = P.native(key)
      local icons = ""
      for _, pk in ipairs(nat) do icons = icons .. "[item=" .. pk .. "]" end
      local l = col.add{type = "label", caption = {"tr-gui.planet-unvisited-hint", icons ~= "" and {"tr-gui.planet-native", icons} or ""}}
      l.style.font_color = {0.55, 0.55, 0.55}
    end
  end
  muted(pane, {"tr-gui.planets-hint"})
end

local function fill_research(p, pane)
  pane.clear()
  local f = game.forces.player
  local cur = f.current_research
  local cbox = deep_frame(card_frame(pane, {"tr-gui.research-current"}))
  if cur then
    bar(cbox, f.research_progress, {"", "[technology=" .. cur.name .. "] ", cur.localised_name,
      " — " .. math.floor(f.research_progress * 100) .. "%"}, 240)
  else
    muted(cbox, {"tr-gui.research-idle"})
  end

  -- что реально тратят лаборатории, рядом с тем, что делается (статистика за 10 минут)
  local sbox = deep_frame(card_frame(pane, {"tr-gui.sci-head"}, {"tr-gui.sci-tip"}))
  local use = RS.consumption()
  if #use == 0 then muted(sbox, {"tr-gui.sci-none"}) else
    local ut = sbox.add{type = "table", column_count = 4, draw_horizontal_line_after_headers = true}
    ut.style.horizontal_spacing = 18
    for _, h in ipairs({"pack", "made", "spent", "where"}) do
      ut.add{type = "label", caption = {"tr-gui.sci-col-" .. h}, style = "caption_label"}
    end
    for _, r in ipairs(use) do
      ut.add{type = "label", caption = {"", "[item=" .. r.name .. "] ", prototypes.item[r.name].localised_name}}
      ut.add{type = "label", caption = {"tr-gui.sci-rate", string.format("%.1f", r.made)}}
      local lack = r.spent > r.made * 1.05 and r.spent > 0.05
      ut.add{type = "label", caption = {"", lack and "[color=1,0.6,0.45]" or "[color=0.7,1,0.7]", {"tr-gui.sci-rate", string.format("%.1f", r.spent)}, "[/color]"}}
      ut.add{type = "label", caption = r.where and (r.platform and r.where or C.planet_ls(r.where)) or "—"}
    end
  end

  local rows = RS.infinite_rows()
  local ibox = deep_frame(card_frame(pane, {"tr-gui.research-infinite"}))
  if #rows == 0 then muted(ibox, {"tr-gui.why-no-infinite"}) end
  local t = ibox.add{type = "table", column_count = 3, draw_horizontal_line_after_headers = true}
  t.style.horizontal_spacing = 14
  for _, h in ipairs({"tech", "level", "gained"}) do
    t.add{type = "label", caption = {"tr-gui.research-col-" .. h}, style = "caption_label"}
  end
  for i = 1, math.min(25, #rows) do
    local r = rows[i]
    t.add{type = "label", caption = {"", "[technology=" .. r.tech.name .. "] ", r.tech.localised_name}}
    t.add{type = "label", caption = {"", "[font=default-bold]", tostring(r.level), "[/font]"}}
    t.add{type = "label", caption = {"tr-gui.research-gained", r.shift, r.total}}
  end

  local ms = RS.milestone_rows()
  local mbox = deep_frame(card_frame(pane, {"tr-gui.research-milestones"}))
  if #ms == 0 then muted(mbox, {"tr-gui.research-milestones-none"}) else
    local mt = mbox.add{type = "table", column_count = 1 + #RS.MILESTONES, draw_horizontal_line_after_headers = true}
    mt.style.horizontal_spacing = 8
    mt.add{type = "label", caption = {"tr-gui.research-col-pack"}, style = "caption_label"}
    -- короткие заголовки (1, 1k, 10k ... 1M, 1B), чтобы все колонки влезли в окно
    local function short(th)
      if th >= 1e9 then return (th / 1e9) .. "B" elseif th >= 1e6 then return (th / 1e6) .. "M"
      elseif th >= 1e3 then return (th / 1e3) .. "k" end
      return tostring(th)
    end
    for _, th in ipairs(RS.MILESTONES) do
      local hl = mt.add{type = "label", caption = {"tr-gui.research-col-nth", short(th)}, style = "caption_label",
        tooltip = {"tr-gui.research-col-nth-tip", C.big(th)}}
      hl.style.minimal_width = 96
    end
    for _, r in ipairs(ms) do
      local pn = wrap(mt.add{type = "label", caption = {"", "[item=" .. r.name .. "] ", prototypes.item[r.name].localised_name}}, 190)
      pn.style.minimal_width = 190
      for _, th in ipairs(RS.MILESTONES) do
        local m = r.m[th]
        local cap
        if not m then cap = "[color=0.45,0.45,0.45]—[/color]"
        elseif m.before then cap = {"", "[color=0.6,0.6,0.6]", {"tr-gui.before-install"}, "[/color]"}
        else cap = {"", "[font=default-bold]", C.clock(m.tick), "[/font]", m.place and (" [img=space-location/" .. m.place .. "]") or ""} end
        local cl = mt.add{type = "label", caption = cap}
        cl.style.minimal_width = 96
      end
    end
  end

  reset_bar(p, pane, "research")
end

-- Какие планеты/платформы показывать: кнопка справа в заголовке открывает панельку РЯДОМ с окном.
-- Панель не закрывается при переключении (выпадающий список закрывался бы после каждого клика)
-- и ничего не двигает во вкладке. Светлое = показано, утопленное = скрыто. Скрытое вообще не считается.
-- Планеты: у «q» (Качество), «e» (Энергия), «c» (Бой) свой выбор; «pl» — платформы
local FLT = "tr_filter"
local FLT_TAB = {q = "quality", e = "energy", pl = "platforms", c = "combat"}
local function hidden_set(p, which) return GS(p)[which == "pl" and "hide_plats" or ("hide_" .. which)] or {} end
local function hidden_planets(p, which) return hidden_set(p, which) end
local function planet_entries()
  local list = {}
  for _, sf in pairs(game.surfaces) do
    if C.RP(sf) then list[#list + 1] = {id = sf.planet.prototype.name, caption = C.planet_ls(sf.planet.prototype.name)} end
  end
  table.sort(list, function(a, b) return a.id < b.id end)
  return list
end
local function filter_entries(which)
  if which == "pl" then
    local list = {}
    for _, pl in pairs(game.forces.player.platforms) do if pl.valid then list[#list + 1] = {id = pl.index, caption = pl.name} end end
    table.sort(list, function(a, b) return a.caption < b.caption end)
    return list
  elseif which == "c" then
    local list = {}
    for _, r in ipairs(CB.evo_rows()) do list[#list + 1] = {id = r.key, caption = C.planet_ls(r.key)} end
    table.sort(list, function(a, b) return a.id < b.id end)
    return list
  end
  return planet_entries()
end
local function filter_button(p, parent, which, entries)
  if #entries < 2 then return end
  local hidden = hidden_set(p, which)
  local shown = 0
  for _, e in ipairs(entries) do if not hidden[e.id] then shown = shown + 1 end end
  local fill = parent.add{type = "empty-widget"}
  fill.style.horizontally_stretchable = true
  local b = parent.add{type = "button", caption = {"tr-gui.flt-btn-" .. which, shown, #entries}, tags = {tr = "flt_open", which = which},
    tooltip = {"tr-gui.flt-tip"}, toggled = GS(p).flt_open == which}
  b.style.height = 24
  b.style.minimal_width = 0
  b.style.padding = {0, 10}
  return b
end

local function fill_combat(p, pane)
  pane.clear()
  local gs = GS(p)
  local shift = scope(p) == "shift"
  local s = CB.S()
  local total = shift and s.shift or s.total
  local wbox = deep_frame(card_frame(pane, {shift and "tr-gui.combat-total-shift" or "tr-gui.combat-total-total", C.n(total)}))
  local wh = wbox.add{type = "label", caption = {"tr-gui.combat-weapons"}, style = "caption_label", tooltip = {"tr-gui.tip-weapons"}}
  wh.style.bottom_margin = 4
  local ws = CB.top(shift and s.weap_shift or s.weap, 10)
  if #ws == 0 then muted(wbox, {sk(p, "tr-gui.why-no-kills")}) end
  local mx = ws[1] and ws[1][2] or 1
  for _, w in ipairs(ws) do
    local pct = math.floor(w[2] / math.max(1, total) * 100 + 0.5)
    local wr = bar(wbox, w[2] / mx, {"", C.weapon_ls(w[1]), " — ", C.n(w[2]), "  (" .. pct .. "%)"}, 200,
      {"tr-gui.tip-weapon", C.n(w[2]), pct})
    wr.style.bottom_margin = 3
  end

  local pcard = card_frame(pane, {"tr-gui.combat-planets"})
  -- какие планеты показывать: тот же список, что в других вкладках (без врагов — скрыты сразу)
  local all = CB.evo_rows()
  table.sort(all, function(a, b) return a.key < b.key end)
  if not gs.hide_c_init then
    gs.hide_c_init = true
    gs.hide_c = gs.hide_c or {}
    for _, r in ipairs(all) do if not r.active then gs.hide_c[r.key] = true end end
  end
  local hidden_c = gs.hide_c or {}
  local picker = pcard.add{type = "flow", direction = "horizontal"}
  picker.style.bottom_margin = 6
  picker.style.vertical_align = "center"
  picker.style.horizontally_stretchable = true
  local entries = {}
  for _, r in ipairs(all) do entries[#entries + 1] = {id = r.key, caption = C.planet_ls(r.key)} end
  filter_button(p, picker, "c", entries)
  local evo = {}
  for _, r in ipairs(all) do if not hidden_c[r.key] then evo[#evo + 1] = r end end
  table.sort(evo, function(a, b) return a.now > b.now end)
  if #evo == 0 then muted(pcard, {"tr-gui.combat-pick-none"}) end
  for _, r in ipairs(evo) do
    local pk = s.planets[r.key] or {kills = 0, kills_shift = 0, weap = {}}
    local card = pcard.add{type = "frame", direction = "horizontal", style = "inside_deep_frame"}
    card.style.horizontally_stretchable = true
    card.style.padding = 8
    card.style.bottom_margin = 6
    local icon = card.add{type = "sprite", sprite = "space-location/" .. r.key}
    icon.style.width = 40
    icon.style.height = 40
    icon.style.stretch_image_to_widget_size = true
    local col = card.add{type = "flow", direction = "vertical"}
    col.style.left_margin = 8
    local k = shift and pk.kills_shift or pk.kills
    col.add{type = "label", caption = {"", "[font=default-bold]", r.s.planet.prototype.localised_name, "[/font]   ",
      k > 0 and {"tr-gui.combat-kills", C.n(k)} or {sk(p, "tr-gui.combat-kills-none")}}}
    -- эволюция каждой вражеской фракции тут, для подсказки
    local fr = {""}
    for i, f in ipairs(CB.evolution_by_force(r.s)) do
      if i > 8 then break end
      fr[#fr + 1] = {"", "\n", f.name, ": ", CB.pct(f.v)}
    end
    local bw = CB.best(pk.weap)
    bar(col, r.now, {"tr-gui.combat-evo", CB.pct(r.now), CB.dpct(r.delta),
      bw and {"tr-gui.combat-most-here", C.weapon_icon(bw) ~= "" and C.weapon_icon(bw) or C.weapon_ls(bw)} or ""}, 200,
      {"tr-gui.tip-evo", fr})
    if r.hist and #r.hist > 0 then
      -- три последние смены числами: 98.97% → 98.98% → 99.00% (+0.03%)
      local n = #r.hist
      local first = math.max(1, n - 2)
      local parts = {}
      for i = first, n do parts[#parts + 1] = CB.pct2(r.hist[i]) end
      local txt = table.concat(parts, " → ")
      if n > first then txt = txt .. "  (" .. CB.dpct(r.hist[n] - r.hist[first]) .. ")" end
      local hl = col.add{type = "label", caption = {"tr-gui.combat-evo-history3", txt}, tooltip = {"tr-gui.combat-evo-history-tip"}}
      hl.style.font_color = {0.6, 0.6, 0.6}
    end
  end

  local ebox = deep_frame(card_frame(pane, {sk(p, "tr-gui.combat-enemies")}))
  local arr = {}
  for name, en in pairs(shift and s.enemies_shift or s.enemies) do arr[#arr + 1] = {name, en} end
  table.sort(arr, function(a, b) return a[2].n > b[2].n end)
  if #arr == 0 then muted(ebox, {sk(p, "tr-gui.why-no-kills")}) else
    local t = ebox.add{type = "table", column_count = 3, draw_horizontal_line_after_headers = true}
    t.style.horizontal_spacing = 16
    for _, h in ipairs({"enemy", "count", "best"}) do t.add{type = "label", caption = {"tr-gui.combat-col-" .. h}, style = "caption_label"} end
    for i = 1, math.min(15, #arr) do
      local name, en = arr[i][1], arr[i][2]
      local proto = prototypes.entity[name]
      t.add{type = "label", caption = {"", "[entity=" .. name .. "] ", proto and proto.localised_name or name}}
      t.add{type = "label", caption = C.n(en.n)}
      local bw, bn = CB.best(en.w)
      t.add{type = "label", caption = bw and {"", C.weapon_ls(bw), "  [color=0.6,0.6,0.6]", C.n(bn), "[/color]"} or "—"}
    end
  end
  muted(pane, {"tr-gui.combat-hint"})
  reset_bar(p, pane, "combat")
end
local function fill_titles(p, pane)
  pane.clear()
  if C.S("tr-chat-titles") then
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
  -- мои звания: за что выданы
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
  -- команда
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
      if t then why[#why + 1] = {"", "\n", C.title_rich(x.id), " — ", C.title_reason(t)}; if #why >= 18 then why = {"", why} end end
    end
    local l = wrap(tbox.add{type = "label", caption = {"", "[font=default-bold]" .. name .. "[/font] (" .. #tt .. "): ",
      #tt > 0 and C.join(tt) or {"tr-gui.none"}}, tooltip = #tt > 0 and {"", {"tr-gui.tip-titles-why"}, why} or nil}, W - 90)
    l.style.bottom_margin = 3
  end
  -- ближе всего к получению
  local nbox = deep_frame(card_frame(pane, {"tr-gui.titles-next"}))
  for _, n in ipairs(C.next_titles(p.name, 5)) do
    local br = bar(nbox, n.ratio, {"tr-gui.title-left", C.title_rich(n.t.id), C.title_left(n)}, 240, C.title_reason(n.t))
    br.style.bottom_margin = 3
  end
  -- все
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

  reset_bar(p, pane, "titles")
end

local function fill_journal(p, pane)
  pane.clear()
  local j = C.D().journal
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

---------------------------------------------------------------- Космос: платформы
local STATE_COL = {on_the_path = "0.5,0.85,1", waiting_at_station = "0.6,1,0.6", waiting_for_departure = "0.6,1,0.6",
  paused = "1,0.8,0.4", no_path = "1,0.5,0.4", no_schedule = "0.7,0.7,0.7"}
local function state_chip(state)
  return {"", "[color=" .. (STATE_COL[state] or "0.8,0.8,0.8") .. "]", {"tr-plat.state-" .. state}, "[/color]"}
end
local function item_rich(it)
  local q = it.quality and it.quality ~= "normal" and (",quality=" .. it.quality) or ""
  return "[item=" .. it.name .. q .. "]"
end

-- «3 мин 12 с» для коротких времён, с часа — часы
local function dur(ticks)
  local sec = math.floor((ticks or 0) / 60)
  if sec < 60 then return {"tr-plat.dur-s", sec} end
  if sec < 3600 then return {"tr-plat.dur-ms", math.floor(sec / 60), sec % 60} end
  return C.time(ticks)
end
local function speed_txt(v)
  return v and {"tr-plat.speed", string.format(v >= 10 and "%.0f" or "%.1f", v)} or "—"
end
local function km_txt(km)
  return {"tr-plat.km", C.big(math.floor((km or 0) + 0.5))}
end
local function place_icon(name) return "[img=space-location/" .. name .. "]" end
-- текущий полёт одной строкой: время, средняя скорость, пройдено км
local function flight_caption(r)
  local f = PF.flight(r)
  if not f then return nil end
  -- длина всего пути: все связи маршрута (пройдено, текущая, осталось)
  local total = f.route_km
  local hops = PF.route(r)
  if hops then
    total = 0
    for _, h in ipairs(hops) do total = total + (h.len or 0) end
  end
  return {"tr-plat.fl-now", dur(f.elapsed), speed_txt(f.speed), km_txt(total)}
end
-- подсказка к прыжку маршрута: длина, а для пройденных — время и средняя скорость
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
-- последние полёты платформы (новые сверху): все планеты пути значками с подсказкой, потом время,
-- средняя скорость и длина маршрута
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

local function fill_platforms(p, pane)
  pane.clear()
  local rows = PF.rows(GS(p).hide_plats)
  local pins = GS(p).plat_pins or {}
  table.sort(rows, function(a, b)       -- сначала закреплённые, потом по имени
    local pa, pb = pins[a.pl.index] and true or false, pins[b.pl.index] and true or false
    if pa ~= pb then return pa end
    return a.pl.name < b.pl.name
  end)
  local moving = 0
  for _, r in ipairs(rows) do if r.from then moving = moving + 1 end end
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
    lb.style.padding = {0, 8}
    lb.style.left_margin = 8
  end
  local entries = {}
  for _, pl in pairs(game.forces.player.platforms) do if pl.valid then entries[#entries + 1] = {id = pl.index, caption = pl.name} end end
  table.sort(entries, function(a, b) return a.caption < b.caption end)
  filter_button(p, srow, "pl", entries)
  if GS(p).lost_open then
    local lost = PF.lost()
    local lbox = deep_frame(card_frame(pane, {"tr-plat.lost-head"}))
    for _, l in ipairs(lost) do
      local where = l.at and C.planet_ls(l.at) or (l.from and {"tr-plat.between", C.planet_ls(l.from), C.planet_ls(l.to)} or "?")
      -- что убило: значок и название (астероид, враг...), а если сущности нет — тип урона
      local cp = l.cause and prototypes.entity[l.cause]
      local cause = l.cause and {"", helpers.is_valid_sprite_path("entity/" .. l.cause) and ("[img=entity/" .. l.cause .. "] ") or "", cp and cp.localised_name or l.cause}
        or (l.damage and C.damage_ls(l.damage)) or {"tr-plat.cause-unknown"}
      wrap(lbox.add{type = "label", caption = {"tr-plat.lost-row", C.clock(l.tick), C.chat_rich(l.name), where, cause, l.trips or 0, C.big(l.ast or 0)}})
    end
    if #lost < PF.lost_total() then muted(lbox, {"tr-plat.lost-more", PF.lost_total() - #lost}) end
  end
  if #rows == 0 then muted(pane, {"tr-plat.none"}) end
  for _, r in ipairs(rows) do
    local idx = r.pl.index
    local card = pane.add{type = "frame", direction = "vertical", style = "inside_shallow_frame_with_padding",
      tags = {tr = "plat_card", idx = idx, sig = PF.sig(r)}}
    card.style.horizontally_stretchable = true
    card.style.bottom_margin = 4
    -- 1) имя, состояние, рейсы и астероиды по размеру (крупные первыми); виды по наведению
    local tiers, alist = PF.asteroid_tiers(r.st.asteroids)
    local tparts = {}
    for _, t in ipairs(tiers) do tparts[#tparts + 1] = {"tr-plat.tier", {"tr-plat.tier-" .. t.tier}, C.n(t.n)} end
    local atip = {"", {"tr-plat.tip-ast"}}
    for i, a in ipairs(alist) do
      if i <= 25 then
        atip[#atip + 1] = {"", "\n[entity=" .. a.name .. "] ", prototypes.entity[a.name] and prototypes.entity[a.name].localised_name or a.name,
          " — ", C.big(a.n), " [color=0.6,0.6,0.6](", {"tr-plat.tier-" .. PF.tier_of(a.name)}, ")[/color]"}
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
    pb.style.padding = {0, 8}
    local sub = card.add{type = "label", caption = {"tr-plat.head-sub", r.st.trips, #tparts > 0 and C.join(tparts, " · ") or "0"}}
    sub.style.font_color = {0.7, 0.7, 0.7}
    -- 2) текущий полёт: [откуда] ====== 63% [куда] или «стоит у [планета]»
    local now = card.add{type = "flow", direction = "horizontal"}
    now.style.vertical_align = "center"
    now.style.horizontal_spacing = 6
    local last = #r.stops > 0 and r.stops[#r.stops].name or nil
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
    -- путь к текущей цели (расписание или прерывание): пройденные прыжки, текущий, планеты впереди;
    -- на полоске — длина прыжка (а у пройденных время и скорость)
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
      -- время всего маршрута идёт после самого маршрута
      local total = 0
      for _, h in ipairs(hops) do total = total + (h.len or 0) end
      local eta = PF.eta_ticks(r, total)
      local el = strip.add{type = "label", caption = eta and {"tr-plat.route-eta", dur(eta), km_txt(total)} or {"tr-plat.route-len", km_txt(total)},
        tags = {tr = "plat_eta"}, tooltip = {"tr-plat.tip-eta"}}
      el.style.font_color = {0.8, 0.8, 0.8}
      el.style.left_margin = 8
    end
    -- текущий полёт одной строкой, ниже последние
    local trip = flight_caption(r)
    if trip then
      local tl = card.add{type = "label", caption = trip, tags = {tr = "plat_trip"}, tooltip = {"tr-plat.tip-trip"}}
      tl.style.single_line = false
      tl.style.maximal_width = W - 60
    end
    add_history(card, r)
    -- 4) груз: своя тёмная рамка, наука первой; свёрнут по умолчанию, кнопка в правом верхнем углу разворачивает
    if #r.cargo > 0 then
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
      tb.style.padding = {0, 8}
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
    if r.hp < 0.999 then bar(card, r.hp, {"tr-plat.hp", math.floor(r.hp * 100)}, 120) end
  end
  reset_bar(p, pane, "platforms")
end

-- «a b c» из топ-N таблицы {ключ = количество}
function M.top_list(t, n, fmt)
  local arr = {}
  for k, v in pairs(t or {}) do arr[#arr + 1] = {k, v} end
  table.sort(arr, function(a, b) if a[2] ~= b[2] then return a[2] > b[2] end return tostring(a[1]) < tostring(b[1]) end)
  local parts = {}
  for i = 1, math.min(n, #arr) do parts[#parts + 1] = fmt(arr[i][1], arr[i][2]) end
  if #parts == 0 then return "" end
  return C.join(parts, "   ")
end

---------------------------------------------------------------- Завод: качество
local QCATS = {"all", "buildings", "modules", "intermediate"}
local function gs_q_window(p) return GS(p).q_window == 60 and 60 or 10 end
-- полоска тревоги по электросетям: красная, когда энергии нет или не хватает, жёлтая, когда на пределе или перебой был
-- недавно (до 5 минут назад). Если всё хорошо — её нет. Стоит над подвкладками группы «Фабрика», поэтому видна и в самой
-- «Фабрике», и в «Электросетях» (и в других её вкладках)
local function fill_quality(p, pane)
  pane.clear()
  local quals = QL.qualities()
  if #quals == 0 then muted(pane, {"tr-q.no-quality"}) return end
  local cat = C.P(p, "q-cat") or "all"
  local hidden = C.P(p, "q-hide") or {}
  local show_hidden = GS(p).q_show_hidden
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
  local any = false
  for _, s in ipairs((function() local o = {} for _, ss in pairs(game.surfaces) do if C.RP(ss) then o[#o + 1] = ss end end table.sort(o, function(a, b) return a.name < b.name end) return o end)()) do
    local key = s.planet.prototype.name
    local rows, minutes = nil, 0
    if not hidden_planets(p, "q")[key] then rows, minutes = QL.planet_rows(key, gs_q_window(p)) end
    local shown = {}
    for _, r in ipairs(rows or {}) do
      local hid = hidden[r.item]
      if prototypes.item[r.item] and (cat == "all" or QL.category(r.item) == cat) and (not hid or show_hidden) then shown[#shown + 1] = r end
    end
    if #shown > 0 then
      any = true
      local card = card_frame(pane, {"", C.planet_ls(key), minutes > 0 and {"tr-q.window", math.floor(minutes + 0.5)} or ""})
      -- первые пять; кнопка под названием планеты показывает все
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
        cb.style.padding = {0, 8}
      end
      local t = deep_frame(card).add{type = "table", column_count = 1 + #quals, draw_horizontal_line_after_headers = true}
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
            qcell(t.add{type = "label", caption = "[color=0.4,0.4,0.4]—[/color]"})
          end
        end
      end
    end
  end
  if not any then muted(pane, {"tr-q.none-anywhere"}) end
  reset_bar(p, pane, "quality")
end

---------------------------------------------------------------- Завод: энергия

-- Электросети: каждая планета с сетью в одной таблице (состояние — быстрая проверка последней секунды, числа —
-- последний замер, до ~20 с); ниже журнал последних 10 перебоев всех планет, новые сверху, с игровым
-- временем и вероятными причинами. Окно перерисовывается сразу, когда перебой начинается или кончается
local function energy_chip(r)
  local h, an = r.h, r.an
  local cur = h and h.short
  if r.cur_known then cur = r.cur end       -- быстрая проверка знает лучше замера
  if not h and not cur then return {"tr-en.chip-wait"}
  elseif cur == "none" then return {"tr-en.chip-out"}
  elseif cur then return {"tr-en.chip-low"}
  elseif an and an.score >= 1 then return {"tr-en.chip-risk"}
  elseif an and an.idle then return {"tr-en.chip-idle"} end
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

-- заряд аккумуляторов синей полоской с числами рядом
local function acc_bar(parent, h, width)
  if not h or (h.cap or 0) <= 0 then return nil end
  local pct = math.floor(h.stored / h.cap * 100)
  -- что даёт такой запас: сколько аккумуляторов и на сколько хватит заряда при текущем потреблении
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

-- три крупнейших источника или потребителя планеты: «значок xN мощность»
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

-- одна запись журнала: время, планета, что было и сколько (+ причины при full)
local function energy_entry(parent, e, full)
  local head = {"", "[color=0.6,0.8,1]", C.clock(e.start), "[/color]  [font=default-bold]", C.planet_ls(e.key), "[/font] — ",
    {"tr-en.kindn-" .. e.kind}, ", ", dur(EN.duration(e)),
    (e.n or 1) > 1 and {"tr-en.log-repeat", e.n} or "",
    e.done and {"tr-en.log-ago", dur(game.tick - (e.last or game.tick))} or {"tr-en.log-now"}}
  local hl = wrap(parent.add{type = "label", caption = head}, W - 110)
  hl.style.top_margin = 3
  if full then
    if e.why and #e.why > 0 then
      for _, line in ipairs(e.why) do
        -- закончившийся перебой — в прошедшем времени: «ключ-past»
        local shown = line
        if e.done and type(line) == "table" and type(line[1]) == "string" then
          shown = {line[1] .. "-past"}
          for i = 2, #line do shown[i] = line[i] end
        end
        local wl = wrap(parent.add{type = "label", caption = {"", "    · ", shown}}, W - 110)
        wl.style.font_color = {0.85, 0.85, 0.85}
      end
    else
      local wl = wrap(parent.add{type = "label", caption = {"", "    · ", {e.done and "tr-en.why-unknown-past" or "tr-en.why-unknown"}}}, W - 110)
      wl.style.font_color = {0.65, 0.65, 0.65}
    end
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
  -- сначала худшие, потом крупнейшие потребители
  table.sort(rows, function(a, b)
    if a.an.score ~= b.an.score then return a.an.score > b.an.score end
    return (a.h and a.h.cons or 0) > (b.h and b.h.cons or 0)
  end)
  if #rows > 0 then
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

  -- журнал: свёрнуто — одна строка, развёрнуто — каждая запись с причинами
  local log = EN.log()
  local lcard = card_frame(pane, {"tr-en.log-head"}, {"tr-en.tip-log"})
  local lbox = deep_frame(lcard)
  if #log == 0 then muted(lbox, {"tr-en.log-none"}) else
    local open = gs.en_log_open
    if open then
      for _, e in ipairs(log) do energy_entry(lbox, e, true) end
    else
      energy_entry(lbox, log[1], false)
    end
    local tb = lbox.add{type = "button", caption = open and {"tr-en.log-hide"} or {"tr-en.log-show", #log},
      tags = {tr = "en_log_toggle"}}
    tb.style.height = 22
    tb.style.minimal_width = 0
    tb.style.padding = {0, 8}
    tb.style.top_margin = 6
  end
  muted(pane, {"tr-en.hint3"})
  gs.en_sig = EN.sig()
  reset_bar(p, pane, "energy")
end

---------------------------------------------------------------- Бой: разрушения по планетам
local function fill_destruction(p, pane)
  pane.clear()
  local d = C.D()
  -- сущность с картинкой и названием и сколько
  local function ent_part(name, n)
    local pr = prototypes.entity[name]
    return {"", "[entity=" .. name .. "] ", pr and pr.localised_name or name, " ×", C.n(n)}
  end
  local sc = scope(p)
  local src = sc == "total" and d.plost or d.shift_plost
  local lds = sc == "total" and (d.ldest or {}) or (d.ldest_shift or {})
  local keys = {}
  for k, n in pairs(src) do if n > 0 then keys[#keys + 1] = k end end
  -- сверху планеты, где разрушали последними
  table.sort(keys, function(a, b)
    local la, lb = (lds[a] or {}).last or 0, (lds[b] or {}).last or 0
    if la ~= lb then return la > lb end
    return src[a] > src[b]
  end)
  local total, by_enemy = 0, 0
  for _, k in ipairs(keys) do
    total = total + src[k]
    by_enemy = by_enemy + ((lds[k] or {}).enemy_n or 0)
  end
  local head = card_frame(pane, {sk(p, "tr-gui.dest-total"), C.n(total), C.n(by_enemy)})
  if #keys == 0 then muted(deep_frame(head), {sk(p, "tr-gui.why-no-lost")}) end
  -- самые свежие разрушения списком: когда, где, что, чем и чьё
  local recent = d.dest_recent or {}
  if #recent > 0 then
    local rbox = deep_frame(card_frame(pane, {"tr-gui.dest-recent-head"}))
    for i = 1, math.min(12, #recent) do
      local r = recent[i]
      local pr = prototypes.entity[r.what]
      local by
      if string.sub(r.by, 1, 7) == "damage:" then by = C.damage_ls(string.sub(r.by, 8))
      elseif r.by == "unknown" then by = {"tr-gui.dest-unknown"}
      else
        local bp = prototypes.entity[r.by]
        by = {"", "[entity=" .. r.by .. "] ", bp and bp.localised_name or r.by}
      end
      wrap(rbox.add{type = "label", caption = {"tr-gui.dest-recent-row", C.clock(r.tick), C.planet_ls(r.planet),
        {"", "[entity=" .. r.what .. "] ", pr and pr.localised_name or r.what}, by, r.whose}}, W - 90)
    end
  end
  for _, key in ipairs(keys) do
    local ld = lds[key] or {what = {}, by = {}, other = {}, whose = {}}
    local card = card_frame(pane, {"tr-gui.dest-planet", C.planet_ls(key), C.n(d.shift_plost[key] or 0), C.n(d.plost[key] or 0)})
    local box = deep_frame(card)
    local function line(key_, list)
      if list ~= "" then
        local l = wrap(box.add{type = "label", caption = {key_, list}}, W - 90)
        l.style.bottom_margin = 3
      end
    end
    line("tr-gui.dest-what", M.top_list(ld.what, 6, function(name, n) return ent_part(name, n) end))
    -- враги: кто
    line("tr-gui.dest-by", M.top_list(ld.by, 5, function(name, n)
      if string.sub(name, 1, 7) == "damage:" then return {"", C.damage_ls(string.sub(name, 8)), " ×", C.n(n)} end
      if name == "unknown" then return {"", {"tr-gui.dest-unknown"}, " ×", C.n(n)} end
      return ent_part(name, n)
    end))
    -- не враги: взрывы, огонь, кислота, молнии, свои машины: по типу урона или по причине
    line("tr-gui.dest-other", M.top_list(ld.other or {}, 5, function(name, n)
      if string.sub(name, 1, 7) == "damage:" then return {"", C.damage_ls(string.sub(name, 8)), " ×", C.n(n)} end
      if name == "unknown" then return {"", {"tr-gui.dest-unknown"}, " ×", C.n(n)} end
      return ent_part(name, n)
    end))
    line("tr-gui.dest-whose", M.top_list(ld.whose, 5, function(name, n) return {"tr-gui.dest-whose-item", name, C.n(n)} end))
  end
  muted(pane, {"tr-gui.dest-hint"})
  reset_bar(p, pane, "destruction")
end

---------------------------------------------------------------- Команда: достижения (личные и командные)
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
    -- за что выдано, видно всегда
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
        tip[#tip + 1] = {"", "\n[color=0.6,1,0.6]✓[/color] ", {"tr-ach." .. a.id}, " — ", {"tr-ach." .. a.id .. "-tip"}}
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

---------------------------------------------------------------- раскладка окна: группы с подвкладками
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

-- группы и подвкладки, которые игрок хочет видеть
local function layout(p)
  local out = {}
  for _, g in ipairs(GROUPS) do
    local subs = {}
    for _, s in ipairs(g.subs) do if ALWAYS[s[1]] or C.P(p, "tab-" .. s[1]) then subs[#subs + 1] = s end end
    if #subs > 0 then out[#out + 1] = {id = g.id, icon = g.icon, subs = subs} end
  end
  return out
end

local function pane_of(frame, g, sub)
  local tabs = frame.tr_tabs
  if #g.subs == 1 then return tabs["tr_pane_" .. sub] end
  local holder = tabs["tr_grp_" .. g.id]
  return holder and holder["tr_sub_" .. g.id] and holder["tr_sub_" .. g.id]["tr_pane_" .. sub]
end

-- открытые сейчас группа и подвкладка
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
  local ok, err = pcall(sub[2], p, pane)
  if not ok then
    log("Factory Radar GUI error in " .. sub[1] .. ": " .. tostring(err))
    pcall(function() pane.clear(); pane.add{type = "label", caption = {"tr-gui.tab-error"}} end)
  end
end

-- панель выбора рядом с окном (см. filter_button)
local function sync_filter(p)
  local gs = GS(p)
  local which = gs.flt_open
  local frame = p.gui.screen[FRAME]
  local f = p.gui.screen[FLT]
  local tab_ok = false
  if which and frame then
    local g, sub = active_sub(p, frame)
    tab_ok = sub ~= nil and sub[1] == FLT_TAB[which]
  end
  if not tab_ok then                       -- только пока открыта её вкладка
    if f then f.destroy() end
    gs.flt_open = nil
    return
  end
  if f and f.tags.which ~= which then f.destroy(); f = nil end
  if not f then
    -- создаётся один раз и потом только обновляется: запоминает, куда её перетащили (за заголовок)
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
      local x = math.min(loc.x + (W + 100) * sc, res.width - 250 * sc)      -- не за край экрана
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
    b.style.padding = {0, 6}
    b.style.bottom_margin = 1
  end
  local row = box.add{type = "flow", direction = "horizontal"}
  row.style.top_margin = 6
  row.style.horizontal_spacing = 6
  local all = row.add{type = "button", caption = {nh == 0 and "tr-gui.flt-none" or "tr-gui.flt-all"}, tags = {tr = "flt_all", which = which}}
  all.style.height = 22
  all.style.minimal_width = 0
  all.style.padding = {0, 6}
end

-- шапка и открытая вкладка: остальные не строятся, пока не откроешь (строить вкладку — дорого)
function M.refresh(p)
  local frame = p.gui.screen[FRAME]
  if not frame then return end
  pcall(fill_header, p, frame.tr_header)
  local g, sub = active_sub(p, frame)
  if g then
    -- окно высотой с открытую вкладку: у ушедших вкладок содержимого нет (tabbed-pane равен самой большой)
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

-- автообновление: то же, но вкладку настроек не трогаем (поле ввода не должно перерисовываться при наборе)
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

-- раз в секунду: полоски платформ двигаются на месте; карточка, у которой сменилось состояние, перерисовывает вкладку
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

-- раз в секунду: «Кто где» обновляет тексты и кулдауны молнии на месте (без перерисовки окна)
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

-- раз в секунду: строка викторины в сводке отсчитывает на месте (вкладка перерисовывается только при смене состояния)
local function live_summary(p, frame)
  if GS(p).tab_name ~= "summary" or not C.S("tr-s-roulette") then return false end
  local g
  for _, x in ipairs(layout(p)) do if x.id == "summary" then g = x end end
  local pane = g and pane_of(frame, g, "summary")
  if not (pane and pane.valid) then return false end
  local st, a, b = RU.status()
  local found, redraw = false, false
  local function walk(el)
    for _, ch in ipairs(el.children) do
      if ch.tags and ch.tags.tr == "rou_status" then
        found = true
        if ch.tags.st ~= st then redraw = true
        elseif st == "cooldown" then ch.caption = {"tr-gui.rou-cd", a}
        elseif st == "join" then ch.caption = {"tr-gui.rou-join", a, b} end
      elseif #ch.children > 0 then walk(ch) end
    end
  end
  walk(pane)
  return redraw
end

-- раз в секунду: вкладка энергии перерисовывается, как только перебой начался или кончился
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

-- игра может молча сбросить opened (например, прыжок в удалённый просмотр); без него Esc не работает, возвращаем
local function keep_opened(p)
  local frame = p.gui.screen[FRAME]
  if frame and frame.valid and p.opened == nil then pcall(function() p.opened = frame end) end
end

local SLOW_TABS = {titles = true, achievements = true, help = true}
function M.autorefresh()
  for _, p in pairs(game.connected_players) do
    keep_opened(p)
    if game.tick % 300 == 0 and p.gui.screen[FIND] then M.refresh_find(p) end
    -- на окно АФК-игрока никто не смотрит: не перерисовываем, пока не двинется
    local frame = p.afk_time <= 5 * 3600 and p.gui.screen[FRAME] or nil
    if frame then
      if live_platforms(p, frame) or live_where(p, frame) or live_summary(p, frame) or live_energy(p, frame) then M.refresh_active(p) end
      local secs = C.P(p, "autorefresh") or 0
      if secs > 0 then
        -- тяжёлые и почти не меняющиеся вкладки перерисовываем в 4 раза реже (кнопка обновления по-прежнему мгновенная)
        local _, sub = active_sub(p, frame)
        if sub and SLOW_TABS[sub[1]] then secs = secs * 4 end
        if math.floor(game.tick / 60) % secs == 0 then M.refresh_active(p) end
      end
    end
  end
end

---------------------------------------------------------------- быстрый доступ: закреплённые и недавние подвкладки
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

---------------------------------------------------------------- поиск предмета по логистическим сетям
-- маленькое окно: выбираешь предмет (с качеством), видишь, на каких планетах и платформах сколько его есть в логсетях.
-- Клик по месту: камера уходит туда (удалённый просмотр), контейнеры с предметом подсвечиваются и перечислены в окне.
-- Галочка «и вне сетей» просматривает обычные контейнеры на всех планетах (по одной планете за раз)
local function loupe() return helpers.is_valid_sprite_path("utility/search") and "[img=utility/search] " or "" end
local function item_icon(it) return "[item=" .. it.name .. ",quality=" .. (it.quality or "normal") .. "]" end

-- где это место: поверхность планеты или платформы
local function find_surface(planet, platform)
  if planet then
    local pl = game.planets[planet]
    return pl and pl.surface
  end
  for _, pf in pairs(game.forces.player.platforms) do
    if pf.valid and pf.name == platform then return pf.surface end
  end
end

-- подсветка найденного убирается, когда поиск закрыт или начат новый (на случай чего сама гаснет через 2 минуты)
local function clear_marks(p)
  local gs = GS(p)
  for _, o in ipairs(gs.find_marks or {}) do
    pcall(function() if o.valid then o.destroy() end end)
  end
  gs.find_marks = nil
end

-- как в игре: рамка вокруг контейнера и значок предмета на карте
local function mark_chests(p, s, list)
  clear_marks(p)
  local gs = GS(p)
  local it = gs.find_item
  gs.find_marks = {}
  local function keep(o) if o then gs.find_marks[#gs.find_marks + 1] = o end end
  local q = it and it.quality or "normal"
  local qpath = "quality/" .. q
  local qok = q ~= "normal" and helpers.is_valid_sprite_path(qpath)
  for i, c in ipairs(list) do
    if i > 300 then break end
    local b = c.box or {c.x - 0.5, c.y - 0.5, c.x + 0.5, c.y + 0.5}
    pcall(function()
      -- рамка из игры (жёлтые уголки, как у выбранной сущности); видит её только тот, кто искал
      keep(s.create_entity{name = "highlight-box", position = {x = c.x, y = c.y}, box_type = "entity", render_player_index = p.index,
        bounding_box = {left_top = {x = b[1], y = b[2]}, right_bottom = {x = b[3], y = b[4]}}, time_to_live = 7200})
    end)
    if it then
      -- значок предмета на карте (размер в клетках, поэтому крупный) и значок качества в его углу
      pcall(function()
        keep(rendering.draw_sprite{sprite = "item/" .. it.name, target = {x = c.x, y = c.y}, surface = s, x_scale = 10, y_scale = 10,
          time_to_live = 7200, players = {p}, render_mode = "chart"})
      end)
      if qok then
        pcall(function()
          keep(rendering.draw_sprite{sprite = qpath, target = {x = c.x - 4, y = c.y + 4}, surface = s, x_scale = 5, y_scale = 5,
            time_to_live = 7200, players = {p}, render_mode = "chart"})
        end)
      end
    end
  end
end
-- подпись места: значок и название в одной кнопке, как в панели «Какие планеты показывать»
local function place_caption(planet, platform)
  if planet then return C.planet_ls(planet) end
  return {"", "[img=entity/space-platform-hub] ", {"tr-find.platform", platform}}
end

local function fill_find_details(p, box)
  box.clear()
  local gs = GS(p)
  local sel = gs.find_det
  local it = gs.find_item
  if not (sel and it) then return end
  local where = sel.planet and C.planet_ls(sel.planet) or {"tr-find.platform", sel.platform}
  local head = box.add{type = "label", caption = {sel.outside and "tr-find.det-head-out" or "tr-find.det-head", where, C.big(sel.found or 0)},
    style = "caption_label"}
  head.style.top_margin = 6
  if #sel.list == 0 then muted(box, {"tr-find.det-none"}) return end
  -- сеть насчитала больше, чем нашлось в контейнерах: остальное в машинах, роботах или контейнерах особого вида
  if not sel.outside and (sel.total or 0) > (sel.found or 0) * 1.02 + 1 then
    local types = {}
    for ty, n in pairs(sel.unknown or {}) do types[#types + 1] = ty .. " x" .. n end
    table.sort(types)
    local m = muted(box, {"tr-find.det-rest", C.big((sel.total or 0) - (sel.found or 0)), #types > 0 and table.concat(types, ", ") or "-"})
    m.style.single_line = false
    m.style.maximal_width = 420
  end
  if (sel.n_all or #sel.list) > #sel.list then muted(box, {"tr-find.det-more", #sel.list, sel.n_all}) end
  local sp = box.add{type = "scroll-pane", direction = "vertical"}
  sp.horizontal_scroll_policy = "auto"
  sp.style.maximal_height = 260
  sp.style.minimal_width = 440
  local icon = item_icon(it)
  for _, c in ipairs(sel.list) do
    local pr = prototypes.entity[c.name]
    -- у игрока вместо контейнера его значок и никнейм
    local who = (c.player ~= nil) and (c.player or {"tr-find.no-player"}) or (pr and pr.localised_name or c.name)
    local b = sp.add{type = "button",
      caption = {"", "[entity=" .. c.name .. ((c.quality and c.quality ~= "normal") and (",quality=" .. c.quality) or "") .. "]  ", who,
        "   ", C.big(c.count), " ", icon,
        "   (", math.floor(c.x), ", ", math.floor(c.y), ")"},
      tags = {tr = "find_chest", s = sel.surface, x = c.x, y = c.y}, tooltip = {"tr-find.det-tip"}}
    b.style.horizontal_align = "left"
    b.style.height = 30
    b.style.minimal_width = 420
    b.style.padding = {0, 6}
  end
end
local function start_scan(p)
  local it = GS(p).find_item
  if it and it.name then LG.scan_start(p.index, it.name, it.quality or "normal") end
end

-- блок «вне логистических сетей»
local function fill_find_outside(p, res)
  local gs = GS(p)
  local job = LG.scan_job(p.index)
  local sbox = res.add{type = "flow", direction = "vertical"}
  sbox.style.top_margin = 8
  sbox.add{type = "label", caption = {"tr-find.out-head"}, style = "caption_label"}
  if not job then return end
  if not job.finished then
    muted(sbox, {"tr-find.scan-progress", job.total - #job.queue, job.total})
  end
  local rows = {}
  for key, r in pairs(job.done) do if r.count > 0 then rows[#rows + 1] = {key = key, r = r} end end
  table.sort(rows, function(a, b) return a.r.count > b.r.count end)
  if #rows == 0 then
    if job.finished then muted(sbox, {"tr-find.out-none"}) end
    return
  end
  local sp = sbox.add{type = "scroll-pane", direction = "vertical"}
  sp.horizontal_scroll_policy = "auto"
  sp.style.maximal_height = 200
  sp.style.minimal_width = 400
  local t = sp.add{type = "table", column_count = 2}
  t.style.horizontal_spacing = 8
  t.style.vertical_spacing = 1
  for _, x in ipairs(rows) do
    local chosen = gs.find_det and gs.find_det.outside and gs.find_det.planet == x.key
    local b = t.add{type = "button", caption = C.planet_ls(x.key), toggled = chosen and true or false,
      tags = {tr = "find_go_out", planet = x.key}, tooltip = {"tr-find.out-tip", x.r.chests}}
    b.style.horizontal_align = "left"
    b.style.height = 30
    b.style.width = 230
    b.style.padding = {0, 6}
    local cnt = t.add{type = "label", caption = C.big(x.r.count), style = "bold_label"}
    cnt.style.horizontal_align = "right"
    cnt.style.minimal_width = 100
  end
end

local function fill_find_results(p, res)
  res.clear()
  local gs = GS(p)
  local it = gs.find_item
  if not (it and it.name and prototypes.item[it.name]) then
    local m = muted(res, {"tr-find.hint"})
    m.style.maximal_width = 380
    m.style.single_line = false
    return
  end
  local rows, total = LG.search(it.name, it.quality)
  local head = res.add{type = "label", caption = {"tr-find.total", loupe(), item_icon(it), C.big(total), #rows}, style = "caption_label"}
  head.style.bottom_margin = 4
  if #rows == 0 then
    muted(res, {"tr-find.none"})
  else
    local sp = res.add{type = "scroll-pane", direction = "vertical"}
    sp.horizontal_scroll_policy = "auto"
    sp.style.maximal_height = 280
    sp.style.minimal_width = 400
    local t = sp.add{type = "table", column_count = 2}
    t.style.horizontal_spacing = 8
    t.style.vertical_spacing = 1
    for _, r in ipairs(rows) do
      local chosen = gs.find_det and not gs.find_det.outside and gs.find_det.planet == r.planet and gs.find_det.platform == r.platform
      local b = t.add{type = "button", caption = place_caption(r.planet, r.platform), toggled = chosen and true or false,
        tags = {tr = "find_go", planet = r.planet, platform = r.platform, count = r.count}, tooltip = {"tr-find.nets", r.nets}}
      b.style.horizontal_align = "left"
      b.style.height = 30
      b.style.width = 230
      b.style.padding = {0, 6}
      local cnt = t.add{type = "label", caption = C.big(r.count), style = "bold_label"}
      cnt.style.horizontal_align = "right"
      cnt.style.minimal_width = 100
    end
  end
  if gs.find_scan then fill_find_outside(p, res) end
  res.add{type = "flow", name = "tr_find_det", direction = "vertical"}
  fill_find_details(p, res.tr_find_det)
end

function M.refresh_find(p)
  local f = p.gui.screen[FIND]
  if f and f.valid and f.tr_find_box and f.tr_find_box.tr_find_res then fill_find_results(p, f.tr_find_box.tr_find_res) end
end

-- по таймеру: идущий просмотр обычных контейнеров делает шаг (одна планета), окно обновляется
function M.scan_tick()
  for _, pi in ipairs(LG.scan_step()) do
    local p = game.get_player(pi)
    if p and p.valid then M.refresh_find(p) end
  end
end

-- клик по месту в сетях: перейти туда и показать контейнеры с предметом
local function find_go(p, planet, platform, count)
  local gs = GS(p)
  local it = gs.find_item
  local s = find_surface(planet, platform)
  if not (it and s and s.valid) then return end
  local list, found, unknown, n_all = LG.chests(s, it.name, it.quality, 300)
  gs.find_det = {planet = planet, platform = platform, surface = s.index, list = list, found = found, total = count or found,
    unknown = unknown, n_all = n_all}
  mark_chests(p, s, list)
  local pos = list[1] and {x = list[1].x, y = list[1].y} or {x = 0, y = 0}
  pcall(function() p.set_controller{type = defines.controllers.remote, surface = s, position = pos} end)
  M.refresh_find(p)
end

-- клик по планете в блоке «вне сетей»
local function find_go_out(p, planet)
  local gs = GS(p)
  local job = LG.scan_job(p.index)
  local r = job and job.done[planet]
  local s = find_surface(planet, nil)
  if not (r and s and s.valid) then return end
  gs.find_det = {planet = planet, surface = s.index, list = r.list, found = r.count, total = r.count, outside = true, n_all = r.chests}
  mark_chests(p, s, r.list)
  local pos = r.list[1] and {x = r.list[1].x, y = r.list[1].y} or {x = 0, y = 0}
  pcall(function() p.set_controller{type = defines.controllers.remote, surface = s, position = pos} end)
  M.refresh_find(p)
end

local function close_find(p)
  clear_marks(p)
  LG.scan_cancel(p.index)
  if p.gui.screen[FIND] then p.gui.screen[FIND].destroy() end
end

function M.toggle_find(p)
  local f = p.gui.screen[FIND]
  if f then close_find(p) return end
  f = p.gui.screen.add{type = "frame", name = FIND, direction = "vertical"}
  local tb = f.add{type = "flow", direction = "horizontal"}
  tb.drag_target = f
  tb.style.vertical_align = "center"
  tb.add{type = "label", caption = {"", loupe(), {"tr-find.title"}}, style = "frame_title", ignored_by_interaction = true}
  local dr = tb.add{type = "empty-widget", style = "draggable_space_header", ignored_by_interaction = true}
  dr.style.horizontally_stretchable = true
  dr.style.height = 24
  tb.add{type = "sprite-button", sprite = "utility/close", style = "frame_action_button", tags = {tr = "find_close"}}
  local box = f.add{type = "frame", name = "tr_find_box", direction = "vertical", style = "inside_shallow_frame_with_padding"}
  local row = box.add{type = "flow", direction = "horizontal"}
  row.style.vertical_align = "center"
  row.style.horizontal_spacing = 8
  row.style.bottom_margin = 6
  row.add{type = "label", caption = {"tr-find.item"}}
  local ok, pick = pcall(function()
    return row.add{type = "choose-elem-button", elem_type = "item-with-quality", tags = {tr = "find_pick"}}
  end)
  if not ok then pick = row.add{type = "choose-elem-button", elem_type = "item", tags = {tr = "find_pick"}} end
  local it = GS(p).find_item
  if it and it.name and prototypes.item[it.name] then
    pcall(function() pick.elem_value = (pick.elem_type == "item") and it.name or {name = it.name, quality = it.quality or "normal"} end)
  end
  local fill = row.add{type = "empty-widget"}
  fill.style.horizontally_stretchable = true
  row.add{type = "sprite-button", sprite = "utility/refresh", style = "tool_button", tags = {tr = "find_refresh"}, tooltip = {"tr-find.refresh"}}
  local cb = box.add{type = "checkbox", caption = {"tr-find.scan-check"}, state = GS(p).find_scan and true or false,
    tags = {tr = "find_scan"}, tooltip = {"tr-find.scan-tip"}}
  cb.style.bottom_margin = 6
  box.add{type = "flow", name = "tr_find_res", direction = "vertical"}
  if GS(p).find_scan then start_scan(p) end
  fill_find_results(p, box.tr_find_res)
  pcall(function()
    local frame = p.gui.screen[FRAME]
    local loc, sc, res = frame and frame.location, p.display_scale, p.display_resolution
    if loc then
      f.location = {x = math.floor(math.max(0, math.min(loc.x + (W + 100) * sc, res.width - 450 * sc))), y = math.floor(loc.y + 60 * sc)}
    else
      f.force_auto_center()
    end
  end)
end

function M.on_elem(e)
  local el = e.element
  if not (el and el.valid and el.tags and el.tags.tr == "find_pick") then return end
  local p = game.get_player(e.player_index)
  if not p then return end
  local v = el.elem_value
  if type(v) == "table" then GS(p).find_item = {name = v.name, quality = v.quality or "normal"}
  elseif type(v) == "string" then GS(p).find_item = {name = v, quality = "normal"}
  else GS(p).find_item = nil end
  GS(p).find_det = nil
  clear_marks(p)
  if GS(p).find_scan then
    if GS(p).find_item then start_scan(p) else LG.scan_cancel(p.index) end
  end
  M.refresh_find(p)
end

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
    -- закреплённые: значок и имя; недавние: только значок (имя при наведении), чтобы ряд влезал
    local b = q.add{type = "button", caption = pinned and {"", s[3], " ", {"tr-gui.tab-" .. name}} or s[3],
      tags = {tr = "goto", sub = name}, tooltip = {"", {"tr-gui.tab-" .. name}, "\n", {pinned and "tr-gui.quick-pinned" or "tr-gui.quick-recent"}}}
    b.style.height = 26
    b.style.minimal_width = 0
    b.style.padding = {0, 6}
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
  fb.style.height = 26
  fb.style.minimal_width = 0
  fb.style.padding = {0, 6}
  if cur and cur ~= "settings" and cur ~= "help" then
    local is_pinned = false
    for _, n in ipairs(pins) do if n == cur then is_pinned = true end end
    local pb = q.add{type = "button", caption = {is_pinned and "tr-gui.unpin" or "tr-gui.pin"}, tags = {tr = "pin", sub = cur},
      tooltip = {is_pinned and "tr-gui.unpin-tip" or "tr-gui.pin-tip"}}
    pb.style.height = 26
    pb.style.minimal_width = 0
    pb.style.padding = {0, 6}
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
  pane.horizontal_scroll_policy = "never"      -- только вверх-вниз; всё переносится по ширине
  pane.vertical_scroll_policy = "auto-and-reserve-space"      -- место под полосу всегда, сама полоса только когда нужна
  pane.style.maximal_height = 470
  pane.style.width = PANE_W
  pane.style.horizontally_stretchable = true
  pane.style.padding = 8
  pane.style.left_padding = PAD_L
  pane.style.right_padding = PAD_R
  return pane
end

function M.toggle(p)
  if p.gui.screen[FRAME] then M.close(p); return end
  local gs = GS(p)
  local frame = p.gui.screen.add{type = "frame", name = FRAME, direction = "vertical"}
  -- фиксированная ширина: окно не меняет размер от содержимого (скрытое вступление, длинные имена, много кнопок)
  frame.style.minimal_width = W + 90
  frame.style.maximal_width = W + 90
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
  -- белый значок: чёрный сливается с тёмной шапкой окна
  title.add{type = "sprite-button", sprite = helpers.is_valid_sprite_path("utility/reset_white") and "utility/reset_white" or "utility/refresh", style = "frame_action_button",
    tooltip = {"tr-gui.refresh"}, tags = {tr = "refresh"}}
  title.add{type = "sprite-button", sprite = "utility/close", style = "frame_action_button",
    tooltip = {"tr-gui.close"}, tags = {tr = "close"}}
  local header = frame.add{type = "frame", name = "tr_header", direction = "vertical", style = "inside_shallow_frame_with_padding"}
  header.style.horizontally_stretchable = true
  header.style.bottom_margin = 4
  local quick = frame.add{type = "flow", name = "tr_quick", direction = "horizontal"}
  quick.style.vertical_align = "center"
  quick.style.horizontal_spacing = 4
  quick.style.bottom_margin = 4
  local tabs = frame.add{type = "tabbed-pane", name = "tr_tabs"}
  local lay = layout(p)
  -- какую группу/подвкладку открыть
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
      content = new_pane(tabs, "tr_pane_" .. g.subs[1][1])
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
  pcall(fill_quick, p, quick)
  frame.force_auto_center()
  M.refresh(p)
  p.opened = frame
     -- Esc (или открытие другого окна) закрывает через on_gui_closed
  pcall(p.set_shortcut_toggled, "tr-toggle", true)
end

---------------------------------------------------------------- маленькие окна выбора (голосование за MVP, запись на викторину)
-- в чат кнопки не поставить, поэтому эти два вопроса — маленькое окно сверху экрана: один клик
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
        b.style.padding = {0, 10}
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
    yes.style.padding = {0, 12}
    local no = row.add{type = "button", caption = {"tr-gui.pop-decline"}, tags = {tr = "pop_close", frame = name}}
    no.style.height = 28
    no.style.minimal_width = 0
    no.style.padding = {0, 12}
  end
  if kind == "mvp" then
    local cl = row.add{type = "button", caption = {"tr-gui.pop-close"}, tags = {tr = "pop_close", frame = name}}
    cl.style.height = 28
    cl.style.minimal_width = 0
    cl.style.padding = {0, 10}
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
  M.refresh(p)     -- только что открытая вкладка заполняется сейчас
end

local GSET_CLICK = {cfg_title_editor = true, cfg_msg_reset = true, cfg_titles_reset = true, cfg_reset_all = true,
  cfg_ignore = true, ctitle_del = true, new_title_add = true, cfg_native = true, cfg_native_auto = true, cfg_census = true}

function M.on_click(e)
  local el = e.element
  if not (el and el.valid) then return end
  local p = game.get_player(e.player_index)
  if el.name == BTN then M.toggle(p); return end
  local tag = el.tags and el.tags.tr
  if not tag then return end
  local gs = GS(p)
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
  elseif tag == "zap" then
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
  elseif tag == "find_go" then find_go(p, el.tags.planet, el.tags.platform, el.tags.count)
  elseif tag == "find_go_out" then find_go_out(p, el.tags.planet)
  elseif tag == "find_chest" then
    local s = game.surfaces[el.tags.s]
    if s and s.valid then
      pcall(function() p.set_controller{type = defines.controllers.remote, surface = s, position = {x = el.tags.x, y = el.tags.y}} end)
    end
  elseif tag == "plat_lost_toggle" then
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
    M.refresh(p)           -- вкладка тоже перерисовывается: кнопка сразу перестаёт гореть
  elseif tag == "pop_close" then
    local f = p.gui.screen[el.tags.frame]
    if f then f.destroy() end
  elseif tag == "mvp_vote" then
    local who = el.tags.who
    local tp = who ~= "" and game.get_player(who) or nil
    -- голосовать можно только за тех, кто онлайн (старая кнопка ушедшего игрока ничего не делает)
    if who == "" or (tp and tp.valid and tp.connected and who ~= p.name) then
      C.D().mvp[p.name] = who ~= "" and who or nil
    end
    if p.gui.screen[POP.mvp] then p.gui.screen[POP.mvp].destroy() end
    M.refresh(p)
  elseif tag == "evo_pick" then
    gs.evo_pick = gs.evo_pick or {}
    gs.evo_pick[el.tags.planet] = not el.tags.shown
    M.refresh(p)
  elseif tag == "refresh" then gs.tip_shift = (gs.tip_shift or 0) + 1; M.refresh(p)
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
  end
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
  if el and el.valid and el.tags and el.tags.tr == "find_scan" then
    local p = game.get_player(e.player_index)
    GS(p).find_scan = el.state or nil
    if el.state then start_scan(p) else LG.scan_cancel(p.index) end
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
  -- число, которое админ ставит в игре (кулдауны)
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

return M
