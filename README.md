# AI usage counter in menu bar on macOS

SwiftBar plugin for Claude/Codex usage in the macOS menu bar (top right).

[![Watch demo](https://img.youtube.com/vi/dT2NoWe50r4/maxresdefault.jpg)](https://youtube.com/shorts/dT2NoWe50r4?feature=share)

![AI Usage Bar in the macOS menu bar](docs/menu-bar.png)

Usage data is collected via [ccusage](https://github.com/ryoppippi/ccusage).

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
