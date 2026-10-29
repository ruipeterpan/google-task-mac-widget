import SwiftUI
import AppKit

@MainActor enum AppPresence {
    static func apply(hideDockIcon: Bool) {
        NSApp.setActivationPolicy(hideDockIcon ? .accessory : .regular)
    }
}
final class TaskGlassAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppPresence.apply(hideDockIcon: UserDefaults.standard.bool(forKey: "hideDockIcon"))
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

@main struct TaskGlassApp: App {
    @NSApplicationDelegateAdaptor(TaskGlassAppDelegate.self) private var appDelegate
    @StateObject private var store = TaskStore.shared
    var body: some Scene {
        WindowGroup("TaskGlass", id: "tasks") {
            TasksView(store: store).frame(minWidth: 360, idealWidth: 390, minHeight: 420, idealHeight: 540)
                .onOpenURL { _ in NSApp.activate(ignoringOtherApps: true); Task { await store.sync() } }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in Task { await store.sync() } }
        }.defaultSize(width: 390, height: 540)
        Settings { TaskGlassSettings(store: store) }
        MenuBarExtra("TaskGlass", systemImage: "checkmark.circle") {
            MenuContents(store: store)
        }
    }
}
struct MenuContents: View {
    @ObservedObject var store: TaskStore
    @Environment(\.openWindow) var openWindow
    var body: some View {
        Button("Open TaskGlass") { openWindow(id: "tasks"); NSApp.activate(ignoringOtherApps: true) }
        Button("Refresh now") { Task { await store.sync() } }.disabled(store.busy || !store.connected)
        if let updated = store.updated { Text("Synced \(updated.formatted(date: .omitted, time: .shortened))") }
        Divider()
        SettingsLink { Text("Settings…") }.keyboardShortcut(",")
        Button("Quit TaskGlass") { NSApplication.shared.terminate(nil) }
    }
}
struct TasksView: View {
    @ObservedObject var store: TaskStore
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
                Menu { SettingsLink { Text("Settings…") }; Button("Connection setup") { showSetup = true }; if store.connected { Button("Disconnect Google…", role: .destructive) { confirmDisconnect = true }.disabled(store.busy) } } label: { Image(systemName: "gearshape") }.menuStyle(.borderlessButton).frame(width: 24)
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
        }.padding(22).sheet(isPresented: $showSetup) { SetupView(store: store) }
            .sheet(item: $editingTask) { task in
                TaskEditor(store: store, task: task, listID: store.selectedList, initialTitle: task.title)
            }
            .confirmationDialog("Disconnect Google Tasks and remove the local task cache?", isPresented: $confirmDisconnect) { Button("Disconnect", role: .destructive) { store.disconnect() } }
    }
    private var taskComposer: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                TextField("Add a task", text: $title)
                    .textFieldStyle(.plain).onSubmit { add() }.accessibilityLabel("New task title")
                Button { add() } label: { Image(systemName: "plus.circle.fill").font(.title3) }
                    .buttonStyle(.plain).foregroundStyle(.blue)
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.busy)
                    .keyboardShortcut(.return, modifiers: .command)
                    .accessibilityLabel("Add task").help("Add task (⌘Return)")
            }
            Divider()
            TextField("Details (optional)", text: $details, axis: .vertical)
                .textFieldStyle(.plain).font(.callout).lineLimit(1...4)
                .accessibilityLabel("New task details (optional)")
        }.padding(11)
            .background(.background, in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(.quaternary))
    }
    private func add() {
        let draft = TaskDraft(title: title, details: details), listID = store.selectedList
        Task {
            if await store.saveTask(draft, listID: listID), title == draft.title, details == draft.details {
                title = ""; details = ""
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
    @AppStorage("hideDockIcon") private var hideDockIcon = false
    var body: some View {
        Form {
            Section("Appearance") {
                Toggle("Hide Dock icon", isOn: $hideDockIcon)
                    .onChange(of: hideDockIcon) { _, value in AppPresence.apply(hideDockIcon: value) }
                Text("TaskGlass stays in the menu bar and continues syncing. Use its menu bar icon to open the task window or settings.")
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
