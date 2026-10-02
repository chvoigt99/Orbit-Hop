import AVFoundation
import Foundation

// MARK: - Sound

/// Weiche, musikalische Klänge, alle im Code erzeugt (keine Audiodateien).
/// Alle Töne liegen in D-Dur pentatonisch, damit sich überlagernde Effekte nie beißen.
/// Kurze Effekte liegen als fertige Puffer bereit und laufen über einen kleinen Pool von Abspielern
/// mit großem Hall. Darunter liegt ein leiser Klangteppich, der mit dem Flugtempo heller wird.
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
    private var buffers: [Effect: [AVAudioPCMBuffer]] = [:]
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

        // Effekte laufen über einen gemeinsamen Bus mit großem, weichem Hall
        engine.attach(fxBus)
        engine.attach(reverb)
        reverb.loadFactoryPreset(.largeHall)
        reverb.wetDryMix = 30
        engine.connect(fxBus, to: reverb, format: nil)
        engine.connect(reverb, to: engine.mainMixerNode, format: nil)
        for _ in 0..<14 {
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
            var made: [Effect: [AVAudioPCMBuffer]] = [:]
            for e in Effect.allCases {
                made[e] = (0..<Synth.variants(e)).compactMap { Synth.buffer(for: e, variant: $0, format: format) }
            }
            DispatchQueue.main.async { self.buffers = made }
        }
    }

    private func startEngine() {
        guard !engine.isRunning else { return }
        try? engine.start()
    }

    /// Effekt abspielen (nur vom Main-Thread). `variant` wählt eine bestimmte Variante,
    /// zum Beispiel den nächsten Ton der Melodie beim Einfangen; ohne Angabe zufällig.
    func play(_ effect: Effect, volume: CGFloat = 1, variant: Int? = nil) {
        guard Self.enabled, let list = buffers[effect], !list.isEmpty else { return }
        let buf = variant.map { list[(($0 % list.count) + list.count) % list.count] } ?? list.randomElement()!
        startEngine()
        guard engine.isRunning else { return }
        let p = players[nextPlayer]
        nextPlayer = (nextPlayer + 1) % players.count
        p.stop()
        p.volume = Float(max(0, min(1, volume)))
        p.scheduleBuffer(buf, at: nil, options: [], completionHandler: nil)
        p.play()
    }

    /// Klangteppich pro Frame setzen: `level` 0…1, `pitch` steigt mit dem Tempo (50 = Ruhe).
    func engineHum(level: CGFloat, pitch: CGFloat) {
        hum.level = Self.enabled ? Float(max(0, min(1, level))) : 0
        hum.pitch = Float(max(20, pitch))
    }

    /// Weicher Klangteppich statt Triebwerksbrummen: Grundton D und Quinte A aus leicht verstimmten
    /// Sinus-Paaren, die langsam schweben. Mit dem Tempo öffnet sich ein Filter, die Oktave kommt dazu.
    private func makeHumNode() -> AVAudioSourceNode {
        let hum = self.hum
        let sr = Float(Self.rate)
        let freqs: [Float] = [73.42, 73.62, 110.0, 110.3, 146.83, 220.0]
        var phases = [Float](repeating: 0, count: freqs.count)
        var level: Float = 0
        var bright: Float = 0
        var lfo: Float = 0
        var lp: Float = 0

        return AVAudioSourceNode(format: format) { _, _, frameCount, audioBufferList -> OSStatus in
            let abl = UnsafeMutableAudioBufferListPointer(audioBufferList)
            let targetLevel = hum.level
            let targetBright = min(1, max(0, (hum.pitch - 50) / 60))
            for frame in 0..<Int(frameCount) {
                level += (targetLevel - level) * 0.00008
                bright += (targetBright - bright) * 0.00005
                lfo += 2 * .pi * 0.11 / sr
                if lfo > 2 * .pi { lfo -= 2 * .pi }
                var s: Float = 0
                for i in 0..<freqs.count {
                    phases[i] += 2 * .pi * freqs[i] / sr
                    if phases[i] > 2 * .pi { phases[i] -= 2 * .pi }
                    // tiefe Töne immer, Oktave und Quinte darüber kommen mit dem Tempo
                    let w: Float = i < 4 ? 1 : 0.15 + 0.85 * bright
                    // leichte Obertöne, damit es nicht nach reinem Sinus klingt
                    let p = phases[i]
                    s += (sin(p) + 0.18 * sin(2 * p) + 0.06 * sin(3 * p)) * w
                }
                s *= 0.8 + 0.2 * sin(lfo)
                let cut = (0.02 + 0.06 * bright)
                lp += (s - lp) * cut
                let out = lp * level * 0.05
                for buffer in abl {
                    buffer.mData?.assumingMemoryBound(to: Float.self)[frame] = out
                }
            }
            return noErr
        }
    }
}

/// Zielwerte für den Klangteppich, vom Spiel geschrieben und vom Audio-Thread gelesen
private final class HumState {
    var level: Float = 0
    var pitch: Float = 50
}

// MARK: - Klangerzeugung

/// Kleiner Offline-Synthesizer. Jeder Effekt ist ein Rezept aus Bausteinen und wird einmal
/// in einen Puffer gerechnet.
private enum Synth {
    static let sr: Double = 44_100

    static func buffer(for e: SoundFX.Effect, variant: Int, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let (dur, gain, gen) = recipe(e, variant)
        let n = Int(dur * sr)
        guard let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(n)),
              let out = buf.floatChannelData?[0] else { return nil }
        buf.frameLength = AVAudioFrameCount(n)
        var samples = [Double](repeating: 0, count: n)
        var peak: Double = 0.0001
        // leichter Hochpass gegen Gleichanteil
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
            if i > n - fade * 8 { s *= Double(n - i) / Double(fade * 8) }
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

    // MARK: Tonleiter und Instrumente

    /// D-Dur pentatonisch: D E F# A B, über mehrere Oktaven
    static func note(_ degree: Int, octave: Int = 4) -> Double {
        let steps = [0, 2, 4, 7, 9]
        let d = ((degree % 5) + 5) % 5
        let o = octave + Int((Double(degree) / 5).rounded(.down))
        let semis = Double(steps[d] + (o - 4) * 12 + 2)   // D4 liegt 2 Halbtöne über C4
        return 261.63 * pow(2, semis / 12)
    }

    /// Weiches Zupfinstrument zwischen Kalimba und Marimba: Sinus mit kurzem FM-Anschlag
    static func pluck(_ f: Double, at start: Double = 0, decay: Double = 0.5, bright: Double = 1) -> (Double) -> Double {
        let fm = FM(), body = Sine()
        return { t in
            let tt = t - start
            guard tt >= 0 else { return 0 }
            let strike = fm.next(f, ratio: 4, index: 1.2 * bright * exp(-tt / 0.025))
            let tone = body.next(f) + 0.12 * sin(body.phase * 2)
            return (tone * 0.8 + strike * 0.35 * exp(-tt / 0.06)) * env(tt, attack: 0.004, decay: decay)
        }
    }

    /// Glocke mit sanftem FM-Glanz, klingt lange nach
    static func bell(_ f: Double, at start: Double = 0, decay: Double = 0.9) -> (Double) -> Double {
        let fm = FM()
        return { t in
            let tt = t - start
            guard tt >= 0 else { return 0 }
            let idx = 0.25 + 0.9 * exp(-tt / 0.15)
            return fm.next(f, ratio: 3, index: idx) * env(tt, attack: 0.006, decay: decay)
        }
    }

    /// Flächenklang: drei leicht verstimmte Sinus, schwillt an und ab
    static func pad(_ f: Double, attack: Double, decay: Double) -> (Double) -> Double {
        let a = Sine(), b = Sine(), c = Sine()
        return { t in
            let s = a.next(f) + b.next(f * 1.004) + 0.5 * c.next(f * 2.002)
            return s / 2.5 * env(t, attack: attack, decay: decay)
        }
    }

    /// Luftiger Hauch: sanft gefiltertes Rauschen, ohne Zischen
    static func breath(_ from: Double, _ to: Double, length: Double, seed: UInt64) -> (Double) -> Double {
        let n = Noise(seed), f = SVF()
        return { t in
            f.band(n.white(), glide(from, to, t / length), q: 0.9) * env(t, attack: length * 0.35, decay: length * 0.45)
        }
    }

    /// Weiches „Wumm“ statt Explosion: dumpfer Atem und tiefer, gleitender Ton
    static func whomp(length: Double, root: Double, seed: UInt64) -> (Double) -> Double {
        let n = Noise(seed), f = SVF(), low = Sine(), fifth = Sine()
        return { t in
            let k = t / length
            let air = f.low(n.white(), glide(1400, 150, k), q: 0.8) * env(t, attack: 0.01, decay: length * 0.3)
            let tone = low.next(glide(root * 2, root, t / 0.25)) * env(t, attack: 0.005, decay: length * 0.35)
            let shine = fifth.next(root * 3) * env(t, attack: 0.02, decay: length * 0.25) * 0.25
            return air * 1.3 + tone + shine
        }
    }

    static func sum(_ parts: [(Double) -> Double]) -> (Double) -> Double {
        { t in parts.reduce(0.0) { $0 + $1(t) } }
    }

    // MARK: Rezepte

    static func variants(_ e: SoundFX.Effect) -> Int {
        switch e {
        case .capture: return 8      // Melodie: jeder Planet spielt den nächsten Ton
        case .cannon, .crack, .hit, .item: return 3
        default: return 1
        }
    }

    static func recipe(_ e: SoundFX.Effect, _ v: Int) -> (Double, Double, (Double) -> Double) {
        switch e {
        case .launch:
            // sanftes Aufschwingen: Atem nach oben, dazu zwei Töne aufwärts
            return (1.4, 0.6, sum([breath(300, 2200, length: 0.7, seed: 11),
                                   pluck(note(3), decay: 0.5), pluck(note(0, octave: 5), at: 0.09, decay: 0.7)]))
        case .perfect:
            // funkelnder Dreiklang ganz oben
            return (1.8, 0.45, sum([bell(note(0, octave: 6), decay: 0.9), bell(note(2, octave: 6), at: 0.06, decay: 0.9),
                                    bell(note(3, octave: 6), at: 0.12, decay: 1.1)]))
        case .capture:
            // Melodie über acht Planeten, jeweils Ton plus leiser Grundton darunter
            let melody = [0, 2, 3, 4, 3, 5, 4, 7]
            let d = melody[v % melody.count]
            return (1.6, 0.6, sum([bell(note(d), decay: 0.8), pluck(note(d, octave: 3), decay: 0.6, bright: 0.4),
                                   pad(note(0, octave: 3), attack: 0.08, decay: 0.5)]))
        case .release:
            return (1.0, 0.5, sum([pluck(note(4, octave: 3), decay: 0.4), pluck(note(1, octave: 4), at: 0.12, decay: 0.6)]))
        case .item:
            let starts = [[0, 2, 3], [2, 3, 5], [3, 5, 7]][v % 3]
            return (1.2, 0.5, sum(starts.enumerated().map { pluck(note($0.element, octave: 5), at: Double($0.offset) * 0.07, decay: 0.45) }))
        case .tech:
            return (1.8, 0.5, sum([0, 2, 3, 5].enumerated().map { bell(note($0.element, octave: 5), at: Double($0.offset) * 0.08, decay: 0.8) }
                                  + [pad(note(0, octave: 4), attack: 0.2, decay: 0.7)]))
        case .bonus:
            return (0.8, 0.4, bell(note(1, octave: 5), decay: 0.4))
        case .cannon:
            return (0.5, 0.3, pluck(note([3, 4, 5][v % 3], octave: 5), decay: 0.12, bright: 0.6))
        case .rocket:
            return (0.9, 0.45, sum([breath(500, 1800, length: 0.5, seed: 21), pluck(note(0, octave: 4), decay: 0.3, bright: 0.5)]))
        case .railgun:
            // gläserner Strich nach unten
            let fm = FM()
            return (0.9, 0.4, { t in
                fm.next(glide(note(0, octave: 6), note(0, octave: 5), t / 0.25), ratio: 2, index: 0.8 * exp(-t / 0.2))
                    * env(t, attack: 0.005, decay: 0.3)
            })
        case .bomb:
            return (0.7, 0.45, pluck(note(0, octave: 3), decay: 0.3, bright: 0.5))
        case .blast:
            return (1.2, 0.6, whomp(length: 1.0, root: note(0, octave: 2), seed: 101))
        case .bigBlast:
            return (2.4, 0.75, sum([whomp(length: 2.0, root: note(0, octave: 1), seed: 202),
                                    pad(note(3, octave: 3), attack: 0.15, decay: 0.9)]))
        case .hit:
            // gedämpfter, hölzerner Schlag
            let n = Noise(31 + UInt64(v)), f = SVF(), body = Sine()
            let root = note([0, 4, 3][v % 3], octave: 2)
            return (0.7, 0.6, { t in
                let knock = f.low(n.white(), 700, q: 0.8) * env(t, attack: 0.002, decay: 0.04)
                return knock * 1.5 + body.next(glide(root * 1.5, root, t / 0.08)) * env(t, attack: 0.003, decay: 0.18)
            })
        case .crack:
            // zerbrechender Kristall: kurzes, helles Klingeln
            let a = [1, 2, 4][v % 3]
            return (0.9, 0.35, sum([pluck(note(a, octave: 5), decay: 0.18), pluck(note(a + 2, octave: 5), at: 0.03, decay: 0.2)]))
        case .empty:
            return (0.5, 0.3, sum([pluck(note(3, octave: 3), decay: 0.1, bright: 0.3),
                                   pluck(note(3, octave: 3), at: 0.13, decay: 0.1, bright: 0.3)]))
        case .warning:
            // zwei sanfte Glockentöne abwärts
            return (1.0, 0.35, sum([bell(note(3, octave: 5), decay: 0.25), bell(note(2, octave: 5), at: 0.2, decay: 0.3)]))
        case .gameOver:
            // ruhige Melodie abwärts über einem tiefen Klang
            let line = [5, 3, 2, 0]
            return (3.5, 0.6, sum(line.enumerated().map { bell(note($0.element, octave: 4), at: Double($0.offset) * 0.32, decay: 1.0) }
                                  + [pad(note(0, octave: 2), attack: 0.4, decay: 1.6), whomp(length: 1.4, root: note(0, octave: 1), seed: 303)]))
        case .rescue:
            return (1.8, 0.55, sum([0, 3, 5, 7, 10].enumerated().map { pluck(note($0.element, octave: 4), at: Double($0.offset) * 0.06, decay: 0.5) }
                                   + [breath(300, 2600, length: 0.9, seed: 51)]))
        }
    }
}
