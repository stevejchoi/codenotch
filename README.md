<div align="center">

# Codenotch

[![CI](https://github.com/vinzdg/codenotch/actions/workflows/ci.yml/badge.svg)](https://github.com/vinzdg/codenotch/actions/workflows/ci.yml)
![Platform](https://img.shields.io/badge/platform-macOS%2026%2B-black)
![Swift](https://img.shields.io/badge/swift-5-orange)
![License](https://img.shields.io/badge/license-MIT-green)

**A macOS app that pins a small black notch to a screen edge, showing how much
of each coding assistant's usage limit you have burned — and whether it is
still working, done, or waiting on you.**

![Collapsed notch with hover tooltip](docs/design/frame-124-hover-tooltip.png)

</div>

Hover a ring for its limit windows and when they reset. Claude's ring shows the
same **current session** window Claude Code's own `/usage` leads with, so the
two never disagree.

## Windows

A Windows port — Rust/Tauri 2, same design and providers — lives in [`windows/`](windows/README.md).

## What it reads

| Provider | Source | How |
|---|---|---|
| **Claude Code** | official | Claude Code's own `/usage`, asked of the installed `claude`. Falls back to the OAuth token in the login keychain, against the endpoint that command uses, when Claude Code isn't installed. |
| **Cursor** | official | The editor's signed-in session in its local SQLite state, or the `cursor-agent` login in the keychain — no separate sign-in. |
| **Codex** | official | ChatGPT's usage endpoint, using the local Codex sign-in. Shows the 5-hour and weekly limits when available. |
| **Antigravity** | official where licensed, otherwise a request count | Antigravity's local language server first, then Google's quota endpoint; a plain count when neither will answer for the account. |
| **GLM** | official | Z.ai's Coding Plan monitor endpoint, with a key borrowed from whichever coding tool already holds one — Claude Code's `settings.json`, ZCode, or OpenCode. |
| **Ollama** | local runtime | Its local `/api/ps` listing: loaded models, reported model memory and context capacity. Enable it in Settings → Accounts. |
| **Grok** | official | The Grok CLI session in `~/.grok/auth.json`, against the same credits billing endpoint `/usage` uses. |
| **OpenCode** | official | The Go plan's official usage endpoint, with the `opencode-go` key OpenCode itself stores on sign-in. |
| **GitHub Copilot** | official | GitHub's Copilot quota endpoint, authenticated with the GitHub CLI session already on the Mac (`gh auth login`). |

Codenotch never signs in anywhere. Cloud usage is borrowed from a credential
or session a tool on your Mac already holds — install and sign in to any of
them, and its ring appears. Switching a provider off in Settings stops its
usage polling and forgets the readings taken from it; it does
not sign you out of the tool that owns the account, and the row says so.

**Ollama monitoring is opt-in.** Switch **Monitor Ollama** on under
**Settings → Ollama**. It checks
`http://127.0.0.1:11434` every second; the address can be
changed to another HTTP port on this Mac. Each loaded model gets its own
cell showing its last measured generation speed, such as **30 tok/s**, or
**— tok/s** until measured. Qwen, Gemma, Llama (Meta), DeepSeek
and Mistral models get their brand icon automatically from the model name;
unrecognized or custom names use the Ollama llama icon. Hover for the model name,
last speed, speed band, measurement age, RAM, **Quantization** (such as `Q4_K_M`
or `Q8_0`) and **Context limit** in tokens;
this limit is not actual token consumption. A cell
disappears when its model unloads. Detected models also appear in **Connected**
while Settings is open. Drag a model between other providers to place its notch
cell; the order is remembered across launches. Switching a model off moves it
to **Not connected** and hides its cell while it stays loaded in Ollama.
Switching it back on appends it to the connected list. Unloaded models leave
both lists. The separate Ollama settings page keeps the server address and
the switch for all monitoring; Accounts contains the detected model rows.
Clicking a model animates only that cell while refreshing the shared inventory.
Background polls leave model icons still; newly detected models appear after
the models already shown, with their own entrance animation.
There is no quota percentage, and a loaded model does not produce a working indicator. Switching
monitoring off leaves Ollama running and removes the reading; model readings
are not saved across launches. Monitoring never initiates inference.


Enabling Ollama monitoring also starts the local relay. For speed measurements
and a live **Thinking** indicator, point your Ollama client at
`http://127.0.0.1:11435` while Codenotch is open. The backend stays on `11434`.
Settings → Ollama shows whether this connection is listening or unavailable,
whether it has received generation speed, and the Terminal command to use it.
Ordinary `ollama` commands using `11434` are detected but cannot supply speed
or thinking to Codenotch. Closing Codenotch also closes `11435`.
For example:

```sh
OLLAMA_HOST=http://127.0.0.1:11435 ollama run gemma4:e4b --think
```

The existing white arc spins only while that model emits streamed reasoning,
and stops when answer text starts or the request ends/cancels. Native Ollama
`/api/chat`, `/api/generate`, and OpenAI-compatible `/v1/chat/completions` streams
are observed. Direct backend requests and non-streaming responses cannot show
live thinking. Completed native `/api/chat` and `/api/generate` responses,
streamed or not, update speed from `eval_count / (eval_duration / 1e9)`.
This is the latest response's average generation speed, excluding model loading
and prompt processing; OpenAI-compatible responses lack the required timing.
The full outer ring is blue at ≥40 tok/s, green at 20–<40, yellow at 10–<20,
red below 10, and gray before measurement. These are display thresholds, not a
PC health rating. The white thinking arc remains independent of the speed color.

The relay keeps active request/model identifiers and timestamps, plus the latest
speed measurement per model (up to 128 models), only in memory. It does not save
prompts, reasoning, or replies. It binds to loopback only and
forwards requests to your configured local Ollama server (32 MiB request limit).
Disabling monitoring closes the relay's connections and clears activity
and speed measurements. Changing the backend or relaunching also clears them.

Settings lists the connected providers in the order the notch draws them, and
you can drag one by its handle to move it. The order is remembered across
launches. A provider you switch back on joins the end of that list rather than
reclaiming an older position, so nothing you cannot currently see jumps ahead
of something you placed deliberately.

It also answers **"is it still working?"** — a thin arc spins inside a
provider's ring while a session is busy, and becomes a pulsing amber ring when
one is blocked waiting on you. Hover for every live session by name, where it
is running, and what it wants.

Two Claude Code logins are two rings. Anyone who keeps a work account apart with
`CLAUDE_CONFIG_DIR=~/.claude-work claude` gets a **Claude (work)** ring beside the
personal one, with its own limits, its own sessions and its own row in Settings.
Any `~/.claude-<slug>` directory Claude Code has run against is found at launch;
the default `~/.claude` always comes first, the rest in alphabetical order, so the
rings never swap places.

## When a session ends

The notch opens itself for five seconds when an agent stops working, or stops
to ask you something, and sounds the system alert. Clicking it while it is open
brings that session's application to the front.

The app, not the tab. A session publishes its pid and nothing else — no window,
no tab, no tty — so the app is found by walking up the process tree from the
agent to whatever launched it. Choosing the *tab* inside that app needs the
terminal's own scripting interface, and there is no general one: Terminal.app
and iTerm2 can match a tab by tty, Warp and Ghostty publish no scripting
dictionary at all. So the app is raised for everybody and the tooltip names the
session, which leaves the last hop one keystroke rather than working for two
terminals and silently doing nothing in a third.

Both halves switch off separately in Settings, because they fail differently:
the peek is no use behind a full-screen window, and the sound is no use in a
meeting. Each of the two events — finished, and waiting on you — picks its own
sound there, with a preview button beside it.

The sound is played as a file on the ordinary output rather than handed to
`NSSound` as a system alert. A system alert goes through the interface
sound-effects channel, which System Settings → Sound can switch off — and on a
Mac where it is off, `NSSound.play()` reports success and nothing is heard.

Only *leaving* busy counts. A question being answered is not a piece of work
ending, and a session whose file disappears mid-turn — which is what quitting
Claude Code looks like — is not announced at all, since there is no window left
to jump to. Nothing is announced from the first reading either: every session
already running at launch arrives with no history, and treating that as a
transition would ring once per open window on every start.

## Alerts

A provider's headline limit crossing **80%** — and reaching **100%** —
becomes a system notification: once per crossing, never repeated while it
stays crossed, and again only after the window has genuinely rolled over.
Each provider can be muted from its own row in Settings, and macOS permission
is asked on the first real alert rather than at launch.

## Placement

The notch lives on any of the four screen edges. Right and left keep a
vertical column; top and bottom lay the readings out side by side. It pins
itself to the *usable* edge, so a bottom notch rests on the Dock and follows
when the Dock hides or moves. On a Mac with a hardware notch, the top
placement takes its exact shape, so the two read as one rather than as a bar
parked underneath it.

At rest it is a small pill on the screen edge that unfolds when the pointer
reaches it — configurable in Settings to always show, or to hide entirely.
Settings live in an orb below the notch: an arc at rest, a gear on hover.

In Settings → Appearance → Reset time, choose **Time remaining** for countdowns
like "Resets in 3 Days 3h". **Reset date** keeps the reset date and time, with
minutes shown when less than an hour remains.

Appearance also carries the ring's accent colour. The device accent is the
default; fixed presets are available for pink, red, orange, yellow, green,
teal, blue, indigo, purple and off-white.

The app itself can show a Dock icon, a menu bar icon, or neither.

## Updates

Codenotch updates itself. [Sparkle](https://sparkle-project.org) checks daily
and installs in the background without prompting; Settings says so and can
switch it off. Every update is EdDSA-signed, so nothing installs that wasn't
built and signed by the maintainer.

## Building

```sh
brew install xcodegen   # once
make run                # generate, build, launch a Debug build
make test               # unit tests
```

No signing identity is required for either. `make release` — which archives,
notarizes, and produces a signed auto-update feed — needs a Developer ID
certificate and an App Store Connect notary profile, and is only ever run by
the maintainer to cut an official release. See
[CONTRIBUTING.md](CONTRIBUTING.md). CI runs the same unit tests unsigned via
`make test-ci`.

Run with `CODENOTCH_DEMO=1` to see fixed sample data instead of live readings.

## Architecture

Every provider implements `UsageProvider` (`Sources/Providers/`) and declares
its own `Fidelity` — `.official`, `.derived`, or `.manual` — so the UI never
presents a guess as if a vendor had published it. `UsageStore`
(`Sources/Model/`) polls them on a timer, keeps the last good reading across
launches, and degrades every failure to a visible status rather than a
made-up percentage.

The notch itself works in one-dimensional **stack space** (`along`/`across`)
regardless of which screen edge it's on; `NotchPlacement` is the only place
that maps that back onto real screen coordinates. `NotchLayout` holds every
measurement, quoted from `docs/design/frame-124-hover-tooltip.png` so the
layout can be checked against the design frame directly.

- Design spec: [`docs/specs/2026-08-28-usage-notch-design.md`](docs/specs/2026-08-28-usage-notch-design.md)
- Implementation history: [`TASKS.md`](TASKS.md)

## The honest caveat

No vendor publishes a clean "your session limit is N% used" API for any of
these tools. Each adapter reads whatever the owning app itself reads from —
an internal endpoint, a local database, a language server's own RPC — and
those can change without notice. Every adapter's response shape is pinned by
tests, and every failure degrades to a visible status (`stale`, `needsAuth`,
`error`) rather than an invented number.

**Keychain:** Claude's readings do not use it where Claude Code is installed.
Claude Code files a *new* keychain item on every token rotation, and the new
item's access list does not carry this app, so an "Always Allow" granted
against the old one stops working about an hour later — asking `claude` itself
avoids the question entirely. Where the keychain is still the source (no
Claude Code on the machine, or Antigravity), the app is signed with a stable
Developer ID identity so a grant survives rebuilds, and the secret is read
only when the owning app has actually changed it — checked via the item's
modification date, which isn't behind the same access prompt as the
credential — so a valid grant does not mean a prompt on every poll.

**Rate limits:** Claude's endpoint returns 429 if polled too hard, with an
unhelpful `Retry-After: 0`. The back-off treats that as a floor-raiser only —
60s, doubling per consecutive 429, capped at 15 minutes — and the deadline is
persisted, so relaunching during a penalty waits instead of spending an
attempt on it. Polling drops to every 5 minutes when nothing is running, and
right-clicking the notch offers **Refresh now**.

**Logs:** the app has no window, so anything worth diagnosing goes to the
unified log.

```sh
/usr/bin/log stream --predicate 'subsystem == "com.vinz.codenotch"' --level debug
```

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

[MIT](LICENSE) © 2026 Vinz
