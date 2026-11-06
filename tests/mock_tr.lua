-- TR_SRC: path to the mod folder, with a trailing slash (set by run_tr.py)
TR_SRC = TR_SRC or "../src/factory-radar/"
local LANG = arg and arg[1] or "en"
-- locale resolver
local LOC = {}
do
  local sec
  for l in io.lines(TR_SRC.."locale/"..LANG.."/factory-radar.cfg") do
    local s = l:match("^%[(.+)%]$")
    if s then sec = s elseif sec and l:find("=") then local k, v = l:match("^([^=]+)=(.*)$"); LOC[sec.."."..k] = v end
  end
end
_G.MISSING = {}
local function flat(m)
  if type(m) ~= "table" then return tostring(m) end
  local key = m[1]
  if #m - 1 > 20 then error("LocalisedString with more than 20 parameters: "..tostring(key)) end
  local args = {} for i = 2, #m do args[#args+1] = flat(m[i]) end
  if key == "" then return table.concat(args) end
  local v = LOC[key]
  if not v then
    if key:match("^tr") then _G.MISSING[key] = true end
    return "<"..key..">"
  end
  return (v:gsub("__(%d+)__", function(n) return args[tonumber(n)] or ("__"..n.."__") end))
end
_G.flat = flat
pcall = pcall
function log(s) print("LOG", s) end
serpent = {line = function(t) return tostring(t) end}
function table_size(t) local n=0 for _ in pairs(t) do n=n+1 end return n end
defines = {flow_precision_index={ten_minutes=3, five_minutes=2}, space_platform_state={on_the_path=2, waiting_at_station=6, paused=7, no_schedule=4}, entity_status={working=1, low_power=14, no_power=54}, shooting={not_shooting=0}, events = setmetatable({}, {__index=function(t,k) return k end}), controllers = {remote="remote", character="character"}, inventory={character_guns=1, hub_main=1}}
settings = {global = setmetatable({}, {__index=function(t,k) if k=='tr-shift-hours' then return {value=4} end return {value=true} end})}
storage = {}
local SD={["tr-s-shift-hours"]=4,["tr-s-afk-minutes"]=10,["tr-s-death-limit"]=3,["tr-s-journal"]=100,["tr-s-history"]=8,["tr-s-idle-percent"]=25,["tr-s-min-output"]=1000,["tr-s-mvp-reminder"]=10,["tr-s-roulette-join"]=60,["tr-s-roulette-cooldown"]=60,["tr-s-zap-cooldown"]=10,["tr-s-zap-percent"]=10}
settings.startup = setmetatable({}, {__index=function(t,k) local v=SD[k] if v==nil then v=true end return {value=v} end})
script_active={}
helpers = {is_valid_sprite_path=function(s) return s=='utility/electricity_icon' end, evaluate_expression=function(f, v) return 1000*(v.L-2) end}
remote = {interfaces={}, add_interface=function() end, call=function() return false end}
_G.drawn=0 _G.destroyed=0 _G.texts={}
rendering = {clear=function() end, draw_text=function(t) local o={valid=true,text=t.text,target=t.target,color=t.color} function o.destroy() o.valid=false _G.destroyed=_G.destroyed+1 end _G.drawn=_G.drawn+1 table.insert(_G.texts,t.text) return o end}
local function newel(spec, parent)
  local el = {children={}, style=setmetatable({column_alignments=(spec.type=="table") and {} or nil}, {__newindex=function(t,k,v)
    if (k=="vertical_spacing" or k=="horizontal_spacing") and spec.type~="table" and spec.type~="flow" and spec.type~="tabbed-pane" then error("Expected Table or Flow style type but was "..tostring(spec.type)) end
    if k=="font_color" and not ({label=1,button=1,["sprite-button"]=1,checkbox=1,radiobutton=1})[spec.type] then error("font_color on "..tostring(spec.type)) end
    if k=="color" and spec.type~="progressbar" then error("color on "..tostring(spec.type)) end
    rawset(t,k,v) end}), valid=true, tags=spec.tags or {}, name=spec.name, type=spec.type, caption=spec.caption, tooltip=spec.tooltip, switch_state=spec.switch_state, value=spec.value, items=spec.items, selected_index=spec.selected_index, state=spec.state, toggled=spec.toggled, sprite=spec.sprite, parent=parent}
  setmetatable(el, {__index=function(t,k) for _,c in ipairs(rawget(t,"children")) do if c.name==k then return c end end return nil end})
  function el.add(sp) assert(sp.type, "no type"); if sp.name then assert(not el[sp.name], "duplicate name "..sp.name) end local c=newel(sp, el); table.insert(el.children,c); return c end
  function el.clear() el.children={} end
  function el.destroy() el.valid=false; if parent then for i,c in ipairs(parent.children) do if c==el then table.remove(parent.children,i) end end end end
  function el.add_tab(t,p) end
  function el.force_auto_center() end
  function el.bring_to_front() end
  return el
end
package.loaded["mod-gui"] = {button_style="mod_gui_button", get_button_flow=function(p) return p._flow end}
local PRESS = {nauvis=1000, castra=1000, pelagos=1000, gleba=2000, muluna=50}
local function proto(name) return {name=name, localised_name={"space-location-name."..name}, surface_properties={pressure=PRESS[name] or 1000}} end
local nauvis = {name="nauvis", index=1, valid=true, planet={prototype=proto("nauvis")}}
local castra = {name="castra", index=2, valid=true, planet={prototype=proto("castra")}}
local hid = {name="kr-air-purifier-helper", index=9, valid=true, planet={prototype={name="kr-air-purifier-helper", localised_name="Air purifier", hidden=true}}}
local plat = {name="platform-1", index=3, valid=true, platform={name="SpeedDaemon", space_location=nil, space_connection={from=proto("gleba"), to=proto("nauvis")}}}
local function mkplayer(i, name, surf, pos)
  local p = {object_name="LuaPlayer", index=i, name=name, valid=true, connected=true, physical_surface=surf, surface=surf, physical_surface_index=surf.index, surface_index=surf.index,
    physical_position=pos, position=pos, afk_time=0, online_time=1000, last_online=0, ticks_to_respawn=nil, character={valid=true, surface=surf}, vehicle=nil, admin=true,
    gui={screen=newel({type="screen"})}, _flow=newel({type="flow"}), controller_type="character"}
  function p.print(m) print("  ["..name.."] "..flat(m)) end
  function p.request_translation(ls) p._req = ls end
  p.mod_settings = setmetatable({}, {__index=function(t,k) if k=="tr-p-open-tab" then return {value="last"} end if k=="tr-p-msg-deaths" and name=="bruklyn.ben" then return {value=false} end return {value=true} end})
  function p.set_shortcut_toggled(n, v) p._sc = v end
  p.tag = ""
  function p.set_controller(t) print("  set_controller ->", t.surface.name, t.position.x, t.position.y) end
  return p
end
local p1 = mkplayer(1, "bruklyn.ben", nauvis, {x=0,y=0})
local p2 = mkplayer(2, "Oleg", castra, {x=100,y=50})
local p3 = mkplayer(3, "sleekhead", plat, {x=0,y=0}); p3.connected=false; p3.last_online=50000
local plist = {p1,p2,p3}
local force = {name="player", valid=true}
force.players = plist
for _,p in ipairs(plist) do p.force = force end
local function tech(name, researched, maxl, lvl, plvl)
  return {name=name, valid=true, force=force, enabled=true, researched=researched, level=lvl or 1, localised_name={"technology-name."..name},
    research_unit_ingredients={{name="automation-science-pack", amount=1},{name="space-science-pack", amount=1}},
    prototype={hidden=false, max_level=maxl or 1, level=plvl or 1, research_unit_count_formula=maxl and "1000*(L-2)" or nil, research_unit_count=100}}
end
force.technologies = {a=tech("automation", true), b=tech("logistics", false), c=tech("steel", true),
  ["mining-productivity-3"]=tech("mining-productivity-3", false, 4294967295, 3, 3),
  ["worker-robots-speed-7"]=tech("worker-robots-speed-7", false, 4294967295, 7, 7)}
force.current_research = force.technologies.b
local BIGCARGO = {} for i=1,12 do BIGCARGO[i]={name="item-"..i, count=100000/i, quality=(i%3==0) and "rare" or "normal"} end
force.platforms = {
  {valid=true, index=2, name="Back[item=iron-plate]", force=force, state=2, paused=false, distance=0.8,
   space_connection={from={name="nauvis"}, to={name="vulcanus"}}, schedule={current=1, records={{station="nauvis"},{station="vulcanus"},{station="gleba"}}},
   hub={valid=true, health=1000, max_health=1000, get_inventory=function() return {get_contents=function() return BIGCARGO end} end}},
  {valid=true, index=3, name="Parked", force=force, state=6, paused=false, space_location={name="gleba"}, schedule={current=3, records={{station="nauvis"},{station="shattered-planet"},{station="gleba"},{station="aquilo"}}},
   hub={valid=true, health=10, max_health=1000, get_inventory=function() return {get_contents=function() return {} end} end}},
  {valid=true, index=4, name="NoSched", force=force, state=4, paused=false, space_location={name="nauvis"}, schedule=nil, hub=nil},
  {valid=true, index=1, name="SpeedDaemon", force=force, state=2, paused=false, distance=0.4,
  space_connection={from={name="gleba"}, to={name="nauvis"}}, schedule={current=2, records={{station="gleba"},{station="aquilo"}}},
  hub={valid=true, health=800, max_health=1000, get_inventory=function() return {get_contents=function() return {{name="iron-plate",count=500,quality="normal"},{name="rocket-fuel",count=40,quality="rare"}} end} end}}}
force.research_progress = 0.42
force.laboratory_productivity_bonus = 0.5
local out_counter = 1000
function force.get_item_production_statistics(s)
  local k = s.index == 1 and 3 or 1
  return {get_flow_count=function(a) return 2.5*k end, get_input_count=function(n) return 40*k*out_counter/1000 end, get_output_count=function(n) return out_counter end,
    input_counts={["iron-plate"]=5000*k*out_counter/1000, ["gear"]=300, ["automation-science-pack"]=26400*k, ["space-science-pack"]=3237}}
end
game = {planets={["kr-air-purifier-helper"]={prototype={name="kr-air-purifier-helper",hidden=true}},nauvis={prototype=proto('nauvis'), surface=nauvis},castra={prototype=proto('castra'), surface=castra},pelagos={prototype=proto('pelagos')},gleba={prototype=proto('gleba')},muluna={prototype=proto('muluna')}},
  tick=100000, players=plist, connected_players={p1,p2}, surfaces={nauvis, castra, plat, hid}, forces={}}
local enemy = {name="enemy", valid=true, players={}, get_evolution_factor=function(s) return (s.index==2 and 0.62 or 0.31) + (_G.EVO or 0) end}
local erm = {name="enemy_erm_zerg", valid=true, players={}, get_evolution_factor=function(s) return 0.4 end}
local neutral = {name="neutral", valid=true, players={}}
force.is_enemy = function(f) return f.name ~= "neutral" end
game.forces = {player=force, enemy=enemy, enemy_erm_zerg=erm, neutral=neutral}
for _,sf in ipairs(game.surfaces) do sf.count_entities_filtered=function(f) return 7 end sf.find_entities_filtered=function(f) if f.type=="rocket-silo" and sf.index==2 then return {{valid=true,energy=1,name="rocket-silo"}} end return {} end end
prototypes = {space_connection={a={from={name="nauvis"},to={name="vulcanus"},length=15000},b={from={name="vulcanus"},to={name="gleba"},length=9000},c={from={name="gleba"},to={name="aquilo"},length=20000}}, space_location=setmetatable({}, {__index=function(t,k) return proto(k) end}), quality={normal={level=0}, uncommon={level=1}, rare={level=2}, legendary={level=5}}, technology={}, surface_property={pressure={default_value=1000}},
  recipe={a={name="a", hidden=false, category="crafting", products={{type="item", name="automation-science-pack"}}},
          m1={name="m1", hidden=false, category="crafting", products={{type="item", name="muluna-pack"}}, surface_conditions={{property="pressure", max=100}}},
          m2={name="m2", hidden=false, category="crafting", products={{type="item", name="muluna-pack-2"}}, surface_conditions={{property="pressure", max=100}}},
          rec={name="rec", hidden=false, category="recycling", products={{type="item", name="muluna-pack"}}},
          g={name="g", hidden=false, category="crafting", products={{type="item", name="space-science-pack"}}, surface_conditions={{property="pressure", min=1500, max=2500}}}},
  get_entity_filtered=function() return {lab={lab_inputs={"automation-science-pack","space-science-pack","muluna-pack","muluna-pack-2"}}} end, item={["muluna-pack"]={localised_name="Muluna pack"},["muluna-pack-2"]={localised_name="Muluna pack 2"},["submachine-gun"]={localised_name={"item-name.submachine-gun"}},["automation-science-pack"]={localised_name={"item-name.automation-science-pack"}}, ["space-science-pack"]={localised_name={"item-name.space-science-pack"}}}, entity={["rocket-silo"]={}}}
function game.get_player(i) if type(i)=="string" then for _,p in ipairs(plist) do if p.name==i then return p end end return nil end return plist[i] end
function game.print(m) print("ALL: "..flat(m)) end
local handlers, nth, init = {}, {}, nil
script = {active_mods={["ups-guard"]="1.0.0"}, on_init=function(f) init=f end, on_configuration_changed=function() end, on_load=function() end,
  on_event=function(ev, f) if type(ev)=="table" then for _,e in pairs(ev) do handlers[e]=f end else handlers[ev]=f end end,
  on_nth_tick=function(n,f) nth[n]=f end}
commands = {cmds={}, add_command=function(n,h,f) assert(LOC[h[1]], "no help "..h[1]) commands.cmds[n]=f end}
package.path = TR_SRC.."?.lua;" .. package.path
-- make errors loud: C.safe logs; we print LOG lines
require("control")
if os.getenv("STRESS") then
  local C = package.loaded["scripts.core"]
  C.n = function(n) return {"tr.num-k", tostring(n)} end
  C.planet_ls = function(k) return {"", "[img=space-location/"..tostring(k).."] ", {"space-location-name."..tostring(k)}} end
  print("STRESS MODE")
end
init()
print("button:", p1._flow.tr_button and "ok" or "MISSING")
local pel = {name="pelagos", index=4, valid=true, planet={prototype=proto("pelagos")}}
pel.find_entities_filtered=function() return {} end
table.insert(game.surfaces, pel)
p1.physical_surface = pel; p1.physical_surface_index = 4; p1.surface=pel; p1.surface_index=4
handlers.on_player_changed_surface({player_index=1})
-- Oleg looks at pelagos via remote view
p2.surface = pel; p2.position = {x=500, y=-300}
local biter = {valid=true, force=enemy, name="small-biter", type="unit", surface=nauvis}
local char2 = {valid=true, type="character", player=p2, name="character", selected_gun_index=1, get_inventory=function() return {{valid_for_read=true, name="submachine-gun"}} end}
for i=1,120 do handlers.on_entity_died({entity=biter, force=force, cause=char2}) end
local zerg = {valid=true, force=erm, name="zergling", type="unit", surface=castra}
local turret = {valid=true, type="ammo-turret", name="gun-turret", last_user=p1}
for i=1,30 do handlers.on_entity_died({entity=zerg, force=force, cause=turret}) end
handlers.on_entity_died({entity={valid=true, force=enemy, name="biter-spawner", type="unit-spawner", surface=nauvis}, force=force, cause=char2})
handlers.on_entity_died({entity=zerg, force=force, damage_type={name="fire"}})
-- neutral tree should not count
handlers.on_entity_died({entity={valid=true, force=neutral, name="tree", type="tree", surface=nauvis}, force=force, cause=char2})
handlers.on_entity_died({entity={valid=true, force=enemy, name="data-collector-12", type="unit", surface=castra}, force=force, cause=char2})
handlers.on_player_crafted_item({player_index=1, item_stack={valid_for_read=true, count=600}})
local wall = {valid=true, type="wall", name="stone-wall", force=force, surface=nauvis, last_user=p1}
for i=1,5 do handlers.on_built_entity({player_index=1, entity={valid=true, type="assembling-machine", surface=nauvis}}) end
for i=1,7 do handlers.on_entity_died({entity=wall, force=enemy, cause=biter}) end
handlers.on_entity_died({entity={valid=true,type="wall",force=force,surface=nauvis,last_user=nil}, force=enemy})
for i=1,100 do handlers.on_built_entity({player_index=1, entity={valid=true, type="transport-belt", surface=nauvis}}) end
handlers.on_player_mined_entity({player_index=2, entity=wall})
nth[127](); p1.physical_position={x=300,y=400}; nth[127]()
for i=1,2 do
  local t = force.technologies["mining-productivity-3"]; t.level = t.level + 1
  handlers.on_research_finished({research=t})
end
p1.character=nil; game.tick=game.tick+10000
handlers.on_player_died({player_index=1, cause={valid=true, type="locomotive", name="locomotive", force=force}})
p1.character={valid=true, surface=pel}
print("--- commands ---")
for _,c in ipairs({{"tr-where",""},{"tr-now",""},{"tr-top",""},{"tr-me",""},{"tr-vs","Oleg"},{"tr-planets",""},{"tr-research",""},{"tr-log","5"},{"tr-mvp","Oleg"},{"tr-combat",""}}) do
  print("> /"..c[1].." "..c[2]); commands.cmds[c[1]]({player_index=1, parameter=c[2]})
end
for i=1,3 do game.tick=game.tick+5*3600+10 nth[3600]() end
print("--- GUI ---")
p1.vehicle = {valid=true, name="spidertron", localised_name={"entity-name.spidertron"}, type="spider-vehicle"}
handlers.on_gui_click({player_index=1, element=p1._flow.tr_button})
local fr = p1.gui.screen.tr_frame
print("frame:", fr and "ok" or "MISSING")
local function dump(e,d) local s="" if e.caption then s=flat(e.caption) end if e.type=="progressbar" then s=s.."[bar "..string.format("%.2f",e.value or 0).."]" end if e.type=="sprite-button" then s=s.."(btn "..tostring(e.sprite)..")" end if s~="" then print(string.rep(" ",d)..s) end for _,c in ipairs(e.children) do dump(c,d+1) end end
local function findtag(e, key, val) if e.tags and e.tags.tr==key and (not val or e.tags.what==val or e.tags.who==val) then return e end for _,c in ipairs(e.children) do local r=findtag(c,key,val) if r then return r end end end
print("button sprite:", p1._flow.tr_button.sprite, "shortcut toggled:", tostring(p1._sc))
function PANE(n) local function f(e) if e.name=="tr_pane_"..n then return e end for _,c in ipairs(e.children) do local r=f(c) if r then return r end end end return f(p1.gui.screen.tr_frame) or {children={}} end
-- a tab is built when it is opened: open every tab once so all panes have content, then go back to the summary
for _,tn in ipairs({"summary","where","players","titles","achievements","records","planets","platforms","combat","destruction","research","quality","energy","journal","settings","help","summary"}) do
  local t0 = os.clock()
  handlers.on_gui_click({player_index=1, element={valid=true, name="x", tags={tr="goto", sub=tn}}})
  if os.getenv("PROF") == "1" then print(string.format("PROF tab %-13s %.1f ms", tn, (os.clock() - t0) * 1000)) end
end
print("=== HEADER ===") dump(fr.tr_header,0)
for _,tn in ipairs({"summary","where","players","titles","achievements","records","planets","platforms","combat","destruction","research","quality","energy","journal","settings","help"}) do
  print("=== TAB "..tn.." ===")
  dump(PANE(tn),0)
end
local look = findtag(PANE("where"), "jump", "look")
print("look btn:", look and "ok" or "MISSING") if look then handlers.on_gui_click({player_index=1, element=look}) end
local body = findtag(PANE("where"), "jump", "body") if body then handlers.on_gui_click({player_index=1, element=body}) end
local sortb=findtag(PANE("players"),"sort") print("sort btn", sortb and sortb.tags.key) if sortb then handlers.on_gui_click({player_index=1, element=sortb}) end
local cardb=findtag(PANE("players"),"card") print("card btn", cardb and cardb.tags.who)
if cardb then handlers.on_gui_click({player_index=1, element=cardb}); print("=== CARD ===") dump(PANE("players"),0) end
local pk = findtag(PANE("combat"), "evo_pick")
print("evo picker first:", pk and pk.tags.planet, pk and tostring(pk.toggled))
if pk then handlers.on_gui_click({player_index=1, element=pk}) end
local cnt=0 local function c2(e) if e.tags and e.tags.tr=="evo_pick" then cnt=cnt+1; print("  pick", e.tags.planet, tostring(e.toggled)) end for _,c in ipairs(e.children) do c2(c) end end c2(PANE("combat"))
-- chat title picker: give p1 two titles first
storage.tr.titles["bruklyn.ben"] = {["spaghetti-chef"]=100, exterminator=200}
handlers.on_gui_click({player_index=1, element=findtag(fr, "refresh") or {valid=true,name="x",tags={tr="refresh"}}})
local function findname(e, n) if e.name==n then return e end for _,c in ipairs(e.children) do local r=findname(c,n) if r then return r end end end
handlers.on_gui_click({player_index=1, element={valid=true, name="x", tags={tr="goto", sub="titles"}}})
local dd = findname(fr, "tr_tag_pick")
print("tag dropdown items:", dd and #dd.items, "req:", p1._req and flat(p1._req))
handlers.on_string_translated({player_index=1, localised_string=p1._req, translated=true, result=p1._req and flat(p1._req) or "?"})
print("p1.tag =", p1.tag)
dd = findname(fr, "tr_tag_pick") print("items:", #dd.items) dd.selected_index=3 handlers.on_gui_selection_state_changed({player_index=1, element=dd})
print("picked req:", flat(p1._req)) handlers.on_string_translated({player_index=1, localised_string=p1._req, translated=true, result=flat(p1._req)}) print("p1.tag =", p1.tag)
local cb = findname(fr, "tr_tag_on") cb.state=false handlers.on_gui_checked_state_changed({player_index=1, element=cb}) print("after off p1.tag =", "'"..p1.tag.."'")
print("--- quick test ---")
handlers.on_gui_click({player_index=1, element={valid=true, name="x", tags={tr="pin", sub="platforms"}}})
handlers.on_gui_click({player_index=1, element={valid=true, name="x", tags={tr="goto", sub="energy"}}})
local q = p1.gui.screen.tr_frame.tr_quick
for _,c in ipairs(q.children) do if c.caption then print("  quick:", flat(c.caption)) end end
print("--- energy: fast check, log, merge, dead networks ---")
do
  local EN = require("scripts.energy")
  local keys = {}
  local machine = {valid = true, status = 14}                       -- low_power
  for _, sf in ipairs(game.surfaces) do
    if sf.planet then
      local key = sf.planet.prototype.name
      keys[#keys + 1] = key
      local pe = EN.planet(key)
      pe.nets = {a = {valid = true, electric_network_statistics = {output_counts = {["steam-engine"] = 1}, input_counts = {}}},
        b = {valid = true, electric_network_statistics = {output_counts = {}, input_counts = {}}}}      -- b: a network that never had a source
      pe.refs = {a = {machine}, b = {{valid = true, status = 54}}}; pe.refs_v = 2; pe.gens = {a = {{valid = true}}}
      local smp = {tick = game.tick, prod = 5e6, capw = 8e6, cons = 7.8e6, acc_in = 0, acc_out = 1e6, stored = 2e9, cap = 1e10, short = "low",
        by_prod = {["lightning-rod"] = 5e6}, by_cons = {}, cnt = {}}
      pe.hist = {smp, smp, smp, smp}
      pe.last = {tick = game.tick, prod = {}, cons = {}}
      pe.scanned = 1e12                                              -- never rescanned in this test
    end
  end
  for n = 2, #keys do EN.planet(keys[n]).refs = {} end              -- only the first planet has trouble
  local key1 = keys[1]
  -- a dip of 5 seconds is not logged; a shortage of 32 seconds is (30 s for "not enough")
  machine.status = 14
  for i = 1, 5 do game.tick = game.tick + 60; EN.fast() end
  machine.status = 1
  for i = 1, 3 do game.tick = game.tick + 60; EN.fast() end
  print("short dip logged:", #EN.log(), "(expected 0)")
  machine.status = 14
  for i = 1, 62 do game.tick = game.tick + 60; EN.fast() end
  local e1 = EN.log()[1]
  print("shortage logged:", #EN.log(), e1 and e1.key == key1 and "first planet" or "?", "done:", tostring(e1 and e1.done), "kind:", e1 and e1.kind, "(expected 1 first planet done false kind low: the dead network is ignored)")
  -- the tab shows it at once
  handlers.on_gui_click({player_index=1, element={valid=true, name="x", tags={tr="goto", sub="energy"}}})
  handlers.on_gui_click({player_index=1, element={valid=true, name="x", tags={tr="en_log_toggle"}}})
  if os.getenv("DUMP_ENERGY") then dump(PANE("energy"), 0) end
  -- it ends after two clean checks; the next one within ten minutes is the same entry
  machine.status = 1
  for i = 1, 3 do game.tick = game.tick + 60; EN.fast() end
  print("shortage closed:", tostring(EN.log()[1].done), "(expected true)")
  machine.status = 14
  for i = 1, 62 do game.tick = game.tick + 60; EN.fast() end
  print("repeat merged:", #EN.log(), "times:", EN.log()[1].n, "(expected 1, 2)")
  machine.status = 1
  for i = 1, 3 do game.tick = game.tick + 60; EN.fast() end
  -- more entries than the log holds
  for i = 1, 24 do
    local pe = EN.planet(keys[1])
    game.tick = game.tick + 11 * 3600
    machine.status = 14
    for j = 1, 62 do game.tick = game.tick + 60; EN.fast() end
    machine.status = 1
    for j = 1, 3 do game.tick = game.tick + 60; EN.fast() end
  end
  print("log size:", #EN.log(), "(expected 20)")
  -- a yellow entry: two risky measurements in a row write it, two calm ones close it
  do
    local pe = EN.planet("warn-test")
    pe.hist = {{cons = 5e6, prod = 5e6}}
    local risky = {score = 1, loggable = true, reasons = {{"tr-en.why-nofuel", 2, 3}}}
    for i = 1, 14 do game.tick = game.tick + 1200; EN.warn_track(pe, "warn-test", risky, nil) end
    print("warn not yet (14 of 15 measurements):", (EN.log()[1] and EN.log()[1].key == "warn-test") and "WRONG" or "ok")
    game.tick = game.tick + 1200; EN.warn_track(pe, "warn-test", risky, nil)
    local w = EN.log()[1]
    print("warn logged:", w and w.key == "warn-test" and w.level == "warn" and not w.done and "ok" or "MISSING")
    local calm = {score = 0, reasons = {}}
    for i = 1, 3 do game.tick = game.tick + 1200; EN.warn_track(pe, "warn-test", calm, nil) end
    print("warn closed:", EN.log()[1].done and "ok" or "STILL OPEN")
    handlers.on_gui_click({player_index=1, element={valid=true, name="x", tags={tr="goto", sub="energy"}}})
    print("journal with yellow entry rendered:", "ok")
    -- accumulators draining and not connected are explained
    local an = EN.analyze({h = {prod = 0, cons = 8e6, capw = 8e6, stored = 3e9, cap = 1e10, acc_in = 0, acc_out = 8e6, acc_n = 5, acc_iso = 5, short = nil},
      hist = {}, cur = nil, cur_known = true})
    local keys_found = {}
    for _, r in ipairs(an.reasons) do keys_found[#keys_found + 1] = r[1] end
    print("acc reasons:", table.concat(keys_found, ","))
    local function keys_of(a) local t = {} for _, r in ipairs(a.reasons) do t[#t + 1] = r[1] end return table.concat(t, ",") end
    local night = {valid = true, freeze_daytime = false, daytime = 0.5, ticks_per_day = 25000, dusk = 0.25, evening = 0.45, morning = 0.55, dawn = 0.75}
    local a1 = EN.analyze({h = {prod = 0, prod_ns = 0, cons = 5e6, capw = 5e6, stored = 1e8, cap = 1e9, acc_in = 0, acc_out = 5e6, acc_n = 5, solar = true},
      hist = {}, cur = nil, cur_known = true, s = night})
    print("night forecast short:", keys_of(a1):find("why%-night%-short") and "ok" or ("MISSING " .. keys_of(a1)))
    local a2 = EN.analyze({h = {prod = 5e6, prod_ns = 0, cons = 5e6, capw = 9e6, stored = 2e8, cap = 2e8, acc_in = 0, acc_out = 0, acc_n = 5, solar = true},
      hist = {}, cur = nil, cur_known = true, s = {valid = true, freeze_daytime = false, daytime = 0.0, ticks_per_day = 25000, dusk = 0.25, evening = 0.45, morning = 0.55, dawn = 0.75}})
    print("day, capacity not enough for the night:", keys_of(a2):find("why%-night%-cap") and "ok" or ("MISSING " .. keys_of(a2)))
    local a3 = EN.analyze({h = {prod = 0, cons = 5e6, capw = 5e6, stored = 0, cap = 0, acc_n = 0, fuel_miss = 2, fuel_n = 3, short = "low"},
      hist = {}, cur = "low", cur_known = true})
    print("no fuel reason:", keys_of(a3):find("why%-nofuel") and "ok" or ("MISSING " .. keys_of(a3)))
    local a4 = EN.analyze({h = {prod = 5e6, cons = 4e6, capw = 5e6, stored = 5e8, cap = 1e9, acc_n = 4, acc_iso = 4}, hist = {}, cur = nil, cur_known = true})
    print("isolated accumulators are only a note:", (a4.score == 0 and #a4.notes == 1) and "ok" or "WRONG")
    -- an hour of history: growing consumption reaches the capacity; fuel that only goes down runs out
    do
      local hist = {}
      for i = 1, 90 do
        hist[i] = {tick = 1000 + i * 1200, prod = 10e6 + i * 2e5, cons = 10e6 + i * 2e5, capw = 40e6, stored = 0, cap = 0, acc_n = 0, by_prod = {}, by_cons = {},
          fuel = 5e9 - i * 4e7}
      end
      local hh = hist[90]
      local an5 = EN.analyze({h = hh, hist = hist, cur = nil, cur_known = true})
      local ks = {}
      for _, r in ipairs(an5.reasons) do ks[#ks + 1] = r[1] end
      ks = table.concat(ks, ",")
      print("trend reaches the capacity:", ks:find("why%-trend%-cap") and "ok" or ("MISSING " .. ks))
      print("fuel running out:", ks:find("why%-fuel%-low") and "ok" or ("MISSING " .. ks))
    end
    -- a space platform: empty accumulators while the sources do not cover the demand are a red entry after three measurements
    do
      local stats = {output_counts = {}, input_counts = {}}
      local pole = {valid = true, type = "electric-pole", name = "pole", electric_network_id = 1, electric_network_statistics = stats}
      local acc = {valid = true, type = "accumulator", name = "accumulator", energy = 1e4, electric_buffer_size = 5e6}
      local solar = {valid = true, type = "solar-panel", name = "solar-panel", prototype = {get_max_energy_production = function() return 1000 end}}
      local mach = {valid = true, type = "assembling-machine", name = "assembling-machine", status = 1}
      local sf = {valid = true, solar_power_multiplier = 1, find_entities_filtered = function(f)
        if f.type == "electric-pole" then return {pole} elseif f.type == "accumulator" then return {acc} end
        if type(f.type) == "table" and f.type[1] == "generator" then return {solar} end
        return {mach}
      end}
      local pl = {valid = true, index = 77, name = "TestPlat", surface = sf}
      table.insert(force.platforms, pl)
      for i = 1, 3 do
        game.tick = game.tick + 1300
        stats.input_counts["assembling-machine"] = i * 6e8
        stats.output_counts["solar-panel"] = i * 1e8
        EN.sample_platform(pl)
      end
      local e = EN.log()[1]
      print("platform red entry:", (e and e.plat == "TestPlat" and e.kind == "empty" and not e.done) and "ok" or "MISSING")
      print("platform rows:", #EN.plat_rows() == 1 and "ok" or "WRONG")
      handlers.on_gui_click({player_index=1, element={valid=true, name="x", tags={tr="goto", sub="energy"}}})
      handlers.on_gui_click({player_index=1, element={valid=true, name="x", tags={tr="en_log_toggle"}}})
      print("platform block rendered:", "ok")
      table.remove(force.platforms)
    end
  end
  for i, e in ipairs(EN.log()) do if i <= 2 then print("   entry", i, e.key, e.start, e.last, e.n, tostring(e.done)) end end
  print("sig:", EN.sig() ~= "" and "ok" or "empty", "trouble_since:", #EN.trouble_since(0))
  handlers.on_gui_click({player_index=1, element={valid=true, name="x", tags={tr="refresh"}}})
  print("  energy tab opened with", #keys, "planets")
end
print("--- settings interactions ---")
handlers.on_gui_click({player_index=1, element={valid=true, name="x", tags={tr="goto", sub="settings"}}})
local sp = PANE("settings")
local function findtag2(e, key, f) if e.tags and e.tags.tr==key and (not f or f(e.tags)) then return e end for _,c in ipairs(e.children) do local r=findtag2(c,key,f) if r then return r end end end
-- mute deaths for Oleg via personal checkbox (as p1 here)
local cbm = findtag2(sp, "pcfg", function(t) return t.key=="msg-titles" end) cbm.state=false handlers.on_gui_checked_state_changed({player_index=1, element=cbm})
-- audience for title -> self
local aud = findtag2(sp, "cfg_aud", function(t) return t.kind=="title" end) aud.selected_index=2 handlers.on_gui_selection_state_changed({player_index=1, element=aud})
-- template for death
local tpl = findtag2(sp, "cfg_tpl", function(t) return t.kind=="death" end) tpl.text="RIP {player} ({killer}) #{count}" handlers.on_gui_text_changed({player_index=1, element=tpl})
-- tracking: robots on
local tr = findtag2(sp, "cfg", function(t) return t.key=="tr-track-robots" end) tr.state=true handlers.on_gui_checked_state_changed({player_index=1, element=tr})
-- open title editor, rename Exterminator, set threshold, add custom title
handlers.on_gui_click({player_index=1, element=findtag2(sp, "cfg_title_editor")})
sp = PANE("settings")
local tn = findtag2(sp, "title_name", function(t) return t.id=="spaghetti-chef" end) tn.text="Макаронный монстр" handlers.on_gui_text_changed({player_index=1, element=tn})
local tnn = findtag2(sp, "title_n", function(t) return t.id=="spaghetti-chef" end) tnn.text="50" handlers.on_gui_text_changed({player_index=1, element=tnn})
local nn = findtag2(sp, "new_title_name") nn.text="Король фабрики" handlers.on_gui_text_changed({player_index=1, element=nn})
local nk = findtag2(sp, "new_title_key") nk.selected_index=3 handlers.on_gui_selection_state_changed({player_index=1, element=nk})
local nv = findtag2(sp, "new_title_n") nv.text="10" handlers.on_gui_text_changed({player_index=1, element=nv})
handlers.on_gui_click({player_index=1, element=findtag2(PANE("settings"), "new_title_add")})
print("custom titles:", #storage.tr.cfg.titles_custom, storage.tr.cfg.titles_custom[1].name, storage.tr.cfg.titles_custom[1].key, storage.tr.cfg.titles_custom[1].n)
print("p1 titles now:") for id in pairs(storage.tr.titles["bruklyn.ben"]) do print("  ", id) end
-- robot build credited
handlers.on_robot_built_entity({entity={valid=true, type="transport-belt", surface=nauvis, last_user=p2}})
print("Oleg built after robot:", storage.tr.total["Oleg"].built, "belts", storage.tr.total["Oleg"].belts)
-- death with template
p2.character=nil game.tick=game.tick+20000
handlers.on_player_died({player_index=2, cause={valid=true, type="unit", name="big-biter", force=enemy}})
p2.character={valid=true, surface=castra}
-- hide a tab -> rebuild
local tabcb = findtag2(PANE("settings"), "pcfg", function(t) return t.key=="tab-journal" end) tabcb.state=false handlers.on_gui_checked_state_changed({player_index=1, element=tabcb})
fr = p1.gui.screen.tr_frame
local names={} for _,c in ipairs(fr.tr_tabs.children) do if c.type=="tab" then names[#names+1]=flat(c.caption) end end print("tabs:", table.concat(names," | "))
-- intro_hide_test
handlers.on_gui_click({player_index=1, element={valid=true, name="x", tags={tr="goto", sub="planets"}}})
handlers.on_gui_click({player_index=1, element={valid=true, name="x", tags={tr="pcfg_set", key="intro", value=false}}})
print("intro after hide:", tostring(storage.tr.pcfg[1] and storage.tr.pcfg[1].intro))
-- live_plat_test
handlers.on_gui_click({player_index=1, element={valid=true, name="x", tags={tr="goto", sub="platforms"}}})
force.platforms[1].distance = 0.55
nth[60]()
local function findt(e, key) if e.tags and e.tags.tr==key then return e end for _,c in ipairs(e.children) do local r=findt(c,key) if r then return r end end end
local pane = PANE("platforms"); local pct = findt(pane, "plat_pct")
print("live pct:", pct and flat(pct.caption))
force.platforms[1].state = 6; force.platforms[1].space_location={name="gleba"}; force.platforms[1].space_connection=nil
nth[60]()
print("redrawn:", findt(PANE("platforms"), "plat_card") and "ok")
print("--- interrupt / idle / cargo / where live / esc ---")
force.platforms[2].schedule = {current=2, records={{station="nauvis"},{station="aquilo", temporary=true},{station="gleba"}}}
force.platforms[2].get_schedule = function() return {ticks_in_station = 9000} end
force.platforms[2].schedule = {current=2, records={{station="nauvis"},{station="aquilo", temporary=true},{station="gleba"}}}
force.platforms[2].get_schedule = function() return {ticks_in_station = 9000} end
handlers.on_gui_click({player_index=1, element={valid=true, name="x", tags={tr="goto", sub="platforms"}}})
handlers.on_gui_click({player_index=1, element={valid=true, name="x", tags={tr="cargo_toggle", idx=2}}})   -- folded by default: unfold
nth[60]()
local ip = PANE("platforms")
local function allt(e, key, out) out = out or {} if e.tags and e.tags.tr==key then out[#out+1]=e end for _,c in ipairs(e.children or {}) do allt(c, key, out) end return out end
local shown = 0 for _,l in ipairs(allt(ip, "plat_idle")) do if l.visible then shown = shown + 1 end end
print("idle labels visible:", shown, "(expected 1)")
local function anytip(e, needle) if e.tooltip and flat(e.tooltip):find(needle, 1, true) then return true end for _,c in ipairs(e.children or {}) do if anytip(c, needle) then return true end end end
local function anytext(e, needle) if e.caption and flat(e.caption):find(needle, 1, true) then return true end for _,c in ipairs(e.children or {}) do if anytext(c, needle) then return true end end end
print("interrupt line:", (anytext(ip, "By interrupt") or anytext(ip, "По прерыванию")) and "ok" or "MISSING")
print("cargo block:", (anytext(ip, "Other") or anytext(ip, "Прочее")) and "ok" or "MISSING")
-- flight books: two hops, then parked
local fp = force.platforms[1]
fp.state = 2; fp.space_location = nil
fp.space_connection = {from={name="nauvis"}, to={name="vulcanus"}, length=15000}; fp.distance = 0.1
game.tick = game.tick + 600; nth[127]()
fp.distance = 0.9; game.tick = game.tick + 3600; nth[127]()
fp.space_connection = {from={name="vulcanus"}, to={name="gleba"}, length=9000}; fp.distance = 0.05
game.tick = game.tick + 1200; nth[127]()
fp.distance = 0.5; game.tick = game.tick + 1800; nth[127]()
handlers.on_gui_click({player_index=1, element={valid=true, name="x", tags={tr="goto", sub="platforms"}}})
print("trip flying:", anytext(PANE("platforms"), "Flying") or anytext(PANE("platforms"), "В пути") and "ok" or "MISSING")
-- passing a planet on the way: no connection for a moment, still on the path - the route must keep the flown hops
fp.space_connection = nil; fp.space_location = {name="gleba"}; fp.state = 2
game.tick = game.tick + 120; nth[127]()
local PFm = require("scripts.platforms")
local prow = PFm.row(fp)
local ph = PFm.route(prow)
local nd = 0 for _, h in ipairs(ph or {}) do if h.kind == "done" then nd = nd + 1 end end
print("route while passing:", ph and #ph or "nil", "done hops:", nd, "(expected >= 2)")
fp.space_connection = nil; fp.space_location = {name="gleba"}; fp.state = 6
game.tick = game.tick + 600; nth[127]()
handlers.on_gui_click({player_index=1, element={valid=true, name="x", tags={tr="refresh"}}})
handlers.on_gui_click({player_index=1, element={valid=true, name="x", tags={tr="plat_pin", idx=3}}})
print("pin:", (storage.tr.gui[1].plat_pins or {})[3] and "ok" or "MISSING")
local hh = ((storage.tr.plat or {})[2] or {}).history
print("history nodes:", hh and hh[1] and #hh[1].nodes or "none", hh and hh[1] and table.concat(hh[1].nodes, ">") or "")
-- arrival at the target without standing there, then straight back: that is two flights
local sd = force.platforms[4]
sd.state = 2; sd.space_location = nil
sd.schedule = {current = 1, records = {{station = "gleba"}, {station = "nauvis"}}}
sd.space_connection = {from={name="vulcanus"}, to={name="gleba"}, length=9000}; sd.distance = 0.2
game.tick = game.tick + 300; nth[127]()
sd.distance = 0.8; game.tick = game.tick + 600; nth[127]()
sd.distance = 0.99; game.tick = game.tick + 600; nth[127]()
sd.schedule = {current = 2, records = {{station = "gleba"}, {station = "nauvis"}}}
sd.space_connection = {from={name="gleba"}, to={name="nauvis"}, length=12000}; sd.distance = 0.02
game.tick = game.tick + 300; nth[127]()
local h4 = ((storage.tr.plat or {})[1] or {}).history
print("arrival without stop:", h4 and h4[1] and table.concat(h4[1].nodes, ">") or "none")
local r4 = PFm.row(sd)
local f4 = PFm.flight(r4)
print("hop already changed:", f4 and f4.cur and (f4.cur.from .. ">" .. f4.cur.to) or "none")
-- nuclear roulette: two players agree, fate picks one, the rocket is launched, the victim is finished off
local RUm = require("scripts.roulette")
local function body()
  local fired = {}
  return {valid=true, position={x=10,y=20}, name="character", die=function(self) self.dead=true end,
    surface={valid=true, find_entities_filtered=function() return {} end,
      create_entity=function(_, a) end}, _fired=fired}
end
p1.character = body(); p2.character = body()
p1.character.surface.create_entity = function(a) _G.ROCKET = a; return {} end
p2.character.surface.create_entity = p1.character.surface.create_entity
RUm.start(p1); RUm.join(p2)
for i = 1, 90 do game.tick = game.tick + 60; nth[60]() end
local ro = storage.tr.roul
print("roulette:", ro.state, "victim:", tostring(ro.victim), "rocket:", _G.ROCKET and _G.ROCKET.name or "none",
  "victim dead:", tostring((ro.victim == p1.name and p1.character.dead) or (ro.victim == p2.name and p2.character.dead)))
-- the rest after the strike (live timer), the title only for the one who died, a cancelled quiz rests too
do
  print("roulette by default:", (RUm.status()), "(expected idle: no rest by default)")
  storage.tr.cfg.num = {["tr-s-roulette-cooldown"] = 60}
  local st, clock = RUm.status()
  print("roulette rest:", st, clock, "(expected cooldown 59:..)", "prize stat:", require("scripts.core").pstat(ro.victim, "roulette_lost"), "(expected 1)")
  storage.tr.roul.last_end = nil
  p1.admin = true
  storage.tr.roul.last_end = nil
  storage.tr.cfg.num = nil
  print("roulette after reset:", (RUm.status()), "(expected idle)")
  -- nobody joined: the quiz rests 5 minutes and a new one cannot be started
  RUm.start(p1)
  for i = 1, 70 do game.tick = game.tick + 60; nth[60]() end
  print("roulette nobody joined:", (RUm.status()), "(expected cooldown)")
  storage.tr.roul.last_end, storage.tr.roul.fail_until = nil, nil
  handlers.on_gui_click({player_index=1, element={valid=true, name="x", tags={tr="goto", sub="summary"}}})
  nth[60]()
  print("summary quiz line:", findt(PANE("summary"), "rou_status") and "ok" or "MISSING")
  storage.tr.mvp_hist = {{tick = 90000, names = {"Oleg"}, n = 2}, {tick = 300000, names = {}, n = 0}}
  handlers.on_gui_click({player_index=1, element={valid=true, name="x", tags={tr="mvp_hist_toggle"}}})
  print("mvp history opened:", findt(PANE("summary"), "mvp_hist_toggle") and "ok" or "MISSING")
  handlers.on_gui_click({player_index=1, element={valid=true, name="x", tags={tr="mvp_hist_toggle"}}})
end
print("trip last:", (anytext(PANE("platforms"), "Last flights") or anytext(PANE("platforms"), "Прошлые рейсы")) and "ok" or "MISSING")
handlers.on_gui_click({player_index=1, element={valid=true, name="x", tags={tr="goto", sub="where"}}})
nth[60]()
print("where live:", findt(PANE("where"), "where_line") and "ok" or "MISSING")
handlers.on_gui_closed({player_index=1, element=p1.gui.screen.tr_frame})
print("esc closes:", p1.gui.screen.tr_frame and "STILL OPEN" or "closed")
require("scripts.gui").toggle(p1)   -- the window is needed by the checks below
print("reopened:", p1.gui.screen.tr_frame and "ok" or "FAILED", "opened =", p1.opened and "set" or "nil")
print("--- lost platforms / item search / shown title ---")
do
  local dd = storage.tr
  dd.plat_lost = {{name="Alpha", tick=game.tick, at="nauvis", route={"nauvis","gleba"}, cause="gleba-spawner", trips=3, ast=10},
                  {name="Beta", tick=game.tick-100, from="nauvis", to="vulcanus", route={}, damage="physical", trips=0, ast=0}}
  dd.plat_lost_n = 7
  handlers.on_gui_click({player_index=1, element={valid=true, name="x", tags={tr="goto", sub="platforms"}}})
  local pp = PANE("platforms")
  print("lost button:", (anytext(pp, "Destroyed: 7") or anytext(pp, "Уничтожены: 7")) and "ok" or "MISSING")
  handlers.on_gui_click({player_index=1, element={valid=true, name="x", tags={tr="plat_lost_toggle"}}})
  pp = PANE("platforms")
  print("lost cause named:", anytext(pp, "gleba-spawner") and "ok" or "MISSING")
  print("lost older:", (anytext(pp, "older ones") or anytext(pp, "ещё старше")) and "ok" or "MISSING")
  handlers.on_gui_click({player_index=1, element={valid=true, name="x", tags={tr="plat_lost_toggle"}}})
end
do
  -- the item search: a window, a pick, rows by planet from the most to the least, no zero rows
  setmetatable(game.surfaces, {__index = function(t, k) if type(k) == "string" then for _, s in ipairs(t) do if s.name == k then return s end end end end})
  prototypes.item["iron-plate"] = prototypes.item["iron-plate"] or {localised_name = {"item-name.iron-plate"}}
  force.logistic_networks = {
    nauvis = {{valid=true, get_item_count=function(it) return it.quality == "rare" and 5 or 120 end}, {valid=true, get_item_count=function(it) return 30 end}},
    castra = {{valid=true, get_item_count=function(it) return 0 end}}}
  handlers.on_gui_click({player_index=1, element={valid=true, name="x", tags={tr="find_open"}}})
  local ff = p1.gui.screen.tr_find
  print("find window:", ff and "ok" or "MISSING")
  handlers.on_gui_elem_changed({player_index=1, element={valid=true, tags={tr="find_pick"}, elem_value={name="iron-plate", quality="normal"}}})
  local rows = {}
  local function collect(e) if e.type == "table" then for _, c in ipairs(e.children) do rows[#rows + 1] = flat(c.caption or "") end end for _, c in ipairs(e.children or {}) do collect(c) end end
  collect(ff)
  print("find rows:", table.concat(rows, " | "))
  print("find total:", (anytext(ff, "150") ~= nil) and "ok" or "MISSING")
  handlers.on_gui_elem_changed({player_index=1, element={valid=true, tags={tr="find_pick"}, elem_value={name="iron-plate", quality="rare"}}})
  print("find rare:", anytext(ff, "5") and "ok" or "MISSING")
  -- a click on a place: chests with the item are listed and the camera goes there
  defines.inventory.chest = 1
  local marks_made, marks_gone = 0, 0
  local function mk() marks_made = marks_made + 1 local o = {valid=true} function o.destroy() o.valid=false marks_gone = marks_gone + 1 end return o end
  rendering.draw_sprite = mk
  game.surfaces[1].create_entity = function(spec) assert(spec.name == "highlight-box", "wrong entity") return mk() end
  force.logistic_networks.nauvis[1].storages = {{valid=true, unit_number=1, type="container", name="storage-chest", position={x=3,y=4}, selection_box={left_top={x=2.5,y=3.5}, right_bottom={x=3.5,y=4.5}}, get_inventory=function() return {get_item_count=function(f) return 90 end} end}}
  force.logistic_networks.nauvis[1].providers = {{valid=true, unit_number=2, type="logistic-container", name="passive-provider-chest", position={x=8,y=9}, get_inventory=function() return {get_item_count=function(f) return 30 end} end},
    -- a machine that is not a container: its own inventory is not looked at (a foundry with something in the input must not be found)
    {valid=true, unit_number=6, type="logistic-container", name="requester-in-providers", prototype={logistic_mode="requester"}, position={x=50,y=51}, get_inventory=function() return {get_item_count=function(f) return 33 end} end},
    {valid=true, unit_number=9, type="character", name="character", player={name="Oleg"}, position={x=70,y=71}, get_item_count=function(f) return 12 end},
    {valid=true, unit_number=3, type="foundry", name="foundry", position={x=20,y=20}, get_inventory=function() return {get_item_count=function(f) return 999 end} end}}
  -- buffer chests are neither storages nor providers: they are found among the members, a requester chest is not
  force.logistic_networks.nauvis[1].logistic_members = {
    {valid=true, unit_number=4, type="logistic-container", name="buffer-chest", prototype={logistic_mode="buffer"}, position={x=30,y=31}, get_inventory=function() return {get_item_count=function(f) return 77 end} end},
    {valid=true, unit_number=5, type="logistic-container", name="requester-chest", prototype={logistic_mode="requester"}, position={x=40,y=41}, get_inventory=function() return {get_item_count=function(f) return 55 end} end}}
  handlers.on_gui_elem_changed({player_index=1, element={valid=true, tags={tr="find_pick"}, elem_value={name="iron-plate", quality="normal"}}})
  -- the player's own character carries 12: it can be clicked too, the coordinates are in the tooltip
  local oldch = p1.character
  p1.character = {valid=true, surface=game.surfaces[1], position={x=70,y=71}, get_item_count=function() return 12 end}
  local go = findtag(ff, "find_go")
  handlers.on_gui_click({player_index=1, element=go})
  print("find chests:", (anytip(ff, "(3, 4)") and anytip(ff, "(8, 9)")) and "ok" or "MISSING")
  print("find chest row has name and item icon:", (anytext(ff, "storage-chest") and anytext(ff, "[item=iron-plate,quality=normal]")) and "ok" or "MISSING")
  print("find player holding the item:", (anytext(ff, "bruklyn.ben") and anytip(ff, "(70, 71)") and findtag(ff, "find_chest", nil)) and "ok" or "MISSING")
  print("find foundry skipped:", anytip(ff, "(20, 20)") and "WRONG" or "ok")
  print("find buffer chest:", (anytip(ff, "(30, 31)") and not anytip(ff, "(40, 41)") and not anytip(ff, "(50, 51)")) and "ok" or "MISSING/WRONG")
  print("find marks drawn:", marks_made > 0 and "ok" or "MISSING")
  local ch = findtag(ff, "find_chest")
  handlers.on_gui_click({player_index=1, element=ch})
  -- the scan of ordinary containers: the box is ticked, one planet per step; the one in a network is skipped
  handlers.on_gui_elem_changed({player_index=1, element={valid=true, tags={tr="find_pick"}, elem_value={name="iron-plate", quality="normal"}}})
  local outside = {valid=true, unit_number=7, type="container", name="wooden-chest", position={x=100,y=100}, get_inventory=function() return {get_item_count=function() return 61 end} end}
  local inside = {valid=true, unit_number=8, type="container", name="iron-chest", position={x=5,y=5}, logistic_network={}, get_inventory=function() return {get_item_count=function() return 500 end} end}
  game.surfaces[1].find_entities_filtered = function(f) if type(f.type) == "table" then return {outside, inside} end return {} end
  handlers.on_gui_checked_state_changed({player_index=1, element={valid=true, state=true, tags={tr="find_scan"}}})
  for i = 1, 6 do nth[7]() end
  p1.character = oldch
  print("scan outside:", (anytext(ff, "211") and not anytext(ff, "500")) and "ok" or "MISSING")
  handlers.on_gui_click({player_index=1, element=findtag(ff, "find_go")})
  print("scan chest listed:", anytip(ff, "(100, 100)") and "ok" or "MISSING")
  handlers.on_gui_checked_state_changed({player_index=1, element={valid=true, state=false, tags={tr="find_scan"}}})
  print("scan cancelled:", (storage.tr.find_job and storage.tr.find_job[1]) and "STILL" or "ok")
  handlers.on_gui_checked_state_changed({player_index=1, element={valid=true, state=true, tags={tr="find_mach"}}})
  for i = 1, 6 do nth[7]() end
  handlers.on_gui_click({player_index=1, element={valid=true, name="x", tags={tr="find_min"}}})
  print("find minimized:", (p1.gui.screen.tr_find and p1.gui.screen.tr_find.tr_find_box and not p1.gui.screen.tr_find.tr_find_box.visible) and "ok" or "WRONG")
  handlers.on_gui_click({player_index=1, element={valid=true, name="x", tags={tr="find_min"}}})
  handlers.on_gui_checked_state_changed({player_index=1, element={valid=true, state=false, tags={tr="find_mach"}}})
  handlers.on_gui_elem_changed({player_index=1, element={valid=true, tags={tr="find_pick"}, elem_value=nil}})
  print("find cleared hint:", (anytext(ff, "Pick an item") or anytext(ff, "Выбери предмет")) and "ok" or "MISSING")
  game.tick = math.ceil(game.tick / 300) * 300; nth[60]()   -- the open search window refreshes itself every 5 seconds
  print("find autorefresh:", "ok")
  handlers.on_gui_click({player_index=1, element={valid=true, name="x", tags={tr="find_close"}}})
  print("find closed:", p1.gui.screen.tr_find and "still" or "closed")
  print("find marks removed:", (marks_made > 0 and marks_gone == marks_made) and "ok" or ("MISSING " .. marks_made .. "/" .. marks_gone))
  -- quick access has the button
  local quick = p1.gui.screen.tr_frame and p1.gui.screen.tr_frame.tr_quick
  print("find button in quick access:", quick and findtag(quick, "find_open") and "ok" or "MISSING")
end
do
  -- the chosen title is the one shown, not the newest one
  local CC = require("scripts.core")
  local d2 = storage.tr
  d2.titles["Oleg"] = {exterminator = 100, foreman = 900}
  d2.tags[2] = {on = true, id = "exterminator"}
  print("shown title (chosen):", CC.shown_title("Oleg"), "(expected exterminator)")
  d2.tags[2] = {on = true, id = "auto"}
  print("shown title (auto):", CC.shown_title("Oleg"), "(expected foreman)")
end
do
  storage.tr.dest_recent = {{tick=game.tick, planet="nauvis", what="stone-wall", by="damage:poison", enemy=false, whose="Oleg"},
                            {tick=game.tick-60, planet="nauvis", what="gun-turret", by="small-biter", enemy=true, whose="bruklyn.ben"}}
  handlers.on_gui_click({player_index=1, element={valid=true, name="x", tags={tr="goto", sub="destruction"}}})
  local dp = PANE("destruction")
  print("recent destruction head:", (anytext(dp, "Последние разрушения") or anytext(dp, "Latest destruction")) and "ok" or "MISSING")
  print("recent destruction effect label:", (anytext(dp, "эффект:") or anytext(dp, "effect:")) and "ok" or "MISSING")
end
do
  storage.tr.pbuilt = {nauvis = {Oleg = 4242424}}
  storage.tr.gui[1] = storage.tr.gui[1] or {}
  storage.tr.gui[1].scope = "total"
  handlers.on_gui_click({player_index=1, element={valid=true, name="x", tags={tr="goto", sub="summary"}}})
  local sp = PANE("summary")
  local shown = anytext(sp, "(4.2") and "ok" or "MISSING"
  print("all-time leader built (census):", shown)
  print("leader label capital:", (anytext(sp, "Больше всех") or anytext(sp, "Top ")) and "ok" or "MISSING")
  storage.tr.gui[1].scope = nil
end
print("--- reset/undo ---")
for _,sec in ipairs({"players","records","combat","destruction","platforms","quality","energy","journal","titles","achievements","research"}) do
  handlers.on_gui_click({player_index=1, element={valid=true, name="x", tags={tr="reset", sec=sec}}})
end
print("after reset total Oleg:", storage.tr.total["Oleg"] and "has" or "nil")
for _,tn in ipairs({"players","records","combat","destruction","platforms","quality","energy","journal","titles","achievements","research"}) do dump(PANE(tn),0) end
handlers.on_gui_click({player_index=1, element={valid=true, name="x", tags={tr="undo", sec="players"}}})
print("after undo total Oleg:", storage.tr.total["Oleg"] and "has" or "nil")
print("--- mvp: our own pick, auto MVP, unrecognized genius, zap at the same target ---")
do
  local SHm = require("scripts.shift")
  local d = storage.tr
  local A, B = p1.name, p2.name
  d.shift = {[A] = {kills = 100, built = 10, mined = 0, walk = 500}, [B] = {kills = 10, built = 90, mined = 0, walk = 100}}
  d.mvp = {[A] = B}
  local pk, why = SHm.pick()
  print("pick:", pk, #why, flat(SHm.why_ls(why)), "(expected", A, ")")
  -- B voted for... nobody picked A: A is the genius
  d.mvp = {[A] = B}
  commands.cmds["tr-shift-now"]({player_index = 1})
  print("genius_missed:", storage.tr.pstat[A] and storage.tr.pstat[A].genius_missed, "(expected 1)")
  d.shift = {[A] = {kills = 100, built = 10, mined = 0, walk = 500}, [B] = {kills = 10, built = 90, mined = 0, walk = 100}}
  d.mvp = {}
  commands.cmds["tr-shift-now"]({player_index = 1})
  local h = storage.tr.mvp_hist[#storage.tr.mvp_hist]
  print("auto mvp:", h.auto, h.names[1], "(expected true", A, ")")
  for _, je in ipairs(storage.tr.journal) do
    if type(je.text) == "table" and (je.text[1] == "tr-msg.mvp-auto-j" or je.text[1] == "tr-msg.genius-j") then
      print("journal why:", flat(je.text))
    end
  end
  storage.tr.gui = storage.tr.gui or {}
  -- the hist is drawn
  local ZP = require("scripts.zap")
  print("zap blocked twice at one target:", tostring(ZP.blocked(p1, p2)))
end
do local old = helpers.is_valid_sprite_path; helpers.is_valid_sprite_path = function(s) return s ~= "item/iron-plate" end
print("chat_rich:", require("scripts.core").chat_rich("[planet=nauvis] [virtual-signal=signal-A] [item=iron-plate,quality=rare] [color=1,0,0]Penguin[/color] [foo=bar]")); helpers.is_valid_sprite_path = old end
print("--- shift close ---")
out_counter = 3000 _G.EVO = 0.023
commands.cmds["tr-shift-now"]({player_index=1})
p2.afk_time = 11*3600
nth[127]()
for i=1,200 do game.tick = game.tick + 6; nth[6]() end
print("afk drawn", _G.drawn, "destroyed", _G.destroyed)
print("afk texts:", table.concat((function() local o={} for i=1,math.min(12,#_G.texts) do o[i]=flat(_G.texts[i]) end return o end)(), " | "))
handlers.on_gui_click({player_index=1, element=findtag(fr, "close") or {valid=true,name="x",tags={tr="close"}}})
print("frame after close:", p1.gui.screen.tr_frame and "still" or "closed")
local m = {} for k in pairs(_G.MISSING) do m[#m+1]=k end table.sort(m)
print("MISSING KEYS:", #m, table.concat(m, ", "))
-- space tabs open with the research of the rocket silo or the space platform
print("--- space gate ---")
do
  local C0 = require("scripts.core")
  local G0 = require("scripts.gui")
  local function has_space() local fr = p1.gui.screen.tr_frame; return fr and fr.tr_tabs and fr.tr_tabs["tr_grp_space"] ~= nil end
  force.technologies = {["rocket-silo"] = {researched = false}, ["space-platform"] = {researched = false}}
  print("locked:", C0.space_unlocked() and "WRONG" or "ok")
  if not p1.gui.screen.tr_frame then G0.toggle(p1) end
  C0.hooks.space_unlocked()
  print("space tab hidden while locked:", has_space() and "WRONG" or "ok")
  handlers.on_gui_click({player_index=1, element={valid=true, name="x", tags={tr="goto", sub="summary"}}})
  pcall(require("scripts.research").on_research_finished, {research = {valid = true, name = "space-platform", localised_name = {"x"}, force = {name = "player"}}})
  force.technologies["space-platform"].researched = true
  C0.hooks.space_unlocked()
  print("unlocked by the research:", C0.space_unlocked() and "ok" or "WRONG")
  print("space tab shown after the research:", has_space() and "ok" or "WRONG")
  force.technologies = nil
  print("no such technologies: open:", C0.space_unlocked() and "ok" or "WRONG")
end
