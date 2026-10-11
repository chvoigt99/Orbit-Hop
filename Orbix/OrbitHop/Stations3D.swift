import SceneKit
import UIKit

// MARK: - Raumstationen

/// Zehn Stationsmodelle, eins je Stationsname (AURORA, VEGA, …). Alle passen in den Stationsradius R,
/// und jedes hat außen bei R einen Ring oder Rand, an dem der Steg der Andockplattform endet.
/// Die Lacke teilen sich alle Modelle (drei Texturen, beim Laden vorbereitet); die Modelle unterscheiden
/// sich in Form, Akzentfarbe und Lichtern.
enum StationModels {
    /// Farben je Modell: Akzent (Lackton), Lampen, Fenster, Andocklichter
    struct Style {
        let accent: UIColor
        let lamp: UIColor
        let window: UIColor
        let dock: UIColor
    }

    static let styles: [Style] = [
        // AURORA: klassisches Rot
        Style(accent: UIColor(red: 0.62, green: 0.2, blue: 0.16, alpha: 1), lamp: UIColor(red: 1, green: 0.7, blue: 0.3, alpha: 1),
              window: UIColor(red: 1, green: 0.86, blue: 0.6, alpha: 1), dock: UIColor(red: 0.45, green: 0.95, blue: 1, alpha: 1)),
        // VEGA: Kobaltblau
        Style(accent: UIColor(red: 0.16, green: 0.3, blue: 0.7, alpha: 1), lamp: UIColor(red: 0.5, green: 0.8, blue: 1, alpha: 1),
              window: UIColor(red: 0.75, green: 0.9, blue: 1, alpha: 1), dock: UIColor(red: 0.45, green: 0.95, blue: 1, alpha: 1)),
        // HELIOS: Gold
        Style(accent: UIColor(red: 0.78, green: 0.58, blue: 0.18, alpha: 1), lamp: UIColor(red: 1, green: 0.8, blue: 0.35, alpha: 1),
              window: UIColor(red: 1, green: 0.9, blue: 0.6, alpha: 1), dock: UIColor(red: 1, green: 0.85, blue: 0.4, alpha: 1)),
        // KEPLER: Grün
        Style(accent: UIColor(red: 0.2, green: 0.55, blue: 0.3, alpha: 1), lamp: UIColor(red: 0.55, green: 1, blue: 0.5, alpha: 1),
              window: UIColor(red: 0.9, green: 1, blue: 0.8, alpha: 1), dock: UIColor(red: 0.5, green: 1, blue: 0.6, alpha: 1)),
        // BOREAS: Eisweiß und Cyan
        Style(accent: UIColor(red: 0.55, green: 0.8, blue: 0.9, alpha: 1), lamp: UIColor(red: 0.6, green: 0.95, blue: 1, alpha: 1),
              window: UIColor(red: 0.8, green: 0.97, blue: 1, alpha: 1), dock: UIColor(red: 0.55, green: 1, blue: 1, alpha: 1)),
        // LYRA: Violett
        Style(accent: UIColor(red: 0.45, green: 0.22, blue: 0.65, alpha: 1), lamp: UIColor(red: 0.85, green: 0.55, blue: 1, alpha: 1),
              window: UIColor(red: 0.95, green: 0.85, blue: 1, alpha: 1), dock: UIColor(red: 0.8, green: 0.6, blue: 1, alpha: 1)),
        // ZENIT: Orange
        Style(accent: UIColor(red: 0.85, green: 0.4, blue: 0.1, alpha: 1), lamp: UIColor(red: 1, green: 0.6, blue: 0.25, alpha: 1),
              window: UIColor(red: 1, green: 0.85, blue: 0.65, alpha: 1), dock: UIColor(red: 1, green: 0.7, blue: 0.35, alpha: 1)),
        // POLARIS: Signalrot und Weiß
        Style(accent: UIColor(red: 0.75, green: 0.1, blue: 0.12, alpha: 1), lamp: UIColor(red: 1, green: 0.3, blue: 0.3, alpha: 1),
              window: UIColor(red: 1, green: 0.95, blue: 0.9, alpha: 1), dock: UIColor(red: 1, green: 0.45, blue: 0.45, alpha: 1)),
        // ANDROMEDA: Türkis
        Style(accent: UIColor(red: 0.1, green: 0.55, blue: 0.55, alpha: 1), lamp: UIColor(red: 0.4, green: 1, blue: 0.9, alpha: 1),
              window: UIColor(red: 0.8, green: 1, blue: 0.95, alpha: 1), dock: UIColor(red: 0.4, green: 1, blue: 0.9, alpha: 1)),
        // ELYSIUM: Magenta und Gold
        Style(accent: UIColor(red: 0.7, green: 0.15, blue: 0.5, alpha: 1), lamp: UIColor(red: 1, green: 0.5, blue: 0.85, alpha: 1),
              window: UIColor(red: 1, green: 0.88, blue: 0.6, alpha: 1), dock: UIColor(red: 1, green: 0.6, blue: 0.9, alpha: 1))
    ]

    /// Lacke, die alle Stationen teilen; beim Laden einmal erzeugen, sonst hakt es beim Auftauchen der ersten Station
    static let paints: [(String, UIColor)] = [("station", UIColor(white: 0.66, alpha: 1)),
                                               ("station-dark", UIColor(white: 0.22, alpha: 1)),
                                               ("station-accent", UIColor(white: 0.8, alpha: 1))]

    /// Baukasten für ein Modell: Materialien und kleine Helfer
    private struct Kit {
        let R: Float
        let hull: SCNMaterial
        let dark: SCNMaterial
        let accent: SCNMaterial
        let lamp: SCNMaterial
        let window: SCNMaterial
        let dock: SCNMaterial
        let solar: SCNMaterial
        let style: Style

        func node(_ g: SCNGeometry, _ m: SCNMaterial, _ pos: SCNVector3, rot: SCNVector3 = SCNVector3(0, 0, 0)) -> SCNNode {
            g.materials = [m]
            let n = SCNNode(geometry: g)
            n.position = pos
            n.eulerAngles = rot
            return n
        }

        func blink(_ n: SCNNode, _ delay: Double) {
            n.runAction(.repeatForever(.sequence([.wait(duration: delay), .fadeOut(duration: 0.12),
                                                  .wait(duration: 0.9), .fadeIn(duration: 0.12)])))
        }

        func glow(_ c: UIColor) -> SCNMaterial {
            let m = SCNMaterial()
            m.lightingModel = .constant
            m.diffuse.contents = c
            return m
        }

        func cyl(_ r: Float, _ h: Float, _ m: SCNMaterial, _ pos: SCNVector3, rot: SCNVector3 = SCNVector3(0, 0, 0), segments: Int = 32) -> SCNNode {
            let g = SCNCylinder(radius: CGFloat(r), height: CGFloat(h))
            g.radialSegmentCount = segments
            return node(g, m, pos, rot: rot)
        }

        func box(_ w: Float, _ h: Float, _ l: Float, _ m: SCNMaterial, _ pos: SCNVector3, rot: SCNVector3 = SCNVector3(0, 0, 0)) -> SCNNode {
            node(SCNBox(width: CGFloat(w), height: CGFloat(h), length: CGFloat(l), chamferRadius: CGFloat(min(w, h, l) * 0.1)), m, pos, rot: rot)
        }

        func sphere(_ r: Float, _ m: SCNMaterial, _ pos: SCNVector3) -> SCNNode {
            let g = SCNSphere(radius: CGFloat(r))
            g.segmentCount = 32
            return node(g, m, pos)
        }

        func torus(_ ring: Float, _ pipe: Float, _ m: SCNMaterial, _ pos: SCNVector3 = SCNVector3(0, 0, 0)) -> SCNNode {
            let g = SCNTorus(ringRadius: CGFloat(ring), pipeRadius: CGFloat(pipe))
            g.ringSegmentCount = 96
            g.pipeSegmentCount = 16
            return node(g, m, pos)
        }

        func tube(_ inner: Float, _ outer: Float, _ h: Float, _ m: SCNMaterial, _ pos: SCNVector3 = SCNVector3(0, 0, 0)) -> SCNNode {
            let g = SCNTube(innerRadius: CGFloat(inner), outerRadius: CGFloat(outer), height: CGFloat(h))
            g.radialSegmentCount = 96
            return node(g, m, pos)
        }

        /// Stab von a nach b (Zylinder entlang der Verbindung)
        func rod(_ a: SCNVector3, _ b: SCNVector3, _ r: Float, _ m: SCNMaterial) -> SCNNode {
            let dx = b.x - a.x, dy = b.y - a.y, dz = b.z - a.z
            let len = max(0.01, (dx * dx + dy * dy + dz * dz).squareRoot())
            let n = cyl(r, len, m, SCNVector3((a.x + b.x) / 2, (a.y + b.y) / 2, (a.z + b.z) / 2), segments: 12)
            // Zylinder liegt entlang y; auf die Verbindung drehen
            n.look(at: b, up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 1, 0))
            return n
        }

        /// Fensterreihe rund um einen Zylinder
        func windowRing(_ parent: SCNNode, radius: Float, y: Float, count: Int) {
            for k in 0..<count {
                let a = Float(k) / Float(count) * .pi * 2
                let w = SCNBox(width: CGFloat(R * 0.03), height: CGFloat(R * 0.04), length: CGFloat(R * 0.045), chamferRadius: 0)
                parent.addChildNode(node(w, window, SCNVector3(cos(a) * radius, y, sin(a) * radius), rot: SCNVector3(0, -a, 0)))
            }
        }

        /// Solarflügel: Paneele entlang eines Auslegers, beidseitig
        func solarWing(_ parent: SCNNode, from x0: Float, to x1: Float, width: Float) {
            let len = x1 - x0
            parent.addChildNode(box(len, R * 0.02, R * 0.02, dark, SCNVector3((x0 + x1) / 2, 0, 0)))
            let panels = max(1, Int(len / (R * 0.32)))
            let pw = len / Float(panels)
            for k in 0..<panels {
                let x = x0 + pw * (Float(k) + 0.5)
                parent.addChildNode(box(pw * 0.92, R * 0.008, width, solar, SCNVector3(x, 0, width * 0.55)))
                parent.addChildNode(box(pw * 0.92, R * 0.008, width, solar, SCNVector3(x, 0, -width * 0.55)))
            }
        }

        /// Positionslichter rot und grün auf dem Außenrand
        func navLights(_ parent: SCNNode, radius: Float, y: Float) {
            for (a, c) in [(Float(0), UIColor(red: 1, green: 0.2, blue: 0.2, alpha: 1)), (Float.pi, UIColor(red: 0.3, green: 1, blue: 0.4, alpha: 1))] {
                let ln = sphere(R * 0.025, glow(c), SCNVector3(cos(a) * radius, y, sin(a) * radius))
                blink(ln, Double(a) * 0.2)
                parent.addChildNode(ln)
            }
        }

        /// Leuchtender Leitring bei R: Modelle ohne eigenen Außenring zeigen damit, wo der Steg ankommt
        func guideRing(_ parent: SCNNode) {
            parent.addChildNode(torus(R * 0.98, R * 0.012, glow(style.dock.withAlphaComponent(0.85))))
            parent.addChildNode(torus(R * 0.98, R * 0.03, dark, SCNVector3(0, -R * 0.03, 0)))
        }
    }

    static func make(_ p: Planet, paint: (String, UIColor) -> SCNMaterial) -> SCNNode {
        let no = max(0, p.stationNo) % Game.stationModels
        let style = styles[no % styles.count]
        let accent = paint("station-accent", UIColor(white: 0.8, alpha: 1))
        accent.multiply.contents = style.accent
        let solar = SCNMaterial()
        solar.lightingModel = .physicallyBased
        solar.diffuse.contents = WorldTextures.solarCells
        solar.metalness.contents = 0.6
        solar.roughness.contents = 0.3
        let base = Kit(R: Float(p.radius), hull: paint("station", UIColor(white: 0.66, alpha: 1)),
                       dark: paint("station-dark", UIColor(white: 0.22, alpha: 1)), accent: accent,
                       lamp: SCNMaterial(), window: SCNMaterial(), dock: SCNMaterial(), solar: solar, style: style)
        let k = Kit(R: base.R, hull: base.hull, dark: base.dark, accent: base.accent,
                    lamp: base.glow(style.lamp), window: base.glow(style.window), dock: base.glow(style.dock),
                    solar: solar, style: style)
        let root = SCNNode()
        root.eulerAngles = SCNVector3(0.12, 0, 0.06)
        switch no {
        case 1: vega(k, root)
        case 2: helios(k, root)
        case 3: kepler(k, root)
        case 4: boreas(k, root)
        case 5: lyra(k, root)
        case 6: zenit(k, root)
        case 7: polaris(k, root)
        case 8: andromeda(k, root)
        case 9: elysium(k, root)
        default: aurora(k, root)
        }
        return root
    }

    // MARK: 0 AURORA: Nabe mit Wohnrad, Speichen und Solarflügeln

    private static func aurora(_ k: Kit, _ root: SCNNode) {
        let R = k.R
        let hub = SCNNode()
        root.addChildNode(hub)
        hub.addChildNode(k.cyl(R * 0.24, R * 0.55, k.hull, SCNVector3(0, 0, 0)))
        for y in [-0.22, 0, 0.22] as [Float] {
            hub.addChildNode(k.cyl(R * 0.28, R * 0.06, y == 0 ? k.accent : k.dark, SCNVector3(0, y * R, 0)))
        }
        hub.addChildNode(k.cyl(R * 0.11, R * 0.45, k.hull, SCNVector3(0, R * 0.48, 0)))
        hub.addChildNode(k.sphere(R * 0.13, k.dark, SCNVector3(0, R * 0.7, 0)))
        hub.addChildNode(k.cyl(R * 0.025, R * 0.6, k.dark, SCNVector3(0, -R * 0.55, 0)))
        let tip = k.sphere(R * 0.03, k.lamp, SCNVector3(0, -R * 0.86, 0))
        k.blink(tip, 0.3)
        hub.addChildNode(tip)
        k.windowRing(hub, radius: R * 0.242, y: -R * 0.11, count: 16)
        k.windowRing(hub, radius: R * 0.242, y: R * 0.11, count: 16)

        // Wohnrad: dreht sich langsam um die Nabe
        let wheel = SCNNode()
        wheel.runAction(.repeatForever(.rotateBy(x: 0, y: .pi * 2, z: 0, duration: 70)))
        root.addChildNode(wheel)
        wheel.addChildNode(k.tube(R * 0.84, R, R * 0.16, k.hull))
        for y in [-0.085, 0.085] as [Float] {
            wheel.addChildNode(k.tube(R * 0.83, R * 1.015, R * 0.025, k.dark, SCNVector3(0, y * R, 0)))
        }
        wheel.addChildNode(k.tube(R * 1.0, R * 1.006, R * 0.03, k.window))
        for i in 0..<12 {
            let holder = SCNNode()
            holder.eulerAngles.y = Float(i) / 12 * .pi * 2
            wheel.addChildNode(holder)
            holder.addChildNode(k.box(R * 0.2, R * 0.22, R * 0.16, i % 4 == 0 ? k.accent : (i % 2 == 0 ? k.dark : k.hull), SCNVector3(R * 0.92, 0, 0)))
            let ln = k.box(R * 0.03, R * 0.02, R * 0.03, k.lamp, SCNVector3(R * 0.92, R * 0.12, 0))
            if i % 2 == 0 { k.blink(ln, Double(i) * 0.12) }
            holder.addChildNode(ln)
            if i % 3 == 0 {
                let len = R * 0.6
                holder.addChildNode(k.cyl(R * 0.04, len, k.dark, SCNVector3(R * 0.24 + len / 2, 0, 0), rot: SCNVector3(0, 0, Float.pi / 2)))
                holder.addChildNode(k.cyl(R * 0.06, R * 0.05, k.hull, SCNVector3(R * 0.55, 0, 0), rot: SCNVector3(0, 0, Float.pi / 2)))
            }
        }

        // Solarflügel über dem Rad, gegenläufig
        let arrays = SCNNode()
        arrays.position = SCNVector3(0, R * 0.36, 0)
        arrays.runAction(.repeatForever(.rotateBy(x: 0, y: -.pi * 2, z: 0, duration: 140)))
        root.addChildNode(arrays)
        for i in 0..<4 {
            let holder = SCNNode()
            holder.eulerAngles.y = Float(i) * .pi / 2 + .pi / 4
            arrays.addChildNode(holder)
            k.solarWing(holder, from: R * 0.1, to: R * 1.15, width: R * 0.2)
        }
        k.navLights(root, radius: R * 1.02, y: R * 0.1)
    }

    // MARK: 1 VEGA: zwei gegenläufige Räder an einer langen Spindel

    private static func vega(_ k: Kit, _ root: SCNNode) {
        let R = k.R
        root.addChildNode(k.cyl(R * 0.12, R * 1.3, k.hull, SCNVector3(0, 0, 0)))
        for y in [-0.5, 0.5] as [Float] {
            root.addChildNode(k.cyl(R * 0.18, R * 0.12, k.accent, SCNVector3(0, y * R, 0)))
        }
        let cap = k.sphere(R * 0.06, k.lamp, SCNVector3(0, R * 0.68, 0))
        k.blink(cap, 0.2)
        root.addChildNode(cap)
        k.windowRing(root, radius: R * 0.122, y: 0, count: 12)
        for (y, r, dir, dur) in [(Float(-0.2), Float(1.0), Float(1), 60.0), (Float(0.22), Float(0.78), Float(-1), 45.0)] {
            let wheel = SCNNode()
            wheel.position = SCNVector3(0, y * R, 0)
            wheel.runAction(.repeatForever(.rotateBy(x: 0, y: CGFloat(dir) * .pi * 2, z: 0, duration: dur)))
            root.addChildNode(wheel)
            wheel.addChildNode(k.tube(R * (r - 0.12), R * r, R * 0.1, k.hull))
            wheel.addChildNode(k.tube(R * r, R * (r + 0.006), R * 0.025, k.window))
            for i in 0..<4 {
                let a = Float(i) / 4 * .pi * 2 + (dir > 0 ? 0 : .pi / 4)
                let end = SCNVector3(cos(a) * R * (r - 0.1), 0, sin(a) * R * (r - 0.1))
                wheel.addChildNode(k.rod(SCNVector3(0, 0, 0), end, R * 0.03, k.dark))
                wheel.addChildNode(k.box(R * 0.14, R * 0.13, R * 0.14, k.accent, SCNVector3(cos(a) * R * (r - 0.05), 0, sin(a) * R * (r - 0.05)),
                                         rot: SCNVector3(0, -a, 0)))
            }
        }
        k.navLights(root, radius: R * 1.02, y: -R * 0.15)
    }

    // MARK: 2 HELIOS: goldene Kugel, dünner Ring mit Kapseln, große Sonnensegel

    private static func helios(_ k: Kit, _ root: SCNNode) {
        let R = k.R
        root.addChildNode(k.sphere(R * 0.3, k.accent, SCNVector3(0, 0, 0)))
        root.addChildNode(k.torus(R * 0.3, R * 0.035, k.dark))
        k.windowRing(root, radius: R * 0.3, y: R * 0.06, count: 20)
        let ring = SCNNode()
        ring.runAction(.repeatForever(.rotateBy(x: 0, y: .pi * 2, z: 0, duration: 80)))
        root.addChildNode(ring)
        ring.addChildNode(k.torus(R * 0.94, R * 0.06, k.hull))
        ring.addChildNode(k.torus(R * 0.94, R * 0.065, k.window, SCNVector3(0, 0, 0)).then { $0.scale = SCNVector3(1, 0.15, 1) })
        for i in 0..<3 {
            let a = Float(i) / 3 * .pi * 2
            ring.addChildNode(k.rod(SCNVector3(cos(a) * R * 0.3, 0, sin(a) * R * 0.3),
                                    SCNVector3(cos(a) * R * 0.88, 0, sin(a) * R * 0.88), R * 0.035, k.dark))
        }
        for i in 0..<6 {
            let a = Float(i) / 6 * .pi * 2 + .pi / 6
            let pod = SCNNode()
            pod.position = SCNVector3(cos(a) * R * 0.94, 0, sin(a) * R * 0.94)
            pod.eulerAngles.y = -a
            pod.addChildNode(k.cyl(R * 0.09, R * 0.2, k.accent, SCNVector3(0, 0, 0), rot: SCNVector3(Float.pi / 2, 0, 0)))
            let l = k.sphere(R * 0.025, k.lamp, SCNVector3(0, R * 0.1, 0))
            k.blink(l, Double(i) * 0.2)
            pod.addChildNode(l)
            ring.addChildNode(pod)
        }
        // zwei lange Sonnensegel über der Kugel
        let sails = SCNNode()
        sails.position = SCNVector3(0, R * 0.42, 0)
        root.addChildNode(sails)
        sails.addChildNode(k.cyl(R * 0.04, R * 0.14, k.dark, SCNVector3(0, -R * 0.07, 0)))
        for side in [Float(1), -1] {
            let holder = SCNNode()
            holder.eulerAngles.y = side > 0 ? 0 : .pi
            sails.addChildNode(holder)
            k.solarWing(holder, from: R * 0.08, to: R * 1.05, width: R * 0.3)
        }
        k.navLights(root, radius: R * 1.0, y: R * 0.08)
    }

    // MARK: 3 KEPLER: Gitterträger mit Modulen und vier Solarflügelpaaren

    private static func kepler(_ k: Kit, _ root: SCNNode) {
        let R = k.R
        // Hauptträger entlang x
        root.addChildNode(k.box(R * 1.7, R * 0.06, R * 0.06, k.dark, SCNVector3(0, R * 0.12, 0)))
        for i in 0..<9 {
            let x = (Float(i) - 4) * R * 0.2
            root.addChildNode(k.box(R * 0.02, R * 0.1, R * 0.1, k.hull, SCNVector3(x, R * 0.12, 0)))
        }
        // Wohnmodule quer zum Träger
        for (z, len, m) in [(Float(0), Float(0.9), k.hull), (Float(0.1), Float(0.5), k.accent)] {
            root.addChildNode(k.cyl(R * 0.09, R * len, m, SCNVector3(0, 0, z * R), rot: SCNVector3(Float.pi / 2, 0, 0)))
        }
        root.addChildNode(k.cyl(R * 0.08, R * 0.5, k.hull, SCNVector3(R * 0.22, 0, 0), rot: SCNVector3(0, 0, Float.pi / 2)))
        root.addChildNode(k.sphere(R * 0.11, k.dark, SCNVector3(0, 0, R * 0.45)))
        root.addChildNode(k.sphere(R * 0.11, k.dark, SCNVector3(0, 0, -R * 0.45)))
        for z in [-0.3, -0.1, 0.1, 0.3] as [Float] {
            root.addChildNode(k.box(R * 0.04, R * 0.03, R * 0.05, k.window, SCNVector3(0, R * 0.09, z * R)))
        }
        // Radiatoren
        for x in [-0.3, 0.3] as [Float] {
            root.addChildNode(k.box(R * 0.12, R * 0.01, R * 0.35, k.hull, SCNVector3(x * R, R * 0.04, -R * 0.25)))
        }
        // Solarflügel an beiden Enden, je zwei
        for side in [Float(1), -1] {
            for (dz, dy) in [(Float(0.0), Float(0.12))] {
                let holder = SCNNode()
                holder.position = SCNVector3(side * R * 0.68, dy * R, dz)
                holder.eulerAngles.y = .pi / 2
                root.addChildNode(holder)
                k.solarWing(holder, from: -R * 0.7, to: R * 0.7, width: R * 0.16)
            }
        }
        k.guideRing(root)
        k.navLights(root, radius: R * 0.85, y: R * 0.16)
    }

    // MARK: 4 BOREAS: Kugelkern mit sechs Andockarmen bis an den Außenring

    private static func boreas(_ k: Kit, _ root: SCNNode) {
        let R = k.R
        root.addChildNode(k.sphere(R * 0.3, k.hull, SCNVector3(0, 0, 0)))
        root.addChildNode(k.torus(R * 0.3, R * 0.04, k.accent))
        root.addChildNode(k.cyl(R * 0.08, R * 0.3, k.dark, SCNVector3(0, R * 0.38, 0)))
        let beacon = k.sphere(R * 0.05, k.lamp, SCNVector3(0, R * 0.55, 0))
        k.blink(beacon, 0.1)
        root.addChildNode(beacon)
        k.windowRing(root, radius: R * 0.28, y: R * 0.1, count: 18)
        let arms = SCNNode()
        arms.runAction(.repeatForever(.rotateBy(x: 0, y: .pi * 2, z: 0, duration: 120)))
        root.addChildNode(arms)
        for i in 0..<6 {
            let a = Float(i) / 6 * .pi * 2
            let c = cos(a), s = sin(a)
            arms.addChildNode(k.rod(SCNVector3(c * R * 0.28, 0, s * R * 0.28), SCNVector3(c * R * 0.86, 0, s * R * 0.86), R * 0.045, k.dark))
            arms.addChildNode(k.sphere(R * 0.08, i % 2 == 0 ? k.accent : k.hull, SCNVector3(c * R * 0.6, 0, s * R * 0.6)))
            let l = k.box(R * 0.03, R * 0.03, R * 0.03, k.dock, SCNVector3(c * R * 0.6, R * 0.09, s * R * 0.6))
            k.blink(l, Double(i) * 0.15)
            arms.addChildNode(l)
        }
        arms.addChildNode(k.tube(R * 0.86, R, R * 0.08, k.hull))
        arms.addChildNode(k.tube(R * 1.0, R * 1.006, R * 0.02, k.window))
        k.navLights(root, radius: R * 1.02, y: R * 0.06)
    }

    // MARK: 5 LYRA: drei Arme mit großen Kapseln, außen durch einen Ring verbunden

    private static func lyra(_ k: Kit, _ root: SCNNode) {
        let R = k.R
        // sechseckige Nabe
        let hub = SCNCylinder(radius: CGFloat(R * 0.22), height: CGFloat(R * 0.3))
        hub.radialSegmentCount = 6
        root.addChildNode(k.node(hub, k.hull, SCNVector3(0, 0, 0)))
        let top = SCNCone(topRadius: CGFloat(R * 0.05), bottomRadius: CGFloat(R * 0.16), height: CGFloat(R * 0.25))
        root.addChildNode(k.node(top, k.accent, SCNVector3(0, R * 0.27, 0)))
        k.windowRing(root, radius: R * 0.2, y: 0, count: 12)
        let frame = SCNNode()
        frame.runAction(.repeatForever(.rotateBy(x: 0, y: .pi * 2, z: 0, duration: 90)))
        root.addChildNode(frame)
        for i in 0..<3 {
            let a = Float(i) / 3 * .pi * 2
            let c = cos(a), s = sin(a)
            frame.addChildNode(k.rod(SCNVector3(c * R * 0.2, 0, s * R * 0.2), SCNVector3(c * R * 0.72, 0, s * R * 0.72), R * 0.05, k.dark))
            frame.addChildNode(k.sphere(R * 0.17, k.accent, SCNVector3(c * R * 0.78, 0, s * R * 0.78)))
            frame.addChildNode(k.torus(R * 0.17, R * 0.02, k.window, SCNVector3(c * R * 0.78, 0, s * R * 0.78)))
            let l = k.sphere(R * 0.03, k.lamp, SCNVector3(c * R * 0.78, R * 0.19, s * R * 0.78))
            k.blink(l, Double(i) * 0.3)
            frame.addChildNode(l)
        }
        frame.addChildNode(k.torus(R * 0.96, R * 0.04, k.hull))
        k.guideRing(root)
        k.navLights(root, radius: R * 1.0, y: R * 0.05)
    }

    // MARK: 6 ZENIT: liegender Wohnzylinder mit Spiegelsegeln

    private static func zenit(_ k: Kit, _ root: SCNNode) {
        let R = k.R
        let drum = SCNNode()
        drum.eulerAngles = SCNVector3(0, 0, Float.pi / 2)
        root.addChildNode(drum)
        let spin = SCNNode()
        spin.runAction(.repeatForever(.rotateBy(x: 0, y: .pi * 2, z: 0, duration: 50)))
        drum.addChildNode(spin)
        spin.addChildNode(k.cyl(R * 0.26, R * 1.4, k.hull, SCNVector3(0, 0, 0), segments: 48))
        for i in 0..<3 {
            let a = Float(i) / 3 * .pi * 2
            // Fensterbänder längs des Zylinders
            spin.addChildNode(k.box(R * 0.06, R * 1.3, R * 0.02, k.window, SCNVector3(cos(a) * R * 0.262, 0, sin(a) * R * 0.262), rot: SCNVector3(0, -a, 0)))
            // Spiegelsegel, schräg abstehend
            let mirror = k.box(R * 0.02, R * 1.2, R * 0.3, k.solar, SCNVector3(cos(a + 0.5) * R * 0.45, 0, sin(a + 0.5) * R * 0.45),
                               rot: SCNVector3(0, -a - 0.5, 0))
            spin.addChildNode(mirror)
        }
        for y in [-0.72, 0.72] as [Float] {
            drum.addChildNode(k.cyl(R * 0.3, R * 0.06, k.accent, SCNVector3(0, y * R, 0), segments: 48))
            drum.addChildNode(k.cyl(R * 0.1, R * 0.16, k.dark, SCNVector3(0, y * R * 1.1, 0)))
            let l = k.sphere(R * 0.04, k.lamp, SCNVector3(0, y * R * 1.22, 0))
            k.blink(l, Double(y) * 0.5 + 0.5)
            drum.addChildNode(l)
        }
        k.guideRing(root)
        k.navLights(root, radius: R * 1.0, y: R * 0.04)
    }

    // MARK: 7 POLARIS: gestaffelte Scheiben mit Turm und Leuchtfeuer

    private static func polaris(_ k: Kit, _ root: SCNNode) {
        let R = k.R
        root.addChildNode(k.cyl(R, R * 0.06, k.hull, SCNVector3(0, -R * 0.12, 0), segments: 64))
        root.addChildNode(k.tube(R * 1.0, R * 1.006, R * 0.025, k.window, SCNVector3(0, -R * 0.12, 0)))
        root.addChildNode(k.tube(R * 0.9, R * 0.93, R * 0.07, k.accent, SCNVector3(0, -R * 0.12, 0)))
        var y = -R * 0.06
        for (r, h, m) in [(Float(0.7), Float(0.08), k.dark), (Float(0.5), Float(0.12), k.hull), (Float(0.32), Float(0.16), k.accent)] {
            root.addChildNode(k.cyl(R * r, R * h, m, SCNVector3(0, y + R * h / 2, 0), segments: 48))
            k.windowRing(root, radius: R * r, y: y + R * h / 2, count: Int(r * 40))
            y += R * h
        }
        root.addChildNode(k.cyl(R * 0.06, R * 0.5, k.hull, SCNVector3(0, y + R * 0.25, 0)))
        let beacon = k.sphere(R * 0.06, k.lamp, SCNVector3(0, y + R * 0.52, 0))
        beacon.runAction(.repeatForever(.sequence([.fadeOut(duration: 0.5), .fadeIn(duration: 0.5)])))
        root.addChildNode(beacon)
        // Andockbuchten am Rand der großen Scheibe
        for i in 0..<8 {
            let a = Float(i) / 8 * .pi * 2
            let l = k.box(R * 0.04, R * 0.02, R * 0.04, k.dock, SCNVector3(cos(a) * R * 0.8, -R * 0.08, sin(a) * R * 0.8))
            k.blink(l, Double(i) * 0.1)
            root.addChildNode(l)
        }
        k.navLights(root, radius: R * 1.02, y: -R * 0.08)
    }

    // MARK: 8 ANDROMEDA: großer Außenring, darin ein sechseckiger Rahmen um den Kern

    private static func andromeda(_ k: Kit, _ root: SCNNode) {
        let R = k.R
        root.addChildNode(k.torus(R * 0.93, R * 0.07, k.hull))
        root.addChildNode(k.torus(R * 0.93, R * 0.075, k.window).then { $0.scale = SCNVector3(1, 0.12, 1) })
        let core = SCNBox(width: CGFloat(R * 0.3), height: CGFloat(R * 0.3), length: CGFloat(R * 0.3), chamferRadius: CGFloat(R * 0.05))
        let coreNode = k.node(core, k.accent, SCNVector3(0, 0, 0))
        coreNode.runAction(.repeatForever(.rotateBy(x: 0, y: .pi * 2, z: 0, duration: 30)))
        root.addChildNode(coreNode)
        let hex = SCNNode()
        hex.runAction(.repeatForever(.rotateBy(x: 0, y: -.pi * 2, z: 0, duration: 75)))
        root.addChildNode(hex)
        for i in 0..<6 {
            let a0 = Float(i) / 6 * .pi * 2, a1 = Float(i + 1) / 6 * .pi * 2
            let p0 = SCNVector3(cos(a0) * R * 0.6, 0, sin(a0) * R * 0.6)
            let p1 = SCNVector3(cos(a1) * R * 0.6, 0, sin(a1) * R * 0.6)
            hex.addChildNode(k.rod(p0, p1, R * 0.05, k.dark))
            hex.addChildNode(k.box(R * 0.12, R * 0.12, R * 0.12, i % 2 == 0 ? k.accent : k.hull, p0))
            hex.addChildNode(k.rod(SCNVector3(cos(a0) * R * 0.15, 0, sin(a0) * R * 0.15), p0, R * 0.025, k.dark))
            let l = k.sphere(R * 0.025, k.lamp, SCNVector3(p0.x, R * 0.08, p0.z))
            k.blink(l, Double(i) * 0.15)
            hex.addChildNode(l)
        }
        // Speichen vom Rahmen zum festen Außenring
        for i in 0..<3 {
            let a = Float(i) / 3 * .pi * 2 + .pi / 6
            root.addChildNode(k.rod(SCNVector3(cos(a) * R * 0.66, 0, sin(a) * R * 0.66), SCNVector3(cos(a) * R * 0.87, 0, sin(a) * R * 0.87), R * 0.03, k.dark))
        }
        k.navLights(root, radius: R * 1.02, y: R * 0.05)
    }

    // MARK: 9 ELYSIUM: zwei gegeneinander geneigte Ringe und eine leuchtende Turmspitze

    private static func elysium(_ k: Kit, _ root: SCNNode) {
        let R = k.R
        let spire = SCNCone(topRadius: 0, bottomRadius: CGFloat(R * 0.14), height: CGFloat(R * 0.9))
        root.addChildNode(k.node(spire, k.hull, SCNVector3(0, R * 0.35, 0)))
        let base = SCNCone(topRadius: CGFloat(R * 0.14), bottomRadius: CGFloat(R * 0.05), height: CGFloat(R * 0.4))
        root.addChildNode(k.node(base, k.dark, SCNVector3(0, -R * 0.3, 0)))
        root.addChildNode(k.sphere(R * 0.17, k.accent, SCNVector3(0, -R * 0.05, 0)))
        k.windowRing(root, radius: R * 0.17, y: -R * 0.05, count: 14)
        let tip = k.sphere(R * 0.05, k.lamp, SCNVector3(0, R * 0.82, 0))
        tip.runAction(.repeatForever(.sequence([.fadeOut(duration: 0.8), .fadeIn(duration: 0.8)])))
        root.addChildNode(tip)
        root.addChildNode(k.torus(R * 0.12, R * 0.008, k.lamp, SCNVector3(0, R * 0.78, 0)))
        for (r, tilt, dur) in [(Float(0.95), Float(0.0), 70.0), (Float(0.66), Float(0.25), -50.0)] {
            let holder = SCNNode()
            holder.eulerAngles = SCNVector3(tilt, 0, tilt * 0.5)
            root.addChildNode(holder)
            let ring = SCNNode()
            ring.runAction(.repeatForever(.rotateBy(x: 0, y: CGFloat(dur > 0 ? 1 : -1) * .pi * 2, z: 0, duration: abs(dur))))
            holder.addChildNode(ring)
            ring.addChildNode(k.torus(R * r, R * 0.05, k.hull))
            ring.addChildNode(k.torus(R * r, R * 0.055, k.window).then { $0.scale = SCNVector3(1, 0.15, 1) })
            for i in 0..<4 {
                let a = Float(i) / 4 * .pi * 2 + (dur > 0 ? 0 : .pi / 4)
                ring.addChildNode(k.rod(SCNVector3(cos(a) * R * 0.17, 0, sin(a) * R * 0.17),
                                        SCNVector3(cos(a) * R * (r - 0.05), 0, sin(a) * R * (r - 0.05)), R * 0.02, k.dark))
                ring.addChildNode(k.sphere(R * 0.06, k.accent, SCNVector3(cos(a) * R * r, 0, sin(a) * R * r)))
            }
        }
        k.navLights(root, radius: R * 1.0, y: R * 0.06)
    }
}

private extension SCNNode {
    /// Knoten noch anpassen und zurückgeben (für einzeilige Aufbauten)
    func then(_ f: (SCNNode) -> Void) -> SCNNode {
        f(self)
        return self
    }
}
