-- Factory Radar: викторина (ядерная рулетка). Кто-то запускает; все онлайн получают маленькое окно (и строку в чат):
-- согласиться или отказаться (работает и /tr-in). Меньше двух игроков — ничего не происходит. Иначе чат называет
-- участников, считает 5..1, объявляет проигравшего, и на его персонажа падает ракета; с этого момента он не может
-- двигаться и садиться в машину, пока ракета его не убьёт.
-- Ракета настоящая (картинка, звук, радиус ~35 клеток), но копия, бьющая только по силе запустившего
-- (см. data-final-fixes.lua), так что враги и природа целы. Плюс перед ударом всё, что принадлежит игрокам и НЕ
-- принадлежит жертве (чужие постройки, другие персонажи), на несколько секунд неразрушаемо — теряются только
-- выбранный и его постройки.
local C = require("scripts.core")
local M = {}

local RADIUS = 50      -- радиус защиты вокруг удара (взрыв доходит примерно на 35 клеток)

local function R()
  local d = C.D()
  d.roul = d.roul or {state = "idle", players = {}}
  return d.roul
end

local function eligible(p)
  return p and p.valid and p.connected and p.character and p.character.valid
    and p.character.surface.valid and not p.character.surface.platform
end

local function cooldown_left()
  local r = R()
  local rest = C.S("tr-s-roulette-cooldown") * 3600      -- 0 (по умолчанию): отдыха нет, новую блокирует только идущая
  local left = 0
  if rest > 0 and r.last_end then left = math.max(0, r.last_end + rest - game.tick) end
  -- викторина, в которой никто не согласился (запустивший один, остальные отказались), отдыхает несколько минут:
  -- иначе окно появлялось бы у остальных снова и снова
  if r.fail_until then left = math.max(left, r.fail_until - game.tick) end
  return left
end

local function say(msg) C.announce(msg, {1, 0.75, 0.45}, msg) end

-- мм:сс игрового времени (отдых бывает долгим: 75:12)
function M.clock(ticks)
  local s = math.max(0, math.ceil(ticks / 60))
  return string.format("%d:%02d", math.floor(s / 60), s % 60)
end
-- ракета картинкой (ссылка на предмет показалась бы в чате именем в скобках)
local function icon()
  return helpers.is_valid_sprite_path("item/atomic-bomb") and "[img=item/atomic-bomb] " or ""
end

-- значок викторины в начале объявления
local function quiz_icon()
  for _, s in ipairs({"virtual-signal/signal-question-mark", "utility/questionmark"}) do
    if helpers.is_valid_sprite_path(s) then return "[img=" .. s .. "] " end
  end
  return ""
end

local function names(r)
  local out = {}
  for name in pairs(r.players) do out[#out + 1] = name end
  table.sort(out)
  return out
end

local function popup_close() if C.hooks.popup_close then C.hooks.popup_close("rou") end end

-- состояние для окна: idle | join | fall | impact | cooldown, сколько секунд (минут) осталось, игроки
function M.status()
  local r = R()
  if r.state == "join" then return "join", math.max(0, math.ceil((r.deadline - game.tick) / 60)), #names(r) end
  if r.state == "idle" then
    local cd = cooldown_left()
    if cd > 0 then return "cooldown", M.clock(cd) end
  end
  return r.state or "idle", 0
end

---------------------------------------------------------------- защита всего, что не принадлежит жертве
local function protect(surface, center, victim_name)
  local prot = {}
  local ok, list = pcall(function()
    return surface.find_entities_filtered{position = center, radius = RADIUS, force = game.forces.player}
  end)
  if not ok then return prot end
  for _, e in ipairs(list) do
    if e.valid then
      local mine = e.last_user and e.last_user.valid and e.last_user.name == victim_name
      local himself = e.type == "character" and e.player and e.player.name == victim_name
      if not mine and not himself then
        if pcall(function() e.destructible = false end) then prot[#prot + 1] = e end
      end
    end
  end
  return prot
end

local function restore(list)
  for _, e in ipairs(list or {}) do
    if e.valid then pcall(function() e.destructible = true end) end
  end
end

---------------------------------------------------------------- жертва не двигается, пока её не убьёт ракета
local function freeze(p)
  local r = R()
  r.frozen = p.name
  pcall(function()
    r.old_speed = p.character_running_speed_modifier
    p.character_running_speed_modifier = -1
    p.driving = false
  end)
end

-- камера остаётся там, где падает ракета (катсцена: без карты и осмотра), пока удар не кончится
local function lock_camera(p)
  local r = R()
  local ch = p.character
  if not (ch and ch.valid) then return end
  local pos = ch.position
  -- если смотрит в другое место (карта, удалённый просмотр другой планеты): каждый шаг пробуем отдельно, чтобы
  -- отказ игры не остановил следующий
  -- 1) удалённый просмотр на место падения (работает между планетами — это документированный
  --    параметр контроллера remote), 2) обратно в тело, 3) катсцена на этом месте
  if p.controller_type == defines.controllers.remote or p.surface ~= ch.surface then
    pcall(function()
      p.set_controller{type = defines.controllers.remote, surface = ch.surface, position = pos}
    end)
  end
  if p.controller_type ~= defines.controllers.character then
    pcall(function() p.set_controller{type = defines.controllers.character, character = ch} end)
  end
  local ok = pcall(function()
    p.set_controller{type = defines.controllers.cutscene, start_position = pos, start_zoom = 0.5,
      waypoints = {{position = pos, transition_time = 0, time_to_wait = 60 * 60, zoom = 0.5}}}
  end)
  if ok and p.controller_type == defines.controllers.cutscene then r.cam = p.name end
end

local function unlock_camera()
  local r = R()
  if not r.cam then return end
  local p = game.get_player(r.cam)
  r.cam = nil
  if p and p.valid and p.connected and p.controller_type == defines.controllers.cutscene then
    pcall(p.exit_cutscene)
    -- умершему в катсцене респавн сам не приходит: запускаем (обычные 10 секунд)
    pcall(function()
      if not (p.character and p.character.valid) and p.ticks_to_respawn == nil then p.ticks_to_respawn = 10 * 60 end
    end)
  end
end

local function unfreeze()
  local r = R()
  if not r.frozen then return end
  local p = game.get_player(r.frozen)
  if p and p.valid then
    pcall(function() p.character_running_speed_modifier = r.old_speed or 0 end)
  end
  r.frozen, r.old_speed = nil, nil
end

-- садиться в машину тоже нельзя
function M.on_driving(e)
  local r = R()
  if r.state ~= "impact" or not r.frozen then return end
  local p = game.get_player(e.player_index)
  if p and p.valid and p.name == r.frozen and p.driving then pcall(function() p.driving = false end) end
end

-- после загрузки или обновления: ничего не должно остаться неразрушаемым или замороженным из-за оборванного удара
function M.cleanup()
  local r = R()
  if r.prot then restore(r.prot); r.prot = nil end
  unfreeze()
  unlock_camera()
  if r.state == "fall" or r.state == "impact" or r.state == "settle" then
    r.state, r.last_end = "idle", game.tick     -- оборванный удар всё равно запускает отдых
  end
end

-- ничего ни с кем не случилось (выбранного нет, ракету не запустить): отдых всё равно начинается,
-- иначе викторину можно было бы запускать снова и снова
local function cancel(name)
  local r = R()
  r.state, r.last_end = "idle", game.tick
  say({"tr-roulette.cancel", name})
end

-- выбранный умер (от ракеты или за секунды до неё): запоминаем для итога
function M.on_died(e)
  local r = R()
  if r.state ~= "impact" then return end
  local p = game.get_player(e.player_index)
  if p and p.valid and p.name == r.victim then r.died, r.died_at = true, game.tick end
end

-- запуск ракеты в точку. С жертвой всё, что не её, защищено до finish()
function M.fire(surface, target, victim_name)
  local r = R()
  restore(r.prot)
  r.prot = victim_name and protect(surface, target, victim_name) or nil
  local ok = pcall(function()
    surface.create_entity{name = "tr-atomic-rocket", position = {x = target.x + 60, y = target.y - 150}, target = target,
      force = game.forces.player, speed = 0.3}
  end)
  if not ok then restore(r.prot); r.prot = nil end
  return ok
end

---------------------------------------------------------------- игра
function M.start(p)
  local function no(msg) p.print(msg, {color = {1, 0.8, 0.6}}) end
  if not C.S("tr-s-roulette") then no({"tr-roulette.off"}) return end
  local r = R()
  if r.state ~= "idle" then no({"tr-roulette.busy"}) return end
  local left = cooldown_left()
  if left > 0 then no({"tr-roulette.cooldown", M.clock(left)}) return end
  if not eligible(p) then no({"tr-roulette.no-body"}) return end
  local able = {}
  for _, pl in pairs(game.connected_players) do if eligible(pl) then able[#able + 1] = pl end end
  if #able < 2 then no({"tr-roulette.few"}) return end
  r.state, r.players, r.deadline = "join", {[p.name] = true}, game.tick + C.S("tr-s-roulette-join") * 60
  r.warned = {}
  local list = {}
  for _, pl in ipairs(able) do list[#list + 1] = pl.name end
  table.sort(list)
  say({"", quiz_icon(), {"tr-roulette.start", p.name, C.S("tr-s-roulette-join"), table.concat(list, ", ")}})
  -- маленькое окно с выбором для остальных
  if C.hooks.popup then for _, pl in ipairs(able) do if pl.index ~= p.index then C.hooks.popup(pl, "rou") end end end
end

function M.join(p)
  local function no(msg) p.print(msg, {color = {1, 0.8, 0.6}}) end
  local r = R()
  if r.state ~= "join" then no({"tr-roulette.not-open"}) return end
  if r.players[p.name] then no({"tr-roulette.already"}) return end
  if not eligible(p) then no({"tr-roulette.no-body"}) return end
  r.players[p.name] = true
  say({"tr-roulette.joined", p.name, #names(r)})
end

local function resolve()
  local r = R()
  popup_close()
  local list = {}
  for _, name in ipairs(names(r)) do
    local pl = game.get_player(name)
    if eligible(pl) then list[#list + 1] = name end
  end
  if #list < 2 then
    r.state = "idle"
    local mins = C.S("tr-s-roulette-fail")
    r.fail_until = game.tick + mins * 3600
    say({"tr-roulette.none", mins})
    return
  end
  r.victim = list[math.random(#list)]
  say({"tr-roulette.pool", table.concat(list, ", "), #list})
  r.state, r.fall_at, r.said = "fall", game.tick + 7 * 60, {}
end

local function launch()
  local r = R()
  local p = game.get_player(r.victim)
  if not eligible(p) then cancel(r.victim) return end
  local ch = p.character
  if not M.fire(ch.surface, ch.position, r.victim) then cancel(r.victim) return end
  freeze(p)
  lock_camera(p)
  say({"tr-roulette.lost", r.victim, icon()})
  r.state, r.kill_at, r.died = "impact", game.tick + 10 * 60, nil
end

local function finish()
  local r = R()
  local p = game.get_player(r.victim)
  -- работу делает взрыв; здесь только убеждаемся, что выбранного точно нет, и всё снова становится
  -- разрушаемым и подвижным
  unfreeze()
  local died = r.died
  -- в катсцене персонаж хранится как `cutscene_character`
  local ch = nil
  if p and p.valid then
    ch = p.character
    if not (ch and ch.valid) then pcall(function() ch = p.cutscene_character end) end
  end
  if ch and ch.valid then
    if pcall(function() ch.die(game.forces.player) end) then died = true end
  end
  -- чужие постройки защищены ещё несколько секунд: волны взрыва ещё идут
  unlock_camera()
  r.state, r.settle_at = "settle", game.tick + 6 * 60
  r.died = nil
  if died then
    -- звание («Победитель по жизни») — тому, кто правда погиб
    C.pstat_add(r.victim, "roulette_lost", 1)
    if p and p.valid then C.check_titles(p) end
    say({"tr-roulette.done", r.victim, icon(), C.S("tr-s-roulette-cooldown")})
  else
    say({"tr-roulette.escaped", r.victim, C.S("tr-s-roulette-cooldown")})
  end
end

-- раз в секунду
function M.tick()
  local r = R()
  if r.state == "join" then
    local rem = r.deadline - game.tick
    for _, mark in ipairs({30, 10}) do
      if rem <= mark * 60 and not r.warned[mark] then
        r.warned[mark] = true
        if rem > 0 then say({"tr-roulette.remind", mark, #names(r)}) end
      end
    end
    if rem <= 0 then resolve() end
  elseif r.state == "fall" then
    local rem = r.fall_at - game.tick
    for sec = 5, 1, -1 do
      if rem <= sec * 60 and not r.said[sec] and rem > 0 then
        r.said[sec] = true
        say({"tr-roulette.count", sec})
      end
    end
    if rem <= 0 then launch() end
  elseif r.state == "impact" then
    -- держим на месте (сиденье машины или смена скорости не должны спасти)
    local p = r.frozen and game.get_player(r.frozen)
    if p and p.valid then pcall(function() p.driving = false; p.character_running_speed_modifier = -1 end) end
    -- мёртв, когда его персонажа нет (в катсцене событие смерти может не прийти)
    if not r.died then
      local v = game.get_player(r.victim)
      if v and v.valid and v.connected then
        local ch = v.character
        if not (ch and ch.valid) then pcall(function() ch = v.cutscene_character end) end
        if not (ch and ch.valid) then r.died, r.died_at = true, game.tick end
      end
    end
    -- конец: в назначенное время или через 4 секунды после смерти (посмотрел на взрыв)
    if game.tick >= r.kill_at or (r.died and game.tick >= (r.died_at or 0) + 4 * 60) then finish() end
  elseif r.state == "settle" then
    if game.tick >= (r.settle_at or 0) then
      restore(r.prot)
      r.prot = nil
      r.state = "idle"
      r.last_end = game.tick      -- отдых идёт с момента, когда всё закончилось
    end
  end
end

return M
