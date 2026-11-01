import Foundation

struct TaskList: Codable, Identifiable, Hashable { let id: String; var title: String }
struct GoogleTask: Codable, Identifiable, Hashable {
    let id: String
    var title: String
    var notes: String?
    var due: String?
    var status: String
    var parent: String?
    var position: String?
    var isComplete: Bool { status == "completed" }
    // Tasks due dates are calendar dates; do not shift midnight UTC into yesterday locally.
    var dueDate: Date? {
        guard let due else { return nil }
        let formatter = DateFormatter(); formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: String(due.prefix(10)))
    }
}
struct Page<T: Decodable>: Decodable { var items: [T]?; var nextPageToken: String? }
struct OAuthClient: Codable {
    var client_id: String
    var client_secret: String?
    static func load(_ data: Data) throws -> Self {
        struct Envelope: Decodable { var installed: OAuthClient }
        return try JSONDecoder().decode(Envelope.self, from: data).installed
    }
}
struct Tokens: Codable {
    var access: String
    var refresh: String
    var expiry: Date
}
enum CompletionTiming {
    static let holdDuration: TimeInterval = 0.7
}

struct CompletionFeedback: Codable {
    var listID: String
    var task: GoogleTask
    // nil means the Google request is still pending. A confirmed completion
    // stays visible briefly, then disappears on its own timeline entry.
    var removeAfter: Date?
}
struct TaskCache: Codable {
    var listTitle: String
    var tasks: [GoogleTask]
    var updated: Date
    var listID: String? = nil
    var completionFeedback: [CompletionFeedback]? = nil

    var incompleteCount: Int {
        let checkedIDs = Set((completionFeedback ?? []).map { $0.task.id })
        return tasks.filter { !$0.isComplete && !checkedIDs.contains($0.id) }.count
    }
    func displayedTasks(at date: Date) -> [GoogleTask] {
        var rows = tasks
        for feedback in completionFeedback ?? [] {
            guard feedback.removeAfter.map({ $0 > date }) ?? true else { continue }
            var checked = feedback.task; checked.status = "completed"
            if let index = rows.firstIndex(where: { $0.id == checked.id }) { rows[index] = checked }
            else { rows.append(checked) }
        }
        return rows.enumerated().sorted {
            let left = $0.element.position ?? "", right = $1.element.position ?? ""
            return left == right ? $0.offset < $1.offset : left < right
        }.map(\.element)
    }
    func feedbackTransitionDates(after date: Date) -> [Date] {
        Array(Set((completionFeedback ?? []).compactMap(\.removeAfter).filter { $0 > date })).sorted()
    }
}
enum AppError: LocalizedError {
    case message(String)
    var errorDescription: String? { switch self { case .message(let text): text } }
}
func formEncoded(_ values: [String: String]) -> Data {
    var allowed = CharacterSet.alphanumerics; allowed.insert(charactersIn: "-._~")
    return values.sorted { $0.key < $1.key }.map {
        $0.key.addingPercentEncoding(withAllowedCharacters: allowed)! + "=" + $0.value.addingPercentEncoding(withAllowedCharacters: allowed)!
    }.joined(separator: "&").data(using: .utf8)!
}
func checkHTTP(_ data: Data, _ response: URLResponse) throws {
    guard let http = response as? HTTPURLResponse else { throw AppError.message("No response from Google.") }
    guard (200..<300).contains(http.statusCode) else {
        struct Failure: Decodable { struct Detail: Decodable { var message: String }; var error: Detail }
        let detail = (try? JSONDecoder().decode(Failure.self, from: data).error.message) ?? "Google returned HTTP \(http.statusCode). Try signing in again."
        throw AppError.message(detail)
    }
}

struct TaskDraft {
    var title: String
    var details: String

    func apiFields() throws -> [String: String] {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { throw AppError.message("Enter a task title.") }
        guard title.count <= 1024 else { throw AppError.message("Task titles can contain up to 1,024 characters.") }
        guard details.count <= 8192 else { throw AppError.message("Details can contain up to 8,192 characters.") }
        // Patch only title and notes, preserving Google dates, times and all
        // other fields that cannot be represented by this editor.
        return ["title": title, "notes": details]
    }
}

enum RefreshInterval: Int, CaseIterable, Identifiable {
    case thirtySeconds = 30
    case oneMinute = 60
    case threeMinutes = 180
    case fiveMinutes = 300
    case tenMinutes = 600
    case thirtyMinutes = 1800
    var id: Int { rawValue }
    var label: String {
        switch self {
        case .thirtySeconds: "30 seconds"
        case .oneMinute: "1 minute"
        case .threeMinutes: "3 minutes"
        case .fiveMinutes: "5 minutes"
        case .tenMinutes: "10 minutes"
        case .thirtyMinutes: "30 minutes"
        }
    }
    static func savedValue(_ seconds: Int) -> Self { Self(rawValue: seconds) ?? .oneMinute }
}

struct TaskDetailsLink {
    var range: NSRange
    var url: URL
}

enum TaskDetailsLinks {
    static func detect(in text: String) -> [TaskDetailsLink] {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return [] }
        return detector.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
            guard let url = match.url, let scheme = url.scheme?.lowercased(),
                  scheme == "https" || scheme == "http" else { return nil }
            return TaskDetailsLink(range: match.range, url: url)
        }
    }
}
