import Foundation
import Observation

@MainActor @Observable
public final class BrowserWorkspace {
    public let preferences: BrowserPreferences
    public let engine: any BrowserEnginePort
    private let systemIntegrationsEnabled: Bool
    public private(set) var profiles: [BrowserProfile]
    public private(set) var bookmarks: [BrowserBookmark]
    public private(set) var visits: [BrowserVisit]
    public private(set) var shortcuts: [BrowserShortcut]
    public private(set) var defaultProfileID: UUID
    @ObservationIgnored private var libraryWrite: Task<Void, Never>?
    @ObservationIgnored private var spotlightWrite: Task<Void, Never>?
    @ObservationIgnored private let spotlight = SpotlightBookmarkIndex()
    @ObservationIgnored private let persistenceQueue = DispatchQueue(label: "aether.persistence", qos: .utility)
    public var persistenceError: String?
    public private(set) var windows: [BrowserWindowModel] = []

    public init(engine: any BrowserEnginePort, preferences: BrowserPreferences? = nil,
                systemIntegrationsEnabled: Bool = true) {
        self.engine = engine; self.preferences = preferences ?? BrowserPreferences()
        self.systemIntegrationsEnabled = systemIntegrationsEnabled
        let archive = BrowserPersistence.load()
        let all = archive.profiles.isEmpty ? [BrowserProfile(name: "Personal")] : archive.profiles
        profiles = all
        bookmarks = archive.bookmarks.filter { item in all.contains(where: { $0.id == item.profileID }) }
        visits = archive.visits.filter { item in all.contains(where: { $0.id == item.profileID }) }
        // A one-time migration: removing all shortcuts must not resurrect defaults.
        let shouldSeed = archive.shortcuts.isEmpty
            && !UserDefaults.standard.bool(forKey: "aether.shortcuts.seeded.v1")
        shortcuts = shouldSeed ? [
            BrowserShortcut(name: "YouTube", url: "https://www.youtube.com/"),
            BrowserShortcut(name: "Safari", url: "https://www.apple.com/safari/"),
            BrowserShortcut(name: "Slack", url: "https://slack.com/"),
            BrowserShortcut(name: "GitHub", url: "https://github.com/")
        ] : archive.shortcuts
        defaultProfileID = all.contains(where: { $0.id == archive.defaultProfileID }) ? archive.defaultProfileID! : all[0].id
        if shouldSeed {
            // Make the first launch durable before recording the migration flag.
            BrowserPersistence.save(BrowserArchive(profiles: all, bookmarks: bookmarks,
                visits: visits, shortcuts: shortcuts, defaultProfileID: defaultProfileID))
        }
        UserDefaults.standard.set(true, forKey: "aether.shortcuts.seeded.v1")
        syncSpotlight()
    }

    @ObservationIgnored private var sessionSaveArmed = false

    /// Asking for a save no longer builds one.
    ///
    /// Closing a tab asks for this once, so closing forty meant forty whole
    /// archives read on the main thread and forty whole-file writes queued
    /// behind them — work that grew with the list it was writing. The session
    /// is read at the moment it is written, so a burst of changes needs one
    /// write and not forty: the first caller arms the write, every later one is
    /// covered by it, and a change made while a write is in flight is picked up
    /// by the write that follows it. Nothing is lost, because the last change
    /// always leaves an armed write behind it.
    public func scheduleSessionSave() {
        guard !sessionSaveArmed else { return }
        sessionSaveArmed = true
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard let self, self.sessionSaveArmed else { return }
            self.sessionSaveArmed = false
            let archive = self.sessionArchive()
            self.persistenceQueue.async {
                BrowserPersistence.saveSession(archive)
            }
        }
    }

    public func flushSession() {
        // An armed write is now unnecessary rather than cancelled: whatever it
        // would have read, this reads later and writes last.
        sessionSaveArmed = false
        let archive = sessionArchive()
        persistenceQueue.sync {
            BrowserPersistence.saveSession(archive)
        }
    }

    public func sessionArchive() -> BrowserSessionArchive {
        let incognitoIDs = Set(profiles.filter(\.isIncognito).map(\.id))
        let knownIDs = Set(profiles.map(\.id))
        return BrowserSessionArchive(windows: windows.map { window in
            BrowserSessionWindow(
                id: window.id,
                activeProfileID: window.activeProfileID,
                arrangement: preferences.arrangement,
                sidebarCollapsed: window.sidebarCollapsed,
                selectedByProfile: window.selectionByProfile.filter { knownIDs.contains($0.key) },
                tabs: window.tabsByProfile
                    .filter { knownIDs.contains($0.key) && !incognitoIDs.contains($0.key) }
                    .flatMap { $0.value }
                    .compactMap(BrowserSessionTab.init(tab:)))
        })
    }

    public func savedSession() -> BrowserSessionArchive { BrowserPersistence.loadSession() }

    public func syncSearchKeysToEngine() async {
        guard let intelligence = engine as? any BrowserSearchIntelligence else { return }
        await intelligence.jevUpdateKeys(typeSafeKey: preferences.typeSafeAPIKey,
                                         search1APIKey: preferences.search1APIKey)
    }

    public func loadEngineLibraries() async {
        guard let provider = engine as? any BrowserLibraryProviding else { return }
        for profile in profiles {
            do {
                if let library = try await provider.loadLibrary(profileID: profile.id) {
                    bookmarks.removeAll { $0.profileID == profile.id }
                    visits.removeAll { $0.profileID == profile.id }
                    bookmarks += library.bookmarks.filter { $0.profileID == profile.id }
                    visits += library.visits.filter { $0.profileID == profile.id }
                }
            } catch { persistenceError = error.localizedDescription }
        }
        visits.sort { $0.visitedAt > $1.visitedAt }
        syncSpotlight()
    }

    public func addWindow(_ window: BrowserWindowModel) { windows.append(window) }
    public func removeWindow(_ id: UUID) { windows.removeAll { $0.id == id } }
    public func name(for profileID: UUID) -> String { profiles.first(where: { $0.id == profileID })?.name ?? "Personal" }
    public func createProfile(_ raw: String, colorIndex: Int = -1) -> BrowserProfile {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let profile = BrowserProfile(name: trimmed.isEmpty ? "New Profile" : trimmed, colorIndex: colorIndex)
        profiles.append(profile); persist(); return profile
    }
    public func renameProfile(_ id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = profiles.firstIndex(where: { $0.id == id }) else { return }
        profiles[index].name = trimmed; persist()
    }
    @discardableResult public func deleteProfile(_ id: UUID) -> Bool {
        guard profiles.count > 1, profiles.contains(where: { $0.id == id }) else { return false }
        let next = profiles.first(where: { $0.id != id })!.id
        for window in windows { window.removeProfile(id, switchTo: next) }
        if let provider = engine as? any BrowserProfileManaging {
            let previous = libraryWrite
            libraryWrite = Task {
                await previous?.value
                do { try await provider.deleteProfile(profileID: id) }
                catch { persistenceError = error.localizedDescription }
            }
        }
        profiles.removeAll { $0.id == id }
        bookmarks.removeAll { $0.profileID == id }
        visits.removeAll { $0.profileID == id }
        if defaultProfileID == id { defaultProfileID = next }
        persist()
        syncSpotlight()
        flushSession()
        return true
    }
    public func setDefaultProfile(_ id: UUID) {
        guard profiles.contains(where: { $0.id == id }) else { return }
        defaultProfileID = id; persist()
    }
    public func bookmarks(for profileID: UUID) -> [BrowserBookmark] {
        bookmarks.filter { $0.profileID == profileID }
    }
    public func history(for profileID: UUID, limit: Int = 200) -> [BrowserVisit] {
        Array(visits.lazy.filter { $0.profileID == profileID }.prefix(max(0, limit)))
    }
    public func rememberedSite(for text: String, profileID: UUID) -> URL? {
        AddressResolver.rememberedSite(text,
            visits: visits.filter { $0.profileID == profileID },
            bookmarks: bookmarks.filter { $0.profileID == profileID })
    }
    public func isBookmarked(_ url: String?, profileID: UUID) -> Bool {
        guard let url else { return false }
        return bookmarks.contains { $0.profileID == profileID && $0.url == url }
    }
    public func toggleBookmark(profileID: UUID, title: String, url: String) {
        guard !isIncognito(profileID) else { return }
        if let index = bookmarks.firstIndex(where: { $0.profileID == profileID && $0.url == url }) {
            bookmarks.remove(at: index)
        } else {
            bookmarks.append(BrowserBookmark(profileID: profileID, title: title, url: url))
        }
        persist()
        syncSpotlight()
    }
    public func editBookmark(_ id: UUID, title: String, url: String, folder: String) {
        guard let index = bookmarks.firstIndex(where: { $0.id == id }) else { return }
        bookmarks[index].title = title; bookmarks[index].url = url; bookmarks[index].folder = folder
        persist()
        syncSpotlight()
    }
    public func deleteBookmark(_ id: UUID) { bookmarks.removeAll { $0.id == id }; persist(); syncSpotlight() }
    public func importBookmarks(_ items: [ExportedBookmark], into profileID: UUID) {
        guard profiles.contains(where: { $0.id == profileID }), !isIncognito(profileID) else { return }
        for item in items where !bookmarks.contains(where: { $0.profileID == profileID && $0.url == item.url }) {
            bookmarks.append(BrowserBookmark(profileID: profileID, title: item.title, url: item.url, folder: item.folder))
        }
        persist()
        syncSpotlight()
    }
    public func importSharedLinks() async {
        guard systemIntegrationsEnabled else { return }
        let pending = SharedLinkInbox.pending()
        guard !pending.isEmpty,
              let profileID = windows.first.map(\.activeProfileID).flatMap({ isIncognito($0) ? nil : $0 })
                ?? profiles.first(where: { !$0.isIncognito })?.id else { return }
        for (record, _) in pending {
            guard let url = URL(string: record.url),
                  ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
                  let host = url.host, url.user == nil,
                  !bookmarks.contains(where: { $0.profileID == profileID && $0.url == url.absoluteString })
            else { continue }
            let title = record.title.trimmingCharacters(in: .whitespacesAndNewlines)
            bookmarks.append(BrowserBookmark(profileID: profileID,
                title: title.isEmpty ? host : String(title.prefix(240)), url: url.absoluteString))
        }
        persist()
        syncSpotlight()
        persistenceQueue.sync {}
        await libraryWrite?.value
        guard persistenceError == nil else { return }
        for (_, file) in pending { try? FileManager.default.removeItem(at: file) }
    }
    public func setSpotlightSavedPages(_ enabled: Bool) {
        preferences.spotlightSavedPages = enabled
        syncSpotlight()
    }

    private func syncSpotlight() {
        guard systemIntegrationsEnabled else { return }
        let allowed = Set(profiles.filter { !$0.isIncognito }.map(\.id))
        let entries = bookmarks.filter { allowed.contains($0.profileID) }
        let enabled = preferences.spotlightSavedPages
        let previous = spotlightWrite
        spotlightWrite = Task {
            await previous?.value
            do { try await spotlight.update(bookmarks: entries, enabled: enabled) }
            catch { persistenceError = error.localizedDescription }
        }
    }
    public func clearHistory(_ profileID: UUID) { visits.removeAll { $0.profileID == profileID }; persist() }
    public func deleteVisit(_ id: UUID) { visits.removeAll { $0.id == id }; persist() }
    @discardableResult public func recordVisit(profileID: UUID, title: String, url: String) -> UUID {
        let visit = BrowserVisit(profileID: profileID, title: title, url: url)
        visits.insert(visit, at: 0)
        if visits.count > 3000 { visits = Array(visits.prefix(3000)) }
        if !isIncognito(profileID) { persist() }
        return visit.id
    }
    public func updateVisitExcerpt(_ id: UUID, profileID: UUID, text: String) {
        guard !isIncognito(profileID),
              let index = visits.firstIndex(where: { $0.id == id && $0.profileID == profileID })
        else { return }
        let excerpt = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1000))
        guard !excerpt.isEmpty else { return }
        visits[index].excerpt = excerpt
        persist()
    }
    public func pinnedShortcuts() -> [BrowserShortcut] { shortcuts.filter(\.isPinned) }
    public func toggleShortcutPin(_ id: UUID) {
        guard let index = shortcuts.firstIndex(where: { $0.id == id }) else { return }
        shortcuts[index].isPinned.toggle(); persist()
    }
    public func isIncognito(_ profileID: UUID) -> Bool {
        profiles.first(where: { $0.id == profileID })?.isIncognito == true
    }
    @discardableResult public func ensureIncognitoProfile() -> BrowserProfile {
        if let existing = profiles.first(where: \.isIncognito) { return existing }
        let profile = BrowserProfile(name: "Incognito", isIncognito: true)
        profiles.append(profile); persist(); return profile
    }
    public func addShortcut(name: String, url: String) {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty,
              let destination = AddressResolver.resolve(url, provider: preferences.provider,
                  locality: preferences.searchLocality, localityTerms: preferences.localityQueryTerms,
                  customTemplate: preferences.customSearchTemplate), destination.scheme == "https" || destination.scheme == "http" else { return }
        shortcuts.append(BrowserShortcut(name: name, url: destination.absoluteString, isPinned: false)); persist()
    }
    public func editShortcut(_ id: UUID, name: String, url: String) {
        guard let i = shortcuts.firstIndex(where: { $0.id == id }),
              let resolved = AddressResolver.resolve(url, provider: preferences.provider,
                  locality: preferences.searchLocality, localityTerms: preferences.localityQueryTerms,
                  customTemplate: preferences.customSearchTemplate) else { return }
        shortcuts[i].name = name; shortcuts[i].url = resolved.absoluteString; persist()
    }
    public func removeShortcut(_ id: UUID) { shortcuts.removeAll { $0.id == id }; persist() }
    public func persist() {
        let incognitoIDs = Set(profiles.filter(\.isIncognito).map(\.id))
        let archive = BrowserArchive(profiles: profiles,
                                     bookmarks: bookmarks.filter { !incognitoIDs.contains($0.profileID) },
                                     visits: visits.filter { !incognitoIDs.contains($0.profileID) },
                                     shortcuts: shortcuts, defaultProfileID: defaultProfileID)
        persistenceQueue.async {
            BrowserPersistence.save(archive)
        }
        scheduleSessionSave()
        if let provider = engine as? any BrowserLibraryProviding {
            let libraries = profiles.filter { !$0.isIncognito }.map { profile in
                (profile.id, BrowserProfileLibrary(bookmarks: bookmarks.filter { $0.profileID == profile.id },
                    visits: visits.filter { $0.profileID == profile.id }))
            }
            let previous = libraryWrite
            libraryWrite = Task {
                await previous?.value
                for (id, library) in libraries {
                    do { try await provider.saveLibrary(profileID: id, library: library) }
                    catch { persistenceError = error.localizedDescription }
                }
            }
        }
    }
}
