import SwiftUI
import SceneKit
import UIKit
import simd

// MARK: - Hilfen

private func v3(_ p: CGPoint, _ y: CGFloat = 0) -> SCNVector3 { SCNVector3(Float(p.x), Float(y), Float(p.y)) }
private func uic(_ h: Double, _ s: Double, _ l: Double, _ a: Double = 1) -> UIColor { UIColor(hsl(h, s, l, a)) }

private func glowMat(_ color: UIColor, additive: Bool = true) -> SCNMaterial {
    let m = SCNMaterial()
    m.lightingModel = .constant
    m.diffuse.contents = color
    m.emission.contents = color
    if additive {
        m.blendMode = .add
        m.writesToDepthBuffer = false
    }
    m.isDoubleSided = true
    return m
}

private func spriteMat(_ image: UIImage) -> SCNMaterial {
    let m = SCNMaterial()
    m.lightingModel = .constant
    m.diffuse.contents = image
    m.blendMode = .add
    m.writesToDepthBuffer = false
    m.isDoubleSided = true
    return m
}

/// Flacher Ring in der XZ-Ebene aus einem 2D-Pfad
private func flatShape(_ path: UIBezierPath, _ mat: SCNMaterial, depth: CGFloat = 0.5) -> SCNNode {
    let shape = SCNShape(path: path, extrusionDepth: depth)
    shape.materials = [mat]
    let n = SCNNode(geometry: shape)
    n.eulerAngles.x = .pi / 2
    return n
}

private func arcPath(radius: CGFloat, width: CGFloat, from a0: CGFloat, to a1: CGFloat) -> UIBezierPath {
    let p = UIBezierPath()
    p.addArc(withCenter: .zero, radius: radius + width / 2, startAngle: a0, endAngle: a1, clockwise: true)
    p.addArc(withCenter: .zero, radius: radius - width / 2, startAngle: a1, endAngle: a0, clockwise: false)
    p.close()
    return p
}

// MARK: - Prozedurale Texturen

enum WorldTextures {
    static let dot: UIImage = radial(size: 64, stops: [(1, 1), (0.35, 0.4), (0, 0)])
    static let soft: UIImage = radial(size: 128, stops: [(0.9, 0), (0.5, 0.45), (0, 1)])

    /// Solarzellen: dunkelblaue Felder mit hellem Raster
    static let solarCells: UIImage = textureRenderer(CGSize(width: 128, height: 64)).image { ctx in
        UIColor(red: 0.06, green: 0.1, blue: 0.22, alpha: 1).setFill()
        ctx.fill(CGRect(x: 0, y: 0, width: 128, height: 64))
        UIColor(red: 0.5, green: 0.6, blue: 0.75, alpha: 0.6).setStroke()
        let g = ctx.cgContext
        g.setLineWidth(1)
        for x in stride(from: 0, through: 128, by: 16) { g.move(to: CGPoint(x: x, y: 0)); g.addLine(to: CGPoint(x: x, y: 64)) }
        for y in stride(from: 0, through: 64, by: 16) { g.move(to: CGPoint(x: 0, y: y)); g.addLine(to: CGPoint(x: 128, y: y)) }
        g.strokePath()
    }

    static func radial(size: Int, stops: [(CGFloat, CGFloat)]) -> UIImage {
        textureRenderer(CGSize(width: size, height: size)).image { ctx in
            let colors = stops.map { UIColor(white: 1, alpha: $0.0).cgColor } as CFArray
            let locs = stops.map { $0.1 }
            let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: locs)!
            let c = CGPoint(x: size / 2, y: size / 2)
            ctx.cgContext.drawRadialGradient(grad, startCenter: c, startRadius: 0, endCenter: c,
                                             endRadius: CGFloat(size) / 2, options: [])
        }
    }

    /// Sternenhimmel als Rundum-Panorama. Doppelte Auflösung reicht für scharfe Sterne
    /// (dreifach, wie UIKit es von sich aus nähme, wären über 70 MB).
    static let sky: UIImage = skyImage(scale: 2)

    /// Kleine Fassung desselben Himmels für die Umgebungsbeleuchtung: SceneKit filtert sie ohnehin weich,
    /// eine große Vorlage kostet dort nur Speicher und Ladezeit
    static let skyLight: UIImage = skyImage(scale: 0.25)

    private static func skyImage(scale: CGFloat) -> UIImage {
        var rng = SeededRNG("sky")
        let w: CGFloat = 2048, h: CGFloat = 1024
        // in Punkten zeichnen und das Bild selbst skalieren, damit beide Fassungen denselben Himmel zeigen
        return textureRenderer(CGSize(width: w * scale, height: h * scale)).image { ctx in
            let g = ctx.cgContext
            g.scaleBy(x: scale, y: scale)
            g.setFillColor(UIColor(red: 0.012, green: 0.016, blue: 0.04, alpha: 1).cgColor)
            g.fill(CGRect(x: 0, y: 0, width: w, height: h))
            for _ in 0..<26 {
                let r = rng.c(120...420)
                let c = CGPoint(x: rng.c(0...w), y: rng.c(h * 0.15...h * 0.85))
                let col = uic(rng.d(190...330), 0.7, 0.4, rng.d(0.05...0.14))
                let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                      colors: [col.cgColor, col.withAlphaComponent(0).cgColor] as CFArray, locations: [0, 1])!
                g.drawRadialGradient(grad, startCenter: c, startRadius: 0, endCenter: c, endRadius: r, options: [])
            }
            for _ in 0..<2600 {
                let p = CGPoint(x: rng.c(0...w), y: rng.c(0...h))
                let s = rng.chance(0.03) ? rng.c(2...3.4) : rng.c(0.6...1.6)
                let tint: UIColor = rng.chance(0.15) ? UIColor(red: 1, green: 0.85, blue: 0.7, alpha: 1)
                    : (rng.chance(0.2) ? UIColor(red: 0.7, green: 0.8, blue: 1, alpha: 1) : .white)
                g.setFillColor(tint.withAlphaComponent(rng.c(0.35...1)).cgColor)
                g.fillEllipse(in: CGRect(x: p.x - s / 2, y: p.y - s / 2, width: s, height: s))
            }
        }
    }

    /// Gasriese / Gesteinsplanet als Panoramatextur
    static func planet(_ p: Planet, seed: String) -> UIImage {
        var rng = SeededRNG(seed)
        let w: CGFloat = 512, h: CGFloat = 256
        return textureRenderer(CGSize(width: w, height: h), scale: 2).image { ctx in
            let g = ctx.cgContext
            let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                  colors: [uic(p.hue, 0.55, 0.5).cgColor, uic(p.hue, 0.6, 0.38).cgColor, uic(p.hue, 0.55, 0.5).cgColor] as CFArray,
                                  locations: [0, 0.5, 1])!
            g.drawLinearGradient(grad, start: .zero, end: CGPoint(x: 0, y: h), options: [])
            // wellige Wolkenbänder
            let bandH = h / CGFloat(p.bands.count)
            for (i, band) in p.bands.enumerated() {
                let y0 = CGFloat(i) * bandH
                let amp = bandH * 0.35
                let ph = CGFloat(i) * 1.7
                let path = UIBezierPath()
                path.move(to: CGPoint(x: 0, y: y0 + sin(ph) * amp))
                for k in 0...64 {
                    let x = w * CGFloat(k) / 64
                    path.addLine(to: CGPoint(x: x, y: y0 + sin(x / w * .pi * 6 + ph) * amp))
                }
                for k in stride(from: 64, through: 0, by: -1) {
                    let x = w * CGFloat(k) / 64
                    path.addLine(to: CGPoint(x: x, y: y0 + bandH + sin(x / w * .pi * 4 + ph + 1.3) * amp))
                }
                path.close()
                let col = band.dark ? uic(p.hue - 20, 0.5, 0.2, Double(band.alpha) * 0.45)
                                    : uic(p.hue2, 0.6, 0.78, Double(band.alpha) * 0.3)
                col.setFill()
                path.fill()
            }
            // feine Turbulenzen
            for _ in 0..<220 {
                let x = rng.c(0...w), y = rng.c(0...h)
                let r = rng.c(2...10)
                UIColor(white: rng.chance(0.5) ? 1 : 0, alpha: rng.c(0.03...0.08)).setFill()
                UIBezierPath(ovalIn: CGRect(x: x - r * 2, y: y - r / 2, width: r * 4, height: r)).fill()
            }
            if p.hasStorm {
                let sc = CGPoint(x: w * 0.6, y: h * 0.62)
                uic(p.hue + 30, 0.7, 0.42, 0.75).setFill()
                UIBezierPath(ovalIn: CGRect(x: sc.x - 40, y: sc.y - 16, width: 80, height: 32)).fill()
                uic(p.hue + 40, 0.75, 0.62, 0.6).setFill()
                UIBezierPath(ovalIn: CGRect(x: sc.x - 22, y: sc.y - 8, width: 44, height: 16)).fill()
            } else {
                for cr in p.craters {
                    let x = w * (cr.angle / (.pi * 2)), y = h * (0.25 + cr.dist * 0.5)
                    let r = cr.size * 90
                    UIColor(white: 0, alpha: 0.22).setFill()
                    UIBezierPath(ovalIn: CGRect(x: x - r, y: y - r * 0.7, width: r * 2, height: r * 1.4)).fill()
                    UIColor(white: 1, alpha: 0.1).setStroke()
                    let ring = UIBezierPath(ovalIn: CGRect(x: x - r, y: y - r * 0.7, width: r * 2, height: r * 1.4))
                    ring.lineWidth = 2
                    ring.stroke()
                }
            }
        }
    }

    /// Photonenring des Schwarzen Lochs: dünner, heller Saum knapp außerhalb des Kerns
    static let photonRing: UIImage = {
        let size: CGFloat = 256
        return textureRenderer(CGSize(width: size, height: size)).image { ctx in
            let c = CGPoint(x: size / 2, y: size / 2)
            let colors = [UIColor(red: 1, green: 0.75, blue: 0.45, alpha: 0).cgColor,
                          UIColor(red: 1, green: 0.93, blue: 0.8, alpha: 1).cgColor,
                          UIColor(red: 1, green: 0.6, blue: 0.3, alpha: 0.35).cgColor,
                          UIColor(red: 1, green: 0.5, blue: 0.2, alpha: 0).cgColor] as CFArray
            // Kern belegt 1/2.7 des Bildes, der Ring sitzt direkt daran
            let k = 1 / 2.7
            let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors,
                                  locations: [CGFloat(k * 0.97), CGFloat(k * 1.06), CGFloat(k * 1.3), 1])!
            ctx.cgContext.drawRadialGradient(grad, startCenter: c, startRadius: 0, endCenter: c,
                                             endRadius: size / 2, options: [])
        }
    }()

    /// Akkretionsscheibe: innen weißglühend, außen dunkelrot, mit spiralförmigen Schlieren
    static let accretionDisk: UIImage = {
        var rng = SeededRNG("accretion")
        let size: CGFloat = 512
        return textureRenderer(CGSize(width: size, height: size), scale: 2).image { ctx in
            let g = ctx.cgContext
            let c = CGPoint(x: size / 2, y: size / 2)
            let R = size / 2
            // Kern = 1/2.1 des Scheibenradius (siehe Planet.outerRadius)
            let inner = R / 2.1
            let colors = [UIColor(white: 0, alpha: 0).cgColor,
                          UIColor(red: 1, green: 0.95, blue: 0.85, alpha: 1).cgColor,
                          UIColor(red: 1, green: 0.62, blue: 0.25, alpha: 0.85).cgColor,
                          UIColor(red: 0.75, green: 0.18, blue: 0.08, alpha: 0.4).cgColor,
                          UIColor(red: 0.4, green: 0.05, blue: 0.05, alpha: 0).cgColor] as CFArray
            let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors,
                                  locations: [inner / R * 0.98, inner / R * 1.08, 0.66, 0.85, 1])!
            g.drawRadialGradient(grad, startCenter: c, startRadius: 0, endCenter: c, endRadius: R, options: [])
            // Schlieren: kurze Spiralbögen in hellen und dunklen Tönen
            for _ in 0..<160 {
                let r0 = rng.c(inner * 1.05...R * 0.92)
                let a0 = rng.c(0...(.pi * 2))
                let len = rng.c(0.3...1.1)
                let path = UIBezierPath()
                for k in 0...12 {
                    let t = CGFloat(k) / 12
                    let a = a0 + len * t
                    let rr = r0 * (1 + 0.06 * t)
                    let pt = CGPoint(x: c.x + cos(a) * rr, y: c.y + sin(a) * rr)
                    if k == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
                }
                path.lineWidth = rng.c(1...3.5)
                let hot = 1 - (r0 - inner) / (R - inner)
                (rng.chance(0.65) ? UIColor(red: 1, green: 0.8, blue: 0.55, alpha: 0.12 + 0.3 * hot)
                                  : UIColor(white: 0, alpha: 0.25)).setStroke()
                path.stroke()
            }
        }
    }()

    /// Sonnenoberfläche: Granulation und Flecken auf heller Grundfarbe
    static func sunSurface(hue: Double, seed: String) -> UIImage {
        var rng = SeededRNG(seed)
        let w: CGFloat = 256, h: CGFloat = 128
        return textureRenderer(CGSize(width: w, height: h), scale: 2).image { ctx in
            uic(hue, 0.95, 0.66).setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
            for _ in 0..<500 {
                let x = rng.c(0...w), y = rng.c(0...h), r = rng.c(1.5...5)
                (rng.chance(0.5) ? uic(hue + 8, 1, 0.85, 0.35) : uic(hue - 12, 0.9, 0.45, 0.25)).setFill()
                UIBezierPath(ovalIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)).fill()
            }
            for _ in 0..<3 {
                let x = rng.c(0...w), y = rng.c(h * 0.3...h * 0.7), r = rng.c(3...7)
                uic(hue - 20, 0.8, 0.3, 0.6).setFill()
                UIBezierPath(ovalIn: CGRect(x: x - r * 1.4, y: y - r, width: r * 2.8, height: r * 2)).fill()
            }
        }
    }

    private static var ringCache: [Int: UIImage] = [:]

    /// Bei Speicherwarnung: Ringtexturen neu erzeugen lassen statt sie vorzuhalten
    static func purge() { ringCache.removeAll() }

    /// Ringtextur je Farbton nur einmal erzeugen (gleicher Farbton ergibt ohnehin dasselbe Bild)
    static func ring(hue: Double) -> UIImage {
        if let img = cachedRing(hue: hue) { return img }
        let img = makeRing(hue: hue)
        storeRing(img, hue: hue)
        return img
    }

    /// Zugriff auf den Vorrat nur vom Hauptthread
    static func cachedRing(hue: Double) -> UIImage? { ringCache[Int(hue)] }

    static func storeRing(_ img: UIImage, hue: Double) {
        // kleiner Vorrat genügt, es sind immer nur wenige Planeten gleichzeitig in der Szene
        if ringCache.count > 8 { ringCache.removeAll() }
        ringCache[Int(hue)] = img
    }

    /// darf auf jedem Thread laufen
    static func makeRing(hue: Double) -> UIImage {
        var rng = SeededRNG("ring\(Int(hue))")
        let s: CGFloat = 512
        return textureRenderer(CGSize(width: s, height: s), scale: 2).image { ctx in
            let g = ctx.cgContext
            var r: CGFloat = s / 2
            while r > s * 0.3 {
                let wdt = rng.c(3...14)
                g.setStrokeColor(uic(hue + rng.d(-20...40), 0.45, rng.d(0.55...0.85), rng.d(0.15...0.7)).cgColor)
                g.setLineWidth(wdt)
                g.strokeEllipse(in: CGRect(x: s / 2 - r, y: s / 2 - r, width: r * 2, height: r * 2))
                r -= wdt + rng.c(0...6)
            }
        }
    }

    static let rock: UIImage = {
        var rng = SeededRNG("rock")
        let s: CGFloat = 256
        return textureRenderer(CGSize(width: s, height: s)).image { ctx in
            UIColor(red: 0.42, green: 0.38, blue: 0.35, alpha: 1).setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: s, height: s))
            for _ in 0..<500 {
                let r = rng.c(2...16)
                UIColor(white: rng.chance(0.5) ? 0.75 : 0.1, alpha: rng.c(0.05...0.2)).setFill()
                UIBezierPath(ovalIn: CGRect(x: rng.c(0...s), y: rng.c(0...s), width: r, height: r)).fill()
            }
        }
    }()

    private static var badgeCache: [ItemKind: UIImage] = [:]

    /// Hexagon-Plakette mit Symbol (Items und Ladering), je Sorte nur einmal gezeichnet
    static func badge(_ kind: ItemKind) -> UIImage {
        if let img = badgeCache[kind] { return img }
        let img = makeBadge(kind)
        badgeCache[kind] = img
        return img
    }

    private static func makeBadge(_ kind: ItemKind) -> UIImage {
        let s: CGFloat = 128
        let col = uic(kind.hue, 0.85, 0.62)
        return textureRenderer(CGSize(width: s, height: s)).image { _ in
            let hex = UIBezierPath()
            for k in 0..<6 {
                let a = CGFloat(k) * .pi / 3 + .pi / 6
                let p = CGPoint(x: s / 2 + cos(a) * s * 0.44, y: s / 2 + sin(a) * s * 0.44)
                if k == 0 { hex.move(to: p) } else { hex.addLine(to: p) }
            }
            hex.close()
            UIColor(red: 0.02, green: 0.07, blue: 0.11, alpha: 0.9).setFill()
            hex.fill()
            col.setStroke()
            hex.lineWidth = 6
            hex.stroke()
            let conf = UIImage.SymbolConfiguration(pointSize: 48, weight: .bold)
            if let sym = UIImage(systemName: kind.symbol, withConfiguration: conf)?.withTintColor(col, renderingMode: .alwaysOriginal) {
                let sz = sym.size
                sym.draw(in: CGRect(x: (s - sz.width) / 2, y: (s - sz.height) / 2, width: sz.width, height: sz.height))
            }
        }
    }
}

extension ItemKind {
    var symbol: String {
        switch self {
        case .energy: return "bolt.fill"
        case .wideCone: return "dot.radiowaves.forward"
        case .superBomb: return "burst.fill"
        case .rescue: return "flame.fill"
        case .tech: return "gearshape.fill"
        case .shipPart: return "puzzlepiece.fill"
        }
    }
}

// MARK: - Asteroiden-Geometrie

enum RockMesh {
    static let variants: [SCNGeometry] = (0..<6).map { make(seed: "rock\($0)") }

    static func make(seed: String) -> SCNGeometry {
        var rng = SeededRNG(seed)
        let lat = 8, lon = 12
        var grid: [[SCNVector3]] = []
        for i in 0...lat {
            let th = Float(i) / Float(lat) * .pi
            var row: [SCNVector3] = []
            for j in 0..<lon {
                let ph = Float(j) / Float(lon) * .pi * 2
                let r = Float(rng.d(0.72...1.12))
                let rr = (i == 0 || i == lat) ? 0.9 : r
                row.append(SCNVector3(sin(th) * cos(ph) * rr, cos(th) * rr * 0.85, sin(th) * sin(ph) * rr))
            }
            grid.append(row)
        }
        var verts: [SCNVector3] = []
        var norms: [SCNVector3] = []
        var uvs: [CGPoint] = []
        func tri(_ a: SCNVector3, _ b: SCNVector3, _ c: SCNVector3) {
            let u = SCNVector3(b.x - a.x, b.y - a.y, b.z - a.z)
            let v = SCNVector3(c.x - a.x, c.y - a.y, c.z - a.z)
            var n = SCNVector3(u.y * v.z - u.z * v.y, u.z * v.x - u.x * v.z, u.x * v.y - u.y * v.x)
            let len = max(0.0001, sqrt(n.x * n.x + n.y * n.y + n.z * n.z))
            n = SCNVector3(n.x / len, n.y / len, n.z / len)
            // nach außen zeigen lassen
            let mid = SCNVector3((a.x + b.x + c.x) / 3, (a.y + b.y + c.y) / 3, (a.z + b.z + c.z) / 3)
            if n.x * mid.x + n.y * mid.y + n.z * mid.z < 0 {
                verts += [a, c, b]
                n = SCNVector3(-n.x, -n.y, -n.z)
            } else {
                verts += [a, b, c]
            }
            norms += [n, n, n]
            for p in [a, b, c] { uvs.append(CGPoint(x: CGFloat(p.x * 0.5 + 0.5), y: CGFloat(p.z * 0.5 + 0.5))) }
        }
        for i in 0..<lat {
            for j in 0..<lon {
                let j2 = (j + 1) % lon
                tri(grid[i][j], grid[i + 1][j], grid[i + 1][j2])
                tri(grid[i][j], grid[i + 1][j2], grid[i][j2])
            }
        }
        let idx = (0..<Int32(verts.count)).map { $0 }
        let geo = SCNGeometry(sources: [SCNGeometrySource(vertices: verts), SCNGeometrySource(normals: norms),
                                        SCNGeometrySource(textureCoordinates: uvs)],
                              elements: [SCNGeometryElement(indices: idx, primitiveType: .triangles)])
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = WorldTextures.rock
        m.roughness.contents = 0.9
        m.metalness.contents = 0.1
        m.emission.contents = UIColor(red: 0.12, green: 0.05, blue: 0.02, alpha: 1)
        geo.materials = [m]
        return geo
    }
}

// MARK: - Welt

final class World3D {
    let scene = SCNScene()
    let cameraNode = SCNNode()
    weak var view: SCNView?

    /// 0 = Draufsicht, 1 = Verfolgerkamera hinter dem Schiff
    private(set) var chase: CGFloat = 0
    private var chaseOn = false
    /// Ausgleiten ohne Energie: Kamera rückt noch dichter ans Schiff (0…1)
    private var coastClose: CGFloat = 0
    /// Explosion: Kamera schaut auf das Wrack statt voraus und weicht etwas zurück (0…1)
    private var blastView: CGFloat = 0
    private var releasing = false
    private var chasedThisFlight = false
    /// geglätteter Kurs für die Verfolgerkamera, damit Lenkkorrekturen nicht als Ruckler ankommen
    private var chaseHeading = SmoothAngle(0)
    /// 1 = Hangar-Nahaufnahme, läuft nach dem Start in die normale Kamera aus
    private var hangar: CGFloat = 1
    /// Schrägblick auf die Raumstation, solange das Stationsmenü offen ist (0…1)
    private var stationView: CGFloat = 0
    private var lastUITime: CGFloat = 0
    private let hangarBlendTime: CGFloat = 1.8
    private let dockNode = SCNNode()
    private var lastHangarFade: CGFloat = 0
    private var lastPhase: Game.Phase = .orbiting

    private var generation = -1
    private var planetNodes: [Int: SCNNode] = [:]
    private struct BonusRing {
        let node: SCNNode
        let progress: SCNNode
        /// Materialien der Fortschrittsbögen (Schein, Kern, heller Strich); ihr Shader blendet den Rest des Rings aus
        let arcMats: [SCNMaterial]
        let head: SCNNode
        let radius: CGFloat
        var step = -1
    }
    private var bonusRings: [Int: BonusRing] = [:]
    private var asteroidNodes: [Int: SCNNode] = [:]
    /// Andockplattformen der Raumstationen, je Planetenindex
    private var stationDocks: [Int: SCNNode] = [:]
    private var itemNodes: [Int: SCNNode] = [:]
    private var projectileNodes: [Int: SCNNode] = [:]
    private var enemyShotNodes: [Int: SCNNode] = [:]
    private var cloudNodes: [Int: SCNNode] = [:]
    private var seenBeams = Set<Int>()
    private var seenWaves = Set<Int>()

    private let shipHolder = SCNNode()
    private let bankNode = SCNNode()
    private var shipModelNode: SCNNode?
    /// unzusammengefasstes Modell des aktuellen Schiffs: liefert die Wrackteile für die Explosion
    private var debrisSource: SCNNode?
    private var exploded = false
    /// Teile mit Düsenglut und ihre aktuelle Helligkeit
    private var nozzleMats: [SCNMaterial] = []
    /// Grundfarbe je Glut-Material (Düsenglut orange, Leuchtringe der Waffe in Waffenfarbe)
    private var nozzleBase: [UIColor] = []
    private var nozzleHalos: [SCNNode] = []
    private var appliedNozzleGlow: CGFloat = 1
    private var nozzleGlow: CGFloat = 1
    private var lastNozzleTime: CGFloat = 0
    private var shipID = ""
    private let exhaust = SCNParticleSystem()
    private var exhausts: [(SCNParticleSystem, CGFloat)] = []
    private let trail = SCNParticleSystem()
    // Schadensbild: Rauch ab 50 % Panzerung, Funken ab 25 %, rotes Aufblitzen bei Treffern
    private let damageSmoke = SCNParticleSystem()
    private let damageSparks = SCNParticleSystem()
    private let hitFlash = SCNNode()
    private var hitShellMat: SCNMaterial?
    private let impactSparks = SCNParticleSystem()
    private var lastBrakeFlash: CGFloat = 0
    private var hitAt: CGFloat = -10
    private var appliedHit: Float = -1

    private let orbitGroup = SCNNode()
    private let orbitRing = SCNNode()
    private let arrowSpinner = SCNNode()
    private let coneNode = SCNNode()
    private var coneKey = ""
    private var coneMats: [SCNMaterial] = []
    private static let orbitRevealTime: CGFloat = 1.1
    private var orbitReveal: CGFloat = 0   // 0…1 linear seit Eintritt in den Orbit
    private var coneHeat: CGFloat = 0      // weicher Übergang grau → grün im Kegel
    private var orbitIndex = -1

    private let lockGroup = SCNNode()
    private let lockArcs = SCNNode()
    private let lockTicks = SCNNode()
    private let lockHolo = SCNNode()
    private var lockIndex = -1

    private let dust = SCNNode()
    private let dustTile: CGFloat = 5000
    private var lastTime: CGFloat = 0

    init() {
        scene.background.contents = WorldTextures.sky
        scene.lightingEnvironment.contents = WorldTextures.skyLight
        scene.lightingEnvironment.intensity = 0.5

        let cam = SCNCamera()
        cam.fieldOfView = 50
        cam.zNear = 4
        cam.zFar = 400000
        cam.wantsHDR = true
        cam.bloomIntensity = 0.9
        cam.bloomThreshold = 0.9
        cam.bloomBlurRadius = 10
        cam.wantsExposureAdaptation = false
        cameraNode.camera = cam
        scene.rootNode.addChildNode(cameraNode)

        let sun = SCNNode()
        sun.light = SCNLight()
        sun.light?.type = .directional
        sun.light?.intensity = 2200
        sun.light?.color = UIColor(red: 1, green: 0.96, blue: 0.9, alpha: 1)
        sun.eulerAngles = SCNVector3(-Float.pi / 6, Float.pi / 2.3, 0)
        scene.rootNode.addChildNode(sun)
        let amb = SCNNode()
        amb.light = SCNLight()
        amb.light?.type = .ambient
        amb.light?.intensity = 90
        amb.light?.color = UIColor(red: 0.45, green: 0.55, blue: 0.85, alpha: 1)
        scene.rootNode.addChildNode(amb)

        buildDust()
        buildShipFX()
        scene.rootNode.addChildNode(shipHolder)
        shipHolder.addChildNode(bankNode)
        scene.rootNode.addChildNode(orbitGroup)
        scene.rootNode.addChildNode(lockGroup)
        buildOrbitParts()
        buildDock()
        // Stationslacke schon während des Ladebildschirms erzeugen, sonst hakt es beim Auftauchen der ersten Station
        for (key, c) in StationModels.paints {
            _ = WornPaint.material(key, base: c)
        }
        // Texturen des Schwarzen Lochs entstehen beim ersten Zugriff; das im Hintergrund erledigen
        Self.textureQueue.async {
            _ = WorldTextures.accretionDisk
            _ = WorldTextures.photonRing
        }
        scene.rootNode.addChildNode(dockNode)
    }

    // MARK: Hangar

    /// Startplattform im Stil der Schiffe: gleicher Baukasten (ShipKit) mit abgenutztem Lack, Panzerplatten,
    /// facettierten Trägern, Leitungen und Kleinteilen. Gebaut in Schiffseinheiten und wie das Schiff im
    /// Hangar fünffach skaliert. Lokal zeigt +x in Flugrichtung, das Deck liegt knapp unter dem Schiff.
    private func buildDock() {
        let k = ShipKit(seed: "dock", base: ShipDesigns.bone, accent: ShipDesigns.red, second: ShipDesigns.gunmetal,
                        weaponHue: 165, marking: "PAD")
        let edge = ShipKit.glow(UIColor(red: 79 / 255, green: 227 / 255, blue: 193 / 255, alpha: 1))
        let amber = ShipKit.glow(UIColor(red: 1, green: 0.55, blue: 0.15, alpha: 1))

        // Deck: gekantetes Achteck wie die Flügel, darunter ein dunkler Rahmen
        let deck: [(CGFloat, CGFloat)] = [(5, -3), (5, 3), (3.8, 4.2), (-3.8, 4.2), (-5, 3), (-5, -3), (-3.8, -4.2), (3.8, -4.2)]
        k.plate(deck, y: -0.15, thick: 0.3, k.paint, mirror: false)
        k.plate(deck.map { ($0.0 * 1.05, $0.1 * 1.05) }, y: -0.42, thick: 0.3, k.dark, mirror: false)
        // Panzerplatten mit Nähten quer über das Deck
        k.plates(x0: -4.4, x1: 4.0, y: -0.02, width: 6.4, count: 7)
        // Warnstreifen an Vorder- und Hinterkante
        k.box(4.7, 0.06, 0, 0.45, 0.1, 5.6, k.stripe, chamfer: 0.03, mirror: false)
        k.box(-4.7, 0.06, 0, 0.45, 0.1, 5.6, k.stripe, chamfer: 0.03, mirror: false)

        // Landekreis mit Leuchtring und Lampen
        let ring = SCNTube(innerRadius: 1.55, outerRadius: 1.7, height: 0.04)
        ring.radialSegmentCount = 64
        k.addNode(ring, edge, SCNVector3(0, 0.15, 0))
        let disc = SCNCylinder(radius: 1.5, height: 0.06)
        disc.radialSegmentCount = 48
        k.addNode(disc, k.second, SCNVector3(0, 0.12, 0))
        for i in 0..<8 {
            let a = Float(i) / 8 * .pi * 2
            k.box(cos(a) * 2.05, 0.15, sin(a) * 2.05, 0.18, 0.06, 0.18, amber, chamfer: 0.01, mirror: false)
        }
        // Leuchtkanten an den Seiten und eine gestrichelte Startlinie vorn
        k.box(0, 0.12, 4.05, 7.4, 0.06, 0.1, edge, chamfer: 0.01)
        for i in 0..<4 { k.box(4.35, 0.12, Float(i) * 1.6 - 2.4, 0.1, 0.06, 0.9, edge, chamfer: 0.01, mirror: false) }

        // Seitenträger: facettiert wie die Rümpfe, mit Leitungen und Seitenpaneelen
        k.hull([ShipKit.Sec(-4.6, 0.25, 0.32, 0.3), ShipKit.Sec(-3.8, 0.3, 0.38, 0.36),
                ShipKit.Sec(3.6, 0.3, 0.38, 0.36), ShipKit.Sec(4.4, 0.25, 0.32, 0.3)], z: 4.65, k.second)
        k.pipes(x0: -4.2, x1: 3.8, y: 0.2, z: 4.25)
        k.sidePanels(x0: -3.6, x1: 3.4, y: 0.2, z: 5.05, count: 5)

        // Tor vorn: zwei gepanzerte Pylonen mit Brücke, das Schiff startet hindurch
        k.box(4.4, 2.3, 4.6, 0.75, 4.6, 0.75, k.paint, chamfer: 0.12)
        k.box(4.4, 1.0, 4.6, 0.85, 0.5, 0.85, k.stripe, chamfer: 0.06)
        k.box(4.4, 3.4, 4.6, 0.85, 0.35, 0.85, k.dark, chamfer: 0.06)
        k.intake(4.4, 2.2, 4.2, h: 0.6, w: 0.3)
        k.lamp(4.4, 4.75, 4.6, size: 0.3)
        k.box(4.4, 4.3, 0, 0.7, 0.5, 9.9, k.accent, chamfer: 0.1, mirror: false)
        k.box(4.4, 4.0, 0, 0.5, 0.2, 9.4, k.dark, chamfer: 0.04, mirror: false)
        for z: Float in [-3, -1, 1, 3] { k.lamp(4.75, 4.3, z, size: 0.14) }

        // Heck: Lufteinlässe, Kleinteile und Antennen
        k.intake(-4.55, 0.35, 2.6, h: 0.45, w: 0.7)
        k.greeble(x0: -4.8, x1: -3.6, y: 0.05, zMax: 1.8, count: 12)
        k.antenna(-4.3, 0.4, 3.9, h: 2.2)
        k.box(-4.2, 0.25, 3.3, 0.6, 0.5, 0.5, k.metal, chamfer: 0.05)

        k.root.scale = SCNVector3(5, 5, 5)
        dockNode.addChildNode(k.root)

        // eigenes Licht für die Nahaufnahme
        let light = SCNNode()
        light.light = SCNLight()
        light.light?.type = .omni
        light.light?.intensity = 700
        light.light?.color = UIColor(red: 0.85, green: 0.92, blue: 1, alpha: 1)
        light.light?.attenuationStartDistance = 20
        light.light?.attenuationEndDistance = 140
        light.position = SCNVector3(-8, 34, 0)
        dockNode.addChildNode(light)
    }

    private func syncDock(_ game: Game) {
        // knapp unter dem Schiff (Schiffsmitte auf Höhe 4); bleibt stehen, bis der erste Planet erreicht ist
        dockNode.isHidden = game.score > 0 || game.phase == .over
        dockNode.position = v3(game.dockPos, -1)
        dockNode.eulerAngles.y = Float(-game.dockHeading)
    }

    // MARK: Aufbau

    private func buildDust() {
        // Staub unterhalb der Ebene gibt Parallaxe beim Kamerawechsel
        var rng = SeededRNG("dust")
        var pts: [SCNVector3] = []
        for _ in 0..<420 {
            pts.append(SCNVector3(Float(rng.c(0...dustTile)), Float(rng.c(-2400 ... -250)), Float(rng.c(0...dustTile))))
        }
        let src = SCNGeometrySource(vertices: pts)
        let el = SCNGeometryElement(indices: (0..<Int32(pts.count)).map { $0 }, primitiveType: .point)
        el.pointSize = 2
        el.minimumPointScreenSpaceRadius = 0.5
        el.maximumPointScreenSpaceRadius = 1.4
        let geo = SCNGeometry(sources: [src], elements: [el])
        geo.materials = [glowMat(UIColor(red: 0.3, green: 0.36, blue: 0.5, alpha: 1))]
        for i in -1...1 {
            for j in -1...1 {
                let n = SCNNode(geometry: geo)
                n.position = SCNVector3(Float(CGFloat(i) * dustTile), 0, Float(CGFloat(j) * dustTile))
                dust.addChildNode(n)
            }
        }
        scene.rootNode.addChildNode(dust)
    }

    private func buildShipFX() {
        damageSmoke.birthRate = 0
        damageSmoke.particleLifeSpan = 1.3
        damageSmoke.particleLifeSpanVariation = 0.4
        damageSmoke.particleVelocity = 0
        // weiche, gefüllte Puffs (dot ist ein Leuchtring und sähe wie eine Perlenkette aus)
        damageSmoke.particleImage = WorldTextures.soft
        damageSmoke.particleSizeVariation = 0.5
        damageSmoke.particleAngleVariation = 180
        damageSmoke.particleAngularVelocityVariation = 60
        damageSmoke.emitterShape = SCNSphere(radius: 0.8)
        damageSmoke.blendMode = .alpha
        damageSmoke.isLightingEnabled = false
        damageSmoke.isAffectedByGravity = false
        damageSmoke.particleColor = UIColor(white: 0.5, alpha: 0.45)
        damageSmoke.particleColorVariation = SCNVector4(0, 0, 0.15, 0)
        let fade = CAKeyframeAnimation()
        fade.values = [0.9, 0.5, 0]
        let grow = CAKeyframeAnimation()
        grow.values = [0.5, 1.4, 2.4]
        damageSmoke.propertyControllers = [.opacity: SCNParticlePropertyController(animation: fade),
                                           .size: SCNParticlePropertyController(animation: grow)]
        shipHolder.addParticleSystem(damageSmoke)

        damageSparks.birthRate = 0
        damageSparks.particleLifeSpan = 0.35
        damageSparks.particleLifeSpanVariation = 0.15
        damageSparks.spreadingAngle = 180
        damageSparks.particleImage = WorldTextures.soft
        // kurze Leuchtschweife in Flugrichtung der Funken
        damageSparks.stretchFactor = 0.08
        damageSparks.blendMode = .additive
        damageSparks.isLightingEnabled = false
        damageSparks.isAffectedByGravity = false
        damageSparks.particleColor = UIColor(red: 1, green: 0.78, blue: 0.4, alpha: 1)
        let sparkFade = CAKeyframeAnimation()
        sparkFade.values = [1, 0]
        damageSparks.propertyControllers = [.opacity: SCNParticlePropertyController(animation: sparkFade)]
        shipHolder.addParticleSystem(damageSparks)

        // Treffer: kurz aufleuchtende Schildhülle um das Schiff, nur am Rand hell (Fresnel), dazu Funken.
        // Bleibt immer in der Szene (mit Stärke 0), damit der Shader schon beim Laden übersetzt ist.
        let shell = SCNSphere(radius: 3.4)
        shell.segmentCount = 40
        let fm = SCNMaterial()
        fm.lightingModel = .constant
        fm.diffuse.contents = UIColor.black
        fm.blendMode = .add
        fm.writesToDepthBuffer = false
        fm.isDoubleSided = false
        fm.shaderModifiers = [.fragment: """
        #pragma arguments
        float intensity;
        #pragma body
        float3 n = normalize(_surface.normal);
        float3 v = normalize(_surface.view);
        float rim = pow(1.0 - saturate(abs(dot(n, v))), 2.4);
        float3 col = mix(float3(1.0, 0.25, 0.12), float3(1.0, 0.85, 0.6), rim * rim);
        _output.color = float4(col * (rim * 1.6 + 0.04) * intensity, 0.0);
        """]
        fm.setValue(0.0 as Float, forKey: "intensity")
        shell.materials = [fm]
        hitShellMat = fm
        hitFlash.geometry = shell
        hitFlash.scale = SCNVector3(1.25, 0.6, 1.0)
        hitFlash.renderingOrder = 50
        shipHolder.addChildNode(hitFlash)

        impactSparks.birthRate = 0
        impactSparks.particleLifeSpan = 0.4
        impactSparks.particleLifeSpanVariation = 0.2
        impactSparks.spreadingAngle = 180
        impactSparks.particleImage = WorldTextures.soft
        impactSparks.stretchFactor = 0.1
        impactSparks.blendMode = .additive
        impactSparks.isLightingEnabled = false
        impactSparks.isAffectedByGravity = false
        impactSparks.particleColor = UIColor(red: 1, green: 0.6, blue: 0.3, alpha: 1)
        let impactFade = CAKeyframeAnimation()
        impactFade.values = [1, 0]
        impactSparks.propertyControllers = [.opacity: SCNParticlePropertyController(animation: impactFade)]
        shipHolder.addParticleSystem(impactSparks)

        exhaust.birthRate = 0
        exhaust.isLocal = true
        exhaust.particleLifeSpan = 0.09
        exhaust.particleLifeSpanVariation = 0.03
        exhaust.emittingDirection = SCNVector3(-1, 0, 0)
        exhaust.spreadingAngle = 10
        exhaust.particleImage = WorldTextures.dot
        exhaust.blendMode = .additive
        exhaust.isLightingEnabled = false
        exhaust.isAffectedByGravity = false
        exhaust.particleColor = UIColor(red: 1, green: 0.7, blue: 0.35, alpha: 1)

        trail.birthRate = 0
        trail.particleLifeSpan = 0.9
        trail.particleVelocity = 0
        trail.particleImage = WorldTextures.dot
        trail.blendMode = .additive
        trail.isLightingEnabled = false
        trail.isAffectedByGravity = false
        trail.particleColor = UIColor(red: 0.2, green: 0.55, blue: 0.48, alpha: 1)
        let anim = CAKeyframeAnimation()
        anim.values = [1, 0]
        trail.propertyControllers = [.opacity: SCNParticlePropertyController(animation: anim)]
        let tr = SCNNode()
        tr.position = SCNVector3(-2.4, 0, 0)

        shipHolder.addChildNode(tr)
    }

    private func buildOrbitParts() {
        orbitGroup.addChildNode(orbitRing)
        orbitGroup.addChildNode(arrowSpinner)
        orbitGroup.addChildNode(coneNode)
        lockGroup.addChildNode(lockArcs)
        lockGroup.addChildNode(lockTicks)
        lockGroup.addChildNode(lockHolo)
    }

    private func clearAll() {
        for d in [planetNodes, asteroidNodes, itemNodes, projectileNodes, cloudNodes, enemyShotNodes] {
            d.values.forEach { $0.removeFromParentNode() }
        }
        bonusRings.values.forEach { $0.node.removeFromParentNode() }
        stationDocks.values.forEach { $0.removeFromParentNode() }
        stationDocks = [:]
        planetNodes = [:]; asteroidNodes = [:]; itemNodes = [:]; projectileNodes = [:]; cloudNodes = [:]; bonusRings = [:]; enemyShotNodes = [:]
        seenBeams = []; seenWaves = []
        orbitIndex = -1; lockIndex = -1; coneKey = ""
        arrivalIndex = -1; arrivalActive = false; arrival = 0
        trail.reset()
    }

    // MARK: Planeten

    /// Planeten- und Ringtexturen entstehen im Hintergrund: ein Planet braucht dafür um 50 ms, auf dem
    /// Hauptthread war das jedes Mal ein spürbarer Hänger. Neue Planeten liegen weit voraus, bis sie ins Bild
    /// kommen, ist die Textur längst da.
    private static let textureQueue = DispatchQueue(label: "orbix.textures", qos: .userInitiated)

    /// Lädt Texturen und Shader eines Materials oder Knotens vorab auf die GPU und ruft dann `then` auf dem
    /// Hauptthread auf. Ohne das erledigt SceneKit es im ersten Bild, in dem das Objekt auftaucht, und dieses Bild hängt.
    private func upload(_ object: Any, then: @escaping () -> Void) {
        guard let view else { then(); return }
        view.prepare([object]) { _ in DispatchQueue.main.async(execute: then) }
    }

    private func makePlanet(_ p: Planet, index: Int, immediate: Bool) -> SCNNode {
        let root = SCNNode()
        root.position = v3(p.center)
        // Raumstation statt Planet: eigenes Modell, kein Planetenkörper
        if p.isStation {
            root.addChildNode(makeStation(p))
            return root
        }
        switch p.kind {
        case .normal: break
        case .blackHole:
            root.addChildNode(makeBlackHole(p))
            return root
        case .binary:
            root.addChildNode(makeBinary(p, seed: "binary\(index)", immediate: immediate))
            return root
        }

        let tilt = SCNNode()
        tilt.eulerAngles = SCNVector3(Float(p.tilt) * 0.6, 0, Float(p.tilt))
        root.addChildNode(tilt)

        let sphere = SCNSphere(radius: p.radius)
        sphere.segmentCount = 64
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        let seed = "planet\(index)"
        if immediate {
            m.diffuse.contents = WorldTextures.planet(p, seed: seed)
        } else {
            // Grundfarbe als Platzhalter, bis die Textur fertig ist
            m.diffuse.contents = uic(p.hue, 0.55, 0.45)
            Self.textureQueue.async { [weak self] in
                let img = WorldTextures.planet(p, seed: seed)
                DispatchQueue.main.async {
                    let ready = m.copy() as! SCNMaterial
                    ready.diffuse.contents = img
                    self?.upload(ready) { sphere.materials = [ready] }
                }
            }
        }
        m.roughness.contents = 0.85
        m.metalness.contents = 0
        sphere.materials = [m]
        let body = SCNNode(geometry: sphere)
        body.runAction(.repeatForever(.rotateBy(x: 0, y: .pi * 2, z: 0, duration: Double(60 / max(0.4, p.spin)))))
        tilt.addChildNode(body)

        // Atmosphäre: leuchtender Rand
        let atmo = SCNSphere(radius: p.radius * 1.06)
        atmo.segmentCount = 48
        let am = SCNMaterial()
        am.lightingModel = .constant
        am.diffuse.contents = UIColor.black
        am.blendMode = .add
        am.writesToDepthBuffer = false
        am.shaderModifiers = [.fragment: """
            #pragma arguments
            float3 rimColor;
            #pragma body
            float f = 1.0 - abs(dot(normalize(_surface.normal), normalize(_surface.view)));
            _output.color = float4(rimColor * pow(f, 2.2) * 1.6, 1.0);
            """]
        let c = uic(p.hue, 0.85, 0.7)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c.getRed(&r, green: &g, blue: &b, alpha: &a)
        am.setValue(SCNVector3(Float(r), Float(g), Float(b)), forKey: "rimColor")
        atmo.materials = [am]
        root.addChildNode(SCNNode(geometry: atmo))

        if p.hasRing {
            let rx = min(p.radius * 1.9, p.radius + 60)
            let path = UIBezierPath(ovalIn: CGRect(x: -rx, y: -rx, width: rx * 2, height: rx * 2))
            path.append(UIBezierPath(ovalIn: CGRect(x: -p.radius * 1.25, y: -p.radius * 1.25, width: p.radius * 2.5, height: p.radius * 2.5)))
            path.usesEvenOddFillRule = true
            let rm = SCNMaterial()
            // Form entsteht erst unten; die Textur kann frühestens im nächsten Durchlauf des Hauptthreads kommen
            weak var shape: SCNGeometry?
            rm.lightingModel = .lambert
            if let img = WorldTextures.cachedRing(hue: p.hue) {
                rm.diffuse.contents = img
            } else if immediate {
                rm.diffuse.contents = WorldTextures.ring(hue: p.hue)
            } else {
                // unsichtbar, bis die Ringtextur im Hintergrund fertig ist
                rm.diffuse.contents = UIColor.clear
                let hue = p.hue
                Self.textureQueue.async { [weak self] in
                    let img = WorldTextures.makeRing(hue: hue)
                    DispatchQueue.main.async {
                        WorldTextures.storeRing(img, hue: hue)
                        let ready = rm.copy() as! SCNMaterial
                        ready.diffuse.contents = img
                        self?.upload(ready) { shape?.materials = [ready] }
                    }
                }
            }
            rm.isDoubleSided = true
            rm.writesToDepthBuffer = true
            rm.transparencyMode = .aOne
            let ring = flatShape(path, rm, depth: 0.5)
            shape = ring.geometry
            tilt.addChildNode(ring)
        }

        if p.hasMoon {
            let spin = SCNNode()
            spin.eulerAngles = SCNVector3(Float(p.tilt), Float(p.moonPhase), 0)
            spin.runAction(.repeatForever(.rotateBy(x: 0, y: .pi * 2, z: 0, duration: 25)))
            let mr = max(9, p.radius * 0.16)
            let moon = SCNSphere(radius: mr)
            let mm = SCNMaterial()
            mm.lightingModel = .physicallyBased
            mm.diffuse.contents = WorldTextures.rock
            mm.roughness.contents = 0.95
            moon.materials = [mm]
            let mn = SCNNode(geometry: moon)
            mn.position = SCNVector3(Float(p.radius * 1.5 + 80), 0, 0)
            spin.addChildNode(mn)
            root.addChildNode(spin)
        }
        return root
    }

    // MARK: Sonderplaneten

    /// Schwarzes Loch: lichtloser Kern, heller Photonenring, rotierende Akkretionsscheibe und
    /// ein zweiter, aufgerichteter Scheibenbogen als Andeutung der Lichtablenkung
    private func makeBlackHole(_ p: Planet) -> SCNNode {
        let root = SCNNode()
        let r = p.radius

        // Kern: absolut schwarz und deckend, verdeckt alles dahinter
        let core = SCNSphere(radius: r)
        core.segmentCount = 48
        let cm = SCNMaterial()
        cm.lightingModel = .constant
        cm.diffuse.contents = UIColor.black
        core.materials = [cm]
        let coreNode = SCNNode(geometry: core)
        coreNode.renderingOrder = 5
        root.addChildNode(coreNode)

        // Photonenring: schmaler, heller Saum, immer zur Kamera gedreht
        let halo = SCNNode(geometry: SCNPlane(width: r * 2.7, height: r * 2.7))
        halo.geometry?.materials = [spriteMat(WorldTextures.photonRing)]
        halo.constraints = [SCNBillboardConstraint()]
        halo.renderingOrder = 6
        root.addChildNode(halo)

        // weiter, schwacher Schein
        let glow = SCNNode(geometry: SCNPlane(width: r * 4, height: r * 4))
        let gm = spriteMat(WorldTextures.soft)
        gm.multiply.contents = uic(p.hue, 0.9, 0.5, 0.2)
        glow.geometry?.materials = [gm]
        glow.constraints = [SCNBillboardConstraint()]
        root.addChildNode(glow)

        // Akkretionsscheibe: liegt flach in der Bahnebene, genau wie die Orbit- und Bonusringe, und wirkt
        // deshalb aus jeder Kamera so elliptisch wie diese; dreht sich innen sichtbar schnell
        let tilt = SCNNode()
        root.addChildNode(tilt)
        let diskSize = p.outerRadius * 2
        let disk = SCNNode(geometry: SCNPlane(width: diskSize, height: diskSize))
        disk.geometry?.materials = [spriteMat(WorldTextures.accretionDisk)]
        disk.eulerAngles.x = -.pi / 2
        disk.renderingOrder = 7
        let spinner = SCNNode()
        spinner.addChildNode(disk)
        spinner.runAction(.repeatForever(.rotateBy(x: 0, y: -.pi * 2, z: 0, duration: 7)))
        tilt.addChildNode(spinner)
        // (Früher lag hier ein zur Kamera gedrehtes rundes Abbild der Scheibe als Lichtablenkung.
        // Es ließ das Ganze wie eine leuchtende Kugel wirken und ist deshalb entfallen.)
        return root
    }

    /// Doppelstern: zwei Sonnen umkreisen den gemeinsamen Schwerpunkt. Der Winkel kommt aus dem Spiel,
    /// damit das Pendeln der Bahn zur sichtbaren Stellung der Sonnen passt.
    private func makeBinary(_ p: Planet, seed: String, immediate: Bool) -> SCNNode {
        let root = SCNNode()
        let pair = SCNNode()
        pair.name = "binary"
        root.addChildNode(pair)
        let suns: [(hue: Double, size: CGFloat, dist: CGFloat)] = [(42, 0.42, 0.52), (205, 0.3, 0.68)]
        for (k, sun) in suns.enumerated() {
            let r = p.radius * sun.size
            let holder = SCNNode()
            // erste Sonne auf dem Winkel, zweite gegenüber; die kleinere läuft weiter außen (gemeinsamer Schwerpunkt)
            let side: Float = k == 0 ? 1 : -1
            holder.position = SCNVector3(side * Float(p.radius * sun.dist), 0, 0)
            pair.addChildNode(holder)

            let sphere = SCNSphere(radius: r)
            sphere.segmentCount = 48
            let m = SCNMaterial()
            m.lightingModel = .constant
            let sunSeed = "\(seed)-\(k)"
            if immediate {
                let tex = WorldTextures.sunSurface(hue: sun.hue, seed: sunSeed)
                m.diffuse.contents = tex
                m.emission.contents = tex
            } else {
                // zwei Sonnentexturen kosteten zusammen bis 90 ms auf dem Hauptthread; bis sie fertig sind, Grundfarbe
                let base = uic(sun.hue, 0.95, 0.6)
                m.diffuse.contents = base
                m.emission.contents = base
                Self.textureQueue.async { [weak self] in
                    let tex = WorldTextures.sunSurface(hue: sun.hue, seed: sunSeed)
                    DispatchQueue.main.async {
                        let ready = m.copy() as! SCNMaterial
                        ready.diffuse.contents = tex
                        ready.emission.contents = tex
                        self?.upload(ready) { sphere.materials = [ready] }
                    }
                }
            }
            sphere.materials = [m]
            let body = SCNNode(geometry: sphere)
            body.runAction(.repeatForever(.rotateBy(x: 0, y: .pi * 2, z: 0, duration: 18 + Double(k) * 6)))
            holder.addChildNode(body)

            // Korona: mehrere weiche Lichthöfe in der Sonnenfarbe
            for (scale, alpha) in [(2.6, 0.75), (4.6, 0.32)] as [(CGFloat, Double)] {
                let g = SCNNode(geometry: SCNPlane(width: r * scale, height: r * scale))
                let gm = spriteMat(WorldTextures.soft)
                gm.multiply.contents = uic(sun.hue, 0.95, 0.62, alpha)
                g.geometry?.materials = [gm]
                g.constraints = [SCNBillboardConstraint()]
                holder.addChildNode(g)
            }
        }
        // Materiebrücke zwischen den Sonnen
        let bridge = SCNNode(geometry: SCNPlane(width: p.radius * 1.3, height: p.radius * 0.32))
        let bm = spriteMat(WorldTextures.soft)
        bm.multiply.contents = uic(30, 0.9, 0.6, 0.35)
        bridge.geometry?.materials = [bm]
        bridge.eulerAngles.x = -.pi / 2
        pair.addChildNode(bridge)
        return root
    }

    /// Raumstation: zehn Modelle je nach Stationsnummer (Stations3D.swift)
    private func makeStation(_ p: Planet) -> SCNNode {
        // Lack wie bei den Schiffen, aber auf Stationsgröße skaliert (sonst kachelt er hundertfach)
        StationModels.make(p) { key, c in
            let m = WornPaint.material(key, base: c).copy() as! SCNMaterial
            m.setValue(NSNumber(value: 1.0 / 70.0), forKey: "tpScale")
            m.setValue(NSNumber(value: 0.01), forKey: "tpBump")
            return m
        }
    }

    /// Andockplattform an einer Station: dieselbe Plattform wie im Hangar, mit einem Steg bis an den Rand der Station
    private func makeStationDock(_ p: Planet, pos: CGPoint, heading: CGFloat) -> SCNNode {
        let root = SCNNode()
        root.position = v3(pos, -1)
        root.eulerAngles.y = Float(-heading)
        let pad = dockNode.clone()
        pad.position = SCNVector3(0, 0, 0)
        pad.eulerAngles = SCNVector3(0, 0, 0)
        pad.isHidden = false
        pad.opacity = 1
        root.addChildNode(pad)
        // Die Station liegt lokal in +z (Plattform links der Flugrichtung, siehe Game.stationDock)
        let z0: Float = 22
        let z1 = Float(p.orbitRadius - p.radius * 0.97)
        guard z1 > z0 + 4 else { return root }
        let len = z1 - z0
        let metal = WornPaint.material("dock", base: UIColor(white: 0.34, alpha: 1))
        let edge = glowMat(UIColor(red: 79 / 255, green: 227 / 255, blue: 193 / 255, alpha: 1))
        for x: Float in [-6, 6] {
            let rail = SCNBox(width: 1.6, height: 1.6, length: CGFloat(len), chamferRadius: 0.2)
            rail.materials = [metal]
            let n = SCNNode(geometry: rail)
            n.position = SCNVector3(x, -1.5, z0 + len / 2)
            root.addChildNode(n)
            let light = SCNBox(width: 0.5, height: 0.4, length: CGFloat(len), chamferRadius: 0)
            light.materials = [edge]
            let ln = SCNNode(geometry: light)
            ln.position = SCNVector3(x, -0.5, z0 + len / 2)
            root.addChildNode(ln)
        }
        let steps = max(2, Int(len / 8))
        for i in 0...steps {
            let cross = SCNBox(width: 12, height: 0.8, length: 1.2, chamferRadius: 0)
            cross.materials = [metal]
            let n = SCNNode(geometry: cross)
            n.position = SCNVector3(0, -2, z0 + len * Float(i) / Float(steps))
            root.addChildNode(n)
        }
        return root
    }

    /// Andockplattformen der Stationen im Bild nachführen
    private func syncStationDocks(_ game: Game) {
        for (i, n) in stationDocks where planetNodes[i] == nil {
            n.removeFromParentNode()
            stationDocks[i] = nil
        }
        for i in planetNodes.keys where stationDocks[i] == nil {
            guard game.planets.indices.contains(i), game.planets[i].isStation, let d = game.stationDock(i) else { continue }
            let n = makeStationDock(game.planets[i], pos: d.pos, heading: d.heading)
            scene.rootNode.addChildNode(n)
            stationDocks[i] = n
        }
    }

    /// Durchgehender Ladering: dunkler Grundring, darüber der wachsende Fortschrittsbogen
    private func makeBonusRing(_ p: Planet, kind: ItemKind) -> BonusRing {
        let root = SCNNode()
        root.position = v3(p.center)
        let rr = p.radius + 18
        let col = uic(kind.hue, 0.85, 0.6)
        // Grundspur: deutlich sichtbar, damit man den Bonus-Planeten schon von weitem erkennt
        let base = UIBezierPath(ovalIn: CGRect(x: -rr - 5, y: -rr - 5, width: (rr + 5) * 2, height: (rr + 5) * 2))
        base.append(UIBezierPath(ovalIn: CGRect(x: -rr + 5, y: -rr + 5, width: (rr - 5) * 2, height: (rr - 5) * 2)))
        base.usesEvenOddFillRule = true
        root.addChildNode(flatShape(base, glowMat(col.withAlphaComponent(0.4)), depth: 0.5))
        let progress = SCNNode()
        root.addChildNode(progress)
        // Fortschritt: drei volle Ringe, einmal gebaut; der Shader zeigt nur den geladenen Anteil.
        // Früher entstanden beim Laden bis zu 360 neue SCNShape-Geometrien je Bonus.
        let arcMats = [glowMat(col.withAlphaComponent(0.45)), glowMat(col), glowMat(UIColor.white.withAlphaComponent(0.85))]
        for (m, (width, depth)) in zip(arcMats, [(34, 0.4), (13, 0.8), (4, 1.0)] as [(CGFloat, CGFloat)]) {
            m.shaderModifiers = [.fragment: Self.progressShader]
            m.setValue(NSNumber(value: 0), forKey: "pgProgress")
            let path = UIBezierPath(ovalIn: CGRect(x: -rr - width / 2, y: -rr - width / 2, width: rr * 2 + width, height: rr * 2 + width))
            path.append(UIBezierPath(ovalIn: CGRect(x: -rr + width / 2, y: -rr + width / 2, width: rr * 2 - width, height: rr * 2 - width)))
            path.usesEvenOddFillRule = true
            progress.addChildNode(flatShape(path, m, depth: depth))
        }
        let head = SCNNode(geometry: SCNSphere(radius: 11))
        head.geometry?.materials = [glowMat(UIColor.white)]
        progress.addChildNode(head)
        progress.isHidden = true
        let badge = SCNNode(geometry: SCNPlane(width: 1, height: 1))
        // immer obenauf, damit der Planet das Symbol nicht verdeckt
        let bm = spriteMat(WorldTextures.badge(kind))
        bm.readsFromDepthBuffer = false
        badge.geometry?.materials = [bm]
        badge.renderingOrder = 50
        badge.constraints = [SCNBillboardConstraint()]
        badge.name = "badge"
        badge.position = SCNVector3(0, Float(p.radius * 0.35), Float(-rr - 12))
        root.addChildNode(badge)
        return BonusRing(node: root, progress: progress, arcMats: arcMats, head: head, radius: rr)
    }

    private func updateProgress(_ r: inout BonusRing, fraction: CGFloat) {
        let step = Int(fraction * 120)
        guard step != r.step else { return }
        r.step = step
        let f = CGFloat(step) / 120
        r.progress.isHidden = step <= 0
        r.arcMats.forEach { $0.setValue(NSNumber(value: Float(f)), forKey: "pgProgress") }
        // heller Punkt an der Spitze des Fortschritts
        let a1 = -CGFloat.pi / 2 + .pi * 2 * f
        r.head.position = SCNVector3(Float(cos(a1) * r.radius), 1, Float(sin(a1) * r.radius))
    }

    /// Zeigt von einem vollen Ring nur den Bogen ab 12 Uhr bis `pgProgress` (0…1). Die Materialien mischen additiv,
    /// Schwarz ist daher unsichtbar. Winkel im Modellraum der Ringform (Pfadebene), wie bei arcPath.
    private static let progressShader = """
    #pragma arguments
    float pgProgress;

    #pragma body
    float3 pgPos = (scn_node.inverseModelViewTransform * float4(_surface.position, 1.0)).xyz;
    float pgT = fract((atan2(pgPos.y, pgPos.x) + 1.5707963) / 6.2831853);
    if (pgT > pgProgress) { _output.color = float4(0.0); }
    """

    // MARK: Bahn, Kegel, Zielerfassung

    private func rebuildOrbit(_ game: Game) {
        let p = game.planets[game.currentIndex]
        orbitRing.childNodes.forEach { $0.removeFromParentNode() }
        // Doppelstern: vor dem hellen Sonnenschein ginge eine schwache, additive Linie unter,
        // daher kräftiger, deckend und obenauf
        let bright = p.kind == .binary
        let ring = SCNTorus(ringRadius: p.orbitRadius, pipeRadius: bright ? 2.4 : 1.2)
        ring.ringSegmentCount = 96
        ring.materials = [bright ? glowMat(UIColor(red: 0.3, green: 0.6, blue: 1, alpha: 0.9), additive: false)
                                 : glowMat(UIColor(red: 0.45, green: 0.75, blue: 1, alpha: 0.35))]
        let ringNode = SCNNode(geometry: ring)
        if bright { ringNode.renderingOrder = 20 }
        orbitRing.addChildNode(ringNode)
        // Skala außen
        let ticks = UIBezierPath()
        for k in 0..<48 {
            let a = CGFloat(k) / 48 * .pi * 2
            let r0 = p.orbitRadius + 10
            let len: CGFloat = k % 4 == 0 ? 10 : 4
            let w: CGFloat = 1.2
            let t = UIBezierPath(rect: CGRect(x: r0, y: -w / 2, width: len, height: w))
            t.apply(CGAffineTransform(rotationAngle: a))
            ticks.append(t)
        }
        orbitRing.addChildNode(flatShape(ticks, glowMat(UIColor(red: 0.45, green: 0.75, blue: 1, alpha: 0.5)), depth: 0.2))

        arrowSpinner.childNodes.forEach { $0.removeFromParentNode() }
        for q in 0..<6 {
            let a = CGFloat(q) / 6 * .pi * 2
            let cone = SCNCone(topRadius: 0, bottomRadius: 5, height: 12)
            cone.materials = [glowMat(UIColor(red: 0.67, green: 0.88, blue: 1, alpha: 0.9))]
            // Halter dreht um y, der Kegel darin kippt um x: Spitze zeigt entlang der Tangente
            let holder = SCNNode()
            holder.position = SCNVector3(Float(cos(a) * p.orbitRadius), 0, Float(sin(a) * p.orbitRadius))
            holder.eulerAngles.y = Float(-a)
            holder.addChildNode(SCNNode(geometry: cone))
            arrowSpinner.addChildNode(holder)
        }
    }

    private func rebuildCone(_ game: Game) {
        coneNode.childNodes.forEach { $0.removeFromParentNode() }
        let half = game.coneHalfAngle
        let len: CGFloat = 480
        let tri = UIBezierPath()
        tri.move(to: .zero)
        tri.addLine(to: CGPoint(x: cos(half) * len, y: sin(half) * len))
        tri.addLine(to: CGPoint(x: cos(half) * len, y: -sin(half) * len))
        tri.close()
        let fill = spriteMat(WorldTextures.coneFade)
        fill.multiply.contents = UIColor.white
        let fillNode = flatShape(tri, fill, depth: 0.3)
        coneNode.addChildNode(fillNode)
        let edgeMat = glowMat(UIColor(white: 0.7, alpha: 1))
        for side in [-1, 1] as [CGFloat] {
            let edge = SCNBox(width: len, height: 1, length: 2.2, chamferRadius: 0)
            edge.materials = [edgeMat]
            let e = SCNNode(geometry: edge)
            let a = side * half
            e.position = SCNVector3(Float(cos(a) * len / 2), 0, Float(sin(a) * len / 2))
            e.eulerAngles.y = Float(-a)
            coneNode.addChildNode(e)
        }
        let center = SCNBox(width: len, height: 0.5, length: 1.2, chamferRadius: 0)
        center.materials = [edgeMat]
        let cn = SCNNode(geometry: center)
        cn.position = SCNVector3(Float(len / 2), 0, 0)
        cn.opacity = 0.5
        coneNode.addChildNode(cn)
        let marker = SCNTorus(ringRadius: 11, pipeRadius: 1.4)
        marker.materials = [edgeMat]
        coneNode.addChildNode(SCNNode(geometry: marker))
        coneMats = [fill, edgeMat]
    }

    private func rebuildLock(_ p: Planet) {
        // Klammern und Bögen um die sichtbare Ausdehnung (beim Schwarzen Loch samt Scheibe)
        let R = p.outerRadius
        lockArcs.childNodes.forEach { $0.removeFromParentNode() }
        lockTicks.childNodes.forEach { $0.removeFromParentNode() }
        lockHolo.childNodes.forEach { $0.removeFromParentNode() }
        lockGroup.childNodes.filter { $0.name == "bracket" }.forEach { $0.removeFromParentNode() }

        let holo = UIColor(red: 0.45, green: 0.85, blue: 1, alpha: 0.9)
        let amber = UIColor(red: 1, green: 0.78, blue: 0.4, alpha: 1)
        for k in 0..<3 {
            let a0 = CGFloat(k) * 2 * .pi / 3
            lockArcs.addChildNode(flatShape(arcPath(radius: R + 30, width: 3, from: a0, to: a0 + 1.4), glowMat(holo), depth: 0.4))
        }
        let ticks = UIBezierPath()
        for k in 0..<36 {
            let a = CGFloat(k) / 36 * .pi * 2
            let t = UIBezierPath(rect: CGRect(x: R + 44, y: -0.6, width: k % 3 == 0 ? 9 : 4, height: 1.2))
            t.apply(CGAffineTransform(rotationAngle: a))
            ticks.append(t)
        }
        lockTicks.addChildNode(flatShape(ticks, glowMat(holo.withAlphaComponent(0.5)), depth: 0.2))

        // Holo-Gitter um den Zielplaneten (bei Stationen nicht, es würde das Modell verdecken)
        if !p.isStation && p.kind == .normal {
            let hm = spriteMat(WorldTextures.holoGrid)
            hm.multiply.contents = holo.withAlphaComponent(0.35)
            let sphere = SCNSphere(radius: p.radius * 1.03)
            sphere.segmentCount = 48
            sphere.materials = [hm]
            lockHolo.addChildNode(SCNNode(geometry: sphere))
        }

        // Klammern
        let h = R + 62
        let len = h * 0.28
        for (sx, sy) in [(-1, -1), (1, -1), (1, 1), (-1, 1)] as [(CGFloat, CGFloat)] {
            let path = UIBezierPath()
            let c = CGPoint(x: sx * h, y: sy * h)
            path.append(UIBezierPath(rect: CGRect(x: min(c.x, c.x - sx * len), y: c.y - 1.5, width: len, height: 3)))
            path.append(UIBezierPath(rect: CGRect(x: c.x - 1.5, y: min(c.y, c.y - sy * len), width: 3, height: len)))
            let n = flatShape(path, glowMat(amber), depth: 1)
            n.name = "bracket"
            lockGroup.addChildNode(n)
        }
    }

    // MARK: Objekte

    private func makeObstacle(_ a: Asteroid) -> SCNNode {
        switch a.kind {
        case .rock: return makeAsteroid(a)
        case .debris: return makeDebris(a)
        case .wreck: return makeWreck(a)
        case .comet: return makeComet(a)
        case .drone: return makeDrone(a)
        }
    }

    /// Jägerdrohne: dunkler Rumpf, rotierender Schutzring mit drei Gondeln, rotes Auge vorn (+x)
    private func makeDrone(_ a: Asteroid) -> SCNNode {
        let root = SCNNode()
        root.position = v3(a.center, 6)
        let r = a.radius
        // Wächterkugel aus dem Baukasten der Schiffe; Modell einmal im Hintergrund bauen, dann klonen
        withDroneModel { [weak root] model in
            guard let root else { return }
            let body = model.clone()
            // Modell hat Radius 1: Kugel etwa so groß wie der Trefferradius, Gürtel etwas darüber
            let s = Float(r * 0.95)
            body.scale = SCNVector3(s, s, s)
            body.name = "body"
            root.addChildNode(body)
        }
        // roter Schein, damit man die Kugel auch klein erkennt
        let glow = SCNNode(geometry: SCNPlane(width: r * 3.2, height: r * 3.2))
        let gm = spriteMat(WorldTextures.soft)
        gm.multiply.contents = UIColor(red: 1, green: 0.2, blue: 0.15, alpha: 0.35)
        glow.geometry?.materials = [gm]
        glow.constraints = [SCNBillboardConstraint()]
        root.addChildNode(glow)
        return root
    }

    /// Öffnungsgrad der Schalen je Drohne (0 zu, 1 offen)
    private var droneOpen: [Int: CGFloat] = [:]

    /// Schalen klappen kurz vor jedem Schuss auf und danach wieder zu
    private func animateDrone(_ n: SCNNode, _ a: Asteroid, _ game: Game, dt: CGFloat) {
        let d = hypot(game.pos.x - a.center.x, game.pos.y - a.center.y)
        let aiming = game.phase == .flying && a.gap == game.originIndex + 1 && d < Game.droneRange
            && a.fireAt - game.time < 0.5
        let open = smoothApproach(droneOpen[a.uid] ?? 0, aiming ? 1 : 0, rate: aiming ? 9 : 5, dt: dt)
        droneOpen[a.uid] = open
        guard let body = n.childNode(withName: "body", recursively: false) else { return }
        let k = Float(open * open * (3 - 2 * open)) * 0.62
        body.childNode(withName: "upper", recursively: false)?.eulerAngles.z = k
        body.childNode(withName: "lower", recursively: false)?.eulerAngles.z = -k
    }

    private var droneModel: SCNNode?
    private var droneWaiting: [(SCNNode) -> Void] = []

    private func withDroneModel(_ use: @escaping (SCNNode) -> Void) {
        if let m = droneModel { use(m); return }
        droneWaiting.append(use)
        guard droneWaiting.count == 1 else { return }
        Self.textureQueue.async { [weak self] in
            let model = Self.buildDroneModel()
            DispatchQueue.main.async {
                guard let self else { return }
                self.upload(model) { [weak self] in
                    guard let self else { return }
                    self.droneModel = model
                    let waiting = self.droneWaiting
                    self.droneWaiting = []
                    waiting.forEach { $0(model) }
                }
            }
        }
    }

    /// Facettierte Halbkugel (Radius 1, nach oben offen bei y = 0), flach schattiert wie gekantetes Blech
    private static func shellGeometry(rings: Int = 4, slices: Int = 12) -> SCNGeometry {
        var pos: [SCNVector3] = [], nor: [SCNVector3] = []
        func p(_ i: Int, _ j: Int) -> SIMD3<Float> {
            let lat = Float(i) / Float(rings) * .pi / 2          // 0 = Äquator, π/2 = Pol
            let lon = Float(j) / Float(slices) * 2 * .pi
            return SIMD3(cos(lat) * cos(lon), sin(lat), cos(lat) * sin(lon))
        }
        func tri(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>) {
            var n = simd_normalize(cross(b - a, c - a))
            var v = [a, b, c]
            if dot(n, (a + b + c) / 3) < 0 { n = -n; v = [a, c, b] }
            for q in v {
                pos.append(SCNVector3(q.x, q.y, q.z))
                nor.append(SCNVector3(n.x, n.y, n.z))
            }
        }
        for i in 0..<rings {
            for j in 0..<slices {
                let a = p(i, j), b = p(i, j + 1), c = p(i + 1, j + 1), d = p(i + 1, j)
                tri(a, b, c)
                if i + 1 < rings { tri(a, c, d) }
            }
        }
        let idx = (0..<Int32(pos.count)).map { $0 }
        let uv = pos.map { CGPoint(x: CGFloat($0.x) / 2, y: CGFloat($0.y + $0.z) / 2) }
        return SCNGeometry(sources: [SCNGeometrySource(vertices: pos), SCNGeometrySource(normals: nor),
                                     SCNGeometrySource(textureCoordinates: uv)],
                           elements: [SCNGeometryElement(indices: idx, primitiveType: .triangles)])
    }

    /// Wächterkugel: zwei gepanzerte Halbschalen mit Scharnier hinten, die vor dem Schuss aufklappen
    /// und ein rotes Auge freigeben; dazwischen ein dunkler Gürtel mit Lampen. Auge zeigt nach +x.
    private static func buildDroneModel() -> SCNNode {
        let k = ShipKit(seed: "drone", base: ShipDesigns.gunmetal, accent: ShipDesigns.red, second: ShipDesigns.night,
                        weaponHue: 0, marking: "X")
        let red = ShipKit.glow(UIColor(red: 1, green: 0.16, blue: 0.12, alpha: 1))
        let root = k.root
        // Innenleben: dunkler Kern, rotes Auge vorn
        let core = SCNSphere(radius: 0.78)
        core.segmentCount = 20
        core.materials = [k.dark]
        root.addChildNode(SCNNode(geometry: core))
        let eye = SCNSphere(radius: 0.3)
        eye.materials = [red]
        let eyeNode = SCNNode(geometry: eye)
        eyeNode.position = SCNVector3(0.62, 0, 0)
        root.addChildNode(eyeNode)
        // Halbschalen: Drehpunkt hinten am Gürtel, die Vorderkante hebt sich beim Öffnen
        let shell = shellGeometry()
        for (name, flip) in [("upper", Float(1)), ("lower", Float(-1))] {
            let hinge = SCNNode()
            hinge.name = name
            hinge.position = SCNVector3(-0.95, 0, 0)
            let half = SCNNode()
            half.position = SCNVector3(0.95, flip * 0.06, 0)
            // untere Schale: dieselbe Schale um die Längsachse gedreht (keine negative Skalierung, sonst kippen die Flächen)
            if flip < 0 { half.eulerAngles.x = .pi }
            let g = shell.copy() as! SCNGeometry
            g.materials = [flip > 0 ? k.paint : k.second]
            half.addChildNode(SCNNode(geometry: g))
            // roter Streifen quer über die Schale und Panzerrippen
            let band = SCNBox(width: 0.22, height: 0.08, length: 1.5, chamferRadius: 0.02)
            band.materials = [k.accent]
            let bn = SCNNode(geometry: band)
            bn.position = SCNVector3(0.1, 0.96, 0)
            half.addChildNode(bn)
            for z in [-0.55, 0.55] as [Float] {
                let rib = SCNBox(width: 1.2, height: 0.07, length: 0.1, chamferRadius: 0.02)
                rib.materials = [k.metal]
                let rn = SCNNode(geometry: rib)
                rn.position = SCNVector3(0, 0.8, z)
                half.addChildNode(rn)
            }
            if flip > 0 {
                // Sensormast und Antenne oben
                let mast = SCNBox(width: 0.18, height: 0.3, length: 0.18, chamferRadius: 0.03)
                mast.materials = [k.dark]
                let mn = SCNNode(geometry: mast)
                mn.position = SCNVector3(-0.35, 1.0, 0)
                half.addChildNode(mn)
                let tip = SCNSphere(radius: 0.07)
                tip.materials = [red]
                let tn = SCNNode(geometry: tip)
                tn.position = SCNVector3(-0.35, 1.2, 0)
                tn.runAction(.repeatForever(.sequence([.fadeOpacity(to: 0.15, duration: 0.3), .fadeOpacity(to: 1, duration: 0.3)])))
                half.addChildNode(tn)
            }
            hinge.addChildNode(half)
            root.addChildNode(hinge)
        }
        // Gürtel mit Lampen und seitlichen Steuerdüsen
        let belt = SCNTube(innerRadius: 0.9, outerRadius: 1.1, height: 0.16)
        belt.radialSegmentCount = 24
        belt.materials = [k.dark]
        root.addChildNode(SCNNode(geometry: belt))
        for j in 0..<6 {
            let ang = Float(j) / 6 * 2 * .pi + .pi / 6
            let lamp = SCNBox(width: 0.1, height: 0.06, length: 0.1, chamferRadius: 0.01)
            lamp.materials = [red]
            let ln = SCNNode(geometry: lamp)
            ln.position = SCNVector3(cos(ang) * 1.1, 0, sin(ang) * 1.1)
            root.addChildNode(ln)
        }
        for z in [-1.12, 1.12] as [Float] {
            let pod = SCNBox(width: 0.4, height: 0.22, length: 0.18, chamferRadius: 0.04)
            pod.materials = [k.second]
            let pn = SCNNode(geometry: pod)
            pn.position = SCNVector3(-0.2, 0, z)
            root.addChildNode(pn)
        }
        return root
    }

    /// Plasmaschuss der Drohnen: rote Kugel mit Schein
    private func makeEnemyShot() -> SCNNode {
        let n = SCNNode()
        let core = SCNSphere(radius: 5)
        core.materials = [glowMat(UIColor(red: 1, green: 0.85, blue: 0.8, alpha: 1))]
        n.addChildNode(SCNNode(geometry: core))
        let glow = SCNNode(geometry: SCNPlane(width: 34, height: 34))
        let gm = spriteMat(WorldTextures.soft)
        gm.multiply.contents = UIColor(red: 1, green: 0.15, blue: 0.1, alpha: 1)
        glow.geometry?.materials = [gm]
        glow.constraints = [SCNBillboardConstraint()]
        n.addChildNode(glow)
        return n
    }

    private static let foil: SCNMaterial = {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = UIColor(red: 0.85, green: 0.62, blue: 0.2, alpha: 1)
        m.metalness.contents = 1
        m.roughness.contents = 0.45
        m.normal.contents = WorldTextures.rock
        m.normal.intensity = 0.4
        return m
    }()

    private static let solar: SCNMaterial = {
        let img = textureRenderer(CGSize(width: 256, height: 256)).image { ctx in
            UIColor(red: 0.06, green: 0.12, blue: 0.32, alpha: 1).setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 256, height: 256))
            UIColor(red: 0.5, green: 0.6, blue: 0.75, alpha: 1).setStroke()
            let p = UIBezierPath()
            for k in 0...8 {
                let v = CGFloat(k) * 32
                p.move(to: CGPoint(x: v, y: 0)); p.addLine(to: CGPoint(x: v, y: 256))
                p.move(to: CGPoint(x: 0, y: v)); p.addLine(to: CGPoint(x: 256, y: v))
            }
            p.lineWidth = 3
            p.stroke()
        }
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = img
        m.metalness.contents = 0.6
        m.roughness.contents = 0.2
        return m
    }()

    /// Satellitentrümmer: Rumpf in Goldfolie, abgerissene Solarflügel, Schüssel
    private func makeDebris(_ a: Asteroid) -> SCNNode {
        var rng = SeededRNG("debris\(a.uid)")
        let root = SCNNode()
        root.position = v3(a.center, CGFloat((a.uid * 37) % 30 - 15))
        let body = SCNNode()
        let s = a.radius / 1.3
        body.scale = SCNVector3(Float(s), Float(s), Float(s))
        root.addChildNode(body)
        let bus = SCNBox(width: 1.1, height: 0.8, length: 0.8, chamferRadius: 0.05)
        bus.materials = [World3D.foil]
        body.addChildNode(SCNNode(geometry: bus))
        for k in 0..<(a.variant == 0 ? 2 : 1) {
            let panel = SCNBox(width: 0.06, height: 0.7, length: rng.c(1.2...2.0), chamferRadius: 0.01)
            panel.materials = [World3D.solar]
            let pn = SCNNode(geometry: panel)
            let side: Float = k == 0 ? 1 : -1
            pn.position = SCNVector3(0, 0, side * Float(0.4 + panel.length / 2))
            pn.eulerAngles = SCNVector3(Float(rng.c(-0.6...0.6)), Float(rng.c(-0.4...0.4)), Float(rng.c(-0.5...0.5)))
            body.addChildNode(pn)
        }
        if a.variant != 2 {
            let dish = SCNCone(topRadius: 0.45, bottomRadius: 0.05, height: 0.25)
            let dm = SCNMaterial()
            dm.lightingModel = .physicallyBased
            dm.diffuse.contents = UIColor(white: 0.85, alpha: 1)
            dm.roughness.contents = 0.5
            dm.isDoubleSided = true
            dish.materials = [dm]
            let dn = SCNNode(geometry: dish)
            dn.position = SCNVector3(0.6, 0.5, 0)
            dn.eulerAngles.z = -0.6
            body.addChildNode(dn)
        }
        let axis = SCNVector3(Float(rng.c(-1...1)), 1, Float(rng.c(-1...1)))
        body.runAction(.repeatForever(.rotate(by: .pi * 2, around: axis, duration: Double(rng.c(5...10)))))
        let light = SCNNode(geometry: SCNSphere(radius: 0.08))
        light.geometry?.materials = [glowMat(UIColor(red: 1, green: 0.3, blue: 0.2, alpha: 1), additive: false)]
        light.position = SCNVector3(0.56, 0.41, 0)
        light.runAction(.repeatForever(.sequence([.fadeOut(duration: 0.1), .wait(duration: 0.8), .fadeIn(duration: 0.1)])))
        body.addChildNode(light)
        return root
    }

    /// Treibendes Schiffswrack mit Brandherd
    private func makeWreck(_ a: Asteroid) -> SCNNode {
        let root = SCNNode()
        root.position = v3(a.center, CGFloat((a.uid * 37) % 30 - 15))
        // Schiffsmodell je Typ nur einmal bauen und danach klonen (der Klon teilt Geometrie und Materialien).
        // Der Bau mit neuen Lacken dauert pro Typ bis 100 ms, deshalb im Hintergrund; das Wrack liegt weit
        // voraus und bekommt seinen Rumpf, sobald das Modell fertig ist
        let s = a.radius / 3.2
        let phase = a.phase
        withWreckModel(a.variant % ShipModel.all.count) { model in
            let hull = model.clone()
            hull.scale = SCNVector3(Float(s), Float(s), Float(s))
            hull.eulerAngles = SCNVector3(Float(phase), Float(phase * 1.7), 0.5)
            hull.runAction(.repeatForever(.rotate(by: .pi * 2, around: SCNVector3(0.3, 1, 0.2), duration: 22)))
            root.addChildNode(hull)
        }
        let fire = SCNNode(geometry: SCNPlane(width: a.radius * 1.4, height: a.radius * 1.4))
        let fm = spriteMat(WorldTextures.soft)
        fm.multiply.contents = UIColor(red: 1, green: 0.35, blue: 0.08, alpha: 1)
        fire.geometry?.materials = [fm]
        fire.constraints = [SCNBillboardConstraint()]
        fire.position = SCNVector3(Float(a.radius * 0.2), Float(a.radius * 0.2), 0)
        fire.runAction(.repeatForever(.sequence([.fadeOpacity(to: 0.5, duration: 0.15), .fadeOpacity(to: 1, duration: 0.2)])))
        root.addChildNode(fire)
        let sparks = SCNParticleSystem()
        sparks.birthRate = 25
        sparks.particleLifeSpan = 1.2
        sparks.particleVelocity = 30
        sparks.spreadingAngle = 180
        sparks.particleSize = 2.5
        sparks.particleImage = WorldTextures.dot
        sparks.blendMode = .additive
        sparks.isLightingEnabled = false
        sparks.isAffectedByGravity = false
        sparks.particleColor = UIColor(red: 1, green: 0.6, blue: 0.2, alpha: 1)
        fire.addParticleSystem(sparks)
        return root
    }

    /// Komet: eisiger Kern, leuchtende Koma, langer Schweif entgegen der Flugrichtung
    private func makeComet(_ a: Asteroid) -> SCNNode {
        let root = SCNNode()
        root.position = v3(a.center, 0)
        root.eulerAngles.y = Float(-atan2(a.vel.dy, a.vel.dx))
        let geo = RockMesh.variants[abs(a.uid) % RockMesh.variants.count].copy() as! SCNGeometry
        let ice = SCNMaterial()
        ice.lightingModel = .physicallyBased
        ice.diffuse.contents = UIColor(red: 0.75, green: 0.85, blue: 0.95, alpha: 1)
        ice.roughness.contents = 0.35
        ice.metalness.contents = 0.1
        ice.emission.contents = UIColor(red: 0.08, green: 0.2, blue: 0.3, alpha: 1)
        geo.materials = [ice]
        let core = SCNNode(geometry: geo)
        core.scale = SCNVector3(Float(a.radius), Float(a.radius), Float(a.radius))
        core.runAction(.repeatForever(.rotate(by: .pi * 2, around: SCNVector3(0.2, 1, 0.4), duration: 9)))
        root.addChildNode(core)
        let coma = SCNNode(geometry: SCNPlane(width: a.radius * 5, height: a.radius * 5))
        let cm = spriteMat(WorldTextures.soft)
        cm.multiply.contents = UIColor(red: 0.35, green: 0.75, blue: 1, alpha: 1)
        coma.geometry?.materials = [cm]
        coma.constraints = [SCNBillboardConstraint()]
        root.addChildNode(coma)
        let tail = SCNParticleSystem()
        tail.birthRate = 70
        tail.particleLifeSpan = 3.2
        tail.particleVelocity = 90
        tail.particleVelocityVariation = 30
        tail.emittingDirection = SCNVector3(-1, 0, 0)
        tail.spreadingAngle = 10
        tail.particleSize = a.radius * 0.9
        tail.particleImage = WorldTextures.soft
        tail.blendMode = .additive
        tail.isLightingEnabled = false
        tail.isAffectedByGravity = false
        tail.particleColor = UIColor(red: 0.35, green: 0.7, blue: 1, alpha: 0.6)
        let grow = CAKeyframeAnimation()
        grow.values = [0.6, 2.2]
        let fade = CAKeyframeAnimation()
        fade.values = [0.8, 0]
        tail.propertyControllers = [.size: SCNParticlePropertyController(animation: grow),
                                    .opacity: SCNParticlePropertyController(animation: fade)]
        root.addParticleSystem(tail)
        return root
    }

    /// Kometen-Zerstörung: greller Lichtblitz, Koma bläht sich auf, der Kern zerbricht in Eisbrocken,
    /// die auseinanderfliegen, und der Schweif verweht, statt mitten im Bild abzureißen
    private func shatterComet(_ a: Asteroid) {
        let r = a.radius
        if let n = asteroidNodes.removeValue(forKey: a.uid) {
            // Schweif sofort weg, Kern und Leuchthülle schrumpfen in einem Zug auf nichts zusammen
            // reset() löscht auch die schon ausgestoßenen Partikel; sie leben sonst in der Szene weiter und glühen nach
            killParticles(n)
            for c in n.childNodes {
                let shrink = SCNAction.scale(to: 0, duration: 0.12)
                shrink.timingMode = .easeIn
                c.runAction(.sequence([shrink, .hide()]))
            }
            n.runAction(.sequence([.wait(duration: 0.15), .removeFromParentNode()]))
        }
        let root = SCNNode()
        root.position = v3(a.center, 0)
        scene.rootNode.addChildNode(root)

        // Lichtblitz
        let flash = SCNNode(geometry: SCNPlane(width: r * 4, height: r * 4))
        let fm = spriteMat(WorldTextures.soft)
        fm.multiply.contents = UIColor(red: 0.85, green: 0.97, blue: 1, alpha: 1)
        flash.geometry?.materials = [fm]
        flash.constraints = [SCNBillboardConstraint()]
        flash.renderingOrder = 10
        // kurzer Blitz, der mit dem Kometen zusammenschrumpft statt sich auszubreiten
        let fshrink = SCNAction.scale(to: 0, duration: 0.12)
        fshrink.timingMode = .easeIn
        flash.runAction(.sequence([fshrink, .hide()]))
        root.addChildNode(flash)

        // Eisbrocken
        let ice = SCNMaterial()
        ice.lightingModel = .physicallyBased
        ice.diffuse.contents = UIColor(red: 0.8, green: 0.9, blue: 1, alpha: 1)
        ice.roughness.contents = 0.3
        ice.metalness.contents = 0.1
        ice.emission.contents = UIColor(red: 0.2, green: 0.5, blue: 0.7, alpha: 1)
        let meshes: [SCNGeometry] = (0..<3).map { k in
            let g = RockMesh.variants[(abs(a.uid) + k) % RockMesh.variants.count].copy() as! SCNGeometry
            g.materials = [ice]
            return g
        }
        let count = 10
        for k in 0..<count {
            let frag = SCNNode(geometry: meshes[k % meshes.count])
            let s = Float(r * CGFloat.random(in: 0.16...0.36))
            frag.scale = SCNVector3(s, s, s)
            let ang = CGFloat(k) / CGFloat(count) * .pi * 2 + CGFloat.random(in: -0.3...0.3)
            let dist = r * CGFloat.random(in: 4...8)
            // Brocken behalten etwas vom Schwung des Kometen
            let dx = cos(ang) * dist + a.vel.dx * 1.2
            let dz = sin(ang) * dist + a.vel.dy * 1.2
            let dy = r * CGFloat.random(in: -1.5...1.5)
            let move = SCNAction.move(by: SCNVector3(Float(dx), Float(dy), Float(dz)), duration: 1.9)
            move.timingMode = .easeOut
            let axis = SCNVector3(Float.random(in: -1...1), 1, Float.random(in: -1...1))
            frag.runAction(.group([
                move,
                .rotate(by: CGFloat.random(in: 4...9), around: axis, duration: 1.9),
                .sequence([.wait(duration: 1.1), .fadeOut(duration: 0.8)])
            ]))
            root.addChildNode(frag)
        }
        root.runAction(.sequence([.wait(duration: 2.1), .removeFromParentNode()]))
    }

    /// Partikelsystem samt bereits ausgestoßener Partikel sofort entfernen (Kometenschweif)
    private func killParticles(_ n: SCNNode) {
        for ps in n.particleSystems ?? [] {
            ps.birthRate = 0
            ps.reset()
        }
        n.removeAllParticleSystems()
    }

    private func makeAsteroid(_ a: Asteroid) -> SCNNode {
        let geo = RockMesh.variants[abs(a.uid) % RockMesh.variants.count]
        let n = SCNNode(geometry: geo)
        n.scale = SCNVector3(Float(a.radius), Float(a.radius), Float(a.radius))
        n.position = v3(a.center, CGFloat((a.uid * 37) % 30 - 15))
        n.eulerAngles = SCNVector3(Float(a.phase), Float(a.phase * 2), 0)
        let axis = SCNVector3(Float(cos(a.phase)), 1, Float(sin(a.phase)))
        n.runAction(.repeatForever(.rotate(by: CGFloat(a.spin) * 2, around: axis, duration: 4)))
        // schwacher Warnschein
        let glow = SCNNode(geometry: SCNPlane(width: 3, height: 3))
        glow.geometry?.materials = [spriteMat(WorldTextures.soft)]
        glow.geometry?.firstMaterial?.multiply.contents = UIColor(red: 0.35, green: 0.16, blue: 0.08, alpha: 1)
        glow.constraints = [SCNBillboardConstraint()]
        glow.renderingOrder = -1
        n.addChildNode(glow)
        return n
    }

    private func makeCloud(_ cl: GasCloud) -> SCNNode {
        let root = SCNNode()
        root.position = v3(cl.center, -60)
        for b in cl.blobs {
            let plane = SCNPlane(width: b.r * 2.2, height: b.r * 2.2)
            let m = spriteMat(WorldTextures.soft)
            m.multiply.contents = uic(b.hue, 0.7, 0.32, 1)
            plane.materials = [m]
            let n = SCNNode(geometry: plane)
            n.position = SCNVector3(Float(b.off.x), Float(b.off.y * 0.2), Float(b.off.y))
            n.constraints = [SCNBillboardConstraint()]
            root.addChildNode(n)
        }
        for sp in cl.sparkles {
            let n = SCNNode(geometry: SCNPlane(width: 14, height: 14))
            n.geometry?.materials = [spriteMat(WorldTextures.dot)]
            n.position = SCNVector3(Float(sp.x - cl.center.x), 10, Float(sp.y - cl.center.y))
            n.constraints = [SCNBillboardConstraint()]
            n.runAction(.repeatForever(.sequence([.fadeOpacity(to: 0.2, duration: 0.8), .fadeOpacity(to: 1, duration: 0.8)])))
            root.addChildNode(n)
        }
        root.runAction(.repeatForever(.rotateBy(x: 0, y: .pi * 2, z: 0, duration: 120)))
        return root
    }

    private func makeItem(_ it: Item) -> SCNNode {
        let n = SCNNode(geometry: SCNPlane(width: 1, height: 1))
        n.geometry?.materials = [spriteMat(WorldTextures.badge(it.kind))]
        n.constraints = [SCNBillboardConstraint()]
        let glow = SCNNode(geometry: SCNPlane(width: 2.6, height: 2.6))
        let gm = spriteMat(WorldTextures.soft)
        gm.multiply.contents = uic(it.kind.hue, 0.85, 0.6, 0.6)
        glow.geometry?.materials = [gm]
        glow.renderingOrder = -1
        n.addChildNode(glow)
        return n
    }

    /// Geschoss: kleiner Leuchtkörper mit kurzer Spur, ohne Partikel
    private func makeProjectile(_ pr: Projectile) -> SCNNode {
        let n = SCNNode()
        let col = uic(pr.kind.hue, 0.9, 0.62)
        let bolt = SCNNode()
        bolt.name = "bolt"
        n.addChildNode(bolt)
        switch pr.kind {
        case .cannon, .railgun:
            // Spur hinten, heller Kern vorn
            let streak = SCNBox(width: 1, height: 0.35, length: 0.35, chamferRadius: 0.17)
            streak.materials = [glowMat(col.withAlphaComponent(0.6))]
            let sn = SCNNode(geometry: streak)
            sn.position.x = -0.35
            bolt.addChildNode(sn)
            let core = SCNBox(width: 0.35, height: 0.22, length: 0.22, chamferRadius: 0.11)
            core.materials = [glowMat(.white)]
            let cn = SCNNode(geometry: core)
            cn.position.x = 0.05
            bolt.addChildNode(cn)
        case .rocket:
            let body = SCNBox(width: 0.6, height: 0.18, length: 0.18, chamferRadius: 0.06)
            let bm = SCNMaterial()
            bm.lightingModel = .physicallyBased
            bm.diffuse.contents = UIColor(white: 0.85, alpha: 1)
            body.materials = [bm]
            bolt.addChildNode(SCNNode(geometry: body))
            let flame = SCNBox(width: 0.5, height: 0.14, length: 0.14, chamferRadius: 0.07)
            flame.materials = [glowMat(UIColor(red: 1, green: 0.55, blue: 0.2, alpha: 0.8))]
            let fn = SCNNode(geometry: flame)
            fn.position.x = -0.5
            bolt.addChildNode(fn)
        case .bomb:
            let sphere = SCNSphere(radius: 0.3)
            sphere.materials = [glowMat(col)]
            let sn = SCNNode(geometry: sphere)
            sn.runAction(.repeatForever(.sequence([.fadeOpacity(to: 0.35, duration: 0.1), .fadeOpacity(to: 1, duration: 0.1)])))
            bolt.addChildNode(sn)
            let blast = SCNTorus(ringRadius: 280, pipeRadius: 1.2)
            blast.materials = [glowMat(col.withAlphaComponent(0.25))]
            n.addChildNode(SCNNode(geometry: blast))
        }
        return n
    }

    private var activeBeams: [(node: SCNNode, angle: CGFloat, len: CGFloat)] = []
    private var wreckModels: [Int: SCNNode] = [:]
    private var wreckWaiting: [Int: [(SCNNode) -> Void]] = [:]

    /// liefert das Wrack-Modell eines Schiffstyps, sofort oder (beim ersten Mal) nach dem Bau im Hintergrund
    private func withWreckModel(_ variant: Int, _ use: @escaping (SCNNode) -> Void) {
        if let m = wreckModels[variant] { use(m); return }
        if wreckWaiting[variant] != nil {
            wreckWaiting[variant]?.append(use)
            return
        }
        wreckWaiting[variant] = [use]
        Self.textureQueue.async { [weak self] in
            let model = Ship3D.simplified(ShipDesigns.build(ShipModel.all[variant]))
            DispatchQueue.main.async {
                guard let self else { return }
                // Klone teilen Geometrie und Lacke, einmal hochladen reicht für alle Wracks dieses Typs
                self.upload(model) { [weak self] in
                    guard let self else { return }
                    self.wreckModels[variant] = model
                    let waiting = self.wreckWaiting.removeValue(forKey: variant) ?? []
                    waiting.forEach { $0(model) }
                }
            }
        }
    }

    private func spawnBeam(_ b: Beam, px: CGFloat) {
        let dx = b.to.x - b.from.x, dy = b.to.y - b.from.y
        let len = hypot(dx, dy)
        let col = uic(WorldTextures.railHue, 0.9, 0.65)
        let root = SCNNode()
        root.position = v3(CGPoint(x: (b.from.x + b.to.x) / 2, y: (b.from.y + b.to.y) / 2))
        root.eulerAngles.y = Float(-atan2(dy, dx))
        // breiter, schwacher Saum in Weltgröße: zeigt, wie breit der Strahl trifft
        // schmaler Saum als flacher Keil, nach außen durchsichtiger: drei übereinanderliegende Keile,
        // innen kräftiger, außen kaum sichtbar (zusammen so breit wie ein Drittel der Trefferbreite)
        let half = len / 2
        for (f, alpha) in [(1.0, 0.02), (0.6, 0.035), (0.3, 0.06)] as [(CGFloat, CGFloat)] {
            let w0 = 1.5 * f, w1 = Game.railWidth * 0.35 * f
            let wedge = UIBezierPath()
            wedge.move(to: CGPoint(x: -half, y: -w0))
            wedge.addLine(to: CGPoint(x: half, y: -w1))
            wedge.addLine(to: CGPoint(x: half, y: w1))
            wedge.addLine(to: CGPoint(x: -half, y: w0))
            wedge.close()
            let band = SCNShape(path: wedge, extrusionDepth: 0.5)
            band.materials = [glowMat(col.withAlphaComponent(alpha))]
            let bandNode = SCNNode(geometry: band)
            bandNode.eulerAngles.x = -.pi / 2
            root.addChildNode(bandNode)
        }
        for (w, c) in [(6 * px, col.withAlphaComponent(0.45)), (2.2 * px, col), (0.9 * px, UIColor.white)] {
            let box = SCNBox(width: len, height: w, length: w, chamferRadius: 0)
            box.materials = [glowMat(c)]
            root.addChildNode(SCNNode(geometry: box))
        }
        scene.rootNode.addChildNode(root)
        activeBeams.append((root, atan2(dy, dx), len))
        root.runAction(.sequence([.fadeOut(duration: 0.4), .removeFromParentNode()]))
    }

    private func spawnWave(_ w: Wave, px: CGFloat) {
        let torus = SCNTorus(ringRadius: w.r0, pipeRadius: 2.5 * px)
        torus.ringSegmentCount = 72
        torus.materials = [glowMat(uic(w.hue, 0.8, 0.7))]
        let n = SCNNode(geometry: torus)
        n.position = v3(w.center)
        scene.rootNode.addChildNode(n)
        let dur = Double(w.maxAge)
        let r0 = w.r0
        n.runAction(.sequence([
            .customAction(duration: dur) { node, t in
                let f = t / CGFloat(dur)
                (node.geometry as? SCNTorus)?.ringRadius = r0 + f * 280
                node.opacity = 0.8 * (1 - f)
            },
            .removeFromParentNode()
        ]))
    }

    private func spawnBurst(_ b: Burst, px: CGFloat) {
        let ps = SCNParticleSystem()
        ps.birthRate = CGFloat(b.count) * 18
        ps.emissionDuration = 0.04
        ps.loops = false
        ps.particleLifeSpan = b.life
        ps.particleLifeSpanVariation = b.life * 0.5
        ps.particleVelocity = b.speed * px
        ps.particleVelocityVariation = b.speed * px * 0.7
        ps.spreadingAngle = 180
        ps.particleSize = 1.4 * px
        ps.particleSizeVariation = 0.6 * px
        ps.particleImage = WorldTextures.dot
        ps.blendMode = .additive
        ps.isLightingEnabled = false
        ps.isAffectedByGravity = false
        ps.dampingFactor = 1.5
        ps.particleColor = uic(b.hue, 0.9, 0.65)
        ps.particleColorVariation = SCNVector4(0.05, 0.1, 0.2, 0)
        let anim = CAKeyframeAnimation()
        anim.values = [1, 1, 0]
        anim.keyTimes = [0, 0.5, 1]
        ps.propertyControllers = [.opacity: SCNParticlePropertyController(animation: anim)]
        let n = SCNNode()
        n.position = v3(b.pos)
        n.addParticleSystem(ps)
        scene.rootNode.addChildNode(n)
        n.runAction(.sequence([.wait(duration: Double(b.life) * 1.6 + 0.2), .removeFromParentNode()]))
    }

    // MARK: Abgleich pro Frame

    private(set) var framesSynced = 0

    func sync(_ game: Game, size: CGSize) {
        guard size.width > 0, !game.planets.isEmpty else { return }
        framesSynced += 1
        let dt = max(0, min(0.1, game.time - lastTime))
        lastTime = game.time

        if game.generation != generation {
            generation = game.generation
            clearAll()
        }

        // Kamera-Mischung auf Strecken mit Hindernissen, fest gegliedert:
        // Abflug mit Übergang in die Verfolgerkamera, Hindernispassage in der Nahaufnahme,
        // am Ende der Passage bleibt die Kamera stehen und lässt das Schiff in den Zielorbit fliegen.
        let ti = min(game.originIndex + 1, game.planets.count - 1)
        let tgt = game.planets[ti]
        let distT = hypot(tgt.center.x - game.pos.x, tgt.center.y - game.pos.y)
        let shipAt = game.progress(game.pos, gap: ti)
        let passageDone = shipAt.map { $0 >= tgt.passageTo } ?? true
        if game.phase == .flying && lastPhase != .flying { chasedThisFlight = false }
        if game.phase == .flying && !chasedThisFlight && tgt.hardRoute && !passageDone {
            chaseOn = true
            chasedThisFlight = true
        }
        if game.phase != .flying || passageDone { chaseOn = false }
        // Spielende: Nahaufnahme für das Ausgleiten bzw. die Explosion
        if game.phase == .over { chaseOn = true }
        lastPhase = game.phase
        let danger = chaseOn
        let want: CGFloat = danger ? 1 : 0
        // rein zügig, raus langsam und weich
        // Der Vorwärts-Schub beim Herauszoomen gilt nur im Flug; im Orbit würde er mit dem Schiff im Kreis laufen
        releasing = !danger && chase > 0.001 && game.phase == .flying
        // Im Orbit blendet eine Rest-Nahansicht zügig aus, sonst folgt die Kamera dem kreisenden Schiff
        let chaseRate: CGFloat = game.phase == .over ? 2.2 : (danger ? 1.4 : (game.phase == .flying ? 0.45 : 3))
        chase = smoothApproach(chase, want, rate: chaseRate, dt: dt)
        if game.phase == .over && !game.destroyed {
            coastClose = smoothApproach(coastClose, 1, rate: 0.7, dt: dt)
        } else {
            coastClose = 0
        }
        if game.phase == .over && game.destroyed {
            blastView = smoothApproach(blastView, 1, rate: 2.5, dt: dt)
        } else {
            blastView = 0
        }
        // Solange die Verfolgerkamera aus ist, liegt der Kurs direkt an; danach folgt er mit kurzer Verzögerung
        if chase < 0.001 {
            chaseHeading.snap(to: game.heading)
        } else if game.phase == .flying {
            // im Orbit dreht sich der Kurs ständig mit, dort bleibt er stehen
            chaseHeading.update(to: game.heading, smoothTime: 0.18, dt: dt)
        }
        updateArrival(game, dt: dt, ti: ti, distT: distT, tgt: tgt, passageDone: passageDone)
        // Hangar: steht, solange das Schiff ruht; nach dem Start fährt die Kamera in einer festen Zeit heraus
        // Beim Abflug löst sich die Kamera schon während des Anrollens
        let holdHangar = game.phase == .docked && (game.departElapsed ?? 0) < Game.liftTime + 0.7
        // Anflug auf eine Station: weich in die Plattform-Nahaufnahme, statt hart zu schneiden
        if holdHangar && game.arriveAt != nil {
            hangar = min(1, hangar + dt / 1.2)
        } else {
            hangar = holdHangar ? 1 : max(0, hangar - dt / hangarBlendTime)
        }
        // Spielzeit steht im Menü still, deshalb hier die durchlaufende UI-Zeit
        let uiDt = max(0, min(0.1, game.uiTime - lastUITime))
        lastUITime = game.uiTime
        stationView = game.stationOpen ? min(1, stationView + uiDt / 1.4) : max(0, stationView - uiDt / 1.0)
        let kh = hangar * hangar * (3 - 2 * hangar)
        let k = chase * chase * (3 - 2 * chase)
        // Übergang aus der Anflug-Einstellung: eine einzige weiche Kurve (smootherstep) für Position,
        // Blick, Bildwinkel und Schiffsgröße, damit alles als eine Bewegung läuft
        let ap = 1 - arrival
        let ka = 1 - ap * ap * ap * (ap * (ap * 6 - 15) + 10)

        // Bildschirm-konstante Größe (Welt-Einheiten pro Punkt)
        let fovRad = CGFloat(50) * .pi / 180
        let topDist = (size.height / max(0.02, game.camScale) / 2) / tan(fovRad / 2)
        let chaseDist: CGFloat = 230
        let dist = topDist + (chaseDist - topDist) * k
        let normalPx = 2 * dist * tan(fovRad / 2) / size.height
        let px = normalPx + (parkedPx - normalPx) * ka
        lastPx = px

        let t0 = CACurrentMediaTime()
        syncPlanets(game, px: px)
        let t1 = CACurrentMediaTime()
        // Im Hangar die Planeten voraus ausblenden, sie lägen je nach Level hinter dem Titel
        for (i, n) in planetNodes where i > game.currentIndex {
            n.opacity = 1 - kh
        }
        for (i, r) in bonusRings where i > game.currentIndex {
            r.node.opacity = 1 - kh
        }
        syncOrbit(game, px: px, dt: dt)
        let t2 = CACurrentMediaTime()
        syncShip(game, px: normalPx, k: k, ka: ka, kh: kh)
        syncObjects(game, px: px)
        let t3 = CACurrentMediaTime()
        // Messung: einzelne langsame Abgleiche benennen
        if PerfLog.enabled && t3 - t0 > 0.012 {
            print(String(format: "OHSPIKE planets=%.1fms orbit=%.1fms objects=%.1fms idx=%d",
                         (t1 - t0) * 1000, (t2 - t1) * 1000, (t3 - t2) * 1000, game.currentIndex))
        }
        // ebenso Hindernisse, Nebel und Items auf der Strecke (nur solange der Hangar-Übergang läuft)
        if kh > 0 || lastHangarFade > 0 {
            for n in [asteroidNodes, cloudNodes, itemNodes].flatMap({ $0.values }) {
                n.opacity = 1 - kh
            }
        }
        lastHangarFade = kh
        syncDock(game)
        syncStationDocks(game)
        syncCamera(game, k: k, topDist: topDist, ka: ka, kh: kh)

        // Staub folgt der Kamera kachelweise
        let cp = cameraNode.position
        dust.position = SCNVector3(Float(floor(CGFloat(cp.x) / dustTile) * dustTile), 0,
                                   Float(floor(CGFloat(cp.z) / dustTile) * dustTile))
    }

    private func syncPlanets(_ game: Game, px: CGFloat) {
        let first = max(0, game.currentIndex - 3)
        for (i, n) in planetNodes where i < first {
            n.removeFromParentNode()
            planetNodes[i] = nil
        }
        for i in first..<game.planets.count where planetNodes[i] == nil {
            // Start- und Zielplanet sofort fertig, alles weiter voraus mit Textur aus dem Hintergrund
            let n = makePlanet(game.planets[i], index: i + game.generation * 1000, immediate: i <= game.currentIndex + 1)
            scene.rootNode.addChildNode(n)
            planetNodes[i] = n
        }

        // Doppelsterne: Stellung der Sonnen kommt aus dem Spiel (bestimmt das Pendeln der Bahn)
        for (i, n) in planetNodes where game.planets.indices.contains(i) && game.planets[i].kind == .binary {
            n.childNode(withName: "binary", recursively: true)?.eulerAngles.y = Float(-game.planets[i].binaryAngle(at: game.time))
        }

        // Ladering für Bonus-Items
        for (i, r) in bonusRings where i < first || game.bonusTaken.contains(i) {
            r.node.removeFromParentNode()
            bonusRings[i] = nil
        }
        for i in first..<game.planets.count {
            guard let kind = game.planets[i].bonus, !game.bonusTaken.contains(i) else { continue }
            if bonusRings[i] == nil {
                let r = makeBonusRing(game.planets[i], kind: kind)
                scene.rootNode.addChildNode(r.node)
                // Ladeshader schon jetzt übersetzen, nicht erst beim ersten Laden im Orbit
                view?.prepare([r.node], completionHandler: nil)
                bonusRings[i] = r
            }
            guard var r = bonusRings[i] else { continue }
            let isCur = i == game.currentIndex && game.phase != .over
            let frac = isCur ? min(1, game.orbitCharge / game.chargeNeeded) : 0
            updateProgress(&r, fraction: frac)
            // Fortschrittsring atmet beim Laden, damit man sieht, dass etwas passiert
            r.progress.opacity = frac > 0 ? 0.7 + 0.3 * CGFloat(sin(game.time * 5)) : 1
            bonusRings[i] = r
            if let badge = r.node.childNode(withName: "badge", recursively: false) {
                let s = Float(24 * px * (isCur ? 1 + 0.08 * sin(game.time * 6) : 1))
                badge.scale = SCNVector3(s, s, s)
                // Abstand zum Ring in Bildschirmpunkten, damit das Symbol bei jedem Zoom neben dem Planeten sitzt
                badge.position.z = Float(-(r.radius + 22 * px))
            }
        }

        // Zielerfassung
        lockGroup.isHidden = game.phase == .over || game.inHangarView
        let ti = game.currentIndex + 1
        if ti < game.planets.count {
            let t = game.planets[ti]
            if lockIndex != ti {
                lockIndex = ti
                rebuildLock(t)
            }
            lockGroup.position = v3(t.center)
            lockArcs.eulerAngles.y = Float(-game.time * 0.7)
            lockTicks.eulerAngles.y = Float(game.time * 0.2)
            lockHolo.eulerAngles.y = Float(-game.time * 0.4)
            let pulse = Float(1 + 0.05 * sin(game.time * 5))
            for n in lockGroup.childNodes where n.name == "bracket" { n.scale = SCNVector3(pulse, pulse, 1) }
        }
    }

    private func syncOrbit(_ game: Game, px: CGFloat, dt: CGFloat) {
        orbitGroup.isHidden = game.phase != .orbiting
        guard !orbitGroup.isHidden else {
            orbitReveal = 0
            return
        }
        // Weich einblenden: erst Bahn und Pfeile, der Kegel fährt leicht verzögert von der Spitze aus auf
        if orbitReveal == 0 { coneHeat = game.inCone ? 1 : 0 }
        orbitReveal = min(1, orbitReveal + dt / Self.orbitRevealTime)
        func smoother(_ x: CGFloat) -> CGFloat { let c = min(1, max(0, x)); return c * c * c * (c * (c * 6 - 15) + 10) }
        let ringIn = smoother(orbitReveal / 0.75)
        let coneIn = smoother((orbitReveal - 0.25) / 0.75)
        orbitRing.opacity = ringIn
        arrowSpinner.opacity = ringIn
        // im Stationsmenü kein Startkegel, er ragt sonst ins HUD
        coneNode.opacity = game.stationOpen ? 0 : coneIn
        let sweep = Float(0.2 + 0.8 * coneIn)
        coneNode.scale = SCNVector3(sweep, 1, sweep)
        let p = game.planets[game.currentIndex]
        if orbitIndex != game.currentIndex {
            orbitIndex = game.currentIndex
            rebuildOrbit(game)
        }
        orbitGroup.position = v3(p.center)
        // Schwarzes Loch: die Bahnanzeige schrumpft mit der zerfallenden Bahn
        let ringScale = Float(game.orbitRingRadius / p.orbitRadius)
        orbitRing.scale = SCNVector3(ringScale, 1, ringScale)
        for (q, holder) in arrowSpinner.childNodes.enumerated() {
            let a = CGFloat(q) / 6 * .pi * 2
            holder.position = SCNVector3(Float(cos(a) * game.orbitRingRadius), 0, Float(sin(a) * game.orbitRingRadius))
        }
        arrowSpinner.eulerAngles.y = Float(-game.orbitDir * game.time * 0.5)
        arrowSpinner.childNodes.forEach { $0.childNodes.first?.eulerAngles.x = Float(game.orbitDir > 0 ? Float.pi / 2 : -Float.pi / 2) }

        let key = "\(game.currentIndex)-\(Int(game.coneHalfAngle * 1000))"
        if key != coneKey {
            coneKey = key
            rebuildCone(game)
        }
        let apex = point(from: p.center, angle: game.coneApexAngle, distance: game.orbitRingRadius)
        coneNode.position = SCNVector3(Float(apex.x - p.center.x), 0, Float(apex.y - p.center.y))
        coneNode.eulerAngles.y = Float(-game.coneDirection)
        coneHeat = smoothApproach(coneHeat, game.inCone ? 1 : 0, rate: 14, dt: dt)
        let h = coneHeat
        let tint = UIColor(red: 0.55 + (0.25 - 0.55) * h, green: 0.55 + (0.75 - 0.55) * h,
                           blue: 0.55 + (0.62 - 0.55) * h, alpha: 1)
        coneMats.forEach { $0.multiply.contents = tint }
    }

    /// Schiff zerstört: das Modell zerfällt in seine Einzelteile, die brennend auseinanderfliegen,
    /// dazu mehrere kleine Feuerbälle nacheinander über dem Wrack
    private func explodeShip(_ game: Game) {
        guard let model = shipModelNode, let src = debrisSource else { return }
        let base = model.worldTransform
        let center = SCNVector3(base.m41, base.m42, base.m43)
        // Wrack um die Schiffsmitte aufhängen: in der Draufsicht (Orbit) ist das Schiff größer gezeichnet als in der
        // Nahaufnahme; beim Heranfahren der Kamera schrumpft das Wrack auf Nahaufnahme-Maß, damit Teile und Tempo passen
        let root = SCNNode()
        root.position = center
        scene.rootNode.addChildNode(root)
        // Größe des Schiffs in Weltkoordinaten (für Tempo der Teile und Abstand der Feuerbälle)
        let probe = SCNNode()
        probe.transform = base
        let (mn, mx) = src.boundingBox
        let a = probe.convertPosition(mn, to: nil), b = probe.convertPosition(mx, to: nil)
        let ex = b.x - a.x, ey = b.y - a.y, ez = b.z - a.z
        let size = max(8, CGFloat((ex * ex + ey * ey + ez * ez).squareRoot()))

        var pieces: [SCNNode] = []
        src.enumerateHierarchy { n, _ in
            if n.geometry != nil { pieces.append(n) }
        }
        // sehr viele Kleinteile zusammen begrenzen: größere Teile bevorzugt
        func volume(_ n: SCNNode) -> Float {
            let (lo, hi) = n.boundingBox
            let sc = n.scale
            return abs((hi.x - lo.x) * sc.x * (hi.y - lo.y) * sc.y * (hi.z - lo.z) * sc.z)
        }
        pieces = Array(pieces.sorted { volume($0) > volume($1) }.prefix(36))
        for (i, n) in pieces.enumerated() {
            let local = src.convertTransform(SCNMatrix4Identity, from: n)
            let c = SCNNode(geometry: n.geometry)
            c.transform = root.convertTransform(SCNMatrix4Mult(local, base), from: nil)
            root.addChildNode(c)
            // nach außen, weg von der Schiffsmitte, mit etwas Zufall und Auftrieb
            var dx = CGFloat(c.position.x), dz = CGFloat(c.position.z)
            let len = max(0.001, hypot(dx, dz))
            dx /= len; dz /= len
            let ang = atan2(dz, dx) + CGFloat.random(in: -0.6...0.6)
            let speed = size * CGFloat.random(in: 1.2...3.2)
            let move = SCNAction.move(by: SCNVector3(Float(cos(ang) * speed), Float(size * CGFloat.random(in: -0.6...1.2)),
                                                     Float(sin(ang) * speed)), duration: 2.6)
            move.timingMode = .easeOut
            let axis = SCNVector3(Float.random(in: -1...1), Float.random(in: -1...1), Float.random(in: -1...1))
            c.runAction(.group([
                move,
                .rotate(by: CGFloat.random(in: 3...10), around: axis, duration: 2.6),
                .sequence([.wait(duration: 1.7 + Double.random(in: 0...0.5)), .fadeOut(duration: 0.6)])
            ]))
            // die größten Teile ziehen eine kurze Feuerspur hinter sich her
            if i < 6 {
                let trail = SCNParticleSystem()
                trail.birthRate = 90
                trail.particleLifeSpan = 0.45
                trail.particleLifeSpanVariation = 0.15
                trail.particleVelocity = 6
                trail.spreadingAngle = 180
                trail.particleSize = size * 0.09
                trail.particleImage = WorldTextures.soft
                trail.blendMode = .additive
                trail.isLightingEnabled = false
                trail.isAffectedByGravity = false
                trail.particleColor = UIColor(red: 1, green: 0.55, blue: 0.15, alpha: 0.9)
                let grow = CAKeyframeAnimation()
                grow.values = [1.0, 0.3]
                let fade = CAKeyframeAnimation()
                fade.values = [1, 0]
                trail.propertyControllers = [.size: SCNParticlePropertyController(animation: grow),
                                             .opacity: SCNParticlePropertyController(animation: fade)]
                c.addParticleSystem(trail)
                // Feuer erlischt, bevor das Teil verblasst; reset() nimmt auch die schon ausgestoßenen Partikel mit
                c.runAction(.sequence([.wait(duration: 1.2 + Double.random(in: 0...0.5)),
                                       .run { _ in trail.birthRate = 0 },
                                       .wait(duration: 0.5),
                                       .run { node in trail.reset(); node.removeAllParticleSystems() }]))
            }
        }

        // kleine Feuerbälle nacheinander, verteilt über das Wrack: heller Kern, orange Hülle, dunkler Rauch
        for k in 0..<8 {
            let delay = k == 0 ? 0 : Double.random(in: 0.05...1.1)
            let off = SCNVector3(Float(size * CGFloat.random(in: -0.7...0.7)), Float(size * CGFloat.random(in: -0.2...0.4)),
                                 Float(size * CGFloat.random(in: -0.7...0.7)))
            // deutlich größer als die Funken, damit man die einzelnen Feuerbälle erkennt
            let big: CGFloat = k == 0 ? 2.6 : CGFloat.random(in: 1.3...2.0)
            let ball = SCNNode()
            ball.position = off
            ball.opacity = 0
            root.addChildNode(ball)
            for (scale, color, additive) in [(1.0, UIColor(red: 1, green: 0.42, blue: 0.08, alpha: 1), true),
                                             (0.55, UIColor(red: 1, green: 0.9, blue: 0.6, alpha: 1), true),
                                             (1.3, UIColor(white: 0.12, alpha: 0.75), false)] as [(CGFloat, UIColor, Bool)] {
                let w = size * big * scale
                let plane = SCNNode(geometry: SCNPlane(width: w, height: w))
                let m = spriteMat(WorldTextures.soft)
                m.multiply.contents = color
                if !additive {
                    m.blendMode = .alpha
                    plane.renderingOrder = 8
                } else {
                    plane.renderingOrder = 9
                }
                plane.geometry?.materials = [m]
                plane.constraints = [SCNBillboardConstraint()]
                if !additive {
                    // Rauch quillt langsamer auf und bleibt etwas länger stehen
                    plane.scale = SCNVector3(0.4, 0.4, 0.4)
                    plane.runAction(.scale(to: 1.4, duration: 1.1))
                } else {
                    plane.scale = SCNVector3(0.2, 0.2, 0.2)
                    let pop = SCNAction.scale(to: 1, duration: 0.18)
                    pop.timingMode = .easeOut
                    plane.runAction(.sequence([pop, .group([.scale(to: 1.25, duration: 0.4), .fadeOut(duration: 0.4)])]))
                }
                ball.addChildNode(plane)
            }
            ball.runAction(.sequence([.wait(duration: delay), .fadeIn(duration: 0.04),
                                      .wait(duration: 0.7), .fadeOut(duration: 0.5), .removeFromParentNode()]))
        }
        let f = Float(min(1, 5 / max(0.1, lastShipScale)))
        if f < 0.99 {
            let shrink = SCNAction.scale(to: CGFloat(f), duration: 0.9)
            shrink.timingMode = .easeInEaseOut
            root.runAction(shrink)
        }
        root.runAction(.sequence([.wait(duration: 3.0), .removeFromParentNode()]))
    }

    /// Materialien, Partikel und Wrackteile der Explosion einmal vorab auf die GPU laden, sonst hängt das erste Bild
    private func prepareExplosion(_ src: SCNNode) {
        let warm = SCNNode()
        warm.addChildNode(src.clone())
        for blend in [SCNBlendMode.add, .alpha] {
            let plane = SCNNode(geometry: SCNPlane(width: 1, height: 1))
            let m = spriteMat(WorldTextures.soft)
            m.multiply.contents = UIColor.orange
            m.blendMode = blend
            plane.geometry?.materials = [m]
            warm.addChildNode(plane)
        }
        upload(warm) {}
    }

    private func syncShip(_ game: Game, px: CGFloat, k: CGFloat, ka: CGFloat, kh: CGFloat) {
        if shipID != game.ship.model.id {
            shipID = game.ship.model.id
            shipModelNode?.removeFromParentNode()
            let n = Ship3D.shipNode(for: game.ship.model, showcase: false)
            bankNode.addChildNode(n)
            shipModelNode = n
            // Düsenglut dieses Schiffs: eigene Kopie der Glut-Materialien (das Modell ist zusammengefasst und teilt
            // seine Materialien), dazu die Glut-Sprites hinter den Düsen
            var mats: [SCNMaterial] = []
            var bases: [UIColor] = []
            let glowNames: Set<String> = ["engineFire", "weaponGlow"]
            n.enumerateHierarchy { node, _ in
                guard let g = node.geometry, g.materials.contains(where: { glowNames.contains($0.name ?? "") }) else { return }
                let own = g.copy() as! SCNGeometry
                own.materials = g.materials.map { m in
                    guard glowNames.contains(m.name ?? "") else { return m }
                    let c = m.copy() as! SCNMaterial
                    mats.append(c)
                    bases.append((m.diffuse.contents as? UIColor) ?? .orange)
                    return c
                }
                node.geometry = own
            }
            nozzleMats = mats
            nozzleBase = bases
            nozzleHalos = Ship3D.outlets(of: n).flatMap { $0.0.childNodes }
            // Einzelteile für die Explosion vorhalten (Materialien sind ohnehin im ShipKit-Cache)
            let src = ShipDesigns.build(game.ship.model)
            debrisSource = src
            prepareExplosion(src)

        }
        // Triebwerke aus (Spielende): Düsenglut klingt ab
        let glowTarget: CGFloat = game.phase == .over ? 0 : 1
        nozzleGlow = smoothApproach(nozzleGlow, glowTarget, rate: 2.2, dt: max(0, min(0.1, game.time - lastNozzleTime)))
        lastNozzleTime = game.time
        if game.phase != .over { nozzleGlow = 1 }
        if abs(nozzleGlow - appliedNozzleGlow) > 0.01 || (nozzleGlow == 1 && appliedNozzleGlow != 1) {
            appliedNozzleGlow = nozzleGlow
            // Farbe direkt setzen (multiply wirkt beim konstanten Glut-Material nicht zuverlässig): von Orange zu kalt-dunkel
            let g = nozzleGlow
            for (m, base) in zip(nozzleMats, nozzleBase) {
                var r: CGFloat = 0, gr: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
                base.getRed(&r, green: &gr, blue: &b, alpha: &a)
                // von der Grundfarbe zu kalt-dunkel
                let ember = UIColor(red: 0.05 + (r - 0.05) * g, green: 0.045 + (gr - 0.045) * g, blue: 0.04 + (b - 0.04) * g, alpha: 1)
                m.diffuse.contents = ember
                m.emission.contents = ember
            }
            for h in nozzleHalos { h.opacity = nozzleGlow }
        }
        // ohne Energie bleibt das Schiff sichtbar und gleitet aus, nur ein zerstörtes verschwindet in der Explosion
        if game.phase == .over && game.destroyed {
            if !exploded {
                exploded = true
                explodeShip(game)
            }
        } else {
            exploded = false
        }
        shipHolder.isHidden = game.phase == .over && game.destroyed
        shipHolder.position = v3(game.pos, 4 + game.liftHeight)
        // leichte Schräglage in Kurven
        let bank: CGFloat = game.phase == .orbiting ? -game.orbitDir * 0.35 : game.dodgeBank * 0.6
        shipHolder.eulerAngles.y = Float(-game.heading)
        bankNode.eulerAngles.x = Float(bank)
        // bildschirmfest, aber nie zu groß im Vergleich zu den Planeten
        let topScale = min(8.4 * px, 14)
        var sc = topScale + (5.0 - topScale) * k
        sc += (parkedScale - sc) * ka
        sc += (5.0 - sc) * kh
        lastShipScale = sc
        let s = Float(sc)
        shipHolder.scale = SCNVector3(s, s, s)

        let flying = game.phase == .flying
        let boost = game.boostTime > 0
        for (ps, r) in exhausts {
            // im Hangar aus, beim Abheben leise, beim Anrollen voll
            let departing: CGFloat = game.departElapsed.map { $0 > Game.liftTime ? 120 : 30 } ?? (game.dockArriving ? 60 : 0)
            ps.birthRate = game.phase == .over ? 0 : (game.phase == .docked ? departing : (flying ? (boost ? 260 : 120) : 35))
            ps.particleVelocity = CGFloat(s) * (flying || departing > 100 ? (boost ? 6 : 3) : 1.5)
            ps.particleSize = CGFloat(s) * r * (boost ? 1.7 : 1.25)
        }
        trail.birthRate = flying ? 90 : (game.phase == .orbiting ? 40 : 0)
        trail.particleSize = CGFloat(s) * 0.22

        // Schadensbild nach Panzerung
        let alive = game.phase != .over && game.phase != .docked
        let hull = game.hull
        damageSmoke.birthRate = alive && hull < 50 ? 30 + 60 * (1 - hull / 50) : 0
        damageSmoke.particleSize = CGFloat(s) * 0.55
        // Funken flackern: in unregelmäßigen Stößen, ab und zu ein kräftiger Schauer
        let wave = sin(game.time * 23) + sin(game.time * 37 + 1.3)
        let burstNow = sin(game.time * 2.3) + sin(game.time * 5.1 + 0.7) > 1.5
        damageSparks.birthRate = alive && hull < 25 && wave > 0.2 ? (burstNow ? 420 : 140) : 0
        damageSparks.particleVelocity = CGFloat(s) * 9
        damageSparks.particleVelocityVariation = CGFloat(s) * 5
        damageSparks.particleSize = CGFloat(s) * 0.2
        // neuer Treffer: Schild blitzt auf und klingt in knapp einer halben Sekunde ab, Funken nur im ersten Moment
        if game.brakeFlash > lastBrakeFlash + 0.05 { hitAt = game.time }
        lastBrakeFlash = game.brakeFlash
        let age = game.time - hitAt
        let e = alive ? max(0, 1 - age / 0.45) : 0
        let strength = Float(e * e * 1.4)
        if abs(strength - appliedHit) > 0.01 || (strength == 0 && appliedHit != 0) {
            appliedHit = strength
            hitShellMat?.setValue(strength, forKey: "intensity")
        }
        // Schild weitet sich beim Abklingen leicht
        let grow = Float(1 + 0.18 * (1 - e))
        hitFlash.scale = SCNVector3(1.25 * grow, 0.6 * grow, 1.0 * grow)
        impactSparks.birthRate = alive && age < 0.08 ? 900 : 0
        impactSparks.particleVelocity = CGFloat(s) * 14
        impactSparks.particleVelocityVariation = CGFloat(s) * 7
        impactSparks.particleSize = CGFloat(s) * 0.18
    }

    private var lastObjectsTime: CGFloat = 0

    private func syncObjects(_ game: Game, px: CGFloat) {
        let dt = max(0, min(0.1, game.time - lastObjectsTime))
        lastObjectsTime = game.time
        // zerstörte Kometen zerplatzen, statt einfach zu verschwinden
        for a in game.shatters { shatterComet(a) }
        game.shatters.removeAll()

        // Asteroiden
        var alive = Set<Int>()
        for a in game.asteroids {
            alive.insert(a.uid)
            if let n = asteroidNodes[a.uid] {
                if a.kind != .rock {
                    n.position = SCNVector3(Float(a.center.x), n.position.y, Float(a.center.y))
                }
                if a.kind == .comet && (a.vel.dx != 0 || a.vel.dy != 0) {
                    n.eulerAngles.y = Float(-atan2(a.vel.dy, a.vel.dx))
                }
                // Drohnen schauen in Flugrichtung, sobald sie Tempo haben
                if a.kind == .drone {
                    // beim Zielen schaut das Auge aufs Schiff, sonst in Flugrichtung
                    let aim = (droneOpen[a.uid] ?? 0) > 0.05
                    if aim {
                        n.eulerAngles.y = Float(-atan2(game.pos.y - a.center.y, game.pos.x - a.center.x))
                    } else if hypot(a.vel.dx, a.vel.dy) > 40 {
                        n.eulerAngles.y = Float(-atan2(a.vel.dy, a.vel.dx))
                    }
                    animateDrone(n, a, game, dt: dt)
                }
            } else {
                let n = makeObstacle(a)
                scene.rootNode.addChildNode(n)
                asteroidNodes[a.uid] = n
            }
        }
        for (id, n) in asteroidNodes where !alive.contains(id) {
            killParticles(n)
            n.removeFromParentNode()
            asteroidNodes[id] = nil
            droneOpen[id] = nil
        }
        // Wrack-Modelle nur vorhalten, solange ein Wrackfeld in der Nähe ist (je Typ etwa 10 MB Lacktexturen)
        if !wreckModels.isEmpty && !game.asteroids.contains(where: { $0.kind == .wreck }) {
            wreckModels.removeAll()
        }

        // Nebel
        alive = []
        for c in game.clouds {
            alive.insert(c.uid)
            if cloudNodes[c.uid] == nil {
                let n = makeCloud(c)
                scene.rootNode.addChildNode(n)
                cloudNodes[c.uid] = n
            }
        }
        for (id, n) in cloudNodes where !alive.contains(id) {
            n.removeFromParentNode()
            cloudNodes[id] = nil
        }

        // Items
        alive = []
        for it in game.items {
            alive.insert(it.uid)
            let n: SCNNode
            if let e = itemNodes[it.uid] { n = e } else {
                n = makeItem(it)
                scene.rootNode.addChildNode(n)
                itemNodes[it.uid] = n
            }
            let t = min(1, it.age / Item.flyTime)
            let grow = 0.4 + 0.9 * sin(t * .pi) + 0.3 * (1 - t)
            let s = Float(30 * px * grow)
            n.scale = SCNVector3(s, s, s)
            n.position = v3(it.p, 8)
        }
        for (id, n) in itemNodes where !alive.contains(id) {
            n.removeFromParentNode()
            itemNodes[id] = nil
        }

        // Geschosse
        alive = []
        for pr in game.projectiles {
            alive.insert(pr.uid)
            let n: SCNNode
            if let e = projectileNodes[pr.uid] { n = e } else {
                n = makeProjectile(pr)
                scene.rootNode.addChildNode(n)
                projectileNodes[pr.uid] = n
            }
            n.position = v3(pr.p, 4)
            if let b = n.childNode(withName: "bolt", recursively: false) {
                let size: CGFloat = pr.kind == .bomb ? 12 : 10
                let s = Float(size * px)
                b.scale = SCNVector3(s, s, s)
                b.eulerAngles.y = Float(-atan2(pr.v.dy, pr.v.dx))
            }
        }
        for (id, n) in projectileNodes where !alive.contains(id) {
            n.removeFromParentNode()
            projectileNodes[id] = nil
        }

        // Plasmaschüsse der Drohnen
        alive = []
        for sh in game.enemyShots {
            alive.insert(sh.uid)
            let n: SCNNode
            if let e = enemyShotNodes[sh.uid] { n = e } else {
                n = makeEnemyShot()
                scene.rootNode.addChildNode(n)
                enemyShotNodes[sh.uid] = n
            }
            n.position = v3(sh.p, 5)
        }
        for (id, n) in enemyShotNodes where !alive.contains(id) {
            n.removeFromParentNode()
            enemyShotNodes[id] = nil
        }

        // einmalige Effekte
        for b in game.beams where !seenBeams.contains(b.uid) {
            seenBeams.insert(b.uid)
            spawnBeam(b, px: px)
        }
        // Strahl geht immer vom Schiff aus
        activeBeams.removeAll { $0.node.parent == nil }
        for b in activeBeams {
            let start = point(from: game.pos, angle: b.angle, distance: 30)
            b.node.position = v3(point(from: start, angle: b.angle, distance: b.len / 2))
        }
        for w in game.waves where !seenWaves.contains(w.uid) {
            seenWaves.insert(w.uid)
            spawnWave(w, px: px)
        }
        if seenWaves.count > 300 { seenWaves = Set(game.waves.map(\.uid)) }
        if seenBeams.count > 300 { seenBeams = Set(game.beams.map(\.uid)) }
        for b in game.bursts { spawnBurst(b, px: px) }
        game.bursts.removeAll()
    }

    // MARK: Anflug-Einstellung

    private var arrival: CGFloat = 0
    private var arrivalActive = false
    private var arrivalIndex = -1
    private var arrivalHold: CGFloat = .infinity
    /// Dauer des Übergangs von der angehaltenen Kamera in die Orbit-Ansicht
    private let arrivalBlendTime: CGFloat = 1.7
    private var parkedPos = SCNVector3(0, 0, 0)
    private var parkedLook = SCNVector3(0, 0, 0)
    private var parkedScale: CGFloat = 1
    private var parkedPx: CGFloat = 1
    private var parkedFov: CGFloat = 50
    private var lastShipScale: CGFloat = 1
    private var lastPx: CGFloat = 1
    private var lastLook = SCNVector3(0, 0, 0)

    /// Am Ende der Hindernispassage bleibt die Kamera hinter dem Schiff stehen und lässt es auf den Orbit zufliegen.
    /// Kurz vor dem Orbit wechselt sie langsam in die Draufsicht.
    private func updateArrival(_ game: Game, dt: CGFloat, ti: Int, distT: CGFloat, tgt: Planet, passageDone: Bool) {
        if game.phase == .over {
            arrivalActive = false
            arrival = 0
            return
        }
        // Kamera hält genau dort an, wo sie gerade ist: kein eigener Kameraschwenk
        // nur aus der Nahansicht (Verfolgerkamera), nie in der Draufsicht
        if game.phase == .flying && arrivalIndex != ti && passageDone && chase > 0.15 {
            arrivalIndex = ti
            arrivalActive = true
            // stehen bleiben, bis das Schiff kurz vor dem Orbit ist (Sicherheitsgrenze 6 s), dann in die Draufsicht
            arrivalHold = game.time + 6
            parkedPos = cameraNode.position
            parkedLook = lastLook
            parkedScale = lastShipScale
            parkedPx = lastPx
            parkedFov = cameraNode.camera?.fieldOfView ?? 50
            arrival = 1
            // Verfolgerkamera und Draufsicht stellen sich unsichtbar dahinter auf den Orbit-Ausschnitt ein
            chase = 0
            chaseOn = false
            game.cameraLock = ti
        }
        // ein einziger Übergang in den vorab berechneten Orbit-Ausschnitt, noch vor dem Orbiteintritt
        if arrivalActive && game.time < arrivalHold
            && (game.phase == .orbiting || distT < tgt.orbitRadius + 450
                // fliegt das Schiff nicht mehr aufs Ziel zu (abgelenkt oder vorbei), nicht weiter stehen bleiben
                || game.vel.dx * (tgt.center.x - game.pos.x) + game.vel.dy * (tgt.center.y - game.pos.y) < 0) {
            arrivalHold = game.time
        }
        let want: CGFloat = arrivalActive && game.time < arrivalHold ? 1 : 0
        // feste Dauer statt exponentiellem Ausklingen: kein langer Schwanz am Ende,
        // die weiche Kurve kommt über smoothstep in sync/syncCamera
        arrival = want == 1 ? 1 : max(0, arrival - dt / arrivalBlendTime)
        if want == 0 && arrival < 0.01 {
            arrival = 0
            arrivalActive = false
            if game.phase == .orbiting { game.cameraLock = nil }
        }
    }

    private func syncCamera(_ game: Game, k: CGFloat, topDist: CGFloat, ka: CGFloat, kh: CGFloat) {
        // Draufsicht, leicht gekippt
        let tilt: CGFloat = 0.42
        let target = v3(game.cam)
        let topPos = SCNVector3(target.x, Float(topDist * cos(tilt)), target.z + Float(topDist * sin(tilt)))

        // hinter und über dem Schiff
        let hd = chaseHeading.value
        // beim Ausweichen zieht die Kamera seitlich verzögert nach
        let lag = game.dodgeCameraLag
        let ship = CGPoint(x: game.pos.x - lag.dx, y: game.pos.y - lag.dy)
        // beim Ausgleiten ohne Energie fährt sie langsam noch dichter heran
        let cc = coastClose * coastClose * (3 - 2 * coastClose)
        let bv = blastView * blastView * (3 - 2 * blastView)
        let back = 190 - 95 * cc + 70 * bv, height = Float(95 - 45 * cc + 55 * bv), ahead = (260 - 130 * cc) * (1 - bv)
        let chasePos = SCNVector3(Float(ship.x - cos(hd) * back), height, Float(ship.y - sin(hd) * back))
        let chaseLook = SCNVector3(Float(ship.x + cos(hd) * ahead), 0, Float(ship.y + sin(hd) * ahead))

        func mix(_ a: SCNVector3, _ b: SCNVector3) -> SCNVector3 {
            let f = Float(k)
            return SCNVector3(a.x + (b.x - a.x) * f, a.y + (b.y - a.y) * f, a.z + (b.z - a.z) * f)
        }
        var pos = mix(topPos, chasePos)
        var look = mix(target, chaseLook)
        // Beim Herauszoomen gleitet die Kamera zugleich nach vorn, statt nach hinten wegzufahren
        if releasing {
            let bump = Float(sin(k * .pi) * topDist * 0.15)
            pos.x += Float(cos(hd)) * bump
            pos.z += Float(sin(hd)) * bump
        }
        // Start-Kick: kurzer Ruck in Flugrichtung, Kamera und Blickpunkt gemeinsam
        let kick = launchKick(game)
        if kick > 0 {
            let push = Float(kick) * pos.y * 0.05
            let fx = Float(cos(game.heading)) * push, fz = Float(sin(game.heading)) * push
            pos.x += fx
            pos.z += fz
            look.x += fx
            look.z += fz
        }
        // Wackeln: glattes Rauschen aus überlagerten Sinuswellen statt Zufall pro Bild, dazu leichtes Rollen
        var roll: Float = 0
        if game.shake > 0 {
            let t = Float(game.time)
            let amp = Float(game.shake) * pos.y * 0.012
            pos.x += amp * (sin(t * 23.7) * 0.6 + sin(t * 41.3 + 1.7) * 0.4)
            pos.z += amp * (sin(t * 29.1 + 0.4) * 0.6 + sin(t * 47.9 + 2.9) * 0.4)
            roll = Float(game.shake) * 0.035 * (sin(t * 19.3 + 0.8) * 0.7 + sin(t * 33.1) * 0.3)
        }
        // Anflug-Einstellung einblenden: als Bogenfahrt um den Planeten (Abstand, Richtung und Höhenwinkel
        // werden gemeinsam überblendet) statt einer geraden Linie. Dreht sich und zieht hoch in einem Zug.
        var lookA = look
        if ka > 0 {
            let fa = Float(ka)
            let pivot = look
            func spherical(_ p: SCNVector3) -> (d: Float, az: Float, el: Float) {
                let vx = p.x - pivot.x, vy = p.y - pivot.y, vz = p.z - pivot.z
                let d = max(1, (vx * vx + vy * vy + vz * vz).squareRoot())
                return (d, atan2(vz, vx), asin(max(-1, min(1, vy / d))))
            }
            let a = spherical(pos), b = spherical(parkedPos)
            var dAz = (b.az - a.az).truncatingRemainder(dividingBy: 2 * .pi)
            if dAz > .pi { dAz -= 2 * .pi }
            if dAz < -.pi { dAz += 2 * .pi }
            let d = exp(log(a.d) + (log(b.d) - log(a.d)) * fa)
            let az = a.az + dAz * fa
            let el = a.el + (b.el - a.el) * fa
            pos = SCNVector3(pivot.x + d * cos(el) * cos(az), pivot.y + d * sin(el), pivot.z + d * cos(el) * sin(az))
            lookA = SCNVector3(look.x + (parkedLook.x - look.x) * fa, look.y + (parkedLook.y - look.y) * fa, look.z + (parkedLook.z - look.z) * fa)
        }
        // Hangar-Nahaufnahme von hinten links, fest am Liegeplatz: das Schiff fliegt beim Start aus dem Bild,
        // dann zieht die Kamera hoch in die Übersicht
        if kh > 0 {
            let dh = game.dockHeading, dp = game.dockPos
            let fx = cos(dh), fz = sin(dh)
            // links aus Sicht hinter dem Schiff
            let lx = fz, lz = -fx
            // weit genug hinten, dass beide Pylonen des Tors im Bild sind
            var hangarPos = SCNVector3(Float(dp.x - fx * 110 + lx * 30), 26, Float(dp.y - fz * 110 + lz * 30))
            var hangarLook = SCNVector3(Float(dp.x + fx * 22), 7, Float(dp.y + fz * 22))
            // Anflug auf eine Station: dieselbe Nahansicht, aber so weit zurückgezogen und zwischen Schiff und
            // Plattform ausgerichtet, dass beide im Bild sind; beim Näherkommen läuft sie in die feste Einstellung
            if game.dockArriving {
                let sx = game.pos.x - dp.x, sz = game.pos.y - dp.y
                let gap = hypot(sx, sz)
                let mx = dp.x + sx * 0.5, mz = dp.y + sz * 0.5
                let back = 110 + gap * 0.55
                hangarPos = SCNVector3(Float(mx - fx * back + lx * (30 + gap * 0.15)), Float(26 + gap * 0.28), Float(mz - fz * back + lz * (30 + gap * 0.15)))
                hangarLook = SCNVector3(Float(mx + fx * 22), 7, Float(mz + fz * 22))
            }
            let f = Float(kh)
            pos = SCNVector3(pos.x + (hangarPos.x - pos.x) * f, pos.y + (hangarPos.y - pos.y) * f, pos.z + (hangarPos.z - pos.z) * f)
            lookA = SCNVector3(lookA.x + (hangarLook.x - lookA.x) * f, lookA.y + (hangarLook.y - lookA.y) * f, lookA.z + (hangarLook.z - lookA.z) * f)
        }
        // Stationsmenü: schräger 3/4-Blick auf die Station statt Draufsicht
        let sv = Float(stationView * stationView * (3 - 2 * stationView))
        if sv > 0, game.planets.indices.contains(game.currentIndex) {
            let sp = game.planets[game.currentIndex]
            let center = SCNVector3(Float(sp.center.x), 0, Float(sp.center.y))
            // von vorn rechts, etwa 33° über der Bahnebene
            let el: Float = 0.58, az: Float = 1.25
            let d = Float(topDist) * 0.92
            let svPos = SCNVector3(center.x + d * cos(el) * cos(az), d * sin(el), center.z + d * cos(el) * sin(az))
            pos = SCNVector3(pos.x + (svPos.x - pos.x) * sv, pos.y + (svPos.y - pos.y) * sv, pos.z + (svPos.z - pos.z) * sv)
            // Blickpunkt vor die Station ziehen, damit sie im oberen Drittel über dem Menü sitzt:
            // die Kamera schaut um tilt steiler nach unten als zur Stationsmitte
            let tilt: Float = 0.12
            let h = d * sin(el), dh = d * cos(el)
            let pull = dh - h / tan(el + tilt)
            let svLook = SCNVector3(center.x + pull * cos(az), 0, center.z + pull * sin(az))
            lookA = SCNVector3(lookA.x + (svLook.x - lookA.x) * sv, lookA.y + (svLook.y - lookA.y) * sv, lookA.z + (svLook.z - lookA.z) * sv)
        }
        cameraNode.position = pos
        // Rollen: Hochrichtung leicht zur Seite kippen (Seite = Blickrichtung × oben)
        let dx = lookA.x - pos.x, dz = lookA.z - pos.z
        let len = max(0.001, (dx * dx + dz * dz).squareRoot())
        let up = SCNVector3(-dz / len * roll, 1, dx / len * roll)
        cameraNode.look(at: lookA, up: up, localFront: SCNVector3(0, 0, -1))
        lastLook = lookA
        let normalFov = 50 + 12 * k
        var fov = normalFov + (parkedFov - normalFov) * ka
        fov += (55 - fov) * kh
        cameraNode.camera?.fieldOfView = fov + 9 * kick
    }

    /// Hüllkurve des Start-Kicks: steigt in 0,09 s auf das Maximum und klingt dann ab.
    /// Ein knapper Start ist kaum zu spüren, ein perfekter deutlich.
    private func launchKick(_ game: Game) -> CGFloat {
        let t = game.time - game.lastLaunchTime
        guard t >= 0, t < 0.8, game.phase != .over else { return 0 }
        let tau: CGFloat = 0.09
        let envelope = (t / tau) * exp(1 - t / tau)
        let a = game.lastAccuracy
        return envelope * (0.15 + 0.85 * a * a)
    }

    // MARK: Projektion für das HUD

    func project(_ p: CGPoint) -> CGPoint? {
        guard let view else { return nil }
        let v = view.projectPoint(v3(p))
        guard v.z > 0, v.z < 1 else { return nil }
        return CGPoint(x: CGFloat(v.x), y: CGFloat(v.y))
    }
}

extension WorldTextures {
    static let railHue: Double = WeaponKind.railgun.hue

    /// Verlauf im Startkegel: zur Spitze hell, nach außen dunkel
    static let coneFade: UIImage = textureRenderer(CGSize(width: 256, height: 8)).image { ctx in
        let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                           colors: [UIColor(white: 0.45, alpha: 1).cgColor, UIColor(white: 0, alpha: 1).cgColor] as CFArray,
                           locations: [0, 1])!
        ctx.cgContext.drawLinearGradient(g, start: .zero, end: CGPoint(x: 256, y: 0), options: [])
    }

    /// Holo-Gitter der Zielerfassung, wird für jeden Zielplaneten wiederverwendet
    static let holoGrid: UIImage = textureRenderer(CGSize(width: 512, height: 256), scale: 2).image { ctx in
        let g = ctx.cgContext
        g.setStrokeColor(UIColor(white: 1, alpha: 0.5).cgColor)
        g.setLineWidth(1.5)
        for k in 0...16 { let x = CGFloat(k) * 32; g.move(to: CGPoint(x: x, y: 0)); g.addLine(to: CGPoint(x: x, y: 256)) }
        for k in 0...8 { let y = CGFloat(k) * 32; g.move(to: CGPoint(x: 0, y: y)); g.addLine(to: CGPoint(x: 512, y: y)) }
        g.strokePath()
    }
}

// MARK: - SwiftUI-Hülle

struct WorldView: UIViewRepresentable {
    let world: World3D
    /// angehalten, solange ein Vollbild-Menü (Werft, Missionen) die Welt verdeckt
    var paused = false

    func makeCoordinator() -> FrameCounter { FrameCounter() }

    /// zählt fertig gezeichnete SceneKit-Bilder für die Bildraten-Messung
    final class FrameCounter: NSObject, SCNSceneRendererDelegate {
        func renderer(_ renderer: SCNSceneRenderer, didRenderScene scene: SCNScene, atTime time: TimeInterval) {
            PerfLog.sceneFrame()
        }
    }

    func makeUIView(context: Context) -> SCNView {
        let v = SCNView()
        if PerfLog.enabled { v.delegate = context.coordinator }
        v.scene = world.scene
        v.pointOfView = world.cameraNode
        v.backgroundColor = .black
        // 2× reicht bei der Pixeldichte aktueller iPhones; 4× verdoppelt die HDR-Bildpuffer
        v.antialiasingMode = .multisampling2X
        v.preferredFramesPerSecond = 60
        apply(paused, to: v)
        world.view = v
        return v
    }

    func updateUIView(_ v: SCNView, context: Context) {
        if v.isPlaying == paused { apply(paused, to: v) }
    }

    private func apply(_ paused: Bool, to v: SCNView) {
        v.isPlaying = !paused
        v.rendersContinuously = !paused
    }
}
