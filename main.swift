import Charts
import ServiceManagement
import SwiftUI
@preconcurrency import UserNotifications

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
    var tools: [Tool]
    let budget: Double?
    var globalBudget: Tool.Budget?
    var indicator: IndicatorConfig?
    var availableTools: [AvailableTool]?

    struct AvailableTool: Codable, Identifiable { let id: String; let name: String; var enabled: Bool }
    struct IndicatorConfig: Codable { let mode: String; let toolId: String?; var toolIds: [String]? = nil }
    struct IndicatorPart { let symbol: String; let text: String; var toolId: String? = nil }
    struct IndicatorPresentation { let text: String; let warning: Bool }
    enum CodingKeys: String, CodingKey { case updatedAt, tools, budget, globalBudget, indicator, availableTools }

    init(from decoder: Decoder) throws {
        let data = try decoder.container(keyedBy: CodingKeys.self)
        updatedAt = try data.decode(Date.self, forKey: .updatedAt)
        tools = try data.decode([Tool].self, forKey: .tools)
        budget = try data.decodeIfPresent(Double.self, forKey: .budget)
        indicator = try data.decodeIfPresent(IndicatorConfig.self, forKey: .indicator)
        availableTools = try data.decodeIfPresent([AvailableTool].self, forKey: .availableTools)
        if data.contains(.globalBudget) {
            globalBudget = try data.decodeIfPresent(Tool.Budget.self, forKey: .globalBudget)
        } else if let budget, budget > 0 {
            globalBudget = Tool.Budget(amount: budget, period: "daily")
        } else { globalBudget = nil }
    }

    var costTools: [Tool] { tools.filter { $0.mode != "quota" && $0.error == nil } }
    func total(_ window: Window) -> Double { costTools.reduce(0) { $0 + $1.amount(window) } }
    var hasPartialCosts: Bool { tools.contains { $0.mode != "quota" && $0.error != nil } }

    /// Pinned tools minus the ones the user hid with the tool filter.
    var pinnedIds: [String] {
        (indicator?.toolIds ?? []).filter { id in availableTools?.first(where: { $0.id == id })?.enabled != false }
    }

    var compactIndicatorParts: [IndicatorPart] {
        func compact(_ tool: Tool) -> IndicatorPart {
            if tool.error != nil { return IndicatorPart(symbol: tool.symbol, text: "—", toolId: tool.id) }
            if tool.mode == "quota" {
                let used = tool.quotas?.map(\.usedPercent).max()
                return IndicatorPart(symbol: tool.symbol, text: used.map { "\(Int(max(0, 100 - $0)))%" } ?? "—", toolId: tool.id)
            }
            return IndicatorPart(symbol: tool.symbol, text: tool.today.compactDollars, toolId: tool.id)
        }
        if indicator?.mode == "fixed", let id = indicator?.toolId {
            return [tools.first(where: { $0.id == id }).map(compact) ?? IndicatorPart(symbol: "exclamationmark.circle", text: "—")]
        }
        if indicator?.mode == "pinned", case let ids = pinnedIds, !ids.isEmpty {
            return ids.prefix(2).map { id in
                tools.first(where: { $0.id == id }).map(compact) ?? IndicatorPart(symbol: "exclamationmark.circle", text: "—")
            }
        }
        if indicator?.mode == "urgent" {
            var limits: [(Double, String, String?)] = []
            for tool in tools where tool.error == nil {
                for quota in tool.quotas ?? [] { limits.append((quota.usedPercent / 100, tool.symbol, tool.id)) }
                if let budget = tool.budget {
                    limits.append(((budget.period == "monthly" ? tool.month : tool.today) / budget.amount, tool.symbol, tool.id))
                }
            }
            if let globalBudget, !hasPartialCosts { limits.append((total(.today) / globalBudget.amount, "dollarsign.circle", nil)) }
            if let highest = limits.max(by: { $0.0 < $1.0 }) {
                return [IndicatorPart(symbol: highest.1, text: "\(Int(max(0, 100 - highest.0 * 100)))%", toolId: highest.2)]
            }
        }
        var parts: [IndicatorPart] = []
        let quotaTools = tools.filter { $0.error == nil && $0.quotas?.isEmpty == false }
        if let quota = quotaTools.max(by: { ($0.quotas?.map(\.usedPercent).max() ?? 0) < ($1.quotas?.map(\.usedPercent).max() ?? 0) }) {
            parts.append(compact(quota))
        }
        if !costTools.isEmpty {
            parts.append(IndicatorPart(symbol: costTools.count == 1 ? costTools[0].symbol : "dollarsign.circle", text: total(.today).compactDollars, toolId: costTools.count == 1 ? costTools[0].id : nil))
        }
        return parts.isEmpty ? [IndicatorPart(symbol: "sparkles", text: "—")] : parts
    }

    var indicatorPresentation: IndicatorPresentation {
        func label(_ tool: Tool) -> String {
            if tool.error != nil { return "\(tool.name) indisponível" }
            if tool.mode == "quota" {
                guard let quota = tool.quotas?.max(by: { $0.usedPercent < $1.usedPercent }) else { return "\(tool.name) sem cota" }
                return "\(tool.name) \(Int(max(0, 100 - quota.usedPercent)))% livre"
            }
            return "\(tool.name) \(tool.today.dollars)"
        }
        var candidates: [(Double, String)] = []
        for tool in tools where tool.error == nil {
            for quota in tool.quotas ?? [] {
                candidates.append((quota.usedPercent / 100, "\(tool.name) \(Int(max(0, 100 - quota.usedPercent)))% livre"))
            }
            if let budget = tool.budget, budget.amount > 0 {
                let amount = budget.period == "monthly" ? tool.month : tool.today
                candidates.append((amount / budget.amount, "\(tool.name) \(Int((amount / budget.amount * 100).rounded()))% usado"))
            }
        }
        if let globalBudget, !hasPartialCosts {
            candidates.append((total(.today) / globalBudget.amount, "Global \(Int((total(.today) / globalBudget.amount * 100).rounded()))% usado"))
        }
        let highest = candidates.max { $0.0 < $1.0 }
        let mode = indicator?.mode ?? "summary"
        let text: String
        if mode == "fixed", let id = indicator?.toolId {
            text = tools.first(where: { $0.id == id }).map(label) ?? "\(id.capitalized) indisponível"
        } else if mode == "pinned", case let ids = pinnedIds, !ids.isEmpty {
            text = ids.map { id in tools.first(where: { $0.id == id }).map(label) ?? "\(id.capitalized) indisponível" }.joined(separator: " · ")
        } else if mode == "urgent", let highest {
            text = highest.1
        } else {
            text = tools.isEmpty ? "Sem ferramentas" : tools.map(label).joined(separator: " · ")
        }
        if mode == "pinned", case let ids = pinnedIds, !ids.isEmpty {
            let selected = tools.filter { ids.contains($0.id) }
            let isHot = selected.contains { tool in
                let quotaWarning = tool.quotas?.contains { $0.usedPercent >= 80 } ?? false
                let budgetWarning = tool.budget.map { (tool.period($0) / $0.amount) >= 0.8 } ?? false
                return tool.error != nil || quotaWarning || budgetWarning
            }
            return IndicatorPresentation(text: text, warning: selected.count < ids.count || isHot)
        }
        if mode == "fixed" {
            let selected = tools.first { $0.id == indicator?.toolId }
            let quotaWarning = selected?.quotas?.contains { $0.usedPercent >= 80 } ?? false
            var budgetWarning = false
            if let selected, let budget = selected.budget {
                budgetWarning = (budget.period == "monthly" ? selected.month : selected.today) >= budget.amount * 0.8
            }
            return IndicatorPresentation(text: text, warning: selected == nil || selected?.error != nil || quotaWarning || budgetWarning)
        }
        return IndicatorPresentation(text: text, warning: (highest?.0 ?? 0) >= 0.8 || tools.contains { $0.error != nil })
    }

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
    var alertsEnabled: Bool?
    let mode: String?
    var budget: Budget?
    let quotas: [Quota]?

    struct Budget: Codable { let amount: Double; let period: String }
    struct Quota: Codable, Identifiable {
        let id: String
        let label: String
        let usedPercent: Double
        let resetsAt: Double?
        let windowMins: Double?

        /// Linear projection of the usage so far over the rest of the window.
        var forecast: (text: String, isUrgent: Bool)? {
            guard let reset = resetsAt, let mins = windowMins, mins > 0, usedPercent > 0, usedPercent < 100 else { return nil }
            let remaining = reset - Date.now.timeIntervalSince1970
            let elapsed = mins * 60 - remaining
            guard remaining > 0, elapsed >= 600 else { return nil }
            let perSecond = usedPercent / elapsed
            let projected = usedPercent + perSecond * remaining
            if projected >= 100 {
                return ("No ritmo atual esgota em ~\(duration(hours: (100 - usedPercent) / perSecond / 3600)), antes de renovar", true)
            }
            return ("No ritmo atual chega a ~\(Int(projected.rounded()))% ao renovar", false)
        }
    }

    struct Chat: Codable, Identifiable { let name: String; let cost: Double; let model: String; var id: String { name + model } }
    struct Day: Codable { let date: String; let cost: Double }
    struct Model: Codable, Identifiable { let name: String; let cost: Double; var id: String { name } }

    func period(_ budget: Budget) -> Double { budget.period == "monthly" ? month : today }

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
        case "codex": [Color(hex: 0xA6B8FF), Color(hex: 0x798DED)]
        default: [Color(hex: 0x4BE3A4), Color(hex: 0x1FB57E)]
        }
    }

    var color: Color { palette[0] }
    var gradient: LinearGradient { LinearGradient(colors: palette, startPoint: .topLeading, endPoint: .bottomTrailing) }

    var symbol: String {
        switch id {
        case "cursor": "cursorarrow.rays"
        case "claude": "asterisk"
        case "codex": "chevron.left.forwardslash.chevron.right"
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
    private var refreshRequested = false

    init(cachedOnly: Bool = false) {
        usage = try? Self.decoder.decode(Usage.self, from: Data(contentsOf: cache))
        guard !cachedOnly else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    func refresh() {
        guard !isLoading else { refreshRequested = true; return }
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
                if self.refreshRequested {
                    self.refreshRequested = false
                    self.refresh()
                }
            }
        }
    }

    /// Fraction of the daily budget that triggers each alert; each fires at most once per day.
    static let alertLevels: [Double] = [0.8, 1.0]

    private static func alertIfOverBudget(_ usage: Usage) {
        if let budget = usage.globalBudget, !usage.hasPartialCosts {
            let ratio = usage.total(.today) / budget.amount
            if let level = alertLevels.last(where: { ratio >= $0 }) {
                let day = Date.now.formatted(.iso8601.year().month().day())
                let key = "alert-global-\(day)-\(budget.amount)"
                if UserDefaults.standard.double(forKey: key) < level {
                    UserDefaults.standard.set(level, forKey: key)
                    var body = "Hoje: \(usage.total(.today).dollars) de \(budget.amount.dollars)"
                    if level < 1, usage.rate > 0.5 {
                        body += "\nNo ritmo de \(usage.rate.dollars)/h, limite em ~\(duration(hours: (budget.amount - usage.total(.today)) / usage.rate))"
                    }
                    notify(title: "Orçamento global · \(level >= 1 ? "Limite atingido" : "Próximo do limite")", body: body, id: key)
                }
            }
        }
        for tool in usage.tools where tool.error == nil && tool.alertsEnabled != false {
            var checks: [(String, Double, String)] = []
            if let budget = tool.budget {
                let monthly = budget.period == "monthly"
                let period = monthly ? Date.now.formatted(.dateTime.year().month()) : Date.now.formatted(.iso8601.year().month().day())
                let amount = monthly ? tool.month : tool.today
                checks.append(("budget-\(period)", amount / budget.amount,
                               "\(amount.dollars) de \(budget.amount.dollars) · \(monthly ? "mensal" : "diário")"))
            }
            for quota in tool.quotas ?? [] {
                checks.append(("\(quota.id)-\(quota.resetsAt ?? 0)", quota.usedPercent / 100,
                               "\(quota.label): \(Int(quota.usedPercent))% utilizado"))
            }
            let forecasts = Dictionary(uniqueKeysWithValues: (tool.quotas ?? []).map { ("\($0.id)-\($0.resetsAt ?? 0)", $0.forecast?.text) })
            for (period, ratio, detail) in checks {
                guard let level = alertLevels.last(where: { ratio >= $0 }) else { continue }
                let key = "alert-\(tool.id)-\(period)"
                guard UserDefaults.standard.double(forKey: key) < level else { continue }
                UserDefaults.standard.set(level, forKey: key)
                let forecast = level < 1 ? forecasts[period].flatMap { $0 } : nil
                notify(title: "\(tool.name) · \(level >= 1 ? "Limite atingido" : "Próximo do limite")",
                       body: forecast.map { "\(detail)\n\($0)" } ?? detail, id: key)
            }
        }
    }

    nonisolated static func notify(title: String, body: String, id: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            if granted { UNUserNotificationCenter.current().add(request) }
        }
    }

    // Preference changes show up immediately; the collector only persists them (and a failure forces a refresh).
    func setIndicator(mode: String, toolId: String? = nil, toolIds: [String]? = nil) {
        usage?.indicator = Usage.IndicatorConfig(mode: mode, toolId: toolId, toolIds: toolIds)
        setPreference(arguments: ["--set-indicator", mode] + (toolId.map { [$0] } ?? []) + (toolIds ?? []), refresh: false) { failure in
            if let failure { self.failure = failure; self.refresh() }
        }
    }

    /// Pins up to two tools in the menu bar; a third pin replaces the oldest. No pins falls back to the summary.
    func togglePinned(_ id: String, on: Bool) {
        let indicator = usage?.indicator
        var ids = indicator?.mode == "pinned" ? (indicator?.toolIds ?? [])
                : indicator?.mode == "fixed" ? [indicator?.toolId].compactMap { $0 } : []
        ids.removeAll { $0 == id }
        if on {
            ids.append(id)
            if ids.count > 2 { ids.removeFirst(ids.count - 2) }
        }
        if ids.isEmpty { setIndicator(mode: "summary") } else { setIndicator(mode: "pinned", toolIds: ids) }
    }

    /// Hides or shows a tool immediately; enabling needs fresh data, so it also refreshes.
    func setToolEnabled(id: String, enabled: Bool) {
        if let index = usage?.availableTools?.firstIndex(where: { $0.id == id }) { usage?.availableTools?[index].enabled = enabled }
        if !enabled { usage?.tools.removeAll { $0.id == id } }
        setPreference(arguments: ["--set-tool-enabled", id, enabled ? "on" : "off"], refresh: enabled) { failure in
            if let failure { self.failure = failure; self.refresh() }
        }
    }

    func setAlerts(tool: Tool, enabled: Bool) {
        if let index = usage?.tools.firstIndex(where: { $0.id == tool.id }) { usage?.tools[index].alertsEnabled = enabled }
        setPreference(arguments: ["--set-alerts", tool.id, enabled ? "on" : "off"], refresh: false) { failure in
            if let failure { self.failure = failure; self.refresh() }
        }
    }

    func setBudget(tool: Tool, period: String, amount: Double, completion: @escaping (String?) -> Void) {
        if let index = usage?.tools.firstIndex(where: { $0.id == tool.id }) {
            usage?.tools[index].budget = amount > 0 ? Tool.Budget(amount: amount, period: period) : nil
        }
        setPreference(arguments: ["--set-tool-budget", tool.id, period, String(amount)], completion: completion)
    }

    func setGlobalBudget(_ amount: Double, completion: @escaping (String?) -> Void) {
        usage?.globalBudget = amount > 0 ? Tool.Budget(amount: amount, period: "daily") : nil
        setPreference(arguments: ["--set-budget", String(amount)], completion: completion)
    }

    func setPreference(arguments: [String], refresh: Bool = true, completion: @escaping (String?) -> Void) {
        let collector = collector
        Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
            process.arguments = [collector] + arguments
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            let failure: String?
            do {
                try process.run()
                process.waitUntilExit()
                failure = process.terminationStatus == 0 ? nil : "Não foi possível salvar a configuração."
            } catch { failure = error.localizedDescription }
            await MainActor.run {
                completion(failure)
                if failure == nil && refresh { self.refresh() }
            }
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
    var compactDollars: String { "$" + formatted(.number.precision(.fractionLength(2)).locale(Locale(identifier: "pt_BR"))) }
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
    static let secondary = Color.white.opacity(0.70)
    static let tertiary = Color.white.opacity(0.60)
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
    var spacing: CGFloat = 10
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: spacing) { content }
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
                    Text(window == .today ? "Hoje" : window == .week ? "Semana" : "Mês")
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

struct UsageBar: View {
    let fraction: Double
    let color: Color
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.10))
                Capsule().fill(color).frame(width: geometry.size.width * min(max(fraction, 0), 1))
            }
        }.frame(height: 6)
        .accessibilityLabel("Consumo")
        .accessibilityValue("\(Int(fraction * 100)) por cento")
    }
}

struct Sparkline: View {
    let tool: Tool
    var width: CGFloat = 54
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
        .frame(width: width, height: 22)
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
    @State private var editingTool: Tool?
    @State private var editingGlobalBudget = false
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @AppStorage("chartExpanded") private var chartExpanded = false

    init(window: Window = .today, expanded: String? = nil) {
        _window = State(initialValue: window)
        _expanded = State(initialValue: expanded)
    }

    var body: some View {
        VStack(spacing: 8) {
            header
            if let usage = store.usage {
                if !usage.costTools.isEmpty { hero(usage) }
                tools(usage)
                if !usage.costTools.isEmpty { chart(usage) }
                if usage.tools.isEmpty {
                    Text(usage.availableTools?.isEmpty == false
                         ? "Todas as ferramentas estão ocultas. Ative alguma na engrenagem."
                         : "Nenhuma ferramenta detectada. Abra o Codex, OpenCode, Claude Code ou Cursor para começar.")
                        .font(.system(size: 12)).foregroundStyle(Theme.secondary).padding(.vertical, 24)
                }
            } else {
                ProgressView().controlSize(.small).tint(.white).frame(height: 120)
            }
        }
        .padding(12)
        .frame(width: 340)
        .background(Theme.background)
        .environment(\.colorScheme, .dark)
        .environment(\.locale, Locale(identifier: "pt_BR"))
        .sheet(item: $editingTool) { tool in BudgetEditor(tool: tool).environmentObject(store) }
        .sheet(isPresented: $editingGlobalBudget) { BudgetEditor(globalBudget: store.usage?.globalBudget).environmentObject(store) }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(LinearGradient(colors: [Color(hex: 0x7C8CFF), Color(hex: 0xFF9A6B)],
                                           startPoint: .topLeading, endPoint: .bottomTrailing),
                            in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            VStack(alignment: .leading, spacing: 0) {
                Text("AI Usage").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.primary)
                Group {
                    if let failure = store.failure {
                        Text(failure).foregroundStyle(Theme.bad)
                    } else if store.isLoading {
                        Text("Atualizando…")
                    } else if let updated = store.usage?.updatedAt {
                        Text("Atualizado \(updated, format: .relative(presentation: .named))")
                    }
                }
                .font(.system(size: 10.5)).foregroundStyle(Theme.secondary).lineLimit(1)
            }
            Spacer()
            Button(action: store.refresh) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.secondary)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(Color.white.opacity(0.06)))
                    .rotationEffect(.degrees(store.isLoading ? 360 : 0))
                    .animation(store.isLoading ? .linear(duration: 1).repeatForever(autoreverses: false) : .default,
                               value: store.isLoading)
            }
            .buttonStyle(.plain)
            .help("Atualizar consumo")
            settingsMenu
        }
    }

    private var settingsMenu: some View {
        let mode = store.usage?.indicator?.mode ?? "summary"
        let pinned = mode == "pinned" ? (store.usage?.indicator?.toolIds ?? [])
                   : mode == "fixed" ? [store.usage?.indicator?.toolId].compactMap { $0 } : []
        return Menu {
            Section("Indicador da barra") {
                Toggle("Resumo combinado", isOn: Binding(get: { mode == "summary" }, set: { _ in store.setIndicator(mode: "summary") }))
                Toggle("Mais próximo do limite", isOn: Binding(get: { mode == "urgent" }, set: { _ in store.setIndicator(mode: "urgent") }))
                Menu("Fixar até 2 ferramentas") {
                    ForEach(store.usage?.tools ?? []) { tool in
                        Toggle(tool.name, isOn: Binding(get: { pinned.contains(tool.id) },
                                                        set: { store.togglePinned(tool.id, on: $0) }))
                    }
                }
            }
            if let available = store.usage?.availableTools, !available.isEmpty {
                Section("Ferramentas monitoradas") {
                    ForEach(available) { tool in
                        Toggle(tool.name, isOn: Binding(get: { tool.enabled }, set: { store.setToolEnabled(id: tool.id, enabled: $0) }))
                    }
                }
            }
            Divider()
            Button("Orçamento global diário…") { editingGlobalBudget = true }
            Toggle("Iniciar com o Mac", isOn: Binding(get: { launchAtLogin }, set: { _ in toggleLaunchAtLogin() }))
            Divider()
            Button("Sair") { NSApp.terminate(nil) }
        } label: {
            Image(systemName: "gearshape")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.secondary)
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color.white.opacity(0.06)))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Configurações do app")
    }

    private func toggleLaunchAtLogin() {
        try? launchAtLogin ? SMAppService.mainApp.unregister() : SMAppService.mainApp.register()
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    // MARK: Hero

    /// The daily budget scales with the days elapsed in the selected window (weeks start Monday).
    private func hero(_ usage: Usage) -> some View {
        let total = usage.total(window)
        let days = window.days
        let allowed = (usage.globalBudget?.amount ?? 0) * Double(days.elapsed)
        let ratio = allowed > 0 ? total / allowed : 0
        let isWarm = allowed > 0 && ratio >= 0.8
        let left = allowed - total
        let showsPace = window == .today && usage.rate > 0.5 && !usage.hasPartialCosts
        return Card(padding: 12, spacing: 7) {
            SegmentedPill(selection: $window)
            HStack(alignment: .firstTextBaseline) {
                Text(total.dollars)
                    .font(.system(size: 28, weight: .bold, design: .rounded)).monospacedDigit()
                    .foregroundStyle(ratio >= 1 ? Theme.bad : Theme.primary)
                    .contentTransition(.numericText(value: total))
                    .animation(.snappy, value: total)
                Spacer()
                if allowed > 0 {
                    Text("\(Int((ratio * 100).rounded()))%")
                        .font(.system(size: 11.5, weight: .bold, design: .rounded))
                        .foregroundStyle(isWarm ? Theme.bad : Theme.good)
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Capsule().fill((isWarm ? Theme.bad : Theme.good).opacity(0.14)))
                }
            }
            if usage.hasPartialCosts {
                Text("Consumo parcial: uma ferramenta está indisponível.").font(.system(size: 10.5)).foregroundStyle(Theme.bad)
            } else if allowed > 0 {
                UsageBar(fraction: ratio, color: isWarm ? Theme.bad : Theme.good)
                HStack {
                    Text(left < 0 ? "\((-left).dollars) acima de \(allowed.shortDollars)" : "\(left.dollars) restam de \(allowed.shortDollars)")
                        .foregroundStyle(left < 0 ? Theme.bad : Theme.secondary)
                    Spacer()
                    if showsPace {
                        Label("\(usage.rate.shortDollars)/h", systemImage: "speedometer")
                    }
                }.font(.system(size: 10.5, weight: .medium))
                if showsPace, left > 0 {
                    Text("No ritmo atual, limite em ~\(duration(hours: left / usage.rate))")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(left / usage.rate < 1 ? Theme.bad : Theme.secondary)
                }
                if window != .today {
                    Text("\(days.elapsed)/\(days.total) dias × \((usage.globalBudget?.amount ?? 0).shortDollars) · média \((total / Double(days.elapsed)).shortDollars)/dia · cheio \(((usage.globalBudget?.amount ?? 0) * Double(days.total)).shortDollars)")
                        .font(.system(size: 10)).foregroundStyle(Theme.tertiary)
                }
            } else if showsPace {
                Label("\(usage.rate.dollars)/h agora", systemImage: "speedometer")
                    .font(.system(size: 10.5, weight: .medium)).foregroundStyle(Theme.secondary)
            }
        }
        .help("Soma dos custos locais. Cotas de assinatura ficam separadas. O mês do Cursor segue o período de cobrança.")
    }

    // MARK: Tools

    private func tools(_ usage: Usage) -> some View {
        Card(padding: 4, spacing: 0) {
            ForEach(usage.tools) { tool in
                toolRow(tool)
                if tool.id != usage.tools.last?.id { Divider().overlay(Theme.stroke).padding(.horizontal, 8) }
            }
        }
    }

    private func toolRow(_ tool: Tool) -> some View {
        let isExpanded = expanded == tool.id
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.snappy(duration: 0.2)) { expanded = isExpanded ? nil : tool.id }
            } label: {
                HStack(spacing: 10) {
                    ToolAppIcon(toolId: tool.id, fallback: tool.symbol, size: 24).foregroundStyle(tool.color)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(tool.name).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.primary)
                        rowSubtitle(tool)
                    }
                    Spacer(minLength: 4)
                    rowTrailing(tool)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.tertiary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .padding(.horizontal, 8).padding(.vertical, 7)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                details(tool)
                    .padding(.horizontal, 8).padding(.bottom, 8)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    @ViewBuilder
    private func rowSubtitle(_ tool: Tool) -> some View {
        if let error = tool.error {
            Text(error).font(.system(size: 10.5)).foregroundStyle(Theme.bad).lineLimit(1)
        } else if tool.mode == "quota" {
            if let urgent = tool.quotas?.compactMap({ $0.forecast }).first(where: { $0.isUrgent }) {
                Text(urgent.text).font(.system(size: 10.5)).foregroundStyle(Theme.bad).lineLimit(1)
            } else {
                Text("Assinatura").font(.system(size: 10.5)).foregroundStyle(Theme.secondary)
            }
        } else {
            Text(costSubtitle(tool)).font(.system(size: 10.5)).foregroundStyle(Theme.secondary).lineLimit(1)
        }
    }

    private func costSubtitle(_ tool: Tool) -> String {
        var parts: [String] = []
        if let budget = tool.budget {
            let spent = budget.period == "monthly" ? tool.month : tool.today
            parts.append("\(Int((spent / budget.amount * 100).rounded()))% do orçamento")
        }
        if let rate = tool.rate, rate > 0.5 { parts.append("\(rate.shortDollars)/h") }
        return parts.isEmpty ? (tool.id == "opencode" ? "Modelos pagos" : "Uso local") : parts.joined(separator: " · ")
    }

    @ViewBuilder
    private func rowTrailing(_ tool: Tool) -> some View {
        if tool.error != nil {
            EmptyView()
        } else if tool.mode == "quota" {
            HStack(spacing: 5) {
                ForEach(tool.quotas ?? []) { quota in
                    let isHot = quota.usedPercent >= 80
                    Text("\(shortLabel(quota.label)) \(Int(quota.usedPercent.rounded()))%")
                        .font(.system(size: 10.5, weight: .semibold, design: .rounded)).monospacedDigit()
                        .foregroundStyle(isHot ? Theme.bad : Theme.primary)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill((isHot ? Theme.bad : Color.white).opacity(isHot ? 0.14 : 0.08)))
                }
            }
        } else {
            HStack(spacing: 8) {
                Sparkline(tool: tool, width: 40)
                Text(tool.amount(window).dollars)
                    .font(.system(size: 13, weight: .semibold, design: .rounded)).monospacedDigit()
                    .foregroundStyle(Theme.primary)
            }
        }
    }

    private func shortLabel(_ label: String) -> String {
        if label == "Semanal" { return "Sem" }
        if let hours = label.split(separator: " ").first, label.contains("hora") { return "\(hours)h" }
        return String(label.prefix(4))
    }

    @ViewBuilder
    private func details(_ tool: Tool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if tool.mode == "quota" {
                ForEach(tool.quotas ?? []) { quota in quotaRow(quota, tool: tool) }
            } else if tool.error == nil {
                costDetails(tool)
            }
            toolMenu(tool)
        }
    }

    private func quotaRow(_ quota: Tool.Quota, tool: Tool) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(quota.label).foregroundStyle(Theme.secondary)
                Spacer()
                Text("\(Int(quota.usedPercent.rounded()))% usado").fontWeight(.semibold).monospacedDigit()
            }.font(.system(size: 11.5))
            UsageBar(fraction: quota.usedPercent / 100, color: quota.usedPercent >= 80 ? Theme.bad : tool.color)
            if let reset = quota.resetsAt {
                let date = Date(timeIntervalSince1970: reset)
                Text("Renova \(date, format: .relative(presentation: .named)) · \(date, format: .dateTime.weekday().hour().minute())")
                    .font(.system(size: 10.5)).foregroundStyle(Theme.secondary)
            }
            if let forecast = quota.forecast {
                Label(forecast.text, systemImage: forecast.isUrgent ? "exclamationmark.triangle.fill" : "chart.line.uptrend.xyaxis")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(forecast.isUrgent ? Theme.bad : Theme.secondary)
            }
        }
    }

    @ViewBuilder
    private func costDetails(_ tool: Tool) -> some View {
        if let budget = tool.budget {
            let spent = budget.period == "monthly" ? tool.month : tool.today
            VStack(alignment: .leading, spacing: 4) {
                UsageBar(fraction: spent / budget.amount, color: spent >= budget.amount * 0.8 ? Theme.bad : tool.color)
                Text("\(spent.dollars) de \(budget.amount.dollars) · \(budget.period == "monthly" ? "mensal" : "diário")")
                    .font(.system(size: 10.5)).foregroundStyle(Theme.secondary)
            }
        }
        if tool.id == "cursor", let limit = tool.limit, limit > 0 {
            VStack(alignment: .leading, spacing: 4) {
                UsageBar(fraction: tool.month / limit, color: tool.color)
                Text("Plano \(tool.month.shortDollars) de \(limit.shortDollars)\(tool.periodEnd.map { " · renova \($0)" } ?? "")")
                    .font(.system(size: 10.5)).foregroundStyle(Theme.secondary)
            }
        }
        VStack(alignment: .leading, spacing: 3) {
            sectionLabel("Modelos hoje")
            ForEach(tool.models) { model in
                HStack {
                    Text(model.name).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Text(model.cost.dollars).monospacedDigit()
                }.font(.system(size: 11)).foregroundStyle(Theme.primary.opacity(0.8))
            }
            if tool.models.isEmpty { Text("Sem consumo hoje").font(.system(size: 11)).foregroundStyle(Theme.tertiary) }
        }
        if let chats = tool.chats, !chats.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                sectionLabel("Sessões mais caras")
                ForEach(chats) { chat in
                    HStack {
                        Text(chat.name).lineLimit(1).truncationMode(.tail)
                        Spacer()
                        Text(chat.cost.dollars).monospacedDigit()
                    }.font(.system(size: 11)).foregroundStyle(Theme.primary.opacity(0.8))
                }
                Text("Custo total da sessão, pode incluir outros dias.").font(.system(size: 9.5)).foregroundStyle(Theme.tertiary)
            }
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased()).font(.system(size: 9, weight: .semibold)).tracking(0.6).foregroundStyle(Theme.tertiary)
    }

    private func toolMenu(_ tool: Tool) -> some View {
        Menu {
            if tool.mode != "quota" { Button("Configurar orçamento…") { editingTool = tool } }
            Button(tool.alertsEnabled == false ? "Ativar alertas" : "Desativar alertas") {
                store.setAlerts(tool: tool, enabled: tool.alertsEnabled == false)
            }
            if tool.id == "cursor" {
                Divider()
                Button("Abrir painel do Cursor") { NSWorkspace.shared.open(URL(string: "https://cursor.com/dashboard?tab=usage")!) }
            }
        } label: {
            Label(tool.alertsEnabled == false ? "Opções · alertas desligados" : "Opções", systemImage: "ellipsis.circle")
                .font(.system(size: 10.5, weight: .medium)).foregroundStyle(Theme.secondary)
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
    }

    // MARK: History

    private func chart(_ usage: Usage) -> some View {
        Card(padding: 10, spacing: 6) {
            Button {
                withAnimation(.snappy(duration: 0.2)) { chartExpanded.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Text("ÚLTIMOS 14 DIAS · USD").font(.system(size: 9.5, weight: .semibold)).tracking(0.6)
                        .foregroundStyle(Theme.tertiary)
                    Spacer()
                    if chartExpanded {
                        HStack(spacing: 8) {
                            ForEach(usage.costTools) { tool in
                                HStack(spacing: 3) {
                                    Circle().fill(tool.gradient).frame(width: 5, height: 5)
                                    Text(tool.name.components(separatedBy: " ").first ?? tool.name)
                                }
                            }
                        }.font(.system(size: 9.5)).foregroundStyle(Theme.secondary)
                    }
                    Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.tertiary)
                        .rotationEffect(.degrees(chartExpanded ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if chartExpanded {
                Chart {
                    ForEach(usage.costTools) { tool in
                        ForEach(tool.daily, id: \.date) { day in
                            BarMark(x: .value("Day", dayParser.date(from: day.date) ?? .now, unit: .day),
                                    y: .value("Cost", day.cost), width: .ratio(0.62))
                                .foregroundStyle(tool.gradient)
                                .cornerRadius(3)
                        }
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
                .frame(height: 90)
                .transition(.opacity)
            }
        }
    }
}

struct BudgetEditor: View {
    let tool: Tool?
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var amount: String
    @State private var period: String
    @State private var saving = false
    @State private var error: String?

    init(tool: Tool) {
        self.tool = tool
        _amount = State(initialValue: tool.budget.map { String($0.amount) } ?? "")
        _period = State(initialValue: tool.budget?.period ?? "monthly")
    }

    init(globalBudget: Tool.Budget?) {
        tool = nil
        _amount = State(initialValue: globalBudget.map { String($0.amount) } ?? "")
        _period = State(initialValue: "daily")
    }

    private var value: Double? { Double(amount.replacingOccurrences(of: ",", with: ".")) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(tool.map { "Orçamento · \($0.name)" } ?? "Orçamento global diário").font(.headline)
            Text(tool == nil ? "Alerta para a soma dos custos locais. Não bloqueia o uso." : "Um alerta de consumo para esta ferramenta. Não bloqueia o uso.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
            if tool != nil { Picker("Período", selection: $period) {
                Text("Diário").tag("daily")
                Text("Mensal").tag("monthly")
            }.pickerStyle(.segmented) }
            TextField("Limite em USD", text: $amount).textFieldStyle(.roundedBorder)
            Text("Deixe sem orçamento para acompanhar apenas o consumo.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
            if let error { Text(error).font(.system(size: 11)).foregroundStyle(.red) }
            HStack {
                Button("Sem orçamento") { save(0) }.disabled(saving)
                Spacer()
                Button("Cancelar") { dismiss() }.keyboardShortcut(.cancelAction).disabled(saving)
                Button(saving ? "Salvando…" : "Salvar") { if let value { save(value) } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(saving || value == nil || !(value?.isFinite ?? false) || (value ?? 0) <= 0)
            }
        }.padding(20).frame(width: 360).preferredColorScheme(.dark)
    }

    private func save(_ value: Double) {
        saving = true
        let completion: (String?) -> Void = { failure in
            saving = false
            error = failure
            if failure == nil { dismiss() }
        }
        if let tool { store.setBudget(tool: tool, period: period, amount: value, completion: completion) }
        else { store.setGlobalBudget(value, completion: completion) }
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

struct MenuBarContent: View {
    @ObservedObject var store: Store
    var body: some View {
        let presentation = store.usage?.indicatorPresentation
        let parts = store.usage?.compactIndicatorParts ?? [Usage.IndicatorPart(symbol: "sparkles", text: "—")]
        HStack(spacing: 6) {
            ForEach(parts.indices, id: \.self) { index in
                HStack(spacing: 3) {
                    ToolAppIcon(toolId: parts[index].toolId, fallback: parts[index].symbol, size: 15)
                    Text(parts[index].text).font(.system(size: 12, weight: .medium)).monospacedDigit()
                }
            }
            if presentation?.warning == true { Image(systemName: "exclamationmark.circle.fill").font(.system(size: 9)) }
        }
        .help((presentation?.text ?? "AI Usage") + "\nPercentual: cota ou orçamento restante. Valores: custo estimado de hoje em USD.")
        .accessibilityLabel(presentation?.text ?? "AI Usage")
    }
}

/// MenuBarExtra only needs to extract one image, preserving all app/value pairs.
struct MenuLabel: View {
    @ObservedObject var store: Store
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let content = MenuBarContent(store: store)
            .foregroundStyle(colorScheme == .dark ? Color.white : Color.black)
            .fixedSize().padding(.vertical, 1)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        return Group {
            if let icon = renderer.nsImage {
                Image(nsImage: icon).renderingMode(.original)
            } else { Image(systemName: "sparkles") }
        }
        .help((store.usage?.indicatorPresentation.text ?? "AI Usage") + "\nPercentual restante · custo estimado de hoje em USD")
        .accessibilityLabel(store.usage?.indicatorPresentation.text ?? "AI Usage")
    }
}

@MainActor
struct ToolAppIcon: View {
    let toolId: String?
    let fallback: String
    var size: CGFloat = 15
    private static var images: [String: NSImage] = [:]

    private var appIcon: NSImage? {
        guard let toolId else { return nil }
        if let cached = Self.images[toolId] { return cached }
        let names: [String]
        switch toolId {
        case "codex": names = ["Codex", "ChatGPT"]
        case "opencode": names = ["OpenCode"]
        case "cursor": names = ["Cursor"]
        case "claude": names = ["Claude"]
        default: return nil
        }
        let roots = ["/Applications", FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications").path]
        for name in names {
            for root in roots {
                let path = "\(root)/\(name).app"
                if FileManager.default.fileExists(atPath: path) {
                    let image = NSWorkspace.shared.icon(forFile: path)
                    Self.images[toolId] = image
                    return image
                }
            }
        }
        return nil
    }

    var body: some View {
        Group {
            if let appIcon {
                Image(nsImage: appIcon).renderingMode(.original).resizable().interpolation(.high)
            } else {
                Image(systemName: fallback).resizable().scaledToFit().padding(1)
            }
        }.frame(width: size, height: size).accessibilityHidden(true)
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
        // `AIUsage --snapshot out.png [Today|Week|Month]` renders the popover from the cached JSON and exits.
        guard let flag = CommandLine.arguments.firstIndex(of: "--snapshot") ?? CommandLine.arguments.firstIndex(of: "--snapshot-bar") else { return }
        let window = Window(rawValue: CommandLine.arguments.dropFirst(flag + 2).first ?? "") ?? .today
        let expanded = CommandLine.arguments.dropFirst(flag + 3).first
        let cached = Store(cachedOnly: true)
        let content = CommandLine.arguments[flag] == "--snapshot-bar"
            ? AnyView(MenuLabel(store: cached).environment(\.colorScheme, .dark).padding(8).background(Color(hex: 0x172C40)).foregroundStyle(.white))
            : AnyView(ContentView(window: window, expanded: expanded).environmentObject(cached))
        let renderer = ImageRenderer(content: content)
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
