import Foundation

// MARK: - Weltgenerator

/// Zufall für den Aufbau der Welt (Planeten, Hindernisse, Stationen). Im Tagesmodus festgelegt durch
/// das Datum, damit alle Spieler am selben Tag dieselbe Strecke fliegen; sonst echter Zufall.
/// Effekte, Partikel und Beute nutzen ihn nicht, sonst hinge die Welt vom Spielverlauf ab.
struct WorldRNG: RandomNumberGenerator {
    var seeded: SeededRNG?

    mutating func next() -> UInt64 {
        if seeded != nil { return seeded!.next() }
        var system = SystemRandomNumberGenerator()
        return system.next()
    }
}

enum Dice {
    static var rng = WorldRNG()
}

// MARK: - Tägliche Herausforderung

/// Jeden Tag (UTC) eine feste Strecke für alle. Bestes Ergebnis des Tages wird lokal gespeichert
/// und an die tägliche Game-Center-Bestenliste gemeldet.
enum DailyChallenge {
    /// In App Store Connect als wiederkehrende Bestenliste (täglich) anzulegen
    static let leaderboardID = "com.chv.OrbitHop.daily"

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// Tageskennung, z. B. 2026-10-03
    static var today: String { dayFormatter.string(from: Date()) }

    /// Datum zum Anzeigen, z. B. 03.10.
    static var todayLabel: String {
        let parts = today.split(separator: "-")
        guard parts.count == 3 else { return today }
        return "\(parts[2]).\(parts[1])."
    }

    static func seed(for day: String) -> SeededRNG { SeededRNG("orbix-daily-\(day)") }

    private static func bestKey(_ day: String) -> String { "orbitHopDailyBest-\(day)" }
    private static func triesKey(_ day: String) -> String { "orbitHopDailyTries-\(day)" }

    static func best(for day: String) -> Int { UserDefaults.standard.integer(forKey: bestKey(day)) }
    static func tries(for day: String) -> Int { UserDefaults.standard.integer(forKey: triesKey(day)) }

    /// Ergebnis eines Versuchs speichern; true, wenn es ein neuer Tagesbestwert ist
    @discardableResult
    static func record(score: Int, day: String) -> Bool {
        let d = UserDefaults.standard
        d.set(tries(for: day) + 1, forKey: triesKey(day))
        guard score > best(for: day) else { return false }
        d.set(score, forKey: bestKey(day))
        return true
    }
}
