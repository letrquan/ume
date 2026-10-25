# ume 梅

A personal Wayland desktop shell written in [Quickshell](https://quickshell.org) (QML) for the
[mango](https://github.com/mangowm/mango) compositor. Liquid-glass islands, colors taken from the
wallpaper, and every piece of the desktop in one shell.

> This is my daily setup on one laptop, published as-is. It's tuned to my hardware and my
> taste, so expect to read and change some code before it fits yours. Inside the code it's
> still called **mine** (`qs -c mine`, `~/.config/quickshell/mine`).

![The desktop with the control center open](docs/screenshot.jpg)

## Tour

Every clip below is the real shell, recorded in a headless session with made-up data
(notifications, music, lyrics, calendar, clipboard, updates, devices). That session had no network
or Bluetooth, so those show as off. The whole walkthrough as one video (2 min, 1920×1200 MP4, 37 MB):
[walkthrough.mp4](https://github.com/letrquan/ume/releases/download/walkthrough/walkthrough.mp4).

<table>
<tr>
<td width="50%"><img src="docs/desktop.webp" alt="The desktop"><br><b>Desktop</b>: three glass islands, the dock, a desktop clock with the weather and music. Hover a stat for more; plugging in the charger grows a live activity out of the middle island.</td>
<td width="50%"><img src="docs/notifications.webp" alt="Notifications"><br><b>Notifications</b> grow out of the middle island. The list, grouped by app, sits behind the bell.</td>
</tr>
<tr>
<td><img src="docs/launcher.webp" alt="Launcher"><br><b>Launcher</b> (tap Super): apps, settings, math and emoji (<code>:</code>) in one field.</td>
<td><img src="docs/control-center.webp" alt="Control center"><br><b>Control center</b> (Super+N): toggles, volume, the player and the battery.</td>
</tr>
<tr>
<td><img src="docs/now-playing.webp" alt="Now Playing"><br><b>Now Playing</b>: click the music in the bar. The accent colors follow the album art.</td>
<td><img src="docs/calendar.webp" alt="Calendar and weather"><br><b>Calendar</b> (click the clock): your <code>.ics</code> events and the next hours of weather.</td>
</tr>
<tr>
<td><img src="docs/overview.webp" alt="Overview"><br><b>Overview</b> (Super+O, the hot corner, 4 fingers): every workspace with live windows. Type to find one, drag to move it.</td>
<td><img src="docs/alt-tab.webp" alt="Alt+Tab"><br><b>Alt+Tab</b>: hold Alt, tap Tab, let go to switch.</td>
</tr>
<tr>
<td><img src="docs/wallpaper.webp" alt="Wallpaper picker"><br><b>Wallpaper</b> (Super+Y): the new one spreads from where you clicked, and every color follows it (matugen).</td>
<td><img src="docs/osd-power.webp" alt="Volume popup and power menu"><br><b>Volume popup</b> and the <b>power menu</b> (Super+X).</td>
</tr>
<tr>
<td><img src="docs/cheat-sheet.webp" alt="Shortcut cheat sheet"><br><b>Cheat sheet</b> (Super+/): every shortcut, read from mango's config.</td>
<td><img src="docs/settings.webp" alt="Settings"><br><b>Settings</b> (Super+,): every knob of the shell, searchable.</td>
</tr>
<tr>
<td><img src="docs/clipboard.webp" alt="Clipboard history"><br><b>Clipboard history</b> (Super+V). API keys, tokens and one-time codes are left out, and so is whatever a password manager marks secret.</td>
<td><img src="docs/lock.webp" alt="Lock screen"><br><b>Lock screen</b>: face unlock (optional), a wrong password shakes, and "while you were away" lists what came in.</td>
</tr>
<tr>
<td><img src="docs/updates.webp" alt="Updates panel"><br><b>Updates</b> (click the updates icon): what waits in the repos, the AUR and Flatpak, Arch news since your last upgrade, and a heads-up for packages worth a look first. Update installs with live progress and says what needs a restart.</td>
<td><img src="docs/control-pages.webp" alt="Hotspot and Tailscale pages"><br><b>Hotspot</b> and <b>Tailscale</b> in the control center: turn the hotspot on and share it with a QR code; see your tailnet's devices and its exit nodes.</td>
</tr>
<tr>
<td><img src="docs/tiles-song.webp" alt="Name that song and the tile editor"><br><b>Name that song</b> listens to what's playing and names it (songrec). <b>Edit</b> picks and orders the control center's tiles.</td>
<td><img src="docs/usb-battery.webp" alt="USB drives and battery popups"><br><b>USB drives</b>: a notification, then a bar item with free space, Open and Eject. The <b>battery</b> popup graphs the last 24 hours and shows the battery's health.</td>
</tr>
<tr>
<td><img src="docs/lyrics.webp" alt="Lyrics"><br><b>Lyrics</b> (lrclib.net) follow the song in the bar, in Now Playing and on the desktop music card.</td>
<td><img src="docs/markup.webp" alt="Screenshot markup"><br><b>Screenshot markup</b> (Print, then E): box, arrow, text, blur and pen right on the frozen screen, then save or copy.</td>
</tr>
<tr>
<td><img src="docs/translate.webp" alt="Translate a region"><br><b>Translate</b> (Super+Shift+D): pick text on the screen; it's read (tesseract) and translated, English ⇄ Vietnamese by default.</td>
<td><img src="docs/qr.webp" alt="QR scan"><br><b>QR scan</b> (Super+Shift+Q): pick a code on the screen; a link can be opened or copied from the notification.</td>
</tr>
</table>

## What's in it

- **Bar**: three glass islands (left, clock, right) whose items you can rearrange, a live-activity
  segment in the middle island, a system tray, and items for updates, USB drives and Tailscale
- **Notifications** that grow out of the middle island, with a history list behind the bell
- **Launcher** (tap Super) with an app, emoji, calculator and settings search, and a **clipboard history** (Super+V)
- **Control center** (Super+N) for Wi-Fi (share a network as a QR code), Bluetooth, audio, a hotspot,
  Tailscale, airplane mode, night light, phone (KDE Connect), name that song (songrec), battery health
  and media. Pick and order its tiles in Settings
- **Dock**, **overview** (Super+O / hot corner) with live window pictures and drag between workspaces,
  and an **Alt+Tab** switcher
- **OSD** for volume, brightness, mic, caps lock and num lock
- **Wallpaper picker** (Super+Y) with [matugen](https://github.com/InioX/matugen) colors pushed to
  GTK, foot, starship and mango's borders
- **Screenshots** (freeze, then pick a region or window) with **markup** right in the overlay (pen,
  arrow, box, text, blur), **screen recording**, **OCR** (Super+Shift+T), **QR scan** (Super+Shift+Q),
  **Google Lens** (Super+Shift+G), **translate** a region (Super+Shift+D) and a **color picker**
- **Calendar** with weather (Open-Meteo) and `.ics` events, a desktop clock, and a **Now Playing** card
  with synced lyrics ([lrclib.net](https://lrclib.net)), also on the desktop music card
- **Updates** panel (Arch): repo, AUR and Flatpak updates, Arch news, and a heads-up for packages
  worth a look first (kernel, mesa, Qt, ...)
- **Power menu** (with "Restart to Windows" on dual boot), **polkit** password dialog, **lock screen**
  (`lock.qml`), and an optional **greetd login screen** built from the same parts
- **Idle**: dim, screen off and lock, with an optional presence sensor lock, and optional auto
  brightness from the light sensor
- **Settings window** (Super+,) where every knob in `common/Style.qml` can be changed
- **Tablet mode**: on-screen keyboard, auto-rotate
- **Cheat sheet** of every shortcut (Super+/)

## Requirements

Developed on CachyOS with these versions:

| | |
|---|---|
| Shell | `quickshell` 0.3.2, Qt 6 |
| Compositor | `mango` 0.18 (talks to it through `mmsg`) |
| Colors | `matugen` 4.x |
| Fonts | Google Sans Flex, Material Symbols Rounded |
| Clipboard | `wl-clipboard`, `cliphist`, `wl-clip-persist` |
| Screenshots | `grim`, `slurp`, `swappy`, `tesseract` (OCR), `hyprpicker`, `wf-recorder`, `imagemagick` |
| System | `brightnessctl`, `wlsunset`, `hypridle`, `iio-sensor-proxy`, `iproute2`, `jq`, `curl` |
| Optional | `cava` (visualizer), `kdeconnect` (phone), `wtype` (on-screen keyboard), `hyprlock` (lock fallback), `howdy` (face unlock), `greetd` + `cage` (login screen) |
| Optional, newer parts | `socat` (faster key binds; without it they go through `qs ipc`), `networkmanager` (hotspot, Wi-Fi QR), `qrencode` (Wi-Fi QR), `zbar` (QR scan), `songrec` (name that song), `tailscale`, `udisks2` (USB drives), `pacman-contrib` + `paru` + `flatpak` (updates), `efibootmgr` (restart to Windows), `tesseract-data-vie` (translate from Vietnamese) |

The icon theme is set to `ZorinGrey-Dark` at the top of `shell.qml`, `lock.qml` and
`lock-preview.qml`. Change it to one you have.

## Install

```sh
git clone https://github.com/letrquan/ume ~/.config/quickshell/mine
install -Dm755 ~/.config/quickshell/mine/extras/bin/mine    ~/.local/bin/mine
install -Dm755 ~/.config/quickshell/mine/extras/bin/qs-lock ~/.local/bin/qs-lock
cp ~/.config/quickshell/mine/extras/mango/shell-mine.conf ~/.config/mango/
touch ~/.config/mango/noctalia-colors.conf   # the shell fills it with wallpaper colors
```

Then add `source=./shell-mine.conf` to `~/.config/mango/config.conf`, log out and log back in.
That file starts the shell (`mine start`, which restarts it if it crashes), starts the backup lock
(`scripts/lock-guard.sh`) and binds the keys.

To try it without mango's keybinds, run `qs -c mine`.

### Settings

Your changes are saved in `~/.local/state/mine-shell/settings.json`. Any value missing there
falls back to the default in `common/Style.qml`. Weather defaults to Ho Chi Minh City; change it
in Settings → Calendar & weather. Translate defaults to Vietnamese ⇄ English (`translatePair`).

These parts talk to outside services: weather (Open-Meteo, city level), lyrics (lrclib.net, the
song playing), translate (Google Translate over HTTPS, the text you pick), Google Lens (the picture
you pick), name that song (songrec, a few seconds of audio) and Arch news (archlinux.org).

### Things that touch the system

These scripts use `sudo` and change files under `/etc`. Read them before running them. Each one
has an undo script.

- `greeter-setup/`: greetd login screen (`greeter-install.sh` / `greeter-revert.sh`)
- `setup/face-setup.sh`: Howdy face unlock for the lock screen only (`face-undo.sh`)
- `setup/boot-setup.sh`: quiet boot (hidden GRUB menu, plymouth) (`boot-undo.sh`)
- `scripts/tablet-keyboard.sh`: libinput quirk that keeps the keyboard working in tablet mode

These run as root through `pkexec`, so the shell's own polkit dialog asks for your password each time:

- the updates panel's Install (`scripts/update-run.sh`: `pacman -Syu`; Flatpaks run as you)
- "Restart to Windows" (`efibootmgr -n`, the next boot only)

### Hardware notes

Written on an HP OmniBook 2-in-1 (AMD, 1.25 scale, OLED). Some parts assume it:

- the built-in screen is `eDP-1` (auto-rotate, pen mapping)
- the presence lock reads an iio proximity sensor
- tablet mode comes from mango's `fold`/`unfold` switch events
- `scripts/tablet-keyboard.sh` targets that laptop's keyboard

`extras/bin/mine` also falls back to [Noctalia](https://github.com/noctalia-dev/noctalia-shell)
when the shell isn't running. Without Noctalia, those fallbacks just do nothing.

## Layout

```
shell.qml        entry point (qs -c mine)
lock.qml         the lock screen, started by qs-lock
greeter.qml      the greetd login screen
common/          Style (every knob), Motion, Colors, glass, shapes, shaders
services/        state and system glue (audio, network, notifications, idle, mango, ...)
bar/ dock/ control/ launcher/ notifications/ overview/ ...   one folder per surface
matugen/         color templates
scripts/         helpers the shell runs
extras/          ~/.local/bin/mine, qs-lock and the mango config
```

After editing a shader, rebuild its `.qsb` with Qt's `qsb` (`/usr/lib/qt6/bin/qsb` on Arch):

```sh
qsb --glsl "100 es,120,150,300 es,330" --hlsl 50 --msl 12 \
    -o common/shaders/glassrim.frag.qsb common/shaders/glassrim.frag
```

## Credits

- `common/shapes/`: [rounded-polygon-qmljs](https://github.com/end-4/rounded-polygon-qmljs) by end-4
  (Apache-2.0, license in that folder), a port of AndroidX's shape library
- The lock screen's typed-character shapes and opening animation follow
  [Caelestia](https://github.com/caelestia-dots/shell)'s lock
- Motion curves follow [end-4's dots](https://github.com/end-4/dots-hyprland) and Material 3 Expressive
- Emoji names come from GTK 4's emoji data (Unicode CLDR)
- Wallpapers in the screenshots and clips: Unsplash photos that ship with Zorin OS (Canyon by
  Ashim D'Silva, Waves by Angus Gray and the rest of the picker), the Tarantula Nebula (NASA, ESA,
  CSA, STScI; public domain), M83 (NASA, ESA and the Hubble Heritage Team; public domain) and a beech
  forest (W.carter, CC0)

## License

GPL-3.0. See [LICENSE](LICENSE).
