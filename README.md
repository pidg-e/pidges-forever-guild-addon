# Pidge's Forever Guild AddOn

Guild tools for any guild on WoW Forever: crafting orders, members'
professions, and buttons for your guild's Discord and Warcraft Logs pages.
Nothing in it shows up, or talks to anyone, unless your character is in a
guild.

## Features

### Crafting Orders

A **Crafting Orders** tab (anvil icon) under the guild panel's side tabs.

* **New Order**: start typing an item's name and pick it from the
  suggestions (or shift-click an item), set the quantity, the profession, an
  optional tip and a short note, then **Post Order**. Suggestions come first
  from what guild crafters' recipes make, then from every craftable kind of
  item in the game (the addon reads the game's item list in the background
  the first time you log in). The form shows who can make the item, or who
  has the profession.
* **Guild Order** button on the profession window (above Create All): opens a
  new order for the selected recipe's item, with its profession filled in.
* Orders are always for a real item, shown like an item link: hover a row
  (or the icon in the form) to see the item's tooltip.
* **Open** lists everyone's open orders; **Accept** one to craft it. Orders
  someone already took stay listed, greyed out and marked "Taken by" them.
* **My Orders** are yours: **Cancel**, or **Received** once you have it.
* **My Crafts** are the ones you accepted: **Done** when it's handed over,
  or **Give Back** to reopen it. At a mailbox, the letter button fills in
  the mail for you: the requester (first and last name, no realm), a subject, the crafted items from your
  bags (exactly the amount ordered: stacks are split into a free bag slot
  first, so keep one free), and a C.O.D. for the tip. Check it and press Send; once the mail
  has gone, the order is marked Done.
* The tip is entered in gold, silver and copper.
* **History** keeps finished and cancelled orders for two weeks.
* Filter by profession, hover a row for the item and note, right-click to
  whisper the other person. You get a chat message when someone accepts or
  finishes your order.

### Wishlist

A **Wishlist** tab (note icon) just above Crafting Orders. List items you want
or need (type a name or shift-click an item, with a quantity and a short note),
and see what everyone else is after. **Guild Wishlist** lists the guild's
members (those with something listed first, with how many items); click one to
show their wishlist beneath their name, and again to fold it away. **My Wishlist** is yours. Whisper
someone from their wish (or right-click it),
and remove your own when you've got it. Officers can remove anyone's. Up to 30
wishes each; it syncs between guildmates just like the orders. Item
suggestions leave out things nobody can get (NPC weapons like "Monster - 2H
Axe", PvP and test placeholders).

### Members' professions

Click a member on the guild **Roster** and a **Professions** panel appears
under their details (below Remove and Group Invite), with each profession and
skill level, even while they're offline.

### Links

Buttons on the guild panel's **Info** tab, level with the "Info" title above
the Message of the Day:

* **Pidge's Forever Guild AddOn** (CurseForge) shows the addon's
  [CurseForge page](https://www.curseforge.com/wow/addons/pidges-forever-guild-addon).
  It is always there.
* **Discord** and **Warcraft Logs** show your guild's invite and logs page,
  once your Guild Master has set them. They appear to the right of the
  CurseForge button, which moves left to make room.

Clicking one opens a box with the link already selected: press **Ctrl+C**,
then paste it into your browser. (WoW doesn't let addons open web pages, so
copying is the closest it can get.)

### Guild Master settings

The Guild Master gets a **Pidge's Forever Settings** entry in the Guild
Control dropdown (or type `/pfg settings`). Enter the Discord invite (a
`discord.gg` link or just the code) and the Warcraft Logs guild page, then
**Save**. Leave a box empty to remove that button.

WoW doesn't let addons change the guild's Info text, so the links travel
between guildmates' addons instead. The Guild Master's addon sends them when
you save and every time you log in, and everyone keeps a copy, so members
who log in while you're offline get them from any guildmate who has them.
Links straight from the Guild Master always win over a copy passed on by
someone else, so members can't swap in their own.

### Guild colors

On the **Colors & Ranks** page of Pidge's Forever Settings, the Guild Master
picks a color for the guild's name and for each rank (right-click a swatch to
reset it to white), and ticks which ranks count as officers.

* Player tooltips show the guild line as **Rank of Guild** in those colors.
* In chat, the guild's name (with or without the angle brackets) shows in the
  guild's color, in the default chat window and in chat addons such as Prat,
  Chatter or Chattynator.
* Other guilds' colors come from their own members, if they use the addon:
  hovering one of them asks their addon quietly. Guilds without it stay white.

### Officers

Officers and up (the Guild Master and the ranks ticked as officers; by
default the rank just below Guild Master) get an **X** on other members'
open and in-progress orders to remove them. The requester is told who
removed it.

### Version

The Info tab shows the addon's version next to "Info". Guildmates' addons
compare versions, and anyone on an older one gets a note in chat to update.

### How guildmates share data

Crafters share what their recipes make the first time they open each
profession window with the addon.

Orders and professions travel between guildmates over hidden guild addon
messages, and everyone keeps a copy in their saved variables. So only
guildmates who run the addon take part, but they see each other's orders and
professions even when the other person is offline.

The way it keeps everyone in step is modelled on
[CraftBoard](https://github.com/MartinPTielemans/craftboard):

* Messages go through AceComm and ChatThrottleLib, which share the server's
  addon bandwidth by size rather than one message a second, and split long
  messages and join them back together. Your own changes (placing, accepting,
  finishing an order) always go first.
* Catch-up traffic is bundled and compressed with LibDeflate, so a sync of
  hundreds of orders takes a handful of messages.
* When you log in, your addon sends a list of the orders it has. One online
  guildmate answers with only the ones you're missing or have old copies of,
  and you send back any they're missing.
* Every ten minutes or so each addon shares a short fingerprint of its orders.
  If someone's doesn't match, they ask for a sync, so a missed message gets
  fixed on its own.

Version 1.3.0 talks a new protocol: guildmates on 1.2.4 or older don't see
orders from 1.3.0 (and the other way round) until they update. They get an
in-game note asking them to.

### Commands

* `/pfg orders` opens the crafting orders.
* `/pfg wishlist` opens the wishlist.
* `/pfg sync` asks the guild for the latest orders and professions.
* `/pfg items` shows how many items the order form can suggest.
* `/pfg profs` shows what professions the addon can see.
* `/pfg discord`, `/pfg logs`, `/pfg curseforge` show the links.
* `/pfg settings` (Guild Master) opens the settings (links, colors, officers).
* `/pfg version` shows which version you have.

## Libraries

Bundled in `Libs`, each under its own license: LibStub (public domain),
CallbackHandler-1.0 and AceComm-3.0 (Ace3, BSD), ChatThrottleLib (public
domain), LibDeflate (zlib, see `Libs/LibDeflate/LICENSE.txt`).

## Install

Install it from
[CurseForge](https://www.curseforge.com/wow/addons/pidges-forever-guild-addon),
or download this repository (Code > Download ZIP), unzip it, rename the folder
to `PidgesForeverGuild`, and put it in
`World of Warcraft\_forever_\Interface\AddOns\`, so that
`AddOns\PidgesForeverGuild\PidgesForeverGuild.toc` exists. Then restart the
game.
