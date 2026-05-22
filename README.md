# AI usage counter in menu bar on macOS

SwiftBar plugin for Claude/Codex usage in the macOS menu bar.

![AI Usage Bar in the macOS menu bar](docs/menu-bar.png)

```sh
brew install swiftbar
npm install -g ccusage
open -a SwiftBar
```

When SwiftBar asks for a plugin folder, choose:

```text
/path/to/repo/swiftbar
```

Click the menu bar item to change the source, refresh interval, or reset time.


## After reboot

To start after reboot: 

```
System Settings -> General -> Login Items & Extensions -> Open at Login -> add SwiftBar
```

If the item is missing after reboot, open SwiftBar (command + space, type SwiftBar) and select the plugin folder again.
