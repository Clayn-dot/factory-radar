-- Factory Radar: электричество по планетам — выработка, потребление, аккумуляторы, перебои
-- в статистике сети input = ПОТРЕБИТЕЛИ, output = ИСТОЧНИКИ (наоборот, чем кажется)
-- сети ищем редко (поиск столбов дорогой), читаем часто — это дёшево
local C = require("scripts.core")
local M = {}

local HIST = 180                -- отсчёт раз в ~20 с → час истории
local LONG = 288                -- и средние по 5 минутам за сутки
local SAMPLE_GAP = 1200         -- тиков между двумя замерами планеты с сетью
local REDISCOVER = 60 * 3600    -- тиков между поисками сетей
local CHECK_TYPES = {"assembling-machine", "furnace", "lab", "mining-drill"}
local MIN_EVENT = 600           -- «тока нет» пишем, когда он длится 10 с (короче игнорим)
local MIN_EVENT_LOW = 3600      -- «не хватает» (машины работают не на полную мощность) — когда длится минуту
local MERGE_GAP = 10 * 3600     -- перебои одной планеты ближе этого — одна запись («6 раз за 40 мин»)
local CLOSE_AFTER = 2           -- проверок подряд без перебоя, чтобы его закрыть
local LOG_MAX = 20
local WARN_AFTER = 15             -- замеров подряд (~5 минут) с серьёзной причиной, чтобы это стало жёлтой записью журнала

local function E()
  local d = C.D()
  d.energy = d.energy or {}
  return d.energy
end
function M.planet(key)
  local e = E()
  e[key] = e[key] or {nets = {}, acc = {}, refs = {}, hist = {}, scanned = nil, last = nil}
  return e[key]
end

-- журнал перебоев: все планеты вместе, новые сверху, последние LOG_MAX, новой сменой не чистится
local function LOG()
  local d = C.D()
  d.energy_log = d.energy_log or {}
  return d.energy_log
end
function M.log() return LOG() end
-- level: "red" (перебой: тока нет или не хватает; у старых записей поля нет) или "warn" (жёлтое: на пределе, риск)
local function open_entry(key, level)
  for _, e in ipairs(LOG()) do
    if e.key == key and not e.done and (e.level or "red") == (level or "red") then return e end
  end
  return nil
end
-- сколько всего длился перебой (все прогоны), в тиках
function M.duration(e)
  return (e.total or 0) + ((not e.done) and math.max(0, (e.last or 0) - (e.run or e.start or 0)) or 0)
end

-- сеть рабочая? Перебой считается только на сети, где ток есть (или только что был):
--  * стоит источник (генератор, панель...; один аккумулятор не источник) и сеть хоть раз давала ток; или
--  * сеть давала ток за последние 10 минут (источник только что снесли — это блэкаут).
-- Форпост без питания, с одними аккумуляторами или со снесёнными давно источниками перебоем не считается:
-- его тока никто не ждёт
local RECENT = 10 * 3600

local function any_source(pe, id)
  for _, e in ipairs((pe.gens or {})[id] or {}) do if e.valid then return true end end
  return false
end

-- сеть хоть раз давала ток? «да» запоминается, «пока нет» спрашиваем снова через 10 с
local function ever_produced(pe, id)
  pe.ever = pe.ever or {}
  local v = pe.ever[id]
  if v == true then return true end
  if v and game.tick - v < 600 then return false end
  local pole = pe.nets[id]
  local ok = true
  if pole and pole.valid then
    local okc, has = pcall(function() return next(pole.electric_network_statistics.output_counts) ~= nil end)
    ok = (not okc) or has
  end
  pe.ever[id] = ok and true or game.tick
  return ok
end

local function alive(pe, id)
  local r = pe.recent and pe.recent[id]
  if r and game.tick - r < RECENT then return true end
  return any_source(pe, id) and ever_produced(pe, id)
end

-- «none» (тока нет), «low» (не хватает) или nil, и набор сетей с перебоем. На сеть опрашивается до REFS машин
-- (одна простаивающая перебой не покажет). Если большинства машин сети уже нет — скоро пересканируем
-- планету
local function shortage_kind(pe)
  local st = defines.entity_status
  local kind, ids = nil, nil
  local frac = 0
  for id, list in pairs(pe.refs) do
    if type(list) == "userdata" then list = {list} end      -- формат старой версии, до следующего скана
    if alive(pe, id) then
      local good, n_none, n_low = 0, 0, 0
      for _, m in ipairs(list) do
        if m.valid then
          good = good + 1
          local ok, status = pcall(function() return m.status end)
          if ok then
            if status == st.no_power then n_none = n_none + 1
            elseif status == st.low_power then n_low = n_low + 1 end
          end
        end
      end
      -- «тока нет» — когда без него хотя бы половина проверяемых машин; «не хватает» — когда не на полную мощность работает
      -- хотя бы четверть (одна переключённая или отрезанная машина перебоя не делает)
      local bad = n_none + n_low
      if good > 0 and bad / good > frac then frac = bad / good end
      if good > 0 and n_none * 2 >= good and n_none > 0 then
        kind = "none"; ids = ids or {}; ids[id] = true
      elseif good > 0 and bad >= 1 and bad * 4 >= good then
        if kind ~= "none" then kind = "low" end
        ids = ids or {}; ids[id] = true
      end
      if good * 2 < #list then pe.refs_bad = true end
    end
  end
  return kind, ids, frac
end

local SOURCE_TYPES = {"generator", "burner-generator", "solar-panel", "fusion-generator", "lightning-attractor",
  "electric-energy-interface"}
local REFS = 6          -- машин на сеть
local SOURCES = 4       -- запоминаемых источников на сеть

-- Поиск построек планеты. Первый раз — сразу весь (sync), повторные — по одному шагу за замер (раз в ~20 с), чтобы большая база
-- не давала провала в один кадр: поиск столбов, аккумуляторов, источников, машин, топливных построек. Данные меняются на новые, когда
-- все шаги прошли
local function scan(s, pe, sync)
  local job = pe.scan_job
  if not job then
    job = {stage = 1, nets = {}, acc = {}, gens = {}, refs = {}}
    pe.scan_job = job
  end
  local force = game.forces.player
  repeat
    local st = job.stage
    if st == 1 then
      for _, pole in pairs(s.find_entities_filtered{type = "electric-pole", force = force}) do
        local id = pole.electric_network_id
        if id and not job.nets[id] then job.nets[id] = pole end
      end
    elseif st == 2 then
      for _, a in pairs(s.find_entities_filtered{type = "accumulator", force = force, limit = 3000}) do job.acc[#job.acc + 1] = a end
    elseif st == 3 then
      -- источники каждой сети
      local okp, srcs = pcall(s.find_entities_filtered, {type = SOURCE_TYPES, force = force, limit = 5000})
      if okp then
        for _, e in pairs(srcs) do
          local ok, id = pcall(function() return e.electric_network_id end)
          if ok and id then
            local list = job.gens[id] or {}
            job.gens[id] = list
            if #list < SOURCES then list[#list + 1] = e end
          end
        end
      end
    elseif st == 4 then
      -- машины для опроса, равномерно по списку (он упорядочен по месту)
      local all = {}
      for _, m in pairs(s.find_entities_filtered{type = CHECK_TYPES, force = force, limit = 600}) do
        local ok, id = pcall(function() return m.electric_network_id end)
        if ok and id then all[id] = all[id] or {}; table.insert(all[id], m) end
      end
      for id, list in pairs(all) do
        local pick = {}
        local n = math.min(REFS, #list)
        for k = 1, n do pick[#pick + 1] = list[math.floor((k - 1) * #list / n) + 1] end
        job.refs[id] = pick
      end
    else
      -- реакторы и котлы: у кого кончилось топливо
      local burners = {}
      local okf, fl = pcall(s.find_entities_filtered, {type = {"reactor", "boiler", "fusion-reactor", "burner-generator"}, force = force, limit = 400})
      if not okf then okf, fl = pcall(s.find_entities_filtered, {type = {"reactor", "boiler", "burner-generator"}, force = force, limit = 400}) end
      if okf then for _, e in pairs(fl) do burners[#burners + 1] = e end end
      -- аккумуляторы в сети, где никто ничего не потребляет (или вне сети): им нечего питать. Это справка, не перебой
      local iso = 0
      local has_cons = {}
      for _, a in ipairs(job.acc) do
        local isolated = true
        local oka, aid = pcall(function() return a.electric_network_id end)
        if oka and aid then
          if has_cons[aid] == nil then
            has_cons[aid] = false
            local pole = job.nets[aid]
            if pole and pole.valid then
              local okc, has = pcall(function()
                for name in pairs(pole.electric_network_statistics.input_counts) do
                  local pr = prototypes.entity[name]
                  if not (pr and pr.type == "accumulator") then return true end
                end
                return false
              end)
              has_cons[aid] = okc and has or false
            end
          end
          if has_cons[aid] then isolated = false end
        end
        if isolated then iso = iso + 1 end
      end
      pe.nets, pe.refs, pe.acc, pe.gens, pe.burners, pe.acc_iso = job.nets, job.refs, job.acc, job.gens, burners, iso
      pe.ever, pe.recent, pe.net_sum = {}, {}, {}
      pe.refs_v = 2
      pe.scanned = game.tick
      pe.dirty, pe.refs_bad = nil, nil
      pe.scan_job = nil
      return
    end
    job.stage = st + 1
  until not sync
end

-- солнце «в космосе» там, где платформа сейчас: у локации своё значение (в процентах), в полёте — между значениями начала и конца
-- маршрута по пройденной части пути. nil, если узнать не удалось
local function plat_solar(pl)
  local function sip(name)
    local ok, v = pcall(function() return prototypes.space_location[name].solar_power_in_space end)
    return ok and type(v) == "number" and v or nil
  end
  local f = nil
  pcall(function()
    local conn = pl.space_connection
    if pl.space_location then
      f = sip(pl.space_location.name)
    elseif conn then
      local a, b = sip(conn.from.name), sip(conn.to.name)
      if a and b then f = a + (b - a) * math.max(0, math.min(1, pl.distance or 0)) end
    end
  end)
  return f and f / 100 or nil
end


-- солнце на поверхности: у каждой солнечной панели есть своё свойство поверхности («solar-power» по умолчанию: у планеты это
-- «солнце в атмосфере», у платформы — «солнце в космосе» там, где она сейчас летит), мощность делится на значение свойства по умолчанию.
-- Плюс общий множитель поверхности
local SPROP = {}
local function prop_default(name)
  local d = SPROP[name]
  if d == nil then
    d = false
    pcall(function()
      local v = prototypes.surface_property[name].default_value
      if type(v) == "number" and v > 0 then d = v end
    end)
    SPROP[name] = d
  end
  return d
end
local function solar_factor(s, prop)
  prop = prop or "solar-power"
  local f = 1
  pcall(function() f = (s.solar_power_multiplier or 1) end)
  pcall(function()
    local v = s.get_property(prop)
    local d = prop_default(prop)
    if type(v) == "number" and d then f = f * v / d end
  end)
  return f
end

local function sum(t) local n = 0; for _, v in pairs(t) do n = n + v end; return n end

-- «паспорт» типа постройки: сколько он даёт и тратит в самом лучшем случае, с учётом качества. Читается из прототипов один раз
-- и запоминается (это не состояние мира, при каждой загрузке считается заново одинаково у всех)
local PASS = {}
local function pass(name, quality)
  local q = quality or "normal"
  local k = name .. "|" .. q
  local p = PASS[k]
  if p == nil then
    p = false
    local pr = prototypes.entity[name]
    if pr then
      local okp, mp = pcall(function() return pr.get_max_energy_production(q) end)
      local okc, mc = pcall(function() return pr.get_max_energy_usage(q) end)
      p = {type = pr.type, maxp = (okp and type(mp) == "number") and mp * 60 or 0, maxc = (okc and type(mc) == "number") and mc * 60 or 0}
      if p.type == "solar-panel" then pcall(function() p.prop = pr.solar_panel_solar_coefficient_property.name end) end
      pcall(function()
        local dr = pr.electric_energy_source_prototype.drain
        if type(dr) == "number" then p.drain = dr * 60 end
      end)
    end
    PASS[k] = p
  end
  return p or nil
end

local QUALS = nil
local function quality_names()
  if not QUALS then
    QUALS = {}
    pcall(function()
      for qn, q in pairs(prototypes.quality) do
        local hidden = false
        pcall(function() hidden = q.hidden end)
        if not hidden then QUALS[#QUALS + 1] = qn end
      end
    end)
    table.sort(QUALS)
    if #QUALS == 0 then QUALS = {"normal"} end
  end
  return QUALS
end

-- сколько таких построек по качествам: {качество = n}, всего
local function count_q(s, name)
  local per, total = {}, 0
  for _, qn in ipairs(quality_names()) do
    local ok, n = pcall(s.count_entities_filtered, {name = name, force = game.forces.player, quality = qn})
    if ok and type(n) == "number" and n > 0 then per[qn] = n; total = total + n end
  end
  if total == 0 then
    local ok, n = pcall(s.count_entities_filtered, {name = name, force = game.forces.player})
    if ok and type(n) == "number" and n > 0 then per, total = {normal = n}, n end
  end
  return per, total
end

-- максимум источников этого имени по качествам; солнечные панели умножаются на множитель поверхности
local function capacity_of(per, name, s)
  local c = 0
  for qn, n in pairs(per) do
    local p = pass(name, qn)
    if p and p.maxp > 0 then
      local w = n * p.maxp
      if p.type == "solar-panel" then w = w * solar_factor(s, p.prop) end
      c = c + w
    end
  end
  return c
end

-- сколько энергии лежит в топливе всех сжигателей (реакторы, котлы): запас в инвентаре и остаток горящего. Работает с любым топливом, в том числе модовым
local function fuel_energy(list)
  local total = 0
  for _, e in ipairs(list or {}) do
    if e.valid then
      pcall(function()
        local inv = e.get_fuel_inventory()
        if inv then
          for _, c in ipairs(inv.get_contents()) do
            local pr = prototypes.item[c.name]
            if pr and pr.fuel_value then total = total + pr.fuel_value * c.count end
          end
        end
        local b = e.burner
        if b then total = total + (b.remaining_burning_fuel or 0) end
      end)
    end
  end
  return total
end

-- наклон ряда (единиц в секунду) по последним n замерам (линейная регрессия) и среднее; nil, если замеров мало
local function slope(hist, key, n)
  local m = math.min(#hist, n)
  if m < 6 then return nil end
  local t0 = hist[#hist - m + 1].tick
  local sx, sy, sxx, sxy = 0, 0, 0, 0
  for i = #hist - m + 1, #hist do
    local x = (hist[i].tick - t0) / 60
    local y = hist[i][key] or 0
    sx = sx + x; sy = sy + y; sxx = sxx + x * x; sxy = sxy + x * y
  end
  local den = m * sxx - sx * sx
  if den == 0 then return nil end
  return (m * sxy - sx * sy) / den, sy / m
end

-- что говорит длинный ряд: потребление растёт или падает (за 30 минут), когда оно упрётся в предел, не кончается ли топливо
-- (запас только убывает 10 минут подряд, без подвоза), как изменилось потребление за последние часы. add(line, score) — причина,
-- notes — справка без влияния на статус. cap_eff — предельная мощность источников (0 — не знаем)
function M.series(hist, long, cap_eff, add, notes)
  local n = #hist
  if n >= 60 then
    local sl, mean = slope(hist, "cons", 90)
    if sl and mean > 1e5 then
      local rel = sl * 3600 / mean
      local now = hist[n].cons
      if rel >= 0.15 then
        local eta = (cap_eff > now and sl > 0) and (cap_eff - now) / sl / 60 or nil
        if eta and eta < 180 then add({"tr-en.why-trend-cap", math.floor(rel * 100 + 0.5), math.max(1, math.floor(eta + 0.5))}, 1)
        else notes[#notes + 1] = {"tr-en.note-trend-up", math.floor(rel * 100 + 0.5)} end
      elseif rel <= -0.15 then
        notes[#notes + 1] = {"tr-en.note-trend-down", math.floor(-rel * 100 + 0.5)}
      end
    end
  end
  if long and #long >= 36 then
    local function avg(a, b) local t = 0; for i = a, b do t = t + long[i].cons end; return t / (b - a + 1) end
    local recent, older = avg(#long - 11, #long), avg(#long - 35, #long - 24)
    if older > 1e5 and math.abs(recent / older - 1) >= 0.3 then
      notes[#notes + 1] = {"tr-en.note-trend-long", math.floor((recent / older - 1) * 100 + 0.5)}
    end
  end
  if n >= 30 and (hist[n].fuel or 0) > 0 then
    local first = hist[n - 29]
    local f0, f1 = first.fuel or 0, hist[n].fuel
    local rises = false
    for i = n - 28, n do
      if (hist[i].fuel or 0) > (hist[i - 1].fuel or 0) * 1.01 + 1e3 then rises = true; break end
    end
    if not rises and f0 > f1 and hist[n].tick > first.tick then
      local rate = (f0 - f1) / ((hist[n].tick - first.tick) / 60)
      if rate > 1e4 then
        local eta = f1 / rate / 60
        if eta < 15 then add({"tr-en.why-fuel-low", math.max(1, math.floor(eta + 0.5))}, 1) end
      end
    end
  end
end

-- пятиминутные средние за сутки: потребление и заряд
local function push_long(pe, tick, prod, cons, stored)
  pe.long = pe.long or {}
  local a5 = pe.a5 or {n = 0, prod = 0, cons = 0, stored = 0}
  a5.n = a5.n + 1; a5.prod = a5.prod + prod; a5.cons = a5.cons + cons; a5.stored = a5.stored + stored
  if a5.n >= 15 then
    table.insert(pe.long, {tick = tick, prod = a5.prod / a5.n, cons = a5.cons / a5.n, stored = a5.stored / a5.n})
    while #pe.long > LONG do table.remove(pe.long, 1) end
    a5 = nil
  end
  pe.a5 = a5
end

-- замер планеты (зовётся из sample_due)
function M.sample(only)
  local st = defines.entity_status
  for _, s in pairs(only and {only} or game.surfaces) do
    if C.RP(s) then
      local key = s.planet.prototype.name
      local pe = M.planet(key)
      local stale = not pe.scanned or game.tick - pe.scanned > REDISCOVER
        or (pe.dirty and game.tick - pe.scanned > 5 * 3600)
        or (pe.refs_bad and game.tick - pe.scanned > 3 * 3600)
        or (next(pe.nets) and pe.refs_v ~= 2)
      if not stale then for _, pole in pairs(pe.nets) do if not pole.valid then stale = true break end end end
      if stale or pe.scan_job then scan(s, pe, not pe.scanned) end
      -- суммы (джоули с создания сети) по именам источников и потребителей
      local prod, cons = {}, {}
      pe.net_sum, pe.recent = pe.net_sum or {}, pe.recent or {}
      for id, pole in pairs(pe.nets) do
        if pole.valid then
          local fs = pole.electric_network_statistics
          local made = 0
          for name, j in pairs(fs.output_counts) do prod[name] = (prod[name] or 0) + j; made = made + j end
          for name, j in pairs(fs.input_counts) do cons[name] = (cons[name] or 0) + j end
          if pe.net_sum[id] and made > pe.net_sum[id] then pe.recent[id] = game.tick end     -- сеть даёт ток прямо сейчас
          pe.net_sum[id] = made
        end
      end
      -- проверка перебоя по нескольким машинам каждой сети
      local short, short_ids = shortage_kind(pe)
      local stored, cap, acc_n, acc_short = 0, 0, 0, 0
      for _, a in ipairs(pe.acc) do
        if a.valid then
          stored = stored + a.energy; cap = cap + a.electric_buffer_size; acc_n = acc_n + 1
          if short_ids then
            local oka, aid = pcall(function() return a.electric_network_id end)
            if oka and short_ids[aid] then acc_short = acc_short + 1 end
          end
        end
      end
      local now = {tick = game.tick, prod = prod, cons = cons}
      local last = pe.last
      if last and now.tick > last.tick then
        local sec = (now.tick - last.tick) / 60
        local by_prod, by_cons = {}, {}
        for name, j in pairs(prod) do local dj = j - ((last.prod or {})[name] or 0); if dj > 0 then by_prod[name] = dj / sec end end
        for name, j in pairs(cons) do local dj = j - ((last.cons or {})[name] or 0); if dj > 0 then by_cons[name] = dj / sec end end
        local acc_out, acc_in = 0, 0
        for name, w in pairs(by_prod) do if prototypes.entity[name] and prototypes.entity[name].type == "accumulator" then acc_out = acc_out + w; by_prod[name] = nil end end
        for name, w in pairs(by_cons) do if prototypes.entity[name] and prototypes.entity[name].type == "accumulator" then acc_in = acc_in + w; by_cons[name] = nil end end
        -- сколько топ-источников и потребителей стоит на планете (все качества вместе)
        -- считать дорого на больших базах: имя пересчитывается не чаще раза в 10 минут
        -- подсчёты дорогие на большой базе: не больше нескольких имён за замер, каждое обновляется раз в 10 минут
        pe.cnt, pe.cntq, pe.cnt_t = pe.cnt or {}, pe.cntq or {}, pe.cnt_t or {}
        local cnt = pe.cnt
        local budget = 4
        local function count_top(by, limit)
          local arr = {}
          for name, w in pairs(by) do arr[#arr + 1] = {name, w} end
          table.sort(arr, function(a, b) return a[2] > b[2] end)
          for i = 1, math.min(limit, #arr) do
            local name = arr[i][1]
            if (cnt[name] == nil or game.tick - (pe.cnt_t[name] or 0) > 36000) and budget > 0 then
              budget = budget - 1
              local per, total = count_q(s, name)
              cnt[name] = total > 0 and total or false
              pe.cntq[name] = per
              pe.cnt_t[name] = game.tick
            end
          end
        end
        count_top(by_prod, 30)      -- все источники: от них зависит максимум
        count_top(by_cons, 5)
        -- максимум, что могут дать источники: сколько их стоит × сколько даёт один в лучшем случае
        -- (текущая выработка часто ниже — столько и нужно)
        -- с учётом качества каждой постройки и множителя солнца этой планеты
        local capw = 0
        for name, w in pairs(by_prod) do
          local per = pe.cntq[name]
          local c = per and capacity_of(per, name, s) or 0
          if c > 0 then capw = capw + c else capw = capw + w end
        end
        local made = sum(by_prod)
        if capw < made then capw = made end
        -- выработка без солнца (ночью её должны дать аккумуляторы только сверх неё) и перепись топлива и источников
        local prod_ns = 0
        for name, w in pairs(by_prod) do
          local pr = prototypes.entity[name]
          if not (pr and pr.type == "solar-panel") then prod_ns = prod_ns + w end
        end
        -- реакторы и котлы: статусы и запас топлива читаем раз в ~100 секунд (их до 400 штук)
        local bc = pe.bcache
        if not bc or game.tick - bc.tick >= 6000 then
          local fn, fm = 0, 0
          for _, e in ipairs(pe.burners or {}) do
            if e.valid then
              fn = fn + 1
              local okb, stb = pcall(function() return e.status end)
              if okb and stb == st.no_fuel then fm = fm + 1 end
            end
          end
          bc = {tick = game.tick, n = fn, miss = fm, fuel = fuel_energy(pe.burners)}
          pe.bcache = bc
        end
        local fuel_n, fuel_miss = bc.n, bc.miss
        local g_nofuel, g_nofluid, solar = 0, 0, false
        for _, list in pairs(pe.gens or {}) do
          for _, e in ipairs(list) do
            if e.valid then
              if e.type == "solar-panel" then solar = true end
              local okg, stg = pcall(function() return e.status end)
              if okg then
                if stg == st.no_fuel then g_nofuel = g_nofuel + 1
                elseif stg == st.no_input_fluid then g_nofluid = g_nofluid + 1 end
              end
            end
          end
        end
        table.insert(pe.hist, {tick = now.tick, cnt = cnt, prod = sum(by_prod), capw = capw, cons = sum(by_cons), acc_in = acc_in, acc_out = acc_out,
          stored = stored, cap = cap, short = short, by_prod = by_prod, by_cons = by_cons, acc_n = acc_n, acc_short = acc_short,
          acc_iso = pe.acc_iso or 0, fuel = bc.fuel, prod_ns = prod_ns, fuel_n = fuel_n, fuel_miss = fuel_miss, g_nofuel = g_nofuel, g_nofluid = g_nofluid,
          solar = solar})
        while #pe.hist > HIST do table.remove(pe.hist, 1) end
        local hh = pe.hist[#pe.hist]
        push_long(pe, now.tick, hh.prod, hh.cons, hh.stored)
        local an = M.analyze({h = pe.hist[#pe.hist], hist = pe.hist, long = pe.long, cur = short, cur_known = true, s = s})
        -- у открытого перебоя свежие причины (саму запись создаёт быстрая проверка)
        local open = short and open_entry(key, "red")
        if open then
          if #an.reasons > 0 then open.why = an.reasons end
          open.cons, open.prod = pe.hist[#pe.hist].cons, pe.hist[#pe.hist].prod
        end
        M.warn_track(pe, key, an, short)
      end
      pe.last = now
    end
  end
end

-- жёлтые записи: сеть работает, но на пределе или с риском (причины те же, что в подсказке к планете).
-- Запись появляется, когда так было WARN_AFTER замеров подряд, и закрывается после двух спокойных замеров
-- или когда начинается настоящий перебой (красная запись)
local function close_entry(e)
  if e.done then return end
  e.done = true
  e.total = (e.total or 0) + math.max(0, (e.last or 0) - (e.run or e.start or 0))
end
function M.warn_track(pe, key, an, red)
  local now = game.tick
  local open = open_entry(key, "warn")
  if red or not an or not an.loggable then
    pe.warn_n = 0
    if open then
      pe.warn_ok = (pe.warn_ok or 0) + 1
      if red or pe.warn_ok >= 3 then close_entry(open); pe.warn_ok = 0 end
    end
    return
  end
  pe.warn_ok = 0
  pe.warn_n = (pe.warn_n or 0) + 1
  local h = pe.hist[#pe.hist]
  if open then
    open.last = now
    if #an.reasons > 0 then open.why = an.reasons end
    open.cons, open.prod = h and h.cons, h and h.prod
  elseif pe.warn_n >= WARN_AFTER then
    local log = LOG()
    local again = nil
    for i, e in ipairs(log) do
      if e.key == key and e.done and (e.level or "red") == "warn" and now - (e.last or 0) < MERGE_GAP then again = i; break end
    end
    local start = now - (WARN_AFTER - 1) * SAMPLE_GAP
    if again then
      local e = table.remove(log, again)
      e.done, e.n, e.run, e.last = false, (e.n or 1) + 1, start, now
      if #an.reasons > 0 then e.why = an.reasons end
      table.insert(log, 1, e)
    else
      table.insert(log, 1, {key = key, level = "warn", start = start, run = start, last = now, kind = "warn", why = an.reasons,
        n = 1, total = 0, done = false, cons = h and h.cons, prod = h and h.prod})
      while #log > LOG_MAX do table.remove(log) end
    end
  end
end

-- растянуто по времени: раз в 2 секунды максимум одна планета, чей замер устарел
-- (а не все планеты в один тик)
function M.sample_due()
  local best, best_t = nil, nil
  for _, s in pairs(game.surfaces) do
    if C.RP(s) then
      local pe = M.planet(s.planet.prototype.name)
      local t = pe.last and pe.last.tick or -1
      -- с сетью — раз в ~20 с, без — изредка (новый столб помечает «грязной»)
      local gap = next(pe.nets) and SAMPLE_GAP or 3600
      if game.tick - t >= gap and (not best_t or t < best_t) then best, best_t = s, t end
    end
  end
  if best then M.sample(best) end
  -- платформы: по одной за вызов, самая давно не измерявшаяся
  local pbest, pt = nil, nil
  local pd = M.plat_data()
  for _, pl in pairs(game.forces.player.platforms) do
    if pl.valid and pl.surface and pl.surface.valid then
      local t = pd[pl.index] and pd[pl.index].tick or -1
      if game.tick - t >= SAMPLE_GAP and (not pt or t < pt) then pbest, pt = pl, t end
    end
  end
  if pbest then pcall(M.sample_platform, pbest) end
end

---------------------------------------------------------------- быстрая проверка: перебой пишется, когда случился
-- раз в секунду у каждой сети спрашивается статус одной машины (дёшево). Перебой в 10 секунд сразу
-- становится записью журнала со свежими причинами; две чистые проверки подряд закрывают его. Перебои одной
-- планеты ближе 10 минут — одна запись со счётчиком повторов (иначе солнечные ночи забили бы журнал)
local function commit(pe, key, s, kind)
  local now = game.tick
  local pending = pe.pending
  pe.pending = nil
  -- свежие числа для причин
  if s then M.sample(s) end
  local an = M.analyze({h = pe.hist[#pe.hist], hist = pe.hist, long = pe.long, cur = kind, cur_known = true, s = s})
  local log = LOG()
  local again = nil
  for i, e in ipairs(log) do
    if e.key == key and e.done and (e.level or "red") == "red" and now - (e.last or 0) < MERGE_GAP then again = i; break end
  end
  if again then
    local e = table.remove(log, again)
    e.done, e.n, e.run, e.last = false, (e.n or 1) + 1, pending.tick, now
    e.prev_t, e.prev_k = nil, nil
    e.share = math.max(e.share or 0, pending.share or 0)
    if kind == "none" then e.kind = "none" end
    if #an.reasons > 0 then e.why = an.reasons end
    table.insert(log, 1, e)
  else
    local h0 = pe.hist[#pe.hist]
    table.insert(log, 1, {key = key, level = "red", start = pending.tick, run = pending.tick, last = now, kind = kind, why = an.reasons,
      n = 1, total = 0, done = false, t_none = 0, t_low = 0, share = pending.share, cons = h0 and h0.cons, prod = h0 and h0.prod})
    while #log > LOG_MAX do table.remove(log) end
  end
  if now - (pe.warned or -1e9) > 30 * 3600 then
    pe.warned = now
    C.journal({"tr-msg.power-" .. kind, C.planet_ls(key)})
  end
end

local function track(pe, key, s, kind, frac)
  local now = game.tick
  pe.cur = kind
  local open = open_entry(key, "red")
  if kind then
    pe.good = 0
    if open then
      -- сколько из этого времени тока не было совсем, а сколько просто не хватало
      local dt = math.min(now - (open.prev_t or now), 300)
      if (open.prev_k or kind) == "none" then open.t_none = (open.t_none or 0) + dt else open.t_low = (open.t_low or 0) + dt end
      open.prev_t, open.prev_k = now, kind
      open.last = now
      open.share = math.max(open.share or 0, frac or 0)
      if kind == "none" then open.kind = "none" end
    else
      if not pe.pending then pe.pending = {tick = now, kind = kind, share = frac or 0}
      else
        if kind == "none" then pe.pending.kind = "none" end
        pe.pending.share = math.max(pe.pending.share or 0, frac or 0)
      end
      if now - pe.pending.tick >= (pe.pending.kind == "none" and MIN_EVENT or MIN_EVENT_LOW) then commit(pe, key, s, pe.pending.kind) end
    end
  else
    pe.pending = nil
    if open then
      pe.good = (pe.good or 0) + 1
      if pe.good >= CLOSE_AFTER then
        open.done = true
        open.total = (open.total or 0) + math.max(0, (open.last or 0) - (open.run or open.start or 0))
        pe.good = 0
      end
    end
  end
end

function M.fast()
  for key, pe in pairs(E()) do
    if pe.refs and (next(pe.refs) or pe.cur or pe.pending or open_entry(key, "red") or open_entry(key, "warn")) then
      local pl = game.planets and game.planets[key]
      local s = pl and pl.surface
      if s and not s.valid then s = nil end
      local kind, frac = nil, 0
      if next(pe.refs) then
        local ok, k, _, fr = pcall(shortage_kind, pe)
        kind = ok and k or nil
        frac = ok and fr or 0
      end
      track(pe, key, s, kind, frac)
    end
  end
end

---------------------------------------------------------------- космические платформы
-- У платформы своя маленькая сеть: солнечные панели, аккумуляторы, машины. Меряем раз в ~20 с (две плохие проверки подряд —
-- запись журнала). Красное: машинам не хватает или нет тока, аккумуляторы разрядились и источники не тянут, источников нет,
-- работающие машины могут потребить больше, чем дают источники. Жёлтое: заряд на исходе, потребление у предела
local PCONS = {"assembling-machine", "furnace", "lab", "inserter", "roboport", "radar", "lamp", "beacon", "mining-drill",
  "electric-turret", "asteroid-collector"}
local PCHECK = {["assembling-machine"] = true, furnace = true, lab = true, ["mining-drill"] = true}

function M.plat_data()
  local d = C.D()
  d.energy_plat = d.energy_plat or {}
  return d.energy_plat
end

local function plat_track(pe, key, kind, why, h)
  local now = game.tick
  local open = open_entry(key, "red")
  if kind then
    pe.ok = 0
    pe.bad = (pe.bad or 0) + 1
    pe.bad_since = pe.bad_since or now
    if open then
      local dt = math.min(now - (open.prev_t or now), 3000)
      if (open.prev_k or kind) == "none" then open.t_none = (open.t_none or 0) + dt else open.t_low = (open.t_low or 0) + dt end
      open.prev_t, open.prev_k = now, kind
      open.last, open.kind, open.why, open.plat = now, kind, why, pe.name
      open.cons, open.prod = h.cons, h.prod
      open.share = math.max(open.share or 0, h.share or 0)
    elseif pe.bad >= ((kind == "low") and 3 or 2) then
      local log = LOG()
      local again = nil
      for i, e in ipairs(log) do
        if e.key == key and e.done and (e.level or "red") == "red" and now - (e.last or 0) < MERGE_GAP then again = i; break end
      end
      if again then
        local e = table.remove(log, again)
        e.done, e.n, e.run, e.last = false, (e.n or 1) + 1, pe.bad_since, now
        e.prev_t, e.prev_k, e.kind, e.why, e.plat = nil, nil, kind, why, pe.name
        table.insert(log, 1, e)
      else
        table.insert(log, 1, {key = key, plat = pe.name, level = "red", start = pe.bad_since, run = pe.bad_since, last = now,
          kind = kind, why = why, n = 1, total = 0, done = false, t_none = 0, t_low = 0, share = h.share, cons = h.cons, prod = h.prod})
        while #log > LOG_MAX do table.remove(log) end
      end
      if now - (pe.warned or -1e9) > 30 * 3600 then
        pe.warned = now
        C.journal({"tr-msg.power-plat-" .. kind, pe.name})
      end
    end
  else
    pe.bad, pe.bad_since = 0, nil
    if open then
      pe.ok = (pe.ok or 0) + 1
      if pe.ok >= 2 then close_entry(open); pe.ok = 0 end
    end
  end
end

function M.sample_platform(pl)
  local s = pl.surface
  if not (s and s.valid) then return end
  local pd = M.plat_data()
  local pe = pd[pl.index]
  if not pe then pe = {}; pd[pl.index] = pe end
  pe.hist = pe.hist or {}
  local key = "pf" .. pl.index
  pe.name, pe.tick = pl.name, game.tick
  local force = game.forces.player
  local function find(f) local ok, r = pcall(s.find_entities_filtered, f); return ok and r or {} end
  -- на платформе столбы не нужны: все электрические постройки в одной сети, а статистики сети без столба нет
  local accs = find{type = "accumulator", force = force}
  local srcs = find{type = SOURCE_TYPES, force = force}
  local cons = find{type = PCONS, force = force}
  local burners = find{type = {"reactor", "boiler", "fusion-reactor", "burner-generator"}, force = force}
  if #accs == 0 and #srcs == 0 and #cons == 0 then
    pe.empty, pe.h, pe.reasons, pe.score, pe.cur, pe.notes = true, nil, nil, 0, nil, nil
    plat_track(pe, key, nil, nil, {})
    return
  end
  pe.empty = nil
  local now = game.tick
  local st = defines.entity_status
  -- заряд
  local stored, cap = 0, 0
  for _, a in ipairs(accs) do
    if a.valid then stored = stored + a.energy; cap = cap + a.electric_buffer_size end
  end
  -- что могут дать источники: у каждого своё качество, у солнечных панелей — солнце «в космосе» там, где платформа сейчас
  local sfac = {}
  local function sf(prop) prop = prop or "solar-power"; if not sfac[prop] then sfac[prop] = solar_factor(s, prop) end; return sfac[prop] end
  local maxp = 0
  local space_sun = plat_solar(pl)
  pe.sun = space_sun
  local non_solar = 0
  for _, e in ipairs(srcs) do
    if e.valid then
      local q = "normal"
      pcall(function() q = e.quality.name end)
      local p = pass(e.name, q)
      if p and p.maxp > 0 then
        local k = 1
        if p.type == "solar-panel" then
          if p.prop and p.prop ~= "solar-power" then k = sf(p.prop) else k = space_sun or sf(p.prop) end
        end
        maxp = maxp + p.maxp * k
        if p.type ~= "solar-panel" then non_solar = non_solar + 1 end
      end
    end
  end
  -- потребление оцениваем по состоянию машин: работающая тянет максимум, стоящая — только то, что тянет в простое
  local maxc, use = 0, 0
  local good, n_none, n_low = 0, 0, 0
  for _, e in ipairs(cons) do
    if e.valid then
      local q = "normal"
      pcall(function() q = e.quality.name end)
      local p = pass(e.name, q)
      local okst, status = pcall(function() return e.status end)
      local active = (not okst) or status == nil or status == st.working or status == st.low_power or status == st.no_power or status == st.normal
      if p then
        if active then maxc = maxc + p.maxc; use = use + p.maxc else use = use + (p.drain or p.maxc / 30) end
      end
      if PCHECK[e.type] and okst then
        good = good + 1
        if status == st.no_power then n_none = n_none + 1 elseif status == st.low_power then n_low = n_low + 1 end
      end
    end
  end
  local kind_hint = (good > 0 and (n_none + n_low) >= 1 and (n_none + n_low) * 4 >= good) or false
  -- топливо реакторов и котлов, если они есть
  local fuel_n, fuel_miss = 0, 0
  for _, e in ipairs(burners) do
    if e.valid then
      fuel_n = fuel_n + 1
      local okb, stb = pcall(function() return e.status end)
      if okb and stb == st.no_fuel then fuel_miss = fuel_miss + 1 end
    end
  end
  -- история: час по 20 секунд, сутки по 5 минут. Выработка оценивается по заряду: сколько тратится плюс сколько уходит в аккумуляторы
  local entry = {tick = now, cons = use, stored = stored, cap = cap, fuel = fuel_energy(burners), prod = use}
  table.insert(pe.hist, entry)
  while #pe.hist > HIST do table.remove(pe.hist, 1) end
  local ssl = slope(pe.hist, "stored", 12)
  -- оценка по максимумам машин — верхняя граница (игра считает «возможный максимум», а работают они обычно слабее). Уточняем:
  --  * только солнечные панели и аккумуляторы заряжаются или разряжаются: тогда потребление = выработка панелей минус заряд в секунду;
  --  * машины не жалуются на нехватку: потребление не может быть больше, чем дают источники
  local fill = cap > 0 and stored / cap or nil
  if ssl and fill and fill > 0.005 and fill < 0.995 and maxp > 0 and non_solar == 0 then
    use = math.max(0, maxp - ssl)
  elseif maxp > 0 and use > maxp and not kind_hint then
    use = maxp
  end
  local prod_w = use
  if ssl and cap > 0 then prod_w = math.max(0, math.min(maxp > 0 and maxp or math.huge, use + ssl)) end
  entry.cons, entry.prod = use, prod_w
  push_long(pe, now, prod_w, use, stored)
  -- состояние: красное только по фактам, жёлтое — по запасу и тренду
  local kind = nil
  local share = good > 0 and (n_none + n_low) / good or 0
  if good > 0 and n_none * 2 >= good and n_none > 0 then kind = "none"
  elseif good > 0 and (n_none + n_low) >= 1 and (n_none + n_low) * 4 >= good then kind = "low" end
  local reasons, score, notes = {}, 0, {}
  local function add(line, sc) reasons[#reasons + 1] = line; if sc > score then score = sc end end
  local pct = cap > 0 and math.floor(stored / cap * 100) or nil
  if kind == "none" then add({"tr-en.plat-why-none"}, 3) elseif kind == "low" then add({"tr-en.plat-why-low"}, 2) end
  local log_kind = kind
  local is_empty = false
  if cap > 0 and stored / cap < 0.02 and (maxp <= 0 or use >= maxp * 0.98) then
    add({"tr-en.plat-why-empty", pct}, 2)
    log_kind = log_kind or "empty"
    is_empty = true
  end
  if #srcs == 0 and #cons > 0 and use > 0 then add({"tr-en.plat-why-nosrc"}, 2) end
  if fuel_miss > 0 and (kind or use > maxp * 0.98) and fuel_miss * 2 >= fuel_n then
    add({"tr-en.why-nofuel", fuel_miss, fuel_n}, kind and 2 or 1)
  end
  if cap > 0 and stored / cap < 0.15 and use > maxp and not is_empty then add({"tr-en.plat-why-acc-low", pct}, 1) end
  if maxp > 0 and use >= maxp * 0.9 and score < 2 and not (fill and fill >= 0.995) then add({"tr-en.plat-why-limit", M.power(use), M.power(maxp)}, 1) end
  if ssl and ssl < 0 and stored > 0 and #pe.hist >= 8 and score < 2 then
    local eta = stored / -ssl
    if eta < 600 then add({"tr-en.why-acc-drain", math.max(1, math.floor(eta / 60 + 0.5)), M.power(-ssl)}, 1) end
  end
  pcall(M.series, pe.hist, pe.long, maxp, add, notes)
  pe.h = {prod = prod_w, cons = use, capw = maxp, maxc = maxc, stored = stored, cap = cap, acc_n = #accs,
    acc_in = (ssl and ssl > 0) and ssl or 0, acc_out = (ssl and ssl < 0) and -ssl or 0, src_n = #srcs, short = log_kind, share = share, est = true}
  pe.reasons, pe.score, pe.cur, pe.notes = reasons, score, log_kind, notes
  plat_track(pe, key, log_kind, reasons, pe.h)
end

-- платформы для окна: худшие первыми
function M.plat_rows()
  local rows = {}
  local pd = M.plat_data()
  for _, pl in pairs(game.forces.player.platforms) do
    if pl.valid then
      local pe = pd[pl.index]
      if pe and not pe.empty and pe.h then
        rows[#rows + 1] = {name = pl.name, h = pe.h, reasons = pe.reasons or {}, notes = pe.notes or {}, score = pe.score or 0, kind = pe.cur, cur = pe.cur, cur_known = true}
      end
    end
  end
  table.sort(rows, function(a, b)
    if a.score ~= b.score then return a.score > b.score end
    return a.name < b.name
  end)
  return rows
end

-- меняется, когда могло измениться то, что показывает вкладка (окно перерисовывается только тогда)
function M.sig()
  local parts = {}
  for key, pe in pairs(E()) do if pe.cur then parts[#parts + 1] = key .. ":" .. pe.cur end end
  local npl = 0
  for idx, pe in pairs(M.plat_data()) do
    if pe.cur then parts[#parts + 1] = "pf" .. idx .. ":" .. pe.cur end
    if not pe.empty and pe.h then npl = npl + 1 end
  end
  parts[#parts + 1] = "n" .. npl
  table.sort(parts)
  local log = LOG()
  local top = log[1]
  return table.concat(parts, ",") .. "|" .. #log .. "|" .. (top and (top.start .. ":" .. tostring(top.done) .. ":" .. (top.n or 1)) or "")
end

-- построили столб или аккумулятор: пересканировать планету на следующем замере
function M.on_built(ent)
  if not (ent and ent.valid) then return end
  local t = ent.type
  if t ~= "electric-pole" and t ~= "accumulator" and t ~= "generator" then return end
  if not C.RP(ent.surface) then return end
  M.planet(ent.surface.planet.prototype.name).dirty = true   -- пересканируется на следующем замере, не чаще раза в 5 минут
end

-- сводка для окна
function M.rows()
  local rows = {}
  for _, s in pairs(game.surfaces) do
    if C.RP(s) then
      local key = s.planet.prototype.name
      local pe = M.planet(key)
      local h = pe.hist[#pe.hist]
      local nets = 0
      for _, pole in pairs(pe.nets) do if pole.valid then nets = nets + 1 end end
      rows[#rows + 1] = {key = key, s = s, h = h, hist = pe.hist, long = pe.long, nets = nets, cur = pe.cur, cur_known = true}
    end
  end
  table.sort(rows, function(a, b) return (a.h and a.h.prod or 0) > (b.h and b.h.prod or 0) end)
  return rows
end

-- планета живёт на молниях (громоотводы среди источников за последний час)?
function M.storm(hist)
  for _, smp in ipairs(hist or {}) do
    for name in pairs(smp.by_prod or {}) do
      local pr = prototypes.entity[name]
      if pr and pr.type == "lightning-attractor" then return true end
    end
  end
  return false
end

-- электричеству плохо? Почему? По последним замерам планеты.
--   score 3 = тока нет, 2 = не хватает, 1 = риск (спрос на пределе, аккумуляторы почти пусты или не дотянут до утра), 0 = норма
--   reasons = строки причин: спрос выше выработки, пустые аккумуляторы, кончилось топливо, нет пара, скачок спроса, падение выработки,
--   прогноз на ночь (солнечные планеты: хватит ли заряда до рассвета)
--   notes = справка, на статус не влияет (например, аккумуляторы, которым нечего питать)
-- на грозовой планете выработка из статистики врёт (удар молнии даёт скачок), поэтому там смотрим на потребление и заряд аккумуляторов
function M.analyze(r)
  local out = {score = 0, reasons = {}, notes = {}}
  local h = r.h
  if not h then return out end
  -- быстрая проверка (раз в секунду) знает лучше замера (он до ~20 с старый)
  local sh = h.short
  if r.cur_known then sh = r.cur end
  if sh == "none" then out.score = 3 elseif sh then out.score = 2 end
  -- в журнал идут только причины, которые точно измерены и серьёзны (топливо, пар, нехватка заряда до рассвета, быстрая разрядка);
  -- «на пределе», скачки и просадки видны в окне, но журнал не заполняют
  local LOGGABLE = {["tr-en.why-nofuel"] = true, ["tr-en.why-gen-nofuel"] = true, ["tr-en.why-gen-nofluid"] = true,
    ["tr-en.why-night-short"] = true, ["tr-en.why-acc-drain"] = true, ["tr-en.why-fuel-low"] = true, ["tr-en.why-acc"] = true, ["tr-en.why-acc-storm"] = true}
  local function add(line, score)
    out.reasons[#out.reasons + 1] = line
    if score > out.score then out.score = score end
    if type(line) == "table" and LOGGABLE[line[1]] then out.loggable = true end
  end
  local storm = M.storm(r.hist)
  -- предел источников: номинал с учётом качества и солнца или пик, который реально наблюдался за час (что больше)
  local peak = 0
  if not storm then for _, x in ipairs(r.hist or {}) do if x.prod > peak then peak = x.prod end end end
  local cap = math.max(h.capw or 0, h.prod, peak)
  local acc_ok = (h.cap or 0) > 0 and h.stored / h.cap >= 0.15
  local no_acc = (h.acc_n or 0) == 0 and (h.cap or 0) == 0
  local nostore = false
  local short_of_prod = h.prod <= 0 or h.prod < (h.cons or 0) * 0.98
  -- топливо: у реакторов и котлов оно кончилось, у генераторов нет топлива или пара
  if (h.fuel_miss or 0) > 0 and (sh or short_of_prod) and (sh or h.fuel_miss * 2 >= (h.fuel_n or h.fuel_miss)) then
    add({"tr-en.why-nofuel", h.fuel_miss, h.fuel_n or h.fuel_miss}, sh and 2 or 1)
  end
  if (h.g_nofuel or 0) > 0 and (sh or short_of_prod) then add({"tr-en.why-gen-nofuel", h.g_nofuel}, sh and 2 or 1) end
  if (h.g_nofluid or 0) > 0 and (sh or short_of_prod) and (h.fuel_miss or 0) == 0 then
    add({"tr-en.why-gen-nofluid", h.g_nofluid}, sh and 2 or 1)
  end
  local fuel_known = #out.reasons > 0
  if h.prod <= 0 and (h.cons > 0 or sh) then
    if storm and acc_ok then
      -- между грозами: норма
    elseif storm then add({"tr-en.why-noprod-storm"}, 2)
    elseif no_acc then add({"tr-en.why-nostore"}, 2); nostore = true       -- ничего не вырабатывает и ничего не хранит
    elseif h.cons > 0 then add({"tr-en.why-noprod", M.power(h.cons)}, 2)
    else add({"tr-en.why-noprod0"}, 2) end
  elseif not storm and cap > 0 and h.cons >= cap * 0.92 then
    add({"tr-en.why-demand", M.power(h.cons), M.power(cap)}, 1)
  end
  if (h.cap or 0) > 0 and h.stored / h.cap < 0.15 and (storm and (h.cons or 0) > 1e4 or h.cons > cap * 0.8) then
    if storm then add({"tr-en.why-acc-storm", math.floor(h.stored / h.cap * 100)}, 1)
    else add({"tr-en.why-acc", math.floor(h.stored / h.cap * 100)}, 1) end
  end
  -- солнечная планета: хватит ли заряда до рассвета (или хватит ли ёмкости на ночь). Длину дня и ночи берём у самой планеты
  local forecast = false
  if h.solar and not storm and (h.acc_n or 0) > 0 and r.s and r.s.valid then
    local okd, d = pcall(function()
      local sf = r.s
      if sf.freeze_daytime then return nil end
      return {t = sf.daytime, tpd = sf.ticks_per_day, dusk = sf.dusk, evening = sf.evening, morning = sf.morning, dawn = sf.dawn}
    end)
    if okd and d and d.tpd and d.tpd > 0 and d.dusk and d.dawn then
      forecast = true
      local load = math.max(0, (h.cons or 0) - (h.prod_ns or 0))        -- столько ночью должны отдать аккумуляторы
      if load > 1e4 then
        local t = d.t % 1
        local dark_now = t >= d.dusk and t < d.dawn
        local night_ticks
        if dark_now then
          if t < d.morning then night_ticks = (d.morning - t) * d.tpd + (d.dawn - d.morning) * d.tpd / 2
          else night_ticks = (d.dawn - t) * d.tpd / 2 end
        else
          night_ticks = ((d.evening - d.dusk) / 2 + (d.morning - d.evening) + (d.dawn - d.morning) / 2) * d.tpd
        end
        local need = load * night_ticks / 60                           -- Дж
        local have = dark_now and h.stored or h.cap
        if need > 0 and have < need then
          add({dark_now and "tr-en.why-night-short" or "tr-en.why-night-cap", math.floor(have / load / 60 + 0.5), math.floor(night_ticks / 3600 + 0.5)}, 1)
        end
      end
    end
  end
  -- аккумуляторы несут сеть и скоро сядут (там, где день и ночь не считаются): на сколько хватит заряда при текущей отдаче
  -- (отдача считается по тому, как реально убывает заряд за последние ~10 минут, а если замеров мало — по статистике сети)
  local drain = h.acc_out or 0
  local ssl = slope(r.hist or {}, "stored", 30)
  if ssl and #(r.hist or {}) >= 8 then drain = math.max(0, -ssl) end
  if not forecast and not (h.solar and not storm) and drain > 1e4 and (h.stored or 0) > 0 and h.prod < h.cons then
    local eta = h.stored / drain
    if eta < 600 then add({"tr-en.why-acc-drain", math.max(1, math.floor(eta / 60 + 0.5)), M.power(drain)}, 1) end
  end
  -- длинный ряд: тренд потребления, топливо на исходе
  pcall(M.series, r.hist or {}, r.long, storm and 0 or cap, add, out.notes)
  -- сравнение со средним до 10 замеров перед последним
  local hist = r.hist or {}
  local n, sc, sp = 0, 0, 0
  for i = math.max(1, #hist - 10), #hist - 1 do sc = sc + hist[i].cons; sp = sp + hist[i].prod; n = n + 1 end
  if n >= 3 then
    local ac, ap = sc / n, sp / n
    if ac > 0 and h.cons > ac * 1.3 and h.cons - ac > 5e6 then
      local best, bn = 0, nil
      for name, w in pairs(h.by_cons or {}) do
        local before = 0
        for i = math.max(1, #hist - 10), #hist - 1 do before = before + ((hist[i].by_cons or {})[name] or 0) end
        local grow = w - before / n
        if grow > best then best, bn = grow, name end
      end
      if bn then add({"tr-en.why-jump", math.floor((h.cons / ac - 1) * 100), "[entity=" .. bn .. "]", M.power(best)}, 1)
      else add({"tr-en.why-jump-plain", math.floor((h.cons / ac - 1) * 100)}, 1) end
    end
    if not storm and not fuel_known and ap > 0 and h.prod < ap * 0.7 and ap - h.prod > 5e6 then
      local worst, wn = 0, nil
      for name, w in pairs(hist[#hist - 1].by_prod or {}) do
        local drop = w - ((h.by_prod or {})[name] or 0)
        if drop > worst then worst, wn = drop, name end
      end
      local pr = wn and prototypes.entity[wn]
      local pct = math.floor((1 - h.prod / ap) * 100)
      if pr and pr.type == "lightning-attractor" then
        if not acc_ok then add({"tr-en.why-drop-storm", pct, "[entity=" .. wn .. "]"}, 1) end   -- затишье между грозами
      elseif pr and pr.type == "solar-panel" then
        -- ночь — причина, только если сеть чем-то держится; без аккумуляторов это неисправность
        if no_acc then
          if not nostore then add({"tr-en.why-solar-nostore", pct, "[entity=" .. wn .. "]"}, 2) end
        elseif not forecast then add({"tr-en.why-drop-solar", pct, "[entity=" .. wn .. "]"}, 1) end
      elseif wn then add({"tr-en.why-drop", pct, "[entity=" .. wn .. "]", M.power(worst)}, 1)
      else add({"tr-en.why-drop-plain", pct}, 1) end
    end
  end
  if storm and sh and #out.reasons == 0 then add({"tr-en.why-short-storm"}, 2) end
  -- заряженные аккумуляторы ничего не отдают при нехватке: скорее всего не подключены к сети
  if sh and (h.cap or 0) > 0 and h.stored / h.cap >= 0.2 and h.acc_short ~= nil then
    if h.acc_short == 0 and (h.acc_n or 0) > 0 then
      add({"tr-en.why-acc-elsewhere", h.acc_n}, 2)
    elseif (h.acc_out or 0) < 1e4 then
      add({"tr-en.why-acc-idle", math.floor(h.stored / h.cap * 100)}, 2)
    end
  end
  -- справка: аккумуляторы, которым нечего питать (на статус и журнал не влияет)
  if (h.acc_iso or 0) > 0 and (h.acc_n or 0) > 0 then out.notes[#out.notes + 1] = {"tr-en.note-acc-iso", h.acc_iso, h.acc_n} end
  -- ничего не вырабатывается и ничего не потребляется: «хватает» тут не скажешь
  if out.score == 0 and h.prod <= 0 and (h.cons or 0) <= 0 and not sh then out.idle = true end
  return out
end

-- перебои с тика, для итогов смены: {{key, count, minutes}} худшие первыми
function M.trouble_since(tick)
  local by = {}
  for _, ev in ipairs(LOG()) do
    if ev.start >= tick and (ev.level or "red") == "red" and not ev.plat then
      local x = by[ev.key] or {key = ev.key, n = 0, mins = 0}
      by[ev.key] = x
      x.n = x.n + (ev.n or 1)
      x.mins = x.mins + math.max(1, math.floor(M.duration(ev) / 3600 + 0.5))
    end
  end
  local out = {}
  for _, x in pairs(by) do out[#out + 1] = x end
  table.sort(out, function(a, b) return a.mins > b.mins end)
  return out
end

function M.power(w)
  w = w or 0
  if w >= 1e9 then return {"tr.power-gw", string.format("%.2f", w / 1e9)} end
  if w >= 1e6 then return {"tr.power-mw", string.format("%.1f", w / 1e6)} end
  return {"tr.power-kw", string.format("%.0f", w / 1e3)}
end
function M.energy(j)
  j = j or 0
  if j >= 1e9 then return {"tr.energy-gj", string.format("%.1f", j / 1e9)} end
  return {"tr.energy-mj", string.format("%.0f", j / 1e6)}
end

return M
