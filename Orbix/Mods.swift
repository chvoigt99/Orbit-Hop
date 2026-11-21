import SwiftUI

// MARK: - Pilotenrang

/// Ruf aus erfüllten Aufträgen und Missionen ergibt den Pilotenrang. Höhere Ränge schalten stärkere Mods
/// und besser bezahlte Aufträge frei (Christian, 2026-11-20).
enum PilotRank {
    static let titles = ["KADETT", "PILOT", "LEUTNANT", "KAPITÄN", "KOMMANDANT", "ADMIRAL", "LEGENDE"]
    static let thresholds = [0, 40, 120, 260, 480, 800, 1300]

    static func rank(for reputation: Int) -> Int {
        var r = 0
        for (i, t) in thresholds.enumerated() where reputation >= t { r = i }
        return r
    }

    static func title(_ rank: Int) -> String { titles[max(0, min(titles.count - 1, rank))] }

    /// Fortschritt zum nächsten Rang (0...1), beim höchsten Rang 1
    static func progress(for reputation: Int) -> CGFloat {
        let r = rank(for: reputation)
        guard r + 1 < thresholds.count else { return 1 }
        let lo = thresholds[r], hi = thresholds[r + 1]
        return CGFloat(reputation - lo) / CGFloat(max(1, hi - lo))
    }

    /// Ruf, der zum nächsten Rang fehlt (0 beim höchsten Rang)
    static func missing(for reputation: Int) -> Int {
        let r = rank(for: reputation)
        guard r + 1 < thresholds.count else { return 0 }
        return thresholds[r + 1] - reputation
    }
}

// MARK: - Schiffsrollen

extension ShipModel {
    /// Frachtraum in Containern: Frachter tragen ein Vielfaches und verdienen bei Frachtaufträgen am meisten
    var cargoCapacity: Int {
        switch hull {
        case .fighter: return 4
        case .scout: return 2
        case .hauler: return 14
        case .tank: return 6
        case .cruiser: return 7
        case .interceptor: return 3
        case .battleship: return 11
        case .phantom: return 4
        case .nova: return 7
        }
    }

    /// Kopfgeld-Faktor: schnelle Jäger kassieren beim Kämpfen am meisten
    var bountyFactor: CGFloat {
        switch hull {
        case .fighter: return 1.35
        case .scout: return 1.2
        case .hauler: return 0.6
        case .tank: return 0.9
        case .cruiser: return 1.0
        case .interceptor: return 1.6
        case .battleship: return 0.8
        case .phantom: return 1.3
        case .nova: return 1.5
        }
    }

    /// Einbauplätze für Mods
    var modSlots: Int {
        switch grade {
        case .start, .normal: return 2
        case .good: return 3
        case .superior: return 4
        }
    }

    var role: ShipRole {
        switch hull {
        case .hauler, .battleship: return .freighter
        case .fighter, .scout, .interceptor, .phantom, .nova: return .fighter
        case .tank, .cruiser: return .allround
        }
    }
}

enum ShipRole {
    case freighter, fighter, allround

    var title: String {
        switch self {
        case .freighter: return "FRACHTER"
        case .fighter: return "JÄGER"
        case .allround: return "ALLROUNDER"
        }
    }

    var symbol: String {
        switch self {
        case .freighter: return "shippingbox.fill"
        case .fighter: return "scope"
        case .allround: return "circle.hexagongrid.fill"
        }
    }

    /// ein Satz, der die Rolle im Hangar erklärt
    var pitch: String {
        switch self {
        case .freighter: return "Viel Fracht, dicke Hülle, Rundum-Geschützturm. Träge im Gefecht."
        case .fighter: return "Wendig, starke Bugkanonen. Kaum Frachtraum."
        case .allround: return "Kann beides ein wenig, nichts davon richtig."
        }
    }

    /// Farbe der Triebwerksglut: Jäger blaues Plasma, Frachter schwere orange Brenner
    var engineColor: UIColor {
        switch self {
        case .freighter: return UIColor(red: 1, green: 0.42, blue: 0.08, alpha: 1)
        case .fighter: return UIColor(red: 0.35, green: 0.75, blue: 1, alpha: 1)
        case .allround: return UIColor(red: 1, green: 0.72, blue: 0.3, alpha: 1)
        }
    }

    /// Größe im Flug: Frachter wirken wuchtig, Jäger klein und flink
    var flightScale: CGFloat {
        switch self {
        case .freighter: return 1.3
        case .fighter: return 0.92
        case .allround: return 1.1
        }
    }

    // Gefecht
    /// Wendigkeit und Tempo im Gefecht
    var combatTurn: CGFloat { self == .fighter ? 1.3 : (self == .freighter ? 0.7 : 1) }
    var combatSpeed: CGFloat { self == .fighter ? 1.15 : (self == .freighter ? 0.85 : 1) }
    /// Schaden und Feuerpause der Bordkanonen
    /// (Jäger feuern zwei Rohre zugleich: zusammen etwa das Dreifache eines Frachter-Turms)
    var gunDamage: CGFloat { self == .fighter ? 0.85 : (self == .freighter ? 1.0 : 1.2) }
    var gunCooldown: CGFloat { self == .fighter ? 0.85 : (self == .freighter ? 1.5 : 1.15) }
    /// Rohre: Jäger feuern Zwillingskanonen aus dem Bug, die anderen ein Geschütz
    var gunBarrels: Int { self == .fighter ? 2 : 1 }
    /// Schwenkbereich: Bugkanonen nach vorn, der Frachter-Turm rundum
    var gunArc: CGFloat { self == .fighter ? 0.9 : (self == .freighter ? .pi : 1.3) }
    /// Anteil des Schadens, der im Gefecht durchkommt (dicke Frachterhülle)
    var combatDamageTaken: CGFloat { self == .freighter ? 0.7 : (self == .fighter ? 1 : 0.85) }

    var color: Color {
        switch self {
        case .freighter: return Color(red: 0.55, green: 0.7, blue: 1)
        case .fighter: return Color(red: 1, green: 0.45, blue: 0.4)
        case .allround: return Color(red: 0.8, green: 0.8, blue: 0.85)
        }
    }
}

// MARK: - Mods

enum ModRole: CaseIterable, Identifiable {
    case cargo, combat, system

    var id: ModRole { self }

    var title: String {
        switch self {
        case .cargo: return "FRACHT & BERGUNG"
        case .combat: return "KAMPF"
        case .system: return "ANTRIEB & SYSTEME"
        }
    }

    var color: Color {
        switch self {
        case .cargo: return Color(red: 0.55, green: 0.7, blue: 1)
        case .combat: return Color(red: 1, green: 0.45, blue: 0.4)
        case .system: return Color(red: 79 / 255, green: 227 / 255, blue: 193 / 255)
        }
    }
}

/// Aufrüstungen für die Schiffe. Mods kauft man in der Werkstatt mit Tech-Teilen; einmal gekauft lassen sie sich
/// in jedes eigene Schiff einbauen, so weit dessen Plätze reichen. Jede Mod hat drei Stufen (MK I bis MK III).
enum ModKind: String, CaseIterable, Identifiable {
    case battery, thrusters, cargoBay, salvage, shield, plating, dampers, piercing, twinCannon,
         capacitor, targeting, smuggler, bountyScanner, nanoRepair

    static let maxLevel = 3

    var id: String { rawValue }

    var title: String {
        switch self {
        case .battery: return "ZUSATZBATTERIE"
        case .thrusters: return "NACHBRENNER-DÜSEN"
        case .cargoBay: return "FRACHTRAUM-ERWEITERUNG"
        case .salvage: return "BERGUNGSDROHNE"
        case .shield: return "DEFLEKTORSCHILD"
        case .plating: return "VERBUNDPANZERUNG"
        case .dampers: return "TRÄGHEITSDÄMPFER"
        case .piercing: return "PANZERBRECHER"
        case .twinCannon: return "ZWILLINGSKANONE"
        case .capacitor: return "ENERGIEWANDLER"
        case .targeting: return "ZIELCOMPUTER"
        case .smuggler: return "SCHMUGGLERFACH"
        case .bountyScanner: return "KOPFGELD-SCANNER"
        case .nanoRepair: return "NANO-REPARATUR"
        }
    }

    var symbol: String {
        switch self {
        case .battery: return "battery.100.bolt"
        case .thrusters: return "flame.fill"
        case .cargoBay: return "shippingbox.fill"
        case .salvage: return "hand.raised.fill"
        case .shield: return "shield.lefthalf.filled"
        case .plating: return "square.stack.3d.up.fill"
        case .dampers: return "waveform.path.ecg"
        case .piercing: return "bolt.fill"
        case .twinCannon: return "scope"
        case .capacitor: return "arrow.triangle.2.circlepath"
        case .targeting: return "target"
        case .smuggler: return "eye.slash.fill"
        case .bountyScanner: return "dollarsign.circle.fill"
        case .nanoRepair: return "wrench.and.screwdriver.fill"
        }
    }

    var role: ModRole {
        switch self {
        case .cargoBay, .salvage, .dampers, .smuggler: return .cargo
        case .shield, .plating, .piercing, .twinCannon, .targeting, .bountyScanner: return .combat
        case .battery, .thrusters, .capacitor, .nanoRepair: return .system
        }
    }

    /// nötiger Pilotenrang
    var rank: Int {
        switch self {
        case .battery, .thrusters, .cargoBay: return 0
        case .salvage, .shield, .plating: return 1
        case .dampers, .piercing, .twinCannon: return 2
        case .capacitor, .targeting, .smuggler: return 3
        case .bountyScanner, .nanoRepair: return 4
        }
    }

    /// Stärke der Wirkung je Stufe (Index 0 = nicht eingebaut)
    func amount(_ level: Int) -> CGFloat {
        let l = max(0, min(ModKind.maxLevel, level))
        let table: [CGFloat]
        switch self {
        case .battery: table = [0, 0.12, 0.24, 0.36]
        case .thrusters: table = [0, 0.06, 0.12, 0.18]
        case .cargoBay: table = [0, 0.35, 0.7, 1.1]
        case .salvage: table = [0, 0.3, 0.6, 1.0]
        case .shield: table = [0, 15, 25, 40]
        case .plating: table = [0, 0.05, 0.1, 0.15]
        case .dampers: table = [0, 0.35, 0.55, 0.75]
        case .piercing: table = [0, 0.25, 0.5, 0.8]
        case .twinCannon: table = [0, 0, 0.1, 0.2]
        case .capacitor: table = [0, 0.1, 0.2, 0.3]
        case .targeting: table = [0, 0.15, 0.3, 0.45]
        case .smuggler: table = [0, 0.25, 0.5, 0.8]
        case .bountyScanner: table = [0, 0.25, 0.5, 0.8]
        case .nanoRepair: table = [0, 1, 2, 3]
        }
        return table[l]
    }

    /// Wirkung einer Stufe als kurzer Text
    func effect(_ level: Int) -> String {
        let a = amount(level)
        let pct = Int((a * 100).rounded())
        switch self {
        case .battery: return "+\(pct) % ENERGIESPEICHER"
        case .thrusters: return "+\(pct) % TEMPO"
        case .cargoBay: return "+\(pct) % FRACHTRAUM"
        case .salvage: return "+\(pct) % BEUTE AUS WRACKS UND PIRATEN"
        case .shield: return "SCHILD \(Int(a)) · LÄDT NACH 3 S"
        case .plating: return "+\(pct) PANZERUNG"
        case .dampers: return "\(pct) % WENIGER FRACHTVERLUST"
        case .piercing: return "+\(pct) % SCHADEN GEGEN SCHIFFE"
        case .twinCannon: return level <= 1 ? "KANONE FEUERT DOPPELT" : "DOPPELT · \(pct) % SCHNELLER"
        case .capacitor: return "−\(pct) % WAFFENKOSTEN"
        case .targeting: return "+\(pct) % REICHWEITE UND ZIELHILFE"
        case .smuggler: return "+\(pct) % FRACHTLOHN"
        case .bountyScanner: return "+\(pct) % KOPFGELD"
        case .nanoRepair: return "+\(Int(a)) PANZERUNG/S IM ORBIT"
        }
    }

    /// Tech-Teile für den Kauf (Stufe 1) oder die nächste Stufe
    func cost(toLevel level: Int) -> Int {
        let base: CGFloat
        switch rank {
        case 0: base = 20
        case 1: base = 35
        case 2: base = 55
        case 3: base = 80
        default: base = 120
        }
        let factor: CGFloat = level <= 1 ? 1 : (level == 2 ? 2 : 3.5)
        return Int((base * factor / 5).rounded()) * 5
    }

    static func roman(_ level: Int) -> String { ["", "MK I", "MK II", "MK III"][max(0, min(3, level))] }
}

// MARK: - Werkstatt

struct WorkshopView: View {
    let profile: Profile
    let onClose: () -> Void

    private let signal = Color(red: 79 / 255, green: 227 / 255, blue: 193 / 255)
    private let gold = Color(red: 1, green: 0.85, blue: 0.42)
    private let dim = Color(red: 0.55, green: 0.6, blue: 0.72)
    private let warn = Color(red: 1, green: 0.42, blue: 0.37)
    private let panel = Color(red: 0.02, green: 0.07, blue: 0.11)

    private func label(_ text: String) -> Text {
        Text(text)
            .font(.system(size: 9, weight: .medium, design: .monospaced))
            .tracking(1.4)
    }

    var body: some View {
        let ship = profile.selected
        VStack(spacing: 10) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    slotsPanel(ship)
                    ForEach(ModRole.allCases) { role in
                        label(role.title).foregroundStyle(role.color.opacity(0.9)).padding(.top, 8)
                        ForEach(ModKind.allCases.filter { $0.role == role }) { k in
                            modRow(k, ship)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
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
                label("HANGAR // MODS").foregroundStyle(signal.opacity(0.8))
                Text("WERKSTATT")
                    .font(.system(size: 24, weight: .heavy, design: .monospaced))
                    .tracking(3)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .foregroundStyle(.white)
                    .shadow(color: signal.opacity(0.6), radius: 10)
                label("RANG \(PilotRank.title(profile.rank))").foregroundStyle(gold)
            }
            .layoutPriority(1)
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                label("TECH-TEILE").foregroundStyle(dim).lineLimit(1).fixedSize()
                HStack(spacing: 5) {
                    Image(systemName: "gearshape.fill").font(.system(size: 14))
                    Text("\(profile.parts)")
                        .font(.system(size: 20, weight: .bold, design: .monospaced))
                        .lineLimit(1)
                        .fixedSize()
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

    /// Einbauplätze des gewählten Schiffs; Tippen auf eine Mod baut sie aus
    private func slotsPanel(_ ship: Ship) -> some View {
        let installed = profile.installed(ship.model)
        let role = ship.model.role
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                label("\(ship.name) · \(role.title)").foregroundStyle(role.color)
                Spacer()
                label("\(installed.count)/\(ship.model.modSlots) PLÄTZE").foregroundStyle(dim)
            }
            HStack(spacing: 6) {
                ForEach(0..<ship.model.modSlots, id: \.self) { i in
                    if i < installed.count {
                        let k = installed[i]
                        Button { profile.remove(k, from: ship.model) } label: {
                            VStack(spacing: 3) {
                                Image(systemName: k.symbol).font(.system(size: 15, weight: .bold))
                                label(ModKind.roman(profile.modLevel(k)))
                            }
                            .foregroundStyle(k.role.color)
                            .frame(maxWidth: .infinity, minHeight: 50)
                            .background(Chamfer(cut: 6).fill(k.role.color.opacity(0.12)))
                            .overlay(Chamfer(cut: 6).stroke(k.role.color.opacity(0.7), lineWidth: 1))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(k.title) ausbauen")
                    } else {
                        label("FREI")
                            .foregroundStyle(dim.opacity(0.6))
                            .frame(maxWidth: .infinity, minHeight: 50)
                            .overlay(Chamfer(cut: 6).stroke(dim.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
                    }
                }
            }
            label("FRACHTRAUM \(ship.cargoCapacity) · KOPFGELD ×\(String(format: "%.2f", ship.bountyFactor))"
                  + (ship.shieldMax > 0 ? " · SCHILD \(Int(ship.shieldMax))" : ""))
                .foregroundStyle(dim)
        }
        .padding(12)
        .background(Chamfer(cut: 10).fill(panel.opacity(0.85)))
        .overlay(Chamfer(cut: 10).stroke(signal.opacity(0.45), lineWidth: 1))
    }

    private func modRow(_ k: ModKind, _ ship: Ship) -> some View {
        let level = profile.modLevel(k)
        let locked = profile.rank < k.rank
        let installed = profile.installed(ship.model).contains(k)
        let full = profile.installed(ship.model).count >= ship.model.modSlots
        let color = k.role.color
        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: locked ? "lock.fill" : k.symbol)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(locked ? dim.opacity(0.6) : color)
                .frame(width: 26)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(k.title)
                        .font(.system(size: 12, weight: .heavy, design: .monospaced))
                        .tracking(1)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .foregroundStyle(locked ? dim : .white)
                    Spacer(minLength: 4)
                    HStack(spacing: 3) {
                        ForEach(0..<ModKind.maxLevel, id: \.self) { i in
                            Rectangle().fill(i < level ? color : Color.white.opacity(0.1)).frame(width: 8, height: 8)
                        }
                    }
                }
                label(level > 0 ? k.effect(level) : k.effect(1)).foregroundStyle(level > 0 ? color : dim)
                if level > 0 && level < ModKind.maxLevel {
                    label("NÄCHSTE STUFE: \(k.effect(level + 1))").foregroundStyle(dim)
                }
                if k == .twinCannon && ship.weapon != .cannon {
                    label("WIRKT NUR BEI SCHIFFEN MIT KANONE").foregroundStyle(warn.opacity(0.85))
                }
                HStack(spacing: 6) {
                    if locked {
                        label("AB RANG \(PilotRank.title(k.rank))").foregroundStyle(dim)
                    } else {
                        if level < ModKind.maxLevel {
                            let cost = k.cost(toLevel: level + 1)
                            let can = profile.parts >= cost
                            smallButton(level == 0 ? "KAUFEN ⚙ \(cost)" : "\(ModKind.roman(level + 1)) ⚙ \(cost)",
                                        can ? gold : dim, enabled: can) {
                                profile.buyMod(k)
                            }
                        } else {
                            label("MAXIMUM").foregroundStyle(gold)
                        }
                        if level > 0 {
                            if installed {
                                smallButton("AUSBAUEN", signal, enabled: true) { profile.remove(k, from: ship.model) }
                            } else {
                                smallButton(full ? "PLÄTZE VOLL" : "EINBAUEN", full ? dim : signal, enabled: !full) {
                                    profile.install(k, on: ship.model)
                                }
                            }
                        }
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(12)
        .background(Chamfer(cut: 8).fill(panel.opacity(installed ? 0.95 : 0.75)))
        .overlay(Chamfer(cut: 8).stroke((installed ? color : dim).opacity(installed ? 0.7 : 0.3), lineWidth: 1))
    }

    private func smallButton(_ text: String, _ color: Color, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .tracking(1)
                .lineLimit(1)
                .fixedSize()
                .foregroundStyle(color)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Chamfer(cut: 5).fill(color.opacity(0.12)))
                .overlay(Chamfer(cut: 5).stroke(color.opacity(0.7), lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}
