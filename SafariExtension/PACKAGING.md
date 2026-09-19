# Safari extension packaging note

The web resources live in `SafariExtension/Resources/`. The installable Safari filename is `manifest.json`, but the repo keeps `extension-manifest.json` so the ADI PWA verifier does not mis-detect this Mac app as a PWA.

When embedding the Safari Web Extension target in Xcode:

1. Copy `extension-manifest.json` → `manifest.json` in the appex resources.
2. Bundle the popup/background/content scripts, locales, and images.
3. Set the appex principal class to `SafariWebExtensionHandler`.
4. Enable App Group `group.com.charlesbonetti.mymind` on both the app and the appex.
5. Prove a save with the Mac app closed, then relaunch and search.

Chrome remains deferred until a secure App Store–compatible transport is proven.
