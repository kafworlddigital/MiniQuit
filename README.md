# MiniQuit

A tiny macOS menu-bar app: click the Sermo mark, get a small Force Quit card.
Hung apps rise to the top with a "Not running" badge — click one and force quit it.
Healthy apps show no badge. The card closes when you click away.

![MiniQuit icon](icon-preview.png)

## Build

Needs only Xcode's command-line tools. No Xcode project, no dependencies.

```sh
./build.sh
open MiniQuit.app
```

First run tip: `open MiniQuit.app --args --show` pops the card open so you can spot the menu icon straight away.

## Files

- `main.swift` — the whole app: status item, popover list, force quit.
- `Info.plist` — bundle metadata (menu-bar-only via `LSUIElement`).
- `build.sh` — compiles and ad-hoc signs `MiniQuit.app`.

## Notes

- Hung detection reads the same flag Finder uses, with a safe fallback.
- Because of that private flag this is distributed here, not via the Mac App Store.
- macOS 13+.
