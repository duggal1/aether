# Human browser integration

Base 896d939 plus the existing uncommitted BrowserUI, Metal, content blocker and protocol source snapshot. Preserve other-agent work; never replace the shared checkout. Read all 63 Swift files in BrowserUI (including manifest, preview and tests; approximately 2,856 lines excluding manifest) before implementation.

1. Root UI library and production app target, preserving components/materials.
2. BrowserRuntime presentation, navigation cancellation and live observation; no second runtime.
3. Profile-backed adapter, native Metal view/input, existing feature ports and app bundle.
4. Compile during implementation; run full tests and native launch/flow verification only after coding.
5. Report real-site/authentication/media limitations based on actual results.

Captured existing modifications:
- Aether/browser/frontend/PLAN.md
- Package.swift
- Sources/AgentProtocol/AgentAuth.swift
- Sources/AgentProtocol/AgentAuthority.swift
- Sources/AgentProtocol/AgentMessages.swift
- Sources/AgentProtocol/UnixSocket.swift
- Sources/BrowserUI/Documentation/DESIGN_AUDIT.md
- Sources/BrowserUI/Documentation/DesignSources/DESIGN.md
- Sources/BrowserUI/Documentation/DesignSources/ENHANCE-DESIGN.md
- Sources/BrowserUI/Documentation/ENHANCED_DESIGN.md
- Sources/BrowserUI/Documentation/INTEGRATION.md
- Sources/BrowserUI/Documentation/QA_CHECKLIST.md
- Sources/BrowserUI/Documentation/References/example-history.jpg
- Sources/BrowserUI/Documentation/References/example-profile-chnage.jpg
- Sources/BrowserUI/Documentation/References/example-settings.jpg
- Sources/BrowserUI/Documentation/References/example-sidebar-tabs.jpg
- Sources/BrowserUI/Documentation/References/history-open-dialog.jpg
- Sources/BrowserUI/Documentation/References/sidebar-tabs-1.jpg
- Sources/BrowserUI/Documentation/References/website-search.jpg
- Sources/BrowserUI/Package.swift
- Sources/BrowserUI/README.md
- Sources/BrowserUI/Sources/AetherHumanPreview/AetherHumanPreviewApp.swift
- Sources/BrowserUI/Sources/AetherHumanUI/Chrome/BrowserContentView.swift
- Sources/BrowserUI/Sources/AetherHumanUI/Chrome/BrowserWindowRoot.swift
- Sources/BrowserUI/Sources/AetherHumanUI/Chrome/BrowserWindowView.swift
- Sources/BrowserUI/Sources/AetherHumanUI/Chrome/FindBarView.swift
- Sources/BrowserUI/Sources/AetherHumanUI/Chrome/MoreMenuView.swift
- Sources/BrowserUI/Sources/AetherHumanUI/Chrome/NavigationBarView.swift
- Sources/BrowserUI/Sources/AetherHumanUI/Chrome/OmniboxView.swift
- Sources/BrowserUI/Sources/AetherHumanUI/Chrome/ProfileSwitcherView.swift
- Sources/BrowserUI/Sources/AetherHumanUI/Chrome/SidebarResizeHandle.swift
- Sources/BrowserUI/Sources/AetherHumanUI/Chrome/SidebarTabListView.swift
- Sources/BrowserUI/Sources/AetherHumanUI/Chrome/TabItemView.swift
- Sources/BrowserUI/Sources/AetherHumanUI/Chrome/TopTabStripView.swift
- Sources/BrowserUI/Sources/AetherHumanUI/Components/AetherEmptyState.swift
- Sources/BrowserUI/Sources/AetherHumanUI/Components/AetherField.swift
- Sources/BrowserUI/Sources/AetherHumanUI/Components/AetherRow.swift
- Sources/BrowserUI/Sources/AetherHumanUI/Components/ChromeButton.swift
- Sources/BrowserUI/Sources/AetherHumanUI/Components/DomainIcon.swift
- Sources/BrowserUI/Sources/AetherHumanUI/Components/HoverSurface.swift
- Sources/BrowserUI/Sources/AetherHumanUI/Design/AetherGlass.swift
- Sources/BrowserUI/Sources/AetherHumanUI/Design/AetherMaterial.swift
- Sources/BrowserUI/Sources/AetherHumanUI/Design/AetherMotion.swift
- Sources/BrowserUI/Sources/AetherHumanUI/Design/AetherPalette.swift
- Sources/BrowserUI/Sources/AetherHumanUI/Design/AetherTheme.swift
- Sources/BrowserUI/Sources/AetherHumanUI/Design/AetherTypography.swift
- Sources/BrowserUI/Sources/AetherHumanUI/Engine/BrowserEnginePort.swift
- Sources/BrowserUI/Sources/AetherHumanUI/Engine/BrowserFeaturePorts.swift
- Sources/BrowserUI/Sources/AetherHumanUI/Engine/DisconnectedEnginePort.swift
- Sources/BrowserUI/Sources/AetherHumanUI/Foundation/AddressResolver.swift
- Sources/BrowserUI/Sources/AetherHumanUI/Foundation/BookmarkTransfer.swift
- Sources/BrowserUI/Sources/AetherHumanUI/Foundation/BrowserPersistence.swift
- Sources/BrowserUI/Sources/AetherHumanUI/Models/BrowserModels.swift
- Sources/BrowserUI/Sources/AetherHumanUI/Models/BrowserTab.swift
- Sources/BrowserUI/Sources/AetherHumanUI/Native/BrowserCommands.swift
- Sources/BrowserUI/Sources/AetherHumanUI/Native/PersistentPageSurface.swift
- Sources/BrowserUI/Sources/AetherHumanUI/Pages/NewTabView.swift
- Sources/BrowserUI/Sources/AetherHumanUI/Pages/ShortcutEditor.swift
- Sources/BrowserUI/Sources/AetherHumanUI/Panels/BookmarksView.swift
- Sources/BrowserUI/Sources/AetherHumanUI/Panels/DownloadsView.swift
- Sources/BrowserUI/Sources/AetherHumanUI/Panels/HistoryView.swift
- Sources/BrowserUI/Sources/AetherHumanUI/Panels/InspectorView.swift
- Sources/BrowserUI/Sources/AetherHumanUI/Panels/ReaderView.swift
- Sources/BrowserUI/Sources/AetherHumanUI/Panels/TabSearchView.swift
- Sources/BrowserUI/Sources/AetherHumanUI/Settings/AdvancedSettingsView.swift
- Sources/BrowserUI/Sources/AetherHumanUI/Settings/AppearanceSettingsView.swift
- Sources/BrowserUI/Sources/AetherHumanUI/Settings/DownloadsSettingsView.swift
- Sources/BrowserUI/Sources/AetherHumanUI/Settings/GeneralSettingsView.swift
- Sources/BrowserUI/Sources/AetherHumanUI/Settings/PasswordsSettingsView.swift
- Sources/BrowserUI/Sources/AetherHumanUI/Settings/PrivacySettingsView.swift
- Sources/BrowserUI/Sources/AetherHumanUI/Settings/ProfilesSettingsView.swift
- Sources/BrowserUI/Sources/AetherHumanUI/Settings/SearchSettingsView.swift
- Sources/BrowserUI/Sources/AetherHumanUI/Settings/SettingsControls.swift
- Sources/BrowserUI/Sources/AetherHumanUI/Settings/SettingsSection.swift
- Sources/BrowserUI/Sources/AetherHumanUI/Settings/SettingsSidebarView.swift
- Sources/BrowserUI/Sources/AetherHumanUI/Settings/SettingsWindowView.swift
- Sources/BrowserUI/Sources/AetherHumanUI/Settings/ShortcutsSettingsView.swift
- Sources/BrowserUI/Sources/AetherHumanUI/Settings/TabsSettingsView.swift
- Sources/BrowserUI/Sources/AetherHumanUI/State/BrowserPreferences.swift
- Sources/BrowserUI/Sources/AetherHumanUI/State/BrowserWindowModel.swift
- Sources/BrowserUI/Sources/AetherHumanUI/State/BrowserWorkspace.swift
- Sources/BrowserUI/Tests/AetherHumanUITests/AddressResolverTests.swift
- Sources/BrowserUI/Tests/AetherHumanUITests/PersistenceTests.swift
- Sources/BrowserUI/Tests/AetherHumanUITests/WorkspaceTests.swift
- Sources/ContentBlocker/BlockerTypes.swift
- Sources/ContentBlocker/FilterEngine.swift
- Sources/ContentBlocker/FilterRule.swift
- Sources/EngineRuntime/RuntimeTypes.swift
- Sources/Graphics/MetalRenderer.swift
- Sources/browserd/main.swift
