#!/usr/bin/env bash
# Test matrica za tools/claude-window. Pokreni: ./tools/claude-window.test.sh
#
# Scenariji su izvedeni iz stvarnih slučajeva u SCHEDULING.md: nightly koji se
# prelio u 07:35 i 08:31, watcher u 08:13, i tjedni limit koji je 18.-21.8. bio
# pun četiri dana.
set -uo pipefail
CW="$(dirname "$0")/claude-window"
STATE="$(mktemp -t cw-state)"
export CLAUDE_WINDOW_STATE="$STATE"
# Prazan projects dir → scan ne nalazi observed limite osim kad ih test podmetne.
export HOME_REAL="$HOME"

pass=0; fail=0

# run <opis> <ocekivano: OK|ODGODI> <vrijeme> [state-json]
run() {
    local desc="$1" want="$2" when="$3" state="${4:-}"
    if [ -n "$state" ]; then printf '%s' "$state" > "$STATE"; else rm -f "$STATE"; fi
    CLAUDE_WINDOW_NOW="$when" "$CW" check >/dev/null 2>"$STATE.err"
    local rc=$?
    local got="OK"; [ $rc -eq 10 ] && got="ODGODI"
    if [ "$got" = "$want" ]; then
        pass=$((pass+1)); printf "ok   %-52s %s\n" "$desc" "$(sed 's/^claude-window: //' "$STATE.err")"
    else
        fail=$((fail+1)); printf "FAIL %-52s ocekivano=%s dobiveno=%s (rc=%s)\n" "$desc" "$want" "$got" "$rc"
    fi
}

epoch() { date -j -f "%Y-%m-%dT%H:%M:%S" "$1" +%s; }
win()   { printf '{"windowStart": %s000}' "$(epoch "$1")"; }
limit() { printf '{"observed":{"%s":{"resetsAt":%s000,"seenAt":%s000}},"observedAt":%s000}' \
            "$1" "$(epoch "$2")" "$(epoch "$3")" "$(epoch "$3")"; }

echo "── nema otvorenog prozora (poziv bi otvorio novi) ──"
run "00:10 watcher — nov prozor do 05:10"          OK     2026-09-01T00:10:00
run "03:15 rub — nov prozor do 08:15"              OK     2026-09-01T03:15:00
run "03:25 preko ruba (08:25 > 08:20 s marginom)"  ODGODI 2026-09-01T03:25:00
run "05:20 nightly se prelio, prozor istekao"      ODGODI 2026-09-01T05:20:00
run "07:35 stvarni slucaj 14.8."                   ODGODI 2026-09-01T07:35:00
# Nakon 08:30 je granica prosla i korisnik vec radi — arbitar stiti TRENUTAK 08:30,
# ne cijeli radni dan, inace bi zablokirao priority poller preko dana.
run "08:31 granica prosla, dalje je radni dan"     OK     2026-09-01T08:31:00
run "15:00 radno vrijeme, stiti se tek sutra 08:30" OK    2026-09-01T15:00:00

echo
echo "── prozor otvoren u 00:10, istjece 05:10 ──"
run "01:00 nightly krece"          OK     2026-09-01T01:00:00 "$(win 2026-09-01T00:10:00)"
run "02:30 stari cutoff — sad prolazi" OK  2026-09-01T02:30:00 "$(win 2026-09-01T00:10:00)"
run "05:00 jos unutar prozora"     OK     2026-09-01T05:00:00 "$(win 2026-09-01T00:10:00)"
run "05:11 prozor istekao"         ODGODI 2026-09-01T05:11:00 "$(win 2026-09-01T00:10:00)"

echo
echo "── prozor otvoren prekasno (traje preko 08:30) ──"
run "04:00 u prozoru otvorenom 03:50 (do 08:50)" ODGODI 2026-09-01T04:00:00 "$(win 2026-09-01T03:50:00)"

echo
echo "── tvrdi limiti iz session logova ──"
run "five_hour iscrpljen, reset 13:10"   ODGODI 2026-09-01T09:38:00 "$(limit five_hour 2026-09-01T13:10:00 2026-09-01T09:38:00)"
run "five_hour reset prosao"             OK     2026-09-01T13:20:00 "$(limit five_hour 2026-09-01T13:10:00 2026-09-01T09:38:00)"
run "seven_day iscrpljen (18.-21.8.)"    ODGODI 2026-09-01T01:00:00 "$(limit seven_day 2026-09-04T02:00:00 2026-09-01T01:00:00)"
# Stariji zapis (izvan TTL-a) mora prezivjeti re-scan koji ga vise ne nadje.
run "seven_day zapamcen i nakon isteka TTL-a" ODGODI 2026-09-01T02:00:00 "$(limit seven_day 2026-09-04T02:00:00 2026-09-01T00:50:00)"

echo
echo "── escape hatch ──"
CLAUDE_WINDOW_DISABLE=1 CLAUDE_WINDOW_NOW=2026-09-01T07:35:00 "$CW" check >/dev/null 2>&1 \
    && { pass=$((pass+1)); echo "ok   CLAUDE_WINDOW_DISABLE=1 dopusta i u 07:35"; } \
    || { fail=$((fail+1)); echo "FAIL CLAUDE_WINDOW_DISABLE=1"; }

rm -f "$STATE" "$STATE.err"
echo
echo "prošlo: $pass, palo: $fail"
[ "$fail" -eq 0 ]
