import SwiftUI
import SceneKit
import Metal
import UIKit

// MARK: - Reproduzierbarer Zufall

struct SeededRNG: RandomNumberGenerator {
    var state: UInt64

    init(_ text: String) {
        var h: UInt64 = 1469598103934665603
        for b in text.utf8 { h = (h ^ UInt64(b)) &* 1099511628211 }
        state = h
    }

    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        var z = state
        z = (z ^ (z >> 30)) &* 0xbf58476d1ce4e5b9
        z = (z ^ (z >> 27)) &* 0x94d049bb133111eb
        return z ^ (z >> 31)
    }

    mutating func d(_ r: ClosedRange<Double>) -> Double { Double.random(in: r, using: &self) }
    mutating func c(_ r: ClosedRange<CGFloat>) -> CGFloat { CGFloat.random(in: r, using: &self) }
    mutating func chance(_ p: Double) -> Bool { d(0...1) < p }
}

// MARK: - Prozedurale Rumpf-Texturen

struct HullTextures {
    let albedo: UIImage
    let normal: UIImage
    let roughness: UIImage
    let emission: UIImage

    private struct Panel {
        let rect: CGRect
        let shade: Double
        let kind: Int          // 0 normal, 1 dunkel, 2 Warnstreifen, 3 Gitter, 4 Fenster
        let rough: Double
        let height: Double
        let rivets: Bool
    }

    static func make(for m: ShipModel, paint: (Double, Double, Double)) -> HullTextures {
        var rng = SeededRNG(m.id)
        let size: CGFloat = 1024

        // Panels durch rekursives Teilen
        var leaves: [CGRect] = []
        func split(_ r: CGRect, _ depth: Int) {
            if depth > 5 || (r.width < 110 && r.height < 110) || (depth > 2 && rng.chance(0.18)) {
                leaves.append(r)
                return
            }
            if r.width > r.height {
                let t = rng.c(0.3...0.7)
                split(CGRect(x: r.minX, y: r.minY, width: r.width * t, height: r.height), depth + 1)
                split(CGRect(x: r.minX + r.width * t, y: r.minY, width: r.width * (1 - t), height: r.height), depth + 1)
            } else {
                let t = rng.c(0.3...0.7)
                split(CGRect(x: r.minX, y: r.minY, width: r.width, height: r.height * t), depth + 1)
                split(CGRect(x: r.minX, y: r.minY + r.height * t, width: r.width, height: r.height * (1 - t)), depth + 1)
            }
        }
        split(CGRect(x: 0, y: 0, width: size, height: size), 0)

        let panels: [Panel] = leaves.map { r in
            let roll = rng.d(0...1)
            let kind: Int
            if roll < 0.05 { kind = 2 } else if roll < 0.13 { kind = 3 } else if roll < 0.2 { kind = 4 } else if roll < 0.34 { kind = 1 } else { kind = 0 }
            return Panel(rect: r, shade: rng.d(-0.06...0.06), kind: kind, rough: rng.d(0.25...0.6),
                         height: rng.d(0.42...0.58), rivets: rng.chance(0.45))
        }

        let (h, s, l) = paint
        let accent = UIColor(hsl(m.weapon.hue, 0.85, 0.58))

        // Albedo
        let albedo = UIGraphicsImageRenderer(size: CGSize(width: size, height: size)).image { ctx in
            let g = ctx.cgContext
            for p in panels {
                let col: UIColor
                switch p.kind {
                case 1: col = UIColor(hsl(h, s, max(0.1, l - 0.2 + p.shade)))
                case 3: col = UIColor(hsl(h, s * 0.5, max(0.08, l - 0.35)))
                default: col = UIColor(hsl(h, s, min(0.95, l + p.shade)))
                }
                g.setFillColor(col.cgColor)
                g.fill(p.rect)

                if p.kind == 2 {
                    g.saveGState()
                    g.clip(to: p.rect.insetBy(dx: 6, dy: 6))
                    g.setFillColor(UIColor(red: 0.95, green: 0.75, blue: 0.15, alpha: 1).cgColor)
                    g.fill(p.rect)
                    g.setFillColor(UIColor(white: 0.08, alpha: 1).cgColor)
                    var x = p.rect.minX - p.rect.height
                    while x < p.rect.maxX {
                        g.beginPath()
                        g.move(to: CGPoint(x: x, y: p.rect.maxY))
                        g.addLine(to: CGPoint(x: x + 22, y: p.rect.maxY))
                        g.addLine(to: CGPoint(x: x + 22 + p.rect.height, y: p.rect.minY))
                        g.addLine(to: CGPoint(x: x + p.rect.height, y: p.rect.minY))
                        g.closePath()
                        g.fillPath()
                        x += 44
                    }
                    g.restoreGState()
                }
                if p.kind == 3 {
                    g.setStrokeColor(UIColor(white: 0, alpha: 0.6).cgColor)
                    g.setLineWidth(3)
                    var y = p.rect.minY + 8
                    while y < p.rect.maxY - 6 {
                        g.move(to: CGPoint(x: p.rect.minX + 8, y: y))
                        g.addLine(to: CGPoint(x: p.rect.maxX - 8, y: y))
                        y += 9
                    }
                    g.strokePath()
                }
                // Fase: helle Oberkante, dunkle Unterkante
                g.setStrokeColor(UIColor(white: 1, alpha: 0.12).cgColor)
                g.setLineWidth(2)
                g.stroke(p.rect.insetBy(dx: 3, dy: 3))
                // Naht
                g.setStrokeColor(UIColor(white: 0, alpha: 0.55).cgColor)
                g.setLineWidth(3)
                g.stroke(p.rect)
                if p.rivets {
                    g.setFillColor(UIColor(white: 0, alpha: 0.4).cgColor)
                    var x = p.rect.minX + 10
                    while x < p.rect.maxX - 6 {
                        g.fillEllipse(in: CGRect(x: x - 2.5, y: p.rect.minY + 8, width: 5, height: 5))
                        g.fillEllipse(in: CGRect(x: x - 2.5, y: p.rect.maxY - 13, width: 5, height: 5))
                        x += 18
                    }
                }
            }
            // Akzentstreifen und Markierungen
            g.setFillColor(accent.withAlphaComponent(0.85).cgColor)
            g.fill(CGRect(x: 0, y: size * 0.47, width: size, height: 10))
            g.fill(CGRect(x: 0, y: size * 0.53 - 10, width: size, height: 4))
            for k in 0..<4 {
                let x = size * 0.18 + CGFloat(k) * 26
                g.beginPath()
                g.move(to: CGPoint(x: x, y: size * 0.36))
                g.addLine(to: CGPoint(x: x + 14, y: size * 0.36))
                g.addLine(to: CGPoint(x: x + 28, y: size * 0.4))
                g.addLine(to: CGPoint(x: x + 14, y: size * 0.44))
                g.addLine(to: CGPoint(x: x, y: size * 0.44))
                g.addLine(to: CGPoint(x: x + 14, y: size * 0.4))
                g.closePath()
                g.fillPath()
            }
            // Kennung
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedSystemFont(ofSize: 54, weight: .heavy),
                .foregroundColor: UIColor(white: l > 0.55 ? 0.12 : 0.92, alpha: 0.75),
                .kern: 6
            ]
            (m.name as NSString).draw(at: CGPoint(x: size * 0.42, y: size * 0.57), withAttributes: attrs)
            let small: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedSystemFont(ofSize: 22, weight: .bold),
                .foregroundColor: UIColor(white: l > 0.55 ? 0.15 : 0.85, alpha: 0.6),
                .kern: 3
            ]
            ("OH-\(Int(rng.d(100...999))) // ORBITAL FLEET" as NSString).draw(at: CGPoint(x: size * 0.42, y: size * 0.64), withAttributes: small)
            // Gebrauchsspuren
            for _ in 0..<160 {
                let r = rng.c(10...90)
                let rect = CGRect(x: rng.c(0...size), y: rng.c(0...size), width: r * rng.c(1...3), height: r)
                g.setFillColor(UIColor(white: 0, alpha: rng.c(0.02...0.06)).cgColor)
                g.fillEllipse(in: rect)
            }
            g.setStrokeColor(UIColor(white: 0, alpha: 0.05).cgColor)
            g.setLineWidth(2)
            for _ in 0..<70 {
                let x = rng.c(0...size)
                let y = rng.c(0...size)
                g.move(to: CGPoint(x: x, y: y))
                g.addLine(to: CGPoint(x: x - rng.c(30...160), y: y + rng.c(-4...4)))
            }
            g.strokePath()
        }

        // Höhenkarte → Normal-Map
        let hs = 512
        let scale = CGFloat(hs) / size
        let heightImg = UIGraphicsImageRenderer(size: CGSize(width: hs, height: hs)).image { ctx in
            let g = ctx.cgContext
            g.scaleBy(x: scale, y: scale)
            for p in panels {
                g.setFillColor(UIColor(white: p.height, alpha: 1).cgColor)
                g.fill(p.rect)
                if p.kind == 3 {
                    g.setStrokeColor(UIColor(white: 0.2, alpha: 1).cgColor)
                    g.setLineWidth(4)
                    var y = p.rect.minY + 8
                    while y < p.rect.maxY - 6 {
                        g.move(to: CGPoint(x: p.rect.minX + 8, y: y))
                        g.addLine(to: CGPoint(x: p.rect.maxX - 8, y: y))
                        y += 9
                    }
                    g.strokePath()
                }
                g.setStrokeColor(UIColor(white: 0.05, alpha: 1).cgColor)
                g.setLineWidth(6)
                g.stroke(p.rect)
                if p.rivets {
                    g.setFillColor(UIColor(white: 0.95, alpha: 1).cgColor)
                    var x = p.rect.minX + 10
                    while x < p.rect.maxX - 6 {
                        g.fillEllipse(in: CGRect(x: x - 3, y: p.rect.minY + 7, width: 6, height: 6))
                        g.fillEllipse(in: CGRect(x: x - 3, y: p.rect.maxY - 13, width: 6, height: 6))
                        x += 18
                    }
                }
            }
        }
        let normal = normalMap(from: heightImg, size: hs, strength: 3.0)

        let roughness = UIGraphicsImageRenderer(size: CGSize(width: hs, height: hs)).image { ctx in
            let g = ctx.cgContext
            g.scaleBy(x: scale, y: scale)
            for p in panels {
                g.setFillColor(UIColor(white: p.kind == 3 ? 0.8 : p.rough, alpha: 1).cgColor)
                g.fill(p.rect)
            }
        }

        let emission = UIGraphicsImageRenderer(size: CGSize(width: hs, height: hs)).image { ctx in
            let g = ctx.cgContext
            g.setFillColor(UIColor.black.cgColor)
            g.fill(CGRect(x: 0, y: 0, width: hs, height: hs))
            g.scaleBy(x: scale, y: scale)
            for p in panels where p.kind == 4 {
                let warm = p.shade > 0
                g.setFillColor((warm ? UIColor(red: 1, green: 0.85, blue: 0.55, alpha: 1)
                                     : UIColor(red: 0.5, green: 0.95, blue: 1, alpha: 1)).cgColor)
                var x = p.rect.minX + 12
                while x < p.rect.maxX - 18 {
                    g.fill(CGRect(x: x, y: p.rect.midY - 5, width: 10, height: 10))
                    x += 22
                }
            }
            g.setFillColor(accent.cgColor)
            g.fill(CGRect(x: 0, y: size * 0.47, width: size, height: 10))
        }

        return HullTextures(albedo: albedo, normal: normal, roughness: roughness, emission: emission)
    }

    private static func normalMap(from img: UIImage, size: Int, strength: Double) -> UIImage {
        guard let cg = img.cgImage else { return img }
        var gray = [UInt8](repeating: 0, count: size * size)
        let gctx = CGContext(data: &gray, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size,
                             space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
        gctx.draw(cg, in: CGRect(x: 0, y: 0, width: size, height: size))

        var out = [UInt8](repeating: 255, count: size * size * 4)
        func hgt(_ x: Int, _ y: Int) -> Double {
            Double(gray[min(size - 1, max(0, y)) * size + min(size - 1, max(0, x))]) / 255
        }
        for y in 0..<size {
            for x in 0..<size {
                let dx = (hgt(x + 1, y) - hgt(x - 1, y)) * strength
                let dy = (hgt(x, y + 1) - hgt(x, y - 1)) * strength
                let len = (dx * dx + dy * dy + 1).squareRoot()
                let i = (y * size + x) * 4
                out[i] = UInt8(max(0, min(255, (-dx / len * 0.5 + 0.5) * 255)))
                out[i + 1] = UInt8(max(0, min(255, (dy / len * 0.5 + 0.5) * 255)))
                out[i + 2] = UInt8(max(0, min(255, (1 / len * 0.5 + 0.5) * 255)))
            }
        }
        let provider = CGDataProvider(data: Data(out) as CFData)!
        let image = CGImage(width: size, height: size, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: size * 4,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                            provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)!
        return UIImage(cgImage: image)
    }
}

// MARK: - 3D-Modell

enum Ship3D {
    private static var sceneCache: [String: SCNScene] = [:]
    private static var spriteCache: [String: UIImage] = [:]
    private static var textureCache: [String: HullTextures] = [:]
    private static var renderer: SCNRenderer? = {
        guard let device = MTLCreateSystemDefaultDevice() else { return nil }
        return SCNRenderer(device: device, options: nil)
    }()

    /// Ausschnitt des Sprites in Modell-Einheiten (Breite = Höhe)
    static let spriteSpan: CGFloat = 9

    static func scene(for m: ShipModel) -> SCNScene {
        if let s = sceneCache[m.id] { return s }
        let s = build(m, showcase: true)
        sceneCache[m.id] = s
        return s
    }

    /// Draufsicht des Modells für das Spiel, Nase zeigt nach rechts.
    static func sprite(for m: ShipModel) -> UIImage? {
        if let img = spriteCache[m.id] { return img }
        guard let r = renderer else { return nil }
        let scene = build(m, showcase: false)
        r.scene = scene
        r.pointOfView = scene.rootNode.childNode(withName: "camera", recursively: false)
        let img = r.snapshot(atTime: 0, with: CGSize(width: 384, height: 384), antialiasingMode: .multisampling4X)
        spriteCache[m.id] = img
        return img
    }

    /// Nur für die Entwicklung (Startargument `-renderShips`): rendert jedes Schiff der Auswahl aus zwei
    /// Blickwinkeln als PNG in den Dokumente-Ordner der App, damit man die Modelle ohne Tippen vergleichen kann.
    static func renderGallery() {
        guard let r = renderer,
              let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        for m in ShipModel.all {
            let scene = build(m, showcase: true)
            scene.background.contents = UIColor(white: 0.13, alpha: 1)
            guard let pivot = scene.rootNode.childNode(withName: "pivot", recursively: false),
                  let cam = scene.rootNode.childNode(withName: "camera", recursively: false) else { continue }
            pivot.removeAllActions()
            r.scene = scene
            r.pointOfView = cam
            for (i, angle) in [0.7, Double.pi - 0.7].enumerated() {
                pivot.eulerAngles.y = Float(angle)
                let img = r.snapshot(atTime: 0, with: CGSize(width: 1024, height: 768), antialiasingMode: .multisampling4X)
                try? img.pngData()?.write(to: dir.appendingPathComponent("ship-\(m.id)-\(i).png"))
            }
        }
        print("OHRENDER done \(dir.path)")
    }

    private static func textures(for m: ShipModel) -> HullTextures {
        if let t = textureCache[m.id] { return t }
        let t = HullTextures.make(for: m, paint: m.hull.paint)
        textureCache[m.id] = t
        return t
    }

    private static func ui(_ h: Double, _ s: Double, _ l: Double) -> UIColor { UIColor(hsl(h, s, l)) }

    private static func pbr(_ color: UIColor, metal: CGFloat = 0.6, rough: CGFloat = 0.35) -> SCNMaterial {
        let mat = SCNMaterial()
        mat.lightingModel = .physicallyBased
        mat.diffuse.contents = color
        mat.metalness.contents = metal
        mat.roughness.contents = rough
        return mat
    }

    private static func glow(_ color: UIColor) -> SCNMaterial {
        let mat = SCNMaterial()
        mat.lightingModel = .constant
        mat.diffuse.contents = color
        mat.emission.contents = color
        return mat
    }

    private static func node(_ g: SCNGeometry, _ mat: SCNMaterial, _ p: SCNVector3) -> SCNNode {
        g.materials = [mat]
        let n = SCNNode(geometry: g)
        n.position = p
        return n
    }

    /// Zylinder oder Kapsel entlang der x-Achse
    private static func alongX(_ g: SCNGeometry, _ mat: SCNMaterial, _ p: SCNVector3) -> SCNNode {
        let n = node(g, mat, p)
        n.eulerAngles.z = -.pi / 2
        return n
    }

    private static func blink(_ n: SCNNode, period: Double, offset: Double) {
        n.opacity = 0.15
        n.runAction(.sequence([.wait(duration: offset),
                               .repeatForever(.sequence([.fadeOpacity(to: 1, duration: 0.05),
                                                         .wait(duration: 0.12),
                                                         .fadeOpacity(to: 0.15, duration: 0.2),
                                                         .wait(duration: period)]))]))
    }

    private static func dotImage() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 32, height: 32)).image { ctx in
            let colors = [UIColor.white.cgColor, UIColor.white.withAlphaComponent(0).cgColor] as CFArray
            let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
            ctx.cgContext.drawRadialGradient(grad, startCenter: CGPoint(x: 16, y: 16), startRadius: 0,
                                             endCenter: CGPoint(x: 16, y: 16), endRadius: 16, options: [])
        }
    }

    /// Studio-Umgebung für Spiegelungen: dunkler Raum mit großen Softboxen, die Kanten auf Metall
    /// und Lack aufblitzen lassen (äquirektangulär, oben = Himmel)
    private static let environment: UIImage = UIGraphicsImageRenderer(size: CGSize(width: 1024, height: 512)).image { ctx in
        let g = ctx.cgContext
        let colors = [UIColor(red: 0.15, green: 0.145, blue: 0.14, alpha: 1).cgColor,
                      UIColor(red: 0.05, green: 0.05, blue: 0.05, alpha: 1).cgColor,
                      UIColor(red: 0.02, green: 0.02, blue: 0.02, alpha: 1).cgColor] as CFArray
        let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.55, 1])!
        g.drawLinearGradient(grad, start: .zero, end: CGPoint(x: 0, y: 512), options: [])
        // Softboxen: breite Streifen oben und seitlich
        func box(_ r: CGRect, _ c: UIColor) {
            g.setFillColor(c.cgColor)
            g.fill(r)
        }
        box(CGRect(x: 180, y: 40, width: 260, height: 70), UIColor(white: 1, alpha: 1))
        box(CGRect(x: 640, y: 120, width: 60, height: 200), UIColor(red: 0.92, green: 0.92, blue: 0.9, alpha: 1))
        box(CGRect(x: 900, y: 150, width: 90, height: 120), UIColor(red: 1, green: 0.85, blue: 0.7, alpha: 0.8))
        box(CGRect(x: 0, y: 236, width: 1024, height: 4), UIColor(white: 0.5, alpha: 1))
    }

    private static func scaledPath(_ hull: HullClass, sx: CGFloat, sy: CGFloat, dx: CGFloat) -> CGPath {
        var t = CGAffineTransform(translationX: dx, y: 0).scaledBy(x: sx, y: sy)
        return ShipArt.hullPath(hull, 1).cgPath.copy(using: &t) ?? ShipArt.hullPath(hull, 1).cgPath
    }

    private static func extrude(_ path: CGPath, depth: CGFloat, chamfer: CGFloat, mat: SCNMaterial, y: Float) -> SCNNode {
        let shape = SCNShape(path: UIBezierPath(cgPath: path), extrusionDepth: depth)
        shape.chamferRadius = chamfer
        shape.chamferMode = .both
        shape.materials = [mat]
        let n = SCNNode(geometry: shape)
        n.eulerAngles.x = -.pi / 2
        n.position.y = y
        return n
    }

    /// Fürs Spiel: alle Bauteile zu wenigen Zeichenaufrufen (einer je Material) verschmelzen,
    /// die Düsen-Marker bleiben als eigene Knoten erhalten.
    static func simplified(_ ship: SCNNode) -> SCNNode {
        let markers = outlets(of: ship).map { $0.0 }
        markers.forEach { $0.removeFromParentNode() }
        let flat = ship.flattenedClone()
        markers.forEach { flat.addChildNode($0) }
        return flat
    }

    /// Düsen-Austritte eines Modells mit Radius
    static func outlets(of node: SCNNode) -> [(SCNNode, CGFloat)] {
        node.childNodes.compactMap { n in
            guard let name = n.name, name.hasPrefix("outlet:"), let r = Double(name.dropFirst(7)) else { return nil }
            return (n, CGFloat(r))
        }
    }

    /// Das Schiffsmodell ohne Licht und Kamera, Nase zeigt nach +x.
    static func shipNode(for m: ShipModel, showcase: Bool) -> SCNNode {
        let n = showcase ? ShipDesigns.build(m) : simplified(ShipDesigns.build(m))
        for (o, r) in outlets(of: n) {
            // Glut hinter der Düse
            let halo = SCNNode(geometry: SCNPlane(width: r * 2.4, height: r * 2.4))
            let hm = SCNMaterial()
            hm.lightingModel = .constant
            hm.diffuse.contents = dotImage()
            hm.multiply.contents = UIColor(red: 1, green: 0.5, blue: 0.15, alpha: 1)
            hm.blendMode = .add
            hm.writesToDepthBuffer = false
            halo.geometry?.materials = [hm]
            halo.constraints = [SCNBillboardConstraint()]
            o.addChildNode(halo)
        }
        return n
    }

    private static func build(_ m: ShipModel, showcase: Bool) -> SCNScene {
        let scene = SCNScene()
        scene.background.contents = UIColor.clear
        scene.lightingEnvironment.contents = environment
        scene.lightingEnvironment.intensity = showcase ? 0.9 : 1.6

        let accent = ui(m.weapon.hue, 0.85, 0.6)
        let pivot = shipNode(for: m, showcase: showcase)
        pivot.name = "pivot"
        scene.rootNode.addChildNode(pivot)

        // Licht
        let key = SCNNode()
        key.light = SCNLight()
        key.light?.type = .directional
        key.light?.intensity = showcase ? 1500 : 1100
        key.light?.color = UIColor(red: 1, green: 0.95, blue: 0.88, alpha: 1)
        if showcase {
            // weiche Schatten geben den Bauteilen Tiefe
            key.light?.castsShadow = true
            key.light?.shadowMode = .deferred
            key.light?.shadowMapSize = CGSize(width: 2048, height: 2048)
            key.light?.shadowSampleCount = 16
            key.light?.shadowRadius = 2.5
            key.light?.shadowColor = UIColor(white: 0, alpha: 0.75)
            key.light?.orthographicScale = 6
            key.light?.zNear = 1
            key.light?.zFar = 40
        }
        key.eulerAngles = showcase ? SCNVector3(-Float.pi / 3, Float.pi / 5, 0) : SCNVector3(-Float.pi / 2.4, Float.pi / 6, 0)
        scene.rootNode.addChildNode(key)
        let rim = SCNNode()
        rim.light = SCNLight()
        rim.light?.type = .directional
        rim.light?.intensity = showcase ? 1000 : 600
        rim.light?.color = showcase ? UIColor(red: 0.9, green: 0.92, blue: 1, alpha: 1) : UIColor(red: 0.6, green: 0.75, blue: 1, alpha: 1)
        rim.eulerAngles = SCNVector3(-Float.pi / 6, Float.pi, 0)
        scene.rootNode.addChildNode(rim)
        let amb = SCNNode()
        amb.light = SCNLight()
        amb.light?.type = .ambient
        amb.light?.intensity = showcase ? 70 : 250
        amb.light?.color = showcase ? UIColor(red: 0.85, green: 0.83, blue: 0.8, alpha: 1) : UIColor(red: 0.6, green: 0.7, blue: 0.9, alpha: 1)
        scene.rootNode.addChildNode(amb)

        let cam = SCNNode()
        cam.camera = SCNCamera()
        cam.name = "camera"
        if showcase {
            // Holo-Plattform
            let platform = UIColor(red: 0.31, green: 0.89, blue: 0.76, alpha: 0.45)
            scene.rootNode.addChildNode(node(SCNTorus(ringRadius: 3.8, pipeRadius: 0.025), glow(platform), SCNVector3(0, -1.1, 0)))
            scene.rootNode.addChildNode(node(SCNTorus(ringRadius: 3.2, pipeRadius: 0.012), glow(platform.withAlphaComponent(0.5)), SCNVector3(0, -1.1, 0)))
            let discMat = glow(UIColor(red: 0.02, green: 0.12, blue: 0.11, alpha: 1))
            discMat.blendMode = .add
            let disc = node(SCNCylinder(radius: 3.8, height: 0.01), discMat, SCNVector3(0, -1.12, 0))
            scene.rootNode.addChildNode(disc)
            // unsichtbarer Boden, der nur den Schatten des Schiffs zeigt
            let catcher = SCNMaterial()
            catcher.lightingModel = .shadowOnly
            let floor = node(SCNPlane(width: 14, height: 14), catcher, SCNVector3(0, -1.1, 0))
            floor.eulerAngles.x = -.pi / 2
            scene.rootNode.addChildNode(floor)
            // schwaches Gegenlicht von unten, damit die Unterseite nicht absäuft
            let fill = SCNNode()
            fill.light = SCNLight()
            fill.light?.type = .directional
            fill.light?.intensity = 300
            fill.light?.color = UIColor(red: 1, green: 0.7, blue: 0.45, alpha: 1)
            fill.eulerAngles = SCNVector3(Float.pi / 5, -Float.pi / 1.5, 0)
            scene.rootNode.addChildNode(fill)

            pivot.runAction(.repeatForever(.rotateBy(x: 0, y: .pi * 2, z: 0, duration: 12)))
            let up = SCNAction.moveBy(x: 0, y: 0.15, z: 0, duration: 1.6)
            up.timingMode = .easeInEaseOut
            let down = SCNAction.moveBy(x: 0, y: -0.15, z: 0, duration: 1.6)
            down.timingMode = .easeInEaseOut
            pivot.runAction(.repeatForever(.sequence([up, down])))

            cam.camera?.fieldOfView = 36
            cam.camera?.wantsHDR = true
            cam.camera?.bloomIntensity = 0.6
            cam.camera?.bloomThreshold = 0.95
            cam.camera?.bloomBlurRadius = 8
            cam.camera?.screenSpaceAmbientOcclusionIntensity = 1.6
            cam.camera?.screenSpaceAmbientOcclusionRadius = 0.35
            cam.camera?.screenSpaceAmbientOcclusionBias = 0.02
            cam.camera?.vignettingIntensity = 0.7
            cam.camera?.vignettingPower = 1.2
            cam.camera?.saturation = 1.1
            cam.camera?.contrast = 0.15
            cam.position = SCNVector3(0, 5.4, 9.8)
            cam.look(at: SCNVector3(0, -0.1, 0))
        } else {
            // Draufsicht für das Spiel
            cam.camera?.usesOrthographicProjection = true
            cam.camera?.orthographicScale = Double(spriteSpan / 2)
            cam.position = SCNVector3(0, 20, 0)
            cam.eulerAngles = SCNVector3(-Float.pi / 2, 0, 0)
        }
        scene.rootNode.addChildNode(cam)
        return scene
    }
}

struct ShipModelView: UIViewRepresentable {
    let model: ShipModel

    func makeUIView(context: Context) -> SCNView {
        let v = SCNView()
        v.backgroundColor = .clear
        v.antialiasingMode = .multisampling4X
        v.isPlaying = true
        v.rendersContinuously = true
        configure(v)
        return v
    }

    func updateUIView(_ v: SCNView, context: Context) {
        if v.scene !== Ship3D.scene(for: model) { configure(v) }
    }

    private func configure(_ v: SCNView) {
        let scene = Ship3D.scene(for: model)
        v.scene = scene
        v.pointOfView = scene.rootNode.childNode(withName: "camera", recursively: false)
    }
}
