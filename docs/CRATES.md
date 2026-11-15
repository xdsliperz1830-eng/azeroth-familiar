# Crates (formerly Crate Scout)

Crate Scout 0.2.0 was merged into Azeroth Familiar 0.9.0 as the **Crates** page. The
standalone addon is retired; its recipe data, validation, scanner and cost engine are
unchanged and live in `Crates/` under the `AA.Crates` namespace.

## Use
Open `/fam crates` (or `/cratescout`, or **Crates** in the window's navigation).

- **My Crates:** crates in your carried bags; owned materials are deducted. One fully
  owned bundle shows **Ready to fill** at **0c**. Mixed bundles never fill a crate.
- **All Crates:** every catalog recipe, cheapest first; **Count owned** deducts bag
  materials. Unverified recipes stay visible as unsupported. Level requirements show as
  `L10`, red with `!` when your character is too low.
- **Buy & Fill:** empty-crate cash plus fill cost, without owned materials. Expanded, it
  shows the empty crate, its whole-stack purchase plan, extra crates from that stack, the
  material cost and the total cash for that one crate.
- Click a row to expand every alternative: owned/required, need, cost, status and the
  stack or unit purchase plan. **Search** opens Auctionator's exact search when it is
  loaded, otherwise it puts the name in the AH search box for copying.
- **Scan Auction House** runs only when clicked, with the AH open. It shows progress;
  **Cancel** stops safely. Closing the AH invalidates live results at once.
- Every row is an **independent comparison for one crate**. Bags and listings are not
  shared between rows, so there is no combined total.

## Tooltip highlighting
Hovering a supported crate adds four lines (`Azeroth Familiar · Crates`, the best
bundle, what to buy and its cost, the price source and age) and colors the matching
line of the crate's own accepted-bundle list:

- **Green:** cheapest total cash for the missing quantity, including whole-stack
  purchases, from a complete AH snapshot under 120 s old with the AH open; or a fully
  owned bundle (**Ready to fill · 0c**). Ties highlight all tied bundles and say **Tie**.
- **Amber:** the cheapest is only a cached Auctionator estimate (**Estimate**).
- **Cheapest of priced bundles** when some alternatives have no price.
- No highlight when nothing is priced, the scan is incomplete or expired, the AH is
  closed, or the crate is unknown/unverified.

The bundle is found by item ID and matched by its displayed quantity and client item name,
only inside the accepted-bundle section and only on whole lines. When bundles share one
tooltip FontString, only that substring is colored. Lines update in place as data changes
and the client text is restored on hide. Switch it off on the Interface page
("Crate tooltips: highlight the cheapest bundle"). The page's BEST / TIE / READY / EST
badges use the same rules (`*` = cheapest of priced).

## Data and verification
Catalog 2026-11-15.1: 30 published client recipe records, 96 material IDs, sourced from
build 1.60.1.70532 ([ForeverDiff](https://foreverdiff.com/waylaid-crates/); per-recipe URLs
in `docs/crates-catalog-source.json`). Each recipe is used only after this client's own
rendered tooltip matches it (material ID/name pairs, quantities, bundle count, required
level); English clients only, others fail closed. Server drop availability is not
established by these records.

The AH scanner refuses unreviewed builds (reviewed: 1.60.1.70938, interface 16001). It uses
`C_AuctionHouse.SendSearchQuery`, waits for metadata, pages until results are complete,
checks the throttle, spaces requests by 0.8 s and cancels if another AH search starts.
Item auctions use exact whole-stack (0/1) optimization; commodities use the cheapest
unit-price tiers. Own and account auctions are excluded. Snapshots expire after 120 s or
when the AH closes and are never saved. Auctionator 347 is optional: only its public API
(`GetAuctionPriceByItemID`, `GetAuctionAgeByItemID` in days, `MultiSearchExact`) is used,
guarded and discovered late, with the caller name "Azeroth Familiar".

Client evidence for the tooltip hooks: addons installed for this client hook
`TooltipDataProcessor.AddTooltipPostCall` when present and otherwise `OnTooltipSetItem`,
plus `OnTooltipCleared`/`OnHide`. Crates does the same for GameTooltip and ItemRefTooltip
only (never its own validation tooltip). DaylightUI_Tooltip does not rewrite Use text.

## Settings
`AzerothAssistantDB.settings.crates = { countOwned = false, tooltip = true }`. The old
`CrateScoutDB` only held the Count owned checkbox and the standalone minimap and window
positions, and is not read. Tick Count owned again if you used it.

## Tests
`python tests/run.py [path/to/lua51.dll]` runs `tests/crates_test.lua` (40 groups) against
Familiar's real Core, widgets and page shell with mocked client APIs: optimizer (200
randomized cases vs exhaustive search), catalog, ownership, providers, scanning,
validation, tooltip highlighting (shared FontString, decoys, ties, estimates, staleness,
AH close, tooltip switching), the page, events, slash commands, settings and diagnostics.
Fixtures only: not an in-game test.
