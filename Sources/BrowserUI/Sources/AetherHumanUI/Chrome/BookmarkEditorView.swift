import SwiftUI

struct BookmarkEditorView: View {
    @Environment(\.aetherTheme) private var theme
    @Environment(\.aetherChromeAppearance) private var chrome
    @Environment(\.accessibilityReduceMotion) private var reduced
    @FocusState private var nameFocused: Bool
    @State private var name: String
    @State private var folder: String

    let bookmark: BrowserBookmark
    let isNew: Bool
    let workspace: BrowserWorkspace
    let onDismiss: () -> Void

    init(bookmark: BrowserBookmark, isNew: Bool, workspace: BrowserWorkspace, onDismiss: @escaping () -> Void) {
        self.bookmark = bookmark
        self.isNew = isNew
        self.workspace = workspace
        self.onDismiss = onDismiss
        _name = State(initialValue: bookmark.title)
        _folder = State(initialValue: bookmark.folder.isEmpty ? "Favorites" : bookmark.folder)
    }

    private var appearance: AetherChromeAppearance { chrome ?? (theme.dark ? .dark : .light) }

    private var folders: [String] {
        let existing = workspace.bookmarks(for: bookmark.profileID).map(\.folder).filter { !$0.isEmpty }
        return Array(Set(["Favorites", folder] + existing)).sorted()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(isNew ? "Bookmark added" : "Edit bookmark")
                .font(AetherType.emphasis(13))
                .foregroundStyle(appearance.text)

            VStack(alignment: .leading, spacing: 6) {
                Text("Name")
                    .font(AetherType.caption(11))
                    .foregroundStyle(appearance.secondary)
                TextField("Name", text: $name)
                    .textFieldStyle(.plain)
                    .font(AetherType.body(13))
                    .foregroundStyle(appearance.text)
                    .tint(appearance.text)
                    .padding(.horizontal, 10)
                    .frame(height: 32)
                    .background {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(appearance.addressInputBG)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(nameFocused ? appearance.selected : Color.clear, lineWidth: 1)
                    }
                    .focused($nameFocused)
                    .onSubmit(save)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Folder")
                    .font(AetherType.caption(11))
                    .foregroundStyle(appearance.secondary)
                Menu {
                    ForEach(folders, id: \.self) { value in
                        Button {
                            withAnimation(AetherMotion.popover(reduced)) { folder = value }
                        } label: {
                            HStack {
                                Text(value)
                                if value == folder {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        BrowserIconView(icon: .folder, tint: appearance.secondary).iconSize(13)
                        Text(folder)
                            .font(AetherType.body(13))
                            .foregroundStyle(appearance.text)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(AetherType.symbol(10))
                            .foregroundStyle(appearance.secondary)
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 32)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(appearance.addressInputBG)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(BookmarkMenuButtonStyle(reduced: reduced))
                .focusEffectDisabled()
            }

            HStack(spacing: 8) {
                Button {
                    workspace.deleteBookmark(bookmark.id)
                    onDismiss()
                } label: {
                    Text("Remove")
                        .font(AetherType.body(12))
                        .foregroundStyle(appearance.text)
                        .frame(minWidth: 88, minHeight: 30)
                        .background {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(removeFill)
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(BookmarkPressButtonStyle(reduced: reduced))
                .focusEffectDisabled()

                Spacer(minLength: 8)

                Button(action: save) {
                    HStack(spacing: 7) {
                        AetherCustomIconView(.terminalLeft, tint: doneText, size: 13)
                        Text("Done")
                            .font(AetherType.body(12))
                            .foregroundStyle(doneText)
                    }
                    .frame(minWidth: 88, minHeight: 30)
                    .background {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(doneFill)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(BookmarkPressButtonStyle(reduced: reduced))
                .focusEffectDisabled()
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .opacity(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.45 : 1)
            }
            .padding(.top, 2)
        }
        .padding(16)
        .frame(width: 320)
        .background { AetherPopoverBackground() }
        .transition(AetherMotion.disclosure(reduced, expanded: true))
        .animation(AetherMotion.popover(reduced), value: folder)
        .onAppear { nameFocused = true }
    }

    private var removeFill: Color {
        appearance.isDark
            ? Color(.sRGB, red: 0x26 / 255, green: 0x26 / 255, blue: 0x26 / 255, opacity: 0.9)
            : Color.black.opacity(0.05)
    }

    private var doneFill: Color {
        appearance.isDark
            ? Color(.sRGB, red: 0xFA / 255, green: 0xFA / 255, blue: 0xFA / 255, opacity: 1)
            : Color(.sRGB, red: 0x17 / 255, green: 0x17 / 255, blue: 0x17 / 255, opacity: 1)
    }

    private var doneText: Color {
        appearance.isDark
            ? Color(.sRGB, red: 0x17 / 255, green: 0x17 / 255, blue: 0x17 / 255, opacity: 1)
            : Color(.sRGB, red: 0xFA / 255, green: 0xFA / 255, blue: 0xFA / 255, opacity: 1)
    }

    private func save() {
        let title = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        workspace.editBookmark(bookmark.id, title: title, url: bookmark.url, folder: folder)
        onDismiss()
    }
}

private struct BookmarkPressButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reducedMotion
    let reduced: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .focusEffectDisabled()
            .modifier(AetherPointingCursor())
            .scaleEffect(configuration.isPressed && !reduced ? AetherMotion.pressScale : 1)
            .animation(AetherMotion.press(reduced || reducedMotion), value: configuration.isPressed)
    }
}

private struct BookmarkMenuButtonStyle: ButtonStyle {
    let reduced: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .focusEffectDisabled()
            .modifier(AetherPointingCursor())
            .scaleEffect(configuration.isPressed && !reduced ? AetherMotion.pressScale : 1)
            .animation(AetherMotion.press(reduced), value: configuration.isPressed)
    }
}
