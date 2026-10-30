import SwiftUI
import AppKit

extension Notification.Name {
    static let taskGlassFocusComposer = Notification.Name("TaskGlass.focusComposer")
}

// Own one reusable window rather than letting URL events create WindowGroup scenes.
@MainActor final class TaskWindowController {
    static let shared = TaskWindowController()
    private var window: NSWindow?

    func show() {
        if window == nil {
            let content = TasksView(store: TaskStore.shared)
                .frame(minWidth: 360, idealWidth: 390, minHeight: 420, idealHeight: 540)
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                    Task { await TaskStore.shared.sync() }
                }
            let newWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 390, height: 540),
                                     styleMask: [.titled, .closable, .miniaturizable, .resizable],
                                     backing: .buffered, defer: false)
            newWindow.title = "TaskGlass"
            newWindow.identifier = NSUserInterfaceItemIdentifier("tasks")
            newWindow.isReleasedWhenClosed = false
            newWindow.tabbingMode = .disallowed
            newWindow.contentView = NSHostingView(rootView: content)
            newWindow.center()
            window = newWindow
        }
        NSApp.setActivationPolicy(.accessory)
        if window?.isMiniaturized == true { window?.deminiaturize(nil) }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .taskGlassFocusComposer, object: nil)
        }
    }
}

@MainActor final class TaskGlassAppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "checkmark.circle", accessibilityDescription: "TaskGlass")
        let menu = NSMenu()
        addItem("Open TaskGlass", action: #selector(openTasks), to: menu)
        addItem("Refresh now", action: #selector(refresh), to: menu)
        menu.addItem(.separator())
        addItem("Settings…", action: #selector(openSettings), key: ",", to: menu)
        addItem("Quit TaskGlass", action: #selector(quit), key: "q", to: menu)
        item.menu = menu
        statusItem = item
        installMainMenu()
        openTasks()
    }
    private func addItem(_ title: String, action: Selector, key: String = "", to menu: NSMenu) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        menu.addItem(item)
    }
    private func installMainMenu() {
        let main = NSMenu()
        let appMenu = NSMenu()
        addItem("Settings…", action: #selector(openSettings), key: ",", to: appMenu)
        addItem("Quit TaskGlass", action: #selector(quit), key: "q", to: appMenu)
        let appItem = NSMenuItem(); appItem.submenu = appMenu; main.addItem(appItem)
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        let fileItem = NSMenuItem(); fileItem.submenu = fileMenu; main.addItem(fileItem)
        let editMenu = NSMenu(title: "Edit")
        for (title, action, key) in [("Undo", "undo:", "z"), ("Cut", "cut:", "x"), ("Copy", "copy:", "c"), ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a")] {
            editMenu.addItem(withTitle: title, action: Selector(action), keyEquivalent: key)
        }
        let editItem = NSMenuItem(); editItem.submenu = editMenu; main.addItem(editItem)
        NSApp.mainMenu = main
    }
    @objc func openTasks() { TaskWindowController.shared.show() }
    @objc func refresh() { Task { await TaskStore.shared.sync() } }
    @objc func openSettings() {
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 430, height: 370),
                                  styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "TaskGlass Settings"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: TaskGlassSettings(store: TaskStore.shared))
            window.center()
            settingsWindow = window
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    @objc func quit() { NSApp.terminate(nil) }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openTasks()
        return false
    }
    func application(_ application: NSApplication, open urls: [URL]) {
        guard urls.contains(where: { $0.scheme == "taskglass" && $0.host == "open" }) else { return }
        openTasks()
        refresh()
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

// AppKit owns application events so SwiftUI cannot create an extra scene on reopen.
@main @MainActor struct TaskGlassApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = TaskGlassAppDelegate()
        app.setActivationPolicy(.accessory)
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
struct TasksView: View {
    @ObservedObject var store: TaskStore
    private enum ComposerField: Hashable { case title, details }
    @FocusState private var composerFocus: ComposerField?
    @State private var title = ""
    @State private var details = ""
    @State private var showSetup = false
    @State private var confirmDisconnect = false
    @State private var editingTask: GoogleTask?
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Image(systemName: "checkmark.circle.fill").font(.title).foregroundStyle(.blue)
                Text("TaskGlass").font(.title2.bold())
                Spacer()
                if store.busy { ProgressView().controlSize(.small) }
                Button { Task { await store.sync() } } label: { Image(systemName: "arrow.clockwise") }.buttonStyle(.borderless).disabled(store.busy || !store.connected).help("Refresh tasks")
                Menu { Button("Settings…") { (NSApp.delegate as? TaskGlassAppDelegate)?.openSettings() }; Button("Connection setup") { showSetup = true }; if store.connected { Button("Disconnect Google…", role: .destructive) { confirmDisconnect = true }.disabled(store.busy) } } label: { Image(systemName: "gearshape").font(.system(size: 16)) }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden)
                    .frame(width: 28, height: 28).help("Settings and connection")
                    .accessibilityLabel("Settings and connection")
            }
            if store.connected {
                Picker("List", selection: $store.selectedList) { ForEach(store.lists) { Text($0.title).tag($0.id) } }
                    .onChange(of: store.selectedList) { _, _ in Task { await store.sync() } }
                taskComposer
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if store.tasks.isEmpty { ContentUnavailableView("All clear", systemImage: "checkmark.circle", description: Text("No incomplete tasks in this list.")) }
                        ForEach(store.tasks) { task in
                            HStack(alignment: .top, spacing: 10) {
                                Button { Task { await store.complete(task) } } label: { Image(systemName: "circle").font(.title3).foregroundStyle(.secondary) }.buttonStyle(.plain).disabled(store.busy).accessibilityLabel("Complete \(task.title)")
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(task.title).textSelection(.enabled)
                                    if let notes = task.notes, !notes.isEmpty {
                                        Text(notes).font(.caption).foregroundStyle(.secondary).lineLimit(3).textSelection(.enabled)
                                    }
                                    if let date = task.dueDate { Text(date, format: .dateTime.month(.abbreviated).day()).font(.caption).foregroundStyle(Calendar.current.startOfDay(for: date) < Calendar.current.startOfDay(for: Date()) ? .red : .secondary) }
                                }
                                Spacer()
                                Button { editingTask = task } label: { Image(systemName: "square.and.pencil") }
                                    .buttonStyle(.borderless).foregroundStyle(.secondary).disabled(store.busy)
                                    .accessibilityLabel("Edit \(task.title)").help("Edit title and details")
                            }.padding(.vertical, 11).padding(.leading, task.parent == nil ? 0 : 20)
                            Divider()
                        }
                    }
                }
            } else {
                Spacer()
                VStack(alignment: .leading, spacing: 14) {
                    Text("Your tasks. On your desktop.").font(.title2.bold())
                    Text("Connect Google Tasks, then add TaskGlass from your Mac’s widget gallery.").foregroundStyle(.secondary)
                    Button("Connect Google Tasks") { showSetup = true }.buttonStyle(.borderedProminent)
                }
                Spacer()
            }
            if let error = store.error { Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled) }
            HStack {
                if let updated = store.updated { Text("Synced \(updated.formatted(date: .omitted, time: .shortened))") } else { Text("Not connected") }
                Spacer()
                Link("Google Tasks ↗", destination: URL(string: "https://tasks.google.com/")!)
            }.font(.caption).foregroundStyle(.secondary)
            Text("Sync every \(store.refreshInterval.label) while running. macOS schedules widget updates.").font(.caption2).foregroundStyle(.tertiary)
        }.padding(22)
            .onAppear { focusComposer() }
            .onReceive(NotificationCenter.default.publisher(for: .taskGlassFocusComposer)) { _ in focusComposer() }
            .onChange(of: store.connected) { _, connected in if connected { focusComposer() } }
            .sheet(isPresented: $showSetup) { SetupView(store: store) }
            .sheet(item: $editingTask) { task in
                TaskEditor(store: store, task: task, listID: store.selectedList, initialTitle: task.title)
            }
            .confirmationDialog("Disconnect Google Tasks and remove the local task cache?", isPresented: $confirmDisconnect) { Button("Disconnect", role: .destructive) { store.disconnect() } }
    }
    private var taskComposer: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                TextField("Add a task", text: $title)
                    .textFieldStyle(.plain).focused($composerFocus, equals: .title)
                    .onKeyPress(.tab, phases: .down) { press in
                        guard press.modifiers.isEmpty else { return .ignored }
                        composerFocus = .details
                        return .handled
                    }
                    .onSubmit { add() }.accessibilityLabel("New task title")
                Button { add() } label: { Image(systemName: "plus.circle.fill").font(.title3) }
                    .buttonStyle(.plain).foregroundStyle(.blue)
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.busy)
                    .keyboardShortcut(.return, modifiers: .command)
                    .accessibilityLabel("Add task").help("Add task (⌘Return)")
            }
            Divider()
            TextField("Details (optional)", text: $details, axis: .vertical)
                .textFieldStyle(.plain).font(.callout).lineLimit(1...4)
                .focused($composerFocus, equals: .details)
                .onKeyPress(keys: [.tab, KeyEquivalent("\u{19}")], phases: .down) { press in
                    guard press.modifiers.contains(.shift) || press.characters == "\u{19}" else { return .ignored }
                    composerFocus = .title
                    return .handled
                }
                .onKeyPress(.return, phases: .down) { press in
                    if press.modifiers.contains(.shift) {
                        guard let editor = NSApp.keyWindow?.firstResponder as? NSTextView else { return .ignored }
                        editor.insertText("\n", replacementRange: editor.selectedRange())
                        return .handled
                    }
                    add()
                    return .handled
                }
                .accessibilityLabel("New task details (optional)")
                .help("Return adds the task; Shift-Return inserts a new line")
        }.padding(11)
            .background(.background, in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(.quaternary))
    }
    private func focusComposer() {
        guard store.connected, !showSetup, editingTask == nil else { return }
        composerFocus = .title
    }
    private func add() {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !store.busy else { return }
        let draft = TaskDraft(title: title, details: details), listID = store.selectedList
        Task {
            if await store.saveTask(draft, listID: listID), title == draft.title, details == draft.details {
                title = ""; details = ""
                focusComposer()
            }
        }
    }
}
struct SetupView: View {
    @ObservedObject var store: TaskStore
    @Environment(\.dismiss) var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Connect Google Tasks").font(.title2.bold())
            Text("This personal build needs a Google Cloud Desktop app OAuth client. Credentials stay in your Mac’s Keychain.")
            Text("1. Create a Google Cloud project and enable the Google Tasks API.\n2. Configure Google Auth Platform: External audience, your email as a test user, and the Tasks scope.\n3. Create an OAuth client with application type Desktop app. Download its JSON file.")
                .font(.callout).foregroundStyle(.secondary)
            Link("Open Google Cloud setup ↗", destination: URL(string: "https://console.cloud.google.com/apis/library/tasks.googleapis.com")!)
            Button(store.hasClient ? "Replace OAuth JSON…" : "Import OAuth JSON…") { store.importClient() }.disabled(store.busy || store.connected)
            Button("Sign in with Google") { Task { await store.signIn(); if store.connected { dismiss() } } }.buttonStyle(.borderedProminent).disabled(!store.hasClient || store.busy || store.connected)
            if store.busy { HStack { ProgressView().controlSize(.small); Text("Finish sign-in in your browser…"); Button("Cancel sign-in") { store.auth.cancel() } } }
            if let error = store.error { Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled) }
            Text("Google testing-mode refresh tokens may expire after 7 days. Reconnect if Google asks. No Google password is entered here.").font(.caption).foregroundStyle(.secondary)
            HStack { Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.cancelAction) }
        }.padding(24).frame(width: 480)
    }
}


struct TaskEditor: View {
    @ObservedObject var store: TaskStore
    var task: GoogleTask?
    var listID: String
    var onSaved: () -> Void = {}
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var details: String

    init(store: TaskStore, task: GoogleTask?, listID: String, initialTitle: String, onSaved: @escaping () -> Void = {}) {
        self.store = store; self.task = task; self.listID = listID; self.onSaved = onSaved
        _title = State(initialValue: initialTitle); _details = State(initialValue: task?.notes ?? "")
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(task == nil ? "New task" : "Edit task").font(.title2.bold())
            VStack(alignment: .leading, spacing: 6) {
                Text("Title").font(.headline)
                TextField("Task title", text: $title).textFieldStyle(.roundedBorder)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Details").font(.headline)
                TextEditor(text: $details).font(.body).frame(minHeight: 140)
                    .padding(5).background(.background, in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
                    .accessibilityLabel("Task details")
                Text("Details sync with Google Tasks.").font(.caption).foregroundStyle(.secondary)
            }
            if let error = store.error { Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled) }
            HStack {
                if store.busy { ProgressView().controlSize(.small) }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction).disabled(store.busy)
                Button(task == nil ? "Add task" : "Save") {
                    Task {
                        if await store.saveTask(TaskDraft(title: title, details: details), taskID: task?.id, listID: listID) {
                            onSaved(); dismiss()
                        }
                    }
                }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
                    .disabled(store.busy || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(24).frame(width: 440).interactiveDismissDisabled(store.busy)
    }
}

struct TaskGlassSettings: View {
    @ObservedObject var store: TaskStore
    var body: some View {
        Form {
            Section("Appearance") {
                LabeledContent("App location", value: "Menu bar only")
                Text("TaskGlass stays in the menu bar, never in the Dock. Closing the window keeps syncing. Use the widget or menu bar icon to reopen it; Quit stops syncing.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Google Tasks") {
                LabeledContent("Connection", value: store.connected ? "Connected" : "Not connected")
                Picker("Refresh every", selection: $store.refreshInterval) {
                    ForEach(RefreshInterval.allCases) { interval in Text(interval.label).tag(interval) }
                }
                Text("Applies immediately and is remembered between launches. macOS controls when widgets display updates.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped).padding(8).frame(width: 430, height: 370)
    }
}
