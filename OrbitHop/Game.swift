import SwiftUI
import QuartzCore
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Haptik

/// Bildraten-Messung für Tests auf dem Gerät (Startargument `-bot` oder `-perf`): schreibt alle 5 s eine Zeile
/// `OHPERF` mit Simulationsschritten, SwiftUI- und SceneKit-Bildern pro Sekunde, langsamen Schritten (gesamt und
/// im Orbit), Hängern des SceneKit-Renderers und Hauptthread-Zeit je Schritt.
enum PerfLog {
    static let enabled = Game.bot || ProcessInfo.processInfo.arguments.contains("-perf")
    /// nur für Messungen: Canvas-Overlay (`-noCanvas`) oder HUD und Menüs (`-noHUD`) weglassen
    static let noCanvas = ProcessInfo.processInfo.arguments.contains("-noCanvas")
    static let noHUD = ProcessInfo.processInfo.arguments.contains("-noHUD")
    /// vom SceneKit-Renderthread geschrieben (nur grobe Zählung für das Log)
    static var sceneFrames = 0
    private static var sceneLast: Double = 0
    private static var sceneSlow = 0
    private static var sceneWorst: Double = 0
    /// SwiftUI-Auswertungen der Oberfläche
    static var uiFrames = 0
    private static var frames = 0
    private static var slow = 0
    private static var orbitSlow = 0
    private static var worst: Double = 0
    private static var mainSum: Double = 0
    private static var mainMax: Double = 0
    private static var last: Double = 0
    private static var windowStart: Double = 0
    private static var lastScene = 0

    /// vom SceneKit-Renderthread nach jedem gezeichneten Bild
    static func sceneFrame() {
        let now = CACurrentMediaTime()
        if sceneLast > 0 {
            let dt = now - sceneLast
            if dt > 1.0 / 45 { sceneSlow += 1 }
            sceneWorst = max(sceneWorst, dt)
        }
        sceneLast = now
        sceneFrames += 1
    }

    /// einmal pro Simulationsschritt aufrufen; `main` = Dauer von Simulation und Szenenabgleich
    static func frame(main: Double, orbiting: Bool) {
        guard enabled else { return }
        let now = CACurrentMediaTime()
        if last > 0 {
            let dt = now - last
            if dt > 1.0 / 45 {
                slow += 1
                if orbiting { orbitSlow += 1 }
            }
            worst = max(worst, dt)
        } else {
            windowStart = now
        }
        last = now
        frames += 1
        mainSum += main
        mainMax = max(mainMax, main)
        let span = now - windowStart
        guard span >= 5 else { return }
        let scene = sceneFrames - lastScene
        lastScene = sceneFrames
        print(String(format: "OHPERF sim=%.0ffps ui=%.0ffps scene=%.0ffps slow=%d orbitSlow=%d worst=%.0fms "
                     + "sceneSlow=%d sceneWorst=%.0fms main=%.1f/%.1fms mem=%dMB thermal=%d",
                     Double(frames) / span, Double(uiFrames) / span, Double(scene) / span, slow, orbitSlow, worst * 1000,
                     sceneSlow, sceneWorst * 1000,
                     mainSum / Double(max(1, frames)) * 1000, mainMax * 1000, Game.memoryMB(),
                     ProcessInfo.processInfo.thermalState.rawValue))
        frames = 0; slow = 0; orbitSlow = 0; worst = 0; mainSum = 0; mainMax = 0; uiFrames = 0
        sceneSlow = 0; sceneWorst = 0
        windowStart = now
    }
}

enum Haptics {
    static func launch(_ accuracy: CGFloat) {
        #if canImport(UIKit)
        let generator = UIImpactFeedbackGenerator(style: accuracy > 0.85 ? .heavy : .medium)
        generator.impactOccurred(intensity: 0.4 + 0.6 * accuracy)
        #endif
    }

    static func capture() {
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        #endif
    }

    static func miss() {
        #if canImport(UIKit)
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
        #endif
    }

    static func bonus() {
        #if canImport(UIKit)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
    }

    static func gameOver() {
        #if canImport(UIKit)
        UINotificationFeedbackGenerator().notificationOccurred(.error)
        #endif
    }
}

// MARK: - Farben

/// HSL (Grad, 0...1, 0...1) als SwiftUI-Farbe.
func hsl(_ h: Double, _ s: Double, _ l: Double, _ a: Double = 1) -> Color {
    let hue = (h.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360) / 360
    let v = l + s * min(l, 1 - l)
    let sat = v == 0 ? 0 : 2 * (1 - l / v)
    return Color(hue: hue, saturation: sat, brightness: v, opacity: a)
}

// MARK: - Modelle

/// Sonderplaneten mit eigener Spielmechanik
enum PlanetKind {
    case normal
    /// Starke Schwerkraft, schnelle Bahn und Schleuderstart. Die Bahn zerfällt, am Ereignishorizont leidet die Panzerung.
    case blackHole
    /// Zwei Sonnen umkreisen sich. Ihr Licht lädt Energie auf, ihre Schwerkraft lässt die Bahn pendeln.
    case binary
}

struct Planet {
    struct Band {
        let alpha: CGFloat
        let dark: Bool
    }

    struct Crater {
        let angle: CGFloat
        let dist: CGFloat
        let size: CGFloat
    }

    let center: CGPoint
    let radius: CGFloat
    let spin: CGFloat          // Umlauftempo des Satelliten in rad/s (Planeten selbst drehen sich nicht)
    let hue: Double
    let hasRing: Bool
    let tilt: CGFloat
    let bands: [Band]
    let craters: [Crater]
    let hue2: Double           // Zweitfarbe der hellen Streifen
    let hasStorm: Bool
    let hasMoon: Bool
    let moonPhase: CGFloat
    let energyScale: CGFloat   // spätere Planeten geben weniger Energie
    let bonus: ItemKind?       // Planetentyp bestimmt das Bonus-Item
    var hardRoute = false      // auf dem Weg hierher liegen Hindernisse
    var isStation = false      // Raumstation: Reparatur, Werft und Upgrades
    var stationNo = -1         // laufende Nummer der Station (Name und Modell), sonst -1
    var kind: PlanetKind = .normal

    /// Schwarze Löcher ziehen viel stärker, als ihre Größe vermuten lässt
    var mass: CGFloat { radius * radius * (kind == .blackHole ? 3.2 : 1) }
    /// Beim Schwarzen Loch liegt die Bahn außerhalb der Akkretionsscheibe
    var orbitRadius: CGFloat { radius + (kind == .blackHole ? 150 : 90) }
    /// Sichtbare Ausdehnung (Akkretionsscheibe zählt mit), für Zielerfassung und Ladering
    var outerRadius: CGFloat { kind == .blackHole ? radius * 2.1 : radius }
    /// Ab diesem Abstand beginnt die Zone, in der das Schwarze Loch die Panzerung zerreißt
    var horizonDanger: CGFloat { radius + 70 }
    /// Doppelstern: Winkel der Verbindungslinie beider Sonnen (sie umkreisen sich gleichmäßig)
    func binaryAngle(at time: CGFloat) -> CGFloat { moonPhase + time * 0.55 }
    /// Kleine, schnell umkreiste Planeten geben mehr Energie ab.
    var energyGain: CGFloat { (20 + 15 * spin) * energyScale }

    static func make(center: CGPoint, radius: CGFloat, spin: CGFloat, hue: Double, allowRing: Bool,
                     energyScale: CGFloat = 1, bonus: ItemKind? = nil) -> Planet {
        let bandCount = 5 + Int(radius / 14)
        let bands = (0..<bandCount).map { _ in
            Band(alpha: CGFloat.random(in: 0.2...1, using: &Dice.rng), dark: Bool.random(using: &Dice.rng))
        }
        let craters = (0..<4).map { _ in
            Crater(angle: CGFloat.random(in: 0...(CGFloat.pi * 2), using: &Dice.rng),
                   dist: CGFloat.random(in: 0.15...0.75, using: &Dice.rng),
                   size: CGFloat.random(in: 0.06...0.16, using: &Dice.rng))
        }
        return Planet(center: center, radius: radius, spin: spin, hue: hue,
                      hasRing: allowRing && Double.random(in: 0...1, using: &Dice.rng) < 0.35,
                      tilt: CGFloat.random(in: -0.45...0.45, using: &Dice.rng),
                      bands: bands, craters: craters,
                      hue2: hue + Double.random(in: -50...50, using: &Dice.rng),
                      hasStorm: radius > 70 && Bool.random(using: &Dice.rng),
                      hasMoon: Double.random(in: 0...1, using: &Dice.rng) < 0.45,
                      moonPhase: CGFloat.random(in: 0...(CGFloat.pi * 2), using: &Dice.rng),
                      energyScale: energyScale,
                      bonus: bonus)
    }
}

struct Star {
    let x: CGFloat
    let y: CGFloat
    let depth: CGFloat
    let alpha: CGFloat
    let phase: CGFloat
}

struct Nebula {
    let x: CGFloat
    let y: CGFloat
    let r: CGFloat
    let hue: Double
    let depth: CGFloat
}

struct Particle {
    var x: CGFloat
    var y: CGFloat
    var vx: CGFloat
    var vy: CGFloat
    var life: CGFloat
    let maxLife: CGFloat
    let size: CGFloat
    let hue: Double
}

struct Popup {
    let pos: CGPoint
    let text: String
    let color: Color
    var age: CGFloat

    /// So lange bleibt der Text voll sichtbar, danach blendet er über `fade` aus.
    static let hold: CGFloat = 1.4
    static let fade: CGFloat = 0.8
    static var lifetime: CGFloat { hold + fade }
}

struct Wave {
    let uid = UID.next()
    let center: CGPoint
    let r0: CGFloat
    var age: CGFloat
    let maxAge: CGFloat
    let hue: Double
}

// MARK: - IDs für die 3D-Welt

enum UID {
    private static var counter = 0
    static func next() -> Int {
        counter += 1
        return counter
    }
}

/// Partikelausbruch, wird von der 3D-Welt abgeholt.
struct Burst {
    let pos: CGPoint
    let count: Int
    let hue: Double
    let speed: CGFloat
    let life: CGFloat
}

// MARK: - Bonus-Items

enum ItemKind: CaseIterable {
    case energy, wideCone, superBomb, rescue, tech, shipPart

    var hue: Double {
        switch self {
        case .energy: return 140
        case .wideCone: return 190
        case .superBomb: return 275
        case .rescue: return 22
        case .tech: return 48
        case .shipPart: return 330
        }
    }

    var title: String {
        switch self {
        case .energy: return "+35 ENERGIE"
        case .wideCone: return "KEGEL+"
        case .superBomb: return "SUPERBOMBE"
        case .rescue: return "NACHBRENNER"
        case .tech: return "+1 TECH-TEIL"
        case .shipPart: return "+1 SCHIFFSTEIL"
        }
    }

    /// Farbe der Planeten dieses Typs.
    var planetHue: Double {
        switch self {
        case .energy: return Double.random(in: 95...150)
        case .wideCone: return Double.random(in: 180...215)
        case .superBomb: return Double.random(in: 255...295)
        case .rescue: return Double.random(in: 5...30)
        case .tech: return 48
        case .shipPart: return 330
        }
    }

    /// Gewichtete Zufallsauswahl, der Nachbrenner ist selten.
    static func random() -> ItemKind {
        let r = Double.random(in: 0...1, using: &Dice.rng)
        if r < 0.42 { return .energy }
        if r < 0.64 { return .wideCone }
        if r < 0.86 { return .superBomb }
        return .rescue
    }
}

struct Item {
    let uid = UID.next()
    let kind: ItemKind
    let from: CGPoint          // Austrittspunkt am Planeten
    var p: CGPoint             // aktuelle Position, fliegt direkt in den Satelliten
    let gap: Int               // gehört zu Planet mit diesem Index
    let phase: CGFloat
    var age: CGFloat = 0

    static let flyTime: CGFloat = 0.7
}

// MARK: - Hindernisse und Nebel

enum ObstacleKind {
    case rock, debris, wreck, comet
    /// Jägerdrohne: lauert auf der Strecke, verfolgt das fliegende Schiff und schießt
    case drone

    var title: String {
        switch self {
        case .rock: return "ASTEROID"
        case .debris: return "TRÜMMER"
        case .wreck: return "WRACK"
        case .comet: return "KOMET"
        case .drone: return "DROHNE"
        }
    }
}

struct Asteroid {
    let uid = UID.next()
    var center: CGPoint
    let radius: CGFloat
    let shape: [CGFloat]       // Radius-Faktoren der Eckpunkte
    let spin: CGFloat
    let phase: CGFloat
    let tone: Double           // Helligkeit des Gesteins
    let gap: Int
    var kind: ObstacleKind = .rock
    var hp = 1
    var maxHP = 1
    var vel = CGVector.zero    // Kometen und Wracks bewegen sich
    var end: CGPoint? = nil    // hier verglüht der Komet
    var variant = 0
    var bumpUntil: CGFloat = 0 // nach einer Kollision kurz keine weitere
    var fireAt: CGFloat = 0    // Drohne: nächster Schuss frühestens dann
}

/// Plasmaschuss einer Drohne
struct EnemyShot {
    let uid = UID.next()
    var p: CGPoint
    let v: CGVector
    var age: CGFloat = 0
    static let maxAge: CGFloat = 2.6
    static let speed: CGFloat = 430
}

struct GasCloud {
    let uid = UID.next()
    struct Blob {
        let off: CGPoint
        let r: CGFloat
        let hue: Double
        let speed: CGFloat
    }

    let center: CGPoint
    let radius: CGFloat
    let blobs: [Blob]
    let sparkles: [CGPoint]
    let gap: Int
}

// MARK: - Waffen

enum WeaponKind: CaseIterable {
    case cannon, rocket, railgun, bomb

    var cost: CGFloat {
        switch self {
        case .cannon: return 2
        case .rocket: return 6
        case .railgun: return 10
        case .bomb: return 14
        }
    }

    var cooldown: CGFloat {
        switch self {
        case .cannon: return 0.12
        case .rocket: return 0.35
        case .railgun: return 0.6
        case .bomb: return 0.9
        }
    }

    var title: String {
        switch self {
        case .cannon: return "KANONE"
        case .rocket: return "RAKETE"
        case .railgun: return "RAILGUN"
        case .bomb: return "BOMBE"
        }
    }

    var symbol: String {
        switch self {
        case .cannon: return "scope"
        case .rocket: return "paperplane.fill"
        case .railgun: return "bolt.horizontal.fill"
        case .bomb: return "burst.fill"
        }
    }

    var hue: Double {
        switch self {
        case .cannon: return 50
        case .rocket: return 12
        case .railgun: return 190
        case .bomb: return 320
        }
    }
}

struct Projectile {
    let uid = UID.next()
    let kind: WeaponKind
    var p: CGPoint
    var v: CGVector
    var age: CGFloat = 0
    let maxAge: CGFloat
    var target: Int? = nil     // uid des anvisierten Hindernisses
}

struct Beam {
    let uid = UID.next()
    let from: CGPoint
    let to: CGPoint
    var age: CGFloat = 0
}

// MARK: - Spiel

final class Game {
    enum Phase { case docked, orbiting, flying, over }

    // MARK: Tuning
    let gravityConstant: CGFloat = 230    // ausgeglichen für die großen Planeten
    let minSpeed: CGFloat = 150
    let maxSpeed: CGFloat = 520
    let spinBonus: CGFloat = 0.4          // Extra-Tempo durch das Umlauftempo
    let homingRate: CGFloat = 2.4         // Lenkhilfe zum Ziel, rad/s
    let minFlightSpeed: CGFloat = 170     // Tempo sinkt im Flug nie darunter
    // Schiff und Profil
    let profile = Profile()
    var ship: Ship = .starter
    var maxEnergy: CGFloat { ship.maxEnergy }
    var weapon: WeaponKind { ship.weapon }
    var weaponCost: CGFloat { (weapon.cost * ship.weaponCostFactor).rounded() }
    var runParts = 0                      // in diesem Flug gesammelte Tech-Teile
    var runShipParts = 0                  // in diesem Flug gefundene Schiffsteile

    /// Schwierigkeit 0...1, erreicht nach 40 Planeten das Maximum.
    var level: CGFloat { min(1, CGFloat(score) / 40) }
    /// Kegel wird enger: ca. 20° bis 11°
    var coneHalfAngle: CGFloat { 0.34 - 0.15 * level + (wideConeLaunches > 0 ? 0.2 : 0) }
    let chargeNeeded: CGFloat = 2 * CGFloat.pi   // eine ganze Umrundung
    /// Energieverbrauch pro Sekunde steigt
    var energyDrain: CGFloat { (5 + 4 * level) * ship.drain }
    let captureMargin: CGFloat = 120

    static let stars: [Star] = (0..<170).map { _ in
        Star(x: CGFloat.random(in: 0...1),
             y: CGFloat.random(in: 0...1),
             depth: CGFloat.random(in: 0.02...0.14),
             alpha: CGFloat.random(in: 0.25...0.9),
             phase: CGFloat.random(in: 0...(CGFloat.pi * 2)))
    }

    static let nebulae: [Nebula] = (0..<6).map { _ in
        Nebula(x: CGFloat.random(in: 0...1),
               y: CGFloat.random(in: 0...1),
               r: CGFloat.random(in: 0.35...0.75),
               hue: Double.random(in: 190...330),
               depth: CGFloat.random(in: 0.008...0.03))
    }

    // MARK: Zustand
    var planets: [Planet] = []
    var phase: Phase = .docked
    /// Liegeplatz im Hangar am Startplaneten (für die 3D-Welt)
    private(set) var dockPos = CGPoint.zero
    private(set) var dockHeading: CGFloat = 0
    /// letzter Start kam aus dem Hangar (keine Genauigkeitsanzeige)
    private(set) var dockLaunch = false
    /// Zeitpunkt des Starttipps im Hangar; danach hebt das Schiff ab und rollt beschleunigend los
    private(set) var departAt: CGFloat?
    static let liftTime: CGFloat = 1.1
    static let rollTime: CGFloat = 1.6
    /// Sekunden seit dem Starttipp, solange das Schiff noch am Liegeplatz abhebt oder anrollt
    var departElapsed: CGFloat? {
        guard phase == .docked, let t0 = departAt else { return nil }
        return time - t0
    }
    /// Höhe über der Plattform (nur 3D): sanft hoch, nach dem Abflug wieder auf Flughöhe
    var liftHeight: CGFloat {
        if departAt == nil, phase == .docked, let t0 = arriveAt {
            // Anflug: leicht über die Plattform heben und weich aufsetzen
            let u = min(1, max(0, (time - t0) / arriveDuration))
            return 6 * sin(u * .pi)
        }
        guard let t0 = departAt else { return 0 }
        let t = time - t0
        func ease(_ x: CGFloat) -> CGFloat { let c = min(1, max(0, x)); return c * c * (3 - 2 * c) }
        let up = ease(t / Game.liftTime)
        let down = ease((t - Game.liftTime - Game.rollTime) / 1.0)
        let hover = 0.5 * sin(t * 3.2) * up * (1 - ease((t - Game.liftTime) / 0.6))
        return (7 * up + hover) * (1 - down)
    }
    /// Anflug auf eine Raumstation: Startzeit, Dauer und Bogen um die Station bis zur Plattform
    private(set) var arriveAt: CGFloat?
    private var arriveDuration: CGFloat = 2.5
    private var arriveFromAngle: CGFloat = 0
    private var arriveFromDist: CGFloat = 0
    private var arriveSweep: CGFloat = 0
    private var arriveHeading: CGFloat = 0
    /// Das Schiff fliegt gerade die Andockplattform einer Station an
    var dockArriving: Bool {
        guard phase == .docked, departAt == nil, let t0 = arriveAt else { return false }
        return time - t0 < arriveDuration
    }
    /// Hangar-Nahaufnahme oder der Übergang danach: Zielanzeigen der Draufsicht passen dann nicht ins Bild
    var inHangarView: Bool { phase == .docked || (dockLaunch && time - lastLaunchTime < 1.8) }
    var started = false
    var hintShown = true
    var currentIndex = 0
    var originIndex = 0
    var score = 0
    var best = UserDefaults.standard.integer(forKey: "orbitHopBest")
    var energy: CGFloat = 100

    var orbitAngle: CGFloat = 0
    var orbitDist: CGFloat = 0
    var orbitDir: CGFloat = 1            // +1 oder -1, je nach Anflugseite
    var orbitVr: CGFloat = 0             // Radialtempo beim Einschwingen
    var orbitOmega: CGFloat = 0          // aktuelle Winkelgeschwindigkeit (mit Vorzeichen)
    var orbitPace: CGFloat = 0           // Ziel-Winkeltempo, startet beim Eintrittstempo
    var pos = CGPoint.zero
    var vel = CGVector.zero
    var heading: CGFloat = 0
    var flightTime: CGFloat = 0
    var trail: [CGPoint] = []

    var particles: [Particle] = []
    var bursts: [Burst] = []              // neue Effekte für die 3D-Welt
    var shatters: [Asteroid] = []         // zerstörte Kometen: die 3D-Welt lässt sie in Eisbrocken zerplatzen
    var cometKilledAt: CGFloat = -10      // Zeitpunkt der letzten Kometen-Zerstörung (Blitz und Banner)
    var generation = 0                    // zählt hoch bei jedem Neustart
    var project: ((CGPoint) -> CGPoint?)? // Welt → Bildschirm, kommt von der 3D-Welt
    var popups: [Popup] = []
    var waves: [Wave] = []
    var shake: CGFloat = 0
    var missFlash: CGFloat = 0

    var time: CGFloat = 0
    /// läuft auch in Pause und Stationsmenü weiter (für Kamerafahrten im Menü)
    var uiTime: CGFloat = 0
    var lastTime: TimeInterval?
    private var distanceTick = -1
    private var distanceShown = 0
    /// Zielentfernung für Ziel-Label und Pfeil, zweimal pro Sekunde übernommen: eine neue Zahl in jedem Bild
    /// bedeutete in jedem Bild neues Textlayout
    var shownDistance: Int {
        let t = Int(uiTime * 2)
        if t != distanceTick {
            distanceTick = t
            distanceShown = Int(targetDistance)
        }
        return distanceShown
    }
    var overAt: CGFloat = 0
    var lastAccuracy: CGFloat = 0
    var lastLaunchTime: CGFloat = -10

    var cam = CGPoint.zero
    var camScale: CGFloat = 0.4
    // Federn hinter cam und camScale (Zoom läuft logarithmisch, damit Rein- und Rauszoomen gleich wirken)
    private var camSpringX = SmoothSpring(0)
    private var camSpringY = SmoothSpring(0)
    private var camSpringZoom = SmoothSpring(log(0.4))

    // Bonus-Items
    var items: [Item] = []
    var wideConeLaunches = 0              // so viele Starts mit breitem Kegel
    var superBombs = 0                    // zündet beim nächsten Hindernis in der Flugbahn
    var rescueCharges = 0                 // eingesammelte Nachbrenner
    var boostTime: CGFloat = 0            // Nachbrenner-Effekt läuft
    var weaponCooldown: CGFloat = 0
    var projectiles: [Projectile] = []
    var beams: [Beam] = []
    var noEnergyFlash: CGFloat = 0
    var asteroids: [Asteroid] = []
    var enemyShots: [EnemyShot] = []
    var clouds: [GasCloud] = []
    var brakeFlash: CGFloat = 0           // kurz nach einem Asteroidentreffer
    var orbitCharge: CGFloat = 0          // umrundeter Winkel am aktuellen Planeten
    var bonusTaken: Set<Int> = []         // Planeten, die ihr Item schon abgegeben haben
    /// Doppelstern: Sonnenenergie, die dieser Orbit noch abgeben kann (nur beim Erstbesuch)
    var solarPool: CGFloat = 0
    /// Schwarzes Loch: Zeitpunkt, ab dem die Bahn zu zerfallen beginnt
    private var decayStart: CGFloat = 0
    /// Schwarzes Loch: das Schiff ist in der Gefahrenzone am Ereignishorizont
    private(set) var inHorizon = false
    private var horizonPopupAt: CGFloat = -10

    /// Sollradius der aktuellen Bahn. Am Schwarzen Loch schrumpft er nach kurzer Schonzeit stetig.
    var orbitRingRadius: CGFloat {
        let p = planets[currentIndex]
        guard phase == .orbiting, p.kind == .blackHole else { return p.orbitRadius }
        let shrink = max(0, time - decayStart) * Game.decayRate
        return max(p.radius + 18, p.orbitRadius - shrink)
    }
    static let decayRate: CGFloat = 13
    /// Schwarzes Loch: Sekunden bis die Gefahrenzone erreicht ist (nil, wenn nicht dort)
    var horizonCountdown: CGFloat? {
        let p = planets[currentIndex]
        guard phase == .orbiting, p.kind == .blackHole else { return nil }
        return max(0, (orbitRingRadius - p.horizonDanger) / Game.decayRate)
    }
    var currentKind: PlanetKind { planets[currentIndex].kind }

    // MARK: Combo
    /// Neue Planeten in Folge, jeweils mit mindestens „SEHR GUT“ gestartet und ohne Kollision erreicht
    private(set) var combo = 0
    /// längste Combo in diesem Flug und insgesamt
    private(set) var runBestCombo = 0
    private(set) var bestCombo = UserDefaults.standard.integer(forKey: "orbitHopBestCombo")
    /// Der laufende Flug zählt für die Combo (guter Start aus einem Orbit, noch keine Kollision)
    private var comboFlight = false
    static let comboAccuracy: CGFloat = 0.7
    /// Energiebonus: je Combo-Stufe 10 % mehr Energie beim Erreichen eines Planeten, höchstens doppelt so viel
    var comboMultiplier: CGFloat { 1 + 0.1 * CGFloat(min(combo, 10)) }
    /// Zeitpunkt der letzten Combo-Änderung (für das Aufblinken im HUD)
    private(set) var comboChangedAt: CGFloat = -10

    private func breakCombo() {
        if combo >= 2 {
            popups.append(Popup(pos: pos, text: "COMBO VERLOREN", color: Color(red: 0.75, green: 0.7, blue: 0.7), age: 0))
        }
        if combo > 0 { comboChangedAt = time }
        combo = 0
    }

    /// Ladefortschritt 0...1 am aktuellen Planeten, nil wenn es dort nichts gibt.
    /// Lädt gerade ein Bonus-Item auf (kein Energieverbrauch)
    var isCharging: Bool { phase == .orbiting && chargeFraction != nil }

    /// Farbe des Items, das gerade geladen wird
    var chargingKind: ItemKind? { isCharging ? planets[currentIndex].bonus : nil }

    var chargeFraction: CGFloat? {
        guard planets[currentIndex].bonus != nil, !bonusTaken.contains(currentIndex) else { return nil }
        return min(1, orbitCharge / chargeNeeded)
    }
    /// Bildausschnitt für den freien Flug, einmal beim Start festgelegt (Startpunkt und Zielorbit)
    private var flightFrame: CGRect?
    var insets = EdgeInsets()
    var techFocus: CGFloat = 0            // Restzeit: Kamera zoomt näher an den Planeten
    var overflow: CGFloat = 0             // überschüssige Energie, alle 100 ein Tech-Teil
    var techZoom: CGFloat = 0
    /// Während der Anflug-Einstellung: Orbit-Ausschnitt dieses Planeten schon vorab ansteuern
    var cameraLock: Int?
    var startedAt: CGFloat = 0

    // MARK: Anzeige-Werte (nur Optik)

    var speed: CGFloat {
        switch phase {
        case .flying: return hypot(vel.dx, vel.dy)
        case .docked:
            guard let t = departElapsed, t > Game.liftTime else { return 0 }
            return launchSpeed(accuracy: Game.dockAccuracy) * (t - Game.liftTime) / Game.rollTime
        default: return abs(orbitOmega) * orbitDist
        }
    }

    var targetDistance: CGFloat {
        let t = planets[min(currentIndex + 1, planets.count - 1)]
        return max(0, hypot(t.center.x - pos.x, t.center.y - pos.y) - t.radius)
    }

    var headingDegrees: Int {
        let d = (heading + CGFloat.pi / 2) * 180 / CGFloat.pi
        return Int(mod(d, 360))
    }

    var missionTime: CGFloat {
        guard started else { return 0 }
        return (phase == .over ? overAt : time) - startedAt
    }

    static let autopilot = ProcessInfo.processInfo.arguments.contains("-autopilot")
    /// Nur für Tests: alle 3 s drei Meldungen auf einmal, um das Stapeln zu prüfen
    static let popupTest = ProcessInfo.processInfo.arguments.contains("-popupTest")
    /// Nur für Tests: Flug startet mit 20 % Panzerung, um Rauch und Funken zu sehen
    static let hullTest = ProcessInfo.processInfo.arguments.contains("-hullTest")
    /// Testspieler mit menschenähnlichem Verhalten und Protokoll (Start mit -bot)
    static let bot = ProcessInfo.processInfo.arguments.contains("-bot")
    /// Testphase: erste Raumstation schon als zweites Ziel (vor der Veröffentlichung auf false setzen)
    static let stationTest = true   // TESTFLIGHT-TEST: erste Station als zweites Ziel; vor der Veröffentlichung wieder auf false
    /// Nur für Tests: Schwarzes Loch als zweites, Doppelstern als viertes Ziel (Start mit -planetTest)
    static let planetTest = ProcessInfo.processInfo.arguments.contains("-planetTest")
    /// Nur für Tests: Drohnen auf jeder Strecke ab dem zweiten Ziel (Start mit -droneTest)
    static let droneTest = ProcessInfo.processInfo.arguments.contains("-droneTest")

    // MARK: Raumstation
    /// Namen der Raumstationen; ab der elften wiederholen sie sich mit Zählung (AURORA II …).
    /// Name und Modell hängen an der Nummer, damit man eine Station wiedererkennt und dort neu starten kann.
    static let stationNames = ["AURORA", "VEGA", "HELIOS", "KEPLER", "BOREAS",
                               "LYRA", "ZENIT", "POLARIS", "ANDROMEDA", "ELYSIUM"]
    static let stationModels = 10

    static func stationName(_ k: Int) -> String {
        let round = max(0, k) / stationNames.count
        let roman = ["", " II", " III", " IV", " V", " VI", " VII", " VIII", " IX", " X"]
        return stationNames[max(0, k) % stationNames.count] + (round < roman.count ? roman[round] : " \(round + 1)")
    }

    /// Planetennummer der k-ten Station. Fest statt zufällig, damit jede Station immer an derselben
    /// Stelle der Strecke liegt: anfangs alle gut 30 Planeten, später alle gut 40.
    static func stationPlanet(_ k: Int) -> Int {
        var n = stationTest ? 2 : 32
        for j in 0..<max(0, k) {
            let lvl = min(1, CGFloat(n) / 40)
            n += Int(30 + 12 * lvl) + (j * 5) % 9
        }
        return n
    }

    /// Nummer der nächsten Station, die auf der Strecke entsteht
    private var nextStationNo = 0
    /// Planetennummer des ersten Planeten dieses Flugs: 0 im Hangar, sonst die der Startstation
    private(set) var planetBase = 0
    /// Name der Station, an der das Schiff gerade liegt
    var currentStationName: String? {
        let p = planets[currentIndex]
        return p.isStation ? Game.stationName(p.stationNo) : nil
    }
    /// Menü der Raumstation ist offen, die Simulation ruht
    var stationOpen = false
    /// Zeitpunkt, zu dem das Stationsmenü aufgeht (nach dem Einschwenken der Kamera)
    private var stationMenuAt: CGFloat?
    var atStation: Bool {
        planets[currentIndex].isStation && (phase == .orbiting || (phase == .docked && departAt == nil))
    }

    /// Andockplattform einer Station: auf der Bahn an der Stelle, von der aus die Tangente genau zum
    /// nächsten Planeten zeigt (wie im Hangar). Stationen werden immer gegen den Uhrzeigersinn angeflogen.
    func stationDock(_ i: Int) -> (pos: CGPoint, heading: CGFloat, angle: CGFloat)? {
        guard planets.indices.contains(i), planets.indices.contains(i + 1) else { return nil }
        let c = planets[i].center, t = planets[i + 1].center
        let dir = atan2(t.y - c.y, t.x - c.x)
        let angle = dir - CGFloat.pi / 2
        return (point(from: c, angle: angle, distance: planets[i].orbitRadius), dir, angle)
    }

    /// Panzerung: Kollisionen zehren daran, bei null explodiert das Schiff. Nur an Stationen reparierbar.
    static let maxHull: CGFloat = 100
    var hull: CGFloat = Game.maxHull
    /// Flug endete durch zerstörte Panzerung statt leerer Energie
    private(set) var destroyed = false

    /// Tech-Teile für eine volle Reparatur: etwa 1 je 10 % Panzerung und 1 je 25 Energie, mindestens 1
    var repairCost: Int {
        let missing = (Game.maxHull - hull) / 10 + (maxEnergy - energy) / 25
        return missing < 0.05 ? 0 : max(1, Int(missing.rounded()))
    }
    var needsRepair: Bool { repairCost > 0 }

    func repair() {
        let cost = repairCost
        guard cost > 0, profile.spendParts(cost) else { return }
        energy = maxEnergy
        hull = Game.maxHull
        overflow = 0
        Haptics.bonus()
    }

    /// Weiterfliegen: Menü zu, das Schiff hebt von der Plattform ab wie beim Spielstart
    func leaveStation() {
        stationOpen = false
        if phase == .docked { depart() }
    }

    /// Anflug auf die Station: das Schiff zieht in einem Bogen um die Station zur Andockplattform,
    /// bremst dabei ab und setzt auf. Danach öffnet sich das Stationsmenü.
    private func beginDocking(_ index: Int) {
        guard let d = stationDock(index) else { return }
        let c = planets[index].center
        arriveFromAngle = atan2(pos.y - c.y, pos.x - c.x)
        arriveFromDist = hypot(pos.x - c.x, pos.y - c.y)
        arriveSweep = mod(d.angle - arriveFromAngle, CGFloat.pi * 2)
        arriveHeading = heading
        let arc = arriveSweep * planets[index].orbitRadius
        arriveDuration = min(4.2, 1.8 + arc / 380)
        arriveAt = time
        orbitDir = 1
        orbitAngle = d.angle
        orbitDist = planets[index].orbitRadius
        orbitOmega = 0
        orbitVr = 0
        dockPos = d.pos
        dockHeading = d.heading
        departAt = nil
        dockLaunch = false
        vel = .zero
        phase = .docked
        stationMenuAt = time + arriveDuration + 0.3
    }

    /// Bogen zur Plattform: zügig herein, weich abbremsen; der Kurs dreht in der ersten halben Sekunde ein
    private func updateDocking() {
        guard let t0 = arriveAt else { return }
        let u = min(1, max(0, (time - t0) / arriveDuration))
        let e = 1 - (1 - u) * (1 - u) * (1 - u)
        let s = u * u * (3 - 2 * u)
        let c = planets[currentIndex].center
        let a = arriveFromAngle + arriveSweep * e
        pos = point(from: c, angle: a, distance: arriveFromDist + (orbitDist - arriveFromDist) * s)
        let turn = min(1, (time - t0) / 0.5)
        let k = turn * turn * (3 - 2 * turn)
        heading = arriveHeading + wrap(a + CGFloat.pi / 2 - arriveHeading) * k
        if u >= 1 {
            pos = dockPos
            heading = dockHeading
        }
    }
    var botThreshold: CGFloat = -1
    var botSkip = false
    var botWaitBonus = false
    var botWasInCone = false
    var botShots = 0
    var botNextTick: CGFloat = 0
    var captureTime: CGFloat = 0

    func blog(_ text: String) {
        guard Game.bot else { return }
        print("OHLOG \(String(format: "%.1f", time)) \(text)")
    }

    /// Speicherbedarf der App in MB, so wie iOS ihn für das Beenden wegen Speichermangels zählt (nur fürs Bot-Log)
    static func memoryMB() -> Int {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? Int(info.phys_footprint / 1_048_576) : -1
    }

    init() {
        ship = profile.selected
        reset()
    }

    /// Im Shop gewähltes Schiff übernehmen.
    func equip() {
        ship = profile.selected
        if !started { energy = maxEnergy } else { energy = min(energy, maxEnergy) }
    }

    // MARK: Start / Level

    func reset() {
        generation += 1
        runRecorded = false
        // Tagesmodus: Welt aus dem Datum, damit alle dieselbe Strecke fliegen
        if dailyMode {
            dailyDay = DailyChallenge.today
            dailyBest = DailyChallenge.best(for: dailyDay)
            Dice.rng = WorldRNG(seeded: DailyChallenge.seed(for: dailyDay))
        } else {
            Dice.rng = WorldRNG()
        }
        lastWarnTime = -10
        bursts = []
        ship = profile.selected
        runParts = 0
        runShipParts = 0
        hull = Game.hullTest ? 20 : Game.maxHull
        destroyed = false
        items = []
        projectiles = []
        beams = []
        weaponCooldown = 0
        asteroids = []
        enemyShots = []
        clouds = []
        brakeFlash = 0
        cometKilledAt = -10
        orbitCharge = 0
        bonusTaken = []
        solarPool = 0
        inHorizon = false
        combo = 0
        runBestCombo = 0
        runPerfects = 0
        comboFlight = false
        wideConeLaunches = 0
        superBombs = 0
        rescueCharges = 0
        boostTime = 0
        stationOpen = false
        stationMenuAt = nil
        arriveAt = nil
        // Start im Hangar oder an einer schon erreichten Raumstation (nie im Tagesflug)
        let startNo = dailyMode ? -1 : min(profile.startStation, profile.stationsReached - 1)
        planetBase = startNo >= 0 ? Game.stationPlanet(startNo) : 0
        nextStationNo = startNo + 1
        if startNo >= 0 {
            var first = Planet.make(center: .zero, radius: 160, spin: 0.85, hue: 165, allowRing: false, energyScale: 0)
            first.isStation = true
            first.stationNo = startNo
            planets = [first]
        } else {
            planets = [Planet.make(center: .zero, radius: 180, spin: 0.85, hue: 215, allowRing: false)]
        }
        while planets.count < 4 { addPlanet() }
        phase = .orbiting
        currentIndex = 0
        originIndex = 0
        score = planetBase
        energy = maxEnergy
        orbitAngle = CGFloat.random(in: 0...(CGFloat.pi * 2))
        // an einer Station liegt die Plattform immer auf derselben Seite (siehe stationDock)
        orbitDir = startNo >= 0 ? 1 : (Bool.random(using: &Dice.rng) ? 1 : -1)
        orbitDist = planets[0].orbitRadius
        orbitVr = 0
        orbitOmega = orbitDir * planets[0].spin
        orbitPace = planets[0].spin
        pos = point(from: planets[0].center, angle: orbitAngle, distance: orbitDist)
        heading = orbitAngle + orbitDir * CGFloat.pi / 2
        // Start aus dem Hangar: das Schiff ruht an der Kegelspitze, die Nase zeigt auf den ersten Zielplaneten
        orbitAngle = coneApexAngle
        orbitOmega = 0
        pos = point(from: planets[0].center, angle: orbitAngle, distance: orbitDist)
        heading = orbitAngle + orbitDir * CGFloat.pi / 2
        dockPos = pos
        dockHeading = heading
        dockLaunch = false
        departAt = nil
        phase = .docked
        vel = .zero
        trail = []
        particles = []
        popups = []
        waves = []
        flightTime = 0
        missFlash = 0
        shake = 0
        hintShown = true
        cam = planets[0].center
        camScale = 0.4
        camSpringX.snap(to: cam.x)
        camSpringY.snap(to: cam.y)
        camSpringZoom.snap(to: log(camScale))
        techFocus = 0
        techZoom = 0
        overflow = 0
        cameraLock = nil
        startedAt = time
    }

    func addPlanet() {
        let prev = planets[planets.count - 1]
        // je weiter hinten, desto kleiner, schneller umkreist und weiter entfernt
        // Nummer des neuen Planeten auf der ganzen Strecke (beim Start an einer Station nicht bei 0)
        let n = planetBase + planets.count
        let lvl = min(1, CGFloat(n) / 40)
        let station = n == Game.stationPlanet(nextStationNo)
        // Sonderplaneten ab Planet 6, nie zwei hintereinander und nicht direkt vor einer Station
        var kind = PlanetKind.normal
        if !station && n >= 6 && prev.kind == .normal && !prev.isStation && n + 1 != Game.stationPlanet(nextStationNo) {
            let roll = Double.random(in: 0...1, using: &Dice.rng)
            if roll < 0.06 + 0.05 * Double(lvl) { kind = .blackHole }
            else if roll < 0.13 + 0.05 * Double(lvl) { kind = .binary }
        }
        if Game.planetTest && !station {
            kind = n == 2 ? .blackHole : (n == 4 ? .binary : .normal)
        }
        // Raumstationen sind große, ruhige Planeten mit freier Anflugstrecke
        let r: CGFloat
        switch kind {
        case .blackHole: r = CGFloat.random(in: 62...76, using: &Dice.rng)
        case .binary: r = CGFloat.random(in: 120...150, using: &Dice.rng)
        case .normal: r = station ? 160 : CGFloat.random(in: (85 - 15 * lvl)...(240 - 70 * lvl), using: &Dice.rng)
        }
        let angle = -CGFloat.pi / 2 + CGFloat.random(in: -(0.9 + 0.3 * lvl)...(0.9 + 0.3 * lvl), using: &Dice.rng)
        // Liegt ein Asteroidenfeld auf der Strecke, ist der nächste Planet deutlich weiter weg
        // Kometen bekommen eine extra lange Strecke, damit sie lange vor einem bleiben
        let hasComet = !station && n >= 5 && Double.random(in: 0...1, using: &Dice.rng) < Double(0.07 + 0.08 * lvl)
        let hasField = !station && !hasComet && n >= 2 && Double.random(in: 0...1, using: &Dice.rng) < Double(0.45 + 0.4 * lvl)
        // Jägerdrohnen ab Planet 8, auch zusätzlich zu einem Feld (nie mit Komet oder vor einer Station)
        let hasDrones = !station && !hasComet && n >= (Game.droneTest ? 2 : 8)
            && Double.random(in: 0...1, using: &Dice.rng) < (Game.droneTest ? 1 : Double(0.12 + 0.18 * lvl))
        let gap = CGFloat.random(in: (1500 + 450 * lvl)...(2400 + 650 * lvl), using: &Dice.rng)
            + (hasField ? 2200 + 500 * lvl : 0) + (hasComet ? 3400 : 0)
        let dist = prev.radius + r + gap
        let c = point(from: prev.center, angle: angle, distance: dist)
        // Das Schwarze Loch wird so schnell umkreist wie ein mittelgroßer Planet, nicht wie ein winziger
        let spin = 150 / (kind == .blackHole ? 115 : r) * CGFloat.random(in: 0.9...1.2, using: &Dice.rng) * (1.1 + 0.5 * lvl)
        // Planetentyp: 3 von 4 Planeten haben ein Bonus-Item, die Farbe verrät welches (Sonderplaneten nie)
        let bonus: ItemKind? = !station && kind == .normal && Double.random(in: 0...1, using: &Dice.rng) < 0.75 ? ItemKind.random() : nil
        let hue: Double
        switch kind {
        case .blackHole: hue = 28
        case .binary: hue = 45
        case .normal: hue = station ? 165 : bonus?.planetHue ?? (Bool.random(using: &Dice.rng) ? Double.random(in: 40...80, using: &Dice.rng) : Double.random(in: 315...350, using: &Dice.rng))
        }
        // Energie: Schwarzes Loch als Belohnung für das Risiko mehr, Doppelstern lädt erst im Orbit nach
        let kindEnergy: CGFloat = kind == .blackHole ? 1.6 : (kind == .binary ? 0.4 : 1)
        planets.append(Planet.make(center: c, radius: r, spin: spin,
                                   hue: hue, allowRing: !station && kind == .normal,
                                   energyScale: station ? 0 : (0.85 - 0.3 * lvl) * (hasField || hasComet ? 1.35 : 1) * kindEnergy, bonus: bonus))
        planets[planets.count - 1].hardRoute = hasField || hasComet || hasDrones
        planets[planets.count - 1].isStation = station
        planets[planets.count - 1].kind = kind
        if station {
            planets[planets.count - 1].stationNo = nextStationNo
            nextStationNo += 1
        }

        guard planets.count >= 3 else { return }
        let gapIndex = planets.count - 1

        if hasField { spawnField(from: prev, to: planets[gapIndex], gap: gapIndex, lvl: lvl) }
        if hasComet { spawnComet(from: prev, to: planets[gapIndex], gap: gapIndex, lvl: lvl) }
        if hasDrones { spawnDrones(from: prev, to: planets[gapIndex], gap: gapIndex, lvl: lvl) }

        // Gelegentlich ein Gasnebel (nur Optik)
        if Double.random(in: 0...1, using: &Dice.rng) < 0.2 {
            let t = CGFloat.random(in: 0.3...0.7, using: &Dice.rng)
            let mid = CGPoint(x: prev.center.x + (c.x - prev.center.x) * t,
                              y: prev.center.y + (c.y - prev.center.y) * t)
            let cc = point(from: mid, angle: angle + CGFloat.pi / 2, distance: CGFloat.random(in: -250...250, using: &Dice.rng))
            let R = CGFloat.random(in: 260...420, using: &Dice.rng)
            let hue = Double.random(in: 0...360, using: &Dice.rng)
            let blobs = (0..<7).map { _ in
                GasCloud.Blob(off: CGPoint(x: CGFloat.random(in: -0.5...0.5, using: &Dice.rng) * R, y: CGFloat.random(in: -0.5...0.5, using: &Dice.rng) * R),
                              r: R * CGFloat.random(in: 0.35...0.7, using: &Dice.rng),
                              hue: hue + Double.random(in: -45...45, using: &Dice.rng),
                              speed: CGFloat.random(in: -0.12...0.12, using: &Dice.rng))
            }
            let sparkles = (0..<14).map { _ in
                point(from: cc, angle: CGFloat.random(in: 0...(CGFloat.pi * 2), using: &Dice.rng), distance: CGFloat.random(in: 0...(R * 0.7), using: &Dice.rng))
            }
            clouds.append(GasCloud(center: cc, radius: R, blobs: blobs, sparkles: sparkles, gap: gapIndex))
        }
    }

    // MARK: Hindernisse

    /// Feld aus Gestein, Satellitentrümmern oder Schiffswracks auf der Strecke
    private func spawnField(from a: Planet, to b: Planet, gap: Int, lvl: CGFloat) {
        let roll = Double.random(in: 0...1, using: &Dice.rng)
        let kind: ObstacleKind = gap >= 5 && roll < 0.15 ? .wreck : (gap >= 3 && roll < 0.4 ? .debris : .rock)
        let count: Int
        switch kind {
        case .rock: count = Int.random(in: 8...(12 + Int(6 * lvl)), using: &Dice.rng)
        case .debris: count = Int.random(in: 10...(15 + Int(5 * lvl)), using: &Dice.rng)
        case .wreck: count = Int.random(in: 3...4, using: &Dice.rng)
        case .comet, .drone: count = 0
        }
        for _ in 0..<count {
            // über die ganze Strecke verteilt, seitlich gestreut
            let t = CGFloat.random(in: 0.32...0.8, using: &Dice.rng)
            let along = CGPoint(x: a.center.x + (b.center.x - a.center.x) * t, y: a.center.y + (b.center.y - a.center.y) * t)
            let p = point(from: along, angle: CGFloat.random(in: 0...(CGFloat.pi * 2), using: &Dice.rng), distance: CGFloat.random(in: 0...280, using: &Dice.rng))
            if hypot(p.x - a.center.x, p.y - a.center.y) < a.orbitRadius + 70 { continue }
            if hypot(p.x - b.center.x, p.y - b.center.y) < b.orbitRadius + 70 { continue }
            var o = Asteroid(center: p, radius: CGFloat.random(in: 16...40, using: &Dice.rng),
                             shape: (0..<9).map { _ in CGFloat.random(in: 0.7...1.15, using: &Dice.rng) },
                             spin: CGFloat.random(in: -0.8...0.8, using: &Dice.rng),
                             phase: CGFloat.random(in: 0...(CGFloat.pi * 2), using: &Dice.rng),
                             tone: Double.random(in: 0.35...0.5, using: &Dice.rng), gap: gap)
            o.kind = kind
            switch kind {
            case .debris:
                o = Asteroid(center: p, radius: CGFloat.random(in: 12...24, using: &Dice.rng), shape: o.shape, spin: o.spin * 2,
                             phase: o.phase, tone: o.tone, gap: gap, kind: .debris,
                             vel: CGVector(dx: CGFloat.random(in: -12...12, using: &Dice.rng), dy: CGFloat.random(in: -12...12, using: &Dice.rng)),
                             variant: Int.random(in: 0...2, using: &Dice.rng))
            case .wreck:
                o = Asteroid(center: p, radius: CGFloat.random(in: 30...38, using: &Dice.rng), shape: o.shape, spin: o.spin * 0.3,
                             phase: o.phase, tone: o.tone, gap: gap, kind: .wreck, hp: 3, maxHP: 3,
                             vel: CGVector(dx: CGFloat.random(in: -18...18, using: &Dice.rng), dy: CGFloat.random(in: -18...18, using: &Dice.rng)),
                             variant: Int.random(in: 0..<ShipModel.all.count, using: &Dice.rng))
            default:
                break
            }
            asteroids.append(o)
        }
    }

    /// Komet fliegt langsam in Flugrichtung vor dem Schiff her und braucht mehrere Treffer
    private func spawnComet(from a: Planet, to b: Planet, gap: Int, lvl: CGFloat) {
        let dx = b.center.x - a.center.x, dy = b.center.y - a.center.y
        let len = hypot(dx, dy)
        let dir = CGVector(dx: dx / len, dy: dy / len)
        let start = CGPoint(x: a.center.x + dx * 0.3, y: a.center.y + dy * 0.3)
        let end = CGPoint(x: a.center.x + dx * 0.85, y: a.center.y + dy * 0.85)
        let hp = 8 + Int(4 * lvl)
        asteroids.append(Asteroid(center: start, radius: 52, shape: (0..<9).map { _ in CGFloat.random(in: 0.8...1.1, using: &Dice.rng) },
                                  spin: 0.3, phase: CGFloat.random(in: 0...(CGFloat.pi * 2), using: &Dice.rng), tone: 0.8, gap: gap,
                                  kind: .comet, hp: hp, maxHP: hp,
                                  vel: CGVector(dx: dir.dx * 105, dy: dir.dy * 105), end: end))
    }

    /// Ein bis drei Drohnen warten seitlich der Streckenmitte
    private func spawnDrones(from a: Planet, to b: Planet, gap: Int, lvl: CGFloat) {
        let count = 1 + (lvl > 0.35 ? 1 : 0) + (Double.random(in: 0...1, using: &Dice.rng) < Double(lvl) * 0.5 ? 1 : 0)
        let dir = atan2(b.center.y - a.center.y, b.center.x - a.center.x)
        for _ in 0..<count {
            let t = CGFloat.random(in: 0.4...0.68, using: &Dice.rng)
            let along = CGPoint(x: a.center.x + (b.center.x - a.center.x) * t, y: a.center.y + (b.center.y - a.center.y) * t)
            let p = point(from: along, angle: dir + .pi / 2, distance: CGFloat.random(in: -340...340, using: &Dice.rng))
            let hp = 3 + Int(3 * lvl)
            asteroids.append(Asteroid(center: p, radius: 22, shape: Array(repeating: 1, count: 9),
                                      spin: 0, phase: CGFloat.random(in: 0...(CGFloat.pi * 2), using: &Dice.rng),
                                      tone: 0.5, gap: gap, kind: .drone, hp: hp, maxHP: hp))
        }
    }

    static let droneSpeed: CGFloat = 235
    static let droneSight: CGFloat = 1500
    static let droneRange: CGFloat = 780

    /// Drohnen: im Flug auf ihrer Strecke Kurs auf das Schiff mit Vorhalt, schießen in Reichweite.
    /// Sonst schweben sie langsam an ihrem Platz. In den Zielorbit folgen sie nicht.
    private func moveDrones(_ dt: CGFloat) {
        let tg = planets[min(originIndex + 1, planets.count - 1)]
        for i in asteroids.indices where asteroids[i].kind == .drone {
            let c = asteroids[i].center
            let dx = pos.x - c.x, dy = pos.y - c.y
            let d = hypot(dx, dy)
            let hunting = phase == .flying && asteroids[i].gap == originIndex + 1 && d < Game.droneSight
            var want = CGVector.zero
            if hunting {
                // Vorhalt: dorthin, wo das Schiff gleich sein wird
                let lead = min(1.2, d / 600)
                let ax = pos.x + vel.dx * lead - c.x, ay = pos.y + vel.dy * lead - c.y
                let al = max(1, hypot(ax, ay))
                want = CGVector(dx: ax / al * Game.droneSpeed, dy: ay / al * Game.droneSpeed)
                // Drohnen rammen nicht: aus der Nähe drehen sie seitlich ab und halten Abstand
                if d < 320 {
                    let side: CGFloat = asteroids[i].phase > .pi ? 1 : -1
                    want = CGVector(dx: (-dx / max(1, d) - side * dy / max(1, d)) * Game.droneSpeed,
                                    dy: (-dy / max(1, d) + side * dx / max(1, d)) * Game.droneSpeed)
                }
                if d < Game.droneRange && time >= asteroids[i].fireAt {
                    asteroids[i].fireAt = time + CGFloat.random(in: 1.6...2.4)
                    let sl = max(1, hypot(ax, ay))
                    enemyShots.append(EnemyShot(p: c, v: CGVector(dx: ax / sl * EnemyShot.speed, dy: ay / sl * EnemyShot.speed)))
                }
            } else {
                // langsames Kreisen am Platz
                let a = asteroids[i].phase + time * 0.8
                want = CGVector(dx: cos(a) * 25, dy: sin(a) * 25)
            }
            // nicht in den Zielorbit hinein
            let tdx = c.x - tg.center.x, tdy = c.y - tg.center.y
            let td = max(1, hypot(tdx, tdy))
            if td < tg.orbitRadius + 260 {
                want = CGVector(dx: tdx / td * Game.droneSpeed * 0.6, dy: tdy / td * Game.droneSpeed * 0.6)
            }
            // weich lenken statt sofort umzudrehen
            let k = min(1, dt * 2.2)
            asteroids[i].vel.dx += (want.dx - asteroids[i].vel.dx) * k
            asteroids[i].vel.dy += (want.dy - asteroids[i].vel.dy) * k
        }

        // Plasmaschüsse fliegen geradeaus und treffen nur das Schiff
        for i in enemyShots.indices.reversed() {
            enemyShots[i].age += dt
            enemyShots[i].p.x += enemyShots[i].v.dx * dt
            enemyShots[i].p.y += enemyShots[i].v.dy * dt
            let p = enemyShots[i].p
            if phase != .docked && phase != .over && hypot(p.x - pos.x, p.y - pos.y) < 16 {
                enemyShots.remove(at: i)
                let damage = (9 * (1 - 0.6 * ship.armor)).rounded()
                hull = max(0, hull - damage)
                brakeFlash = max(brakeFlash, 0.6)
                burst(at: p, count: 18, hue: 355, speed: 200, life: 0.6)
                popups.append(Popup(pos: pos, text: "PLASMATREFFER -\(Int(damage))", color: Color(red: 1, green: 0.45, blue: 0.45), age: 0))
                shake = max(shake, 0.25)
                Haptics.miss()
                if comboFlight {
                    comboFlight = false
                    breakCombo()
                }
            } else if enemyShots[i].age > EnemyShot.maxAge {
                enemyShots.remove(at: i)
            }
        }
    }

    private func moveObstacles(_ dt: CGFloat) {
        moveDrones(dt)
        // Kometen schieben sich immer vor das fliegende Schiff
        let sp = hypot(vel.dx, vel.dy)
        if phase == .flying && sp > 1 {
            let fwd = CGVector(dx: vel.dx / sp, dy: vel.dy / sp)
            let tgt = planets[min(originIndex + 1, planets.count - 1)]
            for i in asteroids.indices where asteroids[i].kind == .comet && asteroids[i].gap == originIndex + 1 {
                let c = asteroids[i].center
                let along = (c.x - pos.x) * fwd.dx + (c.y - pos.y) * fwd.dy
                guard along > asteroids[i].radius else { continue }
                // Punkt auf der Flugbahn in gleicher Entfernung
                let want = CGPoint(x: pos.x + fwd.dx * along, y: pos.y + fwd.dy * along)
                let dx = want.x - c.x, dy = want.y - c.y
                let d = hypot(dx, dy)
                let step = min(d, 260 * dt)
                if d > 0.01 {
                    asteroids[i].center.x += dx / d * step
                    asteroids[i].center.y += dy / d * step
                }
                // weiter in Flugrichtung, aber nicht in den Zielorbit hinein
                let nearTarget = hypot(tgt.center.x - c.x, tgt.center.y - c.y) < tgt.orbitRadius + 550
                asteroids[i].vel = nearTarget ? .zero : CGVector(dx: fwd.dx * 105, dy: fwd.dy * 105)
                asteroids[i].end = nil
            }
        }
        for i in asteroids.indices.reversed() {
            let v = asteroids[i].vel
            guard v.dx != 0 || v.dy != 0 else { continue }
            asteroids[i].center.x += v.dx * dt
            asteroids[i].center.y += v.dy * dt
            if let e = asteroids[i].end {
                let c = asteroids[i].center
                if (e.x - c.x) * v.dx + (e.y - c.y) * v.dy < 0 {
                    // Komet bleibt am Streckenende stehen, bis er abgeschossen wird
                    asteroids[i].center = e
                    asteroids[i].vel = .zero
                }
            }
        }
    }

    // MARK: Kegel

    /// Richtung (Winkel) vom aktuellen Planeten zum Ziel.
    var coneDirection: CGFloat {
        let c = planets[currentIndex].center
        let t = planets[currentIndex + 1].center
        return atan2(t.y - c.y, t.x - c.x)
    }

    /// Bahnwinkel, bei dem die Tangente genau zum Ziel zeigt (Kegelspitze).
    var coneApexAngle: CGFloat { coneDirection - orbitDir * CGFloat.pi / 2 }

    func wrap(_ a: CGFloat) -> CGFloat {
        let twoPi = CGFloat.pi * 2
        var x = a.truncatingRemainder(dividingBy: twoPi)
        if x > CGFloat.pi { x -= twoPi }
        if x < -CGFloat.pi { x += twoPi }
        return x
    }

    var angleOffCenter: CGFloat { abs(wrap(orbitAngle - coneApexAngle)) }
    var inCone: Bool { phase == .orbiting && angleOffCenter < coneHalfAngle }

    // MARK: Effekte

    func burst(at p: CGPoint, count: Int, hue: Double, speed: CGFloat, life: CGFloat) {
        bursts.append(Burst(pos: p, count: count, hue: hue, speed: speed, life: life))
    }

    // MARK: Eingabe

    // MARK: Missionen und Erfolge

    let missions = MissionLog()
    /// perfekte Starts in diesem Flug
    private(set) var runPerfects = 0

    /// Ereignis melden; erfüllte Missionen und neue Erfolge zahlen sofort Tech-Teile aus
    private func track(_ event: MissionEvent) {
        for r in missions.record(event) {
            profile.addParts(r.parts)
            runParts += r.parts
            popups.append(Popup(pos: pos, text: r.text, color: Color(red: 0.55, green: 1, blue: 0.75), age: 0))
            Haptics.bonus()
        }
    }

    // MARK: Tägliche Herausforderung

    /// Tagesmodus: feste Strecke des Tages, eigener Bestwert und Bestenliste
    private(set) var dailyMode = ProcessInfo.processInfo.arguments.contains("-daily")
    /// Tag der laufenden Herausforderung (bleibt über Mitternacht hinweg für den laufenden Versuch gleich)
    private(set) var dailyDay = DailyChallenge.today
    private(set) var dailyBest = 0
    /// Letzter Versuch brachte einen neuen Tagesbestwert
    private(set) var dailyNewBest = false
    /// Ergebnis dieses Laufs ist schon gespeichert (Spielende, Abbruch und Neustart melden nur einmal)
    private var runRecorded = false

    /// Startpunkt wählen: -1 = Hangar, sonst eine erreichte Station; baut die Welt neu auf
    func setStartStation(_ k: Int) {
        profile.setStartStation(k)
        reset()
    }

    /// Zwischen freiem Spiel und Tagesherausforderung wechseln; baut die Welt neu auf
    func setDaily(_ on: Bool) {
        finishRun()
        dailyMode = on
        paused = false
        reset()
    }

    /// Ergebnis des Laufs festhalten: Rekord im freien Spiel, Tagesbestwert und Bestenliste im Tagesmodus
    private func finishRun() {
        // noch nicht losgeflogen: kein Versuch
        guard started, !runRecorded, score > 0 || phase != .docked else { return }
        runRecorded = true
        if dailyMode {
            dailyNewBest = DailyChallenge.record(score: score, day: dailyDay)
            if score > 0 { track(.dailyDone) }
            dailyBest = DailyChallenge.best(for: dailyDay)
            GameCenter.shared.submitDaily(score)
        } else if score > best {
            best = score
            UserDefaults.standard.set(best, forKey: "orbitHopBest")
        }
    }

    // MARK: Pause

    var paused = false
    private var lastWarnTime: CGFloat = -10

    func restart() {
        finishRun()
        paused = false
        reset()
        started = true
        startedAt = time
    }

    /// Lauf abbrechen und zurück zum Titel
    func abort() {
        finishRun()
        paused = false
        reset()
        started = false
    }

    func tap() {
        guard !paused && !stationOpen else { return }
        if !started {
            started = true
            startedAt = time
            // der Tipp auf dem Titel startet direkt aus dem Hangar
            if phase == .docked { depart() }
            return
        }
        switch phase {
        case .docked:
            // beim Anflug auf eine Station und im Stationsmenü startet ein Tipp nichts
            if arriveAt == nil { depart() }
        case .over:
            if time - overAt > 0.6 { reset() }
        case .flying:
            fire()
        case .orbiting:
            // im Kegel: Katapult, sonst feuert die Bordwaffe
            let diff = angleOffCenter
            guard diff < coneHalfAngle else {
                fire()
                return
            }
            launch(accuracy: 1 - diff / coneHalfAngle)
        }
    }

    private func launchSpeed(accuracy: CGFloat) -> CGFloat {
        let p = planets[currentIndex]
        // Schwarzes Loch: Schleuderstart mit deutlich mehr Tempo
        let sling: CGFloat = p.kind == .blackHole && phase == .orbiting ? 1.25 : 1
        return (minSpeed + accuracy * (maxSpeed - minSpeed) + p.spin * orbitDist * spinBonus) * ship.speed * sling
    }

    /// Schwarzes Loch: Warnung beim Eintritt in die Gefahrenzone, dort nagt die Gezeitenkraft an der Panzerung
    private func updateHorizon(_ p: Planet, _ dt: CGFloat) {
        let danger = orbitDist < p.horizonDanger
        if danger && !inHorizon && time - horizonPopupAt > 2 {
            horizonPopupAt = time
            popups.append(Popup(pos: pos, text: "EREIGNISHORIZONT", color: Color(red: 1, green: 0.45, blue: 0.3), age: 0))
            Haptics.miss()
        }
        inHorizon = danger
        guard danger else { return }
        // je tiefer, desto schlimmer; Panzerung des Schiffs mildert wie bei Kollisionen
        let depth = min(1, (p.horizonDanger - orbitDist) / 50)
        hull = max(0, hull - (10 + 22 * depth) * (1 - 0.5 * ship.armor) * dt)
        shake = max(shake, 0.12 + 0.15 * depth)
    }

    /// Katapult aus dem Orbit (oder aus dem Hangar) in Richtung der Bahntangente.
    private func launch(accuracy: CGFloat) {
        let speed = launchSpeed(accuracy: accuracy)
        let hd = orbitAngle + orbitDir * CGFloat.pi / 2
        vel = CGVector(dx: cos(hd) * speed, dy: sin(hd) * speed)
        originIndex = currentIndex
        flightTime = 0
        lastAccuracy = accuracy
        lastLaunchTime = time
        dockLaunch = false
        let tg = planets[min(currentIndex + 1, planets.count - 1)]
        let ext = tg.orbitRadius + 360
        flightFrame = CGRect(x: tg.center.x - ext, y: tg.center.y - ext, width: ext * 2, height: ext * 2)
            .union(CGRect(x: pos.x - 90, y: pos.y - 90, width: 180, height: 180))
        if wideConeLaunches > 0 { wideConeLaunches -= 1 }
        if planets[currentIndex].kind == .blackHole && phase == .orbiting {
            popups.append(Popup(pos: pos, text: "SCHLEUDERSTART", color: Color(red: 1, green: 0.7, blue: 0.35), age: 0))
            track(.blackHoleEscape)
        }
        if phase == .orbiting && accuracy >= 0.9 {
            runPerfects += 1
            track(.perfect(inRun: runPerfects))
        }
        inHorizon = false
        // ein schwacher Start beendet die Combo sofort, ein guter hält sie bis zur Ankunft offen
        comboFlight = phase == .orbiting && accuracy >= Game.comboAccuracy
        if phase == .orbiting && !comboFlight { breakCombo() }
        techFocus = 0
        cameraLock = nil
        hintShown = false
        phase = .flying
        // Partikel nur beim allerersten Start
        if score == 0 && originIndex == 0 {
            burst(at: pos, count: 26, hue: 175, speed: 120 + accuracy * 260, life: 0.7)
        }
        shake = max(shake, 0.1 + accuracy * 0.15)
        Haptics.launch(accuracy)
        SoundFX.shared.play(.launch, volume: 0.55 + 0.45 * accuracy)
        if accuracy >= 0.9 { SoundFX.shared.play(.perfect) }
        blog("launch idx=\(currentIndex) acc=\(Int(accuracy * 100)) speed=\(Int(speed)) energy=\(Int(energy)) orbit=\(String(format: "%.1f", time - captureTime))s field=\(asteroids.contains { $0.gap == currentIndex + 1 })")
    }

    /// Start aus dem Hangar: fester, kräftiger Start ohne Genauigkeitswertung.
    /// Der Hinweis bleibt stehen, bis der Spieler zum ersten Mal selbst aus einem Orbit startet.
    static let dockAccuracy: CGFloat = 0.7

    /// Starttipp im Hangar: abheben, dann losrollen (weitere Tipps werden ignoriert)
    private func depart() {
        guard departAt == nil else { return }
        departAt = time
        arriveAt = nil
        Haptics.capture()
        SoundFX.shared.play(.release)
    }

    /// Abflug aus dem Hangar: erst schweben, dann gleichmäßig beschleunigen bis auf Starttempo.
    /// Am Ende übernimmt der normale Flug mit genau diesem Tempo.
    private func updateDeparture() {
        guard let t = departElapsed else { return }
        let roll = t - Game.liftTime
        guard roll > 0 else { return }
        let s = min(roll, Game.rollTime)
        let v = launchSpeed(accuracy: Game.dockAccuracy)
        let d = 0.5 * v / Game.rollTime * s * s
        pos = CGPoint(x: dockPos.x + cos(dockHeading) * d, y: dockPos.y + sin(dockHeading) * d)
        if roll >= Game.rollTime { launchFromDock() }
    }

    private func launchFromDock() {
        launch(accuracy: Game.dockAccuracy)
        dockLaunch = true
        hintShown = true
    }

    // MARK: Simulation

    func step(date: Date, size: CGSize) {
        let now = date.timeIntervalSinceReferenceDate
        let dt = CGFloat(min(max(now - (lastTime ?? now), 0), 1.0 / 20.0))
        lastTime = now
        uiTime += dt
        if stationOpen && (Game.bot || Game.autopilot) { leaveStation() }
        guard !paused && !stationOpen else {
            SoundFX.shared.engineHum(level: 0, pitch: 50)
            // im Stationsmenü fährt die Kamera noch auf die Station über dem Menü
            if stationOpen { updateCamera(dt, size) }
            return
        }
        time += dt

        boostTime = max(0, boostTime - dt)
        // kurze Zeitlupe nach einem perfekten Start, läuft in 0,2 s wieder auf Normaltempo
        let sinceLaunch = time - lastLaunchTime
        let simDt = lastAccuracy >= 0.9 && sinceLaunch < 0.2 ? dt * (0.35 + 0.65 * sinceLaunch / 0.2) : dt
        // Nur für Tests im Simulator: Start mit Argument -autopilot
        if Game.bot { botStep() } else if Game.autopilot {
            if !started || (phase == .over && time - overAt > 2) { tap() }
            // an der Station auf das Menü warten, statt sofort weiterzufliegen
            else if atStation && stationMenuAt != nil {}
            else if phase == .docked || (phase == .orbiting && inCone && angleOffCenter < coneHalfAngle * 0.3) { tap() }
        }
        if Game.popupTest, phase == .orbiting, !atStation, Int((time - dt) / 3) != Int(time / 3) {
            for (t, h) in [("+1 TECH-TEIL", ItemKind.tech.hue), ("KOMET ZERSTÖRT", 200.0), ("+24", 140.0)] {
                popups.append(Popup(pos: pos, text: t, color: hsl(h, 0.85, 0.65), age: 0))
            }
        }
        if phase != .over { simulate(simDt) }
        if let t = stationMenuAt, time >= t {
            stationMenuAt = nil
            if atStation { stationOpen = true }
        }
        updateFx(simDt)
        updateCamera(dt, size)
        updateSound()
    }

    /// Triebwerkston nachführen und bei knapper Energie warnen
    private func updateSound() {
        var level: CGFloat = 0
        var pitch: CGFloat = 48
        switch phase {
        case .docked:
            if let t = departElapsed {
                // Abheben: Triebwerke laufen hoch, beim Losrollen wird der Ton höher
                let lift = min(1, t / Game.liftTime)
                let roll = min(1, max(0, (t - Game.liftTime) / Game.rollTime))
                level = 0.35 + 0.35 * lift + 0.3 * roll
                pitch = 42 + 14 * lift + 30 * roll
            }
        case .orbiting:
            level = 0.3
            pitch = 50
        case .flying:
            level = 0.55 + (boostTime > 0 ? 0.35 : 0)
            pitch = 50 + min(70, speed / 9)
        case .over:
            level = 0
        }
        SoundFX.shared.engineHum(level: started ? level : 0, pitch: pitch)

        if started && (phase == .orbiting || phase == .flying) && energy < 20 && time - lastWarnTime > 1.4 {
            lastWarnTime = time
            SoundFX.shared.play(.warning)
        }
    }

    private func botStep() {
        if !started { tap(); return }
        if phase == .over {
            if time - overAt > 2.5 { tap() }
            return
        }
        if time >= botNextTick {
            botNextTick = time + 5
            blog("tick phase=\(phase) idx=\(currentIndex) score=\(score) energy=\(Int(energy)) speed=\(Int(speed)) shots=\(botShots) obstacles=\(asteroids.count) mem=\(Game.memoryMB())MB")
        }
        switch phase {
        case .docked:
            tap()
        case .orbiting:
            if botThreshold < 0 {
                botThreshold = coneHalfAngle * CGFloat.random(in: 0.08...0.95)
                botSkip = Double.random(in: 0...1) < 0.12
                botWaitBonus = Double.random(in: 0...1) < 0.7
            }
            if let f = chargeFraction, f < 1, energy > 35, botWaitBonus { return }
            if inCone {
                botWasInCone = true
                if !botSkip && angleOffCenter < botThreshold {
                    tap()
                    botThreshold = -1
                }
            } else if botWasInCone {
                botWasInCone = false
                botSkip = false
                botThreshold = -1
            }
        case .flying:
            botThreshold = -1
            botWasInCone = false
            if weaponCooldown <= 0, energy > weaponCost + 12, aimTarget() != nil, Double.random(in: 0...1) < 0.25 {
                botShots += 1
                fire()
            }
        case .over:
            break
        }
    }

    private func simulate(_ dt: CGFloat) {
        let before = pos
        // Beim Aufladen eines Bonus-Items kein Verbrauch
        let charging = isCharging || (phase == .orbiting && currentKind == .binary && solarPool > 0)
        let hardFlight = phase == .flying && planets[min(originIndex + 1, planets.count - 1)].hardRoute
        // längere Strecken: im Flug generell 25 % weniger Verbrauch
        let flightFactor: CGFloat = phase == .flying ? (hardFlight ? 0.4 : 0.75) : 1
        if started && phase != .docked { energy -= energyDrain * dt * (charging ? 0 : 1) * flightFactor }
        missFlash = max(0, missFlash - dt)

        if energy <= 0 && rescueCharges > 0 {
            fireRescue()
        }

        if energy <= 0 || hull <= 0 {
            destroyed = hull <= 0
            blog("over score=\(score) t=\(Int(missionTime)) phase=\(phase) idx=\(currentIndex) flight=\(String(format: "%.1f", flightTime)) parts=\(runParts)")
            energy = 0
            phase = .over
            overAt = time
            burst(at: pos, count: 50, hue: 12, speed: 300, life: 1.2)
            shake = 0.5
            finishRun()
            Haptics.gameOver()
            SoundFX.shared.play(.gameOver)
            return
        }

        switch phase {
        case .docked:
            if departAt == nil { updateDocking() } else { updateDeparture() }
        case .orbiting:
            let p = planets[currentIndex]
            // weiches Einschwingen: Tempo und Radius gleiten auf die Bahn
            // Eintrittstempo bleibt erhalten und sinkt nur langsam aufs Grundtempo des Planeten
            orbitPace += (p.spin - orbitPace) * min(1, dt * 0.15)
            orbitOmega += (orbitDir * orbitPace - orbitOmega) * min(1, dt * 2.5)
            var targetDist = orbitRingRadius
            switch p.kind {
            case .normal:
                break
            case .blackHole:
                updateHorizon(p, dt)
            case .binary:
                // die beiden Sonnen drücken die Bahn im Takt ihres Umlaufs nach außen und innen
                targetDist += 22 * cos(2 * (orbitAngle - p.binaryAngle(at: time)))
                if solarPool > 0 {
                    let gain = min(solarPool, 9 * dt)
                    solarPool -= gain
                    addEnergy(gain, from: p.center)
                }
            }
            orbitVr += (30 * (targetDist - orbitDist) - 11 * orbitVr) * dt
            orbitDist = max(p.radius + 15, orbitDist + orbitVr * dt)
            orbitAngle += orbitOmega * dt
            pos = point(from: p.center, angle: orbitAngle, distance: orbitDist)
            if chargeFraction != nil {
                orbitCharge += abs(orbitOmega) * dt
                if orbitCharge >= chargeNeeded { spitBonus() }
            }
        case .flying:
            flightTime += dt
            if superBombs > 0 && obstacleAhead() { detonateSuperBomb() }
            let steps = max(1, Int(ceil(dt / (1.0 / 120.0))))
            let h = dt / CGFloat(steps)
            for _ in 0..<steps {
                integrate(h)
                if phase != .flying { break }
            }
            spawnExhaust()
        case .over:
            break
        }

        if hypot(pos.x - before.x, pos.y - before.y) > 0.0001 {
            heading = atan2(pos.y - before.y, pos.x - before.x)
        }
        trail.append(pos)
        if trail.count > 80 { trail.removeFirst(trail.count - 80) }

        collectItems()
    }

    // MARK: Bonus-Items

    private func collectItems() {
        guard phase != .over else { return }
        var i = 0
        while i < items.count {
            let it = items[i]
            if it.age >= Item.flyTime {
                items.remove(at: i)
                apply(it.kind, at: pos)
            } else {
                i += 1
            }
        }
    }

    private func apply(_ kind: ItemKind, at p: CGPoint) {
        blog("item \(kind) energy=\(Int(energy))")
        if kind != .tech && kind != .shipPart { track(.bonus) }
        switch kind {
        case .energy:
            addEnergy(35, from: p)
        case .wideCone:
            wideConeLaunches = 3
        case .superBomb:
            superBombs = min(2, superBombs + 1)
        case .rescue:
            rescueCharges = min(2, rescueCharges + 1)
        case .tech:
            runParts += 1
            profile.addParts(1)
        case .shipPart:
            runShipParts += 1
            profile.addShipParts(1)
            Haptics.bonus()
        }
        if kind == .tech || kind == .shipPart {
            burst(at: p, count: 30, hue: kind.hue, speed: 260, life: 0.9)
            waves.append(Wave(center: p, r0: 20, age: 0, maxAge: 0.7, hue: kind.hue))
        }
        // keine Texteinblendung beim Einsammeln: Lichtblitz, Ton und HUD-Anzeige reichen
        Haptics.capture()
        SoundFX.shared.play(kind == .tech || kind == .shipPart ? .tech : .item)
    }

    // MARK: Waffen


    func fire() {
        guard started, phase != .over, weaponCooldown <= 0 else { return }
        guard energy > weaponCost else {
            noEnergyFlash = 0.5
            Haptics.miss()
            SoundFX.shared.play(.empty)
            return
        }
        energy -= weaponCost
        weaponCooldown = weapon.cooldown
        let muzzle = point(from: pos, angle: heading, distance: 30)
        // Zielhilfe: nächstes Hindernis voraus anvisieren, mit Vorhalt bei bewegten Zielen
        let target = aimTarget()
        var fwd = CGVector(dx: cos(heading), dy: sin(heading))
        if let t = target {
            let lead = hypot(t.center.x - muzzle.x, t.center.y - muzzle.y) / 1900
            let ax = t.center.x + t.vel.dx * lead - muzzle.x
            let ay = t.center.y + t.vel.dy * lead - muzzle.y
            // nur minimal ablenken: höchstens etwa 10°, bei Drohnen bis etwa 35°
            let want = atan2(ay, ax)
            let limit: CGFloat = t.kind == .drone ? 0.6 : 0.18
            let hd = heading + max(-limit, min(limit, wrap(want - heading)))
            fwd = CGVector(dx: cos(hd), dy: sin(hd))
        }

        switch weapon {
        case .railgun:
            let to = CGPoint(x: muzzle.x + fwd.dx * 2400, y: muzzle.y + fwd.dy * 2400)
            beams.append(Beam(from: muzzle, to: to))
            for i in asteroids.indices.reversed() {
                let a = asteroids[i]
                if distanceToSegment(a.center, muzzle, to) < a.radius + 22 { damageObstacle(i, 3, blast: false) }
            }
            shake = max(shake, 0.2)
        case .cannon:
            projectiles.append(Projectile(kind: .cannon, p: muzzle,
                                          v: CGVector(dx: fwd.dx * 1900 + vel.dx * 0.3, dy: fwd.dy * 1900 + vel.dy * 0.3),
                                          maxAge: 1.6, target: target?.uid))
        case .rocket:
            projectiles.append(Projectile(kind: .rocket, p: muzzle,
                                          v: CGVector(dx: fwd.dx * 700 + vel.dx * 0.5, dy: fwd.dy * 700 + vel.dy * 0.5), maxAge: 2.5))
        case .bomb:
            projectiles.append(Projectile(kind: .bomb, p: muzzle,
                                          v: CGVector(dx: fwd.dx * 600 + vel.dx * 0.6, dy: fwd.dy * 600 + vel.dy * 0.6), maxAge: 0.9))
        }
        Haptics.launch(0.3)
        switch weapon {
        case .cannon: SoundFX.shared.play(.cannon)
        case .rocket: SoundFX.shared.play(.rocket)
        case .railgun: SoundFX.shared.play(.railgun)
        case .bomb: SoundFX.shared.play(.bomb)
        }
    }

    /// Nahes Hindernis fast genau voraus (bis ca. 15° seitlich, 750 weit)
    private func aimTarget() -> Asteroid? {
        let fwd = CGVector(dx: cos(heading), dy: sin(heading))
        var best: Asteroid?
        var bestScore = CGFloat.infinity
        for a in asteroids {
            let dx = a.center.x - pos.x, dy = a.center.y - pos.y
            let d = hypot(dx, dy)
            // Kometen liegen ohnehin in der Flugbahn und werden früher erfasst
            let range: CGFloat = a.kind == .comet ? 1700 : (a.kind == .drone ? 950 : 750)
            guard d > 1, d < range + a.radius else { continue }
            let cosA = (dx * fwd.dx + dy * fwd.dy) / d
            // Drohnen greifen von der Seite an: weiter Erfassungswinkel
            guard cosA > (a.kind == .drone ? 0.6 : 0.96) || d * sqrt(max(0, 1 - cosA * cosA)) < a.radius + 30 else { continue }
            guard cosA > 0 else { continue }
            // Objekte direkt in der Flugbahn haben Vorrang
            let side = d * sqrt(max(0, 1 - cosA * cosA))
            let score = d * 0.4 + max(0, side - a.radius) * 4
            if score < bestScore {
                best = a
                bestScore = score
            }
        }
        return best
    }

    private func updateWeapons(_ dt: CGFloat) {
        moveObstacles(dt)
        weaponCooldown = max(0, weaponCooldown - dt)
        noEnergyFlash = max(0, noEnergyFlash - dt)
        for i in beams.indices { beams[i].age += dt }
        beams.removeAll { $0.age > 0.4 }

        var i = 0
        while i < projectiles.count {
            var pr = projectiles[i]
            pr.age += dt

            if pr.kind == .rocket {
                // sucht den nächsten Asteroiden und beschleunigt
                var sp = hypot(pr.v.dx, pr.v.dy)
                var hd = atan2(pr.v.dy, pr.v.dx)
                func pathScore(_ a: Asteroid) -> CGFloat {
                    let dx = a.center.x - pr.p.x, dy = a.center.y - pr.p.y
                    let along = dx * cos(hd) + dy * sin(hd)
                    let side = abs(-dx * sin(hd) + dy * cos(hd))
                    return along < 0 ? .infinity : along * 0.4 + max(0, side - a.radius) * 4
                }
                if let t = asteroids.min(by: { pathScore($0) < pathScore($1) }),
                   pathScore(t) < .infinity, hypot(t.center.x - pr.p.x, t.center.y - pr.p.y) < 1800 {
                    let want = atan2(t.center.y - pr.p.y, t.center.x - pr.p.x)
                    hd += max(-5 * dt, min(5 * dt, wrap(want - hd)))
                }
                sp = min(1500, sp + 1400 * dt)
                pr.v = CGVector(dx: cos(hd) * sp, dy: sin(hd) * sp)
            }

            pr.p.x += pr.v.dx * dt
            pr.p.y += pr.v.dy * dt

            let reach: CGFloat = pr.kind == .bomb ? 24 : 12
            let hit = asteroids.firstIndex { hypot($0.center.x - pr.p.x, $0.center.y - pr.p.y) < $0.radius + reach }
            if hit != nil || pr.age >= pr.maxAge {
                switch pr.kind {
                case .cannon:
                    if let h = hit { damageObstacle(h, 1, blast: false) }
                case .rocket:
                    explode(at: pr.p, radius: 110, hue: WeaponKind.rocket.hue, damage: 2)
                case .bomb:
                    explode(at: pr.p, radius: 280, hue: WeaponKind.bomb.hue, damage: 4)
                case .railgun:
                    break
                }
                projectiles.remove(at: i)
            } else {
                projectiles[i] = pr
                i += 1
            }
        }
    }

    private func explode(at p: CGPoint, radius: CGFloat, hue: Double, damage: Int) {
        for i in asteroids.indices.reversed() {
            let a = asteroids[i]
            if hypot(a.center.x - p.x, a.center.y - p.y) < radius + a.radius { damageObstacle(i, damage, blast: true) }
        }
        burst(at: p, count: radius > 200 ? 60 : 30, hue: hue, speed: radius > 200 ? 420 : 260, life: 0.9)
        waves.append(Wave(center: p, r0: 10, age: 0, maxAge: 0.6, hue: hue))
        shake = max(shake, radius > 200 ? 0.45 : 0.25)
        Haptics.launch(radius > 200 ? 1 : 0.6)
        SoundFX.shared.play(radius > 200 ? .bigBlast : .blast)
    }

    /// Waffenschaden steigt mit der Ausbaustufe des Schiffs
    var weaponDamageFactor: CGFloat { 1 + 0.3 * CGFloat(ship.level) }

    private func damageObstacle(_ i: Int, _ base: Int, blast: Bool) {
        let amount = max(1, Int((CGFloat(base) * weaponDamageFactor).rounded()))
        asteroids[i].hp -= amount
        if asteroids[i].hp <= 0 {
            destroyAsteroid(i, blast: blast)
        } else {
            let a = asteroids[i]
            burst(at: a.center, count: 10, hue: a.kind == .comet ? 195 : 32, speed: 170, life: 0.5)
            shake = max(shake, 0.08)
            if !blast { SoundFX.shared.play(.crack, volume: 0.45) }
        }
    }

    private func destroyAsteroid(_ i: Int, blast: Bool) {
        let a = asteroids.remove(at: i)
        blog("destroy kind=\(a.kind)")
        track(a.kind == .comet ? .comet : (a.kind == .drone ? .drone : .obstacle))
        let techChance: Double
        switch a.kind {
        case .rock: techChance = 0.08
        case .debris: techChance = 0.08
        case .wreck: techChance = 0.35
        case .comet: techChance = 1
        case .drone: techChance = 0.4
        }
        if Double.random(in: 0...1) < techChance { spawnTech(from: a.center) }
        // Schiffsteile sind selten: nur aus Wracks und Kometen
        let shipPartChance: Double = a.kind == .wreck ? 0.2 : (a.kind == .comet ? 0.25 : 0)
        if Double.random(in: 0...1) < shipPartChance { spawnTech(from: a.center, kind: .shipPart) }
        if a.kind == .comet {
            // Der Komet soll unübersehbar zerplatzen: Eisbrocken, Lichtblitz, doppelte Druckwelle,
            // Bildschirmblitz und Banner (Renderer), dazu ein kräftiger Ruck
            shatters.append(a)
            cometKilledAt = time
            burst(at: a.center, count: 120, hue: 195, speed: 520, life: 1.6)
            burst(at: a.center, count: 50, hue: 180, speed: 260, life: 2.2)
            waves.append(Wave(center: a.center, r0: 30, age: 0, maxAge: 0.9, hue: 195))
            waves.append(Wave(center: a.center, r0: 10, age: 0, maxAge: 1.4, hue: 185))
            shake = max(shake, 0.6)
            Haptics.launch(1)
        }
        if a.kind == .drone {
            burst(at: a.center, count: 36, hue: 355, speed: 300, life: 0.9)
            popups.append(Popup(pos: a.center, text: "DROHNE ZERSTÖRT", color: Color(red: 1, green: 0.5, blue: 0.45), age: 0))
        }
        burst(at: a.center, count: 20, hue: a.kind == .wreck ? 20 : 32, speed: 240, life: 0.8)
        burst(at: a.center, count: 12, hue: 35, speed: 140, life: 1.0)
        if !blast { shake = max(shake, 0.12) }
        SoundFX.shared.play(a.kind == .comet ? .blast : .crack, volume: blast ? 0.6 : 1)
    }

    private func hitAsteroid(_ i: Int) {
        let a = asteroids[i]
        // Kometen überstehen Kollisionen, alles andere zerbricht
        blog("hit kind=\(a.kind) energy=\(Int(energy))")
        if a.kind == .comet {
            asteroids[i].bumpUntil = time + 1.2
        } else {
            asteroids.remove(at: i)
        }
        // Panzerung mindert Bremswirkung und Schaden
        let (baseKeep, baseDamage): (CGFloat, CGFloat)
        switch a.kind {
        case .rock: (baseKeep, baseDamage) = (0.55, 3)
        case .debris: (baseKeep, baseDamage) = (0.7, 2)
        case .wreck: (baseKeep, baseDamage) = (0.45, 5)
        case .comet: (baseKeep, baseDamage) = (0.3, 8)
        case .drone: (baseKeep, baseDamage) = (0.7, 2)
        }
        let keep = baseKeep + (1 - baseKeep) * ship.armor
        // Treffer gehen auf die Panzerung; gepanzerte Schiffe stecken mehr weg (Panzerungswert 0,6 → etwa 40 % weniger)
        let damage = (baseDamage * 8 * (1 - 0.7 * ship.armor)).rounded()
        vel = CGVector(dx: vel.dx * keep, dy: vel.dy * keep)
        hull = max(0, hull - damage)
        brakeFlash = 1.2
        if comboFlight {
            comboFlight = false
            breakCombo()
        }
        burst(at: a.center, count: 30, hue: 30, speed: 260, life: 0.8)
        burst(at: a.center, count: 16, hue: 35, speed: 150, life: 1.1)
        popups.append(Popup(pos: pos, text: damage > 0 ? "PANZERUNG -\(Int(damage))" : "ABGEPRALLT", color: Color(red: 0.8, green: 0.75, blue: 0.7), age: 0))
        shake = max(shake, 0.35)
        Haptics.miss()
        SoundFX.shared.play(.hit)
    }

    /// Energie auffüllen; was über das Maximum geht, sammelt sich und wird alle 100 zu einem Tech-Teil.
    private func addEnergy(_ amount: CGFloat, from origin: CGPoint) {
        let room = maxEnergy - energy
        if amount > room {
            overflow += amount - room
            energy = maxEnergy
        } else {
            energy += amount
        }
        while overflow >= 100 {
            overflow -= 100
            spawnTech(from: origin)
        }
    }

    /// Tech-Teil (oder Schiffsteil) fliegt von der Fundstelle direkt ins Schiff.
    private func spawnTech(from p: CGPoint, kind: ItemKind = .tech) {
        items.append(Item(kind: kind, from: p, p: p, gap: currentIndex + 1,
                          phase: CGFloat.random(in: 0...(CGFloat.pi * 2))))
    }

    /// Planet spuckt sein Item aus, es landet ein Stück voraus auf der Umlaufbahn.
    private func spitBonus() {
        let p = planets[currentIndex]
        guard let kind = p.bonus else { return }
        bonusTaken.insert(currentIndex)
        let from = point(from: p.center, angle: orbitAngle - orbitDir * 0.5, distance: p.radius)
        items.append(Item(kind: kind, from: from, p: from, gap: currentIndex,
                          phase: CGFloat.random(in: 0...(CGFloat.pi * 2))))
        shake = max(shake, 0.15)
        Haptics.bonus()
        SoundFX.shared.play(.bonus)
    }

    /// Liegt ein Hindernis dieser Strecke vor dem Schiff in der Flugbahn?
    private func obstacleAhead() -> Bool {
        let sp = hypot(vel.dx, vel.dy)
        guard sp > 1 else { return false }
        let fx = vel.dx / sp, fy = vel.dy / sp
        return asteroids.contains { a in
            guard a.gap == originIndex + 1 else { return false }
            let rx = a.center.x - pos.x, ry = a.center.y - pos.y
            let along = rx * fx + ry * fy
            let side = abs(rx * fy - ry * fx)
            return along > 0 && along < 900 && side < a.radius + 140
        }
    }

    /// Superbombe: zerstört alle Hindernisse bis zum nächsten Planeten
    private func detonateSuperBomb() {
        superBombs -= 1
        let seg = originIndex + 1
        blog("superbomb obstacles=\(asteroids.filter { $0.gap == seg }.count)")
        for i in asteroids.indices.reversed() where asteroids[i].gap == seg {
            destroyAsteroid(i, blast: true)
        }
        // Druckwellen entlang der Strecke
        let tgt = planets[min(seg, planets.count - 1)]
        let dist = hypot(tgt.center.x - pos.x, tgt.center.y - pos.y)
        let steps = max(1, Int(dist / 700))
        for k in 0...steps {
            let t = CGFloat(k) / CGFloat(steps)
            let c = CGPoint(x: pos.x + (tgt.center.x - pos.x) * t, y: pos.y + (tgt.center.y - pos.y) * t)
            waves.append(Wave(center: c, r0: 40, age: 0, maxAge: 0.9 + 0.15 * t, hue: ItemKind.superBomb.hue))
        }
        burst(at: pos, count: 60, hue: ItemKind.superBomb.hue, speed: 420, life: 1.2)
        shake = max(shake, 0.6)
        Haptics.launch(1)
        SoundFX.shared.play(.bigBlast)
    }

    private func fireRescue() {
        blog("rescue")
        rescueCharges -= 1
        energy = 30
        boostTime = 1.6
        if phase == .flying {
            vel = CGVector(dx: vel.dx * 1.35, dy: vel.dy * 1.35)
        }
        burst(at: pos, count: 60, hue: ItemKind.rescue.hue, speed: 380, life: 1.1)
        waves.append(Wave(center: pos, r0: 10, age: 0, maxAge: 1.0, hue: ItemKind.rescue.hue))
        popups.append(Popup(pos: pos, text: "NACHBRENNER +30", color: hsl(ItemKind.rescue.hue, 0.9, 0.62), age: 0))
        shake = max(shake, 0.45)
        Haptics.launch(1)
        SoundFX.shared.play(.rescue)
    }

    private func spawnExhaust() {}

    private func integrate(_ h: CGFloat) {
        let lo = max(0, currentIndex - 3)
        let hi = min(planets.count - 1, currentIndex + 4)

        var ax: CGFloat = 0
        var ay: CGFloat = 0
        for i in lo...hi {
            let p = planets[i]
            let dx = p.center.x - pos.x
            let dy = p.center.y - pos.y
            let d2 = dx * dx + dy * dy + 2500   // Softening
            let d = sqrt(d2)
            let a = gravityConstant * p.mass / d2
            ax += a * dx / d
            ay += a * dy / d
        }
        vel.dx += ax * h
        vel.dy += ay * h

        if flightTime > 0.3 {
            // Lenkhilfe: Anflug auf den Tangentenpunkt der Umlaufbahn, nie frontal auf den Planeten
            let tg = planets[originIndex + 1]
            let sp = hypot(vel.dx, vel.dy)
            var hd = atan2(vel.dy, vel.dx)
            let tdx = tg.center.x - pos.x
            let tdy = tg.center.y - pos.y
            let dd = hypot(tdx, tdy)
            let phi = atan2(tdy, tdx)
            var aim = phi
            if dd > tg.orbitRadius * 1.02 {
                let al = asin(min(1, tg.orbitRadius / dd))
                let a1 = phi + al
                let a2 = phi - al
                aim = abs(wrap(a1 - hd)) < abs(wrap(a2 - hd)) ? a1 : a2
            }
            // Nach längerem Flug lenkt die Hilfe stärker, damit der Satellit nicht festhängt
            let rate = homingRate * (1 + max(0, flightTime - 1.5))
            let dl = wrap(aim - hd)
            hd += max(-rate * h, min(rate * h, dl))
            // Mindesttempo: sonst heben sich die Anziehungskräfte zwischen zwei Planeten auf
            let floorSpeed = minFlightSpeed * ship.speed * (1 + 0.5 * max(0, flightTime - 1.5))
            let v = max(sp, floorSpeed)
            vel = CGVector(dx: cos(hd) * v, dy: sin(hd) * v)
        }

        pos.x += vel.dx * h
        pos.y += vel.dy * h

        for i in asteroids.indices.reversed() {
            let a = asteroids[i]
            if time >= a.bumpUntil && hypot(a.center.x - pos.x, a.center.y - pos.y) < a.radius + 8 {
                hitAsteroid(i)
            }
        }

        for i in lo...hi {
            if i == originIndex && flightTime < 1.0 { continue }
            let p = planets[i]
            let dx = pos.x - p.center.x
            let dy = pos.y - p.center.y
            // Schwarzes Loch: Fang erst nah an der Bahn, die Scheibe ist kein Planetenkörper
            let catchRadius = p.kind == .blackHole ? p.orbitRadius - 10 : p.radius + captureMargin
            if hypot(dx, dy) < catchRadius {
                capture(i, dx: dx, dy: dy)
                return
            }
        }
    }

    private func capture(_ index: Int, dx: CGFloat, dy: CGFloat) {
        blog("capture idx=\(index) kind=\(planets[index].kind) new=\(index > score) back=\(index == originIndex) flight=\(String(format: "%.1f", flightTime))s energy=\(Int(energy)) gain=\(Int(planets[index].energyGain))")
        captureTime = time
        // Drehrichtung ergibt sich aus der Anflugseite, Tempo und Radius gleiten danach auf die Bahn
        let cd = max(1, hypot(dx, dy))
        orbitOmega = (dx * vel.dy - dy * vel.dx) / (cd * cd)
        orbitVr = (dx * vel.dx + dy * vel.dy) / cd
        orbitDir = orbitOmega >= 0 ? 1 : -1
        let entry = abs(orbitOmega) * cd / planets[index].orbitRadius
        orbitPace = min(max(planets[index].spin, entry * 0.92), planets[index].spin * 2.8)
        currentIndex = index
        phase = .orbiting
        if cameraLock != index { cameraLock = nil }
        orbitAngle = atan2(dy, dx)
        orbitDist = hypot(dx, dy)
        orbitCharge = 0
        // Schwarzes Loch: kurze Schonzeit, dann zieht es die Bahn nach innen
        decayStart = time + 1.5
        inHorizon = false
        solarPool = 0

        let pl = planets[index]
        shake = max(shake, 0.3)
        // kein Vibrieren beim Einfangen (Christian, 2026-10-03)
        SoundFX.shared.play(.capture, variant: index)

        // zurückgefallen statt weiter: Combo ist weg
        let number = planetBase + index
        if number <= score && comboFlight { breakCombo() }
        if number > score {
            score = number
            if number % 5 == 0 {
                spawnTech(from: planets[index].center)
                techFocus = .infinity    // bleibt nah dran bis zum nächsten Start
            }
            if comboFlight {
                combo += 1
                comboChangedAt = time
                runBestCombo = max(runBestCombo, combo)
                track(.combo(combo))
                if combo > bestCombo {
                    bestCombo = combo
                    UserDefaults.standard.set(bestCombo, forKey: "orbitHopBestCombo")
                }
                // Combo zeigt die HUD-Leiste oben, keine zusätzliche Einblendung
                // alle 5 in Folge ein Tech-Teil
                if combo % 5 == 0 {
                    spawnTech(from: pl.center)
                }
            }
            // Stationen geben keine Energie ab, dort repariert man
            if pl.energyGain > 0 {
                let gain = pl.energyGain * comboMultiplier
                addEnergy(gain, from: pl.center)
            }
            track(.planet(index))
            if pl.isStation {
                track(.station)
                // ab jetzt kann man hier neu starten
                profile.reachStation(pl.stationNo)
                popups.append(Popup(pos: pos, text: "STATION \(Game.stationName(pl.stationNo))", color: Color(red: 0.45, green: 0.95, blue: 0.85), age: 0))
            }
            switch pl.kind {
            case .normal: break
            case .blackHole:
                popups.append(Popup(pos: pos, text: "SCHWARZES LOCH", color: Color(red: 1, green: 0.6, blue: 0.3), age: 0))
            case .binary:
                solarPool = 45
                track(.binary)
                popups.append(Popup(pos: pos, text: "DOPPELSTERN", color: Color(red: 1, green: 0.88, blue: 0.5), age: 0))
            }
        }
        comboFlight = false
        while planets.count < index + 4 { addPlanet() }
        items.removeAll { $0.gap < index - 2 }
        asteroids.removeAll { $0.gap < index - 1 || ($0.kind == .comet && $0.gap <= index) }
        clouds.removeAll { $0.gap < index - 2 }
        // Raumstation: nicht in den Orbit, sondern die Andockplattform anfliegen und landen
        if pl.isStation { beginDocking(index) }
    }

    private func updateFx(_ dt: CGFloat) {
        let drag = exp(-dt * 2.2)
        // Items fliegen im Bogen und beschleunigend in den Satelliten
        for i in items.indices {
            items[i].age += dt
            let t = min(1, items[i].age / Item.flyTime)
            let e = t * t
            let f = items[i].from
            let dx = pos.x - f.x
            let dy = pos.y - f.y
            let len = max(1, hypot(dx, dy))
            let arc = sin(t * CGFloat.pi) * min(60, len * 0.5) * orbitDir
            items[i].p = CGPoint(x: f.x + dx * e - dy / len * arc,
                                 y: f.y + dy * e + dx / len * arc)
        }
        for i in particles.indices {
            particles[i].life -= dt
            particles[i].x += particles[i].vx * dt
            particles[i].y += particles[i].vy * dt
            particles[i].vx *= drag
            particles[i].vy *= drag
        }
        particles.removeAll { $0.life <= 0 }

        for i in popups.indices { popups[i].age += dt }
        popups.removeAll { $0.age > Popup.lifetime }

        for i in waves.indices { waves[i].age += dt }
        waves.removeAll { $0.age > $0.maxAge }

        shake = max(0, shake - dt * 1.4)
        brakeFlash = max(0, brakeFlash - dt)
        updateWeapons(dt)
    }

    // MARK: Kamera

    /// Die Kamera rahmt den aktuellen und den nächsten Planeten gemeinsam ein. So bleibt der Ausschnitt
    /// beim Start und im Flug ruhig und wechselt nur einmal weich, wenn ein neuer Planet erreicht ist.
    private func updateCamera(_ dt: CGFloat, _ size: CGSize) {
        guard size.width > 0, phase != .over else { return }
        // Orbit-Ansicht: genau auf den Planeten zentriert, groß genug für Bahn und ein Stück Startkegel
        let lockedIndex = cameraLock.map { min($0, planets.count - 1) }
        let frameIndex = lockedIndex ?? (phase == .flying ? min(currentIndex + 1, planets.count - 1) : currentIndex)
        let fp = planets[frameIndex]
        let extent = fp.orbitRadius + 360
        let usable = min(size.width, size.height * 0.62)
        var targetCenter = fp.center
        var targetScale = usable / (extent * 2)
        // Freier Flug: fester Ausschnitt aus Startpunkt und Zielorbit, damit nicht ständig nachgezoomt wird.
        // Er wächst nur, falls das Schiff doch hinausfliegt. Kurz vor dem Ziel übernimmt die Orbit-Ansicht.
        if phase == .flying && cameraLock == nil
            && hypot(pos.x - fp.center.x, pos.y - fp.center.y) > fp.orbitRadius + 700 {
            let ship = CGRect(x: pos.x - 90, y: pos.y - 90, width: 180, height: 180)
            let r = flightFrame.map { $0.union(ship) } ?? ship
            targetCenter = CGPoint(x: r.midX, y: r.midY)
            targetScale = min(size.width / r.width, size.height * 0.62 / r.height)
        }
        // Stationsmenü: Maßstab für die Station über dem Menü (Blickwinkel und Lage setzt World3D)
        if stationOpen {
            targetScale = min(size.width, size.height * 0.4) / ((fp.orbitRadius + 60) * 2)
        }
        targetScale = min(max(targetScale, 0.04), 0.8)

        // Tech-Teil gefunden: weich näher heranzoomen
        techFocus = max(0, techFocus - dt)
        // rein zügig, raus langsam
        techZoom = smoothApproach(techZoom, techFocus > 0 ? 1 : 0, rate: techFocus > 0 ? 1.6 : 0.6, dt: dt)
        let f = techZoom * techZoom * (3 - 2 * techZoom)
        // Näher ran, aber weiter auf den Planeten zentriert: so passt die ganze Bahn ins Bild und die
        // Kamera kreist nicht mit dem Schiff mit
        let orbitFit = usable / ((fp.orbitRadius + 80) * 2)
        targetScale += (max(targetScale, orbitFit) - targetScale) * f

        // Federn statt fester Lerp-Rate: bei jedem Zielwechsel (neuer Planet, Start) läuft die Kamera
        // weich an, statt mit voller Geschwindigkeit loszuspringen.
        // gesperrt: zügig ansteuern, das passiert unsichtbar hinter der Anflug-Einstellung
        let smoothTime: CGFloat = cameraLock != nil ? 0.45 : 1.2
        cam.x = camSpringX.update(to: targetCenter.x, smoothTime: smoothTime, dt: dt)
        cam.y = camSpringY.update(to: targetCenter.y, smoothTime: smoothTime, dt: dt)
        camScale = exp(camSpringZoom.update(to: log(targetScale), smoothTime: smoothTime, dt: dt))
    }
}

// MARK: - Geometrie-Helfer

func point(from c: CGPoint, angle: CGFloat, distance: CGFloat) -> CGPoint {
    CGPoint(x: c.x + cos(angle) * distance, y: c.y + sin(angle) * distance)
}

func circlePath(_ c: CGPoint, _ r: CGFloat) -> Path {
    Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
}

func distanceToSegment(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
    let dx = b.x - a.x
    let dy = b.y - a.y
    let l2 = dx * dx + dy * dy
    guard l2 > 0 else { return hypot(p.x - a.x, p.y - a.y) }
    let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / l2))
    return hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy))
}

func mod(_ v: CGFloat, _ m: CGFloat) -> CGFloat {
    let r = v.truncatingRemainder(dividingBy: m)
    return r < 0 ? r + m : r
}
