local addonRoot = (arg and arg[1]) or "./"
if string.sub(addonRoot, -1) ~= "/" and string.sub(addonRoot, -1) ~= "\\" then
  addonRoot = addonRoot .. "/"
end

local createdFrames = {}
local ctrlDown = false

UIParent = {}
MapQuestInfoRewardsFrame = { HookScript = function() end }
QuestInfoRewardsFrame = { HookScript = function() end }

local function newFrame()
  local frame = { scripts = {} }
  function frame:RegisterEvent() end
  function frame:UnregisterEvent() end
  function frame:SetScript(name, callback) self.scripts[name] = callback end
  function frame:CreateAnimationGroup()
    return {
      CreateAnimation = function()
        return { SetDuration = function() end, SetSmoothing = function() end }
      end,
      Play = function() end,
      SetScript = function(_, _, callback) callback() end,
    }
  end
  table.insert(createdFrames, frame)
  return frame
end

CreateFrame = newFrame
UnitClass = function() return "Warrior", "WARRIOR" end
IsControlKeyDown = function() return ctrlDown end
IsShiftKeyDown = function() return false end
IsAltKeyDown = function() return false end
GetMouseButtonClicked = function() return "RightButton" end
GetQuestLogItemLink = function() return nil end
C_AddOns = { IsAddOnLoaded = function() return false end }
C_Timer = { After = function(_, callback) callback() end }

function strsplit(separator, value)
  local result = {}
  local pattern = "(.-)" .. separator
  for part in string.gmatch(value .. separator, pattern) do
    table.insert(result, part)
  end
  return table.unpack(result)
end

local itemLink = "|cnIQ0:|Hitem:12345:0:0:0:0:0:-7:0:1:60:0:0:0|h[Test Item]|h|r"
local soldBag, soldSlot
C_Container = {
  GetContainerItemInfo = function(bag, slot)
    if bag == 0 and slot == 1 then
      return { itemID = 12345, stackCount = 1 }
    end
  end,
  GetContainerItemLink = function(bag, slot)
    if bag == 0 and slot == 1 then return itemLink end
  end,
  GetContainerNumSlots = function(bag) return bag == 0 and 1 or 0 end,
  UseContainerItem = function(bag, slot) soldBag, soldSlot = bag, slot end,
}

C_Item = {
  DoesItemExist = function() return true end,
  IsBound = function() return false end,
  GetItemInfo = function()
    return "Test Item", itemLink, 0, 1, 1, "Miscellaneous", "Junk", 1, "", 0, 25
  end,
}

Item = {
  CreateFromBagAndSlot = function(_, bag, slot)
    return { GetItemLocation = function() return { bag = bag, slot = slot } end }
  end,
}

ItemLocation = {
  CreateFromBagAndSlot = function(_, bag, slot)
    return { GetBagAndSlot = function() return bag, slot end }
  end,
}

local texture = { shown = false }
function texture:SetTexture() end
function texture:SetSize(width, height)
  assert(width == 16 and height == 16, "coin texture has the wrong size")
end
function texture:SetPoint() end
function texture:Show() self.shown = true end
function texture:Hide() self.shown = false end

local itemButton = { id = 1, bag = 0 }
function itemButton:GetID() return self.id end
function itemButton:GetBagID() return self.bag end
function itemButton:CreateTexture() return texture end

local container = {}
function container:IsShown() return true end
function container:EnumerateValidItems() return ipairs({ itemButton }) end
ContainerFrameUtil_EnumerateContainerFrames = function() return ipairs({ container }) end

ContainerFrameItemButtonMixin = { OnModifiedClick = function() end }
function hooksecurefunc(target, method, callback)
  assert(type(target) == "table", "Forever should use the mixin hook")
  local original = target[method]
  target[method] = function(...)
    original(...)
    callback(...)
  end
end

local namespace = {}
assert(loadfile(addonRoot .. "vo/WantedItems.lua"))("Peddler", namespace)
assert(loadfile(addonRoot .. "Peddler.lua"))("Peddler", namespace)

local eventFrame = createdFrames[1]
eventFrame.scripts.OnEvent(eventFrame, "ADDON_LOADED", "Peddler")

namespace.markWares()
assert(texture.shown, "a grey item from a named-colour hyperlink was not marked")

AutoSellGreyItems = false
namespace.markWares()
assert(not texture.shown, "the automatic grey marker did not clear")

ctrlDown = true
ContainerFrameItemButtonMixin.OnModifiedClick(itemButton, "RightButton")
assert(ItemsToSell["12345-7"] == 1, "Ctrl-right-click did not mark the random-suffix item")
assert(texture.shown, "the manual coin marker did not appear")

eventFrame.scripts.OnEvent(eventFrame, "MERCHANT_SHOW")
assert(soldBag == 0 and soldSlot == 1, "the marked item was not sold through C_Container.UseContainerItem")

print("Peddler Forever functional test passed")
