-- Factory Radar: the chosen title next to the nick in chat (and on the map) through player.tag
-- player.tag is plain text, so the title is first translated to the owner's language
local C = require("scripts.core")
local M = {}

local function T(p)
  local t = C.D().tags
  t[p.index] = t[p.index] or {on = true, id = "auto"}
  return t[p.index]
end
M.T = T

-- which title to show now (nil = none)
function M.current(p)
  local st = T(p)
  if not (C.S("tr-chat-titles") and st.on) then return nil end
  local got = C.D().titles[p.name] or {}
  if st.id ~= "auto" and got[st.id] then return st.id end
  return C.best_title(p.name)
end

-- "[Title]" in the title colour, if the player did not turn colours off
-- a legendary title has syllables of different colours (the text is already so), the brackets stay plain
local function make_tag(p, id, text, colored)
  local tag = "[" .. text .. "]"
  if colored then return tag end
  if C.P(p, "tag-color") then tag = "[color=" .. C.title_color(id) .. "]" .. tag .. "[/color]" end
  return tag
end

local function clear(p, st)
  if st.set and p.tag == st.set then p.tag = "" end
  st.set = nil
  st.pending = nil
end

function M.apply(p)
  if not (p and p.valid) then return end
  local st = T(p)
  local id = M.current(p)
  if not id then clear(p, st) return end
  if not p.connected then return end      -- translation needs a connected player; applied again on join
  st.pending = id
  local name = C.title_tagname(id)     -- plain name, without the planet icon
  st.pending_colored = nil
  if type(name) == "string" then          -- an admin's own title: no translation needed
    st.pending = nil
    if p.tag ~= "" and p.tag ~= st.set then return end
    p.tag = make_tag(p, id, name)
    st.set = p.tag
    return
  end
  -- legendary title with colours: the coloured text of its name
  if C.LEGEND[id] and C.P(p, "tag-color") and name[1] == "tr-title." .. id then
    name = {"tr-title." .. id .. "-c"}
    st.pending_colored = true
  end
  st.pending_key = name[1]
  p.request_translation(name)
end

function M.on_translated(e)
  local p = game.get_player(e.player_index)
  if not p then return end
  local st = T(p)
  local ls = e.localised_string
  if not (st.pending and e.translated and type(ls) == "table" and ls[1] == st.pending_key) then return end
  local id = st.pending
  st.pending, st.pending_key = nil, nil
  local tag = make_tag(p, id, e.result, st.pending_colored)
  st.pending_colored = nil
  -- do not overwrite a tag the player set themselves through /tag
  if p.tag ~= "" and p.tag ~= st.set then return end
  p.tag = tag
  st.set = tag
end

function M.apply_all() for _, p in pairs(game.players) do M.apply(p) end end

C.on_title = function(p) if T(p).id == "auto" then M.apply(p) end end

return M
