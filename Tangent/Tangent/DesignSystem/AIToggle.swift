import SwiftUI

struct AIToggle: View {
    @EnvironmentObject private var preferences: AppPreferences

    var body: some View {
        Toggle("AI summaries", isOn: $preferences.aiEnabled)
            .tint(Color.tangentPurple)
            .accessibilityIdentifier("ai-enabled")
    }
}

struct AIRequirementsNote: View {
    var body: some View {
        Text(UIDevice.current.userInterfaceIdiom == .pad
             ? "Requires an iPad with A14, M1 or newer and iPadOS 18.2+. Larger models need more memory."
             : "Requires iPhone 12 or later, or iPhone SE (3rd generation), with iOS 18.2+. Larger models need more memory.")
            .font(.footnote)
            .foregroundStyle(Color(uiColor: .secondaryLabel))
    }
}
