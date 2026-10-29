import AppKit
import Combine
import WidgetKit

@MainActor final class TaskStore: ObservableObject {
    static let shared = TaskStore()
    @Published var lists: [TaskList] = []
    @Published var tasks: [GoogleTask] = []
    @Published var selectedList = UserDefaults.standard.string(forKey: "selectedList") ?? ""
    @Published var listTitle = "My tasks"
    @Published var busy = false
    @Published var error: String?
    @Published var updated: Date?
    @Published var connected = false
    @Published var hasClient = false
    @Published var refreshInterval = RefreshInterval.savedValue(UserDefaults.standard.integer(forKey: "refreshIntervalSeconds")) {
        didSet {
            UserDefaults.standard.set(refreshInterval.rawValue, forKey: "refreshIntervalSeconds")
            scheduleRefresh()
        }
    }
    let auth = GoogleAuth()
    private var timer: Timer?
    private var completionFeedback: [CompletionFeedback] = []
    init() {
        connected = auth.signedIn; hasClient = auth.client != nil
        if let cache = SharedCache.read() { tasks = cache.tasks; listTitle = cache.listTitle; updated = cache.updated }
        scheduleRefresh()
        Task { await sync() }
    }
    private func scheduleRefresh() {
        timer?.invalidate()
        let next = Timer(timeInterval: TimeInterval(refreshInterval.rawValue), repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.sync() }
        }
        RunLoop.main.add(next, forMode: .common)
        timer = next
    }
    func importClient() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]; panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            do { try auth.importClient(Data(contentsOf: url)); hasClient = true; error = nil }
            catch { self.error = error.localizedDescription }
        }
    }
    func signIn() async {
        guard !busy else { return }; busy = true; error = nil
        do { try await auth.signIn(); connected = true } catch { self.error = error.localizedDescription }
        busy = false
        if connected { await sync() }
    }
    func disconnect() {
        auth.disconnect(); connected = false; hasClient = false; tasks = []; lists = []; updated = nil; error = nil
        completionFeedback = []
        SharedCache.remove(); WidgetCenter.shared.reloadAllTimelines()
    }
    private func request(_ path: String, method: String = "GET", body: [String: String]? = nil, query: [URLQueryItem] = []) async throws -> Data {
        var url = URLComponents(string: "https://tasks.googleapis.com/tasks/v1/" + path)!
        url.queryItems = query.isEmpty ? nil : query
        var request = URLRequest(url: url.url!); request.httpMethod = method; request.timeoutInterval = 30
        request.setValue("Bearer \(try await auth.accessToken())", forHTTPHeaderField: "Authorization")
        if let body { request.httpBody = try JSONSerialization.data(withJSONObject: body); request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        let (data, response) = try await URLSession.shared.data(for: request); try checkHTTP(data, response); return data
    }
    private func pages<T: Decodable>(_ path: String, query: [URLQueryItem] = []) async throws -> [T] {
        var result: [T] = []; var pageToken: String?
        repeat {
            var parameters = query + [URLQueryItem(name: "maxResults", value: "100")]
            if let pageToken { parameters.append(URLQueryItem(name: "pageToken", value: pageToken)) }
            let page = try JSONDecoder().decode(Page<T>.self, from: await request(path, query: parameters))
            result += page.items ?? []; pageToken = page.nextPageToken
        } while pageToken != nil
        return result
    }
    private func segment(_ value: String) -> String { value.addingPercentEncoding(withAllowedCharacters: .alphanumerics)! }
    func sync() async {
        guard connected, !busy else { return }; busy = true; defer { busy = false }
        do {
            let fetchedLists: [TaskList] = try await pages("users/@me/lists")
            lists = fetchedLists
            guard let selected = lists.first(where: { $0.id == selectedList }) ?? lists.first else {
                tasks = []; listTitle = "No task lists"; updated = Date(); try publish(); error = nil; return
            }
            
            let fetched: [GoogleTask] = try await pages("lists/\(segment(selected.id))/tasks", query: [URLQueryItem(name: "showCompleted", value: "false"), URLQueryItem(name: "showAssigned", value: "true")])
            selectedList = selected.id; listTitle = selected.title
            UserDefaults.standard.set(selectedList, forKey: "selectedList")
            tasks = fetched.filter { !$0.isComplete }.sorted { ($0.position ?? "") < ($1.position ?? "") }
            updated = Date(); try publish(); error = nil
        } catch { self.error = error.localizedDescription }
    }
    private func publish() throws {
        try SharedCache.write(TaskCache(listTitle: listTitle, tasks: tasks, updated: updated ?? Date(), listID: selectedList, completionFeedback: completionFeedback.filter { $0.listID == selectedList }))
        WidgetCenter.shared.reloadTimelines(ofKind: "TaskGlassWidget")
    }
    func complete(_ task: GoogleTask) async {
        do { try await completeTask(taskID: task.id, listID: selectedList) }
        catch { self.error = error.localizedDescription }
    }
    func completeTask(taskID: String, listID: String) async throws {
        // Serialize widget actions with refreshes and other checkbox actions.
        let deadline = Date().addingTimeInterval(35)
        while busy {
            guard Date() < deadline else { throw AppError.message("TaskGlass is still syncing. Please try again shortly.") }
            try await Task.sleep(for: .milliseconds(100))
        }
        guard connected else { throw AppError.message("Open TaskGlass and connect Google Tasks first.") }
        guard !taskID.isEmpty, !listID.isEmpty else { throw AppError.message("Refresh TaskGlass and try again.") }
        // An already checked row is presentation feedback, not a request to
        // un-complete it. Ignore repeated taps while it is fading away.
        guard !completionFeedback.contains(where: { $0.listID == listID && $0.task.id == taskID }) else { return }
        busy = true
        let task = selectedList == listID ? tasks.first(where: { $0.id == taskID }) : nil
        if let task { completionFeedback.append(CompletionFeedback(listID: listID, task: task)) }
        do {
            // Publish the checked circle and reduced count before the network
            // round trip. The native Toggle also gives immediate tap feedback.
            if task != nil { try publish() }
            _ = try await request("lists/\(segment(listID))/tasks/\(segment(taskID))", method: "PATCH", body: ["status": "completed"])
            let removeAfter = Date().addingTimeInterval(CompletionTiming.holdDuration)
            if let index = completionFeedback.firstIndex(where: { $0.listID == listID && $0.task.id == taskID }) {
                completionFeedback[index].removeAfter = removeAfter
            }
            if selectedList == listID { tasks.removeAll { $0.id == taskID }; updated = Date() }
            try publish()
            error = nil
            busy = false
            // The widget has a matching future timeline entry, so removal does
            // not depend on another discretionary background reload.
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(CompletionTiming.holdDuration + 0.1))
                self.completionFeedback.removeAll {
                    $0.listID == listID && $0.task.id == taskID && $0.removeAfter == removeAfter
                }
                try? self.publish()
                await self.sync()
            }
        } catch {
            completionFeedback.removeAll { $0.listID == listID && $0.task.id == taskID }
            self.error = error.localizedDescription
            try? publish() // Roll back the circle and count on API failure.
            busy = false
            throw error
        }
    }
    func add(_ title: String) async -> Bool {
        await saveTask(TaskDraft(title: title, details: ""))
    }
    func saveTask(_ draft: TaskDraft, taskID: String? = nil, listID: String? = nil) async -> Bool {
        let targetList = listID ?? selectedList
        guard connected, !targetList.isEmpty, !busy else { return false }
        let fields: [String: String]
        do { fields = try draft.apiFields() }
        catch { self.error = error.localizedDescription; return false }
        busy = true; error = nil
        do {
            let path = "lists/\(segment(targetList))/tasks" + (taskID.map { "/" + segment($0) } ?? "")
            _ = try await request(path, method: taskID == nil ? "POST" : "PATCH", body: fields)
        } catch { self.error = error.localizedDescription; busy = false; return false }
        busy = false; await sync(); return true
    }
}
