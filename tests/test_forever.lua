local addonRoot = (arg and arg[1]) or "./"
if string.sub(addonRoot, -1) ~= "/" and string.sub(addonRoot, -1) ~= "\\" then
  addonRoot = addonRoot .. "/"
end

local unpackValues = table.unpack or unpack
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
local loadedAddons = {}
C_AddOns = { IsAddOnLoaded = function(name) return loadedAddons[name] or false end }
C_Timer = { After = function(_, callback) callback() end }

function strsplit(separator, value)
  local result = {}
  local pattern = "(.-)" .. separator
  for part in string.gmatch(value .. separator, pattern) do
    table.insert(result, part)
  end
  return unpackValues(result)
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

-- Baganator compatibility and view-lifecycle regressions.
loadedAddons.Baganator = true
AutoSellGreyItems = true
ItemsToSell = {}
UnmarkedItems = {}
Baganator_SingleViewBackpackViewFrame = nil
Baganator_CategoryViewBackpackViewFrame = nil
Baganator = nil
for i=1,200 do namespace.markWares() end
print('  ok: absent Baganator views do not cause repeated errors')

function itemButton:IsVisible() return true end
function itemButton:GetSlotAndBagID() return 1,0 end
texture.shown=false
Baganator_CategoryViewBackpackViewFrame={IsShown=function() return true end,Container={Layouts={{buttons={itemButton}}}}}
namespace.markWares()
assert(texture.shown,'legacy category-only view must mark its live items')
print('  ok: category view works without a single view')
Baganator_CategoryViewBackpackViewFrame.Container=nil
namespace.markWares()
Baganator_CategoryViewBackpackViewFrame.Container={}
namespace.markWares()
Baganator_CategoryViewBackpackViewFrame=nil
print('  ok: partially initialized legacy layouts are safe')

local frames={}
local callbacks={}
Baganator={API={Skins={GetAllFrames=function() return frames end}},CallbackRegistry={}}
function Baganator.CallbackRegistry:RegisterCallback(event,callback,owner)
  assert(owner==eventFrame)
  callbacks[event]=callback
end
itemButton.GetSlotAndBagID=nil
texture.shown=false
frames={{regionType='ItemButton',region=itemButton}}
namespace.markWares()
assert(texture.shown,'grouped frames must be found through the registry and modern bag/slot methods')
print('  ok: modern grouped Baganator marks live backpack items')

local function InvalidButton(bag,visible,methods)
 local b={coins={shown=true,Hide=function(self) self.shown=false end}}
 function b:IsVisible() return visible end
 if methods then
  function b:GetBagID() error('hidden/cached buttons must not be read') end
  function b:GetID() return 1 end
 end
 return b
end
local hidden=InvalidButton(0,false,true)
local cached=InvalidButton(0,true,false)
local bank={IsVisible=function() return true end,GetBagID=function() return -1 end,GetID=function() return 1 end}
local warbank={IsVisible=function() return true end,GetBagID=function() return 6 end,GetID=function() return 1 end}
frames={{regionType='ItemButton',region=hidden},{regionType='ItemButton',region=cached},{regionType='ItemButton',region=bank},{regionType='ItemButton',region=warbank}}
namespace.markWares()
assert(hidden.coins.shown and cached.coins.shown,'unrelated cached/hidden buttons must not be modified')
print('  ok: hidden, cached-character and bank buttons are excluded')

frames={}
for i=1,200 do namespace.markWares() end
Baganator.API.Skins.GetAllFrames=function() return nil end
namespace.markWares()
print('  ok: an empty or not-yet-ready public registry is safe')
Baganator.API.Skins.GetAllFrames=function() return frames end
frames={{regionType='ItemButton',region=itemButton}}
eventFrame.scripts.OnEvent(eventFrame,'ADDON_LOADED','Peddler')
assert(callbacks.BagShow and callbacks.BackpackFrameChanged,'bag lifecycle callbacks must be installed')
AutoSellGreyItems=false;ItemsToSell={}
callbacks.BagShow()
assert(not texture.shown,'opening bags refreshes recycled buttons and clears stale coins')
AutoSellGreyItems=true
callbacks.BackpackFrameChanged()
assert(texture.shown,'switching views refreshes coin markers')
print('  ok: opening bags and changing view refresh coin overlays')
