import SwiftUI

struct HistoryOverlayView: View {
    @ObservedObject var store: ClipboardStore
    var onDismiss: () -> Void

    @State private var selection: UUID?
    @FocusState private var listFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Clipboard history")
                    .font(.headline)
                Spacer()
                Text("⌃⌘V")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider()

            if store.items.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("Nothing copied yet")
                        .font(.title3.weight(.semibold))
                    Text("Copy text in any app; it appears here in order.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                List(selection: $selection) {
                    ForEach(store.items) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.text)
                                .lineLimit(4)
                                .textSelection(.enabled)
                            Text(item.copiedAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) {
                            selection = item.id
                            pasteSelected()
                        }
                        .tag(Optional(item.id))
                    }
                    .onDelete { offsets in
                        for i in offsets {
                            store.remove(store.items[i])
                        }
                    }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
                .focused($listFocused)
            }

            Divider()

            HStack {
                Button("Clear all") {
                    store.clearAll()
                    selection = nil
                }
                .disabled(store.items.isEmpty)

                Spacer()

                if !PasteSimulator.hasAccessibilityPermission {
                    Button("Allow pasting…") {
                        PasteSimulator.promptForAccessibilityIfNeeded()
                    }
                    .help("Grant Accessibility so the Paste button can send ⌘V to the active app.")
                }

                Button("Paste") {
                    pasteSelected()
                }
                .keyboardShortcut(.return, modifiers: [])
                .disabled(selectedItem == nil)
            }
            .padding(10)
        }
        .frame(minWidth: 380, minHeight: 400)
        .onAppear {
            if selection == nil {
                selection = store.items.first?.id
            }
            listFocused = true
        }
        .onChange(of: store.items) { newItems in
            if let s = selection, !newItems.contains(where: { $0.id == s }) {
                selection = newItems.first?.id
            }
        }
        .onExitCommand { onDismiss() }
    }

    private var selectedItem: ClipboardItem? {
        guard let id = selection else { return nil }
        return store.items.first { $0.id == id }
    }

    private func pasteSelected() {
        guard let item = selectedItem else { return }
        onDismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            store.copyToPasteboard(item.text)
            if PasteSimulator.hasAccessibilityPermission {
                PasteSimulator.pasteUsingCommandV()
            }
        }
    }
}
