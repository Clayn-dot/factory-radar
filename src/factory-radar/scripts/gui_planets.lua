-- Factory Radar: window: planets, research and planet filters
local C = require("scripts.core")
local P = require("scripts.planets")
local RS = require("scripts.research")
local CB = require("scripts.combat")
local U = require("scripts.gui_ui")
local FIT, GS, W, bar, card_frame, deep_frame, muted = U.FIT, U.GS, U.W, U.bar, U.card_frame, U.deep_frame, U.muted
local reset_bar, short_tab, wrap = U.reset_bar, U.short_tab, U.wrap

local function planet_rows(gs)
  local rows = {}
  for _, key in ipairs(C.planets_list()) do
    local surf = C.surface(key)
    rows[#rows + 1] = {key = key, s = (surf and surf.valid) and surf or nil, st = C.PL(key)}
  end
  local frozen = gs.nat_rank or {}
  local function natural_rank(r) if r.st.mastered then return 0 elseif r.s then return 1 end return 2 end
  -- while a planet's own science is being edited it keeps its place (a shift can move the rank)
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
  return rows
end

local function card_head(p, pcard, r, gs)
    local key, st = r.key, r.st
    local card = pcard.add{type = "frame", direction = "horizontal", style = "inside_deep_frame"}
    card.style.horizontally_stretchable = true
    card.style.padding = 8
    card.style.bottom_margin = 6
    -- planet icon vertically in the middle of the card
    local ibox = card.add{type = "flow", direction = "vertical"}
    ibox.style.vertically_stretchable = true
    ibox.style.vertical_align = "center"
    local icon_path = C.place_icon(key)
    if icon_path then
      local icon = ibox.add{type = "sprite", sprite = icon_path}
      icon.style.width = 36
      icon.style.height = 36
      icon.style.stretch_image_to_widget_size = true
    end
    local col = card.add{type = "flow", direction = "vertical"}
    col.style.left_margin = 8
    col.style.horizontally_stretchable = true      -- the planet card is full width
    local status
    if st.mastered then status = {"tr-gui.planet-mastered", st.by or {"tr-gui.before-install"}}
    elseif r.s then status = {"tr-gui.planet-in-progress"}
    else status = {"tr-gui.planet-unvisited"} end
    local head = col.add{type = "flow", direction = "horizontal"}
    head.style.vertical_align = "center"
    head.style.horizontally_stretchable = true
    head.add{type = "label", caption = {"", "[font=default-bold]", C.planet_ls(key), "[/font]  ", status}}
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
    ne.style.height = 24
    ne.style.minimal_width = 0
    ne.style.padding = {0, 8, 2, 8}
  return col, hmanual, ned
end

local function native_editor(p, col, key, hmanual)
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
    rb.style.padding = {0, 8, 2, 8}
    rb.style.top_margin = 4
    rb.enabled = p.admin
  end
  if not p.admin then muted(ebox, {"tr-gui.native-admin"}) end
end

local function pack_progress(col, key, st, first)
  local sci_ok, list = P.science_state(key)
  local nsteps = 2 + math.max(1, #list)
  local got = (first and 1 or 0) + (st.silo and 1 or 0)
  local packs = {}        -- {item, orbital?, present?}
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
  local brw = bar(brow, st.mastered and 1 or got / nsteps, nil, 150, tip)
  local function step(cap, ok)
    local sl = brw.add{type = "label", caption = cap, tooltip = tip}
    sl.style.left_margin = 6
    if not ok then sl.style.font_color = {0.6, 0.6, 0.6} end
  end
  step({"tr-gui.planet-step-land", first and "✓" or "✗"}, first)
  step({"tr-gui.planet-step-silo", "[entity=" .. silo .. "]", st.silo and "✓" or "✗"}, st.silo)
  local pbox = brow.add{type = "flow", direction = "horizontal"}
  pbox.style.vertical_align = "center"
  pbox.style.left_margin = 10
  local pn = pbox.add{type = "label", caption = {"tr-gui.planet-native-head"}, tooltip = tip}
  for _, x in ipairs(packs) do if not x[3] then pn.style.font_color = {0.6, 0.6, 0.6} end end
  local ptab2 = pbox.add{type = "table", column_count = math.max(1, math.floor((W - 595) / 44))}
  ptab2.style.horizontal_spacing = 4
  ptab2.style.vertical_spacing = 2
  for _, x in ipairs(packs) do
    local orb = x[2] and "[img=item/space-platform-starter-pack]" or ""
    local cl2 = ptab2.add{type = "label", caption = "[item=" .. x[1] .. "]" .. orb .. " " .. (x[3] and "✓" or "✗"), tooltip = tip}
    cl2.style.minimal_width = 40
    cl2.style.single_line = true
    if not x[3] then cl2.style.font_color = {0.6, 0.6, 0.6} end
  end
end

local function made_lines(col, r, key)
  local made = P.made_here(r.s)
  -- only what was really made here (a pack with 0 is not shown)
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
    -- science: all kinds made here; plain items: the six biggest
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
end

local function info_lines(col, st, key, d, first)
  local info = {}
  if first then
    info[#info + 1] = {first.crew and #first.crew > 1 and "tr-gui.planet-first-many" or "tr-gui.planet-first", C.first_who(first)}
  end
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
    -- output of the last three shifts as numbers, the oldest first; always a separate line at the left edge
    local n = #st.history
    local parts = {}
    for i = math.max(1, n - 2), n do parts[#parts + 1] = C.n(st.history[i]) end
    local hl = col.add{type = "label", caption = {"tr-gui.planet-history3", C.join(parts, " → ")}, tooltip = {"tr-gui.planet-history-tip"}}
    hl.style.font_color = {0.6, 0.6, 0.6}
  end
end

local function unvisited_body(col, key)
  local nat = P.native(key)
  local icons = ""
  for _, pk in ipairs(nat) do icons = icons .. "[item=" .. pk .. "]" end
  local l = col.add{type = "label", caption = {"tr-gui.planet-unvisited-hint", icons ~= "" and {"tr-gui.planet-native", icons} or ""}}
  l.style.font_color = {0.55, 0.55, 0.55}
end

local function fill_planets(p, pane)
  pane.clear()
  local d = C.D()
  -- all visible planets of the game, including those nobody has visited
  local gs = GS(p)
  local rows = planet_rows(gs)
  local done, open = C.count_mastered()
  short_tab(pane, 90 + 150 * #rows <= FIT)
  local pcard = card_frame(pane, {"tr-gui.tab-planets"})
  local sbar = bar(pcard, #rows > 0 and done / #rows or 0, {"tr-gui.planets-summary", done, open, #rows}, 260)
  sbar.style.bottom_margin = 8
  for _, r in ipairs(rows) do
    local key, st = r.key, r.st
    local col, hmanual, ned = card_head(p, pcard, r, gs)
    if ned then native_editor(p, col, key, hmanual) end
    if r.s then
      local first = d.first[key]
      pack_progress(col, key, st, first)
      made_lines(col, r, key)
      info_lines(col, st, key, d, first)
    else
      unvisited_body(col, key)
    end
  end
  muted(pane, {"tr-gui.planets-hint"})
end

local function science_usage(pane)
  -- what the labs really spend, next to what is made (10 minute statistics)
  local sbox = deep_frame(card_frame(pane, {"tr-gui.sci-head"}, {"tr-gui.sci-tip"}))
  local use = RS.consumption()
  if #use == 0 then muted(sbox, {"tr-gui.sci-none"}) else
    local ut = sbox.add{type = "table", column_count = 4}
    ut.style.horizontal_spacing = 18
    for _, h in ipairs({"pack", "made", "spent", "where"}) do
      ut.add{type = "label", caption = {"tr-gui.sci-col-" .. h}, style = "caption_label"}
    end
    for _, r in ipairs(use) do
      ut.add{type = "label", caption = {"", "[item=" .. r.name .. "] ", prototypes.item[r.name].localised_name}}
      ut.add{type = "label", caption = {"tr-gui.sci-rate", string.format("%.1f", r.made)}}
      local lack = r.spent > r.made * 1.05 and r.spent > 0.05
      ut.add{type = "label", caption = {"", lack and "[color=1,0.6,0.45]" or "[color=0.7,1,0.7]", {"tr-gui.sci-rate", string.format("%.1f", r.spent)}, "[/color]"}}
      ut.add{type = "label", caption = r.where and (r.platform and {"", "[img=item/space-platform-starter-pack] ", r.where} or C.planet_ls(r.where)) or "-"}
    end
  end
end

local function milestones(pane)
  local ms = RS.milestone_rows()
  local mbox = deep_frame(card_frame(pane, {"tr-gui.research-milestones"}))
  if #ms == 0 then muted(mbox, {"tr-gui.research-milestones-none"}) else
    local mt = mbox.add{type = "table", column_count = 1 + #RS.MILESTONES}
    mt.style.horizontal_spacing = 8
    mt.add{type = "label", caption = {"tr-gui.research-col-pack"}, style = "caption_label"}
    -- short headers (1, 1k, 10k ... 1M, 1B) so all columns fit in the window
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
        if not m then cap = "[color=0.45,0.45,0.45]-[/color]"
        elseif m.before then cap = {"", "[color=0.6,0.6,0.6]", {"tr-gui.before-install"}, "[/color]"}
        else
          local loc
          if m.place then
            if m.plat then loc = {"", " [img=item/space-platform-starter-pack] ", m.place}
            else
              local path = C.place_icon(m.place)
              loc = path and (" [img=" .. path .. "]") or ""
            end
          end
          cap = {"", "[font=default-bold]", C.clock(m.tick), "[/font]", loc or ""}
        end
        local cl = mt.add{type = "label", caption = cap}
        cl.style.minimal_width = 96
      end
    end
  end
end

local function fill_research(p, pane)
  pane.clear()
  local f = game.forces.player
  local cur = f.current_research
  local cbox = deep_frame(card_frame(pane, {"tr-gui.research-current"}))
  if cur then
    bar(cbox, f.research_progress, {"", "[technology=" .. cur.name .. "] ", cur.localised_name,
      " - " .. math.floor(f.research_progress * 100) .. "%"}, 240)
  else
    muted(cbox, {"tr-gui.research-idle"})
  end

  science_usage(pane)

  local rows = RS.infinite_rows()
  local ibox = deep_frame(card_frame(pane, {"tr-gui.research-infinite"}))
  if #rows == 0 then muted(ibox, {"tr-gui.why-no-infinite"}) end
  local t = ibox.add{type = "table", column_count = 3}
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

  milestones(pane)

  reset_bar(p, pane, "research")
end

-- Which planets/platforms to show: the button at the right of the header opens a small panel NEXT to the window.
-- The panel does not close on toggling (a dropdown would close after every click)
-- and moves nothing in the tab. Light = shown, pressed = hidden. A hidden one is not counted at all.
-- Planets: "q" (Quality), "e" (Energy), "c" (Combat) each have their own choice; "pl" is platforms
local FLT = "tr_filter"
local FLT_TAB = {q = "quality", e = "energy", pl = "platforms", c = "combat"}
local function hidden_set(p, which) return GS(p)[which == "pl" and "hide_plats" or ("hide_" .. which)] or {} end
local function hidden_planets(p, which) return hidden_set(p, which) end
local function planet_entries()
  local list = {}
  for _, sf in pairs(game.surfaces) do
    if C.RP(sf) then
      local key = C.key(sf)
      if key then list[#list + 1] = {id = key, caption = C.planet_ls(key)} end
    end
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
  b.style.padding = {0, 10, 2, 10}
  return b
end
U.filter_button = filter_button
U.planet_entries = planet_entries
U.hidden_planets = hidden_planets
U.fill_research = fill_research
U.fill_planets = fill_planets
U.hidden_set = hidden_set
U.filter_entries = filter_entries
U.FLT_TAB = FLT_TAB
U.FLT = FLT
