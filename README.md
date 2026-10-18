# Peddler for WoW Forever

This is a compatibility fork of **[Peddler by Cartas](https://github.com/Cartas/Peddler)**, based on upstream Peddler `9.1`. It contains small edits to make the existing addon work on WoW Forever `1.60.1` / interface `16001`, while keeping the Classic equipment rules.

## Credits

- **Original addon author: [Cartas](https://github.com/Cartas)** (credited in the addon as Cartas @ Bloodfang-Classic).
- **Upstream contributors:** [Pierre-Sassoulas](https://github.com/Pierre-Sassoulas), [steino](https://github.com/steino), and [mandmyay1](https://github.com/mandmyay1). See the [upstream contributor history](https://github.com/Cartas/Peddler/graphs/contributors).
- **Small WoW Forever compatibility edits and regression tests:** [saad780](https://github.com/saad780). This fork does not claim authorship of the original addon.

The original code and included artwork come from upstream Peddler. The [original CurseForge project](https://www.curseforge.com/wow/addons/peddler), maintained by Cartas, lists its license as **Public Domain**.

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
