-- Factory Radar: window: shared sizes, bricks and the radar button
local mod_gui = require("mod-gui")
local C = require("scripts.core")
local RST = require("scripts.reset")
local M = {}
local U = {M = M}    -- shared table of window parts: each part puts here what the others need

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

---------------------------------------------------------------- small blocks
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
-- top level frames in a scroll area get the same width. Without it they shrink to the width of
-- their content (in a scroll area stretchable only stretches to the widest element),
-- and short tabs have more room on the right than on the left
-- One standard for all tabs. The scroll area takes the full window width (before, about 40 px on the right was lost),
-- there is always room on the right for the scroll bar (BAR), the left has the same margin, so edges are symmetric with and without the bar
local PANE_W, PAD_L, PAD_R, BAR = W + 53, 9, 8, 14
local CARD_W = PANE_W - PAD_L - PAD_R - BAR - 6
-- Two templates: a long tab (room for the scroll bar, frames already BAR wide) and a short one (no bar, frames full width).
-- The template is chosen when a tab is built; fill_sub always starts with the long one, a short tab switches by itself
local FW = CARD_W
local FIT = 430      -- how much scroll area height counts as "fits without a bar" (470 maximum minus margins)
-- every tab starts with the long template
function M.reset_fw() FW = CARD_W end
local function full_width(f, parent)
  if parent.type == "scroll-pane" then f.style.minimal_width = FW end
end
local function short_tab(pane, short)
  if short then
    pane.vertical_scroll_policy = "auto"
    FW = CARD_W + BAR
  end
end
-- a card with a header (lighter) and a dark frame for data
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
-- for admins: "Reset" / "Roll back" the tab's statistics
local function reset_bar(p, pane, sec)
  if not p.admin then return end
  local row = pane.add{type = "flow", direction = "horizontal"}
  row.style.top_margin = 10
  local b = row.add{type = "button", caption = {"tr-gui.reset"}, tooltip = {"tr-gui.tip-reset"}, tags = {tr = "reset", sec = sec}}
  b.style.height = 24
  b.style.minimal_width = 0
  b.style.padding = {0, 8, 2, 8}
  if RST.can_undo(sec) then
    local u = row.add{type = "button", caption = {"tr-gui.undo"}, tooltip = {"tr-gui.tip-undo"}, tags = {tr = "undo", sec = sec}}
    u.style.height = 24
    u.style.minimal_width = 0
    u.style.padding = {0, 8, 2, 8}
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

---------------------------------------------------------------- scope: this shift (default) or all time
local function scope(p) return GS(p).scope == "total" and "total" or "shift" end
local function sk(p, key) return key .. "-" .. scope(p) end   -- locale key with the scope suffix

-- "built" for all time: from standing buildings of planets (with robots), like the planets' own count, but not less than the manual counter.
-- Returns a copy of the all-time player table with a refined built
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
U.wrap = wrap
U.deep_frame = deep_frame
U.scope = scope
U.muted = muted
U.bar = bar
U.heading = heading
U.W = W
U.GS = GS
U.card_frame = card_frame
U.sk = sk
U.total_with_built = total_with_built
U.short_tab = short_tab
U.smallbtn = smallbtn
U.COLS = COLS
U.reset_bar = reset_bar
U.FIT = FIT
U.icon = icon
U.FRAME = FRAME
U.FIND = FIND
U.PAD_R = PAD_R
U.PANE_W = PANE_W
U.PAD_L = PAD_L
U.BTN = BTN
return U
