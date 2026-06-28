-- TradeScanner_Commands.lua
-- Slash command handler (/ts) split into per-command methods.

local TS = TradeScanner

function TS:_CmdProfs()
    if not self.Guild then return end
    local mine = self.Guild.myProfessions or self.Guild:DetectMyProfessions()
    print("|cFF00CCFFGuild Economy|r My professions: " ..
        (#mine > 0 and table.concat(mine, ", ") or "|cFF888888none|r"))
    local n = 0
    for player, info in pairs(self.db.guildRoster) do
        n = n + 1
        print(string.format("  |cFFCCCCCC%s|r : %s",
            player, table.concat(info.professions or {}, ", ")))
    end
    if n == 0 then print("  |cFF888888(no other member known yet)|r") end
end

-- Registre de recettes (#1/#2/#9) : sans argument, récap "connu/total" par métier ; avec un
-- objet shift-cliqué, qui dans la confédération connaît la recette qui le produit.
function TS:_CmdRecipes(arg)
    if not self.Registry then
        print("|cFF00CCFFGuild Economy|r Recipe registry unavailable (CraftLink missing).")
        return
    end
    local itemID = tonumber((arg or ""):match("item:(%d+)")) or tonumber(arg)
    if itemID then
        local info = self.staticItems and self.staticItems[itemID]
        local prof = info and info.profession
        if not prof then
            print("|cFF00CCFFGuild Economy|r Not a known craftable item.")
            return
        end
        local who = self.Registry:WhoKnowsItem(prof, itemID) or {}
        print(string.format("|cFF00CCFFGuild Economy|r %s |cFF888888[%s]|r known by: %s",
            self:GetItemName(itemID), prof,
            #who > 0 and table.concat(who, ", ") or "|cFF888888nobody known yet|r"))
        return
    end
    local summary = self.Registry:Summary()
    if #summary == 0 then
        print("|cFF00CCFFGuild Economy|r No recipes captured yet — open a profession window once.")
        return
    end
    print("|cFF00CCFFGuild Economy|r My known recipes (registry):")
    for _, e in ipairs(summary) do
        print(string.format("  |cFFE8B84B%s|r : %d / %d", e.prof, e.known, e.total))
    end
    print("  |cFF888888/ts recipes <shift-click item> — who can craft it|r")
end

function TS:_CmdScan()
    local count, prof = self:ScanOpenProfession()
    if prof then
        print(string.format("|cFF00CCFFGuild Economy|r %s: %d recipes indexed.", prof, count))
    else
        print("|cFF00CCFFGuild Economy|r Open a profession window first.")
    end
end

function TS:_CmdPanel()
    if not self.ProfPanel then
        print("|cFF00CCFFGuild Economy|r ProfPanel not loaded.")
        return
    end
    local name, isCraft = self:GetOpenProfessionInfo()
    if not name then
        print("|cFF00CCFFGuild Economy|r No profession window open (neither TradeSkill nor Craft).")
        return
    end
    print(string.format("|cFF00CCFFGuild Economy|r Profession: '%s' (%s) → canonical: '%s'",
        name, isCraft and "Craft" or "TradeSkill", tostring(self:ResolveProfession(name))))
    local ok, err = pcall(function() self.ProfPanel:OnTradeSkillShow() end)
    if not ok then print("|cFFFF4444Panel error:|r " .. tostring(err)) end
end

function TS:_CmdSell(arg)
    local itemID = tonumber((arg or ""):match("item:(%d+)")) or tonumber(arg)
    if itemID then
        if self.db.manualSellable[itemID] then
            self:RemoveManualSellable(itemID)
            print("|cFF00CCFFGuild Economy|r Removed from sellable: " .. self:GetItemName(itemID))
        else
            self:AddManualSellable(itemID)
            print("|cFF00CCFFGuild Economy|r Added to sellable: " .. self:GetItemName(itemID))
        end
    else
        print("|cFF00CCFFGuild Economy|r Usage: /ts sell <shift-click item>")
    end
end

function TS:_CmdExclude(arg)
    local itemID = tonumber((arg or ""):match("item:(%d+)")) or tonumber(arg)
    if itemID then
        local excluded = self:ToggleExcluded(itemID)
        local state = excluded and "|cFFFF4444excluded|r" or "|cFF33DD33included|r"
        print("|cFF00CCFFGuild Economy|r " .. self:GetItemName(itemID) .. " " .. state)
    else
        print("|cFF00CCFFGuild Economy|r Usage: /ts exclude <shift-click item>")
    end
end

function TS:_CmdChannel(arg)
    local sub, rest = (arg or ""):match("^(%S*)%s*(.*)$")
    sub = (sub or ""):lower()
    rest = (rest or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if sub == "add" and rest ~= "" then
        if self:AddWatchedChannel(rest) then
            print("|cFF00CCFFGuild Economy|r Watching channel: |cFF00CCFF" .. rest:lower() .. "|r")
        else
            print("|cFF00CCFFGuild Economy|r Already watched: " .. rest:lower())
        end
    elseif sub == "remove" and rest ~= "" then
        if self:RemoveWatchedChannel(rest) then
            print("|cFF00CCFFGuild Economy|r Stopped watching: |cFFFF4444" .. rest:lower() .. "|r")
        else
            print("|cFF00CCFFGuild Economy|r Not in watch list: " .. rest:lower())
        end
    elseif sub == "confed" and rest ~= "" then
        local on = self:ToggleConfedChannel(rest)
        local state = on and "|cFF33DD33ON|r" or "|cFFFF4444OFF|r"
        print("|cFF00CCFFGuild Economy|r Confederation-only filter for |cFF00CCFF"
              .. rest:lower() .. "|r: " .. state)
    elseif sub == "list" then
        print("|cFF00CCFFGuild Economy|r Watched channels: |cFF00CCFF" .. self:ChannelsLabel() .. "|r")
        local confed = {}
        for c in pairs(self.db.confedChannels or {}) do confed[#confed + 1] = c end
        if #confed > 0 then
            print("|cFF00CCFFGuild Economy|r Confederation-only: |cFFFFCC00" .. table.concat(confed, ", ") .. "|r")
        end
        print("|cFF00CCFFGuild Economy|r Default send channel: |cFF00CCFF" .. (self.db.channel or "?") .. "|r")
    elseif sub ~= "" then
        -- Rétro-compat : /ts channel <nom> définit le canal d'ENVOI par défaut.
        self.db.channel = (sub .. (rest ~= "" and (" " .. rest) or "")):lower()
        print("|cFF00CCFFGuild Economy|r Default send channel: |cFF00CCFF" .. self.db.channel .. "|r")
    else
        print("|cFF00CCFFGuild Economy|r Usage: /ts channel add|remove|list <name> (or <name> = set send channel)")
        print("|cFF00CCFFGuild Economy|r Watched: |cFF00CCFF" .. self:ChannelsLabel() .. "|r")
    end
    if self.UI and self.UI.Refresh then self.UI:Refresh() end
    if self.Settings and self.Settings.Refresh then self.Settings:Refresh() end
end

function TS:_CmdAdd(arg)
    local side, kw = (arg or ""):match("^(%S+)%s+(.+)")
    if side and kw and (side == "sell" or side == "buy" or side == "gift") then
        local kwUpper = kw:upper():gsub("%s+", "")
        table.insert(self.db.keywords[side], kwUpper)
        print(string.format("|cFF00CCFFGuild Economy|r Keyword [%s] added: |cFFFFFF00%s|r", side, kwUpper))
    else
        print("|cFF00CCFFGuild Economy|r Usage: /ts add sell|buy|gift <WORD>")
    end
end

function TS:_CmdRemove(arg)
    local side, kw = (arg or ""):match("^(%S+)%s+(.+)")
    if side and kw and (side == "sell" or side == "buy" or side == "gift") then
        local kwUpper = kw:upper():gsub("%s+", "")
        local list = self.db.keywords[side]
        for i = #list, 1, -1 do
            if list[i] == kwUpper then
                table.remove(list, i)
                print(string.format("|cFF00CCFFGuild Economy|r Keyword [%s] removed: |cFFFF4444%s|r", side, kwUpper))
                return
            end
        end
        print("|cFF00CCFFGuild Economy|r Keyword not found: " .. kwUpper)
    else
        print("|cFF00CCFFGuild Economy|r Usage: /ts remove sell <WORD> or /ts remove buy <WORD>")
    end
end

function TS:_CmdLog(arg)
    local n       = tonumber(arg) or 30
    local entries = (self.log and self.log.entries) or {}
    local shown   = math.min(n, #entries)
    print(string.format("|cFF00CCFFGuild Economy|r — Last %d messages (%d total):", shown, #entries))
    for i = 1, shown do
        local e   = entries[i]
        local age = time() - e.ts
        local col = e.r == "sell"      and "|cFF33DD33"
                 or e.r == "buy"       and "|cFF33AAFF"
                 or e.r == "skip_kw"   and "|cFFFF9900"
                 or e.r == "skip_chan" and "|cFF666666"
                 or "|cFFAAAAAA"
        local txt = e.m or ""
        if #txt > 70 then txt = txt:sub(1, 70) .. "…" end
        print(string.format("  %s[%s]|r %ds [%s] %s: %s",
            col, e.r, age, e.ch or "?", e.p or "?", txt))
    end
end

function TS:_CmdRetest(arg)
    local entries    = (self.log and self.log.entries) or {}
    local limit      = tonumber(arg) or 30
    local counts     = { sell = 0, buy = 0, skip_kw = 0 }
    local changes    = {}
    local considered = 0
    for _, e in ipairs(entries) do
        if e.r ~= "skip_chan" then
            considered = considered + 1
            local cls    = self:Classify(e.m or "")
            local newCat = cls.offerType or "skip_kw"
            counts[newCat] = (counts[newCat] or 0) + 1
            if newCat ~= e.r then
                table.insert(changes, { e = e, from = e.r, to = newCat, cls = cls })
            end
        end
    end
    print(string.format("|cFF00CCFFGuild Economy retest|r — %d messages replayed (excl. skip_chan)", considered))
    print(string.format("  result: |cFF33DD33sell=%d|r |cFF33AAFFbuy=%d|r |cFFFF9900skip_kw=%d|r — |cFFFFFF00%d changes|r",
        counts.sell or 0, counts.buy or 0, counts.skip_kw or 0, #changes))
    local shown = math.min(limit, #changes)
    for i = 1, shown do
        local ch  = changes[i]
        local txt = ch.e.m or ""
        if #txt > 55 then txt = txt:sub(1, 55) .. "…" end
        local extra = ""
        if #ch.cls.items > 0 then
            local parts = {}
            for _, it in ipairs(ch.cls.items) do
                parts[#parts + 1] = string.format("%s%s",
                    it.priceText or "—", it.qtyText and (" " .. it.qtyText) or "")
            end
            extra = " |cFF888888{" .. table.concat(parts, ", ") .. "}|r"
        elseif ch.cls.priceText then
            extra = " |cFF888888{" .. ch.cls.priceText .. "}|r"
        end
        print(string.format("  |cFFFFFF00%s→%s|r %s%s", tostring(ch.from), ch.to, txt, extra))
    end
    if #changes > shown then
        print(string.format("  … (+%d more; /ts retest %d to see all)", #changes - shown, #changes))
    end
end

function TS:_CmdErrors(arg)
    if arg == "clear" then
        if self.db then self.db.errorLog = {} end
        print("|cFF00CCFFGuild Economy|r Error log cleared.")
        return
    end
    local log = self.db and self.db.errorLog or {}
    if #log == 0 then
        print("|cFF00CCFFGuild Economy|r No Lua errors logged."); return
    end
    print(string.format("|cFF00CCFFGuild Economy|r — |cFFFF4444%d error(s)|r:", #log))
    for i, e in ipairs(log) do
        print(string.format("  |cFFFF4444[%d]|r |cFF888888%s|r %s", i, e.t, e.e))
    end
end

function TS:_CmdConfed()
    self.db.useGreenWall = not self.db.useGreenWall
    local state = self.db.useGreenWall and "|cFF33DD33enabled|r" or "|cFFFF4444disabled|r"
    print("|cFF00CCFFGuild Economy|r Cross-realm sync (GreenWall): " .. state ..
        " |cFF888888(disable to silence ADDON_ACTION_BLOCKED)|r")
end

function TS:_CmdGwDebug()
    self.db.gwDebug = not self.db.gwDebug
    local state = self.db.gwDebug and "|cFF33DD33ON|r" or "|cFFFF4444OFF|r"
    print("|cFF00CCFFGuild Economy|r GreenWall debug: " .. state ..
        " |cFF888888([GW->] envois, [GW<-] receptions cross-guilde)|r")
end

function TS:_CmdHelp()
    print("|cFF00CCFFGuild Economy|r --- Help ---")
    print("  /ts                       - open/close window")
    print("  /ts order                 - Guild Craft Orders panel")
    print("  /ts profs                 - my professions + guild roster")
    print("  /ts recipes [item]        - my known recipes / who can craft an item")
    print("  /ts clear                 - clear all offers")
    print("  /ts scan                  - scan open profession window")
    print("  /ts sell <shift-click>    - add/remove a manual sellable item")
    print("  /ts exclude <shift-click> - exclude/include an item from scan")
    print("  /ts settings              - open the settings panel")
    print("  /ts channel <name>        - set default send channel")
    print("  /ts channel add <name>    - watch an extra channel")
    print("  /ts channel remove <name> - stop watching a channel")
    print("  /ts channel confed <name> - toggle confederation-only filter on a channel")
    print("  /ts channel list          - list watched channels")
    print("  /ts guild                 - toggle /g scan (GreenWall)")
    print("  /ts wts                   - toggle bag Alt-right-click WTS shortcut")
    print("  /ts confed                - toggle cross-realm sync (GreenWall)")
    print("  /ts gwdebug               - toggle GreenWall send/recv debug prints")
    print("  /ts alert                 - toggle craft alert sound")
    print("  /ts debug                 - toggle real-time channel display")
    print("  /ts log [N]               - show last N messages (default: 30)")
    print("  /ts retest [N]            - replay parser on log (validate changes)")
    print("  /ts logclear              - clear the log")
    print("  /ts errors                - show recent Lua errors (TradeScanner)")
    print("  /ts errors clear          - clear error log")
    print("  /ts add sell <WORD>       - add a sell keyword")
    print("  /ts add buy <WORD>        - add a buy keyword")
    print("  /ts remove sell <WORD>    - remove a sell keyword")
    print("  /ts keywords              - list active keywords")
end

function TS:HandleSlash(msg)
    msg = msg or ""
    local cmd, arg = msg:lower():match("^%s*(%S*)%s*(.*)")
    cmd = cmd or ""
    if cmd == "" then
        if self.UI then self.UI:Toggle() end
    elseif cmd == "order" or cmd == "orders" then
        if self.OrderPanel then self.OrderPanel:Toggle() end
    elseif cmd == "settings" or cmd == "config" or cmd == "options" then
        if self.Settings then self.Settings:Toggle() end
    elseif cmd == "profs" or cmd == "professions" then
        self:_CmdProfs()
    elseif cmd == "recipes" then self:_CmdRecipes(arg)
    elseif cmd == "clear" then
        self.db.offers = {}
        if self.UI then self.UI:Refresh() end
        print("|cFF00CCFFGuild Economy|r Offers cleared.")
    elseif cmd == "scan" then self:_CmdScan()
    elseif cmd == "panel" then self:_CmdPanel()
    elseif cmd == "sell" then self:_CmdSell(arg)
    elseif cmd == "exclude" then self:_CmdExclude(arg)
    elseif cmd == "channel" then self:_CmdChannel(arg)
    elseif cmd == "add" then self:_CmdAdd(arg)
    elseif cmd == "remove" then self:_CmdRemove(arg)
    elseif cmd == "alert" then
        self.db.alertSound = not self.db.alertSound
        local state = self.db.alertSound and "|cFF33DD33enabled|r" or "|cFFFF4444disabled|r"
        print("|cFF00CCFFGuild Economy|r Craft alert sound: " .. state)
    elseif cmd == "debug" then
        self.db.debugLog = not self.db.debugLog
        local state = self.db.debugLog and "|cFF33DD33ON|r" or "|cFFFF4444OFF|r"
        print("|cFF00CCFFGuild Economy|r Debug log: " .. state .. " (each channel message shown)")
    elseif cmd == "log" then self:_CmdLog(arg)
    elseif cmd == "errors" then self:_CmdErrors(arg)
    elseif cmd == "logclear" then
        if self.log then self.log.entries = {} end
        print("|cFF00CCFFGuild Economy|r Log cleared.")
    elseif cmd == "retest" then self:_CmdRetest(arg)
    elseif cmd == "guild" then
        self.db.scanGuild = not self.db.scanGuild
        local state = self.db.scanGuild and "|cFF33DD33enabled|r" or "|cFFFF4444disabled|r"
        print("|cFF00CCFFGuild Economy|r Guild chat scan (GreenWall): " .. state)
    elseif cmd == "wts" then
        self.db.bagSellEnabled = not self.db.bagSellEnabled
        local state = self.db.bagSellEnabled and "|cFF33DD33enabled|r" or "|cFFFF4444disabled|r"
        print("|cFF00CCFFGuild Economy|r Bag Alt-right-click WTS shortcut: " .. state)
    elseif cmd == "confed" or cmd == "greenwall" then self:_CmdConfed()
    elseif cmd == "gwdebug" then self:_CmdGwDebug()
    elseif cmd == "keywords" or cmd == "kw" then
        print("|cFF00CCFFGuild Economy|r Sell keywords: " .. table.concat(self.db.keywords.sell, ", "))
        print("|cFF00CCFFGuild Economy|r Buy keywords:  " .. table.concat(self.db.keywords.buy,  ", "))
        print("|cFF00CCFFGuild Economy|r Gift keywords: " .. table.concat(self.db.keywords.gift or {}, ", "))
    elseif cmd == "help" then self:_CmdHelp()
    else
        if self.UI then self.UI:Toggle() end
    end
end
