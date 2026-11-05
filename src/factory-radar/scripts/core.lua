-- Factory Radar: общее состояние, помощники, звания, командные достижения, журнал
local C = {}

---------------------------------------------------------------- настройки
-- серверные переключатели лежат в сейве, админы меняют их в окне (вкладка «Настройки»)
-- редкие числа — стартовые настройки (главное меню → Настройки → Моды)
C.CFG = {
  -- функции
  {key = "tr-titles", group = "features", default = true},
  {key = "tr-chat-titles", group = "features", default = true},
  {key = "tr-death-tags", group = "features", default = true},
  {key = "tr-afk", group = "features", default = true},
  {key = "tr-zap", group = "features", default = true},
  -- что считаем
  {key = "tr-track-robots", group = "tracking", default = true},
  {key = "tr-track-robot-mined", group = "tracking", default = true},
  {key = "tr-track-defense", group = "tracking", default = true},
  {key = "tr-track-ff", group = "tracking", default = true},
  {key = "tr-track-vehicles", group = "tracking", default = true},
}
C.CFG_DEFAULT = {}
for _, c in ipairs(C.CFG) do C.CFG_DEFAULT[c.key] = c.default end

-- личные настройки игрока
C.PCFG = {
  {key = "button", default = true},
  {key = "tag-color", default = true},
  {key = "greet", default = true},
  {key = "intro", default = true},
  {key = "know", default = true},
  {key = "autorefresh", default = 15},
  {key = "open-tab", default = "last"},
  {key = "msg-titles", default = true, group = "msg"},
  {key = "msg-team", default = true, group = "msg"},
  {key = "msg-planets", default = true, group = "msg"},
  {key = "msg-science", default = true, group = "msg"},
  {key = "msg-deaths", default = true, group = "msg"},
  {key = "msg-shift", default = true, group = "msg"},
}
C.PCFG_DEFAULT = {}
for _, c in ipairs(C.PCFG) do C.PCFG_DEFAULT[c.key] = c.default end

-- старые названия переключателей чата, теперь решает аудитория сообщения
C.FEATURE_MSG = {["tr-shift-summary"] = {"shift"}, ["tr-planet-report"] = {"report"},
  ["tr-first-landing"] = {"first-landing"}, ["tr-planet-mastered"] = {"mastered"},
  ["tr-science-milestones"] = {"science-first", "science-milestone"}, ["tr-team"] = {"team"}, ["tr-deaths"] = {"death"}}

-- числа, которые админ ставит в игре; пока не менял — значение по умолчанию
C.NUM_DEFAULT = {["tr-s-zap-cooldown"] = 3, ["tr-s-roulette-cooldown"] = 0, ["tr-s-roulette-fail"] = 5}      -- 0 = у викторины нет отдыха, ждёт только идущую
C.NUM_RANGE = {["tr-s-zap-cooldown"] = {1, 60, "sec"}, ["tr-s-roulette-cooldown"] = {0, 240, "min"}, ["tr-s-roulette-fail"] = {1, 60, "min"}}

function C.S(name)
  local nd = C.NUM_DEFAULT[name]
  if nd ~= nil then
    local cfg = storage.tr and storage.tr.cfg
    return cfg and cfg.num and cfg.num[name] or nd
  end
  local fm = C.FEATURE_MSG[name]
  if fm then
    for _, kind in ipairs(fm) do if C.aud(kind) ~= "none" then return true end end
    return false
  end
  local def = C.CFG_DEFAULT[name]
  if def ~= nil then
    local cfg = storage.tr and storage.tr.cfg
    local v = cfg and cfg[name]
    if v == nil then return def end
    return v
  end
  return settings.startup[name].value
end
-- обычная длина смены в тиках (цикл UPS Guard, если он есть, иначе наша настройка)
function C.shift_ticks()
  local d = storage.tr
  if d and d.ups_period then return d.ups_period * 3600 end
  return math.max(3600, math.floor(settings.startup["tr-s-shift-hours"].value * 216000))
end

function C.set(name, value) C.D().cfg[name] = value end

-- «1 Oleg · 2 sleekhead» — одинаково у всех (отсортированные имена онлайн), и сами имена
function C.online_numbered()
  local names = {}
  for _, pl in pairs(game.connected_players) do names[#names + 1] = pl.name end
  table.sort(names)
  local parts = {}
  for i, n in ipairs(names) do parts[#parts + 1] = i .. " " .. n end
  return table.concat(parts, " · "), names
end

function C.P(p, key)
  local t = C.D().pcfg[p.index]
  local v = t and t[key]
  if v == nil then
    if string.sub(key, 1, 4) == "tab-" then return true end
    return C.PCFG_DEFAULT[key]
  end
  return v
end
function C.pset(p, key, value)
  local all = C.D().pcfg
  all[p.index] = all[p.index] or {}
  all[p.index][key] = value
end

---------------------------------------------------------------- сообщения в чат: кто получает и в каких словах
-- aud: all (все), self (только тот, о ком), none (только журнал)
C.MSGS = {
  {kind = "title", cat = "titles", params = {"player", "title", "reason"}, self = true},
  {kind = "team", cat = "team", params = {"text"}},
  {kind = "first-landing", cat = "planets", params = {"player", "planet", "gps"}, self = true},
  {kind = "mastered", cat = "planets", params = {"planet", "science", "builder", "done", "total"}},
  {kind = "science-first", cat = "science", params = {"icon", "place"}},
  {kind = "science-milestone", cat = "science", params = {"count", "icon", "place", "time"}},
  {kind = "death", cat = "deaths", params = {"player", "joke", "killer", "count", "gps"}, self = true},
  {kind = "mvp", cat = "shift", params = {"minutes"}},
  {kind = "ach", cat = "titles", params = {"player", "achievement", "why"}, self = true, aud = "self"},
  {kind = "zap", cat = "deaths", params = {"from", "to", "percent"}, self = true},
  {kind = "platform-lost", cat = "planets", params = {"platform", "where"}},
  {kind = "shift", cat = "shift"},
  {kind = "report", cat = "shift"},
}
C.MSG_BY = {}
for _, m in ipairs(C.MSGS) do C.MSG_BY[m.kind] = m end

function C.msgcfg(kind)
  local all = C.D().cfg
  all.msg = all.msg or {}
  all.msg[kind] = all.msg[kind] or {}
  return all.msg[kind]
end
function C.aud(kind)
  local m = storage.tr and storage.tr.cfg and storage.tr.cfg.msg and storage.tr.cfg.msg[kind]
  return (m and m.aud) or (C.MSG_BY[kind] and C.MSG_BY[kind].aud) or "all"
end

-- «{игрок} получил {звание}» + параметры → локализованная строка
function C.render(kind, default, params)
  local m = storage.tr and storage.tr.cfg and storage.tr.cfg.msg and storage.tr.cfg.msg[kind]
  local tpl = m and m.tpl
  if not tpl or tpl == "" or not params then return default end
  local out, i = {""}, 1
  while true do
    local s, e, name = string.find(tpl, "{([%w_%-]+)}", i)
    if not s then
      if i <= #tpl then out[#out + 1] = string.sub(tpl, i) end
      break
    end
    if s > i then out[#out + 1] = string.sub(tpl, i, s - 1) end
    local v = params[name]
    if v == nil then v = "{" .. name .. "}" end
    out[#out + 1] = v
    i = e + 1
    if #out >= 18 then out = {"", out} end
  end
  return out
end

-- отправка в чат по настройкам админа; возвращает готовый текст
function C.send(kind, default, params, color, subject, journal_text)
  local def = C.MSG_BY[kind]
  local text = C.render(kind, default, params)
  local aud = C.aud(kind)
  if aud == "all" then
    C.broadcast(text, color, def and def.cat)
  elseif aud == "self" and subject and subject.valid and subject.connected
      and (not def or C.P(subject, "msg-" .. def.cat)) then
    subject.print(text, {color = color})
  end
  if journal_text ~= false then C.journal(journal_text or text) end
  return text
end

-- планеты, которые админ исключил из статистики
function C.ignored(key) local i = storage.tr and storage.tr.cfg and storage.tr.cfg.ignore return i and i[key] or false end

-- каждый обработчик в обёртке: ошибка не должна останавливать игру у всех
function C.safe(fn)
  return function(...)
    local ok, err = pcall(fn, ...)
    if not ok then log("Factory Radar error: " .. tostring(err)) end
  end
end

---------------------------------------------------------------- хранилище
C.COUNTERS = {"kills", "built", "craft", "walk", "ride", "deaths", "mined", "lost", "ff",
  "belts", "rails", "poles", "turrets", "defense", "nests"}

function C.blank()
  local t = {}
  for _, k in pairs(C.COUNTERS) do t[k] = 0 end
  return t
end

-- хранилище мода; полная проверка таблиц один раз (и после сброса),
-- потому что C.D() зовётся на каждую смерть врага и другие горячие события
local D_KEYS
local D_VER = 4     -- поднять при изменении списка таблиц ниже
function C.D()
  local d = storage.tr
  if d and d._ready == D_VER then return d end
  storage.tr = storage.tr or {}
  d = storage.tr
  for _, k in pairs(D_KEYS or {"total", "shift", "first", "visited", "titles", "killers", "recent", "last_pos", "journal",
                      "planets", "pbuilt", "plost", "shift_plost", "team", "team_seen", "streak", "records",
                      "ptime", "mvp", "gui", "afk", "afk_fx", "research", "combat", "tags", "death_kinds",
                      "afk_time", "cfg", "pcfg", "decon", "pkills", "ach", "pstat", "pbest", "greeted", "zap",
                      "pwalk", "pdeaths", "ppipe", "pcraft", "pmine_tree", "pmine_rock", "pturrets", "psolar", "pbelts", "pacc", "pdrill", "pfact"}) do
    d[k] = d[k] or {}
  end
  d._ready = D_VER
  return d
end

-- счётчики по игроку и планете (прошёл, умер, скрафтил...): d[tbl][player][planet]
function C.pp_add(tbl, name, surface, n)
  if not C.RP(surface) then return end
  local t = C.D()[tbl]
  t[name] = t[name] or {}
  local key = surface.planet.prototype.name
  t[name][key] = (t[name][key] or 0) + n
end

function C.rec(tbl, name)
  local r = tbl[name]
  if not r then r = C.blank(); tbl[name] = r end
  for _, k in pairs(C.COUNTERS) do r[k] = r[k] or 0 end
  return r
end

function C.add(name, key, n)
  local d = C.D()
  local a, b = C.rec(d.total, name), C.rec(d.shift, name)
  a[key] = a[key] + n
  b[key] = b[key] + n
end

-- сообщения с жирным основным текстом в чате; журнал показывает копию («ключ-j») обычного размера
local J_ALT = {["tr-msg.ach"] = true, ["tr-msg.first-landing"] = true, ["tr-msg.mastered"] = true,
  ["tr-msg.mastered-short"] = true, ["tr-msg.platform-lost"] = true, ["tr-msg.power-low"] = true,
  ["tr-msg.power-none"] = true, ["tr-msg.science-first"] = true, ["tr-msg.science-milestone"] = true,
  ["tr-msg.shift-mvp"] = true, ["tr-msg.shift-mvp-tie"] = true, ["tr-msg.team"] = true, ["tr-msg.title"] = true}
-- текст записи журнала как он показывается: копия обычного размера для сообщений, жирных в чате
-- (работает и для старых записей)
function C.journal_view(text)
  if type(text) == "table" and J_ALT[text[1]] then
    local alt = {text[1] .. "-j"}
    for i = 2, #text do alt[i] = text[i] end
    return alt
  end
  return text
end
function C.journal(text)
  local j = C.D().journal
  j[#j + 1] = {tick = game.tick, text = text}
  while #j > C.S("tr-s-journal") do table.remove(j, 1) end
end

-- всем: чат + журнал
-- чат всем, кто не отключил эту категорию в личных настройках
function C.broadcast(msg, color, cat)
  for _, p in pairs(game.connected_players) do
    if not cat or C.P(p, "msg-" .. cat) then p.print(msg, {color = color}) end
  end
end

function C.announce(msg, color, journal_text, cat)
  C.broadcast(msg, color, cat)
  C.journal(journal_text or msg)
end

---------------------------------------------------------------- форматирование (локализованное)
function C.n(n)
  n = math.floor(n or 0)
  if n >= 1000000 then return {"tr.num-m", string.format("%.1f", n / 1000000)} end
  if n >= 10000 then return {"tr.num-k", string.format("%.1f", n / 1000)} end
  return tostring(n)
end

function C.km(tiles)
  tiles = tiles or 0
  if tiles < 1000 then return {"tr.dist-m", tostring(math.floor(tiles))} end
  local km = tiles / 1000
  return {"tr.dist-km", string.format(km >= 100 and "%.0f" or "%.1f", km)}
end

function C.time(ticks)
  local m = math.floor((ticks or 0) / 3600)
  if m < 60 then return {"tr.time-m", m} end
  local h = math.floor(m / 60)
  if h < 48 then return {"tr.time-hm", h, m % 60} end
  return {"tr.time-dh", math.floor(h / 24), h % 24}
end

-- игровое время как момент: «14:32» в первый день, «3 д 14:32» со второго (сутки по 24 ч).
-- LocalisedString: не склеивать через `..`
function C.clock(tick)
  local m = math.floor(tick / 3600)
  local h = math.floor(m / 60)
  local hhmm = string.format("%02d:%02d", h % 24, m % 60)
  if h < 24 then return hhmm end
  return {"tr.clock-days", math.floor(h / 24), hhmm}
end

function C.gps(pos, surface)
  return "[gps=" .. math.floor(pos.x) .. "," .. math.floor(pos.y) .. "," .. surface.name .. "]"
end

-- настоящая видимая планета (моды могут создавать скрытые)
function C.RP(surface)
  return surface and surface.valid and surface.planet and not surface.planet.prototype.hidden
    and not C.ignored(surface.planet.prototype.name) and true or false
end

function C.planet_ls(key)
  local pl = prototypes.space_location and prototypes.space_location[key]
  return {"", "[img=space-location/" .. key .. "] ", pl and pl.localised_name or key}
end

-- Имена платформ игроки пишут с иконками ([item=..], [planet=..]). В чате такие теги показываются
-- словами в скобках, поэтому переводим их в [img=..]; тег, для которого нет картинки, убираем
local TAG_SPRITE = {item = "item", entity = "entity", planet = "space-location", ["space-location"] = "space-location",
  ["virtual-signal"] = "virtual-signal", fluid = "fluid", recipe = "recipe", technology = "technology", tech = "technology",
  quality = "quality"}
function C.chat_rich(s)
  if type(s) ~= "string" then return s end
  return (s:gsub("%[([%w%-]+)=([^%],]+)[^%]]*%]", function(tag, name)
    local prefix = TAG_SPRITE[tag]
    if not prefix then return nil end
    local path = prefix .. "/" .. name
    if helpers.is_valid_sprite_path(path) then return "[img=" .. path .. "]" end
    return ""
  end))
end

function C.place(surface)
  if surface.platform then
    return {"", "[img=item/space-platform-starter-pack] «", C.chat_rich(surface.platform.name), "»"}
  end
  if surface.planet then return C.planet_ls(surface.planet.prototype.name) end
  return surface.name
end

-- склейка локализованных строк через разделитель (вложенно, из-за лимита в 20 параметров)
function C.join(list, sep)
  local out = {""}
  for i, v in ipairs(list) do
    if i > 1 then out[#out + 1] = sep or ", " end
    out[#out + 1] = v
    if #out >= 18 then out = {"", out} end
  end
  return out
end

function C.leader(tbl, key)
  local best, v = nil, 0
  for name, r in pairs(tbl) do
    if (r[key] or 0) > v then best, v = name, r[key] end
  end
  return best, v
end

function C.sorted_names(tbl, key)
  local names = {}
  for name in pairs(tbl) do names[#names + 1] = name end
  table.sort(names, function(a, b) return (tbl[a][key] or 0) > (tbl[b][key] or 0) end)
  return names
end

-- яд, огонь и кислота — это эффекты (облако, лужа, горение), а не удар оружия: «эффект: Яд», а не «урон: Яд»
local EFFECT_DAMAGE = {poison = true, fire = true, acid = true}
function C.damage_ls(dtype)
  return {EFFECT_DAMAGE[dtype] and "tr-gui.weapon-effect" or "tr-gui.weapon-damage", {"damage-type-name." .. dtype}}
end

-- в чате [item=...] уже показывает имя, поэтому только иконка
function C.weapon_chat(key)
  if string.sub(key, 1, 7) == "damage:" then return C.damage_ls(string.sub(key, 8)) end
  if key == "character" or key == "unknown" then return {"tr-gui.weapon-" .. key} end
  if prototypes.item[key] then return "[item=" .. key .. "]" end
  if prototypes.entity[key] then return "[entity=" .. key .. "]" end
  return key
end

-- ключ оружия (предмет / сущность / damage:<тип>) как локализованная строка с иконкой
function C.weapon_ls(key)
  if string.sub(key, 1, 7) == "damage:" then
    return C.damage_ls(string.sub(key, 8))
  end
  if key == "character" or key == "unknown" then return {"tr-gui.weapon-" .. key} end
  local it = prototypes.item[key]
  if it then return {"", "[item=" .. key .. "] ", it.localised_name} end
  local en = prototypes.entity[key]
  if en then return {"", "[entity=" .. key .. "] ", en.localised_name} end
  return key
end
function C.weapon_icon(key)
  if prototypes.item[key] then return "[item=" .. key .. "]" end
  if prototypes.entity[key] then return "[entity=" .. key .. "]" end
  return ""
end

---------------------------------------------------------------- планетные помощники для званий
function C.PL(key)
  local d = C.D()
  d.planets[key] = d.planets[key] or {}
  return d.planets[key]
end

function C.planets_in_game()
  local n = 0
  for name, pl in pairs(game.planets) do if not pl.prototype.hidden and not C.ignored(name) then n = n + 1 end end
  return n
end

function C.count_mastered()
  local done, total = 0, 0
  for _, s in pairs(game.surfaces) do
    if C.RP(s) then
      total = total + 1
      if C.PL(s.planet.prototype.name).mastered then done = done + 1 end
    end
  end
  return done, total
end

function C.planets_visited(name)
  local v = C.D().visited[name]
  return v and table_size(v) or 0
end

function C.best_planet_time(name)
  local t = C.D().ptime[name]
  local best, key = 0, nil
  if t then for k, v in pairs(t) do if v > best then best, key = v, k end end end
  return best, key
end

---------------------------------------------------------------- звания
C.TITLES = {
  {id = "exterminator", key = "kills", n = 100},
  {id = "hive-terror", key = "kills", n = 1000},
  {id = "walking-genocide", key = "kills", n = 5000},
  {id = "food-chain-end", key = "kills", n = 20000},
  {id = "foreman", key = "built", n = 10000},
  {id = "architect", key = "built", n = 100000},
  {id = "factory-wont-build-itself", key = "built", n = 500000},
  {id = "hand-assembler", key = "craft", n = 10000},
  {id = "human-factory", key = "craft", n = 100000},
  {id = "marathoner", key = "walk", n = 100000},
  {id = "forrest-gump", key = "walk", n = 500000},
  {id = "trucker", key = "ride", n = 500000},
  {id = "legend-slayer", key = "kills", n = 100000},
  {id = "legend-builder", key = "built", n = 2000000},
  {id = "legend-crafter", key = "craft", n = 1000000},
  {id = "legend-runner", key = "walk", n = 5000000},
  {id = "legend-regular", key = "online", n = 500},
  {id = "legend-colonizer", key = "colonizer", n = 10},
  {id = "legend-scientist", key = "infinite", n = 100},
  {id = "legend-mvp", key = "mvp_wins", n = 10},
  {id = "legend-shifts", key = "shifts", n = 100},
  {id = "legend-thunder", key = "zaps", n = 200},
  {id = "roulette-loser", key = "roulette_lost", n = 1},
  {id = "roulette-regular", key = "roulette_lost", n = 3},
  {id = "interplanetary-pilot", key = "ride", n = 2000000},
  {id = "immortal-not", key = "deaths", n = 10},
  {id = "professional-corpse", key = "deaths", n = 50},
  {id = "respawn-regular", key = "deaths", n = 150},
  {id = "tourist", key = "planets", n = 5},
  {id = "star-wanderer", key = "planets", n = 10},
  {id = "chief-slacker", key = "mined", n = 1000},
  {id = "demolition-crew", key = "mined", n = 10000},
  {id = "breaking-not-building", key = "mined", n = 50000},
  {id = "butterfingers", key = "ff", n = 10},
  {id = "saboteur", key = "ff", n = 100},
  {id = "keeper-of-ruins", key = "lost", n = 500},
  {id = "building-for-biters", key = "lost", n = 5000},
  {id = "pathfinder", key = "first", n = 3},
  {id = "columbus", key = "first", n = 8},
  {id = "colonizer", key = "colonizer", n = 3},
  {id = "terraformer", key = "colonizer", n = 6},
  {id = "local", key = "hours", n = 10},
  {id = "resident", key = "hours", n = 50},
  {id = "not-a-scratch", key = "streak", n = 500},
  {id = "infinite-scholar", key = "infinite", n = 25},
  -- заводская жизнь и мемы
  {id = "factory-must-grow", key = "built", n = 50000},
  {id = "spaghetti-chef", key = "belts", n = 2000},
  {id = "main-bus", key = "belts", n = 20000},
  {id = "choo-choo", key = "rails", n = 2000},
  {id = "rail-world", key = "rails", n = 20000},
  {id = "electrician", key = "poles", n = 1000},
  {id = "turret-creep", key = "turrets", n = 100},
  {id = "turret-baron", key = "defense", n = 10000},
  {id = "nest-cleaner", key = "nests", n = 100},
  {id = "pyromaniac", key = "pyro", n = 1000},
  {id = "trains-real-enemy", key = "death_train", n = 3},
  {id = "self-taught-sapper", key = "death_self", n = 3},
  {id = "pedestrian", key = "death_vehicle", n = 3},
  {id = "biter-snack", key = "death_creature", n = 10},
  {id = "veteran", key = "online", n = 100},
  {id = "touch-grass", key = "online", n = 500},
  {id = "tea-break", key = "afk", n = 5},
  -- именные
  {id = "pentapod-hunter", key = "pentapod", n = 1000},
  {id = "italian", key = "belts", n = 10000},
  {id = "shy", key = "novote_best", n = 10},
  {id = "unrecognized-genius", key = "genius_missed", n = 1},
  {id = "loser", key = "death_leader", n = 3},
  {id = "burden", key = "afk_end", n = 10},
  {id = "darwin-award", key = "death_self", n = 10},
  {id = "negotiations-over", key = "best_nests", n = 10},
  {id = "heisenberg", key = "nutrients_max", n = 3000},
  -- очень сложные, с цветным названием
  {id = "belt-emperor", key = "belts", n = 100000},
  {id = "grid-lord", key = "poles", n = 20000},
  {id = "rail-baron", key = "rails", n = 100000},
  {id = "iron-bastion", key = "defense", n = 100000},
  {id = "fire-sovereign", key = "pyro", n = 20000},
  {id = "demolition-titan", key = "mined", n = 250000},
  {id = "server-legend", key = "online", n = 2000},
  {id = "untouchable", key = "streak", n = 5000},
  {id = "nest-breaker", key = "nests", n = 1000},
  {id = "endless-mind", key = "infinite", n = 500},
  {id = "eternal-wanderer", key = "walk", n = 20000000},
  {id = "galaxy-master", key = "planets", n = 20},
  {id = "living-rod", key = "zapped", n = 300},
  {id = "colony-emperor", key = "colonizer", n = 25},
  -- MVP
  {id = "mvp-star", key = "mvp_wins", n = 1},
  {id = "mvp-pillar", key = "mvp_wins", n = 3},
  {id = "mvp-boss", key = "mvp_wins", n = 5},
  {id = "mvp-eternal", key = "mvp_wins", n = 25},
}
C.TITLE_UNIT = {walk = "km", ride = "km", hours = "h", online = "h", afk = "h", best_walk = "km", trait_lava = "h", trait_peace = "h", trait_uranium = "h"}
C.TITLE_HIDDEN_PROGRESS = {roulette_lost = true, deaths = true, lost = true, ff = true, death_train = true, death_self = true,
  death_vehicle = true, death_creature = true, afk = true, death_leader = true, afk_end = true, novote_best = true,
  genius_missed = true}

-- единица измерения звания (km, h или nil); ключи планет вида ptime:vulcanus
function C.unit(key)
  local base = string.match(key, "^([%w_]+):") or key
  if base == "ptime" then return "h" end
  if base == "pwalk" then return "km" end
  return C.TITLE_UNIT[base]
end

-- доп. статистика игрока (для достижений): полёты, победы MVP, смены, молнии...
function C.pstat(name, key) local t = C.D().pstat[name]; return t and t[key] or 0 end
function C.pstat_add(name, key, n)
  local d = C.D()
  d.pstat[name] = d.pstat[name] or {}
  d.pstat[name][key] = (d.pstat[name][key] or 0) + (n or 1)
end

local PLAYER_PLANET = {pwalk = true, pdeaths = true, ppipe = true, pcraft = true, pmine_tree = true, pmine_rock = true, pturrets = true,
  psolar = true, pbelts = true, pacc = true, pdrill = true, pfact = true}
-- дополнительная статистика игрока в pstat
local PSTAT = {space = true, mvp_wins = true, shifts = true, zaps = true, zapped = true, roulette_lost = true, pentapod = true,
  novote_best = true, death_leader = true, afk_end = true, nutrients_max = true, genius_missed = true}
function C.title_value(name, key)
  local d = C.D()
  local r = C.rec(d.total, name)
  local base, planet = string.match(key, "^([%w_]+):(.+)$")
  if base == "ptime" then return ((d.ptime[name] or {})[planet] or 0) / 216000 end
  if base == "pbuilt" then return ((d.pbuilt[planet] or {})[name] or 0) end
  if base == "pkills" then return ((d.pkills[name] or {})[planet] or 0) end
  if PLAYER_PLANET[base] then return ((d[base] or {})[name] or {})[planet] or 0 end
  if string.sub(key, 1, 6) == "trait_" then return C.trait_sum(name, string.sub(key, 7)) end
  if string.sub(key, 1, 5) == "best_" then return ((d.pbest[name] or {})[string.sub(key, 6)] or 0) end
  if PSTAT[key] then return C.pstat(name, key) end
  if key == "planets" then return C.planets_visited(name) end
  if key == "first" then
    local n = 0
    for _, v in pairs(d.first) do if v.who == name then n = n + 1 end end
    return n
  end
  if key == "colonizer" then
    local n = 0
    for _, st in pairs(d.planets) do if st.mastered and st.by == name then n = n + 1 end end
    return n
  end
  if key == "hours" then return C.best_planet_time(name) / 216000 end
  if key == "streak" then return (d.records.best_streak or {})[name] or 0 end
  if key == "infinite" then return (d.research.levels_by and d.research.levels_by[name]) or 0 end
  if key == "online" then
    local p = game.get_player(name)
    return p and p.online_time / 216000 or 0
  end
  if key == "afk" then return (d.afk_time[name] or 0) / 216000 end
  if key == "pyro" then
    local n = 0
    for w, c in pairs((d.combat.pweap or {})[name] or {}) do if string.find(w, "flamethrower", 1, true) then n = n + c end end
    return n
  end
  if string.sub(key, 1, 6) == "death_" then return (d.death_kinds[name] or {})[string.sub(key, 7)] or 0 end
  return r[key] or 0
end

function C.title_name(id)
  C.titles()
  local t = C.TITLE_BY_ID[id]
  if t and t.name then return t.name end
  if t and t.lname then return t.lname end
  if t and t.custom then return id end
  local cfg = storage.tr and storage.tr.cfg
  for _, c in ipairs(cfg and cfg.titles_custom or {}) do if c.id == id then return c.name end end
  return {"tr-title." .. id}
end

-- имя для тега в чате: без иконки планеты
function C.title_tagname(id)
  C.titles()
  local t = C.TITLE_BY_ID[id]
  if t and t.tagname then return t.tagname end
  return C.title_name(id)
end

-- 1234567 → «1 234 567» (точно, для круглых порогов)
function C.big(n)
  local s = tostring(math.floor(n))
  local out = s:reverse():gsub("(%d%d%d)", "%1 "):reverse()
  return (out:gsub("^ ", ""))
end

-- «убийств: 100» и т.п.
function C.fmt_amount(key, n)
  local u = C.unit(key)
  if u == "km" then return {"tr.dist-km", C.big(n / 1000)} end
  if u == "h" then return {"tr.hours", (n == math.floor(n)) and tostring(n) or string.format("%.1f", n)} end
  return C.big(n)
end
function C.title_by_id(id)
  for _, t in ipairs(C.titles()) do if t.id == id then return t end end
  return nil
end

function C.title_reason(t)
  local base, planet = string.match(t.key, "^([%w_]+):(.+)$")
  if base then return {"tr-why." .. base, C.fmt_amount(t.key, t.n), C.planet_ls(planet)} end
  return {"tr-why." .. t.key, C.fmt_amount(t.key, t.n)}
end

---------------------------------------------------------------- цвета званий
local COLOR_OF = {
  kills = "1,0.45,0.35", streak = "1,0.45,0.35", nests = "1,0.45,0.35", defense = "1,0.55,0.4", pkills = "1,0.45,0.35",
  built = "1,0.72,0.3", belts = "1,0.72,0.3", rails = "1,0.72,0.3", poles = "1,0.8,0.35", turrets = "1,0.6,0.3",
  pbuilt = "1,0.72,0.3", craft = "1,0.9,0.4", walk = "0.45,0.85,1", ride = "0.45,0.85,1",
  planets = "0.78,0.62,1", first = "0.78,0.62,1", colonizer = "0.78,0.62,1", hours = "0.78,0.62,1", ptime = "0.78,0.62,1",
  deaths = "0.72,0.72,0.72", mined = "0.85,0.62,0.45", ff = "1,0.55,0.75", lost = "0.85,0.5,0.45",
  infinite = "0.45,0.72,1", online = "0.6,1,0.6", afk = "0.6,1,0.6", pyro = "1,0.55,0.15",
}
-- у каждого звания свой цвет: цвет темы (вид планеты или группа статистики), чуть сдвинутый
-- по хэшу id, чтобы два звания одной темы отличались
local function str_hash(str)
  local n = 5381
  for i = 1, #str do n = (n * 33 + string.byte(str, i)) % 2147483647 end
  return n
end
local function rgb_to_hsv(r, g, b)
  local mx, mn = math.max(r, g, b), math.min(r, g, b)
  local d = mx - mn
  local h = 0
  if d > 0 then
    if mx == r then h = ((g - b) / d) % 6 elseif mx == g then h = (b - r) / d + 2 else h = (r - g) / d + 4 end
    h = h * 60
  end
  return h, mx > 0 and d / mx or 0, mx
end
local function hsv_to_rgb(h, s, v)
  local c = v * s
  local x = c * (1 - math.abs((h / 60) % 2 - 1))
  local m = v - c
  local r, g, b = 0, 0, 0
  if h < 60 then r, g, b = c, x, 0 elseif h < 120 then r, g, b = x, c, 0 elseif h < 180 then r, g, b = 0, c, x
  elseif h < 240 then r, g, b = 0, x, c elseif h < 300 then r, g, b = x, 0, c else r, g, b = c, 0, x end
  return string.format("%.3f,%.3f,%.3f", r + m, g + m, b + m)
end
local KIND_HUE = {lava = 12, water = 205, oil = 35, ammonia = 175, trees = 118, rocks = 28, uranium = 88, peace = 150,
  veteran = 270, builder = 48, defender = 2}
function C.title_color(id)
  if C.LEGEND[id] then return "1,0.92,0.55" end
  C.titles()
  local t = C.TITLE_BY_ID[id]
  local h = str_hash(id)
  local hue, sat, val
  if t and t.planet then
    local kind = string.match(id, "^pl%-(%a+)%-")
    hue, sat, val = KIND_HUE[kind] or (h % 360), 0.55, 1
  else
    local rgb = "0.95,0.95,0.6"
    if t and not t.custom then
      local base = string.match(t.key, "^([%w_]+):") or t.key
      if string.sub(base, 1, 6) == "death_" then base = "deaths" end
      rgb = COLOR_OF[base] or "1,0.85,0.3"
    end
    local r, g, b = string.match(rgb, "([%d%.]+),([%d%.]+),([%d%.]+)")
    hue, sat, val = rgb_to_hsv(tonumber(r), tonumber(g), tonumber(b))
    sat = math.max(sat, 0.3)
  end
  hue = (hue + (h % 41) - 20) % 360
  val = math.max(0.75, val - (math.floor(h / 41) % 3) * 0.06)
  return hsv_to_rgb(hue, sat, val)
end
-- название в своём цвете (кавычки берутся из текста локали вокруг)
function C.title_rich(id)
  C.titles()
  if C.LEGEND[id] then
    local t = C.TITLE_BY_ID[id]
    if not (t and t.name) then return {"", {"tr-title." .. id .. "-c"}} end    -- название от админа красится одним цветом
  end
  return {"", "[color=" .. C.title_color(id) .. "]", C.title_name(id), "[/color]"}
end
-- как в чате: без иконки планеты в названии
function C.title_rich_tag(id)
  C.titles()
  if C.LEGEND[id] then return C.title_rich(id) end
  return {"", "[color=" .. C.title_color(id) .. "]", C.title_tagname(id), "[/color]"}
end

---------------------------------------------------------------- звания планет (для каждой посещённой)
-- у планет базы свои названия; у остальных (модовых) — вида «Планета: Ветеран»
C.PLANET_SPECIAL = {nauvis = true, vulcanus = true, fulgora = true, gleba = true, aquilo = true}
-- виды званий планет; needs = что должно быть на планете (враги, лава, вода, peace = врагов нет совсем),
-- pool = сколько мемных имён у вида (только у видов, где пул на каждой планете).
-- Модовая планета получает три звания: из «присутствия», из «работы» (оба по имени планеты, чтобы
-- планеты различались) и одно по тому, что на планете есть (THEME_ORDER). У планет базы свои
-- звания (pl-<вид>-<планета> в локали)
C.PLANET_TITLE_KINDS = {
  -- присутствие
  {kind = "veteran", key = "ptime", n = 24},                                   -- часов на планете
  {kind = "wanderer", key = "pwalk", n = 30000},                               -- 30 км пешком
  {kind = "mortal", key = "pdeaths", n = 8},                                   -- умер 8 раз
  -- работа
  {kind = "builder", key = "pbuilt", n = 8000},
  {kind = "handy", key = "pcraft", n = 1000},                                  -- ручной крафт
  {kind = "warden", key = "pturrets", n = 100},                                -- поставлено турелей
  -- что есть на планете (задача по теме планеты)
  {kind = "defender", key = "pkills", n = 2000, needs = "enemies"},
  {kind = "lava", key = "pdeaths", n = 5, needs = "lava"},                     -- погибнуть на планете с лавой
  {kind = "acid", key = "pbelts", n = 2000, needs = "acid"},                   -- ленты рядом с кислотой
  {kind = "oil", key = "ppipe", n = 1000, needs = "oil"},                      -- трубы, насосы, баки, скважины на нефтяной планете
  {kind = "brine", key = "ppipe", n = 1500, needs = "brine"},                  -- то же на солёной, но больше
  {kind = "ammonia", key = "pfact", n = 150, needs = "ammonia"},               -- заводы и печи на аммиачной планете
  {kind = "goo", key = "pfact", n = 300, needs = "goo"},                       -- заводы и печи на планете со слизью
  {kind = "uranium", key = "pdrill", n = 80, needs = "uranium"},               -- буры на планете с ураном
  {kind = "water", key = "pwalk", n = 40000, needs = "water"},                 -- 40 км пешком по планете с водой
  {kind = "dark", key = "pacc", n = 150, needs = "dark"},                      -- накопители там, где мало солнца
  {kind = "bright", key = "psolar", n = 300, needs = "bright"},                -- солнечные панели там, где сильное солнце
  {kind = "heavy", key = "pwalk", n = 20000, needs = "heavy"},                 -- 20 км при тяжёлой гравитации
  {kind = "light", key = "ptime", n = 20, needs = "light"},                    -- часов при лёгкой гравитации
  {kind = "vacuum", key = "pbuilt", n = 4000, needs = "vacuum"},               -- построено без атмосферы
  {kind = "trees", key = "pmine_tree", n = 1000, needs = "trees"},             -- срублено деревьев
  {kind = "rocks", key = "pdrill", n = 150, needs = "rocks"},                  -- буры на каменистой планете
  {kind = "peace", key = "ptime", n = 24, needs = "peace"},
}
-- что на планете есть на самом деле: базы врагов, лава, жидкость (вода, океаны). Находится один раз по настройкам
-- поверхности. Враги считаются и тогда, когда там кого-то убили. Хранится с версией, заново не считается
local FLAGS_V = 4
local function planet_flags(s, key)
  local d = C.D()
  d.pflags = d.pflags or {}
  local f = d.pflags[key]
  if not f or f.v ~= FLAGS_V then
    f = {v = FLAGS_V}
    pcall(function()
      local mgs = s.map_gen_settings
      -- контролы автогенерации: базы врагов, деревья/растения, камни, уран
      for name, c in pairs(mgs.autoplace_controls or {}) do
        if (c.size or 0) > 0 then
          if name:find("enemy", 1, true) or name:find("nest", 1, true) then f.nests = true end
          if name:find("tree", 1, true) or name:find("plants", 1, true) then f.trees = true end
          if name:find("rock", 1, true) then f.rocks = true end
          if name:find("uranium", 1, true) then f.uranium = true end
        end
      end
      -- что размещено на планете: деревья, камни, уран
      local ent = mgs.autoplace_settings and mgs.autoplace_settings.entity and mgs.autoplace_settings.entity.settings or {}
      for name in pairs(ent) do
        local proto = prototypes.entity[name]
        local t = proto and proto.type
        if t == "tree" then f.trees = true
        elseif t == "simple-entity" and name:find("rock", 1, true) then f.rocks = true
        elseif t == "resource" and name:find("uranium", 1, true) then f.uranium = true end
      end
      -- жидкости по составу
      local tiles = mgs.autoplace_settings and mgs.autoplace_settings.tile and mgs.autoplace_settings.tile.settings or {}
      for name in pairs(tiles) do
        local proto = prototypes.tile[name]
        local fluid = proto and proto.fluid
        local fname = fluid and fluid.name or ""
        if name:find("lava", 1, true) or fname:find("lava", 1, true) then f.lava = true
        elseif fname:find("oil", 1, true) or fname:find("crude", 1, true) then f.oil = true
        elseif fname:find("ammon", 1, true) then f.ammonia = true
        elseif fname:find("acid", 1, true) or fname:find("sulfur", 1, true) then f.acid = true
        elseif fname:find("brine", 1, true) or fname:find("salt", 1, true) or fname:find("lithium", 1, true) then f.brine = true
        elseif fname:find("slime", 1, true) or fname:find("sludge", 1, true) or fname:find("jelly", 1, true)
          or fname:find("mud", 1, true) or fname:find("tar", 1, true) then f.goo = true
        elseif fname ~= "" then f.water = true end
      end
    end)
    -- свойства поверхности (сравниваем со стандартной планетой: гравитация 10, давление 1000, солнце 100)
    pcall(function()
      local g, pr, sun = s.get_property("gravity"), s.get_property("pressure"), s.get_property("solar-power")
      if g then
        if g >= 15 then f.heavy = true elseif g <= 6 then f.light = true end
      end
      if pr and pr <= 100 then f.vacuum = true end
      if sun then
        if sun <= 40 then f.dark = true elseif sun >= 200 then f.bright = true end
      end
    end)
    d.pflags[key] = f
  end
  local pl = d.combat and d.combat.planets and d.combat.planets[key]
  local enemies = f.nests or (pl and pl.kills or 0) > 0
  return {nests = f.nests, lava = f.lava, water = f.water, oil = f.oil, ammonia = f.ammonia, trees = f.trees, rocks = f.rocks,
    uranium = f.uranium, acid = f.acid, brine = f.brine, goo = f.goo, heavy = f.heavy, light = f.light, vacuum = f.vacuum,
    dark = f.dark, bright = f.bright, enemies = enemies, peace = not enemies}
end

function C.planet_traits(key)
  local pl = game.planets[key]
  local s = pl and pl.surface
  if not (s and s.valid) then return nil end
  return planet_flags(s, key)
end

-- сумма игрока по всем планетам с признаком: часы (лава, мир, уран...), постройки (вода, нефть), убийства (гнёзда)
local HOURS_TRAITS = {lava = true, peace = true, uranium = true, ammonia = true, trees = true, rocks = true}
local BUILD_TRAITS = {water = true, oil = true}
function C.trait_sum(name, trait)
  local d = C.D()
  local total = 0
  if HOURS_TRAITS[trait] then
    for planet, ticks in pairs(d.ptime[name] or {}) do
      local f = C.planet_traits(planet)
      if f and f[trait] then total = total + ticks / 216000 end
    end
  elseif BUILD_TRAITS[trait] then
    for planet, by in pairs(d.pbuilt) do
      local f = by[name] and C.planet_traits(planet)
      if f and f[trait] then total = total + by[name] end
    end
  elseif trait == "nests" then
    for planet, n in pairs(d.pkills[name] or {}) do
      local f = C.planet_traits(planet)
      if f and f.nests then total = total + n end
    end
  end
  return total
end

-- звания остальных планет: «прилагательное существительное» (ADJ x NOUN имён на вид). Для каждой планеты игры
-- своя комбинация в каждом виде, считается по отсортированному списку ВСЕХ планет (видели или нет),
-- поэтому имя не повторяется и не меняется при открытии новой планеты
local ADJ, NOUN = 12, 8
local function hash_name(str)
  local n = 5381
  for i = 1, #str do n = (n * 33 + string.byte(str, i)) % 2147483647 end
  return n
end
local function assign_names(all_names)
  local out = {}
  for _, k in ipairs(C.PLANET_TITLE_KINDS) do
    local used, map = {}, {}
    for _, name in ipairs(all_names) do
      local u = hash_name(k.kind .. "/" .. name) % (ADJ * NOUN)
      local tries = 0
      while used[u] and tries < ADJ * NOUN do u = (u + 1) % (ADJ * NOUN); tries = tries + 1 end
      used[u] = true
      map[name] = u
    end
    out[k.kind] = map
  end
  return out
end

-- звания планеты — три. У планет базы свои (ветеран, строитель, защитник). Модовая получает вид
-- «присутствия», вид «работы» (по имени) и один тематический: первый из списка, что на планете есть
-- (враги, лава, кислота, нефть, соль, аммиак, слизь, уран, вода, нет солнца, сильное солнце, нет воздуха,
-- тяжёлая и лёгкая гравитация, деревья, камни), иначе мирный. Имена как выше, без повторов
local THEME_ORDER = {"defender", "lava", "acid", "oil", "brine", "ammonia", "goo", "uranium", "water", "dark", "bright",
  "vacuum", "heavy", "light", "trees", "rocks", "peace"}
local PRESENCE, WORK = {"veteran", "wanderer", "mortal"}, {"builder", "handy", "warden"}
local function planet_titles(list)
  local keys, surf = {}, {}
  for _, s in pairs(game.surfaces) do
    if C.RP(s) then keys[#keys + 1] = s.planet.prototype.name; surf[s.planet.prototype.name] = s end
  end
  table.sort(keys)
  local all = {}
  for name, pl in pairs(game.planets) do
    if not pl.prototype.hidden then all[#all + 1] = name end
  end
  table.sort(all)
  local names = assign_names(all)
  local by_kind = {}
  for _, k in ipairs(C.PLANET_TITLE_KINDS) do by_kind[k.kind] = k end
  local taken = {}
  for _, p in ipairs(keys) do
    local fl = planet_flags(surf[p], p)
    local kinds
    if C.PLANET_SPECIAL[p] then
      kinds = {"veteran", "builder", "defender"}
    else
      local theme = "peace"
      for _, name in ipairs(THEME_ORDER) do
        local k = by_kind[name]
        if k and (not k.needs or fl[k.needs]) then theme = name break end
      end
      kinds = {PRESENCE[hash_name(p .. "/presence") % #PRESENCE + 1], WORK[hash_name(p .. "/work") % #WORK + 1], theme}
    end
    for _, kind in ipairs(kinds) do
      local k = by_kind[kind]
      local lname, tagname
      if C.PLANET_SPECIAL[p] then
        lname = {"tr-title.pl-" .. kind .. "-" .. p}
        tagname = lname
      else
        local u = names[kind][p] or 0
        taken[kind] = taken[kind] or {}
        local tries = 0
        while taken[kind][u] and tries < ADJ * NOUN do u = (u + 1) % (ADJ * NOUN); tries = tries + 1 end   -- без повторов имён
        taken[kind][u] = true
        tagname = {"", {"tr-title.modadj-" .. (u % ADJ + 1)}, " ", {"tr-title.modnoun-" .. kind .. "-" .. (math.floor(u / ADJ) % NOUN + 1)}}
        lname = {"", "[img=space-location/" .. p .. "] ", tagname}     -- в теге чата tagname, без иконки
      end
      list[#list + 1] = {id = "pl-" .. kind .. "-" .. p, key = k.key .. ":" .. p, n = k.n, planet = p, lname = lname, tagname = tagname}
    end
  end
  return #keys
end
C.BASE_TITLES = C.TITLES
C.TITLE_KEYS = {}
do
  local seen = {}
  for _, t in ipairs(C.BASE_TITLES) do if not seen[t.key] then seen[t.key] = true; C.TITLE_KEYS[#C.TITLE_KEYS + 1] = t.key end end
end

-- используемый список: встроенные звания с правками админа плюс его собственные
local cache_ver, cache_list = nil, nil
local planets_at, planets_n = -1e9, 0
function C.titles()
  local cfg = storage.tr and storage.tr.cfg or {}
  -- планеты пересчитываем раз в 10 секунд
  if game.tick < planets_at or game.tick - planets_at >= 600 then
    planets_at, planets_n = game.tick, 0
    for _, s in pairs(game.surfaces) do if C.RP(s) then planets_n = planets_n + 1 end end
  end
  local ver = (storage.tr and storage.tr.titles_ver or 0) .. "/" .. planets_n
  if cache_list and cache_ver == ver then return cache_list end
  local over = cfg.title_over or {}
  local list = {}
  for _, t in ipairs(C.BASE_TITLES) do
    local o = over[t.id] or {}
    if not o.off then
      list[#list + 1] = {id = t.id, key = t.key, n = o.n or t.n, name = (o.name and o.name ~= "") and o.name or nil}
    end
  end
  for _, t in ipairs(cfg.titles_custom or {}) do
    if not t.off then list[#list + 1] = {id = t.id, key = t.key, n = t.n, name = t.name, custom = true} end
  end
  if not cfg.planet_titles_off then planet_titles(list) end
  cache_ver, cache_list = ver, list
  C.TITLE_BY_ID = {}
  for _, t in ipairs(list) do C.TITLE_BY_ID[t.id] = t end
  return list
end
function C.titles_changed()
  local d = C.D()
  d.titles_ver = (d.titles_ver or 0) + 1
end
-- легендарные звания (очень сложные): каждый слог своим цветом (палитра — значение: огонь, золото,
-- лёд, радуга); цветной текст — ключ локали «<id>-c»
C.LEGEND = {
  ["legend-slayer"] = "fire", ["legend-builder"] = "gold", ["legend-crafter"] = "gold", ["legend-runner"] = "ice",
  ["legend-regular"] = "rainbow", ["legend-colonizer"] = "rainbow", ["legend-scientist"] = "ice",
  ["legend-mvp"] = "rainbow", ["legend-shifts"] = "gold", ["legend-thunder"] = "fire",
  -- серьёзные (сложные) звания: градиент по буквам
  ["food-chain-end"] = "fire", ["factory-wont-build-itself"] = "gold", ["architect"] = "royal", ["forrest-gump"] = "aurora",
  ["interplanetary-pilot"] = "ice", ["star-wanderer"] = "sunset", ["columbus"] = "sunset", ["terraformer"] = "emerald",
  ["main-bus"] = "toxic", ["rail-world"] = "steel", ["turret-baron"] = "fire", ["breaking-not-building"] = "sunset",
  ["respawn-regular"] = "violet", ["mvp-eternal"] = "rainbow", ["mvp-boss"] = "gold", ["heisenberg"] = "toxic",
  ["italian"] = "italy", ["negotiations-over"] = "fire", ["darwin-award"] = "violet", ["pentapod-hunter"] = "emerald",
  -- ещё сложные: у каждого своя покраска (градиент, через букву, по словам, только заглавные, волна)
  ["belt-emperor"] = "alt", ["grid-lord"] = "alt", ["rail-baron"] = "duo", ["iron-bastion"] = "accent", ["fire-sovereign"] = "grad",
  ["demolition-titan"] = "duo", ["server-legend"] = "wave", ["untouchable"] = "grad", ["nest-breaker"] = "grad", ["endless-mind"] = "grad",
  ["eternal-wanderer"] = "grad", ["galaxy-master"] = "grad", ["living-rod"] = "alt", ["colony-emperor"] = "accent",
}
C.TITLE_BY_ID = {}
C.on_title = nil   -- ставит модуль тегов чата
C.hooks = {}        -- ставит модуль окна: popup(player, kind), popup_close(kind)

-- silent: выдать без сообщения в чат (после пересчёта, когда сразу много)
function C.check_titles(player, silent)
  if not (player and player.valid) or not C.S("tr-titles") then return end
  local d = C.D()
  local got = d.titles[player.name] or {}
  d.titles[player.name] = got
  for _, t in ipairs(C.titles()) do
    if not got[t.id] and C.title_value(player.name, t.key) >= t.n then
      got[t.id] = game.tick
      if not silent then
        local name, reason = C.title_rich(t.id), C.title_reason(t)
        C.send("title", {"tr-msg.title", player.name, name, reason}, {player = player.name, title = name, reason = reason},
          {0.85, 0.95, 1}, player)
      end
      if C.on_title then C.on_title(player) end
    end
  end
  C.check_ach(player)
end

---------------------------------------------------------------- личные достижения (одноразовые)
-- достижения. Часть идёт ступенями (одно семейство, пороги выше): у ступени палочки после названия
-- («Bloody Harvest |||»), тексты каждого id в локали (имя, «<id>-tip» и «<id>-did»)
C.ACH = {
  -- ступени
  {id = "first-blood", key = "kills", n = 1}, {id = "kills-2", key = "kills", n = 1000}, {id = "kills-3", key = "kills", n = 10000},
  {id = "kills-4", key = "kills", n = 100000}, {id = "kills-5", key = "kills", n = 1000000},
  {id = "builder-1", key = "built", n = 1000}, {id = "builder-2", key = "built", n = 10000}, {id = "builder-3", key = "built", n = 100000},
  {id = "builder-4", key = "built", n = 1000000}, {id = "builder-5", key = "built", n = 10000000},
  {id = "walker-1", key = "walk", n = 100000}, {id = "walker-2", key = "walk", n = 500000}, {id = "walker-3", key = "walk", n = 1000000},
  {id = "walker-4", key = "walk", n = 5000000},
  {id = "shifts-10", key = "shifts", n = 10}, {id = "shifts-50", key = "shifts", n = 50}, {id = "shifts-3", key = "shifts", n = 100},
  {id = "shifts-4", key = "shifts", n = 500},
  {id = "mvp-1", key = "mvp_wins", n = 1}, {id = "mvp-3", key = "mvp_wins", n = 3}, {id = "mvp-4", key = "mvp_wins", n = 10},
  {id = "mvp-5", key = "mvp_wins", n = 25},
  {id = "planet-hopper", key = "planets", n = 3}, {id = "planets-2", key = "planets", n = 6}, {id = "planets-3", key = "planets", n = 10},
  {id = "planets-4", key = "planets", n = 20},
  {id = "infinite-1", key = "infinite", n = 1}, {id = "infinite-2", key = "infinite", n = 10}, {id = "infinite-3", key = "infinite", n = 50},
  {id = "infinite-4", key = "infinite", n = 200},
  {id = "zap-1", key = "zaps", n = 1}, {id = "zap-2", key = "zaps", n = 10}, {id = "zap-3", key = "zaps", n = 50},
  {id = "zap-4", key = "zaps", n = 200},
  {id = "zapped-10", key = "zapped", n = 10}, {id = "zapped-2", key = "zapped", n = 50}, {id = "zapped-3", key = "zapped", n = 200},
  -- одиночные
  {id = "first-nest", key = "nests", n = 1},
  {id = "first-death", key = "deaths", n = 1},
  {id = "first-landing", key = "first", n = 1},
  {id = "spaceman", key = "space", n = 1},
  {id = "shift-builder", key = "best_built", n = 3000},
  {id = "shift-runner", key = "best_walk", n = 50000},
  {id = "shift-slayer", key = "best_kills", n = 1500},
  {id = "belts-500", key = "belts", n = 2000},
  {id = "train-victim", key = "death_train", n = 1},
  {id = "lava-walker", key = "trait_lava", n = 24},
  {id = "island-builder", key = "trait_water", n = 5000},
  {id = "peace-quiet", key = "trait_peace", n = 30},
  {id = "nest-neighbour", key = "trait_nests", n = 1000},
  {id = "oil-tycoon", key = "trait_oil", n = 3000},
  {id = "democracy", key = "trait_uranium", n = 24},
}
function C.check_ach(player)
  if not (player and player.valid) then return end
  local d = C.D()
  local got = d.ach[player.name] or {}
  d.ach[player.name] = got
  -- ступени одной статистики, взятые разом, выдаются все, объявляется только высшая
  local new, by_key = {}, {}
  for _, a in ipairs(C.ACH) do
    if not got[a.id] and C.title_value(player.name, a.key) >= a.n then
      got[a.id] = game.tick
      new[#new + 1] = a
      by_key[a.key] = a
    end
  end
  for _, a in ipairs(new) do
    if by_key[a.key] == a then
      local why = {"tr-ach." .. a.id .. "-did"}      -- «за что» в прошедшем времени для чата
      C.send("ach", {"tr-msg.ach", player.name, {"tr-ach." .. a.id}, why},
        {player = player.name, achievement = {"tr-ach." .. a.id}, why = why}, {1, 0.95, 0.75}, player,
        C.aud("ach") == "self" and false or nil)
    end
  end
end

function C.titles_of(name)
  local got = C.D().titles[name] or {}
  local list = {}
  for id, tick in pairs(got) do list[#list + 1] = {id = id, tick = tick} end
  table.sort(list, function(a, b) return a.tick > b.tick end)
  return list
end

function C.best_title(name)
  local l = C.titles_of(name)
  return l[1] and l[1].id or nil
end

-- звание, которое игрок выбрал для ника (если выбрал и оно у него есть), иначе самое новое
function C.shown_title(name)
  local pl = game.get_player(name)
  local st = pl and C.D().tags[pl.index]
  local got = C.D().titles[name] or {}
  if st and st.id and st.id ~= "auto" and got[st.id] then return st.id end
  return C.best_title(name)
end

function C.next_titles(name, count)
  local got = C.D().titles[name] or {}
  local list = {}
  for _, t in ipairs(C.titles()) do
    if not got[t.id] and not C.TITLE_HIDDEN_PROGRESS[t.key] then
      local v = C.title_value(name, t.key)
      list[#list + 1] = {t = t, v = v, ratio = math.min(1, v / t.n)}
    end
  end
  table.sort(list, function(a, b) return a.ratio > b.ratio end)
  local out = {}
  for i = 1, math.min(count, #list) do out[#out + 1] = list[i] end
  return out
end

function C.title_left(n)
  local left = n.t.n - n.v
  local u = C.unit(n.t.key)
  if u == "km" then return C.km(left) end
  if u == "h" then return {"tr.hours", string.format("%.1f", left)} end
  return C.n(math.ceil(left))
end

---------------------------------------------------------------- командные достижения
C.TEAM = {
  {key = "lost", n = 1000}, {key = "lost", n = 10000}, {key = "lost", n = 100000},
  {key = "mined", n = 10000}, {key = "mined", n = 100000},
  {key = "kills", n = 10000}, {key = "kills", n = 100000}, {key = "kills", n = 1000000},
  {key = "built", n = 100000}, {key = "built", n = 1000000},
  {key = "deaths", n = 100},
  {key = "ff", n = 100},
  {key = "mastered", n = 3}, {key = "mastered", n = 5}, {key = "mastered", n = 10}, {key = "mastered", n = 20},
  {key = "research", n = 25}, {key = "research", n = 50}, {key = "research", n = 75}, {key = "research", n = 100},
  {key = "infinite", n = 100}, {key = "infinite", n = 1000},
  -- наука в минуту у всей команды
  {key = "spm", n = 100}, {key = "spm", n = 1000}, {key = "spm", n = 10000}, {key = "spm", n = 100000}, {key = "spm", n = 1000000},
}

function C.team_text(a) return {"tr-team." .. a.key .. "-" .. a.n} end

function C.team_check(key, value, silent)
  local d = C.D()
  for _, a in ipairs(C.TEAM) do
    local id = a.key .. a.n
    if a.key == key and value >= a.n and not d.team_seen[id] then
      d.team_seen[id] = game.tick
      if not silent and C.S("tr-team") then
        C.send("team", {"tr-msg.team", C.team_text(a)}, {text = C.team_text(a)}, {1, 0.95, 0.75})
      end
    end
  end
end

function C.team_add(key, n)
  local t = C.D().team
  t[key] = (t[key] or 0) + n
  C.team_check(key, t[key], false)
end

return C
