import SwiftUI
import SceneKit
import UIKit
import simd

/// Bildrenderer für Texturen: ein Pixel pro Punkt. Ohne festes Format nimmt UIKit die Bildschirm-Skalierung
/// (3× auf aktuellen iPhones) und jede Textur bräuchte neunmal so viel Speicher.
/// `scale` nur dort erhöhen, wo feine Details (Sternenhimmel) sonst verwischen.
func textureRenderer(_ size: CGSize, scale: CGFloat = 1) -> UIGraphicsImageRenderer {
    let f = UIGraphicsImageRendererFormat()
    f.scale = scale
    return UIGraphicsImageRenderer(size: size, format: f)
}

// MARK: - Abgenutzter Lack

/// Prozedurale Lacktexturen im Stil „gebrauchtes Kriegsgerät“: Paneelnähte, abgeplatzte Farbe, Kratzer, Schmutz.
enum WornPaint {
    private static var cache: [String: SCNMaterial] = [:]
    private static var order: [String] = []
    /// Obergrenze für zwischengespeicherte Lacke (je Schiff etwa fünf), damit der Speicher nicht mit jedem Schiff wächst
    private static let cacheLimit = 24

    /// Wrack-Modelle entstehen im Hintergrund, der Zwischenspeicher wird deshalb abgesichert
    private static let lock = NSRecursiveLock()

    static func material(_ key: String, base: UIColor, stripe: UIColor? = nil, marking: String? = nil) -> SCNMaterial {
        lock.lock()
        defer { lock.unlock() }
        let id = "\(key)-\(marking ?? "")"
        order.removeAll { $0 == id }
        order.append(id)
        while order.count > cacheLimit { cache[order.removeFirst()] = nil }
        if let m = cache[id] { return m }
        // Kennungen würden sich beim Kacheln überall wiederholen, deshalb ohne Beschriftung
        let (albedo, height, rough, metal) = textures(seed: id, base: base, stripe: stripe, marking: nil)
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        // Fallback, falls der Shader nicht greift
        m.diffuse.contents = albedo
        m.roughness.contents = 0.7
        m.metalness.contents = 0.1
        // Texturen werden dreiachsig im Modellraum projiziert: gleiche Detaildichte auf jedem Bauteil,
        // egal wie groß oder klein es ist. Nähte und Kanten kommen als Relief über die Höhenkarte.
        m.shaderModifiers = [.surface: triplanar]
        m.setValue(SCNMaterialProperty(contents: albedo), forKey: "tpAlbedo")
        // Rauheit, Metall und Höhe teilen sich eine Textur (R, G, B)
        m.setValue(SCNMaterialProperty(contents: pack(rough, metal, height)), forKey: "tpMask")
        m.setValue(NSNumber(value: 1.0 / 2.0), forKey: "tpScale")
        m.setValue(NSNumber(value: 0.02), forKey: "tpBump")
        cache[id] = m
        return m
    }

    /// Bei Speicherwarnung: Zwischenspeicher leeren. Lacke, die gerade auf einem Modell sitzen, bleiben dort erhalten.
    static func purge() {
        lock.lock()
        defer { lock.unlock() }
        cache.removeAll()
        order.removeAll()
    }

    /// Dreiachsige Projektion (Triplanar) im Modellraum plus Relief aus der Höhenkarte über Bildschirm-Ableitungen.
    static let triplanar = """
    #pragma arguments
    texture2d<float> tpAlbedo;
    texture2d<float> tpMask;
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
    float3 tpK = tpMask.sample(tpS, tpUX).rgb * tpW.x + tpMask.sample(tpS, tpUY).rgb * tpW.y + tpMask.sample(tpS, tpUZ).rgb * tpW.z;
    float tpR = tpK.r;
    float tpM = tpK.g;
    float tpH = tpK.b;
    _surface.diffuse = float4(tpA.rgb, 1.0);
    _surface.roughness = tpR;
    _surface.metalness = tpM;
    // Kantenabrieb: wo die Normale sich schnell dreht (Fasen, Rundungen), Lack aufhellen
    // und stellenweise bis aufs blanke Metall abplatzen lassen
    float tpEdge = saturate((length(fwidth(tpN)) - 0.03) * 5.0);
    float2 tpUW = (tpUX * tpW.x + tpUY * tpW.y + tpUZ * tpW.z) * 2.7;
    float tpChip = smoothstep(0.4, 0.7, tpMask.sample(tpS, tpUW).g + tpMask.sample(tpS, tpUW * 0.37 + 0.5).g);
    _surface.diffuse.rgb = mix(_surface.diffuse.rgb, _surface.diffuse.rgb * 1.18 + 0.03, tpEdge * 0.6);
    float tpBare = tpEdge * tpChip;
    _surface.diffuse.rgb = mix(_surface.diffuse.rgb, float3(0.42, 0.41, 0.39), tpBare);
    _surface.metalness = mix(_surface.metalness, 0.85, tpBare);
    _surface.roughness = mix(_surface.roughness, 0.38, tpBare);
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

    /// Drei Graustufenbilder in die Kanäle R, G, B eines Bildes legen
    private static func pack(_ r: UIImage, _ g: UIImage, _ b: UIImage) -> UIImage {
        let n = 512
        func gray(_ img: UIImage) -> [UInt8] {
            var px = [UInt8](repeating: 0, count: n * n)
            if let cg = img.cgImage,
               let ctx = CGContext(data: &px, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n,
                                   space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) {
                ctx.draw(cg, in: CGRect(x: 0, y: 0, width: n, height: n))
            }
            return px
        }
        let cr = gray(r), cg = gray(g), cb = gray(b)
        var out = [UInt8](repeating: 255, count: n * n * 4)
        for i in 0..<(n * n) {
            out[i * 4] = cr[i]
            out[i * 4 + 1] = cg[i]
            out[i * 4 + 2] = cb[i]
        }
        let provider = CGDataProvider(data: Data(out) as CFData)!
        let image = CGImage(width: n, height: n, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: n * 4,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                            provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)!
        return UIImage(cgImage: image)
    }

    /// liefert (Farbe, Höhe, Rauheit, Metall)
    private static func textures(seed: String, base: UIColor, stripe: UIColor?, marking: String?) -> (UIImage, UIImage, UIImage, UIImage) {
        var rng = SeededRNG(seed)
        let s: CGFloat = 512

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
        // Abplatzer in kleinen Gruppen entlang von Paneelkanten und Lukenrändern, wo Lack wirklich abgeht
        struct Chip { let path: UIBezierPath; let deep: Bool }
        var chips: [Chip] = []
        var anchors: [CGPoint] = []
        for (p, q) in seams {
            for _ in 0..<4 {
                let t = rng.c(0...1)
                anchors.append(CGPoint(x: p.x + (q.x - p.x) * t, y: p.y + (q.y - p.y) * t))
            }
        }
        for h in hatches {
            anchors.append(CGPoint(x: rng.chance(0.5) ? h.minX : h.maxX, y: rng.c(h.minY...h.maxY)))
            anchors.append(CGPoint(x: rng.c(h.minX...h.maxX), y: rng.chance(0.5) ? h.minY : h.maxY))
        }
        for _ in 0..<6 {
            anchors.append(rng.chance(0.5) ? CGPoint(x: rng.chance(0.5) ? 10 : s - 10, y: rng.c(0...s))
                                           : CGPoint(x: rng.c(0...s), y: rng.chance(0.5) ? 10 : s - 10))
        }
        for a in anchors {
            for _ in 0..<Int(rng.d(2...6)) {
                let x = a.x + rng.c(-14...14), y = a.y + rng.c(-8...8)
                let r = rng.c(1.5...7)
                let p = UIBezierPath()
                let n = 7
                for k in 0..<n {
                    let ang = CGFloat(k) / CGFloat(n) * .pi * 2
                    let rr = r * rng.c(0.35...1.3)
                    let pt = CGPoint(x: x + cos(ang) * rr * rng.c(0.8...1.9), y: y + sin(ang) * rr)
                    if k == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
                }
                p.close()
                chips.append(Chip(path: p, deep: rng.chance(0.45)))
            }
        }
        let stencils = ["NO STEP", "A-17", "▲ 04", "VENT", "07", "HX-2", "⚠", "PWR"]

        let albedo = textureRenderer(CGSize(width: s, height: s)).image { ctx in
            let g = ctx.cgContext
            base.setFill()
            g.fill(CGRect(x: 0, y: 0, width: s, height: s))
            // ungleichmäßig ausgeblichener Lack: große, weiche Flecken statt Rauschen
            for _ in 0..<26 {
                let r = rng.c(40...120)
                let c = CGPoint(x: rng.c(0...s), y: rng.c(0...s))
                let tone = rng.chance(0.5) ? UIColor.white : UIColor.black
                let fade = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                      colors: [tone.withAlphaComponent(rng.c(0.04...0.08)).cgColor, tone.withAlphaComponent(0).cgColor] as CFArray,
                                      locations: [0, 1])!
                g.drawRadialGradient(fade, startCenter: c, startRadius: 0, endCenter: c, endRadius: r, options: [])
            }
            if let stripe {
                stripe.setFill()
                // senkrechtes Band, damit es beim Kacheln nahtlos weiterläuft
                g.fill(CGRect(x: s * 0.3, y: 0, width: s * 0.3, height: s))
            }
            // Schmutz sammelt sich in den Fugen und läuft unter Luken in Schlieren ab
            g.setStrokeColor(UIColor(red: 0.16, green: 0.12, blue: 0.08, alpha: 0.18).cgColor)
            g.setLineWidth(12)
            for (a, b) in seams { g.move(to: a); g.addLine(to: b) }
            g.strokePath()
            for h in hatches where rng.chance(0.7) {
                let len = rng.c(30...110)
                let streak = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                        colors: [UIColor(red: 0.16, green: 0.12, blue: 0.08, alpha: 0.22).cgColor,
                                                 UIColor(red: 0.16, green: 0.12, blue: 0.08, alpha: 0).cgColor] as CFArray,
                                        locations: [0, 1])!
                g.saveGState()
                g.clip(to: CGRect(x: h.minX + 4, y: h.maxY, width: h.width - 8, height: len))
                g.drawLinearGradient(streak, start: CGPoint(x: 0, y: h.maxY), end: CGPoint(x: 0, y: h.maxY + len), options: [])
                g.restoreGState()
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
            // Kratzer: lange, meist waagerechte Riefen, hell wie blankes Metall
            g.setLineWidth(0.8)
            for _ in 0..<55 {
                let x = rng.c(0...s), y = rng.c(0...s), l = rng.c(20...120)
                g.setStrokeColor(UIColor(white: 0.85, alpha: rng.c(0.12...0.3)).cgColor)
                g.move(to: CGPoint(x: x, y: y))
                g.addLine(to: CGPoint(x: x + l, y: y + rng.c(-6...6)))
                g.strokePath()
            }
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
            textureRenderer(CGSize(width: s, height: s)).image { ctx in
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
    /// Zielknoten für neue Teile (für gedrehte Baugruppen wie Geschütztürme kurz umschaltbar)
    private(set) var root = SCNNode()
    fileprivate func withRoot(_ n: SCNNode, _ body: () -> Void) {
        let old = root
        root = n
        body()
        root = old
    }
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
    private var twoSided: [ObjectIdentifier: SCNMaterial] = [:]

    init(seed: String, base: UIColor, accent accentColor: UIColor, second secondColor: UIColor, weaponHue: Double, marking: String,
         engine: UIColor = UIColor(red: 1, green: 0.5, blue: 0.12, alpha: 1)) {
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
        fire = ShipKit.glow(engine)
        fire.name = "engineFire"   // Düsenglut: World3D schaltet sie aus, wenn die Triebwerke aus sind
        weaponGlow = ShipKit.glow(UIColor(hsl(weaponHue, 0.9, 0.6)))
        weaponGlow.name = "weaponGlow"   // Leuchtringe der Waffe: erlöschen am Spielende wie die Düsenglut
    }

    static func glow(_ c: UIColor) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = c
        m.emission.contents = c
        return m
    }

    func addNode(_ g: SCNGeometry, _ m: SCNMaterial, _ p: SCNVector3, rot: SCNVector3 = SCNVector3(0, 0, 0)) {
        add(g, m, p, rot: rot, mirror: false)
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

    /// Querschnitt eines facettierten Rumpfs: Position x, Mittelhöhe y, halbe Breite w, halbe Höhe h
    struct Sec {
        let x: Float, y: Float, w: Float, h: Float
        init(_ x: Float, _ y: Float, _ w: Float, _ h: Float) { self.x = x; self.y = y; self.w = w; self.h = h }
    }

    /// Facettierter Rumpf: achteckige Querschnitte entlang x, flach schattiert wie gekantetes Blech.
    /// top/bottom = Breite der Ober-/Unterseite relativ zu w, shoulder = Höhe der Seitenkante relativ zu h.
    func hull(_ secs: [Sec], z: Float = 0, top: Float = 0.55, bottom: Float = 0.7, shoulder: Float = 0.25,
              _ m: SCNMaterial? = nil, mirror: Bool = true) {
        func ring(_ c: Sec) -> [SIMD3<Float>] {
            let o: [(Float, Float)] = [(top, 1), (1, shoulder), (1, -shoulder), (bottom, -1),
                                       (-bottom, -1), (-1, -shoulder), (-1, shoulder), (-top, 1)]
            return o.map { SIMD3(c.x, c.y + $0.1 * c.h, $0.0 * c.w) }
        }
        var pos: [SCNVector3] = [], nor: [SCNVector3] = []
        func face(_ pts: [SIMD3<Float>], outward: SIMD3<Float>) {
            guard pts.count >= 3 else { return }
            var n = SIMD3<Float>(0, 0, 0)
            for i in 1..<(pts.count - 1) { n += cross(pts[i] - pts[0], pts[i + 1] - pts[0]) }
            guard simd_length(n) > 1e-7 else { return }
            let flip = dot(n, outward) < 0
            let nn = simd_normalize(flip ? -n : n)
            for i in 1..<(pts.count - 1) {
                let tri = flip ? [pts[0], pts[i + 1], pts[i]] : [pts[0], pts[i], pts[i + 1]]
                for v in tri {
                    pos.append(SCNVector3(v.x, v.y, v.z))
                    nor.append(SCNVector3(nn.x, nn.y, nn.z))
                }
            }
        }
        let rings = secs.map(ring)
        for i in 0..<(rings.count - 1) {
            let a = rings[i], b = rings[i + 1]
            let axis = SIMD3<Float>((secs[i].x + secs[i + 1].x) / 2, (secs[i].y + secs[i + 1].y) / 2, 0)
            for k in 0..<a.count {
                let k1 = (k + 1) % a.count
                let quad = [a[k], a[k1], b[k1], b[k]]
                let mid = quad.reduce(SIMD3<Float>(0, 0, 0), +) / 4
                face(quad, outward: mid - axis)
            }
        }
        let dir = SIMD3<Float>(secs.last!.x > secs[0].x ? 1 : -1, 0, 0)
        face(rings[0], outward: -dir)
        face(rings[rings.count - 1], outward: dir)
        let idx = (0..<Int32(pos.count)).map { $0 }
        // Texturkoordinaten braucht die Render-Pipeline, auch wenn der Lack-Shader dreiachsig projiziert
        let uv = pos.map { CGPoint(x: CGFloat($0.x) / 2, y: CGFloat($0.y + $0.z) / 2) }
        let g = SCNGeometry(sources: [SCNGeometrySource(vertices: pos), SCNGeometrySource(normals: nor),
                                      SCNGeometrySource(textureCoordinates: uv)],
                            elements: [SCNGeometryElement(indices: idx, primitiveType: .triangles)])
        add(g, m ?? paint, SCNVector3(0, 0, z), mirror: mirror)
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
        // glühende Lüftungsschlitze an der Außenseite (Glut-Material: kühlen mit den Triebwerken ab)
        let outer: Float = z >= 0 ? 1 : -1
        for k in 0..<3 {
            box(x - 0.1 + Float(k) * 0.22, y, z + outer * Float(r * 1.0), 0.12, 0.04, 0.04, fire, chamfer: 0.01, mirror: mirror)
        }
        // offene Düse: Glut sitzt vertieft im Rohr, davor ein dunkler Innenring
        let nozzle = SCNTube(innerRadius: r * 0.74, outerRadius: r * 0.92, height: 0.3)
        nozzle.radialSegmentCount = 24
        add(nozzle, metal, SCNVector3(x - half - 0.12, y, z), rot: SCNVector3(0, 0, -Float.pi / 2), mirror: mirror)
        let liner = SCNTube(innerRadius: r * 0.6, outerRadius: r * 0.74, height: 0.22)
        liner.radialSegmentCount = 24
        add(liner, dark, SCNVector3(x - half - 0.08, y, z), rot: SCNVector3(0, 0, -Float.pi / 2), mirror: mirror)
        tube(x - half - 0.02, y, z, r: r * 0.62, len: 0.02, fire, mirror: mirror)
        let ring = SCNTorus(ringRadius: r * 0.66, pipeRadius: 0.02)
        add(ring, fire, SCNVector3(x - half - 0.18, y, z), rot: SCNVector3(0, 0, Float.pi / 2), mirror: mirror)
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
    func canopy(_ x: Float, _ y: Float, z: Float = 0, len: CGFloat, height: CGFloat, width: CGFloat) {
        let l = len, h = height
        profile([(l * 0.55, 0), (l * 0.1, h), (-l * 0.35, h * 0.85), (-l * 0.5, 0)].map { ($0.0 + CGFloat(x), $0.1 + CGFloat(y)) },
                z: z, thick: width, glass, chamfer: width * 0.4, mirror: false)
        for t in [-0.3, -0.05, 0.2] as [CGFloat] {
            box(x + Float(l * t), y + Float(h * (0.82 - abs(t) * 0.6)), z, 0.05, 0.07, width * 1.03, metal, mirror: false)
        }
        box(x - Float(l * 0.05), y + Float(h * 0.9), z, l * 0.75, 0.05, 0.05, metal, mirror: false)
        box(x - Float(l * 0.05), y + 0.02, z, l * 1.05, 0.08, width * 1.12, dark, chamfer: 0.03, mirror: false)
    }

    /// Weich gerundeter Rumpf: Querschnitte als Superellipsen entlang x, glatt schattiert (kein gekantetes Blech).
    /// round = 2 ergibt Ellipsen, größere Werte werden kastiger mit runden Ecken.
    func smoothHull(_ secs: [Sec], z: Float = 0, round: Float = 2.4, segments: Int = 28,
                    _ m: SCNMaterial? = nil, mirror: Bool = true) {
        guard secs.count >= 2 else { return }
        let n = segments
        let e = 2 / round
        func pt(_ c: Sec, _ k: Int) -> SIMD3<Float> {
            let a = Float(k) / Float(n) * 2 * .pi
            let cs = cos(a), sn = sin(a)
            let pz = (cs < 0 ? -1 : 1) * pow(abs(cs), e) * c.w
            let py = (sn < 0 ? -1 : 1) * pow(abs(sn), e) * c.h
            return SIMD3(c.x, c.y + py, pz)
        }
        let rows = secs.count
        var grid: [[SIMD3<Float>]] = secs.map { c in (0..<n).map { pt(c, $0) } }
        var pos: [SCNVector3] = [], nor: [SCNVector3] = []
        var idx: [Int32] = []
        let dirX: Float = secs[rows - 1].x > secs[0].x ? 1 : -1
        for i in 0..<rows {
            for k in 0..<n {
                let p = grid[i][k]
                let ring = grid[i][(k + 1) % n] - grid[i][(k + n - 1) % n]
                let along = grid[min(rows - 1, i + 1)][k] - grid[max(0, i - 1)][k]
                var nn = cross(along, ring) * dirX
                // nach außen richten
                let out = SIMD3<Float>(0, p.y - secs[i].y, p.z)
                if dot(nn, out) < 0 { nn = -nn }
                let len = simd_length(nn)
                nn = len > 1e-6 ? nn / len : (simd_length(out) > 1e-6 ? simd_normalize(out) : SIMD3(0, 1, 0))
                pos.append(SCNVector3(p.x, p.y, p.z))
                nor.append(SCNVector3(nn.x, nn.y, nn.z))
            }
        }
        for i in 0..<(rows - 1) {
            for k in 0..<n {
                let a = Int32(i * n + k), b = Int32(i * n + (k + 1) % n)
                let c = Int32((i + 1) * n + k), d = Int32((i + 1) * n + (k + 1) % n)
                idx += [a, b, c, b, d, c]
            }
        }
        // Endkappen als Fächer
        for (row, sign) in [(0, -dirX), (rows - 1, dirX)] {
            let center = Int32(pos.count)
            pos.append(SCNVector3(secs[row].x, secs[row].y, 0))
            nor.append(SCNVector3(sign, 0, 0))
            for k in 0..<n {
                idx += [center, Int32(row * n + k), Int32(row * n + (k + 1) % n)]
            }
        }
        grid.removeAll()
        let uv = pos.map { CGPoint(x: CGFloat($0.x) / 2, y: CGFloat($0.y + $0.z) / 2) }
        let g = SCNGeometry(sources: [SCNGeometrySource(vertices: pos), SCNGeometrySource(normals: nor),
                                      SCNGeometrySource(textureCoordinates: uv)],
                            elements: [SCNGeometryElement(indices: idx, primitiveType: .triangles)])
        // beidseitig: Dreiecksrichtung ist egal, die Normalen zeigen nach außen (je Lack nur eine Kopie)
        let src = m ?? paint
        let mat: SCNMaterial
        if let c = twoSided[ObjectIdentifier(src)] { mat = c } else {
            let c = src.copy() as! SCNMaterial
            c.isDoubleSided = true
            twoSided[ObjectIdentifier(src)] = c
            mat = c
        }
        add(g, mat, SCNVector3(0, 0, z), mirror: mirror)
    }

    /// Tropfenförmige Glaskanzel, weich in den Rumpf eingelassen
    func bubble(_ x: Float, _ y: Float, z: Float = 0, len: Float, height: Float, width: Float) {
        var secs: [Sec] = []
        for i in 0...8 {
            let t = Float(i) / 8
            // vorn spitzer, hinten lang auslaufend
            let r = pow(sin(.pi * pow(t, 0.75)), 0.7)
            secs.append(Sec(x + len * (0.45 - t), y, max(0.01, width / 2 * r), max(0.01, height * r)))
        }
        smoothHull(secs, z: z, round: 2, segments: 20, glass, mirror: false)
        // schmaler Rahmenring um den Fuß der Kanzel
        smoothHull([Sec(x + len * 0.47, y - height * 0.15, width * 0.3, 0.03), Sec(x, y - height * 0.15, width * 0.56, 0.05),
                    Sec(x - len * 0.57, y - height * 0.15, width * 0.3, 0.03)], z: z, round: 2, segments: 16, dark, mirror: false)
    }

    /// Geschwungener Flügel: Draufsicht mit gebogener Vorderkante und runder Spitze.
    /// rootLead/rootTrail = x an der Wurzel, tip = (x, z) der Spitze, sweep biegt die Vorderkante.
    func wing(rootLead: CGFloat, rootTrail: CGFloat, rootZ: CGFloat, tip: (CGFloat, CGFloat), tipChord: CGFloat,
              bulge: CGFloat = 0.35, y: Float, thick: CGFloat, _ m: SCNMaterial? = nil) -> [(CGFloat, CGFloat)] {
        var pts: [(CGFloat, CGFloat)] = []
        func bez(_ a: (CGFloat, CGFloat), _ c: (CGFloat, CGFloat), _ b: (CGFloat, CGFloat), _ steps: Int, skipFirst: Bool) {
            for i in (skipFirst ? 1 : 0)...steps {
                let t = CGFloat(i) / CGFloat(steps), u = 1 - t
                pts.append((u * u * a.0 + 2 * u * t * c.0 + t * t * b.0, u * u * a.1 + 2 * u * t * c.1 + t * t * b.1))
            }
        }
        let a = (rootLead, rootZ), tl = (tip.0 + tipChord / 2, tip.1), tt = (tip.0 - tipChord / 2, tip.1), b = (rootTrail, rootZ)
        let span = tip.1 - rootZ
        // Vorderkante nach außen gewölbt
        bez(a, ((a.0 + tl.0) / 2 + bulge * abs(a.0 - tl.0), (a.1 + tl.1) / 2 + span * 0.12), tl, 8, skipFirst: false)
        // runde Spitze
        bez(tl, (tip.0, tip.1 + tipChord * 0.45), tt, 5, skipFirst: true)
        // Hinterkante leicht eingezogen
        bez(tt, ((tt.0 + b.0) / 2 + 0.12 * abs(tt.0 - b.0), (tt.1 + b.1) / 2 - span * 0.05), b, 6, skipFirst: true)
        plate(pts, y: y, thick: thick, m ?? stripe, chamfer: thick * 0.45)
        return pts
    }

    /// Triebwerksgondel mit weich gerundeter Verkleidung vor der Düse
    @discardableResult
    func nacelle(_ x: Float, _ y: Float, _ z: Float, r: Float, len: Float, _ m: SCNMaterial? = nil, mirror: Bool = true) -> Float {
        let front = x + len / 2
        smoothHull([Sec(front + r * 1.6, y, r * 0.12, r * 0.12), Sec(front + r * 0.9, y, r * 0.75, r * 0.75),
                    Sec(front, y, r * 1.12, r * 1.12), Sec(x, y, r * 1.18, r * 1.18), Sec(x - len * 0.35, y, r * 1.08, r * 1.08)],
                   z: z, round: 2, segments: 24, m ?? paint, mirror: mirror)
        // Leuchtring um die Gondel
        let ring = SCNTorus(ringRadius: CGFloat(r) * 1.2, pipeRadius: 0.025)
        add(ring, fire, SCNVector3(x + len * 0.12, y, z), rot: SCNVector3(0, 0, Float.pi / 2), mirror: mirror)
        return engine(x - len * 0.2, y, z, r: CGFloat(r), len: CGFloat(len) * 0.6, m, mirror: mirror)
    }

    /// Kanone: gerundetes Gehäuse, Lauf im geschlitzten Kühlmantel, Mündungsbremse mit schmalem Leuchtspalt
    func cannon(_ x: Float, _ y: Float, _ z: Float, len: CGFloat, r: CGFloat = 0.07) {
        let l = Float(len), rf = Float(r)
        let back = x - l / 2
        // Gehäuse (Verschluss) als weiche Kapsel
        smoothHull([Sec(back - l * 0.1, y, rf * 0.8, rf * 0.8), Sec(back, y, rf * 2.3, rf * 2.3), Sec(back + l * 0.22, y, rf * 2.5, rf * 2.5),
                    Sec(back + l * 0.36, y, rf * 1.5, rf * 1.5)], z: z, round: 2.6, segments: 16, second)
        // Lauf
        tube(x + l * 0.1, y, z, r: r, len: len * 0.8, metal)
        // Kühlmantel mit Rippen
        tube(back + l * 0.52, y, z, r: r * 1.5, len: len * 0.3, dark)
        for k in 0..<5 {
            tube(back + l * (0.4 + 0.06 * Float(k)), y, z, r: r * 1.8, len: 0.03, metal)
        }
        // Mündungsbremse: zwei Scheiben, dazwischen ein schmaler Leuchtspalt
        tube(x + l / 2 - 0.17, y, z, r: r * 1.65, len: 0.07, dark)
        tube(x + l / 2 - 0.05, y, z, r: r * 1.65, len: 0.07, dark)
        tube(x + l / 2 - 0.11, y, z, r: r * 1.2, len: 0.05, weaponGlow)
        tube(x + l / 2 - 0.005, y, z, r: r * 0.6, len: 0.02, weaponGlow)
    }

    /// Raketenwerfer: kantig-runder Behälter am Pylon, vorn ragen sechs Raketenspitzen heraus
    func rocketPod(_ x: Float, _ y: Float, _ z: Float) {
        box(x - 0.05, y + 0.27, z, 0.6, 0.22, 0.07, dark, chamfer: 0.03)
        smoothHull([Sec(x - 0.8, y, 0.06, 0.06), Sec(x - 0.5, y, 0.27, 0.24), Sec(x + 0.35, y, 0.31, 0.27), Sec(x + 0.45, y, 0.31, 0.27)],
                   z: z, round: 3.4, segments: 20, second)
        box(x + 0.46, y, z, 0.04, 0.48, 0.56, dark, chamfer: 0.02)
        box(x - 0.1, y, z, 0.1, 0.57, 0.65, metal, chamfer: 0.02)
        for row in [-0.11, 0.11] as [Float] {
            for col in [-0.18, 0, 0.18] as [Float] {
                tube(x + 0.52, y + row, z + col, r: 0.07, len: 0.12, metal)
                tube(x + 0.585, y + row, z + col, r: 0.072, len: 0.025, weaponGlow)
                let tip = SCNCone(topRadius: 0, bottomRadius: 0.07, height: 0.18)
                add(tip, accent, SCNVector3(x + 0.685, y + row, z + col), rot: SCNVector3(0, 0, -Float.pi / 2), mirror: true)
            }
        }
    }

    /// Schienenkanone: zwei kantige Schienen, dazwischen die Energiebahn, gehalten von Klammern
    func railgun(_ x0: Float, _ x1: Float, _ y: Float) {
        let len = CGFloat(x1 - x0)
        let cx = (x0 + x1) / 2
        for z in [-0.15, 0.15] as [Float] {
            box(cx, y, z, len, 0.15, 0.1, metal, chamfer: 0.03, mirror: false)
            box(x1 - 0.14, y, z, 0.28, 0.2, 0.13, dark, chamfer: 0.03, mirror: false)
        }
        box(cx, y, 0, len * 0.97, 0.05, 0.2, weaponGlow, chamfer: 0, mirror: false)
        // Kondensatorblock am Fuß der Schienen
        smoothHull([Sec(x0 - 0.25, y, 0.14, 0.1), Sec(x0 + 0.1, y, 0.38, 0.22), Sec(x0 + 0.7, y, 0.34, 0.2), Sec(x0 + 0.95, y, 0.2, 0.12)],
                   round: 2.8, segments: 16, second, mirror: false)
        var x = x0 + 1.4
        while x < x1 - 0.4 {
            box(x, y, 0, 0.16, 0.26, 0.5, dark, chamfer: 0.04, mirror: false)
            box(x, y + 0.14, 0, 0.08, 0.03, 0.3, weaponGlow, chamfer: 0, mirror: false)
            x += 0.75
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

    /// Geschützturm: Sockel mit Drehkranz, gerundete Panzerkuppel, Panzerblende und Zwillingsrohre mit Mündungsbremsen.
    /// yaw dreht den Turm (0 = nach vorn), down = true hängt ihn unter den Rumpf.
    func turret(_ x: Float, _ y: Float, z: Float = 0, r: Float = 0.42, yaw: Float = 0, down: Bool = false) {
        let up: Float = down ? -1 : 1
        let holder = SCNNode()
        holder.name = "turret"
        holder.position = SCNVector3(x, y, z)
        holder.eulerAngles.y = yaw
        root.addChildNode(holder)
        let cr = CGFloat(r)
        let h = r * 0.55
        let len = r * 3.0
        ShipKitPart(kit: self, node: holder).build { k in
            let base = SCNCylinder(radius: cr * 1.25, height: 0.12)
            base.radialSegmentCount = 28
            k.addNode(base, k.dark, SCNVector3(0, 0, 0))
            let collar = SCNCylinder(radius: cr * 1.05, height: 0.1)
            collar.radialSegmentCount = 28
            k.addNode(collar, k.metal, SCNVector3(0, 0.1 * up, 0))
            let cy = (0.12 + h * 0.6) * up
            k.smoothHull([Sec(r * 1.0, cy, r * 0.45, h * 0.45), Sec(r * 0.55, cy, r * 0.85, h * 0.85), Sec(-r * 0.35, cy, r * 0.95, h),
                          Sec(-r * 1.05, cy, r * 0.55, h * 0.5)], round: 2.6, segments: 20, k.paint, mirror: false)
            // Panzerblende vor der Kuppel
            k.box(r * 0.95, cy, 0, 0.16, cr * 0.7, cr * 1.5, k.second, chamfer: 0.04, mirror: false)
            for bz in [-r * 0.38, r * 0.38] {
                k.tube(r + len * 0.18, cy, bz, r: cr * 0.2, len: CGFloat(len) * 0.36, k.dark, mirror: false)
                k.tube(r + len * 0.5, cy, bz, r: cr * 0.12, len: CGFloat(len), k.metal, mirror: false)
                k.tube(r + len * 0.93, cy, bz, r: cr * 0.19, len: CGFloat(len) * 0.1, k.dark, mirror: false)
                k.tube(r + len + 0.005, cy, bz, r: cr * 0.08, len: 0.02, k.lamp, mirror: false)
            }
            // Zielgerät auf der Kuppel
            k.box(-r * 0.3, cy + h * 1.05 * up, r * 0.4, 0.14, 0.08, 0.12, k.dark, chamfer: 0.02, mirror: false)
            k.box(-r * 0.22, cy + h * 1.05 * up, r * 0.4, 0.03, 0.05, 0.08, k.lamp, chamfer: 0.01, mirror: false)
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

/// baut Teile in einen Unterknoten des Bausatzes
struct ShipKitPart {
    let kit: ShipKit
    let node: SCNNode
    func build(_ body: (ShipKit) -> Void) {
        kit.withRoot(node) { body(kit) }
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
    static let navy = c(205, 0.12, 0.4)
    static let gold = c(44, 0.6, 0.55)
    static let night = c(262, 0.12, 0.17)

    static func build(_ m: ShipModel) -> SCNNode {
        let k: ShipKit
        switch m.id {
        case "libelle": k = kit(m, bone, orange, gunmetal, "LB"); libelle(k, m)
        case "atlas": k = kit(m, bone, olive, orange, "AT"); atlas(k, m)
        case "bastion": k = kit(m, olive, bone, gunmetal, "BS"); bastion(k, m)
        case "orion": k = kit(m, bone, navy, gunmetal, "OR"); orion(k, m)
        case "viper": k = kit(m, red, bone, gunmetal, "VP"); viper(k, m)   // rot lackiert, damit sie sich vom Falken abhebt
        case "titan": k = kit(m, gunmetal, olive, orange, "TT"); titan(k, m)
        case "phantom": k = kit(m, night, red, gunmetal, "PH"); phantom(k, m)
        case "nova": k = kit(m, bone, gold, navy, "NV"); nova(k, m)
        default: k = kit(m, bone, red, gunmetal, "FK"); falke(k, m)
        }
        return k.root
    }

    /// Piratenschiffe: bekannte Rümpfe in dunklem Lack mit roten Akzenten (0 Jäger, 1 Kanonenboot, 2 Anführer)
    static func pirate(_ variant: Int) -> SCNNode {
        let id: String
        let base: UIColor, acc: UIColor, sec: UIColor
        switch variant {
        case 1: id = "bastion"; base = gunmetal; acc = red; sec = night
        case 2: id = "titan"; base = night; acc = red; sec = gold
        default: id = "viper"; base = night; acc = red; sec = gunmetal
        }
        let m = ShipModel.with(id: id) ?? ShipModel.all[0]
        let k = ShipKit(seed: "pirate\(variant)", base: base, accent: acc, second: sec, weaponHue: WeaponKind.cannon.hue, marking: "PX")
        switch variant {
        case 1: bastion(k, m)
        case 2: titan(k, m)
        default: viper(k, m)
        }
        return k.root
    }

    private static func kit(_ m: ShipModel, _ base: UIColor, _ acc: UIColor, _ sec: UIColor, _ code: String) -> ShipKit {
        ShipKit(seed: m.id, base: base, accent: acc, second: sec, weaponHue: m.weapon.hue, marking: code, engine: m.role.engineColor)
    }

    // Jäger: weich gezogener Rumpf mit Tropfenkanzel, geschwungene Pfeilflügel, zwei Gondeln, zwei Leitwerke
    private static func falke(_ k: ShipKit, _ m: ShipModel) {
        typealias S = ShipKit.Sec
        k.smoothHull([S(3.7, -0.02, 0.02, 0.02), S(3.2, 0.0, 0.14, 0.1), S(2.3, 0.05, 0.33, 0.23), S(1.0, 0.12, 0.5, 0.36),
                      S(-0.4, 0.15, 0.54, 0.4), S(-1.6, 0.14, 0.46, 0.33), S(-2.3, 0.12, 0.3, 0.22), S(-2.55, 0.12, 0.12, 0.1)],
                     round: 2.5, mirror: false)
        // Rückenwulst hinter der Kanzel
        k.smoothHull([S(0.4, 0.42, 0.05, 0.04), S(-0.2, 0.48, 0.24, 0.13), S(-1.4, 0.44, 0.2, 0.1), S(-2.2, 0.3, 0.06, 0.04)],
                     round: 2.2, segments: 18, k.second, mirror: false)
        k.bubble(1.25, 0.4, len: 1.9, height: 0.3, width: 0.58)
        let w = k.wing(rootLead: 1.3, rootTrail: -1.5, rootZ: 0.4, tip: (-1.25, 2.75), tipChord: 0.7, y: -0.02, thick: 0.13)
        // Akzentfläche an der Flügelspitze
        _ = k.wing(rootLead: -0.55, rootTrail: -1.35, rootZ: 2.2, tip: (-1.3, 2.78), tipChord: 0.6, bulge: 0.1, y: 0.0, thick: 0.15, k.accent)
        _ = w
        // Lufteinläufe als weiche Schultern
        k.smoothHull([S(1.5, 0.08, 0.04, 0.05), S(1.0, 0.1, 0.2, 0.2), S(-0.6, 0.12, 0.24, 0.24), S(-1.2, 0.14, 0.2, 0.2)],
                     z: 0.62, round: 2.4, segments: 18, k.second)
        let tail = k.nacelle(-1.3, 0.2, 0.88, r: 0.34, len: 1.9)
        k.fin(-1.2, 0.42, 0.55, height: 1.1, len: 1.05, tilt: -0.3)
        k.lamp(-1.3, 0.05, 2.9, size: 0.09)
        k.lamp(-2.5, 0.25, 0)
        k.sensorNose(3.7, -0.02)
        k.weapon(m.weapon, hardpoints: [(0.5, -0.14, 1.65)], spine: (-1.2, 3.2, 0.66), belly: (-0.3, -0.5))
        // Bugkanonen in den Wangen und Leuchtstreifen entlang der Flanke
        k.cannon(2.2, -0.12, 0.42, len: 2.2, r: 0.085)
        k.box(0.4, 0.22, 0.56, 1.9, 0.045, 0.03, k.weaponGlow, chamfer: 0.01)
        _ = tail
    }

    // Späher (Libelle): große Kanzel vorn, dünner Leib, zwei schmale Flügelpaare, ein Triebwerk im Heck
    private static func libelle(_ k: ShipKit, _ m: ShipModel) {
        typealias S = ShipKit.Sec
        k.smoothHull([S(3.3, 0.05, 0.03, 0.03), S(2.9, 0.08, 0.26, 0.22), S(2.1, 0.12, 0.42, 0.36), S(1.2, 0.12, 0.4, 0.34),
                      S(0.2, 0.1, 0.3, 0.27), S(-1.0, 0.08, 0.24, 0.22), S(-1.9, 0.08, 0.26, 0.24)], round: 2.2, mirror: false)
        k.bubble(2.15, 0.36, len: 1.7, height: 0.34, width: 0.66)
        // vorderes Flügelpaar leicht nach vorn, hinteres nach hinten gepfeilt
        _ = k.wing(rootLead: 1.2, rootTrail: 0.6, rootZ: 0.3, tip: (1.35, 2.7), tipChord: 0.42, bulge: 0.05, y: 0.16, thick: 0.07)
        _ = k.wing(rootLead: 0.2, rootTrail: -0.4, rootZ: 0.25, tip: (-0.9, 2.4), tipChord: 0.38, bulge: 0.1, y: 0.02, thick: 0.07, k.accent)
        // Flügelwurzeln als weiche Schultern
        k.smoothHull([S(1.5, 0.12, 0.04, 0.04), S(0.9, 0.12, 0.16, 0.14), S(-0.3, 0.08, 0.14, 0.12), S(-0.7, 0.06, 0.04, 0.04)],
                     z: 0.34, round: 2.2, segments: 16, k.second)
        k.nacelle(-2.4, 0.08, 0, r: 0.3, len: 1.2, mirror: false)
        k.fin(-2.0, 0.2, 0.12, height: 0.7, len: 0.7, tilt: -0.6)
        k.lamp(1.4, 0.18, 2.85, size: 0.08)
        k.lamp(-0.9, 0.04, 2.55, size: 0.08)
        k.sensorNose(3.3, 0.05)
        k.weapon(m.weapon, hardpoints: [(0.9, -0.22, 0.8)], spine: (-1.0, 2.4, 0.5), belly: (-0.2, -0.45))
    }

    // Frachter: bulliges rundes Kopfmodul, Tragrohr, Frachtcontainer, schwere Triebwerke, drei Geschütztürme
    private static func atlas(_ k: ShipKit, _ m: ShipModel) {
        typealias S = ShipKit.Sec
        // Kopfmodul: runde Schlepperkabine
        k.smoothHull([S(3.35, 0.05, 0.1, 0.08), S(3.1, 0.1, 0.55, 0.4), S(2.4, 0.18, 0.86, 0.66), S(1.6, 0.18, 0.82, 0.64), S(1.25, 0.12, 0.5, 0.4)],
                     round: 3.2, mirror: false)
        k.bubble(2.6, 0.72, len: 1.2, height: 0.26, width: 1.0)
        // Tragrohr von vorn bis zum Heck
        k.smoothHull([S(1.5, 0.1, 0.42, 0.42), S(0.0, 0.1, 0.46, 0.46), S(-1.8, 0.1, 0.5, 0.5), S(-2.3, 0.1, 0.4, 0.4)],
                     round: 2.2, segments: 20, k.dark, mirror: false)
        // Frachtcontainer: echte Kisten mit gebrochenen Kanten und Sicken, je Seite zwei Lagen
        for (i, x) in ([0.72, -0.62] as [Float]).enumerated() {
            let lower = i == 0 ? k.accent : k.second
            let upper = i == 0 ? k.second : k.stripe
            k.box(x, -0.1, 0.98, 1.24, 0.76, 0.72, lower, chamfer: 0.07)
            k.box(x, 0.62, 0.92, 1.2, 0.56, 0.64, upper, chamfer: 0.06)
            for dx in [-0.4, -0.2, 0.0, 0.2, 0.4] as [Float] {
                k.box(x + dx, -0.1, 1.345, 0.05, 0.6, 0.03, k.dark, chamfer: 0.01)
                k.box(x + dx, 0.62, 1.245, 0.05, 0.42, 0.03, k.dark, chamfer: 0.01)
            }
            k.box(x, 0.26, 0.98, 1.1, 0.08, 0.8, k.metal, chamfer: 0.02)
        }
        // Heckblock mit vier Triebwerken
        k.smoothHull([S(-1.5, 0.1, 0.7, 0.55), S(-2.0, 0.1, 1.0, 0.7), S(-2.6, 0.1, 0.9, 0.62), S(-2.85, 0.1, 0.5, 0.36)],
                     round: 3.4, k.paint, mirror: false)
        k.nacelle(-2.3, 0.4, 1.12, r: 0.42, len: 1.5)
        k.nacelle(-2.4, -0.42, 0.55, r: 0.3, len: 1.1)
        k.fin(-1.9, 0.72, 0.5, height: 0.85, len: 0.9, tilt: -0.3)
        k.lamp(3.2, -0.1, 0.4)
        k.lamp(-1.6, 0.72, 0)
        k.weapon(m.weapon, hardpoints: [(2.5, -0.45, 0.6)], spine: (-1.4, 2.6, 1.2), belly: (0.1, -0.7))
        // Geschützturm auf dem Rücken, auf einem runden Sockel
        k.smoothHull([S(1.1, 0.56, 0.2, 0.06), S(0.6, 0.6, 0.6, 0.12), S(0.1, 0.6, 0.6, 0.12), S(-0.4, 0.56, 0.2, 0.06)],
                     round: 2.4, segments: 18, k.dark, mirror: false)
        k.turret(0.35, 0.7, r: 0.46)
        // zwei weitere Türme: Heck oben (nach hinten gerichtet) und unter dem Kopfmodul
        k.turret(-2.15, 0.82, r: 0.34, yaw: .pi)
        k.turret(2.3, -0.5, r: 0.3, down: true)
    }

    // Panzerschiff: breiter, flacher Schildkrötenpanzer mit überlappenden Rückenschilden und schwerem Turm
    private static func bastion(_ k: ShipKit, _ m: ShipModel) {
        typealias S = ShipKit.Sec
        k.smoothHull([S(3.0, -0.05, 0.25, 0.12), S(2.5, 0.02, 0.9, 0.36), S(1.2, 0.1, 1.45, 0.56), S(-0.6, 0.12, 1.6, 0.62),
                      S(-1.9, 0.1, 1.4, 0.55), S(-2.6, 0.05, 0.9, 0.36)], round: 3.0, segments: 32, mirror: false)
        // überlappende Rückenschilde
        let shields: [(Float, Float)] = [(1.5, 0.72), (0.4, 0.98), (-0.7, 1.0), (-1.7, 0.82)]
        for (i, s) in shields.enumerated() {
            let x = s.0, f = s.1
            k.smoothHull([S(x + 0.65, 0.4, 0.7 * f, 0.18), S(x + 0.2, 0.48, 1.08 * f, 0.26), S(x - 0.45, 0.5, 1.02 * f, 0.24),
                          S(x - 0.7, 0.44, 0.8 * f, 0.16)], round: 3.0, segments: 24, i % 2 == 0 ? k.stripe : k.second, mirror: false)
        }
        // seitliche Panzerschürzen
        k.smoothHull([S(1.7, -0.05, 0.1, 0.14), S(0.8, -0.05, 0.3, 0.3), S(-1.4, -0.05, 0.32, 0.32), S(-2.2, -0.05, 0.14, 0.16)],
                     z: 1.5, round: 3.0, segments: 18, k.second)
        // flache Sichtkanzel im Bug
        k.bubble(2.0, 0.36, len: 1.0, height: 0.2, width: 0.8)
        k.nacelle(-2.4, 0.1, 0.75, r: 0.42, len: 1.3)
        k.fin(-1.8, 0.55, 1.0, height: 0.6, len: 0.9, tilt: -0.4)
        k.lamp(2.6, 0.0, 0.62)
        k.lamp(-0.6, 0.1, 1.85, size: 0.1)
        k.sensorNose(3.05, -0.05)
        k.turret(-0.2, 0.8, r: 0.52)
        k.weapon(m.weapon, hardpoints: [(1.9, -0.2, 1.5)], spine: (-1.6, 3.0, 1.1), belly: (-0.4, -0.8))
    }

    // Kreuzer: runder Nadelrumpf in einem großen Ring, Kanzel in einer Seitenkapsel, drei Triebwerke
    private static func orion(_ k: ShipKit, _ m: ShipModel) {
        typealias S = ShipKit.Sec
        k.smoothHull([S(4.0, 0.05, 0.04, 0.04), S(3.0, 0.1, 0.28, 0.22), S(1.2, 0.15, 0.42, 0.34),
                      S(-0.9, 0.15, 0.5, 0.4), S(-2.1, 0.15, 0.44, 0.34), S(-2.4, 0.15, 0.3, 0.24)], round: 2.3, mirror: false)
        // Rückenwulst, trägt die Schienenkanone
        k.smoothHull([S(3.0, 0.34, 0.06, 0.04), S(2.0, 0.5, 0.24, 0.12), S(0.5, 0.5, 0.32, 0.16), S(-0.1, 0.44, 0.22, 0.1)],
                     round: 2.4, segments: 18, k.second, mirror: false)
        let ring = SCNTube(innerRadius: 0.95, outerRadius: 1.12, height: 0.5)
        ring.radialSegmentCount = 48
        k.addNode(ring, k.stripe, SCNVector3(-0.6, 0.15, 0), rot: SCNVector3(0, 0, -Float.pi / 2))
        let rim = SCNTorus(ringRadius: 1.12, pipeRadius: 0.06)
        rim.ringSegmentCount = 48
        for dx in [-0.25, 0.25] as [Float] {
            k.addNode(rim, k.dark, SCNVector3(-0.6 + dx, 0.15, 0), rot: SCNVector3(0, 0, -Float.pi / 2))
        }
        let glowRim = SCNTorus(ringRadius: 1.13, pipeRadius: 0.025)
        glowRim.ringSegmentCount = 48
        k.addNode(glowRim, k.fire, SCNVector3(-0.6, 0.15, 0), rot: SCNVector3(0, 0, -Float.pi / 2))
        // Speichen vom Rumpf zum Ring
        for i in 0..<4 {
            let a = Float(i) * .pi / 2 + .pi / 4
            let r: Float = 0.72
            k.box(-0.6, 0.15 + sin(a) * r, cos(a) * r, 0.34, 0.12, 0.55, k.dark, chamfer: 0.05,
                  rot: SCNVector3(-a, 0, 0), mirror: false)
        }
        // drei Triebwerke im Dreieck
        k.nacelle(-2.3, 0.45, 0, r: 0.28, len: 1.3, mirror: false)
        k.nacelle(-2.2, -0.1, 0.38, r: 0.25, len: 1.2)
        k.fin(-1.7, 0.5, 0.0, height: 0.8, len: 0.9, tilt: 0, k.accent)
        // Kanzel seitlich in eigener Kapsel, gegenüber eine Sensorkapsel
        k.smoothHull([S(2.4, 0.25, 0.05, 0.05), S(1.95, 0.28, 0.29, 0.23), S(0.6, 0.29, 0.34, 0.26), S(0.0, 0.27, 0.2, 0.15)],
                     z: 0.82, round: 2.3, segments: 20, k.stripe, mirror: false)
        k.bubble(1.45, 0.46, z: 0.82, len: 1.2, height: 0.2, width: 0.42)
        k.smoothHull([S(2.0, 0.2, 0.04, 0.04), S(1.6, 0.2, 0.2, 0.16), S(0.6, 0.2, 0.22, 0.18), S(0.1, 0.2, 0.1, 0.08)],
                     z: -0.74, round: 2.3, segments: 18, k.dark, mirror: false)
        k.lamp(2.0, 0.2, -0.74, size: 0.08)
        k.sensorNose(4.0, 0.05)
        k.weapon(m.weapon, hardpoints: [(1.6, -0.05, 0.6)], spine: (0.0, 3.3, 0.76), belly: (0.5, -0.5))
    }

    // Abfangjäger: Nadelrumpf, kurze, stark nach vorn gepfeilte Sichelflügel, zwei enge Triebwerke, Entenflügel
    private static func viper(_ k: ShipKit, _ m: ShipModel) {
        typealias S = ShipKit.Sec
        k.smoothHull([S(4.0, 0.0, 0.02, 0.02), S(3.3, 0.02, 0.12, 0.09), S(2.2, 0.06, 0.27, 0.2), S(0.6, 0.12, 0.4, 0.32),
                      S(-0.8, 0.14, 0.46, 0.34), S(-1.9, 0.12, 0.36, 0.26), S(-2.4, 0.1, 0.16, 0.12)], round: 2.3, mirror: false)
        k.bubble(1.3, 0.36, len: 1.8, height: 0.27, width: 0.5)
        // Sichelflügel: Spitze liegt weit vor der Wurzel
        _ = k.wing(rootLead: -0.4, rootTrail: -1.7, rootZ: 0.34, tip: (1.3, 2.35), tipChord: 0.5, bulge: -0.25, y: -0.02, thick: 0.11)
        _ = k.wing(rootLead: 1.05, rootTrail: 0.6, rootZ: 1.9, tip: (1.35, 2.4), tipChord: 0.4, bulge: 0.05, y: 0.0, thick: 0.13, k.accent)
        // Entenflügel am Bug
        _ = k.wing(rootLead: 2.5, rootTrail: 1.9, rootZ: 0.2, tip: (1.75, 1.05), tipChord: 0.3, bulge: 0.15, y: 0.06, thick: 0.06, k.accent)
        k.nacelle(-1.4, 0.2, 0.5, r: 0.31, len: 1.8)
        k.fin(-1.2, 0.4, 0.0, height: 1.0, len: 1.2, tilt: 0, k.accent)
        k.fin(-1.5, 0.3, 0.72, height: 0.55, len: 0.7, tilt: -0.75)
        k.lamp(1.4, 0.02, 2.55, size: 0.09)
        k.sensorNose(4.0, 0.0)
        k.weapon(m.weapon, hardpoints: [(1.7, -0.02, 2.3)], spine: (-1.2, 3.4, 0.55), belly: (-0.2, -0.45))
        // lange Bugkanonen in den Wangen
        k.cannon(2.5, -0.08, 0.34, len: 2.6, r: 0.08)
        k.box(0.3, 0.2, 0.44, 2.1, 0.045, 0.03, k.weaponGlow, chamfer: 0.01)
    }

    // Schwerer Frachter: Doppelrumpf mit Brückendeck, Container dazwischen, fünf Geschütztürme
    private static func titan(_ k: ShipKit, _ m: ShipModel) {
        typealias S = ShipKit.Sec
        // zwei lange Rümpfe
        k.smoothHull([S(3.6, 0.0, 0.08, 0.08), S(3.0, 0.05, 0.42, 0.36), S(1.5, 0.1, 0.62, 0.52), S(-1.0, 0.12, 0.68, 0.58),
                      S(-2.4, 0.1, 0.6, 0.5), S(-2.9, 0.1, 0.4, 0.34)], z: 1.35, round: 3.0)
        // Brückendeck dazwischen
        k.smoothHull([S(2.2, 0.15, 0.5, 0.14), S(1.4, 0.2, 1.2, 0.3), S(-1.2, 0.25, 1.3, 0.36), S(-2.2, 0.2, 1.0, 0.26)],
                     round: 3.4, k.stripe, mirror: false)
        // Kommandoturm mit Sichtkanzel
        k.smoothHull([S(-0.3, 0.7, 0.2, 0.1), S(-0.8, 0.85, 0.5, 0.3), S(-1.5, 0.85, 0.5, 0.3), S(-2.0, 0.7, 0.3, 0.14)],
                     round: 2.8, segments: 20, k.second, mirror: false)
        k.bubble(-0.85, 1.1, len: 0.9, height: 0.16, width: 0.7)
        // Container unter dem Deck
        for (i, x) in ([1.0, -0.2, -1.4] as [Float]).enumerated() {
            k.box(x, -0.3, 0.42, 1.05, 0.55, 0.66, i == 1 ? k.second : k.accent, chamfer: 0.06)
            for dx in [-0.3, 0.0, 0.3] as [Float] {
                k.box(x + dx, -0.3, 0.76, 0.05, 0.42, 0.03, k.dark, chamfer: 0.01)
            }
        }
        // Geschütztürme: je Rumpf einer vorn und einer hinten, ein schwerer auf dem Deck
        k.turret(1.6, 0.66, z: 1.35, r: 0.38)
        k.turret(1.6, 0.66, z: -1.35, r: 0.38)
        k.turret(-1.8, 0.68, z: 1.35, r: 0.34, yaw: .pi)
        k.turret(-1.8, 0.68, z: -1.35, r: 0.34, yaw: .pi)
        k.turret(0.6, 0.56, r: 0.5)
        k.nacelle(-2.6, 0.1, 1.35, r: 0.46, len: 1.3)
        k.nacelle(-2.3, 0.2, 0, r: 0.36, len: 1.1, mirror: false)
        k.fin(-2.0, 0.6, 1.35, height: 0.9, len: 1.0, tilt: -0.15)
        k.lamp(3.5, 0.0, 1.35)
        k.lamp(0.0, 0.1, 2.05)
        k.weapon(m.weapon, hardpoints: [(1.8, 0.0, 2.05)], spine: (-2.2, 3.0, 1.35), belly: (-0.2, -1.05))
    }

    // Tarnschiff: geschwungener Nurflügler, zwei Kanzelblasen, versenkte Düsen, rote Leuchtlinien an der Vorderkante
    private static func phantom(_ k: ShipKit, _ m: ShipModel) {
        typealias S = ShipKit.Sec
        let w = k.wing(rootLead: 2.9, rootTrail: -1.5, rootZ: 0.0, tip: (-1.3, 3.0), tipChord: 0.6, bulge: 0.3, y: 0.0, thick: 0.18, k.paint)
        _ = k.wing(rootLead: 0.2, rootTrail: -1.2, rootZ: 1.3, tip: (-1.2, 2.9), tipChord: 0.5, bulge: 0.2, y: 0.02, thick: 0.2, k.second)
        // flacher Rumpf, weich in den Flügel übergehend
        k.smoothHull([S(3.4, 0.06, 0.03, 0.03), S(2.4, 0.12, 0.5, 0.2), S(0.8, 0.18, 0.85, 0.34), S(-0.9, 0.16, 0.8, 0.3),
                      S(-1.9, 0.1, 0.5, 0.16)], round: 2.2, mirror: false)
        // Rückengrat, trägt die Schienenkanone
        k.smoothHull([S(2.5, 0.3, 0.1, 0.06), S(1.6, 0.45, 0.22, 0.12), S(-0.4, 0.5, 0.24, 0.1), S(-1.2, 0.4, 0.1, 0.05)],
                     round: 2.4, segments: 18, k.second, mirror: false)
        // zwei Kanzelblasen links und rechts vom Grat
        k.bubble(1.0, 0.4, z: 0.5, len: 1.4, height: 0.2, width: 0.36)
        k.bubble(1.0, 0.4, z: -0.5, len: 1.4, height: 0.2, width: 0.36)
        // rote Leuchtlinie entlang der geschwungenen Vorderkante
        let red = ShipKit.glow(UIColor(red: 1, green: 0.15, blue: 0.2, alpha: 1))
        let lead = Array(w[1...8])
        k.plate(lead + lead.reversed().map { ($0.0 - 0.1, $0.1) }, y: 0.1, thick: 0.02, red, chamfer: 0)
        // flache Düsen im Flügel
        k.nacelle(-1.5, 0.12, 0.7, r: 0.22, len: 1.2, k.dark)
        // nach innen geneigte Doppelflossen und Winglets
        k.fin(-1.0, 0.25, 0.95, height: 0.55, len: 0.8, tilt: 0.45, k.accent)
        k.fin(-1.1, 0.06, 2.85, height: 0.4, len: 0.6, tilt: -0.9, k.accent)
        k.sensorNose(3.4, 0.06)
        k.lamp(-1.2, 0.08, 3.05, size: 0.1)
        k.weapon(m.weapon, hardpoints: [(1.0, -0.1, 1.2)], spine: (-0.8, 2.4, 0.66), belly: (-0.2, -0.4))
    }

    // Flaggschiff: langer Schwanenrumpf, weit geschwungene Sichelflügel mit Triebwerken an den Spitzen, goldener Kamm
    private static func nova(_ k: ShipKit, _ m: ShipModel) {
        typealias S = ShipKit.Sec
        k.smoothHull([S(4.2, 0.0, 0.02, 0.02), S(3.4, 0.04, 0.16, 0.12), S(2.2, 0.1, 0.38, 0.28), S(0.6, 0.16, 0.56, 0.42),
                      S(-1.0, 0.18, 0.6, 0.44), S(-2.2, 0.14, 0.44, 0.32), S(-2.8, 0.12, 0.2, 0.14)], round: 2.3, mirror: false)
        k.smoothHull([S(0.2, 0.5, 0.05, 0.04), S(-0.6, 0.58, 0.22, 0.12), S(-1.8, 0.5, 0.18, 0.1), S(-2.5, 0.32, 0.05, 0.04)],
                     round: 2.2, segments: 18, k.accent, mirror: false)
        k.bubble(1.3, 0.46, len: 2.2, height: 0.3, width: 0.6)
        _ = k.wing(rootLead: 1.2, rootTrail: -1.4, rootZ: 0.45, tip: (-1.5, 2.55), tipChord: 0.9, bulge: 0.45, y: 0.0, thick: 0.13)
        // Entenflügel am Bug
        _ = k.wing(rootLead: 2.9, rootTrail: 2.3, rootZ: 0.22, tip: (2.1, 1.0), tipChord: 0.26, bulge: 0.15, y: 0.08, thick: 0.06, k.accent)
        k.nacelle(-1.5, 0.0, 2.6, r: 0.3, len: 1.8, k.accent)
        k.nacelle(-2.3, 0.16, 0.42, r: 0.3, len: 1.1)
        k.fin(-1.5, 0.5, 0.0, height: 1.3, len: 1.2, tilt: 0, k.accent)
        k.fin(-1.2, 0.2, 2.6, height: 0.6, len: 0.7, tilt: -0.3, k.second)
        k.lamp(2.2, 0.1, 1.1, size: 0.08)
        k.sensorNose(4.2, 0.0)
        k.box(0.4, 0.26, 0.6, 2.2, 0.045, 0.03, k.weaponGlow, chamfer: 0.01)
        k.weapon(m.weapon, hardpoints: [(1.1, -0.36, 1.4)], spine: (-1.0, 3.6, 0.7), belly: (-0.3, -0.6))
    }
}
