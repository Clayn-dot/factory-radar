-- Factory Radar: поиск предмета по логистическим сетям всех планет и платформ
-- считаем только по запросу (кнопка в быстром доступе), в фоне ничего не крутится
local C = require("scripts.core")
local M = {}

-- сколько предмета лежит в сущности и доступно сети: контейнеры, трюм платформы, грузовая площадка, выход машины,
-- ПЕРСОНАЖ игрока (то, что он несёт, сеть тоже считает), робопорт (роботы и ремкомплекты внутри), паук.
-- Номера инвентарей у разных типов совпадают, поэтому у каждого типа берём свой (иначе в машине можно «найти» чужие предметы).
-- nil — тип, в котором мы не умеем смотреть
local function count_in(ent, name, quality)
  local t = ent.type
  local it = {name = name, quality = quality or "normal"}
  if t == "container" or t == "logistic-container" then return ent.get_inventory(defines.inventory.chest).get_item_count(it) end
  if t == "space-platform-hub" then return ent.get_inventory(defines.inventory.hub_main).get_item_count(it) end
  if t == "cargo-landing-pad" then return ent.get_inventory(defines.inventory.cargo_landing_pad_main).get_item_count(it) end
  if t == "assembling-machine" or t == "furnace" then return ent.get_output_inventory().get_item_count(it) end
  if t == "character" then return ent.get_item_count(it) end
  if t == "roboport" then
    local n = 0
    for _, idx in ipairs({defines.inventory.roboport_robot, defines.inventory.roboport_material}) do
      local inv = ent.get_inventory(idx)
      if inv then n = n + inv.get_item_count(it) end
    end
    return n
  end
  if t == "spider-vehicle" then return ent.get_inventory(defines.inventory.spider_trunk).get_item_count(it) end
  return nil
end

-- то, что в сети лежит у персонажей: считается отдельно («у игроков»)
local function chars_in(net, name, quality)
  local n = 0
  pcall(function()
    for _, m in ipairs(net.providers or {}) do
      if m.valid and m.type == "character" then n = n + (m.get_item_count{name = name, quality = quality} or 0) end
    end
  end)
  return n
end

-- сколько предмета (с качеством) доступно в логистических сетях, по планетам и платформам, от большего к меньшему; нули не берём
function M.search(name, quality)
  local rows, total = {}, 0
  if not (name and prototypes.item[name]) then return rows, total end
  local nets = game.forces.player.logistic_networks
  for sname, list in pairs(nets) do
    local s = game.surfaces[sname]
    if s and s.valid then
      local planet = C.RP(s) and s.planet and s.planet.prototype.name or nil
      local plat = s.platform and s.platform.valid and s.platform or nil
      if planet or plat then
        local sum, n = 0, 0
        for _, net in ipairs(list) do
          if net.valid then
            local ok, c = pcall(function() return net.get_item_count{name = name, quality = quality or "normal"} end)
            if ok and type(c) == "number" then c = math.max(0, c - chars_in(net, name, quality or "normal")) end
            if ok and type(c) == "number" and c > 0 then sum = sum + c; n = n + 1 end
          end
        end
        if sum > 0 then
          rows[#rows + 1] = {planet = planet, platform = plat and plat.name or nil, count = sum, nets = n}
          total = total + sum
        end
      end
    end
  end
  -- платформы: груз лежит в трюме хаба, а логистической сети у платформы может и не быть
  local by_plat = {}
  for _, r in ipairs(rows) do if r.platform then by_plat[r.platform] = r end end
  for _, pl in pairs(game.forces.player.platforms) do
    if pl.valid then
      local hub = pl.hub
      if hub and hub.valid then
        local ok, c = pcall(count_in, hub, name, quality)
        if ok and type(c) == "number" and c > 0 then
          local r = by_plat[pl.name]
          if r then
            if c > r.count then total = total + (c - r.count); r.count = c end
          else
            rows[#rows + 1] = {platform = pl.name, count = c, nets = 0}
            total = total + c
          end
        end
      end
    end
  end
  table.sort(rows, function(a, b)
    if a.count ~= b.count then return a.count > b.count end
    return (a.planet or a.platform or "") < (b.planet or b.platform or "")
  end)
  return rows, total
end

-- сколько предмета несут игроки (в инвентаре персонажа), больше всего первыми, с местом, где игрок стоит
function M.carried(name, quality)
  local out = {}
  if not (name and prototypes.item[name]) then return out end
  for _, pl in pairs(game.players) do
    local ch = pl.character
    if ch and ch.valid then
      local ok, c = pcall(ch.get_item_count, {name = name, quality = quality or "normal"})
      if ok and type(c) == "number" and c > 0 then
        local s = ch.surface
        local planet = C.RP(s) and s.planet and s.planet.prototype.name or nil
        local plat = s.platform and s.platform.valid and s.platform.name or nil
        out[#out + 1] = {player = pl.name, count = c, surface = s.index, planet = planet, platform = plat,
          x = ch.position.x, y = ch.position.y}
      end
    end
  end
  table.sort(out, function(a, b) return a.count > b.count end)
  return out
end

-- контейнеры логистических сетей поверхности, в которых лежит предмет, больше всего первыми.
-- Второе значение — сколько предмета лежит во ВСЕХ найденных контейнерах (а не только в показанных)
function M.chests(s, name, quality, limit)
  local out, seen, sum, unknown = {}, {}, 0, {}
  local function entry(ent, c)
    local box = {ent.position.x - 0.5, ent.position.y - 0.5, ent.position.x + 0.5, ent.position.y + 0.5}
    pcall(function()
      local sb = ent.selection_box
      box = {sb.left_top.x, sb.left_top.y, sb.right_bottom.x, sb.right_bottom.y}
    end)
    local ql = "normal"
    pcall(function() ql = ent.quality.name end)
    return {name = ent.name, count = c, x = ent.position.x, y = ent.position.y, box = box, quality = ql}
  end
  -- хаб платформы: трюм с грузом (у платформы логистической сети может не быть)
  local hub = s.platform and s.platform.valid and s.platform.hub
  if hub and hub.valid then
    local ok, c = pcall(count_in, hub, name, quality)
    if ok and type(c) == "number" and c > 0 then
      sum = sum + c
      out[#out + 1] = entry(hub, c)
      if hub.unit_number then seen[hub.unit_number] = true end
    end
  end
  local nets = game.forces.player.logistic_networks[s.name] or {}
  for _, net in ipairs(nets) do
    if net.valid then
      -- буферные сундуки лежат среди запрашивающих и участников сети, а не среди провайдеров: берём их оттуда
      local extra = {}
      pcall(function()
        for _, list in ipairs({net.requesters or {}, net.logistic_members or {}}) do
          for _, m in ipairs(list) do
            if m.valid and m.type == "logistic-container" and m.prototype.logistic_mode == "buffer" then extra[#extra + 1] = m end
          end
        end
      end)
      for _, list in ipairs({net.storages or {}, net.providers or {}, extra}) do
        for _, ent in ipairs(list) do
          local mode = nil
          pcall(function() mode = ent.prototype.logistic_mode end)
          -- то, что лежит в запрашивающем сундуке, остальным недоступно
          if ent.valid and ent.unit_number and not seen[ent.unit_number] and mode ~= "requester" and ent.type ~= "character" then
            seen[ent.unit_number] = true
            local ok, c = pcall(count_in, ent, name, quality)
            if ok and c == nil then
              -- тип, в котором мы не умеем смотреть: запоминаем, чтобы показать в окне (помогает понять, куда делись предметы)
              unknown[ent.type] = (unknown[ent.type] or 0) + 1
            elseif ok and type(c) == "number" and c > 0 then
              sum = sum + c
              local box = {ent.position.x - 0.5, ent.position.y - 0.5, ent.position.x + 0.5, ent.position.y + 0.5}
              pcall(function()
                local sb = ent.selection_box
                box = {sb.left_top.x, sb.left_top.y, sb.right_bottom.x, sb.right_bottom.y}
              end)
              local ql = "normal"
              pcall(function() ql = ent.quality.name end)
              local who = nil
              if ent.type == "character" then
                pcall(function() who = ent.player and ent.player.name end)
                who = who or false
              end
              out[#out + 1] = {name = ent.name, count = c, x = ent.position.x, y = ent.position.y, box = box, player = who, quality = ql}
            end
          end
        end
      end
    end
  end
  table.sort(out, function(a, b) return a.count > b.count end)
  local n_all = #out
  while #out > (limit or 1000) do table.remove(out) end
  return out, sum, unknown, n_all
end

---------------------------------------------------------------- обычные контейнеры вне логистических сетей
-- Считается по запросу и по одной планете за раз (по таймеру), чтобы игра не зависала. Состояние лежит в storage.
-- машины: то, что лежит внутри (ингредиенты и результат, без модулей)
local MACHINE_INV = {
  ["assembling-machine"] = {"crafter_input", "crafter_output"},
  furnace = {"furnace_source", "furnace_result"},
  lab = {"lab_input"},
  ["rocket-silo"] = {"rocket_silo_input", "rocket_silo_output"},
}
local function machine_count(ent, name, quality)
  local n = 0
  for _, key in ipairs(MACHINE_INV[ent.type] or {}) do
    local idx = defines.inventory[key]
    local inv = idx and ent.get_inventory(idx)
    if inv then n = n + inv.get_item_count{name = name, quality = quality} end
  end
  return n
end

local function scan_machines(s, name, quality)
  local list, sum, n = {}, 0, 0
  local ents = s.find_entities_filtered{type = {"assembling-machine", "furnace", "lab", "rocket-silo"}, force = game.forces.player}
  for _, ent in ipairs(ents) do
    if ent.valid then
      local ok, c = pcall(machine_count, ent, name, quality)
      if ok and type(c) == "number" and c > 0 then
        n = n + 1
        sum = sum + c
        local box = {ent.position.x - 0.5, ent.position.y - 0.5, ent.position.x + 0.5, ent.position.y + 0.5}
        pcall(function()
          local sb = ent.selection_box
          box = {sb.left_top.x, sb.left_top.y, sb.right_bottom.x, sb.right_bottom.y}
        end)
        local ql = "normal"
        pcall(function() ql = ent.quality.name end)
        list[#list + 1] = {name = ent.name, count = c, x = ent.position.x, y = ent.position.y, box = box, quality = ql}
      end
    end
  end
  table.sort(list, function(a, b) return a.count > b.count end)
  while #list > 1000 do table.remove(list) end
  return {count = sum, chests = n, list = list}
end

local function scan_surface(s, name, quality)
  local list, sum, n = {}, 0, 0
  local ents = s.find_entities_filtered{type = {"container", "logistic-container"}, force = game.forces.player}
  for _, ent in ipairs(ents) do
    if ent.valid then
      local inside = false
      pcall(function() inside = ent.logistic_network ~= nil end)
      if not inside then
        local ok, c = pcall(function()
          local inv = ent.get_inventory(defines.inventory.chest)
          return inv and inv.get_item_count{name = name, quality = quality} or 0
        end)
        if ok and type(c) == "number" and c > 0 then
          n = n + 1
          sum = sum + c
          local box = {ent.position.x - 0.5, ent.position.y - 0.5, ent.position.x + 0.5, ent.position.y + 0.5}
          pcall(function()
            local sb = ent.selection_box
            box = {sb.left_top.x, sb.left_top.y, sb.right_bottom.x, sb.right_bottom.y}
          end)
          local ql = "normal"
          pcall(function() ql = ent.quality.name end)
          list[#list + 1] = {name = ent.name, count = c, x = ent.position.x, y = ent.position.y, box = box, quality = ql}
        end
      end
    end
  end
  table.sort(list, function(a, b) return a.count > b.count end)
  while #list > 1000 do table.remove(list) end
  return {count = sum, chests = n, list = list}
end

function M.scan_start(pi, name, quality, opts)
  local d = C.D()
  d.find_job = d.find_job or {}
  local queue = {}
  for _, s in pairs(game.surfaces) do
    if C.RP(s) and s.planet then queue[#queue + 1] = s.planet.prototype.name end
  end
  table.sort(queue)
  d.find_job[pi] = {name = name, quality = quality or "normal", queue = queue, total = #queue, done = {}, mach = {},
    opts = opts or {chests = true}, finished = (#queue == 0)}
end

function M.scan_cancel(pi)
  local d = C.D()
  if d.find_job then d.find_job[pi] = nil end
end

function M.scan_job(pi)
  local d = C.D()
  return d.find_job and d.find_job[pi] or nil
end

-- один шаг: по одной планете для каждого идущего поиска; возвращает игроков, чьё окно надо обновить
function M.scan_step()
  local changed = {}
  local jobs = C.D().find_job
  if not jobs or not next(jobs) then return changed end
  for pi, job in pairs(jobs) do
    if not job.finished then
      local key = table.remove(job.queue, 1)
      if key then
        local pl = game.planets[key]
        local s = pl and pl.surface
        if s and s.valid then
          if job.opts.chests then job.done[key] = scan_surface(s, job.name, job.quality) end
          if job.opts.machines then job.mach[key] = scan_machines(s, job.name, job.quality) end
        end
        changed[#changed + 1] = pi
      end
      if #job.queue == 0 then job.finished = true end
    end
  end
  return changed
end

return M
