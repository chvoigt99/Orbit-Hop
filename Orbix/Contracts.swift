import SwiftUI
import Observation

// MARK: - Aufträge

/// Aufträge geben einem Flug ein Ziel: Fracht zustellen, ein Kopfgeld kassieren oder eine Route von Piraten säubern.
/// Man nimmt sie im Hangar oder an einer Raumstation an; sie gelten bis zum Ende des Flugs (Christian, 2026-11-20).
enum ContractKind: String, Codable {
    case cargo, bounty, patrol
}

enum CargoType: String, Codable {
    /// normale Ware
    case standard
    /// bruchempfindlich: jeder Treffer kostet doppelt so viel Fracht, dafür deutlich besser bezahlt
    case fragile
    /// eilig: Aufschlag, wenn die Fracht rechtzeitig ankommt
    case express

    var title: String {
        switch self {
        case .standard: return "STANDARD"
        case .fragile: return "ZERBRECHLICH"
        case .express: return "EXPRESS"
        }
    }

    var payFactor: CGFloat {
        switch self {
        case .standard: return 1
        case .fragile: return 1.6
        case .express: return 1.15
        }
    }
}

struct Contract: Codable, Identifiable, Equatable {
    var id = UUID()
    let kind: ContractKind
    /// Schwierigkeit und Lohnstufe, wächst mit dem Pilotenrang
    let tier: Int
    /// Fracht: Sprünge bis zum Zielplaneten; Kopfgeld: Sprünge, bis das Ziel auftaucht
    let jumps: Int
    var cargo: CargoType = .standard
    /// Patrouille: so viele Piraten in einem Flug abschießen
    var kills: Int = 0
    /// Ware (Fracht) oder Name des Kopfgeldziels
    var subject: String = ""
    var client: String = ""

    static let goods = ["ERZ", "WASSEREIS", "SAATGUT", "ERSATZTEILE", "LUXUSWAREN", "TREIBSTOFF"]
    static let fragileGoods = ["MEDIZIN", "KRISTALLE", "REAKTORKERNE", "SENSOREN"]
    static let clients = ["HANDELSGILDE", "MINENKONSORTIUM", "KOLONIERAT", "FREIHÄNDLER", "STATIONSRAT", "FORSCHUNGSFLOTTE"]
    static let targets = ["ROTE NATTER", "SCHWARZER KOMET", "KAPITÄN KRAAL", "DIE WITWE", "EISENZAHN",
                          "NULL-SIGNAL", "GRAUER WOLF", "SKORPION", "ASCHEFAUST", "LADY VOLT"]

    static func make(_ kind: ContractKind, tier: Int) -> Contract {
        let t = max(0, min(6, tier))
        switch kind {
        case .cargo:
            let roll = Double.random(in: 0...1)
            let type: CargoType = roll < 0.5 ? .standard : (roll < 0.75 ? .fragile : .express)
            let subject = (type == .fragile ? fragileGoods : goods).randomElement() ?? "ERZ"
            return Contract(kind: .cargo, tier: t, jumps: Int.random(in: 5...8) + t / 2, cargo: type,
                            subject: subject, client: clients.randomElement() ?? "")
        case .bounty:
            return Contract(kind: .bounty, tier: t, jumps: Int.random(in: 4...7),
                            subject: targets.randomElement() ?? "ROTE NATTER", client: clients.randomElement() ?? "")
        case .patrol:
            return Contract(kind: .patrol, tier: t, jumps: 0, kills: min(10, 3 + t + Int.random(in: 0...1)),
                            client: clients.randomElement() ?? "")
        }
    }

    // MARK: Lohn

    /// Lohn je zugestellten Container
    func unitPay(_ ship: Ship) -> CGFloat {
        (0.9 + 0.12 * CGFloat(jumps)) * cargo.payFactor * (1 + 0.1 * CGFloat(tier)) * ship.cargoPayFactor
    }

    /// Tech-Teile, wenn dieses Schiff den Auftrag erfüllt (Fracht: voller Laderaum, Express ohne Zeitbonus)
    func reward(_ ship: Ship, units: Int? = nil) -> Int {
        switch kind {
        case .cargo:
            return max(1, Int((unitPay(ship) * CGFloat(units ?? ship.cargoCapacity)).rounded()))
        case .bounty:
            return Int((CGFloat(14 + 5 * tier) * ship.bountyFactor).rounded())
        case .patrol:
            return Int((CGFloat(3 * kills + 2 * tier) * ship.bountyFactor).rounded())
        }
    }

    var reputation: Int {
        switch kind {
        case .cargo: return 8 + jumps + 2 * tier
        case .bounty: return 20 + 4 * tier
        case .patrol: return 12 + 3 * tier
        }
    }

    var shipPartChance: Double {
        switch kind {
        case .cargo: return 0.1 + 0.02 * Double(tier)
        case .bounty: return 0.3 + 0.03 * Double(tier)
        case .patrol: return 0.12 + 0.02 * Double(tier)
        }
    }

    /// Zeitlimit für den Express-Aufschlag
    var expressTime: CGFloat { CGFloat(jumps) * 11 }
    static let expressBonus: CGFloat = 1.5

    // MARK: Texte

    var title: String {
        switch kind {
        case .cargo: return "FRACHT · \(subject)"
        case .bounty: return "KOPFGELD · \(subject)"
        case .patrol: return "PATROUILLE"
        }
    }

    var detail: String {
        switch kind {
        case .cargo:
            let extra = cargo == .express ? " · IN \(Int(expressTime)) S +50 %" : (cargo == .fragile ? " · TREFFER KOSTEN DOPPELT" : "")
            return "\(cargo.title) · ZIEL IN \(jumps) SPRÜNGEN\(extra)"
        case .bounty:
            return "PIRATENANFÜHRER · TAUCHT IN \(jumps) SPRÜNGEN AUF"
        case .patrol:
            return "ZERSTÖRE \(kills) PIRATEN IN EINEM FLUG"
        }
    }

    var symbol: String {
        switch kind {
        case .cargo: return "shippingbox.fill"
        case .bounty: return "scope"
        case .patrol: return "shield.lefthalf.filled"
        }
    }

    var color: Color {
        switch kind {
        case .cargo: return Color(red: 0.55, green: 0.7, blue: 1)
        case .bounty: return Color(red: 1, green: 0.45, blue: 0.4)
        case .patrol: return Color(red: 1, green: 0.7, blue: 0.35)
        }
    }

    /// Schiffsrolle, die für diesen Auftrag am meisten verdient
    var bestRole: ShipRole { kind == .cargo ? .freighter : .fighter }
}

// MARK: - Auftragsbrett

/// Drei Angebote (möglichst je eine Art) und höchstens ein angenommener Auftrag, gespeichert in UserDefaults
@Observable
final class ContractBoard {
    private(set) var offers: [Contract] = []
    private(set) var active: Contract? = nil
    private(set) var completed: Int

    private let defaults = UserDefaults.standard
    private static let offersKey = "orbixContractOffers"
    private static let activeKey = "orbixContractActive"
    private static let completedKey = "orbixContractsDone"

    init() {
        completed = defaults.integer(forKey: Self.completedKey)
        if let data = defaults.data(forKey: Self.offersKey),
           let saved = try? JSONDecoder().decode([Contract].self, from: data) {
            offers = saved
        }
        if let data = defaults.data(forKey: Self.activeKey),
           let saved = try? JSONDecoder().decode(Contract.self, from: data) {
            active = saved
        }
        refill()
    }

    /// Rang aus dem gespeicherten Ruf (das Brett braucht kein Profil)
    private var rank: Int { PilotRank.rank(for: defaults.integer(forKey: "orbixReputation")) }

    /// Angebote auf drei auffüllen, fehlende Arten zuerst
    func refill() {
        while offers.count < 3 {
            let kinds: [ContractKind] = [.cargo, .bounty, .patrol]
            let missing = kinds.filter { k in !offers.contains { $0.kind == k } }
            let kind = missing.randomElement() ?? kinds.randomElement() ?? .cargo
            offers.append(Contract.make(kind, tier: rank + Int.random(in: 0...1)))
        }
        save()
    }

    func accept(_ c: Contract) {
        guard active == nil, let i = offers.firstIndex(where: { $0.id == c.id }) else { return }
        active = c
        offers.remove(at: i)
        refill()
    }

    /// angenommenen, noch nicht begonnenen Auftrag zurückgeben
    func cancel() {
        guard let c = active else { return }
        active = nil
        if offers.count >= 3 { offers.removeLast() }
        offers.insert(c, at: 0)
        save()
    }

    func finish() {
        active = nil
        completed += 1
        save()
    }

    func fail() {
        active = nil
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(offers) { defaults.set(data, forKey: Self.offersKey) }
        if let c = active, let data = try? JSONEncoder().encode(c) {
            defaults.set(data, forKey: Self.activeKey)
        } else {
            defaults.removeObject(forKey: Self.activeKey)
        }
        defaults.set(completed, forKey: Self.completedKey)
    }
}

// MARK: - Ansicht

struct ContractBoardView: View {
    let board: ContractBoard
    let profile: Profile
    /// gerade ein Auftrag im laufenden Flug aktiv (dann kein neuer)
    let running: Bool
    /// im Tagesflug gibt es keine Aufträge
    let daily: Bool
    let onClose: () -> Void

    private let signal = Color(red: 79 / 255, green: 227 / 255, blue: 193 / 255)
    private let gold = Color(red: 1, green: 0.85, blue: 0.42)
    private let dim = Color(red: 0.55, green: 0.6, blue: 0.72)
    private let warn = Color(red: 1, green: 0.42, blue: 0.37)
    private let panel = Color(red: 0.02, green: 0.07, blue: 0.11)
    private let shipPartColor = hsl(ItemKind.shipPart.hue, 0.8, 0.68)

    private func label(_ text: String) -> Text {
        Text(text)
            .font(.system(size: 9, weight: .medium, design: .monospaced))
            .tracking(1.4)
    }

    var body: some View {
        let ship = profile.selected
        VStack(spacing: 12) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    rankPanel
                    if let c = board.active {
                        label(running ? "LAUFENDER AUFTRAG" : "ANGENOMMEN · BEGINNT BEIM NÄCHSTEN START")
                            .foregroundStyle(signal.opacity(0.8))
                            .padding(.top, 6)
                        card(c, ship: ship, active: true)
                    }
                    label(daily ? "IM TAGESFLUG GIBT ES KEINE AUFTRÄGE" : "ANGEBOTE · \(ship.name) · \(ship.model.role.title)")
                        .foregroundStyle(daily ? warn : signal.opacity(0.8))
                        .padding(.top, 6)
                    ForEach(board.offers) { c in card(c, ship: ship, active: false) }
                    label("FRACHTER VERDIENEN AN FRACHT, SCHNELLE JÄGER MIT KANONEN AN KOPFGELD. JEDER ERFÜLLTE AUFTRAG BRINGT RUF UND MIT GLÜCK EIN SCHIFFSTEIL.")
                        .foregroundStyle(dim)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 6)
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
                label("FUNK // AUFTRAGSBRETT").foregroundStyle(signal.opacity(0.8))
                Text("AUFTRÄGE")
                    .font(.system(size: 26, weight: .heavy, design: .monospaced))
                    .tracking(3)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .foregroundStyle(.white)
                    .shadow(color: signal.opacity(0.6), radius: 10)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                label("TECH-TEILE").foregroundStyle(dim)
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

    private var rankPanel: some View {
        let rep = profile.reputation
        let rank = profile.rank
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "star.circle.fill").font(.system(size: 14, weight: .bold))
                Text("RANG \(PilotRank.title(rank))")
                    .font(.system(size: 14, weight: .heavy, design: .monospaced))
                    .tracking(2)
                Spacer()
                label("RUF \(rep)").foregroundStyle(dim)
            }
            .foregroundStyle(gold)
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Rectangle().fill(gold.opacity(0.15))
                    Rectangle().fill(gold).frame(width: g.size.width * PilotRank.progress(for: rep))
                }
            }
            .frame(height: 4)
            let missing = PilotRank.missing(for: rep)
            label(missing > 0 ? "NOCH \(missing) RUF BIS \(PilotRank.title(rank + 1)) · \(board.completed) AUFTRÄGE ERFÜLLT"
                              : "HÖCHSTER RANG · \(board.completed) AUFTRÄGE ERFÜLLT")
                .foregroundStyle(dim)
        }
        .padding(12)
        .background(Chamfer(cut: 8).fill(panel.opacity(0.85)))
        .overlay(Chamfer(cut: 8).stroke(gold.opacity(0.45), lineWidth: 1))
    }

    private func card(_ c: Contract, ship: Ship, active: Bool) -> some View {
        let reward = c.reward(ship)
        let fits = ship.model.role == c.bestRole
        let canAccept = !active && board.active == nil && !running && !daily
        return VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 10) {
                Image(systemName: c.symbol)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(c.color)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(c.title)
                        .font(.system(size: 13, weight: .heavy, design: .monospaced))
                        .tracking(1)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .foregroundStyle(.white)
                    label(c.client.isEmpty ? "STUFE \(c.tier + 1)" : "\(c.client) · STUFE \(c.tier + 1)").foregroundStyle(dim)
                }
                Spacer()
            }
            label(c.detail).foregroundStyle(c.color.opacity(0.9)).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                HStack(spacing: 4) {
                    Image(systemName: "gearshape.fill").font(.system(size: 11))
                    Text("\(reward)").font(.system(size: 15, weight: .bold, design: .monospaced))
                }
                .foregroundStyle(gold)
                label("+\(c.reputation) RUF").foregroundStyle(gold.opacity(0.8))
                label("SCHIFFSTEIL \(Int((c.shipPartChance * 100).rounded())) %").foregroundStyle(shipPartColor)
                Spacer()
            }
            // Rollenhinweis: welches Schiff hier am meisten verdient
            label(roleHint(c, ship: ship, fits: fits))
                .foregroundStyle(fits ? c.bestRole.color : dim)
                .fixedSize(horizontal: false, vertical: true)
            if canAccept {
                Button { board.accept(c) } label: {
                    Text("ANNEHMEN")
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .tracking(2)
                        .foregroundStyle(c.color)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Chamfer(cut: 6).fill(c.color.opacity(0.12)))
                        .overlay(Chamfer(cut: 6).stroke(c.color.opacity(0.8), lineWidth: 1.2))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else if active && !running {
                Button { board.cancel() } label: {
                    Text("ZURÜCKGEBEN")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .tracking(2)
                        .foregroundStyle(dim)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .overlay(Chamfer(cut: 6).stroke(dim.opacity(0.6), lineWidth: 1))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(Chamfer(cut: 8).fill(panel.opacity(active ? 0.95 : 0.8)))
        .overlay(Chamfer(cut: 8).stroke(c.color.opacity(active ? 0.8 : 0.4), lineWidth: active ? 1.5 : 1))
    }

    private func roleHint(_ c: Contract, ship: Ship, fits: Bool) -> String {
        switch c.kind {
        case .cargo:
            let per = String(format: "%.1f", c.unitPay(ship))
            return fits ? "FRACHTER-BONUS · \(ship.cargoCapacity) CONTAINER × \(per) ⚙"
                        : "NUR \(ship.cargoCapacity) CONTAINER × \(per) ⚙ · EIN FRACHTER LÄDT VIEL MEHR"
        case .bounty, .patrol:
            let f = String(format: "%.2f", ship.bountyFactor)
            return fits ? "JÄGER-BONUS · KOPFGELD ×\(f)" : "KOPFGELD ×\(f) · SCHNELLE JÄGER MIT KANONEN VERDIENEN MEHR"
        }
    }
}

// MARK: - Aufträge im Flug

extension Game {
    private var gold: Color { Color(red: 1, green: 0.85, blue: 0.42) }

    /// Name des Kopfgeldziels (im Test ohne Auftrag ein Platzhalter)
    var bountyName: String {
        if let c = contracts.active, c.kind == .bounty { return c.subject }
        return "ANFÜHRER"
    }

    /// angenommenen Auftrag im laufenden Flug beginnen: Fracht laden, Kopfgeldziel orten, Patrouille melden
    func beginContract() {
        guard !contractRunning, !dailyMode, phase != .over, let c = contracts.active else { return }
        contractRunning = true
        contractStartedAt = time
        contractResult = nil
        switch c.kind {
        case .cargo:
            cargoStart = ship.cargoCapacity
            cargoLoaded = cargoStart
            cargoDest = score + c.jumps
            popups.append(Popup(pos: pos, text: "\(cargoStart) CONTAINER \(c.subject) GELADEN", color: c.color, age: 0))
        case .bounty:
            // erst auf einer Strecke, die noch nicht erzeugt ist
            bountyPlanet = max(score + c.jumps, planetBase + planets.count)
            popups.append(Popup(pos: pos, text: "KOPFGELDZIEL \(c.subject) GEORTET", color: c.color, age: 0))
        case .patrol:
            patrolKills = 0
            popups.append(Popup(pos: pos, text: "PATROUILLE · \(c.kills) PIRATEN", color: c.color, age: 0))
        }
        blog("contract begin \(c.kind) tier=\(c.tier)")
    }

    /// Grund fürs Scheitern, wenn der Flug vorher endet
    var contractFailReason: String {
        switch contracts.active?.kind {
        case .cargo: return "FRACHT NICHT ZUGESTELLT"
        case .bounty: return "ZIEL NICHT GESTELLT"
        case .patrol: return "PATROUILLE ABGEBROCHEN"
        case nil: return "ABGEBROCHEN"
        }
    }

    func failContract(_ reason: String) {
        guard contractRunning else { return }
        blog("contract failed \(reason)")
        contracts.fail()
        contractRunning = false
        contractSuccess = false
        contractResult = "AUFTRAG GESCHEITERT · \(reason)"
        cargoLoaded = 0
        bountyPlanet = -1
    }

    /// Auftrag erfüllt: Tech-Teile, Ruf, mit Glück ein Schiffsteil
    private func completeContract(_ c: Contract, reward: Int, note: String = "") {
        blog("contract done \(c.kind) reward=\(reward)")
        profile.addParts(reward)
        runParts += reward
        let promoted = profile.addReputation(c.reputation)
        if Double.random(in: 0...1) < c.shipPartChance { spawnTech(from: pos, kind: .shipPart) }
        contracts.finish()
        contractRunning = false
        contractSuccess = true
        contractResult = "AUFTRAG ERFÜLLT · +\(reward) TECH · +\(c.reputation) RUF"
        popups.append(Popup(pos: pos, text: "AUFTRAG ERFÜLLT\(note) · +\(reward) TECH", color: gold, age: 0, lift: 20))
        if let r = promoted {
            popups.append(Popup(pos: pos, text: "BEFÖRDERT: \(PilotRank.title(r))", color: gold, age: 0, lift: 50))
        }
        waves.append(Wave(center: pos, r0: 20, age: 0, maxAge: 0.9, hue: 48))
        burst(at: pos, count: 50, hue: 48, speed: 300, life: 1.1)
        shake = max(shake, 0.3)
        Haptics.bonus()
        SoundFX.shared.play(.bonus)
        track(.contract)
    }

    /// Fracht abliefern, sobald der Zielplanet (oder ein späterer) erreicht ist
    func checkDelivery(_ number: Int) {
        guard contractRunning, let c = contracts.active, c.kind == .cargo, number >= cargoDest, cargoLoaded > 0 else { return }
        let units = cargoLoaded
        let inTime = c.cargo == .express && time - contractStartedAt <= c.expressTime
        let reward = Int((CGFloat(c.reward(ship, units: units)) * (inTime ? Contract.expressBonus : 1)).rounded())
        cargoLoaded = 0
        track(.delivered(units))
        completeContract(c, reward: reward, note: inTime ? " · EXPRESS" : "")
    }

    /// Treffer mit Fracht an Bord: je nach Ware und Trägheitsdämpfer gehen Container verloren
    func loseCargo(_ damage: CGFloat) {
        guard contractRunning, let c = contracts.active, c.kind == .cargo, cargoLoaded > 0 else { return }
        let chance = ship.cargoLossChance * (c.cargo == .fragile ? 1 : 0.65)
        guard CGFloat.random(in: 0...1) < chance else { return }
        var n = damage >= 25 ? 2 : 1
        if c.cargo == .fragile { n *= 2 }
        n = min(n, cargoLoaded)
        cargoLoaded -= n
        burst(at: pos, count: 16, hue: ItemKind.cargo.hue, speed: 230, life: 0.9)
        popups.append(Popup(pos: pos, text: "FRACHT −\(n) · \(cargoLoaded)/\(cargoStart)", color: hsl(ItemKind.cargo.hue, 0.8, 0.7), age: 0, lift: 30))
        if cargoLoaded == 0 {
            popups.append(Popup(pos: pos, text: "ALLE FRACHT VERLOREN", color: Color(red: 1, green: 0.45, blue: 0.4), age: 0, lift: 60))
            failContract("ALLE FRACHT VERLOREN")
        }
    }

    /// Frachtcontainer aus einem Wrack: verlorene Fracht ersetzen, sonst als Bergungsgut verkaufen
    func collectCargo() {
        if contractRunning, contracts.active?.kind == .cargo, cargoLoaded < cargoStart {
            cargoLoaded += 1
            popups.append(Popup(pos: pos, text: "FRACHT GEBORGEN · \(cargoLoaded)/\(cargoStart)", color: hsl(ItemKind.cargo.hue, 0.8, 0.7), age: 0))
        } else {
            profile.addParts(2)
            runParts += 2
            popups.append(Popup(pos: pos, text: "BERGUNGSGUT · +2 TECH", color: hsl(ItemKind.cargo.hue, 0.8, 0.7), age: 0))
        }
    }

    /// Abschuss für Patrouille und Kopfgeld zählen
    func contractKill(boss: Bool) {
        guard contractRunning, let c = contracts.active else { return }
        switch c.kind {
        case .patrol:
            patrolKills += 1
            if patrolKills >= c.kills { completeContract(c, reward: c.reward(ship)) }
        case .bounty:
            if boss { completeContract(c, reward: c.reward(ship), note: " · \(c.subject)") }
        case .cargo:
            break
        }
    }

    /// Anführer ist entkommen: er taucht ein paar Strecken später wieder auf
    func bossEscaped() {
        guard contractRunning, contracts.active?.kind == .bounty else { return }
        bountyPlanet = max(score + 3, planetBase + planets.count)
        popups.append(Popup(pos: pos, text: "\(bountyName) ENTKOMMEN · NEUE SPUR", color: Color(red: 1, green: 0.55, blue: 0.4), age: 0, lift: 40))
    }

    /// kurze Zeile fürs HUD, nil ohne laufenden Auftrag
    var contractLine: String? {
        guard contractRunning, let c = contracts.active else { return nil }
        switch c.kind {
        case .cargo:
            let left = max(0, cargoDest - score)
            var t = "FRACHT \(cargoLoaded)/\(cargoStart) · \(c.subject) · " + (left <= 1 ? "ZIEL VORAUS" : "ZIEL IN \(left) SPRÜNGEN")
            if c.cargo == .express {
                let rest = Int(max(0, c.expressTime - (time - contractStartedAt)))
                t += rest > 0 ? String(format: " · EXPRESS %d:%02d", rest / 60, rest % 60) : " · EXPRESS VERPASST"
            }
            return t
        case .bounty:
            let left = bountyPlanet - score
            return "KOPFGELD · \(c.subject) · " + (left <= 1 ? "ZIEL AUF DIESER STRECKE" : "IN \(left) SPRÜNGEN")
        case .patrol:
            return "PATROUILLE · \(patrolKills)/\(c.kills) PIRATEN"
        }
    }
}
