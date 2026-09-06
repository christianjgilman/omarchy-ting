# Ting

Ting is the chief personal assistant layer for this Omarchy machine: an always-on
pearl orb that listens on a hotkey, answers instantly in her own cloned voice,
and routes organized work to zcode sessions.

## Install

```
omarchy plugin add https://github.com/christianjgilman/omarchy-ting.git --enable
```

Then place the orb: `omarchy bar put champion.ting --section right`.

## Hotkeys

| Key | Action |
|---|---|
| Alt+` | Talk to Ting (toggle). Press again mid-reply to barge in. |
| Super+Shift+BackSpace | Panic: silence her instantly. |

These live in `~/.config/hypr/bindings.lua` and call the IPC target `ting`.

## How it works

- Ears: local STT at `http://127.0.0.1:8765/v1/audio/transcriptions` (dictationd).
- Voice: local LuxTTS at `http://127.0.0.1:5059/v1/audio/speech`, default voice `ting`
  (placeholder ref until the Voice-Atelier refinement lands; drop a new
  `refs/ting/reference.wav` to swap it).
- Brain: one non-thinking chat call (Groq by default, any OpenAI-compatible
  provider) that returns a spoken acknowledgment plus a routing decision in a
  single JSON object. With no API key configured she runs a mock brain so the
  whole pipeline is testable.
- Delegation: tasks go into a ledger and then to a zcode harness session
  (browser transport when live, desktop injection fallback).
- Updates: silent while work runs; one short spoken line when a tracked task
  finishes (configurable).

## Control

```
tingctl toggle | mute | panic | status
tingctl say "text"          # speak arbitrary text in her voice
tingctl route "fix the wifi script in omarchy-setup"
tingctl record-test 2       # record 2s from the mic and run the full loop
omarchy-shell -q ting toggle|mute|panic|say
```

Config lives in `~/.config/ting/config.json` (0600). The orb's right-click menu
edits everything: voice, provider, model, key, update cadence.

State: `$XDG_RUNTIME_DIR/ting/state.json` · Latency log: `~/.local/state/omarchy/ting/latency.csv`
