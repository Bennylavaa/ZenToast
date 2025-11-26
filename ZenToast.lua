-- Configuration --
local TOAST_DURATION = 4.0
local FADE_DURATION = 0.5
local FRAME_WIDTH = 250
local FRAME_HEIGHT = 40
-- Position (Center of screen, slightly up)
local POS_POINT = "TOP"
local POS_X = 0
local POS_Y = -150
-------------------

local _G = _G
local pairs, string, time = pairs, string, time
local GetFriendInfo, GetNumFriends = GetFriendInfo, GetNumFriends
local SendChatMessage = SendChatMessage
local RAID_CLASS_COLORS = RAID_CLASS_COLORS

-- 1. Create the Minimalist Toast Frame
local Toast = CreateFrame("Button", "MinFriendToast", UIParent)
Toast:SetSize(FRAME_WIDTH, FRAME_HEIGHT)
Toast:SetPoint(POS_POINT, POS_X, POS_Y)
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
Toast:SetBackdropColor(0.1, 0.1, 0.1, 0.8) -- Dark Grey, 80% opacity
Toast:SetBackdropBorderColor(0, 0, 0, 1)   -- Black Border
  
-- Aesthetic: Icon (Class Icon or Generic)
Toast.Icon = Toast:CreateTexture(nil, "ARTWORK")
Toast.Icon:SetSize(FRAME_HEIGHT - 4, FRAME_HEIGHT - 4)
Toast.Icon:SetPoint("LEFT", 2, 0)
Toast.Icon:SetTexture("Interface\\Icons\\Inv_misc_groupneedmore") -- Default icon

-- Aesthetic: Text
Toast.Text = Toast:CreateFontString(nil, "OVERLAY", "GameFontNormal")
Toast.Text:SetPoint("LEFT", Toast.Icon, "RIGHT", 10, 2)
Toast.Text:SetJustifyH("LEFT")
Toast.Text:SetText("Friend Online")

Toast.SubText = Toast:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
Toast.SubText:SetPoint("TOPLEFT", Toast.Text, "BOTTOMLEFT", 0, -2)
Toast.SubText:SetText("Click to whisper")

-- Animation Logic
local animTime = 0
local animState = "HIDDEN" -- HIDDEN, FADEIN, HOLD, FADEOUT
local targetName = ""

Toast:SetScript("OnUpdate", function(self, elapsed)
    if animState == "HIDDEN" then return end

    animTime = animTime + elapsed

    if animState == "FADEIN" then
        local alpha = animTime / FADE_DURATION
        if alpha >= 1 then
            alpha = 1
            animState = "HOLD"
            animTime = 0
        end
        self:SetAlpha(alpha)
    elseif animState == "HOLD" then
        if animTime >= TOAST_DURATION then
            animState = "FADEOUT"
            animTime = 0
        end
    elseif animState == "FADEOUT" then
        local alpha = 1 - (animTime / FADE_DURATION)
        if alpha <= 0 then
            self:Hide()
            animState = "HIDDEN"
        else
            self:SetAlpha(alpha)
        end
    end
end)

Toast:SetScript("OnClick", function(self, button)
    if targetName and targetName ~= "" then
        ChatFrame_OpenChat("/w " .. targetName .. " ")
        self:Hide()
    end
end)

local function ShowToast(name, isOnline)
    -- Find class info for color
    local classColor = "ffffffff" -- Default white
    local iconPath = "Interface\\Icons\\Inv_misc_groupneedmore"

    -- Loop friends to find info (Data might not be ready instantly on login, but usually is cached)
    for i = 1, GetNumFriends() do
        local fName, _, fClass = GetFriendInfo(i)
        if fName and fName == name then
            -- Get Class Icon and Color
            if fClass then
                -- Convert localized class name to filename (approximate) or just use generic
                -- In 3.3.5 pure Lua without libraries, getting class filename from localized string is tricky.
                -- We will try to match standard classes if possible, or just color the name.
                for k, v in pairs(RAID_CLASS_COLORS) do
                    if k == string.upper(fClass) or fClass == k then -- This check is weak in localized clients, but works for English
                        classColor = v.colorStr
                    end
                end
            end
            break
        end
    end

    targetName = name

    if isOnline then
        Toast.Text:SetText("|c" .. classColor .. name .. "|r is now |cff00ff00Online|r")
        Toast:SetBackdropBorderColor(0, 1, 0, 0.5) -- Greenish border
    else
        Toast.Text:SetText("|c" .. classColor .. name .. "|r went |cffff0000Offline|r")
        Toast:SetBackdropBorderColor(1, 0, 0, 0.5) -- Reddish border
    end

    Toast:Show()
    Toast:SetAlpha(0)
    animState = "FADEIN"
    animTime = 0
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
-- Re-purposing the FriendsFrame Broadcast Input just like the original, but safer code.

local function Broadcast_OnEnterPressed(self)
    local text = self:GetText()
    if not text or text == "" then return end

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

    DEFAULT_CHAT_FRAME:AddMessage("|cff0099ffMinFriends:|r Broadcast sent to " .. sentCount .. " friends.")
    self:SetText("")
    self:ClearFocus()
end

-- Hook into the frame existing in 3.3.5a
if FriendsFrameBroadcastInput then
    FriendsFrameBroadcastInput:SetScript("OnEnterPressed", Broadcast_OnEnterPressed)
    FriendsFrameBroadcastInput:Show()
    -- Prevent the default UI from hiding it (Original addon logic)
    FriendsFrameBroadcastInput.Hide = function() end

    -- Optional: Style the input box to fit the theme
    local bg = _G["FriendsFrameBroadcastInputLeft"]:GetParent()
    if bg then
       -- You could strip textures here if you wanted it fully minimalist
    end
end
