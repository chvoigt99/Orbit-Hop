import SwiftUI

// MARK: - Ereignisse aus dem Spiel

/// Was im Flug passiert und für Missionen oder Erfolge zählen kann
enum MissionEvent {
    /// neuer Planet erreicht, mit dem Planetenstand dieses Flugs
    case planet(Int)
    case perfect(inRun: Int)
    case obstacle
    case comet
    case bonus
    case blackHoleEscape
    case binary
    case station
    case combo(Int)
    case dailyDone
}

// MARK: - Missionen

/// Drei laufende Aufträge, die über mehrere Flüge hinweg erfüllt werden. Jede erfüllte Mission
/// bringt Tech-Teile und wird durch eine neue, etwas schwerere ersetzt.
struct Mission: Codable, Identifiable {
    enum Kind: String, Codable, CaseIterable {
        case planetsInRun, obstacles, perfects, combo, specials, bonuses
    }

    var id = UUID()
    let kind: Kind
    let target: Int
    let reward: Int
    var progress = 0

    var done: Bool { progress >= target }
    var fraction: CGFloat { min(1, CGFloat(progress) / CGFloat(max(1, target))) }

    /// zählt nur innerhalb eines Flugs (Fortschritt ist der beste Flug), sonst über alle Flüge
    var singleRun: Bool { kind == .planetsInRun || kind == .combo }

    var title: String {
        switch kind {
        case .planetsInRun: return "Erreiche \(target) Planeten in einem Flug"
        case .obstacles: return "Zerstöre \(target) Hindernisse"
        case .perfects: return "Schaffe \(target) perfekte Starts"
        case .combo: return "Erreiche eine Combo ×\(target)"
        case .specials: return "Besuche \(target) Sonderplaneten"
        case .bonuses: return "Sammle \(target) Bonus-Items"
        }
    }

    var symbol: String {
        switch kind {
        case .planetsInRun: return "globe"
        case .obstacles: return "burst.fill"
        case .perfects: return "scope"
        case .combo: return "flame.fill"
        case .specials: return "circle.hexagongrid.fill"
        case .bonuses: return "sparkles"
        }
    }

    /// neue Mission; Stufe wächst mit der Zahl der schon erfüllten
    static func make(_ kind: Kind, tier: Int) -> Mission {
        let t = min(tier, 12)
        let target: Int
        switch kind {
        case .planetsInRun: target = 8 + 4 * t
        case .obstacles: target = 10 + 5 * t
        case .perfects: target = 4 + 2 * t
        case .combo: target = 3 + t
        case .specials: target = 2 + t
        case .bonuses: target = 4 + 2 * t
        }
        return Mission(kind: kind, target: target, reward: 2 + t)
    }
}

// MARK: - Erfolge

/// Einmalige Auszeichnungen mit einer festen Belohnung in Tech-Teilen
struct Achievement: Identifiable {
    let id: String
    let title: String
    let detail: String
    let reward: Int
    let symbol: String
    let matches: (MissionEvent) -> Bool

    static let all: [Achievement] = [
        Achievement(id: "planets10", title: "Kadett", detail: "10 Planeten in einem Flug", reward: 2, symbol: "1.circle.fill") {
            if case .planet(let n) = $0 { return n >= 10 }; return false
        },
        Achievement(id: "planets25", title: "Pilot", detail: "25 Planeten in einem Flug", reward: 4, symbol: "2.circle.fill") {
            if case .planet(let n) = $0 { return n >= 25 }; return false
        },
        Achievement(id: "planets50", title: "Navigator", detail: "50 Planeten in einem Flug", reward: 8, symbol: "3.circle.fill") {
            if case .planet(let n) = $0 { return n >= 50 }; return false
        },
        Achievement(id: "planets100", title: "Legende", detail: "100 Planeten in einem Flug", reward: 15, symbol: "crown.fill") {
            if case .planet(let n) = $0 { return n >= 100 }; return false
        },
        Achievement(id: "perfect1", title: "Präzision", detail: "Ein perfekter Start", reward: 1, symbol: "scope") {
            if case .perfect = $0 { return true }; return false
        },
        Achievement(id: "perfect5", title: "Scharfschütze", detail: "5 perfekte Starts in einem Flug", reward: 3, symbol: "target") {
            if case .perfect(let n) = $0 { return n >= 5 }; return false
        },
        Achievement(id: "combo5", title: "Kettenreaktion", detail: "Combo ×5", reward: 3, symbol: "flame") {
            if case .combo(let n) = $0 { return n >= 5 }; return false
        },
        Achievement(id: "combo10", title: "Unaufhaltsam", detail: "Combo ×10", reward: 6, symbol: "flame.fill") {
            if case .combo(let n) = $0 { return n >= 10 }; return false
        },
        Achievement(id: "blackhole", title: "Ereignishorizont", detail: "Aus einem Schwarzen Loch geschleudert", reward: 3, symbol: "circle.circle.fill") {
            if case .blackHoleEscape = $0 { return true }; return false
        },
        Achievement(id: "binary", title: "Doppelsonne", detail: "Einen Doppelstern besucht", reward: 2, symbol: "sun.max.fill") {
            if case .binary = $0 { return true }; return false
        },
        Achievement(id: "station", title: "Angedockt", detail: "Eine Raumstation erreicht", reward: 4, symbol: "building.2.fill") {
            if case .station = $0 { return true }; return false
        },
        Achievement(id: "comet", title: "Kometenjäger", detail: "Einen Kometen zerstört", reward: 3, symbol: "sparkle") {
            if case .comet = $0 { return true }; return false
        },
        Achievement(id: "daily", title: "Tagesflieger", detail: "Einen Tagesflug abgeschlossen", reward: 2, symbol: "calendar") {
            if case .dailyDone = $0 { return true }; return false
        },
    ]
}

// MARK: - Fortschritt

/// Laufende Missionen und freigeschaltete Erfolge, gespeichert in UserDefaults
final class MissionLog {
    private(set) var missions: [Mission] = []
    private(set) var unlocked: Set<String>
    private(set) var completedCount: Int

    private let defaults = UserDefaults.standard
    private static let missionsKey = "orbitHopMissions"
    private static let unlockedKey = "orbitHopAchievements"
    private static let completedKey = "orbitHopMissionsDone"

    init() {
        unlocked = Set(defaults.stringArray(forKey: Self.unlockedKey) ?? [])
        completedCount = defaults.integer(forKey: Self.completedKey)
        if let data = defaults.data(forKey: Self.missionsKey),
           let saved = try? JSONDecoder().decode([Mission].self, from: data) {
            missions = saved
        }
        while missions.count < 3 { missions.append(nextMission()) }
        save()
    }

    /// Ergebnis einer Meldung: was gerade erfüllt oder freigeschaltet wurde
    struct Reward {
        let text: String
        let parts: Int
    }

    /// Ereignis verarbeiten; liefert erfüllte Missionen und neue Erfolge (Belohnung zahlt der Aufrufer aus)
    func record(_ event: MissionEvent) -> [Reward] {
        var rewards: [Reward] = []
        for i in missions.indices {
            let m = missions[i]
            var p = m.progress
            switch (m.kind, event) {
            case (.planetsInRun, .planet(let n)): p = max(p, n)
            case (.combo, .combo(let n)): p = max(p, n)
            case (.obstacles, .obstacle), (.obstacles, .comet): p += 1
            case (.perfects, .perfect): p += 1
            case (.specials, .blackHoleEscape), (.specials, .binary): p += 1
            case (.bonuses, .bonus): p += 1
            default: break
            }
            missions[i].progress = min(p, m.target)
        }
        // erfüllte Missionen auszahlen und ersetzen
        for i in missions.indices where missions[i].done {
            let m = missions[i]
            rewards.append(Reward(text: "MISSION ERFÜLLT · +\(m.reward) TECH", parts: m.reward))
            completedCount += 1
            missions[i] = nextMission(excluding: m.kind)
        }
        for a in Achievement.all where !unlocked.contains(a.id) && a.matches(event) {
            unlocked.insert(a.id)
            rewards.append(Reward(text: "ERFOLG: \(a.title.uppercased()) · +\(a.reward) TECH", parts: a.reward))
        }
        save()
        return rewards
    }

    /// neue Mission einer Art, die gerade nicht läuft
    private func nextMission(excluding: Mission.Kind? = nil) -> Mission {
        let busy = Set(missions.map(\.kind)).union(excluding.map { [$0] } ?? [])
        let free = Mission.Kind.allCases.filter { !busy.contains($0) }
        let kind = free.randomElement() ?? Mission.Kind.allCases.randomElement()!
        // Stufe je Art: alle drei erfüllten Missionen wird es etwas schwerer
        return Mission.make(kind, tier: completedCount / 3)
    }

    private func save() {
        if let data = try? JSONEncoder().encode(missions) { defaults.set(data, forKey: Self.missionsKey) }
        defaults.set(Array(unlocked), forKey: Self.unlockedKey)
        defaults.set(completedCount, forKey: Self.completedKey)
    }
}

// MARK: - Ansicht

struct MissionsView: View {
    let log: MissionLog
    let parts: Int
    let onClose: () -> Void

    private let signal = Color(red: 79 / 255, green: 227 / 255, blue: 193 / 255)
    private let gold = Color(red: 1, green: 0.85, blue: 0.42)
    private let dim = Color(red: 0.55, green: 0.6, blue: 0.72)
    private let panel = Color(red: 0.02, green: 0.07, blue: 0.11)

    private func label(_ text: String) -> Text {
        Text(text)
            .font(.system(size: 9, weight: .medium, design: .monospaced))
            .tracking(1.4)
    }

    var body: some View {
        VStack(spacing: 12) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    label("LAUFENDE MISSIONEN").foregroundStyle(signal.opacity(0.8))
                    ForEach(log.missions) { missionRow($0) }
                    label("ERFOLGE · \(log.unlocked.count)/\(Achievement.all.count)")
                        .foregroundStyle(signal.opacity(0.8))
                        .padding(.top, 10)
                    // freigeschaltete zuerst, damit sie ohne Scrollen zu sehen sind
                    ForEach(Achievement.all.filter { log.unlocked.contains($0.id) }) { achievementRow($0) }
                    ForEach(Achievement.all.filter { !log.unlocked.contains($0.id) }) { achievementRow($0) }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
            }
        }
        .padding(.top, 8)
        .background(
            LinearGradient(colors: [Color(red: 0.03, green: 0.045, blue: 0.1), Color(red: 0.01, green: 0.015, blue: 0.04)],
                           startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
        )
        .statusBarHidden(true)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                label("LOGBUCH // AUFTRÄGE").foregroundStyle(signal.opacity(0.8))
                Text("MISSIONEN")
                    .font(.system(size: 28, weight: .heavy, design: .monospaced))
                    .tracking(3)
                    .foregroundStyle(.white)
                    .shadow(color: signal.opacity(0.6), radius: 10)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                label("TECH-TEILE").foregroundStyle(dim)
                HStack(spacing: 5) {
                    Image(systemName: "gearshape.fill").font(.system(size: 14))
                    Text("\(parts)")
                        .font(.system(size: 20, weight: .bold, design: .monospaced))
                }
                .foregroundStyle(gold)
            }
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(signal)
                    .frame(width: 40, height: 40)
                    .background(Chamfer(cut: 8).fill(panel))
                    .overlay(Chamfer(cut: 8).stroke(signal.opacity(0.6), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .padding(.leading, 8)
        }
        .padding(.horizontal, 16)
    }

    private func missionRow(_ m: Mission) -> some View {
        HStack(spacing: 12) {
            Image(systemName: m.symbol)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(signal)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 6) {
                Text(m.title)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white)
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Rectangle().fill(signal.opacity(0.15))
                        Rectangle().fill(signal).frame(width: g.size.width * m.fraction)
                    }
                }
                .frame(height: 4)
                label("\(m.progress)/\(m.target)\(m.singleRun ? " · IN EINEM FLUG" : "") · +\(m.reward) TECH")
                    .foregroundStyle(dim)
            }
        }
        .padding(12)
        .background(Chamfer(cut: 8).fill(panel.opacity(0.85)))
        .overlay(Chamfer(cut: 8).stroke(signal.opacity(0.4), lineWidth: 1))
    }

    private func achievementRow(_ a: Achievement) -> some View {
        let got = log.unlocked.contains(a.id)
        return HStack(spacing: 12) {
            Image(systemName: got ? a.symbol : "lock.fill")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(got ? gold : dim.opacity(0.6))
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(a.title.uppercased())
                    .font(.system(size: 13, weight: .heavy, design: .monospaced))
                    .tracking(1.5)
                    .foregroundStyle(got ? .white : dim)
                label(a.detail.uppercased()).foregroundStyle(dim)
            }
            Spacer()
            label(got ? "ERHALTEN" : "+\(a.reward) TECH")
                .foregroundStyle(got ? gold : dim)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Chamfer(cut: 6).fill(panel.opacity(got ? 0.9 : 0.6)))
        .overlay(Chamfer(cut: 6).stroke((got ? gold : dim).opacity(got ? 0.55 : 0.25), lineWidth: 1))
    }
}
