import Foundation

/// Shared selection for the history window so AppKit keyboard handling and SwiftUI stay in sync.
@MainActor
final class HistoryOverlayKeyboardState: ObservableObject {
    @Published var selectedId: UUID?

    var scrollToSelectionForKeyboardNavigation = false
}
