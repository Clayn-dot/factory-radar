-- Factory Radar: window: item search over logistic networks
local C = require("scripts.core")
local LG = require("scripts.logistics")
local U = require("scripts.gui_ui")
local M = U.M
local FIND, FRAME, GS, W, muted = U.FIND, U.FRAME, U.GS, U.W, U.muted

---------------------------------------------------------------- item search over logistic networks
-- a small window: pick an item (with quality), see on which planets and platforms and how much of it is in logistic networks.
-- Click a place: the camera goes there (remote view), containers with the item are highlighted and listed in the window.
-- The "and outside networks" box scans plain containers on all planets (one planet at a time)
local function loupe() return helpers.is_valid_sprite_path("utility/search") and "[img=utility/search] " or "" end
local function item_icon(it) return "[item=" .. it.name .. ",quality=" .. (it.quality or "normal") .. "]" end

-- where this place is: a planet or platform surface
local function find_surface(planet, platform)
  if planet then
    return C.surface(planet)
  end
  for _, pf in pairs(game.forces.player.platforms) do
    if pf.valid and pf.name == platform then return pf.surface end
  end
end

-- the highlight is removed when the search is closed or a new one starts (it also fades by itself after 2 minutes)
local function clear_marks(p)
  local gs = GS(p)
  for _, o in ipairs(gs.find_marks or {}) do
    pcall(function() if o.valid then o.destroy() end end)
  end
  gs.find_marks = nil
end

-- as in the game: a frame around the container and an item icon on the map
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
      -- game frame (yellow corners like a selected entity); only the one who searched sees it
      keep(s.create_entity{name = "highlight-box", position = {x = c.x, y = c.y}, box_type = "entity", render_player_index = p.index,
        bounding_box = {left_top = {x = b[1], y = b[2]}, right_bottom = {x = b[3], y = b[4]}}, time_to_live = 7200})
    end)
    if it then
      -- item icon on the map (size in tiles, so it is large) and a quality icon in its corner
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
-- place label: icon and name (a platform gets the hub icon and the name)
local function place_caption(planet, platform)
  if planet then return C.planet_ls(planet) end
  return {"", "[img=entity/space-platform-hub] ", platform}
end

-- enabled search places: logistic networks and players are on by default, the rest are not
local function find_opts(gs)
  return {net = gs.find_net ~= false, ply = gs.find_ply ~= false, scan = gs.find_scan and true or false, mach = gs.find_mach and true or false}
end

-- section header and a dark frame for data
local function find_section(parent, title)
  local f = parent.add{type = "flow", direction = "vertical"}
  f.style.top_margin = 8
  local l = f.add{type = "label", caption = title, style = "caption_label"}
  l.style.bottom_margin = 3
  local box = f.add{type = "frame", direction = "vertical", style = "inside_deep_frame"}
  box.style.horizontally_stretchable = true
  box.style.padding = 6
  return box
end

-- list row: the place (a button) and how much is there
local ROW_W = 360
local LIST_H = 5 * 29 + 4   -- five rows are shown, the rest scrolls
local function find_row(t, caption, tags, tip, chosen, count, icon)
  local fl = t.add{type = "flow", direction = "horizontal"}
  fl.style.horizontal_spacing = 0
  fl.style.horizontally_stretchable = true
  fl.style.vertical_align = "center"
  local b = fl.add{type = "button", caption = caption, toggled = chosen and true or false, tags = tags, tooltip = tip}
  b.style.horizontal_align = "left"
  b.style.height = 28
  b.style.minimal_width = ROW_W
  b.style.horizontally_stretchable = true
  b.style.padding = {0, 6}
  -- the number with the item icon lies over the button's right edge (a click passes through), black and centered on the button
  local cnt = fl.add{type = "label", caption = {"", C.big(count), " ", icon or ""}, style = "bold_label", ignored_by_interaction = true}
  cnt.style.width = 120
  cnt.style.height = 28
  cnt.style.vertical_align = "center"
  cnt.style.horizontal_align = "right"
  cnt.style.right_padding = 10
  cnt.style.left_margin = -120
  cnt.style.font_color = {0, 0, 0}
end

-- planets and platforms with the item: only what is ticked is counted; most first
local function find_places(p, it)
  local gs = GS(p)
  local o = find_opts(gs)
  local by, list, total = {}, {}, 0
  local function add(planet, platform, src, n)
    if not (n and n > 0) then return end
    local k = planet or ("pf:" .. platform)
    local r = by[k]
    if not r then r = {planet = planet, platform = platform, count = 0, src = {}}; by[k] = r; list[#list + 1] = r end
    r.count = r.count + n
    r.src[src] = (r.src[src] or 0) + n
    total = total + n
  end
  if o.net then for _, r in ipairs((LG.search(it.name, it.quality))) do add(r.planet, r.platform, "net", r.count) end end
  if o.ply then for _, c in ipairs(LG.carried(it.name, it.quality)) do add(c.planet, c.platform, "ply", c.count) end end
  local job = LG.scan_job(p.index)
  if job then
    if o.scan then for key, r in pairs(job.done or {}) do add(key, nil, "out", r.count) end end
    if o.mach then for key, r in pairs(job.mach or {}) do add(key, nil, "mach", r.count) end end
  end
  table.sort(list, function(a, b)
    if a.count ~= b.count then return a.count > b.count end
    return (a.planet or a.platform or "") < (b.planet or b.platform or "")
  end)
  return list, total, job
end

-- tooltip of a place row: what the number is made of
local function row_tip(r)
  local t = {""}
  for _, k in ipairs({"net", "ply", "out", "mach"}) do
    if r.src[k] then
      if #t > 1 then t[#t + 1] = "\n" end
      t[#t + 1] = {"tr-find.src-" .. k, C.big(r.src[k])}
    end
  end
  t[#t + 1] = "\n"
  t[#t + 1] = {"tr-find.row-tip"}
  return t
end

-- what is at the chosen place, by ticked boxes: logistic networks, players, plain containers, machines
local function place_data(p, sel)
  local gs = GS(p)
  local it = gs.find_item
  local s = find_surface(sel.planet, sel.platform)
  if not (it and s and s.valid) then return nil end
  local o = find_opts(gs)
  local secs = {}
  if o.net then
    local list, found, _, n_all = LG.chests(s, it.name, it.quality, 1000)
    secs[#secs + 1] = {key = "net", list = list, found = found, n_all = n_all}
  end
  local job = LG.scan_job(p.index)
  if sel.planet and job then
    if o.scan then
      local r = job.done and job.done[sel.planet]
      secs[#secs + 1] = {key = "out", list = r and r.list or {}, found = r and r.count or 0, n_all = r and r.chests or 0, pending = (not r) and not job.finished}
    end
    if o.mach then
      local r = job.mach and job.mach[sel.planet]
      secs[#secs + 1] = {key = "mach", list = r and r.list or {}, found = r and r.count or 0, n_all = r and r.chests or 0, pending = (not r) and not job.finished}
    end
  end
  if o.ply then
    local list, sum = {}, 0
    for _, c in ipairs(LG.carried(it.name, it.quality)) do
      if c.surface == s.index then
        list[#list + 1] = {name = "character", count = c.count, x = c.x, y = c.y, player = c.player, quality = "normal"}
        sum = sum + c.count
      end
    end
    secs[#secs + 1] = {key = "ply", list = list, found = sum, n_all = #list}
  end
  return s, secs
end

-- details of the chosen place. Coordinates are in the tooltip, not in the row
local function fill_find_details(p, box, s, secs)
  box.clear()
  local gs = GS(p)
  local sel, it = gs.find_det, gs.find_item
  if not (sel and it and s) then return end
  local head = box.add{type = "label", caption = {"tr-find.det-place", place_caption(sel.planet, sel.platform)}, style = "caption_label"}
  head.style.top_margin = 10
  local icon = item_icon(it)
  local shown = 0
  for _, sec in ipairs(secs) do
    if sec.pending or #sec.list > 0 then
      shown = shown + 1
      local inner = find_section(box, {"tr-find.sec-" .. sec.key, C.big(sec.found)})
      if sec.pending then
        muted(inner, {"tr-find.scan-wait"})
      else
        local lst = inner.add{type = "scroll-pane", direction = "vertical"}
        lst.horizontal_scroll_policy = "never"
        lst.vertical_scroll_policy = "auto-and-reserve-space"
        lst.style.maximal_height = LIST_H
        lst.style.minimal_width = 400
        lst.style.padding = 0
        local col = lst.add{type = "flow", direction = "vertical"}
        col.style.vertical_spacing = 1
        col.style.horizontally_stretchable = true
        for _, c in ipairs(sec.list) do
          local pr = prototypes.entity[c.name]
          local who = c.player or (pr and pr.localised_name or c.name)
          find_row(col, {"", "[entity=" .. c.name .. ((c.quality and c.quality ~= "normal") and (",quality=" .. c.quality) or "") .. "]  ", who},
            {tr = "find_chest", s = s.index, x = c.x, y = c.y},
            {"tr-find." .. (sec.key == "ply" and "det-tip-player" or (sec.key == "mach" and "det-tip-machine" or "det-tip")), math.floor(c.x), math.floor(c.y)},
            false, c.count, icon)
        end
        if sec.n_all > #sec.list then muted(inner, {"tr-find.det-more", #sec.list, sec.n_all}) end
      end
    end
  end
  if shown == 0 then muted(box, {"tr-find.det-none"}) end
end

local function start_scan(p)
  local gs = GS(p)
  local it = gs.find_item
  if not (it and it.name) then return end
  if gs.find_scan or gs.find_mach then
    LG.scan_start(p.index, it.name, it.quality or "normal", {chests = gs.find_scan and true or false, machines = gs.find_mach and true or false})
  else
    LG.scan_cancel(p.index)
  end
end

local function fill_find_results(p, res)
  local gs = GS(p)
  local it = gs.find_item
  local row = res.parent and res.parent.tr_find_row
  local has_item = it and it.name and prototypes.item[it.name]
  if row and row.tr_find_hint then row.tr_find_hint.visible = not has_item end
  if not has_item then
    res.clear()
    gs.find_sig = nil
    return
  end
  local rows, total, job = find_places(p, it)
  local d = gs.find_det
  local fs, secs
  if d then fs, secs = place_data(p, d) end
  -- nothing changed since last time: do not rebuild the window (otherwise the scroll jumps up)
  local sg = {it.name, it.quality or "", tostring(gs.find_net), tostring(gs.find_ply), tostring(gs.find_scan), tostring(gs.find_mach),
    total, #rows, job and #job.queue or "-", d and (d.planet or d.platform) or "-"}
  for _, r in ipairs(rows) do sg[#sg + 1] = (r.planet or r.platform) .. ":" .. r.count end
  for _, sec in ipairs(secs or {}) do
    local c1 = sec.list[1]
    sg[#sg + 1] = sec.key .. ":" .. sec.found .. ":" .. #sec.list .. ":" .. tostring(sec.pending) .. ":" .. (c1 and (c1.x .. "," .. c1.y) or "-")
  end
  local sig = table.concat(sg, "|")
  if gs.find_sig == sig and #res.children > 0 then return end
  gs.find_sig = sig
  res.clear()
  local head = res.add{type = "label", name = "tr_find_head", caption = {"tr-find.total", loupe(), item_icon(it), C.big(total), #rows}, style = "caption_label"}
  head.style.top_margin = 4
  if job and not job.finished and (gs.find_scan or gs.find_mach) then
    local pr = muted(res, {"tr-find.scan-progress", job.total - #job.queue, job.total})
    pr.name = "tr_find_prog"
  end
  local inner = find_section(res, {"tr-find.sec-where"})
  if #rows == 0 then
    muted(inner, {"tr-find.none"})
  else
    local sp = inner.add{type = "scroll-pane", direction = "vertical"}
    sp.horizontal_scroll_policy = "never"
    sp.vertical_scroll_policy = "auto-and-reserve-space"
    sp.style.maximal_height = LIST_H
    sp.style.minimal_width = 400
    sp.style.padding = 0
    local t = sp.add{type = "flow", direction = "vertical"}
    t.style.vertical_spacing = 1
    t.style.horizontally_stretchable = true
    for _, r in ipairs(rows) do
      local chosen = d and d.planet == r.planet and d.platform == r.platform
      find_row(t, place_caption(r.planet, r.platform), {tr = "find_go", planet = r.planet, platform = r.platform}, row_tip(r), chosen, r.count, item_icon(it))
    end
  end
  res.add{type = "flow", name = "tr_find_det", direction = "vertical"}
  fill_find_details(p, res.tr_find_det, fs, secs)
end

-- auto: scheduled refresh (if nothing changed, the window is left alone)
function M.refresh_find(p, auto)
  if not auto then GS(p).find_sig = nil end
  local f = p.gui.screen[FIND]
  if f and f.valid and f.tr_find_box and f.tr_find_box.tr_find_res then fill_find_results(p, f.tr_find_box.tr_find_res) end
end

-- on a timer: a running plain-container scan does a step (one planet), the window refreshes
function M.scan_tick()
  for _, pi in ipairs(LG.scan_step()) do
    local p = game.get_player(pi)
    if p and p.valid then
      local job = LG.scan_job(pi)
      local f = p.gui.screen[FIND]
      local res = f and f.valid and f.tr_find_box and f.tr_find_box.tr_find_res
      local gs = GS(p)
      if job and not job.finished and res and res.valid and res.tr_find_head and gs.find_item then
        -- while a scan runs: only the total line and progress change, lists are left alone (otherwise the scroll jumps)
        local rows, total = find_places(p, gs.find_item)
        res.tr_find_head.caption = {"tr-find.total", loupe(), item_icon(gs.find_item), C.big(total), #rows}
        if res.tr_find_prog then res.tr_find_prog.caption = {"tr-find.scan-progress", job.total - #job.queue, job.total} end
      else
        M.refresh_find(p, true)
      end
    end
  end
end

-- click on a place: go there, highlight what was found and show details
local function find_go(p, planet, platform, no_move)
  local gs = GS(p)
  gs.find_det = {planet = planet, platform = platform}
  local s, secs = place_data(p, gs.find_det)
  if not s then return end
  local all, first = {}, nil
  for _, sec in ipairs(secs) do
    for _, c in ipairs(sec.list) do
      all[#all + 1] = c
      first = first or c
    end
  end
  mark_chests(p, s, all)
  local pos = first and {x = first.x, y = first.y} or {x = 0, y = 0}
  if not no_move then pcall(function() p.set_controller{type = defines.controllers.remote, surface = s, position = pos} end) end
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
  local gs = GS(p)
  f = p.gui.screen.add{type = "frame", name = FIND, direction = "vertical"}
  local tb = f.add{type = "flow", direction = "horizontal"}
  tb.drag_target = f
  tb.style.vertical_align = "center"
  tb.add{type = "label", caption = {"", loupe(), {"tr-find.title"}}, style = "frame_title", ignored_by_interaction = true}
  local dr = tb.add{type = "empty-widget", style = "draggable_space_header", ignored_by_interaction = true}
  dr.style.horizontally_stretchable = true
  dr.style.height = 24
  -- collapse, refresh, close
  tb.add{type = "sprite-button", sprite = gs.find_min and "tr-win-max-d" or "tr-win-min-d", style = "frame_action_button", tags = {tr = "find_min"},
    tooltip = {gs.find_min and "tr-find.expand-tip" or "tr-find.min-tip"}}
  tb.add{type = "sprite-button", sprite = helpers.is_valid_sprite_path("utility/reset_white") and "utility/reset_white" or "utility/refresh",
    style = "frame_action_button", tags = {tr = "find_refresh"}, tooltip = {"tr-find.refresh"}}
  tb.add{type = "sprite-button", sprite = "utility/close", style = "frame_action_button", tags = {tr = "find_close"}}
  local box = f.add{type = "frame", name = "tr_find_box", direction = "vertical", style = "inside_shallow_frame_with_padding"}
  local row = box.add{type = "flow", direction = "horizontal"}
  row.style.vertical_align = "center"
  row.style.horizontal_spacing = 8
  row.style.bottom_margin = 4
  row.name = "tr_find_row"
  row.add{type = "label", caption = {"tr-find.item"}, style = "caption_label"}
  local ok, pick = pcall(function()
    return row.add{type = "choose-elem-button", elem_type = "item-with-quality", tags = {tr = "find_pick"}}
  end)
  if not ok then pick = row.add{type = "choose-elem-button", elem_type = "item", tags = {tr = "find_pick"}} end
  local hint = row.add{type = "label", name = "tr_find_hint", caption = {"tr-find.hint"}}
  hint.style.font_color = {0.65, 0.65, 0.65}
  hint.style.single_line = false
  hint.style.maximal_width = 280
  local it = gs.find_item
  if it and it.name and prototypes.item[it.name] then
    pcall(function() pick.elem_value = (pick.elem_type == "item") and it.name or {name = it.name, quality = it.quality or "normal"} end)
  end
  -- where to search: quick on the left (on at once), slower on the right (off)
  local opts = box.add{type = "table", column_count = 2}
  opts.style.horizontal_spacing = 24
  opts.style.vertical_spacing = 2
  opts.style.left_padding = 6
  local o = find_opts(gs)
  opts.add{type = "checkbox", caption = {"tr-find.net-check"}, state = o.net, tags = {tr = "find_net"}, tooltip = {"tr-find.net-tip"}}
  opts.add{type = "checkbox", caption = {"tr-find.scan-check"}, state = o.scan, tags = {tr = "find_scan"}, tooltip = {"tr-find.scan-tip"}}
  opts.add{type = "checkbox", caption = {"tr-find.ply-check"}, state = o.ply, tags = {tr = "find_ply"}, tooltip = {"tr-find.ply-tip"}}
  opts.add{type = "checkbox", caption = {"tr-find.mach-check"}, state = o.mach, tags = {tr = "find_mach"}, tooltip = {"tr-find.mach-check-tip"}}
  box.add{type = "flow", name = "tr_find_res", direction = "vertical"}
  if gs.find_scan or gs.find_mach then start_scan(p) end
  fill_find_results(p, box.tr_find_res)
  box.visible = not gs.find_min
  pcall(function()
    local frame = p.gui.screen[FRAME]
    local loc, sc, res = frame and frame.location, p.display_scale, p.display_resolution
    if loc then
      -- right of the main window, at the top edge of the screen (the window is tall, there would be no room below) and fully on screen
      f.location = {x = math.floor(math.max(0, math.min(loc.x + (W + 100) * sc, res.width - 580 * sc))), y = math.floor(math.max(0, math.min(loc.y, 30 * sc)))}
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
  if GS(p).find_scan or GS(p).find_mach then
    if GS(p).find_item then start_scan(p) else LG.scan_cancel(p.index) end
  end
  M.refresh_find(p)
end
U.close_find = close_find
U.find_go = find_go
U.start_scan = start_scan
