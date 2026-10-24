"""Compile real old/current Swift models and verify wire compatibility and indicators."""
import json
from pathlib import Path
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[1]
legacy = subprocess.check_output(["rtk", "proxy", "git", "show", "2bfe2d7:main.swift"], cwd=ROOT, text=True)
current = (ROOT / "main.swift").read_text()
tool = {"id": "opencode", "name": "OpenCode", "error": None, "mode": "cost", "today": 8,
        "week": 14, "month": 20, "monthLabel": "", "daily": [], "models": [],
        "budget": {"amount": 10, "period": "daily"}}
codex = {**tool, "id": "codex", "name": "Codex", "mode": "quota", "today": 0,
         "week": 0, "month": 0, "budget": None,
         "quotas": [{"id": "primary", "label": "5 horas", "usedPercent": 30, "resetsAt": 2000000000}]}
payload = {"updatedAt": "2026-10-23T20:00:00-03:00", "budget": 80,
           "globalBudget": {"amount": 80, "period": "daily"},
           "indicator": {"mode": "summary"}, "tools": [codex, tool]}

common = '''
@main struct CompatibilityCheck {
    @MainActor static func main() throws {
        func check(_ condition: Bool) { Swift.precondition(condition) }
        UserDefaults.standard.set("pt", forKey: "language")
        let url = URL(fileURLWithPath: CommandLine.arguments[1])
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let usage = try decoder.decode(Usage.self, from: data)
'''
old_test = common + '''
        check(usage.budget == 80)
        check(usage.total(.today) == 8)
        print("Old app decodes the new payload and retains its budget")
    }
}
'''
new_test = common + '''
        check(usage.globalBudget?.amount == 80)
        check(usage.total(.today) == 8)
        check(3.0.dollars == "$3")
        check(3.08.dollars == "$3.1")
        check(3.0.compactDollars == "$3")
        check(3.08.compactDollars == "$3,1")
        check(76.44.percentValue == "76,4")
        check(usage.indicatorPresentation.text.contains("Codex 70% livre"))
        check(usage.indicatorPresentation.text.contains("OpenCode $8"))
        check(usage.indicatorPresentation.warning)
        check(usage.compactIndicatorParts.count == 2)
        check(usage.compactIndicatorParts[0].text == "70%")
        check(usage.compactIndicatorParts[1].text == "$8")
        check(usage.compactIndicatorParts[0].toolId == "codex")
        check(usage.compactIndicatorParts[1].toolId == "opencode")
        var json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        func read() throws -> Usage { try decoder.decode(Usage.self, from: JSONSerialization.data(withJSONObject: json)) }
        json["indicator"] = ["mode": "urgent"]
        check(try read().indicatorPresentation.text == "OpenCode 80% usado")
        check(try read().compactIndicatorParts.count == 1)
        check(try read().compactIndicatorParts[0].text == "20%")
        json["indicator"] = ["mode": "fixed", "toolId": "codex"]
        check(try read().indicatorPresentation.text == "Codex 70% livre")
        check(try !read().indicatorPresentation.warning)
        check(try read().compactIndicatorParts[0].text == "70%")
        json["indicator"] = ["mode": "fixed", "toolId": "missing"]
        check(try read().indicatorPresentation.text.contains("indisponível"))
        json["indicator"] = ["mode": "pinned", "toolIds": ["codex", "opencode"]]
        check(try read().compactIndicatorParts.count == 2)
        check(try read().compactIndicatorParts[0].text == "70%")
        check(try read().indicatorPresentation.text == "Codex 70% livre · OpenCode $8")
        check(try read().indicatorPresentation.warning)
        json["indicator"] = ["mode": "pinned", "toolIds": ["codex", "opencode", "extra"]]
        check(try read().compactIndicatorParts.count == 2)
        json["indicator"] = ["mode": "pinned", "toolIds": ["codex", "missing"]]
        check(try read().indicatorPresentation.text.contains("indisponível"))
        check(try read().indicatorPresentation.warning)
        json["indicator"] = ["mode": "pinned", "toolIds": ["codex", "opencode"]]
        json["availableTools"] = [["id": "codex", "name": "Codex", "enabled": false], ["id": "opencode", "name": "OpenCode", "enabled": true]]
        check(try read().compactIndicatorParts.count == 1)
        check(try read().indicatorPresentation.text == "OpenCode $8")
        json.removeValue(forKey: "availableTools")
        json["indicator"] = ["mode": "summary"]
        UserDefaults.standard.set("en", forKey: "language")
        check(try read().indicatorPresentation.text == "Codex 70% left · OpenCode $8")
        UserDefaults.standard.set("es", forKey: "language")
        check(try read().indicatorPresentation.text == "Codex 70% libre · OpenCode $8")
        UserDefaults.standard.set("pt", forKey: "language")
        check(try read().indicatorPresentation.text == "Codex 70% livre · OpenCode $8")
        check(L10n.translate("Unknown key %@", ["x"]) == "Unknown key x")
        let weekly = Tool.Quota(id: "w", label: "Semanal", usedPercent: 10, resetsAt: nil, windowMins: 10080)
        check(weekly.title == "Semanal" && weekly.shortTitle == "Sem")
        UserDefaults.standard.set("en", forKey: "language")
        check(weekly.title == "Weekly" && weekly.shortTitle == "Wk")
        check(Tool.Quota(id: "h", label: "5 horas", usedPercent: 10, resetsAt: nil, windowMins: 300).title == "5 hours")
        UserDefaults.standard.set("pt", forKey: "language")
        let imminent = Tool.Quota(id: "h", label: "5 horas", usedPercent: 99,
                                  resetsAt: Date.now.timeIntervalSince1970 + 600, windowMins: 300)
        check(imminent.forecast?.isUrgent == true)
        check(imminent.forecast?.rowText?.contains("Previsão: cota 5h") == true &&
              imminent.forecast?.rowText?.contains("Esgota em ~") == true)
        check(imminent.forecast?.text.contains("antes de renovar") == true)
        json["globalBudget"] = NSNull()
        check(try read().globalBudget == nil)
        json.removeValue(forKey: "globalBudget")
        json.removeValue(forKey: "indicator")
        check(try read().globalBudget?.amount == 80)
        // The new app also reads old collectors, which don't know quotas or modes.
        var oldTool = (json["tools"] as! [[String: Any]])[1]
        oldTool.removeValue(forKey: "mode")
        oldTool.removeValue(forKey: "budget")
        json["tools"] = [oldTool]
        let oldPayload = try read()
        check(oldPayload.total(.today) == 8)
        check(oldPayload.globalBudget?.amount == 80)
        print("Current app: combined/fixed/urgent indicators, explicit disable and legacy payload pass")
    }
}
'''

with tempfile.TemporaryDirectory(prefix="ai-usage-swift-") as folder:
    folder = Path(folder)
    fixture = folder / "usage.json"
    fixture.write_text(json.dumps(payload))
    for name, source, test in (("legacy", legacy, old_test), ("current", current, new_test)):
        path = folder / f"{name}.swift"
        path.write_text(source.split("\n@main\nstruct AIUsageApp:", 1)[0] + test)
        binary = folder / name
        subprocess.run(["rtk", "proxy", "xcrun", "swiftc", "-parse-as-library", str(path), "-o", str(binary)], check=True)
        subprocess.run([str(binary), str(fixture)], check=True)
