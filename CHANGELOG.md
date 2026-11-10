# Changelog

## 0.4.0 (2026-11-10)

- New: language choice (Tweaks+ > General): Automatic, English or Deutsch, applied after /reload. Spell, item and zone names stay in the game's language.
- Hide chat: with EllesmereUI Chat the chat, its tab strip and panels now vanish at once. The new option "Fade" (off by default) brings back EllesmereUI's own one-second fade.
- Fixed: the zone text and hide chat settings follow EllesmereUI profile switches (the sub zone setting is kept per profile, a chat override no longer stays behind in the old profile or after a crash).
- Fixed: fast zoom on a keyboard key zoomed twice per press.
- Fixed: the icon search found spells with IDs above 40000 only by icon name; names are now indexed up to ID 1,600,000 without stalling the game.
- Fixed: the copy chat window could be changed with Backspace, Delete, cut and paste.

## 0.3.0 (2026-11-06)

- Tweaks > Item count: stackable items show in the top right corner of the tooltip how many of them this character
  has, all stacks added up, with the split between bags and bank once the bank holds some. A format field sets the
  text around the number: `[{count}]` shows `[20]`, `{count} pcs` shows `20 pcs`. Off by default.

## 0.2.0 (2026-11-05)

- **The icon search matches this game again.** Its icon data had been built from a Retail client: it offered about 2,500 icons World of Warcraft: Forever does not have (empty tiles in the filter) and was missing the ones Forever brought. It is now built from the Forever client, 30,550 icons.
- Tweaks > Window reset: a key binding (game key bindings > AddOns > EUI Tweaks) resets the window under the
  mouse to its default position and zoom, like "Reset Specific Window" of EllesmereUI's Shifter. Asks first by
  default; "Reset without asking" reloads at once.

## 0.1.0

- First version.
- Options in the EllesmereUI panel, section "Tweaks+" (Tweaks, Extensions, ColorRewrite).
- Tweaks: fast camera zoom, hide chat (button in the EllesmereUI accent or a picked color), a better copy-chat window
  behind EllesmereUI's Copy Chat button (search, timestamps, channel colors, font size; all text selected on opening).
- Tweaks > Zone text: the sub zone in a second box at the EllesmereUI minimap zone text, with position and X/Y offset.
- Extensions: search and category filter for EllesmereUI's macro "Choose Icon" window (icon data loads on demand).
- ColorRewrite: find one color everywhere in the EllesmereUI settings and replace it, with undo.
