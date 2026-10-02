import AVFoundation
import Foundation

// MARK: - Sound

/// Alle Klänge werden beim Start im Code erzeugt, es gibt keine Audiodateien.
/// Kurze Effekte liegen als fertige Puffer bereit und laufen über einen kleinen Pool von Abspielern.
/// Der Triebwerkston ist ein durchgehender Synthesizer, dessen Lautstärke und Tonhöhe das Spiel pro Frame setzt.
final class SoundFX {
    static let shared = SoundFX()

    static let enabledKey = "orbitHopSound"
    static var enabled: Bool {
        get { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    enum Effect: CaseIterable {
        case launch, perfect, capture, release, item, tech, bonus
        case cannon, rocket, railgun, bomb
        case blast, bigBlast, hit, crack, empty, warning, gameOver, rescue
    }

    private static let rate: Double = 44_100
    private let engine = AVAudioEngine()
    private let format = AVAudioFormat(standardFormatWithSampleRate: SoundFX.rate, channels: 1)!
    private var players: [AVAudioPlayerNode] = []
    private let fxBus = AVAudioMixerNode()
    private let reverb = AVAudioUnitReverb()
    private var nextPlayer = 0
    private var buffers: [Effect: AVAudioPCMBuffer] = [:]
    private let hum = HumState()
    private var started = false

    private init() {}

    /// Einmal beim App-Start aufrufen. Die Klänge werden im Hintergrund erzeugt.
    func prepare() {
        guard !started else { return }
        started = true
        let session = AVAudioSession.sharedInstance()
        // .ambient: mischt sich mit Musik anderer Apps und folgt dem Stummschalter
        try? session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
        try? session.setActive(true)

        // Effekte laufen über einen gemeinsamen Bus mit etwas Hall, das gibt Raum statt trockener Töne
        engine.attach(fxBus)
        engine.attach(reverb)
        reverb.loadFactoryPreset(.mediumHall)
        reverb.wetDryMix = 16
        engine.connect(fxBus, to: reverb, format: nil)
        engine.connect(reverb, to: engine.mainMixerNode, format: nil)
        for _ in 0..<12 {
            let p = AVAudioPlayerNode()
            engine.attach(p)
            engine.connect(p, to: fxBus, format: format)
            players.append(p)
        }
        let humNode = makeHumNode()
        engine.attach(humNode)
        engine.connect(humNode, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = 0.9
        engine.prepare()
        startEngine()

        NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil,
                                               queue: .main) { [weak self] _ in self?.startEngine() }
        NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine,
                                               queue: .main) { [weak self] _ in self?.startEngine() }

        let format = self.format
        DispatchQueue.global(qos: .userInitiated).async {
            var made: [Effect: AVAudioPCMBuffer] = [:]
            for e in Effect.allCases {
                if let b = Synth.buffer(for: e, format: format) { made[e] = b }
            }
            DispatchQueue.main.async { self.buffers = made }
        }
    }

    private func startEngine() {
        guard !engine.isRunning else { return }
        try? engine.start()
    }

    /// Effekt abspielen (nur vom Main-Thread)
    func play(_ effect: Effect, volume: CGFloat = 1) {
        guard Self.enabled, let buf = buffers[effect] else { return }
        startEngine()
        guard engine.isRunning else { return }
        let p = players[nextPlayer]
        nextPlayer = (nextPlayer + 1) % players.count
        p.stop()
        p.volume = Float(max(0, min(1, volume)))
        p.scheduleBuffer(buf, at: nil, options: [], completionHandler: nil)
        p.play()
    }

    /// Triebwerkston pro Frame setzen: `level` 0…1, `pitch` in Hz. Die Werte werden im Synth weich angeglichen.
    func engineHum(level: CGFloat, pitch: CGFloat) {
        hum.level = Self.enabled ? Float(max(0, min(1, level))) : 0
        hum.pitch = Float(max(20, pitch))
    }


    /// Triebwerk: zwei leicht verstimmte Sägezähne mit Sub-Oktave durch einen resonanten Tiefpass,
    /// dazu bandgefiltertes Rauschen als Fauchen. Wird mit der Last heller und lauter.
    private func makeHumNode() -> AVAudioSourceNode {
        let hum = self.hum
        let sr = Float(Self.rate)
        var t1: Float = 0, t2: Float = 0.37, sub: Float = 0
        var level: Float = 0
        var pitch: Float = 50
        var lp1: Float = 0, lp2: Float = 0
        var bp1: Float = 0, bp2: Float = 0
        var seed: UInt32 = 22_222
        var wobble: Float = 0

        func blep(_ t: Float, _ dt: Float) -> Float {
            if t < dt { let x = t / dt; return x + x - x * x - 1 }
            if t > 1 - dt { let x = (t - 1) / dt; return x * x + x + x + 1 }
            return 0
        }

        return AVAudioSourceNode(format: format) { _, _, frameCount, audioBufferList -> OSStatus in
            let abl = UnsafeMutableAudioBufferListPointer(audioBufferList)
            let targetLevel = hum.level
            let targetPitch = hum.pitch
            for frame in 0..<Int(frameCount) {
                level += (targetLevel - level) * 0.0004
                pitch += (targetPitch - pitch) * 0.0006
                wobble += 2 * .pi * 0.7 / sr
                if wobble > 2 * .pi { wobble -= 2 * .pi }
                let f = pitch * (1 + 0.006 * sin(wobble))

                let d1 = f / sr, d2 = f * 1.007 / sr
                t1 += d1; if t1 >= 1 { t1 -= 1 }
                t2 += d2; if t2 >= 1 { t2 -= 1 }
                sub += 2 * .pi * f * 0.5 / sr; if sub > 2 * .pi { sub -= 2 * .pi }
                let saw = (2 * t1 - 1 - blep(t1, d1)) + (2 * t2 - 1 - blep(t2, d2))
                let raw = saw * 0.35 + sin(sub) * 0.6

                // Tiefpass (zweistufig), Grenzfrequenz steigt mit Last und Tonhöhe
                let cut = min(0.35, (180 + level * 900 + pitch * 5) * 2 * .pi / sr)
                lp1 += (raw - lp1) * cut
                lp2 += (lp1 - lp2) * cut

                seed = seed &* 1_664_525 &+ 1_013_904_223
                let white = Float(Int32(bitPattern: seed)) / Float(Int32.max)
                // Fauchen: Rauschen zwischen zwei Tiefpässen als einfacher Bandpass
                let bc = min(0.5, (900 + pitch * 18) * 2 * .pi / sr)
                bp1 += (white - bp1) * bc
                bp2 += (bp1 - bp2) * bc * 0.35
                let hiss = (bp1 - bp2) * (0.15 + 0.6 * level)

                let mix = (lp2 * 0.9 + hiss) * level * 0.5
                let s = tanh(mix * 1.6) * 0.42
                for buffer in abl {
                    buffer.mData?.assumingMemoryBound(to: Float.self)[frame] = s
                }
            }
            return noErr
        }
    }
}

/// Zielwerte für den Triebwerkston, vom Spiel geschrieben und vom Audio-Thread gelesen
private final class HumState {
    var level: Float = 0
    var pitch: Float = 50
}

// MARK: - Klangerzeugung

/// Kleiner Offline-Synthesizer: Sägezahn, FM, resonantes Filter, Sättigung, Körnung.
/// Jeder Effekt ist ein Rezept aus diesen Bausteinen und wird einmal in einen Puffer gerechnet.
private enum Synth {
    static let sr: Double = 44_100

    static func buffer(for e: SoundFX.Effect, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let (dur, gain, gen) = recipe(e)
        let n = Int(dur * sr)
        guard let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(n)),
              let out = buf.floatChannelData?[0] else { return nil }
        buf.frameLength = AVAudioFrameCount(n)
        var samples = [Double](repeating: 0, count: n)
        var peak: Double = 0.0001
        // leichter Hochpass gegen Gleichanteil und Rumpeln unter 30 Hz
        var hpIn = 0.0, hpOut = 0.0
        let hpA = 1 / (1 + 2 * .pi * 30 / sr)
        for i in 0..<n {
            let x = gen(Double(i) / sr)
            hpOut = hpA * (hpOut + x - hpIn)
            hpIn = x
            samples[i] = hpOut
            peak = max(peak, abs(hpOut))
        }
        let fade = Int(0.003 * sr)
        for i in 0..<n {
            var s = samples[i] / peak * gain
            if i < fade { s *= Double(i) / Double(fade) }
            if i > n - fade * 4 { s *= Double(n - i) / Double(fade * 4) }
            out[i] = Float(s)
        }
        return buf
    }

    // MARK: Bausteine

    static func env(_ t: Double, attack: Double, decay: Double) -> Double {
        guard t >= 0 else { return 0 }
        return min(1, t / max(0.0001, attack)) * exp(-t / decay)
    }

    static func lerp(_ a: Double, _ b: Double, _ k: Double) -> Double { a + (b - a) * min(1, max(0, k)) }

    /// exponentielle Kurve zwischen zwei Frequenzen (klingt natürlicher als linear)
    static func glide(_ a: Double, _ b: Double, _ k: Double) -> Double { a * pow(b / a, min(1, max(0, k))) }

    /// Sättigung: rundet Spitzen ab und fügt Obertöne hinzu
    static func drive(_ x: Double, _ amount: Double) -> Double { tanh(x * amount) / tanh(amount) }

    final class Sine {
        var phase: Double = 0
        func next(_ f: Double) -> Double {
            phase += 2 * .pi * f / Synth.sr
            if phase > 2 * .pi { phase -= 2 * .pi }
            return sin(phase)
        }
    }

    /// Bandbegrenzter Sägezahn (PolyBLEP), Grundlage für satte Synth-Klänge
    final class Saw {
        var t: Double
        init(_ start: Double = 0) { t = start }
        func next(_ f: Double) -> Double {
            let dt = f / Synth.sr
            t += dt
            if t >= 1 { t -= 1 }
            var v = 2 * t - 1
            if t < dt { let x = t / dt; v -= x + x - x * x - 1 }
            else if t > 1 - dt { let x = (t - 1) / dt; v -= x * x + x + x + 1 }
            return v
        }
    }

    /// Mehrere verstimmte Sägezähne: breiter, schwebender Klang
    final class SawStack {
        let saws: [Saw]
        let detune: [Double]
        init(voices: Int = 3, spread: Double = 0.012) {
            saws = (0..<voices).map { Saw(Double($0) * 0.31) }
            detune = (0..<voices).map { 1 + spread * (Double($0) - Double(voices - 1) / 2) }
        }
        func next(_ f: Double) -> Double {
            var s = 0.0
            for (o, d) in zip(saws, detune) { s += o.next(f * d) }
            return s / Double(saws.count)
        }
    }

    /// Zwei-Operator-FM: metallische Glocken, Laser, Klonks
    final class FM {
        var pc: Double = 0, pm: Double = 0
        func next(_ f: Double, ratio: Double, index: Double) -> Double {
            pm += 2 * .pi * f * ratio / Synth.sr
            pc += 2 * .pi * f / Synth.sr
            if pm > 2 * .pi { pm -= 2 * .pi }
            if pc > 2 * .pi { pc -= 2 * .pi }
            return sin(pc + index * sin(pm))
        }
    }

    /// Zustandsvariablen-Filter (TPT), stabil auch bei schnellen Sweeps und hoher Resonanz
    final class SVF {
        var ic1 = 0.0, ic2 = 0.0
        /// liefert (Tiefpass, Bandpass, Hochpass)
        func run(_ x: Double, _ cutoff: Double, q: Double) -> (Double, Double, Double) {
            let fc = min(cutoff, Synth.sr * 0.45)
            let g = tan(.pi * fc / Synth.sr)
            let k = 1 / max(0.5, q)
            let a1 = 1 / (1 + g * (g + k))
            let a2 = g * a1
            let a3 = g * a2
            let v3 = x - ic2
            let v1 = a1 * ic1 + a2 * v3
            let v2 = ic2 + a2 * ic1 + a3 * v3
            ic1 = 2 * v1 - ic1
            ic2 = 2 * v2 - ic2
            return (v2, v1, x - k * v1 - v2)
        }
        func low(_ x: Double, _ c: Double, q: Double = 0.7) -> Double { run(x, c, q: q).0 }
        func band(_ x: Double, _ c: Double, q: Double = 2) -> Double { run(x, c, q: q).1 }
        func high(_ x: Double, _ c: Double, q: Double = 0.7) -> Double { run(x, c, q: q).2 }
    }

    final class Noise {
        var seed: UInt64
        init(_ seed: UInt64 = 0x9E37_79B9_7F4A_7C15) { self.seed = seed }
        func white() -> Double {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Double(Int64(bitPattern: seed)) / Double(Int64.max)
        }
        /// zufällige kurze Impulse: Knistern, Splitter, Geröll
        func crackle(density: Double) -> Double {
            let w = white()
            guard abs(w) > 1 - density / Synth.sr * 2 else { return 0 }
            return w < 0 ? -1 : 1
        }
    }

    // MARK: Zusammengesetzte Klänge

    /// Explosion: Druckwelle (tiefer Schlag mit fallender Tonhöhe), Körper aus resonant gefiltertem
    /// Rauschen, dazu nachrieselnde Trümmer. `size` 0…1.
    static func explosion(length: Double, size: Double, seed: UInt64) -> (Double) -> Double {
        let n = Noise(seed), deb = Noise(seed &+ 7), f1 = SVF(), f2 = SVF(), fd = SVF(), sub = Sine()
        return { t in
            let k = t / length
            let boom = sub.next(glide(110 - 40 * size, 32, t / 0.5)) * env(t, attack: 0.002, decay: 0.16 + 0.25 * size)
            let body = f1.low(n.white(), glide(4500, 160, pow(k, 0.6)), q: 1.4)
            let roar = f2.band(n.white(), glide(900, 220, k), q: 1.2)
            let bodyEnv = env(t, attack: 0.004, decay: length * (0.22 + 0.12 * size))
            let debris = fd.band(deb.crackle(density: 900 * (1 - k)), 2600, q: 3) * env(t - 0.05, attack: 0.05, decay: length * 0.35)
            let s = boom * (1.1 + 0.8 * size) + (body * 1.6 + roar * 1.2) * bodyEnv + debris * 0.5
            return drive(s, 1.8 + size)
        }
    }

    /// Glocke aus FM, klingt metallisch und hell
    static func bell(_ f: Double, at start: Double, decay: Double, ratio: Double = 3.5, index: Double = 2.2) -> (Double) -> Double {
        let fm = FM()
        return { t in
            let tt = t - start
            guard tt >= 0 else { return 0 }
            let e = env(tt, attack: 0.002, decay: decay)
            return fm.next(f, ratio: ratio, index: index * (0.3 + 0.7 * exp(-tt / (decay * 0.4)))) * e
        }
    }

    static func recipe(_ e: SoundFX.Effect) -> (Double, Double, (Double) -> Double) {
        switch e {
        case .launch:
            // Katapult: tiefer Schub, Sägezahn-Sweep durch sich öffnenden Filter, Düsenfauchen
            let stack = SawStack(voices: 4, spread: 0.018), f = SVF(), n = Noise(11), fn = SVF(), sub = Sine()
            return (1.0, 0.8, { t in
                let k = t / 1.0
                let tone = f.low(stack.next(glide(55, 190, pow(k * 1.4, 0.6))), glide(250, 5200, min(1, k * 2.2)) * (1 - 0.5 * k), q: 2.2)
                let jet = fn.band(n.white(), glide(600, 3800, k * 1.8), q: 1.6)
                let thump = sub.next(glide(90, 45, t / 0.2)) * env(t, attack: 0.002, decay: 0.09)
                let s = tone * env(t, attack: 0.015, decay: 0.32) + jet * 1.4 * env(t, attack: 0.04, decay: 0.3) + thump * 1.2
                return drive(s, 2.2)
            })
        case .perfect:
            // heller FM-Zweiklang mit Schimmer
            let b1 = bell(1318.5, at: 0, decay: 0.45), b2 = bell(1975.5, at: 0.075, decay: 0.55)
            let b3 = bell(3951, at: 0.075, decay: 0.25, ratio: 1.41, index: 1.2)
            return (1.1, 0.55, { t in b1(t) + b2(t) * 0.85 + b3(t) * 0.25 })
        case .capture:
            // Traktorstrahl rastet ein: Akkord gleitet nach unten in Position, weicher Schlag, Glocke
            let a = SawStack(voices: 3, spread: 0.01), b = SawStack(voices: 3, spread: 0.01), f = SVF(), sub = Sine()
            let ding = bell(659.3, at: 0.06, decay: 0.35, ratio: 2, index: 1.4)
            return (0.9, 0.65, { t in
                let k = t / 0.18
                let chord = a.next(glide(392, 196, k)) + b.next(glide(587, 293.7, k))
                let pad = f.low(chord, glide(3000, 700, t / 0.4), q: 3) * env(t, attack: 0.01, decay: 0.22)
                let thump = sub.next(glide(120, 50, t / 0.12)) * env(t, attack: 0.002, decay: 0.08)
                return drive(pad * 0.8 + thump * 1.3 + ding(t) * 0.5, 1.6)
            })
        case .release:
            // Halteklammern lösen sich: metallischer Klonk, dann zischende Hydraulik
            let fm = FM(), fm2 = FM(), n = Noise(5), f = SVF()
            return (0.9, 0.6, { t in
                let clank = fm.next(180, ratio: 1.41, index: 4 * exp(-t / 0.03)) * env(t, attack: 0.001, decay: 0.1)
                let ring = fm2.next(523, ratio: 2.76, index: 1.5) * env(t, attack: 0.001, decay: 0.25) * 0.3
                let hiss = f.band(n.white(), glide(5000, 2200, t / 0.6), q: 1.5) * env(t - 0.05, attack: 0.03, decay: 0.22)
                return drive(clank + ring + hiss * 1.2, 1.5)
            })
        case .item:
            let notes = [659.3, 987.8, 1318.5]
            let bells = notes.enumerated().map { bell($0.element, at: Double($0.offset) * 0.07, decay: 0.28, ratio: 2, index: 1.6) }
            return (0.75, 0.55, { t in bells.reduce(0.0) { $0 + $1(t) } })
        case .tech:
            let notes = [880, 1318.5, 1760, 2637]
            let bells = notes.enumerated().map { bell($0.element, at: Double($0.offset) * 0.06, decay: 0.32, ratio: 3.5, index: 2) }
            let shimmer = bell(5274, at: 0.2, decay: 0.3, ratio: 1.41, index: 0.8)
            return (1.0, 0.6, { t in bells.reduce(0.0) { $0 + $1(t) } + shimmer(t) * 0.3 })
        case .bonus:
            // Plopp mit resonantem Filter-Sweep
            let s = Saw(), f = SVF()
            return (0.35, 0.55, { t in
                f.low(s.next(glide(140, 420, t / 0.08)), glide(300, 3500, t / 0.07), q: 6) * env(t, attack: 0.002, decay: 0.07)
            })
        case .cannon:
            // Laser: FM mit stark fallender Tonhöhe
            let fm = FM(), n = Noise(3), f = SVF()
            return (0.22, 0.5, { t in
                let pew = fm.next(glide(1900, 240, t / 0.11), ratio: 0.5, index: 3 * exp(-t / 0.04)) * env(t, attack: 0.001, decay: 0.05)
                let click = f.high(n.white(), 3000) * env(t, attack: 0.0005, decay: 0.006)
                return drive(pew + click * 0.6, 1.8)
            })
        case .rocket:
            // Zündung, dann fauchender Schub, der davonzieht
            let n = Noise(9), f = SVF(), fi = SVF(), saw = SawStack(voices: 2, spread: 0.03), fl = SVF(), n2 = Noise(4)
            return (0.75, 0.6, { t in
                let ignite = fi.high(n2.white(), 2000) * env(t, attack: 0.001, decay: 0.012)
                let thrust = f.band(n.white(), glide(700, 2400, t / 0.4), q: 2.5) * env(t, attack: 0.02, decay: 0.25)
                let rumble = fl.low(saw.next(glide(70, 50, t / 0.6)), 400, q: 1.5) * env(t, attack: 0.01, decay: 0.2)
                return drive(ignite * 0.8 + thrust * 1.6 + rumble * 0.6, 2)
            })
        case .railgun:
            // elektrischer Schuss: heller FM-Zap, Knall und nachklingendes Sirren
            let fm = FM(), ring = FM(), n = Noise(21), f = SVF()
            return (0.6, 0.65, { t in
                let zap = fm.next(glide(3200, 140, pow(t / 0.22, 0.5)), ratio: 1.5, index: 5 * exp(-t / 0.05)) * env(t, attack: 0.001, decay: 0.1)
                let crack = f.high(n.white(), 1500, q: 1) * env(t, attack: 0.0005, decay: 0.02)
                let sing = ring.next(1760, ratio: 2.01, index: 0.6) * env(t, attack: 0.003, decay: 0.2) * 0.25
                return drive(zap + crack + sing, 2.2)
            })
        case .bomb:
            // dumpfes Abfeuern
            let saw = Saw(), f = SVF(), n = Noise(13), fn = SVF()
            return (0.35, 0.55, { t in
                let thunk = f.low(saw.next(glide(160, 55, t / 0.12)), 500, q: 2) * env(t, attack: 0.002, decay: 0.08)
                let puff = fn.low(n.white(), 1200) * env(t, attack: 0.002, decay: 0.04)
                return drive(thunk * 1.3 + puff, 1.8)
            })
        case .blast:
            return (1.0, 0.8, explosion(length: 1.0, size: 0.4, seed: 101))
        case .bigBlast:
            return (2.0, 0.9, explosion(length: 2.0, size: 1, seed: 202))
        case .hit:
            // Aufprall auf Fels: metallischer Schlag, Knirschen, Splitter
            let fm = FM(), n = Noise(31), f = SVF(), deb = Noise(37), fd = SVF(), sub = Sine()
            return (0.8, 0.85, { t in
                let clang = fm.next(140, ratio: 1.73, index: 3 * exp(-t / 0.05)) * env(t, attack: 0.001, decay: 0.12)
                let grit = f.band(n.white(), glide(2500, 700, t / 0.3), q: 1.2) * env(t, attack: 0.002, decay: 0.12)
                let chips = fd.band(deb.crackle(density: 1200), 3200, q: 4) * env(t, attack: 0.01, decay: 0.2)
                let thud = sub.next(glide(80, 38, t / 0.25)) * env(t, attack: 0.002, decay: 0.14)
                return drive(clang * 0.7 + grit * 1.4 + chips * 0.5 + thud * 1.3, 2.2)
            })
        case .crack:
            // Asteroid zerbricht: Knacken und Geröll
            let n = Noise(41), f = SVF(), deb = Noise(43), fd = SVF(), sub = Sine()
            return (0.6, 0.6, { t in
                let snap = f.band(n.white(), glide(3500, 900, t / 0.2), q: 1.5) * env(t, attack: 0.001, decay: 0.06)
                let rubble = fd.band(deb.crackle(density: 1500 * exp(-t / 0.2)), 2000, q: 3) * env(t, attack: 0.005, decay: 0.18)
                let thud = sub.next(glide(110, 55, t / 0.15)) * env(t, attack: 0.002, decay: 0.06)
                return drive(snap * 1.5 + rubble * 0.7 + thud * 0.7, 2)
            })
        case .empty:
            // gesperrt: zwei kurze, gefilterte Brummer
            let s = SawStack(voices: 2, spread: 0.02), f = SVF()
            return (0.3, 0.4, { t in
                let gate = (t < 0.09 || (t > 0.14 && t < 0.23)) ? 1.0 : 0
                return f.low(s.next(98), 900, q: 2) * gate
            })
        case .warning:
            // Alarm: zwei Töne mit Rechteck-Charakter
            let a = Saw(), b = Saw(0.5), f = SVF()
            return (0.4, 0.35, { t in
                let freq = t < 0.17 ? 988.0 : 740.0
                let tt = t < 0.17 ? t : t - 0.19
                guard tt >= 0 else { return 0 }
                let pulse = a.next(freq) - b.next(freq)
                return f.low(pulse, 3200, q: 1) * env(tt, attack: 0.004, decay: 0.08)
            })
        case .gameOver:
            // Systeme fahren herunter, dann große Explosion
            let stack = SawStack(voices: 4, spread: 0.02), f = SVF(), boom = explosion(length: 2.0, size: 1, seed: 303)
            return (2.4, 0.9, { t in
                let down = f.low(stack.next(glide(330, 40, t / 1.6)), glide(4000, 200, t / 1.4), q: 3) * env(t, attack: 0.01, decay: 0.7)
                return boom(t) * 0.9 + down * 0.6
            })
        case .rescue:
            // Nachbrenner: steigender Sägezahn-Chor und Düsenfauchen
            let stack = SawStack(voices: 4, spread: 0.02), f = SVF(), n = Noise(51), fn = SVF()
            return (1.2, 0.75, { t in
                let rise = f.low(stack.next(glide(110, 440, t / 0.7)), glide(500, 6000, t / 0.5), q: 2.5) * env(t, attack: 0.02, decay: 0.45)
                let jet = fn.band(n.white(), glide(500, 4000, t / 0.6), q: 1.5) * env(t, attack: 0.04, decay: 0.35)
                return drive(rise * 0.9 + jet * 1.5, 2)
            })
        }
    }
}
