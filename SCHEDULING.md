# Raspored launchd jobova — analiza i reshuffle (2026-08-26)

Zapis odluke: **zašto** su jobovi pomaknuti, ne samo **kamo**. Ako ikad budeš vraćao
neki job u jutarnji termin, pročitaj §2 prvo — postoji razlog zašto je 08:13 bio loš.

## 1. Cilj

Mac mini radi 24/7, korisnik za njim nije od **00:00 do 08:30**. Dva zahtjeva:

1. U 08:30 dočekati **svjež (neiskorišten) Claude Code prozor kvote**.
2. Dugi pozadinski poslovi (nightly pipeline zna trajati 6h+) trebaju se odvrtjeti
   dok korisnik spava, a ne preko jutra.

## 2. Nalaz — zašto jutro nikad nije bilo svježe

Claude Code pretplata broji kvotu u prozoru od ~5h. Poziv nakon isteka prethodnog
prozora otvara **novi**. Dakle nije bitno koliko tokena job potroši — bitno je **u
koji sat** ispali prvi poziv. (Točna mehanika nije do kraja izvedena, vidi §5.)

Mjereno iz `~/.claude/projects/*/*.jsonl`, startovi sessiona po satu (14 dana):

```
03h: 41   fetch.nightly (opus)         ✅ prozor istekne ~08:00
05h:  1   fetch.nightly (prelio se)    ❌ prozor živ do ~10:00
07h:  7   fetch.nightly (prelio se)    ❌ prozor živ do ~12:00
08h:  9   yc-jobwatch @08:13           ❌ prozor živ do ~13:00
09h: 182  toptal-jobwatch (13/dan)     ❌ troši tvoj svjež prozor
09h: 13   javna-nabava
09h:  4   grant-watch
```

Dva uzroka:

**(a) `yc-jobwatch` u 08:13** — otvarao prozor 17 minuta prije nego korisnik sjedne.
Strukturno je bilo nemoguće da jutro počne svježe.

**(b) `fetch.nightly` ima dugačak rep.** Zadnjih 12 runova (start 03:00):

| trajanje | 9m | 10m | 12m | 16m | 18m | 25m | 57m | 1h07 | 1h32 | 2h11 | **4h31** | **6h37** |
|---|---|---|---|---|---|---|---|---|---|---|---|---|

Medijan ~20 min, ali 14.8. je završio u 09:37 i 16.8. u 07:31. U tim runovima je
`--gemini-backend claude` spawnao Opus sessione u 07:35 i 08:31 — točno u trenutku
kad je prozor trebao biti prazan. **Pomak sata sam po sebi ovo ne rješava** — run
pokrenut u 01:00 koji traje 6h i dalje zove `claude` u 07:00. Zato ograda u §4.

Ostali jobovi (`ecosystem-brain`, `nightly-build`, `rag.sync`, `hobba-daily`,
`voting-drift`, revenuecat fetcheri) **ne diraju Claude kvotu** — `ecosystem-brain`
ide preko Vertex/Gemini (`bin/llm`) unatoč imenu funkcije (§5), ostali su čisti
node/bash/docker. Statički grep tu vara: watcheri spawnaju kroz
`process.env.CLAUDE_CLI || conf.cli || "claude"`, pa literala nema na mjestu poziva —
mjerodavni su session logovi.

## 3. Novi raspored

Pravilo dizajna: **svi jobovi koji zovu `claude` kreću na početku noći**, da otvore
jedan prozor rano i svi stanu u njega. Kad prozor točno istječe ne odlučuje raspored
nego arbitar iz §4. Poslije toga u noći rade samo ne-AI teški poslovi.

| vrijeme | job | prije | claude? | zašto tu |
|---|---|---|---|---|
| 00:10 | `com.italk.yc-jobwatch` | 08:13 | **da** | glavni krivac; prvi u redu jer je najkraći |
| 00:20 | `com.italk.toptal-jobwatch` | 09:13 | **da** | ~13 sessiona/run, treba mu prostora |
| 00:45 | `com.italk.javna-nabava` | 09:25 | **da** | |
| 00:50 | `com.italk.grant-watch` (pon/čet) | 09:40 | **da** | |
| 01:00 | `tv.domovina.fetch.nightly` | 03:00 | **da** | 2h ranije = 2h više AI budžeta unutar prozora |
| 02:00 | `com.revenuecat.podcast.enrich-youtube` | — | ne | ostaje |
| 03:00 | `ai.domovina.nightly-build` | 01:00 | ne | maknuto s fetch pipelinea, Flutter build do 80 min |
| 03:30 | `com.stepanic.dotclaude-backup` | — | ne | ostaje |
| 04:00 | `ai.domovina.apple-secret-rotate` (1. u mj.) | — | ne | ostaje |
| 05:00 | `tv.domovina.rag.sync` | 04:00 | ne | konzumira output nightlyja — vidi §5 |
| 05:30 | `com.domovina.ecosystem-brain.daily` | — | ne | ostaje (Vertex, ne Claude) |
| 06:00 / 06:05 | `revenuecat.podcast.subclub` / `.launched` | — | ne | ostaju, traju ~1s |
| 07:00 | `com.airkuna.hobba-daily` | 09:20 | ne | miče se iz radnog vremena |
| 08:00 | `ai.domovina.voting-drift` | 08:30 | ne | ne startaj baš dok korisnik sjeda |

Rezultat: **nijedan scheduled job više ne pada izvan 00:00–08:30.** Vidljivo u
LaunchdBaru — sekcija "Daytime" je prazna.

Vremena pollera nisu mijenjana (`fetch.priority` 90s, `fetch.magisterium` 10m,
`pediludium.matchsync` 15m, `.health` 30m, `.snapshot` :05) ni KeepAlive servisi.
Prva dva ipak **zovu `claude`** kad video to zatraži, pa su pokrivena ogradom iz §4 —
ne pomakom sata, jer tikaju 24/7.

## 4. Ograda: dijeljeni `claude-window` arbitar

### Zašto ne fiksno vrijeme

Prva verzija je imala hardkodiran cutoff (`CLAUDE_WINDOW_END=02:30`) u nightly
pipelineu. To je bilo krivo postavljeno pitanje. Postoje dva različita pitanja:

| pitanje | odgovor | što daje |
|---|---|---|
| Jesam li **unutar** već otvorenog prozora? | do kraja tog prozora | poziv je besplatan |
| Otvaram li **novi** prozor? | `sada + 5h ≤ 08:30` → prije ~03:30 | tvrda granica |

- **02:30 fiksno** odgovara samo na drugo pitanje → baca 3h budžeta kad je prozor
  ionako otvoren od 00:10.
- **05:30 fiksno** odgovara samo na prvo → puca kad je taj prozor u međuvremenu
  istekao: poziv u 05:20 otvara **nov** prozor do ~10:20.

Iz sata se ne vidi koji je slučaj. Zato odluku donosi jedno mjesto koje drži stanje.

### Alat

**`tools/claude-window`** u ovom repou, symlinkan u `~/.local/bin/claude-window`
(sva tri fetch plista i sve `run-cron.sh` skripte već imaju `~/.local/bin` u PATH-u):

```bash
ln -sf ~/git/stepanic/launchd-menubar/tools/claude-window ~/.local/bin/claude-window
claude-window status          # stanje bez odluke
claude-window check           # exit 0 = smiješ zvati, exit 10 = odgodi
./tools/claude-window.test.sh # 17 testova, scenariji iz §2
```

Logika `check`, redom:

1. **Tvrdi limiti.** Čita `quotaLimits` zapise koje Claude Code CLI ostavlja u
   `~/.claude/projects/*/*.jsonl` kad request bude odbijen (nose `resetsAt` i
   `rateLimitType`). Ako `seven_day` ili `five_hour` reset još nije prošao → odgodi.
   Ovo ujedno rješava hamranje iz §5: 20.8. je `toptal-jobwatch` retryao u tvrdu
   tjednu odbijenicu svakih ~3 min od 09:25 do 10:26.
2. **Unutar zapamćenog prozora?** Ako da i prozor istječe prije 08:30 → pusti.
3. **Inače poziv otvara novi** → pusti samo ako `sada + 5h` stane prije 08:30, i
   zapamti početak.

Zato `check` zovi **neposredno prije** stvarnog `claude` poziva — exit 0 ujedno
zapisuje da je prozor otvoren.

Bitna posljedica koraka 3: **preko dana arbitar propušta**, jer je sljedećih 08:30
tek sutra. Blokira samo prozor ~03:20–08:30. Ad-hoc zahtjevi tijekom radnog dana
nisu ništa sporiji.

Podesivo: `CLAUDE_WINDOW_PROTECT_AT` (default 08:30), `CLAUDE_WINDOW_HOURS` (5),
`CLAUDE_WINDOW_MARGIN_MIN` (10), `CLAUDE_WINDOW_DISABLE=1` (escape hatch).

### Tko ga pita

Ograda je svugdje aktivna samo uz `CLAUDE_WINDOW_GUARD=1`, koji postavljaju launchd
wrapperi — ručna pokretanja rade bez nje.

| repo | mjesto | kada odgađa |
|---|---|---|
| `fetch.domovina.tv` | `lib/claude_window.js` → `summarize_gemini.js` (korak 7), `generate_article_gemini.js` (korak 8) | po epizodi |
| `fetch.domovina.tv` | `automatic/nightly_pipeline.sh`, `priority_pipeline.sh`, `magisterium_pipeline.sh` | postavljaju guard |
| `pipeline.domovina.ai` | `bridge/magisterium_poller.js` | prije claima, cijeli tick |
| `ms-toptal-projects` | `tools/{yc,job,grant}-watch/src/claudeWindow.js` → `run.js` | na početku runa |
| `italk/javna-nabava` | `src/claudeWindow.js` → `run.js` | na početku runa |

Watcheri provjeravaju **prije ijednog fetcha**, da odgođen run ne pojede stavke bez
AI klasifikacije — seen-cache ostaje netaknut i idući run ih pokupi. Ako arbitar
nije dostupan (symlink fali), svi propuštaju posao i viču u log; gora je varijanta
da nightly stane zbog ograde.

**Odgoda, ne degradacija.** Alternativa je bila past cutoff pasti natrag na
Vertex/Flash, ali to poništava odluku od 2026-07-29: Flash je u incidentu atribucije
imena (Ivan Voras / `cb4CsFDCDho`) prekršio strict uputu i imenovao voditelja iz
općeg znanja, Opus nije. Epizoda je trajni statični sadržaj → radije čeka noć nego
dobije lošiji tekst. Pipeline je dir-driven pa epizoda bez `.summary.json` ostaje u
redu i bude pokupljena idući nightly. Ne-AI koraci (transcribe, R2 upload, index)
nastavljaju normalno.

## 5. Što je ostalo otvoreno

- **Tjedni (`seven_day`) limit je često prava prepreka, ne raspored.** 18.–21.8. je
  bio pun četiri dana, sve odbijeno do 22.8. 02:00. Reshuffle mijenja *kad* se kvota
  troši, ne *koliko*. Arbitar sad barem prestane hamrati u zid.
- **Mehanika prozora nije do kraja izvedena.** Iz 111 `quotaLimits` zapisa resetovi
  padaju na :10/:40 granice, ali se ne slažu s "prva poruka + 5h": 25.8. u 09:38
  reset 13:10, a u 13:59 istog dana reset 14:40 (unatrag 09:40, prije prethodnog
  reseta). Arbitar zato računa konzervativno s 5h + margina i vjeruje izmjerenom
  `resetsAt` kad ga ima, umjesto da modelira pravilo.
- **`rag.sync` vs `fetch.nightly` je i dalje race, ne sinkronizacija.** 25.8. je
  nightly trajao do 05:11 dok je rag.sync krenuo u 04:00 i počeo konzumirati
  nedovršen output. Pomak na 05:00 je zakrpa; pravo rješenje je da rag.sync čeka
  pipeline lock ili marker datoteku.
- **`ecosystem-brain` ima `call_claude()` koja ne zove Claude.** `bin/rollup_lib.py`,
  docstring: *"Name kept for callers; backend is now Gemini via Vertex (bin/llm)"*.
  Ime laže, kvotu ne troši — ne treba mu ograda.

## 6. Revert

Originalni plistovi: `~/Library/LaunchAgents/_schedule-backup-2026-08-26/`

```bash
cp ~/Library/LaunchAgents/_schedule-backup-2026-08-26/*.plist ~/Library/LaunchAgents/
for l in com.italk.yc-jobwatch com.italk.toptal-jobwatch com.italk.javna-nabava \
         com.italk.grant-watch tv.domovina.fetch.nightly ai.domovina.nightly-build \
         tv.domovina.rag.sync com.airkuna.hobba-daily ai.domovina.voting-drift; do
  launchctl bootout "gui/$(id -u)/$l" 2>/dev/null
  launchctl bootstrap "gui/$(id -u)" ~/Library/LaunchAgents/$l.plist
done
```

Ogradu isključiš bez diranja koda: `CLAUDE_WINDOW_DISABLE=1` u okolišu joba, ili
`rm ~/.local/bin/claude-window` (svi consumeri tad propuštaju posao uz warning u logu).
Za jedan job dovoljno je maknuti `CLAUDE_WINDOW_GUARD=1` iz njegovog wrappera.

## 7. Kako je mjereno

```bash
# raspored svih jobova iz plistova
plutil -p ~/Library/LaunchAgents/<label>.plist

# kad automatizirani jobovi otvaraju Claude session (start po satu, po projektu)
# prvi timestamp svakog ~/.claude/projects/*/*.jsonl, grupirano po hour-of-day

# stvarno trajanje nightlyja
cd ~/git/domovinatv/fetch.domovina.tv/automatic/logs
for f in nightly_2026-08-*.log; do
  echo "$f $(grep -aoE '[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9:]{8}' $f | sed -n '1p;$p' | tr '\n' ' ')"
done
```
