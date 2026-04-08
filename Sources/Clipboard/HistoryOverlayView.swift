import SwiftUI

struct HistoryOverlayView: View {
    @ObservedObject var store: ClipboardStore
    @ObservedObject var keyboardState: HistoryOverlayKeyboardState
    var onDismiss: () -> Void
    var onPaste: () -> Void

    @FocusState private var listFocused: Bool

    var body: some View {
        GeometryReader { geometry in
            let cardWidth = max(0, geometry.size.width - 40)
            let cardHeight = max(0, geometry.size.height - 48)

            ZStack {
                Color.clear
                    .contentShape(Rectangle())
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .onTapGesture { onDismiss() }

                VStack(alignment: .leading, spacing: 0) {
                    header
                    separator
                    Group {
                        if store.items.isEmpty {
                            emptyState
                        } else {
                            historyScroll
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    separator
                    footer
                }
                .padding(20)
                .background {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(.regularMaterial)
                }
                .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .frame(width: cardWidth, height: cardHeight)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .frame(minWidth: 400, minHeight: 440)
        .focused($listFocused)
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

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "doc.on.doc.fill")
                .font(.system(size: 22, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
                .frame(width: 36, height: 36)
                .background {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(.thinMaterial)
                }

            VStack(alignment: .leading, spacing: 2) {
                Text("Clipboard")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(store.items.isEmpty ? "Ready when you copy" : "\(store.items.count) clips")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 0)
        }
        .padding(.bottom, 4)
    }

    private var separator: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.08))
            .frame(height: 1)
            .padding(.vertical, 14)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 44, weight: .light))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)

            Text("Nothing copied yet")
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)

            Text("Copy text in any app — newest clips appear at the top.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 32)
    }

    private var historyScroll: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(store.items) { item in
                        historyRow(item)
                            .id(item.id)
                    }
                }
                .padding(.vertical, 4)
            }
            .scrollIndicators(.hidden)
            .onChange(of: keyboardState.selectedId) { newId in
                guard let newId else { return }
                let scroll = keyboardState.scrollToSelectionForKeyboardNavigation
                keyboardState.scrollToSelectionForKeyboardNavigation = false
                guard scroll else { return }
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(newId, anchor: .center)
                }
            }
        }
    }

    private func historyRow(_ item: ClipboardItem) -> some View {
        let isSelected = keyboardState.selectedId == item.id

        return VStack(alignment: .leading, spacing: 6) {
            Text(item.text)
                .font(.body)
                .textSelection(.enabled)
                .lineLimit(4)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(item.copiedAt.formatted(date: .abbreviated, time: .shortened))
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(isSelected ? 0.08 : 0.04))
                .overlay {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.18), lineWidth: 1)
                    }
                }
        }
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onTapGesture {
            keyboardState.selectedId = item.id
        }
        .contextMenu {
            Button {
                keyboardState.selectedId = item.id
                onPaste()
            } label: {
                Label("Paste", systemImage: "doc.on.clipboard")
            }
            Divider()
            Button(role: .destructive) {
                store.remove(item)
                if keyboardState.selectedId == item.id {
                    keyboardState.selectedId = store.items.first?.id
                }
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private var footer: some View {
        HStack(alignment: .center, spacing: 12) {
            Button("Clear all", systemImage: "trash") {
                store.clearAll()
                keyboardState.selectedId = nil
            }
            .disabled(store.items.isEmpty)
            .buttonStyle(OverlayMaterialButtonStyle())
            .controlSize(.large)

            Spacer(minLength: 8)

            Button("Paste", systemImage: "doc.on.clipboard") {
                onPaste()
            }
            .keyboardShortcut(.return, modifiers: [])
            .disabled(selectedItem == nil)
            .buttonStyle(OverlayMaterialButtonStyle())
            .controlSize(.large)
        }
        .padding(.top, 2)
    }

    private var selectedItem: ClipboardItem? {
        guard let id = keyboardState.selectedId else { return nil }
        return store.items.first { $0.id == id }
    }
}

private struct OverlayMaterialButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(fillOpacity(isPressed: configuration.isPressed)))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            }
            .opacity(isEnabled ? 1 : 0.45)
    }

    private func fillOpacity(isPressed: Bool) -> Double {
        if isPressed { return 0.09 }
        return 0.04
    }
}
