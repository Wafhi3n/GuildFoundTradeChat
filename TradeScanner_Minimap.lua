-- TradeScanner_Minimap.lua

local TS = TradeScanner
local MM = {}
TS.Minimap = MM

local RADIUS_PADDING = 5  -- distance entre le bord du minimap et le centre du bouton (même valeur que LibDBIcon)

local function GetAngle()
    return (TS.db and TS.db.minimapAngle) or 225
end

local function SaveAngle(a)
    if TS.db then TS.db.minimapAngle = a end
end

local function GetRadius()
    return (Minimap:GetWidth() / 2) + RADIUS_PADDING
end

local function ApplyPosition(btn, angle)
    local rad = math.rad(angle)
    local r   = GetRadius()
    btn:ClearAllPoints()
    btn:SetPoint("CENTER", Minimap, "CENTER", r * math.cos(rad), r * math.sin(rad))
end

local function SetupTooltip(btn, mm)
    btn:SetScript("OnEnter", function(b)
        GameTooltip:SetOwner(b, "ANCHOR_LEFT")
        GameTooltip:SetText("Guild Economy", 0, 0.8, 1)
        GameTooltip:AddLine(TS.L["Left-click: open/close"], 1, 1, 1)
        GameTooltip:AddLine(TS.L["Right-drag: move button"], 0.6, 0.6, 0.6)
        if mm.pendingAlerts and mm.pendingAlerts > 0 then
            GameTooltip:AddLine("|cFFFFCC00" .. string.format(
                TS.L["%d craftable request(s)!"], mm.pendingAlerts) .. "|r", 1, 1, 1)
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
            local scale   = Minimap:GetEffectiveScale()
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

    local btn = CreateFrame("Button", "TradeScannerMinimapBtn", Minimap)
    btn:SetSize(31, 31)
    btn:SetFrameStrata("MEDIUM")
    btn:SetFrameLevel(8)
    btn:SetClampedToScreen(false)

    -- Placement standard LibDBIcon. La texture MiniMap-TrackingBorder dessine
    -- l'anneau dans le coin HAUT-GAUCHE de son cadre 53×53 : il faut donc l'ancrer
    -- en TOPLEFT (et non centrée) et décaler le fond/l'icône de (7,-5)/(7,-6) pour
    -- qu'ils tombent à l'intérieur de l'anneau. Centrer le cadre poussait l'anneau
    -- vers le bas-droite par rapport à l'icône → c'était le bug « cercle décalé ».
    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetSize(20, 20)
    bg:SetPoint("TOPLEFT", 7, -5)
    bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")

    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetSize(17, 17)
    icon:SetPoint("TOPLEFT", 7, -6)
    icon:SetTexture("Interface\\Icons\\INV_Misc_Bag_08")
    self.icon = icon

    local border = btn:CreateTexture(nil, "OVERLAY")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT", 0, 0)
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    self.border = border

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
        self.icon:SetVertexColor(1, 0.78, 0)
        local t = 0
        self.btn:SetScript("OnUpdate", function(_, dt)
            t = t + dt
            local v = 0.6 + 0.4 * math.abs(math.sin(t * math.pi))
            self.border:SetVertexColor(1, 0.78 * v, 0)
        end)
    else
        self.pendingAlerts = 0
        self.btn:SetScript("OnUpdate", nil)
        self.border:SetVertexColor(1, 1, 1)
        self.icon:SetVertexColor(1, 1, 1)
    end
end

function MM:Init()
    self:Build()
end
