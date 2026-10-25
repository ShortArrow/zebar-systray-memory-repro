# zebar-systray-memory-repro

While a tray app animates its icons, a [Zebar](https://github.com/glzr-io/zebar)
widget subscribed to the `systray` provider grows its WebView2 renderer to
about 2 GB in one minute, and the memory stays there after the animation stops.

Animated tray apps such as [PPCpuMon](https://github.com/tomozh/PPCpuMon) and
[RunCat365](https://github.com/runcat-dev/RunCat365) trigger it. In a real
setup with such an app running all day, renderers reached about 3 GB each.

## Cause

Two things in Zebar, both at
[5f90d34](https://github.com/glzr-io/zebar/tree/5f90d341867122175cb4a57af594a44752885056):

1. **The systray payload is huge.** Every tray event emits every visible icon
   with its full PNG bytes
   ([systray_provider.rs](https://github.com/glzr-io/zebar/blob/5f90d341867122175cb4a57af594a44752885056/packages/desktop/src/providers/systray/systray_provider.rs)).
   Tauri delivers each emit as JSON, so the bytes travel as a number array:
   `"iconBytes":[137,80,78,71,...]`. 8 icons animating at 10 fps make about
   75 outputs per second of about 150 KB each, about 25 MB/s of garbage in the
   widget. V8 lets it pile up to gigabytes and does not collect it once the
   page goes idle.
2. **Every provider output is logged.** `createBaseProvider` calls
   `logger.debug('Provider output:', output)`
   ([create-base-provider.ts L87](https://github.com/glzr-io/zebar/blob/5f90d341867122175cb4a57af594a44752885056/packages/client-api/src/providers/create-base-provider.ts#L87)),
   and `debug` is a plain `console.log`
   ([create-logger.ts L26-L28](https://github.com/glzr-io/zebar/blob/5f90d341867122175cb4a57af594a44752885056/packages/client-api/src/utils/create-logger.ts#L26-L28)).
   The console keeps the last 1000 logged outputs alive, which for systray is
   100-160 MB per widget that no GC can free. This is bounded, but applies to
   every provider.

Outputs are also sent to every webview, not only the subscribers
([main.rs L317](https://github.com/glzr-io/zebar/blob/5f90d341867122175cb4a57af594a44752885056/packages/desktop/src/main.rs#L317)),
so every widget window receives and parses the payload of 1.

## Evidence

Zebar 3.3.1, WebView2 155, Windows 11, only this widget running. "After GC"
is right after a garbage collection forced with `gc.mjs`.

| Run | JS heap | JS heap after GC | Renderer | Renderer after GC |
|---|---|---|---|---|
| idle | 11 MB | 4 MB | 43 MB | 43 MB |
| `tray.ps1 -DurationSeconds 20` | 710 MB | 161 MB | 1205 MB | 292 MB |
| `tray.ps1 -DurationSeconds 60` | 1186 MB | 96 MB | 1986 MB | 185 MB |
| 20 s, `console.log = () => {}` in the widget | 337 MB | 1.4 MB | 597 MB | 43 MB |

- Without a forced GC nothing is freed: after a 20 s run with `console.log`
  disabled, the heap stayed at 511 MB and the renderer at 880 MB through
  3 minutes of idling.
- A heap snapshot after the 60 s run holds exactly 1001 systray outputs: the
  current one plus 1000 retained by `DevTools console` global handles.
- The console keeps them without any debugger attached, too. In a 60 s run
  with Zebar started normally, the widget's count of outputs not yet freed
  (`alive`) fell back to 1007-1043 after each collection and never below.

## Reproduce and check

Requires PowerShell 7 and Node.js 22 or later.

1. Make the widget pack available to Zebar:

   ```powershell
   New-Item -ItemType SymbolicLink -Path "$HOME/.glzr/zebar/systray-memory-repro" -Target "$PWD/widget"
   ```

2. Start Zebar with a debugging port, then start widget `systray` of pack
   `systray-memory-repro` from Zebar's tray menu. Close other widgets to keep
   the numbers clean. Zebar started this way stays attached to the terminal
   and prints its log there.

   ```powershell
   Stop-Process -Name zebar -Force
   Start-Process 'C:\Program Files\glzr.io\Zebar\zebar.exe' -Environment @{
     WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS = '--remote-debugging-port=9222'
   }
   ```

3. In one terminal, print the widget's reports next to the renderer memory:

   ```powershell
   ./collector.ps1
   ```

4. In another, animate 8 tray icons for 60 s:

   ```powershell
   ./tray.ps1
   ```

   The renderer column of `collector.ps1` climbs by about 30 MB/s and stays up
   after `tray.ps1` ends. `alive` in the report counts the outputs not freed
   yet: it drops after each garbage collection, but never below about 1000.
   This needs no debugging port.

5. Force a garbage collection:

   ```powershell
   node gc.mjs
   ```

   The heap drops to about 100 MB, not to the idle 4 MB: that is the outputs
   held by the console. To see who holds them, open `edge://inspect`, inspect
   the widget, take a heap snapshot in the Memory tab and look at the
   retainers of any `iconBytes` array.

6. To confirm the console part, add `console.log = () => {};` right after the
   `import` in `widget/index.html`, restart Zebar and repeat. The heap now
   drops back to the idle size.

## Files

- `tray.ps1`: shows 8 WinForms `NotifyIcon`s and swaps their image every 100 ms.
- `widget/`: a widget pack whose only widget subscribes to `systray` and posts
  what it received: outputs, outputs not freed yet, image bytes and JS heap.
- `collector.ps1`: prints each widget report next to the memory of every Zebar
  renderer.
- `gc.mjs`: forces a garbage collection in the widget and prints its heap.

## Possible fixes

1. Send icon bytes only for icons the client has not seen. The client already
   caches icons by `iconHash`
   ([create-systray-provider.ts L39-L55](https://github.com/glzr-io/zebar/blob/5f90d341867122175cb4a57af594a44752885056/packages/client-api/src/providers/systray/create-systray-provider.ts#L39-L55)),
   and an animated icon cycles through a few hashes, so after the first cycle
   outputs would carry only ids and hashes. The cache would have to keep
   hashes missing from the latest output instead of revoking them (L130-L135).
   Base64 instead of a number array would cut the size by about 3x on its own.
2. Stop logging output objects in `createBaseProvider`, or log them only when
   debugging is on.
3. Emit provider outputs only to the webviews that subscribed to them.
