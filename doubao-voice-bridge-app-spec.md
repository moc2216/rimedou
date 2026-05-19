# DoubaoVoiceBridge macOS App Spec

## Goal

Build a tiny local-only macOS background/menu bar app that lets the user keep their current input method, while using Doubao IME only for voice input.

The app replaces the current Hammerspoon script. It should not depend on Hammerspoon.

## Final Verified Behavior

Default state:

- The user's normal input method can be any input source.
- The system should return to the input source that was active before each voice session.
- Doubao should not remain the normal typing input method.

Trigger:

- Physical Right Command key is used as push-to-talk.
- On Right Command down:
  1. Record current typing input source in memory for this session.
  2. Switch input method to `豆包输入法`.
  3. Wait until the active input method is confirmed as Doubao.
  4. Perform an app focus bounce to force macOS InputMethodKit/AppKit to rebind the current text input context.
  5. Send Doubao's voice shortcut: left Option warmup tap, then hold left Option.
- On Right Command up:
  1. Release synthetic left Option.
  2. After about `0.20s`, restore the input source recorded on Right Command down.

Critical discovery:

- The second invocation fails if we only switch the input source and synthesize left Option.
- The working fix is to simulate the system-level "focus leaves and returns" behavior before pressing left Option.
- The successful non-mouse version is an app focus bounce:
  - Temporarily activate another app, e.g. the bridge app itself or Finder.
  - Reactivate the original app and focused window.
  - Then trigger Doubao voice.

This suggests the real issue is not keyboard delivery, Bluetooth, or input-source switching. It is that Doubao's voice module needs the current text input client to be rebound/activated after switching input methods.

## Current Constants

```text
TARGET_INPUT_SOURCE = "豆包输入法"

RIGHT_CMD_KEYCODE = 54
LEFT_OPTION_KEYCODE = 58 // kVK_Option

OPTION_PRESS_DELAY = 0.08
OPTION_WARMUP_TAP_DURATION = 0.05
OPTION_WARMUP_TO_HOLD_DELAY = 0.22
POST_SWITCH_SETTLE_DELAY = 1.20
SWITCH_WAIT_TIMEOUT = 2.00
SWITCH_POLL_INTERVAL = 0.05
RESTORE_IME_DELAY = 0.20

APP_FOCUS_BOUNCE_BACK_DELAY = 0.16
APP_FOCUS_BOUNCE_SETTLE_DELAY = 0.16
```

## Recommended App Shape

Name: `DoubaoVoiceBridge`

Type:

- Native Swift macOS app.
- Menu bar app or background-only app.
- No main window required.

Menu bar items:

- Enable / Disable
- Open Log
- Quit

Optional config file:

```json
{
  "launchAtLogin": true,
  "restoreDelay": 0.2,
  "postSwitchSettleDelay": 1.2,
  "focusBounceBackDelay": 0.16,
  "focusBounceSettleDelay": 0.16,
  "optionWarmupTapDuration": 0.05,
  "optionWarmupToHoldDelay": 0.22
}
```

Path suggestion:

```text
./config.json
~/Library/Logs/DoubaoVoiceBridge/app.log
```

## Required macOS Permissions

The app needs:

- Accessibility permission
- Input Monitoring permission

No paid Apple Developer account is required for local personal use. Xcode can build and run it locally with local/ad-hoc signing. Developer ID and notarization are only needed for smooth distribution to other users.

## Swift API Mapping

Global key monitoring:

- Use `CGEvent.tapCreate` for a global event tap.
- Listen for `.flagsChanged`.
- Detect physical Right Command by keycode `54` and right-command flags.
- Swallow Right Command events so the key does not leak into the active app.

Synthetic left Option:

- Use `CGEvent(keyboardEventSource:virtualKey:keyDown:)`.
- Post left Option down/up with `CGEvent.post(tap: .cghidEventTap)`.
- Use keycode `58` for left Option.

Input method switching:

- Use Text Input Source Services:
  - `TISCopyInputSourceForLanguage`
  - `TISCopyInputSourceProperty`
  - `TISSelectInputSource`
- Find input source by localized name or source id.
- Confirm active input method after switching by polling current source.

App focus bounce:

- Capture:
  - `NSWorkspace.shared.frontmostApplication`
  - focused window through Accessibility if needed.
- Temporarily activate a neutral app:
  - the bridge app itself, if it can activate briefly, or Finder.
- After `0.16s`, reactivate original app.
- If possible, refocus the original focused window via Accessibility.
- After another `0.16s`, proceed to left Option warmup/hold.

Logging:

- Log every state transition with timestamps.
- Include:
  - active input method before and after switch
  - whether focus bounce ran
  - option down/up events
  - restore events
  - frontmost app bundle id

## State Machine

States:

```text
idle
rightCmdDown
switchingToDoubao
waitingForDoubao
focusBouncing
warmingOption
holdingOption
restoringPreviousInputMethod
```

On Right Command down:

```text
idle
 -> rightCmdDown
 -> switchingToDoubao
 -> waitingForDoubao
 -> focusBouncing
 -> warmingOption
 -> holdingOption
```

On Right Command up:

```text
holdingOption
 -> release left Option
 -> restoringPreviousInputMethod after 0.20s
 -> idle
```

Important:

- Do not use "keep Doubao active while idle" as final behavior.
- The final desired behavior is to restore whichever input source was active before the voice session.
- Always run focus bounce after switching to Doubao before triggering left Option.

## Edge Cases

Ignore repeated Right Command flagsChanged events:

- Do not toggle internal state blindly.
- Read physical state from raw flags and compare with internal state.

Short press:

- If Right Command is released before the delayed Option trigger, cancel the pending Option press.

Already in Doubao:

- Record Doubao as the previous input source for that session.
- Releasing Right Command restores the recorded source, which is a no-op in this case.

Reload/relaunch:

- Do not infer or persist a default input source across launches.
- The app only restores a source recorded during the current in-memory key session.

## Verification Plan

Test 1: First invocation from a non-Doubao input method

1. Ensure current input method is a normal typing input source.
2. Hold Right Command.
3. App switches to Doubao.
4. App focus bounce runs.
5. Doubao voice starts.
6. Release Right Command.
7. App restores the original input source after `0.20s`.

Test 2: Second invocation

1. After Test 1, type normally in the restored input source.
2. Hold Right Command again.
3. App switches to Doubao again.
4. App focus bounce runs again.
5. Doubao voice starts again.
6. Release restores the second session's original input source.

Expected logs:

```text
right command down
record original input source: <previous input source>
switch to doubao input source: 豆包输入法
confirmed doubao input source
start app focus bounce
returned to original app/window
left option warmup down/up
left option formal hold down
right command up
left option release
restore previous input method: <previous input source>
```

## Notes From Debugging

Things that were ruled out:

- Bluetooth keyboard instability: synthetic Option and raw modifiers were consistently delivered.
- Simple input source switching: logs confirmed Doubao became active even when voice did not start.
- Keeping Doubao prearmed as idle input method: this made typing default to Doubao and still did not reliably start voice.
- Mouse click as the only solution: a real click can help, but the cleaner fix is app focus bounce.

Working hypothesis:

Doubao's voice feature depends on macOS text input context activation. Switching TIS input source updates the menu/input source, but does not always cause Doubao's IMK server to bind voice handling to the current text client. App focus bounce forces a detach/attach path similar to manual focus switching.
