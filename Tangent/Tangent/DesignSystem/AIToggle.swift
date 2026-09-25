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
             ? "Requires an iPad with A14, M1 or newer and iPadOS 26+. We recommend iPads with 6 GB of RAM."
             : "Requires iPhone 12 or later, or iPhone SE (3rd generation), with iOS 26+. We recommend iPhones with 6 GB of RAM.")
            .font(.footnote)
            .foregroundStyle(Color(uiColor: .secondaryLabel))
    }
}
