--[[
    RedLoc - UI.lua
    Hanterar allt visuellt:
      - Röd overlay på låsta items i väskan
      - "Lås / Lås upp"-alternativ i Blizzards högerklicksmeny
--]]

local addonName, ns = ...


-- ============================================================
-- Overlay-cache
-- Återanvänder samma frame-objekt för att minimera minnesanvändning
-- ============================================================

local overlayCache = {}     -- { [button] = texture }

--- Hämtar (eller skapar) en overlay-texture för en given knapp.
--- @param button Frame  Väsk-knappen (ContainerFrameItemButton)
--- @return Texture
local function GetOverlay(button)
    if overlayCache[button] then
        return overlayCache[button]
    end

    -- Skapa en ny halvtransparent röd texture ovanpå knappen
    local overlay = button:CreateTexture(nil, "OVERLAY", nil, 7)
    overlay:SetAllPoints(button)
    overlay:SetColorTexture(1, 0, 0, 0.38)  -- R, G, B, Alpha
    overlay:Hide()

    overlayCache[button] = overlay
    return overlay
end

--- Uppdaterar overlyen för en enskild knapp baserat på låsstatus.
--- @param button Frame
local function UpdateOverlay(button)
    -- Hämta påse och slot från knappen (moderna WoW)
    local bagID  = button.bagID or (button:GetBagID and button:GetBagID())
    local slotID = button:GetID()

    if not bagID or not slotID then return end

    local info    = C_Container.GetContainerItemInfo(bagID, slotID)
    local overlay = GetOverlay(button)

    if info and ns:IsLocked(info.itemGUID) then
        overlay:Show()
    else
        overlay:Hide()
    end
end

--- Koppla in oss i WoW:s egna uppdatering av väsk-knappar.
--- hooksecurefunc kör vår kod EFTER den ursprungliga koden, utan att störa säkerheten.
hooksecurefunc("ContainerFrameItemButton_Update", function(button)
    UpdateOverlay(button)
end)

-- ============================================================
-- Skärm-overlay (mörknar skärmen när lås-läge är aktivt)
-- ============================================================

local screenOverlay = CreateFrame("Frame", nil, UIParent)
screenOverlay:SetAllPoints(UIParent)
screenOverlay:SetFrameStrata("DIALOG")

local screenTexture = screenOverlay:CreateTexture(nil, "BACKGROUND")
screenTexture:SetAllPoints(screenOverlay)
screenTexture:SetColorTexture(0, 0, 0, 0.6)
screenOverlay:Hide()

--- Aktivera/inaktivera skärm-overlyen baserat på lås-läge.
function ns:SetLockModeOverlay(active)
    if active then
        screenOverlay:Show()
    else
        screenOverlay:Hide()
    end
end

-- ============================================================
-- Refresh-funktioner (anropas från Core.lua)
-- ============================================================

--- Uppdaterar overlyen för en specifik påse och slot.
--- @param bagID  number
--- @param slotID number
function ns:RefreshBagSlot(bagID, slotID)
    -- Försök hitta knappen via det gamla globala namnformatet
    -- Fungerar för de flesta WoW-versioner
    local buttonName = string.format("ContainerFrame%dItem%d", bagID + 1, slotID)
    local button     = _G[buttonName]

    if button then
        UpdateOverlay(button)
    end
end

--- Uppdaterar overlys för alla slots i alla påsar.
function ns:RefreshAllBags()
    for bagID = 0, 4 do
        local numSlots = C_Container.GetContainerNumSlots(bagID)
        for slotID = 1, numSlots do
            ns:RefreshBagSlot(bagID, slotID)
        end
    end
end


-- ============================================================
-- Högerklicksmeny – Blizzards moderna Menu-API (Dragonflight / TWW)
-- ============================================================

-- Spåra vilken knapp som senast högerklickades
local lastBagID, lastSlotID

--- Fånga högerklick på väsk-knappar för att veta vilket item som menas.
hooksecurefunc("ContainerFrameItemButton_OnClick", function(self, button)
    if button == "RightButton" then
        lastBagID  = self.bagID or (self:GetBagID and self:GetBagID())
        lastSlotID = self:GetID()
    end
end)

--- Lägg till RedLoc-alternativet i Blizzards eget högerklicksmeny för items.
--- Menu.ModifyMenu är den moderna API:n (Dragonflight+).
if Menu and Menu.ModifyMenu then
    Menu.ModifyMenu("ITEM", function(dropdown, rootDescription)
        -- Vi behöver ett känt item att arbeta med
        if not lastBagID or not lastSlotID then return end

        local info = C_Container.GetContainerItemInfo(lastBagID, lastSlotID)
        if not info or not info.itemGUID then return end

        local isLocked = ns:IsLocked(info.itemGUID)
        local label    = isLocked
            and "|cFF00FF00🔓 Lås upp (RedLoc)|r"
            or  "|cFFFF4444🔒 Lås (RedLoc)|r"

        -- Lägg till en avdelare och vår knapp i menyn
        rootDescription:CreateDivider()
        rootDescription:CreateButton(label, function()
            ns:ToggleLock(lastBagID, lastSlotID)
        end)
    end)
else
    --[[
        Fallback för äldre WoW-versioner som använder UIDropDownMenu.
        Om du spelar på en version äldre än Dragonflight, kontakta mig
        så kan vi lägga till stöd för det gamla API:et.
    --]]
    -- (Ej implementerat i v1.0)
end