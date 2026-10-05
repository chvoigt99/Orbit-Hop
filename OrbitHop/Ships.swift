import SwiftUI
import Observation

// MARK: - Rumpfformen

enum HullClass: Int, CaseIterable {
    case fighter, scout, hauler, tank, cruiser, interceptor, battleship, phantom, nova

    /// Rumpffarbe (Farbton, Sättigung, Helligkeit)
    var paint: (Double, Double, Double) {
        switch self {
        case .fighter: return (220, 0.1, 0.9)
        case .scout: return (190, 0.2, 0.82)
        case .hauler: return (45, 0.35, 0.62)
        case .tank: return (210, 0.12, 0.45)
        case .cruiser: return (222, 0.4, 0.6)
        case .interceptor: return (355, 0.55, 0.5)
        case .battleship: return (140, 0.12, 0.4)
        case .phantom: return (272, 0.3, 0.3)
        case .nova: return (45, 0.55, 0.72)
        }
    }

    /// Heck-Position (für das Triebwerk)
    var tailX: CGFloat {
        switch self {
        case .fighter: return -2.3
        case .scout: return -2.2
        case .hauler: return -2.6
        case .tank: return -2.5
        case .cruiser: return -2.8
        case .interceptor: return -2.3
        case .battleship: return -2.8
        case .phantom: return -2.4
        case .nova: return -2.6
        }
    }

    /// Obere Hälfte des Umrisses von der Nase bis zur Heckmitte (wird gespiegelt)
    var outline: [(CGFloat, CGFloat)] {
        switch self {
        case .fighter: return [(3, 0), (1.2, -0.7), (-0.2, -0.9), (-1.4, -2.8), (-2.2, -2.8), (-1.8, -1.0), (-2.3, -0.8), (-2.3, 0)]
        case .scout: return [(3.6, 0), (1, -0.6), (-1.2, -0.9), (-2.2, -2.0), (-2.5, -2.0), (-1.9, -0.7), (-2.2, 0)]
        case .hauler: return [(2.6, 0), (2.3, -0.9), (1.6, -1.4), (-2.4, -1.4), (-2.6, -0.9), (-2.6, 0)]
        case .tank: return [(2.4, 0), (1.8, -1.0), (0.6, -1.9), (-1.6, -2.1), (-2.5, -1.4), (-2.5, 0)]
        case .cruiser: return [(3.6, 0), (2.6, -0.55), (-2.6, -0.75), (-2.8, 0)]
        case .interceptor: return [(3.4, 0), (1.2, -0.55), (0.4, -0.7), (1.1, -2.4), (0.3, -2.5), (-1.5, -0.9), (-2.3, -1.3), (-2.5, -1.1), (-2.1, 0)]
        case .battleship: return [(3, 0), (2.4, -0.8), (1.2, -1.2), (0.8, -2.4), (-1.2, -2.6), (-1.6, -1.6), (-2.8, -1.5), (-2.8, 0)]
        case .phantom: return [(2.8, 0), (-2.2, -3.0), (-1.4, -1.0), (-2.4, 0)]
        case .nova: return [(3.8, 0), (2.0, -0.5), (0.5, -1.0), (-0.5, -2.6), (-1.4, -2.8), (-1.2, -1.2), (-2.6, -1.6), (-2.2, -0.6), (-2.6, 0)]
        }
    }
}

// MARK: - Schiffsmodelle

enum Grade: Int {
    case start, normal, good, superior

    var title: String {
        switch self {
        case .start: return "STANDARD"
        case .normal: return "NORMAL"
        case .good: return "GUT"
        case .superior: return "SUPERSCHIFF"
        }
    }

    /// Schiffsteile zum Freischalten (Tech-Teile sind nur für Upgrades)
    var cost: Int {
        switch self {
        case .start: return 0
        case .normal: return 15
        case .good: return 35
        case .superior: return 75
        }
    }

    /// Tech-Teile für das erste Upgrade
    var upgradeBase: Int {
        switch self {
        case .start: return 40
        case .normal: return 50
        case .good: return 75
        case .superior: return 100
        }
    }

    var color: Color {
        switch self {
        case .start: return Color(red: 0.55, green: 0.6, blue: 0.72)
        case .normal: return Color(red: 79 / 255, green: 227 / 255, blue: 193 / 255)
        case .good: return Color(red: 0.45, green: 0.7, blue: 1)
        case .superior: return Color(red: 1, green: 0.78, blue: 0.35)
        }
    }
}

struct ShipModel: Identifiable {
    let id: String
    let name: String
    let classTitle: String
    let blurb: String
    let grade: Grade
    let hull: HullClass
    let weapon: WeaponKind
    let speed: CGFloat
    let energy: CGFloat
    let armor: CGFloat
    let drain: CGFloat

    static let all: [ShipModel] = [
        ShipModel(id: "falke", name: "FALKE", classTitle: "JÄGER", blurb: "Ausgewogen. Der Standard der Flotte.",
                  grade: .start, hull: .fighter, weapon: .cannon, speed: 1.0, energy: 100, armor: 0.1, drain: 1.0),
        ShipModel(id: "libelle", name: "LIBELLE", classTitle: "SPÄHER", blurb: "Sehr schnell und wendig, kleiner Speicher, keine Panzerung.",
                  grade: .normal, hull: .scout, weapon: .rocket, speed: 1.25, energy: 85, armor: 0, drain: 0.95),
        ShipModel(id: "atlas", name: "ATLAS", classTitle: "FRACHTER", blurb: "Riesiger Energiespeicher, dafür träge.",
                  grade: .normal, hull: .hauler, weapon: .bomb, speed: 0.85, energy: 150, armor: 0.15, drain: 1.0),
        ShipModel(id: "bastion", name: "BASTION", classTitle: "PANZERSCHIFF", blurb: "Schwer gepanzert, Asteroiden bremsen kaum.",
                  grade: .normal, hull: .tank, weapon: .cannon, speed: 0.85, energy: 115, armor: 0.55, drain: 1.05),
        ShipModel(id: "orion", name: "ORION", classTitle: "KREUZER", blurb: "Railgun und solide Werte in allen Bereichen.",
                  grade: .good, hull: .cruiser, weapon: .railgun, speed: 1.05, energy: 130, armor: 0.3, drain: 0.95),
        ShipModel(id: "viper", name: "VIPER", classTitle: "ABFANGJÄGER", blurb: "Extrem schnell, Lenkraketen räumen den Weg.",
                  grade: .good, hull: .interceptor, weapon: .rocket, speed: 1.35, energy: 105, armor: 0.15, drain: 0.9),
        ShipModel(id: "titan", name: "TITAN", classTitle: "SCHLACHTSCHIFF", blurb: "Gewaltiger Speicher und dicke Panzerung.",
                  grade: .good, hull: .battleship, weapon: .bomb, speed: 0.9, energy: 170, armor: 0.6, drain: 1.0),
        ShipModel(id: "phantom", name: "PHANTOM", classTitle: "TARNSCHIFF", blurb: "Verbraucht kaum Energie, schnell und gut geschützt.",
                  grade: .superior, hull: .phantom, weapon: .railgun, speed: 1.3, energy: 140, armor: 0.4, drain: 0.7),
        ShipModel(id: "nova", name: "NOVA", classTitle: "FLAGGSCHIFF", blurb: "Das Beste, was die Werft hergibt.",
                  grade: .superior, hull: .nova, weapon: .rocket, speed: 1.45, energy: 160, armor: 0.5, drain: 0.75)
    ]

    static func with(id: String) -> ShipModel? { all.first { $0.id == id } }
}

// MARK: - Schiff mit Upgrade-Stufe

struct Ship {
    /// Zehn Ausbaustufen; jede kostet 25 % mehr als die vorige (Christian, 2026-10-04)
    static let maxLevel = 10

    let model: ShipModel
    let level: Int

    var hull: HullClass { model.hull }
    var weapon: WeaponKind { model.weapon }
    var name: String { model.name }

    private var l: CGFloat { CGFloat(level) }

    var speed: CGFloat { model.speed * (1 + 0.04 * l) }
    var maxEnergy: CGFloat { (model.energy * (1 + 0.08 * l)).rounded() }
    var armor: CGFloat { min(0.85, model.armor + 0.04 * l) }
    var drain: CGFloat { model.drain * (1 - 0.03 * l) }
    var weaponCostFactor: CGFloat { max(0.35, 1 - 0.07 * l) }

    /// Tech-Teile für die nächste Stufe: Grundpreis je Klasse, jede Stufe 25 % teurer als die vorige,
    /// auf 5 gerundet (Stufe 10 kostet gut das Siebenfache der ersten)
    var upgradeCost: Int {
        let raw = CGFloat(model.grade.upgradeBase) * pow(1.25, l)
        return Int((raw / 5).rounded()) * 5
    }

    static let starter = Ship(model: ShipModel.all[0], level: 0)
}

// MARK: - Spielerprofil

@Observable
final class Profile {
    var parts: Int
    var shipParts: Int
    var owned: Set<String>
    var levels: [String: Int]
    var selectedID: String
    /// Anzahl erreichter Raumstationen; an jeder davon kann ein neuer Flug starten
    var stationsReached: Int
    /// gewählter Startpunkt: -1 = Hangar, sonst die Nummer einer erreichten Station
    var startStation: Int

    private let defaults = UserDefaults.standard

    init() {
        parts = defaults.integer(forKey: "orbitHopParts")
        shipParts = defaults.integer(forKey: "orbitHopShipParts")
        owned = Set(defaults.stringArray(forKey: "orbitHopFleet") ?? [])
        levels = (defaults.dictionary(forKey: "orbitHopLevels") as? [String: Int]) ?? [:]
        selectedID = defaults.string(forKey: "orbitHopSelected") ?? Ship.starter.model.id
        stationsReached = defaults.integer(forKey: "orbitHopStations")
        startStation = (defaults.object(forKey: "orbitHopStartStation") as? Int) ?? -1
        owned.insert(Ship.starter.model.id)
        if !owned.contains(selectedID) { selectedID = Ship.starter.model.id }
    }

    func ship(_ m: ShipModel) -> Ship { Ship(model: m, level: levels[m.id] ?? 0) }

    var selected: Ship { ship(ShipModel.with(id: selectedID) ?? Ship.starter.model) }

    func isOwned(_ m: ShipModel) -> Bool { owned.contains(m.id) }

    func unlock(_ m: ShipModel) {
        guard !isOwned(m), shipParts >= m.grade.cost else { return }
        shipParts -= m.grade.cost
        owned.insert(m.id)
        selectedID = m.id
        save()
    }

    func canUpgrade(_ m: ShipModel) -> Bool {
        let s = ship(m)
        return isOwned(m) && s.level < Ship.maxLevel && parts >= s.upgradeCost
    }

    func upgrade(_ m: ShipModel) {
        guard canUpgrade(m) else { return }
        let s = ship(m)
        parts -= s.upgradeCost
        levels[m.id] = s.level + 1
        save()
    }

    func select(_ m: ShipModel) {
        guard isOwned(m) else { return }
        selectedID = m.id
        save()
    }

    func reachStation(_ k: Int) {
        guard k >= 0, k + 1 > stationsReached else { return }
        stationsReached = k + 1
        save()
    }

    func setStartStation(_ k: Int) {
        startStation = min(max(-1, k), stationsReached - 1)
        save()
    }

    /// zieht Tech-Teile ab, wenn genug da sind
    func spendParts(_ n: Int) -> Bool {
        guard parts >= n else { return false }
        parts -= n
        save()
        return true
    }

    func addParts(_ n: Int) {
        parts += n
        save()
    }

    func addShipParts(_ n: Int) {
        shipParts += n
        save()
    }

    func save() {
        defaults.set(parts, forKey: "orbitHopParts")
        defaults.set(shipParts, forKey: "orbitHopShipParts")
        defaults.set(Array(owned), forKey: "orbitHopFleet")
        defaults.set(levels, forKey: "orbitHopLevels")
        defaults.set(selectedID, forKey: "orbitHopSelected")
        defaults.set(stationsReached, forKey: "orbitHopStations")
        defaults.set(startStation, forKey: "orbitHopStartStation")
    }
}

// MARK: - 2D-Schiffsgrafik (im Spiel)

enum ShipArt {
    /// Zeichnet das Schiff mit der Nase nach +x. `u` ist die Grundeinheit (Schiff ca. 6u lang).
    static func draw(_ c: GraphicsContext, ship: Ship, u: CGFloat, time: CGFloat, thrust: CGFloat) {
        let hull = ship.hull
        let (h, s, l) = hull.paint
        let accent = hsl(ship.weapon.hue, 0.85, 0.62)
        let signal = Color(red: 79 / 255, green: 227 / 255, blue: 193 / 255)

        var add = c
        add.blendMode = .plusLighter
        drawFlame(c, ship: ship, u: u, time: time, thrust: thrust)

        // Anbauten hinter dem Rumpf
        switch hull {
        case .hauler:
            for side in [-1, 1] as [CGFloat] {
                let pod = Path(roundedRect: CGRect(x: -1.9 * u, y: (side > 0 ? 1.45 : -2.35) * u, width: 2.9 * u, height: 0.9 * u),
                               cornerRadius: 0.35 * u)
                c.fill(pod, with: .color(hsl(h, s, l - 0.12)))
                c.stroke(pod, with: .color(hsl(h, s, l + 0.15)), lineWidth: 0.1 * u)
            }
        case .cruiser:
            for side in [-1, 1] as [CGFloat] {
                var strut = Path()
                strut.move(to: CGPoint(x: -0.8 * u, y: side * 0.6 * u))
                strut.addLine(to: CGPoint(x: -1.4 * u, y: side * 1.7 * u))
                c.stroke(strut, with: .color(hsl(h, s, l - 0.1)), lineWidth: 0.35 * u)
                let nac = Path(roundedRect: CGRect(x: -2.6 * u, y: (side > 0 ? 1.5 : -2.1) * u, width: 3.2 * u, height: 0.6 * u),
                               cornerRadius: 0.3 * u)
                c.fill(nac, with: .color(hsl(h, s, l - 0.05)))
                add.fill(Path(CGRect(x: -2.6 * u, y: (side > 0 ? 1.62 : -1.98) * u, width: 0.35 * u, height: 0.36 * u)),
                         with: .color(accent.opacity(0.9)))
            }
        default:
            break
        }

        // Rumpf
        let body = hullPath(hull, u)
        c.fill(body, with: .linearGradient(Gradient(colors: [hsl(h, s, min(0.97, l + 0.12)), hsl(h, s, l - 0.2)]),
                                           startPoint: CGPoint(x: 0, y: -2 * u), endPoint: CGPoint(x: 0, y: 2 * u)))

        var inner = c
        inner.clip(to: body)
        inner.fill(Path(CGRect(x: -1.0 * u, y: -3 * u, width: 0.35 * u, height: 6 * u)), with: .color(accent.opacity(0.9)))
        if hull == .tank || hull == .battleship {
            var plates = Path()
            for x in stride(from: -2.0, through: 1.6, by: 0.9) {
                plates.move(to: CGPoint(x: CGFloat(x) * u, y: -2.6 * u))
                plates.addLine(to: CGPoint(x: CGFloat(x) * u + 0.4 * u, y: 2.6 * u))
            }
            inner.stroke(plates, with: .color(Color.black.opacity(0.25)), lineWidth: 0.08 * u)
        }
        inner.fill(Path(CGRect(x: -4 * u, y: 0.3 * u, width: 8 * u, height: 3 * u)), with: .color(Color.black.opacity(0.12)))

        let glowEdge = hull == .phantom || hull == .nova
        c.stroke(body, with: .color(glowEdge ? accent : Color.white.opacity(0.6)), lineWidth: (glowEdge ? 0.14 : 0.09) * u)

        // Waffe
        switch ship.weapon {
        case .cannon:
            var barrels = Path()
            for side in [-1, 1] as [CGFloat] {
                barrels.move(to: CGPoint(x: 0.8 * u, y: side * 0.55 * u))
                barrels.addLine(to: CGPoint(x: 2.9 * u, y: side * 0.55 * u))
            }
            c.stroke(barrels, with: .color(Color(red: 0.4, green: 0.43, blue: 0.5)), lineWidth: 0.28 * u)
            c.stroke(barrels, with: .color(accent.opacity(0.8)), lineWidth: 0.1 * u)
        case .rocket:
            for side in [-1, 1] as [CGFloat] {
                let pod = Path(roundedRect: CGRect(x: -0.8 * u, y: side * 1.25 * u - 0.25 * u, width: 1.8 * u, height: 0.5 * u),
                               cornerRadius: 0.25 * u)
                c.fill(pod, with: .color(Color(red: 0.85, green: 0.87, blue: 0.92)))
                c.fill(circlePath(CGPoint(x: 1.0 * u, y: side * 1.25 * u), 0.25 * u), with: .color(accent))
            }
        case .railgun:
            var rail = Path()
            for side in [-1, 1] as [CGFloat] {
                rail.move(to: CGPoint(x: -1.4 * u, y: side * 0.2 * u))
                rail.addLine(to: CGPoint(x: 4.1 * u, y: side * 0.2 * u))
            }
            add.stroke(rail, with: .color(accent.opacity(0.4)), lineWidth: 0.35 * u)
            c.stroke(rail, with: .color(accent), lineWidth: 0.12 * u)
        case .bomb:
            let bc = CGPoint(x: -0.5 * u, y: 0)
            c.fill(circlePath(bc, 0.6 * u), with: .color(Color(red: 0.22, green: 0.22, blue: 0.28)))
            c.stroke(circlePath(bc, 0.6 * u), with: .color(accent), lineWidth: 0.14 * u)
            add.fill(circlePath(bc, 0.2 * u), with: .color(accent.opacity(0.6 + 0.4 * Double(sin(time * 6)))))
        }

        // Cockpit
        let cockpit = Path(ellipseIn: CGRect(x: 0.3 * u, y: -0.38 * u, width: 1.3 * u, height: 0.76 * u))
        c.fill(cockpit, with: .linearGradient(Gradient(colors: [glowEdge ? accent : signal, Color(red: 0.05, green: 0.2, blue: 0.25)]),
                                              startPoint: CGPoint(x: 1.2 * u, y: -0.4 * u), endPoint: CGPoint(x: 0.4 * u, y: 0.4 * u)))
        c.fill(Path(ellipseIn: CGRect(x: 0.9 * u, y: -0.25 * u, width: 0.4 * u, height: 0.2 * u)), with: .color(Color.white.opacity(0.7)))

        // Upgrade-Marken
        for k in 0..<ship.level {
            c.fill(Path(CGRect(x: (-1.9 + CGFloat(k) * 0.17) * u, y: -0.1 * u, width: 0.11 * u, height: 0.2 * u)),
                   with: .color(Color(red: 1, green: 0.85, blue: 0.42)))
        }
    }

    /// Animierte Triebwerksflamme am Heck
    static func drawFlame(_ c: GraphicsContext, ship: Ship, u: CGFloat, time: CGFloat, thrust: CGFloat) {
        var add = c
        add.blendMode = .plusLighter
        let hull = ship.hull
        let tail = hull.tailX * u
        let flame = (1 + 0.35 * sin(time * 55)) * u * (1.2 + 2.6 * thrust)
        var fl = Path()
        fl.move(to: CGPoint(x: tail, y: -0.6 * u))
        fl.addLine(to: CGPoint(x: tail - flame, y: 0))
        fl.addLine(to: CGPoint(x: tail, y: 0.6 * u))
        fl.closeSubpath()
        add.fill(fl, with: .linearGradient(Gradient(stops: [
            .init(color: Color(red: 1, green: 0.92, blue: 0.7).opacity(0.95), location: 0),
            .init(color: hsl(ship.weapon.hue, 0.9, 0.55, 0.7), location: 0.45),
            .init(color: hsl(ship.weapon.hue, 0.9, 0.5, 0), location: 1)
        ]), startPoint: CGPoint(x: tail, y: 0), endPoint: CGPoint(x: tail - flame, y: 0)))
    }

    static func hullPath(_ hull: HullClass, _ u: CGFloat) -> Path {
        let pts = hull.outline.map { CGPoint(x: $0.0 * u, y: $0.1 * u) }
        var p = Path()
        p.move(to: pts[0])
        for pt in pts.dropFirst() { p.addLine(to: pt) }
        for pt in pts.dropFirst().dropLast().reversed() { p.addLine(to: CGPoint(x: pt.x, y: -pt.y)) }
        p.closeSubpath()
        return p
    }
}

// MARK: - Hangar „SCHIFFE“

struct ShipShopView: View {
    let profile: Profile
    let onClose: () -> Void

    @State private var page = 0
    @State private var buyFor: ShipModel?

    private let signal = Color(red: 79 / 255, green: 227 / 255, blue: 193 / 255)
    private let gold = Color(red: 1, green: 0.85, blue: 0.42)
    private let dim = Color(red: 0.55, green: 0.6, blue: 0.72)
    private let shipPartColor = hsl(ItemKind.shipPart.hue, 0.8, 0.68)
    private let panel = Color(red: 0.02, green: 0.07, blue: 0.11)

    private func label(_ text: String) -> Text {
        Text(text)
            .font(.system(size: 9, weight: .medium, design: .monospaced))
            .tracking(1.4)
    }

    var body: some View {
        VStack(spacing: 6) {
            header
            TabView(selection: $page) {
                ForEach(Array(ShipModel.all.enumerated()), id: \.offset) { i, m in
                    shipPage(m, visible: i == page).tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            pager
        }
        .padding(.top, 8)
        .padding(.bottom, 8)
        .background(
            LinearGradient(colors: [Color(red: 0.03, green: 0.045, blue: 0.1), Color(red: 0.01, green: 0.015, blue: 0.04)],
                           startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
        )
        .onAppear { page = ShipModel.all.firstIndex { $0.id == profile.selectedID } ?? 0 }
        .statusBarHidden(true)
        .sheet(item: $buyFor) { m in
            ShipPartStoreView(profile: profile, model: m) { buyFor = nil }
                .presentationDetents([.medium])
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                label("HANGAR // FLOTTE").foregroundStyle(signal.opacity(0.8))
                Text("SCHIFFE")
                    .font(.system(size: 28, weight: .heavy, design: .monospaced))
                    .tracking(3)
                    .foregroundStyle(.white)
                    .shadow(color: signal.opacity(0.6), radius: 10)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                label("SCHIFFSTEILE").foregroundStyle(dim)
                HStack(spacing: 5) {
                    Image(systemName: "puzzlepiece.fill").font(.system(size: 14))
                    Text("\(profile.shipParts)")
                        .font(.system(size: 20, weight: .bold, design: .monospaced))
                }
                .foregroundStyle(shipPartColor)
            }
            VStack(alignment: .trailing, spacing: 2) {
                label("TECH-TEILE").foregroundStyle(dim)
                HStack(spacing: 5) {
                    Image(systemName: "gearshape.fill").font(.system(size: 14))
                    Text("\(profile.parts)")
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

    private var pager: some View {
        HStack(spacing: 14) {
            Button { withAnimation { page = max(0, page - 1) } } label: {
                Image(systemName: "chevron.left").font(.system(size: 16, weight: .bold)).frame(width: 36, height: 30)
            }
            .buttonStyle(.plain)
            .opacity(page > 0 ? 1 : 0.25)
            HStack(spacing: 6) {
                ForEach(Array(ShipModel.all.enumerated()), id: \.offset) { i, m in
                    Rectangle()
                        .fill(i == page ? m.grade.color : dim.opacity(0.35))
                        .frame(width: i == page ? 18 : 7, height: 3)
                }
            }
            Button { withAnimation { page = min(ShipModel.all.count - 1, page + 1) } } label: {
                Image(systemName: "chevron.right").font(.system(size: 16, weight: .bold)).frame(width: 36, height: 30)
            }
            .buttonStyle(.plain)
            .opacity(page < ShipModel.all.count - 1 ? 1 : 0.25)
        }
        .foregroundStyle(signal)
    }

    private func statRow(_ name: String, _ value: String, _ fraction: CGFloat, _ color: Color) -> some View {
        HStack(spacing: 8) {
            label(name).foregroundStyle(dim).lineLimit(1).fixedSize().frame(width: 66, alignment: .leading)
            HStack(spacing: 2) {
                ForEach(0..<14, id: \.self) { i in
                    Slant().fill(CGFloat(i) < fraction * 14 ? color : Color.white.opacity(0.08))
                }
            }
            .frame(height: 9)
            .shadow(color: color.opacity(0.4), radius: 4)
            Text(value)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white)
                .frame(width: 48, alignment: .trailing)
        }
    }

    private func norm(_ v: CGFloat, _ lo: CGFloat, _ hi: CGFloat) -> CGFloat { max(0.05, min(1, (v - lo) / (hi - lo))) }

    private func shipPage(_ m: ShipModel, visible: Bool) -> some View {
        let ship = profile.ship(m)
        let owned = profile.isOwned(m)
        let active = profile.selectedID == m.id
        let accent = hsl(m.weapon.hue, 0.85, 0.65)

        return VStack(spacing: 10) {
            VStack(spacing: 4) {
                label("\(m.grade.title) · \(m.classTitle)")
                    .foregroundStyle(m.grade.color)
                Text(m.name)
                    .font(.system(size: 34, weight: .heavy, design: .monospaced))
                    .tracking(5)
                    .foregroundStyle(.white)
                    .shadow(color: m.grade.color.opacity(0.6), radius: 12)
                Text(m.blurb)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(dim)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 20)

            ZStack {
                ShipModelView(model: m, active: visible)
                    .opacity(owned ? 1 : 0.55)
                    .saturation(owned ? 1 : 0.3)
                if !owned {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(dim)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .padding(18)
                }
            }
            .frame(maxHeight: .infinity)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: m.weapon.symbol).font(.system(size: 11, weight: .bold))
                    label("WAFFE · \(m.weapon.title)")
                    Spacer()
                    label("\(Int((m.weapon.cost * ship.weaponCostFactor).rounded())) E / SCHUSS").foregroundStyle(dim)
                }
                .foregroundStyle(accent)
                Rectangle().fill(signal.opacity(0.25)).frame(height: 1)
                statRow("TEMPO", String(format: "%.2f", ship.speed), norm(ship.speed, 0.7, 1.8), signal)
                statRow("ENERGIE", "\(Int(ship.maxEnergy))", norm(ship.maxEnergy, 60, 260), Color(red: 0.4, green: 0.9, blue: 0.5))
                statRow("PANZER", "\(Int(ship.armor * 100)) %", norm(ship.armor, 0, 0.85), Color(red: 1, green: 0.65, blue: 0.4))
                statRow("VERBRAUCH", "\(Int(ship.drain * 100)) %", norm(1.15 - ship.drain, 0.05, 0.65), Color(red: 0.6, green: 0.7, blue: 1))
                if owned { upgradeRow(m, ship) }
            }
            .padding(14)
            .background(Chamfer(cut: 12).fill(panel.opacity(0.85)))
            .overlay(Chamfer(cut: 12).stroke((active ? signal : m.grade.color).opacity(0.5), lineWidth: 1))
            .padding(.horizontal, 16)

            actionButton(m, owned: owned, active: active)
                .padding(.horizontal, 16)
        }
        .padding(.bottom, 4)
    }

    private func upgradeRow(_ m: ShipModel, _ ship: Ship) -> some View {
        HStack(spacing: 8) {
            label("UPGRADE").foregroundStyle(dim).frame(width: 66, alignment: .leading)
            HStack(spacing: 3) {
                ForEach(0..<Ship.maxLevel, id: \.self) { i in
                    Rectangle()
                        .fill(i < ship.level ? gold : Color.white.opacity(0.1))
                        .frame(width: 8, height: 8)
                }
            }
            Spacer()
            if ship.level < Ship.maxLevel {
                let can = profile.canUpgrade(m)
                Button { profile.upgrade(m) } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up").font(.system(size: 9, weight: .bold))
                        Image(systemName: "gearshape.fill").font(.system(size: 9))
                        Text("\(ship.upgradeCost)").font(.system(size: 11, weight: .bold, design: .monospaced))
                    }
                    .foregroundStyle(can ? gold : dim)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Chamfer(cut: 5).fill((can ? gold : dim).opacity(0.12)))
                    .overlay(Chamfer(cut: 5).stroke((can ? gold : dim).opacity(0.7), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .disabled(!can)
            } else {
                label("MAXIMUM").foregroundStyle(gold)
            }
        }
        .padding(.top, 2)
    }

    @ViewBuilder
    private func actionButton(_ m: ShipModel, owned: Bool, active: Bool) -> some View {
        if active {
            buttonLabel("AUSGEWÄHLT", signal, filled: true)
        } else if owned {
            // Wählen schließt die Schiffsauswahl und führt zurück in den Hangar
            Button { profile.select(m); onClose() } label: { buttonLabel("WÄHLEN", signal, filled: false) }
                .buttonStyle(.plain)
        } else {
            // zu wenig Schiffsteile: der Knopf führt zum Kauf
            let can = profile.shipParts >= m.grade.cost
            Button { if can { profile.unlock(m) } else { buyFor = m } } label: {
                buttonLabel(can ? "FREISCHALTEN · \(m.grade.cost) SCHIFFSTEILE" : "\(m.grade.cost - profile.shipParts) FEHLEN · KAUFEN",
                            shipPartColor.opacity(can ? 1 : 0.7), filled: false)
            }
            .buttonStyle(.plain)
        }
    }

    private func buttonLabel(_ text: String, _ color: Color, filled: Bool) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .bold, design: .monospaced))
            .tracking(2)
            .foregroundStyle(filled ? Color.black : color)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Chamfer(cut: 8).fill(filled ? color : color.opacity(0.1)))
            .overlay(Chamfer(cut: 8).stroke(color.opacity(0.8), lineWidth: 1.2))
    }
}
