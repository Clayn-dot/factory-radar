-- Factory Radar: кто что построил, считаем по стоящим постройкам (у каждой есть last_user).
-- Нужно для «за всё время»: у счётчика смены времени построек нет.
-- Запускается сам один раз (через минуту после старта) и по просьбе админа, маленькими шагами,
-- чтобы не вешать игру. Счётчик планеты заменяется результатом, а не дополняется — иначе постройки
-- с момента установки мода посчитались бы дважды.
local C = require("scripts.core")
local ST = require("scripts.stats")
local M = {}

local BUDGET = 1500      -- построек за шаг (шаг раз в 2 тика)
local EMPTY = 5          -- пустой чанк тоже чего-то стоит

local function S()
  local d = C.D()
  d.census = d.census or {state = "idle"}
  return d.census
end

-- что видит админ: idle | run, планета в работе, сколько осталось, тик окончания
function M.status()
  local c = S()
  return c.state, c.cur and c.cur.key or nil, c.queue and #c.queue or 0, c.finished
end

function M.start()
  local c = S()
  if c.state == "run" then return false end
  c.state, c.queue, c.cur, c.done = "run", {}, nil, true
  for _, s in pairs(game.surfaces) do
    if s.valid and C.RP(s) then c.queue[#c.queue + 1] = s.planet.prototype.name end
  end
  table.sort(c.queue)
  return true
end

local function finish(c)
  c.state, c.queue, c.cur, c.finished = "idle", nil, nil, game.tick
  -- звания за планеты выдаём тихо, иначе десяток сообщений разом
  for _, p in pairs(game.players) do C.check_titles(p, true) end
  C.titles_changed()
  C.journal({"tr-msg.census-done"})
end

-- шаг: раз в 2 тика, без запущенного подсчёта ничего не делает
function M.step()
  local c = S()
  if c.state ~= "run" then
    if c.state == "idle" and not c.done and game.tick > 3600 then M.start() end    -- в первый раз стартует сам
    return
  end
  if not c.cur then
    local key = table.remove(c.queue, 1)
    if not key then finish(c) return end
    local pl = game.planets and game.planets[key]
    local s = pl and pl.surface
    if not (s and s.valid) then return end
    local chunks = {}
    for ch in s.get_chunks() do chunks[#chunks + 1] = ch.x; chunks[#chunks + 1] = ch.y end
    c.cur = {key = key, i = 1, chunks = chunks, counts = {}}
    return
  end
  local cur = c.cur
  local pl = game.planets and game.planets[cur.key]
  local s = pl and pl.surface
  if not (s and s.valid) then c.cur = nil return end
  local force = game.forces.player
  local skip = ST.NOT_BUILDINGS
  local budget = BUDGET
  local chunks = cur.chunks
  while budget > 0 and cur.i <= #chunks do
    local x, y = chunks[cur.i], chunks[cur.i + 1]
    cur.i = cur.i + 2
    local ok, list = pcall(s.find_entities_filtered, {area = {{x * 32, y * 32}, {x * 32 + 32, y * 32 + 32}}, force = force})
    budget = budget - EMPTY
    if ok then
      for _, e in ipairs(list) do
        budget = budget - 1
        if e.valid and not skip[e.type] then
          local u = e.last_user
          if u and u.valid then cur.counts[u.name] = (cur.counts[u.name] or 0) + 1 end
        end
      end
    end
  end
  if cur.i > #chunks then
    C.D().pbuilt[cur.key] = cur.counts
    c.cur = nil
  end
end

return M
