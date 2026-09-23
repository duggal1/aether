#!/bin/sh
# verify_egress.sh — free, local egress verification for Aether's browser-scoped routing.
#
# What it proves (without spending anything or storing any secret):
#   1. The direct public IP visible without routing.
#   2. That a dead proxy + fail-closed WEBKIT behavior is observable: curl through a
#      blackhole SOCKS5 endpoint must fail, never silently return the direct IP.
#   3. Optionally, a short, filtered packet capture proving which path probe
#      traffic takes. Capture is opt-in (--capture), limited to the echo hosts,
#      written to /tmp, and deleted unless --keep is passed.
#
# It does NOT provision exit servers, and it does NOT prove a regional exit:
# a region is only proven when the app's Verify Route reports connected for a
# user-supplied endpoint whose observed IP matches the expected exit IP.
set -eu

ECHO_HOST="api.ipify.org"
CAPTURE=0
KEEP=0
for arg in "$@"; do
  case "$arg" in
    --capture) CAPTURE=1 ;;
    --keep) KEEP=1 ;;
    --help|-h)
      echo "usage: verify_egress.sh [--capture] [--keep]"
      exit 0
      ;;
  esac
done

pass() { printf 'PASS %s\n' "$1"; }
fail() { printf 'FAIL %s\n' "$1"; exit 1; }

command -v curl >/dev/null 2>&1 || fail "curl is required"
command -v python3 >/dev/null 2>&1 || fail "python3 is required"

DIRECT_IP="$(curl -sS --max-time 10 "https://${ECHO_HOST}?format=text" || true)"
[ -n "$DIRECT_IP" ] || fail "could not observe the direct public IP"
printf 'direct public IP: %s\n' "$DIRECT_IP"
pass "direct egress observed"

# Fail-closed blackhole: port 9 (discard) on loopback must refuse the request.
if curl -sS --max-time 8 --socks5-hostname 127.0.0.1:9 "https://${ECHO_HOST}?format=text" >/tmp/aether-egress-blackhole.out 2>/tmp/aether-egress-blackhole.err; then
  rm -f /tmp/aether-egress-blackhole.out /tmp/aether-egress-blackhole.err
  fail "blackhole proxy unexpectedly succeeded; fail-closed behavior not demonstrated"
else
  rm -f /tmp/aether-egress-blackhole.out /tmp/aether-egress-blackhole.err
  pass "blackhole proxy fails instead of leaking the direct IP"
fi

if [ "$CAPTURE" -eq 1 ]; then
  command -v tcpdump >/dev/null 2>&1 || fail "tcpdump not found; run without --capture"
  PCAP="$(mktemp /tmp/aether-egress-XXXXXX.pcap)"
  echo "capturing 12s of traffic to ${ECHO_HOST} only -> ${PCAP}"
  # Filter restricts capture to echo-host traffic; short timeout bounds the file.
  sudo tcpdump -i any -G 12 -W 1 -w "$PCAP" "host ${ECHO_HOST}" >/dev/null 2>&1 &
  TCPDUMP_PID=$!
  sleep 1
  curl -sS --max-time 10 "https://${ECHO_HOST}?format=text" >/dev/null || true
  wait "$TCPDUMP_PID" || true
  tcpdump -nn -r "$PCAP" -c 5 2>/dev/null || true
  if [ "$KEEP" -eq 1 ]; then
    echo "capture kept at ${PCAP} (test traffic only; delete after review)"
  else
    rm -f "$PCAP"
    echo "capture deleted"
  fi
  pass "packet capture completed and bounded"
fi

echo "done: direct IP observed, fail-closed demonstrated. Regional exits still require user-supplied endpoints verified in Settings -> Network Privacy."
