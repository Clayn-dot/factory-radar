-- Factory Radar settings in the main menu (Settings, Mods, Startup)
-- Everything else (features, what is counted, chat, titles, personal) is set in game: team window, "Settings" tab
local function s(t) t.setting_type = "startup"; return t end
data:extend({
  s{type = "double-setting", name = "tr-s-shift-hours", default_value = 4, minimum_value = 0.25, maximum_value = 48, order = "a0"},
  s{type = "int-setting", name = "tr-s-afk-minutes", default_value = 10, minimum_value = 2, maximum_value = 120, order = "a1"},
  s{type = "int-setting", name = "tr-s-death-limit", default_value = 3, minimum_value = 1, maximum_value = 30, order = "a2"},
  s{type = "int-setting", name = "tr-s-journal", default_value = 100, minimum_value = 20, maximum_value = 1000, order = "a3"},
  s{type = "int-setting", name = "tr-s-history", default_value = 8, minimum_value = 3, maximum_value = 30, order = "a4"},
  s{type = "int-setting", name = "tr-s-idle-percent", default_value = 25, minimum_value = 0, maximum_value = 100, order = "a5"},
  s{type = "int-setting", name = "tr-s-min-output", default_value = 1000, minimum_value = 0, maximum_value = 100000000, order = "a6"},
  s{type = "int-setting", name = "tr-s-mvp-reminder", default_value = 5, minimum_value = 0, maximum_value = 120, order = "a7"},
  s{type = "int-setting", name = "tr-s-zap-percent", default_value = 10, minimum_value = 1, maximum_value = 50, order = "a9"},
  s{type = "bool-setting", name = "tr-s-roulette", default_value = true, order = "a92"},
  s{type = "int-setting", name = "tr-s-roulette-join", default_value = 60, minimum_value = 10, maximum_value = 300, order = "a94"},
  s{type = "bool-setting", name = "tr-s-shortcut", default_value = true, order = "b0"},
  s{type = "bool-setting", name = "tr-s-white-icon", default_value = true, order = "b1"},
})
