import SwiftUI

@main
struct SECURE_AI_iPadApp: App {
    @StateObject private var browserStore = EmbeddedBrowserStore()
    @StateObject private var automation = AutomationController()
    @StateObject private var licenseService = LicenseService()
    @StateObject private var themeManager = ThemeManager()
    @StateObject private var savedLogins = SavedLoginStore()

    var body: some Scene {
        WindowGroup {
            MainWorkspaceView()
                .environmentObject(browserStore)
                .environmentObject(automation)
                .environmentObject(licenseService)
                .environmentObject(themeManager)
                .environmentObject(savedLogins)
                .preferredColorScheme(themeManager.palette.isLight ? .light : .dark)
        }
    }
}
