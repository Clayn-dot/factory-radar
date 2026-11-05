-- Screenshot helper: opens the Factory Radar window on a tab and saves a full-screen picture with the GUI.
-- Commands: /shot [tab]  /shot-all  /shot-list
-- Pictures go to script-output/shots/<tab>.png. Only for making pictures for a page, not part of the mod.
local TABS = {"summary", "where", "players", "titles", "achievements", "records", "planets", "platforms",
  "combat", "destruction", "research", "quality", "energy", "journal", "settings", "help"}
local OPEN_AFTER, SHOT_AFTER, STEP = 0, 90, 180

local function q() storage.shot_queue = storage.shot_queue or {} return storage.shot_queue end

local function say(player, msg) if player then player.print(msg) else log(msg) end end

local function schedule(player, tabs)
  local now = game.tick
  for i, tab in ipairs(tabs) do
    local t0 = now + OPEN_AFTER + (i - 1) * STEP
    table.insert(q(), {at = t0, kind = "open", player = player.index, tab = tab})
    table.insert(q(), {at = t0 + SHOT_AFTER, kind = "shot", player = player.index, tab = tab})
  end
end

script.on_nth_tick(10, function()
  local queue = storage.shot_queue
  if not queue or #queue == 0 then return end
  local keep = {}
  for _, it in ipairs(queue) do
    if game.tick < it.at then
      keep[#keep + 1] = it
    else
      local p = game.get_player(it.player)
      if p and p.valid then
        if it.kind == "open" then
          local ok = pcall(remote.call, "factory-radar", "open_tab", p.index, it.tab)
          if not ok then say(p, "Could not open the tab " .. it.tab .. ": is Factory Radar enabled?") end
        else
          local res = p.display_resolution
          local ok, err = pcall(game.take_screenshot, {player = p, by_player = p, show_gui = true, show_entity_info = false,
            resolution = {res.width, res.height}, zoom = 1, path = "shots/" .. it.tab .. ".png"})
          say(p, ok and ("Saved script-output/shots/" .. it.tab .. ".png") or ("Screenshot failed: " .. tostring(err)))
        end
      end
    end
  end
  storage.shot_queue = keep
end)

local function valid_tab(name)
  for _, t in ipairs(TABS) do if t == name then return true end end
  return false
end

commands.add_command("shot", "Screenshot of one tab: /shot [tab] (see /shot-list)", function(cmd)
  local p = cmd.player_index and game.get_player(cmd.player_index)
  if not p then return end
  local tab = (cmd.parameter or ""):match("^%s*(%S+)") or "summary"
  if not valid_tab(tab) then say(p, "Unknown tab. Use /shot-list.") return end
  schedule(p, {tab})
  say(p, "Taking " .. tab .. " in a moment. Do not touch the mouse.")
end)

commands.add_command("shot-all", "Screenshots of all tabs, one after another.", function(cmd)
  local p = cmd.player_index and game.get_player(cmd.player_index)
  if not p then return end
  schedule(p, TABS)
  say(p, "Taking " .. #TABS .. " screenshots, about " .. math.ceil(#TABS * STEP / 60) .. " seconds. Do not touch the mouse.")
end)

commands.add_command("shot-list", "List of tab names for /shot.", function(cmd)
  local p = cmd.player_index and game.get_player(cmd.player_index)
  say(p, table.concat(TABS, ", "))
end)
