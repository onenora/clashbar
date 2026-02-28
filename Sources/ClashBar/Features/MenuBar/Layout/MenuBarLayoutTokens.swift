import SwiftUI

enum MenuBarLayoutTokens {
    static let hPage: CGFloat = 12
    static let hRow: CGFloat = 10
    static let hDense: CGFloat = 6
    static let hMicro: CGFloat = 3

    static let vRow: CGFloat = 6
    static let vDense: CGFloat = 3
    static let sectionGap: CGFloat = 6

    static let hairline: CGFloat = 0.6
    static let opticalNudge: CGFloat = 1
}

extension View {
    func menuRowPadding(vertical: CGFloat = MenuBarLayoutTokens.vRow) -> some View {
        padding(.horizontal, MenuBarLayoutTokens.hRow)
            .padding(.vertical, vertical)
    }
}
