import AppKit
import Foundation
import UniformTypeIdentifiers

/// One row of a password export, ready for the vault: the site as an origin,
/// and the pair to keep for it.
public struct ImportedCredential: Equatable, Sendable {
    public let origin: String
    public let username: String
    public let password: String

    public init(origin: String, username: String, password: String) {
        self.origin = origin
        self.username = username
        self.password = password
    }
}

/// What a reader made of a file: the rows it could place, and how many it
/// could not. A row with no site, no password, or a site the vault will not
/// keep for lands in `skipped` rather than being dropped in silence.
public struct CredentialImport: Equatable, Sendable {
    public var credentials: [ImportedCredential]
    public var skipped: Int

    public init(credentials: [ImportedCredential] = [], skipped: Int = 0) {
        self.credentials = credentials
        self.skipped = skipped
    }
}

/// Bringing passwords in from another browser.
///
/// Chrome, Google Password Manager and the browsers built on them all write the
/// same CSV: a header line, then a name, a url, a username and a password. This
/// is Search's `Vault.take(csv:)` reader on Aether's own model — every row goes
/// to the vault through the same origin rule as a password saved from a page,
/// so an import can never invent a credential the vault itself would refuse.
///
/// Nothing here writes: reading a file and keeping what it holds are two steps,
/// and the second one belongs to the caller.
public enum CredentialTransfer {
    /// The column names an export may use, per field and per browser.
    private static let urlColumns = ["url", "login_uri", "website", "site", "origin"]
    private static let usernameColumns = ["username", "login_username", "user", "email", "login"]
    private static let passwordColumns = ["password", "login_password"]

    /// Asks for a file and reads it. Returns nil when the panel is dismissed or
    /// the file cannot be read at all — the two are the same to a caller.
    @MainActor
    public static func pick() -> CredentialImport? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.commaSeparatedText, .plainText]
        panel.allowsMultipleSelection = false
        panel.message = "Choose a passwords CSV exported from Chrome or Google Password Manager."
        guard panel.runModal() == .OK, let url = panel.url, let data = try? Data(contentsOf: url) else {
            return nil
        }
        // Exports are UTF-8 in practice; a Latin-1 file still reads rather than
        // failing the whole import over one accented password.
        guard let text = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
        else { return nil }
        return read(csv: text)
    }

    /// The file as rows. A header naming the url, username and password columns
    /// is required: without it there is no way to tell a site from a name, and
    /// guessing would put passwords against the wrong site.
    public static func read(csv text: String) -> CredentialImport {
        var rows = parse(csv: text)
        guard !rows.isEmpty else { return CredentialImport() }

        let header = rows.removeFirst().map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        func column(_ names: [String]) -> Int? { header.firstIndex { names.contains($0) } }
        guard let urlAt = column(urlColumns),
            let userAt = column(usernameColumns),
            let passAt = column(passwordColumns)
        else { return CredentialImport(skipped: rows.count) }

        let last = max(urlAt, max(userAt, passAt))
        var result = CredentialImport()
        // One entry per site and name, the last row winning: an export that
        // lists a password twice is one password, and the vault keeps one.
        var placed: [String: Int] = [:]

        for row in rows {
            guard row.count > last else {
                result.skipped += 1
                continue
            }
            let password = row[passAt]
            guard !password.isEmpty, let origin = origin(for: row[urlAt]) else {
                result.skipped += 1
                continue
            }
            let username = row[userAt].trimmingCharacters(in: .whitespacesAndNewlines)
            let credential = ImportedCredential(origin: origin, username: username, password: password)
            if let index = placed[credential.origin + "\u{1}" + username] {
                result.credentials[index] = credential
            } else {
                placed[credential.origin + "\u{1}" + username] = result.credentials.count
                result.credentials.append(credential)
            }
        }
        return result
    }

    /// The site of an export row, as the vault would write it.
    ///
    /// A url that is not a website is refused, not reshaped: an Android app's
    /// login names a package (`android://…@com.vendor.app/`), which reads as a
    /// domain somebody else owns and would be offered to them. Those rows are
    /// already nil from `origin(for:)`, which drops any url carrying user
    /// information. Plain http is refused for the same reason the vault refuses
    /// it everywhere: a password is only kept for a page that can be trusted
    /// to carry it.
    public static func origin(for rawValue: String) -> String? {
        var value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, !value.hasPrefix("///") else { return nil }
        if !value.contains("://") { value = "https://" + value }
        guard let origin = AetherCredentialVault.origin(for: value),
            let url = URL(string: origin),
            let scheme = url.scheme?.lowercased(),
            let host = url.host?.lowercased()
        else { return nil }
        if scheme == "http", !isLoopback(host) { return nil }
        return origin
    }

    private static func isLoopback(_ host: String) -> Bool {
        host == "localhost" || host == "127.0.0.1" || host == "::1" || host.hasSuffix(".localhost")
    }

    /// Quoted fields, doubled quotes inside them, and newlines inside those —
    /// all three turn up in a real export.
    static func parse(csv text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var quoted = false
        var index = text.startIndex

        while index < text.endIndex {
            let c = text[index]
            if quoted {
                if c == "\"" {
                    let next = text.index(after: index)
                    if next < text.endIndex, text[next] == "\"" {
                        field.append("\"")
                        index = next
                    } else {
                        quoted = false
                    }
                } else {
                    field.append(c)
                }
            } else {
                switch c {
                case "\"": quoted = true
                case ",": row.append(field); field = ""
                case "\n", "\r\n", "\r":
                    row.append(field)
                    field = ""
                    if row.contains(where: { !$0.isEmpty }) { rows.append(row) }
                    row = []
                default: field.append(c)
                }
            }
            index = text.index(after: index)
        }
        row.append(field)
        if row.contains(where: { !$0.isEmpty }) { rows.append(row) }
        // A trailing newline leaves one empty field behind, not a row; the
        // header check above would otherwise read it as a header.
        return rows
    }
}
