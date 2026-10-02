import SwiftUI
import SceneKit
import UIKit

// MARK: - Abgenutzter Lack

/// Prozedurale Lacktexturen im Stil „gebrauchtes Kriegsgerät“: Paneelnähte, abgeplatzte Farbe, Kratzer, Schmutz.
enum WornPaint {
    private static var cache: [String: SCNMaterial] = [:]

    static func material(_ key: String, base: UIColor, stripe: UIColor? = nil, marking: String? = nil) -> SCNMaterial {
        let id = "\(key)-\(marking ?? "")"
        if let m = cache[id] { return m }
        // Kennungen würden sich beim Kacheln überall wiederholen, deshalb ohne Beschriftung
        let (albedo, height, rough, metal) = textures(seed: id, base: base, stripe: stripe, marking: nil)
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        // Fallback, falls der Shader nicht greift
        m.diffuse.contents = albedo
        m.roughness.contents = rough
        m.metalness.contents = metal
        // Texturen werden dreiachsig im Modellraum projiziert: gleiche Detaildichte auf jedem Bauteil,
        // egal wie groß oder klein es ist. Nähte und Kanten kommen als Relief über die Höhenkarte.
        m.shaderModifiers = [.surface: triplanar]
        m.setValue(SCNMaterialProperty(contents: albedo), forKey: "tpAlbedo")
        m.setValue(SCNMaterialProperty(contents: rough), forKey: "tpRough")
        m.setValue(SCNMaterialProperty(contents: metal), forKey: "tpMetal")
        m.setValue(SCNMaterialProperty(contents: height), forKey: "tpHeight")
        m.setValue(NSNumber(value: 1.0 / 2.0), forKey: "tpScale")
        m.setValue(NSNumber(value: 0.02), forKey: "tpBump")
        cache[id] = m
        return m
    }

    /// Dreiachsige Projektion (Triplanar) im Modellraum plus Relief aus der Höhenkarte über Bildschirm-Ableitungen.
    static let triplanar = """
    #pragma arguments
    texture2d<float> tpAlbedo;
    texture2d<float> tpRough;
    texture2d<float> tpMetal;
    texture2d<float> tpHeight;
    float tpScale;
    float tpBump;

    #pragma body
    constexpr sampler tpS(filter::linear, mip_filter::linear, address::repeat);
    float3 tpPos = (scn_node.inverseModelViewTransform * float4(_surface.position, 1.0)).xyz * tpScale;
    float3 tpN = normalize((scn_node.inverseModelViewTransform * float4(_surface.normal, 0.0)).xyz);
    float3 tpW = pow(abs(tpN), float3(6.0));
    tpW = tpW / (tpW.x + tpW.y + tpW.z);
    float2 tpUX = tpPos.zy;
    float2 tpUY = tpPos.xz;
    float2 tpUZ = tpPos.xy;
    float4 tpA = tpAlbedo.sample(tpS, tpUX) * tpW.x + tpAlbedo.sample(tpS, tpUY) * tpW.y + tpAlbedo.sample(tpS, tpUZ) * tpW.z;
    float tpR = tpRough.sample(tpS, tpUX).r * tpW.x + tpRough.sample(tpS, tpUY).r * tpW.y + tpRough.sample(tpS, tpUZ).r * tpW.z;
    float tpM = tpMetal.sample(tpS, tpUX).r * tpW.x + tpMetal.sample(tpS, tpUY).r * tpW.y + tpMetal.sample(tpS, tpUZ).r * tpW.z;
    float tpH = tpHeight.sample(tpS, tpUX).r * tpW.x + tpHeight.sample(tpS, tpUY).r * tpW.y + tpHeight.sample(tpS, tpUZ).r * tpW.z;
    _surface.diffuse = float4(tpA.rgb, 1.0);
    _surface.roughness = tpR;
    _surface.metalness = tpM;
    // Relief: Normale anhand der Höhenänderung pro Bildpunkt kippen
    float3 tpDpx = dfdx(_surface.position);
    float3 tpDpy = dfdy(_surface.position);
    float tpDhx = dfdx(tpH);
    float tpDhy = dfdy(tpH);
    float3 tpNv = _surface.normal;
    float3 tpR1 = cross(tpDpy, tpNv);
    float3 tpR2 = cross(tpNv, tpDpx);
    float tpDet = dot(tpDpx, tpR1);
    float3 tpGrad = sign(tpDet) * (tpDhx * tpR1 + tpDhy * tpR2);
    float3 tpNew = abs(tpDet) * tpNv - tpBump * tpGrad;
    if (length(tpNew) > 1e-6) { _surface.normal = normalize(tpNew); }
    """

    /// liefert (Farbe, Höhe, Rauheit, Metall)
    private static func textures(seed: String, base: UIColor, stripe: UIColor?, marking: String?) -> (UIImage, UIImage, UIImage, UIImage) {
        var rng = SeededRNG(seed)
        let s: CGFloat = 512

        // Positionen für Abplatzer, bevorzugt an den Kanten
        struct Chip { let path: UIBezierPath; let deep: Bool }
        var chips: [Chip] = []
        for _ in 0..<130 {
            var x = rng.c(0...s), y = rng.c(0...s)
            if rng.chance(0.7) {
                switch Int(rng.d(0...3.99)) {
                case 0: x = rng.c(0...26)
                case 1: x = s - rng.c(0...26)
                case 2: y = rng.c(0...26)
                default: y = s - rng.c(0...26)
                }
            }
            let r = rng.c(2...9)
            let p = UIBezierPath()
            let n = 6
            for k in 0..<n {
                let a = CGFloat(k) / CGFloat(n) * .pi * 2
                let rr = r * rng.c(0.4...1.3)
                let pt = CGPoint(x: x + cos(a) * rr * rng.c(0.8...1.8), y: y + sin(a) * rr)
                if k == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
            }
            p.close()
            chips.append(Chip(path: p, deep: rng.chance(0.45)))
        }
        // Paneelnähte
        var seams: [(CGPoint, CGPoint)] = []
        for _ in 0..<Int(rng.d(6...10)) {
            if rng.chance(0.5) {
                let y = rng.c(60...(s - 60))
                seams.append((CGPoint(x: 0, y: y), CGPoint(x: s, y: y)))
            } else {
                let x = rng.c(60...(s - 60))
                seams.append((CGPoint(x: x, y: 0), CGPoint(x: x, y: s)))
            }
        }

        // Wartungsluken
        var hatches: [CGRect] = []
        for _ in 0..<Int(rng.d(5...9)) {
            hatches.append(CGRect(x: rng.c(30...(s - 120)), y: rng.c(30...(s - 90)), width: rng.c(40...110), height: rng.c(26...70)))
        }
        let stencils = ["NO STEP", "A-17", "▲ 04", "VENT", "07", "HX-2", "⚠", "PWR"]

        let albedo = UIGraphicsImageRenderer(size: CGSize(width: s, height: s)).image { ctx in
            let g = ctx.cgContext
            base.setFill()
            g.fill(CGRect(x: 0, y: 0, width: s, height: s))
            // Farbrauschen
            for _ in 0..<1600 {
                let r = rng.c(1...5)
                UIColor(white: rng.chance(0.5) ? 1 : 0, alpha: rng.c(0.015...0.05)).setFill()
                g.fillEllipse(in: CGRect(x: rng.c(0...s), y: rng.c(0...s), width: r, height: r))
            }
            if let stripe {
                stripe.setFill()
                // senkrechtes Band, damit es beim Kacheln nahtlos weiterläuft
                g.fill(CGRect(x: s * 0.3, y: 0, width: s * 0.3, height: s))
            }
            // Rand-Nähte und Nähte
            g.setStrokeColor(UIColor(white: 0, alpha: 0.45).cgColor)
            g.setLineWidth(3)
            g.stroke(CGRect(x: 10, y: 10, width: s - 20, height: s - 20))
            for (a, b) in seams {
                g.move(to: a); g.addLine(to: b)
            }
            g.strokePath()
            g.setStrokeColor(UIColor(white: 1, alpha: 0.12).cgColor)
            g.setLineWidth(1.5)
            for (a, b) in seams {
                g.move(to: CGPoint(x: a.x + 2, y: a.y + 2)); g.addLine(to: CGPoint(x: b.x + 2, y: b.y + 2))
            }
            g.strokePath()
            // Luken mit Rahmen, Nieten und Griff
            for h in hatches {
                g.setFillColor(UIColor(white: rng.chance(0.5) ? 0 : 1, alpha: 0.06).cgColor)
                g.fill(h)
                g.setStrokeColor(UIColor(white: 0, alpha: 0.45).cgColor)
                g.setLineWidth(2)
                g.stroke(h)
                g.setFillColor(UIColor(white: 0, alpha: 0.4).cgColor)
                for c in [CGPoint(x: h.minX + 5, y: h.minY + 5), CGPoint(x: h.maxX - 8, y: h.minY + 5),
                          CGPoint(x: h.minX + 5, y: h.maxY - 8), CGPoint(x: h.maxX - 8, y: h.maxY - 8)] {
                    g.fillEllipse(in: CGRect(x: c.x, y: c.y, width: 3.5, height: 3.5))
                }
                g.fill(CGRect(x: h.midX - 8, y: h.midY - 1.5, width: 16, height: 3))
            }
            // Nietreihen entlang der Nähte
            UIColor(white: 0, alpha: 0.3).setFill()
            for (a, b) in seams {
                let len = hypot(b.x - a.x, b.y - a.y)
                var d: CGFloat = 8
                while d < len {
                    let p = CGPoint(x: a.x + (b.x - a.x) * d / len, y: a.y + (b.y - a.y) * d / len)
                    let off: CGFloat = 6
                    let q = a.x == b.x ? CGPoint(x: p.x + off, y: p.y) : CGPoint(x: p.x, y: p.y + off)
                    g.fillEllipse(in: CGRect(x: q.x - 1.5, y: q.y - 1.5, width: 3, height: 3))
                    d += 14
                }
            }
            // kleine Schablonenschriften
            let stencilAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedSystemFont(ofSize: 13, weight: .bold),
                .foregroundColor: UIColor(white: 0.1, alpha: 0.55)
            ]
            for _ in 0..<4 {
                let t = stencils[Int(rng.d(0...Double(stencils.count) - 0.01))]
                (t as NSString).draw(at: CGPoint(x: rng.c(20...(s - 90)), y: rng.c(20...(s - 30))), withAttributes: stencilAttrs)
            }
            // Nieten entlang der Ränder
            UIColor(white: 0, alpha: 0.35).setFill()
            var t: CGFloat = 24
            while t < s - 20 {
                g.fillEllipse(in: CGRect(x: t, y: 17, width: 4, height: 4))
                g.fillEllipse(in: CGRect(x: t, y: s - 21, width: 4, height: 4))
                t += 22
            }
            if let marking {
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.monospacedSystemFont(ofSize: 64, weight: .heavy),
                    .foregroundColor: UIColor(white: 0.12, alpha: 0.7)
                ]
                (marking as NSString).draw(at: CGPoint(x: s * 0.62, y: s * 0.12), withAttributes: attrs)
                UIColor(red: 0.85, green: 0.45, blue: 0.1, alpha: 0.85).setFill()
                for k in 0..<5 { g.fill(CGRect(x: s * 0.62 + CGFloat(k) * 16, y: s * 0.32, width: 9, height: 22)) }
            }
            // Abplatzer: dunkles Metall mit hellem Rand
            for c in chips {
                (c.deep ? UIColor(white: 0.22, alpha: 0.95) : UIColor(white: 0.5, alpha: 0.6)).setFill()
                c.path.fill()
                UIColor(white: 1, alpha: 0.18).setStroke()
                c.path.lineWidth = 1
                c.path.stroke()
            }
            // Kratzer
            g.setStrokeColor(UIColor(white: 0.2, alpha: 0.4).cgColor)
            g.setLineWidth(1)
            for _ in 0..<90 {
                let x = rng.c(0...s), y = rng.c(0...s)
                g.move(to: CGPoint(x: x, y: y))
                g.addLine(to: CGPoint(x: x + rng.c(-40...40), y: y + rng.c(-12...12)))
            }
            g.strokePath()
            // weiche Schmutzflecken (kachelbar, ohne Verlauf über die ganze Fläche)
            for _ in 0..<22 {
                let r = rng.c(30...100)
                let c = CGPoint(x: rng.c(0...s), y: rng.c(0...s))
                let grime = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                       colors: [UIColor(red: 0.18, green: 0.14, blue: 0.1, alpha: rng.c(0.12...0.28)).cgColor,
                                                UIColor(red: 0.18, green: 0.14, blue: 0.1, alpha: 0).cgColor] as CFArray,
                                       locations: [0, 1])!
                g.drawRadialGradient(grime, startCenter: c, startRadius: 0, endCenter: c, endRadius: r, options: [])
            }
        }

        func gray(_ draw: (CGContext) -> Void, fill: CGFloat) -> UIImage {
            UIGraphicsImageRenderer(size: CGSize(width: s, height: s)).image { ctx in
                UIColor(white: fill, alpha: 1).setFill()
                ctx.fill(CGRect(x: 0, y: 0, width: s, height: s))
                draw(ctx.cgContext)
            }
        }

        let height = gray({ g in
            g.setStrokeColor(UIColor(white: 0.1, alpha: 1).cgColor)
            g.setLineWidth(5)
            g.stroke(CGRect(x: 10, y: 10, width: s - 20, height: s - 20))
            for (a, b) in seams { g.move(to: a); g.addLine(to: b) }
            g.strokePath()
            g.setLineWidth(3)
            for h in hatches { g.stroke(h) }
            for c in chips {
                UIColor(white: c.deep ? 0.3 : 0.4, alpha: 1).setFill()
                c.path.fill()
            }
        }, fill: 0.5)
        let rough = gray({ _ in
            for c in chips {
                UIColor(white: c.deep ? 0.32 : 0.45, alpha: 1).setFill()
                c.path.fill()
            }
        }, fill: 0.72)
        let metal = gray({ _ in
            for c in chips where c.deep {
                UIColor(white: 0.9, alpha: 1).setFill()
                c.path.fill()
            }
        }, fill: 0.08)
        return (albedo, height, rough, metal)
    }
}

// MARK: - Bausatz

/// Baukasten für Schiffe aus abgeschrägten Modulen. Nase zeigt nach +x, oben ist +y, z ist seitlich.
final class ShipKit {
    let root = SCNNode()
    let paint: SCNMaterial
    let accent: SCNMaterial
    let stripe: SCNMaterial
    let second: SCNMaterial
    let dark: SCNMaterial
    let metal: SCNMaterial
    let glass: SCNMaterial
    let lamp: SCNMaterial
    let fire: SCNMaterial
    let weaponGlow: SCNMaterial
    var rng: SeededRNG

    init(seed: String, base: UIColor, accent accentColor: UIColor, second secondColor: UIColor, weaponHue: Double, marking: String) {
        rng = SeededRNG(seed)
        paint = WornPaint.material("p-\(seed)", base: base, marking: marking)
        accent = WornPaint.material("a-\(seed)", base: accentColor)
        stripe = WornPaint.material("s-\(seed)", base: base, stripe: accentColor)
        second = WornPaint.material("2-\(seed)", base: secondColor)
        dark = WornPaint.material("dark", base: UIColor(red: 0.2, green: 0.2, blue: 0.21, alpha: 1))
        metal = SCNMaterial()
        metal.lightingModel = .physicallyBased
        metal.diffuse.contents = UIColor(red: 0.3, green: 0.29, blue: 0.27, alpha: 1)
        metal.metalness.contents = 0.85
        metal.roughness.contents = 0.55
        glass = SCNMaterial()
        glass.lightingModel = .physicallyBased
        glass.diffuse.contents = UIColor(white: 0.03, alpha: 1)
        glass.metalness.contents = 1
        glass.roughness.contents = 0.06
        glass.emission.contents = UIColor(red: 0.12, green: 0.06, blue: 0.02, alpha: 1)
        lamp = ShipKit.glow(UIColor(red: 1, green: 0.55, blue: 0.15, alpha: 1))
        fire = ShipKit.glow(UIColor(red: 1, green: 0.5, blue: 0.12, alpha: 1))
        weaponGlow = ShipKit.glow(UIColor(hsl(weaponHue, 0.9, 0.6)))
    }

    static func glow(_ c: UIColor) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = c
        m.emission.contents = c
        return m
    }

    @discardableResult
    private func add(_ g: SCNGeometry, _ m: SCNMaterial, _ p: SCNVector3, rot: SCNVector3 = SCNVector3(0, 0, 0), mirror: Bool) -> SCNNode {
        g.materials = [m]
        let n = SCNNode(geometry: g)
        n.position = p
        n.eulerAngles = rot
        root.addChildNode(n)
        if mirror && abs(p.z) > 0.001 || mirror && (rot.x != 0 || rot.y != 0) {
            let c = SCNNode(geometry: g)
            c.position = SCNVector3(p.x, p.y, -p.z)
            c.eulerAngles = SCNVector3(-rot.x, -rot.y, rot.z)
            root.addChildNode(c)
        }
        return n
    }

    /// Abgeschrägter Block. size = (Länge x, Höhe y, Breite z)
    func box(_ x: Float, _ y: Float, _ z: Float, _ l: CGFloat, _ h: CGFloat, _ w: CGFloat,
             _ m: SCNMaterial? = nil, chamfer: CGFloat = 0.05, rot: SCNVector3 = SCNVector3(0, 0, 0), mirror: Bool = true) {
        add(SCNBox(width: l, height: h, length: w, chamferRadius: min(chamfer, min(l, h, w) * 0.45)), m ?? paint,
            SCNVector3(x, y, z), rot: rot, mirror: mirror)
    }

    /// Zylinder entlang der x-Achse
    func tube(_ x: Float, _ y: Float, _ z: Float, r: CGFloat, len: CGFloat, _ m: SCNMaterial? = nil, mirror: Bool = true) {
        let c = SCNCylinder(radius: r, height: len)
        c.radialSegmentCount = 24
        add(c, m ?? metal, SCNVector3(x, y, z), rot: SCNVector3(0, 0, -Float.pi / 2), mirror: mirror)
    }

    /// Seitenprofil (x, y) mit Dicke in z, abgeschrägt
    func profile(_ pts: [(CGFloat, CGFloat)], z: Float, thick: CGFloat, _ m: SCNMaterial? = nil, chamfer: CGFloat = 0.06,
                 rotX: Float = 0, mirror: Bool = true) {
        let p = UIBezierPath()
        p.move(to: CGPoint(x: pts[0].0, y: pts[0].1))
        for q in pts.dropFirst() { p.addLine(to: CGPoint(x: q.0, y: q.1)) }
        p.close()
        let shape = SCNShape(path: p, extrusionDepth: thick)
        shape.chamferRadius = min(chamfer, thick * 0.45)
        shape.chamferMode = .both
        add(shape, m ?? paint, SCNVector3(0, 0, z), rot: SCNVector3(rotX, 0, 0), mirror: mirror)
    }

    /// Draufsicht (x, z) mit Dicke in y, z.B. Flügel
    func plate(_ pts: [(CGFloat, CGFloat)], y: Float, thick: CGFloat, _ m: SCNMaterial? = nil, chamfer: CGFloat = 0.04,
               mirror: Bool = true) {
        let p = UIBezierPath()
        p.move(to: CGPoint(x: pts[0].0, y: pts[0].1))
        for q in pts.dropFirst() { p.addLine(to: CGPoint(x: q.0, y: q.1)) }
        p.close()
        let shape = SCNShape(path: p, extrusionDepth: thick)
        shape.chamferRadius = min(chamfer, thick * 0.45)
        shape.chamferMode = .both
        shape.materials = [m ?? paint]
        // Pfad-y wird zu Welt-z
        let n = SCNNode(geometry: shape)
        n.eulerAngles.x = .pi / 2
        n.position.y = y
        root.addChildNode(n)
        if mirror {
            let c = SCNNode(geometry: shape)
            c.eulerAngles.x = -.pi / 2
            c.position.y = y
            root.addChildNode(c)
        }
    }

    /// Triebwerksgondel mit glühender Düse; gibt die Heck-Position zurück
    @discardableResult
    func engine(_ x: Float, _ y: Float, _ z: Float, r: CGFloat, len: CGFloat, _ m: SCNMaterial? = nil, mirror: Bool = true) -> Float {
        let mat = m ?? paint
        tube(x, y, z, r: r, len: len, mat, mirror: mirror)
        let half = Float(len / 2)
        // Ringe und Einlass
        for k in 0..<3 {
            tube(x - half + 0.25 + Float(k) * 0.22, y, z, r: r * 1.06, len: 0.07, metal, mirror: mirror)
        }
        tube(x + half + 0.04, y, z, r: r * 0.82, len: 0.1, dark, mirror: mirror)
        // Einlassgitter vorn
        for k in 0..<3 {
            box(x + half + 0.1, y - Float(r) * 0.4 + Float(k) * Float(r) * 0.4, z, 0.04, 0.03, r * 1.4, metal, chamfer: 0.005, mirror: mirror)
        }
        // Panzerschale oben, Rippenring hinten
        box(x + 0.15, y + Float(r * 0.62), z, len * 0.7, r * 0.42, r * 1.25, second, chamfer: 0.06, mirror: mirror)
        for k in 0..<5 {
            tube(x - half + 0.08 + Float(k) * 0.09, y, z, r: r * 1.02, len: 0.04, dark, mirror: mirror)
        }
        // glühende Lüftungsschlitze an der Außenseite
        let outer: Float = z >= 0 ? 1 : -1
        for k in 0..<3 {
            box(x - 0.1 + Float(k) * 0.22, y, z + outer * Float(r * 1.0), 0.12, 0.04, 0.04, lamp, chamfer: 0.01, mirror: mirror)
        }
        // Düse mit Glutring
        tube(x - half - 0.12, y, z, r: r * 0.92, len: 0.26, metal, mirror: mirror)
        tube(x - half - 0.26, y, z, r: r * 0.72, len: 0.03, fire, mirror: mirror)
        let ring = SCNTorus(ringRadius: r * 0.8, pipeRadius: 0.025)
        add(ring, lamp, SCNVector3(x - half - 0.24, y, z), rot: SCNVector3(0, 0, Float.pi / 2), mirror: mirror)
        let tail = x - half - 0.28
        for side in mirror && abs(z) > 0.001 ? [z, -z] : [z] {
            let outlet = SCNNode()
            outlet.name = "outlet:\(r)"
            outlet.position = SCNVector3(tail, y, side)
            root.addChildNode(outlet)
        }
        return tail
    }

    /// Senkrechtes Leitwerk, nach außen gekippt
    func fin(_ x: Float, _ y: Float, _ z: Float, height: CGFloat, len: CGFloat, tilt: Float, _ m: SCNMaterial? = nil) {
        let pts: [(CGFloat, CGFloat)] = [(0, 0), (-len * 0.45, height), (-len * 0.85, height), (-len, 0)]
        let p = UIBezierPath()
        p.move(to: CGPoint(x: pts[0].0, y: pts[0].1))
        for q in pts.dropFirst() { p.addLine(to: CGPoint(x: q.0, y: q.1)) }
        p.close()
        let shape = SCNShape(path: p, extrusionDepth: 0.09)
        shape.chamferRadius = 0.03
        shape.chamferMode = .both
        add(shape, m ?? paint, SCNVector3(x, y, z), rot: SCNVector3(tilt, 0, 0), mirror: true)
        // breiter Farbbalken quer über das Leitwerk
        let lead = { (f: CGFloat) in -len * 0.45 * f }, trail = { (f: CGFloat) in -len + len * 0.15 * f }
        let b = UIBezierPath()
        b.move(to: CGPoint(x: lead(0.5) - 0.01, y: height * 0.5))
        b.addLine(to: CGPoint(x: lead(0.78) - 0.01, y: height * 0.78))
        b.addLine(to: CGPoint(x: trail(0.78) + 0.01, y: height * 0.78))
        b.addLine(to: CGPoint(x: trail(0.5) + 0.01, y: height * 0.5))
        b.close()
        let band = SCNShape(path: b, extrusionDepth: 0.1)
        band.chamferRadius = 0.02
        band.chamferMode = .both
        add(band, m == nil ? accent : paint, SCNVector3(x, y, z), rot: SCNVector3(tilt, 0, 0), mirror: true)
    }

    /// Glaskanzel mit Rahmen
    func canopy(_ x: Float, _ y: Float, len: CGFloat, height: CGFloat, width: CGFloat) {
        let l = len, h = height
        profile([(l * 0.55, 0), (l * 0.1, h), (-l * 0.35, h * 0.85), (-l * 0.5, 0)].map { ($0.0 + CGFloat(x), $0.1 + CGFloat(y)) },
                z: 0, thick: width, glass, chamfer: width * 0.4, mirror: false)
        for t in [-0.3, -0.05, 0.2] as [CGFloat] {
            box(x + Float(l * t), y + Float(h * (0.82 - abs(t) * 0.6)), 0, 0.05, 0.07, width * 1.03, metal, mirror: false)
        }
        box(x - Float(l * 0.05), y + Float(h * 0.9), 0, l * 0.75, 0.05, 0.05, metal, mirror: false)
        box(x - Float(l * 0.05), y + 0.02, 0, l * 1.05, 0.08, width * 1.12, dark, chamfer: 0.03, mirror: false)
    }

    /// Kanone mit Gehäuse, Mündungsbremse und Glühspitze
    func cannon(_ x: Float, _ y: Float, _ z: Float, len: CGFloat, r: CGFloat = 0.07) {
        box(x - Float(len * 0.35), y, z, len * 0.35, r * 4, r * 4, dark)
        tube(x, y, z, r: r, len: len, metal)
        tube(x + Float(len / 2) - 0.08, y, z, r: r * 1.6, len: 0.16, metal)
        tube(x + Float(len / 2) + 0.01, y, z, r: r * 0.6, len: 0.02, weaponGlow)
    }

    func rocketPod(_ x: Float, _ y: Float, _ z: Float) {
        box(x, y, z, 1.1, 0.42, 0.5, second, chamfer: 0.08)
        for ty in [-0.1, 0.1] as [Float] {
            for tz in [-0.12, 0.12] as [Float] {
                tube(x + 0.56, y + ty, z + tz, r: 0.075, len: 0.03, weaponGlow)
            }
        }
    }

    func railgun(_ x0: Float, _ x1: Float, _ y: Float) {
        let len = CGFloat(x1 - x0)
        let cx = (x0 + x1) / 2
        for z in [-0.18, 0.18] as [Float] {
            box(cx, y, z, len, 0.1, 0.1, metal, chamfer: 0.02, mirror: false)
        }
        box(cx, y, 0, len * 0.95, 0.03, 0.05, weaponGlow, chamfer: 0, mirror: false)
        var x = x0 + 0.3
        while x < x1 - 0.2 {
            let t = SCNTorus(ringRadius: 0.27, pipeRadius: 0.05)
            add(t, weaponGlow, SCNVector3(x, y, 0), rot: SCNVector3(0, 0, Float.pi / 2), mirror: false)
            x += 0.6
        }
    }

    func bomb(_ x: Float, _ y: Float) {
        let s = SCNSphere(radius: 0.42)
        add(s, dark, SCNVector3(x, y, 0), mirror: false)
        add(SCNTorus(ringRadius: 0.44, pipeRadius: 0.05), weaponGlow, SCNVector3(x, y, 0), mirror: false)
        box(x - 0.45, y, 0, 0.35, 0.05, 0.6, metal, mirror: false)
        box(x - 0.45, y, 0, 0.35, 0.6, 0.05, metal, mirror: false)
    }

    /// Überlappende Panzerplatten entlang der Oberseite
    func plates(x0: Float, x1: Float, y: Float, width: CGFloat, count: Int) {
        let step = (x1 - x0) / Float(count)
        for i in 0..<count {
            let x = x0 + step * (Float(i) + 0.5)
            let mat = i % 3 == 1 ? stripe : (i % 3 == 2 ? second : paint)
            let w = width * rng.c(0.75...1.0)
            box(x, y + 0.04 + Float(i % 2) * 0.03, 0, CGFloat(step) * 1.08, 0.09, w, mat, chamfer: 0.035, mirror: false)
            // Naht mit Nieten
            box(x - step / 2, y + 0.09, 0, 0.03, 0.02, w * 0.9, dark, chamfer: 0.005, mirror: false)
        }
    }

    /// Mechanische Bauchsektion mit Rippen
    func belly(x0: Float, x1: Float, y: Float, width: CGFloat) {
        let len = CGFloat(x1 - x0)
        box((x0 + x1) / 2, y, 0, len, 0.22, width, dark, chamfer: 0.04, mirror: false)
        var x = x0 + 0.15
        while x < x1 - 0.1 {
            box(x, y - 0.11, 0, 0.06, 0.05, width * 1.05, metal, chamfer: 0.01, mirror: false)
            x += 0.28
        }
    }

    /// Leitungen entlang der Flanken
    func pipes(x0: Float, x1: Float, y: Float, z: Float) {
        let len = CGFloat(x1 - x0)
        tube((x0 + x1) / 2, y, z, r: 0.045, len: len, metal)
        tube((x0 + x1) / 2, y - 0.1, z + 0.02, r: 0.03, len: len * 0.8, dark)
        var x = x0 + 0.2
        while x < x1 {
            box(x, y - 0.05, z, 0.05, 0.16, 0.1, metal, chamfer: 0.01)
            x += 0.6
        }
    }

    /// Erhabenes Paneel und dunkle Vorderkante auf einem Flügel (Punkte wie bei plate, rechte Seite)
    func wingDetail(_ pts: [(CGFloat, CGFloat)], y: Float, thick: CGFloat) {
        let cx = pts.map { $0.0 }.reduce(0, +) / CGFloat(pts.count)
        let cz = pts.map { $0.1 }.reduce(0, +) / CGFloat(pts.count)
        let inset = pts.map { (cx + ($0.0 - cx) * 0.68, cz + ($0.1 - cz) * 0.68) }
        plate(inset, y: y + Float(thick / 2) + 0.02, thick: 0.05, second, chamfer: 0.02)
        // Vorderkante: erste Kante des Umrisses
        let a = pts[0], b = pts[1]
        let nx = -(b.1 - a.1), nz = b.0 - a.0
        let nl = max(0.001, hypot(nx, nz))
        let o: CGFloat = 0.12
        plate([a, b, (b.0 + nx / nl * o, b.1 + nz / nl * o), (a.0 + nx / nl * o, a.1 + nz / nl * o)],
              y: y + 0.01, thick: thick + 0.04, dark, chamfer: 0.02)
        // Kleinteile auf dem Flügel
        for _ in 0..<3 {
            let t = rng.c(0.2...0.8)
            let px = cx + (inset[0].0 - cx) * t
            let pz = cz + (inset[0].1 - cz) * t
            box(Float(px), y + Float(thick / 2) + 0.07, Float(pz), rng.c(0.12...0.3), 0.05, rng.c(0.08...0.18), metal, chamfer: 0.01)
        }
    }

    /// Schräge Panzerplatten an den Flanken
    func sidePanels(x0: Float, x1: Float, y: Float, z: Float, count: Int) {
        let step = (x1 - x0) / Float(count)
        for i in 0..<count {
            let x = x0 + step * (Float(i) + 0.5)
            box(x, y, z, CGFloat(step) * 0.92, 0.26, 0.06, i % 2 == 0 ? paint : second, chamfer: 0.02, rot: SCNVector3(-0.28, 0, 0))
            box(x, y - 0.17, z + 0.02, CGFloat(step) * 0.5, 0.05, 0.05, dark, chamfer: 0.01)
        }
    }

    /// Dunkle Sensorspitze mit Schlitzen am Bug
    func sensorNose(_ x: Float, _ y: Float) {
        let cone = SCNCone(topRadius: 0.02, bottomRadius: 0.13, height: 0.4)
        add(cone, dark, SCNVector3(x, y, 0), rot: SCNVector3(0, 0, -Float.pi / 2), mirror: false)
        for k in 0..<2 {
            box(x - 0.45 - Float(k) * 0.12, y, 0.14, 0.06, 0.03, 0.06, lamp, chamfer: 0.005)
        }
    }

    func antenna(_ x: Float, _ y: Float, _ z: Float, h: CGFloat) {
        let c = SCNCylinder(radius: 0.018, height: h)
        add(c, metal, SCNVector3(x, y + Float(h / 2), z), mirror: true)
        box(x, y + Float(h), z, 0.05, 0.05, 0.05, lamp, chamfer: 0.01)
    }

    /// Lufteinlass mit Gitter
    func intake(_ x: Float, _ y: Float, _ z: Float, h: CGFloat, w: CGFloat) {
        box(x, y, z, 0.5, h, w, dark, chamfer: 0.04)
        for k in 0..<4 {
            box(x + 0.26, y - Float(h) * 0.35 + Float(k) * Float(h) * 0.23, z, 0.03, 0.025, w * 0.9, metal, chamfer: 0.005)
        }
    }

    func lamp(_ x: Float, _ y: Float, _ z: Float, size: CGFloat = 0.12) {
        box(x, y, z, size, size * 0.6, size, lamp, chamfer: 0.01)
    }

    /// Kleinteile auf einer Fläche (Rohre, Kästen, Gitter)
    func greeble(x0: Float, x1: Float, y: Float, zMax: Float, count: Int) {
        for _ in 0..<count {
            let x = Float(rng.d(Double(x0)...Double(x1)))
            let z = Float(rng.d(Double(-zMax)...Double(zMax)))
            let roll = rng.d(0...1)
            if roll < 0.5 {
                let h = rng.c(0.05...0.16)
                box(x, y + Float(h / 2), z, rng.c(0.12...0.45), h, rng.c(0.1...0.3), rng.chance(0.5) ? dark : metal, chamfer: 0.02)
            } else if roll < 0.8 {
                tube(x, y + 0.05, z, r: rng.c(0.03...0.06), len: rng.c(0.3...0.9), metal)
            } else {
                let c = SCNCylinder(radius: rng.c(0.06...0.12), height: 0.08)
                add(c, dark, SCNVector3(x, y + 0.04, z), mirror: true)
            }
        }
    }

    func weapon(_ kind: WeaponKind, hardpoints: [(Float, Float, Float)], spine: (Float, Float, Float), belly: (Float, Float)) {
        switch kind {
        case .cannon:
            for h in hardpoints { cannon(h.0, h.1, h.2, len: 2.0) }
        case .rocket:
            for h in hardpoints { rocketPod(h.0 - 0.5, h.1, h.2) }
        case .railgun:
            railgun(spine.0, spine.1, spine.2)
        case .bomb:
            bomb(belly.0, belly.1)
            for h in hardpoints { cannon(h.0 - 0.4, h.1, h.2, len: 1.0, r: 0.05) }
        }
    }
}

// MARK: - Schiffsentwürfe

enum ShipDesigns {
    private static func c(_ h: Double, _ s: Double, _ l: Double) -> UIColor { UIColor(hsl(h, s, l)) }

    static let bone = c(38, 0.13, 0.7)
    static let red = c(356, 0.68, 0.33)
    static let olive = c(75, 0.22, 0.4)
    static let orange = c(32, 0.75, 0.5)
    static let gunmetal = c(30, 0.05, 0.3)
    static let navy = c(212, 0.25, 0.42)
    static let gold = c(44, 0.6, 0.55)
    static let night = c(262, 0.12, 0.17)

    static func build(_ m: ShipModel) -> SCNNode {
        let k: ShipKit
        switch m.id {
        case "libelle": k = kit(m, bone, orange, gunmetal, "LB"); libelle(k, m)
        case "atlas": k = kit(m, bone, olive, orange, "AT"); atlas(k, m)
        case "bastion": k = kit(m, olive, bone, gunmetal, "BS"); bastion(k, m)
        case "orion": k = kit(m, bone, navy, gunmetal, "OR"); orion(k, m)
        case "viper": k = kit(m, bone, red, gunmetal, "VP"); viper(k, m)
        case "titan": k = kit(m, gunmetal, olive, orange, "TT"); titan(k, m)
        case "phantom": k = kit(m, night, red, gunmetal, "PH"); phantom(k, m)
        case "nova": k = kit(m, bone, gold, navy, "NV"); nova(k, m)
        default: k = kit(m, bone, red, gunmetal, "FK"); falke(k, m)
        }
        return k.root
    }

    private static func kit(_ m: ShipModel, _ base: UIColor, _ acc: UIColor, _ sec: UIColor, _ code: String) -> ShipKit {
        ShipKit(seed: m.id, base: base, accent: acc, second: sec, weaponHue: m.weapon.hue, marking: code)
    }

    // Jäger wie im Vorbild: spitzer Rumpf, Pfeilflügel, zwei Gondeln, zwei Leitwerke
    private static func falke(_ k: ShipKit, _ m: ShipModel) {
        k.profile([(3.5, 0.0), (2.4, 0.3), (0.8, 0.5), (-2.0, 0.5), (-2.4, 0.25), (-2.4, -0.3), (0.8, -0.35), (3.0, -0.12)],
                  z: 0, thick: 0.95, mirror: false)
        k.profile([(3.6, -0.02), (2.6, 0.1), (2.6, -0.1)], z: 0.22, thick: 0.18, k.dark)
        k.canopy(1.2, 0.45, len: 1.8, height: 0.42, width: 0.6)
        k.plate([(1.2, 0.45), (-0.7, 2.7), (-1.5, 2.8), (-1.7, 2.55), (-1.4, 0.45)], y: -0.05, thick: 0.14, k.stripe)
        k.plate([(-0.9, 2.55), (-1.6, 2.6), (-1.7, 2.75), (-0.8, 2.72)], y: 0.0, thick: 0.18, k.accent)
        k.box(0.2, 0.15, 0.62, 2.4, 0.4, 0.3, k.paint, chamfer: 0.08)
        let tail = k.engine(-1.35, 0.22, 0.9, r: 0.36, len: 1.9)
        k.fin(-1.2, 0.5, 0.55, height: 1.15, len: 1.0, tilt: -0.28)
        k.greeble(x0: -1.8, x1: 0.2, y: 0.5, zMax: 0.35, count: 10)
        k.lamp(1.0, 0.05, 0.85)
        k.lamp(-2.42, 0.3, 0)
        k.plates(x0: -2.0, x1: 0.4, y: 0.5, width: 0.75, count: 5)
        k.belly(x0: -1.6, x1: 1.6, y: -0.42, width: 0.6)
        k.pipes(x0: -2.0, x1: 0.6, y: 0.12, z: 0.5)
        k.intake(0.95, 0.12, 0.62, h: 0.3, w: 0.26)
        k.wingDetail([(1.2, 0.45), (-0.7, 2.7), (-1.5, 2.8), (-1.7, 2.55), (-1.4, 0.45)], y: -0.05, thick: 0.14)
        k.sidePanels(x0: -1.8, x1: 1.4, y: 0.05, z: 0.5, count: 4)
        k.sensorNose(3.5, 0.0)
        k.antenna(-1.6, 0.5, 0.2, h: 0.5)
        k.weapon(m.weapon, hardpoints: [(1.0, -0.12, 1.55), (2.2, -0.2, 0.42)], spine: (-1.2, 3.2, 0.62), belly: (-0.3, -0.62))
        _ = tail
    }

    // Späher: schlank, ein großes Triebwerk, kleine Flügel
    private static func libelle(_ k: ShipKit, _ m: ShipModel) {
        k.profile([(3.8, 0.0), (2.2, 0.28), (-1.6, 0.36), (-2.0, 0.2), (-2.0, -0.25), (2.4, -0.2)], z: 0, thick: 0.7, mirror: false)
        k.canopy(1.5, 0.3, len: 1.6, height: 0.36, width: 0.48)
        k.plate([(0.6, 0.3), (-0.8, 1.9), (-1.3, 1.95), (-1.1, 0.3)], y: -0.02, thick: 0.1, k.stripe)
        k.plate([(-1.0, 1.75), (-1.3, 1.95), (-1.6, 1.95), (-1.4, 1.7)], y: 0.0, thick: 0.14, k.accent)
        k.engine(-2.2, 0.06, 0, r: 0.44, len: 1.4, mirror: false)
        k.fin(-1.3, 0.32, 0.3, height: 0.8, len: 0.8, tilt: -0.45)
        k.box(-0.2, 0.0, 0.42, 1.6, 0.28, 0.25, k.second, chamfer: 0.06)
        k.greeble(x0: -1.4, x1: 0.4, y: 0.36, zMax: 0.22, count: 7)
        k.lamp(2.0, 0.0, 0.36)
        k.plates(x0: -1.6, x1: 0.6, y: 0.36, width: 0.55, count: 4)
        k.belly(x0: -1.2, x1: 1.8, y: -0.3, width: 0.45)
        k.pipes(x0: -1.6, x1: 0.6, y: 0.05, z: 0.38)
        k.wingDetail([(0.6, 0.3), (-0.8, 1.9), (-1.3, 1.95), (-1.1, 0.3)], y: -0.02, thick: 0.1)
        k.sidePanels(x0: -1.4, x1: 1.4, y: 0.0, z: 0.37, count: 4)
        k.sensorNose(3.8, 0.0)
        k.antenna(-1.2, 0.36, 0.15, h: 0.45)
        k.weapon(m.weapon, hardpoints: [(0.6, -0.2, 1.05)], spine: (-1.0, 3.4, 0.5), belly: (-0.2, -0.45))
    }

    // Frachter wie im Vorbild: Kopfmodul, Containerreihen, schwere Triebwerke
    private static func atlas(_ k: ShipKit, _ m: ShipModel) {
        k.profile([(3.3, -0.25), (3.2, 0.35), (2.5, 0.75), (1.4, 0.85), (1.4, -0.6), (2.9, -0.6)], z: 0, thick: 1.5, chamfer: 0.12, mirror: false)
        k.canopy(2.45, 0.45, len: 1.1, height: 0.38, width: 1.0)
        k.box(0.4, 0.1, 0, 2.2, 1.3, 1.3, k.paint, chamfer: 0.1, mirror: false)
        k.box(-1.6, 0.1, 0, 1.6, 1.2, 1.5, k.dark, chamfer: 0.1, mirror: false)
        // Container
        for (i, x) in [1.0, 0.0, -0.95].enumerated() {
            let mat = i == 1 ? k.second : k.accent
            k.box(Float(x), 0.05, 0.98, 0.9, 0.85, 0.62, mat, chamfer: 0.06)
            k.box(Float(x), 0.05, 1.3, 0.75, 0.12, 0.04, k.metal)
        }
        k.box(0.5, 0.9, 0, 1.6, 0.4, 0.9, k.accent, chamfer: 0.06, mirror: false)
        k.box(-0.6, 0.85, 0, 0.6, 0.3, 0.6, k.second, chamfer: 0.05, mirror: false)
        k.engine(-2.3, 0.25, 1.05, r: 0.46, len: 1.4)
        k.fin(-1.8, 0.7, 0.55, height: 1.0, len: 0.9, tilt: -0.3)
        k.greeble(x0: -2.2, x1: -1.0, y: 0.7, zMax: 0.6, count: 8)
        k.lamp(3.2, -0.1, 0.45)
        k.lamp(1.5, 0.3, 0.76)
        k.plates(x0: -0.4, x1: 1.4, y: 0.75, width: 1.1, count: 3)
        k.belly(x0: -2.0, x1: 2.6, y: -0.7, width: 1.0)
        k.pipes(x0: -2.2, x1: 1.4, y: 0.55, z: 0.72)
        k.intake(2.6, -0.2, 0.62, h: 0.4, w: 0.3)
        k.sidePanels(x0: -2.2, x1: -0.9, y: 0.2, z: 0.78, count: 2)
        k.antenna(-1.4, 0.7, 0.4, h: 0.6)
        k.antenna(0.9, 1.1, 0.3, h: 0.4)
        k.weapon(m.weapon, hardpoints: [(2.3, -0.45, 0.55)], spine: (-1.6, 2.8, 1.15), belly: (0.2, -0.85))
    }

    // Panzerschiff: breiter Keil, Panzerplatten, Turm
    private static func bastion(_ k: ShipKit, _ m: ShipModel) {
        k.profile([(3.0, -0.1), (2.2, 0.45), (0.5, 0.65), (-2.3, 0.65), (-2.5, 0.2), (-2.5, -0.45), (2.4, -0.4)], z: 0, thick: 1.6, chamfer: 0.14, mirror: false)
        k.plate([(2.2, 0.8), (0.4, 1.9), (-2.2, 1.9), (-2.4, 0.8)], y: -0.05, thick: 0.45, k.paint, chamfer: 0.1)
        for x in [1.2, 0.2, -0.8, -1.8] as [Float] {
            k.box(x, 0.25, 1.55, 0.85, 0.22, 0.55, k.stripe, chamfer: 0.05, rot: SCNVector3(-0.3, 0, 0))
        }
        k.canopy(1.6, 0.55, len: 1.2, height: 0.32, width: 0.7)
        k.box(-0.4, 0.82, 0, 1.0, 0.32, 0.9, k.second, chamfer: 0.08, mirror: false)
        k.engine(-2.4, 0.15, 0.65, r: 0.42, len: 1.2)
        k.fin(-1.6, 0.65, 0.75, height: 0.8, len: 1.0, tilt: -0.2)
        k.greeble(x0: -2.2, x1: 0.6, y: 0.65, zMax: 0.7, count: 12)
        k.lamp(2.6, 0.0, 0.62)
        k.plates(x0: -2.0, x1: 0.8, y: 0.65, width: 1.2, count: 5)
        k.belly(x0: -2.0, x1: 2.2, y: -0.55, width: 1.1)
        k.pipes(x0: -2.2, x1: 1.0, y: 0.25, z: 0.82)
        k.intake(1.6, 0.2, 0.75, h: 0.35, w: 0.3)
        k.sidePanels(x0: -2.0, x1: 1.6, y: 0.3, z: 0.82, count: 5)
        k.sensorNose(3.0, -0.05)
        k.antenna(-1.8, 0.65, 0.5, h: 0.55)
        k.weapon(m.weapon, hardpoints: [(0.2, 1.0, 0.18), (1.9, -0.3, 1.35)], spine: (-1.6, 3.0, 1.1), belly: (-0.4, -0.8))
    }

    // Kreuzer: langer Rumpf, Brücke, Seitengondeln an Streben
    private static func orion(_ k: ShipKit, _ m: ShipModel) {
        k.profile([(3.9, 0.0), (2.8, 0.35), (-2.4, 0.4), (-2.7, 0.15), (-2.7, -0.3), (3.0, -0.25)], z: 0, thick: 0.9, mirror: false)
        k.box(-0.6, 0.62, 0, 1.4, 0.5, 0.6, k.stripe, chamfer: 0.08, mirror: false)
        k.canopy(-0.1, 0.85, len: 0.8, height: 0.26, width: 0.5)
        k.box(-1.0, 0.0, 1.0, 0.8, 0.14, 1.2, k.dark, chamfer: 0.03)
        k.engine(-1.1, 0.0, 1.7, r: 0.38, len: 3.0, k.accent)
        k.engine(-2.6, 0.05, 0, r: 0.4, len: 0.8, mirror: false)
        k.fin(-1.7, 0.4, 0.2, height: 0.9, len: 1.0, tilt: -0.15)
        k.greeble(x0: 0.4, x1: 2.6, y: 0.38, zMax: 0.3, count: 10)
        k.lamp(0.4, 0.0, 2.1)
        k.lamp(3.0, 0.1, 0.4)
        k.plates(x0: 0.2, x1: 2.8, y: 0.38, width: 0.7, count: 5)
        k.belly(x0: -2.2, x1: 2.6, y: -0.38, width: 0.6)
        k.pipes(x0: -2.4, x1: 2.4, y: 0.1, z: 0.48)
        k.sidePanels(x0: -2.2, x1: 2.4, y: 0.1, z: 0.47, count: 6)
        k.sensorNose(3.9, 0.0)
        k.antenna(-0.6, 0.87, 0.2, h: 0.6)
        k.weapon(m.weapon, hardpoints: [(1.5, 0.0, 1.7)], spine: (-0.4, 4.0, 0.62), belly: (0.5, -0.55))
    }

    // Abfangjäger: vorwärts gepfeilte Flügel, zwei enge Triebwerke
    private static func viper(_ k: ShipKit, _ m: ShipModel) {
        k.profile([(3.7, 0.0), (2.4, 0.26), (0.0, 0.42), (-2.1, 0.42), (-2.3, 0.1), (-2.3, -0.3), (2.6, -0.18)], z: 0, thick: 0.8, mirror: false)
        k.canopy(1.3, 0.38, len: 1.7, height: 0.38, width: 0.52)
        k.plate([(-0.9, 0.4), (0.7, 2.5), (0.2, 2.65), (-1.6, 0.4)], y: -0.02, thick: 0.12, k.stripe)
        k.plate([(0.2, 2.2), (0.7, 2.5), (0.2, 2.65), (-0.3, 2.3)], y: 0.0, thick: 0.16, k.accent)
        k.engine(-1.5, 0.18, 0.55, r: 0.34, len: 1.8)
        k.fin(-1.4, 0.48, 0.35, height: 1.0, len: 0.9, tilt: -0.5, k.accent)
        k.greeble(x0: -1.8, x1: 0.0, y: 0.42, zMax: 0.25, count: 8)
        k.lamp(0.6, 0.0, 2.45)
        k.plates(x0: -1.8, x1: 0.4, y: 0.42, width: 0.62, count: 4)
        k.belly(x0: -1.6, x1: 2.0, y: -0.36, width: 0.5)
        k.pipes(x0: -1.8, x1: 0.8, y: 0.1, z: 0.42)
        k.intake(0.6, 0.1, 0.45, h: 0.28, w: 0.22)
        k.wingDetail([(-0.9, 0.4), (0.7, 2.5), (0.2, 2.65), (-1.6, 0.4)], y: -0.02, thick: 0.12)
        k.sidePanels(x0: -1.6, x1: 1.8, y: 0.05, z: 0.42, count: 4)
        k.sensorNose(3.7, 0.0)
        k.antenna(-1.4, 0.42, 0.18, h: 0.45)
        k.weapon(m.weapon, hardpoints: [(0.9, -0.1, 2.3), (2.4, -0.2, 0.35)], spine: (-1.2, 3.4, 0.55), belly: (-0.2, -0.5))
    }

    // Schlachtschiff: massiv, drei Triebwerke, zwei Türme
    private static func titan(_ k: ShipKit, _ m: ShipModel) {
        k.profile([(3.4, -0.2), (2.8, 0.5), (1.0, 0.8), (-2.6, 0.8), (-2.8, 0.3), (-2.8, -0.6), (2.6, -0.6)], z: 0, thick: 2.0, chamfer: 0.15, mirror: false)
        k.plate([(2.0, 1.0), (0.6, 2.3), (-1.6, 2.4), (-2.6, 1.0)], y: -0.1, thick: 0.5, k.paint, chamfer: 0.12)
        for x in [1.0, -0.3, -1.6] as [Float] { k.box(x, 0.3, 1.75, 1.0, 0.3, 0.7, k.accent, chamfer: 0.05) }
        k.box(-1.2, 1.0, 0, 1.6, 0.4, 1.0, k.second, chamfer: 0.08, mirror: false)
        k.canopy(-1.0, 1.2, len: 0.9, height: 0.28, width: 0.6)
        for x in [1.6, 0.3] as [Float] {
            let base = SCNCylinder(radius: 0.38, height: 0.24)
            base.materials = [k.dark]
            let n = SCNNode(geometry: base)
            n.position = SCNVector3(x, 0.95, 0)
            k.root.addChildNode(n)
            for z in [-0.13, 0.13] as [Float] { k.tube(x + 0.55, 1.0, z, r: 0.05, len: 0.9, k.metal, mirror: false) }
        }
        k.engine(-2.75, 0.1, 0.9, r: 0.44, len: 1.1)
        k.engine(-2.85, 0.1, 0, r: 0.5, len: 1.1, mirror: false)
        k.fin(-2.0, 0.8, 1.0, height: 0.9, len: 1.0, tilt: -0.25)
        k.greeble(x0: -2.4, x1: 2.0, y: 0.8, zMax: 0.85, count: 16)
        k.lamp(3.0, 0.1, 0.8)
        k.lamp(0.0, 0.3, 2.2)
        k.plates(x0: -2.4, x1: 0.8, y: 0.8, width: 1.5, count: 6)
        k.belly(x0: -2.4, x1: 2.4, y: -0.75, width: 1.4)
        k.pipes(x0: -2.6, x1: 2.0, y: 0.35, z: 1.02)
        k.intake(2.2, 0.1, 0.9, h: 0.45, w: 0.32)
        k.sidePanels(x0: -2.4, x1: 2.2, y: 0.45, z: 1.02, count: 6)
        k.sensorNose(3.4, -0.1)
        k.antenna(-2.0, 0.8, 0.6, h: 0.7)
        k.antenna(1.0, 0.8, 0.5, h: 0.5)
        k.weapon(m.weapon, hardpoints: [(1.8, -0.2, 1.6)], spine: (-2.2, 3.0, 1.35), belly: (-0.2, -1.0))
    }

    // Tarnschiff: flacher Deltaflügel, rote Leuchtlinien
    private static func phantom(_ k: ShipKit, _ m: ShipModel) {
        k.plate([(3.4, 0.0), (-2.2, 2.9), (-1.5, 1.0), (-2.4, 0.0)], y: 0, thick: 0.34, k.paint, chamfer: 0.1, mirror: true)
        k.profile([(3.0, 0.0), (1.6, 0.3), (-1.8, 0.35), (-2.2, 0.0)], z: 0, thick: 0.9, chamfer: 0.1, mirror: false)
        k.canopy(1.2, 0.25, len: 1.5, height: 0.3, width: 0.5)
        let red = ShipKit.glow(UIColor(red: 1, green: 0.15, blue: 0.2, alpha: 1))
        k.plate([(2.6, 0.32), (-1.9, 2.6), (-2.0, 2.52), (2.4, 0.3)], y: 0.18, thick: 0.03, red, chamfer: 0)
        k.engine(-2.0, 0.05, 0.7, r: 0.3, len: 1.2, k.dark)
        k.fin(-1.5, 0.3, 1.6, height: 0.6, len: 0.8, tilt: -0.9, k.accent)
        k.greeble(x0: -1.6, x1: 0.2, y: 0.35, zMax: 0.3, count: 6)
        k.plates(x0: -1.6, x1: 1.0, y: 0.35, width: 0.6, count: 4)
        k.belly(x0: -1.6, x1: 1.6, y: -0.3, width: 0.5)
        k.wingDetail([(3.4, 0.0), (-2.2, 2.9), (-1.5, 1.0), (-2.4, 0.0)], y: 0, thick: 0.34)
        k.sensorNose(3.0, 0.0)
        k.weapon(m.weapon, hardpoints: [(1.0, -0.1, 1.0)], spine: (-1.2, 3.4, 0.5), belly: (-0.4, -0.45))
    }

    // Flaggschiff: elegant, Flügelspitzen-Triebwerke, goldene Akzente
    private static func nova(_ k: ShipKit, _ m: ShipModel) {
        k.profile([(4.0, 0.0), (2.6, 0.32), (0.4, 0.55), (-2.2, 0.5), (-2.6, 0.2), (-2.6, -0.32), (0.6, -0.4), (3.2, -0.15)], z: 0, thick: 1.0, mirror: false)
        k.canopy(1.4, 0.48, len: 1.9, height: 0.4, width: 0.62)
        k.plate([(1.0, 0.45), (-1.0, 2.4), (-1.9, 2.5), (-1.6, 0.45)], y: -0.02, thick: 0.13, k.stripe)
        k.engine(-1.4, 0.0, 2.5, r: 0.3, len: 1.6, k.accent)
        k.engine(-2.4, 0.15, 0.45, r: 0.36, len: 1.0)
        k.fin(-1.4, 0.5, 0.0, height: 1.2, len: 1.1, tilt: 0, k.accent)
        k.fin(-1.0, 0.0, 2.5, height: 0.6, len: 0.7, tilt: -0.3, k.second)
        k.greeble(x0: -1.8, x1: 0.4, y: 0.52, zMax: 0.3, count: 10)
        k.lamp(0.0, 0.0, 2.45)
        k.plates(x0: -1.9, x1: 0.6, y: 0.52, width: 0.75, count: 5)
        k.belly(x0: -1.8, x1: 2.2, y: -0.45, width: 0.6)
        k.pipes(x0: -2.2, x1: 0.8, y: 0.12, z: 0.52)
        k.intake(1.0, 0.1, 0.6, h: 0.3, w: 0.24)
        k.wingDetail([(1.0, 0.45), (-1.0, 2.4), (-1.9, 2.5), (-1.6, 0.45)], y: -0.02, thick: 0.13)
        k.sidePanels(x0: -1.8, x1: 1.8, y: 0.05, z: 0.52, count: 5)
        k.sensorNose(4.0, 0.0)
        k.antenna(-1.6, 0.52, 0.22, h: 0.5)
        k.weapon(m.weapon, hardpoints: [(1.2, -0.15, 1.3), (2.4, -0.2, 0.42)], spine: (-1.0, 3.6, 0.7), belly: (-0.3, -0.6))
    }
}
