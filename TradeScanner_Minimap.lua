-- TradeScanner_Minimap.lua

local TS = TradeScanner
local MM = {}
TS.Minimap = MM

local RADIUS = 80

local function GetAngle()
    return (TS.db and TS.db.minimapAngle) or 225
end

local function SaveAngle(a)
    if TS.db then TS.db.minimapAngle = a end
end

local function ApplyPosition(btn, angle)
    local rad = math.rad(angle)
    btn:ClearAllPoints()
    btn:SetPoint("CENTER", Minimap, "CENTER",
        RADIUS * math.cos(rad),
        RADIUS * math.sin(rad))
end

local function SetupTooltip(btn, mm)
    btn:SetScript("OnEnter", function(b)
        GameTooltip:SetOwner(b, "ANCHOR_LEFT")
        GameTooltip:SetText("Guild Economy", 0, 0.8, 1)
        GameTooltip:AddLine("Left-click: open/close", 1, 1, 1)
        GameTooltip:AddLine("Right-drag: move button", 0.6, 0.6, 0.6)
        if mm.pendingAlerts and mm.pendingAlerts > 0 then
            GameTooltip:AddLine(string.format(
                "|cFFFFCC00%d craftable request(s)!|r", mm.pendingAlerts), 1, 1, 1)
        end
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", GameTooltip_Hide)
end

local function SetupDrag(btn)
    btn:SetMovable(true)
    btn:RegisterForDrag("RightButton")
    btn:SetScript("OnDragStart", function(b)
        b:SetScript("OnUpdate", function(b2)
            local mx, my  = Minimap:GetCenter()
            local scale   = UIParent:GetEffectiveScale()
            local px, py  = GetCursorPosition()
            px, py = px / scale, py / scale
            local angle   = math.deg(math.atan2(py - my, px - mx))
            SaveAngle(angle)
            ApplyPosition(b2, angle)
        end)
    end)
    btn:SetScript("OnDragStop", function(b)
        b:SetScript("OnUpdate", nil)
    end)
end

function MM:Build()
    if self.btn then return end

    local btn = CreateFrame("Button", "TradeScannerMinimapBtn", UIParent)
    btn:SetSize(32, 32)
    btn:SetFrameStrata("MEDIUM")
    btn:SetFrameLevel(8)
    btn:SetClampedToScreen(false)

    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetTexture("Interface\\Minimap\\UI-Minimap-ZoneButton-Background")

    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetSize(20, 20)
    icon:SetPoint("CENTER", 0, 0)
    icon:SetTexture("Interface\\Icons\\INV_Misc_Bag_08")
    self.icon = icon

    local border = btn:CreateTexture(nil, "OVERLAY")
    border:SetSize(56, 56)
    border:SetPoint("CENTER", 0, 0)
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

    local alertRing = btn:CreateTexture(nil, "OVERLAY")
    alertRing:SetSize(36, 36)
    alertRing:SetPoint("CENTER", 0, 0)
    alertRing:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    alertRing:SetVertexColor(1, 0.78, 0, 1)
    alertRing:Hide()
    self.alertRing = alertRing

    btn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoneButton-Highlight")
    btn:SetScript("OnClick", function(_, mouseBtn)
        if mouseBtn == "LeftButton" and TS.UI then
            TS.UI:Toggle()
            if TS.Net then TS.Net:BroadcastWho() end  -- clic = hardware event → s'annoncer cross-guilde
        end
    end)

    SetupTooltip(btn, self)
    SetupDrag(btn)
    ApplyPosition(btn, GetAngle())
    self.btn           = btn
    self.pendingAlerts = 0
end

function MM:SetAlert(active)
    if not self.btn then return end
    if active then
        self.pendingAlerts = (self.pendingAlerts or 0) + 1
        self.alertRing:Show()
        self.icon:SetVertexColor(1, 0.78, 0)
        local t = 0
        self.btn:SetScript("OnUpdate", function(_, dt)
            t = t + dt
            local alpha = 0.55 + 0.45 * math.abs(math.sin(t * math.pi))
            self.alertRing:SetAlpha(alpha)
        end)
    else
        self.pendingAlerts = 0
        self.alertRing:Hide()
        self.btn:SetScript("OnUpdate", nil)
        self.icon:SetVertexColor(1, 1, 1)
    end
end

function MM:Init()
    self:Build()
end
