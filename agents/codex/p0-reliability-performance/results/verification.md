# Aether P0 verification, 2026-09-23

Host: macOS 27.0 (26A5425a), Swift 6.4, full Xcode. The installed system is not macOS 27.2.

## Reproduced defects and changes

- A new `WKWebView` loaded `about:blank` in its initializer. Its delayed callbacks could take ownership of the first requested navigation. Before removing that load, five of nine live WebKit fixture tests failed, including genuine failure, redirect, subframe failure, and content readiness. The unchanged nine tests passed after removal.
- An interrupted attachment navigation produced `WebKitErrorDomain` code 102 after `isLoading` became false and left its waiter pending. The new attachment fixture test failed at three seconds before event-driven settlement and passed afterward. The 60-second deadline remains a last-resort guard.
- A delayed UI navigation error could replace a published ready document. The new `lateNavigationErrorCannotReplacePublishedContent` test failed before the `contentReady` guard and passed afterward.
- A cancelled request with no document and no error could leave the tab showing loading forever. The new focused test passes after mapping that settled state to a new tab.
- The favicon cache had no retained-image bound and decoded arbitrary source dimensions. It now retains at most 128 thumbnails of at most 128 pixels per edge. The UI package builds; no before/after process memory measurement for this change was performed.
- Unused `loadCycle` state in the omnibox was written on each progress update; removing it avoids unrelated SwiftUI invalidation.

## Verification performed

- `/tmp/aether-navigation-tests.log`: initial live WebKit fixture suite, five failures among nine tests.
- `/tmp/aether-navigation-tests-after-blank.log`: nine live WebKit fixture tests passed.
- `/tmp/aether-p0-current-tests.log`: six human integration, 19 agent/navigation, and six omnibox tests passed. This includes the original five failing cases and new redirect, replacement, back/forward/reload, interruption, and simulated process-termination cases.
- `/tmp/aether-interrupted-ui-focused.log`: one focused tab-state regression passed.
- `/tmp/aether-ui-focused-build.log` and `/tmp/aether-ui-final-build.log`: standalone UI package builds passed without warnings.
- `/tmp/aether-p0-release-build.log`: root release build passed before the final favicon and tab-state edits. A separate concurrent release build created a later binary, but its process output was not captured by this investigation.
- A live isolated app opened `clay.com` from the native omnibox, ended at `https://www.clay.com`, rendered the hero, and showed no gradient in `/tmp/aether-p0-clay-window.png`. Apple also rendered in `/tmp/aether-p0-front.png`. A runtime navigation reached `https://www.youtube.com/` and title `YouTube`; a delayed visual observation of that page was not completed.

## Resource sample and limits

During one YouTube load in the isolated app, `ps` showed the WebContent process at 155.5% CPU and 639,696 KiB RSS. Later, with Clay selected and YouTube in the background, it showed 0.7% CPU and 73,104 KiB RSS. A five-second WebContent sample recorded 531.7 MB physical footprint and 732.1 MB peak during the initial load. These are two workload states, not comparable trials or a Chrome benchmark. `/tmp/aether-youtube-sample.txt` and `/tmp/aether-ui-sample.txt` hold the sample stacks.

No median, p95, worst-case first usable paint, gradient gap, scroll frame-time, controlled 4K playback, or post-change memory distribution was measured. The user asked to stop aggressive testing; the remaining live acceptance cases are unverified. `WKWebView` and the website own most page rendering work, and the data does not establish an Aether scrolling hot path.

The isolated test app was stopped and its local-agent socket and token removed. The popup arose from enabling automation in that test profile. Deletion of the test app bundle was rejected by automatic command review; it remains in `.build` but is not running.
