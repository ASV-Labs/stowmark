import SwiftUI

/// In-app alpha how-to shown from Settings → Help and the Help menu.
enum UserGuide {
    struct Section: Identifiable {
        let id: String
        let title: String
        let paragraphs: [String]
        let bullets: [String]
    }

    static let title = "Stowmark — Alpha user guide"

    static let intro = """
    Stowmark keeps a personal library of links, images, PDFs, and excerpts on this Mac. Nothing here requires an account. This alpha is for evaluation — export a backup if the library matters to you.
    """

    static let sections: [Section] = [
        Section(
            id: "get",
            title: "What you can do today",
            paragraphs: [
                "These capture paths work in this alpha without a browser extension.",
            ],
            bullets: [
                "Paste a link into the capture bar, or drop a file onto the library.",
                "Save from the clipboard (⇧⌘V) or the menu bar icon.",
                "Share to Stowmark from Safari, Chrome, and other Mac apps.",
                "Use Services → Save to Stowmark from many apps.",
                "Search with ⌘F. Browse Cards, Rows & Columns, or Covers.",
                "Export and restore a .stowmark archive from Settings → Library.",
            ]
        ),
        Section(
            id: "soon",
            title: "Browser extensions — Coming soon",
            paragraphs: [
                "Safari and Chromium extensions (Chrome, Arc, Brave, Edge) are listed in Settings → Capture as Coming soon. They are not ready for daily use in this alpha.",
                "Until they ship, save from the browser with Share, Services, paste, or the menu bar.",
            ],
            bullets: []
        ),
        Section(
            id: "not",
            title: "What this alpha is not",
            paragraphs: [],
            bullets: [
                "Not a cloud sync product — the library stays on this Mac.",
                "Not notarized yet — first open may need Control-click → Open.",
                "Not a Chrome Web Store listing yet — extension install is Coming soon.",
                "GIF, WebP, TIFF, SVG, and video are not accepted yet.",
            ]
        ),
        Section(
            id: "first",
            title: "First save",
            paragraphs: [
                "Open Stowmark, paste a public https link into the capture bar, and press Return. The card should show what was kept (bookmark, copied file, or excerpt).",
                "Private or loopback addresses are stored as bookmarks and are not fetched for previews.",
            ],
            bullets: []
        ),
        Section(
            id: "settings",
            title: "Settings map",
            paragraphs: [],
            bullets: [
                "General — layout, appearance, sort, capture bar, menu bar, clipboard watcher.",
                "Library — previews, Trash, export and restore, diagnostics.",
                "Capture — browser extensions (Coming soon) and other capture notes.",
                "Help — this guide.",
            ]
        ),
        Section(
            id: "feedback",
            title: "Feedback",
            paragraphs: [
                "Contact the person who sent you this build, or open an issue on the Stowmark GitHub repository if you have access. Do not paste secrets into issues.",
            ],
            bullets: []
        ),
    ]
}

struct UserGuideView: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(UserGuide.title)
                    .font(.title2.weight(.semibold))
                Text(UserGuide.intro)
                    .foregroundStyle(Theme.secondary(scheme))
                    .fixedSize(horizontal: false, vertical: true)

                ForEach(UserGuide.sections) { section in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(section.title)
                            .font(.headline)
                        ForEach(Array(section.paragraphs.enumerated()), id: \.offset) { _, paragraph in
                            Text(paragraph)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if !section.bullets.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(Array(section.bullets.enumerated()), id: \.offset) { _, bullet in
                                    HStack(alignment: .top, spacing: 8) {
                                        Text("•")
                                            .foregroundStyle(Theme.secondary(scheme))
                                        Text(bullet)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.top, 4)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
    }
}
