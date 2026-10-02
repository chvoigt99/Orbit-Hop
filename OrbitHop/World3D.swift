import SwiftUI
import SceneKit
import UIKit

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

    static func radial(size: Int, stops: [(CGFloat, CGFloat)]) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: size, height: size)).image { ctx in
            let colors = stops.map { UIColor(white: 1, alpha: $0.0).cgColor } as CFArray
            let locs = stops.map { $0.1 }
            let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: locs)!
            let c = CGPoint(x: size / 2, y: size / 2)
            ctx.cgContext.drawRadialGradient(grad, startCenter: c, startRadius: 0, endCenter: c,
                                             endRadius: CGFloat(size) / 2, options: [])
        }
    }

    /// Sternenhimmel als Rundum-Panorama
    static let sky: UIImage = {
        var rng = SeededRNG("sky")
        let w: CGFloat = 2048, h: CGFloat = 1024
        return UIGraphicsImageRenderer(size: CGSize(width: w, height: h)).image { ctx in
            let g = ctx.cgContext
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
    }()

    /// Gasriese / Gesteinsplanet als Panoramatextur
    static func planet(_ p: Planet, seed: String) -> UIImage {
        var rng = SeededRNG(seed)
        let w: CGFloat = 512, h: CGFloat = 256
        return UIGraphicsImageRenderer(size: CGSize(width: w, height: h)).image { ctx in
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

    static func ring(hue: Double) -> UIImage {
        var rng = SeededRNG("ring\(Int(hue))")
        let s: CGFloat = 512
        return UIGraphicsImageRenderer(size: CGSize(width: s, height: s)).image { ctx in
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
        return UIGraphicsImageRenderer(size: CGSize(width: s, height: s)).image { ctx in
            UIColor(red: 0.42, green: 0.38, blue: 0.35, alpha: 1).setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: s, height: s))
            for _ in 0..<500 {
                let r = rng.c(2...16)
                UIColor(white: rng.chance(0.5) ? 0.75 : 0.1, alpha: rng.c(0.05...0.2)).setFill()
                UIBezierPath(ovalIn: CGRect(x: rng.c(0...s), y: rng.c(0...s), width: r, height: r)).fill()
            }
        }
    }()

    /// Hexagon-Plakette mit Symbol (Items und Ladering)
    static func badge(_ kind: ItemKind) -> UIImage {
        let s: CGFloat = 128
        let col = uic(kind.hue, 0.85, 0.62)
        return UIGraphicsImageRenderer(size: CGSize(width: s, height: s)).image { _ in
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
    private var releasing = false
    private var chasedThisFlight = false
    /// geglätteter Kurs für die Verfolgerkamera, damit Lenkkorrekturen nicht als Ruckler ankommen
    private var chaseHeading = SmoothAngle(0)
    private var lastPhase: Game.Phase = .orbiting

    private var generation = -1
    private var planetNodes: [Int: SCNNode] = [:]
    private struct BonusRing {
        let node: SCNNode
        let progress: SCNNode
        let color: UIColor
        let radius: CGFloat
        var step = -1
    }
    private var bonusRings: [Int: BonusRing] = [:]
    private var asteroidNodes: [Int: SCNNode] = [:]
    private var itemNodes: [Int: SCNNode] = [:]
    private var projectileNodes: [Int: SCNNode] = [:]
    private var cloudNodes: [Int: SCNNode] = [:]
    private var seenBeams = Set<Int>()
    private var seenWaves = Set<Int>()

    private let shipHolder = SCNNode()
    private let bankNode = SCNNode()
    private var shipModelNode: SCNNode?
    private var shipID = ""
    private let exhaust = SCNParticleSystem()
    private var exhausts: [(SCNParticleSystem, CGFloat)] = []
    private let trail = SCNParticleSystem()

    private let orbitGroup = SCNNode()
    private let orbitRing = SCNNode()
    private let arrowSpinner = SCNNode()
    private let coneNode = SCNNode()
    private var coneKey = ""
    private var coneMats: [SCNMaterial] = []
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
        scene.lightingEnvironment.contents = WorldTextures.sky
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
        for d in [planetNodes, asteroidNodes, itemNodes, projectileNodes, cloudNodes] {
            d.values.forEach { $0.removeFromParentNode() }
        }
        bonusRings.values.forEach { $0.node.removeFromParentNode() }
        planetNodes = [:]; asteroidNodes = [:]; itemNodes = [:]; projectileNodes = [:]; cloudNodes = [:]; bonusRings = [:]
        seenBeams = []; seenWaves = []
        orbitIndex = -1; lockIndex = -1; coneKey = ""
        arrivalIndex = -1; arrivalActive = false; arrival = 0
        trail.reset()
    }

    // MARK: Planeten

    private func makePlanet(_ p: Planet, index: Int) -> SCNNode {
        let root = SCNNode()
        root.position = v3(p.center)

        let tilt = SCNNode()
        tilt.eulerAngles = SCNVector3(Float(p.tilt) * 0.6, 0, Float(p.tilt))
        root.addChildNode(tilt)

        let sphere = SCNSphere(radius: p.radius)
        sphere.segmentCount = 64
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = WorldTextures.planet(p, seed: "planet\(index)")
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
            rm.lightingModel = .lambert
            rm.diffuse.contents = WorldTextures.ring(hue: p.hue)
            rm.isDoubleSided = true
            rm.writesToDepthBuffer = true
            rm.transparencyMode = .aOne
            let ring = flatShape(path, rm, depth: 0.5)
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

    /// Durchgehender Ladering: dunkler Grundring, darüber der wachsende Fortschrittsbogen
    private func makeBonusRing(_ p: Planet, kind: ItemKind) -> BonusRing {
        let root = SCNNode()
        root.position = v3(p.center)
        let rr = p.radius + 18
        let col = uic(kind.hue, 0.85, 0.6)
        let base = UIBezierPath(ovalIn: CGRect(x: -rr - 3, y: -rr - 3, width: (rr + 3) * 2, height: (rr + 3) * 2))
        base.append(UIBezierPath(ovalIn: CGRect(x: -rr + 3, y: -rr + 3, width: (rr - 3) * 2, height: (rr - 3) * 2)))
        base.usesEvenOddFillRule = true
        root.addChildNode(flatShape(base, glowMat(col.withAlphaComponent(0.22)), depth: 0.5))
        let progress = SCNNode()
        root.addChildNode(progress)
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
        return BonusRing(node: root, progress: progress, color: col, radius: rr)
    }

    private func updateProgress(_ r: inout BonusRing, fraction: CGFloat) {
        let step = Int(fraction * 120)
        guard step != r.step else { return }
        r.step = step
        r.progress.childNodes.forEach { $0.removeFromParentNode() }
        guard step > 0 else { return }
        let a0 = -CGFloat.pi / 2
        let a1 = a0 + .pi * 2 * CGFloat(step) / 120
        r.progress.addChildNode(flatShape(arcPath(radius: r.radius, width: 16, from: a0, to: a1),
                                          glowMat(r.color.withAlphaComponent(0.3)), depth: 0.4))
        r.progress.addChildNode(flatShape(arcPath(radius: r.radius, width: 6, from: a0, to: a1),
                                          glowMat(r.color), depth: 0.8))
    }

    // MARK: Bahn, Kegel, Zielerfassung

    private func rebuildOrbit(_ game: Game) {
        let p = game.planets[game.currentIndex]
        orbitRing.childNodes.forEach { $0.removeFromParentNode() }
        let ring = SCNTorus(ringRadius: p.orbitRadius, pipeRadius: 1.2)
        ring.ringSegmentCount = 96
        ring.materials = [glowMat(UIColor(red: 0.45, green: 0.75, blue: 1, alpha: 0.35))]
        orbitRing.addChildNode(SCNNode(geometry: ring))
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
        let grad = UIGraphicsImageRenderer(size: CGSize(width: 256, height: 8)).image { ctx in
            let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                               colors: [UIColor(white: 0.45, alpha: 1).cgColor, UIColor(white: 0, alpha: 1).cgColor] as CFArray,
                               locations: [0, 1])!
            ctx.cgContext.drawLinearGradient(g, start: .zero, end: CGPoint(x: 256, y: 0), options: [])
        }
        let fill = spriteMat(grad)
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
        lockArcs.childNodes.forEach { $0.removeFromParentNode() }
        lockTicks.childNodes.forEach { $0.removeFromParentNode() }
        lockHolo.childNodes.forEach { $0.removeFromParentNode() }
        lockGroup.childNodes.filter { $0.name == "bracket" }.forEach { $0.removeFromParentNode() }

        let holo = UIColor(red: 0.45, green: 0.85, blue: 1, alpha: 0.9)
        let amber = UIColor(red: 1, green: 0.78, blue: 0.4, alpha: 1)
        for k in 0..<3 {
            let a0 = CGFloat(k) * 2 * .pi / 3
            lockArcs.addChildNode(flatShape(arcPath(radius: p.radius + 30, width: 3, from: a0, to: a0 + 1.4), glowMat(holo), depth: 0.4))
        }
        let ticks = UIBezierPath()
        for k in 0..<36 {
            let a = CGFloat(k) / 36 * .pi * 2
            let t = UIBezierPath(rect: CGRect(x: p.radius + 44, y: -0.6, width: k % 3 == 0 ? 9 : 4, height: 1.2))
            t.apply(CGAffineTransform(rotationAngle: a))
            ticks.append(t)
        }
        lockTicks.addChildNode(flatShape(ticks, glowMat(holo.withAlphaComponent(0.5)), depth: 0.2))

        // Holo-Gitter um den Zielplaneten
        let grid = UIGraphicsImageRenderer(size: CGSize(width: 512, height: 256)).image { ctx in
            let g = ctx.cgContext
            g.setStrokeColor(UIColor(white: 1, alpha: 0.5).cgColor)
            g.setLineWidth(1.5)
            for k in 0...16 { let x = CGFloat(k) * 32; g.move(to: CGPoint(x: x, y: 0)); g.addLine(to: CGPoint(x: x, y: 256)) }
            for k in 0...8 { let y = CGFloat(k) * 32; g.move(to: CGPoint(x: 0, y: y)); g.addLine(to: CGPoint(x: 512, y: y)) }
            g.strokePath()
        }
        let hm = spriteMat(grid)
        hm.multiply.contents = holo.withAlphaComponent(0.35)
        let sphere = SCNSphere(radius: p.radius * 1.03)
        sphere.segmentCount = 48
        sphere.materials = [hm]
        lockHolo.addChildNode(SCNNode(geometry: sphere))

        // Klammern
        let h = p.radius + 62
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
        }
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
        let img = UIGraphicsImageRenderer(size: CGSize(width: 256, height: 256)).image { ctx in
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
        let hull = ShipDesigns.build(ShipModel.all[a.variant % ShipModel.all.count])
        let s = a.radius / 3.2
        hull.scale = SCNVector3(Float(s), Float(s), Float(s))
        hull.eulerAngles = SCNVector3(Float(a.phase), Float(a.phase * 1.7), 0.5)
        hull.runAction(.repeatForever(.rotate(by: .pi * 2, around: SCNVector3(0.3, 1, 0.2), duration: 22)))
        root.addChildNode(hull)
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

    private func spawnBeam(_ b: Beam, px: CGFloat) {
        let dx = b.to.x - b.from.x, dy = b.to.y - b.from.y
        let len = hypot(dx, dy)
        let col = uic(WorldTextures.railHue, 0.9, 0.65)
        let root = SCNNode()
        root.position = v3(CGPoint(x: (b.from.x + b.to.x) / 2, y: (b.from.y + b.to.y) / 2))
        root.eulerAngles.y = Float(-atan2(dy, dx))
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

        // Kamera-Mischung: Verfolgerkamera, wenn Asteroiden vor dem Schiff liegen
        // Entscheidung fällt einmal beim Start eines Flugs: Hindernisse auf der Strecke und Weg lang genug?
        // Danach bleibt die Kamera dran, bis der Zielplanet nah ist, und schaltet im selben Flug nicht wieder ein.
        let ti = min(game.originIndex + 1, game.planets.count - 1)
        let tgt = game.planets[ti]
        let distT = hypot(tgt.center.x - game.pos.x, tgt.center.y - game.pos.y)
        let release = tgt.orbitRadius + 1300
        if game.phase == .flying && lastPhase != .flying { chasedThisFlight = false }
        // Hindernisse in einem breiten Korridor um die Strecke, auch etwas neben der Flugbahn
        if game.phase == .flying && !chasedThisFlight && distT > release + 150 {
            let lx = (tgt.center.x - game.pos.x) / max(1, distT), ly = (tgt.center.y - game.pos.y) / max(1, distT)
            let near = game.asteroids.contains { a in
                let rx = a.center.x - game.pos.x, ry = a.center.y - game.pos.y
                let along = rx * lx + ry * ly
                let side = abs(rx * ly - ry * lx)
                return along > -100 && along < distT && side < 750
            }
            if near {
                chaseOn = true
                chasedThisFlight = true
            }
        }
        if game.phase != .flying || distT < release { chaseOn = false }
        lastPhase = game.phase
        let danger = chaseOn
        let want: CGFloat = danger ? 1 : 0
        // rein zügig, raus langsam und weich
        releasing = !danger && chase > 0.001
        chase = smoothApproach(chase, want, rate: danger ? 1.4 : 0.45, dt: dt)
        // Solange die Verfolgerkamera aus ist, liegt der Kurs direkt an; danach folgt er mit kurzer Verzögerung
        if chase < 0.001 {
            chaseHeading.snap(to: game.heading)
        } else {
            chaseHeading.update(to: game.heading, smoothTime: 0.18, dt: dt)
        }
        updateArrival(game, dt: dt, ti: ti, distT: distT, tgt: tgt, release: release)
        let k = chase * chase * (3 - 2 * chase)
        let ka = arrival * arrival * (3 - 2 * arrival)

        // Bildschirm-konstante Größe (Welt-Einheiten pro Punkt)
        let fovRad = CGFloat(50) * .pi / 180
        let topDist = (size.height / max(0.02, game.camScale) / 2) / tan(fovRad / 2)
        let chaseDist: CGFloat = 230
        let dist = topDist + (chaseDist - topDist) * k
        let normalPx = 2 * dist * tan(fovRad / 2) / size.height
        let px = normalPx + (parkedPx - normalPx) * ka
        lastPx = px

        syncPlanets(game, px: px)
        syncOrbit(game, px: px)
        syncShip(game, px: normalPx, k: k, ka: ka)
        syncObjects(game, px: px)
        syncCamera(game, k: k, topDist: topDist, ka: ka)

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
            let n = makePlanet(game.planets[i], index: i + game.generation * 1000)
            scene.rootNode.addChildNode(n)
            planetNodes[i] = n
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
                bonusRings[i] = r
            }
            guard var r = bonusRings[i] else { continue }
            let isCur = i == game.currentIndex && game.phase != .over
            let frac = isCur ? min(1, game.orbitCharge / game.chargeNeeded) : 0
            updateProgress(&r, fraction: frac)
            bonusRings[i] = r
            if let badge = r.node.childNode(withName: "badge", recursively: false) {
                let s = Float(24 * px * (isCur ? 1 + 0.08 * sin(game.time * 6) : 1))
                badge.scale = SCNVector3(s, s, s)
            }
        }

        // Zielerfassung
        lockGroup.isHidden = game.phase == .over
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

    private func syncOrbit(_ game: Game, px: CGFloat) {
        orbitGroup.isHidden = game.phase == .flying || game.phase == .over
        guard !orbitGroup.isHidden else { return }
        let p = game.planets[game.currentIndex]
        if orbitIndex != game.currentIndex {
            orbitIndex = game.currentIndex
            rebuildOrbit(game)
        }
        orbitGroup.position = v3(p.center)
        arrowSpinner.eulerAngles.y = Float(-game.orbitDir * game.time * 0.5)
        arrowSpinner.childNodes.forEach { $0.childNodes.first?.eulerAngles.x = Float(game.orbitDir > 0 ? Float.pi / 2 : -Float.pi / 2) }

        let key = "\(game.currentIndex)-\(Int(game.coneHalfAngle * 1000))"
        if key != coneKey {
            coneKey = key
            rebuildCone(game)
        }
        let apex = point(from: p.center, angle: game.coneApexAngle, distance: p.orbitRadius)
        coneNode.position = SCNVector3(Float(apex.x - p.center.x), 0, Float(apex.y - p.center.y))
        coneNode.eulerAngles.y = Float(-game.coneDirection)
        let hot = game.inCone
        let tint = hot ? UIColor(red: 0.25, green: 0.75, blue: 0.62, alpha: 1) : UIColor(white: 0.55, alpha: 1)
        coneMats.forEach { $0.multiply.contents = tint }
    }

    private func syncShip(_ game: Game, px: CGFloat, k: CGFloat, ka: CGFloat) {
        if shipID != game.ship.model.id {
            shipID = game.ship.model.id
            shipModelNode?.removeFromParentNode()
            let n = Ship3D.shipNode(for: game.ship.model, showcase: false)
            bankNode.addChildNode(n)
            shipModelNode = n

        }
        shipHolder.isHidden = game.phase == .over
        shipHolder.position = v3(game.pos, 4)
        // leichte Schräglage in Kurven
        let bank: CGFloat = game.phase == .orbiting ? -game.orbitDir * 0.35 : 0
        shipHolder.eulerAngles.y = Float(-game.heading)
        bankNode.eulerAngles.x = Float(bank)
        // bildschirmfest, aber nie zu groß im Vergleich zu den Planeten
        let topScale = min(8.4 * px, 14)
        var sc = topScale + (5.0 - topScale) * k
        sc += (parkedScale - sc) * ka
        lastShipScale = sc
        let s = Float(sc)
        shipHolder.scale = SCNVector3(s, s, s)

        let flying = game.phase == .flying
        let boost = game.boostTime > 0
        for (ps, r) in exhausts {
            ps.birthRate = game.phase == .over ? 0 : (flying ? (boost ? 260 : 120) : 35)
            ps.particleVelocity = CGFloat(s) * (flying ? (boost ? 6 : 3) : 1.5)
            ps.particleSize = CGFloat(s) * r * (boost ? 1.7 : 1.25)
        }
        trail.birthRate = flying ? 90 : (game.phase == .orbiting ? 40 : 0)
        trail.particleSize = CGFloat(s) * 0.22
    }

    private func syncObjects(_ game: Game, px: CGFloat) {
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
            } else {
                let n = makeObstacle(a)
                scene.rootNode.addChildNode(n)
                asteroidNodes[a.uid] = n
            }
        }
        for (id, n) in asteroidNodes where !alive.contains(id) {
            n.removeFromParentNode()
            asteroidNodes[id] = nil
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
    private let arrivalBlendTime: CGFloat = 1.3
    private var parkedPos = SCNVector3(0, 0, 0)
    private var parkedLook = SCNVector3(0, 0, 0)
    private var parkedScale: CGFloat = 1
    private var parkedPx: CGFloat = 1
    private var parkedFov: CGFloat = 50
    private var lastShipScale: CGFloat = 1
    private var lastPx: CGFloat = 1
    private var lastLook = SCNVector3(0, 0, 0)

    /// Vor jedem Planeten bleibt die Kamera hinter dem Schiff stehen und lässt es in den Orbit fliegen.
    /// Nach dem Einfangen hält sie kurz und wechselt dann langsam in die Draufsicht.
    private func updateArrival(_ game: Game, dt: CGFloat, ti: Int, distT: CGFloat, tgt: Planet, release: CGFloat) {
        if game.phase == .over {
            arrivalActive = false
            arrival = 0
            return
        }
        // Kamera hält genau dort an, wo sie gerade ist: kein eigener Kameraschwenk
        // nur aus der Nahansicht (Verfolgerkamera), nie in der Draufsicht
        if game.phase == .flying && arrivalIndex != ti && distT < release && chase > 0.5 {
            arrivalIndex = ti
            arrivalActive = true
            // kurz stehen bleiben, dann in die Draufsicht
            arrivalHold = game.time + 0.9
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
            && (game.phase == .orbiting || distT < tgt.orbitRadius + 450) {
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

    private func syncCamera(_ game: Game, k: CGFloat, topDist: CGFloat, ka: CGFloat) {
        // Draufsicht, leicht gekippt
        let tilt: CGFloat = 0.42
        let target = v3(game.cam)
        let topPos = SCNVector3(target.x, Float(topDist * cos(tilt)), target.z + Float(topDist * sin(tilt)))

        // hinter und über dem Schiff
        let hd = chaseHeading.value
        let ship = game.pos
        let chasePos = SCNVector3(Float(ship.x - cos(hd) * 190), 95, Float(ship.y - sin(hd) * 190))
        let chaseLook = SCNVector3(Float(ship.x + cos(hd) * 260), 0, Float(ship.y + sin(hd) * 260))

        func mix(_ a: SCNVector3, _ b: SCNVector3) -> SCNVector3 {
            let f = Float(k)
            return SCNVector3(a.x + (b.x - a.x) * f, a.y + (b.y - a.y) * f, a.z + (b.z - a.z) * f)
        }
        var pos = mix(topPos, chasePos)
        let look = mix(target, chaseLook)
        // Beim Herauszoomen gleitet die Kamera zugleich nach vorn, statt nach hinten wegzufahren
        if releasing {
            let bump = Float(sin(k * .pi) * topDist * 0.15)
            pos.x += Float(cos(hd)) * bump
            pos.z += Float(sin(hd)) * bump
        }
        if game.shake > 0 {
            let amp = Float(game.shake) * pos.y * 0.012
            pos.x += Float.random(in: -amp...amp)
            pos.z += Float.random(in: -amp...amp)
        }
        // Anflug-Einstellung einblenden
        let fa = Float(ka)
        pos = SCNVector3(pos.x + (parkedPos.x - pos.x) * fa, pos.y + (parkedPos.y - pos.y) * fa, pos.z + (parkedPos.z - pos.z) * fa)
        // Der Blick wendet sich in der ersten Hälfte des Übergangs dem Planeten zu,
        // die Position fährt danach noch zu Ende. So ist früh der Planet im Fokus, nicht das Schiff.
        let al = min(1, max(0, (arrival - 0.45) / 0.55))
        let fl = Float(al * al * (3 - 2 * al))
        let lookA = SCNVector3(look.x + (parkedLook.x - look.x) * fl, look.y + (parkedLook.y - look.y) * fl, look.z + (parkedLook.z - look.z) * fl)
        cameraNode.position = pos
        cameraNode.look(at: lookA, up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 0, -1))
        lastLook = lookA
        let normalFov = 50 + 12 * k
        cameraNode.camera?.fieldOfView = normalFov + (parkedFov - normalFov) * ka
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
}

// MARK: - SwiftUI-Hülle

struct WorldView: UIViewRepresentable {
    let world: World3D

    func makeUIView(context: Context) -> SCNView {
        let v = SCNView()
        v.scene = world.scene
        v.pointOfView = world.cameraNode
        v.backgroundColor = .black
        v.antialiasingMode = .multisampling4X
        v.isPlaying = true
        v.rendersContinuously = true
        v.preferredFramesPerSecond = 60
        world.view = v
        return v
    }

    func updateUIView(_ v: SCNView, context: Context) {}
}
