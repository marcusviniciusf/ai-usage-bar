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
    let tools: [Tool]
    let budget: Double?
    let globalBudget: Tool.Budget?
    let indicator: IndicatorConfig?

    struct IndicatorConfig: Codable { let mode: String; let toolId: String? }
    struct IndicatorPart { let symbol: String; let text: String; var toolId: String? = nil }
    struct IndicatorPresentation { let text: String; let warning: Bool }
    enum CodingKeys: String, CodingKey { case updatedAt, tools, budget, globalBudget, indicator }

    init(from decoder: Decoder) throws {
        let data = try decoder.container(keyedBy: CodingKeys.self)
        updatedAt = try data.decode(Date.self, forKey: .updatedAt)
        tools = try data.decode([Tool].self, forKey: .tools)
        budget = try data.decodeIfPresent(Double.self, forKey: .budget)
        indicator = try data.decodeIfPresent(IndicatorConfig.self, forKey: .indicator)
        if data.contains(.globalBudget) {
            globalBudget = try data.decodeIfPresent(Tool.Budget.self, forKey: .globalBudget)
        } else if let budget, budget > 0 {
            globalBudget = Tool.Budget(amount: budget, period: "daily")
        } else { globalBudget = nil }
    }

    var costTools: [Tool] { tools.filter { $0.mode != "quota" && $0.error == nil } }
    func total(_ window: Window) -> Double { costTools.reduce(0) { $0 + $1.amount(window) } }
    var hasPartialCosts: Bool { tools.contains { $0.mode != "quota" && $0.error != nil } }

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
        } else if mode == "urgent", let highest {
            text = highest.1
        } else {
            text = tools.isEmpty ? "Sem ferramentas" : tools.map(label).joined(separator: " · ")
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
    let alertsEnabled: Bool?
    let mode: String?
    let budget: Budget?
    let quotas: [Quota]?

    struct Budget: Codable { let amount: Double; let period: String }
    struct Quota: Codable, Identifiable {
        let id: String
        let label: String
        let usedPercent: Double
        let resetsAt: Double?
    }

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
                    notify(title: "Orçamento global · \(level >= 1 ? "Limite atingido" : "Próximo do limite")",
                           body: "Hoje: \(usage.total(.today).dollars) de \(budget.amount.dollars)", id: key)
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
            for (period, ratio, detail) in checks {
                guard let level = alertLevels.last(where: { ratio >= $0 }) else { continue }
                let key = "alert-\(tool.id)-\(period)"
                guard UserDefaults.standard.double(forKey: key) < level else { continue }
                UserDefaults.standard.set(level, forKey: key)
                notify(title: "\(tool.name) · \(level >= 1 ? "Limite atingido" : "Próximo do limite")",
                       body: detail, id: key)
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

    func setBudget(tool: Tool, period: String, amount: Double, completion: @escaping (String?) -> Void) {
        setPreference(arguments: ["--set-tool-budget", tool.id, period, String(amount)], completion: completion)
    }

    func setPreference(arguments: [String], completion: @escaping (String?) -> Void) {
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
                if failure == nil { self.refresh() }
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
    @State private var editingTool: Tool?
    @State private var configuringTool: String?
    @State private var showingSettings = false
    @State private var editingGlobalBudget = false
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    init(window: Window = .today) { _window = State(initialValue: window) }

    var body: some View {
        VStack(spacing: 10) {
            header
            if let usage = store.usage {
                if let budget = usage.globalBudget { globalBudgetCard(usage, budget: budget) }
                tools(usage)
                if !usage.costTools.isEmpty {
                    chart(usage)
                }
                if usage.tools.isEmpty {
                    Text("Nenhuma ferramenta detectada. Abra o Codex, OpenCode, Claude Code ou Cursor para começar.")
                        .font(.system(size: 12)).foregroundStyle(Theme.secondary).padding(.vertical, 24)
                }
            } else {
                ProgressView().controlSize(.small).tint(.white).frame(height: 160)
            }
            footer
        }
        .padding(14)
        .frame(width: 372)
        .background(Theme.background)
        .environment(\.colorScheme, .dark)
        .environment(\.locale, Locale(identifier: "pt_BR"))
        .sheet(item: $editingTool) { tool in BudgetEditor(tool: tool).environmentObject(store) }
        .sheet(isPresented: $editingGlobalBudget) { BudgetEditor(globalBudget: store.usage?.globalBudget).environmentObject(store) }
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
                        Text("Atualizando…")
                    } else if let updated = store.usage?.updatedAt {
                        Text("Atualizado \(updated, format: .relative(presentation: .named))")
                    }
                }
                .font(.system(size: 11)).foregroundStyle(Theme.secondary).lineLimit(1)
            }
            Spacer()
            Button { showingSettings = true } label: {
                Image(systemName: "gearshape").foregroundStyle(Theme.secondary).frame(width: 24, height: 28)
            }.buttonStyle(.plain).help("Configurações do app")
            .popover(isPresented: $showingSettings) { appSettings }
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
            .help("Atualizar consumo")
        }
    }

    private var appSettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Indicador da barra").font(.headline)
            Button("Resumo combinado") { setIndicator("summary") }
            Button("Mais próximo do limite") { setIndicator("urgent") }
            Text("Fixar uma ferramenta").font(.system(size: 11)).foregroundStyle(.secondary)
            ForEach(store.usage?.tools ?? []) { tool in
                Button(tool.name) { setIndicator("fixed", tool: tool.id) }
            }
            Divider()
            Button("Orçamento global diário…") { showingSettings = false; editingGlobalBudget = true }
            Text("Configurações somente deste Mac.").font(.system(size: 11)).foregroundStyle(.secondary)
        }.padding(16)
    }

    private func setIndicator(_ mode: String, tool: String? = nil) {
        showingSettings = false
        var args = ["--set-indicator", mode]
        if let tool { args.append(tool) }
        store.setPreference(arguments: args) { failure in if let failure { store.failure = failure } }
    }

    private func globalBudgetCard(_ usage: Usage, budget: Tool.Budget) -> some View {
        Card(padding: 14) {
            HStack {
                Text("Orçamento global diário").font(.system(size: 12, weight: .semibold))
                Spacer()
                Button { editingGlobalBudget = true } label: { Image(systemName: "slider.horizontal.3") }
                    .buttonStyle(.plain).help("Editar orçamento global")
            }
            Text("\(usage.total(.today).dollars) de \(budget.amount.dollars) hoje")
                .font(.system(size: 13)).monospacedDigit()
            if usage.hasPartialCosts {
                Text("Consumo parcial: uma ferramenta está indisponível.").font(.system(size: 11)).foregroundStyle(Theme.bad)
            } else {
                UsageBar(fraction: usage.total(.today) / budget.amount,
                         color: usage.total(.today) >= budget.amount * 0.8 ? Theme.bad : Theme.good)
            }
            Text("Soma dos custos locais; cotas de assinatura ficam separadas.")
                .font(.system(size: 10.5)).foregroundStyle(Theme.secondary)
        }
    }

    private func tools(_ usage: Usage) -> some View {
        VStack(spacing: 10) {
            ForEach(usage.tools) { tool in
                if tool.id == usage.costTools.first?.id {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(usage.costTools.count == 1 ? "Custos do \(tool.name)" : "Custos das ferramentas")
                            .font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.secondary)
                        SegmentedPill(selection: $window)
                    }.padding(.vertical, 2)
                }
                Card(padding: 14) {
                    HStack(spacing: 10) {
                        ToolAppIcon(toolId: tool.id, fallback: tool.symbol, size: 24)
                            .foregroundStyle(tool.color)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(tool.name).font(.system(size: 14, weight: .semibold))
                            Text(tool.mode == "quota" ? "Assinatura · conta inteira" : tool.id == "opencode" ? "Modelos não gratuitos · estimativa USD" : "Consumo local · estimativa em USD")
                                .font(.system(size: 10.5)).foregroundStyle(Theme.secondary)
                        }
                        Spacer()
                        Button { configuringTool = tool.id } label: {
                            Image(systemName: "slider.horizontal.3").foregroundStyle(Theme.secondary)
                                .frame(width: 26, height: 26).contentShape(Rectangle())
                        }.buttonStyle(.plain).help("Configurar \(tool.name)")
                        .popover(isPresented: Binding(get: { configuringTool == tool.id }, set: { if !$0 { configuringTool = nil } })) {
                            VStack(alignment: .leading, spacing: 12) {
                                Text(tool.name).font(.headline)
                                if tool.mode != "quota" {
                                    Button("Configurar orçamento…") { configuringTool = nil; editingTool = tool }
                                }
                                Button(tool.alertsEnabled == false ? "Ativar alertas" : "Desativar alertas") {
                                    configuringTool = nil
                                    store.setPreference(arguments: ["--set-alerts", tool.id, tool.alertsEnabled == false ? "on" : "off"]) { failure in
                                        if let failure { store.failure = failure }
                                    }
                                }
                            }.padding(16)
                        }
                    }
                    if let error = tool.error {
                        Text(error).font(.system(size: 11)).foregroundStyle(Theme.bad)
                            .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                    } else if tool.mode == "quota" {
                        ForEach(tool.quotas ?? []) { quota in
                            quotaRow(quota, tool: tool)
                        }
                    } else {
                        costRow(tool)
                    }
                }
            }
        }
    }

    private func quotaRow(_ quota: Tool.Quota, tool: Tool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(quota.label).foregroundStyle(Theme.secondary)
                Spacer()
                Text("\(Int(quota.usedPercent.rounded()))% usado").fontWeight(.semibold).monospacedDigit()
            }.font(.system(size: 12))
            UsageBar(fraction: quota.usedPercent / 100, color: quota.usedPercent >= 80 ? Theme.bad : tool.color)
            if let reset = quota.resetsAt {
                let date = Date(timeIntervalSince1970: reset)
                Text("Renova \(date, format: .relative(presentation: .named)) · \(date, format: .dateTime.weekday().hour().minute())")
                    .font(.system(size: 10.5)).foregroundStyle(Theme.secondary)
            }
        }.padding(.top, 3)
    }

    private func costRow(_ tool: Tool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(tool.amount(window).dollars).font(.system(size: 26, weight: .semibold)).monospacedDigit()
                Text(window == .today ? "hoje" : window == .week ? "nesta semana" : "neste mês")
                    .font(.system(size: 11)).foregroundStyle(Theme.secondary)
                Spacer()
                Sparkline(tool: tool)
            }
            if let budget = tool.budget {
                let amount = budget.period == "monthly" ? tool.month : tool.today
                UsageBar(fraction: amount / budget.amount, color: amount >= budget.amount * 0.8 ? Theme.bad : tool.color)
                HStack {
                    Text("\(amount.dollars) de \(budget.amount.dollars) · \(budget.period == "monthly" ? "mensal" : "diário")")
                    Spacer()
                    Text("\(Int((amount / budget.amount * 100).rounded()))%")
                }.font(.system(size: 10.5)).foregroundStyle(Theme.secondary)
            } else {
                Button("Definir orçamento opcional") { editingTool = tool }
                    .font(.system(size: 11)).buttonStyle(.plain).foregroundStyle(Theme.secondary)
            }
            if tool.id == "cursor", let limit = tool.limit, limit > 0 {
                Text("Plano: \(tool.month.dollars) de \(limit.dollars)").font(.system(size: 11)).foregroundStyle(Theme.secondary)
                if let end = tool.periodEnd { Text("Renova em \(end)").font(.system(size: 10.5)).foregroundStyle(Theme.secondary) }
            }
            Button {
                withAnimation { expanded = expanded == tool.id ? nil : tool.id }
            } label: {
                Label(expanded == tool.id ? "Ocultar detalhes" : "Modelos e sessões de hoje",
                      systemImage: expanded == tool.id ? "chevron.up" : "chevron.down")
                    .font(.system(size: 11)).foregroundStyle(Theme.secondary)
            }.buttonStyle(.plain)
            if expanded == tool.id {
                ForEach(tool.models) { model in
                    HStack {
                        Text(model.name).lineLimit(1)
                        Spacer()
                        Text(model.cost.dollars).monospacedDigit()
                    }.font(.system(size: 11)).foregroundStyle(Theme.secondary)
                }
                if tool.models.isEmpty { Text("Sem consumo hoje").font(.system(size: 11)).foregroundStyle(Theme.secondary) }
                if let chats = tool.chats, !chats.isEmpty {
                    Text("Sessões · custo total, pode incluir outros dias")
                        .font(.system(size: 10)).foregroundStyle(Theme.tertiary)
                    ForEach(chats) { chat in
                        HStack {
                            Text(chat.name).lineLimit(1)
                            Spacer()
                            Text(chat.cost.dollars).monospacedDigit()
                        }.font(.system(size: 11)).foregroundStyle(Theme.secondary)
                    }
                }
                if tool.id == "cursor" {
                    Button("Abrir painel do Cursor") {
                        NSWorkspace.shared.open(URL(string: "https://cursor.com/dashboard?tab=usage")!)
                    }.font(.system(size: 11))
                }
            }
        }
    }

    private func chart(_ usage: Usage) -> some View {
        Card {
            HStack {
                Text("Últimos 14 dias · USD").font(.system(size: 9.5, weight: .semibold)).tracking(0.6)
                    .foregroundStyle(Theme.tertiary)
                Spacer()
                HStack(spacing: 10) {
                    ForEach(usage.costTools) { tool in
                        HStack(spacing: 4) {
                            Circle().fill(tool.gradient).frame(width: 6, height: 6)
                            Text(tool.name.components(separatedBy: " ").first ?? tool.name)
                        }
                    }
                }
                .font(.system(size: 10)).foregroundStyle(Theme.secondary)
            }
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
            .frame(height: 118)
        }
    }

    private var footer: some View {
        HStack(spacing: 6) {
            FooterButton(title: "Iniciar com o Mac", symbol: launchAtLogin ? "checkmark.circle.fill" : "circle",
                         isOn: launchAtLogin) {
                try? launchAtLogin ? SMAppService.mainApp.unregister() : SMAppService.mainApp.register()
                launchAtLogin = SMAppService.mainApp.status == .enabled
            }
            Spacer()
            FooterButton(title: "Sair", symbol: "power") { NSApp.terminate(nil) }
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
        else { store.setPreference(arguments: ["--set-budget", String(value)], completion: completion) }
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
        let cached = Store(cachedOnly: true)
        let content = CommandLine.arguments[flag] == "--snapshot-bar"
            ? AnyView(MenuLabel(store: cached).environment(\.colorScheme, .dark).padding(8).background(Color(hex: 0x172C40)).foregroundStyle(.white))
            : AnyView(ContentView(window: window).environmentObject(cached))
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
