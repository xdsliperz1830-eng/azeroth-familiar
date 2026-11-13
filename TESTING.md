# In-game test checklist

## v0.7.0: toolkit (new window, eight pages)
Fully exit and restart WoW (new files in the .toc). Nothing below has been run in the real game yet.

First, so I can check what your client supports:
- [ ] `/aa diag`, then `/reload`. The diagnostics now list which game settings and features exist. I can read the saved result myself.

Window
- [ ] `/aa` opens on **Overview** with a list of pages down the left. Each page opens; none shows a red "this page hit an error" message.
- [ ] Drag the title bar, resize from the corner, Escape closes, position is kept after `/reload`.
- [ ] The **Assistant** page works exactly as before (ask, shift-click links, Settings, Ask AI, companion).
- [ ] `/aa <question>` and the Assistant chat tab still answer.

Overview
- [ ] The cards show sensible values (name/level, zone and coordinates, gold, durability, bag space, fps/latency).
- [ ] In combat, "Health and mana" says "hidden in combat" and no Lua error appears.

Graphics
- [ ] "Current:" names a preset or says Custom. Each preset button shows a green message in the title bar.
- [ ] Each quality row shows "N of M". Press + and -: the number changes, and the game's own Graphics menu shows the same change. Tell me any row that says "the game kept ...".
- [ ] A greyed-out row means that setting isn't in this client: tell me which.
- [ ] **Restore my original settings** puts everything back. **Game defaults** resets the page.

Performance
- [ ] Frame rate and latency update once a second. "Show frame rate on screen" adds a small movable readout; `/aa fps` toggles it.
- [ ] **Measure** lists addon memory.

Character / Bags / World
- [ ] Character: experience, rested, session numbers, durability list and target line look right.
- [ ] Bags: free slots and gold match; grey items are listed with a vendor value; the search box finds items.
- [ ] Fill every bag slot, then loot a corpse: one chat line names the cheapest stack, the bags open if closed, its slot pulses red with a bouncing "DROP" label (in Bagnon, and in the default bags), and its tooltip says to drop it. No mark with the loot window closed. Close the loot window: the mark goes, and bags opened for it close. Drop the item while looting: the mark goes. Quest items, the hearthstone and profession tools (skinning knife, mining pick, fishing pole) are never picked. Viewing another character in Bagnon shows no mark. Switch it off on the Interface page: no glow.
- [ ] World: coordinates match the map. **Save this spot**, then **Pin** puts the game's map pin there (or Pin is greyed out). **Copy** opens a copy box. `/aa pin Bank` saves from chat.

Gameplay
- [ ] Each toggle matches the game's own option (for example Auto-loot in the Controls menu). Greyed-out ones don't exist here: tell me which.
- [ ] Camera distance and UI scale steppers change the game; the value shown is what the game accepted.
- [ ] In combat, changes are refused with a message.

Interface and reminders
- [ ] Window size, opacity, compact navigation, start page and the card checkboxes all apply.
- [ ] Reminders: one chat line at low durability, at 3 or fewer free bag slots, when opening a vendor with greys or repairs, and on level-up. Each can be switched off.
- [ ] Watch for "Interface action failed because of an AddOn" at any point and tell me what you were doing.

## v0.6.2: auto-check
- [ ] Ask something the addon sends to Mrgl. After the send reload, the tab says it will check automatically in 25 seconds.
- [ ] About 25 seconds later the UI reloads by itself, and the answer appears in the Assistant tab (not duplicated in General).
- [ ] If you're in combat at that moment, it waits and reloads a few seconds after combat ends.
- [ ] [Don't auto-check] stops it; [Check for answer] still works by hand.
- [ ] If you ever see "Interface action failed because of an AddOn" at the auto reload, the addon turns auto-check off by itself. Tell me if that happens.

## v0.6.0: Assistant chat tab
Fully restart WoW (new file in the .toc).
- [ ] An "Assistant" tab appears in the chat window a couple of seconds after login, with a welcome line.
- [ ] With the Assistant tab selected, an "Ask Azeroth Familiar..." box shows just below the chat lines. Click it, type a question, press Enter: the answer appears in the tab. Switching to General hides the box.
- [ ] On the Assistant tab, pressing Enter opens the normal chat box starting with "/aa ". Typing a question there also goes to the assistant, not public chat.
- [ ] On the General tab, pressing Enter does NOT add "/aa ".
- [ ] Item and quest links in the tab show tooltips; [Wowhead]/[Check for answer]/[Ask Mrgl] links work when clicked in the tab.
- [ ] A companion answer arrives in the tab after [Check for answer].
- [ ] /reload: the tab is still there, and no second tab is created.
- [ ] Close the tab (right-click > Close Window), /reload: it stays closed. `/aa tab` brings it back.
- [ ] Chatting normally in General/Party/Guild still works, including in combat (watch for "Interface action failed because of an AddOn"). If it ever appears, tell me.

## v0.5.0: automatic companion
Copy the whole addon folder again, then `/reload` (the .toc didn't gain files, but its version changed; a full restart is safest).
- [ ] With the companion running, `/reload` once: the chat says "Azeroth Companion detected".
- [ ] Ask "what talent should I go next" and press Enter: it says "Asking Mrgl..." and the UI reloads by itself.
- [ ] After the reload, the chat window says "Mrgl is answering ..." with a [Check for answer] link, and the minimap button shows a green "!".
- [ ] The companion window shows the question, then "Answer ready!"
- [ ] Click [Check for answer] in the chat window (or the button in the addon window, or Shift+click the minimap button): the UI reloads.
- [ ] The answer appears in the addon window AND in the normal chat window; source links open a copy box.
- [ ] Offline questions ("search my bags for linen", a linked item) still answer instantly without a reload.
- [ ] "ai <question>" always goes to the companion.
- [ ] Settings: untick "Ask the companion automatically": unanswerable questions show Wowhead/Ask AI again.

## v0.4.0: desktop companion
Because the `.toc` changed (new files), **fully exit and restart the game**.
- [ ] `/aa diag` lists ReloadUI as present.
- [ ] Ask AI > **Send to Companion**: the UI reloads, and chat says 1 question is waiting, with [Check for answer] and [Cancel waiting questions].
- [ ] The companion window says "A question from Azeroth"/"searching", then "Answer ready!"
- [ ] Click [Check for answer]: the UI reloads; the answer shows in purple with clickable Sources; the waiting message is gone.
- [ ] /reload again: the same answer is NOT shown twice.
- [ ] A question typed into the companion window shows in game after the next reload, as "(asked the companion)".
- [ ] Click a Sources link: a copy box opens with the URL.
- [ ] Send to Companion while in combat: it refuses politely and the question stays queued.
- [ ] [Cancel waiting questions] clears the queue.

## v0.3.0: Ask AI box
Because the `.toc` changed (icon), **fully exit and restart the game**. `/reload` isn't enough.
- [ ] The toolbar shows only Ask AI, Settings and Clear.
- [ ] Type a question, click **Ask AI**: the offline answer appears in the chat AND the Ask AI box opens.
- [ ] Top text is already selected; Ctrl+C copies it. Typing into it doesn't change it.
- [ ] Clicking the top text again re-selects all of it.
- [ ] Ticking **Include my character** adds your level/gear/stats to the text right away; unticking removes them.
- [ ] Paste a reply into the bottom box, click **Show answer**: it appears in purple in the chat and the box closes.
- [ ] Clicking **[Ask AI]** inside an answer opens the box for that question (and the item you linked).
- [ ] Settings > **Preview** shows what "include my character" would share; no name/realm/guild.

## v0.2.0 additions
- [ ] A question-mark button appears on the minimap edge. Left-click toggles the window; right-click opens Settings.
- [ ] Drag the button around the minimap; `/reload`; it stays where you left it.
- [ ] `/aa minimap` hides it; run it again to show it. Settings has a "Minimap button" checkbox too.
- [ ] If the client has the AddOn compartment menu (near the minimap), Azeroth Familiar is listed there.
- [ ] `/aa diag` shows "database: contract 4 OK" and "test read: Linen Cloth", plus "Minimap button: OK".
- [ ] "where can I get the sleeping bag?" (no link): vendors/drops with zone and coordinates, or an honest "not listed".
- [ ] Shift-click an item + "which vendor sells this?": vendor list; the coordinates match Questie's map pins.
- [ ] "where is <an NPC name you know>": zone and coordinates.
- [ ] Shift-click a quest + "where do I go?": quest giver and turn-in NPC appear.
- [ ] Link an item, then ask "what is this for?" with no link: it says "(about [item] from your last question)".
- [ ] "what is the meaning of life": no Wowhead search link for junk words.
- [ ] Linking a very common item (Linen Cloth) + "where can I get this": answers without a noticeable freeze.

## First run (v0.1.0 checks)

Do these in order on your Enhancement shaman. Write down anything that fails, plus any Lua error text
(BugSack makes this easy). Nothing here has been run in the real client yet.

## 1. Loading
- [ ] Character screen > AddOns: "Azeroth Familiar" is listed and enabled (note whether it says "out of date").
- [ ] Log in with no Lua error.
- [ ] Chat shows no warning about the interface number. (If it does, note the number it shows.)
- [ ] If chat warns that `/aa` is used by another addon, note which one.

## 2. Diagnostics (the most useful test)
- [ ] `/aa diag`: the window opens with game version, build, interface and "X of Y APIs present".
- [ ] Copy the **Missing:** line and the **Link insertion hooks:** line and send them to me.
- [ ] `/reload`, then send me the `diag` section of
      `WTF\Account\<account>\SavedVariables\AzerothAssistant.lua`. (It has no name, realm or chat data.)

## 3. Window
- [ ] `/aa` opens and closes the window; `/azerothassistant` does too.
- [ ] Drag the title bar to move it; drag the bottom-right corner to resize it.
- [ ] `/reload`: the window keeps its position, size and conversation.
- [ ] Escape closes it.
- [ ] Mouse wheel scrolls the conversation (Shift + wheel jumps to the top/bottom).
- [ ] Settings > font size + and - change the text size.
- [ ] Open it during combat. It shows, and nothing gets "blocked" or tainted.

## 4. Links
- [ ] Click the input box, then shift-click an item in your bags: the link appears in the box.
- [ ] Shift-click a quest in your quest log / tracker while the box has focus: the quest link appears.
- [ ] With the normal chat box open, shift-click still links into chat as usual.
- [ ] Hover a link in the conversation: the item tooltip shows. Click it: the item reference window opens.
- [ ] Click a **[Wowhead: ...]** link: a box opens with the URL selected; Ctrl+C, paste into a browser,
      and check that the page opens. **Test an item link AND a quest link** (the quest URL format is unverified).

## 5. Questions
- [ ] "search my bags for linen" (use something you carry): correct count and stacks.
- [ ] Link one weapon + "is this an upgrade?": the "Current" item is your equipped weapon; stats and DPS look right.
- [ ] Link two items + "which is better for me?": differences match the tooltips.
- [ ] Link an item with an "Equip:" or "Chance on hit:" line: the line is listed; humanoid-only effects are tagged.
- [ ] Link an item still not cached (someone else's link): "still loading" message or full answer, no error.
- [ ] Quest link + "where do I go?": objectives and progress match the quest log.
- [ ] "my quests": the list matches your log, with zone headers.
- [ ] "my professions": skill levels match.
- [ ] Open your Leatherworking (or other) window, close it, then link a craftable item + "what materials do I need?".
      Note whether reagents show, or the "Recipe reading problem" text.
- [ ] "which vendor sells this?" + item link: "not available offline" + Wowhead link, no invented answer.

## 6. Ask AI round-trip
- [ ] Settings: context permission is OFF by default. Ask AI packet says "not included".
- [ ] **Context** button: preview shows level/race/class/gear/stats/professions/quests, and **no** name/realm/guild.
- [ ] Turn permission ON, untick "Quest log": the packet no longer has the quest log line.
- [ ] Ask AI: Ctrl+C works; paste the text into Claude; paste the reply into the bottom box and click **Show answer**.
- [ ] The reply shows in purple under "External answer - pasted by you, not verified by the addon".
- [ ] Paste text containing `|cffff0000red|r`: it shows literally, not as red text.

## 7. Data
- [ ] **Clear** empties the conversation.
- [ ] Settings > **Erase all saved data** asks for confirmation and resets everything.
