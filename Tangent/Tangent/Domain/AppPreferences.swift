import Combine
import Foundation

@MainActor
final class AppPreferences: ObservableObject {
    @Published var aiEnabled: Bool {
        didSet { defaults.set(aiEnabled, forKey: "tangent.aiEnabled") }
    }
    @Published private(set) var onboardingCompleted: Bool
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard, existingInstall: Bool = false) {
        self.defaults = defaults
        aiEnabled = defaults.object(forKey: "tangent.aiEnabled") as? Bool ?? existingInstall
        onboardingCompleted = defaults.object(forKey: "tangent.onboardingCompleted") as? Bool ?? existingInstall
        defaults.set(aiEnabled, forKey: "tangent.aiEnabled")
        defaults.set(onboardingCompleted, forKey: "tangent.onboardingCompleted")
    }

    func completeOnboarding() {
        defaults.set(true, forKey: "tangent.onboardingCompleted")
        onboardingCompleted = true
    }
}
