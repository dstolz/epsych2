# gui.components.ScreenCapture

A camera button for a behavior GUI: one click puts a picture of the whole
window on the system clipboard, ready to paste into an electronic lab
notebook, a slide, or a message to whoever is asking what the rig is doing.

Source: `obj/+gui/@ScreenCapture/`

## What it does

- **Captures the entire figure**, controls and plots alike, at the window's
  own pixel size. Nothing is written to disk that outlives the click.
- **Copies to the system clipboard** — no file dialog, no folder to choose,
  no screenshot to find later.
- **Confirms the copy**: the camera swaps for a green check for `FlashDuration`
  seconds and the tooltip says what happened. The clipboard gives no feedback
  of its own, so without this a click looks like nothing happened.
- **Never throws.** A failed capture is logged (`vprintf(0,1,ME)`) and flashes
  a red error glyph with the reason in the tooltip; a screenshot must not take
  a running experiment's GUI down with it.
- **Works offscreen.** `exportapp` renders the window itself rather than
  grabbing the screen, so an obscured, minimized, or partly offscreen window
  still copies correctly — and so does an invisible one, which is what makes
  the component testable headlessly.

## Usage

```matlab
% In a gui.BehaviorGUI subclass — registered for teardown:
obj.addScreenCapture(row);                        % icon-only button
obj.addScreenCapture(row, Text='Screenshot');     % labeled

% Standalone, in any container:
sc = gui.components.ScreenCapture(fig, Tooltip='Copy this window');
sc.copyToClipboard();                             % also callable from code
```

| Option | Default | Meaning |
|--------|---------|---------|
| `Target` | the button's own figure | Figure to capture. Point it at another window to make one GUI copy another. |
| `Text` | `''` | Button label; empty gives an icon-only button. |
| `Tooltip` | `'Copy this window to the clipboard'` | Hover text, restored after each confirmation flash. |
| `FontSize` | `12` | Label font size. |
| `FlashDuration` | `1.5` | Seconds the confirmation glyph stays up. |

`copyToClipboard` returns `true` on success, so a paradigm can capture on a
schedule (say, at the end of every block) and log whether it worked.

## Why it is built this way

- **`exportapp`, not `print` or `copygraphics`.** It is the only capture that
  includes UI components; the other two render the axes alone, which is not
  what an operator means by a picture of the window.
- **A temporary PNG in the middle.** `exportapp` only writes files and .NET
  only reads images, so the file in `tempdir` is the handoff between the two
  halves. It is deleted by an `onCleanup` on every path, including failure.
- **.NET for the clipboard.** MATLAB's own `clipboard()` is text-only.
  `System.Windows.Forms.Clipboard.SetImage` copies the pixels, so the
  `System.Drawing.Bitmap` — which holds the PNG open — is disposed as soon as
  it returns, and must be before the temp file can be deleted.
- **Windows-only for the full window.** That is the .NET step. Elsewhere the
  button falls back to `copygraphics(ContentType='image')`, which copies the
  plots without the controls, and logs which of the two happened. This is the
  same split `stimgen.calibration.CalibrationGui` makes for its **Copy Window
  to Clipboard** menu item.
- **The glyph comes from `gui.toolbarIcon("camera")`.** `uibutton`'s `Icon`
  accepts only four built-in names — `success`, `error`, `warning`, `info` —
  so anything else has to be drawn as a truecolor array or shipped as an image
  file, and this toolbox ships no image files. The confirmation flash is the
  one place the built-in names are used.
- **The timer is stopped in the destructor** before the button is deleted, or
  a pending restore would fire at a dead handle.

## Validation

`tmp/smoke_test_screen_capture.m` (headless;
`matlab -batch "run('tmp/smoke_test_screen_capture.m')"`) — asserts the glyph
reaches the `Icon` property, that a click leaves a bitmap of the window's size
on the clipboard, that the confirmation appears and is restored, that a missing
target returns `false` instead of throwing, and that `gui.BehaviorGUI` teardown
takes the component and its timer along.

## See also

- [gui_BehaviorGUI.md](gui_BehaviorGUI.md) — `addScreenCapture` and the other
  component helpers
- `obj/+gui/toolbarIcon.m` — where the camera glyph is drawn
