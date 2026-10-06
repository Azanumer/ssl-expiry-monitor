#!/usr/bin/env bash
#
# check-ssl.sh — check TLS certificate expiry for a list of domains and alert by email.
#
# Usage:
#   DOMAINS_FILE=domains.txt WARN_DAYS=30 CRIT_DAYS=7 ALERT_EMAIL=admin@example.com ./check-ssl.sh
#
# Cron example (daily at 8am):
#   0 8 * * * ALERT_EMAIL=admin@example.com /opt/ssl-expiry-monitor/check-ssl.sh >/dev/null 2>&1
#
# domains.txt format: one per line — "example.com" or "example.com:8443". Lines
# starting with # are ignored.

set -euo pipefail

DOMAINS_FILE="${DOMAINS_FILE:-$(dirname "$0")/domains.txt}"
WARN_DAYS="${WARN_DAYS:-30}"
CRIT_DAYS="${CRIT_DAYS:-7}"
ALERT_EMAIL="${ALERT_EMAIL:-}"

if [[ ! -f "$DOMAINS_FILE" ]]; then
	echo "ERROR: domains file not found: $DOMAINS_FILE" >&2
	exit 2
fi

now_epoch="$(date +%s)"
warn_list=()
crit_list=()
fail_list=()

days_left_for() {
	local host="$1" port="$2"
	local enddate
	enddate="$(echo | openssl s_client -connect "${host}:${port}" -servername "$host" 2>/dev/null \
		| openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2 || true)"
	[[ -z "$enddate" ]] && return 1
	local end_epoch
	end_epoch="$(date -d "$enddate" +%s 2>/dev/null || date -j -f '%b %d %T %Y %Z' "$enddate" +%s 2>/dev/null || true)"
	[[ -z "$end_epoch" ]] && return 1
	echo $(( (end_epoch - now_epoch) / 86400 ))
	return 0
}

while IFS= read -r line || [[ -n "$line" ]]; do
	line="$(echo "$line" | sed 's/[[:space:]]//g')"
	[[ -z "$line" || "$line" == \#* ]] && continue

	host="${line%%:*}"
	port="443"
	[[ "$line" == *:* ]] && port="${line##*:}"

	days="$(days_left_for "$host" "$port" || true)"
	if [[ -z "${days:-}" ]]; then
		fail_list+=("$host:$port (could not fetch certificate)")
		continue
	fi

	if (( days <= CRIT_DAYS )); then
		crit_list+=("$host:$port expires in ${days} day(s)")
	elif (( days <= WARN_DAYS )); then
		warn_list+=("$host:$port expires in ${days} day(s)")
	else
		echo "OK: $host:$port — ${days} days left"
	fi
done < "$DOMAINS_FILE"

report=""
[[ ${#crit_list[@]} -gt 0 ]] && report+="CRITICAL (<${CRIT_DAYS}d):\n  $(printf '%s\n  ' "${crit_list[@]}")\n"
[[ ${#warn_list[@]} -gt 0 ]] && report+="WARNING (<${WARN_DAYS}d):\n  $(printf '%s\n  ' "${warn_list[@]}")\n"
[[ ${#fail_list[@]} -gt 0 ]] && report+="UNREACHABLE:\n  $(printf '%s\n  ' "${fail_list[@]}")\n"

if [[ -n "$report" ]]; then
	echo -e "SSL certificate check — $(date)\n$report"
	if [[ -n "$ALERT_EMAIL" ]] && command -v mail >/dev/null 2>&1; then
		echo -e "$report" | mail -s "SSL expiry alert — $(date +%F)" "$ALERT_EMAIL"
	fi
	[[ ${#crit_list[@]} -gt 0 || ${#fail_list[@]} -gt 0 ]] && exit 1 || exit 0
fi

echo "All certificates healthy."
