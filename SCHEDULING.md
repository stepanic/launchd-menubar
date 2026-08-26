# Raspored launchd jobova — analiza i reshuffle (2026-08-26)

Zapis odluke: **zašto** su jobovi pomaknuti, ne samo **kamo**. Ako ikad budeš vraćao
neki job u jutarnji termin, pročitaj §2 prvo — postoji razlog zašto je 08:13 bio loš.

## 1. Cilj

Mac mini radi 24/7, korisnik za njim nije od **00:00 do 08:30**. Dva zahtjeva:

1. U 08:30 dočekati **svjež (neiskorišten) Claude Code prozor kvote**.
2. Dugi pozadinski poslovi (nightly pipeline zna trajati 6h+) trebaju se odvrtjeti
   dok korisnik spava, a ne preko jutra.

## 2. Nalaz — zašto jutro nikad nije bilo svježe

Claude Code pretplata broji kvotu u prozoru od ~5h koji **kreće od prve poruke**.
Svaki `claude` poziv nakon isteka prethodnog prozora otvara **novi** prozor. Dakle
nije bitno koliko tokena job potroši — bitno je **u koji sat** ispali prvi poziv.

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
ide preko Vertex/Gemini (`bin/llm`), ostali su čisti node/bash/docker.

## 3. Novi raspored

Pravilo dizajna: **svi `claude` pozivi kreću prije 02:30.** I najgori slučaj
(02:30 + 5.5h) istekne do 08:00. Poslije 03:00 u noći rade samo ne-AI teški poslovi.

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

Nepromijenjeni polleri (`fetch.priority` 90s, `fetch.magisterium` 10m,
`pediludium.matchsync` 15m, `.health` 30m, `.snapshot` :05) i KeepAlive servisi.

## 4. Ograda: `CLAUDE_WINDOW_*` u fetch pipelineu

Repo: `~/git/domovinatv/fetch.domovina.tv`

- **`lib/claude_window.js`** (novo) — čita `CLAUDE_WINDOW_START` / `CLAUDE_WINDOW_END`
  (HH:MM). Bez `CLAUDE_WINDOW_END` je ograda **isključena**, pa ručni i prioritetni
  runovi rade kao prije. Prozor smije prelaziti ponoć.
- **`summarize_gemini.js`** (korak 7) i **`generate_article_gemini.js`** (korak 8) —
  prije svake epizode: ako je backend `claude` i prozor je zatvoren, epizoda se
  **odgađa**, ne obrađuje.
- **`automatic/nightly_pipeline.sh`** — postavlja `CLAUDE_WINDOW_START=00:00
  CLAUDE_WINDOW_END=02:30` na poziv `run_pipeline.sh`.

**Odgoda, ne degradacija.** Alternativa je bila poslije 02:30 pasti natrag na
Vertex/Flash, ali to poništava odluku od 2026-07-29: Flash je u incidentu atribucije
imena (Ivan Voras / `cb4CsFDCDho`) prekršio strict uputu i imenovao voditelja iz
općeg znanja, Opus nije. Epizoda je trajni statični sadržaj → radije čeka noć nego
dobije lošiji tekst. Pipeline je dir-driven pa epizoda bez `.summary.json` ostaje u
redu i bude pokupljena idući nightly. Ne-AI koraci (transcribe, R2 upload, index)
nastavljaju normalno i poslije 02:30.

## 5. Što je ostalo otvoreno

- **`rag.sync` vs `fetch.nightly` je i dalje race, ne sinkronizacija.** 25.8. je
  nightly trajao do 05:11 dok je rag.sync krenuo u 04:00 i počeo konzumirati
  nedovršen output. Pomak na 05:00 je zakrpa; pravo rješenje je da rag.sync čeka
  pipeline lock ili marker datoteku.
- **`fetch.priority` (90s) i `fetch.magisterium` (10m) mogu zvati `claude` u bilo
  koje doba.** Danas u praksi ne zovu (0 poziva u dnevnim logovima — AI grana se
  pali samo kad video eksplicitno traži `--gemini-backend claude`), ali ako takav
  video stigne u 07:50, prozor je otvoren. Namjerno **nisu** ograđeni: ad-hoc
  zatražen video ne smije čekati do sutra. Ako ovo postane čest problem, ograda
  je već tu — dovoljno je postaviti `CLAUDE_WINDOW_END` i u tim jobovima.
- **Tjedni limit ovo ne dira.** Reshuffle mijenja *kad* se kvota troši, ne *koliko*.

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

Ogradu u fetch pipelineu isključiš tako da makneš `CLAUDE_WINDOW_*` iz
`automatic/nightly_pipeline.sh` — `lib/claude_window.js` bez njih ne radi ništa.

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
