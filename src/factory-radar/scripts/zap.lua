-- Factory Radar: дружеский удар молнией по другому игроку
-- Бьёт только по персонажу цели (без урона по площади и постройкам), забирает долю максимального здоровья,
-- но не убивает; у бьющего кулдаун, в одну цель могут бить несколько игроков. Числа ставит админ в игре (вкладка «Настройки»)
local C = require("scripts.core")
local M = {}

local function Z()
  local z = C.D().zap
  z.cd = z.cd or {}
  return z
end

-- nil, если удар разрешён, иначе локализованная причина
function M.blocked(from, to)
  if not C.S("tr-zap") then return {"tr-zap.off"} end
  if not (to and to.valid) then return {"tr-cmd.no-player", "?"} end
  if not to.connected then return {"tr-zap.offline", to.name} end
  if not (to.character and to.character.valid) then return {"tr-zap.nobody", to.name} end
  -- на космической платформе молнии нет (игрока в машине на планете ударить можно)
  local sf = to.physical_surface
  if sf and sf.valid and sf.platform then return {"tr-zap.platform", to.name} end
  local z = Z()
  local t = game.tick
  if (z.cd[from.index] or 0) > t then return {"tr-zap.cooldown", math.ceil((z.cd[from.index] - t) / 60)} end
  return nil
end

function M.seconds_left(p) local v = (Z().cd[p.index] or 0) - game.tick; return v > 0 and math.ceil(v / 60) or 0 end

-- Молния — линия с неба вниз: создаётся сверху, поэтому чтобы попасть в персонажа, её надо создавать на
-- несколько клеток выше. Сколько — ставит админ: /tr-zap-lift N (клеток, по умолчанию 25), /tr-zap-lift N T ещё
-- задаёт, на сколько тиков вперёд вести движущуюся цель (по умолчанию 12)
local function bolt(ch)
  local s = ch.surface
  local cfg = C.D().cfg
  local lift = cfg.zap_lift or 25
  local x, y = ch.position.x, ch.position.y
  -- движущаяся цель: удар приходит чуть позже создания молнии, так что целимся туда, где он будет
  pcall(function()
    local ws = ch.walking_state
    if ws and ws.walking and not (ch.player and ch.player.vehicle) then
      local speed = ch.character_running_speed or 0.15
      local ang = ws.direction * 2 * math.pi / 16
      local ticks = cfg.zap_lead or 12
      x, y = x + math.sin(ang) * speed * ticks, y - math.cos(ang) * speed * ticks
    end
  end)
  -- настоящая молния (картинка, звук, тряска) без урона. Создаётся как сущность: execute_lightning работает
  -- только на поверхностях с грозами. Нарисованная ниже молния — запас для игр без этого прототипа
  if prototypes.entity["tr-lightning"] then
    if pcall(s.create_entity, {name = "tr-lightning", position = {x = x, y = y - lift}}) then return end
  end
  local col = {0.75, 0.85, 1, 1}
  -- зигзаг с неба в голову
  local pts = {{0.4, -16}, {-0.6, -11}, {0.5, -7}, {-0.4, -3.5}, {0, -1.2}}
  for i = 1, #pts - 1 do
    pcall(rendering.draw_line, {color = col, width = 4, surface = s, time_to_live = 12,
      from = {entity = ch, offset = pts[i]}, to = {entity = ch, offset = pts[i + 1]}})
  end
  pcall(rendering.draw_light, {sprite = "utility/light_medium", scale = 3, intensity = 1, color = col,
    target = ch, surface = s, time_to_live = 10})
end

function M.zap(from, to)
  local why = M.blocked(from, to)
  if why then from.print(why, {color = {1, 0.7, 0.5}}) return false end
  local ch = to.character
  local pct = C.S("tr-s-zap-percent")
  local maxh = ch.max_health or (ch.prototype and ch.prototype.get_max_health and ch.prototype.get_max_health()) or 250
  ch.health = math.max(1, ch.health - maxh * pct / 100)
  bolt(ch)
  local z = Z()
  z.cd[from.index] = game.tick + C.S("tr-s-zap-cooldown") * 60
  C.pstat_add(from.name, "zaps", 1)
  C.pstat_add(to.name, "zapped", 1)
  C.check_ach(from)
  C.check_ach(to)
  local icon = (helpers.is_valid_sprite_path("entity/lightning") and "[img=entity/lightning]")
    or (helpers.is_valid_sprite_path("item/lightning-rod") and "[img=item/lightning-rod]") or "[img=utility/electricity_icon]"
  C.send("zap", {"tr-msg.zap", from.name, to.name, pct, icon}, {from = from.name, to = to.name, percent = pct},
    {0.75, 0.85, 1}, nil, false)
  return true
end

return M
