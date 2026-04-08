import Foundation
import ServiceManagement

enum LoginItemManager {
    private static let userDefaultsKey = "launchAtLoginEnabled"

    static var isLaunchAtLoginEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: userDefaultsKey) != nil {
                return UserDefaults.standard.bool(forKey: userDefaultsKey)
            }
            return SMAppService.mainApp.status == .enabled
        }
        set {
            UserDefaults.standard.set(newValue, forKey: userDefaultsKey)
            apply(enabled: newValue)
        }
    }

    /// Call on launch to align SMAppService with saved preference.
    static func syncOnLaunch() {
        let wants = UserDefaults.standard.object(forKey: userDefaultsKey) as? Bool ?? true
        apply(enabled: wants)
    }

    private static func apply(enabled: Bool) {
        let service = SMAppService.mainApp
        do {
            if enabled {
                if service.status != .enabled {
                    try service.register()
                }
            } else {
                if service.status == .enabled {
                    try service.unregister()
                }
            }
        } catch {
            // User may need to approve in System Settings → General → Login Items.
        }
    }
}
