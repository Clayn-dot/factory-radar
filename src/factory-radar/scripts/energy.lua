-- Factory Radar: электричество по планетам — выработка, потребление, аккумуляторы, перебои
-- в статистике сети input = ПОТРЕБИТЕЛИ, output = ИСТОЧНИКИ (наоборот, чем кажется)
-- сети ищем редко (поиск столбов дорогой), читаем часто — это дёшево
local C = require("scripts.core")
local M = {}

local HIST = 120                -- отсчёт раз в ~20 с → около 40 минут истории
local SAMPLE_GAP = 1200         -- тиков между двумя замерами планеты с сетью
local REDISCOVER = 30 * 3600    -- тиков между поисками сетей
local CHECK_TYPES = {"assembling-machine", "furnace", "lab", "mining-drill"}
local MIN_EVENT = 600           -- перебой пишем, когда он длится 10 с (короче игнорим)
local MERGE_GAP = 10 * 3600     -- перебои одной планеты ближе этого — одна запись («6 раз за 40 мин»)
local CLOSE_AFTER = 2           -- проверок подряд без перебоя, чтобы его закрыть
local LOG_MAX = 10

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
local function open_entry(key)
  for _, e in ipairs(LOG()) do if e.key == key and not e.done then return e end end
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
  for id, list in pairs(pe.refs) do
    if type(list) == "userdata" then list = {list} end      -- формат старой версии, до следующего скана
    if alive(pe, id) then
      local good = 0
      for _, m in ipairs(list) do
        if m.valid then
          good = good + 1
          local ok, status = pcall(function() return m.status end)
          if ok then
            if status == st.no_power then kind = "none"; ids = ids or {}; ids[id] = true
            elseif status == st.low_power then
              if kind ~= "none" then kind = "low" end
              ids = ids or {}; ids[id] = true
            end
          end
        end
      end
      if good * 2 < #list then pe.refs_bad = true end
    end
  end
  return kind, ids
end

local SOURCE_TYPES = {"generator", "burner-generator", "solar-panel", "fusion-generator", "lightning-attractor",
  "electric-energy-interface"}
local REFS = 6          -- машин на сеть
local SOURCES = 4       -- запоминаемых источников на сеть

local function scan(s, pe)
  pe.nets, pe.refs, pe.acc, pe.ever, pe.gens, pe.recent, pe.net_sum = {}, {}, {}, {}, {}, {}, {}
  local force = game.forces.player
  for _, pole in pairs(s.find_entities_filtered{type = "electric-pole", force = force}) do
    local id = pole.electric_network_id
    if id and not pe.nets[id] then pe.nets[id] = pole end
  end
  for _, a in pairs(s.find_entities_filtered{type = "accumulator", force = force, limit = 3000}) do pe.acc[#pe.acc + 1] = a end
  -- источники каждой сети
  local okp, srcs = pcall(s.find_entities_filtered, {type = SOURCE_TYPES, force = force, limit = 5000})
  if okp then
    for _, e in pairs(srcs) do
      local ok, id = pcall(function() return e.electric_network_id end)
      if ok and id then
        local list = pe.gens[id] or {}
        pe.gens[id] = list
        if #list < SOURCES then list[#list + 1] = e end
      end
    end
  end
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
    pe.refs[id] = pick
  end
  pe.refs_v = 2
  pe.scanned = game.tick
  pe.dirty, pe.refs_bad = nil, nil
end

local function sum(t) local n = 0; for _, v in pairs(t) do n = n + v end; return n end

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
      if stale then scan(s, pe) end
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
        if not pe.cnt or game.tick - (pe.cnt_at or 0) > 10 * 3600 then pe.cnt, pe.cnt_at = {}, game.tick end
        local cnt = pe.cnt
        local function count_top(by, limit)
          local arr = {}
          for name, w in pairs(by) do arr[#arr + 1] = {name, w} end
          table.sort(arr, function(a, b) return a[2] > b[2] end)
          for i = 1, math.min(limit, #arr) do
            local name = arr[i][1]
            if cnt[name] == nil then
              local ok4, n = pcall(s.count_entities_filtered, {name = name, force = game.forces.player})
              cnt[name] = ok4 and n or false
            end
          end
        end
        count_top(by_prod, 30)      -- все источники: от них зависит максимум
        count_top(by_cons, 5)
        -- максимум, что могут дать источники: сколько их стоит × сколько даёт один в лучшем случае
        -- (текущая выработка часто ниже — столько и нужно)
        local capw = 0
        for name, w in pairs(by_prod) do
          local n, proto = cnt[name], prototypes.entity[name]
          local mw = nil
          if n and proto then
            local okm, v = pcall(proto.get_max_energy_production)
            if okm and type(v) == "number" then mw = v end
          end
          if n and mw and mw > 0 then capw = capw + n * mw * 60 else capw = capw + w end
        end
        local made = sum(by_prod)
        if capw < made then capw = made end
        table.insert(pe.hist, {tick = now.tick, cnt = cnt, prod = sum(by_prod), capw = capw, cons = sum(by_cons), acc_in = acc_in, acc_out = acc_out,
          stored = stored, cap = cap, short = short, by_prod = by_prod, by_cons = by_cons, acc_n = acc_n, acc_short = acc_short})
        while #pe.hist > HIST do table.remove(pe.hist, 1) end
        -- у открытого перебоя свежие причины (саму запись создаёт быстрая проверка)
        local open = short and open_entry(key)
        if open then
          local an = M.analyze({h = pe.hist[#pe.hist], hist = pe.hist, cur = short, cur_known = true})
          if #an.reasons > 0 then open.why = an.reasons end
        end
      end
      pe.last = now
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
  local an = M.analyze({h = pe.hist[#pe.hist], hist = pe.hist, cur = kind, cur_known = true})
  local log = LOG()
  local again = nil
  for i, e in ipairs(log) do
    if e.key == key and e.done and now - (e.last or 0) < MERGE_GAP then again = i; break end
  end
  if again then
    local e = table.remove(log, again)
    e.done, e.n, e.run, e.last = false, (e.n or 1) + 1, pending.tick, now
    if kind == "none" then e.kind = "none" end
    if #an.reasons > 0 then e.why = an.reasons end
    table.insert(log, 1, e)
  else
    table.insert(log, 1, {key = key, start = pending.tick, run = pending.tick, last = now, kind = kind, why = an.reasons,
      n = 1, total = 0, done = false})
    while #log > LOG_MAX do table.remove(log) end
  end
  if now - (pe.warned or -1e9) > 30 * 3600 then
    pe.warned = now
    C.journal({"tr-msg.power-" .. kind, C.planet_ls(key)})
  end
end

local function track(pe, key, s, kind)
  local now = game.tick
  pe.cur = kind
  local open = open_entry(key)
  if kind then
    pe.good = 0
    if open then
      open.last = now
      if kind == "none" then open.kind = "none" end
    else
      if not pe.pending then pe.pending = {tick = now, kind = kind}
      elseif kind == "none" then pe.pending.kind = "none" end
      if now - pe.pending.tick >= MIN_EVENT then commit(pe, key, s, pe.pending.kind) end
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
    if pe.refs and (next(pe.refs) or pe.cur or pe.pending or open_entry(key)) then
      local pl = game.planets and game.planets[key]
      local s = pl and pl.surface
      if s and not s.valid then s = nil end
      local kind = nil
      if next(pe.refs) then
        local ok, k = pcall(shortage_kind, pe)
        kind = ok and k or nil
      end
      track(pe, key, s, kind)
    end
  end
end

-- меняется, когда могло измениться то, что показывает вкладка (окно перерисовывается только тогда)
function M.sig()
  local parts = {}
  for key, pe in pairs(E()) do if pe.cur then parts[#parts + 1] = key .. ":" .. pe.cur end end
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
      rows[#rows + 1] = {key = key, s = s, h = h, hist = pe.hist, nets = nets, cur = pe.cur, cur_known = true}
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
--   score 3 = тока нет, 2 = не хватает, 1 = риск (спрос на пределе или аккумуляторы почти пусты), 0 = норма
--   reasons = строки: спрос выше выработки, пустые аккумуляторы, скачок спроса (и какая машина выросла больше всего),
--   падение выработки (и какой источник просел сильнее)
function M.analyze(r)
  local out = {score = 0, reasons = {}}
  local h = r.h
  if not h then return out end
  -- быстрая проверка (раз в секунду) знает лучше замера (он до ~20 с старый)
  local sh = h.short
  if r.cur_known then sh = r.cur end
  if sh == "none" then out.score = 3 elseif sh then out.score = 2 end
  local function add(line, score) out.reasons[#out.reasons + 1] = line; if score > out.score then out.score = score end end
  local cap = math.max(h.capw or 0, h.prod)      -- максимум, что дают источники
  -- на грозовой планете источники приходят и уходят с грозами, между ними сеть тянут аккумуляторы
  local storm = M.storm(r.hist)
  local acc_ok = (h.cap or 0) > 0 and h.stored / h.cap >= 0.15
  local no_acc = (h.acc_n or 0) == 0 and (h.cap or 0) == 0
  local nostore = false
  if h.prod <= 0 and (h.cons > 0 or sh) then
    if storm and acc_ok then
      -- между грозами: норма
    elseif storm then add({"tr-en.why-noprod-storm"}, 2)
    elseif no_acc then add({"tr-en.why-nostore"}, 2); nostore = true       -- ничего не вырабатывает и ничего не хранит
    elseif h.cons > 0 then add({"tr-en.why-noprod", M.power(h.cons)}, 2)
    else add({"tr-en.why-noprod0"}, 2) end
  elseif cap > 0 and h.cons >= cap * 0.92 and not (storm and acc_ok) then
    add({"tr-en.why-demand", M.power(h.cons), M.power(cap)}, 1)
  end
  if (h.cap or 0) > 0 and h.stored / h.cap < 0.15 and h.cons > cap * 0.8 then
    if storm then add({"tr-en.why-acc-storm", math.floor(h.stored / h.cap * 100)}, 1)
    else add({"tr-en.why-acc", math.floor(h.stored / h.cap * 100)}, 1) end
  end
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
    if ap > 0 and h.prod < ap * 0.7 and ap - h.prod > 5e6 then
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
        else add({"tr-en.why-drop-solar", pct, "[entity=" .. wn .. "]"}, 1) end
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
  -- ничего не вырабатывается и ничего не потребляется: «хватает» тут не скажешь
  if out.score == 0 and h.prod <= 0 and (h.cons or 0) <= 0 and not sh then out.idle = true end
  return out
end

-- перебои с тика, для итогов смены: {{key, count, minutes}} худшие первыми
function M.trouble_since(tick)
  local by = {}
  for _, ev in ipairs(LOG()) do
    if ev.start >= tick then
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
