# HANDOFF — dovrši LaunchdBar (macOS menu-bar launchd viewer)

> Pokreni `claude` iz `/Users/ms/git/stepanic/launchd-menubar` i zalijepi prompt ispod
> (sve od "PROMPT START" do "PROMPT END"). Pročitaj prvo `CLAUDE.md` u repou — ima okruženje i konvencije.

---

## PROMPT START

Dovrši macOS menu-bar app **LaunchdBar** u ovom repou. Pročitaj `CLAUDE.md` za okruženje
(Swift 6.2, Xcode 26, xcodegen na `/opt/homebrew/bin/xcodegen`, korisnikovi job-prefiksi).

Već postoji:
- `project.yml` — xcodegen konfiguracija (app target, LSUIElement, language mode 5).
- `Sources/Shell.swift` — `Shell.run(launchPath, args) -> (out, code)` wrapper oko Process.

Napravi preostalo i build-aj dok ne radi. Spec:

### Funkcionalnost
Menu-bar app (`MenuBarExtra`, ikona `timer`, `.menuBarExtraStyle(.window)`) koji u dropdownu:
1. Listа sve launchd jobove spojene iz dva izvora:
   - **Runtime:** `launchctl list` → kolone PID / Status(last exit) / Label. `-` PID = ne radi.
   - **Plistovi:** prošetaj `~/Library/LaunchAgents`, `/Library/LaunchAgents`, `/Library/LaunchDaemons`;
     parsiraj svaki `.plist` (`PropertyListSerialization`). Mergaj po `Label`. Preskoči nečitljive.
2. Za svaki job prikaži: status-točkicu (zelena=running, crvena=last exit≠0, siva=idle),
   `Label`, **raspored** (parsiran iz plista), i status-text (`running · pid N` / `idle · last exit C`).
3. Toggle **"Only mine"** (default ON) — filtrira po prefiksima iz CLAUDE.md. "Mine" jobovi idu prvi.
4. Po jobu akcije (gumbići desno ili context menu):
   - **Run now:** `launchctl kickstart -k gui/<uid>/<label>` (uid = `getuid()`), pa reload.
   - **Reveal plist:** `NSWorkspace.shared.activateFileViewerSelecting([url])`.
   - **Open log:** otvori `StandardOutPath` (fallback `StandardErrorPath`) ako postoji.
5. Header: naslov + "Only mine" toggle + refresh gumb + "updated HH:MM:ss".
6. Footer: broj jobova + **Quit** gumb.
7. Auto-refresh svakih ~8 s (Timer) + ručni refresh. Širina prozora ~400, max visina liste ~420 (ScrollView).

### Parsiranje rasporeda (iz plist dicta) → kratki string
- `StartInterval` (Int sekunde) → `every 1h` / `every 30m` / `every 45s` (formatiraj h/m/s).
- `StartCalendarInterval` (dict ili array dictova) → `at HH:MM` (+ weekday ime ako `Weekday`, + `day N` ako `Day`).
- `RunAtLoad == true` → `at load`. `WatchPaths` → `on change`. `KeepAlive` (Bool true ili dict) → `keepalive`.
- Spoji nepraznе dijelove s ` · `. Ako ničega → `manual`.

### Model (`Sources/Models.swift`)
`struct LaunchdJob: Identifiable, Hashable` s poljima: `label` (id), `pid: Int?`,
`lastExitStatus: Int?`, `plistPath: String?`, `schedule: String = "manual"`,
`stdoutPath/stderrPath/program: String?`. Computed: `isMine` (prefix match),
`isRunning` (pid != nil), `statusText`. Memberwise init s defaultima (`LaunchdJob(label:)` mora raditi).
Ovdje stavi i slobodne funkcije `describeSchedule(_:)`, helpere za interval/calendar/weekday.
Stavi `LaunchdLoader.loadAll() -> [LaunchdJob]` (static) koji radi merge gore opisan.

### Store (`Sources/JobStore.swift`)
`@MainActor final class JobStore: ObservableObject` s `@Published jobs`, `showOnlyMine`,
`lastUpdated`, `isLoading`. `visibleJobs` (filter + sort: mine prvo, pa label). `reload()` radi
`LaunchdLoader.loadAll()` na `Task.detached` pa assign na MainActor. Metode `runNow/reveal/openLog`.
Timer 8 s u `init`. Import AppKit za NSWorkspace.

### App + View
- `Sources/LaunchdBarApp.swift`: `@main struct LaunchdBarApp: App` s `@StateObject store`,
  `MenuBarExtra { MenuContentView(store: store) } label: { Image(systemName: "timer") }.menuBarExtraStyle(.window)`.
- `Sources/MenuContentView.swift`: glavni view + `JobRow` subview (status dot, tekst, akcijski gumbi).

### Build (`build.sh`, chmod +x)
```bash
#!/bin/bash
set -e
cd "$(dirname "$0")"
/opt/homebrew/bin/xcodegen generate
xcodebuild -project LaunchdBar.xcodeproj -scheme LaunchdBar -configuration Release \
  -derivedDataPath build build CODE_SIGNING_ALLOWED=NO | tail -5
echo "Built: build/Build/Products/Release/LaunchdBar.app"
```
Pokreni `./build.sh`, popravi greške dok build ne prođe, pa `open build/Build/Products/Release/LaunchdBar.app`
i potvrdi da se ikona pojavi u menu baru i da lista prikazuje korisnikove jobove (domovina/italk/…).

### Po završetku
- `git add -A && git commit` (poruka po konvenciji iz globalnog CLAUDE.md; završi s Co-Authored-By linijom).
- Ažuriraj `CLAUDE.md` "Status" sekciju i ovaj `HANDOFF.md` (označi što je gotovo).
- Ne commitati `LaunchdBar.xcodeproj/` ni `build/` (već u `.gitignore`).

## PROMPT END

---

## Što je već u repou
- `project.yml`, `Sources/Shell.swift`, `CLAUDE.md`, `.gitignore`, ovaj `HANDOFF.md`.

## Ideje za kasnije (opcionalno)
- Enable/disable job (`launchctl bootout`/`bootstrap`) — oprez, mijenja sistem.
- Prikaz zadnjih N linija loga inline.
- Badge u menu-baru ako neki "mine" job ima last exit ≠ 0.
- Search/filter polje.
