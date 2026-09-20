import SwiftUI

struct DiaryLogoButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image("Logo")
                .resizable()
                .scaledToFit()
                .frame(width: 25, height: 25)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Tangent")
        .accessibilityHint("Go to Diary")
        .accessibilityIdentifier("diary-home-logo")
    }
}
