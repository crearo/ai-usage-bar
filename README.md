# Agent Usage Menu Bar

SwiftBar can show today's Claude/Codex usage in the macOS menu bar with the plugin in `swiftbar/codex-usage.1m.sh`.

## Setup

1. Install SwiftBar:

   ```sh
   brew install swiftbar
   ```

   For faster refreshes, install `ccusage` too:

   ```sh
   npm install -g ccusage
   ```

2. Open SwiftBar and choose this repo's `swiftbar` directory as the plugin folder:

   ```text
   /Users/rish/Developer/usage-counter/swiftbar
   ```

3. SwiftBar will refresh `codex-usage.1m.sh` every minute because of the `.1m.sh` filename.

## Options

Click the menu bar item to change:

- `Codex only`
- `Claude only`
- `Claude + Codex`
- Reset time: `00:00`, `04:00`, `08:00`, or `12:00`

The selected options are stored in:

```text
/Users/rish/Developer/usage-counter/swiftbar/.usage-counter.conf
```

Reset time changes ccusage's daily grouping boundary by using a shifted timezone. For example, `04:00` treats the usage day as starting around 04:00 local time.

## Start After Reboot

Add SwiftBar to macOS login items:

1. Open System Settings.
2. Go to General.
3. Open Login Items & Extensions.
4. Under Open at Login, click `+`.
5. Add SwiftBar from `/Applications`.

SwiftBar should keep using this plugin folder after restart:

```text
/Users/rish/Developer/usage-counter/swiftbar
```

The menu bar line shows today's estimated cost and total tokens. The dropdown shows the token breakdown and the option controls.

The script prefers `ccusage` if installed. Otherwise it uses `npx --yes --prefer-offline ccusage@latest`, then `bunx ccusage@latest`.
