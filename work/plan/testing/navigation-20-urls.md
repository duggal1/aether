# Real-app navigation reliability, 2026-09-23

Exercise the user's exact ten homepage/internal URL pairs (20 URLs), starting with Clay. Verify the current app, preserve unrelated changes, and fix only reproduced defects.

1. Inspect current UI/runtime/callback boundaries and prior fixes; build the current packaged application.
2. Establish external UI automation and independent window screenshots. Keep WebKit paint, app presentation, and agent inspection measurements separate.
3. Test immediate homepage interruption, direct internal entry, actual internal links, warm repeats, back/forward, reload, tab switching and concurrent tabs. Record every attempt and failure, expected and actual paths, timing samples and screenshots.
4. Investigate failures using live traces and controlled reproductions; compare Safari where automation permits. Apply minimal verified fixes and rerun affected cases.
5. Run focused navigation regressions, report sample counts/distributions including missing/timed-out observations, and document limits without claiming unmeasured improvements.

First visible content requires window pixels; DOM content and FCP are separate evidence. Cold process launches do not imply empty website caches. No browsing-data deletion.

## User steering: repair local agent infrastructure first
Remove manual per-profile approval and token exchange for the packaged app; default local daemon to direct access. Reproduce and fix newline framing loss. Start local access with the app, expose visible-tab controls and readiness, isolate blocking socket I/O from the Swift executor, and verify reconnects, concurrent/partial/pipelined clients and cold launches before resuming website campaigns. Existing auth remains opt-in for callers that explicitly request it. Local socket remains owner-only.
