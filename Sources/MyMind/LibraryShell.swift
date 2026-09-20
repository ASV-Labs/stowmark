import AppKit
import LibraryCore
import SwiftUI
import UniformTypeIdentifiers

struct LibraryShell: View {
    @Bindable var model: LibraryModel
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openSettings) private var openSettings
    @FocusState private var searchFocused: Bool
    @FocusState private var captureFocused: Bool
    @State private var importFile = false
    @State private var shelfName = ""
    @State private var dropTargeted = false
    @State private var tableSort: [KeyPathComparator<SavedItem>] = [
        KeyPathComparator(\.createdAt, order: .reverse)
    ]
    @State private var columnVisibility: NavigationSplitViewVisibility = Self.storedColumnVisibility
    @State private var detailWidth: CGFloat = 0
    @State private var renamingShelfID: UUID?
    @State private var renameDraft = ""
    @State private var showAllTags = false
    @State private var dropShelfID: UUID?
    @FocusState private var renameFocused: Bool
    @FocusState private var shelfNameFocused: Bool

    private static let sidebarCollapsedKey = "librarySidebarCollapsed"
    private static let itemDragType = UTType(exportedAs: "com.charlesbonetti.mymind.saved-item")
    private static let headerSorts: [HeaderSort] = [
        HeaderSort(order: .recent, title: "Recent"),
        HeaderSort(order: .title, title: "Title"),
        HeaderSort(order: .source, title: "Source"),
        HeaderSort(order: .kind, title: "Kind"),
        HeaderSort(order: .kept, title: "Kept"),
    ]

    private static var storedColumnVisibility: NavigationSplitViewVisibility {
        UserDefaults.standard.bool(forKey: sidebarCollapsedKey) ? .detailOnly : .all
    }

    private var keyboardBrowsingBlocked: Bool {
        searchFocused || captureFocused || renameFocused || shelfNameFocused
    }

    var body: some View {
        Group {
            if model.startupError != nil {
                recovery
            } else {
                NavigationSplitView(columnVisibility: $columnVisibility) {
                    sidebar
                } detail: {
                    detail
                }
                .navigationSplitViewStyle(.balanced)
                .toolbar {
                    ToolbarItem(placement: .navigation) {
                        Button(action: toggleSidebar) {
                            Label("Sidebar", systemImage: "sidebar.leading")
                        }
                        .labelStyle(.iconOnly)
                        .keyboardShortcut("s", modifiers: [.command, .option])
                        .help(columnVisibility == .detailOnly ? "Show sidebar" : "Hide sidebar")
                        .accessibilityLabel(columnVisibility == .detailOnly ? "Show sidebar" : "Hide sidebar")
                    }
                }
                .toolbarBackground(.visible, for: .windowToolbar)
            }
        }
        .background(Theme.canvas(scheme))
        .onChange(of: model.searchFocusToken) { _, _ in searchFocused = true }
        .onChange(of: model.captureFocusToken) { _, _ in captureFocused = true }
        .onChange(of: model.queryText) { _, _ in model.scheduleSearch() }
        .onChange(of: model.importToken) { _, _ in importFile = true }
        .onReceive(NotificationCenter.default.publisher(for: .filterTag)) { note in
            if let label = note.object as? String {
                model.addTagFilter(label)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openMyMindSettings)) { _ in
            NSApp.activate(ignoringOtherApps: true)
            openSettings()
        }
        .fileImporter(isPresented: $importFile, allowedContentTypes: importTypes) { result in
            if case .success(let url) = result { model.importFile(url) }
        }
        .sheet(isPresented: Binding(get: { model.importPlan != nil }, set: { if !$0 { model.importPlan = nil } })) {
            importSheet
        }
        .onAppear {
            tableSort = [Self.tableComparator(for: model.listOrder)]
            if model.allCount == 0 {
                model.focusCapture()
            }
        }
        .onChange(of: columnVisibility) { _, visibility in
            UserDefaults.standard.set(visibility == .detailOnly, forKey: Self.sidebarCollapsedKey)
        }
        .onOpenURL { model.handleIncomingURL($0) }
        .sheet(isPresented: $showAllTags) {
            allTagsSheet
        }
        .onKeyPress(.leftArrow) { handleHorizontal(-1) }
        .onKeyPress(.rightArrow) { handleHorizontal(1) }
        .onKeyPress(.home) { handleEdge(toEnd: false) }
        .onKeyPress(.end) { handleEdge(toEnd: true) }
        .onKeyPress(keys: [.delete], phases: [.down]) { press in
            guard !press.modifiers.contains(.command), !keyboardBrowsingBlocked else { return .ignored }
            model.trashSelected()
            return .handled
        }
        .onKeyPress(keys: [.return], phases: [.down]) { press in
            guard press.modifiers.contains(.command), !keyboardBrowsingBlocked else { return .ignored }
            model.openSelected()
            return .handled
        }
        .onKeyPress(keys: [KeyEquivalent("c")], phases: [.down]) { press in
            guard press.modifiers.contains(.command),
                  !press.modifiers.contains(.shift),
                  !press.modifiers.contains(.option),
                  !press.modifiers.contains(.control),
                  !keyboardBrowsingBlocked else { return .ignored }
            return model.copySelectedOriginalURL() ? .handled : .ignored
        }
        .onKeyPress(keys: [KeyEquivalent("z")], phases: [.down]) { press in
            guard press.modifiers.contains(.command),
                  press.modifiers.contains(.shift),
                  !keyboardBrowsingBlocked else { return .ignored }
            model.undoLastTrash()
            return .handled
        }
        .onDrop(of: LibraryModel.dropTypes, isTargeted: $dropTargeted) { providers in
            model.acceptDrop(providers)
        }
        .onKeyPress(.escape) {
            if renameFocused {
                cancelRename()
                return .handled
            }
            guard model.previewItemID != nil else { return .ignored }
            model.closePreview()
            return .handled
        }
        .onKeyPress(.space) {
            guard !keyboardBrowsingBlocked else { return .ignored }
            if model.previewItemID != nil {
                if NSApp.keyWindow?.firstResponder is NSTextView {
                    return .ignored
                }
                model.closePreview()
            } else {
                model.openPreview()
            }
            return .handled
        }
        .onKeyPress(.downArrow) {
            guard !keyboardBrowsingBlocked else { return .ignored }
            model.moveSelection(1)
            return .handled
        }
        .onKeyPress(.upArrow) {
            guard !keyboardBrowsingBlocked else { return .ignored }
            model.moveSelection(-1)
            return .handled
        }
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: Theme.Radius.panel)
                    .stroke(Theme.accent(scheme), lineWidth: 2)
                    .padding(8)
                    .allowsHitTesting(false)
            }
        }
    }

    private var importTypes: [UTType] {
        var types: [UTType] = [.html, .pdf, .png, .jpeg, .heic]
        if let webloc = UTType(filenameExtension: "webloc") { types.append(webloc) }
        return types
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("My Mind")
                .font(.title2)
                .foregroundStyle(Theme.ink(scheme))
                .padding(.horizontal, 20)
                .padding(.top, 28)
                .padding(.bottom, 18)
            placeRow("All items", count: model.allCount, place: .all, symbol: "square.grid.2x2")
            placeRow("Favorites", count: model.favoriteCount, place: .favorites, symbol: "star")
            Text("Shelves")
                .font(.caption)
                .foregroundStyle(Theme.secondary(scheme))
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 6)
            if !model.shelves.isEmpty {
                List {
                    ForEach(model.shelves) { shelf in
                        shelfRow(shelf)
                            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    }
                    .onMove { source, destination in
                        model.moveShelves(from: source, to: destination)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .environment(\.defaultMinListRowHeight, 32)
                .frame(height: CGFloat(model.shelves.count) * 36)
            }
            if !model.tagCounts.isEmpty {
                Text("Tags")
                    .font(.caption)
                    .foregroundStyle(Theme.secondary(scheme))
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                    .padding(.bottom, 6)
                ForEach(Array(model.tagCounts.prefix(20))) { tag in
                    tagRow(tag)
                }
                Button("All tags…") { showAllTags = true }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.accent(scheme))
                    .frame(minHeight: 32)
                    .padding(.horizontal, 20)
                    .padding(.top, 4)
                    .accessibilityLabel("All tags")
            }
            Spacer()
            placeRow("Trash", count: model.trashCount, place: .trash, symbol: "trash")
            Button {
                NSApp.activate(ignoringOtherApps: true)
                openSettings()
            } label: {
                Image(systemName: "gearshape")
                    .font(.title3)
                    .foregroundStyle(Theme.secondary(scheme))
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Settings")
            .accessibilityLabel("Settings")
            .padding(.horizontal, 16)
            .padding(.top, 8)
            HStack(spacing: 8) {
                TextField("New shelf", text: $shelfName)
                    .textFieldStyle(.plain)
                    .focused($shelfNameFocused)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(Theme.card(scheme), in: RoundedRectangle(cornerRadius: Theme.Radius.chip))
                    .onSubmit { addShelf() }
                Button("Add") { addShelf() }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.accent(scheme))
                    .disabled(shelfName.trimmingCharacters(in: .whitespaces).isEmpty)
                    .frame(minHeight: 32)
            }
            .padding(12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.sidebar(scheme))
        .navigationSplitViewColumnWidth(min: 200, ideal: 232, max: 320)
        .toolbar(removing: .sidebarToggle)
    }

    @ViewBuilder
    private func shelfRow(_ shelf: Shelf) -> some View {
        if renamingShelfID == shelf.id {
            TextField("Shelf name", text: $renameDraft)
                .textFieldStyle(.plain)
                .focused($renameFocused)
                .onSubmit { commitRename() }
                .onExitCommand { cancelRename() }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .padding(.horizontal, 8)
                .onAppear { renameFocused = true }
        } else {
            placeChrome(
                title: shelf.name,
                count: shelf.itemCount,
                selected: model.place == .shelf(shelf.id),
                symbol: "books.vertical"
            )
            .contentShape(Rectangle())
            .onTapGesture { model.choose(.shelf(shelf.id)) }
            .contextMenu {
                Button("Rename") { beginRename(shelf) }
                Button("Remove shelf") { model.deleteShelf(shelf.id) }
            }
            .simultaneousGesture(TapGesture(count: 2).onEnded { beginRename(shelf) })
            .onDrop(of: [Self.itemDragType], isTargeted: shelfDropTargeted(shelf.id)) { providers in
                acceptShelfDrop(providers, shelfID: shelf.id)
            }
            .overlay {
                if dropShelfID == shelf.id {
                    RoundedRectangle(cornerRadius: Theme.Radius.chip)
                        .stroke(Theme.accent(scheme), lineWidth: 2)
                        .padding(.horizontal, 8)
                        .allowsHitTesting(false)
                }
            }
            .accessibilityLabel("\(shelf.name), \(shelf.itemCount) items")
            .accessibilityAddTraits(model.place == .shelf(shelf.id) ? [.isButton, .isSelected] : [.isButton])
            .accessibilityAction(named: "Rename") { beginRename(shelf) }
            .accessibilityAction { model.choose(.shelf(shelf.id)) }
        }
    }

    private func tagRow(_ tag: TagCount) -> some View {
        let selected = model.tagFilters.contains { $0.caseInsensitiveCompare(tag.label) == .orderedSame }
        return Button {
            model.addTagFilter(tag.label)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "tag")
                    .frame(width: 16)
                Text(tag.label)
                    .lineLimit(1)
                Spacer()
                Text("\(tag.count)")
                    .font(.caption)
                    .foregroundStyle(Theme.secondary(scheme))
            }
            .foregroundStyle(selected ? Theme.ink(scheme) : Theme.secondary(scheme))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(selected ? Theme.accentSoft(scheme) : Color.clear, in: RoundedRectangle(cornerRadius: Theme.Radius.chip))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
        .accessibilityLabel("\(tag.label), \(tag.count) items")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func placeRow(_ title: String, count: Int, place: LibraryPlace, symbol: String) -> some View {
        let selected = model.place == place
        return Button {
            model.choose(place)
        } label: {
            placeChrome(title: title, count: count, selected: selected, symbol: symbol)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
        .accessibilityLabel("\(title), \(count) items")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func placeChrome(title: String, count: Int, selected: Bool, symbol: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .frame(width: 16)
            Text(title)
                .lineLimit(1)
            Spacer()
            Text("\(count)")
                .font(.caption)
                .foregroundStyle(Theme.secondary(scheme))
        }
        .foregroundStyle(selected ? Theme.ink(scheme) : Theme.secondary(scheme))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(selected ? Theme.accentSoft(scheme) : Color.clear, in: RoundedRectangle(cornerRadius: Theme.Radius.chip))
        .overlay(alignment: .leading) {
            if selected {
                Capsule()
                    .fill(Theme.accent(scheme))
                    .frame(width: 3)
                    .padding(.vertical, 8)
            }
        }
        .padding(.horizontal, 8)
    }

    private var detail: some View {
        ZStack(alignment: .trailing) {
            VStack(spacing: 0) {
                header
                if model.allCount == 0 && !model.isFiltering && model.place != .trash {
                    empty
                } else if model.items.isEmpty {
                    noResults
                } else {
                    switch model.viewMode {
                    case .cards: gallery
                    case .table: itemList
                    case .covers: covers
                    }
                }
                if model.place != .trash && model.showCaptureBar {
                    captureBar
                }
            }
            if let id = model.previewItemID, let item = model.items.first(where: { $0.id == id }) ?? liveItem(id) {
                previewLayer(item)
            }
        }
        .background(Theme.canvas(scheme))
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear { detailWidth = proxy.size.width }
                    .onChange(of: proxy.size.width) { _, width in
                        detailWidth = width
                    }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Theme.secondary(scheme))
                TextField("Search title, notes, tags, excerpts", text: $model.queryText)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .focused($searchFocused)
                    .accessibilityLabel("Search library")
                    .accessibilityIdentifier("library.search")
                if !model.queryText.isEmpty {
                    Button("Clear query") { model.clearQuery() }
                        .buttonStyle(.plain)
                        .foregroundStyle(Theme.secondary(scheme))
                }
                layoutSwitcher
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Theme.card(scheme), in: RoundedRectangle(cornerRadius: Theme.Radius.bar))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.bar)
                    .stroke(Theme.line(scheme, increased: contrast == .increased))
            )

            HStack(spacing: 8) {
                if columnVisibility == .detailOnly {
                    Button(action: toggleSidebar) {
                        Image(systemName: "sidebar.leading")
                            .frame(width: 32, height: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Show sidebar")
                    .accessibilityLabel("Show sidebar")
                }
                Text(model.placeTitle)
                    .font(.headline)
                    .foregroundStyle(Theme.ink(scheme))
                Text(model.matchedCount > model.items.count
                     ? "\(model.items.count) of \(model.matchedCount)"
                     : "\(model.items.count)")
                    .font(.caption)
                    .foregroundStyle(Theme.secondary(scheme))
                    .accessibilityLabel(model.matchedCount > model.items.count
                        ? "Showing \(model.items.count) of \(model.matchedCount)"
                        : "\(model.items.count) showing")
                    .accessibilityAddTraits(.updatesFrequently)
                Spacer()
                sortMenu
                Picker("Search scope", selection: $model.scope) {
                    Text(model.scopeCurrentLabel).tag(SearchScope.currentPlace)
                    Text("Entire library").tag(SearchScope.allItems)
                }
                .pickerStyle(.menu)
                .help("Search stays in \(model.scopeCurrentLabel) unless you choose Entire library.")
                .onChange(of: model.scope) { _, _ in model.reload() }
                Picker("Saved", selection: $model.dateWindow) {
                    ForEach(DateWindow.allCases) { window in
                        Text(window.label).tag(window)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: model.dateWindow) { _, _ in model.reload() }
            }

            if model.isFiltering {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        kindChip(nil)
                        ForEach(ContentKind.allCases) { kind in
                            kindChip(kind)
                        }
                        ForEach(model.tagFilters, id: \.self) { tag in
                            chip(tag, system: "tag") {
                                model.tagFilters.removeAll { $0 == tag }
                                model.reload()
                            }
                        }
                        if let domain = model.domainFilter {
                            chip(domain, system: "globe") { model.domainFilter = nil; model.reload() }
                        }
                        Button("Clear filters") { model.clearFilters() }
                            .buttonStyle(.plain)
                            .foregroundStyle(Theme.accent(scheme))
                    }
                }
            }

            if let message = model.captureMessage {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(model.captureFailed ? Theme.danger(scheme) : Theme.accent(scheme))
                    .accessibilityLabel(message)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 8)
    }

    private func kindChip(_ kind: ContentKind?) -> some View {
        let selected = kind == nil ? model.kindFilters.isEmpty : model.kindFilters == [kind!]
        let title = kind?.label ?? "Any kind"
        return Button(title) {
            model.setKindFilter(kind)
        }
        .buttonStyle(.plain)
        .font(.caption)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(selected ? Theme.accentSoft(scheme) : Theme.card(scheme), in: RoundedRectangle(cornerRadius: Theme.Radius.chip))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.chip)
                .stroke(selected ? Theme.accent(scheme) : Theme.line(scheme, increased: false))
        )
        .foregroundStyle(Theme.ink(scheme))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func chip(_ title: String, system: String, remove: @escaping () -> Void) -> some View {
        HStack(spacing: 4) {
            Image(systemName: system)
            Text(title)
            Button(action: remove) { Image(systemName: "xmark") }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove \(title)")
        }
        .font(.caption)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Theme.accentSoft(scheme), in: RoundedRectangle(cornerRadius: Theme.Radius.chip))
        .foregroundStyle(Theme.ink(scheme))
    }

    private var layoutSwitcher: some View {
        HStack(spacing: 2) {
            ForEach(ViewMode.allCases) { mode in
                Button {
                    model.setViewMode(mode)
                } label: {
                    Image(systemName: mode.symbol)
                        .frame(width: 28, height: 28)
                        .background(model.viewMode == mode ? Theme.accentSoft(scheme) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
                        .foregroundStyle(model.viewMode == mode ? Theme.accent(scheme) : Theme.secondary(scheme))
                }
                .buttonStyle(.plain)
                .help(mode.label)
                .accessibilityLabel(mode.label)
                .accessibilityAddTraits(model.viewMode == mode ? .isSelected : [])
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Library layout")
    }

    private var gallery: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: model.cardSize.cardMinWidth), spacing: 16)], spacing: 16) {
                    ForEach(model.items) { item in
                        ItemCard(
                            item: item,
                            selected: item.id == model.selectedItemID,
                            root: model.store?.rootURL,
                            size: model.cardSize,
                            onTrash: { model.trashItem(item.id, confirm: false) },
                            onFavorite: { model.toggleFavorite(item.id) },
                            onOpen: item.originalAsset != nil || item.originalURL != nil ? { model.openOriginal(item) } : nil,
                            onAddPreview: { model.choosePreviewPhoto(for: item.id) }
                        )
                            .id(item.id)
                            .modifier(ItemDragModifier(id: item.id, type: Self.itemDragType))
                            .contentShape(Rectangle())
                            .onTapGesture { handleItemTap(item) }
                            .contextMenu { cardMenu(item) }
                            .accessibilityAction(named: "Preview") {
                                model.select(item.id)
                                model.openPreview()
                            }
                            .accessibilityAddTraits(item.id == model.selectedItemID ? .isSelected : [])
                    }
                }
                .padding(20)
                loadMoreControl
            }
            .onChange(of: model.previewItemID) { old, new in
                if old != nil, new == nil, let selected = model.selectedItemID {
                    proxy.scrollTo(selected, anchor: .center)
                }
            }
        }
    }

    private var covers: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: model.cardSize.coverSize), spacing: 12)], spacing: 12) {
                    ForEach(model.items) { item in
                        CoverTile(
                            item: item,
                            selected: item.id == model.selectedItemID,
                            root: model.store?.rootURL,
                            size: model.cardSize.coverSize,
                            onTrash: { model.trashItem(item.id, confirm: false) },
                            onFavorite: { model.toggleFavorite(item.id) },
                            onOpen: item.originalAsset != nil || item.originalURL != nil ? { model.openOriginal(item) } : nil,
                            onAddPreview: { model.choosePreviewPhoto(for: item.id) }
                        )
                            .id(item.id)
                            .modifier(ItemDragModifier(id: item.id, type: Self.itemDragType))
                            .contentShape(Rectangle())
                            .onTapGesture { handleItemTap(item) }
                            .contextMenu { cardMenu(item) }
                            .accessibilityAction(named: "Preview") {
                                model.select(item.id)
                                model.openPreview()
                            }
                    }
                }
                .padding(20)
                loadMoreControl
            }
            .onChange(of: model.previewItemID) { old, new in
                if old != nil, new == nil, let selected = model.selectedItemID {
                    proxy.scrollTo(selected, anchor: .center)
                }
            }
        }
    }

    private func handleItemTap(_ item: SavedItem) {
        if model.selectedItemID == item.id {
            model.openPreview()
        } else {
            model.select(item.id)
            if model.openPreviewOnSelect {
                model.openPreview()
            }
        }
    }

    private var itemList: some View {
        VStack(spacing: 0) {
            Table(of: SavedItem.self, selection: tableSelection, sortOrder: $tableSort) {
                TableColumn("Title", value: \.title) { item in
                    Text(item.title)
                        .lineLimit(1)
                        .modifier(ItemDragModifier(id: item.id, type: Self.itemDragType))
                }
                .width(min: 160, ideal: 260)
                TableColumn("Source", value: \.sourceLabel) { item in
                    Text(item.sourceLabel).lineLimit(1)
                }
                .width(min: 90, ideal: 140)
                TableColumn("Kind", value: \.kindLabel) { item in
                    Text(item.kind.label)
                }
                .width(min: 80, ideal: 100)
                TableColumn("Tags", value: \.tagsLabel) { item in
                    Text(item.tagsLabel).lineLimit(1)
                }
                .width(min: 80, ideal: 140)
                TableColumn("Saved date", value: \.createdAt) { item in
                    Text(item.createdAt, format: .dateTime.month(.abbreviated).day().year())
                }
                .width(min: 90, ideal: 120)
                TableColumn("What’s kept", value: \.keptLabel) { item in
                    Text(item.keptLabel).lineLimit(1)
                }
                .width(min: 90, ideal: 120)
            } rows: {
                ForEach(model.items) { item in
                    TableRow(item)
                }
            }
            .tableStyle(.inset)
            .onChange(of: tableSort) { _, newValue in
                applyTableSort(newValue)
            }
            .contextMenu(forSelectionType: SavedItem.ID.self) { ids in
                if let id = ids.first, let item = model.items.first(where: { $0.id == id }) {
                    cardMenu(item)
                }
            } primaryAction: { ids in
                if let id = ids.first {
                    model.select(id)
                    model.openPreview()
                }
            }
            loadMoreControl
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
        }
    }

    private var tableSelection: Binding<Set<SavedItem.ID>> {
        Binding(
            get: { Set([model.selectedItemID].compactMap { $0 }) },
            set: { newValue in
                model.select(newValue.first)
            }
        )
    }

    private func applyTableSort(_ sort: [KeyPathComparator<SavedItem>]) {
        guard let first = sort.first, let column = TableColumnID(matching: first.keyPath) else { return }
        guard model.listOrder != column.listOrder else { return }
        model.setListOrder(column.listOrder)
    }

    @ViewBuilder
    private var loadMoreControl: some View {
        if model.matchedCount > model.items.count {
            Button("Show \(min(LibraryModel.displayPageSize, model.matchedCount - model.items.count)) more") {
                model.loadMore()
            }
            .padding(.bottom, 16)
        }
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 16) {
            Spacer()
            EmptyHero()
            Text("Save something you want to find.")
                .font(.largeTitle)
                .foregroundStyle(Theme.ink(scheme))
            Text("Paste a link, drop an image or PDF, save from the clipboard, or set up Safari. Organization can wait. Nothing here is sample data.")
                .font(.body)
                .foregroundStyle(Theme.secondary(scheme))
                .frame(maxWidth: 460, alignment: .leading)
            HStack(spacing: 12) {
                Button("Add first item") { model.focusCapture() }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent(scheme))
                    .frame(minHeight: 44)
                Button("Save from clipboard") { model.captureFromClipboard() }
                    .frame(minHeight: 44)
                Button("Import bookmarks") { importFile = true }
                    .frame(minHeight: 44)
            }
            Button("Set up Safari capture") { model.openSafariExtensionSettings() }
                .frame(minHeight: 44)
            SettingsLink {
                Label("Open Settings", systemImage: "gearshape")
            }
            .foregroundStyle(Theme.accent(scheme))
            .labelStyle(.titleAndIcon)
            Spacer()
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var noResults: some View {
        VStack(alignment: .leading, spacing: 12) {
            Spacer()
            Text(model.place == .trash ? "Trash is empty." : "Nothing matches these constraints.")
                .font(.title2)
                .foregroundStyle(Theme.ink(scheme))
            if model.place != .trash {
                Text("The library still has \(model.allCount) saved items. Clearing a filter broadens this search. It does not delete anything.")
                    .font(.body)
                    .foregroundStyle(Theme.secondary(scheme))
                    .frame(maxWidth: 480, alignment: .leading)
                HStack {
                    Button("Clear filters") { model.clearFilters() }
                    if model.scope == .currentPlace && model.place != .all {
                        Button("Search entire library") {
                            model.scope = .allItems
                            model.reload()
                        }
                    }
                }
            }
            Spacer()
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var captureBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "plus")
                .foregroundStyle(Theme.accent(scheme))
            TextField("Paste a link or drop a file", text: $model.captureDraft)
                .textFieldStyle(.plain)
                .focused($captureFocused)
                .accessibilityIdentifier("capture.field")
                .onSubmit { model.captureDraftLink() }
            Button("Clipboard") { model.captureFromClipboard() }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.accent(scheme))
                .frame(minHeight: 44)
                .help("Save a web link or image from the clipboard")
            Button(model.isSaving ? "Saving…" : "Save") { model.captureDraftLink() }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent(scheme))
                .disabled(model.isSaving || model.captureDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                .keyboardShortcut(.defaultAction)
                .frame(minWidth: 88, minHeight: 44)
                .accessibilityIdentifier("capture.save")
            Text(model.captureDestination)
                .font(.caption)
                .foregroundStyle(Theme.secondary(scheme))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Theme.card(scheme), in: RoundedRectangle(cornerRadius: Theme.Radius.bar))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.bar).stroke(Theme.line(scheme, increased: contrast == .increased)))
        .padding(20)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Capture")
    }

    private var recovery: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("The library could not be opened.")
                .font(.largeTitle)
            Text(model.startupError ?? "Unknown problem")
                .font(.body)
                .textSelection(.enabled)
            Text("You can start a new empty library on this Mac. If you already exported a .mymind archive, restore it afterwards from Settings.")
                .font(.body)
                .foregroundStyle(Theme.secondary(scheme))
            HStack(spacing: 12) {
                Button("Create a new library") {
                    model.createFreshLibrary()
                }
                .keyboardShortcut(.defaultAction)
                .frame(minHeight: 44)
                Button("Try again") {
                    model.bootstrap()
                }
                .frame(minHeight: 44)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.canvas(scheme))
    }

    private var importSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Import bookmarks")
                .font(.title2)
            if let plan = model.importPlan {
                Text("\(plan.readyCount) ready, \(plan.duplicateCount) already saved, \(plan.unsupportedCount) unsupported.")
                    .font(.body)
                if !plan.folders.isEmpty {
                    Toggle("Create shelves from folders", isOn: $model.createShelvesOnImport)
                    Text(plan.folders.joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(Theme.secondary(scheme))
                }
            }
            HStack {
                Button("Cancel") { model.importPlan = nil }
                Button("Import") { model.commitImport() }
                    .keyboardShortcut(.defaultAction)
                    .disabled((model.importPlan?.readyCount ?? 0) == 0)
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    private func previewLayer(_ item: SavedItem) -> some View {
        HStack(spacing: 0) {
            Button("Close preview") { model.closePreview() }
                .keyboardShortcut(.cancelAction)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.ink(scheme).opacity(0.18))
                .buttonStyle(.plain)
                .accessibilityLabel("Close preview")
            ItemPreview(item: item, model: model)
                .frame(width: 420)
                .background(Theme.card(scheme))
        }
        .transition(reduceMotion ? .identity : .opacity)
    }

    private func cardMenu(_ item: SavedItem) -> some View {
        Group {
            Button("Preview") { model.select(item.id); model.openPreview() }
            if item.lacksPreviewPhoto, item.trashedAt == nil {
                Button("Add preview photo") { model.choosePreviewPhoto(for: item.id) }
            }
            Button(item.retention == .bookmark ? "Open original" : "Open saved file") { model.openOriginal(item) }
            if model.place == .trash {
                Button("Restore") { model.select(item.id); model.restoreSelected() }
            } else {
                Button(item.favorite ? "Unfavorite" : "Favorite") { model.toggleFavorite(item.id) }
                Button("Filter by \(item.sourceLabel)") { model.filterDomain(item.sourceDomain ?? item.sourceLabel) }
                Button("Move to My Mind Trash") { model.select(item.id); model.trashSelected() }
            }
        }
    }

    private func liveItem(_ id: UUID) -> SavedItem? {
        try? model.store?.item(id: id)
    }

    private func addShelf() {
        let name = shelfName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        model.createShelf(name: name)
        shelfName = ""
    }

    private func toggleSidebar() {
        columnVisibility = columnVisibility == .detailOnly ? .all : .detailOnly
    }

    private func beginRename(_ shelf: Shelf) {
        renameDraft = shelf.name
        renamingShelfID = shelf.id
        renameFocused = true
    }

    private func cancelRename() {
        renamingShelfID = nil
        renameFocused = false
    }

    private func commitRename() {
        guard let id = renamingShelfID else { return }
        let name = renameDraft
        cancelRename()
        model.renameShelf(id: id, to: name)
    }

    private func shelfDropTargeted(_ shelfID: UUID) -> Binding<Bool> {
        Binding(
            get: { dropShelfID == shelfID },
            set: { hovering in
                if hovering {
                    dropShelfID = shelfID
                } else if dropShelfID == shelfID {
                    dropShelfID = nil
                }
            }
        )
    }

    private func acceptShelfDrop(_ providers: [NSItemProvider], shelfID: UUID) -> Bool {
        let type = Self.itemDragType.identifier
        let matched = providers.filter { $0.hasItemConformingToTypeIdentifier(type) }
        guard !matched.isEmpty else { return false }
        for provider in matched {
            provider.loadDataRepresentation(forTypeIdentifier: type) { data, _ in
                guard let data, let id = UUID(uuidString: String(decoding: data, as: UTF8.self)) else { return }
                model.receiveShelfDrop(itemID: id, shelfID: shelfID)
            }
        }
        return true
    }

    private func handleHorizontal(_ direction: Int) -> KeyPress.Result {
        guard !keyboardBrowsingBlocked else { return .ignored }
        if model.previewItemID != nil {
            model.moveSelection(direction)
            return .handled
        }
        guard model.viewMode != .table else { return .ignored }
        let columns = model.viewMode == .covers ? coverColumnCount : cardColumnCount
        model.moveSelection(direction * columns)
        return .handled
    }

    private func handleEdge(toEnd: Bool) -> KeyPress.Result {
        guard !keyboardBrowsingBlocked else { return .ignored }
        model.moveSelection(toEnd: toEnd)
        return .handled
    }

    private var cardColumnCount: Int {
        Self.columnCount(width: detailWidth, minimum: model.cardSize.cardMinWidth, spacing: 16)
    }

    private var coverColumnCount: Int {
        Self.columnCount(width: detailWidth, minimum: model.cardSize.coverSize, spacing: 12)
    }

    private static func columnCount(width: CGFloat, minimum: CGFloat, spacing: CGFloat) -> Int {
        let available = width - 40
        guard available > 0, minimum > 0 else { return 1 }
        return max(1, Int((available + spacing) / (minimum + spacing)))
    }

    private var sortMenu: some View {
        Menu {
            ForEach(Self.headerSorts) { entry in
                Button {
                    chooseSort(entry.order)
                } label: {
                    if sortIsActive(entry.order) {
                        Label(entry.title, systemImage: "checkmark")
                    } else {
                        Text(entry.title)
                    }
                }
            }
        } label: {
            Label(activeSortTitle, systemImage: "arrow.up.arrow.down")
        }
        .accessibilityLabel("Sort, \(activeSortTitle)")
        .help("Sort cards, covers, and the table")
    }

    private var activeSortTitle: String {
        Self.headerSorts.first { sortIsActive($0.order) }?.title ?? "Sort"
    }

    private func sortIsActive(_ order: ResultOrder) -> Bool {
        if order == .recent {
            return model.listOrder == .recent || model.listOrder == .relevance
        }
        return model.listOrder == order
    }

    private func chooseSort(_ order: ResultOrder) {
        model.setListOrder(order)
        tableSort = [Self.tableComparator(for: order)]
    }

    private static func tableComparator(for order: ResultOrder) -> KeyPathComparator<SavedItem> {
        switch order {
        case .title: KeyPathComparator(\.title)
        case .source: KeyPathComparator(\.sourceLabel)
        case .kind: KeyPathComparator(\.kindLabel)
        case .tags: KeyPathComparator(\.tagsLabel)
        case .kept: KeyPathComparator(\.keptLabel)
        case .recent, .relevance: KeyPathComparator(\.createdAt, order: .reverse)
        }
    }

    private var allTagsSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("All tags")
                .font(.title2)
                .foregroundStyle(Theme.ink(scheme))
            List(model.tagCounts) { tag in
                Button {
                    model.addTagFilter(tag.label)
                    showAllTags = false
                } label: {
                    HStack {
                        Text(tag.label)
                        Spacer()
                        Text("\(tag.count)")
                            .foregroundStyle(Theme.secondary(scheme))
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(tag.label), \(tag.count) items")
            }
            Button("Close") { showAllTags = false }
                .keyboardShortcut(.cancelAction)
        }
        .padding(20)
        .frame(width: 360, height: 480)
        .background(Theme.canvas(scheme))
    }
}

private struct EmptyHero: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(Theme.accent(scheme))
                .frame(width: 92, height: 124)
                .rotationEffect(.degrees(8))
                .offset(x: 86, y: 8)
            RoundedRectangle(cornerRadius: 8)
                .fill(Theme.card(scheme))
                .overlay(
                    Text("“ ”")
                        .font(.title)
                        .foregroundStyle(Theme.ink(scheme))
                )
                .frame(width: 110, height: 128)
                .rotationEffect(.degrees(2))
                .offset(x: 36, y: 0)
                .shadow(color: Theme.ink(scheme).opacity(0.08), radius: 8, y: 4)
            RoundedRectangle(cornerRadius: 8)
                .fill(Theme.accentSoft(scheme))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Theme.ink(scheme).opacity(0.12))
                )
                .frame(width: 140, height: 96)
                .rotationEffect(.degrees(-6))
                .offset(x: -28, y: 6)
                .shadow(color: Theme.ink(scheme).opacity(0.12), radius: 10, y: 6)
        }
        .frame(width: 240, height: 150, alignment: .leading)
        .accessibilityHidden(true)
    }
}

private struct HeaderSort: Identifiable {
    let order: ResultOrder
    let title: String
    var id: ResultOrder { order }
}

private enum TableColumnID: Hashable {
    case title, source, kind, tags, kept, savedDate

    var listOrder: ResultOrder {
        switch self {
        case .title: .title
        case .source: .source
        case .kind: .kind
        case .tags: .tags
        case .kept: .kept
        case .savedDate: .recent
        }
    }

    init?(matching keyPath: PartialKeyPath<SavedItem>) {
        let byKeyPath: [PartialKeyPath<SavedItem>: TableColumnID] = [
            \SavedItem.title: .title,
            \SavedItem.sourceLabel: .source,
            \SavedItem.kindLabel: .kind,
            \SavedItem.tagsLabel: .tags,
            \SavedItem.keptLabel: .kept,
            \SavedItem.createdAt: .savedDate,
        ]
        guard let match = byKeyPath[keyPath] else { return nil }
        self = match
    }
}

private struct ItemDragModifier: ViewModifier {
    let id: UUID
    let type: UTType

    func body(content: Content) -> some View {
        content.onDrag {
            let provider = NSItemProvider()
            let payload = Data(id.uuidString.utf8)
            let identifier = type.identifier
            provider.registerDataRepresentation(forTypeIdentifier: identifier, visibility: .all) { completion in
                completion(payload, nil)
                return nil
            }
            return provider
        }
    }
}
