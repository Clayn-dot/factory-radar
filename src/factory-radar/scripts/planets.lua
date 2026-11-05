-- Factory Radar: освоение планет, снимки выпуска по планетам, история и отчёт смены
local C = require("scripts.core")
local M = {}

-- научные паки = предметы, которые принимают лаборатории (простой тип «tool» тоже попадает под фильтры)
local SCIENCE, SET = nil, nil
function M.science_names()
  if not SCIENCE then
    SCIENCE, SET = {}, {}
    for _, lab in pairs(prototypes.get_entity_filtered{{filter = "type", type = "lab"}}) do
      for _, name in pairs(lab.lab_inputs or {}) do
        if not SET[name] and prototypes.item[name] then SET[name] = true; SCIENCE[#SCIENCE + 1] = name end
      end
    end
    table.sort(SCIENCE)
  end
  return SCIENCE
end
function M.is_science(name) M.science_names(); return SET[name] == true end

local function player_force() return game.forces.player end

---------------------------------------------------------------- «родная» наука планеты
-- Пак принадлежит планете, когда сходятся признаки. Сигналы (баллы):
--   условия поверхности: его рецепты работают на 1-2 видимых планетах ........... 4 (сильный, хватает одного)
--   где реально делается: >= 60 % таких паков сделано там ........................ 3 (сильный, нужен ещё один)
--   дерево технологий: ближайшая «planet-discovery-<planet>» перед технологией ... 2
--   домашняя планета предмета (default_import_location, не nauvis) ............... 1
-- Нужно 4+ баллов И один сильный сигнал (простые красные/зелёные, сделанные на Nauvis, — не «наука Nauvis»).
-- Паки, которые делаются только в космосе, привязываются к планете, только если домашняя планета и дерево
-- технологий совпали и у планеты нет своей наземной науки.
-- Админ может переопределить всё по планете во вкладке «Настройки».
local STATIC = nil      -- часть только по прототипам, одинаковая у всех (кэш, безопасно для мультиплеера)

local function prop_value(proto, name)
  local sp = proto.surface_properties or {}
  if sp[name] ~= nil then return sp[name] end
  local pp = prototypes.surface_property[name]
  return pp and pp.default_value or 0
end
local function allowed(recipe, proto)
  local conds = recipe.surface_conditions
  if not conds then return true end
  for _, c in pairs(conds) do
    local v = prop_value(proto, c.property)
    if (c.min and v < c.min) or (c.max and v > c.max) then return false end
  end
  return true
end

-- станки по категориям рецептов (данные прототипов, у всех одинаково): пак, чей станок работает только на
-- некоторых планетах (электромагнитный завод, биокамера...), привязан к этим планетам, даже если рецепт не ограничен
local MACHINES = nil
local function machines_for(category)
  if not MACHINES then
    MACHINES = {}
    for _, t in ipairs({"assembling-machine", "furnace", "rocket-silo"}) do
      for _, m in pairs(prototypes.get_entity_filtered{{filter = "type", type = t}}) do
        local ok, cats = pcall(function() return m.crafting_categories end)
        if ok and cats then
          for c in pairs(cats) do MACHINES[c] = MACHINES[c] or {}; table.insert(MACHINES[c], m) end
        end
      end
    end
  end
  return MACHINES[category]
end
-- категории рецепта: в 2.0 одна (category), в 2.1 список (categories)
local function recipe_categories(r)
  local ok, cats = pcall(function() return r.categories end)
  if ok and cats then return cats end
  local ok2, c = pcall(function() return r.category end)
  return (ok2 and c) and {c} or {}
end
local function machine_ok(recipe, proto)
  local cats = recipe_categories(recipe)
  if #cats == 0 then return true end
  for _, cat in ipairs(cats) do
    local list = machines_for(cat)
    if not list then return true end
    for _, m in ipairs(list) do if allowed(m, proto) then return true end end
  end
  return false
end

local function visible_planets()
  local planets, n = {}, 0
  for name, pl in pairs(game.planets) do
    if not pl.prototype.hidden then planets[name] = pl.prototype; n = n + 1 end
  end
  return planets, n
end

-- ближайшая технология planet-discovery в предпосылках технологий, открывающих эти рецепты
local function tech_planet(recipe_names, planets)
  local unlocks = {}
  for _, t in pairs(prototypes.technology) do
    for _, ef in pairs(t.effects or {}) do
      if ef.type == "unlock-recipe" and recipe_names[ef.recipe] then unlocks[#unlocks + 1] = t end
    end
  end
  if #unlocks == 0 then return nil end
  local seen, frontier, depth = {}, unlocks, 0
  while #frontier > 0 and depth < 12 do
    local found = {}
    for _, t in ipairs(frontier) do
      local name = string.match(t.name, "^planet%-discovery%-(.+)$")
      if name and planets[name] then found[name] = true end
    end
    local n, only = 0, nil
    for k in pairs(found) do n = n + 1; only = k end
    if n == 1 then return only end
    if n > 1 then return nil end              -- неоднозначно
    local nxt = {}
    for _, t in ipairs(frontier) do
      for pname, pre in pairs(t.prerequisites or {}) do
        if not seen[pname] then seen[pname] = true; nxt[#nxt + 1] = pre end
      end
    end
    frontier, depth = nxt, depth + 1
  end
  return nil
end

local function static_info()
  if STATIC then return STATIC end
  local planets, n_planets = visible_planets()
  local makes, rnames = {}, {}
  for _, pack in ipairs(M.science_names()) do makes[pack] = {}; rnames[pack] = {} end
  for _, r in pairs(prototypes.recipe) do
    local recycling = false
    for _, cat in ipairs(recipe_categories(r)) do if string.find(cat, "recycling", 1, true) then recycling = true end end
    if not r.hidden and not recycling then
      for _, pr in pairs(r.products or {}) do
        if pr.type == "item" and makes[pr.name] then table.insert(makes[pr.name], r); rnames[pr.name][r.name] = true end
      end
    end
  end
  STATIC = {}
  for pack, recipes in pairs(makes) do
    local info = {cond = {}, space_only = false, tech = nil, home = nil}
    if #recipes > 0 then
      local where, n = {}, 0
      for pname, proto in pairs(planets) do
        for _, r in ipairs(recipes) do
          if allowed(r, proto) and machine_ok(r, proto) then where[pname] = true; n = n + 1; break end
        end
      end
      if n == 0 then info.space_only = true
      elseif n <= 2 and n < n_planets then info.cond = where end
      info.tech = tech_planet(rnames[pack], planets)
    end
    local ok, loc = pcall(function() return prototypes.item[pack].default_import_location end)
    local home = ok and loc and (type(loc) == "string" and loc or loc.name) or nil
    if home and home ~= "nauvis" and planets[home] then info.home = home end
    STATIC[pack] = info
  end
  return STATIC
end

-- прогрев: «родная наука» считается заранее, пока никто не смотрит (только прототипы, в storage ничего не пишем)
function M.warm() static_info() end

-- где крафтился каждый пак: {пак = {планета = число}, total}
local function crafted_where()
  local out = {}
  for _, s in pairs(game.surfaces) do
    if s.valid and s.planet and not s.planet.prototype.hidden then
      local ok, stats = pcall(function() return game.forces.player.get_item_production_statistics(s) end)
      if ok and stats then
        for _, pack in ipairs(M.science_names()) do
          local ok2, n = pcall(stats.get_input_count, pack)
          if ok2 and n and n > 0 then
            out[pack] = out[pack] or {total = 0, by = {}}
            out[pack].total = out[pack].total + n
            out[pack].by[s.planet.prototype.name] = n
          end
        end
      end
    end
  end
  return out
end

-- баллы по каждой паре пак/планета; обновляются раз в несколько минут, лежат в storage (одинаково у всех)
function M.recompute_native()
  local st = static_info()
  local crafted = crafted_where()
  local scores = {}          -- scores[планета][пак] = {points, strong, why = {...}}
  local function add(planet, pack, pts, strong, why)
    scores[planet] = scores[planet] or {}
    local e = scores[planet][pack] or {points = 0, strong = false, why = {}}
    scores[planet][pack] = e
    e.points = e.points + pts
    e.strong = e.strong or strong
    e.why[#e.why + 1] = why
  end
  for pack, info in pairs(st) do
    for planet in pairs(info.cond) do add(planet, pack, 4, true, "cond") end
    local c = crafted[pack]
    if c and c.total >= 10 then
      for planet, n in pairs(c.by) do if n / c.total >= 0.6 then add(planet, pack, 3, true, "craft") end end
    end
    if info.tech then add(info.tech, pack, 2, false, "tech") end
    if info.home then add(info.home, pack, 1, false, "home") end
  end
  local native, orbit = {}, {}
  for planet, packs in pairs(scores) do
    for pack, e in pairs(packs) do
      if e.points >= 4 and e.strong then
        native[planet] = native[planet] or {}
        table.insert(native[planet], pack)
      end
    end
  end
  -- паки только для орбиты: домашняя планета и дерево совпали, своей наземной науки у планеты нет
  for pack, info in pairs(st) do
    if info.space_only and info.home and info.tech == info.home and not native[info.home] then
      orbit[info.home] = orbit[info.home] or {}
      table.insert(orbit[info.home], pack)
    end
  end
  for planet, packs in pairs(orbit) do
    native[planet] = packs
    for _, pk in ipairs(packs) do
      scores[planet][pk] = scores[planet][pk] or {points = 0, why = {}}
      scores[planet][pk].orbit = true
    end
  end
  -- Nauvis: наука базы — своя (сигналы выше не отличают её от «делается везде»)
  local nv = {}
  M.science_names()
  for _, n in ipairs({"automation-science-pack", "logistic-science-pack", "military-science-pack", "chemical-science-pack",
    "production-science-pack", "utility-science-pack"}) do
    if SET[n] then nv[#nv + 1] = n end
  end
  if #nv > 0 then
    native.nauvis = nv
    scores.nauvis = scores.nauvis or {}
    for _, n in ipairs(nv) do scores.nauvis[n] = scores.nauvis[n] or {points = 4, strong = true, why = {"home"}} end
  end
  for _, list in pairs(native) do table.sort(list) end
  local d = C.D()
  d.native = native
  d.native_scores = scores
end

-- итоговый список планеты: сначала правка админа, потом автоопределение
function M.native(key)
  local d = C.D()
  if not d.native then M.recompute_native() end
  local ov = d.cfg.native_override and d.cfg.native_override[key]
  if ov then
    local list = {}
    for _, pack in ipairs(M.science_names()) do if ov[pack] then list[#list + 1] = pack end end
    return list, true
  end
  return d.native[key] or {}, false
end
function M.is_orbital(key, pack)
  local d = C.D()
  local sc = d.native_scores and d.native_scores[key] and d.native_scores[key][pack]
  if sc and sc.orbit then return true end
  local info = static_info()[pack]
  return info and info.space_only or false
end
function M.why(key, pack)
  local d = C.D()
  local sc = d.native_scores and d.native_scores[key] and d.native_scores[key][pack]
  return sc
end

-- этот пак делали на какой-нибудь платформе?
local function made_in_orbit(pack)
  for _, s in pairs(game.surfaces) do
    if s.valid and s.platform then
      local ok, n = pcall(function() return game.forces.player.get_item_production_statistics(s).get_input_count(pack) end)
      if ok and n and n > 0 then return true end
    end
  end
  return false
end

function M.totals(surface)
  local stats = player_force().get_item_production_statistics(surface)
  local out = 0
  for _, v in pairs(stats.input_counts) do out = out + v end
  -- наука: все виды паков, СДЕЛАННЫХ здесь (все качества); привезённые и съеденные лабами не считаются
  local sci = 0
  local counts = stats.input_counts
  for _, name in ipairs(M.science_names()) do
    local n = counts[name]
    if type(n) == "table" then local s = 0 for _, v in pairs(n) do s = s + v end n = s end
    if n then sci = sci + n end
  end
  return out, sci
end

-- паки, выпущенные на этой поверхности: {имя = число}
local function planet_packs(surface)
  local stats = player_force().get_item_production_statistics(surface)
  local out = {}
  for _, name in ipairs(M.science_names()) do
    local ok, n = pcall(stats.get_input_count, name)
    if ok and n and n > 0 then out[name] = n end
  end
  return out
end

-- шаг науки планеты: готов ли, список {пак, готов}
function M.science_state(key)
  local st = C.PL(key)
  local nat = M.native(key)
  local list = {}
  if #nat == 0 then
    return st.science ~= nil, list
  end
  local all = true
  for _, pack in ipairs(nat) do
    local ok = st.packs and st.packs[pack] ~= nil
    if not ok and M.is_orbital(key, pack) and made_in_orbit(pack) then
      st.packs = st.packs or {}
      st.packs[pack] = game.tick
      ok = true
    end
    list[#list + 1] = {pack, ok}
    if not ok then all = false end
  end
  return all, list
end

local function planet_silo(surface)
  for _, e in pairs(surface.find_entities_filtered{type = "rocket-silo", force = player_force()}) do
    if e.valid and e.energy > 0 then return e end
  end
  return nil
end

local function top_builder(key)
  local t = C.D().pbuilt[key]
  local best, n = nil, 0
  if t then for name, c in pairs(t) do if c > n then best, n = name, c end end end
  return best
end

function M.check(surface, silent)
  if not C.RP(surface) then return end
  local key = surface.planet.prototype.name
  local st = C.PL(key)
  st.packs = st.packs or {}
  local made = planet_packs(surface)
  for name in pairs(made) do
    if not st.packs[name] then st.packs[name] = game.tick end
    if not st.science then st.science = game.tick; st.pack = name end
  end
  -- планеты, освоенные старой версией с частью родной науки
  local sci_done = M.science_state(key)
  if st.mastered and not sci_done then st.mastered = nil end
  if st.mastered then return end
  if not st.silo then
    local silo = planet_silo(surface)
    if silo then st.silo = game.tick; st.silo_name = silo.name end
  end
  if sci_done and st.silo then
    st.mastered = game.tick
    st.by = top_builder(key)
    if not silent and C.S("tr-planet-mastered") then
      local done = C.count_mastered()
      local icons = ""
      local nat = M.native(key)
      if #nat == 0 then icons = "[item=" .. st.pack .. "]" else for _, pk in ipairs(nat) do icons = icons .. "[item=" .. pk .. "]" end end
      local msg = {"tr-msg.mastered", C.place(surface), icons,
        st.by and {"tr-msg.mastered-by", st.by} or "", done, C.planets_in_game()}
      C.send("mastered", msg, {planet = C.place(surface), science = icons, builder = st.by or "-", done = done,
        total = C.planets_in_game()}, {0.55, 1, 0.65}, nil, {"tr-msg.mastered-short", C.place(surface), st.by or "-"})
    end
    if st.by and game.get_player(st.by) then C.check_titles(game.get_player(st.by)) end
  end
end

function M.check_all(silent)
  M.recompute_native()
  for _, s in pairs(game.surfaces) do M.check(s, silent) end
  C.team_check("mastered", (C.count_mastered()), silent)
end

function M.on_rocket_launched(e)
  local silo = e.rocket_silo
  if silo and silo.valid and C.RP(silo.surface) then
    local st = C.PL(silo.surface.planet.prototype.name)
    st.rockets = (st.rockets or 0) + 1
    if not st.silo then st.silo = game.tick end
    st.silo_name = st.silo_name or silo.name
    M.check(silo.surface, false)
  end
end

---------------------------------------------------------------- снимки / живое / отчёт
function M.snapshot_all()
  for _, s in pairs(game.surfaces) do
    if C.RP(s) then
      local st = C.PL(s.planet.prototype.name)
      if not st.snap or not st.base then
        local out, sci = M.totals(s)
        st.snap = st.snap or {out = out, sci = sci, rockets = st.rockets or 0, tick = game.tick}
        st.base = st.base or {out = out, sci = sci, tick = game.tick}
      end
    end
  end
end

-- Рекорды — это ТЕМП (предметов в час игрового времени), поэтому смены любой длины сравниваются честно.
-- Смена идёт в зачёт рекорда, только если длилась хотя бы половину обычной
local HOUR = 216000
local function rate(n, ticks) if ticks <= 0 then return 0 end return n / (ticks / HOUR) end
M.rate = rate
-- «+12%» / «-8%»: изменение темпа к прошлой закрытой смене
function M.vs_text(v) return (v >= 0 and "+" or "-") .. math.abs(v) .. "%" end

-- выпуск с начала смены (охват shift) или с установки (total), ничего не трогая
function M.live(scope)
  local rows = {}
  for _, s in pairs(game.surfaces) do
    if C.RP(s) then
      local st = C.PL(s.planet.prototype.name)
      local from = scope == "total" and st.base or st.snap
      if from then
        local out, sci = M.totals(s)
        local dout = math.max(0, out - from.out)
        local ticks = game.tick - (from.tick or game.tick)
        local load, vs = nil, nil
        -- темп сравниваем только для идущей смены и не раньше 10 минут (раньше слишком шумно)
        if scope ~= "total" and ticks >= 36000 then
          local pace = rate(dout, ticks)
          if (st.record_rate or 0) > 0 then load = math.floor(pace / st.record_rate * 100 + 0.5) end
          -- с прошлой закрытой сменой
          local prev = st.last and st.last.rate
          if prev and prev > 0 then vs = math.floor((pace / prev - 1) * 100 + 0.5) end
        end
        rows[#rows + 1] = {s = s, key = s.planet.prototype.name, out = dout, sci = math.max(0, sci - from.sci),
          load = load, vs = vs, ticks = ticks, record_rate = st.record_rate}
      end
    end
  end
  table.sort(rows, function(a, b) return a.out > b.out end)
  return rows
end

-- закрывает смену на каждой планете; возвращает отчёт в чат (или nil)
function M.close_shift()
  local rows = {}
  local R = C.D().records
  for _, s in pairs(game.surfaces) do
    if C.RP(s) then
      local key = s.planet.prototype.name
      local st = C.PL(key)
      local out, sci = M.totals(s)
      if st.snap then
        local dout = math.max(0, out - st.snap.out)
        local dsci = math.max(0, sci - st.snap.sci)
        local drk = math.max(0, (st.rockets or 0) - (st.snap.rockets or 0))
        local ticks = game.tick - (st.snap.tick or game.tick)
        local r_now = rate(dout, ticks)
        local rated = (st.record_rate or 0) > 0
        local full = ticks >= C.shift_ticks() * 0.5
        local load = rated and math.floor(r_now / st.record_rate * 100 + 0.5) or 0
        -- лучший темп из последних 10 полных смен (старый рекорд не висит вечно после перестройки базы)
        if full then
          st.rate_hist = st.rate_hist or {}
          if #st.rate_hist == 0 and (st.record_rate or 0) > 0 then st.rate_hist[1] = st.record_rate end
          st.rate_hist[#st.rate_hist + 1] = r_now
          while #st.rate_hist > 10 do table.remove(st.rate_hist, 1) end
          local best = 0
          for _, v in ipairs(st.rate_hist) do if v > best then best = v end end
          st.record_rate = best
        end
        -- изменение темпа к предыдущей смене (последней закрытой), для отчёта
        local prev = st.last and st.last.rate
        local vs = nil
        if prev and prev > 0 then vs = math.floor((r_now / prev - 1) * 100 + 0.5) end
        st.last = {out = dout, sci = dsci, rockets = drk, load = load, tick = game.tick, rated = rated, rate = r_now, vs = vs}
        st.history = st.history or {}
        st.history[#st.history + 1] = dout
        while #st.history > C.S("tr-s-history") do table.remove(st.history, 1) end
        R.planet_shift = R.planet_shift or {n = 0}
        if dout > R.planet_shift.n then R.planet_shift = {n = dout, planet = key, tick = game.tick} end
        rows[#rows + 1] = {s = s, out = dout, sci = dsci, rk = drk, load = load, rated = rated, vs = vs}
      end
      st.snap = {out = out, sci = sci, rockets = st.rockets or 0, tick = game.tick}
    end
  end
  if #rows == 0 or not C.S("tr-planet-report") then return nil end

  table.sort(rows, function(a, b) return a.out > b.out end)
  local active = {}
  for _, r in ipairs(rows) do if r.out >= C.S("tr-s-min-output") then active[#active + 1] = r end end
  if #active == 0 then return {"tr-msg.report-quiet"} end

  local function stats_of(r)
    local t = {"", {"tr-msg.report-output", C.n(r.out)}}
    if r.sci > 0 then t[#t + 1] = {"tr-msg.report-science", C.n(r.sci)} end
    if r.rk > 0 then t[#t + 1] = {"tr-msg.report-rockets", r.rk} end
    return t
  end
  local msg = {"", {"tr-msg.report-header"}}
  local top = active[1]
  -- кто больше всех построил на этой поверхности за смену
  local function builder(r)
    local key = r.s.planet and r.s.planet.prototype.name
    local bn, bv = nil, 0
    for name, v in pairs(((C.D().pbuilt_shift or {})[key]) or {}) do if v > bv then bn, bv = name, v end end
    return bn, bv
  end
  local bn, bv = builder(top)
  msg[#msg + 1] = {"", "\n  ", {"tr-msg.report-top", C.place(top.s), stats_of(top), bn and {"tr-msg.report-builder", bn, C.n(bv)} or ""}}
  -- кто вырос и кто упал к прошлой смене; потом простаивающие планеты (далеко ниже своего лучшего темпа)
  local with_vs = {}
  for _, r in ipairs(active) do if r.vs then with_vs[#with_vs + 1] = r end end
  if #with_vs > 0 then
    table.sort(with_vs, function(a, b) if a.vs ~= b.vs then return a.vs > b.vs end return a.out > b.out end)
    local best, worst = with_vs[1], with_vs[#with_vs]
    if best.vs > 0 then
      local bb = builder(best)
      msg[#msg + 1] = {"", "\n  ", {"tr-msg.report-grew", C.place(best.s), M.vs_text(best.vs)}, bb and {"tr-msg.report-by", bb} or ""}
    end
    if worst ~= best and worst.vs <= -20 then
      msg[#msg + 1] = {"", "\n  ", {"tr-msg.report-fell", C.place(worst.s), M.vs_text(worst.vs)}}
    end
  else
    msg[#msg + 1] = {"", "\n  ", {"tr-msg.report-no-records"}}
  end
  local idle = {}
  for _, r in ipairs(rows) do
    if r.rated and r.load < C.S("tr-s-idle-percent") and #idle < 6 then idle[#idle + 1] = {"", C.place(r.s), " " .. r.load .. "%"} end
  end
  if #idle > 0 then msg[#msg + 1] = {"", "\n  ", {"tr-msg.report-idle", C.join(idle)}} end
  local rest = {}
  for i = 2, math.min(6, #active) do
    local r = active[i]
    local rb = builder(r)
    rest[#rest + 1] = {"", C.place(r.s), " ", C.n(r.out), r.vs and (" (" .. M.vs_text(r.vs) .. ")") or "", rb and {"tr-msg.report-by", rb} or ""}
  end
  if #rest > 0 then msg[#msg + 1] = {"", "\n  ", {"tr-msg.report-rest", C.join(rest, " · ")}} end
  return msg
end

-- все виды паков, выпущенные на этой поверхности (за всю игру), больше всего первыми
function M.made_here(surface)
  local out = {}
  local ok, stats = pcall(game.forces.player.get_item_production_statistics, surface)
  if not (ok and stats) then return out end
  local counts = stats.input_counts
  for _, name in ipairs(M.science_names()) do
    local n = counts[name]
    if type(n) == "table" then local s = 0 for _, v in pairs(n) do s = s + v end n = s end
    if n and n > 0 then out[#out + 1] = {name, n} end
  end
  table.sort(out, function(a, b) return a[2] > b[2] end)
  return out
end

return M
