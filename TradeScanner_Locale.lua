-- TradeScanner_Locale.lua
-- Localisation system. The key IS the English string; missing keys fall back to the key itself.
-- To add a locale: create Locale/xxXX.lua that checks GetLocale() and overrides TS.L entries.
local TS = TradeScanner
TS.L = setmetatable({}, { __index = function(_, k) return k end })
