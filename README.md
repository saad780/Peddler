# Peddler for WoW Forever

This private fork adapts Peddler to WoW Forever's modern UI while keeping the Classic equipment rules. It currently targets WoW Forever `1.60.1` / interface `16001` and is based on upstream Peddler `9.1`.

Peddler flags unwanted items and automatically sells them the next time you interact with a vendor. Grey items are flagged automatically by default.

## Usage

- **Ctrl + right-click** an inventory item to toggle its sale marker.
- Open a merchant to sell marked items automatically.
- Run **`/peddler`** to open the addon options.

The options let you change the modifier key, limit each sale to the 12 buyback slots, choose which item qualities are sold automatically, and control chat output.

## Forever compatibility

The fork includes support for:

- Named-color item hyperlinks used by the current Forever client
- `C_Item.GetItemInfo` in place of the removed global API
- Pooled Blizzard container buttons and combined bags
- The current `ContainerFrameItemButtonMixin` modified-click path
- Current container selling through `C_Container.UseContainerItem`
- Classic leveling armor and weapon rules

## Test

From the repository root:

```powershell
npx --yes --package fengari-node-cli fengari tests/test_forever.lua
```

The regression test covers automatic grey marking, Ctrl-right-click marking, random-suffix item links, the coin overlay, and merchant selling.
