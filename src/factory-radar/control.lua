-- Factory Radar
local C = require("scripts.core")
local ST = require("scripts.stats")
local P = require("scripts.planets")
local RS = require("scripts.research")
local AFK = require("scripts.afk")
local SH = require("scripts.shift")
local G = require("scripts.gui")
local CMD = require("scripts.commands")
local CB = require("scripts.combat")
local TG = require("scripts.tags")
local PF = require("scripts.platforms")
local EN = require("scripts.energy")
local CEN = require("scripts.census")
local RU = require("scripts.roulette")

-- how-to hint, once per player (can be switched off in the window)
local function greet(p)
  if not (p and p.valid and p.connected) then return end
  local d = C.D()
  if d.greeted[p.index] or not C.P(p, "greet") then return end
  d.greeted[p.index] = true
  p.print({"tr-msg.greet-1"}, {color = {0.7, 0.9, 1}})
  p.print({"tr-msg.greet-2"}, {color = {0.7, 0.9, 1}})
end

-- clean start on a data format change: everything collected earlier is reset, settings stay
local DATA_VERSION = 3
local function clean_start()
  local old = storage.tr
  if old and old.data_version == DATA_VERSION then return end
  if old then
    for index, st in pairs(old.tags or {}) do
      local p = game.get_player(index)
      if p and p.valid and st.set and p.tag == st.set then p.tag = "" end
    end
    for _, p in pairs(game.players) do
      if p.valid then
        local flow = p.gui.screen.tr_frame
        if flow then flow.destroy() end
      end
    end
    rendering.clear("factory-radar")
    -- personal and admin settings stay, tracking switches go back to defaults
    local cfg = old.cfg or {}
    for _, k in ipairs({"tr-track-robots", "tr-track-robot-mined", "tr-track-defense", "tr-track-ff", "tr-track-vehicles"}) do
      if cfg.flags then cfg.flags[k] = nil end
      cfg[k] = nil
    end
    storage.tr = {cfg = cfg, pcfg = old.pcfg or {}}
  end
  C.D().data_version = DATA_VERSION
end

-- recreate a window left open by an older version
local function drop_old_windows()
  for _, p in pairs(game.players) do
    if p.valid then
      local f = p.gui.screen.tr_frame
      if f then f.destroy() end
      for _, n in ipairs({"tr_popup_mvp", "tr_popup_rou", "tr_find"}) do
        if p.gui.screen[n] then p.gui.screen[n].destroy() end
      end
      pcall(p.set_shortcut_toggled, "tr-toggle", false)
    end
  end
end

local function setup()
  C.SE.reset()
  clean_start()
  drop_old_windows()
  RU.cleanup()
  C.D()
  ST.mark_existing()
  -- quiet recheck on every load: granted packs and planet discovery
  C.D().planets_marked = true
  P.check_all(true)
  if C.space_unlocked() then C.mark_start_crew() end
  P.snapshot_all()
  RS.init()
  RS.science_tick(true)
  CB.init()
  SH.init()
  if not C.D().team_marked then
    C.D().team_marked = true
    C.team_check("mastered", (C.count_mastered()), true)
    local rd, rt = RS.progress()
    if rt > 0 then C.team_check("research", math.floor(rd / rt * 100), true) end
  end
  for _, p in pairs(game.players) do G.ensure_button(p) end
  TG.apply_all()
  for _, p in pairs(game.connected_players) do greet(p) end
end

-- for external tools (screenshot mod): open the window on a given tab.
-- The interface name equals the mod name, so the regular and SE builds do not clash.
remote.add_interface(script.mod_name or "factory-radar", {
  open_tab = function(player_index, tab)
    local p = game.get_player(player_index)
    if not (p and p.valid) then return false end
    if not p.gui.screen["tr_frame"] then G.toggle(p) end
    if tab then G.go_to(p, tab) end
    return true
  end,
})

script.on_init(C.safe(setup))
script.on_configuration_changed(C.safe(setup))

script.on_event(defines.events.on_built_entity, C.safe(function(e) ST.on_built(e); EN.on_built(e.entity) end))
script.on_event(defines.events.on_player_mined_entity, C.safe(ST.on_mined))
script.on_event(defines.events.on_entity_died, C.safe(ST.on_entity_died))
script.on_event(defines.events.on_player_crafted_item, C.safe(ST.on_crafted))
script.on_event(defines.events.on_player_died, C.safe(function(e) RU.on_died(e); ST.on_player_died(e) end))
script.on_event(defines.events.on_player_changed_surface, C.safe(ST.on_changed_surface))
script.on_event(defines.events.on_rocket_launched, C.safe(P.on_rocket_launched))
script.on_event(defines.events.on_research_finished, C.safe(RS.on_research_finished))
script.on_event(defines.events.on_gui_click, C.safe(G.on_click))
script.on_event(defines.events.on_gui_switch_state_changed, C.safe(G.on_switch))
script.on_event(defines.events.on_gui_value_changed, C.safe(G.on_value))
script.on_event(defines.events.on_gui_closed, C.safe(G.on_closed))
script.on_event(defines.events.on_player_driving_changed_state, C.safe(RU.on_driving))
script.on_event(defines.events.on_gui_selected_tab_changed, C.safe(G.on_tab_changed))
script.on_event(defines.events.on_lua_shortcut, C.safe(function(e)
  if e.prototype_name == "tr-toggle" then G.toggle(game.get_player(e.player_index)) end
end))
script.on_event("tr-toggle", C.safe(function(e) G.toggle(game.get_player(e.player_index)) end))
script.on_event(defines.events.on_gui_checked_state_changed, C.safe(G.on_checked))
script.on_event(defines.events.on_gui_selection_state_changed, C.safe(G.on_selection))
script.on_event(defines.events.on_gui_text_changed, C.safe(G.on_text))
script.on_event(defines.events.on_gui_elem_changed, C.safe(G.on_elem))
script.on_event(defines.events.on_robot_built_entity, C.safe(function(e) ST.on_robot_built(e); EN.on_built(e.entity) end))
script.on_event(defines.events.on_robot_mined_entity, C.safe(ST.on_robot_mined))
script.on_event(defines.events.on_marked_for_deconstruction, C.safe(ST.on_marked))
script.on_event(defines.events.on_cancelled_deconstruction, C.safe(ST.on_unmarked))
script.on_event(defines.events.on_object_destroyed, C.safe(ST.on_destroyed))
script.on_event(defines.events.on_research_started, C.safe(RS.on_research_started))
script.on_event(defines.events.on_space_platform_changed_state, C.safe(PF.on_state))
script.on_event({defines.events.on_force_created, defines.events.on_force_cease_fire_changed,
  defines.events.on_force_friends_changed, defines.events.on_forces_merged, defines.events.on_player_changed_force},
  function() CB.reset_cache() end)
script.on_event(defines.events.on_string_translated, C.safe(TG.on_translated))
script.on_event({defines.events.on_player_created, defines.events.on_player_joined_game}, C.safe(function(e)
  local p = game.get_player(e.player_index)
  G.ensure_button(p)
  TG.apply(p)
  greet(p)
end))

script.on_nth_tick(127, C.safe(function() ST.track(); AFK.update_state(); PF.track() end))
-- warm heavy prototype caches a few seconds after load, one per call, so the first window open does not freeze.
-- The counter is local: only caches built from prototypes are warmed and nothing goes to storage, so it is multiplayer safe
local warm_stage = 0
script.on_nth_tick(211, C.safe(function()
  if warm_stage >= 2 then return end
  warm_stage = warm_stage + 1
  if warm_stage == 1 then P.warm() else PF.warm() end
end))
-- scan plain containers for the item search, one planet at a time (does nothing until a search is on)
script.on_nth_tick(7, C.safe(G.scan_tick))
script.on_nth_tick(31, C.safe(EN.sample_due))      -- one planet per call, each planet with a grid about every 20 s
script.on_nth_tick(2, C.safe(CEN.step))           -- building count step, does nothing while it is not running
script.on_nth_tick(6, C.safe(AFK.animate))
script.on_nth_tick(60, C.safe(function() EN.fast(); G.autorefresh(); RU.tick() end))
script.on_nth_tick(3600, C.safe(function()
  RS.sample()
  ST.minute()
  SH.tick()
  RS.science_tick(false)
  C.team_check("spm", RS.spm(), false)
end))
script.on_nth_tick(18011, C.safe(function()
  CB.reset_cache()
  P.check_all(false)
  local rd, rt = RS.progress()
  if rt > 0 then C.team_check("research", math.floor(rd / rt * 100), false) end
end))

CMD.register()
