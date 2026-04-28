import Foundation
import FirebaseCore

enum FirebaseBootstrap {
    /// Configures Firebase when `GoogleService-Info.plist` is present in the app bundle.
    /// Add the plist from the Firebase Console; without it, publishing and browse stay offline.
    static func configureIfAvailable() {
        guard let url = Bundle.main.url(forResource: "GoogleService-Info", withExtension: "plist"),
              FileManager.default.fileExists(atPath: url.path)
        else {
            NSLog("CubeRun: GoogleService-Info.plist not found — Firebase disabled.")
            return
        }
        guard FirebaseApp.app() == nil else { return }
        FirebaseApp.configure()
    }

    static var isConfigured: Bool {
        FirebaseApp.app() != nil
    }
}
