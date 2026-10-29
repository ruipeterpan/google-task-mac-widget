import Foundation

enum SharedCache {
    static var group: String { Bundle.main.object(forInfoDictionaryKey: "AppGroupIdentifier") as? String ?? "unconfigured.local.taskglass" }
    private static var url: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)?.appendingPathComponent("tasks.json")
    }
    static func read() -> TaskCache? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(TaskCache.self, from: data)
    }
    static func write(_ cache: TaskCache) throws {
        guard let url else { throw AppError.message("Shared widget storage unavailable. Check App Groups signing in Xcode.") }
        try JSONEncoder().encode(cache).write(to: url, options: [.atomic, .completeFileProtectionUnlessOpen])
    }
    static func remove() { if let url { try? FileManager.default.removeItem(at: url) } }
}
