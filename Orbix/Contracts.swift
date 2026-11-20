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

// MARK: - Ansicht: Auftragsterminal im Kommandoraum der Station

/// Das Auftragsbrett gibt es nur an Bord einer Raumstation: ein eigener Raum mit einer alten Computerkonsole.
/// Phosphorgrüne Schrift, Rasterlinien und ein kurzer Startvorgang beim Einloggen.
struct ContractBoardView: View {
    let board: ContractBoard
    let profile: Profile
    /// gerade ein Auftrag im laufenden Flug aktiv (dann kein neuer)
    let running: Bool
    /// im Tagesflug gibt es keine Aufträge
    let daily: Bool
    /// Name der Station, an der das Terminal steht
    var station: String = "RAUMSTATION"
    let onClose: () -> Void

    @State private var bootLines = 0
    @State private var ready = false

    private let phosphor = Color(red: 0.42, green: 1, blue: 0.58)
    private let amber = Color(red: 1, green: 0.74, blue: 0.3)
    private let alarm = Color(red: 1, green: 0.4, blue: 0.35)
    private let screen = Color(red: 0.01, green: 0.045, blue: 0.025)
    private let shipPartColor = hsl(ItemKind.shipPart.hue, 0.8, 0.68)
    private var faint: Color { phosphor.opacity(0.55) }

    private func mono(_ text: String, _ size: CGFloat = 10, _ weight: Font.Weight = .medium) -> Text {
        Text(text)
            .font(.system(size: size, weight: weight, design: .monospaced))
            .tracking(size < 12 ? 1.2 : 2)
    }

    var body: some View {
        ZStack {
            room
            VStack(spacing: 0) {
                roomHeader
                console
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
            }
        }
        .statusBarHidden(true)
        .task { await boot() }
    }

    // MARK: Raum

    /// dunkler Kommandoraum: Wandpaneele, gedämpftes Licht von oben, die Konsole leuchtet
    private var room: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.07, green: 0.08, blue: 0.1), Color(red: 0.02, green: 0.02, blue: 0.03)],
                           startPoint: .top, endPoint: .bottom)
            // Wandpaneele
            HStack(spacing: 0) {
                ForEach(0..<6, id: \.self) { _ in
                    Rectangle().fill(Color.white.opacity(0.018))
                        .overlay(Rectangle().fill(Color.black.opacity(0.5)).frame(width: 1), alignment: .trailing)
                }
            }
            RadialGradient(colors: [phosphor.opacity(0.10), .clear], center: .center, startRadius: 40, endRadius: 420)
        }
        .ignoresSafeArea()
    }

    private var roomHeader: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                mono("\(station) · DECK 3").foregroundStyle(Color.white.opacity(0.45))
                mono("KOMMANDORAUM", 15, .heavy).foregroundStyle(Color.white.opacity(0.85))
            }
            Spacer()
            Button(action: onClose) {
                HStack(spacing: 6) {
                    Image(systemName: "door.left.hand.open").font(.system(size: 13, weight: .bold))
                    mono("ZURÜCK ZUM DOCK", 10, .bold)
                }
                .foregroundStyle(Color.white.opacity(0.8))
                .padding(.horizontal, 12)
                .frame(height: 36)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.06)))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.2), lineWidth: 1))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Kommandoraum verlassen")
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
        .padding(.bottom, 10)
    }

    // MARK: Konsole

    /// Gehäuse mit Bildschirm: Metallrahmen, Schrauben, Kontrollleuchten
    private var console: some View {
        VStack(spacing: 8) {
            screenView
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.black, lineWidth: 3))
            HStack(spacing: 10) {
                light(phosphor, on: true)
                light(amber, on: board.active != nil)
                light(alarm, on: running)
                mono("ORBIX-NET TERMINAL MK IV", 8).foregroundStyle(Color.white.opacity(0.35))
                Spacer()
                mono("⚙ \(profile.parts)", 11, .bold).foregroundStyle(amber)
            }
            .padding(.horizontal, 8)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(LinearGradient(colors: [Color(white: 0.24), Color(white: 0.12)], startPoint: .top, endPoint: .bottom))
        )
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.white.opacity(0.18), lineWidth: 1))
        .overlay(alignment: .topLeading) { screw.padding(6) }
        .overlay(alignment: .topTrailing) { screw.padding(6) }
        .overlay(alignment: .bottomLeading) { screw.padding(6) }
        .overlay(alignment: .bottomTrailing) { screw.padding(6) }
        .shadow(color: phosphor.opacity(0.15), radius: 24)
    }

    private var screw: some View {
        Circle().fill(Color(white: 0.35)).frame(width: 5, height: 5)
            .overlay(Rectangle().fill(Color.black.opacity(0.6)).frame(width: 4, height: 1))
    }

    private func light(_ c: Color, on: Bool) -> some View {
        Circle().fill(on ? c : c.opacity(0.15)).frame(width: 7, height: 7)
            .shadow(color: on ? c : .clear, radius: 4)
    }

    private var screenView: some View {
        ZStack {
            screen
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    bootText
                    if ready { terminalContent.transition(.opacity) }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)
            scanlines.allowsHitTesting(false)
            // leichte Wölbung des Bildschirms
            RadialGradient(colors: [.clear, .black.opacity(0.45)], center: .center, startRadius: 160, endRadius: 520)
                .allowsHitTesting(false)
        }
    }

    /// Rasterlinien wie auf einem Röhrenbildschirm (statisch, kostet nichts)
    private var scanlines: some View {
        Canvas { ctx, size in
            var y: CGFloat = 0
            var path = Path()
            while y < size.height {
                path.addRect(CGRect(x: 0, y: y, width: size.width, height: 1))
                y += 3
            }
            ctx.fill(path, with: .color(.black.opacity(0.28)))
        }
    }

    // MARK: Startvorgang

    private var bootMessages: [String] {
        let ship = profile.selected
        return [
            "> VERBINDE MIT STATIONSNETZ ......... OK",
            "> PILOT ERKANNT · RANG \(PilotRank.title(profile.rank)) · RUF \(profile.reputation)",
            "> SCHIFF \(ship.name) · \(ship.model.role.title) · \(ship.cargoCapacity) CONTAINER",
            daily ? "> TAGESFLUG: KEINE AUFTRÄGE FREIGEGEBEN" : "> \(board.offers.count) AUFTRÄGE IM NETZ",
        ]
    }

    private var bootText: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(Array(bootMessages.prefix(bootLines).enumerated()), id: \.offset) { _, line in
                mono(line, 10).foregroundStyle(faint)
            }
            if !ready {
                TimelineView(.periodic(from: .now, by: 0.45)) { t in
                    let on = Int(t.date.timeIntervalSinceReferenceDate / 0.45) % 2 == 0
                    mono("▌", 11).foregroundStyle(phosphor.opacity(on ? 1 : 0))
                }
            }
        }
        .shadow(color: phosphor.opacity(0.5), radius: 3)
    }

    @MainActor
    private func boot() async {
        guard !ready else { return }
        for i in 1...bootMessages.count {
            try? await Task.sleep(nanoseconds: 180_000_000)
            bootLines = i
        }
        try? await Task.sleep(nanoseconds: 200_000_000)
        withAnimation(.easeOut(duration: 0.25)) { ready = true }
    }

    // MARK: Inhalt

    private var terminalContent: some View {
        let ship = profile.selected
        return VStack(alignment: .leading, spacing: 10) {
            divider("AUFTRAGSTERMINAL")
            rankPanel
            if let c = board.active {
                divider(running ? "LAUFENDER AUFTRAG" : "ANGENOMMEN")
                card(c, ship: ship, active: true, number: 0)
            }
            divider(daily ? "GESPERRT" : "ANGEBOTE")
            if daily {
                mono("IM TAGESFLUG GIBT ES KEINE AUFTRÄGE.", 10).foregroundStyle(alarm)
            }
            ForEach(Array(board.offers.enumerated()), id: \.element.id) { i, c in
                card(c, ship: ship, active: false, number: i + 1)
            }
            mono("// FRACHTER VERDIENEN AN FRACHT, SCHNELLE JÄGER MIT KANONEN AN KOPFGELD. JEDER ERFÜLLTE AUFTRAG BRINGT RUF UND MIT GLÜCK EIN SCHIFFSTEIL.", 9)
                .foregroundStyle(faint)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
        }
        .shadow(color: phosphor.opacity(0.45), radius: 3)
    }

    private func divider(_ title: String) -> some View {
        HStack(spacing: 6) {
            mono("== \(title) ", 10, .bold).foregroundStyle(phosphor)
            Rectangle().fill(phosphor.opacity(0.35)).frame(height: 1)
        }
        .padding(.top, 4)
    }

    private var rankPanel: some View {
        let rep = profile.reputation
        let rank = profile.rank
        let blocks = 20
        let filled = Int((PilotRank.progress(for: rep) * CGFloat(blocks)).rounded(.down))
        let bar = String(repeating: "█", count: filled) + String(repeating: "░", count: blocks - filled)
        let missing = PilotRank.missing(for: rep)
        return VStack(alignment: .leading, spacing: 4) {
            mono("RANG  \(PilotRank.title(rank))", 13, .heavy).foregroundStyle(amber)
            mono("[\(bar)]", 10).foregroundStyle(amber.opacity(0.85))
            mono(missing > 0 ? "NOCH \(missing) RUF BIS \(PilotRank.title(rank + 1)) · \(board.completed) AUFTRÄGE ERFÜLLT"
                             : "HÖCHSTER RANG · \(board.completed) AUFTRÄGE ERFÜLLT", 9)
                .foregroundStyle(faint)
        }
    }

    private func card(_ c: Contract, ship: Ship, active: Bool, number: Int) -> some View {
        let reward = c.reward(ship)
        let fits = ship.model.role == c.bestRole
        let canAccept = !active && board.active == nil && !running && !daily
        let tag = active ? "**" : String(format: "%02d", number)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                mono("[\(tag)]", 11, .bold).foregroundStyle(faint)
                Image(systemName: c.symbol).font(.system(size: 12, weight: .bold)).foregroundStyle(c.color)
                mono(c.title, 12, .heavy)
                    .foregroundStyle(phosphor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 0)
            }
            mono(c.client.isEmpty ? "STUFE \(c.tier + 1)" : "AUFTRAGGEBER \(c.client) · STUFE \(c.tier + 1)", 9)
                .foregroundStyle(faint)
            mono(c.detail, 10).foregroundStyle(phosphor.opacity(0.9)).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                mono("LOHN ⚙ \(reward)", 12, .bold).foregroundStyle(amber)
                mono("+\(c.reputation) RUF", 9).foregroundStyle(amber.opacity(0.8))
                mono("TEIL \(Int((c.shipPartChance * 100).rounded())) %", 9).foregroundStyle(shipPartColor)
                Spacer(minLength: 0)
            }
            mono("> " + roleHint(c, ship: ship, fits: fits), 9)
                .foregroundStyle(fits ? phosphor : faint)
                .fixedSize(horizontal: false, vertical: true)
            if canAccept {
                terminalButton("ANNEHMEN", phosphor) { board.accept(c) }
            } else if active && !running {
                terminalButton("ZURÜCKGEBEN", faint) { board.cancel() }
            }
        }
        .padding(10)
        .background(phosphor.opacity(active ? 0.08 : 0.03))
        .overlay(Rectangle().stroke(phosphor.opacity(active ? 0.7 : 0.3), style: StrokeStyle(lineWidth: 1, dash: active ? [] : [4, 3])))
    }

    private func terminalButton(_ title: String, _ color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            mono("[ \(title) ]", 12, .bold)
                .foregroundStyle(color)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(color.opacity(0.1))
                .overlay(Rectangle().stroke(color.opacity(0.8), lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
