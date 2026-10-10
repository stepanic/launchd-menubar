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
./build.sh install    # + deploy u /Applications/LaunchdBar.app i kickstart launchd joba
open build/Build/Products/Release/LaunchdBar.app
```

**VAŽNO:** autostart (`~/Library/LaunchAgents/com.stepanic.LaunchdBar.plist`, label
`com.stepanic.LaunchdBar`) pokreće `/Applications/LaunchdBar.app`. Obični `./build.sh`
samo builda u repo `build/` — nakon reboota launchd digne staru `/Applications` kopiju.
Zato za trajni deploy uvijek koristi `./build.sh install` (prepiše `/Applications`,
re-registrira u LaunchServices da izbjegne `OS_REASON_CODESIGNING` na prvom spawnu,
pa kickstarta job).

**Drugi Mac (bez Xcodea/Homebrewa, npr. Intel MacBook s Command Line Tools):** `build.sh`
automatski pada na `swiftc` + ručno složen `.app` (`build/swiftc/LaunchdBar.app`), a
`install` kreira LaunchAgent plist ako ne postoji (RunAtLoad, KeepAlive samo na crash).

## Konvencije
- Swift language mode 5.0 (postavljeno u project.yml) — izbjegava strict concurrency gnjavažu.
- App je `LSUIElement` (bez dock ikone), samo menu-bar.
- Sav pristup launchd-u ide kroz `Shell.run(...)` wrapper (Process). Bez vanjskih dependencyja.
- Read-only prema sistemu osim eksplicitnih akcija (kickstart). Ništa destruktivno.

## Status
**GOTOVO (2026-06-22)** — app je funkcionalan i build-a clean (`./build.sh` → BUILD SUCCEEDED).
Implementirano svih 5 Swift fajlova:
- `Sources/Models.swift` — `LaunchdJob`, `ScheduleSpec` / `JobCategory` (strukturirani raspored + kategorizacija), `describeSchedule(_:)`, `LaunchdLoader.loadAll()` (merge `launchctl list` + plistovi iz 3 dira).
- `Sources/JobStore.swift` — `@MainActor ObservableObject`, auto-refresh 8 s, `sections` (grupiranje), `searchText`, `runNow/reveal/openLog`.
- `Sources/LaunchdBarApp.swift` — `MenuBarExtra` (`timer` ikona, `.window` stil).
- `Sources/MenuContentView.swift` — header (filter polje, Only mine toggle, refresh), lista grupirana u collapsible sekcije, footer (broj + failing + Quit).
- `build.sh` — xcodegen + xcodebuild Release.

Provjereno: lista prikazuje korisnikove jobove (domovina/italk/stepanic/…), schedule parsing radi
(npr. `com.stepanic.dotclaude-backup` → `at 03:30`). "Only mine" default ON.

## Grupiranje u UI-ju (2026-08-26)
S 24 joba ravna lista je bila nepregledna. `JobCategory` grupira po **tome kad job radi**:
Night (00:00–08:30) · Daytime · Pollers (interval/hourly) · Services (KeepAlive) · No schedule.
Unutar sekcije se sortira po vremenu paljenja, ne abecedno — timeline je ono što se skenira.
Pollers/Services/No schedule startaju collapsed (`@AppStorage("collapsedSections")`).

Podjela na Night/Daytime nije kozmetika: `nightWindowEndMinutes` = 08:30 je granica iz
`SCHEDULING.md`. Prazna "Daytime" sekcija = svi jobovi su u prozoru dok korisnik spava.

Visina liste više nije fiksna (`maxHeight: 480`) nego raste s sadržajem do
`visibleFrame.height - 160`. `MenuBarExtra(.window)` se sizea po sadržaju, pa bez tog
stropa zna nacrtati menu viši od ekrana.

## Raspored launchd jobova
Analiza i odluke o vremenima izvršavanja: **`SCHEDULING.md`**. Kratko: svi AI (Claude)
jobovi su pomaknuti u 00:10–01:00, a `tools/claude-window` je dijeljeni arbitar koji
svaki takav job pita smije li sada trošiti kvotu — fiksni cutoff po jobu ne radi jer
se iz sata ne vidi otvara li poziv nov 5h prozor ili ulazi u već otvoren.

`tools/claude-window` je jedini izvršni dio ovog repa izvan app-a; symlinkan je u
`~/.local/bin` i konzumiraju ga tri druga repa (fetch.domovina.tv, pipeline.domovina.ai,
ms-toptal-projects/tools/*, italk/javna-nabava). Testovi: `./tools/claude-window.test.sh`.

Preostale ideje (opcionalno) vidi u `HANDOFF.md`.
