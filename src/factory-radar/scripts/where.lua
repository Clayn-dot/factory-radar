-- Factory Radar: где кто и на что смотрит
local C = require("scripts.core")
local M = {}

local function activity(p)
  if not p.connected then return {"tr-where.offline"} end
  if p.ticks_to_respawn then return {"tr-where.respawning"} end
  local v = p.vehicle
  if v and v.valid then return {"tr-where.in-vehicle", "[entity=" .. v.name .. "]", v.localised_name} end
  if p.character then return {"tr-where.on-foot"} end
  return {"tr-where.no-body"}
end

local function location(p)
  local s = p.physical_surface
  if not (s and s.valid) then return "?" end
  if s.platform then
    local pl = s.platform
    if pl.space_location then
      return {"tr-where.platform-at", C.place(s), C.planet_ls(pl.space_location.name)}
    elseif pl.space_connection then
      return {"tr-where.platform-flying", C.place(s), C.planet_ls(pl.space_connection.from.name), C.planet_ls(pl.space_connection.to.name)}
    end
  end
  return C.place(s)
end

-- чем сейчас занят игрок (только то, что сообщает игра); nil = ничего особенного
function M.doing(p)
  if not p.connected then return nil end
  local parts = {}
  local function try(fn) local ok, v = pcall(fn); if ok and v then parts[#parts + 1] = v end end
  try(function()
    if p.controller_type == defines.controllers.remote then return {"tr-where.do-remote"} end
  end)
  try(function()
    local o = p.opened
    if o and o.object_name == "LuaEntity" and o.valid then return {"tr-where.do-opened", "[entity=" .. o.name .. "]"} end
  end)
  try(function()
    if (p.crafting_queue_size or 0) > 0 then
      local q = p.crafting_queue[1]
      return {"tr-where.do-crafting", "[recipe=" .. q.recipe .. "]", p.crafting_queue_size}
    end
  end)
  try(function()
    local ms = p.mining_state
    if ms and ms.mining then
      local e = p.selected
      return {"tr-where.do-mining", (e and e.valid) and ("[entity=" .. e.name .. "]") or ""}
    end
  end)
  try(function()
    local sh = p.shooting_state
    if sh and sh.state ~= defines.shooting.not_shooting then return {"tr-where.do-shooting"} end
  end)
  try(function()
    local cs = p.cursor_stack
    if cs and cs.valid_for_read then return {"tr-where.do-holding", "[item=" .. cs.name .. "]"} end
  end)
  if #parts == 0 then return nil end
  return C.join(parts, ", ")
end

-- смотрит ли игрок в другое место (карта / удалённый просмотр)?
function M.looking(p)
  if not p.connected then return nil end
  local s, ps = p.surface, p.physical_surface
  if not (s and s.valid) then return nil end
  local pos, ppos = p.position, p.physical_position
  local far = s.index ~= ps.index or ((pos.x - ppos.x) ^ 2 + (pos.y - ppos.y) ^ 2) > 60 * 60
  if far then return {surface = s, position = pos} end
  return nil
end

function M.rows(viewer, only)
  local out = {}
  local players = {}
  for _, p in pairs(game.players) do
    if not only or string.lower(p.name) == string.lower(only) then players[#players + 1] = p end
  end
  table.sort(players, function(a, b)
    if a.connected ~= b.connected then return a.connected end
    return a.name < b.name
  end)
  for _, p in ipairs(players) do
    local s = p.physical_surface
    local extra = {""}
    if p.connected then
      if viewer and viewer.index ~= p.index and viewer.physical_surface_index == p.physical_surface_index and s and not s.platform then
        local a, b = viewer.physical_position, p.physical_position
        extra[#extra + 1] = {"tr-where.distance", C.km(math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2))}
      end
      if p.afk_time > 3 * 3600 then extra[#extra + 1] = {"tr-where.afk", C.time(p.afk_time)} end
    else
      extra[#extra + 1] = {"tr-where.last-seen", C.time(game.tick - p.last_online)}
    end
    local look = M.looking(p)
    local doing = M.doing(p)
    if doing then extra[#extra + 1] = {"", " · ", doing} end
    local title = C.shown_title(p.name)
    local head = {"", p.connected and "[color=0.6,1,0.6]●[/color] " or "[color=0.6,0.6,0.6]○[/color] ",
      "[font=default-bold]" .. p.name .. "[/font]",
      title and {"", " ", C.title_rich_tag(title)} or ""}
    local detail = {"", location(p), ", ", activity(p), extra}
    local caption = {"", head, " — ", detail}
    out[#out + 1] = {
      player = p, caption = caption, head = head, detail = detail,
      body = (s and s.valid) and {surface = s, position = p.physical_position} or nil,
      look = look,
      look_caption = look and {"tr-where.looking", C.place(look.surface), C.gps(look.position, look.surface)} or nil,
    }
  end
  return out
end

-- двигает камеру смотрящего (удалённый просмотр); запасной вариант — GPS-тег в чат
function M.jump(viewer, target)
  if not (target and target.surface and target.surface.valid) then return end
  local ok = pcall(function()
    viewer.set_controller{type = defines.controllers.remote, surface = target.surface, position = target.position}
  end)
  if not ok then viewer.print(C.gps(target.position, target.surface)) end
end

return M
