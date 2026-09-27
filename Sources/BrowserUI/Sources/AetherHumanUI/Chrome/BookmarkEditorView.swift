import SwiftUI

struct BookmarkEditorView: View {
    @Environment(\.aetherTheme) private var theme
    @Environment(\.aetherSurfaceStyle) private var surface
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

    private var skin: AetherSurfaceStyle { surface ?? AetherSurfaceResolver.themed(dark: theme.dark) }

    private var folders: [String] {
        let existing = workspace.bookmarks(for: bookmark.profileID).map(\.folder).filter { !$0.isEmpty }
        return Array(Set(["Favorites", folder] + existing)).sorted()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(isNew ? "Bookmark added" : "Edit bookmark")
                .font(AetherType.emphasis(13))
                .foregroundStyle(skin.primaryText)

            VStack(alignment: .leading, spacing: 6) {
                Text("Name")
                    .font(AetherType.caption(11))
                    .foregroundStyle(skin.secondaryText)
                TextField("Name", text: $name)
                    .textFieldStyle(.plain)
                    .font(AetherType.body(13))
                    .foregroundStyle(skin.primaryText)
                    .tint(skin.primaryText)
                    .padding(.horizontal, 10)
                    .frame(height: 32)
                    .background { AetherSurfaceFieldBackground() }
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(nameFocused ? skin.primaryText.opacity(0.30) : Color.clear, lineWidth: 1)
                    }
                    .focused($nameFocused)
                    .onSubmit(save)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Folder")
                    .font(AetherType.caption(11))
                    .foregroundStyle(skin.secondaryText)
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
                        BrowserIconView(icon: .folder, tint: skin.secondaryIcon).iconSize(13)
                        Text(folder)
                            .font(AetherType.body(13))
                            .foregroundStyle(skin.primaryText)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(AetherType.symbol(10))
                            .foregroundStyle(skin.secondaryIcon)
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 32)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background { AetherSurfaceFieldBackground() }
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
                        .foregroundStyle(skin.primaryText)
                        .frame(minWidth: 88, minHeight: 30)
                        .background {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(skin.controlFill)
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
        .environment(\.aetherSurfaceStyle, skin)
        .transition(AetherMotion.disclosure(reduced, expanded: true))
        .animation(AetherMotion.popover(reduced), value: folder)
        .onAppear { nameFocused = true }
    }

    private var doneFill: Color {
        skin.isDark
            ? Color(.sRGB, red: 0xFA / 255, green: 0xFA / 255, blue: 0xFA / 255, opacity: 1)
            : Color(.sRGB, red: 0x17 / 255, green: 0x17 / 255, blue: 0x17 / 255, opacity: 1)
    }

    private var doneText: Color {
        skin.isDark
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
