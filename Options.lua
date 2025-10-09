-- Vanilla (1.12) doesn't support top-level varargs; use a global namespace.
local Peddler = _G.Peddler or {}
_G.Peddler = Peddler

-- Vanilla dropdown helper shim
if not UIDropDownMenu_CreateInfo then
    function UIDropDownMenu_CreateInfo() return {} end
end

-- Dropdown width helpers (handle 1.12 vs modern argument order)
local function ddSetWidth(dropdown, width)
    if not UIDropDownMenu_SetWidth then return end
    local ok = pcall(function() UIDropDownMenu_SetWidth(dropdown, width) end)
    if not ok then pcall(function() UIDropDownMenu_SetWidth(width, dropdown) end) end
end

local function ddSetButtonWidth(dropdown, width)
    if not UIDropDownMenu_SetButtonWidth then return end
    local ok = pcall(function() UIDropDownMenu_SetButtonWidth(dropdown, width) end)
    if not ok then
        ok = pcall(function() UIDropDownMenu_SetButtonWidth(width, dropdown) end)
        if not ok then pcall(function() UIDropDownMenu_SetButtonWidth(width) end) end
    end
end

-- Helper to set a click script on Vanilla and modern clients
local function setClickScript(widget, handler)
    if not widget or not widget.SetScript then return end
    local ok = false
    -- Some templates provide PostClick on modern clients
    if widget.GetScript then
        local succeeded = pcall(function() widget:SetScript("PostClick", handler) end)
        ok = succeeded and true or false
    end
    if not ok then
        widget:SetScript("OnClick", handler)
    end
end

local frame = CreateFrame("Frame", nil, InterfaceOptionsFramePanelContainer)
frame.name = "Peddler"
frame:Hide()

-- Add a nice dialog-like backdrop and an easy close button when used standalone
if frame.SetBackdrop then
    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 }
    })
    frame:SetBackdropColor(0,0,0,0.9)
end

frame:SetScript("OnShow", function(self)
	local f = self or (_G and _G.this) or frame
	if f and f.CreateOptions then
		f:CreateOptions()
		f:SetScript("OnShow", nil)
	end
end)

local function createCheckBox(parent, anchor, number, property, label, tooltip)
    local name = "PeddlerCheckBox" .. number
    -- Do NOT use ChatConfigCheckButtonTemplate on 1.12; it does not exist.
    local checkbox = CreateFrame("CheckButton", name, parent, "UICheckButtonTemplate")
    if not checkbox then
        checkbox = CreateFrame("CheckButton", name, parent)
        -- Minimal textures for Vanilla if template missing
        local up = checkbox:CreateTexture(nil, "BACKGROUND")
        up:SetAllPoints(checkbox)
        up:SetTexture("Interface\\Buttons\\UI-CheckBox-Up")
        checkbox:SetNormalTexture(up)

        local down = checkbox:CreateTexture(nil, "BACKGROUND")
        down:SetAllPoints(checkbox)
        down:SetTexture("Interface\\Buttons\\UI-CheckBox-Down")
        checkbox:SetPushedTexture(down)

        local hl = checkbox:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints(checkbox)
        hl:SetTexture("Interface\\Buttons\\UI-CheckBox-Highlight")
        checkbox:SetHighlightTexture(hl)

        local ch = checkbox:CreateTexture(nil, "ARTWORK")
        ch:SetAllPoints(checkbox)
        ch:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
        checkbox:SetCheckedTexture(ch)
    end

    checkbox:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 16, number * -26)

    local checkboxLabel = _G[name .. "Text"]
    if not checkboxLabel then
        checkboxLabel = parent:CreateFontString(name .. "Text", nil, "GameFontHighlightSmall")
        checkboxLabel:SetPoint("LEFT", checkbox, "RIGHT", 5, 0)
    end
    checkboxLabel:SetText(label)

    checkbox.tooltip = tooltip
    if checkbox.SetChecked then checkbox:SetChecked(property) end

    return checkbox
end

local function changeModifierKey(self)
	UIDropDownMenu_SetSelectedID(ModifierKeyDropDown, self:GetID())
	ModifierKey = self.value
end

local function initModifierKeys(self, level)
	local modifierKeys = {"CTRL", "ALT", "SHIFT", "CTRL-SHIFT", "CTRL-ALT", "ALT-SHIFT"}
	for index, modifierKey in pairs(modifierKeys) do
		local modifierKeyOption = UIDropDownMenu_CreateInfo()
		modifierKeyOption.text = modifierKey
		modifierKeyOption.value = modifierKey
		modifierKeyOption.func = changeModifierKey
		UIDropDownMenu_AddButton(modifierKeyOption)

		if modifierKey == ModifierKey then
			UIDropDownMenu_SetSelectedID(ModifierKeyDropDown, index)
		end
	end
end

local function changeIconPlacement(self)
	UIDropDownMenu_SetSelectedID(IconPlacementDropDown, self:GetID())
	IconPlacement = self.value
end

local function initIconPlacement(self, level)
	local iconPlacements = {"TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT"}
	for index, iconPlacement in pairs(iconPlacements) do
		local iconPlacementOption = UIDropDownMenu_CreateInfo()
		iconPlacementOption.text = iconPlacement
		iconPlacementOption.value = iconPlacement
		iconPlacementOption.func = changeIconPlacement
		UIDropDownMenu_AddButton(iconPlacementOption)

		if iconPlacement == IconPlacement then
			UIDropDownMenu_SetSelectedID(IconPlacementDropDown, index)
		end
	end
end

function frame:CreateOptions()
    local title = self:CreateFontString(nil, nil, "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", self, "TOPLEFT", 16, -16)
	title:SetText("Peddler v5.0")

    local sellLimit = createCheckBox(self, title, 1, SellLimit, "Sell Limit", "Limits the amount of items sold in one go, so you may buy all items back.")
    setClickScript(sellLimit, function(self, button)
        SellLimit = self:GetChecked()
    end)

    local silentMode = createCheckBox(self, title, 2, Silent, "Silent Mode", "Silence chat output about prices and sold item information.")
    setClickScript(silentMode, function(self, button)
        Silent = self:GetChecked()
    end)

    local silenceSaleSummary = createCheckBox(self, title, 3, SilenceSaleSummary, "Silence Sale Summary", "Silence the sale summary.")
    setClickScript(silenceSaleSummary, function(self, button)
        SilenceSaleSummary = self:GetChecked()
    end)
	silenceSaleSummary:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 190, 2 * -26)

	local modifierKeyLabel = self:CreateFontString(nil, nil, "GameFontNormal")
	modifierKeyLabel:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 16, -90)
	modifierKeyLabel:SetText("Modifier Key (used with right-click to mark/unmark items):")

    local modifierKey = CreateFrame("Button", "ModifierKeyDropDown", self, "UIDropDownMenuTemplate")
    modifierKey:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 16, -107)
    UIDropDownMenu_Initialize(ModifierKeyDropDown, initModifierKeys)
    ddSetWidth(ModifierKeyDropDown, 90)
    ddSetButtonWidth(ModifierKeyDropDown, 90)

	local iconPlacementLabel = self:CreateFontString(nil, nil, "GameFontNormal")
	iconPlacementLabel:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 16, -150)
	iconPlacementLabel:SetText("Icon Placement (the corner the coins icon should appear in - please reload to apply changes):")

    local iconPlacement = CreateFrame("Button", "IconPlacementDropDown", self, "UIDropDownMenuTemplate")
    iconPlacement:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 16, -167)
    UIDropDownMenu_Initialize(IconPlacementDropDown, initIconPlacement)
    ddSetWidth(IconPlacementDropDown, 110)
    ddSetButtonWidth(IconPlacementDropDown, 110)

	local autoSellLabel = self:CreateFontString(nil, nil, "GameFontNormal")
	autoSellLabel:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 16, -210)
	autoSellLabel:SetText("Automatically sell...")

    local autoSellSoulboundOnly = createCheckBox(self, title, 8, SoulboundOnly, "Restrict to Soulbound Items", "Only allow Peddler to automatically mark soulbound items for sale (does not restrict grey items, naturally).")
    autoSellSoulboundOnly:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 120, -205)
    setClickScript(autoSellSoulboundOnly, function(self, button)
        SoulboundOnly = self:GetChecked()
        Peddler.markWares()
    end)

    local autoSellGreyItems = createCheckBox(self, title, 9, AutoSellGreyItems, "Poor Items", "Automatically sells all grey/junk items.")
    setClickScript(autoSellGreyItems, function(self, button)
        AutoSellGreyItems = self:GetChecked()
        Peddler.markWares()
    end)

    local autoSellWhiteItems = createCheckBox(self, title, 10, AutoSellWhiteItems, "Common Items", "Automatically sells all white/common items.")
    setClickScript(autoSellWhiteItems, function(self, button)
        AutoSellWhiteItems = self:GetChecked()
        Peddler.markWares()
    end)

    local autoSellGreenItems = createCheckBox(self, title, 11, AutoSellGreenItems, "Uncommon Items", "Automatically sells all green/uncommon items.")
    setClickScript(autoSellGreenItems, function(self, button)
        AutoSellGreenItems = self:GetChecked()
        Peddler.markWares()
    end)

    local autoSellBlueItems = createCheckBox(self, title, 12, AutoSellBlueItems, "Rare Items", "Automatically sells all blue/rare items.")
    setClickScript(autoSellBlueItems, function(self, button)
        AutoSellBlueItems = self:GetChecked()
        Peddler.markWares()
    end)

    local autoSellPurpleItems = createCheckBox(self, title, 13, AutoSellPurpleItems, "Epic Items", "Automatically sells all purple/epic items.")
    setClickScript(autoSellPurpleItems, function(self, button)
        AutoSellPurpleItems = self:GetChecked()
        Peddler.markWares()
    end)

    local autoSellUnwantedItems = createCheckBox(self, title, 14, AutoSellUnwantedItems, "Unwanted Items", "Automatically sell all items which are unwanted for your current class (e.g. Priests don't want plate gear, so all plate gear will be marked).")
    setClickScript(autoSellUnwantedItems, function(self, button)
        AutoSellUnwantedItems = self:GetChecked()
        Peddler.markWares()
    end)

    local clearWaresList = CreateFrame("Button", nil, self, "UIPanelButtonTemplate")
    clearWaresList:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 16, -420)
    clearWaresList:SetWidth(110)
    clearWaresList:SetText("Clear Items List")
    setClickScript(clearWaresList, function(self, button)
        ItemsToSell = {}
        Peddler.markWares()
    end)

	local clearWaresLabel = self:CreateFontString(nil, nil, "GameFontHighlightSmall")
	clearWaresLabel:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 19, -450)
	clearWaresLabel:SetText("Clears the list of items you've manually marked for sale, for this character.")

	if self.refresh ~=nil then self:refresh() end
end

if InterfaceOptions_AddCategory then
	InterfaceOptions_AddCategory(frame)
elseif _G.Settings and _G.Settings.RegisterCanvasLayoutCategory then
	local category, layout = _G.Settings.RegisterCanvasLayoutCategory(frame, frame.name)
	_G.Settings.RegisterAddOnCategory(category)
else
    -- 1.12: no options panel; make the frame a standalone panel accessible via /peddler
    frame:SetParent(UIParent)
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    frame:SetWidth(600)
    frame:SetHeight(480)
    -- Provide a top-right X close button and ensure backdrop is visible
    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    if close then close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -6, -6) end
end

-- Handling Peddler's options.
SLASH_PEDDLER_COMMAND1 = '/peddler'
SlashCmdList['PEDDLER_COMMAND'] = function(command)
    if InterfaceOptionsFrame_OpenToCategory then
        InterfaceOptionsFrame_OpenToCategory('Peddler')
    else
        if frame:IsShown() then frame:Hide() else frame:Show() end
    end
end
