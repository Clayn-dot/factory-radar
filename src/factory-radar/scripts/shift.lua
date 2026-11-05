-- Factory Radar: таймер смены и сводка в конце каждой смены
local C = require("scripts.core")
local P = require("scripts.planets")
local RS = require("scripts.research")
local CB = require("scripts.combat")
local M = {}

local function period() return C.shift_ticks() end

-- UPS Guard (если стоит) сообщает, когда у него обслуживание; смена кончается в тот же момент,
-- цикл общий для двух модов. Делится только расписание, не статистика
local function ups()
  if not (remote.interfaces["ups-guard"] and remote.interfaces["ups-guard"].schedule) then return nil end
  local ok, sch = pcall(remote.call, "ups-guard", "schedule")
  if ok and type(sch) == "table" and sch.minutes_left and sch.cycles then return sch end
  return nil
end
M.ups = ups

function M.init()
  local d = C.D()
  d.next_shift = d.next_shift or (game.tick + period())
end

function M.minutes_left()
  local d = C.D()
  local sch = ups()
  if sch then return sch.minutes_left end
  return math.max(0, math.ceil(((d.next_shift or game.tick) - game.tick) / 3600))
end

-- наш счёт «кто сделал больше всех»: доля игрока от общего по команде за смену в четырёх делах
-- (убийства, постройки, добыча, путь). Возвращает ник и
-- список {k, pct} двух главных дел. Никто ничего не сделал за смену — нет кандидата
local PICK_KEYS = {"kills", "built", "mined", "walk"}
function M.pick()
  local d = C.D()
  local names, tot = {}, {}
  for name, r in pairs(d.shift) do
    names[#names + 1] = name
    for _, k in ipairs(PICK_KEYS) do tot[k] = (tot[k] or 0) + (r[k] or 0) end
  end
  -- один игрок за смену: кандидат он сам, если сейчас на сервере; ни одного — нет кандидата
  if #names == 0 then return nil end
  if #names == 1 then
    local pl = game.get_player(names[1])
    if not (pl and pl.connected) then return nil end
  end
  table.sort(names)
  local best, best_score, best_shares
  for _, name in ipairs(names) do
    local r = d.shift[name]
    local score, shares = 0, {}
    for _, k in ipairs(PICK_KEYS) do
      if (tot[k] or 0) > 0 then
        local s = (r[k] or 0) / tot[k]
        shares[#shares + 1] = {k = k, pct = math.floor(s * 100 + 0.5), s = s}
        score = score + s
      end
    end
    if score > 0 and (not best_score or score > best_score) then best, best_score, best_shares = name, score, shares end
  end
  if not best then return nil end
  table.sort(best_shares, function(a, b) if a.s ~= b.s then return a.s > b.s end return a.k < b.k end)
  local why = {}
  for i = 1, math.min(2, #best_shares) do
    if best_shares[i].pct > 0 then why[#why + 1] = {k = best_shares[i].k, pct = best_shares[i].pct} end
  end
  return best, why
end

function M.why_ls(why)
  local out = {}
  for _, w in ipairs(why or {}) do out[#out + 1] = {"tr-gui.mvp-why-item", {"tr-gui.mvp-cat-" .. w.k}, w.pct} end
  return C.join(out, ", ")
end

function M.mvp_leaders()
  local votes = {}
  for _, target in pairs(C.D().mvp) do votes[target] = (votes[target] or 0) + 1 end
  local best = 0
  for _, n in pairs(votes) do if n > best then best = n end end
  local names = {}
  if best > 0 then for name, n in pairs(votes) do if n == best then names[#names + 1] = name end end end
  table.sort(names)
  return names, best, votes
end

local EN = require("scripts.energy")

local function summary()
  local d = C.D()
  local parts = {}
  local k, kv = C.leader(d.shift, "kills")
  if k then parts[#parts + 1] = {"tr-msg.shift-killed", k, C.n(kv)} end
  local b, bv = C.leader(d.shift, "built")
  if b then parts[#parts + 1] = {"tr-msg.shift-built", b, C.n(bv)} end
  local w, wv = C.leader(d.shift, "walk")
  if w then parts[#parts + 1] = {"tr-msg.shift-walked", w, C.km(wv)} end
  local de, dv = C.leader(d.shift, "deaths")
  if de then parts[#parts + 1] = {"tr-msg.shift-died", de, dv} end

  local lost, lost_top, lost_top_n = 0, nil, 0
  for key, n in pairs(d.shift_plost) do
    lost = lost + n
    if n > lost_top_n then lost_top, lost_top_n = key, n end
  end
  local mined = 0
  for _, r in pairs(d.shift) do mined = mined + (r.mined or 0) end
  local m = C.leader(d.shift, "mined")
  local ff, ffv = C.leader(d.shift, "ff")
  local destr = {}
  if lost > 0 then
    destr[#destr + 1] = {"tr-msg.shift-lost", C.n(lost), lost_top and {"tr-msg.shift-lost-top", C.planet_ls(lost_top), C.n(lost_top_n)} or ""}
  end
  if mined > 0 and m then destr[#destr + 1] = {"tr-msg.shift-mined", C.n(mined), m} end
  if ff then destr[#destr + 1] = {"tr-msg.shift-ff", ff, ffv} end

  -- MVP: больше всех голосов; поровну — ничья (все MVP); никто не голосовал — MVP нет
  local mvps, mvp_n, votes = M.mvp_leaders()
  local pick, pick_why = M.pick()
  local auto = false
  if #mvps == 0 and pick then mvps, mvp_n, auto = {pick}, 0, true end   -- никто не голосовал: MVP по нашему счёту
  local mvp = #mvps > 0 and C.join(mvps) or nil
  local nobody_voted = (#mvps == 0)
  -- «непризнанный гений»: голоса были, а нашего кандидата никто не выбрал
  if not auto and pick and next(votes) and not votes[pick] then
    C.pstat_add(pick, "genius_missed", 1)
    C.journal({"tr-msg.genius-j", pick, M.why_ls(pick_why)})
  end
  if auto then C.journal({"tr-msg.mvp-auto-j", pick, M.why_ls(pick_why)}) end
  -- проблемы с энергией за смену (в чат в момент не пишутся)
  local power_parts = {}
  for i, t in ipairs(EN.trouble_since(d.shift_start or 0)) do
    if i <= 3 then power_parts[#power_parts + 1] = {"tr-msg.shift-power-item", C.planet_ls(t.key), t.n, t.mins} end
  end

  -- рекорды
  local R = d.records
  local function rec_best(key, who, n) R[key] = R[key] or {n = 0}; if who and n > R[key].n then R[key] = {n = n, who = who, tick = game.tick} end end
  rec_best("shift_kills", k, kv or 0)
  rec_best("shift_built", b, bv or 0)
  rec_best("shift_deaths", de, dv or 0)
  R.shift_lost = R.shift_lost or {n = 0}
  if lost > R.shift_lost.n then R.shift_lost = {n = lost, tick = game.tick} end

  -- личные лучшие за смену, победы MVP и сыгранные смены (для достижений)
  for name, r in pairs(d.shift) do
    d.pbest[name] = d.pbest[name] or {}
    for _, k in ipairs({"built", "walk", "kills", "nests"}) do
      if (r[k] or 0) > (d.pbest[name][k] or 0) then d.pbest[name][k] = r[k] end
    end
  end
  for _, pl in pairs(game.connected_players) do C.pstat_add(pl.name, "shifts", 1) end
  -- статистика для смешных званий: кто чаще всех умирал, кто стоял в АФК к концу смены, кто ни разу не голосовал за MVP
  if de and (dv or 0) > 0 then C.pstat_add(de, "death_leader", 1) end
  d.novote = d.novote or {}
  for _, pl in pairs(game.connected_players) do
    if pl.afk_time > 5 * 3600 then C.pstat_add(pl.name, "afk_end", 1) end
    local run = d.mvp[pl.name] and 0 or (d.novote[pl.name] or 0) + 1
    d.novote[pl.name] = run
    local ps = C.D().pstat[pl.name] or {}
    if run > (ps.novote_best or 0) then C.D().pstat[pl.name] = ps; ps.novote_best = run end
  end
  for _, name in ipairs(mvps) do C.pstat_add(name, "mvp_wins", 1) end
  for _, pl in pairs(game.connected_players) do C.check_titles(pl) end
  for name in pairs(d.shift) do local pl = game.get_player(name); if pl then C.check_ach(pl) end end
  for _, pl in pairs(game.connected_players) do C.check_ach(pl) end
  -- последние 10 выборов MVP (показываются свёрнуто внизу сводки)
  d.mvp_hist = d.mvp_hist or {}
  d.mvp_hist[#d.mvp_hist + 1] = {tick = game.tick, names = mvps, n = mvp_n or 0, auto = auto or nil, pick = pick, why = auto and pick_why or nil}
  while #d.mvp_hist > 10 do table.remove(d.mvp_hist, 1) end
  d.shift, d.shift_plost, d.mvp = {}, {}, {}
  if C.hooks.popup_close then C.hooks.popup_close("mvp") end
  d.ldest_shift = {}

  local research_line = RS.close_shift()
  local combat_line = CB.close_shift()
  if not C.S("tr-shift-summary") then return nil end
  local players_online = 0
  for _ in pairs(game.connected_players) do players_online = players_online + 1 end
  local show_no_mvp = nobody_voted and players_online >= 2
  if #parts == 0 and #destr == 0 and not mvp and not research_line and not combat_line and #power_parts == 0 and not show_no_mvp then return nil end
  local msg = {"", {"tr-msg.shift-header"}, #parts > 0 and C.join(parts) or {"tr-msg.shift-quiet"}}
  if #destr > 0 then msg[#msg + 1] = {"", "\n  ", {"tr-msg.shift-destruction", C.join(destr, "; ")}} end
  if combat_line then msg[#msg + 1] = combat_line end
  if research_line then msg[#msg + 1] = research_line end
  if #power_parts > 0 then msg[#msg + 1] = {"", "\n  ", {"tr-msg.shift-power", C.join(power_parts, "; ")}} end
  if show_no_mvp then msg[#msg + 1] = {"", "\n  ", {"tr-msg.shift-mvp-none"}} end
  if auto then msg[#msg + 1] = {"", "\n  ", {"tr-msg.shift-mvp-auto", mvp, M.why_ls(pick_why)}}
  elseif mvp then msg[#msg + 1] = {"", "\n  ", {#mvps > 1 and "tr-msg.shift-mvp-tie" or "tr-msg.shift-mvp", mvp, mvp_n}} end
  C.journal(mvp and {"tr-msg.shift-closed", mvp} or {"tr-msg.shift-closed-plain"})
  return msg
end

function M.close()
  local d = C.D()
  local s = summary()
  if s then C.send("shift", s, nil, {1, 0.9, 0.6}, nil, false) end
  local pr = P.close_shift()
  if pr then C.send("report", pr, nil, {0.75, 0.95, 1}, nil, false) end
  d.pbuilt_shift = {}          -- кто где построил: счёт по смене
  d.next_shift = game.tick + period()
  d.shift_start = game.tick
  d.mvp_reminded = nil
end

local function remind_mvp()
  local d = C.D()
  local before = C.S("tr-s-mvp-reminder")
  if before <= 0 or d.mvp_reminded then return end
  if M.minutes_left() > before then return end
  d.mvp_reminded = true
  local others = 0
  for _ in pairs(game.connected_players) do others = others + 1 end
  if others < 2 then return end           -- голосовать не за кого
  local pk, pw = M.pick()
  local tail = pk and {"tr-msg.mvp-pick", pk, M.why_ls(pw)} or ""
  C.send("mvp", {"tr-msg.mvp-reminder", M.minutes_left(), (C.online_numbered()), tail}, {minutes = M.minutes_left()}, {1, 0.85, 0.5}, nil, false)
  if C.hooks.popup then for _, pl in pairs(game.connected_players) do C.hooks.popup(pl, "mvp") end end
end

-- раз в минуту
function M.tick()
  local d = C.D()
  if not d.next_shift then M.init() end
  local sch = ups()
  if sch then
    d.ups_period = sch.period_minutes
    d.next_shift = game.tick + sch.minutes_left * 3600
    if d.ups_cycles == nil then d.ups_cycles = sch.cycles end
    if sch.cycles ~= d.ups_cycles then
      d.ups_cycles = sch.cycles
      M.close()
      d.next_shift = game.tick + sch.minutes_left * 3600
      return
    end
  else
    d.ups_period, d.ups_cycles = nil, nil
    -- настройку могли уменьшить
    if d.next_shift - game.tick > period() then d.next_shift = game.tick + period() end
    if game.tick >= d.next_shift then M.close() return end
  end
  remind_mvp()
end

return M
