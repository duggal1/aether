import Foundation
import Observation

@MainActor @Observable
public final class BrowserWorkspace {
    public let preferences: BrowserPreferences
    public let engine: any BrowserEnginePort
    public private(set) var profiles: [BrowserProfile]
    public private(set) var bookmarks: [BrowserBookmark]
    public private(set) var visits: [BrowserVisit]
    public private(set) var shortcuts: [BrowserShortcut]
    public private(set) var defaultProfileID: UUID
    @ObservationIgnored private var libraryWrite: Task<Void, Never>?
    public var persistenceError: String?
    public private(set) var windows: [BrowserWindowModel] = []

    public init(engine: any BrowserEnginePort, preferences: BrowserPreferences? = nil) {
        self.engine = engine; self.preferences = preferences ?? BrowserPreferences()
        let archive = BrowserPersistence.load()
        let all = archive.profiles.isEmpty ? [BrowserProfile(name: "Personal")] : archive.profiles
        profiles = all
        bookmarks = archive.bookmarks.filter { item in all.contains(where: { $0.id == item.profileID }) }
        visits = archive.visits.filter { item in all.contains(where: { $0.id == item.profileID }) }
        shortcuts = archive.shortcuts
        defaultProfileID = all.contains(where: { $0.id == archive.defaultProfileID }) ? archive.defaultProfileID! : all[0].id
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
    public func isBookmarked(_ url: String?, profileID: UUID) -> Bool {
        guard let url else { return false }
        return bookmarks.contains { $0.profileID == profileID && $0.url == url }
    }
    public func toggleBookmark(profileID: UUID, title: String, url: String) {
        if let index = bookmarks.firstIndex(where: { $0.profileID == profileID && $0.url == url }) {
            bookmarks.remove(at: index)
        } else {
            bookmarks.append(BrowserBookmark(profileID: profileID, title: title, url: url))
        }
        persist()
    }
    public func editBookmark(_ id: UUID, title: String, url: String, folder: String) {
        guard let index = bookmarks.firstIndex(where: { $0.id == id }) else { return }
        bookmarks[index].title = title; bookmarks[index].url = url; bookmarks[index].folder = folder
        persist()
    }
    public func deleteBookmark(_ id: UUID) { bookmarks.removeAll { $0.id == id }; persist() }
    public func importBookmarks(_ items: [ExportedBookmark], into profileID: UUID) {
        guard profiles.contains(where: { $0.id == profileID }) else { return }
        for item in items where !bookmarks.contains(where: { $0.profileID == profileID && $0.url == item.url }) {
            bookmarks.append(BrowserBookmark(profileID: profileID, title: item.title, url: item.url, folder: item.folder))
        }
        persist()
    }
    public func clearHistory(_ profileID: UUID) { visits.removeAll { $0.profileID == profileID }; persist() }
    public func deleteVisit(_ id: UUID) { visits.removeAll { $0.id == id }; persist() }
    public func recordVisit(profileID: UUID, title: String, url: String) {
        visits.insert(BrowserVisit(profileID: profileID, title: title, url: url), at: 0)
        if visits.count > 3000 { visits = Array(visits.prefix(3000)) }
        if isIncognito(profileID) { return }
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
              let destination = AddressResolver.resolve(url), destination.scheme == "https" || destination.scheme == "http" else { return }
        shortcuts.append(BrowserShortcut(name: name, url: destination.absoluteString, isPinned: true)); persist()
    }
    public func editShortcut(_ id: UUID, name: String, url: String) {
        guard let i = shortcuts.firstIndex(where: { $0.id == id }), let resolved = AddressResolver.resolve(url) else { return }
        shortcuts[i].name = name; shortcuts[i].url = resolved.absoluteString; persist()
    }
    public func removeShortcut(_ id: UUID) { shortcuts.removeAll { $0.id == id }; persist() }
    public func persist() {
        let incognitoIDs = Set(profiles.filter(\.isIncognito).map(\.id))
        BrowserPersistence.save(BrowserArchive(profiles: profiles,
                                               bookmarks: bookmarks.filter { !incognitoIDs.contains($0.profileID) },
                                               visits: visits.filter { !incognitoIDs.contains($0.profileID) },
                                               shortcuts: shortcuts, defaultProfileID: defaultProfileID))
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
