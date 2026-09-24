# Aether performance stress — 20260924_114229

Binary: `d2ea7d7bca8ec33dbbc6cd09fccd58d8dc484870a7770e98f08678d8ce6af047`

App launch: 1448.9 ms
Completed: 3/10

| Step | Status | Dispatch ms | Ready ms | FCP ms | LCP ms | Final URL / error |
| --- | --- | ---: | ---: | ---: | ---: | --- |
| pass1_01_land-book_home | failed | 75.2 | — | — | — | no current document with FCP within 45s; tab={"progress": 0.1, "contentReady": false, "pendingURL": null, "error": null, "page": 61, "id": "8646C022-7FE9-4057-802A-53F48F452E3F", "title": "https://land-book.com/", "state": "loading", "loading": true, "paintReady": false, "canGoBack": false, "url": "https://land-book.com/", "canGoForward": false} metrics=null |
| pass1_01_land-book_route | ok | 37.5 | 28408.1 | 28189 | — | https://land-book.com/websites/100215-jack-and-jill-where-remarkable-people-meet-ambitious-companies |
| pass2_01_land-book_home | ok | 15.3 | 27071.1 | 26823 | — | https://land-book.com/ |
| pass2_01_land-book_route | ok | 24.6 | 25269.1 | 25004 | — | https://land-book.com/websites/100215-jack-and-jill-where-remarkable-people-meet-ambitious-companies |
| pass3_01_land-book_home | failed | 19.8 | — | — | — | browserctl app-tabs: connect() failed for /Users/harshitduggal/Library/Containers/dev.aether.browser/Data/tmp/aether-agent/browser.sock

browserctl --app app-status
browserctl --app app-tabs
browserctl --app app-open <url>
browserctl --app app-navigate <tab-uuid> <url>
browserctl --app app-select\|app-close\|app-back\|app-forward\|app-reload\|app-metrics <tab-uuid>
Use --app in place of --socket <path> for any command against the running app. No token required.
Optional authenticated daemon connections: browserctl --socket <path> --token-file <path> <command> [arguments]
browserctl inspect <url>
browserctl render <url> <output.ppm\|output.png> [width] [height]
browserctl eval <url> <javascript>
browserctl shell <url>
browserctl capture <url> <output-dir> [capture-flags]
browserctl --socket <path> ping
browserctl --socket <path> context-create <name>
browserctl --socket <path> context-list
browserctl --socket <path> page-open <context> <url> [commit\|complete]
browserctl --socket <path> page-navigate <page> <url> [commit\|complete]
browserctl --socket <path> page-navigate-input <page> <url-or-search-terms> [--commit\|--complete]
browserctl --socket <path> page-inspect <page>
browserctl --socket <path> page-snapshot <page> [limit]
browserctl --socket <path> page-query <page> <selector>
browserctl --socket <path> page-query-all <page> <selector>
browserctl --socket <path> page-find <page> <text>
browserctl --socket <path> page-wait <page> <selector> [attached\|visible\|hidden\|detached] [timeout-ms]
browserctl --socket <path> page-back <page> [--commit\|--complete]
browserctl --socket <path> page-forward <page> [--commit\|--complete]
browserctl --socket <path> page-reload <page> [--bypass-cache] [--commit\|--complete]
browserctl --socket <path> page-resize <page> <width> <height>
browserctl --socket <path> page-mutations <page> [since-version]
browserctl --socket <path> page-click <page> <node-index> <generation>
browserctl --socket <path> page-type <page> <node-index> <generation> <text>
browserctl --socket <path> page-set-value <page> <node-index> <generation> <value>
browserctl --socket <path> page-eval <page> <javascript>
browserctl --socket <path> page-render <page> <path>
browserctl --socket <path> page-metrics <page>
browserctl --socket <path> context-destroy <context>
browserctl --socket <path> page-create <context> [width height]
browserctl --socket <path> page-close <page>
browserctl --socket <path> page-list <context>
browserctl --socket <path> page-load-html <page> <url> <html>
browserctl --socket <path> page-lifecycle <page>
browserctl --socket <path> page-set-lifecycle <page> <active\|background\|suspended\|frozen\|discarded>
browserctl --socket <path> page-restore <page>
browserctl --socket <path> page-hover <page> <node-index> <generation>
browserctl --socket <path> page-focus <page> <node-index> <generation>
browserctl --socket <path> page-blur <page>
browserctl --socket <path> page-focused <page>
browserctl --socket <path> page-hovered <page>
browserctl --socket <path> page-scroll <page> <x> <y>
browserctl --socket <path> page-scroll-offset <page>
browserctl --socket <path> page-scroll-into-view <page> <node-index> <generation>
browserctl --socket <path> page-node-at-point <page> <x> <y>
browserctl --socket <path> page-press-key <page> <key>
browserctl --socket <path> page-select-option <page> <node-index> <generation> <value>
browserctl --socket <path> page-fill <page> <node-index> <generation> <value>
browserctl --socket <path> page-submit <page> <node-index> <generation>
browserctl --socket <path> page-history <page>
browserctl --socket <path> page-console <page>
browserctl --socket <path> page-network-log <page>
browserctl --socket <path> page-frame <page>
browserctl --socket <path> page-workers <page>
browserctl --socket <path> page-dialogs <page>
browserctl --socket <path> page-media <page>
browserctl --socket <path> page-media-control <page> <nodeIndex> <nodeGeneration> <play\|pause\|seek\|setVolume\|setMuted\|setRate\|load> [number] [--muted]
browserctl --socket <path> dialog-resolve <dialog> [--accept]
browserctl --socket <path> context-cookies <context>
browserctl --socket <path> context-set-cookie <context> <name> <value> <domain> [path]
browserctl --socket <path> context-remove-cookie <context> <name> <domain> [path]
browserctl --socket <path> context-clear-cookies <context>
browserctl --socket <path> context-storage-origins <context>
browserctl --socket <path> context-storage-values <context> <origin>
browserctl --socket <path> context-storage-set <context> <origin> <key> <value>
browserctl --socket <path> context-storage-clear <context> <origin>
browserctl --socket <path> context-permission <context> <permission> <origin>
browserctl --socket <path> context-set-permission <context> <permission> <origin> <allow\|deny\|prompt>
browserctl --socket <path> context-permissions <context>
browserctl --socket <path> context-download <context> <url> [path]
browserctl --socket <path> context-downloads <context>
browserctl --socket <path> context-clear-downloads <context>
browserctl --socket <path> context-open-profile <context> <directory>
browserctl --socket <path> context-checkpoint <context>
browserctl --socket <path> context-blocking <context> <on\|off> [rules...]
browserctl --socket <path> context-profile-usage <context>
browserctl --socket <path> context-bookmark-add <context> <url> [title]
browserctl --socket <path> context-bookmarks <context>
browserctl --socket <path> context-bookmark-remove <context> <url>
browserctl --socket <path> context-suggest <context> <prefix> [limit] [--local]
browserctl --socket <path> context-search-provider <context>
browserctl --socket <path> context-set-search-provider <context> <endpoint>
browserctl --socket <path> session-create <name>
browserctl --socket <path> session-list
browserctl --socket <path> session-destroy <session>
browserctl --socket <path> session-pages <session>
browserctl --socket <path> fleet-stats
browserctl --socket <path> fleet-pages
browserctl --socket <path> fleet-sweep [max-active] [memory-budget-bytes]
browserctl --socket <path> page-capture <url> <output-dir> [capture-flags]
capture-flags: [--format webp\|jpeg\|png] [--quality 0..1] [--width N] [--height N]
  [--max-steps N] [--no-assets] [--no-computed-styles] [--no-sections] [--no-redact] |
| pass3_01_land-book_route | failed | — | — | — | — | browserctl app-navigate 8646C022-7FE9-4057-802A-53F48F452E3F https://land-book.com/websites/100215-jack-and-jill-where-remarkable-people-meet-ambitious-companies: connect() failed for /Users/harshitduggal/Library/Containers/dev.aether.browser/Data/tmp/aether-agent/browser.sock

browserctl --app app-status
browserctl --app app-tabs
browserctl --app app-open <url>
browserctl --app app-navigate <tab-uuid> <url>
browserctl --app app-select\|app-close\|app-back\|app-forward\|app-reload\|app-metrics <tab-uuid>
Use --app in place of --socket <path> for any command against the running app. No token required.
Optional authenticated daemon connections: browserctl --socket <path> --token-file <path> <command> [arguments]
browserctl inspect <url>
browserctl render <url> <output.ppm\|output.png> [width] [height]
browserctl eval <url> <javascript>
browserctl shell <url>
browserctl capture <url> <output-dir> [capture-flags]
browserctl --socket <path> ping
browserctl --socket <path> context-create <name>
browserctl --socket <path> context-list
browserctl --socket <path> page-open <context> <url> [commit\|complete]
browserctl --socket <path> page-navigate <page> <url> [commit\|complete]
browserctl --socket <path> page-navigate-input <page> <url-or-search-terms> [--commit\|--complete]
browserctl --socket <path> page-inspect <page>
browserctl --socket <path> page-snapshot <page> [limit]
browserctl --socket <path> page-query <page> <selector>
browserctl --socket <path> page-query-all <page> <selector>
browserctl --socket <path> page-find <page> <text>
browserctl --socket <path> page-wait <page> <selector> [attached\|visible\|hidden\|detached] [timeout-ms]
browserctl --socket <path> page-back <page> [--commit\|--complete]
browserctl --socket <path> page-forward <page> [--commit\|--complete]
browserctl --socket <path> page-reload <page> [--bypass-cache] [--commit\|--complete]
browserctl --socket <path> page-resize <page> <width> <height>
browserctl --socket <path> page-mutations <page> [since-version]
browserctl --socket <path> page-click <page> <node-index> <generation>
browserctl --socket <path> page-type <page> <node-index> <generation> <text>
browserctl --socket <path> page-set-value <page> <node-index> <generation> <value>
browserctl --socket <path> page-eval <page> <javascript>
browserctl --socket <path> page-render <page> <path>
browserctl --socket <path> page-metrics <page>
browserctl --socket <path> context-destroy <context>
browserctl --socket <path> page-create <context> [width height]
browserctl --socket <path> page-close <page>
browserctl --socket <path> page-list <context>
browserctl --socket <path> page-load-html <page> <url> <html>
browserctl --socket <path> page-lifecycle <page>
browserctl --socket <path> page-set-lifecycle <page> <active\|background\|suspended\|frozen\|discarded>
browserctl --socket <path> page-restore <page>
browserctl --socket <path> page-hover <page> <node-index> <generation>
browserctl --socket <path> page-focus <page> <node-index> <generation>
browserctl --socket <path> page-blur <page>
browserctl --socket <path> page-focused <page>
browserctl --socket <path> page-hovered <page>
browserctl --socket <path> page-scroll <page> <x> <y>
browserctl --socket <path> page-scroll-offset <page>
browserctl --socket <path> page-scroll-into-view <page> <node-index> <generation>
browserctl --socket <path> page-node-at-point <page> <x> <y>
browserctl --socket <path> page-press-key <page> <key>
browserctl --socket <path> page-select-option <page> <node-index> <generation> <value>
browserctl --socket <path> page-fill <page> <node-index> <generation> <value>
browserctl --socket <path> page-submit <page> <node-index> <generation>
browserctl --socket <path> page-history <page>
browserctl --socket <path> page-console <page>
browserctl --socket <path> page-network-log <page>
browserctl --socket <path> page-frame <page>
browserctl --socket <path> page-workers <page>
browserctl --socket <path> page-dialogs <page>
browserctl --socket <path> page-media <page>
browserctl --socket <path> page-media-control <page> <nodeIndex> <nodeGeneration> <play\|pause\|seek\|setVolume\|setMuted\|setRate\|load> [number] [--muted]
browserctl --socket <path> dialog-resolve <dialog> [--accept]
browserctl --socket <path> context-cookies <context>
browserctl --socket <path> context-set-cookie <context> <name> <value> <domain> [path]
browserctl --socket <path> context-remove-cookie <context> <name> <domain> [path]
browserctl --socket <path> context-clear-cookies <context>
browserctl --socket <path> context-storage-origins <context>
browserctl --socket <path> context-storage-values <context> <origin>
browserctl --socket <path> context-storage-set <context> <origin> <key> <value>
browserctl --socket <path> context-storage-clear <context> <origin>
browserctl --socket <path> context-permission <context> <permission> <origin>
browserctl --socket <path> context-set-permission <context> <permission> <origin> <allow\|deny\|prompt>
browserctl --socket <path> context-permissions <context>
browserctl --socket <path> context-download <context> <url> [path]
browserctl --socket <path> context-downloads <context>
browserctl --socket <path> context-clear-downloads <context>
browserctl --socket <path> context-open-profile <context> <directory>
browserctl --socket <path> context-checkpoint <context>
browserctl --socket <path> context-blocking <context> <on\|off> [rules...]
browserctl --socket <path> context-profile-usage <context>
browserctl --socket <path> context-bookmark-add <context> <url> [title]
browserctl --socket <path> context-bookmarks <context>
browserctl --socket <path> context-bookmark-remove <context> <url>
browserctl --socket <path> context-suggest <context> <prefix> [limit] [--local]
browserctl --socket <path> context-search-provider <context>
browserctl --socket <path> context-set-search-provider <context> <endpoint>
browserctl --socket <path> session-create <name>
browserctl --socket <path> session-list
browserctl --socket <path> session-destroy <session>
browserctl --socket <path> session-pages <session>
browserctl --socket <path> fleet-stats
browserctl --socket <path> fleet-pages
browserctl --socket <path> fleet-sweep [max-active] [memory-budget-bytes]
browserctl --socket <path> page-capture <url> <output-dir> [capture-flags]
capture-flags: [--format webp\|jpeg\|png] [--quality 0..1] [--width N] [--height N]
  [--max-steps N] [--no-assets] [--no-computed-styles] [--no-sections] [--no-redact] |
| pass4_01_land-book_home | failed | — | — | — | — | browserctl app-navigate 8646C022-7FE9-4057-802A-53F48F452E3F https://land-book.com/: connect() failed for /Users/harshitduggal/Library/Containers/dev.aether.browser/Data/tmp/aether-agent/browser.sock

browserctl --app app-status
browserctl --app app-tabs
browserctl --app app-open <url>
browserctl --app app-navigate <tab-uuid> <url>
browserctl --app app-select\|app-close\|app-back\|app-forward\|app-reload\|app-metrics <tab-uuid>
Use --app in place of --socket <path> for any command against the running app. No token required.
Optional authenticated daemon connections: browserctl --socket <path> --token-file <path> <command> [arguments]
browserctl inspect <url>
browserctl render <url> <output.ppm\|output.png> [width] [height]
browserctl eval <url> <javascript>
browserctl shell <url>
browserctl capture <url> <output-dir> [capture-flags]
browserctl --socket <path> ping
browserctl --socket <path> context-create <name>
browserctl --socket <path> context-list
browserctl --socket <path> page-open <context> <url> [commit\|complete]
browserctl --socket <path> page-navigate <page> <url> [commit\|complete]
browserctl --socket <path> page-navigate-input <page> <url-or-search-terms> [--commit\|--complete]
browserctl --socket <path> page-inspect <page>
browserctl --socket <path> page-snapshot <page> [limit]
browserctl --socket <path> page-query <page> <selector>
browserctl --socket <path> page-query-all <page> <selector>
browserctl --socket <path> page-find <page> <text>
browserctl --socket <path> page-wait <page> <selector> [attached\|visible\|hidden\|detached] [timeout-ms]
browserctl --socket <path> page-back <page> [--commit\|--complete]
browserctl --socket <path> page-forward <page> [--commit\|--complete]
browserctl --socket <path> page-reload <page> [--bypass-cache] [--commit\|--complete]
browserctl --socket <path> page-resize <page> <width> <height>
browserctl --socket <path> page-mutations <page> [since-version]
browserctl --socket <path> page-click <page> <node-index> <generation>
browserctl --socket <path> page-type <page> <node-index> <generation> <text>
browserctl --socket <path> page-set-value <page> <node-index> <generation> <value>
browserctl --socket <path> page-eval <page> <javascript>
browserctl --socket <path> page-render <page> <path>
browserctl --socket <path> page-metrics <page>
browserctl --socket <path> context-destroy <context>
browserctl --socket <path> page-create <context> [width height]
browserctl --socket <path> page-close <page>
browserctl --socket <path> page-list <context>
browserctl --socket <path> page-load-html <page> <url> <html>
browserctl --socket <path> page-lifecycle <page>
browserctl --socket <path> page-set-lifecycle <page> <active\|background\|suspended\|frozen\|discarded>
browserctl --socket <path> page-restore <page>
browserctl --socket <path> page-hover <page> <node-index> <generation>
browserctl --socket <path> page-focus <page> <node-index> <generation>
browserctl --socket <path> page-blur <page>
browserctl --socket <path> page-focused <page>
browserctl --socket <path> page-hovered <page>
browserctl --socket <path> page-scroll <page> <x> <y>
browserctl --socket <path> page-scroll-offset <page>
browserctl --socket <path> page-scroll-into-view <page> <node-index> <generation>
browserctl --socket <path> page-node-at-point <page> <x> <y>
browserctl --socket <path> page-press-key <page> <key>
browserctl --socket <path> page-select-option <page> <node-index> <generation> <value>
browserctl --socket <path> page-fill <page> <node-index> <generation> <value>
browserctl --socket <path> page-submit <page> <node-index> <generation>
browserctl --socket <path> page-history <page>
browserctl --socket <path> page-console <page>
browserctl --socket <path> page-network-log <page>
browserctl --socket <path> page-frame <page>
browserctl --socket <path> page-workers <page>
browserctl --socket <path> page-dialogs <page>
browserctl --socket <path> page-media <page>
browserctl --socket <path> page-media-control <page> <nodeIndex> <nodeGeneration> <play\|pause\|seek\|setVolume\|setMuted\|setRate\|load> [number] [--muted]
browserctl --socket <path> dialog-resolve <dialog> [--accept]
browserctl --socket <path> context-cookies <context>
browserctl --socket <path> context-set-cookie <context> <name> <value> <domain> [path]
browserctl --socket <path> context-remove-cookie <context> <name> <domain> [path]
browserctl --socket <path> context-clear-cookies <context>
browserctl --socket <path> context-storage-origins <context>
browserctl --socket <path> context-storage-values <context> <origin>
browserctl --socket <path> context-storage-set <context> <origin> <key> <value>
browserctl --socket <path> context-storage-clear <context> <origin>
browserctl --socket <path> context-permission <context> <permission> <origin>
browserctl --socket <path> context-set-permission <context> <permission> <origin> <allow\|deny\|prompt>
browserctl --socket <path> context-permissions <context>
browserctl --socket <path> context-download <context> <url> [path]
browserctl --socket <path> context-downloads <context>
browserctl --socket <path> context-clear-downloads <context>
browserctl --socket <path> context-open-profile <context> <directory>
browserctl --socket <path> context-checkpoint <context>
browserctl --socket <path> context-blocking <context> <on\|off> [rules...]
browserctl --socket <path> context-profile-usage <context>
browserctl --socket <path> context-bookmark-add <context> <url> [title]
browserctl --socket <path> context-bookmarks <context>
browserctl --socket <path> context-bookmark-remove <context> <url>
browserctl --socket <path> context-suggest <context> <prefix> [limit] [--local]
browserctl --socket <path> context-search-provider <context>
browserctl --socket <path> context-set-search-provider <context> <endpoint>
browserctl --socket <path> session-create <name>
browserctl --socket <path> session-list
browserctl --socket <path> session-destroy <session>
browserctl --socket <path> session-pages <session>
browserctl --socket <path> fleet-stats
browserctl --socket <path> fleet-pages
browserctl --socket <path> fleet-sweep [max-active] [memory-budget-bytes]
browserctl --socket <path> page-capture <url> <output-dir> [capture-flags]
capture-flags: [--format webp\|jpeg\|png] [--quality 0..1] [--width N] [--height N]
  [--max-steps N] [--no-assets] [--no-computed-styles] [--no-sections] [--no-redact] |
| pass4_01_land-book_route | failed | — | — | — | — | browserctl app-navigate 8646C022-7FE9-4057-802A-53F48F452E3F https://land-book.com/websites/100215-jack-and-jill-where-remarkable-people-meet-ambitious-companies: connect() failed for /Users/harshitduggal/Library/Containers/dev.aether.browser/Data/tmp/aether-agent/browser.sock

browserctl --app app-status
browserctl --app app-tabs
browserctl --app app-open <url>
browserctl --app app-navigate <tab-uuid> <url>
browserctl --app app-select\|app-close\|app-back\|app-forward\|app-reload\|app-metrics <tab-uuid>
Use --app in place of --socket <path> for any command against the running app. No token required.
Optional authenticated daemon connections: browserctl --socket <path> --token-file <path> <command> [arguments]
browserctl inspect <url>
browserctl render <url> <output.ppm\|output.png> [width] [height]
browserctl eval <url> <javascript>
browserctl shell <url>
browserctl capture <url> <output-dir> [capture-flags]
browserctl --socket <path> ping
browserctl --socket <path> context-create <name>
browserctl --socket <path> context-list
browserctl --socket <path> page-open <context> <url> [commit\|complete]
browserctl --socket <path> page-navigate <page> <url> [commit\|complete]
browserctl --socket <path> page-navigate-input <page> <url-or-search-terms> [--commit\|--complete]
browserctl --socket <path> page-inspect <page>
browserctl --socket <path> page-snapshot <page> [limit]
browserctl --socket <path> page-query <page> <selector>
browserctl --socket <path> page-query-all <page> <selector>
browserctl --socket <path> page-find <page> <text>
browserctl --socket <path> page-wait <page> <selector> [attached\|visible\|hidden\|detached] [timeout-ms]
browserctl --socket <path> page-back <page> [--commit\|--complete]
browserctl --socket <path> page-forward <page> [--commit\|--complete]
browserctl --socket <path> page-reload <page> [--bypass-cache] [--commit\|--complete]
browserctl --socket <path> page-resize <page> <width> <height>
browserctl --socket <path> page-mutations <page> [since-version]
browserctl --socket <path> page-click <page> <node-index> <generation>
browserctl --socket <path> page-type <page> <node-index> <generation> <text>
browserctl --socket <path> page-set-value <page> <node-index> <generation> <value>
browserctl --socket <path> page-eval <page> <javascript>
browserctl --socket <path> page-render <page> <path>
browserctl --socket <path> page-metrics <page>
browserctl --socket <path> context-destroy <context>
browserctl --socket <path> page-create <context> [width height]
browserctl --socket <path> page-close <page>
browserctl --socket <path> page-list <context>
browserctl --socket <path> page-load-html <page> <url> <html>
browserctl --socket <path> page-lifecycle <page>
browserctl --socket <path> page-set-lifecycle <page> <active\|background\|suspended\|frozen\|discarded>
browserctl --socket <path> page-restore <page>
browserctl --socket <path> page-hover <page> <node-index> <generation>
browserctl --socket <path> page-focus <page> <node-index> <generation>
browserctl --socket <path> page-blur <page>
browserctl --socket <path> page-focused <page>
browserctl --socket <path> page-hovered <page>
browserctl --socket <path> page-scroll <page> <x> <y>
browserctl --socket <path> page-scroll-offset <page>
browserctl --socket <path> page-scroll-into-view <page> <node-index> <generation>
browserctl --socket <path> page-node-at-point <page> <x> <y>
browserctl --socket <path> page-press-key <page> <key>
browserctl --socket <path> page-select-option <page> <node-index> <generation> <value>
browserctl --socket <path> page-fill <page> <node-index> <generation> <value>
browserctl --socket <path> page-submit <page> <node-index> <generation>
browserctl --socket <path> page-history <page>
browserctl --socket <path> page-console <page>
browserctl --socket <path> page-network-log <page>
browserctl --socket <path> page-frame <page>
browserctl --socket <path> page-workers <page>
browserctl --socket <path> page-dialogs <page>
browserctl --socket <path> page-media <page>
browserctl --socket <path> page-media-control <page> <nodeIndex> <nodeGeneration> <play\|pause\|seek\|setVolume\|setMuted\|setRate\|load> [number] [--muted]
browserctl --socket <path> dialog-resolve <dialog> [--accept]
browserctl --socket <path> context-cookies <context>
browserctl --socket <path> context-set-cookie <context> <name> <value> <domain> [path]
browserctl --socket <path> context-remove-cookie <context> <name> <domain> [path]
browserctl --socket <path> context-clear-cookies <context>
browserctl --socket <path> context-storage-origins <context>
browserctl --socket <path> context-storage-values <context> <origin>
browserctl --socket <path> context-storage-set <context> <origin> <key> <value>
browserctl --socket <path> context-storage-clear <context> <origin>
browserctl --socket <path> context-permission <context> <permission> <origin>
browserctl --socket <path> context-set-permission <context> <permission> <origin> <allow\|deny\|prompt>
browserctl --socket <path> context-permissions <context>
browserctl --socket <path> context-download <context> <url> [path]
browserctl --socket <path> context-downloads <context>
browserctl --socket <path> context-clear-downloads <context>
browserctl --socket <path> context-open-profile <context> <directory>
browserctl --socket <path> context-checkpoint <context>
browserctl --socket <path> context-blocking <context> <on\|off> [rules...]
browserctl --socket <path> context-profile-usage <context>
browserctl --socket <path> context-bookmark-add <context> <url> [title]
browserctl --socket <path> context-bookmarks <context>
browserctl --socket <path> context-bookmark-remove <context> <url>
browserctl --socket <path> context-suggest <context> <prefix> [limit] [--local]
browserctl --socket <path> context-search-provider <context>
browserctl --socket <path> context-set-search-provider <context> <endpoint>
browserctl --socket <path> session-create <name>
browserctl --socket <path> session-list
browserctl --socket <path> session-destroy <session>
browserctl --socket <path> session-pages <session>
browserctl --socket <path> fleet-stats
browserctl --socket <path> fleet-pages
browserctl --socket <path> fleet-sweep [max-active] [memory-budget-bytes]
browserctl --socket <path> page-capture <url> <output-dir> [capture-flags]
capture-flags: [--format webp\|jpeg\|png] [--quality 0..1] [--width N] [--height N]
  [--max-steps N] [--no-assets] [--no-computed-styles] [--no-sections] [--no-redact] |
| pass5_01_land-book_home | failed | — | — | — | — | browserctl app-navigate 8646C022-7FE9-4057-802A-53F48F452E3F https://land-book.com/: connect() failed for /Users/harshitduggal/Library/Containers/dev.aether.browser/Data/tmp/aether-agent/browser.sock

browserctl --app app-status
browserctl --app app-tabs
browserctl --app app-open <url>
browserctl --app app-navigate <tab-uuid> <url>
browserctl --app app-select\|app-close\|app-back\|app-forward\|app-reload\|app-metrics <tab-uuid>
Use --app in place of --socket <path> for any command against the running app. No token required.
Optional authenticated daemon connections: browserctl --socket <path> --token-file <path> <command> [arguments]
browserctl inspect <url>
browserctl render <url> <output.ppm\|output.png> [width] [height]
browserctl eval <url> <javascript>
browserctl shell <url>
browserctl capture <url> <output-dir> [capture-flags]
browserctl --socket <path> ping
browserctl --socket <path> context-create <name>
browserctl --socket <path> context-list
browserctl --socket <path> page-open <context> <url> [commit\|complete]
browserctl --socket <path> page-navigate <page> <url> [commit\|complete]
browserctl --socket <path> page-navigate-input <page> <url-or-search-terms> [--commit\|--complete]
browserctl --socket <path> page-inspect <page>
browserctl --socket <path> page-snapshot <page> [limit]
browserctl --socket <path> page-query <page> <selector>
browserctl --socket <path> page-query-all <page> <selector>
browserctl --socket <path> page-find <page> <text>
browserctl --socket <path> page-wait <page> <selector> [attached\|visible\|hidden\|detached] [timeout-ms]
browserctl --socket <path> page-back <page> [--commit\|--complete]
browserctl --socket <path> page-forward <page> [--commit\|--complete]
browserctl --socket <path> page-reload <page> [--bypass-cache] [--commit\|--complete]
browserctl --socket <path> page-resize <page> <width> <height>
browserctl --socket <path> page-mutations <page> [since-version]
browserctl --socket <path> page-click <page> <node-index> <generation>
browserctl --socket <path> page-type <page> <node-index> <generation> <text>
browserctl --socket <path> page-set-value <page> <node-index> <generation> <value>
browserctl --socket <path> page-eval <page> <javascript>
browserctl --socket <path> page-render <page> <path>
browserctl --socket <path> page-metrics <page>
browserctl --socket <path> context-destroy <context>
browserctl --socket <path> page-create <context> [width height]
browserctl --socket <path> page-close <page>
browserctl --socket <path> page-list <context>
browserctl --socket <path> page-load-html <page> <url> <html>
browserctl --socket <path> page-lifecycle <page>
browserctl --socket <path> page-set-lifecycle <page> <active\|background\|suspended\|frozen\|discarded>
browserctl --socket <path> page-restore <page>
browserctl --socket <path> page-hover <page> <node-index> <generation>
browserctl --socket <path> page-focus <page> <node-index> <generation>
browserctl --socket <path> page-blur <page>
browserctl --socket <path> page-focused <page>
browserctl --socket <path> page-hovered <page>
browserctl --socket <path> page-scroll <page> <x> <y>
browserctl --socket <path> page-scroll-offset <page>
browserctl --socket <path> page-scroll-into-view <page> <node-index> <generation>
browserctl --socket <path> page-node-at-point <page> <x> <y>
browserctl --socket <path> page-press-key <page> <key>
browserctl --socket <path> page-select-option <page> <node-index> <generation> <value>
browserctl --socket <path> page-fill <page> <node-index> <generation> <value>
browserctl --socket <path> page-submit <page> <node-index> <generation>
browserctl --socket <path> page-history <page>
browserctl --socket <path> page-console <page>
browserctl --socket <path> page-network-log <page>
browserctl --socket <path> page-frame <page>
browserctl --socket <path> page-workers <page>
browserctl --socket <path> page-dialogs <page>
browserctl --socket <path> page-media <page>
browserctl --socket <path> page-media-control <page> <nodeIndex> <nodeGeneration> <play\|pause\|seek\|setVolume\|setMuted\|setRate\|load> [number] [--muted]
browserctl --socket <path> dialog-resolve <dialog> [--accept]
browserctl --socket <path> context-cookies <context>
browserctl --socket <path> context-set-cookie <context> <name> <value> <domain> [path]
browserctl --socket <path> context-remove-cookie <context> <name> <domain> [path]
browserctl --socket <path> context-clear-cookies <context>
browserctl --socket <path> context-storage-origins <context>
browserctl --socket <path> context-storage-values <context> <origin>
browserctl --socket <path> context-storage-set <context> <origin> <key> <value>
browserctl --socket <path> context-storage-clear <context> <origin>
browserctl --socket <path> context-permission <context> <permission> <origin>
browserctl --socket <path> context-set-permission <context> <permission> <origin> <allow\|deny\|prompt>
browserctl --socket <path> context-permissions <context>
browserctl --socket <path> context-download <context> <url> [path]
browserctl --socket <path> context-downloads <context>
browserctl --socket <path> context-clear-downloads <context>
browserctl --socket <path> context-open-profile <context> <directory>
browserctl --socket <path> context-checkpoint <context>
browserctl --socket <path> context-blocking <context> <on\|off> [rules...]
browserctl --socket <path> context-profile-usage <context>
browserctl --socket <path> context-bookmark-add <context> <url> [title]
browserctl --socket <path> context-bookmarks <context>
browserctl --socket <path> context-bookmark-remove <context> <url>
browserctl --socket <path> context-suggest <context> <prefix> [limit] [--local]
browserctl --socket <path> context-search-provider <context>
browserctl --socket <path> context-set-search-provider <context> <endpoint>
browserctl --socket <path> session-create <name>
browserctl --socket <path> session-list
browserctl --socket <path> session-destroy <session>
browserctl --socket <path> session-pages <session>
browserctl --socket <path> fleet-stats
browserctl --socket <path> fleet-pages
browserctl --socket <path> fleet-sweep [max-active] [memory-budget-bytes]
browserctl --socket <path> page-capture <url> <output-dir> [capture-flags]
capture-flags: [--format webp\|jpeg\|png] [--quality 0..1] [--width N] [--height N]
  [--max-steps N] [--no-assets] [--no-computed-styles] [--no-sections] [--no-redact] |
| pass5_01_land-book_route | failed | — | — | — | — | browserctl app-navigate 8646C022-7FE9-4057-802A-53F48F452E3F https://land-book.com/websites/100215-jack-and-jill-where-remarkable-people-meet-ambitious-companies: connect() failed for /Users/harshitduggal/Library/Containers/dev.aether.browser/Data/tmp/aether-agent/browser.sock

browserctl --app app-status
browserctl --app app-tabs
browserctl --app app-open <url>
browserctl --app app-navigate <tab-uuid> <url>
browserctl --app app-select\|app-close\|app-back\|app-forward\|app-reload\|app-metrics <tab-uuid>
Use --app in place of --socket <path> for any command against the running app. No token required.
Optional authenticated daemon connections: browserctl --socket <path> --token-file <path> <command> [arguments]
browserctl inspect <url>
browserctl render <url> <output.ppm\|output.png> [width] [height]
browserctl eval <url> <javascript>
browserctl shell <url>
browserctl capture <url> <output-dir> [capture-flags]
browserctl --socket <path> ping
browserctl --socket <path> context-create <name>
browserctl --socket <path> context-list
browserctl --socket <path> page-open <context> <url> [commit\|complete]
browserctl --socket <path> page-navigate <page> <url> [commit\|complete]
browserctl --socket <path> page-navigate-input <page> <url-or-search-terms> [--commit\|--complete]
browserctl --socket <path> page-inspect <page>
browserctl --socket <path> page-snapshot <page> [limit]
browserctl --socket <path> page-query <page> <selector>
browserctl --socket <path> page-query-all <page> <selector>
browserctl --socket <path> page-find <page> <text>
browserctl --socket <path> page-wait <page> <selector> [attached\|visible\|hidden\|detached] [timeout-ms]
browserctl --socket <path> page-back <page> [--commit\|--complete]
browserctl --socket <path> page-forward <page> [--commit\|--complete]
browserctl --socket <path> page-reload <page> [--bypass-cache] [--commit\|--complete]
browserctl --socket <path> page-resize <page> <width> <height>
browserctl --socket <path> page-mutations <page> [since-version]
browserctl --socket <path> page-click <page> <node-index> <generation>
browserctl --socket <path> page-type <page> <node-index> <generation> <text>
browserctl --socket <path> page-set-value <page> <node-index> <generation> <value>
browserctl --socket <path> page-eval <page> <javascript>
browserctl --socket <path> page-render <page> <path>
browserctl --socket <path> page-metrics <page>
browserctl --socket <path> context-destroy <context>
browserctl --socket <path> page-create <context> [width height]
browserctl --socket <path> page-close <page>
browserctl --socket <path> page-list <context>
browserctl --socket <path> page-load-html <page> <url> <html>
browserctl --socket <path> page-lifecycle <page>
browserctl --socket <path> page-set-lifecycle <page> <active\|background\|suspended\|frozen\|discarded>
browserctl --socket <path> page-restore <page>
browserctl --socket <path> page-hover <page> <node-index> <generation>
browserctl --socket <path> page-focus <page> <node-index> <generation>
browserctl --socket <path> page-blur <page>
browserctl --socket <path> page-focused <page>
browserctl --socket <path> page-hovered <page>
browserctl --socket <path> page-scroll <page> <x> <y>
browserctl --socket <path> page-scroll-offset <page>
browserctl --socket <path> page-scroll-into-view <page> <node-index> <generation>
browserctl --socket <path> page-node-at-point <page> <x> <y>
browserctl --socket <path> page-press-key <page> <key>
browserctl --socket <path> page-select-option <page> <node-index> <generation> <value>
browserctl --socket <path> page-fill <page> <node-index> <generation> <value>
browserctl --socket <path> page-submit <page> <node-index> <generation>
browserctl --socket <path> page-history <page>
browserctl --socket <path> page-console <page>
browserctl --socket <path> page-network-log <page>
browserctl --socket <path> page-frame <page>
browserctl --socket <path> page-workers <page>
browserctl --socket <path> page-dialogs <page>
browserctl --socket <path> page-media <page>
browserctl --socket <path> page-media-control <page> <nodeIndex> <nodeGeneration> <play\|pause\|seek\|setVolume\|setMuted\|setRate\|load> [number] [--muted]
browserctl --socket <path> dialog-resolve <dialog> [--accept]
browserctl --socket <path> context-cookies <context>
browserctl --socket <path> context-set-cookie <context> <name> <value> <domain> [path]
browserctl --socket <path> context-remove-cookie <context> <name> <domain> [path]
browserctl --socket <path> context-clear-cookies <context>
browserctl --socket <path> context-storage-origins <context>
browserctl --socket <path> context-storage-values <context> <origin>
browserctl --socket <path> context-storage-set <context> <origin> <key> <value>
browserctl --socket <path> context-storage-clear <context> <origin>
browserctl --socket <path> context-permission <context> <permission> <origin>
browserctl --socket <path> context-set-permission <context> <permission> <origin> <allow\|deny\|prompt>
browserctl --socket <path> context-permissions <context>
browserctl --socket <path> context-download <context> <url> [path]
browserctl --socket <path> context-downloads <context>
browserctl --socket <path> context-clear-downloads <context>
browserctl --socket <path> context-open-profile <context> <directory>
browserctl --socket <path> context-checkpoint <context>
browserctl --socket <path> context-blocking <context> <on\|off> [rules...]
browserctl --socket <path> context-profile-usage <context>
browserctl --socket <path> context-bookmark-add <context> <url> [title]
browserctl --socket <path> context-bookmarks <context>
browserctl --socket <path> context-bookmark-remove <context> <url>
browserctl --socket <path> context-suggest <context> <prefix> [limit] [--local]
browserctl --socket <path> context-search-provider <context>
browserctl --socket <path> context-set-search-provider <context> <endpoint>
browserctl --socket <path> session-create <name>
browserctl --socket <path> session-list
browserctl --socket <path> session-destroy <session>
browserctl --socket <path> session-pages <session>
browserctl --socket <path> fleet-stats
browserctl --socket <path> fleet-pages
browserctl --socket <path> fleet-sweep [max-active] [memory-budget-bytes]
browserctl --socket <path> page-capture <url> <output-dir> [capture-flags]
capture-flags: [--format webp\|jpeg\|png] [--quality 0..1] [--width N] [--height N]
  [--max-steps N] [--no-assets] [--no-computed-styles] [--no-sections] [--no-redact] |

Successful loads: median 27071.1 ms; p95 28408.1 ms; worst 28408.1 ms.

| Metric | Samples | Median ms | p95 ms | Worst ms |
| --- | ---: | ---: | ---: | ---: |
| dispatchMs | 3 | 24.6 | 37.5 | 37.5 |
| toReadyMs | 3 | 27071.1 | 28408.1 | 28408.1 |
| navigationStartDelayMs | 3 | 62.3 | 127.4 | 127.4 |
| requestStartMs | 3 | 4 | 7 | 7 |
| responseStartMs | 3 | 31 | 31 | 31 |
| responseEndMs | 3 | 26537 | 27996 | 27996 |
| fcpMs | 3 | 26823 | 28189 | 28189 |
| lcpMs | 0 | None | None | None |
| domContentLoadedMs | 3 | 27008 | 28196 | 28196 |
| loadEventEndMs | 2 | 26062.0 | 26974 | 26974 |

Ready requires the Aether ready state and reported FCP for the current document. FCP/LCP use the document navigation clock; ready time includes command dispatch and polling. Screenshots are captured after timing.
