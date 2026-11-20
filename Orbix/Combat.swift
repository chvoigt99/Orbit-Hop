import SwiftUI

// MARK: - Piratenschiffe

/// Werte der drei Piratenklassen: 0 leichter Jäger, 1 Kanonenboot, 2 Anführer (Kopfgeldziel)
enum Raider {
    private static func pick<T>(_ v: Int, _ values: [T]) -> T { values[max(0, min(values.count - 1, v))] }
    static func radius(_ v: Int) -> CGFloat { pick(v, [24, 30, 40] as [CGFloat]) }
    /// so viel schneller als das Spielerschiff dürfen sie werden
    static func speedBonus(_ v: Int) -> CGFloat { pick(v, [120, 60, 90] as [CGFloat]) }
    static func shotDamage(_ v: Int) -> CGFloat { pick(v, [7, 9, 12] as [CGFloat]) }
    static func burstCount(_ v: Int) -> Int { pick(v, [3, 3, 4]) }
    static func title(_ v: Int) -> String { pick(v, ["PIRAT", "KANONENBOOT", "ANFÜHRER"]) }
    static let shotSpeed: CGFloat = 520
    static let range: CGFloat = 900

    /// Rumpf und Schild je Klasse, Schwierigkeit und Auftragsstufe
    static func stats(_ v: Int, lvl: CGFloat, tier: Int) -> (hp: Int, shield: CGFloat) {
        switch v {
        // zäh: Gefechte sollen eine Herausforderung sein (Christian, 2026-11-20)
        case 2: return (60 + Int(30 * lvl) + 8 * tier, 30 + 15 * lvl + 4 * CGFloat(tier))
        case 1: return (22 + Int(12 * lvl) + 2 * tier, 14 + 6 * lvl + CGFloat(tier))
        default: return (10 + Int(6 * lvl) + tier, 6 + 4 * lvl)
        }
    }
}

/// Art des Gefechtsplaneten
enum ArenaKind {
    /// Überfall: Piraten lauern Frachtern auf (und selten jedem anderen)
    case ambush
    /// Auftrag „Piraten bei Planet X beseitigen“: mehrere Wellen
    case patrol
    /// Kopfgeld: der Anführer mit Begleitschutz
    case boss

    var title: String {
        switch self {
        case .ambush: return "PIRATENÜBERFALL"
        case .patrol: return "PIRATENREVIER"
        case .boss: return "PIRATENNEST"
        }
    }
}

// MARK: - Gefecht

/// Gefechte sind ein eigener Spielteil: Man fliegt per Orbit-Sprüngen zu einem rot markierten Gefechtsplaneten.
/// Erreicht man ihn, beginnt dort ein freies Gefecht: Der Finger lenkt, der Feuerknopf schießt, der Planet ist
/// Deckung. Nach dem Sieg (oder nach einer Weile Abdrehen) schwenkt das Schiff zurück in den Orbit und es geht
/// mit Sprüngen weiter (Christian, 2026-11-20).
extension Game {
    /// Bildausschnitt im Gefecht (Weltbreite)
    static let combatView: CGFloat = 1500
    /// so weit vom Planeten reicht das Gefechtsfeld
    static let arenaReach: CGFloat = 1700
    /// ab dann darf man abdrehen
    static let fleeAfter: CGFloat = 20

    var combatCruise: CGFloat { 220 * ship.speed }
    var combatTop: CGFloat { 370 * ship.speed }
    /// schnelle Schiffe sind auch wendiger
    var combatTurn: CGFloat { 2.3 + 1.8 * max(0, ship.speed - 0.8) }

    /// Piraten, die im laufenden Gefecht noch kämpfen
    var arenaRaiders: Int {
        asteroids.reduce(0) { $0 + ($1.kind == .raider && $1.gap == arenaIndex && !$1.retreating ? 1 : 0) }
    }

    var canFlee: Bool { phase == .combat && !arenaReturning && time - arenaStart >= Game.fleeAfter }
    /// Sekunden, bis man abdrehen darf (nil, wenn schon möglich oder kein Gefecht)
    var fleeCountdown: Int? {
        guard phase == .combat, !arenaReturning else { return nil }
        let left = Game.fleeAfter - (time - arenaStart)
        return left > 0 ? Int(left.rounded(.up)) : nil
    }

    /// Statuszeile im Gefecht
    var combatStatus: String {
        if arenaReturning { return arenaWon ? "GEFECHT GEWONNEN · ZURÜCK IN DEN ORBIT" : "ABGEDREHT · ZURÜCK IN DEN ORBIT" }
        if arenaNextWaveAt != nil { return "NÄCHSTE WELLE IM ANFLUG" }
        let n = arenaRaiders
        let wave = arenaWaves.count > 1 ? " · WELLE \(arenaWave + 1)/\(arenaWaves.count)" : ""
        return "GEFECHT\(wave) · \(n) \(n == 1 ? "PIRAT" : "PIRATEN")"
    }

    /// Wellen je Gefechtsart; Patrouillen verteilen ihre Piraten auf mehrere Wellen
    func arenaWaveList(_ kind: ArenaKind) -> [[Int]] {
        let tier = contracts.active?.tier ?? 0
        let lvl = level
        switch kind {
        case .ambush:
            let first: [Int] = [0, 0] + (lvl > 0.3 ? [1] : [])
            return lvl > 0.5 ? [first, [0, 1]] : [first]
        case .patrol:
            var left = contracts.active?.kind == .patrol ? max(3, contracts.active?.kills ?? 4) : 4
            var waves: [[Int]] = []
            while left > 0 {
                let n = min(left, waves.isEmpty ? 3 : 3)
                waves.append((0..<n).map { j in !waves.isEmpty && j == 0 ? 1 : 0 })
                left -= n
            }
            return waves
        case .boss:
            return [[0, 0, 1], [0, 1] + (lvl > 0.5 ? [0] : []), tier >= 3 ? [2, 1, 0, 0] : [2, 0, 0]]
        }
    }

    /// Gefechtsplanet erreicht: Schiff löst sich aus dem Fang und das Gefecht beginnt
    func startArena(_ index: Int) {
        arenaIndex = index
        arenaKind = planets[index].arena ?? .ambush
        arenaStart = time
        arenaWave = 0
        arenaWaves = arenaWaveList(arenaKind)
        arenaNextWaveAt = nil
        arenaReturning = false
        arenaWon = false
        steerAngle = nil
        fireHeld = false
        combatBank = 0
        // Schwung aus dem Anflug mitnehmen
        let sp = hypot(vel.dx, vel.dy)
        if sp > 1 { heading = atan2(vel.dy, vel.dx) }
        combatSpeed = max(combatCruise, min(sp, combatTop))
        vel = CGVector(dx: cos(heading) * combatSpeed, dy: sin(heading) * combatSpeed)
        cameraLock = nil
        techFocus = 0
        enemyShots.removeAll()
        phase = .combat
        spawnArenaWave()
        popups.append(Popup(pos: pos, text: "GEFECHT · \(arenaKind.title)", color: Color(red: 1, green: 0.4, blue: 0.35), age: 0, lift: 60))
        shake = max(shake, 0.35)
        Haptics.launch(0.8)
        SoundFX.shared.play(.warning)
        blog("arena start idx=\(index) kind=\(arenaKind) waves=\(arenaWaves)")
    }

    /// Nächste Welle fliegt von außerhalb des Bildes heran
    func spawnArenaWave() {
        guard arenaWaves.indices.contains(arenaWave) else { return }
        let tier = contracts.active?.tier ?? 0
        let list = arenaWaves[arenaWave]
        let from = CGFloat.random(in: 0...(2 * .pi))
        for (k, v) in list.enumerated() {
            let st = Raider.stats(v, lvl: level, tier: tier)
            let ang = from + CGFloat(k) * 0.4
            let c = point(from: pos, angle: ang, distance: 1050 + 70 * CGFloat(k))
            var a = Asteroid(center: c, radius: Raider.radius(v), shape: Array(repeating: 1, count: 9),
                             spin: 0, phase: CGFloat.random(in: 0...(2 * .pi)),
                             tone: 0.5, gap: arenaIndex, kind: .raider, hp: st.hp, maxHP: st.hp)
            a.variant = v
            a.shield = st.shield
            a.maxShield = st.shield
            a.burstLeft = Raider.burstCount(v)
            a.awake = true
            a.fireAt = time + 1.6 + CGFloat.random(in: 0...1)
            a.orbitR = CGFloat.random(in: 300...480) + 40 * CGFloat(v)
            a.orbitW = (Bool.random() ? 1 : -1) * CGFloat.random(in: 0.5...0.85)
            a.orbitA = atan2(c.y - pos.y, c.x - pos.x)
            a.ringChangeAt = time + CGFloat.random(in: 3...5)
            a.facing = atan2(pos.y - c.y, pos.x - c.x)
            asteroids.append(a)
        }
        if list.contains(2) {
            popups.append(Popup(pos: pos, text: "\(bountyName) GREIFT AN", color: Color(red: 1, green: 0.4, blue: 0.35), age: 0, lift: 90))
            shake = max(shake, 0.25)
        } else if arenaWave > 0 {
            popups.append(Popup(pos: pos, text: "WELLE \(arenaWave + 1) VON \(arenaWaves.count)", color: Color(red: 1, green: 0.55, blue: 0.4), age: 0, lift: 60))
        }
    }

    /// Finger auf dem Bildschirm: dorthin lenken (Bildschirmrichtung vom Schiff aus in Weltrichtung umrechnen)
    func steer(toward p: CGPoint) {
        guard phase == .combat, !arenaReturning, !paused, let project,
              let s = project(pos),
              let ex = project(CGPoint(x: pos.x + 200, y: pos.y)),
              let ey = project(CGPoint(x: pos.x, y: pos.y + 200)) else { return }
        let fx = p.x - s.x, fy = p.y - s.y
        guard hypot(fx, fy) > 14 else { return }
        let ax = ex.x - s.x, ay = ex.y - s.y, bx = ey.x - s.x, by = ey.y - s.y
        let det = ax * by - bx * ay
        guard abs(det) > 0.0001 else { return }
        let u = (fx * by - bx * fy) / det
        let v = (ax * fy - ay * fx) / det
        steerAngle = atan2(v, u)
    }

    /// Abdrehen: Gefecht verlassen und zurück in den Orbit (die Piraten entkommen)
    func flee() {
        guard canFlee else { return }
        endArena(won: false)
    }

    /// Ein Schritt im Gefecht: lenken, Schub, Deckung am Planeten, Rammstöße, Dauerfeuer, Wellen
    func simulateCombat(_ dt: CGFloat) {
        guard planets.indices.contains(arenaIndex) else {
            phase = .flying
            return
        }
        let p = planets[arenaIndex]
        let toC = CGVector(dx: p.center.x - pos.x, dy: p.center.y - pos.y)
        let dc = max(1, hypot(toC.dx, toC.dy))
        var want = steerAngle
        var throttle = steerAngle != nil
        // Testflüge: auf den nächsten Piraten zu und feuern
        if (Game.autopilot || Game.bot) && !arenaReturning {
            let foe = asteroids.filter { $0.kind == .raider && !$0.retreating }
                .min { hypot($0.center.x - pos.x, $0.center.y - pos.y) < hypot($1.center.x - pos.x, $1.center.y - pos.y) }
            if let f = foe { want = atan2(f.center.y - pos.y, f.center.x - pos.x) }
            throttle = true
            fireHeld = foe != nil && energy > weaponCost + 10
        }
        if arenaReturning {
            // zurück auf die Bahn: auf den Tangentenpunkt zu, wie die Lenkhilfe im normalen Flug
            let phi = atan2(toC.dy, toC.dx)
            let al = asin(min(1, p.orbitRadius / max(dc, p.orbitRadius * 1.01)))
            let a1 = phi + al, a2 = phi - al
            want = abs(wrap(a1 - heading)) < abs(wrap(a2 - heading)) ? a1 : a2
            throttle = true
            if dc < p.orbitRadius + 30 {
                arenaReturning = false
                capture(arenaIndex, dx: pos.x - p.center.x, dy: pos.y - p.center.y)
                arenaIndex = -1
                steerAngle = nil
                fireHeld = false
                return
            }
        } else if dc > p.orbitRadius + Game.arenaReach {
            // Rand des Gefechtsfelds: zurück zum Planeten
            want = atan2(toC.dy, toC.dx)
            if time - boundaryWarnAt > 3 {
                boundaryWarnAt = time
                popups.append(Popup(pos: pos, text: "RAND DES GEFECHTSFELDS", color: Color(red: 1, green: 0.6, blue: 0.4), age: 0))
            }
        }
        if let w = want {
            let turn = combatTurn
            let d = wrap(w - heading)
            heading += max(-turn * dt, min(turn * dt, d))
            combatBank += (max(-1, min(1, d * 1.4)) - combatBank) * min(1, dt * 6)
        } else {
            combatBank += (0 - combatBank) * min(1, dt * 4)
        }
        let target = throttle ? combatTop : combatCruise
        combatSpeed += (target - combatSpeed) * min(1, dt * 1.6)
        vel = CGVector(dx: cos(heading) * combatSpeed, dy: sin(heading) * combatSpeed)
        pos.x += vel.dx * dt
        pos.y += vel.dy * dt

        // Planet: abprallen statt hindurchfliegen
        let ox = pos.x - p.center.x, oy = pos.y - p.center.y
        let od = max(1, hypot(ox, oy))
        let skin = p.radius + 22
        if od < skin {
            let nx = ox / od, ny = oy / od
            pos = CGPoint(x: p.center.x + nx * skin, y: p.center.y + ny * skin)
            let vx = cos(heading), vy = sin(heading)
            let dot = vx * nx + vy * ny
            if dot < 0 { heading = atan2(vy - 2 * dot * ny, vx - 2 * dot * nx) }
            combatSpeed *= 0.6
            if time - planetBumpAt > 0.8 {
                planetBumpAt = time
                let damage = takeHit(10, armorFactor: 0.7)
                popups.append(Popup(pos: pos, text: damage > 0 ? "PLANETENKONTAKT -\(Int(damage))" : "ABGEPRALLT",
                                    color: Color(red: 0.8, green: 0.75, blue: 0.7), age: 0))
                shake = max(shake, 0.3)
                Haptics.miss()
                SoundFX.shared.play(.hit)
            }
        }
        // Rammstöße mit Piraten
        for i in asteroids.indices.reversed() where asteroids[i].kind == .raider {
            let a = asteroids[i]
            if time >= a.bumpUntil && hypot(a.center.x - pos.x, a.center.y - pos.y) < a.radius + 10 {
                hitAsteroid(i)
                combatSpeed *= 0.6
                break
            }
        }
        // Bordgenerator lädt im Gefecht langsam nach, damit man nicht ohne Waffe dasteht
        if !arenaReturning { energy = min(maxEnergy, energy + 3 * dt) }
        // Dauerfeuer, solange der Knopf gedrückt ist (ohne Energie nur ab und zu ein Hinweis)
        if fireHeld && !arenaReturning && weaponCooldown <= 0 && (energy > weaponCost || noEnergyFlash <= 0) { fire() }
        updateArena()
    }

    /// Wellen nachschicken, bis alle besiegt sind
    private func updateArena() {
        guard !arenaReturning, arenaRaiders == 0 else { return }
        if let t = arenaNextWaveAt {
            if time >= t {
                arenaNextWaveAt = nil
                spawnArenaWave()
            }
        } else if arenaWave + 1 < arenaWaves.count {
            arenaWave += 1
            arenaNextWaveAt = time + 2
            popups.append(Popup(pos: pos, text: "NÄCHSTE WELLE IM ANFLUG", color: Color(red: 1, green: 0.55, blue: 0.4), age: 0, lift: 30))
        } else {
            endArena(won: true)
        }
    }

    /// Gefecht vorbei: Belohnung oder Rückzug, dann fliegt das Schiff von selbst zurück in den Orbit
    func endArena(won: Bool) {
        arenaReturning = true
        arenaWon = won
        steerAngle = nil
        fireHeld = false
        if won {
            let bonus = max(1, Int((CGFloat(1 + arenaWaves.count) * ship.bountyFactor).rounded()))
            for _ in 0..<bonus { spawnTech(from: pos) }
            addEnergy(30, from: pos)
            popups.append(Popup(pos: pos, text: "GEFECHT GEWONNEN · +\(bonus) TECH", color: Color(red: 1, green: 0.85, blue: 0.42), age: 0, lift: 50))
            waves.append(Wave(center: pos, r0: 20, age: 0, maxAge: 0.9, hue: 48))
            burst(at: pos, count: 40, hue: 48, speed: 280, life: 1.0)
            Haptics.bonus()
            SoundFX.shared.play(.bonus)
            if arenaKind == .patrol { patrolCleared() }
        } else {
            for i in asteroids.indices where asteroids[i].kind == .raider && asteroids[i].gap == arenaIndex {
                asteroids[i].retreating = true
            }
            popups.append(Popup(pos: pos, text: "ABGEDREHT · DIE PIRATEN ENTKOMMEN", color: Color(red: 1, green: 0.55, blue: 0.4), age: 0, lift: 40))
            if arenaKind != .ambush { contractTargetEscaped() }
        }
        blog("arena end won=\(won)")
    }

    // MARK: Piraten im Gefecht

    /// Piraten kreisen um das Schiff, wechseln die Bahn und setzen zu dichten Angriffsflügen an.
    /// Sie feuern Salven, sobald das Schiff vor ihrem Bug liegt und kein Planet dazwischen ist.
    func moveRaiders(_ dt: CGFloat) {
        var gone: [Int] = []
        for i in asteroids.indices where asteroids[i].kind == .raider {
            var a = asteroids[i]
            let c = a.center
            let dx = pos.x - c.x, dy = pos.y - c.y
            let d = max(1, hypot(dx, dy))
            let fighting = phase == .combat && a.gap == arenaIndex && !arenaReturning
            if !fighting { a.retreating = true }
            let planet = planets[max(0, min(a.gap, planets.count - 1))]

            var want: CGVector
            if a.retreating {
                want = CGVector(dx: -dx / d * 640, dy: -dy / d * 640)
                if d > 2400 { gone.append(a.uid) }
            } else {
                if time >= a.ringChangeAt {
                    a.ringChangeAt = time + CGFloat.random(in: 3.5...6)
                    if a.variant != 2 && Double.random(in: 0...1) < 0.4 {
                        a.diveUntil = time + 1.8   // Angriffsflug dicht am Schiff vorbei
                    } else {
                        a.orbitR = CGFloat.random(in: 300...500) + 40 * CGFloat(a.variant)
                    }
                    if Double.random(in: 0...1) < 0.3 { a.orbitW = -a.orbitW }
                }
                a.orbitA += a.orbitW * dt
                let r: CGFloat = time < a.diveUntil ? 130 : a.orbitR
                let target = point(from: pos, angle: a.orbitA, distance: r)
                var vx = vel.dx + (target.x - c.x) * 1.8
                var vy = vel.dy + (target.y - c.y) * 1.8
                // ausweichen, wenn das Schiff direkt auf sie zielt (Haken quer zur Schusslinie)
                let aimedAt = abs(wrap(atan2(-dy, -dx) - heading)) < 0.3 && d < 750
                if aimedAt {
                    let side: CGFloat = sin(time * 1.7 + a.phase) > 0 ? 1 : -1
                    vx += -dy / d * 300 * side
                    vy += dx / d * 300 * side
                }
                // nicht rammen
                if d < 110 {
                    vx -= dx / d * 380
                    vy -= dy / d * 380
                }
                // nicht in den Planeten
                let px = c.x - planet.center.x, py = c.y - planet.center.y
                let pd = max(1, hypot(px, py))
                if pd < planet.radius + a.radius + 40 {
                    vx += px / pd * 420
                    vy += py / pd * 420
                }
                let cap = combatTop + Raider.speedBonus(a.variant)
                let vl = hypot(vx, vy)
                if vl > cap {
                    vx = vx / vl * cap
                    vy = vy / vl * cap
                }
                want = CGVector(dx: vx, dy: vy)
            }
            let k = min(1, dt * 3.2)
            a.vel.dx += (want.dx - a.vel.dx) * k
            a.vel.dy += (want.dy - a.vel.dy) * k

            // Bug: im Kampf zum Schiff, sonst in Flugrichtung
            let toShip = atan2(dy, dx)
            let moving = hypot(a.vel.dx, a.vel.dy) > 40
            let look: CGFloat = !a.retreating && d < 1500 ? toShip : (moving ? atan2(a.vel.dy, a.vel.dx) : a.facing)
            a.facing += max(-4.5 * dt, min(4.5 * dt, wrap(look - a.facing)))

            // Schilde laden nach 2,5 s ohne Treffer wieder auf
            if a.shield < a.maxShield && time - a.hitAt > 2.5 {
                a.shield = min(a.maxShield, a.shield + a.maxShield * 0.35 * dt)
            }
            // Salven, sobald das Schiff vor dem Bug liegt und der Planet nicht dazwischen ist
            if fighting && !a.retreating && d < Raider.range && abs(wrap(toShip - a.facing)) < 0.45 && time >= a.fireAt
                && distanceToSegment(planet.center, c, pos) > planet.radius {
                fireRaiderShot(&a, dist: d)
            }
            asteroids[i] = a
        }
        for uid in gone {
            asteroids.removeAll { $0.uid == uid }
        }
    }

    /// Ein Schuss der Salve mit Vorhalt. Schnelle Schiffe sind schwer zu treffen: die Streuung wächst mit dem Tempo
    /// des Spielerschiffs. Der Anführer feuert kleine Fächer.
    private func fireRaiderShot(_ a: inout Asteroid, dist: CGFloat) {
        let muzzle = point(from: a.center, angle: a.facing, distance: a.radius)
        let lead = dist / (Raider.shotSpeed + 250)
        let base = atan2(pos.y + vel.dy * lead - muzzle.y, pos.x + vel.dx * lead - muzzle.x)
        let spread = 0.05 + 0.14 * max(0, ship.speed - 0.8)
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
            a.fireAt = time + CGFloat.random(in: 1.2...1.9) + (a.variant == 1 ? 0.3 : 0)
        }
    }

    /// Treffer auf ein Piratenschiff. Kanonen-Dauerfeuer zerschlägt Schilde besonders gut, Explosionen weichen
    /// die wendigen Schiffe teilweise aus. Der Schild fängt zuerst ab, danach geht es auf den Rumpf.
    func damageRaider(_ i: Int, _ base: CGFloat, blast: Bool) {
        guard asteroids.indices.contains(i), asteroids[i].kind == .raider else { return }
        let weaponFactor: CGFloat = blast ? 0.6 : (weapon == .cannon ? 1.6 : 1)
        var dmg = base * weaponDamageFactor * weaponFactor * ship.shipDamageFactor
        asteroids[i].hitAt = time
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
        if Double.random(in: 0...1) < 0.5 { spawnTech(from: a.center, kind: .energy) }
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
