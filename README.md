# AI usage counter in menu bar on macOS

SwiftBar plugin for Claude/Codex usage in the macOS menu bar (top right).

![AI Usage Bar in the macOS menu bar](docs/menu-bar.png)

## Setup

```sh
git clone https://github.com/crearo/ai-usage-bar.git
cd ai-usage-bar
brew install swiftbar
npm install -g ccusage@latest
open -a SwiftBar
# When SwiftBar asks for a plugin folder, choose:
/path/to/this/repo/swiftbar
```

Update ccusage regularly with:

```sh
npm install -g ccusage@latest
```

## After reboot

To start after reboot:

```text
System Settings -> General -> Login Items & Extensions -> Open at Login -> add SwiftBar
```

If the item is missing after reboot, open SwiftBar (command + space, type SwiftBar) and select the plugin folder again.

## Troubleshooting

Check ccusage:

At least one of these should work:

- `ccusage codex daily`
- `ccusage claude daily`
