import SwiftUI

/// The shared top-right settings control used across Tangent screens.
struct SettingsToolbarButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "gearshape")
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(Color.tangentPurple)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Settings")
    }
}

#Preview {
    SettingsToolbarButton(action: {})
        .background(Color.tangentWash)
}
