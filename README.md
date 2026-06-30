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

## Configuration

Settings live in `swiftbar/.usage-counter.conf` (most are also editable from the menu bar dropdown):

- `MODE` — `claude`, `codex`, or `both`
- `RANGE` — `today`, `week`, `last7`, `month`, or `last30`
- `RESET_HOUR` — hour (0-23) the "today" range resets at
- `REFRESH_SECONDS` — `15`, `30`, `60`, or `300`
- `CLAUDE_CONFIG_DIR` — optional. Forwarded to `ccusage` as the `CLAUDE_CONFIG_DIR` env var so it can find Claude usage data in non-default locations. Leave blank to use ccusage's default lookup. If you run Claude Code under multiple accounts/profiles (e.g. via `claude --settings` or separate `.claude-*` home dirs), set this to a comma-separated list of paths to aggregate usage across all of them:

  ```
  CLAUDE_CONFIG_DIR=/Users/you/.claude-work,/Users/you/.claude-personal
  ```

  This only affects the `claude` data source — Codex usage is unaffected.

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
