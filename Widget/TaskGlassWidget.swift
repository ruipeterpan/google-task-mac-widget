import WidgetKit
import SwiftUI
import AppIntents

struct TasksEntry: TimelineEntry { var date: Date; var cache: TaskCache?; var preview = false }
struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> TasksEntry { sample }
    func getSnapshot(in context: Context, completion: @escaping (TasksEntry) -> Void) {
        completion(context.isPreview ? sample : TasksEntry(date: Date(), cache: SharedCache.read()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<TasksEntry>) -> Void) {
        let now = Date(), cache = SharedCache.read()
        let dates = [now] + (cache?.feedbackTransitionDates(after: now) ?? [])
        completion(Timeline(entries: dates.map { TasksEntry(date: $0, cache: cache) }, policy: .after(now.addingTimeInterval(15 * 60))))
    }
    private var sample: TasksEntry {
        TasksEntry(date: Date(), cache: TaskCache(listTitle: "My Tasks", tasks: [GoogleTask(id: "1", title: "Review the paper before tomorrow", status: "needsAction"), GoogleTask(id: "2", title: "Prepare for the interview", status: "needsAction"), GoogleTask(id: "3", title: "Pick up groceries", status: "needsAction")], updated: Date()), preview: true)
    }
}
struct WidgetContent: View {
    var entry: TasksEntry
    var family: WidgetFamily
    var capacity: Int { family == .systemLarge ? 6 : 3 }
    private var taskFont: Font { .system(size: 14, weight: .medium, design: .rounded) }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 8) {
                Text(entry.cache?.listTitle ?? "TaskGlass")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .lineLimit(1).minimumScaleFactor(0.85).padding(.top, 3)
                Spacer(minLength: 0)
                if let cache = entry.cache {
                    Text("\(cache.incompleteCount)")
                        .font(.system(size: 25, weight: .bold, design: .rounded))
                        .monospacedDigit().contentTransition(.numericText())
                        .fixedSize().accessibilityLabel("\(cache.incompleteCount) incomplete tasks")
                }
            }.frame(height: 28, alignment: .top)
            if let cache = entry.cache {
                if cache.displayedTasks(at: entry.date).isEmpty {
                    Text("All Tasks\nCompleted").font(taskFont).padding(.top, 6)
                } else {
                    if family == .systemSmall {
                        // Show a third short task when it fits, retaining two
                        // lines per title when longer entries need the space.
                        ViewThatFits(in: .vertical) {
                            taskRows(cache, limit: 3).fixedSize(horizontal: false, vertical: true)
                            taskRows(cache, limit: 2).fixedSize(horizontal: false, vertical: true)
                            taskRows(cache, limit: 1).fixedSize(horizontal: false, vertical: true)
                        }.padding(.top, 6)
                    } else {
                        taskRows(cache, limit: capacity).padding(.top, 6)
                    }
                }
                Spacer(minLength: 6)
                HStack(spacing: 4) {
                    Image(systemName: "arrow.clockwise").font(.system(size: 9))
                    Text(cache.updated, style: .relative).font(.system(size: 10))
                    if entry.preview { Text("· Preview").font(.system(size: 10)) }
                }.foregroundStyle(.tertiary)
                    .accessibilityLabel(Text("Last refreshed \(cache.updated, style: .relative) ago"))
            } else {
                Text("Open TaskGlass to connect Google Tasks.").font(taskFont).foregroundStyle(.secondary).padding(.top, 10)
                Spacer(minLength: 0)
            }
        }
    }
    private func taskRows(_ cache: TaskCache, limit: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(cache.displayedTasks(at: entry.date).prefix(limit))) { task in
                            HStack(alignment: .top, spacing: 10) {
                                if let listID = cache.listID, !entry.preview {
                                    Toggle(isOn: task.isComplete, intent: CompleteTaskIntent(taskID: task.id, listID: listID)) {
                                        Text(task.title)
                                    }.toggleStyle(CompletionCircleStyle())
                                        .disabled(task.isComplete)
                                        .accessibilityLabel("Complete \(task.title)")
                                } else { CompletionCircle(isChecked: task.isComplete) }
                                Text(task.title).font(taskFont)
                                    .lineLimit(family == .systemMedium ? 1 : 2)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                if family != .systemSmall, let date = task.dueDate {
                                    Text(date, format: .dateTime.month(.abbreviated).day())
                                        .font(.caption2).foregroundStyle(.secondary).padding(.top, 2)
                                }
                            }
                        }
        }
    }
}
struct CompletionCircle: View {
    var isChecked: Bool
    var body: some View {
        ZStack {
            Circle().strokeBorder(.primary.opacity(isChecked ? 0.7 : 0.24), lineWidth: 1.5)
            if isChecked { Circle().fill(.primary.opacity(0.7)).padding(4) }
        }.frame(width: 21, height: 21).contentShape(Circle())
    }
}
struct CompletionCircleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            CompletionCircle(isChecked: configuration.isOn)
        }.buttonStyle(.plain)
    }
}
struct WidgetView: View {
    var entry: TasksEntry
    @Environment(\.widgetFamily) var family
    var body: some View {
        WidgetContent(entry: entry, family: family)
            .padding(EdgeInsets(top: 8, leading: 16, bottom: 16, trailing: 16))
            .containerBackground(.background, for: .widget)
            .widgetURL(URL(string: "taskglass://open"))
    }
}
#if !WIDGET_PREVIEW
@main struct TaskGlassWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TaskGlassWidget", provider: Provider()) { WidgetView(entry: $0) }
            .configurationDisplayName("Google Tasks")
            .description("Your Google Tasks at a glance. Click a circle to complete a task.")
            .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
            .contentMarginsDisabled()
    }
}
#endif
