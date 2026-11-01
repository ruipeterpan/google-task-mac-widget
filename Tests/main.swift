import Foundation

func expect(_ value: @autoclosure () -> Bool, _ message: String) {
    guard value() else { fatalError(message) }
}
let encoded = String(data: formEncoded(["a": "x+y&z =/?", "unicode": "任务"]), encoding: .utf8)!
expect(encoded == "a=x%2By%26z%20%3D%2F%3F&unicode=%E4%BB%BB%E5%8A%A1", "OAuth form encoding corrupted a value")
let raw = Data(#"{"id":"t","title":"Test","due":"2026-10-28T00:00:00.000Z","status":"needsAction"}"#.utf8)
let task = try JSONDecoder().decode(GoogleTask.self, from: raw)
for zone in ["America/Los_Angeles", "America/New_York", "Asia/Shanghai"] {
    NSTimeZone.default = TimeZone(identifier: zone)!
    let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd"
    expect(formatter.string(from: task.dueDate!) == "2026-10-28", "Due date shifted in \(zone)")
}
expect(!task.isComplete, "Incomplete task incorrectly completed")
let empty = try JSONDecoder().decode(Page<TaskList>.self, from: Data(#"{}"#.utf8))
expect(empty.items == nil && empty.nextPageToken == nil, "Empty page handling")
let page = try JSONDecoder().decode(Page<TaskList>.self, from: Data(#"{"items":[{"id":"a","title":"Work"}],"nextPageToken":"page-2"}"#.utf8))
expect(page.items?.count == 1 && page.nextPageToken == "page-2", "Pagination decoding")
let client = try OAuthClient.load(Data(#"{"installed":{"client_id":"test.apps.googleusercontent.com","client_secret":"secret"}}"#.utf8))
expect(client.client_secret == "secret", "Desktop OAuth JSON decoding")
do {
    _ = try OAuthClient.load(Data(#"{"web":{"client_id":"wrong"}}"#.utf8))
    fatalError("Web OAuth credentials accepted")
} catch {}
let cache = TaskCache(listTitle: "Test", tasks: [task], updated: Date())
let decoded = try JSONDecoder().decode(TaskCache.self, from: JSONEncoder().encode(cache))
expect(decoded.tasks == [task], "Widget cache failed to round trip")
let url = URL(string: "https://tasks.googleapis.com/")!
try checkHTTP(Data(), HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
do {
    try checkHTTP(Data(#"{"error":{"message":"Permission denied"}}"#.utf8), HTTPURLResponse(url: url, statusCode: 403, httpVersion: nil, headerFields: nil)!)
    fatalError("HTTP failure was ignored")
} catch { expect(error.localizedDescription == "Permission denied", "API error was not preserved") }
print("PASS: form encoding, due dates in 3 time zones, empty pages, pagination decoding, OAuth client import, cache round trip, HTTP error handling")

let legacyCache = try JSONDecoder().decode(TaskCache.self, from: Data(#"{"listTitle":"Old cache","tasks":[],"updated":0}"#.utf8))
expect(legacyCache.listID == nil, "Existing widget cache must remain readable after upgrading")
let routedCache = TaskCache(listTitle: "Other list", tasks: [task], updated: Date(), listID: "exact-list-id")
let routedDecoded = try JSONDecoder().decode(TaskCache.self, from: JSONEncoder().encode(routedCache))
expect(routedDecoded.listID == "exact-list-id", "Widget completion must retain the exact list ID")
print("PASS: backward-compatible widget cache and completion list routing")

// Completion presentation: optimistic check/count, confirmed hold, timed removal,
// rollback, multiple completions, and completing the very last task.
let presentationTime = Date(timeIntervalSince1970: 10000)
let rowA = GoogleTask(id: "A", title: "First", status: "needsAction", position: "01")
let rowB = GoogleTask(id: "B", title: "Second", status: "needsAction", position: "02")
let pendingA = CompletionFeedback(listID: "L", task: rowA)
let pendingCache = TaskCache(listTitle: "L", tasks: [rowA, rowB], updated: presentationTime, listID: "L", completionFeedback: [pendingA])
expect(pendingCache.incompleteCount == 1, "Count must decrease while a completion request is pending")
expect(pendingCache.displayedTasks(at: presentationTime).count == 2, "Checked row must remain visible")
expect(pendingCache.displayedTasks(at: presentationTime).first?.isComplete == true, "Pending circle must be filled")
expect(pendingCache.feedbackTransitionDates(after: presentationTime).isEmpty, "Pending request must not disappear before Google confirms")
let removalTime = presentationTime.addingTimeInterval(CompletionTiming.holdDuration)
let confirmedA = CompletionFeedback(listID: "L", task: rowA, removeAfter: removalTime)
let confirmedCache = TaskCache(listTitle: "L", tasks: [rowB], updated: presentationTime, listID: "L", completionFeedback: [confirmedA])
expect(confirmedCache.incompleteCount == 1, "Acknowledgment must not decrement the count twice")
expect(confirmedCache.displayedTasks(at: presentationTime).map(\.id) == ["A", "B"], "Completed row must keep its original position")
expect(confirmedCache.displayedTasks(at: removalTime.addingTimeInterval(-0.01)).count == 2, "Checked row disappeared too early")
expect(confirmedCache.displayedTasks(at: removalTime).map(\.id) == ["B"], "Checked row must disappear at its timeline boundary")
expect(confirmedCache.feedbackTransitionDates(after: presentationTime) == [removalTime], "Timeline must include the removal deadline")
let rolledBack = TaskCache(listTitle: "L", tasks: [rowA, rowB], updated: presentationTime, listID: "L", completionFeedback: [])
expect(rolledBack.incompleteCount == 2 && rolledBack.displayedTasks(at: presentationTime).allSatisfy { !$0.isComplete }, "Failed completion must restore count and unchecked state")
let finalCache = TaskCache(listTitle: "L", tasks: [], updated: presentationTime, listID: "L", completionFeedback: [confirmedA])
expect(finalCache.incompleteCount == 0 && finalCache.displayedTasks(at: presentationTime).count == 1, "Last completed task must stay visible during feedback")
expect(finalCache.displayedTasks(at: removalTime).isEmpty, "Empty state must appear after the last checked row disappears")
let confirmedB = CompletionFeedback(listID: "L", task: rowB, removeAfter: removalTime.addingTimeInterval(0.5))
let multipleCache = TaskCache(listTitle: "L", tasks: [], updated: presentationTime, listID: "L", completionFeedback: [confirmedB, confirmedA])
expect(multipleCache.displayedTasks(at: presentationTime).map(\.id) == ["A", "B"], "Rapid completions must preserve task order")
expect(multipleCache.displayedTasks(at: removalTime).map(\.id) == ["B"], "Rapid completions must expire independently")
expect(multipleCache.feedbackTransitionDates(after: presentationTime) == [removalTime, removalTime.addingTimeInterval(0.5)], "Timeline boundaries must be ordered")
let restoredFeedback = try JSONDecoder().decode(TaskCache.self, from: JSONEncoder().encode(confirmedCache))
expect(restoredFeedback.displayedTasks(at: presentationTime).first?.isComplete == true, "Checked feedback must survive widget cache serialization")
print("PASS: optimistic count/check, confirmation hold, timed removal, rollback, rapid completions, last-task empty state, and feedback serialization")

let draftFields = try TaskDraft(title: "  Follow up  ", details: "First line\n\nSecond line: 任务").apiFields()
expect(draftFields["title"] == "Follow up", "Task editor must trim title whitespace")
expect(draftFields["notes"] == "First line\n\nSecond line: 任务", "Details formatting must survive serialization")
expect(Set(draftFields.keys) == Set(["title", "notes"]), "Editing details must not overwrite remote date/time or completion fields")
let clearedFields = try TaskDraft(title: "Task", details: "").apiFields()
expect(clearedFields["notes"] == "", "Clearing details must send an empty notes field")
for invalid in [TaskDraft(title: " \n ", details: ""), TaskDraft(title: String(repeating: "a", count: 1025), details: ""), TaskDraft(title: "Task", details: String(repeating: "a", count: 8193))] {
    do { _ = try invalid.apiFields(); fatalError("Invalid task draft accepted") } catch {}
}
print("PASS: details formatting/clearing, title validation, field limits, and preserving remote scheduling fields")

expect(RefreshInterval.allCases.map(\.rawValue) == [30, 60, 180, 300, 600, 1800], "Refresh choices must match the requested six intervals")
expect(RefreshInterval.allCases.map(\.label) == ["30 seconds", "1 minute", "3 minutes", "5 minutes", "10 minutes", "30 minutes"], "Refresh labels must match actual durations")
expect(RefreshInterval.savedValue(0) == .oneMinute && RefreshInterval.savedValue(-30) == .oneMinute && RefreshInterval.savedValue(999) == .oneMinute, "Missing or invalid preferences must safely use the default")
for interval in RefreshInterval.allCases { expect(RefreshInterval.savedValue(interval.rawValue) == interval, "Saved refresh choice must round trip") }
print("PASS: six refresh intervals, labels/durations, saved settings, and default handling")

let linkNotes = "Read 📚 https://example.com/a?q=1&x=2, then\nvisit https://example.org/path."
let links = TaskDetailsLinks.detect(in: linkNotes)
expect(links.count == 2, "Both URLs in multiline Unicode details should be detected")
let linkLabels = links.map { (linkNotes as NSString).substring(with: $0.range) }
expect(linkLabels == ["https://example.com/a?q=1&x=2", "https://example.org/path"], "Link ranges should preserve URLs and exclude sentence punctuation")
expect(links[0].url.absoluteString == "https://example.com/a?q=1&x=2", "Query string should remain intact")
expect(TaskDetailsLinks.detect(in: "Just plain details.").isEmpty, "Plain details should stay plain")
expect(TaskDetailsLinks.detect(in: "file:///tmp/example.txt").isEmpty, "Only browser HTTP/HTTPS links should be enabled")
print("PASS: details links, Unicode ranges, multiline text, query strings, punctuation, and plain-text preservation")
