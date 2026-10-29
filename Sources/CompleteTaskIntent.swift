import AppIntents

struct CompleteTaskIntent: AppIntent {
    static var title: LocalizedStringResource = "Complete Google Task"
    static var description = IntentDescription("Mark a Google task as completed from the desktop widget.")
    static var openAppWhenRun: Bool = false
    static var isDiscoverable: Bool = false

    @Parameter(title: "Task ID") var taskID: String
    @Parameter(title: "List ID") var listID: String

    init() {}
    init(taskID: String, listID: String) { self.taskID = taskID; self.listID = listID }

    func perform() async throws -> some IntentResult {
        #if TASKGLASS_APP
        try await TaskStore.shared.completeTask(taskID: taskID, listID: listID)
        #else
        // Credentials deliberately remain in the companion's Keychain. The
        // companion's ForegroundContinuableIntent conformance routes execution
        // into that process, without bringing its window to the front.
        throw AppError.message("Open TaskGlass once, then try completing this task again.")
        #endif
        return .result()
    }
}

#if TASKGLASS_APP
// Forces execution in the app process, including when macOS must launch it.
// We never request foreground continuation: the checkbox stays on the desktop.
@available(macOSApplicationExtension, unavailable)
extension CompleteTaskIntent: ForegroundContinuableIntent {}
#endif
