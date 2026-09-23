# Private Relay — Proton WireGuard via WireProxy (browser-scoped)

Date: 2026-09-22. No system VPN, no system-wide routing, no Chromium. WebKit
stays the renderer; a userspace WireGuard bridge feeds the existing per-profile
proxy machinery.

## How it works

```
Proton WireGuard server (US)
      ^ WireGuard (userspace, wireproxy process)
      |
127.0.0.1:25344 (SOCKS5, localhost only)
      ^
      | Network.ProxyConfiguration, allowFailover = false
      |
Profile WKWebsiteDataStore -> existing WKWebViews
```

`WireProxyManager` (`Sources/BrowserUI/Sources/AetherHumanUI/Engine/`) owns the
process lifecycle and the `Application Support/Aether/PrivateRoute/` directory
(`proton.conf` + generated `wireproxy.conf` + log, 0700/0600). `PrivateRouteProbe`
verifies the exit over the SOCKS port with `https://ipwho.is/` and requires
`country_code == "US"` — enforced in the manager too, so no verifier can
accidentally report a foreign exit as connected. Traffic application reuses the
existing `BrowserNetworkRouting.applyNetworkRoute` path with a
`127.0.0.1:25344` endpoint; nothing touches `WKWebsiteDataStore` directly and no
second proxy path exists. Status surfaces through the existing
`NetworkRouteStatus`; `connected` is reported only after verification.

## Setup (operator action required — free forever, no card)

1. Create a free Proton account at `protonvpn.com/free-vpn` (recovery email +
   password, no payment instrument).
2. Sign in at `account.protonvpn.com` → Downloads → WireGuard configuration →
   create a config against a **US** server → download the `.conf`.
3. In Aether: Settings → Network Privacy → Private Relay → Import .conf →
   select the file (private key stays in the 0600 file; never in SQLite/logs).
4. Start Relay. The UI shows the verified exit IP + country, or a concrete
   failure (missing binary, bad config, unreachable peer, non-US exit).
5. Confirm independently at that point:
   `curl --proxy socks5h://127.0.0.1:25344 https://ipwho.is/` must show your
   Proton IP with `"country_code": "US"`, differing from the direct
   `curl https://ipwho.is/`.

## Verified by testing (no Proton account needed)

- `wireproxy` v1.1.2 via `go install` (binary self-reports `1.0.8-dev`;
  upstream version-string lag). ISC licensed, so bundling is permitted.
- `-n/--configtest` accepts well-formed configs and rejects garbage
  (observed directly).
- `PrivateRouteTests` (13/13): config validation, owner-only import, exact
  generated-config bytes, binary lookup, probe parsing incl. malformed
  payloads, dead-port failure, no-config start fails closed, injected US probe
  → connected, injected non-US probe → failed naming the country.
- `PrivateRouteLiveTests` (`AETHER_LIVE=1`): the real binary prints
  `Config OK` for manager-written files.
- Failure-path proof with the real stack: process up + unreachable peer →
  curl through the port fails and verification never reports connected.

## Honest limitations

- **Exit city = imported server.** Free plans assign servers; San Francisco vs
  New York vs Boston vs Philadelphia on demand requires either lucky assignment
  or a paid plan with city choice. Multi-city means multiple `.conf` files,
  one relay active at a time. Never claim a city the probe did not confirm.
- **One free device at a time** on Proton Free. Enough for this Mac, nothing more.
- **TCP only.** Upstream wireproxy lists SOCKS5 UDP as TODO. WebRTC can expose
  the direct IP (proven live in `WebKitEgressProbeLiveTests`); the relay must
  not be advertised as leak-free.
- **Distribution.** The signed app is sandboxed; spawning `/opt/homebrew/*`
  will be denied there. Dev and test runs are unsandboxed, which is why
  verification works locally. Shipping requires bundling a signed wireproxy
  build inside the app (license allows it) with the sandbox rules to permit it.
- **Kill-switch scope.** `allowFailover = false` stops WebKit's deliberate
  fallback, and unverified relay blocks navigation in the demo flow, but
  native `URLSession` traffic and non-WebKit processes are outside the
  per-store configuration (same boundary as the existing route machinery).
