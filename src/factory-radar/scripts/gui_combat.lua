-- Factory Radar: window: combat and destruction
local C = require("scripts.core")
local CB = require("scripts.combat")
local U = require("scripts.gui_ui")
local M = U.M
local GS, W, bar, card_frame, deep_frame, muted, reset_bar = U.GS, U.W, U.bar, U.card_frame, U.deep_frame, U.muted, U.reset_bar
local scope, short_tab, sk, wrap = U.scope, U.short_tab, U.sk, U.wrap
local function filter_button(...) return U.filter_button(...) end

local function weapons_card(p, pane, s, shift, total)
  local wbox = deep_frame(card_frame(pane, {shift and "tr-gui.combat-total-shift" or "tr-gui.combat-total-total", C.n(total)}))
  local wh = wbox.add{type = "label", caption = {"tr-gui.combat-weapons"}, style = "caption_label", tooltip = {"tr-gui.tip-weapons"}}
  wh.style.bottom_margin = 4
  local ws = CB.top(shift and s.weap_shift or s.weap, 10)
  if #ws == 0 then muted(wbox, {sk(p, "tr-gui.why-no-kills")}) end
  local mx = ws[1] and ws[1][2] or 1
  for _, w in ipairs(ws) do
    local pct = math.floor(w[2] / math.max(1, total) * 100 + 0.5)
    local wr = bar(wbox, w[2] / mx, {"", C.weapon_ls(w[1]), " - ", C.n(w[2]), "  (" .. pct .. "%)"}, 200,
      {"tr-gui.tip-weapon", C.n(w[2]), pct})
    wr.style.bottom_margin = 3
  end
end

local function planets_evo_card(p, pane, gs, s, shift)
  local pcard = card_frame(pane, {"tr-gui.combat-planets"})
  -- which planets to show: the same list as other tabs (without enemies hidden at once)
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
    local icon_path = C.place_icon(r.key)
    if icon_path then
      local icon = card.add{type = "sprite", sprite = icon_path}
      icon.style.width = 40
      icon.style.height = 40
      icon.style.stretch_image_to_widget_size = true
    end
    local col = card.add{type = "flow", direction = "vertical"}
    col.style.left_margin = 8
    local k = shift and pk.kills_shift or pk.kills
    col.add{type = "label", caption = {"", "[font=default-bold]", C.planet_ls(r.key), "[/font]   ",
      k > 0 and {"tr-gui.combat-kills", C.n(k)} or {sk(p, "tr-gui.combat-kills-none")}}}
    -- evolution of each enemy faction here, for the tooltip
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
      -- last three shifts as numbers: 98.97% -> 98.98% -> 99.00% (+0.03%)
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
end

local function enemies_card(p, pane, s, shift)
  local ebox = deep_frame(card_frame(pane, {sk(p, "tr-gui.combat-enemies")}))
  local arr = {}
  for name, en in pairs(shift and s.enemies_shift or s.enemies) do arr[#arr + 1] = {name, en} end
  table.sort(arr, function(a, b) return a[2].n > b[2].n end)
  if #arr == 0 then muted(ebox, {sk(p, "tr-gui.why-no-kills")}) else
    local t = ebox.add{type = "table", column_count = 3}
    t.style.horizontal_spacing = 16
    for _, h in ipairs({"enemy", "count", "best"}) do t.add{type = "label", caption = {"tr-gui.combat-col-" .. h}, style = "caption_label"} end
    for i = 1, math.min(15, #arr) do
      local name, en = arr[i][1], arr[i][2]
      local proto = prototypes.entity[name]
      t.add{type = "label", caption = {"", "[entity=" .. name .. "] ", proto and proto.localised_name or name}}
      t.add{type = "label", caption = C.n(en.n)}
      local bw, bn = CB.best(en.w)
      t.add{type = "label", caption = bw and {"", C.weapon_ls(bw), "  [color=0.6,0.6,0.6]", C.n(bn), "[/color]"} or "-"}
    end
  end
end

local function fill_combat(p, pane)
  pane.clear()
  local gs = GS(p)
  local shift = scope(p) == "shift"
  local s = CB.S()
  local total = shift and s.shift or s.total
  weapons_card(p, pane, s, shift, total)

  planets_evo_card(p, pane, gs, s, shift)

  enemies_card(p, pane, s, shift)
  muted(pane, {"tr-gui.combat-hint"})
  reset_bar(p, pane, "combat")
end

---------------------------------------------------------------- Combat: destruction per planet
local function fill_destruction(p, pane)
  pane.clear()
  local d = C.D()
  -- an entity with picture and name, and how many
  local function ent_part(name, n)
    local pr = prototypes.entity[name]
    return {"", "[entity=" .. name .. "] ", pr and pr.localised_name or name, " ×", C.n(n)}
  end
  local sc = scope(p)
  local src = sc == "total" and d.plost or d.shift_plost
  local lds = sc == "total" and (d.ldest or {}) or (d.ldest_shift or {})
  local keys = {}
  for k, n in pairs(src) do if n > 0 then keys[#keys + 1] = k end end
  -- planets where things were destroyed last come first
  table.sort(keys, function(a, b)
    local la, lb = (lds[a] or {}).last or 0, (lds[b] or {}).last or 0
    if la ~= lb then return la > lb end
    return src[a] > src[b]
  end)
  short_tab(pane, #keys <= 2)
  local total, by_enemy = 0, 0
  for _, k in ipairs(keys) do
    total = total + src[k]
    by_enemy = by_enemy + ((lds[k] or {}).enemy_n or 0)
  end
  local head = card_frame(pane, {sk(p, "tr-gui.dest-total"), C.n(total), C.n(by_enemy)})
  if #keys == 0 then muted(deep_frame(head), {sk(p, "tr-gui.why-no-lost")}) end
  -- the freshest destruction as a list: when, where, what, with what and whose
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
    -- enemies: who
    line("tr-gui.dest-by", M.top_list(ld.by, 5, function(name, n)
      if string.sub(name, 1, 7) == "damage:" then return {"", C.damage_ls(string.sub(name, 8)), " ×", C.n(n)} end
      if name == "unknown" then return {"", {"tr-gui.dest-unknown"}, " ×", C.n(n)} end
      return ent_part(name, n)
    end))
    -- not enemies: explosions, fire, acid, lightning, own vehicles: by damage type or by cause
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
U.fill_destruction = fill_destruction
U.fill_combat = fill_combat
