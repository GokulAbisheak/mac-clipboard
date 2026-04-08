import SwiftUI

struct HistoryOverlayView: View {
    @ObservedObject var store: ClipboardStore
    @ObservedObject var keyboardState: HistoryOverlayKeyboardState
    @ObservedObject private var accessibility = AccessibilityPermissionCoordinator.shared
    var onDismiss: () -> Void
    var onPaste: () -> Void

    @FocusState private var listFocused: Bool

    private var selectionBinding: Binding<UUID?> {
        Binding(
            get: { keyboardState.selectedId },
            set: { keyboardState.selectedId = $0 }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Clipboard")
                    .font(.headline)
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
                List(selection: selectionBinding) {
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
                            keyboardState.selectedId = item.id
                            onPaste()
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
                    keyboardState.selectedId = nil
                }
                .disabled(store.items.isEmpty)

                Spacer()

                if accessibility.showManualPasteButton {
                    Button("Allow pasting…") {
                        accessibility.openAccessibilitySettingsPrompt()
                    }
                    .help("Open Accessibility settings so Return can paste into the active app with ⌘V.")
                }

                Button("Paste") {
                    onPaste()
                }
                .keyboardShortcut(.return, modifiers: [])
                .disabled(selectedItem == nil)
            }
            .padding(10)
        }
        .frame(minWidth: 380, minHeight: 400)
        .onAppear {
            if keyboardState.selectedId == nil {
                keyboardState.selectedId = store.items.first?.id
            }
            listFocused = true
        }
        .onChange(of: store.items) { newItems in
            if let s = keyboardState.selectedId, !newItems.contains(where: { $0.id == s }) {
                keyboardState.selectedId = newItems.first?.id
            }
        }
        .onExitCommand { onDismiss() }
    }

    private var selectedItem: ClipboardItem? {
        guard let id = keyboardState.selectedId else { return nil }
        return store.items.first { $0.id == id }
    }
}
