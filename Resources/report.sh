#!/bin/bash
# ClaudePill: skickar Claude Code hook-payload till ClaudePill. Får ALDRIG skriva till stdout.
# (Referenskopia – appen skriver ~/.claudepill/report.sh själv via HookInstaller.)
curl -s -m 1 -X POST \
  -H "Content-Type: application/json" \
  --data-binary @- \
  http://127.0.0.1:47824/event >/dev/null 2>&1
exit 0
