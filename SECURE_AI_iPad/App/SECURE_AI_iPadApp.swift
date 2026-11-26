import SwiftUI

@main
struct SECURE_AI_iPadApp: App {
    @StateObject private var browserStore = EmbeddedBrowserStore()
    @StateObject private var automation = AutomationController()
    @StateObject private var licenseService = LicenseService()
    @StateObject private var themeManager = ThemeManager()

    var body: some Scene {
        WindowGroup {
            MainWorkspaceView()
                .environmentObject(browserStore)
                .environmentObject(automation)
                .environmentObject(licenseService)
                .environmentObject(themeManager)
                .preferredColorScheme(themeManager.palette.isLight ? .light : .dark)
        }
    }
}
