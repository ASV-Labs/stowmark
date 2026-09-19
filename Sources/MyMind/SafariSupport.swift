import Foundation
import SafariServices

enum SafariSupport {
    static let extensionIdentifier = "com.charlesbonetti.mymind.extension"

    static func openExtensionPreferences() {
        SFSafariApplication.showPreferencesForExtension(withIdentifier: extensionIdentifier) { _ in }
    }
}
