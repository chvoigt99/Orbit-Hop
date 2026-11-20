import SwiftUI

// MARK: - Piratenschiffe

/// Werte der drei Piratenklassen: 0 leichter Jäger, 1 Kanonenboot, 2 Anführer (Kopfgeldziel)
enum Raider {
    private static func pick<T>(_ v: Int, _ values: [T]) -> T { values[max(0, min(values.count - 1, v))] }
    static func radius(_ v: Int) -> CGFloat { pick(v, [24, 30, 40] as [CGFloat]) }
    /// so viel schneller als das Spielerschiff dürfen sie werden
    static func speedBonus(_ v: Int) -> CGFloat { pick(v, [240, 160, 200] as [CGFloat]) }
    static func shotDamage(_ v: Int) -> CGFloat { pick(v, [6, 8, 10] as [CGFloat]) }
    static func burstCount(_ v: Int) -> Int { pick(v, [2, 3, 3]) }
    static func title(_ v: Int) -> String { pick(v, ["PIRAT", "KANONENBOOT", "ANFÜHRER"]) }
    static let shotSpeed: CGFloat = 520
    static let range: CGFloat = 1000
}

extension Game {
    /// Piraten, die auf der aktuellen Strecke noch angreifen
    var raidersOnRoute: Int {
        asteroids.reduce(0) { $0 + ($1.kind == .raider && $1.gap == originIndex + 1 && !$1.retreating ? 1 : 0) }
    }

    /// Piraten fliegen im Verband vor dem Schiff her, damit man sie in der Verfolgeransicht vor sich hat:
    /// sie halten Abstand und weben seitlich, alle paar Sekunden setzt einer zu einem dichten Angriffsanflug an.
    /// Verlässt das Schiff die Passage, drehen sie ab. Schilde laden sich nach einer Pause wieder auf.
    func moveRaiders(_ dt: CGFloat) {
        var gone: [Int] = []
        let sp = max(1, hypot(vel.dx, vel.dy))
        let f = CGVector(dx: vel.dx / sp, dy: vel.dy / sp)
        let s = CGVector(dx: -f.dy, dy: f.dx)
        for i in asteroids.indices where asteroids[i].kind == .raider {
            var a = asteroids[i]
            let c = a.center
            let dx = pos.x - c.x, dy = pos.y - c.y
            let d = max(1, hypot(dx, dy))
            let route = planets[min(a.gap, planets.count - 1)]
            let shipAt = progress(pos, gap: a.gap) ?? 0
            let onRoute = phase == .flying && a.gap == originIndex + 1
            // Schiff in Sicht: angreifen (der Anführer stellt sich vor)
            if !a.awake && onRoute && shipAt > route.passageFrom - 600 && d < 2400 {
                a.awake = true
                a.fireAt = time + 1.0 + CGFloat.random(in: 0...0.6)
                if a.variant == 2 {
                    popups.append(Popup(pos: c, text: "\(bountyName) GREIFT AN", color: Color(red: 1, green: 0.4, blue: 0.35), age: 0, lift: 70))
                    shake = max(shake, 0.2)
                }
            }
            // Passage hinter sich oder Strecke verlassen: abdrehen
            if a.awake && !a.retreating && (!onRoute || shipAt > route.passageTo) { a.retreating = true }

            var want: CGVector
            if a.retreating {
                let side: CGFloat = a.phase > .pi ? 1 : -1
                want = CGVector(dx: (s.dx * side + f.dx * 0.4) * 560, dy: (s.dy * side + f.dy * 0.4) * 560)
                if d > 2600 { gone.append(a.uid) }
            } else if a.awake && phase == .flying {
                let t = time + a.phase * 3
                // alle gut fünf Sekunden ein dichter Anflug, versetzt je Schiff
                let cycle = frac(time * 0.19 + a.phase / (2 * .pi))
                let attack = cycle > 0.74
                let cruise: CGFloat = 420 + 110 * sin(t * 0.6) + 60 * CGFloat(a.variant)
                let ahead: CGFloat = attack ? 190 : cruise
                let weave: CGFloat = 135 * sin(t * 0.8 + a.phase)
                let lateral: CGFloat = attack ? (a.phase > .pi ? 70 : -70) : weave
                let target = CGPoint(x: pos.x + f.dx * ahead + s.dx * lateral, y: pos.y + f.dy * ahead + s.dy * lateral)
                var vx = vel.dx + (target.x - c.x) * 1.6
                var vy = vel.dy + (target.y - c.y) * 1.6
                // nicht rammen: aus der Nähe wegdrücken
                if d < 140 {
                    vx -= dx / d * 420
                    vy -= dy / d * 420
                }
                let cap = sp + Raider.speedBonus(a.variant)
                let vl = hypot(vx, vy)
                if vl > cap {
                    vx = vx / vl * cap
                    vy = vy / vl * cap
                }
                want = CGVector(dx: vx, dy: vy)
            } else {
                // warten: langsames Kreisen am Platz
                let ang = a.phase + time * 0.6
                want = CGVector(dx: cos(ang) * 30, dy: sin(ang) * 30)
            }
            let k = min(1, dt * (a.awake ? 3.2 : 2))
            a.vel.dx += (want.dx - a.vel.dx) * k
            a.vel.dy += (want.dy - a.vel.dy) * k

            // Bug: im Kampf zum Schiff, sonst in Flugrichtung
            let toShip = atan2(dy, dx)
            let moving = hypot(a.vel.dx, a.vel.dy) > 40
            let look: CGFloat = a.awake && !a.retreating && d < 1500 ? toShip : (moving ? atan2(a.vel.dy, a.vel.dx) : a.facing)
            a.facing += max(-4.5 * dt, min(4.5 * dt, wrap(look - a.facing)))

            // Schilde laden nach 2,5 s ohne Treffer wieder auf
            if a.shield < a.maxShield && time - a.hitAt > 2.5 {
                a.shield = min(a.maxShield, a.shield + a.maxShield * 0.35 * dt)
            }
            // Salven, sobald das Schiff vor dem Bug liegt
            if a.awake && !a.retreating && onRoute && d < Raider.range && abs(wrap(toShip - a.facing)) < 0.45 && time >= a.fireAt {
                fireRaiderShot(&a, dist: d)
            }
            asteroids[i] = a
        }
        for uid in gone {
            guard let i = asteroids.firstIndex(where: { $0.uid == uid }) else { continue }
            let a = asteroids.remove(at: i)
            if a.variant == 2 { bossEscaped() }
        }
    }

    /// Ein Schuss der Salve mit Vorhalt. Schnelle Schiffe sind schwer zu treffen: die Streuung wächst mit dem Tempo
    /// des Spielerschiffs. Der Anführer feuert kleine Fächer.
    private func fireRaiderShot(_ a: inout Asteroid, dist: CGFloat) {
        let muzzle = point(from: a.center, angle: a.facing, distance: a.radius)
        let lead = dist / (Raider.shotSpeed + 250)
        let base = atan2(pos.y + vel.dy * lead - muzzle.y, pos.x + vel.dx * lead - muzzle.x)
        let spread = 0.04 + 0.12 * max(0, ship.speed - 0.8)
        let count = a.variant == 2 ? 3 : 1
        for k in 0..<count {
            let off = count == 1 ? 0 : (CGFloat(k) - 1) * 0.13
            let ang = base + off + CGFloat.random(in: -spread...spread)
            enemyShots.append(EnemyShot(p: muzzle, v: CGVector(dx: cos(ang) * Raider.shotSpeed, dy: sin(ang) * Raider.shotSpeed),
                                        damage: Raider.shotDamage(a.variant), raider: true))
        }
        a.burstLeft -= 1
        if a.burstLeft > 0 {
            a.fireAt = time + 0.15
        } else {
            a.burstLeft = Raider.burstCount(a.variant)
            a.fireAt = time + CGFloat.random(in: 1.5...2.3) + (a.variant == 1 ? 0.4 : 0)
        }
    }

    /// Treffer auf ein Piratenschiff. Kanonen-Dauerfeuer zerschlägt Schilde besonders gut, Explosionen weichen
    /// die wendigen Schiffe teilweise aus. Der Schild fängt zuerst ab, danach geht es auf den Rumpf.
    func damageRaider(_ i: Int, _ base: CGFloat, blast: Bool) {
        guard asteroids.indices.contains(i), asteroids[i].kind == .raider else { return }
        let weaponFactor: CGFloat = blast ? 0.6 : (weapon == .cannon ? 1.6 : 1)
        var dmg = base * weaponDamageFactor * weaponFactor * ship.shipDamageFactor
        asteroids[i].hitAt = time
        if !asteroids[i].awake {
            asteroids[i].awake = true
            asteroids[i].fireAt = time + 0.8
        }
        let c = asteroids[i].center
        if asteroids[i].shield > 0 {
            let absorbed = min(asteroids[i].shield, dmg)
            asteroids[i].shield -= absorbed
            dmg -= absorbed
            burst(at: c, count: 8, hue: 200, speed: 170, life: 0.4)
        }
        // Bruchteile zählen als Zufall, damit auch kleine Treffer wirken
        var whole = Int(dmg)
        if CGFloat.random(in: 0...1) < dmg - CGFloat(whole) { whole += 1 }
        guard whole > 0 else { return }
        asteroids[i].hp -= whole
        if asteroids[i].hp <= 0 {
            destroyAsteroid(i, blast: blast)
        } else {
            burst(at: c, count: 10, hue: 25, speed: 190, life: 0.5)
            shake = max(shake, 0.06)
            if !blast { SoundFX.shared.play(.crack, volume: 0.4) }
        }
    }

    /// Abschuss: Kopfgeld (mal Kopfgeld-Faktor des Schiffs, Jäger kassieren am meisten), Beute und Explosion
    func raiderDestroyed(_ a: Asteroid) {
        let boss = a.variant == 2
        runRaiderKills += 1
        track(boss ? .boss : .raider)
        // Kopfgeld in Tech-Teilen, die zum Schiff fliegen
        let baseBounty: CGFloat = boss ? 4 : (a.variant == 1 ? 2 : 1)
        let bounty = baseBounty * ship.bountyFactor
        var tech = Int(bounty)
        if CGFloat.random(in: 0...1) < bounty - CGFloat(tech) { tech += 1 }
        for _ in 0..<tech { spawnTech(from: a.center) }
        // Beute: Frachtcontainer, Energiezellen, selten Schiffsteile (Bergungsdrohne erhöht die Chancen)
        let salvage = Double(ship.salvageFactor)
        if Double.random(in: 0...1) < (boss ? 1 : 0.35) * salvage { spawnTech(from: a.center, kind: .cargo) }
        if Double.random(in: 0...1) < 0.3 { spawnTech(from: a.center, kind: .energy) }
        let basePart: Double = boss ? 0.35 : (a.variant == 1 ? 0.04 : 0.015)
        let partChance = basePart * salvage
        if Double.random(in: 0...1) < partChance { spawnTech(from: a.center, kind: .shipPart) }

        // Explosion: Feuerball, Trümmerfunken, Druckwelle
        let big: CGFloat = boss ? 1.8 : (a.variant == 1 ? 1.3 : 1)
        burst(at: a.center, count: Int(50 * big), hue: 18, speed: 340 * big, life: 1.0)
        burst(at: a.center, count: Int(26 * big), hue: 40, speed: 170 * big, life: 1.3)
        burst(at: a.center, count: Int(14 * big), hue: 200, speed: 260, life: 0.6)
        waves.append(Wave(center: a.center, r0: 20, age: 0, maxAge: 0.7 * big, hue: 20))
        if boss { waves.append(Wave(center: a.center, r0: 10, age: 0, maxAge: 1.3, hue: 48)) }
        shake = max(shake, boss ? 0.6 : 0.3)
        let text = boss ? "\(bountyName) VERNICHTET" : "\(Raider.title(a.variant)) ZERSTÖRT · +\(tech) KOPFGELD"
        popups.append(Popup(pos: a.center, text: text, color: Color(red: 1, green: 0.55, blue: 0.4), age: 0, lift: 60))
        Haptics.launch(1)
        SoundFX.shared.play(boss ? .bigBlast : .blast)
        contractKill(boss: boss)
    }
}
