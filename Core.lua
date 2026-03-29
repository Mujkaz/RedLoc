--[[
    RedLoc - Core.lua
    Hanterar all grundläggande logik: initiering, låsning/upplåsning och handlarskydd.

    Filstruktur:
        RedLoc.toc   → Addon-metadata
        Core.lua     → Logik (denna fil)
        UI.lua       → Visuella delar (overlay, högerklicksmeny)
--]]

local addonName, ns = ...   -- "ns" (namespace) är vår delade tabell mellan filer

ns.VERSION = "1.0.0"

-- ============================================================
-- Interna variabler
-- ============================================================

ns.lockedItems  = {}    -- { [itemGUID] = true }
ns.merchantOpen = false -- true när handlare är öppen


-- ============================================================
-- Initiering
-- ============================================================

local eventFrame = CreateFrame("Frame")

local function OnInitialize()
    -- RedLocDB skapas automatiskt av WoW om den inte finns
    RedLocDB = RedLocDB or {
        version      = 1,
        lockedItems  = {},
    }

    -- Peka vår lokala tabell mot den sparade datan
    ns.lockedItems = RedLocDB.lockedItems

    -- Meddela spelaren i chatten (kan tas bort om det känns störande)
    -- print("|cFFFF4444[RedLoc]|r laddad. Skriv |cFFFFFF00/redloc help|r för hjälp.")
end

eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("MERCHANT_SHOW")
eventFrame:RegisterEvent("MERCHANT_CLOSED")

eventFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 == addonName then
            OnInitialize()
            -- Vi behöver inte längre lyssna på ADDON_LOADED
            self:UnregisterEvent("ADDON_LOADED")
        end

    elseif event == "MERCHANT_SHOW" then
        ns.merchantOpen = true
        ns:OnMerchantOpen()

    elseif event == "MERCHANT_CLOSED" then
        ns.merchantOpen = false
    end
end)


-- ============================================================
-- Kärnfunktioner
-- ============================================================

--- Kontrollerar om ett item är låst.
--- @param itemGUID string  Det unika ID:t för itemet.
--- @return boolean
function ns:IsLocked(itemGUID)
    if not itemGUID or itemGUID == "" then return false end
    return ns.lockedItems[itemGUID] == true
end

--- Växlar låsstatus för ett item i en specifik påse och slot.
--- @param bagID  number  Påsens ID (0 = ryggsäck, 1-4 = övriga påsar)
--- @param slotID number  Slotens ID i påsen
function ns:ToggleLock(bagID, slotID)
    local info = C_Container.GetContainerItemInfo(bagID, slotID)

    -- Säkerhetskontroll: finns det ett item här?
    if not info then
        print("|cFFFF4444[RedLoc]|r Inget item hittades.")
        return
    end

    -- Säkerhetskontroll: har itemet ett unikt ID?
    local guid = info.itemGUID
    if not guid or guid == "" then
        print("|cFFFF4444[RedLoc]|r Detta item stöds inte (inget GUID).")
        return
    end

    local link = info.hyperlink or "Okänt item"

    if ns:IsLocked(guid) then
        ns.lockedItems[guid] = nil
        UIErrorsFrame:AddExternalErrorMessage("[RedLoc] Upplåst: " .. link)
    else
        ns.lockedItems[guid] = true
        UIErrorsFrame:AddExternalErrorMessage("[RedLoc] Låst: " .. link)
    end

    -- Uppdatera den visuella overlyen för just denna slot
    ns:RefreshBagSlot(bagID, slotID)
end


-- ============================================================
-- Handlarskydd
-- ============================================================

--- Körs när spelaren öppnar en handlare.
--- Varnar om det finns låsta items i väskan.
function ns:OnMerchantOpen()
    local lockedCount = 0

    for bagID = 0, 4 do
        local numSlots = C_Container.GetContainerNumSlots(bagID)
        for slotID = 1, numSlots do
            local info = C_Container.GetContainerItemInfo(bagID, slotID)
            if info and ns:IsLocked(info.itemGUID) then
                lockedCount = lockedCount + 1
            end
        end
    end

    if lockedCount > 0 then
        local msg = string.format(
            "|cFFFF4444[RedLoc]|r Du har |cFFFFFF00%d|r låst(a) item(s) i väskan. " ..
            "De är skyddade mot oavsiktlig försäljning.",
            lockedCount
        )
        print(msg)
    end
end

--[[
    NOTERING: Fullständigt säljskydd (blockera högerklick på låsta items hos
    handlare) kräver SecureFrame-teknik och testas i v1.1.
    För nu varnar vi spelaren när handlaren öppnas.
--]]


-- ============================================================
-- Slash-kommandon  (/redloc eller /rloc)
-- ============================================================

SLASH_REDLOC1 = "/redloc"
SLASH_REDLOC2 = "/rloc"

SlashCmdList["REDLOC"] = function(msg)
    -- Rensa inmatning
    local cmd = (msg or ""):lower():match("^%s*(.-)%s*$")

    if cmd == "help" or cmd == "" then
        print("|cFFFF4444[RedLoc]|r v" .. ns.VERSION .. " – Kommandon:")
        print("  |cFFFFFF00/redloc help|r  – Visa denna hjälp")
        print("  |cFFFFFF00/redloc list|r  – Lista antal låsta items")
        print("  |cFFFFFF00/redloc clear|r – Lås upp alla items")
        print("  |cFFFFFF00Högerklicka|r på ett item i väskan för att låsa/låsa upp.")

    elseif cmd == "list" then
        local count = 0
        for _ in pairs(ns.lockedItems) do count = count + 1 end
        if count == 0 then
            print("|cFFFF4444[RedLoc]|r Inga låsta items.")
        else
            print("|cFFFF4444[RedLoc]|r " .. count .. " låst(a) item(s) för denna karaktär.")
        end

    elseif cmd == "clear" then
        wipe(ns.lockedItems)
        print("|cFFFF4444[RedLoc]|r Alla items upplåsta.")
        ns:RefreshAllBags()

    else
        print("|cFFFF4444[RedLoc]|r Okänt kommando '|cFFFFFF00" .. cmd .. "|r'. Skriv /redloc help.")
    end
end