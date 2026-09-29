import Foundation
import Testing
@testable import AetherHumanUI

// The password export reader, from Search's `Vault.take(csv:)`. A real export
// is not tidy: quoted fields with commas, quotes doubled inside them, notes
// with newlines in them, and rows for things that are not websites at all.
struct CredentialTransferTests {
    @Test func chromeExportReads() {
        let csv = """
        name,url,username,password,note
        Amazon,https://www.amazon.com/,harshit@example.com,"p@ss,word",
        GitHub,https://github.com/,harshit,"s3cret",
        """
        let out = CredentialTransfer.read(csv: csv)
        #expect(out.skipped == 0)
        #expect(out.credentials.count == 2)
        #expect(out.credentials[0] == ImportedCredential(
            origin: "https://www.amazon.com", username: "harshit@example.com", password: "p@ss,word"))
        #expect(out.credentials[1].origin == "https://github.com")
        #expect(out.credentials[1].password == "s3cret")
    }

    /// Google Password Manager writes the four columns with no note.
    @Test func googlePasswordManagerExportReads() {
        let csv = "name,url,username,password\nGoogle,https://accounts.google.com/,me@gmail.com,pw"
        let out = CredentialTransfer.read(csv: csv)
        #expect(out.credentials == [ImportedCredential(
            origin: "https://accounts.google.com", username: "me@gmail.com", password: "pw")])
    }

    /// A doubled quote is one quote, and a newline inside quotes is part of the
    /// field — not the end of the row.
    @Test func quotedFieldsSurvive() {
        let csv = "name,url,username,password,note\nX,https://example.com/,u,\"a\"\"b\",\"line one\nline two\"\nY,https://other.com/,u,pw,"
        let out = CredentialTransfer.read(csv: csv)
        #expect(out.credentials.count == 2)
        #expect(out.credentials[0].password == "a\"b")
        #expect(out.credentials[1].origin == "https://other.com")
    }

    /// A site named without a scheme is the site it plainly is.
    @Test func bareHostBecomesHTTPS() {
        let csv = "name,url,username,password\nX,example.com,u,pw"
        #expect(CredentialTransfer.read(csv: csv).credentials.first?.origin == "https://example.com")
    }

    /// The same site and name twice is one password, and the last row is the
    /// one kept — an export that lists a password twice is not two passwords.
    @Test func duplicateRowsCollapseToTheLastOne() {
        let csv = "name,url,username,password\nX,https://example.com/,u,old\nX,https://example.com/,u,new"
        let out = CredentialTransfer.read(csv: csv)
        #expect(out.credentials.count == 1)
        #expect(out.credentials.first?.password == "new")
    }

    /// Rows that name something other than a website, or carry no password, are
    /// counted rather than guessed at.
    @Test func unplaceableRowsAreCounted() {
        let csv = """
        name,url,username,password
        Instagram,android://E4B1@com.instagram.android/,u,pw
        Old,http://neverssl.com/,u,pw
        Empty,https://example.com/,u,
        Good,https://good.com/,u,pw
        """
        let out = CredentialTransfer.read(csv: csv)
        #expect(out.skipped == 3)
        #expect(out.credentials.count == 1)
        #expect(out.credentials.first?.origin == "https://good.com")
    }

    /// The one http the vault keeps for, because it never leaves the Mac.
    @Test func loopbackHTTPIsKept() {
        let csv = "name,url,username,password\nLocal,http://localhost:3000/,u,pw"
        #expect(CredentialTransfer.read(csv: csv).credentials.first?.origin == "http://localhost:3000")
    }

    /// Without the columns that name a site, a name and a password there is no
    /// way to place a row, and guessing would put passwords against the wrong
    /// site.
    @Test func headerWithoutTheColumnsReadsNothing() {
        let csv = "a,b,c\n1,2,3\n4,5,6"
        let out = CredentialTransfer.read(csv: csv)
        #expect(out.credentials.isEmpty)
        #expect(out.skipped == 2)
    }

    @Test func emptyFileReadsNothing() {
        let out = CredentialTransfer.read(csv: "")
        #expect(out.credentials.isEmpty)
        #expect(out.skipped == 0)
    }

    @Test func originRefusesThingsThatAreNotWebsites() {
        #expect(CredentialTransfer.origin(for: "") == nil)
        #expect(CredentialTransfer.origin(for: "   ") == nil)
        #expect(CredentialTransfer.origin(for: "android://E4B1@com.instagram.android/") == nil)
        #expect(CredentialTransfer.origin(for: "http://neverssl.com/") == nil)
        #expect(CredentialTransfer.origin(for: "https://example.com/") == "https://example.com")
    }
}
