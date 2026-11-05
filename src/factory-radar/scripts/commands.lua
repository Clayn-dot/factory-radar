-- Factory Radar: чат-команды (для всех, /tr-shift-now только админ)
local C = require("scripts.core")
local RU = require("scripts.roulette")
local CEN = require("scripts.census")
local P = require("scripts.planets")
local RS = require("scripts.research")
local WH = require("scripts.where")
local SH = require("scripts.shift")
local G = require("scripts.gui")
local CBM = require("scripts.combat")
local ZAP = require("scripts.zap")
local function require_combat() return CBM end
local M = {}

local function io(cmd)
  local p = cmd.player_index and game.get_player(cmd.player_index)
  return p, function(m)
    if p then p.print(m) else
      if rcon then pcall(rcon.print, m) end
      log(serpent.line(m))
    end
  end
end
local function arg(cmd) return cmd.parameter and cmd.parameter:match("^%s*(.-)%s*$") or "" end

local function cmd_where(cmd)
  local p, out = io(cmd)
  local only = arg(cmd)
  local rows = WH.rows(p, only ~= "" and only or nil)
  if #rows == 0 then out(only ~= "" and {"tr-cmd.no-player", only} or {"tr-cmd.nobody"}) return end
  for _, r in ipairs(rows) do
    out(r.body and {"", r.caption, "  ", C.gps(r.body.position, r.body.surface)} or r.caption)
    if r.look_caption then out({"", "     ", r.look_caption}) end
  end
end

local function cmd_top(cmd)
  local p, out = io(cmd)
  local a = arg(cmd)
  local shift = a:find("смен") or a:find("shift")
  local d = C.D()
  local tbl = shift and d.shift or d.total
  out(shift and {"tr-cmd.top-shift"} or {"tr-cmd.top-total"})
  local any = false
  for _, c in ipairs(G.COLS) do
    local names = C.sorted_names(tbl, c.key)
    local parts = {}
    for i = 1, math.min(5, #names) do
      local v = tbl[names[i]][c.key] or 0
      if v > 0 then parts[#parts + 1] = {"", names[i], " ", c.f(v)} end
    end
    if #parts > 0 then any = true; out({"", {"tr-gui.col-" .. c.key}, ": ", C.join(parts, " | ")}) end
  end
  if not any then out({"tr-cmd.empty"}) end
end

local function cmd_now(cmd)
  local p, out = io(cmd)
  local d = C.D()
  local rd, rt = RS.progress()
  local online = 0
  for _ in pairs(game.connected_players) do online = online + 1 end
  out({"tr-cmd.now-head", online, SH.minutes_left(), rt > 0 and math.floor(rd / rt * 100) or 0, (C.count_mastered()), C.planets_in_game()})
  local parts = {}
  for _, c in ipairs({{"kills", C.n}, {"built", C.n}, {"mined", C.n}, {"deaths", C.n}}) do
    local who, v = C.leader(d.shift, c[1])
    if who then parts[#parts + 1] = {"", {"tr-gui.col-" .. c[1]}, " — ", who, " (", c[2](v), ")"} end
  end
  out({"tr-cmd.now-leaders", #parts > 0 and C.join(parts) or {"tr-cmd.quiet"}})
  local rows = P.live()
  if #rows > 0 then
    local pl = {}
    for i = 1, math.min(5, #rows) do pl[#pl + 1] = {"", C.place(rows[i].s), " ", C.n(rows[i].out), rows[i].load and (" (" .. rows[i].load .. "%)") or ""} end
    out({"tr-cmd.now-planets", C.join(pl, " · ")})
  end
end

local function cmd_me(cmd)
  local p, out = io(cmd)
  local a = arg(cmd)
  local name = a ~= "" and a or (p and p.name)
  if not name then return end
  local r = C.rec(C.D().total, name)
  local t = C.shown_title(name)
  out({"tr-cmd.me", name, t and {"", " «", C.title_name(t), "»"} or "", C.n(r.kills), C.n(r.built), C.n(r.mined),
    C.n(r.lost), r.deaths, C.km(r.walk), C.km(r.ride), #C.titles_of(name)})
  local ticks, fav = C.best_planet_time(name)
  if fav then out({"tr-gui.card-favorite", C.planet_ls(fav), C.time(ticks)}) end
  local nt = C.next_titles(name, 3)
  if #nt > 0 then
    local parts = {}
    for _, n in ipairs(nt) do parts[#parts + 1] = {"", "«", C.title_name(n.t.id), "» ", math.floor(n.ratio * 100), "%"} end
    out({"tr-cmd.me-next", C.join(parts)})
  end
end

local function cmd_vs(cmd)
  local p, out = io(cmd)
  if not p then return end
  local other = arg(cmd)
  if other == "" then out({"tr-cmd.vs-usage"}) return end
  local d = C.D()
  if not d.total[other] and not game.get_player(other) then out({"tr-cmd.no-player", other}) return end
  local a, b = C.rec(d.total, p.name), C.rec(d.total, other)
  local sa, sb, parts = 0, 0, {}
  for _, c in ipairs({{"kills", C.n}, {"built", C.n}, {"craft", C.n}, {"walk", C.km}, {"ride", C.km}, {"mined", C.n}}) do
    local va, vb = a[c[1]] or 0, b[c[1]] or 0
    if va > vb then sa = sa + 1 elseif vb > va then sb = sb + 1 end
    parts[#parts + 1] = {"", {"tr-gui.col-" .. c[1]}, " ", c[2](va), ":", c[2](vb)}
  end
  if a.deaths < b.deaths then sa = sa + 1 elseif b.deaths < a.deaths then sb = sb + 1 end
  parts[#parts + 1] = {"", {"tr-gui.col-deaths"}, " ", a.deaths, ":", b.deaths}
  out({"tr-cmd.vs", p.name, other, C.join(parts)})
  out({"tr-cmd.vs-score", sa, sb, sa > sb and {"tr-cmd.vs-wins", p.name} or (sb > sa and {"tr-cmd.vs-wins", other} or {"tr-cmd.vs-draw"})})
end

local function cmd_log(cmd)
  local p, out = io(cmd)
  local n = tonumber(arg(cmd)) or 10
  local j = C.D().journal
  if #j == 0 then out({"tr-gui.journal-empty"}) return end
  out({"tr-cmd.log-head"})
  for i = math.max(1, #j - n + 1), #j do out({"", "[", C.clock(j[i].tick), "] ", C.journal_view(j[i].text)}) end
end

local function cmd_mvp(cmd)
  local p, out = io(cmd)
  if not p then return end
  local target = arg(cmd)
  local list, online = C.online_numbered()
  if target == "" then out({"tr-cmd.mvp-list", list}) return end
  -- номер из списка онлайн или имя
  local idx = tonumber(target)
  local tp = (idx and online[idx] and game.get_player(online[idx])) or game.get_player(target)
  if not tp then out({"tr-cmd.no-player", target}) return end
  if tp.name == p.name then out({"tr-cmd.mvp-self"}) return end
  if not tp.connected then out({"tr-cmd.mvp-offline", tp.name}) return end
  C.D().mvp[p.name] = tp.name
  out({"tr-cmd.mvp-ok", tp.name})
end

local function cmd_planets(cmd)
  local p, out = io(cmd)
  local d = C.D()
  out({"tr-cmd.planets-head"})
  local rows = {}
  for _, s in pairs(game.surfaces) do if C.RP(s) then rows[#rows + 1] = s end end
  table.sort(rows, function(a, b) return a.name < b.name end)
  for _, s in ipairs(rows) do
    local key = s.planet.prototype.name
    local st = C.PL(key)
    local first = d.first[key]
    local status
    if st.mastered then
      status = {"tr-cmd.planet-mastered", st.by or {"tr-gui.before-install"}}
    else
      local miss = {}
      local sci_ok, list = P.science_state(key)
      if not sci_ok then
        local icons = ""
        for _, x in ipairs(list) do if not x[2] then icons = icons .. "[item=" .. x[1] .. "]" end end
        miss[#miss + 1] = icons ~= "" and {"tr-cmd.planet-no-packs", icons} or {"tr-cmd.planet-no-science"}
      end
      if not st.silo then miss[#miss + 1] = {"tr-cmd.planet-no-silo"} end
      status = {"tr-cmd.planet-not-mastered", C.join(miss)}
    end
    out({"", C.place(s), " — ", status,
      first and {"tr-cmd.planet-first", first.who == "?" and {"tr-gui.before-install"} or first.who} or "",
      st.last and {"tr-cmd.planet-last", C.n(st.last.out), st.last.rated and {"tr-gui.planet-load", st.last.load} or ""} or ""})
  end
  out({"tr-cmd.planets-total", (C.count_mastered()), #rows, C.planets_in_game()})
end

local function cmd_combat(cmd)
  local p, out = io(cmd)
  local CB = require_combat()
  local s = CB.S()
  out({"tr-cmd.combat-head", C.n(s.total), C.n(s.shift)})
  local parts = {}
  for _, w in ipairs(CB.top(s.weap, 5)) do parts[#parts + 1] = {"", C.weapon_chat(w[1]), " ", C.n(w[2])} end
  if #parts > 0 then out({"tr-cmd.combat-weapons", C.join(parts, " · ")}) end
  local ev = {}
  for i, r in ipairs(CB.active_evo_rows()) do
    if i <= 6 then ev[#ev + 1] = {"", C.planet_ls(r.key), " ", CB.pct(r.now), " (", CB.dpct(r.delta), ")"} end
  end
  if #ev > 0 then out({"tr-cmd.combat-evo", C.join(ev, " · ")}) end
end
local function cmd_zap(cmd)
  local p, out = io(cmd)
  if not p then return end
  local name = arg(cmd)
  if name == "" then out({"tr-zap.usage"}) return end
  local to = game.get_player(name)
  if not to then out({"tr-cmd.no-player", name}) return end
  ZAP.zap(p, to)
end

local function cmd_research(cmd)
  local p, out = io(cmd)
  local rd, rt = RS.progress()
  out({"tr-cmd.research-head", rt > 0 and math.floor(rd / rt * 100) or 0, rd, rt})
  for i, r in ipairs(RS.infinite_rows()) do
    if i > 8 then break end
    out({"", "  [technology=" .. r.tech.name .. "]: ", {"tr-cmd.research-row", r.level, r.shift, r.total}})
  end
end

local function cmd_shift_now(cmd)
  local p, out = io(cmd)
  if p and not p.admin then out({"tr-cmd.admin-only"}) return end
  SH.close()
  if not p then out({"tr-cmd.shift-done"}) end
end

local function cmd_roulette(cmd)
  local p = io(cmd)
  if p then RU.start(p) end
end
local function cmd_zap_lift(cmd)
  local p, out = io(cmd)
  if p and not p.admin then out({"tr-cmd.admin-only"}) return end
  local cfg = C.D().cfg
  local a, b = string.match(arg(cmd), "^%s*(%S*)%s*(%S*)")
  local n, t = tonumber(a), tonumber(b)
  if not n then out({"tr-cmd.zap-lift-now", cfg.zap_lift or 25, cfg.zap_lead or 12}) return end
  cfg.zap_lift = math.max(0, math.min(80, n))
  if t then cfg.zap_lead = math.max(0, math.min(60, t)) end
  out({"tr-cmd.zap-lift-ok", cfg.zap_lift, cfg.zap_lead or 12})
end
local function cmd_in(cmd)
  local p = io(cmd)
  if p then RU.join(p) end
end
local function cmd_census(cmd)
  local p, out = io(cmd)
  if p and not p.admin then out({"tr-cmd.admin-only"}) return end
  out(CEN.start() and {"tr-msg.census-started"} or {"tr-msg.census-running"})
end

function M.register()
  local function add(name, fn) commands.add_command(name, {"tr-cmd.help-" .. name}, C.safe(fn)) end
  add("tr-where", cmd_where)
  add("tr-top", cmd_top)
  add("tr-now", cmd_now)
  add("tr-me", cmd_me)
  add("tr-vs", cmd_vs)
  add("tr-log", cmd_log)
  add("tr-mvp", cmd_mvp)
  add("tr-planets", cmd_planets)
  add("tr-research", cmd_research)
  add("tr-combat", cmd_combat)
  add("tr-zap", cmd_zap)
  add("tr-roulette", cmd_roulette)
  add("tr-in", cmd_in)
  add("tr-zap-lift", cmd_zap_lift)
  add("tr-shift-now", cmd_shift_now)
  add("tr-census", cmd_census)
end

return M
