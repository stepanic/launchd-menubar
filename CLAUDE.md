# LaunchdBar — macOS menu-bar viewer za launchd jobove

Namjenski SwiftUI menu-bar (gore desno, `MenuBarExtra`) app koji prikazuje sve launchd
agente/daemone na ovom Macu, s fokusom na **vlastite custom jobove** korisnika (ms).
Cilj: na jednom mjestu vidjeti raspored, status i zadnji exit code svih cron-like jobova,
te ih moći pokrenuti/otvoriti plist/log.

## Okruženje (provjereno 2026-06-22)
- macOS 26 (Tahoe), Apple M4 Pro, 24 GB
- Swift 6.2.4, Xcode 26 (`/Applications/Xcode.app`)
- `xcodegen` instaliran na `/opt/homebrew/bin/xcodegen`
- Projekt se generira iz `project.yml` (xcodegen) — **`.xcodeproj` je u .gitignore**, ne commitati ga.
- Korisnik NEMA klasični crontab (`crontab -l` prazan) — sve ide kroz launchd.

## Korisnikovi custom jobovi (za "Only mine" filter)
Prefiksi labela koje treba tretirati kao "moje":
`ai.domovina`, `tv.domovina`, `com.domovina`, `com.italk`, `com.pediludium`,
`com.revenuecat`, `com.stepanic`, `homebrew.`
Konkretni (iz `launchctl list`): com.revenuecat.podcast.subclub/launched,
com.pediludium.matchsync/snapshot, ai.domovina.apple-secret-rotate,
tv.domovina.rag.sync / fetch.nightly, com.italk.nabava-watch / toptal-jobwatch,
com.stepanic.dotclaude-backup, com.domovina.ecosystem-brain.daily.

## Build / run
```bash
./build.sh            # xcodegen generate + xcodebuild Release + ispiše putanju .app
open build/Build/Products/Release/LaunchdBar.app
```

## Konvencije
- Swift language mode 5.0 (postavljeno u project.yml) — izbjegava strict concurrency gnjavažu.
- App je `LSUIElement` (bez dock ikone), samo menu-bar.
- Sav pristup launchd-u ide kroz `Shell.run(...)` wrapper (Process). Bez vanjskih dependencyja.
- Read-only prema sistemu osim eksplicitnih akcija (kickstart). Ništa destruktivno.

## Status
Vidi `HANDOFF.md` za potpunu spec i što je ostalo za napraviti.
