import SwiftUI

struct HiddenProgressViewStyle: ProgressViewStyle {
    func makeBody(configuration: Configuration) -> some View {
        EmptyView()
    }
}
