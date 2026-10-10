# Contributing to Morax Garage

Thanks for helping out. Bug reports, fixes and focused features are welcome.

## Setup

Requirements: macOS 14+, Xcode 16 (Swift 6).

```bash
git clone https://github.com/Etienne-Morax/morax-garage.git
cd morax-garage
swift build
swift test
```

Use `scripts/build_app.sh` to produce runnable `.app` bundles in `dist/`, and `scripts/install.sh` to install them into `/Applications`.

## Project layout

- `Sources/MoraxCockpitKit`: shared engine (metrics, scanners, `SafetyGate`, services). Most logic and tests live here.
- `Sources/MoraxCockpit`: main SwiftUI app.
- `Sources/MoraxCockpitMenu`: menu bar helper.
- `Tests/`: unit tests. `docs/architecture/`: design notes.

## Workflow

1. Open an issue first for anything larger than a small fix.
2. Fork, then branch from `main` (`feat/...`, `fix/...`, `docs/...`).
3. Keep changes focused. Add or update tests: new behaviour needs a test that fails without it, and a bug fix needs a regression test.
4. Make sure `swift build -c release` and `swift test` pass locally.
5. Open a pull request against `main` and fill in the template. CI must be green before merge. PRs are squash-merged.

## Commit messages

[Conventional Commits](https://www.conventionalcommits.org/): `<type>: <description>` with type one of `feat`, `fix`, `refactor`, `docs`, `test`, `chore`, `perf`, `ci`. Write in English, imperative mood.

## Safety-critical code

Anything that deletes or moves user files must go through `SafetyGate` and the Trash staging service. Changes to `SafetyGate`, the scanners' risk tiers or the denylist need tests covering the new rule, and a note in the PR on what could be lost if the rule is wrong.

## Code style

Swift 6 strict concurrency, immutable values by default, small focused files, no force-unwraps on external input, no hardcoded secrets (use the Keychain). Code and comments in English.

By contributing you agree that your work is released under the [MIT license](LICENSE) and that you follow the [Code of Conduct](CODE_OF_CONDUCT.md).
