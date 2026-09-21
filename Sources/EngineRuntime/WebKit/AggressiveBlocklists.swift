import Foundation

public enum AggressiveBlockFilter {
  public static func ruleList(blockAds: Bool, blockTrackers: Bool, hideIP: Bool,
    cookieBanners: Bool = false) -> String {
    var lines: [String] = []
    if blockAds {
      lines += adHosts.map { "||\($0)^" }
      lines += videoAdPatterns.map { "REGEX:\($0)" }
      lines += minerHosts.map { "||\($0)^" }
    }
    if blockTrackers || hideIP {
      if hideIP {
        lines += trackerHosts.map { "||\($0)^" }
      } else {
        lines += trackerHosts.map { "COOKIE:\($0)" }
      }
    }
    if cookieBanners {
      lines += consentHosts.map { "||\($0)^" }
    }
    return lines.joined(separator: "\n")
  }

  static func domainTrigger(_ domain: String) -> [String: String] {
    let escaped = NSRegularExpression.escapedPattern(for: domain)
    return ["url-filter": "^https?://([^/]+\\.)?" + escaped + "([/:?#]|$)"]
  }

  public static func compile(source: String) throws -> String {
    var blocks: [[String: [String: String]]] = []
    var exceptions: [[String: [String: String]]] = []
    for raw in source.split(separator: "\n", omittingEmptySubsequences: false) {
      let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
      if line.isEmpty || line.hasPrefix("!") || line.hasPrefix("[") { continue }
      if line.hasPrefix("@@||"), line.hasSuffix("^") {
        let domain = String(line.dropFirst(4).dropLast())
        guard !domain.isEmpty else { continue }
        exceptions.append(["trigger": domainTrigger(domain), "action": ["type": "ignore-previous-rules"]])
      } else if line.hasPrefix("||"), line.hasSuffix("^") {
        let domain = String(line.dropFirst(2).dropLast())
        guard !domain.isEmpty else { continue }
        blocks.append(["trigger": domainTrigger(domain), "action": ["type": "block"]])
      } else if line.hasPrefix("COOKIE:") {
        let domain = String(line.dropFirst(7))
        guard !domain.isEmpty else { continue }
        blocks.append(["trigger": domainTrigger(domain), "action": ["type": "block-cookies"]])
      } else if line.hasPrefix("REGEX:") {
        let pattern = String(line.dropFirst(6))
        guard !pattern.isEmpty else { continue }
        blocks.append(["trigger": ["url-filter": pattern], "action": ["type": "block"]])
      }
    }
    let json = String(decoding: try JSONEncoder().encode(blocks + exceptions), as: UTF8.self)
    return json
  }

  static let adHosts: [String] = [
    "doubleclick.net", "googlesyndication.com", "googleadservices.com", "googleads.com",
    "pagead2.googlesyndication.com", "tpc.googlesyndication.com",
    "googleads.g.doubleclick.net", "pubads.g.doubleclick.net", "securepubads.g.doubleclick.net",
    "ad.doubleclick.net", "static.doubleclick.net", "admeld.com",
    "2mdn.net", "s0.2mdn.net", "imasdk.googleapis.com",
    "amazon-adsystem.com", "aax.amazon-adsystem.com",
    "criteo.com", "criteo.net", "adnxs.com", "adnxs-simple.com",
    "rubiconproject.com", "pubmatic.com", "openx.com", "openx.net",
    "moatads.com", "moat.com", "iasds01.com",
    "adsrvr.org", "mathtag.com", "rfihub.com", "lijit.com", "sovrn.com",
    "sharethrough.com", "triplelift.com", "outbrain.com", "taboola.com",
    "revcontent.com", "mgid.com", "adblade.com", "zemanta.com",
    "bidswitch.net", "casalemedia.com", "contextweb.com",
    "spotxchange.com", "spotx.tv", "springserve.com", "freewheel.tv",
    "adform.com", "adform.net", "adtech.de", "adtechus.com", "smartadserver.com",
    "undertone.com", "eqads.com", "nster.net",
    "ads.linkedin.com", "px.ads.linkedin.com",
    "ads.pinterest.com", "ads.reddit.com",
    "ads-api.twitter.com", "ads.twitter.com", "static.ads-twitter.com",
    "ads.snapchat.com", "ads.tiktok.com",
    "an.facebook.com", "ads.facebook.com",
    "applovin.com", "mopub.com", "ironsrc.com", "unityads.unity3d.com", "vungle.com",
    "popads.net", "popcash.net", "adcash.com", "propellerads.com",
    "hilltopads.net", "adsterra.com", "clickadu.com",
    "yandexadexchange.net", "adfox.yandex.ru",
  ]

  static let trackerHosts: [String] = [
    "google-analytics.com", "googletagmanager.com", "analytics.google.com",
    "stats.g.doubleclick.net", "jnn-pa.googleapis.com",
    "connect.facebook.net",
    "analytics.twitter.com",
    "hotjar.com", "hotjar.io", "fullstory.com",
    "mixpanel.com", "cdn.mxpnl.com",
    "segment.io", "cdn.segment.com",
    "amplitude.com", "newrelic.com", "nr-data.net",
    "bugsnag.com", "sessions.bugsnag.com",
    "sentry.io", "browser.sentry-cdn.com",
    "optimizely.com", "cdn.optimizely.com",
    "crazyegg.com", "mouseflow.com", "luckyorange.com", "inspectlet.com",
    "clicktale.net", "contentsquare.net", "quantummetric.com",
    "kissmetrics.com", "heap.io", "cdn.heapanalytics.com",
    "pendo.io", "cdn.pendo.io",
    "analytics.pinterest.com", "log.pinterest.com",
    "events.redditmedia.com",
    "analytics.snapchat.com",
    "analytics.tiktok.com",
    "snap.licdn.com",
    "scorecardresearch.com", "quantserve.com",
    "demdex.net", "omtrdc.net", "2o7.net", "everesttech.net",
    "cdn.fpjs.io", "api.fpjs.io",
  ]

  static let minerHosts: [String] = [
    "coinhive.com", "coin-hive.com", "jsecoin.com",
    "cryptoloot.pro", "minero.cc", "webminepool.com",
  ]

  static let consentHosts: [String] = [
    "consentmanager.net", "cdn.cookielaw.org",
    "consent.trustarc.com", "apis.sourcepoint.com", "cdn.sourcepoint.com",
    "sdk.didomi.io", "app.usercentrics.eu", "sdk.usercentrics.com",
    "consent.cookiebot.com", "cmp.osano.com",
  ]

  static let videoAdPatterns: [String] = [
    "youtube\\.com/(api/stats/ads|ptracking|pagead|get_midroll_info)",
    "twitter\\.com/i/adsct",
    "facebook\\.com/tr[/?]",
    ".*[?&]adformat=",
  ]
}
