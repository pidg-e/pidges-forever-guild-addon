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
* **Open** lists everyone's open orders; **Accept** one to craft it.
* **My Orders** are yours: **Cancel**, or **Received** once you have it.
* **My Crafts** are the ones you accepted: **Done** when it's handed over,
  or **Give Back** to reopen it.
* **History** keeps finished and cancelled orders for two weeks.
* Filter by profession, hover a row for the item and note, right-click to
  whisper the other person. You get a chat message when someone accepts or
  finishes your order.

### Members' professions

Click a member on the guild **Roster** and a **Professions** panel appears
under their details (below Remove and Group Invite), with each profession and
skill level, even while they're offline.

### Links

Buttons on the guild panel's **Info** tab, level with the "Info" title above
the Message of the Day:

* **Pidge's Forever Guild AddOn** (GitHub) shows this repository. It is
  always there.
* **Discord** and **Warcraft Logs** show your guild's invite and logs page,
  once your Guild Master has set them. They appear to the right of the
  GitHub button, which moves left to make room.

Clicking one opens a box with the link already selected: press **Ctrl+C**,
then paste it into your browser. (WoW doesn't let addons open web pages, so
copying is the closest it can get.)

### Guild Master settings

The Guild Master gets a **Pidge's Forever Settings** entry in the Guild
Control dropdown (or type `/pfg settings`). Enter the Discord invite (a
`discord.gg` link or just the code) and the Warcraft Logs guild page, then
**Save**. Leave a box empty to remove that button.

The links are saved as two lines at the end of the guild's Info text:

```
Discord: discord.gg/abc123
Warcraft Logs: forever.warcraftlogs.com/guild/id/12345
```

Every member's game already receives the Info text, even when the Guild
Master is offline, and only ranks allowed to edit it can change it. So the
links reach everyone with the addon, members without it can still read them,
and you can also type or edit those two lines by hand.

### How guildmates share data

Crafters share what their recipes make the first time they open each
profession window with the addon.

Orders and professions travel between guildmates over hidden guild addon
messages, and everyone keeps a copy in their saved variables. So only
guildmates who run the addon take part, but they see each other's orders and
professions even when the other person is offline. When you log in, one
online guildmate sends you everything you missed.

### Commands

* `/pfg orders` opens the crafting orders.
* `/pfg sync` asks the guild for the latest orders and professions.
* `/pfg items` shows how many items the order form can suggest.
* `/pfg profs` shows what professions the addon can see.
* `/pfg discord`, `/pfg logs`, `/pfg github` show the links.
* `/pfg settings` (Guild Master) opens the link settings.

## Install

Download this repository (Code > Download ZIP), unzip it, rename the folder
to `PidgesForeverGuild`, and put it in
`World of Warcraft\_forever_\Interface\AddOns\`, so that
`AddOns\PidgesForeverGuild\PidgesForeverGuild.toc` exists. Then restart the
game.
