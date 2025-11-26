-- Configuration & Constants --
local TOAST_DURATION = 4.0
local FADE_DURATION = 0.5
local FRAME_WIDTH = 250
local FRAME_HEIGHT = 50 -- Increased for extra text
local MAX_TOASTS = 3
local POS_POINT = "TOP"
local POS_X = 0
local POS_Y = -150
local SPACING = 10

-- Defaults
local defaults = {
    hideInRaid = false,
    hideInBG = false,
    hideInArena = false,
    anchorPoint = "TOP",
    anchorX = 0,
    anchorY = -150,
}

local _G = _G
local pairs, string, time, table = pairs, string, time, table
local GetFriendInfo, GetNumFriends = GetFriendInfo, GetNumFriends
local SendChatMessage = SendChatMessage
local PlaySound = PlaySound
local InCombatLockdown = InCombatLockdown
local IsInInstance = IsInInstance
local RAID_CLASS_COLORS = RAID_CLASS_COLORS

-- Event Frame
local EventFrame = CreateFrame("Frame")
EventFrame:RegisterEvent("ADDON_LOADED")
EventFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == "ZenToast" then
        if not ZenToastDB then ZenToastDB = {} end
        for k, v in pairs(defaults) do
            if ZenToastDB[k] == nil then ZenToastDB[k] = v end
        end
        self:UnregisterEvent("ADDON_LOADED")

        -- Setup Options Panel
        local panel = CreateFrame("Frame", "ZenToastOptions", UIParent)
        panel.name = "ZenToast"
        InterfaceOptions_AddCategory(panel)

        local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
        title:SetPoint("TOPLEFT", 16, -16)
        title:SetText("ZenToast Options")

        local function CreateCheck(label, key, yOffset)
            local cb = CreateFrame("CheckButton", "ZenToastCheck"..key, panel, "InterfaceOptionsCheckButtonTemplate")
            cb:SetPoint("TOPLEFT", 16, yOffset)
            _G[cb:GetName().."Text"]:SetText(label)
            cb:SetChecked(ZenToastDB[key])
            cb:SetScript("OnClick", function(self)
                ZenToastDB[key] = self:GetChecked()
            end)
            return cb
        end

        CreateCheck("Hide in Raid", "hideInRaid", -50)
        CreateCheck("Hide in Battleground", "hideInBG", -80)
        CreateCheck("Hide in Arena", "hideInArena", -110)

        -- Unlock Anchor Checkbox
        local unlockCb = CreateCheck("Unlock Anchor", "unlockAnchor", -150)
        unlockCb:SetChecked(false) -- Always start locked
        unlockCb:SetScript("OnClick", function(self)
            if self:GetChecked() then
                ZenToastAnchor:Show()
                ZenToastAnchor:EnableMouse(true)
            else
                ZenToastAnchor:Hide()
                ZenToastAnchor:EnableMouse(false)
            end
        end)

        -- Restore saved position
        if ZenToastDB.anchorPoint then
            ZenToastAnchor:ClearAllPoints()
            ZenToastAnchor:SetPoint(ZenToastDB.anchorPoint, UIParent, ZenToastDB.anchorPoint, ZenToastDB.anchorX, ZenToastDB.anchorY)
        end
    end
end)

-- Anchor Frame
local ZenToastAnchor = CreateFrame("Frame", "ZenToastAnchor", UIParent)
ZenToastAnchor:SetSize(FRAME_WIDTH, 20)
ZenToastAnchor:SetPoint(defaults.anchorPoint, UIParent, defaults.anchorPoint, defaults.anchorX, defaults.anchorY)
ZenToastAnchor:SetClampedToScreen(true)
ZenToastAnchor:SetMovable(true)
ZenToastAnchor:EnableMouse(false)
ZenToastAnchor:RegisterForDrag("LeftButton")
ZenToastAnchor:Hide()

ZenToastAnchor.bg = ZenToastAnchor:CreateTexture(nil, "BACKGROUND")
ZenToastAnchor.bg:SetAllPoints(true)
ZenToastAnchor.bg:SetTexture(0, 1, 0, 0.5)

ZenToastAnchor.text = ZenToastAnchor:CreateFontString(nil, "OVERLAY", "GameFontNormal")
ZenToastAnchor.text:SetPoint("CENTER")
ZenToastAnchor.text:SetText("ZenToast Anchor")

ZenToastAnchor:SetScript("OnDragStart", function(self)
    self:StartMoving()
end)

ZenToastAnchor:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, _, x, y = self:GetPoint()
    ZenToastDB.anchorPoint = point
    ZenToastDB.anchorX = x
    ZenToastDB.anchorY = y
end)

-- Toast Pooling & Stacking
local activeToasts = {}
local toastPool = {}

local function ReanchorToasts()
    for i, toast in ipairs(activeToasts) do
        toast:ClearAllPoints()
        if i == 1 then
            toast:SetPoint("TOP", ZenToastAnchor, "BOTTOM", 0, -SPACING)
        else
            toast:SetPoint("TOP", activeToasts[i-1], "BOTTOM", 0, -SPACING)
        end
    end
end

local function RecycleToast(toast)
    toast:Hide()
    toast:SetAlpha(0)
    toast.animState = "HIDDEN"
    table.insert(toastPool, toast)

    -- Remove from active list
    for i, t in ipairs(activeToasts) do
        if t == toast then
            table.remove(activeToasts, i)
            break
        end
    end
    ReanchorToasts()
end

local function CreateToastFrame()
    local Toast = CreateFrame("Button", nil, UIParent)
    Toast:SetSize(FRAME_WIDTH, FRAME_HEIGHT)
    Toast:SetFrameStrata("FULLSCREEN_DIALOG")
    Toast:Hide()
    Toast:SetAlpha(0)

    -- Aesthetic: Dark Background with thin border
    Toast:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        tile = false, tileSize = 0, edgeSize = 1,
        insets = { left = 0, right = 0, top = 0, bottom = 0 }
    })
    Toast:SetBackdropColor(0.1, 0.1, 0.1, 0.9)
    Toast:SetBackdropBorderColor(0, 0, 0, 1)

    -- Aesthetic: Icon
    Toast.Icon = Toast:CreateTexture(nil, "ARTWORK")
    Toast.Icon:SetSize(FRAME_HEIGHT - 4, FRAME_HEIGHT - 4)
    Toast.Icon:SetPoint("LEFT", 2, 0)

    -- Aesthetic: Text
    Toast.Text = Toast:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    Toast.Text:SetPoint("TOPLEFT", Toast.Icon, "TOPRIGHT", 10, -2)
    Toast.Text:SetJustifyH("LEFT")

    Toast.SubText = Toast:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    Toast.SubText:SetPoint("TOPLEFT", Toast.Text, "BOTTOMLEFT", 0, -2)
    Toast.SubText:SetJustifyH("LEFT")

    -- Click Handler
    Toast:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    Toast:SetScript("OnClick", function(self, button)
        if button == "RightButton" then
            if FriendsFrame_ShowDropdown then
                FriendsFrame_ShowDropdown(self.name, 1)
            end
        else
            if self.name then
                ChatFrame_OpenChat("/w " .. self.name .. " ")
            end
        end
        -- Optional: Dismiss on click? Or let it fade?
        -- Let's dismiss it to be clean
        RecycleToast(self)
    end)

    -- Animation Logic
    Toast.animTime = 0
    Toast.animState = "HIDDEN"

    Toast:SetScript("OnUpdate", function(self, elapsed)
        if self.animState == "HIDDEN" then return end

        self.animTime = self.animTime + elapsed

        if self.animState == "FADEIN" then
            local alpha = self.animTime / FADE_DURATION
            if alpha >= 1 then
                alpha = 1
                self.animState = "HOLD"
                self.animTime = 0
            end
            self:SetAlpha(alpha)
        elseif self.animState == "HOLD" then
            if self.animTime >= TOAST_DURATION then
                self.animState = "FADEOUT"
                self.animTime = 0
            end
        elseif self.animState == "FADEOUT" then
            local alpha = 1 - (self.animTime / FADE_DURATION)
            if alpha <= 0 then
                RecycleToast(self)
            else
                self:SetAlpha(alpha)
            end
        end
    end)

    return Toast
end

local function GetToast()
    local toast = table.remove(toastPool)
    if not toast then
        toast = CreateToastFrame()
    end
    return toast
end

local function ShowToast(name, isOnline)
    -- 1. Combat Suppression
    if InCombatLockdown() then return end

    -- 2. Instance Suppression
    local inInstance, instanceType = IsInInstance()
    if inInstance then
        if instanceType == "raid" and ZenToastDB.hideInRaid then return end
        if instanceType == "pvp" and ZenToastDB.hideInBG then return end -- Battleground
        if instanceType == "arena" and ZenToastDB.hideInArena then return end
    end

    -- 3. Play Sound
    PlaySound("igQuestLogOpen")

    -- 4. Fetch Data
    local classColor = "ffffffff"
    local iconPath = "Interface\\Icons\\Inv_misc_groupneedmore"
    local level = "??"
    local class = "Unknown"
    local area = "Unknown"

    for i = 1, GetNumFriends() do
        local fName, fLevel, fClass, fArea, fConnected = GetFriendInfo(i)
        if fName and fName == name then
            level = fLevel or "??"
            class = fClass or "Unknown"
            area = fArea or "Unknown"

            if fClass then
                for k, v in pairs(RAID_CLASS_COLORS) do
                    if k == string.upper(fClass) or fClass == k then
                        classColor = v.colorStr
                    end
                end
            end
            -- Try to find class icon? 3.3.5 doesn't have easy class icon API without texture coords.
            -- We'll stick to the default icon or maybe use class icon if we had a table.
            -- For now, default icon is fine, or we could use "Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes" with coords.
            -- Let's keep it simple as per request, but maybe update icon if we can.
            break
        end
    end

    -- 5. Setup Toast
    local toast = GetToast()
    toast.name = name

    if isOnline then
        toast.Text:SetText("|c" .. classColor .. name .. "|r")
        toast.SubText:SetText(string.format("Level %s %s\n%s", level, class, area))
        toast:SetBackdropBorderColor(0, 1, 0, 0.5)
    else
        toast.Text:SetText("|c" .. classColor .. name .. "|r")
        toast.SubText:SetText("Went Offline")
        toast:SetBackdropBorderColor(1, 0, 0, 0.5)
    end

    -- Icon Logic
    local iconTexture = "Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes"
    local coords = CLASS_ICON_TCOORDS[string.upper(class)]

    if coords then
        toast.Icon:SetTexture(iconTexture)
        toast.Icon:SetTexCoord(unpack(coords))
    else
        -- Fallback to status icons if class is unknown
        if isOnline then
            toast.Icon:SetTexture("Interface\\FriendsFrame\\StatusIcon-Online")
        else
            toast.Icon:SetTexture("Interface\\FriendsFrame\\StatusIcon-Offline")
        end
        toast.Icon:SetTexCoord(0, 1, 0, 1)
    end

    toast:Show()
    toast:SetAlpha(0)
    toast.animState = "FADEIN"
    toast.animTime = 0

    -- 6. Stacking Logic
    table.insert(activeToasts, 1, toast)
    if #activeToasts > MAX_TOASTS then
        RecycleToast(activeToasts[#activeToasts])
    end
    ReanchorToasts()
end

-- 2. Chat Filter (Hide System Msg, Trigger Toast)
local patternOnline = ERR_FRIEND_ONLINE_SS:gsub("%%s", "(.+)"):gsub("%[", "%%["):gsub("%]","%%]")
local patternOffline = ERR_FRIEND_OFFLINE_S:gsub("%%s", "(.+)"):gsub("%[", "%%["):gsub("%]","%%]")

local function ChatFilter(self, event, msg, ...)
    local name = msg:match(patternOnline)
    if name then
        ShowToast(name, true)
        return true -- Block original message
    end

    name = msg:match(patternOffline)
    if name then
        ShowToast(name, false)
        return true -- Block original message
    end

    return false
end

ChatFrame_AddMessageEventFilter("CHAT_MSG_SYSTEM", ChatFilter)

-- 3. Broadcast Functionality (Mass Whisper)
local BROADCAST_PLACEHOLDER = "Broadcast to friends..."

local function Broadcast_OnEnterPressed(self)
    local text = self:GetText()
    if not text or text == "" or text == BROADCAST_PLACEHOLDER then return end

    local count = GetNumFriends()
    if count < 1 then return end

    local sentCount = 0

    for i = 1, count do
        local name, _, _, _, connected = GetFriendInfo(i)
        if connected then
            SendChatMessage(text, "WHISPER", nil, name)
            sentCount = sentCount + 1
        end
    end

    DEFAULT_CHAT_FRAME:AddMessage("|cff0099ffZenToast:|r Broadcast sent to " .. sentCount .. " friends.")
    self:SetText("")
    self:ClearFocus()

    -- Reset to placeholder
    self:SetText(BROADCAST_PLACEHOLDER)
    self:SetTextColor(0.5, 0.5, 0.5)
end

local function Broadcast_OnEditFocusGained(self)
    if self:GetText() == BROADCAST_PLACEHOLDER then
        self:SetText("")
        self:SetTextColor(1, 1, 1)
    end
end

local function Broadcast_OnEditFocusLost(self)
    if self:GetText() == "" then
        self:SetText(BROADCAST_PLACEHOLDER)
        self:SetTextColor(0.5, 0.5, 0.5)
    end
end

-- Hook into the frame existing in 3.3.5a
if FriendsFrameBroadcastInput then
    FriendsFrameBroadcastInput:SetScript("OnEnterPressed", Broadcast_OnEnterPressed)
    FriendsFrameBroadcastInput:SetScript("OnEditFocusGained", Broadcast_OnEditFocusGained)
    FriendsFrameBroadcastInput:SetScript("OnEditFocusLost", Broadcast_OnEditFocusLost)

    FriendsFrameBroadcastInput:Show()
    -- Prevent the default UI from hiding it (Original addon logic)
    FriendsFrameBroadcastInput.Hide = function() end

    -- Initialize
    FriendsFrameBroadcastInput:SetText(BROADCAST_PLACEHOLDER)
    FriendsFrameBroadcastInput:SetTextColor(0.5, 0.5, 0.5)

    -- Optional: Style the input box to fit the theme
    local bg = _G["FriendsFrameBroadcastInputLeft"]:GetParent()
    if bg then
       -- You could strip textures here if you wanted it fully minimalist
    end
end
