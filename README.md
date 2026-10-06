# SSL Expiry Monitor

A cron-friendly bash script that checks TLS certificate expiry for a list of domains and emails you before one lapses. One expired cert = a scary browser warning and lost visitors; this gives you 30- and 7-day warnings.

## How it works

- Reads `domains.txt` (one per line: `example.com` or `example.com:8443`)
- Pulls each cert with `openssl s_client`, computes days until expiry
- **CRITICAL** (≤ 7 days), **WARNING** (≤ 30 days) — configurable via `CRIT_DAYS` / `WARN_DAYS`
- Sends one digest email via `mail(1)` when anything needs attention
- Exit code `1` on critical/unreachable (so monitoring systems can hook it), `0` otherwise

## Setup

```bash
cp domains.txt.example domains.txt   # edit with your domains
chmod +x check-ssl.sh

# Test run:
ALERT_EMAIL=admin@example.com ./check-ssl.sh

# Cron — daily at 8am:
0 8 * * * ALERT_EMAIL=admin@example.com /opt/ssl-expiry-monitor/check-ssl.sh >/dev/null 2>&1
```

Requires `openssl` and a local MTA for email alerts (postfix/sendmail providing `mail`). Works on Linux and macOS (BSD `date` fallback included).

MIT licensed.
