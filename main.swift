import Charts
import ServiceManagement
import SwiftUI
import UserNotifications

/// Shows banners even while the popover is open (the app counts as frontmost then).
final class NotificationPresenter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationPresenter()

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }
}

// MARK: - Model

struct Usage: Codable {
    let updatedAt: Date
    let budget: Double
    let tools: [Tool]

    func total(_ window: Window) -> Double { tools.reduce(0) { $0 + $1.amount(window) } }

    /// Combined spend per hour right now (Cursor last hour, Claude active 5h block).
    var rate: Double { tools.reduce(0) { $0 + ($1.rate ?? 0) } }
}

func duration(hours: Double) -> String {
    let minutes = Int((hours * 60).rounded())
    return minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(max(minutes, 1))m"
}

struct Tool: Codable, Identifiable {
    let id: String
    let name: String
    let error: String?
    let today: Double
    let week: Double
    let month: Double
    let monthLabel: String
    let daily: [Day]
    let models: [Model]
    let limit: Double?
    let periodEnd: String?
    let rate: Double?
    let chats: [Chat]?

    struct Chat: Codable, Identifiable { let name: String; let cost: Double; let model: String; var id: String { name + model } }
    struct Day: Codable { let date: String; let cost: Double }
    struct Model: Codable, Identifiable { let name: String; let cost: Double; var id: String { name } }

    func amount(_ window: Window) -> Double {
        switch window {
        case .today: today
        case .week: week
        case .month: month
        }
    }

    var palette: [Color] {
        switch id {
        case "cursor": [Color(hex: 0x7C8CFF), Color(hex: 0xA46BFF)]
        case "claude": [Color(hex: 0xFF9A6B), Color(hex: 0xE0603F)]
        default: [Color(hex: 0x4BE3A4), Color(hex: 0x1FB57E)]
        }
    }

    var color: Color { palette[0] }
    var gradient: LinearGradient { LinearGradient(colors: palette, startPoint: .topLeading, endPoint: .bottomTrailing) }

    var symbol: String {
        switch id {
        case "cursor": "cursorarrow.rays"
        case "claude": "asterisk"
        default: "terminal"
        }
    }
}

enum Window: String, CaseIterable, Identifiable {
    case today = "Today", week = "Week", month = "Month"
    var id: String { rawValue }

    /// Days elapsed in the window including today, and the window's full length (weeks start Monday).
    var days: (elapsed: Int, total: Int) {
        let calendar = Calendar(identifier: .iso8601)
        let now = Date.now
        switch self {
        case .today:
            return (1, 1)
        case .week:
            let weekday = calendar.component(.weekday, from: now)
            return ((weekday + 5) % 7 + 1, 7)
        case .month:
            return (calendar.component(.day, from: now), calendar.range(of: .day, in: .month, for: now)?.count ?? 30)
        }
    }
}

// MARK: - Store

@MainActor
final class Store: ObservableObject {
    @Published var usage: Usage?
    @Published var isLoading = false
    @Published var failure: String?

    private let collector = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".local/bin/ai-usage").path
    private let cache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("ai-usage.json")
    private var timer: Timer?

    init(cachedOnly: Bool = false) {
        usage = try? Self.decoder.decode(Usage.self, from: Data(contentsOf: cache))
        guard !cachedOnly else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 600, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    func refresh() {
        guard !isLoading else { return }
        isLoading = true
        let collector = collector
        Task.detached {
            let result = Result { try Self.run(collector) }
            await MainActor.run {
                switch result {
                case .success(let data):
                    if let usage = try? Self.decoder.decode(Usage.self, from: data) {
                        self.usage = usage
                        self.failure = nil
                        try? data.write(to: self.cache)
                        Self.alertIfOverBudget(usage)
                    } else {
                        self.failure = "Collector returned unreadable output"
                    }
                case .failure(let error):
                    self.failure = error.localizedDescription
                }
                self.isLoading = false
            }
        }
    }

    /// Fraction of the daily budget that triggers each alert; each fires at most once per day.
    static let alertLevels: [Double] = [0.8, 1.0]

    /// Sends the highest level crossed today that has not been sent yet, and marks lower levels as sent.
    private static func alertIfOverBudget(_ usage: Usage) {
        let ratio = usage.total(.today) / usage.budget
        let day = Date.now.formatted(.iso8601.year().month().day())
        let crossed = alertLevels.filter { ratio >= $0 }
        guard let level = crossed.last, UserDefaults.standard.string(forKey: "lastAlert-\(level)") != day else { return }
        crossed.forEach { UserDefaults.standard.set(day, forKey: "lastAlert-\($0)") }
        notify(usage, level: level)
    }

    /// Native notification; calls `done` once it is handed to the system (or permission is denied).
    nonisolated static func notify(_ usage: Usage, level: Double, done: @escaping @Sendable () -> Void = {}) {
        let total = usage.total(.today)
        let content = UNMutableNotificationContent()
        content.title = level >= 1 ? "AI spend over budget" : "Approaching daily AI budget"
        content.subtitle = "Today \(total.dollars) of \(usage.budget.shortDollars) (\(Int((total / usage.budget * 100).rounded()))%)"
        var body = usage.tools.map { "\($0.name) \($0.today.dollars)" }.joined(separator: " · ")
        if level < 1, usage.rate > 0.5 {
            body += "\nAt \(usage.rate.dollars)/h you hit the limit in ~\(duration(hours: (usage.budget - total) / usage.rate))"
        }
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: "budget-\(level)", content: content, trigger: nil)
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return done() }
            center.add(request) { _ in done() }
        }
    }

    nonisolated private static func run(_ path: String) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = [path]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return data
    }
}

// MARK: - Formatting & theme

extension Double {
    var dollars: String { formatted(.currency(code: "USD").precision(.fractionLength(2)).locale(Locale(identifier: "en_US"))) }
    var shortDollars: String { formatted(.currency(code: "USD").precision(.fractionLength(0)).locale(Locale(identifier: "en_US"))) }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, opacity: opacity)
    }
}

enum Theme {
    static let background = LinearGradient(colors: [Color(hex: 0x14161D), Color(hex: 0x0B0C10)],
                                           startPoint: .top, endPoint: .bottom)
    static let card = Color.white.opacity(0.045)
    static let stroke = Color.white.opacity(0.07)
    static let primary = Color.white.opacity(0.94)
    static let secondary = Color.white.opacity(0.55)
    static let tertiary = Color.white.opacity(0.32)
    static let good = Color(hex: 0x4BE3A4)
    static let bad = Color(hex: 0xFF5C6C)
}

private let dayParser: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter
}()

// MARK: - Components

struct Card<Content: View>: View {
    var padding: CGFloat = 14
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 10) { content }
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.stroke))
    }
}

struct SegmentedPill: View {
    @Binding var selection: Window
    @Namespace private var pill

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Window.allCases) { window in
                Button {
                    withAnimation(.snappy(duration: 0.25)) { selection = window }
                } label: {
                    Text(window.rawValue)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(selection == window ? Theme.primary : Theme.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                        .background {
                            if selection == window {
                                Capsule().fill(Color.white.opacity(0.12))
                                    .matchedGeometryEffect(id: "pill", in: pill)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Capsule().fill(Color.black.opacity(0.35)))
        .overlay(Capsule().strokeBorder(Theme.stroke))
    }
}

/// Stacked spend bar against a budget; the track scales so the budget tick stays visible when over.
struct BudgetMeter: View {
    let tools: [Tool]
    let window: Window
    let budget: Double

    var body: some View {
        let total = tools.reduce(0) { $0 + $1.amount(window) }
        let scale = max(total, budget, 0.01)
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.07))
                HStack(spacing: 1.5) {
                    ForEach(tools.filter { $0.amount(window) > 0 }) { tool in
                        Rectangle().fill(tool.gradient)
                            .frame(width: max(3, geo.size.width * tool.amount(window) / scale - 1.5))
                    }
                }
                .clipShape(Capsule())
                Rectangle().fill(Theme.primary)
                    .frame(width: 2, height: geo.size.height + 6)
                    .offset(x: geo.size.width * budget / scale - 1)
                    .shadow(color: .black.opacity(0.6), radius: 2)
            }
        }
        .frame(height: 10)
    }
}

struct Sparkline: View {
    let tool: Tool
    var body: some View {
        Chart(tool.daily, id: \.date) { day in
            AreaMark(x: .value("Day", day.date), y: .value("Cost", day.cost))
                .foregroundStyle(LinearGradient(colors: [tool.color.opacity(0.35), tool.color.opacity(0)],
                                                startPoint: .top, endPoint: .bottom))
                .interpolationMethod(.catmullRom)
            LineMark(x: .value("Day", day.date), y: .value("Cost", day.cost))
                .foregroundStyle(tool.color)
                .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round))
                .interpolationMethod(.catmullRom)
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .frame(width: 54, height: 22)
    }
}

struct FooterButton: View {
    let title: String
    let symbol: String
    var isOn = false
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(isOn ? Theme.good : (isHovering ? Theme.primary : Theme.secondary))
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(Capsule().fill(Color.white.opacity(isHovering ? 0.1 : 0.05)))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

// MARK: - Popover

struct ContentView: View {
    @EnvironmentObject var store: Store
    @State private var window: Window = .today
    @State private var expanded: String?
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    init(window: Window = .today) { _window = State(initialValue: window) }

    var body: some View {
        VStack(spacing: 10) {
            header
            if let usage = store.usage {
                hero(usage)
                tools(usage)
                chart(usage)
            } else {
                ProgressView().controlSize(.small).tint(.white).frame(height: 160)
            }
            footer
        }
        .padding(14)
        .frame(width: 372)
        .background(Theme.background)
        .environment(\.colorScheme, .dark)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(LinearGradient(colors: [Color(hex: 0x7C8CFF), Color(hex: 0xFF9A6B)],
                                           startPoint: .topLeading, endPoint: .bottomTrailing),
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text("AI Usage").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.primary)
                Group {
                    if let failure = store.failure {
                        Text(failure).foregroundStyle(Theme.bad)
                    } else if store.isLoading {
                        Text("Refreshing…")
                    } else if let updated = store.usage?.updatedAt {
                        Text("Updated \(updated, format: .relative(presentation: .named))")
                    }
                }
                .font(.system(size: 11)).foregroundStyle(Theme.secondary).lineLimit(1)
            }
            Spacer()
            Button(action: store.refresh) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.secondary)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Color.white.opacity(0.06)))
                    .rotationEffect(.degrees(store.isLoading ? 360 : 0))
                    .animation(store.isLoading ? .linear(duration: 1).repeatForever(autoreverses: false) : .default,
                               value: store.isLoading)
            }
            .buttonStyle(.plain)
            .help("Refresh")
        }
    }

    private func hero(_ usage: Usage) -> some View {
        let total = usage.total(window)
        let days = window.days
        let budgetToDate = usage.budget * Double(days.elapsed)
        let isOver = total > budgetToDate
        let status = isOver ? Theme.bad : Theme.good
        return Card(padding: 16) {
            SegmentedPill(selection: $window)

            HStack(alignment: .firstTextBaseline) {
                Text(total.dollars)
                    .font(.system(size: 38, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(isOver
                        ? AnyShapeStyle(LinearGradient(colors: [Color(hex: 0xFF8A7A), Theme.bad], startPoint: .top, endPoint: .bottom))
                        : AnyShapeStyle(Theme.primary))
                    .contentTransition(.numericText(value: total))
                    .animation(.snappy, value: total)
                Spacer()
                Text("\(Int((total / budgetToDate * 100).rounded()))%")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(status)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(status.opacity(0.14)))
            }
            .padding(.top, 2)

            BudgetMeter(tools: usage.tools, window: window, budget: budgetToDate)

            HStack {
                Text(isOver ? "\((total - budgetToDate).dollars) over \(budgetToDate.shortDollars)"
                            : "\((budgetToDate - total).dollars) left of \(budgetToDate.shortDollars)")
                    .foregroundStyle(isOver ? Theme.bad : Theme.secondary)
                Spacer()
                if window != .today {
                    Text("\(days.elapsed)/\(days.total)d · avg \((total / Double(days.elapsed)).shortDollars)/day")
                        .foregroundStyle(Theme.tertiary)
                }
            }
            .font(.system(size: 11, weight: .medium))

            pace(usage, total: total, budgetToDate: budgetToDate)
        }
        .background(
            RadialGradient(colors: [status.opacity(0.18), .clear], center: .topTrailing, startRadius: 0, endRadius: 260)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        )
    }

    @ViewBuilder
    private func pace(_ usage: Usage, total: Double, budgetToDate: Double) -> some View {
        if window == .today, usage.rate > 0.5 {
            let left = budgetToDate - total
            Label(left > 0 ? "\(usage.rate.dollars)/h now · limit in ~\(duration(hours: left / usage.rate))"
                           : "Burning \(usage.rate.dollars)/h right now",
                  systemImage: "speedometer")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(left > 0 && left / usage.rate < 1 ? Theme.bad : Theme.secondary)
        }
    }

    private func tools(_ usage: Usage) -> some View {
        let total = max(usage.total(window), 0.01)
        return Card(padding: 6) {
            ForEach(usage.tools) { tool in
                toolRow(tool, share: tool.amount(window) / total * 100)
            }
        }
    }

    private func toolRow(_ tool: Tool, share: Double) -> some View {
        let isExpanded = expanded == tool.id
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: tool.symbol)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(tool.gradient, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .shadow(color: tool.color.opacity(0.35), radius: 6, y: 2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(tool.name).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.primary)
                    if let error = tool.error {
                        Text(error).font(.system(size: 10.5)).foregroundStyle(Theme.bad).lineLimit(1)
                    } else {
                        let spend = share > 0 && share < 1 ? "<1% of spend" : "\(Int(share.rounded()))% of spend"
                        Text((tool.rate ?? 0) > 0.5
                             ? "\(spend.replacingOccurrences(of: " of spend", with: "")) · \((tool.rate ?? 0).dollars)/h"
                             : spend)
                            .font(.system(size: 10.5)).foregroundStyle(Theme.secondary)
                    }
                }
                Spacer(minLength: 6)
                Sparkline(tool: tool)
                Text(tool.amount(window).dollars)
                    .font(.system(size: 13, weight: .semibold, design: .rounded)).monospacedDigit()
                    .foregroundStyle(Theme.primary)
                    .frame(minWidth: 68, alignment: .trailing)
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.tertiary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
            }

            if let limit = tool.limit, limit > 0 {
                planLimit(tool, limit: limit)
            }

            if isExpanded {
                VStack(alignment: .leading, spacing: 5) {
                    Text("TOP MODELS TODAY").font(.system(size: 9.5, weight: .semibold)).tracking(0.6)
                        .foregroundStyle(Theme.tertiary)
                    if tool.models.isEmpty {
                        Text("No usage today").font(.system(size: 11)).foregroundStyle(Theme.tertiary)
                    }
                    let top = tool.models.first?.cost ?? 1
                    ForEach(tool.models) { model in
                        HStack(spacing: 8) {
                            Text(model.name).font(.system(size: 11)).foregroundStyle(Theme.primary.opacity(0.85))
                                .lineLimit(1).truncationMode(.middle)
                            Spacer()
                            Capsule().fill(tool.gradient)
                                .frame(width: max(4, 60 * model.cost / max(top, 0.01)), height: 4)
                            Text(model.cost.dollars).font(.system(size: 11)).monospacedDigit()
                                .foregroundStyle(Theme.secondary).frame(width: 58, alignment: .trailing)
                        }
                    }
                    if let chats = tool.chats, !chats.isEmpty {
                        Text("TOP CHATS TODAY").font(.system(size: 9.5, weight: .semibold)).tracking(0.6)
                            .foregroundStyle(Theme.tertiary).padding(.top, 4)
                        ForEach(chats) { chat in
                            HStack(spacing: 8) {
                                Text(chat.name).font(.system(size: 11)).foregroundStyle(Theme.primary.opacity(0.85))
                                    .lineLimit(1).truncationMode(.tail)
                                Spacer()
                                Text(chat.cost.dollars).font(.system(size: 11)).monospacedDigit()
                                    .foregroundStyle(Theme.secondary)
                            }
                        }
                    }
                }
                .padding(.leading, 40)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color.white.opacity(isExpanded ? 0.05 : 0)))
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(.snappy) { expanded = isExpanded ? nil : tool.id } }
    }

    private func planLimit(_ tool: Tool, limit: Double) -> some View {
        let used = tool.month / limit
        let resets = tool.periodEnd.flatMap { dayParser.date(from: $0) }
        return VStack(alignment: .leading, spacing: 4) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.07))
                    Capsule().fill(tool.gradient).frame(width: max(4, geo.size.width * min(used, 1)))
                }
            }
            .frame(height: 4)
            HStack {
                Text("Plan \(tool.month.shortDollars) of \(limit.shortDollars) · \(Int((used * 100).rounded()))%")
                Spacer()
                if let resets {
                    Text("resets \(resets, format: .dateTime.month(.abbreviated).day())")
                }
            }
            .font(.system(size: 10)).foregroundStyle(Theme.tertiary)
        }
        .padding(.leading, 40)
    }

    private func chart(_ usage: Usage) -> some View {
        Card {
            HStack {
                Text("LAST 14 DAYS").font(.system(size: 9.5, weight: .semibold)).tracking(0.6)
                    .foregroundStyle(Theme.tertiary)
                Spacer()
                HStack(spacing: 10) {
                    ForEach(usage.tools) { tool in
                        HStack(spacing: 4) {
                            Circle().fill(tool.gradient).frame(width: 6, height: 6)
                            Text(tool.name.components(separatedBy: " ").first ?? tool.name)
                        }
                    }
                }
                .font(.system(size: 10)).foregroundStyle(Theme.secondary)
            }
            Chart {
                ForEach(usage.tools) { tool in
                    ForEach(tool.daily, id: \.date) { day in
                        BarMark(x: .value("Day", dayParser.date(from: day.date) ?? .now, unit: .day),
                                y: .value("Cost", day.cost), width: .ratio(0.62))
                            .foregroundStyle(tool.gradient)
                            .cornerRadius(3)
                    }
                }
                RuleMark(y: .value("Budget", usage.budget))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 4]))
                    .foregroundStyle(Theme.secondary)
                    .annotation(position: .top, alignment: .leading, spacing: 2) {
                        Text("budget \(usage.budget.shortDollars)").font(.system(size: 9)).foregroundStyle(Theme.tertiary)
                    }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: 4)) {
                    AxisValueLabel(format: .dateTime.day().month(.abbreviated), centered: true)
                        .foregroundStyle(Theme.tertiary)
                }
            }
            .chartYAxis {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
                    AxisGridLine().foregroundStyle(Color.white.opacity(0.06))
                    AxisValueLabel { Text((value.as(Double.self) ?? 0).shortDollars) }
                        .foregroundStyle(Theme.tertiary)
                }
            }
            .frame(height: 118)
        }
    }

    private var footer: some View {
        HStack(spacing: 6) {
            FooterButton(title: "Login", symbol: launchAtLogin ? "checkmark.circle.fill" : "circle",
                         isOn: launchAtLogin) {
                try? launchAtLogin ? SMAppService.mainApp.unregister() : SMAppService.mainApp.register()
                launchAtLogin = SMAppService.mainApp.status == .enabled
            }
            Spacer()
            FooterButton(title: "Cursor", symbol: "arrow.up.right") {
                NSWorkspace.shared.open(URL(string: "https://cursor.com/dashboard?tab=usage")!)
            }
            FooterButton(title: "Quit", symbol: "power") { NSApp.terminate(nil) }
        }
    }
}

struct AppIcon: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 185, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: 0x23273A), Color(hex: 0x0B0C10)], startPoint: .top, endPoint: .bottom))
            RoundedRectangle(cornerRadius: 185, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 4)
            RadialGradient(colors: [Color(hex: 0x7C8CFF, opacity: 0.35), .clear], center: .topLeading, startRadius: 0, endRadius: 620)
                .clipShape(RoundedRectangle(cornerRadius: 185, style: .continuous))
            Image(systemName: "sparkles")
                .font(.system(size: 430, weight: .semibold))
                .foregroundStyle(LinearGradient(colors: [Color(hex: 0x9AA6FF), Color(hex: 0xA46BFF), Color(hex: 0xFF9A6B)],
                                                startPoint: .topLeading, endPoint: .bottomTrailing))
        }
        .frame(width: 824, height: 824)
        .shadow(color: .black.opacity(0.45), radius: 24, y: 12)
        .frame(width: 1024, height: 1024)
    }
}

struct MenuLabel: View {
    @ObservedObject var store: Store
    var body: some View {
        let total = store.usage?.total(.today) ?? 0
        let ratio = total / (store.usage?.budget ?? .infinity)
        HStack(spacing: 3) {
            Image(systemName: ratio >= 1 ? "flame.fill" : ratio >= Store.alertLevels[0] ? "exclamationmark.triangle.fill" : "sparkles")
            Text(store.usage == nil ? "–" : total.shortDollars).monospacedDigit()
        }
    }
}

@main
struct AIUsageApp: App {
    @StateObject private var store = Store()

    init() {
        // `AIUsage --icon out.png` renders the 1024px app icon and exits (used by build.sh).
        if let flag = CommandLine.arguments.firstIndex(of: "--icon") {
            let renderer = ImageRenderer(content: AppIcon())
            renderer.scale = 1
            if let tiff = renderer.nsImage?.tiffRepresentation,
               let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                try? png.write(to: URL(fileURLWithPath: CommandLine.arguments[flag + 1]))
            }
            exit(0)
        }
        UNUserNotificationCenter.current().delegate = NotificationPresenter.shared
        // `AIUsage --test-alert` sends both alert levels with the cached numbers and exits.
        if CommandLine.arguments.contains("--test-alert"), let usage = Store(cachedOnly: true).usage {
            let sent = DispatchSemaphore(value: 0)
            Store.alertLevels.forEach { Store.notify(usage, level: $0) { sent.signal() } }
            Store.alertLevels.forEach { _ in _ = sent.wait(timeout: .now() + 60) }
            exit(0)
        }
        // `AIUsage --snapshot out.png [Today|Week|Month]` renders the popover from the cached JSON and exits.
        guard let flag = CommandLine.arguments.firstIndex(of: "--snapshot") else { return }
        let window = Window(rawValue: CommandLine.arguments.dropFirst(flag + 2).first ?? "") ?? .today
        let renderer = ImageRenderer(content: ContentView(window: window).environmentObject(Store(cachedOnly: true)))
        renderer.scale = 2
        if let tiff = renderer.nsImage?.tiffRepresentation,
           let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: CommandLine.arguments[flag + 1]))
        }
        exit(0)
    }

    var body: some Scene {
        MenuBarExtra {
            ContentView().environmentObject(store)
        } label: {
            MenuLabel(store: store)
        }
        .menuBarExtraStyle(.window)
    }
}
