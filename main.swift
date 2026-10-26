import Charts
import Darwin
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

// MARK: - Localization

enum AppLanguage: String, CaseIterable, Identifiable {
    case system, en, pt, es
    var id: String { rawValue }

    /// Languages are listed by their own name, so they stay recognizable in any UI language.
    var nativeName: String {
        switch self {
        case .system: ""
        case .en: "English"
        case .pt: "Português (Brasil)"
        case .es: "Español"
        }
    }
}

/// English strings are the keys. The language is the one chosen in the settings, or the device's by default.
enum L10n {
    static let key = "language"
    /// Set by `--lang` in snapshot mode so renders never touch the saved preference.
    static var override: AppLanguage?

    static var preference: AppLanguage { AppLanguage(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .system }

    static var resolved: AppLanguage {
        let chosen = override ?? preference
        if chosen != .system { return chosen }
        for identifier in Locale.preferredLanguages {
            if identifier.hasPrefix("pt") { return .pt }
            if identifier.hasPrefix("es") { return .es }
            if identifier.hasPrefix("en") { return .en }
        }
        return .en
    }

    static var locale: Locale {
        switch resolved {
        case .pt: Locale(identifier: "pt_BR")
        case .es: Locale(identifier: "es_ES")
        default: Locale(identifier: "en_US")
        }
    }

    static func translate(_ text: String, _ args: [String]) -> String {
        let template = resolved == .en ? text : (tables[resolved]?[text] ?? text)
        return args.isEmpty ? template : String(format: template, arguments: args.map { $0 as CVarArg })
    }

    static let tables: [AppLanguage: [String: String]] = [
        .pt: [
            "%@ unavailable": "%@ indisponível",
            "%@ no quota": "%@ sem cota",
            "%@ %@%% left": "%@ %@%% livre",
            "%@ %@%% used": "%@ %@%% usado",
            "Global %@%% used": "Global %@%% usado",
            "No tools": "Sem ferramentas",
            "At this pace it runs out in ~%@, before it renews": "No ritmo atual esgota em ~%@, antes de renovar",
            "At this pace it reaches ~%@%% when it renews": "No ritmo atual chega a ~%@%% ao renovar",
            "Forecast: %@ quota": "Previsão: cota %@",
            "Runs out in ~%@": "Esgota em ~%@",
            "No tools detected. Open Codex or OpenCode to get started.": "Nenhuma ferramenta detectada. Abra o Codex ou OpenCode para começar.",
            "Today": "Hoje", "Week": "Semana", "Month": "Mês",
            "Collector returned unreadable output": "O coletor retornou uma saída ilegível",
            "Could not save the setting.": "Não foi possível salvar a configuração.",
            "Could not update launch at login.": "Não foi possível alterar a abertura ao iniciar.",
            "Today: %@ of %@": "Hoje: %@ de %@",
            "At %@/h the limit is reached in ~%@": "No ritmo de %@/h, limite em ~%@",
            "Global budget · Limit reached": "Orçamento global · Limite atingido",
            "Global budget · Close to the limit": "Orçamento global · Próximo do limite",
            "%@ · Limit reached": "%@ · Limite atingido",
            "%@ · Close to the limit": "%@ · Próximo do limite",
            "%@ of %@ · daily": "%@ de %@ · diário",
            "%@ of %@ · monthly": "%@ de %@ · mensal",
            "%@: %@%% used": "%@: %@%% utilizado",
            "Usage": "Consumo",
            "%@ percent": "%@ por cento",
            "All tools are hidden. Turn one on in the gear menu.": "Todas as ferramentas estão ocultas. Ative alguma na engrenagem.",
            "Updating…": "Atualizando…",
            "Updated %@": "Atualizado %@",
            "Refresh usage": "Atualizar consumo",
            "Retry": "Tentar novamente",
            "Usage unavailable": "Consumo indisponível",
            "Refresh timed out after %@ seconds. Try again.": "A atualização excedeu %@ segundos. Tente novamente.",
            "Partial usage: %@ unavailable": "Consumo parcial: %@ indisponível",
            "Some usage data may be out of date. Last update %@.": "Alguns dados podem estar desatualizados. Última atualização %@.",
            "Cost under $0.1": "Custo abaixo de $0,1",
            "Notifications are off in macOS settings.": "As notificações estão desativadas nos Ajustes do macOS.",
            "Open Notification Settings": "Abrir ajustes de notificações",
            "Send test notification": "Enviar notificação de teste",
            "Test notification": "Notificação de teste",
            "Notifications are working.": "As notificações estão funcionando.",
            "Test notification could not be sent.": "Não foi possível enviar a notificação de teste.",
            "Expanded": "Expandido",
            "Collapsed": "Recolhido",
            "Bar indicator": "Indicador da barra",
            "Combined summary": "Resumo combinado",
            "Closest to the limit": "Mais próximo do limite",
            "Pin up to 2 tools": "Fixar até 2 ferramentas",
            "Monitored tools": "Ferramentas monitoradas",
            "Daily global budget…": "Orçamento global diário…",
            "Launch at login": "Iniciar com o Mac",
            "Language": "Idioma",
            "Device language": "Idioma do dispositivo",
            "Quit": "Sair",
            "App settings": "Configurações do app",
            "Partial usage: a tool is unavailable.": "Consumo parcial: uma ferramenta está indisponível.",
            "%@ over %@": "%@ acima de %@",
            "%@ left of %@": "%@ restam de %@",
            "At this pace, the limit is reached in ~%@": "No ritmo atual, limite em ~%@",
            "%@/%@ days × %@ · avg %@/day · full %@": "%@/%@ dias × %@ · média %@/dia · cheio %@",
            "%@/h now": "%@/h agora",
            "Costs use calendar months. Cursor plan usage follows its billing cycle.": "Os custos usam o mês calendário. O plano do Cursor segue o ciclo de cobrança.",
            "Subscription": "Assinatura",
            "%@%% of budget": "%@%% do orçamento",
            "Paid models": "Modelos pagos",
            "Local usage": "Uso local",
            "Weekly": "Semanal",
            "Wk": "Sem",
            "%@ hours": "%@ horas",
            "%@%% used": "%@%% usado",
            "Renews %@ · %@": "Renova %@ · %@",
            "Plan %@ of %@": "Plano %@ de %@",
            "Plan %@ of %@ · renews %@": "Plano %@ de %@ · renova %@",
            "Models today": "Modelos hoje",
            "No usage today": "Sem consumo hoje",
            "Most expensive sessions": "Sessões mais caras",
            "Full session cost, may include other days.": "Custo total da sessão, pode incluir outros dias.",
            "Set budget…": "Configurar orçamento…",
            "Turn alerts on": "Ativar alertas",
            "Turn alerts off": "Desativar alertas",
            "Open Cursor dashboard": "Abrir painel do Cursor",
            "Options · alerts off": "Opções · alertas desligados",
            "Options": "Opções",
            "LAST 14 DAYS · USD": "ÚLTIMOS 14 DIAS · USD",
            "Budget · %@": "Orçamento · %@",
            "Daily global budget": "Orçamento global diário",
            "Alert for the sum of local costs. It does not block usage.": "Alerta para a soma dos custos locais. Não bloqueia o uso.",
            "One usage alert for this tool. It does not block usage.": "Um alerta de consumo para esta ferramenta. Não bloqueia o uso.",
            "Period": "Período",
            "Daily": "Diário", "Monthly": "Mensal",
            "Limit in USD": "Limite em USD",
            "Leave without a budget to only track usage.": "Deixe sem orçamento para acompanhar apenas o consumo.",
            "No budget": "Sem orçamento",
            "Cancel": "Cancelar",
            "Saving…": "Salvando…",
            "Save": "Salvar",
            "Percent: remaining quota or budget. Values: estimated cost today in USD.": "Percentual: cota ou orçamento restante. Valores: custo estimado de hoje em USD.",
            "Percent remaining · estimated cost today in USD": "Percentual restante · custo estimado de hoje em USD",
        ],
        .es: [
            "%@ unavailable": "%@ no disponible",
            "%@ no quota": "%@ sin cuota",
            "%@ %@%% left": "%@ %@%% libre",
            "%@ %@%% used": "%@ %@%% usado",
            "Global %@%% used": "Global %@%% usado",
            "No tools": "Sin herramientas",
            "At this pace it runs out in ~%@, before it renews": "Al ritmo actual se agota en ~%@, antes de renovarse",
            "At this pace it reaches ~%@%% when it renews": "Al ritmo actual llega a ~%@%% al renovarse",
            "Forecast: %@ quota": "Previsión: cuota %@",
            "Runs out in ~%@": "Se agota en ~%@",
            "No tools detected. Open Codex or OpenCode to get started.": "No se detectó ninguna herramienta. Abre Codex u OpenCode para empezar.",
            "Today": "Hoy", "Week": "Semana", "Month": "Mes",
            "Collector returned unreadable output": "El recolector devolvió una salida ilegible",
            "Could not save the setting.": "No se pudo guardar la configuración.",
            "Could not update launch at login.": "No se pudo cambiar el inicio de sesión.",
            "Today: %@ of %@": "Hoy: %@ de %@",
            "At %@/h the limit is reached in ~%@": "A %@/h, el límite se alcanza en ~%@",
            "Global budget · Limit reached": "Presupuesto global · Límite alcanzado",
            "Global budget · Close to the limit": "Presupuesto global · Cerca del límite",
            "%@ · Limit reached": "%@ · Límite alcanzado",
            "%@ · Close to the limit": "%@ · Cerca del límite",
            "%@ of %@ · daily": "%@ de %@ · diario",
            "%@ of %@ · monthly": "%@ de %@ · mensual",
            "%@: %@%% used": "%@: %@%% utilizado",
            "Usage": "Consumo",
            "%@ percent": "%@ por ciento",
            "All tools are hidden. Turn one on in the gear menu.": "Todas las herramientas están ocultas. Activa alguna en el engranaje.",
            "Updating…": "Actualizando…",
            "Updated %@": "Actualizado %@",
            "Refresh usage": "Actualizar consumo",
            "Retry": "Reintentar",
            "Usage unavailable": "Consumo no disponible",
            "Refresh timed out after %@ seconds. Try again.": "La actualización superó %@ segundos. Inténtalo de nuevo.",
            "Partial usage: %@ unavailable": "Consumo parcial: %@ no disponible",
            "Some usage data may be out of date. Last update %@.": "Algunos datos pueden estar desactualizados. Última actualización %@.",
            "Cost under $0.1": "Coste inferior a $0,1",
            "Notifications are off in macOS settings.": "Las notificaciones están desactivadas en Ajustes de macOS.",
            "Open Notification Settings": "Abrir ajustes de notificaciones",
            "Send test notification": "Enviar notificación de prueba",
            "Test notification": "Notificación de prueba",
            "Notifications are working.": "Las notificaciones están funcionando.",
            "Test notification could not be sent.": "No se pudo enviar la notificación de prueba.",
            "Expanded": "Expandido",
            "Collapsed": "Contraído",
            "Bar indicator": "Indicador de la barra",
            "Combined summary": "Resumen combinado",
            "Closest to the limit": "Más cerca del límite",
            "Pin up to 2 tools": "Fijar hasta 2 herramientas",
            "Monitored tools": "Herramientas monitorizadas",
            "Daily global budget…": "Presupuesto global diario…",
            "Launch at login": "Iniciar con el Mac",
            "Language": "Idioma",
            "Device language": "Idioma del dispositivo",
            "Quit": "Salir",
            "App settings": "Ajustes de la app",
            "Partial usage: a tool is unavailable.": "Consumo parcial: una herramienta no está disponible.",
            "%@ over %@": "%@ por encima de %@",
            "%@ left of %@": "%@ restantes de %@",
            "At this pace, the limit is reached in ~%@": "Al ritmo actual, el límite llega en ~%@",
            "%@/%@ days × %@ · avg %@/day · full %@": "%@/%@ días × %@ · media %@/día · completo %@",
            "%@/h now": "%@/h ahora",
            "Costs use calendar months. Cursor plan usage follows its billing cycle.": "Los costes usan el mes natural. El plan de Cursor sigue su ciclo de facturación.",
            "Subscription": "Suscripción",
            "%@%% of budget": "%@%% del presupuesto",
            "Paid models": "Modelos de pago",
            "Local usage": "Uso local",
            "Weekly": "Semanal",
            "Wk": "Sem",
            "%@ hours": "%@ horas",
            "%@%% used": "%@%% usado",
            "Renews %@ · %@": "Se renueva %@ · %@",
            "Plan %@ of %@": "Plan %@ de %@",
            "Plan %@ of %@ · renews %@": "Plan %@ de %@ · se renueva %@",
            "Models today": "Modelos hoy",
            "No usage today": "Sin consumo hoy",
            "Most expensive sessions": "Sesiones más caras",
            "Full session cost, may include other days.": "Coste total de la sesión, puede incluir otros días.",
            "Set budget…": "Configurar presupuesto…",
            "Turn alerts on": "Activar alertas",
            "Turn alerts off": "Desactivar alertas",
            "Open Cursor dashboard": "Abrir panel de Cursor",
            "Options · alerts off": "Opciones · alertas desactivadas",
            "Options": "Opciones",
            "LAST 14 DAYS · USD": "ÚLTIMOS 14 DÍAS · USD",
            "Budget · %@": "Presupuesto · %@",
            "Daily global budget": "Presupuesto global diario",
            "Alert for the sum of local costs. It does not block usage.": "Alerta para la suma de los costes locales. No bloquea el uso.",
            "One usage alert for this tool. It does not block usage.": "Una alerta de consumo para esta herramienta. No bloquea el uso.",
            "Period": "Periodo",
            "Daily": "Diario", "Monthly": "Mensual",
            "Limit in USD": "Límite en USD",
            "Leave without a budget to only track usage.": "Déjalo sin presupuesto para solo seguir el consumo.",
            "No budget": "Sin presupuesto",
            "Cancel": "Cancelar",
            "Saving…": "Guardando…",
            "Save": "Guardar",
            "Percent: remaining quota or budget. Values: estimated cost today in USD.": "Porcentaje: cuota o presupuesto restante. Valores: coste estimado de hoy en USD.",
            "Percent remaining · estimated cost today in USD": "Porcentaje restante · coste estimado de hoy en USD",
        ],
    ]
}

func tr(_ text: String, _ args: String...) -> String { L10n.translate(text, args) }

extension Date {
    var relativeText: String { formatted(.relative(presentation: .named).locale(L10n.locale)) }
    var weekdayTimeText: String { formatted(.dateTime.weekday().hour().minute().locale(L10n.locale)) }
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
                return IndicatorPart(symbol: tool.symbol, text: used.map { "\(Int(min(100, max(0, 100 - $0)).rounded()))%" } ?? "—", toolId: tool.id)
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
                return [IndicatorPart(symbol: highest.1, text: "\(Int(min(100, max(0, 100 - highest.0 * 100)).rounded()))%", toolId: highest.2)]
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
            if tool.error != nil { return tr("%@ unavailable", tool.name) }
            if tool.mode == "quota" {
                guard let quota = tool.quotas?.max(by: { $0.usedPercent < $1.usedPercent }) else { return tr("%@ no quota", tool.name) }
                return tr("%@ %@%% left", tool.name, max(0, 100 - quota.usedPercent).percentValue)
            }
            return "\(tool.name) \(tool.today.dollars)"
        }
        var candidates: [(Double, String)] = []
        for tool in tools where tool.error == nil {
            for quota in tool.quotas ?? [] {
                candidates.append((quota.usedPercent / 100, tr("%@ %@%% left", tool.name, max(0, 100 - quota.usedPercent).percentValue)))
            }
            if let budget = tool.budget, budget.amount > 0 {
                let amount = budget.period == "monthly" ? tool.month : tool.today
                candidates.append((amount / budget.amount, tr("%@ %@%% used", tool.name, (amount / budget.amount * 100).percentValue)))
            }
        }
        if let globalBudget, !hasPartialCosts {
            candidates.append((total(.today) / globalBudget.amount, tr("Global %@%% used", (total(.today) / globalBudget.amount * 100).percentValue)))
        }
        let highest = candidates.max { $0.0 < $1.0 }
        let mode = indicator?.mode ?? "summary"
        let text: String
        if mode == "fixed", let id = indicator?.toolId {
            text = tools.first(where: { $0.id == id }).map(label) ?? tr("%@ unavailable", id.capitalized)
        } else if mode == "pinned", case let ids = pinnedIds, !ids.isEmpty {
            text = ids.map { id in tools.first(where: { $0.id == id }).map(label) ?? tr("%@ unavailable", id.capitalized) }.joined(separator: " · ")
        } else if mode == "urgent", let highest {
            text = highest.1
        } else {
            text = tools.isEmpty ? tr("No tools") : tools.map(label).joined(separator: " · ")
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
    let billingPeriod: BillingPeriod?
    let rate: Double?
    let chats: [Chat]?
    var alertsEnabled: Bool?
    let mode: String?
    var budget: Budget?
    let quotas: [Quota]?

    struct Budget: Codable { let amount: Double; let period: String }
    struct BillingPeriod: Codable { let amount: Double; let label: String }
    struct Quota: Codable, Identifiable {
        struct Forecast {
            enum Severity: Equatable { case normal, warning, critical }
            let text: String
            let rowText: String?
            let severity: Severity
            let secondsToLimit: Double?
        }

        let id: String
        let label: String
        let usedPercent: Double
        let resetsAt: Double?
        let windowMins: Double?

        /// Window name built from its length, so it follows the app language (the collector label is only a fallback).
        var title: String {
            guard let mins = windowMins, mins > 0 else { return label }
            let prefix = label.contains(" · ") ? label.components(separatedBy: " · ")[0] + " · " : ""
            if mins == 10080 { return prefix + tr("Weekly") }
            if mins.truncatingRemainder(dividingBy: 60) == 0 { return prefix + tr("%@ hours", String(Int(mins / 60))) }
            return label
        }

        var shortTitle: String {
            guard let mins = windowMins, mins > 0 else { return String(label.prefix(4)) }
            if mins == 10080 { return tr("Wk") }
            if mins.truncatingRemainder(dividingBy: 60) == 0 { return "\(Int(mins / 60))h" }
            return String(label.prefix(4))
        }

        /// Linear projection of the usage so far over the rest of the window.
        var forecast: Forecast? {
            guard let reset = resetsAt, let mins = windowMins, mins > 0, usedPercent > 0, usedPercent < 100 else { return nil }
            let remaining = reset - Date.now.timeIntervalSince1970
            let elapsed = mins * 60 - remaining
            // A weekly estimate based on a few early hours can turn a short burst into a false alarm.
            let minimumHistoryMinutes = min(24 * 60, max(60, mins / 7))
            guard remaining > 0, elapsed >= minimumHistoryMinutes * 60 else { return nil }
            let perSecond = usedPercent / elapsed
            let projected = usedPercent + perSecond * remaining
            if projected > 100 {
                let secondsToLimit = (100 - usedPercent) / perSecond
                let timeToLimit = duration(hours: secondsToLimit / 3600)
                let severity: Forecast.Severity = secondsToLimit <= 3600 ? .critical : .warning
                return Forecast(text: tr("At this pace it runs out in ~%@, before it renews", timeToLimit),
                                rowText: "\(tr("Forecast: %@ quota", shortTitle))\n\(tr("Runs out in ~%@", timeToLimit))",
                                severity: severity, secondsToLimit: secondsToLimit)
            }
            return Forecast(text: tr("At this pace it reaches ~%@%% when it renews", projected.percentValue),
                            rowText: nil, severity: .normal, secondsToLimit: nil)
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

private final class CollectedData: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = Data()

    func set(_ data: Data) {
        lock.lock()
        storage = data
        lock.unlock()
    }

    var value: Data {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}

@MainActor
final class Store: ObservableObject {
    private static var pendingAlertIDs: Set<String> = []
    @Published var usage: Usage?
    @Published var isLoading = false
    @Published var failure: String?
    @Published var notificationWarning: String?
    @Published var language: AppLanguage = L10n.preference

    private let collector = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".local/bin/ai-usage").path
    private let cache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("ai-usage.json")
    private var timer: Timer?
    private var refreshRequested = false

    init(cachedOnly: Bool = false) {
        usage = try? Self.decoder.decode(Usage.self, from: Data(contentsOf: cache))
        guard !cachedOnly else { return }
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
                        self.failure = tr("Collector returned unreadable output")
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
                if UserDefaults.standard.double(forKey: key) < level && !pendingAlertIDs.contains(key) {
                    var body = tr("Today: %@ of %@", usage.total(.today).dollars, budget.amount.dollars)
                    if level < 1, usage.rate > 0.5 {
                        body += "\n" + tr("At %@/h the limit is reached in ~%@", usage.rate.dollars, duration(hours: (budget.amount - usage.total(.today)) / usage.rate))
                    }
                    scheduleAlert(title: tr(level >= 1 ? "Global budget · Limit reached" : "Global budget · Close to the limit"), body: body, id: key, level: level)
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
                               tr(monthly ? "%@ of %@ · monthly" : "%@ of %@ · daily", amount.dollars, budget.amount.dollars)))
            }
            for quota in tool.quotas ?? [] {
                checks.append(("\(quota.id)-\(quota.resetsAt ?? 0)", quota.usedPercent / 100,
                               tr("%@: %@%% used", quota.title, quota.usedPercent.percentValue)))
            }
            let forecasts = Dictionary(uniqueKeysWithValues: (tool.quotas ?? []).map { ("\($0.id)-\($0.resetsAt ?? 0)", $0.forecast?.text) })
            for (period, ratio, detail) in checks {
                guard let level = alertLevels.last(where: { ratio >= $0 }) else { continue }
                let key = "alert-\(tool.id)-\(period)"
                guard UserDefaults.standard.double(forKey: key) < level, !pendingAlertIDs.contains(key) else { continue }
                let forecast = level < 1 ? forecasts[period].flatMap { $0 } : nil
                scheduleAlert(title: tr(level >= 1 ? "%@ · Limit reached" : "%@ · Close to the limit", tool.name),
                              body: forecast.map { "\(detail)\n\($0)" } ?? detail, id: key, level: level)
            }
        }
    }

    private static func scheduleAlert(title: String, body: String, id: String, level: Double) {
        pendingAlertIDs.insert(id)
        notify(title: title, body: body, id: id) { delivered in
            pendingAlertIDs.remove(id)
            if delivered { UserDefaults.standard.set(level, forKey: id) }
        }
    }

    nonisolated static func notify(title: String, body: String, id: String, completion: @escaping @MainActor (Bool) -> Void) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
                Task { @MainActor in completion(false) }
                return
            }
            UNUserNotificationCenter.current().add(request) { error in
                Task { @MainActor in completion(error == nil) }
            }
        }
    }

    // Preference changes show up immediately; the collector only persists them (and a failure forces a refresh).
    func setIndicator(mode: String, toolId: String? = nil, toolIds: [String]? = nil) {
        setPreference(arguments: ["--set-indicator", mode] + (toolId.map { [$0] } ?? []) + (toolIds ?? []))
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
        setPreference(arguments: ["--set-tool-enabled", id, enabled ? "on" : "off"])
    }

    func setLanguage(_ language: AppLanguage) {
        UserDefaults.standard.set(language.rawValue, forKey: L10n.key)
        self.language = language
    }

    func setAlerts(tool: Tool, enabled: Bool) {
        setPreference(arguments: ["--set-alerts", tool.id, enabled ? "on" : "off"]) { failure in
            if let failure { self.failure = failure; self.refresh() }
            if enabled && failure == nil { self.requestNotificationAuthorization() }
        }
    }

    func setBudget(tool: Tool, period: String, amount: Double, completion: @escaping (String?) -> Void) {
        setPreference(arguments: ["--set-tool-budget", tool.id, period, String(amount)], completion: { failure in
            if failure == nil && amount > 0 { self.requestNotificationAuthorization() }
            completion(failure)
        })
    }

    func setGlobalBudget(_ amount: Double, completion: @escaping (String?) -> Void) {
        setPreference(arguments: ["--set-budget", String(amount)], completion: { failure in
            if failure == nil && amount > 0 { self.requestNotificationAuthorization() }
            completion(failure)
        })
    }

    private func requestNotificationAuthorization(completion: (@MainActor (Bool) -> Void)? = nil) {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { [weak self] settings in
            let resolve: (Bool) -> Void = { granted in
                Task { @MainActor in
                    self?.notificationWarning = granted ? nil : tr("Notifications are off in macOS settings.")
                    completion?(granted)
                }
            }
            switch settings.authorizationStatus {
            case .authorized, .provisional: resolve(true)
            case .notDetermined:
                center.requestAuthorization(options: [.alert, .sound]) { granted, _ in resolve(granted) }
            default: resolve(false)
            }
        }
    }

    func sendTestNotification() {
        requestNotificationAuthorization { granted in
            guard granted else { return }
            Self.notify(title: tr("Test notification"), body: tr("Notifications are working."), id: "test-\(UUID().uuidString)") { delivered in
                if !delivered { self.notificationWarning = tr("Test notification could not be sent.") }
            }
        }
    }

    func setPreference(arguments: [String], refresh: Bool = true, completion: @escaping (String?) -> Void = { _ in }) {
        let collector = collector
        Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
            process.arguments = [collector] + arguments
            process.standardOutput = FileHandle.nullDevice
            let errorPipe = Pipe()
            process.standardError = errorPipe
            let failure: String?
            do {
                try process.run()
                process.waitUntilExit()
                let errorText = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
                failure = process.terminationStatus == 0 ? nil : (errorText.flatMap { $0.isEmpty ? nil : $0 } ?? tr("Could not save the setting."))
            } catch { failure = error.localizedDescription }
            await MainActor.run {
                completion(failure)
                if failure == nil && refresh { self.refresh() }
            }
        }
    }

    nonisolated static func run(_ path: String, timeout: TimeInterval = 90) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = ["-c", "import os,sys; os.execv(sys.executable, [sys.executable, sys.argv[1]])", path]
        let pipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = pipe
        process.standardError = errorPipe
        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }
        try process.run()
        let output = CollectedData()
        let errors = CollectedData()
        let readers = DispatchGroup()
        readers.enter()
        DispatchQueue.global(qos: .utility).async {
            output.set(pipe.fileHandleForReading.readDataToEndOfFile())
            readers.leave()
        }
        readers.enter()
        DispatchQueue.global(qos: .utility).async {
            errors.set(errorPipe.fileHandleForReading.readDataToEndOfFile())
            readers.leave()
        }

        if exited.wait(timeout: .now() + timeout) == .timedOut {
            let processGroup = -process.processIdentifier
            _ = kill(processGroup, SIGTERM)
            if exited.wait(timeout: .now() + 2) == .timedOut {
                _ = kill(processGroup, SIGKILL)
                _ = exited.wait(timeout: .now() + 2)
            }
            readers.wait()
            let message = tr("Refresh timed out after %@ seconds. Try again.", String(Int(timeout.rounded(.up))))
            throw NSError(domain: "AIUsage.Collector", code: Int(ETIMEDOUT),
                          userInfo: [NSLocalizedDescriptionKey: message])
        }
        readers.wait()
        let data = output.value
        guard process.terminationStatus == 0 else {
            let errorText = String(data: errors.value, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let message = errorText.flatMap { $0.isEmpty ? nil : $0 } ?? "Collector exited with status \(process.terminationStatus)."
            throw NSError(domain: "AIUsage.Collector", code: Int(process.terminationStatus),
                          userInfo: [NSLocalizedDescriptionKey: message])
        }
        return data
    }
}

// MARK: - Formatting & theme

extension Double {
    private var isPositiveBelowDisplayPrecision: Bool { self > 0 && self < 0.05 }
    var compactDollars: String {
        if isPositiveBelowDisplayPrecision { return tr("Cost under $0.1") }
        return "$" + formatted(.number.precision(.fractionLength(0...1)).locale(L10n.locale))
    }
    var dollars: String {
        if isPositiveBelowDisplayPrecision { return tr("Cost under $0.1") }
        return "$" + formatted(.number.precision(.fractionLength(0...1)).locale(L10n.locale))
    }
    var shortDollars: String { dollars }
    var percentValue: String { formatted(.number.precision(.fractionLength(0...1)).locale(L10n.locale)) }
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
    static let warning = Color(hex: 0xF0B44D)
    static let bad = Color(hex: 0xFF5C6C)
}

private let dayParser: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter
}()

// MARK: - Components

/// Fades new content in without animating layout. The panel window resizes in one step, so animated
/// sizes or offsets inside it fight the window and make the header drift and the text ghost.
struct FadeInModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isVisible = false

    func body(content: Content) -> some View {
        content
            .opacity(isVisible || reduceMotion ? 1 : 0)
            .onAppear { withAnimation(.easeOut(duration: 0.18)) { isVisible = true } }
    }
}

extension View {
    func fadeIn() -> some View { modifier(FadeInModifier()) }
}

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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Window.allCases) { window in
                Button {
                    selection = window
                } label: {
                    Text(tr(window.rawValue))
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
        .animation(reduceMotion ? nil : .snappy(duration: 0.25), value: selection)
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
        .accessibilityLabel(tr("Usage"))
        .accessibilityValue(tr("%@ percent", String(Int(fraction * 100))))
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var window: Window = .today
    @State private var expanded: String?
    @State private var editingTool: Tool?
    @State private var editingGlobalBudget = false
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var launchSettingError: String?
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
                         ? tr("All tools are hidden. Turn one on in the gear menu.")
                         : tr("No tools detected. Open Codex or OpenCode to get started."))
                        .font(.system(size: 12)).foregroundStyle(Theme.secondary).padding(.vertical, 24)
                }
            } else if store.isLoading {
                ProgressView().controlSize(.small).tint(.white).frame(height: 120)
            } else {
                VStack(spacing: 8) {
                    Text(tr("Usage unavailable")).font(.system(size: 12, weight: .medium))
                    Text(store.failure ?? tr("Collector returned unreadable output"))
                        .font(.system(size: 10.5)).foregroundStyle(Theme.secondary).multilineTextAlignment(.center)
                    Button(tr("Retry"), action: store.refresh).buttonStyle(.borderless)
                }.frame(maxWidth: .infinity).padding(.vertical, 22)
            }
        }
        .padding(12)
        .frame(width: 340)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.background)
        .environment(\.colorScheme, .dark)
        .environment(\.locale, L10n.locale)
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
                    } else if let launchSettingError {
                        Text(launchSettingError).foregroundStyle(Theme.bad)
                    } else if let notificationWarning = store.notificationWarning {
                        Text(notificationWarning).foregroundStyle(Theme.bad)
                    } else if store.isLoading {
                        Text(tr("Updating…"))
                    } else if let updated = store.usage?.updatedAt {
                        Text(tr("Updated %@", updated.relativeText))
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
                    .rotationEffect(.degrees(store.isLoading && !reduceMotion ? 360 : 0))
                    .animation(store.isLoading && !reduceMotion ? .linear(duration: 1).repeatForever(autoreverses: false) : nil,
                               value: store.isLoading)
            }
            .buttonStyle(.plain)
            .help(tr("Refresh usage"))
            if CommandLine.arguments.contains("--snapshot") {
                Image(systemName: "gearshape")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.secondary)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(Color.white.opacity(0.06)))
            } else {
                settingsMenu
            }
        }
    }

    private var settingsMenu: some View {
        let mode = store.usage?.indicator?.mode ?? "summary"
        let pinned = mode == "pinned" ? (store.usage?.indicator?.toolIds ?? [])
                   : mode == "fixed" ? [store.usage?.indicator?.toolId].compactMap { $0 } : []
        return Menu {
            Section(tr("Bar indicator")) {
                Toggle(tr("Combined summary"), isOn: Binding(get: { mode == "summary" }, set: { _ in store.setIndicator(mode: "summary") }))
                Toggle(tr("Closest to the limit"), isOn: Binding(get: { mode == "urgent" }, set: { _ in store.setIndicator(mode: "urgent") }))
                Menu(tr("Pin up to 2 tools")) {
                    ForEach(store.usage?.tools ?? []) { tool in
                        Toggle(tool.name, isOn: Binding(get: { pinned.contains(tool.id) },
                                                        set: { store.togglePinned(tool.id, on: $0) }))
                    }
                }
            }
            if let available = store.usage?.availableTools, !available.isEmpty {
                Section(tr("Monitored tools")) {
                    ForEach(available) { tool in
                        Toggle(tool.name, isOn: Binding(get: { tool.enabled }, set: { store.setToolEnabled(id: tool.id, enabled: $0) }))
                    }
                }
            }
            Divider()
            Button(tr("Daily global budget…")) { editingGlobalBudget = true }
            Toggle(tr("Launch at login"), isOn: Binding(get: { launchAtLogin }, set: { _ in toggleLaunchAtLogin() }))
            Button(tr("Send test notification"), action: store.sendTestNotification)
            if store.notificationWarning != nil {
                Button(tr("Open Notification Settings")) {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!)
                }
            }
            Menu(tr("Language")) {
                ForEach(AppLanguage.allCases) { language in
                    Toggle(language == .system ? tr("Device language") : language.nativeName,
                           isOn: Binding(get: { store.language == language }, set: { _ in store.setLanguage(language) }))
                }
            }
            Divider()
            Button(tr("Quit")) { NSApp.terminate(nil) }
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
        .help(tr("App settings"))
    }

    private func toggleLaunchAtLogin() {
        do {
            try launchAtLogin ? SMAppService.mainApp.unregister() : SMAppService.mainApp.register()
            launchSettingError = nil
        } catch {
            launchSettingError = tr("Could not update launch at login.")
        }
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
                    Text("\((ratio * 100).percentValue)%")
                        .font(.system(size: 11.5, weight: .bold, design: .rounded))
                        .foregroundStyle(isWarm ? Theme.bad : Theme.good)
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Capsule().fill((isWarm ? Theme.bad : Theme.good).opacity(0.14)))
                }
            }
            if usage.hasPartialCosts {
                let unavailable = usage.tools.filter { $0.mode != "quota" && $0.error != nil }.map(\.name)
                Text(tr("Partial usage: %@ unavailable", unavailable.joined(separator: ", ")))
                    .font(.system(size: 10.5)).foregroundStyle(Theme.bad)
            } else if allowed > 0 {
                UsageBar(fraction: ratio, color: isWarm ? Theme.bad : Theme.good)
                HStack {
                    Text(left < 0 ? tr("%@ over %@", (-left).dollars, allowed.shortDollars) : tr("%@ left of %@", left.dollars, allowed.shortDollars))
                        .foregroundStyle(left < 0 ? Theme.bad : Theme.secondary)
                    Spacer()
                    if showsPace {
                        Label("\(usage.rate.shortDollars)/h", systemImage: "speedometer")
                    }
                }.font(.system(size: 10.5, weight: .medium))
                if showsPace, left > 0 {
                    Text(tr("At this pace, the limit is reached in ~%@", duration(hours: left / usage.rate)))
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(left / usage.rate < 1 ? Theme.bad : Theme.secondary)
                }
                if window != .today {
                    Text(tr("%@/%@ days × %@ · avg %@/day · full %@", String(days.elapsed), String(days.total), (usage.globalBudget?.amount ?? 0).shortDollars, (total / Double(days.elapsed)).shortDollars, ((usage.globalBudget?.amount ?? 0) * Double(days.total)).shortDollars))
                        .font(.system(size: 10)).foregroundStyle(Theme.tertiary)
                }
            } else if showsPace {
                Label(tr("%@/h now", usage.rate.dollars), systemImage: "speedometer")
                    .font(.system(size: 10.5, weight: .medium)).foregroundStyle(Theme.secondary)
            }
        }
        .help(tr("Costs use calendar months. Cursor plan usage follows its billing cycle."))
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
                expanded = isExpanded ? nil : tool.id
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
                        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: isExpanded)
                }
                .padding(.horizontal, 8).padding(.vertical, 7)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(tr(isExpanded ? "Expanded" : "Collapsed"))

            if isExpanded {
                details(tool)
                    .padding(.horizontal, 8).padding(.bottom, 8)
                    .fadeIn()
            }
        }
    }

    @ViewBuilder
    private func rowSubtitle(_ tool: Tool) -> some View {
        if let error = tool.error {
            Text(error).font(.system(size: 10.5)).foregroundStyle(Theme.bad).lineLimit(1)
        } else if tool.mode == "quota" {
            if let risk = mostAtRiskForecast(tool), let rowText = risk.rowText {
                Text(rowText).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(forecastColor(risk))
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            } else {
                Text(tr("Subscription")).font(.system(size: 10.5)).foregroundStyle(Theme.secondary)
            }
        } else {
            Text(costSubtitle(tool)).font(.system(size: 10.5)).foregroundStyle(Theme.secondary).lineLimit(1)
        }
    }

    private func mostAtRiskForecast(_ tool: Tool) -> Tool.Quota.Forecast? {
        tool.quotas?.compactMap(\.forecast)
            .filter { $0.severity != .normal }
            .min { ($0.secondsToLimit ?? .infinity) < ($1.secondsToLimit ?? .infinity) }
    }

    private func forecastColor(_ forecast: Tool.Quota.Forecast) -> Color {
        switch forecast.severity {
        case .normal: Theme.secondary
        case .warning: Theme.warning
        case .critical: Theme.bad
        }
    }

    private func costSubtitle(_ tool: Tool) -> String {
        var parts: [String] = []
        if let budget = tool.budget {
            let spent = budget.period == "monthly" ? tool.month : tool.today
            parts.append(tr("%@%% of budget", (spent / budget.amount * 100).percentValue))
        }
        if let rate = tool.rate, rate > 0.5 { parts.append("\(rate.shortDollars)/h") }
        return parts.isEmpty ? (tool.id == "opencode" ? tr("Paid models") : tr("Local usage")) : parts.joined(separator: " · ")
    }

    @ViewBuilder
    private func rowTrailing(_ tool: Tool) -> some View {
        if tool.error != nil {
            EmptyView()
        } else if tool.mode == "quota" {
            VStack(alignment: .trailing, spacing: 3) {
                ForEach(tool.quotas ?? []) { quota in
                    let isHot = quota.usedPercent >= 80
                    HStack(spacing: 4) {
                        Text(quota.shortTitle).foregroundStyle(Theme.secondary)
                        Text(tr("%@%% used", quota.usedPercent.percentValue))
                            .fontWeight(.semibold).foregroundStyle(isHot ? Theme.bad : Theme.primary)
                    }
                    .font(.system(size: 10.5, design: .rounded)).monospacedDigit()
                    .help(tr("%@: %@%% used", quota.title, quota.usedPercent.percentValue))
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

    @ViewBuilder
    private func details(_ tool: Tool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let error = tool.error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 10.5)).foregroundStyle(Theme.bad).fixedSize(horizontal: false, vertical: true)
                Button(tr("Retry"), action: store.refresh).buttonStyle(.borderless)
            } else if tool.mode == "quota" {
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
                Text(quota.title).foregroundStyle(Theme.secondary)
                Spacer()
                Text(tr("%@%% used", quota.usedPercent.percentValue)).fontWeight(.semibold).monospacedDigit()
            }.font(.system(size: 11.5))
            UsageBar(fraction: quota.usedPercent / 100, color: quota.usedPercent >= 80 ? Theme.bad : tool.color)
            if let reset = quota.resetsAt {
                let date = Date(timeIntervalSince1970: reset)
                Text(tr("Renews %@ · %@", date.relativeText, date.weekdayTimeText))
                    .font(.system(size: 11.5)).foregroundStyle(Theme.secondary)
            }
            if let forecast = quota.forecast {
                Label(forecast.text, systemImage: forecast.severity == .normal ? "chart.line.uptrend.xyaxis" : "exclamationmark.triangle.fill")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(forecastColor(forecast))
            }
        }
    }

    @ViewBuilder
    private func costDetails(_ tool: Tool) -> some View {
        if let budget = tool.budget {
            let spent = budget.period == "monthly" ? tool.month : tool.today
            VStack(alignment: .leading, spacing: 4) {
                UsageBar(fraction: spent / budget.amount, color: spent >= budget.amount * 0.8 ? Theme.bad : tool.color)
                Text(tr(budget.period == "monthly" ? "%@ of %@ · monthly" : "%@ of %@ · daily", spent.dollars, budget.amount.dollars))
                    .font(.system(size: 10.5)).foregroundStyle(Theme.secondary)
            }
        }
        if tool.id == "cursor", let limit = tool.limit, limit > 0 {
            let planAmount = tool.billingPeriod?.amount ?? tool.month
            VStack(alignment: .leading, spacing: 4) {
                UsageBar(fraction: planAmount / limit, color: tool.color)
                Text(tool.periodEnd.map { tr("Plan %@ of %@ · renews %@", planAmount.shortDollars, limit.shortDollars, $0) } ?? tr("Plan %@ of %@", planAmount.shortDollars, limit.shortDollars))
                    .font(.system(size: 10.5)).foregroundStyle(Theme.secondary)
            }
        }
        VStack(alignment: .leading, spacing: 3) {
            sectionLabel(tr("Models today"))
            ForEach(tool.models) { model in
                HStack {
                    Text(model.name).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Text(model.cost.dollars).monospacedDigit()
                }.font(.system(size: 11)).foregroundStyle(Theme.primary.opacity(0.8))
            }
            if tool.models.isEmpty { Text(tr("No usage today")).font(.system(size: 11)).foregroundStyle(Theme.tertiary) }
        }
        if let chats = tool.chats, !chats.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                sectionLabel(tr("Most expensive sessions"))
                ForEach(chats) { chat in
                    HStack {
                        Text(chat.name).lineLimit(1).truncationMode(.tail)
                        Spacer()
                        Text(chat.cost.dollars).monospacedDigit()
                    }.font(.system(size: 11)).foregroundStyle(Theme.primary.opacity(0.8))
                }
                Text(tr("Full session cost, may include other days.")).font(.system(size: 9.5)).foregroundStyle(Theme.tertiary)
            }
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased()).font(.system(size: 9, weight: .semibold)).tracking(0.6).foregroundStyle(Theme.tertiary)
    }

    @ViewBuilder
    private func toolMenu(_ tool: Tool) -> some View {
        if CommandLine.arguments.contains("--snapshot") {
            Label(tr(tool.alertsEnabled == false ? "Options · alerts off" : "Options"), systemImage: "ellipsis.circle")
                .font(.system(size: 10.5, weight: .medium)).foregroundStyle(Theme.secondary)
        } else {
            Menu {
                if tool.mode != "quota" { Button(tr("Set budget…")) { editingTool = tool } }
                Button(tr(tool.alertsEnabled == false ? "Turn alerts on" : "Turn alerts off")) {
                    store.setAlerts(tool: tool, enabled: tool.alertsEnabled == false)
                }
                if tool.id == "cursor" {
                    Divider()
                    Button(tr("Open Cursor dashboard")) { NSWorkspace.shared.open(URL(string: "https://cursor.com/dashboard?tab=usage")!) }
                }
            } label: {
                Label(tr(tool.alertsEnabled == false ? "Options · alerts off" : "Options"), systemImage: "ellipsis.circle")
                    .font(.system(size: 10.5, weight: .medium)).foregroundStyle(Theme.secondary)
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        }
    }

    // MARK: History

    private func chart(_ usage: Usage) -> some View {
        Card(padding: 10, spacing: 6) {
            Button {
                chartExpanded.toggle()
            } label: {
                HStack(spacing: 8) {
                    Text(tr("LAST 14 DAYS · USD")).font(.system(size: 9.5, weight: .semibold)).tracking(0.6)
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
                        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: chartExpanded)
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
                .fadeIn()
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
            Text(tool.map { tr("Budget · %@", $0.name) } ?? tr("Daily global budget")).font(.headline)
            Text(tool == nil ? tr("Alert for the sum of local costs. It does not block usage.") : tr("One usage alert for this tool. It does not block usage."))
                .font(.system(size: 12)).foregroundStyle(.secondary)
            if tool != nil { Picker(tr("Period"), selection: $period) {
                Text(tr("Daily")).tag("daily")
                Text(tr("Monthly")).tag("monthly")
            }.pickerStyle(.segmented) }
            TextField(tr("Limit in USD"), text: $amount).textFieldStyle(.roundedBorder)
            Text(tr("Leave without a budget to only track usage."))
                .font(.system(size: 11)).foregroundStyle(.secondary)
            if let error { Text(error).font(.system(size: 11)).foregroundStyle(.red) }
            HStack {
                Button(tr("No budget")) { save(0) }.disabled(saving)
                Spacer()
                Button(tr("Cancel")) { dismiss() }.keyboardShortcut(.cancelAction).disabled(saving)
                Button(saving ? tr("Saving…") : tr("Save")) { if let value { save(value) } }
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
        let unavailable = store.usage?.tools.filter { $0.error != nil }.map(\.name) ?? []
        let status = [
            unavailable.isEmpty ? nil : tr("Partial usage: %@ unavailable", unavailable.joined(separator: ", ")),
            store.failure != nil ? store.usage.map { tr("Some usage data may be out of date. Last update %@.", $0.updatedAt.relativeText) } : nil
        ].compactMap { $0 }
        let accessibilityText = [presentation?.text ?? "AI Usage"] + status
        HStack(spacing: 6) {
            ForEach(parts.indices, id: \.self) { index in
                HStack(spacing: 3) {
                    ToolAppIcon(toolId: parts[index].toolId, fallback: parts[index].symbol, size: 15)
                    Text(parts[index].text).font(.system(size: 12, weight: .medium)).monospacedDigit()
                }
            }
            if presentation?.warning == true { Image(systemName: "exclamationmark.circle.fill").font(.system(size: 9)) }
        }
        .help((accessibilityText + [tr("Percent: remaining quota or budget. Values: estimated cost today in USD.")]).joined(separator: "\n"))
        .accessibilityLabel(accessibilityText.joined(separator: ". "))
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
        .help((store.usage?.indicatorPresentation.text ?? "AI Usage") + "\n" + tr("Percent remaining · estimated cost today in USD"))
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
        let expanded = CommandLine.arguments.dropFirst(flag + 3).first.flatMap { AppLanguage(rawValue: $0) == nil && $0 != "--lang" ? $0 : nil }
        if let lang = CommandLine.arguments.firstIndex(of: "--lang"), lang + 1 < CommandLine.arguments.count, let chosen = AppLanguage(rawValue: CommandLine.arguments[lang + 1]) { L10n.override = chosen }
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
