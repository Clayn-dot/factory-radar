-- Factory Radar: personal and team achievements
local C = require("scripts.core_base")

---------------------------------------------------------------- personal achievements (one-off)
-- achievements. Some come in steps (one family, higher thresholds): a step gets bars after the name
-- ("Bloody Harvest |||"), texts of each id are in locale (name, "<id>-tip" and "<id>-did")
C.ACH = {
  -- steps
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
  -- singles
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
  -- steps of one stat reached at once are all granted, only the highest is announced
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
      local why = {"tr-ach." .. a.id .. "-did"}      -- "what for" in past tense for chat
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

-- the title the player picked for the nick (if picked and owned), otherwise the newest
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

---------------------------------------------------------------- team achievements
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
  -- science per minute of the whole team
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
