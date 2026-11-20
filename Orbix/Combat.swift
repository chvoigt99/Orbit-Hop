import SwiftUI

// MARK: - Piratenschiffe

/// Werte der drei Piratenklassen: 0 leichter Jäger, 1 Kanonenboot, 2 Anführer (Kopfgeldziel)
enum Raider {
    private static func pick<T>(_ v: Int, _ values: [T]) -> T { values[max(0, min(values.count - 1, v))] }
    static func radius(_ v: Int) -> CGFloat { pick(v, [24, 30, 40] as [CGFloat]) }
    /// so viel schneller als das Spielerschiff dürfen sie werden
    static func speedBonus(_ v: Int) -> CGFloat { pick(v, [35, 10, 25] as [CGFloat]) }
    static func shotDamage(_ v: Int) -> CGFloat { pick(v, [5, 6, 9] as [CGFloat]) }
    static func burstCount(_ v: Int) -> Int { pick(v, [2, 3, 3]) }
    static func title(_ v: Int) -> String { pick(v, ["PIRAT", "KANONENBOOT", "ANFÜHRER"]) }
    /// langsam genug, dass man die Schüsse kommen sieht und ausweichen kann
    static let shotSpeed: CGFloat = 360
    static let range: CGFloat = 850

    /// Rumpf und Schild je Klasse, Schwierigkeit und Auftragsstufe
    static func stats(_ v: Int, lvl: CGFloat, tier: Int) -> (hp: Int, shield: CGFloat) {
        switch v {
        // zäh: Gefechte sollen eine Herausforderung sein (Christian, 2026-11-20)
        case 2: return (60 + Int(30 * lvl) + 8 * tier, 30 + 15 * lvl + 4 * CGFloat(tier))
        case 1: return (22 + Int(12 * lvl) + 2 * tier, 14 + 6 * lvl + CGFloat(tier))
        default: return (14 + Int(6 * lvl) + tier, 8 + 4 * lvl)
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

    // ruhiges Tempo, damit man zielen und taktieren kann statt Autoscooter zu fahren (Christian, 2026-11-20)
    var combatCruise: CGFloat { 110 * ship.speed }
    var combatTop: CGFloat { 150 * ship.speed }
    /// schnelle Schiffe sind auch wendiger
    var combatTurn: CGFloat { 1.25 + 0.8 * max(0, ship.speed - 0.8) }

    /// Bordkanonen: im Gefecht immer verfügbar, ohne Energie; Jäger mit starken Kanonen treffen härter
    static let boardShotSpeed: CGFloat = 900
    static let boardCooldown: CGFloat = 0.16

    func fireBoardCannons() {
        weaponCooldown = Game.boardCooldown * ship.weaponReloadFactor
        let muzzle = point(from: pos, angle: heading, distance: 30)
        let target = aimTarget()
        var hd = heading
        var valt = sin(climb) * Game.boardShotSpeed
        if let t = target {
            let d = max(1, hypot(t.center.x - muzzle.x, t.center.y - muzzle.y))
            let lead = d / Game.boardShotSpeed
            let want = atan2(t.center.y + t.vel.dy * lead - muzzle.y, t.center.x + t.vel.dx * lead - muzzle.x)
            // Zielhilfe nur in einem Kegel voraus: anfliegen muss man selbst
            let limit = min(0.45, 0.22 * ship.aimAssistFactor)
            hd = heading + max(-limit, min(limit, wrap(want - heading)))
            let dAlt = t.alt - altitude
            if abs(dAlt) < d * 0.5 { valt = dAlt / lead }
        }
        let fwd = CGVector(dx: cos(hd), dy: sin(hd))
        let v = CGVector(dx: fwd.dx * Game.boardShotSpeed + vel.dx, dy: fwd.dy * Game.boardShotSpeed + vel.dy)
        let sides: [CGFloat] = ship.twinCannon ? [-1, 1] : [0]
        for side in sides {
            let m = CGPoint(x: muzzle.x - fwd.dy * 9 * side, y: muzzle.y + fwd.dx * 9 * side)
            var pr = Projectile(kind: .cannon, p: m, v: v, maxAge: 1.25 * rangeFactor, target: target?.uid)
            pr.alt = altitude
            pr.valt = valt
            projectiles.append(pr)
        }
        Haptics.launch(0.2)
        SoundFX.shared.play(.cannon, volume: 0.6)
    }

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
        let h = Int((altitude / 10).rounded()) * 10
        return "GEFECHT\(wave) · \(n) \(n == 1 ? "PIRAT" : "PIRATEN") · HÖHE \(h > 0 ? "+" : "")\(h)"
    }

    /// Wellen je Gefechtsart; Patrouillen verteilen ihre Piraten auf mehrere Wellen
    func arenaWaveList(_ kind: ArenaKind) -> [[Int]] {
        let tier = contracts.active?.tier ?? 0
        let lvl = level
        switch kind {
        case .ambush:
            let first: [Int] = [0, 0, 1]
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
        stick = nil
        fireHeld = false
        combatBank = 0
        altitude = 0
        climb = 0
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
        popups.append(Popup(pos: pos, text: "GEFECHT · \(arenaKind.title) · BORDKANONEN AKTIV", color: Color(red: 1, green: 0.4, blue: 0.35), age: 0, lift: 60))
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
        // von vorn, damit man sie in der Verfolgerkamera anfliegen sieht
        let from = heading + CGFloat.random(in: -0.5...0.5)
        for (k, v) in list.enumerated() {
            let st = Raider.stats(v, lvl: level, tier: tier)
            let ang = from + (CGFloat(k) - CGFloat(list.count - 1) / 2) * 0.25
            let c = point(from: pos, angle: ang, distance: 1200 + 90 * CGFloat(k))
            var a = Asteroid(center: c, radius: Raider.radius(v), shape: Array(repeating: 1, count: 9),
                             spin: 0, phase: CGFloat.random(in: 0...(2 * .pi)),
                             tone: 0.5, gap: arenaIndex, kind: .raider, hp: st.hp, maxHP: st.hp)
            a.variant = v
            a.shield = st.shield
            a.maxShield = st.shield
            a.burstLeft = Raider.burstCount(v)
            a.awake = true
            a.fireAt = time + 2.5 + CGFloat.random(in: 0...1.5)
            a.orbitR = CGFloat.random(in: 520...760) + 50 * CGFloat(v)
            a.orbitW = (Bool.random() ? 1 : -1) * CGFloat.random(in: 0.25...0.45)
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

    /// Höchster Abstand über bzw. unter der Bahnebene im Gefecht
    static let altLimit: CGFloat = 380
    /// größter Steigwinkel
    static let maxClimb: CGFloat = 0.7

    /// Steuerknüppel: Finger zieht vom Aufsetzpunkt weg. Seitlich lenkt, hoch/runter steigt bzw. sinkt.
    /// Die Seite wird über die Kamera bestimmt, damit „nach rechts ziehen“ auf dem Bildschirm rechts herum fliegt.
    func setStick(from start: CGPoint, to p: CGPoint) {
        guard phase == .combat, !arenaReturning, !paused else { return }
        var sx = max(-1, min(1, (p.x - start.x) / 90))
        let sy = max(-1, min(1, (p.y - start.y) / 90))
        if let project3, let s = project3(pos, altitude),
           let side = project3(point(from: pos, angle: heading + .pi / 2, distance: 60), altitude), side.x < s.x {
            sx = -sx
        }
        stick = CGVector(dx: sx, dy: sy)
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
        // Lenkung: Steuerknüppel (Gierrate und Steigwinkel) oder ein Wunschkurs (Testflug, Rückkehr, Rand)
        var want: CGFloat? = nil
        var yaw: CGFloat = stick.map { $0.dx } ?? 0
        var climbWant: CGFloat = stick.map { -$0.dy * Game.maxClimb } ?? 0
        var throttle = stick != nil
        // Testflüge: auf den nächsten Piraten zu (auch in der Höhe) und feuern
        if (Game.autopilot || Game.bot) && !arenaReturning {
            let foe = asteroids.filter { $0.kind == .raider && !$0.retreating }
                .min { hypot($0.center.x - pos.x, $0.center.y - pos.y) < hypot($1.center.x - pos.x, $1.center.y - pos.y) }
            if let f = foe {
                want = atan2(f.center.y - pos.y, f.center.x - pos.x)
                let d = max(1, hypot(f.center.x - pos.x, f.center.y - pos.y))
                climbWant = max(-Game.maxClimb, min(Game.maxClimb, atan2(f.alt - altitude, d)))
            }
            throttle = true
            fireHeld = foe != nil
        }
        if arenaReturning {
            // zurück auf die Bahn: auf den Tangentenpunkt zu, wie die Lenkhilfe im normalen Flug, und zurück auf Höhe 0
            let phi = atan2(toC.dy, toC.dx)
            let al = asin(min(1, p.orbitRadius / max(dc, p.orbitRadius * 1.01)))
            let a1 = phi + al, a2 = phi - al
            want = abs(wrap(a1 - heading)) < abs(wrap(a2 - heading)) ? a1 : a2
            climbWant = max(-0.5, min(0.5, -altitude / 250))
            throttle = true
            if dc < p.orbitRadius + 30 && abs(altitude) < 25 {
                arenaReturning = false
                altitude = 0
                climb = 0
                stick = nil
                capture(arenaIndex, dx: pos.x - p.center.x, dy: pos.y - p.center.y)
                arenaIndex = -1
                fireHeld = false
                return
            }
            if dc < p.orbitRadius + 30 { want = heading }   // auf Höhe warten, Bahn halten
        } else if dc > p.orbitRadius + Game.arenaReach {
            // Rand des Gefechtsfelds: zurück zum Planeten
            want = atan2(toC.dy, toC.dx)
            if time - boundaryWarnAt > 3 {
                boundaryWarnAt = time
                popups.append(Popup(pos: pos, text: "RAND DES GEFECHTSFELDS", color: Color(red: 1, green: 0.6, blue: 0.4), age: 0))
            }
        }
        // Höhengrenze: sanft zurückdrücken
        if abs(altitude) > Game.altLimit {
            climbWant = altitude > 0 ? -0.4 : 0.4
            if time - boundaryWarnAt > 3 {
                boundaryWarnAt = time
                popups.append(Popup(pos: pos, text: "RAND DES GEFECHTSFELDS", color: Color(red: 1, green: 0.6, blue: 0.4), age: 0))
            }
        }
        let turn = combatTurn
        if let w = want {
            yaw = max(-1, min(1, wrap(w - heading) * 2.5))
        }
        // weich einlenken statt ruckartig
        combatBank += (yaw - combatBank) * min(1, dt * 4)
        heading += combatBank * turn * dt
        climb += (climbWant - climb) * min(1, dt * 2.2)
        let target = throttle ? combatTop : combatCruise
        combatSpeed += (target - combatSpeed) * min(1, dt * 1.2)
        let flat = combatSpeed * cos(climb)
        vel = CGVector(dx: cos(heading) * flat, dy: sin(heading) * flat)
        pos.x += vel.dx * dt
        pos.y += vel.dy * dt
        altitude += sin(climb) * combatSpeed * dt

        // Planet (Kugel): abprallen statt hindurchfliegen
        let ox = pos.x - p.center.x, oy = pos.y - p.center.y
        let od3 = max(1, sqrt(ox * ox + oy * oy + altitude * altitude))
        let skin = p.radius + 22
        if od3 < skin {
            let nx = ox / od3, ny = oy / od3, nz = altitude / od3
            pos = CGPoint(x: p.center.x + nx * skin, y: p.center.y + ny * skin)
            altitude = nz * skin
            let vx = cos(heading), vy = sin(heading)
            let dot = vx * nx + vy * ny
            if dot < 0 { heading = atan2(vy - 2 * dot * ny, vx - 2 * dot * nx) }
            if nz * climb < 0 { climb = -climb }
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
            if time >= a.bumpUntil && hypot(a.center.x - pos.x, a.center.y - pos.y) < a.radius + 10 && abs(a.alt - altitude) < a.radius + 10 {
                hitAsteroid(i)
                combatSpeed *= 0.6
                break
            }
        }
        // Bordgenerator lädt im Gefecht langsam nach
        if !arenaReturning { energy = min(maxEnergy, energy + 2 * dt) }
        // Dauerfeuer, solange der Knopf gedrückt ist (ohne Energie nur ab und zu ein Hinweis)
        if fireHeld && !arenaReturning && weaponCooldown <= 0 { fire() }
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
        stick = nil
        fireHeld = false
        if won {
            enemyShots.removeAll()   // nach dem Sieg trifft nichts mehr nach
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
            var altTarget = a.alt
            if a.retreating {
                want = CGVector(dx: -dx / d * 640, dy: -dy / d * 640)
                if d > 2400 { gone.append(a.uid) }
            } else {
                // Abstand halten statt rammen: Die Piraten stehen in 500–800 Abstand, weben seitlich und weichen
                // ab und zu weit zur Seite aus (Flankenmanöver), sodass man ihnen nachdrehen muss (Christian, 2026-11-20)
                if time >= a.ringChangeAt {
                    a.ringChangeAt = time + CGFloat.random(in: 4...7)
                    if Double.random(in: 0...1) < 0.35 {
                        a.diveUntil = time + CGFloat.random(in: 2.5...4)   // Flankenmanöver
                        a.orbitW = -a.orbitW
                    } else {
                        a.orbitR = CGFloat.random(in: 520...780) + 50 * CGFloat(a.variant)
                    }
                }
                a.orbitA += a.orbitW * dt
                let flanking = time < a.diveUntil
                let offset: CGFloat = flanking ? (a.orbitW > 0 ? 1.25 : -1.25) : 0.5 * sin(a.orbitA)
                let target = point(from: pos, angle: heading + offset, distance: a.orbitR)
                altTarget = altitude + 110 * sin(a.orbitA * 0.8 + a.phase)
                var vx = vel.dx + (target.x - c.x) * 0.9
                var vy = vel.dy + (target.y - c.y) * 0.9
                // ausweichen, wenn das Schiff direkt auf sie zielt (Haken quer zur Schusslinie)
                let aimedAt = abs(wrap(atan2(-dy, -dx) - heading)) < 0.25 && d < 700
                if aimedAt {
                    let side: CGFloat = sin(time * 0.9 + a.phase) > 0 ? 1 : -1
                    vx += -dy / d * 110 * side
                    vy += dx / d * 110 * side
                }
                // Mindestabstand zum Spielerschiff
                if d < 380 {
                    let push = 320 * (1 - d / 380) + 60
                    vx -= dx / d * push
                    vy -= dy / d * push
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
            a.alt += max(-110, min(110, (altTarget - a.alt) * 1.0)) * dt
            let k = min(1, dt * 2.0)
            a.vel.dx += (want.dx - a.vel.dx) * k
            a.vel.dy += (want.dy - a.vel.dy) * k

            // Bug: im Kampf zum Schiff, sonst in Flugrichtung
            let toShip = atan2(dy, dx)
            let moving = hypot(a.vel.dx, a.vel.dy) > 40
            let look: CGFloat = !a.retreating && d < 1500 ? toShip : (moving ? atan2(a.vel.dy, a.vel.dx) : a.facing)
            a.facing += max(-2.5 * dt, min(2.5 * dt, wrap(look - a.facing)))

            // Schilde laden nach 2,5 s ohne Treffer wieder auf
            if a.shield < a.maxShield && time - a.hitAt > 2.5 {
                a.shield = min(a.maxShield, a.shield + a.maxShield * 0.35 * dt)
            }
            // Salven, sobald das Schiff vor dem Bug liegt und der Planet nicht dazwischen ist
            if fighting && !a.retreating && d < Raider.range && abs(wrap(toShip - a.facing)) < 0.45 && time >= a.fireAt
                && abs(altitude - a.alt) < d * 0.55
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
        let lead = dist / (Raider.shotSpeed + 120)
        let base = atan2(pos.y + vel.dy * lead - muzzle.y, pos.x + vel.dx * lead - muzzle.x)
        let spread = 0.1 + 0.14 * max(0, ship.speed - 0.8)
        let count = a.variant == 2 ? 3 : 1
        for k in 0..<count {
            let off = count == 1 ? 0 : (CGFloat(k) - 1) * 0.13
            let ang = base + off + CGFloat.random(in: -spread...spread)
            // Höhe: auf die Schiffshöhe mit Vorhalt der Steigrate, leicht gestreut
            let flight = max(0.1, dist / Raider.shotSpeed)
            let aimAlt = altitude + sin(climb) * combatSpeed * flight * 0.8 + CGFloat.random(in: -18...18)
            enemyShots.append(EnemyShot(p: muzzle, v: CGVector(dx: cos(ang) * Raider.shotSpeed, dy: sin(ang) * Raider.shotSpeed),
                                        damage: Raider.shotDamage(a.variant), raider: true,
                                        alt: a.alt, valt: (aimAlt - a.alt) / flight))
        }
        a.burstLeft -= 1
        if a.burstLeft > 0 {
            a.fireAt = time + 0.25
        } else {
            a.burstLeft = Raider.burstCount(a.variant)
            a.fireAt = time + CGFloat.random(in: 2.4...3.4) + (a.variant == 1 ? 0.3 : 0)
        }
    }

    /// Treffer auf ein Piratenschiff. Kanonen-Dauerfeuer zerschlägt Schilde besonders gut, Explosionen weichen
    /// die wendigen Schiffe teilweise aus. Der Schild fängt zuerst ab, danach geht es auf den Rumpf.
    func damageRaider(_ i: Int, _ base: CGFloat, blast: Bool) {
        guard asteroids.indices.contains(i), asteroids[i].kind == .raider else { return }
        let weaponFactor: CGFloat = blast ? 0.6 : (phase == .combat ? 1.3 : (weapon == .cannon ? 1.6 : 1))
        var dmg = base * weaponDamageFactor * weaponFactor * ship.shipDamageFactor
        asteroids[i].hitAt = time
        let c = asteroids[i].center
        if asteroids[i].shield > 0 {
            let absorbed = min(asteroids[i].shield, dmg)
            asteroids[i].shield -= absorbed
            dmg -= absorbed
            burst(at: c, count: 8, hue: 200, speed: 170, life: 0.4, alt: asteroids[i].alt)
        }
        // Bruchteile zählen als Zufall, damit auch kleine Treffer wirken
        var whole = Int(dmg)
        if CGFloat.random(in: 0...1) < dmg - CGFloat(whole) { whole += 1 }
        guard whole > 0 else { return }
        asteroids[i].hp -= whole
        if asteroids[i].hp <= 0 {
            destroyAsteroid(i, blast: blast)
        } else {
            burst(at: c, count: 10, hue: 25, speed: 190, life: 0.5, alt: asteroids.indices.contains(i) ? asteroids[i].alt : 0)
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
        burst(at: a.center, count: Int(50 * big), hue: 18, speed: 340 * big, life: 1.0, alt: a.alt)
        burst(at: a.center, count: Int(26 * big), hue: 40, speed: 170 * big, life: 1.3, alt: a.alt)
        burst(at: a.center, count: Int(14 * big), hue: 200, speed: 260, life: 0.6, alt: a.alt)
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
