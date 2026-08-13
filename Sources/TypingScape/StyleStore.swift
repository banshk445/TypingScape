import SwiftUI

enum WordCloudStyle: String, CaseIterable, Identifiable {
    case editorial
    case collage

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .editorial: return "기본"
        case .collage: return "콜라주"
        }
    }
}

enum BackgroundStyle: String, CaseIterable, Identifiable {
    case paper
    case newsprint
    case dark

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .paper: return "종이"
        case .newsprint: return "신문지"
        case .dark: return "다크"
        }
    }

    /// Only `.dark` overrides the system appearance — paper/newsprint are
    /// always the light palette regardless of the Mac's own dark mode.
    var colorScheme: ColorScheme? {
        self == .dark ? .dark : .light
    }
}

/// Holds the currently previewed word/background style so the menu bar
/// popover and the big window stay in sync — kept as plain in-memory state
/// (not persisted) since these are still comparison previews, not a
/// settled choice yet.
@MainActor
final class StyleStore: ObservableObject {
    @Published var wordCloudStyle: WordCloudStyle = .editorial
    @Published var backgroundStyle: BackgroundStyle = .paper
}
