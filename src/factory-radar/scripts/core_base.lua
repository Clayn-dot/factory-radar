-- Factory Radar: shared state, helpers, titles, team achievements, journal
local C = {}
local SE = require("scripts.compat_se")
C.SE = SE

---------------------------------------------------------------- settings
-- server switches live in the save, admins change them in the window ("Settings" tab)
-- rare numbers are startup settings (main menu, Settings, Mods)
C.CFG = {
  -- features
  {key = "tr-titles", group = "features", default = true},
  {key = "tr-chat-titles", group = "features", default = true},
  {key = "tr-death-tags", group = "features", default = true},
  {key = "tr-afk", group = "features", default = true},
  {key = "tr-zap", group = "features", default = true},
  {key = "tr-space-gate", group = "features", default = true},
  -- what is counted
  {key = "tr-track-robots", group = "tracking", default = true},
  {key = "tr-track-robot-mined", group = "tracking", default = true},
  {key = "tr-track-defense", group = "tracking", default = true},
  {key = "tr-track-ff", group = "tracking", default = true},
  {key = "tr-track-vehicles", group = "tracking", default = true},
}
C.CFG_DEFAULT = {}
for _, c in ipairs(C.CFG) do C.CFG_DEFAULT[c.key] = c.default end

-- personal player settings
C.PCFG = {
  {key = "button", default = true},
  {key = "tag-color", default = true},
  {key = "greet", default = true},
  {key = "intro", default = true},
  {key = "know", default = true},
  {key = "tips", default = true},
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

-- old names of the chat switches, now the message audience decides
C.FEATURE_MSG = {["tr-shift-summary"] = {"shift"}, ["tr-planet-report"] = {"report"},
  ["tr-first-landing"] = {"first-landing"}, ["tr-planet-mastered"] = {"mastered"},
  ["tr-science-milestones"] = {"science-first", "science-milestone"}, ["tr-team"] = {"team"}, ["tr-deaths"] = {"death"}}

-- numbers the admin sets in game; the default until changed
C.NUM_DEFAULT = {["tr-s-zap-cooldown"] = 3, ["tr-s-roulette-cooldown"] = 0, ["tr-s-roulette-fail"] = 5}      -- 0 = the quiz has no rest, it only waits for the running one
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
-- normal shift length in ticks (UPS Guard cycle if present, otherwise our setting)
function C.shift_ticks()
  local d = storage.tr
  if d and d.ups_period then return d.ups_period * 3600 end
  return math.max(3600, math.floor(settings.startup["tr-s-shift-hours"].value * 216000))
end

function C.set(name, value) C.D().cfg[name] = value end

-- "1 Oleg · 2 sleekhead" is the same for everyone (sorted online names), and the names themselves
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

---------------------------------------------------------------- chat messages: who gets them and in what words
-- aud: all (everyone), self (only the one concerned), none (journal only)
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

-- "{player} got {title}" plus parameters, as a localised string
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

-- send to chat by the admin's settings; returns the final text
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

-- planets the admin excluded from statistics
function C.ignored(key) local i = storage.tr and storage.tr.cfg and storage.tr.cfg.ignore return i and i[key] or false end

-- every handler is wrapped: an error must not stop the game for everyone
function C.safe(fn)
  return function(...)
    local ok, err = pcall(fn, ...)
    if not ok then log("Factory Radar error: " .. tostring(err)) end
  end
end

---------------------------------------------------------------- storage
C.COUNTERS = {"kills", "built", "craft", "walk", "ride", "deaths", "mined", "lost", "ff",
  "belts", "rails", "poles", "turrets", "defense", "nests"}

function C.blank()
  local t = {}
  for _, k in pairs(C.COUNTERS) do t[k] = 0 end
  return t
end

-- mod storage; full table check once (and after a reset),
-- because C.D() is called on every enemy death and other hot events
local D_KEYS
local D_VER = 4     -- raise when the table list below changes
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

-- per player and planet counters (walked, died, crafted...): d[tbl][player][planet]
function C.pp_add(tbl, name, surface, n)
  if not C.RP(surface) then return end
  local t = C.D()[tbl]
  t[name] = t[name] or {}
  local key = C.key(surface)
  if not key then return end
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

-- messages with bold main text in chat; the journal shows a regular size copy ("key-j")
local J_ALT = {["tr-msg.ach"] = true, ["tr-msg.first-landing"] = true, ["tr-msg.mastered"] = true,
  ["tr-msg.mastered-short"] = true, ["tr-msg.platform-lost"] = true, ["tr-msg.power-low"] = true,
  ["tr-msg.power-none"] = true, ["tr-msg.power-plat-none"] = true, ["tr-msg.power-plat-low"] = true,
  ["tr-msg.power-plat-empty"] = true, ["tr-msg.science-first"] = true, ["tr-msg.science-milestone"] = true,
  ["tr-msg.shift-mvp"] = true, ["tr-msg.shift-mvp-tie"] = true, ["tr-msg.team"] = true, ["tr-msg.title"] = true}
-- journal entry text as shown: the regular size copy for messages that are bold in chat
-- (works for old entries too)
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

-- to everyone: chat + journal
-- chat to everyone who did not turn this category off in personal settings
function C.broadcast(msg, color, cat)
  for _, p in pairs(game.connected_players) do
    if not cat or C.P(p, "msg-" .. cat) then p.print(msg, {color = color}) end
  end
end

function C.announce(msg, color, journal_text, cat)
  C.broadcast(msg, color, cat)
  C.journal(journal_text or msg)
end

---------------------------------------------------------------- formatting (localised)
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

-- game time as a moment: "14:32" on the first day, "3 d 14:32" from the second (24 h days).
-- LocalisedString: do not join with `..`
function C.clock(tick)
  local m = math.floor(tick / 3600)
  local h = math.floor(m / 60)
  local hhmm = string.format("%02d:%02d", h % 24, m % 60)
  if h < 24 then return hhmm end
  return {"tr.clock-days", math.floor(h / 24), hhmm}
end

-- same with seconds: "14:32:07"
function C.clock_s(tick)
  local sec = math.floor(tick / 60)
  local h = math.floor(sec / 3600)
  local hhmmss = string.format("%02d:%02d:%02d", h % 24, math.floor(sec / 60) % 60, sec % 60)
  if h < 24 then return hhmmss end
  return {"tr.clock-days", math.floor(h / 24), hhmmss}
end

-- is space open? The "Planets" and "Platforms" tabs and everything about planets on "Summary" show once rocket silo or
-- space platform is researched. If the game has no such technologies (or the admin turned the limit off), always open
local SPACE_TECHS = {"rocket-silo", "space-platform"}
function C.space_techs() return SPACE_TECHS end
function C.space_unlocked()
  if not C.S("tr-space-gate") then return true end
  local ok, res = pcall(function()
    local f = game.forces.player
    local seen = false
    for _, name in ipairs(SPACE_TECHS) do
      local t = f.technologies[name]
      if t then
        seen = true
        if t.researched then return true end
      end
    end
    return not seen
  end)
  return (not ok) or res
end

-- starting planet (landing "before the mod"): when space opens, record all server players as first to land
function C.mark_start_crew()
  local d = C.D()
  local names
  for _, f in pairs(d.first) do
    if f.who == "?" and not f.crew then
      if not names then
        names = {}
        for _, p in pairs(game.players) do if p.valid then names[#names + 1] = p.name end end
        table.sort(names)
      end
      f.crew = names
    end
  end
end

-- "who landed first" for display: the starting planet's team, a name or "before install"
function C.first_who(f)
  if f.crew and #f.crew > 0 then return C.join(f.crew, ", ") end
  if f.who == "?" then return {"tr-gui.before-install"} end
  return f.who
end


-- join localised strings with a separator (nested, because of the 20 parameter limit)
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

-- poison, fire and acid are effects (cloud, puddle, burning), not a weapon hit: "effect: Poison", not "damage: Poison"
local EFFECT_DAMAGE = {poison = true, fire = true, acid = true}
function C.damage_ls(dtype)
  return {EFFECT_DAMAGE[dtype] and "tr-gui.weapon-effect" or "tr-gui.weapon-damage", {"damage-type-name." .. dtype}}
end

-- in chat [item=...] already shows the name, so only the icon
function C.weapon_chat(key)
  if string.sub(key, 1, 7) == "damage:" then return C.damage_ls(string.sub(key, 8)) end
  if key == "character" or key == "unknown" then return {"tr-gui.weapon-" .. key} end
  if prototypes.item[key] then return "[item=" .. key .. "]" end
  if prototypes.entity[key] then return "[entity=" .. key .. "]" end
  return key
end

-- weapon key (item / entity / damage:<type>) as a localised string with an icon
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

---------------------------------------------------------------- planet helpers for titles
function C.PL(key)
  local d = C.D()
  d.planets[key] = d.planets[key] or {}
  return d.planets[key]
end

function C.planets_in_game()
  return #C.planets_list()
end

function C.count_mastered()
  local done, total = 0, 0
  for _, key in ipairs(C.planets_list()) do
    total = total + 1
    if C.PL(key).mastered then done = done + 1 end
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

return C
