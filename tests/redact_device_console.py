#!/usr/bin/env python3
"""Filter live device output before saving it; omit pairing/session secrets."""
import re
import sys

SENSITIVE = re.compile(
    r"(?i)(\bPIN\s*:|\b(?:riKey|riKeyId|salt|clientchallenge|serverchallenge|"
    r"clientpairingsecret|pairingsecret|serverchallengeresp|clientchallengeresp|"
    r"aeskey|sessionkey|privatekey|clientsecret|serversecret)\b)"
)
pem = False
for line in sys.stdin:
    if "-----BEGIN " in line:
        pem = True
    if pem:
        if "-----END " in line:
            pem = False
        continue
    sys.stdout.write("[redacted pairing/session diagnostic]\n" if SENSITIVE.search(line) else line)
    sys.stdout.flush()
