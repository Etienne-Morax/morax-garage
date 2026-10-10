# Morax Cockpit: Build Specification

**Target:** a native macOS application that acts as a single control surface for Mac maintenance, orchestrating existing CLI tools rather than reimplementing them.

**Audience:** an autonomous coding agent. Read this document fully before writing any code. Where this document says MUST, treat it as a hard constraint that overrides convenience.

**Status:** greenfield. No existing codebase.

---

## 0. Read this first: the three rules that govern everything

1. **Never delete with `rm`, `unlink`, or `FileManager.removeItem`.** Every removal goes through `FileManager.trashItem(at:resultingItemURL:)`. No exceptions, no "permanent delete" option, not even behind a confirmation dialog. If a file cannot be trashed, report it as skipped.
2. **No root, no privileged helper, no LaunchDaemon.** The app runs entirely in user space. Any operation requiring elevation is surfaced to the user as a copyable shell command with an explanation, never executed by the app. This is a deliberate security decision and is not open for reinterpretation.
3. **Never bundle third-party binaries.** The app detects tools already installed by the user via Homebrew. It does not ship, download, install, or update them. This is both a licensing requirement and a security requirement.

If a requirement elsewhere in this document appears to conflict with one of these three rules, the rule wins. Stop and flag the conflict rather than resolving it yourself.

---

## 1. Problem statement

The owner is a professional photographer, videographer and director of photography who also builds software. Their machine is a MacBook Pro M1 Max used for DaVinci Resolve colour work, Next.js development, and client data handling under UK GDPR.

Disk pressure comes from four places, in descending order of size:

1. DaVinci Resolve caches, optimised media, proxies and gallery stills
2. JavaScript and Rust build artefacts across project directories
3. Downloaded installer files (DMG, PKG) that accumulate for months
4. Application leftovers from uninstalled software

Existing tools each solve one slice. The user currently has four of them installed and must remember four different invocations. The cockpit unifies the entry point.

The machine was previously compromised by AMOS/Atomic Stealer via a trojanised installer. The user has since adopted a strict posture on privileged access. This history is why rule 2 above exists.

---

## 2. Scope

### In scope

- Detecting which supported tools are installed and at what version
- A live system dashboard (CPU, GPU, memory pressure, swap, disk, power draw, thermals)
- A first-party scanner and cleaner for Resolve caches, dev build artefacts, and installer files
- An embedded terminal pane for running the Mole CLI directly when the first-party scanner is insufficient
- An application inventory that hands off to Pearcleaner for uninstallation
- A read-only audit view of user-level launch agents
- A Homebrew outdated-package view
- A compact menu bar widget running as a separate process

### Explicitly out of scope

Do not build any of the following. Each is either a solved problem, a security liability, or both.

| Excluded | Reason |
|---|---|
| Malware scanning or signature matching | Objective-See tools and XProtect do this properly. A homemade signature scanner is security theatre. |
| Browser privacy or cookie clearing | Requires Full Disk Access for marginal benefit. |
| "Free RAM" / memory purging | Counterproductive on macOS. Free RAM is wasted RAM. |
| "Repair permissions" | Removed by Apple with SIP in El Capitan. Its presence in a tool is a signal of cargo-cult design. |
| System cache deletion under `/System`, `/Library`, `/usr` | Requires root. Rule 2 applies. |
| Duplicate file finding | Adequately served by dedicated tools; high false-positive risk. |
| Reimplementing a menu bar sensor suite | Stats already does this well under MIT. |
| Any telemetry, analytics, crash reporting, or network call other than Homebrew queries | Non-negotiable. |

---

## 3. Orchestrated tools

The app depends on these being installed by the user. It must degrade gracefully when they are absent.

| Tool | Install command | Role in cockpit | Licence | Integration method |
|---|---|---|---|---|
| macmon | `brew install vladkens/tap/macmon` | Live power, thermal, per-cluster CPU metrics | MIT | Subprocess, `macmon pipe` JSON stream |
| Mole (`mo`) | `brew install tw93/tap/mole` | Advanced cleanup beyond first-party scanner | GPL-3.0 | Embedded terminal only. Never parsed. |
| Pearcleaner | `brew install --cask pearcleaner` | App uninstallation | Apache 2.0 + Commons Clause | Deep link / CLI handoff |
| Homebrew | prerequisite | Package inventory | BSD-2 | Subprocess, `brew outdated --json` |
| Stats | `brew install --cask stats` | Not integrated. Detected and reported only. | MIT | None |

### Licensing constraints the agent MUST respect

- **Mole is GPL-3.0.** Invoking it as a separate process through its documented command line interface is aggregation, not derivation. Do not copy any Mole source code into this project. Do not bundle the `mo` binary inside the `.app`. Do not parse its output into a structured model that effectively reimplements its logic. The only permitted integration is spawning it inside an embedded terminal where the user sees the raw output.
- **Pearcleaner is Apache 2.0 with Commons Clause.** Source-available, not OSI open source, and may not be sold. Handoff by URL scheme or CLI invocation only. Do not vendor its code.
- **The cockpit's own licence** should be chosen by the owner. If the owner intends to distribute or sell it, no GPL code may be included, which the above constraints already guarantee.

---

## 4. Non-negotiable safety model

### Deletion

- All removals via `FileManager.trashItem`. Rule 1.
- Every scan is dry-run by default. The user must explicitly select items and confirm before anything moves.
- A hardcoded protected-path denylist, checked before every operation:
  - `/System`, `/usr`, `/bin`, `/sbin`, `/private/var/db`, `/Library/Apple`
  - The user's home directory root itself
  - `~/Library/Keychains`, `~/Library/Application Support/MobileSync`
  - Any path resolving outside the scan root after symlink resolution
- Symlinks MUST be re-resolved immediately before the trash call, not at scan time, to prevent time-of-check-to-time-of-use substitution.
- Firmlink canonicalisation: resolve `/var` to `/private/var`, `/tmp` to `/private/tmp`, `/etc` to `/private/etc` before any comparison against the denylist.
- Hard cap of 10,000 items per single operation. Above that, require the user to narrow the selection.

### Logging

- Every operation writes to `~/Library/Logs/MoraxCockpit/operations.log` with timestamp, absolute path, action, and outcome.
- The log is viewable in-app with an errors-only filter and copy-to-clipboard.
- Logs auto-prune after 90 days.

### Permissions

- Request no permissions at launch.
- Request folder access lazily, only when the user initiates a scan of a location that needs it.
- If Full Disk Access is needed for a feature, explain what it unlocks and let the user decline without breaking the rest of the app.
- Do not attempt to inherit or piggyback on another application's TCC grants.

### Network

The app makes no network requests except:
- `brew outdated --json` (Homebrew's own network activity, invoked as a subprocess)

No update checks, no version pings, no crash reporting. If an update mechanism is later wanted, it goes through Homebrew cask, not in-app.

---

## 5. Architecture

Platform target: macOS 14 (Sonoma) or later. Apple Silicon primary, Intel best-effort.

Language: Swift 6 with strict concurrency. UI in SwiftUI, dropping to AppKit where SwiftUI is insufficient (menu bar, terminal hosting).

```
MoraxCockpit/
├── MoraxCockpit/            Main app target
│   ├── App/                 Entry point, app state, root navigation
│   ├── Core/
│   │   ├── ToolRegistry     Discovery and version detection of external tools
│   │   ├── ProcessRunner    NSTask wrapper: streaming stdout/stderr, cancellation
│   │   ├── SafetyGate       Denylist, canonicalisation, TOCTOU guard, item caps
│   │   ├── TrashService     The single chokepoint for all deletions
│   │   ├── OperationLog     Append-only log writer and reader
│   │   └── Scanners/
│   │       ├── ResolveScanner
│   │       ├── DevArtefactScanner
│   │       └── InstallerScanner
│   ├── Features/
│   │   ├── Environment/     Tool detection status screen
│   │   ├── Dashboard/       Live metrics
│   │   ├── Cleanup/         Scan results, selection, confirmation, results
│   │   ├── Terminal/        Embedded shell for Mole
│   │   ├── Apps/            Inventory plus Pearcleaner handoff
│   │   ├── Brew/            Outdated packages
│   │   └── Audit/           Read-only launch agent listing
│   └── Resources/
├── MoraxCockpitKit/         Shared models, constants, protocols
├── MoraxCockpitMenu/        Menu bar widget, separate process
└── Tests/
```

### Why a separate menu bar process

The menu bar widget must survive the main window being closed and must not carry the main app's memory footprint. Follow the pattern used by Stats: an independent executable launched at login, communicating with the main app only by launching it.

---

## 6. Component specifications

### 6.1 ToolRegistry

Discovers external tools. Runs on launch and on demand.

For each tool, resolve in this order and stop at the first hit:
1. Homebrew prefix binary path (`$(brew --prefix)/bin/<tool>`)
2. `/opt/homebrew/bin/<tool>` and `/usr/local/bin/<tool>`
3. `/Applications/<Name>.app` for cask apps

Do not rely on the inherited `PATH`. A GUI app launched from Finder has a minimal `PATH` that will not include Homebrew.

Output model per tool: `identifier`, `displayName`, `isInstalled`, `resolvedPath`, `version`, `installCommand`.

Version detection: `macmon --version`, `mo --version`, `brew --version`, and `CFBundleShortVersionString` from the app bundle for casks.

### 6.2 ProcessRunner

A single async wrapper over `Process` and `Pipe`.

Requirements:
- Streams stdout and stderr line by line as an `AsyncStream`, never buffering an entire run in memory
- Honours `Task.isCancelled` and terminates the child process on cancellation
- All arguments passed as an array, never as a concatenated shell string. **No `sh -c`. No string interpolation of user-supplied paths into commands.** This closes command injection.
- Configurable timeout with a sensible default of 120 seconds
- Returns exit status alongside collected output

### 6.3 Dashboard

Primary source: `macmon pipe`, a long-lived subprocess emitting JSON.

Verify the exact schema of `macmon pipe` at build time by running it and inspecting the output. Do not assume field names from this document. Documented capability includes CPU, GPU and ANE power draw, per-cluster CPU utilisation, RAM and swap, and average CPU and GPU temperature.

Supplement with native APIs where macmon does not cover:
- Disk capacity per volume via `URLResourceKey.volumeAvailableCapacityForImportantUsageKey`
- Uptime via `ProcessInfo.processInfo.systemUptime`
- Battery health and cycle count via IOKit power sources
- Attached external volumes and displays

Display requirements:
- Rolling 60-minute in-memory history, no persistence
- Swap usage must be visually prominent. For this user, sustained swap during a Resolve export is the single most actionable signal.
- Update interval configurable, default 2 seconds
- If macmon is not installed, the dashboard still works using native APIs alone, with power and thermal panels showing an install prompt

### 6.4 Cleanup scanners

Three first-party scanners. Each returns a tree of candidate items with absolute path, size, last-modified date, and a category tag. Sizes are computed by walking directories recursively, not by stat on the directory node.

**ResolveScanner**

The highest-value scanner and the main reason this project exists. Targets:
- `CacheClip` directories (render cache) under the user-configured Resolve cache location
- Optimised media directories
- Proxy media directories
- Gallery stills
- `~/Library/Application Support/Blackmagic Design/DaVinci Resolve/` logs and crash reports

Critical safety requirement: **project databases, project backups, and `.drp` exports MUST never appear as candidates.** Losing a Resolve project database is catastrophic and unrecoverable from Trash if the user empties it. Add these paths to the denylist explicitly and write a test asserting they are never returned.

The Resolve cache location is user-configurable inside Resolve itself and often points at an external scratch disk. Do not hardcode a path. Read it from Resolve's preferences if reliably possible, otherwise ask the user to select the directory once and persist that choice.

**DevArtefactScanner**

Targets, scanned under user-configured project roots:
- `node_modules`
- `.next`, `dist`, `build`
- `target` (Rust)
- `.venv`, `venv`, `__pycache__`
- `DerivedData` under `~/Library/Developer/Xcode/`

Safety behaviour: any project directory modified within the last 7 days is flagged as recent and deselected by default. This mirrors Mole's approach and exists because deleting `node_modules` on an active project costs a reinstall.

Project roots default to `~/Projects`, `~/GitHub`, `~/dev` and are user-editable.

**InstallerScanner**

Targets `.dmg`, `.pkg`, `.zip` archives over 50 MB in `~/Downloads` and `~/Desktop`, plus the Homebrew downloads cache. Label each result with its source directory and age.

### 6.5 Cleanup flow

Fixed sequence, no shortcuts:

1. User picks a scanner and scope
2. Scan runs with visible progress and a working cancel button
3. Results shown grouped by category, with size totals, everything **deselected by default**
4. User selects items. A running total of reclaimable bytes updates live.
5. Confirmation sheet listing counts and total size, requiring an explicit action
6. Items moved to Trash in chunks of 5,000, checking cancellation between chunks
7. Completion screen with actual bytes reclaimed (recomputed, not estimated), skipped items, and errors, plus a button to open the operation log

There must be no "one-click smart clean" that performs deletion without passing through steps 3 to 5.

### 6.6 Embedded terminal

Host a real terminal emulator to run `mo` and other commands. SwiftTerm (BSD licence) is the recommended dependency.

- Launch the user's login shell so their environment and `PATH` are correct
- Provide quick-launch buttons that **type a command into the terminal without executing it**, leaving the user to press Return: `mo clean --dry-run`, `mo purge --dry-run`, `mo installer --dry-run`, `mo status`
- Never auto-execute a destructive command on the user's behalf
- If `mo` is not installed, show the install command instead of the buttons

This pane is how the cockpit gets Mole's full capability without parsing its output and without any licence entanglement.

### 6.7 Apps inventory

List applications from `/Applications` and `~/Applications` with bundle identifier, version, size on disk, and last-used date where obtainable.

Per app, offer:
- "Reveal in Finder"
- "Uninstall with Pearcleaner", which hands off to Pearcleaner

Verify Pearcleaner's current handoff mechanism against its own documentation before implementing. It documents CLI support and deep link automation, but the exact URL scheme must be confirmed at build time rather than guessed. If handoff cannot be made to work reliably, fall back to revealing the app in Finder with an instruction to drag it onto Pearcleaner.

**The cockpit MUST NOT implement its own app uninstaller.** That is Pearcleaner's job and duplicating it doubles the deletion risk surface for no gain.

### 6.8 Brew view

Run `brew outdated --json=v2` and present installed formulae and casks with available updates.

Offer a "copy upgrade command" button. **Do not execute `brew upgrade` from the app.** Upgrades can be long-running, interactive, and occasionally destructive to a working environment. This is a decision the user makes in their own terminal.

### 6.9 Audit view

Read-only. Lists user-level persistence points:
- `~/Library/LaunchAgents`
- `/Library/LaunchAgents` (readable without root)
- `/Library/LaunchDaemons` (readable without root)
- `~/Library/Application Support/*/`, login items via `SMAppService` where available

For each entry show the label, the program path, and whether the referenced binary still exists (orphaned entries are a useful signal).

**No enable, disable, or delete actions in v1.** This view exists so the user can spot something unexpected and investigate it deliberately. Given the machine's prior compromise, a read-only lens is more valuable and far safer than a toggle.

### 6.10 Menu bar widget

Separate process, launched at login if the user opts in.

Content: compact CPU, memory pressure, disk free, and swap. Click opens the main app.

No recommendations engine, no dismissible tips, no background notifications in v1. Keep it a readout.

---

## 7. Design direction

Visual identity should follow the owner's existing design system, not generic SaaS defaults.

| Token | Value |
|---|---|
| Ink black | `#0A0A0A` |
| Warm off-white | `#F5F1EA` |
| Oxblood accent | `#C8463A` |

Direction notes:
- Editorial and restrained. Dense information, generous spacing, no gradients, no glassmorphism, no rounded-everything.
- Oxblood is reserved for destructive actions and critical thresholds only. It must never be used as a general accent, or it stops carrying meaning.
- Numbers are the interface. Typography should be chosen so figures are legible at a glance, with tabular figures for anything that updates live so values do not jitter.
- Respect system light and dark appearance. The palette above defines the character, not a fixed pair of backgrounds.

---

## 8. Build phases and acceptance criteria

Each phase ends with a working, runnable app. Do not begin a phase before the previous phase's criteria pass.

### Phase 1: Foundation (3 to 4 days)

Deliver: Xcode project, `ToolRegistry`, `ProcessRunner`, `SafetyGate`, `TrashService`, `OperationLog`, and the Environment screen.

Acceptance:
- Environment screen correctly reports installed and missing tools with versions on a machine where some are absent
- `ProcessRunner` streams output from a long-running command and terminates it cleanly on cancel
- `SafetyGate` unit tests pass, including symlink escape, firmlink canonicalisation, denylist hits, and item cap
- `TrashService` moves a fixture file to Trash and the file is recoverable

### Phase 2: Dashboard (3 to 5 days)

Acceptance:
- Live metrics update without measurable UI stutter
- Dashboard degrades correctly with macmon absent
- Running a sustained load produces a visible, correct swap and power curve
- No memory growth over a 30-minute continuous run

### Phase 3: Cleanup (5 to 7 days, the highest-risk phase)

Acceptance:
- All three scanners return correct results against a synthetic fixture tree
- **Zero false positives across a 200-item adversarial fixture**, including symlinks pointing outside the scan root, paths with spaces, unicode and newline characters, and files the process cannot read
- Resolve project databases and backups are never returned. Dedicated test.
- Cancellation mid-scan and mid-clean leaves the filesystem in a consistent state
- The reported reclaimed byte total matches the actual delta in free space within a reasonable tolerance
- Every operation appears in the log with its full path

### Phase 4: Terminal, Apps, Brew, Audit (4 to 5 days)

Acceptance:
- `mo` runs correctly in the embedded terminal with the user's real environment
- Quick-launch buttons type commands without executing them
- Pearcleaner handoff works, or the documented fallback is in place
- Audit view lists agents and correctly flags orphaned entries

### Phase 5: Menu bar, packaging, polish (3 to 4 days)

Acceptance:
- Menu bar process survives main window closure and quits cleanly
- App is signed with Developer ID and notarised
- An uninstall script is shipped that removes the app, its preferences, its logs, and its login item
- Full pass on light and dark appearance

**Realistic total: 20 to 25 working days.**

---

## 9. Testing requirements

- Target 100 percent coverage on `SafetyGate` and `TrashService`. These two files decide whether the user loses data.
- All filesystem tests run against temporary fixture directories. **No test may ever touch the real home directory.** Provide `withTempHome`, `withFakeApp`, `withFakeProject` helpers.
- Adversarial test cases for `SafetyGate` are mandatory, not optional: symlink traversal, `..` escape, null bytes in paths, firmlink aliases, SIP-protected targets, denylist members, and idempotence of repeated calls.
- Scanner tests assert both what is returned and what is not returned. The negative assertions matter more.

---

## 10. Open decisions for the owner

The agent must not resolve these unilaterally. Ask before proceeding past Phase 1.

1. **Apple Developer account.** Résolu le 2026-10-08 : compte individuel Apple Developer Program payant actif (Team ID : NU43RNA6U9). Notarisation Phase 5 débloquée, builds de développement valables 1 an, aucune limite de 3 apps.
2. **Personal tool or Morax product?** If it will be distributed or sold, the licensing constraints in section 3 become structural and some design choices change.
3. **Resolve cache location.** Where does Resolve write its cache on this machine, and is it on an external volume? This determines whether the scanner needs external volume handling from day one.
4. **Project roots.** Confirm the actual directories to scan for dev artefacts.
5. **Licence for the cockpit itself.**

---

## 11. Things a well-meaning agent might do wrong

Listed because each is a plausible mistake that would be a serious regression.

- Adding a "permanent delete" or "secure shred" option because it seems more thorough. It is not. Rule 1.
- Adding a privileged helper to unlock system cache cleaning. Rule 2. The features it unlocks are not worth it and the owner has explicitly rejected this design.
- Parsing `mo` output to build a native cleanup UI. Fragile against every upstream release and a licence grey area. Use the terminal pane.
- Bundling `mo` or `macmon` inside the `.app` for user convenience. Licensing and security violation. Rule 3.
- Building an app uninstaller because Pearcleaner handoff proved awkward. Fall back to Finder reveal instead.
- Adding a malware scanner because the app is "about Mac health". Out of scope, section 2.
- Preselecting scan results to make the flow feel faster. Everything is deselected by default, always.
- Adding an in-app auto-updater. Distribution goes through Homebrew cask.
- Using `sh -c` with an interpolated path anywhere. Command injection.
- Assuming the inherited `PATH` contains Homebrew. It does not for a Finder-launched app.
- Assuming any tool's CLI flags or output schema match this document without verifying against the installed version first. This document was written from public documentation and versions move.
