import SwiftUI

// MARK: - Zeichnen

extension Game {
    private var signal: Color { Color(red: 79 / 255, green: 227 / 255, blue: 193 / 255) }
    private var holo: Color { Color(red: 0.45, green: 0.85, blue: 1) }
    private var amber: Color { Color(red: 1, green: 0.78, blue: 0.4) }
    private var panel: Color { Color(red: 0.02, green: 0.07, blue: 0.11) }

    /// Markierungen, die auf 3D-Objekten sitzen: laufen mit jedem Bild mit, sonst hinken sie hinterher
    func drawTracked(_ base: GraphicsContext, size: CGSize) {
        guard hudAlpha > 0 else { return }
        var context = base
        context.opacity = Double(hudAlpha)
        drawObstacleHP(context, size)
        drawTargetLabel(context, size)
        if !stationOpen { drawIndicator(context, size) }
        if !stationOpen { drawPopups(context, size) }
        drawCometBanner(context, size)
    }

    /// Komet zerstört: kurzer eisblauer Bildschirmblitz. Die Meldung selbst erscheint wie alle anderen
    /// als Schild an der Stelle des Kometen (Popup), damit sie Explosion und Brocken nicht verdeckt.
    private func drawCometBanner(_ c: GraphicsContext, _ size: CGSize) {
        let t = time - cometKilledAt
        guard t >= 0, t < 0.25, phase != .over else { return }
        let ice = Color(red: 0.6, green: 0.9, blue: 1)
        let a = Double(0.2 * (1 - t / 0.25))
        c.fill(Path(CGRect(origin: .zero, size: size)), with: .color(ice.opacity(a)))
    }

    /// Abtastbalken, Radar und Warnblitze: 30 Bilder pro Sekunde reichen. Beide Ebenen mit jedem Bild
    /// auszuwerten, sprengte zusammen mit dem HUD das Zeitbudget des Hauptthreads.
    func drawChrome(_ base: GraphicsContext, size: CGSize) {
        guard hudAlpha > 0 else { return }
        var context = base
        context.opacity = Double(hudAlpha)
        drawScanBar(context, size)
        // in der Hindernispassage sitzen dort die Ausweichknöpfe
        if !stationOpen && !dodgeAvailable { drawRadar(context, size) }
        drawOverlays(context, size)
    }

    /// Trefferanzeige über Hindernissen, die mehrere Treffer brauchen
    private func drawObstacleHP(_ c: GraphicsContext, _ size: CGSize) {
        for a in asteroids where a.maxHP > 1 {
            guard let sp = project?(CGPoint(x: a.center.x, y: a.center.y)) else { continue }
            guard sp.x > -40, sp.x < size.width + 40, sp.y > insets.top + 120, sp.y < size.height - 120 else { continue }
            let col = a.kind == .comet ? Color(red: 0.55, green: 0.85, blue: 1)
                : (a.kind == .drone ? Color(red: 1, green: 0.35, blue: 0.35) : Color(red: 1, green: 0.6, blue: 0.3))
            let segW: CGFloat = 7
            let total = CGFloat(a.maxHP) * (segW + 2)
            let x0 = sp.x - total / 2
            let y = sp.y - 46
            for k in 0..<a.maxHP {
                let r = CGRect(x: x0 + CGFloat(k) * (segW + 2), y: y, width: segW, height: 5)
                c.fill(Path(r), with: .color(k < a.hp ? col : Color.white.opacity(0.15)))
            }
            c.draw(Text(a.kind.title)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(col),
                   at: CGPoint(x: sp.x, y: y - 4), anchor: .bottom)
        }
    }

    private func toScreen(_ p: CGPoint, _ size: CGSize) -> CGPoint {
        if let s = project?(p) { return s }
        return CGPoint(x: (p.x - cam.x) * camScale + size.width / 2,
                       y: (p.y - cam.y) * camScale + size.height / 2)
    }

    // MARK: Hintergrund

    private func drawBackground(_ c: GraphicsContext, _ size: CGSize) {
        let full = Path(CGRect(origin: .zero, size: size))
        c.fill(full, with: .linearGradient(Gradient(colors: [
            Color(red: 0.035, green: 0.045, blue: 0.11),
            Color(red: 0.012, green: 0.02, blue: 0.05),
            Color(red: 0.045, green: 0.02, blue: 0.08)
        ]), startPoint: .zero, endPoint: CGPoint(x: size.width * 0.3, y: size.height)))

        var add = c
        add.blendMode = .plusLighter

        for (i, nb) in Game.nebulae.enumerated() {
            let rad = nb.r * max(size.width, size.height)
            let nx = mod(nb.x * size.width - cam.x * nb.depth, size.width * 1.6) - size.width * 0.3
            let ny = mod(nb.y * size.height - cam.y * nb.depth, size.height * 1.6) - size.height * 0.3
            let center = CGPoint(x: nx, y: ny)
            add.fill(circlePath(center, rad),
                     with: .radialGradient(Gradient(colors: [hsl(nb.hue, 0.75, 0.4, 0.2),
                                                             hsl(nb.hue + 30, 0.7, 0.3, 0.07),
                                                             hsl(nb.hue + 30, 0.7, 0.3, 0)]),
                                           center: center, startRadius: 0, endRadius: rad))
            let a = CGFloat(i) * 2.1
            let lobe = CGPoint(x: center.x + cos(a) * rad * 0.45, y: center.y + sin(a) * rad * 0.35)
            add.fill(circlePath(lobe, rad * 0.55),
                     with: .radialGradient(Gradient(colors: [hsl(nb.hue - 40, 0.8, 0.5, 0.11),
                                                             hsl(nb.hue - 40, 0.8, 0.5, 0)]),
                                           center: lobe, startRadius: 0, endRadius: rad * 0.55))
        }

        drawGrid(c, size)

        for s in Game.stars {
            let x = mod(s.x * size.width - cam.x * s.depth, size.width)
            let y = mod(s.y * size.height - cam.y * s.depth, size.height)
            let twinkle = 0.7 + 0.3 * sin(time * 2 + s.phase)
            let alpha = Double(s.alpha * twinkle)
            let p = CGPoint(x: x, y: y)
            let tint: Color = s.phase < 1.2 ? Color(red: 1, green: 0.82, blue: 0.68)
                : (s.phase > 5.2 ? Color(red: 0.62, green: 0.78, blue: 1) : Color(red: 0.88, green: 0.92, blue: 1))
            add.fill(circlePath(p, 0.6 + s.depth * 9), with: .color(tint.opacity(alpha)))
            if s.depth > 0.11 {
                add.fill(circlePath(p, 6), with: .radialGradient(Gradient(colors: [tint.opacity(alpha * 0.35), tint.opacity(0)]),
                                                                 center: p, startRadius: 0, endRadius: 6))
                var cross = Path()
                cross.move(to: CGPoint(x: x - 6, y: y))
                cross.addLine(to: CGPoint(x: x + 6, y: y))
                cross.move(to: CGPoint(x: x, y: y - 6))
                cross.addLine(to: CGPoint(x: x, y: y + 6))
                add.stroke(cross, with: .color(tint.opacity(alpha * 0.35)), lineWidth: 0.8)
            }
        }

        drawShootingStar(add, size)
    }

    private func drawGrid(_ c: GraphicsContext, _ size: CGSize) {
        let spacing: CGFloat = 64
        let ox = mod(-cam.x * 0.05, spacing)
        let oy = mod(-cam.y * 0.05, spacing)

        var grid = Path()
        var x = ox
        while x < size.width {
            grid.move(to: CGPoint(x: x, y: 0))
            grid.addLine(to: CGPoint(x: x, y: size.height))
            x += spacing
        }
        var y = oy
        while y < size.height {
            grid.move(to: CGPoint(x: 0, y: y))
            grid.addLine(to: CGPoint(x: size.width, y: y))
            y += spacing
        }
        c.stroke(grid, with: .color(holo.opacity(0.03)), lineWidth: 0.5)

        var nodes = Path()
        x = ox
        while x < size.width {
            y = oy
            while y < size.height {
                nodes.move(to: CGPoint(x: x - 3, y: y))
                nodes.addLine(to: CGPoint(x: x + 3, y: y))
                nodes.move(to: CGPoint(x: x, y: y - 3))
                nodes.addLine(to: CGPoint(x: x, y: y + 3))
                y += spacing * 2
            }
            x += spacing * 2
        }
        c.stroke(nodes, with: .color(holo.opacity(0.1)), lineWidth: 0.8)
    }

    private func drawShootingStar(_ c: GraphicsContext, _ size: CGSize) {
        let period: CGFloat = 6
        let k = floor(time / period)
        let t = time - k * period
        guard t < 0.8 else { return }
        let seed = k * 12.9898
        let start = CGPoint(x: frac(sin(seed) * 43758.5) * size.width,
                            y: frac(sin(seed + 1.3) * 24634.6) * size.height * 0.6)
        let side: CGFloat = frac(sin(seed + 4.1) * 9631.7) > 0.5 ? 1 : -1
        let ang = 0.35 + frac(sin(seed + 2.7) * 1234.5) * 0.5
        let dir = CGVector(dx: cos(ang) * side, dy: sin(ang))
        let prog = t / 0.8
        let head = CGPoint(x: start.x + dir.dx * prog * 480, y: start.y + dir.dy * prog * 480)
        let tail = CGPoint(x: head.x - dir.dx * 130, y: head.y - dir.dy * 130)
        var line = Path()
        line.move(to: tail)
        line.addLine(to: head)
        let alpha = Double(sin(prog * CGFloat.pi))
        c.stroke(line, with: .linearGradient(Gradient(colors: [Color.white.opacity(0), Color.white.opacity(alpha * 0.9)]),
                                             startPoint: tail, endPoint: head),
                 style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
        c.fill(circlePath(head, 2), with: .color(Color.white.opacity(alpha)))
    }

    // MARK: Planeten

    private func ellipseArc(_ rx: CGFloat, _ ry: CGFloat, _ a0: CGFloat, _ a1: CGFloat) -> Path {
        var path = Path()
        let steps = 48
        for i in 0...steps {
            let a = a0 + (a1 - a0) * CGFloat(i) / CGFloat(steps)
            let p = CGPoint(x: cos(a) * rx, y: sin(a) * ry)
            if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        return path
    }

    private func drawRingHalf(_ w: GraphicsContext, _ p: Planet, front: Bool) {
        let rx = min(p.radius * 1.6, p.radius + 40)
        let ry = rx * 0.28
        let a0: CGFloat = front ? 0 : CGFloat.pi
        let a1: CGFloat = front ? CGFloat.pi : CGFloat.pi * 2

        var r = w
        r.translateBy(x: p.center.x, y: p.center.y)
        r.rotate(by: .radians(Double(p.tilt)))
        // Mehrere Ringbänder mit Lücken
        let layers: [(scale: CGFloat, width: CGFloat, alpha: Double, shift: Double)] = [
            (1.0, 0.10, 0.26, 25), (0.91, 0.045, 0.5, 35), (0.83, 0.07, 0.2, 10), (0.75, 0.025, 0.55, 40)
        ]
        for l in layers {
            r.stroke(ellipseArc(rx * l.scale, ry * l.scale, a0, a1),
                     with: .color(hsl(p.hue + l.shift, 0.45, 0.8, front ? l.alpha : l.alpha * 0.7)),
                     style: StrokeStyle(lineWidth: p.radius * l.width))
        }
    }

    private func moonPoint(_ p: Planet) -> (CGPoint, CGFloat, CGFloat) {
        let dist = p.radius * 1.5 + 80
        let a = p.moonPhase + time * 0.25
        let local = CGPoint(x: cos(a) * dist, y: sin(a) * dist * 0.32)
        let ct = cos(p.tilt), st = sin(p.tilt)
        let pt = CGPoint(x: p.center.x + local.x * ct - local.y * st,
                         y: p.center.y + local.x * st + local.y * ct)
        return (pt, max(9, p.radius * 0.14), a)
    }

    private func drawMoon(_ w: GraphicsContext, _ p: Planet) {
        let (m, mr, _) = moonPoint(p)
        let light = CGPoint(x: m.x - mr * 0.4, y: m.y - mr * 0.4)
        w.fill(circlePath(m, mr), with: .radialGradient(Gradient(colors: [
            Color(red: 0.85, green: 0.86, blue: 0.9), Color(red: 0.45, green: 0.47, blue: 0.55), Color(red: 0.12, green: 0.13, blue: 0.2)
        ]), center: light, startRadius: 0, endRadius: mr * 1.6))
        w.fill(circlePath(CGPoint(x: m.x + mr * 0.25, y: m.y + mr * 0.1), mr * 0.22),
               with: .color(Color.black.opacity(0.18)))
    }

    private func drawPlanet(_ w: GraphicsContext, _ p: Planet, px: CGFloat) {
        let c = p.center
        let r = p.radius

        // Glow
        w.fill(circlePath(c, r * 1.8),
               with: .radialGradient(Gradient(colors: [hsl(p.hue, 0.6, 0.6, 0.4), hsl(p.hue, 0.6, 0.6, 0)]),
                                     center: c, startRadius: r * 0.9, endRadius: r * 1.8))

        let moonBehind = p.hasMoon && sin(moonPoint(p).2) < 0
        if p.hasMoon {
            var orbit = w
            orbit.translateBy(x: c.x, y: c.y)
            orbit.rotate(by: .radians(Double(p.tilt)))
            let dist = r * 1.5 + 80
            orbit.stroke(Path(ellipseIn: CGRect(x: -dist, y: -dist * 0.32, width: dist * 2, height: dist * 0.64)),
                         with: .color(Color.white.opacity(0.06)), lineWidth: 1 * px)
        }
        if moonBehind { drawMoon(w, p) }
        if p.hasRing { drawRingHalf(w, p, front: false) }

        // Körper
        var body = w
        body.clip(to: circlePath(c, r))
        let square = Path(CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
        let lightPoint = CGPoint(x: c.x - r * 0.38, y: c.y - r * 0.38)
        body.fill(square,
                  with: .radialGradient(Gradient(stops: [
                    .init(color: hsl(p.hue, 0.58, 0.72), location: 0),
                    .init(color: hsl(p.hue, 0.58, 0.46), location: 0.6),
                    .init(color: hsl(p.hue, 0.62, 0.18), location: 1)
                  ]), center: lightPoint, startRadius: 0, endRadius: r * 1.5))

        // Wellige Wolkenbänder (leicht gekippt)
        var bands = body
        bands.translateBy(x: c.x, y: c.y)
        bands.rotate(by: .radians(Double(p.tilt)))
        let bandHeight = r * 2 / CGFloat(p.bands.count)
        let n = 18
        for (i, band) in p.bands.enumerated() {
            let y0 = -r + CGFloat(i) * bandHeight
            let amp = bandHeight * 0.22
            let ph = CGFloat(i) * 1.7
            var path = Path()
            for k in 0...n {
                let x = -r + 2 * r * CGFloat(k) / CGFloat(n)
                let pt = CGPoint(x: x, y: y0 + sin(x / r * 3 + ph) * amp)
                if k == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
            }
            for k in stride(from: n, through: 0, by: -1) {
                let x = -r + 2 * r * CGFloat(k) / CGFloat(n)
                path.addLine(to: CGPoint(x: x, y: y0 + bandHeight + sin(x / r * 3 + ph + 1.3) * amp))
            }
            path.closeSubpath()
            let color: Color = band.dark
                ? hsl(p.hue - 20, 0.5, 0.16, Double(band.alpha * 0.32))
                : hsl(p.hue2, 0.6, 0.78, Double(band.alpha * 0.2))
            bands.fill(path, with: .color(color))
        }

        // Sturmwirbel
        if p.hasStorm {
            let sc = CGPoint(x: r * 0.22, y: r * 0.3)
            bands.fill(Path(ellipseIn: CGRect(x: sc.x - r * 0.24, y: sc.y - r * 0.11, width: r * 0.48, height: r * 0.22)),
                       with: .color(hsl(p.hue + 30, 0.7, 0.42, 0.6)))
            bands.fill(Path(ellipseIn: CGRect(x: sc.x - r * 0.14, y: sc.y - r * 0.06, width: r * 0.28, height: r * 0.12)),
                       with: .color(hsl(p.hue + 40, 0.75, 0.62, 0.5)))
            bands.stroke(Path(ellipseIn: CGRect(x: sc.x - r * 0.3, y: sc.y - r * 0.14, width: r * 0.6, height: r * 0.28)),
                         with: .color(Color.white.opacity(0.12)), lineWidth: r * 0.02)
        } else {
            for cr in p.craters {
                let cp = CGPoint(x: c.x + cos(cr.angle) * cr.dist * r, y: c.y + sin(cr.angle) * cr.dist * r)
                let rad = cr.size * r
                body.fill(circlePath(cp, rad), with: .color(Color(red: 0, green: 0, blue: 0.12).opacity(0.22)))
                body.fill(circlePath(CGPoint(x: cp.x - rad * 0.25, y: cp.y - rad * 0.25), rad * 0.7),
                          with: .color(Color.white.opacity(0.1)))
                body.stroke(circlePath(cp, rad), with: .color(Color.white.opacity(0.08)), lineWidth: rad * 0.12)
            }
        }

        // Glanzlicht
        body.fill(circlePath(lightPoint, r * 0.45),
                  with: .radialGradient(Gradient(colors: [Color.white.opacity(0.22), Color.white.opacity(0)]),
                                        center: lightPoint, startRadius: 0, endRadius: r * 0.45))

        // Schattenseite
        body.fill(square,
                  with: .linearGradient(Gradient(stops: [
                    .init(color: Color(red: 0, green: 0, blue: 0.08).opacity(0), location: 0),
                    .init(color: Color(red: 0, green: 0, blue: 0.08).opacity(0), location: 0.48),
                    .init(color: Color(red: 0, green: 0, blue: 0.08).opacity(0.8), location: 1)
                  ]),
                                        startPoint: CGPoint(x: c.x - r * 0.6, y: c.y - r * 0.6),
                                        endPoint: CGPoint(x: c.x + r * 0.95, y: c.y + r * 0.95)))

        // Atmosphäre und Randlicht
        body.fill(square,
                  with: .radialGradient(Gradient(colors: [hsl(p.hue, 0.85, 0.78, 0), hsl(p.hue, 0.85, 0.78, 0.6)]),
                                        center: c, startRadius: r * 0.8, endRadius: r))
        var rim = w
        rim.blendMode = .plusLighter
        rim.stroke(circlePath(c, r - 1 * px),
                   with: .linearGradient(Gradient(colors: [hsl(p.hue, 0.9, 0.85, 0.9), hsl(p.hue, 0.9, 0.85, 0)]),
                                         startPoint: CGPoint(x: c.x - r * 0.75, y: c.y - r * 0.75), endPoint: c),
                   lineWidth: 2.5 * px)

        if p.hasRing { drawRingHalf(w, p, front: true) }
        if p.hasMoon && !moonBehind { drawMoon(w, p) }
    }

    // MARK: Nebel und Asteroiden

    private func drawClouds(_ w: GraphicsContext) {
        var add = w
        add.blendMode = .plusLighter
        for cl in clouds {
            for b in cl.blobs {
                let a = time * b.speed
                let bc = CGPoint(x: cl.center.x + b.off.x * cos(a) - b.off.y * sin(a),
                                 y: cl.center.y + b.off.x * sin(a) + b.off.y * cos(a))
                add.fill(circlePath(bc, b.r), with: .radialGradient(Gradient(colors: [
                    hsl(b.hue, 0.75, 0.5, 0.2), hsl(b.hue + 20, 0.7, 0.4, 0.07), hsl(b.hue, 0.7, 0.4, 0)
                ]), center: bc, startRadius: 0, endRadius: b.r))
            }
            for (k, sp) in cl.sparkles.enumerated() {
                let tw = 0.5 + 0.5 * sin(time * 2.5 + CGFloat(k) * 1.7)
                add.fill(circlePath(sp, 2 + 2 * tw), with: .color(Color.white.opacity(Double(0.25 + 0.5 * tw))))
            }
        }
    }

    private func drawAsteroids(_ w: GraphicsContext, px: CGFloat) {
        for a in asteroids {
            var g = w
            g.translateBy(x: a.center.x, y: a.center.y)
            var rock = Path()
            let n = a.shape.count
            let rot = a.phase + time * a.spin
            for k in 0..<n {
                let ang = CGFloat(k) / CGFloat(n) * CGFloat.pi * 2 + rot
                let pt = CGPoint(x: cos(ang) * a.radius * a.shape[k], y: sin(ang) * a.radius * a.shape[k])
                if k == 0 { rock.move(to: pt) } else { rock.addLine(to: pt) }
            }
            rock.closeSubpath()

            // Warnschein, damit man sie auch weit herausgezoomt sieht
            g.fill(circlePath(.zero, a.radius * 1.8), with: .radialGradient(Gradient(colors: [
                Color(red: 1, green: 0.55, blue: 0.3).opacity(0.18), Color(red: 1, green: 0.55, blue: 0.3).opacity(0)
            ]), center: .zero, startRadius: a.radius * 0.8, endRadius: a.radius * 1.8))
            g.fill(rock, with: .radialGradient(Gradient(colors: [
                hsl(28, 0.18, a.tone + 0.2), hsl(25, 0.15, a.tone), hsl(240, 0.2, 0.1)
            ]), center: CGPoint(x: -a.radius * 0.4, y: -a.radius * 0.4), startRadius: 0, endRadius: a.radius * 1.6))
            var cr = g
            cr.clip(to: rock)
            let c1 = CGPoint(x: cos(rot) * a.radius * 0.3, y: sin(rot) * a.radius * 0.3)
            let c2 = CGPoint(x: cos(rot + 2.4) * a.radius * 0.45, y: sin(rot + 2.4) * a.radius * 0.45)
            cr.fill(circlePath(c1, a.radius * 0.22), with: .color(Color.black.opacity(0.25)))
            cr.fill(circlePath(c2, a.radius * 0.15), with: .color(Color.black.opacity(0.22)))
            g.stroke(rock, with: .color(Color(red: 1, green: 0.7, blue: 0.5).opacity(0.35)), lineWidth: 1.2 * px)
        }
    }

    // MARK: Waffen

    private func drawWeapons(_ w: GraphicsContext, px: CGFloat) {
        var add = w
        add.blendMode = .plusLighter

        for b in beams {
            let t = b.age / 0.4
            let col = hsl(WeaponKind.railgun.hue, 0.9, 0.65)
            var line = Path()
            line.move(to: b.from)
            line.addLine(to: b.to)
            add.stroke(line, with: .color(col.opacity(Double(0.35 * (1 - t)))), lineWidth: 18 * px * (1 - t * 0.5))
            add.stroke(line, with: .color(col.opacity(Double(0.8 * (1 - t)))), lineWidth: 6 * px * (1 - t))
            add.stroke(line, with: .color(Color.white.opacity(Double(1 - t))), lineWidth: 2 * px * (1 - t))
        }

        for pr in projectiles {
            let col = hsl(pr.kind.hue, 0.9, 0.62)
            let hd = atan2(pr.v.dy, pr.v.dx)
            switch pr.kind {
            case .cannon:
                var streak = Path()
                streak.move(to: point(from: pr.p, angle: hd + CGFloat.pi, distance: 26 * px))
                streak.addLine(to: pr.p)
                add.stroke(streak, with: .color(col.opacity(0.7)), style: StrokeStyle(lineWidth: 4 * px, lineCap: .round))
                add.fill(circlePath(pr.p, 3.5 * px), with: .color(Color.white))
            case .rocket:
                var r = w
                r.translateBy(x: pr.p.x, y: pr.p.y)
                r.rotate(by: .radians(Double(hd)))
                let u = 2.4 * px
                var body = Path()
                body.move(to: CGPoint(x: 4 * u, y: 0))
                body.addLine(to: CGPoint(x: 2 * u, y: -1.1 * u))
                body.addLine(to: CGPoint(x: -3 * u, y: -1.1 * u))
                body.addLine(to: CGPoint(x: -4 * u, y: -2.2 * u))
                body.addLine(to: CGPoint(x: -4 * u, y: 2.2 * u))
                body.addLine(to: CGPoint(x: -3 * u, y: 1.1 * u))
                body.addLine(to: CGPoint(x: 2 * u, y: 1.1 * u))
                body.closeSubpath()
                r.fill(body, with: .color(Color(red: 0.9, green: 0.92, blue: 0.96)))
                r.fill(Path(CGRect(x: 1 * u, y: -1.1 * u, width: 0.8 * u, height: 2.2 * u)), with: .color(col))
                var ra = r
                ra.blendMode = .plusLighter
                let fl = (1 + 0.4 * sin(time * 60)) * 5 * u
                var flame = Path()
                flame.move(to: CGPoint(x: -4 * u, y: -0.8 * u))
                flame.addLine(to: CGPoint(x: -4 * u - fl, y: 0))
                flame.addLine(to: CGPoint(x: -4 * u, y: 0.8 * u))
                flame.closeSubpath()
                ra.fill(flame, with: .color(Color(red: 1, green: 0.7, blue: 0.3).opacity(0.9)))
            case .bomb:
                let blink = sin(time * 30) > 0
                add.fill(circlePath(pr.p, 22 * px), with: .radialGradient(Gradient(colors: [col.opacity(0.6), col.opacity(0)]),
                                                                          center: pr.p, startRadius: 0, endRadius: 22 * px))
                w.fill(circlePath(pr.p, 8 * px), with: .color(Color(red: 0.2, green: 0.2, blue: 0.26)))
                w.stroke(circlePath(pr.p, 8 * px), with: .color(col), lineWidth: 2 * px)
                w.fill(circlePath(pr.p, 3 * px), with: .color(blink ? Color.white : col))
                w.stroke(circlePath(pr.p, 280), with: .color(col.opacity(0.18)),
                         style: StrokeStyle(lineWidth: 1.5 * px, dash: [6 * px, 6 * px]))
            case .railgun:
                break
            }
        }
    }

    // MARK: Bonus-Items

    private func drawItems(_ w: GraphicsContext, px: CGFloat) {
        var add = w
        add.blendMode = .plusLighter
        for it in items {
            let col = hsl(it.kind.hue, 0.85, 0.62)
            let t = min(1, it.age / Item.flyTime)
            let grow = 0.4 + 0.9 * sin(t * CGFloat.pi) + 0.3 * (1 - t)
            let c = it.p
            let r = 15 * px * (1 + 0.06 * sin(time * 5 + it.phase)) * grow

            add.fill(circlePath(c, r * 2.8), with: .radialGradient(Gradient(colors: [col.opacity(0.4), col.opacity(0)]),
                                                                     center: c, startRadius: 0, endRadius: r * 2.8))
            var hex = Path()
            for k in 0..<6 {
                let pt = point(from: c, angle: CGFloat(k) * CGFloat.pi / 3 + time * 0.6 + it.phase, distance: r)
                if k == 0 { hex.move(to: pt) } else { hex.addLine(to: pt) }
            }
            hex.closeSubpath()
            w.fill(hex, with: .color(panel.opacity(0.85)))
            w.stroke(hex, with: .color(col), lineWidth: 1.8 * px)

            for k in 0..<3 {
                let st = -time * 1.2 + CGFloat(k) * 2 * CGFloat.pi / 3
                var arc = Path()
                arc.addArc(center: c, radius: r * 1.5, startAngle: .radians(Double(st)),
                           endAngle: .radians(Double(st + 1.2)), clockwise: false)
                add.stroke(arc, with: .color(col.opacity(0.7)), lineWidth: 1.2 * px)
            }

            var ic = w
            ic.translateBy(x: c.x, y: c.y)
            ic.scaleBy(x: px, y: px)
            drawItemIcon(ic, it.kind, col)
        }
    }

    private func hexPath(_ c: CGPoint, _ r: CGFloat, _ rot: CGFloat) -> Path {
        var hex = Path()
        for k in 0..<6 {
            let pt = point(from: c, angle: CGFloat(k) * CGFloat.pi / 3 + rot, distance: r)
            if k == 0 { hex.move(to: pt) } else { hex.addLine(to: pt) }
        }
        hex.closeSubpath()
        return hex
    }

    /// Ladekreis und Item-Symbol an jedem Planeten, der noch ein Bonus-Item hat.
    private func drawBonusRings(_ w: GraphicsContext, px: CGFloat) {
        var add = w
        add.blendMode = .plusLighter
        let first = max(0, currentIndex - 3)
        for i in first..<planets.count {
            let p = planets[i]
            guard let kind = p.bonus, !bonusTaken.contains(i) else { continue }
            let col = hsl(kind.hue, 0.85, 0.62)
            let rr = p.radius + 12
            let isCur = i == currentIndex && phase != .over
            let fraction = isCur ? min(1, orbitCharge / chargeNeeded) : 0

            w.stroke(circlePath(p.center, rr), with: .color(col.opacity(0.3)),
                     style: StrokeStyle(lineWidth: 3 * px, dash: [2 * px, 3 * px]))
            if fraction > 0 {
                var arc = Path()
                arc.addArc(center: p.center, radius: rr, startAngle: .radians(-Double.pi / 2),
                           endAngle: .radians(-Double.pi / 2 + 2 * Double.pi * Double(fraction)), clockwise: false)
                add.stroke(arc, with: .color(col.opacity(0.35)), lineWidth: 10 * px)
                w.stroke(arc, with: .color(col), style: StrokeStyle(lineWidth: 3.5 * px, lineCap: .round))
            }

            // Symbol oben auf dem Ring
            let bc = CGPoint(x: p.center.x, y: p.center.y - rr)
            let pulse = isCur ? 1 + 0.08 * sin(time * 6) : 1
            let br = 11 * px * pulse
            add.fill(circlePath(bc, br * 2), with: .radialGradient(Gradient(colors: [col.opacity(0.35), col.opacity(0)]),
                                                                   center: bc, startRadius: 0, endRadius: br * 2))
            let hex = hexPath(bc, br, CGFloat.pi / 6)
            w.fill(hex, with: .color(panel.opacity(0.9)))
            w.stroke(hex, with: .color(col), lineWidth: 1.5 * px)
            var ic = w
            ic.translateBy(x: bc.x, y: bc.y)
            ic.scaleBy(x: px * 0.72 * pulse, y: px * 0.72 * pulse)
            drawItemIcon(ic, kind, col)

            if isCur {
                var tc = w
                tc.translateBy(x: bc.x, y: bc.y)
                tc.scaleBy(x: px, y: px)
                tc.draw(Text("\(Int(fraction * 100)) %")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(col),
                        at: CGPoint(x: 0, y: -20), anchor: .bottom)
            }
        }
    }

    private func drawItemIcon(_ c: GraphicsContext, _ kind: ItemKind, _ col: Color) {
        var p = Path()
        switch kind {
        case .energy:
            p.move(to: CGPoint(x: 1.5, y: -8))
            p.addLine(to: CGPoint(x: -4, y: 1))
            p.addLine(to: CGPoint(x: 0, y: 1))
            p.addLine(to: CGPoint(x: -1.5, y: 8))
            p.addLine(to: CGPoint(x: 4, y: -1))
            p.addLine(to: CGPoint(x: 0, y: -1))
            p.closeSubpath()
            c.fill(p, with: .color(col))
        case .wideCone:
            p.move(to: CGPoint(x: -7, y: -5))
            p.addLine(to: CGPoint(x: 0, y: 6))
            p.addLine(to: CGPoint(x: 7, y: -5))
            p.addArc(center: CGPoint(x: 0, y: 6), radius: 13, startAngle: .degrees(-57), endAngle: .degrees(-123), clockwise: true)
            p.closeSubpath()
            c.fill(p, with: .color(col.opacity(0.35)))
            c.stroke(p, with: .color(col), lineWidth: 1.6)
        case .superBomb:
            for k in 0..<16 {
                let a = CGFloat(k) * .pi / 8
                let r: CGFloat = k % 2 == 0 ? 8 : 3.5
                let pt = CGPoint(x: cos(a) * r, y: sin(a) * r)
                if k == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
            }
            p.closeSubpath()
            c.fill(p, with: .color(col))
        case .tech:
            var gear = Path()
            for k in 0..<8 {
                let a0 = CGFloat(k) * CGFloat.pi / 4
                gear.move(to: point(from: .zero, angle: a0, distance: 5))
                gear.addLine(to: point(from: .zero, angle: a0, distance: 8))
            }
            c.stroke(gear, with: .color(col), style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
            c.stroke(circlePath(.zero, 5), with: .color(col), lineWidth: 2)
            c.fill(circlePath(.zero, 2), with: .color(col))
        case .shipPart:
            // kleiner Pfeilrumpf mit Flügeln
            p.move(to: CGPoint(x: 8, y: 0))
            p.addLine(to: CGPoint(x: -6, y: -7))
            p.addLine(to: CGPoint(x: -3, y: 0))
            p.addLine(to: CGPoint(x: -6, y: 7))
            p.closeSubpath()
            c.fill(p, with: .color(col))
        case .rescue:
            p.move(to: CGPoint(x: -5, y: 0))
            p.addLine(to: CGPoint(x: 0, y: -5))
            p.addLine(to: CGPoint(x: 5, y: 0))
            p.move(to: CGPoint(x: -5, y: 6))
            p.addLine(to: CGPoint(x: 0, y: 1))
            p.addLine(to: CGPoint(x: 5, y: 6))
            c.stroke(p, with: .color(col), style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
        }
    }

    // MARK: Zielerfassung

    private func drawTargetLock(_ w: GraphicsContext, _ t: Planet, px: CGFloat) {
        let c = t.center
        let r = t.radius
        var add = w
        add.blendMode = .plusLighter

        // Holo-Gitter auf der Oberfläche
        var hg = add
        hg.clip(to: circlePath(c, r))
        for k in 0..<6 {
            let a = mod(time * 0.5 + CGFloat(k) * CGFloat.pi / 6, CGFloat.pi)
            let rx = abs(cos(a)) * r
            hg.stroke(Path(ellipseIn: CGRect(x: c.x - rx, y: c.y - r, width: rx * 2, height: r * 2)),
                      with: .color(holo.opacity(0.14)), lineWidth: 1 * px)
        }
        var lats = Path()
        for lat in stride(from: -0.75, through: 0.75, by: 0.25) {
            let y = c.y + CGFloat(lat) * r
            let hw = r * sqrt(1 - CGFloat(lat * lat))
            lats.move(to: CGPoint(x: c.x - hw, y: y))
            lats.addLine(to: CGPoint(x: c.x + hw, y: y))
        }
        hg.stroke(lats, with: .color(holo.opacity(0.1)), lineWidth: 1 * px)
        let sy = c.y - r + mod(time * r * 0.9, r * 2.4)
        hg.fill(Path(CGRect(x: c.x - r, y: sy - r * 0.3, width: r * 2, height: r * 0.3)),
                with: .linearGradient(Gradient(colors: [holo.opacity(0), holo.opacity(0.25)]),
                                      startPoint: CGPoint(x: c.x, y: sy - r * 0.3), endPoint: CGPoint(x: c.x, y: sy)))

        // Rotierender Segmentring
        let r1 = r + 30
        for k in 0..<3 {
            let s = time * 0.7 + CGFloat(k) * 2 * CGFloat.pi / 3
            var arc = Path()
            arc.addArc(center: c, radius: r1, startAngle: .radians(Double(s)),
                       endAngle: .radians(Double(s + 1.4)), clockwise: false)
            add.stroke(arc, with: .color(holo.opacity(0.7)), lineWidth: 2.5 * px)
        }

        // Gegenläufige Skala
        let r2 = r + 44
        var ticks = Path()
        for k in 0..<36 {
            let a = CGFloat(k) * CGFloat.pi / 18 - time * 0.2
            let len: CGFloat = (k % 3 == 0 ? 9 : 4) * px
            ticks.move(to: point(from: c, angle: a, distance: r2))
            ticks.addLine(to: point(from: c, angle: a, distance: r2 + len))
        }
        add.stroke(ticks, with: .color(holo.opacity(0.45)), lineWidth: 1 * px)

        // Erfassungsklammern
        let pulse = 1 + 0.05 * sin(time * 5)
        let h = (r + 62) * pulse
        let rect = CGRect(x: c.x - h, y: c.y - h, width: h * 2, height: h * 2)
        add.stroke(Brackets(len: h * 0.28).path(in: rect), with: .color(amber.opacity(0.25)),
                   style: StrokeStyle(lineWidth: 7 * px, lineCap: .square))
        w.stroke(Brackets(len: h * 0.28).path(in: rect), with: .color(amber.opacity(0.9)),
                 style: StrokeStyle(lineWidth: 2.2 * px, lineCap: .square))
        let d = 6 * px
        var diamond = Path()
        diamond.move(to: CGPoint(x: c.x, y: c.y - h - d * 2.2))
        diamond.addLine(to: CGPoint(x: c.x + d, y: c.y - h - d * 1.1))
        diamond.addLine(to: CGPoint(x: c.x, y: c.y - h))
        diamond.addLine(to: CGPoint(x: c.x - d, y: c.y - h - d * 1.1))
        diamond.closeSubpath()
        w.fill(diamond, with: .color(amber.opacity(0.9)))
    }

    /// Bildschirmposition über die echte 3D-Kamera; die 2D-Rechnung kennt Neigung und Perspektive nicht
    private func screenPoint(_ p: CGPoint, _ size: CGSize) -> CGPoint {
        project?(p) ?? toScreen(p, size)
    }

    private func drawTargetLabel(_ c: GraphicsContext, _ size: CGSize) {
        guard phase != .over, !inHangarView else { return }
        let t = planets[currentIndex + 1]
        let sp = screenPoint(t.center, size)
        let edge = screenPoint(CGPoint(x: t.center.x + t.radius + 62, y: t.center.y), size)
        let h = max(16, hypot(edge.x - sp.x, edge.y - sp.y))
        // kein Schattenfilter mehr: er kostete in jedem Bild einen eigenen Renderdurchgang, die dunkle Platte
        // hinter der Schrift hält sie auch vor hellen Planeten lesbar
        let plain = c
        let flip: CGFloat = sp.x + h + 110 > size.width ? -1 : 1
        let corner = CGPoint(x: sp.x + h * flip, y: sp.y - h)
        guard corner.x > 8, corner.x < size.width - 8,
              corner.y > insets.top + 150, corner.y < size.height - insets.bottom - 120 else { return }

        let elbow = CGPoint(x: corner.x + 16 * flip, y: corner.y - 16)
        let end = CGPoint(x: elbow.x + 86 * flip, y: elbow.y)
        var line = Path()
        line.move(to: corner)
        line.addLine(to: elbow)
        line.addLine(to: end)
        c.stroke(line, with: .color(amber.opacity(0.75)), lineWidth: 1)
        c.fill(circlePath(corner, 2), with: .color(amber))

        let anchorTop: UnitPoint = flip > 0 ? .bottomLeading : .bottomTrailing
        let anchorBottom: UnitPoint = flip > 0 ? .topLeading : .topTrailing
        let tx = elbow.x + 2 * flip
        let title = c.resolve(Text(t.isStation ? "RAUMSTATION · WERFT" : "ZIEL \(String(format: "%02d", planetBase + currentIndex + 1))")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(amber))
        let info = c.resolve(Text("\(shownDistance) km · +\(Int(t.energyGain.rounded())) E")
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundColor(amber.opacity(0.85)))
        let s1 = title.measure(in: size), s2 = info.measure(in: size)
        let w = max(s1.width, s2.width)
        let top = elbow.y - 3 - s1.height, bottom = elbow.y + 3 + s2.height
        let plate = CGRect(x: flip > 0 ? tx : tx - w, y: top, width: w, height: bottom - top)
        drawPlate(plain, plate.insetBy(dx: -6, dy: -3), accent: amber, alpha: 1, cut: 5)
        c.draw(title, at: CGPoint(x: tx, y: elbow.y - 3), anchor: anchorTop)
        c.draw(info, at: CGPoint(x: tx, y: elbow.y + 3), anchor: anchorBottom)
    }

    // MARK: Bahn und Kegel

    private func drawOrbitAndCone(_ w: GraphicsContext, px: CGFloat) {
        let cur = planets[currentIndex]
        let ringColor = Color(red: 0.43, green: 0.75, blue: 1)

        var add = w
        add.blendMode = .plusLighter
        add.stroke(circlePath(cur.center, cur.orbitRadius), with: .color(ringColor.opacity(0.08)), lineWidth: 9 * px)
        w.stroke(circlePath(cur.center, cur.orbitRadius),
                 with: .color(Color(red: 0.67, green: 0.88, blue: 1).opacity(0.3)),
                 style: StrokeStyle(lineWidth: 1.5 * px, dash: [4 * px, 6 * px]))

        // Skala außerhalb der Bahn
        var ticks = Path()
        for k in 0..<48 {
            let a = CGFloat(k) * CGFloat.pi / 24 + time * 0.05 * orbitDir
            let len: CGFloat = (k % 4 == 0 ? 8 : 3) * px
            ticks.move(to: point(from: cur.center, angle: a, distance: cur.orbitRadius + 12 * px))
            ticks.addLine(to: point(from: cur.center, angle: a, distance: cur.orbitRadius + 12 * px + len))
        }
        w.stroke(ticks, with: .color(ringColor.opacity(0.28)), lineWidth: 1 * px)

        // wandernde Richtungspfeile
        for q in 0..<6 {
            let an = CGFloat(q) * CGFloat.pi / 3 + orbitDir * time * 0.5
            let qp = point(from: cur.center, angle: an, distance: cur.orbitRadius)
            let ta = an + orbitDir * CGFloat.pi / 2
            let sz = 9 * px
            var arrow = Path()
            arrow.move(to: point(from: qp, angle: ta, distance: sz))
            arrow.addLine(to: point(from: qp, angle: ta + 2.5, distance: sz * 0.8))
            arrow.addLine(to: point(from: qp, angle: ta - 2.5, distance: sz * 0.8))
            arrow.closeSubpath()
            w.fill(arrow, with: .color(Color(red: 0.67, green: 0.88, blue: 1).opacity(0.65)))
        }

        // Kegel: fest, Spitze auf der Bahn
        let dir = coneDirection
        let apex = point(from: cur.center, angle: coneApexAngle, distance: cur.orbitRadius)
        let len: CGFloat = 480
        let left = point(from: apex, angle: dir - coneHalfAngle, distance: len)
        let right = point(from: apex, angle: dir + coneHalfAngle, distance: len)
        let tip = point(from: apex, angle: dir, distance: len)
        let hot = inCone
        let tone: Color = hot ? signal : Color.white

        var cone = Path()
        cone.move(to: apex)
        cone.addLine(to: left)
        cone.addLine(to: right)
        cone.closeSubpath()
        w.fill(cone, with: .linearGradient(Gradient(colors: [tone.opacity(hot ? 0.5 : 0.3), tone.opacity(0)]),
                                           startPoint: apex, endPoint: tip))

        // Scan-Linien laufen vom Scheitel nach außen
        let wide = tan(coneHalfAngle)
        for k in 0..<4 {
            let dist = mod(time * 150 + CGFloat(k) * 120, len)
            let mid = point(from: apex, angle: dir, distance: dist)
            let hw = wide * dist
            var line = Path()
            line.move(to: point(from: mid, angle: dir - CGFloat.pi / 2, distance: hw))
            line.addLine(to: point(from: mid, angle: dir + CGFloat.pi / 2, distance: hw))
            w.stroke(line, with: .color(tone.opacity(Double((1 - dist / len) * 0.3))), lineWidth: 1.5 * px)
        }

        // Entfernungsmarken am Rand
        var marks = Path()
        for k in 1...4 {
            let d = CGFloat(k) * len / 5
            for side in [-1, 1] as [CGFloat] {
                let e = point(from: apex, angle: dir + side * coneHalfAngle, distance: d)
                marks.move(to: e)
                marks.addLine(to: point(from: e, angle: dir + side * CGFloat.pi / 2, distance: 7 * px))
            }
        }
        w.stroke(marks, with: .color(tone.opacity(0.5)), lineWidth: 1.2 * px)

        // Leuchtkanten und Mittellinie
        var edges = Path()
        edges.move(to: left)
        edges.addLine(to: apex)
        edges.addLine(to: right)
        add.stroke(edges, with: .color(tone.opacity(hot ? 0.3 : 0.12)), lineWidth: 7 * px)
        w.stroke(edges, with: .color(tone.opacity(hot ? 0.85 : 0.5)), lineWidth: 2 * px)

        var center = Path()
        center.move(to: apex)
        center.addLine(to: tip)
        w.stroke(center, with: .color(tone.opacity(0.55)),
                 style: StrokeStyle(lineWidth: 1.5 * px, dash: [8 * px, 8 * px]))

        // Marker an der Kegelspitze
        let markerRadius = (11 + (hot ? 4 * sin(time * 12) : 0)) * px
        w.stroke(circlePath(apex, markerRadius), with: .color(tone.opacity(0.9)), lineWidth: 2 * px)
        w.stroke(circlePath(apex, markerRadius + 6 * px), with: .color(tone.opacity(0.35)),
                 style: StrokeStyle(lineWidth: 1 * px, dash: [3 * px, 3 * px]))
    }

    // MARK: Spur, Partikel, Satellit

    private func drawTrailAndParticles(_ w: GraphicsContext, px: CGFloat) {
        var add = w
        add.blendMode = .plusLighter

        if trail.count > 1 {
            for i in 1..<trail.count {
                let f = CGFloat(i) / CGFloat(trail.count)
                var seg = Path()
                seg.move(to: trail[i - 1])
                seg.addLine(to: trail[i])
                add.stroke(seg, with: .color(signal.opacity(Double(f * 0.14))),
                           style: StrokeStyle(lineWidth: 10 * px * f, lineCap: .round))
                add.stroke(seg, with: .color(Color(red: 0.63, green: 1, blue: 0.92).opacity(Double(f * 0.7))),
                           style: StrokeStyle(lineWidth: 2.2 * px * f, lineCap: .round))
            }
        }

        for p in particles {
            let l = p.life / p.maxLife
            add.fill(circlePath(CGPoint(x: p.x, y: p.y), p.size * px * (0.4 + l)),
                     with: .color(hsl(p.hue, 0.9, 0.6 + 0.2 * Double(l), Double(l))))
        }
    }

    private func drawSatellite(_ w: GraphicsContext, px: CGFloat) {
        let u = 5.8 * px
        let accent = hsl(ship.weapon.hue, 0.85, 0.6)

        w.fill(circlePath(pos, u * 5.5),
               with: .radialGradient(Gradient(colors: [accent.opacity(0.35), accent.opacity(0)]),
                                     center: pos, startRadius: 0, endRadius: u * 5.5))

        if boostTime > 0 {
            let col = hsl(ItemKind.rescue.hue, 0.9, 0.6, Double(min(1, boostTime)) * 0.6)
            var add0 = w
            add0.blendMode = .plusLighter
            add0.fill(circlePath(pos, u * 9), with: .radialGradient(Gradient(colors: [col, col.opacity(0)]),
                                                                    center: pos, startRadius: 0, endRadius: u * 9))
        }

        var s = w
        s.translateBy(x: pos.x, y: pos.y)
        s.rotate(by: .radians(Double(heading)))
        let thrust: CGFloat = phase == .flying ? (boostTime > 0 ? 2 : 1) : 0.15
        if let sprite = Ship3D.sprite(for: ship.model) {
            ShipArt.drawFlame(s, ship: ship, u: u, time: time, thrust: thrust)
            let span = Ship3D.spriteSpan * u
            s.draw(Image(uiImage: sprite), in: CGRect(x: -span / 2, y: -span / 2, width: span, height: span))
        } else {
            ShipArt.draw(s, ship: ship, u: u, time: time, thrust: thrust)
        }
    }

    // MARK: Bildschirm-Ebene

    private func drawIndicator(_ c: GraphicsContext, _ size: CGSize) {
        guard phase != .over, !inHangarView else { return }
        let t = planets[currentIndex + 1]
        let sp = toScreen(t.center, size)
        let margin: CGFloat = 34
        // solange oben die Startbewertung steht, rückt der Pfeil darunter (gleitet danach zurück)
        let sinceLaunch = time - lastLaunchTime
        let badge: CGFloat = dockLaunch || sinceLaunch < 0 ? 0 : min(1, max(0, (1.7 - sinceLaunch) / 0.3))
        let top: CGFloat = insets.top + 150 + 46 * badge
        let bottom: CGFloat = size.height - insets.bottom - 130
        if sp.x > margin && sp.x < size.width - margin && sp.y > top && sp.y < bottom { return }

        let cx = size.width / 2
        let cy = (bottom + top) / 2
        let dx = sp.x - cx
        let dy = sp.y - cy
        let kx = (size.width / 2 - margin) / max(abs(dx), 0.001)
        let ky = ((bottom - top) / 2) / max(abs(dy), 0.001)
        let k = min(kx, ky)
        let ix = cx + dx * k
        let iy = cy + dy * k
        let angle = atan2(dy, dx)
        let col = hsl(t.hue, 0.7, 0.65, 0.95)

        var a = c
        a.translateBy(x: ix, y: iy)
        var glow = a
        glow.blendMode = .plusLighter
        glow.fill(circlePath(.zero, 24), with: .color(hsl(t.hue, 0.7, 0.65, 0.2)))
        a.stroke(circlePath(.zero, 20), with: .color(col.opacity(0.6)),
                 style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        a.stroke(Path { p in
            p.addArc(center: .zero, radius: 24, startAngle: .radians(Double(time * 2)),
                     endAngle: .radians(Double(time * 2 + 1.2)), clockwise: false)
        }, with: .color(amber.opacity(0.8)), lineWidth: 1.5)
        var ar = a
        ar.rotate(by: .radians(Double(angle)))
        var arrow = Path()
        arrow.move(to: CGPoint(x: 14, y: 0))
        arrow.addLine(to: CGPoint(x: -7, y: -10))
        arrow.addLine(to: CGPoint(x: -2, y: 0))
        arrow.addLine(to: CGPoint(x: -7, y: 10))
        arrow.closeSubpath()
        ar.fill(arrow, with: .color(col))

        let ty: CGFloat = iy > cy ? -32 : 32
        c.draw(Text("\(shownDistance) km")
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundColor(col),
               at: CGPoint(x: min(max(ix, 40), size.width - 40), y: iy + ty))
    }

    private func drawPopups(_ c: GraphicsContext, _ size: CGSize) {
        // Ältere Meldungen bleiben stehen, neuere weichen nach oben aus, damit sich keine Schilder überdecken
        var placed: [CGRect] = []
        for pp in popups {
            let sp = screenPoint(pp.pos, size)
            // Erst kurz nach oben gleiten, dann ruhig stehen bleiben, damit man lesen kann
            let rise = 1 - exp(-pp.age * 3)
            let sy = sp.y - 18 - pp.lift - rise * 40
            let alpha = Double(min(1, max(0, (Popup.lifetime - pp.age) / Popup.fade)))
            let text = c.resolve(Text(pp.text)
                .font(.system(size: 17, weight: .bold, design: .monospaced))
                .foregroundColor(pp.color.opacity(alpha)))
            let ts = text.measure(in: size)
            var plate = CGRect(x: sp.x - ts.width / 2, y: sy - ts.height / 2,
                               width: ts.width, height: ts.height).insetBy(dx: -9, dy: -4)
            // nicht über den Bildrand hinaus, auch nicht oben oder unten (Ziele weit voraus liegen oft außerhalb)
            plate.origin.x = min(max(plate.minX, 8), size.width - 8 - plate.width)
            plate.origin.y = min(max(plate.minY, insets.top + 150), size.height - insets.bottom - 120 - plate.height)
            var moved = true
            while moved {
                moved = false
                for r in placed where r.insetBy(dx: -2, dy: -3).intersects(plate) {
                    plate.origin.y = r.minY - 4 - plate.height
                    moved = true
                }
            }
            placed.append(plate)
            drawPlate(c, plate, accent: pp.color, alpha: alpha, cut: 6)
            c.draw(text, at: CGPoint(x: plate.midX, y: plate.midY))
        }
    }

    /// Dunkles Schild hinter HUD-Text, damit er auch vor gleichfarbigen Planeten lesbar bleibt.
    private func drawPlate(_ c: GraphicsContext, _ rect: CGRect, accent: Color, alpha: Double, cut: CGFloat) {
        let plate = Chamfer(cut: cut).path(in: rect)
        c.fill(plate, with: .color(Color(red: 0.02, green: 0.03, blue: 0.06).opacity(0.82 * alpha)))
        c.stroke(plate, with: .color(accent.opacity(0.55 * alpha)), lineWidth: 1)
    }

    /// Vignette und Scanlines ändern sich nie und werden nur bei neuer Bildgröße gezeichnet
    func drawStaticFrame(_ c: GraphicsContext, size: CGSize) {
        let full = Path(CGRect(origin: .zero, size: size))

        // Vignette
        c.fill(full, with: .radialGradient(
            Gradient(colors: [Color.black.opacity(0), Color.black.opacity(0.5)]),
            center: CGPoint(x: size.width / 2, y: size.height / 2),
            startRadius: min(size.width, size.height) * 0.45,
            endRadius: max(size.width, size.height) * 0.75))

        // Scanlines
        var scan = Path()
        var y: CGFloat = 0
        while y < size.height {
            scan.move(to: CGPoint(x: 0, y: y))
            scan.addLine(to: CGPoint(x: size.width, y: y))
            y += 3
        }
        c.stroke(scan, with: .color(Color.white.opacity(0.018)), lineWidth: 1)
    }

    private func drawScanBar(_ c: GraphicsContext, _ size: CGSize) {
        let by = mod(time * 70, size.height + 240) - 120
        c.fill(Path(CGRect(x: 0, y: by, width: size.width, height: 120)),
               with: .linearGradient(Gradient(colors: [holo.opacity(0), holo.opacity(0.035), holo.opacity(0)]),
                                     startPoint: CGPoint(x: 0, y: by), endPoint: CGPoint(x: 0, y: by + 120)))
    }

    private func drawRadar(_ c: GraphicsContext, _ size: CGSize) {
        let R: CGFloat = 46
        let center = CGPoint(x: size.width - 16 - R, y: size.height - insets.bottom - 12 - R)
        let disc = circlePath(center, R)
        c.fill(disc, with: .color(panel.opacity(0.75)))

        var inner = c
        inner.clip(to: disc)
        let sweep = time * 2.2
        inner.fill(disc, with: .conicGradient(Gradient(stops: [
            .init(color: signal.opacity(0), location: 0.72),
            .init(color: signal.opacity(0.35), location: 1)
        ]), center: center, angle: .radians(Double(sweep))))
        var rings = Path()
        rings.addPath(circlePath(center, R * 0.33))
        rings.addPath(circlePath(center, R * 0.66))
        rings.move(to: CGPoint(x: center.x - R, y: center.y))
        rings.addLine(to: CGPoint(x: center.x + R, y: center.y))
        rings.move(to: CGPoint(x: center.x, y: center.y - R))
        rings.addLine(to: CGPoint(x: center.x, y: center.y + R))
        inner.stroke(rings, with: .color(holo.opacity(0.18)), lineWidth: 0.8)
        var beam = Path()
        beam.move(to: center)
        beam.addLine(to: point(from: center, angle: sweep, distance: R))
        inner.stroke(beam, with: .color(signal.opacity(0.85)), lineWidth: 1)

        // Planeten als Blips, relativ zum Satelliten
        let scale = R / 1500
        let lo = max(0, currentIndex - 3)
        for i in lo..<planets.count {
            let p = planets[i]
            let rel = CGPoint(x: (p.center.x - pos.x) * scale, y: (p.center.y - pos.y) * scale)
            let d = hypot(rel.x, rel.y)
            let isTarget = i == currentIndex + 1 && phase != .over
            var bp = CGPoint(x: center.x + rel.x, y: center.y + rel.y)
            if d > R - 4 {
                guard isTarget else { continue }
                bp = CGPoint(x: center.x + rel.x / d * (R - 4), y: center.y + rel.y / d * (R - 4))
            }
            let br = max(1.8, p.radius * scale * 1.3)
            inner.fill(circlePath(bp, br), with: .color(hsl(p.hue, 0.7, 0.65, isTarget ? 1 : 0.55)))
            if isTarget {
                inner.stroke(circlePath(bp, br + 3 + 1.5 * sin(time * 6)), with: .color(amber.opacity(0.85)), lineWidth: 1)
            }
        }

        for a in asteroids {
            let rel = CGPoint(x: (a.center.x - pos.x) * scale, y: (a.center.y - pos.y) * scale)
            guard hypot(rel.x, rel.y) < R - 2 else { continue }
            inner.fill(circlePath(CGPoint(x: center.x + rel.x, y: center.y + rel.y), 1.2),
                       with: .color(Color(red: 1, green: 0.65, blue: 0.45).opacity(0.8)))
        }

        for it in items {
            let rel = CGPoint(x: (it.p.x - pos.x) * scale, y: (it.p.y - pos.y) * scale)
            guard hypot(rel.x, rel.y) < R - 3 else { continue }
            let bp = CGPoint(x: center.x + rel.x, y: center.y + rel.y)
            inner.fill(Path(CGRect(x: bp.x - 1.8, y: bp.y - 1.8, width: 3.6, height: 3.6)),
                       with: .color(hsl(it.kind.hue, 0.85, 0.65)))
        }

        var ship = Path()
        ship.move(to: point(from: center, angle: heading, distance: 5))
        ship.addLine(to: point(from: center, angle: heading + 2.5, distance: 4))
        ship.addLine(to: point(from: center, angle: heading - 2.5, distance: 4))
        ship.closeSubpath()
        c.fill(ship, with: .color(Color.white))

        var ticks = Path()
        for k in 0..<24 {
            let a = CGFloat(k) * CGFloat.pi / 12
            ticks.move(to: point(from: center, angle: a, distance: R + 2))
            ticks.addLine(to: point(from: center, angle: a, distance: R + (k % 6 == 0 ? 7 : 4)))
        }
        c.stroke(ticks, with: .color(signal.opacity(0.45)), lineWidth: 1)
        c.stroke(disc, with: .color(signal.opacity(0.55)), lineWidth: 1)
        c.draw(Text("SCAN · 1.5K")
                .font(.system(size: 8, weight: .medium, design: .monospaced))
                .foregroundColor(signal.opacity(0.75)),
               at: CGPoint(x: center.x, y: center.y - R - 9), anchor: .bottom)
    }

    private func drawOverlays(_ c: GraphicsContext, _ size: CGSize) {
        let full = Path(CGRect(origin: .zero, size: size))

        // Warn-Vignette bei wenig Energie
        if energy < 25 && phase != .over && started {
            let pulse = 0.14 + 0.14 * sin(time * 7)
            let alpha = Double(pulse * (1 - energy / 25 * 0.4))
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            c.fill(full, with: .radialGradient(
                Gradient(colors: [Color(red: 1, green: 0.24, blue: 0.2).opacity(0),
                                  Color(red: 1, green: 0.24, blue: 0.2).opacity(alpha)]),
                center: center,
                startRadius: min(size.width, size.height) * 0.35,
                endRadius: max(size.width, size.height) * 0.75))
        }

        if missFlash > 0 {
            c.fill(full, with: .color(Color(red: 1, green: 0.31, blue: 0.27).opacity(Double(missFlash * 0.5))))
        }
    }
}

func frac(_ v: CGFloat) -> CGFloat { v - floor(v) }
