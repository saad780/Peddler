-- Vanilla (1.12) doesn't support top-level varargs (`...`).
-- Use a global namespace table that also works in modern clients.
local Peddler = _G.Peddler or {}
_G.Peddler = Peddler

-- Assign global functions to locals for optimisation.
local C_Container = C_Container
local GetItemInfo = GetItemInfo
local GetQuestLogItemLink = GetQuestLogItemLink
local PickupMerchantItem = PickupMerchantItem
local IsControlKeyDown = IsControlKeyDown
local IsShiftKeyDown = IsShiftKeyDown
local IsAltKeyDown = IsAltKeyDown
local UnitClass = UnitClass
local Baggins = Baggins
if not IsAddOnLoaded then
  function IsAddOnLoaded()
    return false
  end
end

-- Best-effort Bagnon presence detector for 1.12 (no IsAddOnLoaded available)
local function IsBagnonPresent()
  return (type(_G.Bagnon) ~= 'nil')
    or (type(_G['BagnonFrameinventory']) ~= 'nil')
    or (type(_G['BagnonContainerItem1']) ~= 'nil')
    or (type(_G['BagnonItem1']) ~= 'nil')
    or (type(_G['BagnonFrameinventoryItem1']) ~= 'nil')
end

local ARMOUR = Peddler.ARMOUR
local WEAPON = Peddler.WEAPON
local WANTED_ITEMS = Peddler.WANTED_ITEMS

local BAG_COUNT = 5
local BUYBACK_COUNT = 12
local _, PLAYERS_CLASS = UnitClass('player')

-- Lua 5.0 (Vanilla) compatibility helpers
-- print shim for Vanilla
local print = print or function(msg)
  if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
    DEFAULT_CHAT_FRAME:AddMessage(tostring(msg))
  end
end

-- strsplit shim (WoW added strsplit much later)
local strsplit = strsplit or function(delim, text)
  local result = {}
  if not text or text == '' then return unpack(result) end
  local d = tostring(delim or '')
  d = string.gsub(d, "(%W)", "%%%1")
  local pattern = "([^" .. d .. "]+)"
  local last_end = 1
  local s, e, cap = string.find(text, pattern, 1)
  while s do
    table.insert(result, cap)
    last_end = e + 1
    s, e, cap = string.find(text, pattern, last_end)
  end
  if last_end <= string.len(text) then
    table.insert(result, string.sub(text, last_end))
  end
  return unpack(result)
end

-- ipairs shim for Lua 5.0 environments
local ipairs = ipairs or function(t)
  local i = 0
  return function()
    i = i + 1
    if t[i] ~= nil then return i, t[i] end
  end
end

-- hooksecurefunc shim for older clients (simple, string-only, two-arg version)
if not hooksecurefunc then
  function hooksecurefunc(functionName, hook)
    local orig = _G[functionName]
    _G[functionName] = function(a1, a2, a3, a4, a5)
      if orig then orig(a1, a2, a3, a4, a5) end
      -- Try to normalize (self, button) for both modern and 1.12 API styles.
      local selfParam, buttonParam
      if type(a1) == 'table' then
        selfParam, buttonParam = a1, a2
      else
        selfParam, buttonParam = _G.this, a1
      end
      if hook then return hook(selfParam, buttonParam) end
    end
  end
end

-- C_Timer.After shim
local function After(delay, func)
  if C_Timer and C_Timer.After then
    return C_Timer.After(delay, func)
  end
  -- Fallback: schedule once via OnUpdate (GetTime based for 1.12)
  local f = CreateFrame('Frame')
  local start = GetTime and GetTime() or 0
  f:SetScript('OnUpdate', function()
    local now = GetTime and GetTime() or 0
    if (now - start) >= delay then
      f:SetScript('OnUpdate', nil)
      func()
    end
  end)
end

-- Container API shims for Vanilla
local function GetContainerNumSlotsCompat(bag)
  if C_Container and C_Container.GetContainerNumSlots then
    return C_Container.GetContainerNumSlots(bag)
  elseif GetContainerNumSlots then
    return GetContainerNumSlots(bag)
  else
    return 0
  end
end

local function GetContainerItemLinkCompat(bag, slot)
  if C_Container and C_Container.GetContainerItemLink then
    return C_Container.GetContainerItemLink(bag, slot)
  elseif GetContainerItemLink then
    return GetContainerItemLink(bag, slot)
  end
end

local function GetContainerItemInfoCompat(bag, slot)
  if C_Container and C_Container.GetContainerItemInfo then
    return C_Container.GetContainerItemInfo(bag, slot)
  elseif GetContainerItemInfo then
    local texture, itemCount, locked, quality, readable, lootable = GetContainerItemInfo(bag, slot)
    return { stackCount = itemCount, iconFileID = texture, isLocked = locked, quality = quality, isReadable = readable }
  end
end

local function PickupContainerItemCompat(bag, slot)
  if C_Container and C_Container.PickupContainerItem then
    return C_Container.PickupContainerItem(bag, slot)
  elseif PickupContainerItem then
    return PickupContainerItem(bag, slot)
  end
end

-- The typical life-cycle of the addon goes as follows:
--   1. Initially delays for 400ms before attempting to mark wares for the first time.
--   2. We look for and get the item buttons for every item (differs per bag addon).
--   3. Check if this item's ItemID is in our ItemsToSell.
--   4. If 'tis, draw some lovely coins on the itemButton!
--   5. a. Remove the OnUpdate (prev. used for 400ms delay).
--      b. If using the default WoW bags, keep a 30ms timer for re-marking.
--   6. Listen for BagUpdates to refresh the markings (moving an item, etc.).
--        PS: Baggins needs to also listen to the bags being opened!

-- Lua 5.0 does not support the % operator. Provide a safe modulus.
local function mod(a, b)
  if math.fmod then return math.fmod(a, b) end
  if math.mod then return math.mod(a, b) end
  return a - math.floor(a / b) * b
end

-- Turns an integer value into the format "Xg Ys Zc".
local function priceToGold(price)
  local gold = math.floor(price / 10000)
  local rem = mod(price, 10000)
  local silver = math.floor(rem / 100)
  local copper = mod(rem, 100)

  return gold .. "|cFFFFCC33g|r " .. silver .. "|cFFC9C9C9s|r " .. copper .. "|cFFCC8890c|r"
end

local peddler = CreateFrame("Frame", nil, UIParent)
local salesDelay = CreateFrame("Frame")
local usingDefaultBags = false
local markCounter = 1
local countLimit = 1

peddler:RegisterEvent("PLAYER_ENTERING_WORLD")
peddler:RegisterEvent("ADDON_LOADED")
peddler:RegisterEvent("MERCHANT_SHOW")

local function getIsItemSoulbound(bagNumber, slotNumber)
  -- Modern API path
  if Item and C_Item and Item.CreateFromBagAndSlot then
    local item = Item:CreateFromBagAndSlot(bagNumber, slotNumber)
    local location = item and item:GetItemLocation()
    if location and C_Item.DoesItemExist(location) then
      return C_Item.IsBound(location)
    end
  end

  -- Vanilla fallback: scan tooltip for 'Soulbound'
  local scanner = _G.PeddlerTooltipScanner or CreateFrame('GameTooltip', 'PeddlerTooltipScanner', UIParent, 'GameTooltipTemplate')
  _G.PeddlerTooltipScanner = scanner
  scanner:SetOwner(UIParent, 'ANCHOR_NONE')
  if scanner.SetBagItem then
    scanner:ClearLines()
    scanner:SetBagItem(bagNumber, slotNumber)
    for i = 1, 8 do
      local line = _G['PeddlerTooltipScannerTextLeft' .. i]
      local text = line and line:GetText()
      if text and (text == (ITEM_SOULBOUND or 'Soulbound') or string.find(text, (ITEM_SOULBOUND or 'Soulbound'))) then
        return true
      end
    end
  end
  return false
end

-- Serves to get the item's itemID + suffixID.
local function parseItemString(itemString)
  if not itemString then
    return
  end

  local _, itemID, _, _, _, _, _, suffixID = strsplit(":", itemString)
  itemID = tonumber(itemID)
  suffixID = tonumber(suffixID)

  if not itemID then
    return
  end

  local uniqueItemID = itemID
  if suffixID and suffixID ~= 0 then
    uniqueItemID = itemID .. suffixID
  end

  return itemID, uniqueItemID
end

local function isUnwantedItem(itemType, subType, equipSlot)
  local unwantedItem = false

  -- Of course we never want to sell cloaks!
  local isCloak = equipSlot == 'INVTYPE_CLOAK'
  if AutoSellUnwantedItems and (itemType == WEAPON or itemType == ARMOUR) and not isCloak then
    unwantedItem = true
    for key, value in pairs(WANTED_ITEMS[PLAYERS_CLASS][itemType]) do
      if subType == value then
        unwantedItem = false
        break
      end
    end
  end

  return unwantedItem
end

function Peddler.itemIsToBeSold(itemID, uniqueItemID, isSoulbound)
  -- If the user explicitly marked the item, always show as sellable,
  -- even when item info is not cached yet on 1.12.
  if ItemsToSell and ItemsToSell[uniqueItemID] then
    return true
  end

  local _, link, quality, itemLevel, _, itemType, subType, _, equipSlot, _, price = GetItemInfo(itemID)

  -- No price info yet? Defer auto-sell decision, but keep manual marks handled above.
  if not price or price <= 0 then
    return false
  end

  local unmarkedItem = UnmarkedItems[uniqueItemID]

  local unwantedGrey = quality == 0 and AutoSellGreyItems and not unmarkedItem
  local unwantedWhite = quality == 1 and AutoSellWhiteItems and not unmarkedItem
  local unwantedGreen = quality == 2 and AutoSellGreenItems and not unmarkedItem
  local unwantedBlue = quality == 3 and AutoSellBlueItems and not unmarkedItem
  local unwantedPurple = quality == 4 and AutoSellPurpleItems and not unmarkedItem

  local unwantedItem = isUnwantedItem(itemType, subType, equipSlot) and not unmarkedItem

  local autoSellable = (unwantedGrey or unwantedWhite or unwantedGreen or unwantedBlue or unwantedPurple or unwantedItem)

  if autoSellable then
    if SoulboundOnly and not unwantedGrey then
      autoSellable = isSoulbound
    end
  end

  return ItemsToSell[uniqueItemID] or autoSellable
end

local function peddleGoods()
  local total = 0
  local sellCount = 0
  local sellDelay = 0

  for bagNumber = 0, BAG_COUNT do
    local bagsSlotCount = GetContainerNumSlotsCompat(bagNumber)
    for slotNumber = 1, bagsSlotCount do
      local itemID, uniqueItemID, isSoulbound, itemLink = Peddler.getUniqueItemID(bagNumber, slotNumber)

      if uniqueItemID and Peddler.itemIsToBeSold(itemID, uniqueItemID, isSoulbound) then
        local itemButton = _G["ContainerFrame" .. bagNumber + 1 .. "Item" .. bagsSlotCount - slotNumber + 1]

        if itemButton.coins then
          itemButton.coins:Hide()
        end

        local itemInfo = GetContainerItemInfoCompat(bagNumber, slotNumber)
        local amount = (itemInfo and itemInfo.stackCount) or 1

        local _, _, _, _, _, _, _, _, _, _, price = GetItemInfo(itemLink)

        if price and price > 0 then
          price = price * amount

          if total == 0 and (not Silent or not SilenceSaleSummary) then
            print("Peddler sold:")
          end

          total = total + price

          if not Silent then
            local output = "    " .. sellCount + 1 .. '. ' .. itemLink

            if amount > 1 then
              output = output .. "x" .. amount
            end

            output = output .. " for " .. priceToGold(price)
            print(output)
          end
        end

        -- Actually sell the item!
        if (sellDelay > 0) and salesDelay.CreateAnimationGroup then
          local waitAnimationGroup = salesDelay:CreateAnimationGroup("sellDelay" .. sellCount)
          local waitAnimation = waitAnimationGroup:CreateAnimation("Translation")
          waitAnimation:SetDuration(sellDelay)
          waitAnimation:SetSmoothing("OUT")
          waitAnimationGroup:Play()

          waitAnimationGroup:SetScript("OnFinished", function()
            PickupContainerItemCompat(bagNumber, slotNumber)
            PickupMerchantItem()
          end)
        else
          PickupContainerItemCompat(bagNumber, slotNumber)
          PickupMerchantItem()
        end

        sellCount = sellCount + 1
        sellDelay = math.floor(sellCount / 6)
        if (SellLimit and sellCount >= BUYBACK_COUNT) then
          break
        end
      end

      if (SellLimit and sellCount >= BUYBACK_COUNT) then
        break
      end
    end
  end

  if total > 0 and not SilenceSaleSummary then
    print("For a total of " .. priceToGold(total))
  end
end

local function showCoinTexture(itemButton)
  if not itemButton.coins then
    local texture = itemButton:CreateTexture(nil, "OVERLAY")
    -- 1.12 is more strict; include the file extension and set an explicit size
    texture:SetTexture("Interface\\AddOns\\Peddler\\coins.tga")
    texture:SetWidth(14)
    texture:SetHeight(14)

    -- Default padding for making bottom-right look great.
    local paddingX, paddingY = -3, 1
    if string.find(IconPlacement, "TOP") then
      paddingY = -3
    end
    if string.find(IconPlacement, "LEFT") then
      paddingX = 1
    end

    -- 1.12 requires full SetPoint args
    texture:ClearAllPoints()
    texture:SetPoint(IconPlacement, itemButton, IconPlacement, paddingX, paddingY)

    itemButton.coins = texture
  end

  itemButton.coins:Show()

  if not usingDefaultBags then
    peddler:SetScript("OnUpdate", nil)
  end
  markCounter = 0

  if usingDefaultBags or IsAddOnLoaded("Baggins") or IsAddOnLoaded("AdiBags") or IsAddOnLoaded("BetterBags") then
    -- Baggins/AdiBag update slower than the others, so we have to account for that.
    -- Default WoW bags need to constantly be updating, due to opening of individual bags.
    countLimit = 30
  elseif IsAddOnLoaded("Bagnon") or IsBagnonPresent() then
    -- 1.12 Bagnon can update asynchronously; keep a higher limit to ensure overlays appear.
    countLimit = 30
  else
    countLimit = 5
  end
end

local function displayCoins(itemID, uniqueItemID, itemButton, isSoulbound)
  if uniqueItemID then
    if Peddler.itemIsToBeSold(itemID, uniqueItemID, isSoulbound) then
      showCoinTexture(itemButton)
    elseif itemButton.coins then
      itemButton.coins:Hide()
    end
  elseif itemButton.coins then
    itemButton.coins:Hide()
  end
end

local function checkItem(bagNumber, slotNumber, itemButton)
  local itemID, uniqueItemID, isSoulbound = Peddler.getUniqueItemID(bagNumber, slotNumber)
  displayCoins(itemID, uniqueItemID, itemButton, isSoulbound)
end

local function markBagginsBags()
  for bagid, bag in ipairs(Baggins.bagframes) do
    for sectionid, section in ipairs(bag.sections) do
      for buttonid, itemButton in ipairs(section.items) do
        local itemsBagNumber = itemButton:GetParent():GetID()
        local itemsSlotNumber = itemButton:GetID()

        checkItem(itemsBagNumber, itemsSlotNumber, itemButton)
      end
    end
  end
end

local function markBagnonBags()
  local found = false
  -- Robust scan for 1.12-era Bagnon item buttons; look for any global button whose
  -- name begins with 'Bagnon' and contains 'Item', with a parent that has a bag ID.
  for name, frame in pairs(_G) do
    if type(name) == 'string' and type(frame) == 'table' and frame.GetParent and frame.GetID then
      if string.find(name, '^Bagnon') and string.find(name, 'Item') then
        local parent = frame:GetParent()
        if parent and parent.GetID then
          local bag = parent:GetID()
          local slot = frame:GetID()
          checkItem(bag, slot, frame)
          found = true
        end
      end
    end
  end

  -- Fallback to a few known sequences if the generic scan found nothing.
  if not found then
    for i = 1, 1000 do
      local btn = _G['BagnonContainerItem' .. i] or _G['BagnonItem' .. i] or _G['BagnonFrameinventoryItem' .. i]
      if not btn then
        if i > 100 and not found then break end
      else
        local p = btn:GetParent()
        if p then
          checkItem(p:GetID(), btn:GetID(), btn)
          found = true
        end
      end
    end
  end
end

local function markCombuctorBags()
  for bagNumber = 0, BAG_COUNT do
    for slotNumber = 1, 36 do
      local itemButton = _G["ContainerFrame" .. bagNumber + 1 .. "Item" .. slotNumber]

      local itemButtonParent = itemButton:GetParent()
      if itemButtonParent then
        local itemsBagNumber = itemButtonParent:GetID()
        local itemsSlotNumber = itemButton:GetID()
        checkItem(itemsBagNumber, itemsSlotNumber, itemButton)
      end
    end
  end
end

local function markOneBagBags()
  for bagNumber = 0, BAG_COUNT do
    local bagsSlotCount = GetContainerNumSlotsCompat(bagNumber)
    for slotNumber = 1, bagsSlotCount do
      local itemButton = _G["OneBagFrameBag" .. bagNumber .. "Item" .. bagsSlotCount - slotNumber + 1]

      if itemButton then
        local itemsBagNumber = itemButton:GetParent():GetID()
        local itemsSlotNumber = itemButton:GetID()
        checkItem(itemsBagNumber, itemsSlotNumber, itemButton)
      end
    end
  end
end

local function markBaudBagBags()
  for bagNumber = 0, BAG_COUNT do
    local bagsSlotCount = GetContainerNumSlotsCompat(bagNumber)
    for slotNumber = 1, bagsSlotCount do
      local itemButton = _G["BaudBagSubBag" .. bagNumber .. "Item" .. slotNumber]
      checkItem(bagNumber, slotNumber, itemButton)
    end
  end
end

local function markBetterBags()
  -- For some reason, BetterBags can have way more buttons than the actual amount of bag slots... not sure how or why.
  for slotNumber = 1, 1000 do
    local itemButton = _G["BetterBagsItemButton" .. slotNumber]
    if itemButton then
      local itemButtonParent = itemButton:GetParent()
      if itemButtonParent then
        local itemsBagNumber = itemButtonParent:GetID()
        local itemsSlotNumber = itemButton:GetID()
        checkItem(itemsBagNumber, itemsSlotNumber, itemButton)
      end
    end
  end
end

local function markAdiBagBags()
  -- For some reason, AdiBags can have way more buttons than the actual amount of bag slots... not sure how or why.
  for slotNumber = 1, 1000 do
    local itemButton = _G["AdiBagsItemButton" .. slotNumber]
    if itemButton then
      local _, bag, slot = strsplit('-', tostring(itemButton))

      bag = tonumber(bag)
      slot = tonumber(slot)

      if bag and slot then
        checkItem(bag, slot, itemButton)
      end
    end
  end
end

local function markArkInventoryBags()
  for bagNumber = 0, BAG_COUNT do
    local bagsSlotCount = GetContainerNumSlotsCompat(bagNumber)
    for slotNumber = 1, bagsSlotCount do
      local itemButton = _G["ARKINV_Frame1ScrollContainerBag" .. bagNumber + 1 .. "Item" .. slotNumber]
      -- Required to check for itemButton because ArkInventory changed when it builds the item objects so only the first slot of each bag is available prior to the first time its opened, causing Peddler to get a nil obj for itemButton. /vincentSDSH
      if itemButton then checkItem(bagNumber, slotNumber, itemButton) end
    end
  end
end

local function markCargBagsNivayaBags()
  local totalSlotCount = 0
  for bagNumber = 0, BAG_COUNT do
    totalSlotCount = totalSlotCount + GetContainerNumSlotsCompat(bagNumber)
  end

  -- Somehow, Nivaya can have higher slot-numbers than actual bag slots exist...
  totalSlotCount = totalSlotCount * 5

  for slotNumber = 1, totalSlotCount do
    local itemButton = _G["NivayaSlot" .. slotNumber]
    if itemButton then
      local itemsBag = itemButton:GetParent()

      if itemsBag then
        local itemsBagNumber = itemsBag:GetID()
        local itemsSlotNumber = itemButton:GetID()
        checkItem(itemsBagNumber, itemsSlotNumber, itemButton)
      end
    end
    slotNumber = slotNumber + 1
  end
end

local function markMonoBags()
  local totalSlotCount = 0
  for bagNumber = 0, BAG_COUNT do
    totalSlotCount = totalSlotCount + GetContainerNumSlotsCompat(bagNumber)
  end

  for slotNumber = 1, totalSlotCount do
    local itemButton = _G["m_BagsSlot" .. slotNumber]
    if itemButton then
      local itemsBagNumber = itemButton:GetParent():GetID()
      local itemsSlotNumber = itemButton:GetID()
      checkItem(itemsBagNumber, itemsSlotNumber, itemButton)
    end
    slotNumber = slotNumber + 1
  end
end

local function markDerpyBags()
  for bagNumber = 0, BAG_COUNT do
    local bagsSlotCount = GetContainerNumSlotsCompat(bagNumber)
    for slotNumber = 1, bagsSlotCount do
      local itemButton = _G["StuffingBag" .. bagNumber .. "_" .. slotNumber]
      checkItem(bagNumber, slotNumber, itemButton)
    end
  end
end

-- ElvUI is badly coded, so you'll have to excuse the peculiar code.
local function markElvUIBags()
  for bagNumber = 0, BAG_COUNT + 1 do
    local bagsSlotCount = GetContainerNumSlotsCompat(bagNumber)
    for slotNumber = 1, bagsSlotCount do
      local containerFrameName = "ElvUI_ContainerFrameBag"
      local containerFrameBagNumber = bagNumber - 1

      if bagNumber == 0 then
        containerFrameBagNumber = 1
        containerFrameName = containerFrameName .. "-"
      end

      local itemButton = _G[containerFrameName .. containerFrameBagNumber .. "Slot" .. slotNumber]
      if itemButton then
        checkItem(bagNumber, slotNumber, itemButton)
      end
    end
  end
end

local function markInventorianBags()
  for bagNumber = 0, NUM_CONTAINER_FRAMES do
    for slotNumber = 1, 36 do
      local itemButton = _G["ContainerFrame" .. bagNumber + 1 .. "Item" .. slotNumber]

      if itemButton then
        local itemButtonParent = itemButton:GetParent()
        if itemButtonParent then
          local itemsBagNumber = itemButtonParent:GetID()
          local itemsSlotNumber = itemButton:GetID()
          checkItem(itemsBagNumber, itemsSlotNumber, itemButton)
        end
      end
    end
  end
end

-- Special thanks to both Xodiv & Theroxis of Curse for this one.
local function markLiteBagBags()
  for i = 1, LiteBagInventoryPanel.size do
    local button = LiteBagInventoryPanel.itemButtons[i]
    local itemsBagNumber = button:GetParent():GetID()
    local itemsSlotNumber = button:GetID()
    checkItem(itemsBagNumber, itemsSlotNumber, button)
  end
end

-- Special thanks to Tymesink from WowInterface for this one.
local function markfamBagsBags()
  for bagNumber = 0, BAG_COUNT do
    local bagsSlotCount = GetContainerNumSlotsCompat(bagNumber)
    for slotNumber = 1, bagsSlotCount do
      local itemButton = _G["famBagsButton_" .. bagNumber .. "_" .. slotNumber]
      checkItem(bagNumber, slotNumber, itemButton)
    end
  end
end

local function markLUIBags()
  for bagNumber = 0, BAG_COUNT do
    local bagsSlotCount = GetContainerNumSlotsCompat(bagNumber)
    for slotNumber = 1, bagsSlotCount do
      local itemButton = _G["LUIBags_Item" .. bagNumber .. "_" .. slotNumber]
      checkItem(bagNumber, slotNumber, itemButton)
    end
  end
end

local function markRealUIBags()
  local totalSlotCount = 0
  for bagNumber = 0, BAG_COUNT do
    totalSlotCount = totalSlotCount + GetContainerNumSlotsCompat(bagNumber)
  end

  -- Somehow, this can have higher slot-numbers than actual bag slots exist...
  totalSlotCount = totalSlotCount * 5

  for slotNumber = 1, totalSlotCount do
    local itemButton = _G["RealUIInventory_Slot" .. slotNumber]
    if itemButton then
      local itemsBag = itemButton:GetParent()

      if itemsBag then
        local itemsBagNumber = itemsBag:GetID()
        local itemsSlotNumber = itemButton:GetID()
        checkItem(itemsBagNumber, itemsSlotNumber, itemButton)
      end
    end
    slotNumber = slotNumber + 1
  end
end

-- Also works for bBag.
local function markNormalBags()
  for containerNumber = 0, BAG_COUNT do
    local container = _G["ContainerFrame" .. containerNumber + 1]
    local combinedBags = _G["ContainerFrameCombinedBags"]
    if (container:IsShown()) then
      local bagsSlotCount = GetContainerNumSlotsCompat(containerNumber)
      for slotNumber = 1, bagsSlotCount do
        -- It appears there are two ways of finding items!
        --   Accessing via _G means that bagNumbers are 1-based indices and
        --   slot numbers start from the bottom-right rather than top-left!
        -- Additionally, as only a couple of the bags may be visible at any
        --   given time, we may be looking at items whose buttons don't
        --   currently exist, and mark the wrong ones, so get the actual
        --   bag & slot number from the itemButton.
        local itemButton = _G["ContainerFrame" .. containerNumber + 1 .. "Item" .. bagsSlotCount - slotNumber + 1]

        local bagNumber = itemButton:GetParent():GetID()
        local actualSlotNumber = itemButton:GetID()

        checkItem(bagNumber, actualSlotNumber, itemButton)
      end
    elseif (combinedBags and combinedBags:IsShown()) then
      local bagsSlotCount = GetContainerNumSlotsCompat(containerNumber)
      for slotNumber = 1, bagsSlotCount do
        local itemButton = _G["ContainerFrame" .. containerNumber + 1 .. "Item" .. bagsSlotCount - slotNumber + 1]
        local actualSlotNumber = itemButton:GetID()

        checkItem(containerNumber, actualSlotNumber, itemButton)
      end
    end
  end
end

local overridenItemClickFunction = false

-- TODO: Split these into separate, well-coded things already.
local function markWares()
  if IsAddOnLoaded("Baggins") then
    markBagginsBags()
  elseif IsAddOnLoaded("Combuctor")  then
    markCombuctorBags()
  elseif IsAddOnLoaded("Bagnon") or IsBagnonPresent() then
    markBagnonBags()
  elseif IsAddOnLoaded("OneBag3") then
    markOneBagBags()
  elseif IsAddOnLoaded("BaudBag") then
    markBaudBagBags()
  elseif IsAddOnLoaded("AdiBags") then
    markAdiBagBags()
  elseif IsAddOnLoaded("ArkInventory") then
    markArkInventoryBags()
  elseif IsAddOnLoaded("famBags") then
    markfamBagsBags()
  elseif IsAddOnLoaded("cargBags_Nivaya") then
    markCargBagsNivayaBags()
  elseif IsAddOnLoaded("m_Bags") then
    markMonoBags()
  elseif IsAddOnLoaded("DerpyStuffing") then
    markDerpyBags()
  elseif IsAddOnLoaded("Inventorian") then
    markInventorianBags()
  elseif IsAddOnLoaded("LiteBag") then
    markLiteBagBags()
  elseif IsAddOnLoaded("ElvUI") and _G["ElvUI_ContainerFrame"] then
    markElvUIBags()
  elseif IsAddOnLoaded("LUI") and _G["LUIBags_Item0_1"] then
    markLUIBags()
  elseif IsAddOnLoaded("RealUI_Inventory") then
    markRealUIBags()
  elseif IsAddOnLoaded("BetterBags") then
    markBetterBags()
  else
    usingDefaultBags = true
    markNormalBags()
  end
end

Peddler.markWares = markWares

local function onUpdate()
  markCounter = markCounter + 1
  if markCounter <= countLimit then
    return
  else
    markCounter = 0
    markWares()
  end
end

local function handleBagginsOpened()
  if markCounter == 0 then
    peddler:SetScript("OnUpdate", onUpdate)
  end
end

local function setupDefaults()
  -- Setup default settings.
  if not ItemsToSell then
    ItemsToSell = {}
  end

  if not UnmarkedItems then
    UnmarkedItems = {}
  end

  if not ModifierKey then
    ModifierKey = "CTRL"
  end

  if not IconPlacement then
    IconPlacement = "BOTTOMLEFT"
  end

  if AutoSellGreyItems == nil then
    AutoSellGreyItems = true
  end
end

function Peddler.getUniqueItemID(bagNumber, slotNumber)
	if bagNumber == nil then return end

  local itemString = GetContainerItemLinkCompat(bagNumber, slotNumber)
  local itemID, uniqueItemID = parseItemString(itemString)
  local isSoulbound = getIsItemSoulbound(bagNumber, slotNumber)

  return itemID, uniqueItemID, isSoulbound, itemString
end

-- Forward declare to allow calling inside event handler
local scheduleBagnonHookRetries

local function handleEvent(self, event, addonName)
  -- Support both modern and 1.12 event calling conventions
  event = event or _G.event
  addonName = addonName or _G.arg1
  if event == "ADDON_LOADED" and addonName == "Peddler" then
    peddler:UnregisterEvent("ADDON_LOADED")

    setupDefaults()

    countLimit = 400
    peddler:SetScript("OnUpdate", onUpdate)

    if IsAddOnLoaded("Baggins") then
      Baggins:RegisterSignal("Baggins_BagOpened", handleBagginsOpened, Baggins)
    end
    if scheduleBagnonHookRetries then scheduleBagnonHookRetries() end
  elseif event == "PLAYER_ENTERING_WORLD" then
    peddler:RegisterEvent("BAG_UPDATE")
    if scheduleBagnonHookRetries then scheduleBagnonHookRetries() end
  elseif event == "BAG_UPDATE" then
    After(1, markWares)
  elseif event == "MERCHANT_SHOW" then
    peddleGoods()
  end
end

peddler:SetScript("OnEvent", handleEvent)

-- Try to hook Bagnon item button click handlers so Peddler's right-click works in Bagnon.
local hookedBagnonHandlers = {}
local function tryHookBagnonClicks()
  -- Only attempt if Bagnon appears present
  if not (IsAddOnLoaded('Bagnon') or IsBagnonPresent()) then return end
  local candidates = {
    'BagnonItem_OnModifiedClick',
    'BagnonItem_OnClick',
    'Bagnon_ItemButton_OnClick',
    'BagnonItemButton_OnClick',
    'BagnonSlot_OnClick',
  }
  for _, fn in ipairs(candidates) do
    if _G[fn] and not hookedBagnonHandlers[fn] then
      hooksecurefunc(fn, handleItemClick)
      hookedBagnonHandlers[fn] = true
    end
  end
end

-- Retry hooking a few times in case Bagnon loads after Peddler
scheduleBagnonHookRetries = function()
  local delays = { 0.2, 1, 3, 6 }
  for _, d in ipairs(delays) do
    After(d, tryHookBagnonClicks)
  end
end

local function toggleItemPeddling(itemID, uniqueItemID, isSoulbound)
  local _, link, quality, _, _, itemType, subType, _, equipSlot, _, price = GetItemInfo(itemID)
  if price == 0 then
    return
  end

  local unwantedGrey = quality == 0 and AutoSellGreyItems
  local unwantedWhite = quality == 1 and AutoSellWhiteItems
  local unwantedGreen = quality == 2 and AutoSellGreenItems
  local unwantedBlue = quality == 3 and AutoSellBlueItems
  local unwantedPurple = quality == 4 and AutoSellPurpleItems

  local unwantedItem = isUnwantedItem(itemType, subType, equipSlot)

  local autoSellable = (unwantedGrey or unwantedWhite or unwantedGreen or unwantedBlue or unwantedPurple or unwantedItem)

  if autoSellable then
    if SoulboundOnly and not unwantedGrey then
      autoSellable = isSoulbound
    end
  end

  if autoSellable then
    if UnmarkedItems[uniqueItemID] then
      UnmarkedItems[uniqueItemID] = nil
    else
      UnmarkedItems[uniqueItemID] = 1
      ItemsToSell[uniqueItemID] = nil
    end
  elseif ItemsToSell[uniqueItemID] then
    ItemsToSell[uniqueItemID] = nil
  else
    ItemsToSell[uniqueItemID] = 1
  end
end

local function handleItemClick(self, button)
	local ctrlKeyDown = IsControlKeyDown()
	local shiftKeyDown = IsShiftKeyDown()
	local altKeyDown = IsAltKeyDown()

	local modifierDown = (ModifierKey == 'CTRL' and ctrlKeyDown or (ModifierKey == 'SHIFT' and shiftKeyDown or (ModifierKey == 'ALT' and altKeyDown or (ModifierKey == 'CTRL-SHIFT' and ctrlKeyDown and shiftKeyDown or (ModifierKey == 'CTRL-ALT' and ctrlKeyDown and altKeyDown or (ModifierKey == 'ALT-SHIFT' and altKeyDown and shiftKeyDown))))))
	local usingPeddler = (modifierDown and button == 'RightButton')
	if not usingPeddler then
		return
	end

	local bagNumber = self:GetParent():GetID()
	local slotNumber = self:GetID()

	local itemID, uniqueItemID, isSoulbound = Peddler.getUniqueItemID(bagNumber, slotNumber)

	-- Empty bag slots cannot be sold, silly!
	if not itemID then
		return
	end

	toggleItemPeddling(itemID, uniqueItemID, isSoulbound)

	markWares()
end

hooksecurefunc("ContainerFrameItemButton_OnModifiedClick", handleItemClick)
hooksecurefunc("ContainerFrameItemButton_OnClick", handleItemClick)

-- Quest Reward handling.
--[[ 
local listeningToRewards = {}
local function checkQuestReward(itemButton, toggle)
  local rewardIndex = itemButton:GetID()

  local testReward = function(itemString)
    if not itemString then
      return
    end

    local itemID, uniqueItemID = parseItemString(itemString)

    if toggle then
      toggleItemPeddling(itemID, uniqueItemID)
    end

    displayCoins(itemID, uniqueItemID, itemButton)
  end

  testReward(GetQuestLogItemLink("reward", rewardIndex))
  testReward(GetQuestLogItemLink("choice", rewardIndex))
end

local function handleQuestFrameItemClick(self, button)
  if not clickedWithPeddlerCombo() then
    return
  end

  checkQuestReward(self, true)

  markWares()
end

local function setupQuestFrame(frameBaseName)
  for i = 1, 6 do
    local frameName = frameBaseName .. i
    local itemButton = _G[frameName]
    if itemButton then
      checkQuestReward(itemButton, false)

      if not listeningToRewards[frameName] then
        listeningToRewards[frameName] = true
        itemButton:HookScript("OnClick", handleQuestFrameItemClick)
      end
    end
  end
end

local function onQuestRewardsShow()
  setupQuestFrame("QuestInfoRewardsFrameQuestInfoItem")
end

local function onMapQuestRewardsShow()
  setupQuestFrame("MapQuestInfoRewardsFrameQuestInfoItem")
end

MapQuestInfoRewardsFrame:HookScript("OnShow", onMapQuestRewardsShow)
QuestInfoRewardsFrame:HookScript("OnShow", onQuestRewardsShow) 
]]

PeddlerAPI = Peddler
