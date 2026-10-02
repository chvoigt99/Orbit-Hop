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

        for _ in 0..<10 {
            let p = AVAudioPlayerNode()
            engine.attach(p)
            engine.connect(p, to: engine.mainMixerNode, format: format)
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

    private func makeHumNode() -> AVAudioSourceNode {
        let hum = self.hum
        let sr = Float(Self.rate)
        var phase: Float = 0
        var lfo: Float = 0
        var level: Float = 0
        var pitch: Float = 50
        var lp: Float = 0
        var lp2: Float = 0
        var seed: UInt32 = 22_222
        return AVAudioSourceNode(format: format) { _, _, frameCount, audioBufferList -> OSStatus in
            let abl = UnsafeMutableAudioBufferListPointer(audioBufferList)
            let targetLevel = hum.level
            let targetPitch = hum.pitch
            for frame in 0..<Int(frameCount) {
                // weich nachführen, damit es nie knackt
                level += (targetLevel - level) * 0.0004
                pitch += (targetPitch - pitch) * 0.0006
                lfo += 2 * .pi * 3.1 / sr
                if lfo > 2 * .pi { lfo -= 2 * .pi }
                let f = pitch * (1 + 0.012 * sin(lfo))
                phase += 2 * .pi * f / Synth.sr
                if phase > 2 * .pi { phase -= 2 * .pi }
                seed = seed &* 1_664_525 &+ 1_013_904_223
                let white = Float(Int32(bitPattern: seed)) / Float(Int32.max)
                // Rauschen zweifach tiefpassgefiltert: dumpfes Rauschen des Triebwerks
                let cut = min(0.2, 0.01 + pitch / 2500)
                lp += (white - lp) * cut
                lp2 += (lp - lp2) * cut
                let tone = 0.55 * sin(phase) + 0.25 * sin(2 * phase + 0.4) + 0.1 * sin(3 * phase + 1.1)
                let s = (tone * 0.6 + lp2 * 2.2) * level * 0.22
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

private enum Synth {
    static let sr: Double = 44_100

    static func buffer(for e: SoundFX.Effect, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let (dur, gain, gen) = recipe(e)
        let n = Int(dur * sr)
        guard let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(n)),
              let out = buf.floatChannelData?[0] else { return nil }
        buf.frameLength = AVAudioFrameCount(n)
        var peak: Double = 0.0001
        var samples = [Double](repeating: 0, count: n)
        for i in 0..<n {
            let s = gen(Double(i) / sr)
            samples[i] = s
            peak = max(peak, abs(s))
        }
        // auf einheitliche Spitze bringen, kurz ein- und ausblenden gegen Knackser
        let fade = Int(0.004 * sr)
        for i in 0..<n {
            var s = samples[i] / peak * gain
            if i < fade { s *= Double(i) / Double(fade) }
            if i > n - fade { s *= Double(n - i) / Double(fade) }
            out[i] = Float(s)
        }
        return buf
    }

    // Bausteine

    static func env(_ t: Double, attack: Double, decay: Double) -> Double {
        min(1, t / max(0.0001, attack)) * exp(-t / decay)
    }

    /// Oszillator mit gleitender Frequenz: hält seine eigene Phase
    final class Osc {
        var phase: Double = 0
        func sine(_ f: Double) -> Double {
            phase += 2 * .pi * f / Synth.sr
            return sin(phase)
        }
        /// weiches Rechteck (wenige Obertöne)
        func soft(_ f: Double) -> Double {
            phase += 2 * .pi * f / Synth.sr
            return sin(phase) + sin(3 * phase) / 3 + sin(5 * phase) / 5
        }
    }

    /// Rauschen mit Tiefpass, Grenzfrequenz pro Sample wählbar
    final class Noise {
        var seed: UInt64 = 0x9E37_79B9_7F4A_7C15
        var lp: Double = 0
        var lp2: Double = 0
        func white() -> Double {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Double(Int64(bitPattern: seed)) / Double(Int64.max)
        }
        func low(_ cutoff: Double) -> Double {
            let a = min(1, 2 * .pi * cutoff / Synth.sr)
            lp += (white() - lp) * a
            lp2 += (lp - lp2) * a
            return lp2
        }
    }

    static func lerp(_ a: Double, _ b: Double, _ k: Double) -> Double { a + (b - a) * min(1, max(0, k)) }

    /// Mehrere Töne nacheinander (Arpeggio)
    static func arpeggio(_ notes: [Double], step: Double, decay: Double) -> (Double) -> Double {
        let oscs = notes.map { _ in Osc() }
        return { t in
            var s = 0.0
            for (k, f) in notes.enumerated() {
                let tt = t - Double(k) * step
                guard tt >= 0 else { _ = oscs[k].sine(f); continue }
                let o = oscs[k]
                let v = o.sine(f) + 0.3 * sin(o.phase * 2)
                s += v * env(tt, attack: 0.004, decay: decay)
            }
            return s
        }
    }

    /// Explosion: Rauschen, dessen Klang dumpfer wird, plus tiefer Schlag
    static func explosion(length: Double, depth: Double) -> (Double) -> Double {
        let n = Noise(), o = Osc()
        return { t in
            let cutoff = lerp(3200, 180, t / length) * (0.6 + 0.4 * depth)
            let body = n.low(cutoff) * 3 * env(t, attack: 0.003, decay: length * 0.35)
            let thump = o.sine(lerp(90, 35, t / 0.4) * (1.2 - 0.4 * depth)) * env(t, attack: 0.002, decay: 0.12 + 0.18 * depth)
            return body + thump * (0.8 + 0.6 * depth)
        }
    }

    static func recipe(_ e: SoundFX.Effect) -> (Double, Double, (Double) -> Double) {
        switch e {
        case .launch:
            // Fauchen mit steigendem Ton
            let n = Noise(), o = Osc()
            return (0.75, 0.75, { t in
                let k = t / 0.75
                let whoosh = n.low(lerp(400, 4200, k * 2.2) * (1 - 0.6 * k)) * 3 * env(t, attack: 0.03, decay: 0.28)
                let tone = o.sine(lerp(160, 620, pow(min(1, k * 1.6), 0.7))) * env(t, attack: 0.01, decay: 0.18)
                return whoosh + tone * 0.6
            })
        case .perfect:
            // heller Zweiklang
            let a = Osc(), b = Osc()
            return (0.9, 0.55, { t in
                let s1 = a.sine(1318.5) * env(t, attack: 0.003, decay: 0.32)
                let tb = t - 0.07
                let s2 = tb > 0 ? b.sine(1975.5) * env(tb, attack: 0.003, decay: 0.38) : 0
                return s1 + s2 * 0.8
            })
        case .capture:
            // weicher Schlag und gleitender Ton nach oben
            let thump = Osc(), tone = Osc()
            return (0.6, 0.6, { t in
                let th = thump.sine(lerp(110, 55, t / 0.15)) * env(t, attack: 0.002, decay: 0.07)
                let f = lerp(330, 495, t / 0.12)
                let tn = (tone.sine(f) + 0.25 * sin(tone.phase * 2)) * env(t, attack: 0.01, decay: 0.2)
                return th * 1.2 + tn * 0.7
            })
        case .release:
            // Halteklammern lösen sich: metallisches Klacken
            let a = Osc(), b = Osc(), c = Osc(), n = Noise()
            return (0.5, 0.5, { t in
                let ring = a.sine(233) + 0.6 * b.sine(612) + 0.4 * c.sine(1047)
                let click = n.low(5000) * 4 * env(t, attack: 0.001, decay: 0.012)
                return ring * env(t, attack: 0.001, decay: 0.09) + click
            })
        case .item:
            return (0.6, 0.55, arpeggio([659.3, 880, 1318.5], step: 0.065, decay: 0.16))
        case .tech:
            return (0.8, 0.6, arpeggio([880, 1174.7, 1568, 2349.3], step: 0.06, decay: 0.2))
        case .bonus:
            // Plopp, wenn der Planet sein Item ausspuckt
            let o = Osc()
            return (0.25, 0.5, { t in
                o.sine(lerp(260, 900, t / 0.06)) * env(t, attack: 0.002, decay: 0.05)
            })
        case .cannon:
            let o = Osc(), n = Noise()
            return (0.14, 0.45, { t in
                o.soft(lerp(1100, 260, t / 0.08)) * env(t, attack: 0.001, decay: 0.035)
                    + n.low(6000) * 2 * env(t, attack: 0.001, decay: 0.01)
            })
        case .rocket:
            let n = Noise(), o = Osc()
            return (0.55, 0.55, { t in
                n.low(lerp(900, 2600, t / 0.3)) * 3 * env(t, attack: 0.02, decay: 0.2)
                    + o.sine(lerp(140, 90, t / 0.5)) * 0.4 * env(t, attack: 0.01, decay: 0.15)
            })
        case .railgun:
            let o = Osc(), r = Osc(), n = Noise()
            return (0.45, 0.6, { t in
                let zap = o.sine(lerp(2600, 180, pow(t / 0.25, 0.6))) * env(t, attack: 0.001, decay: 0.09)
                let ring = r.sine(1760) * 0.25 * env(t, attack: 0.002, decay: 0.15)
                return zap + ring + n.low(7000) * 1.5 * env(t, attack: 0.001, decay: 0.02)
            })
        case .bomb:
            let o = Osc()
            return (0.3, 0.55, { t in
                o.soft(lerp(180, 60, t / 0.15)) * env(t, attack: 0.002, decay: 0.07)
            })
        case .blast:
            return (0.8, 0.75, explosion(length: 0.8, depth: 0.4))
        case .bigBlast:
            return (1.6, 0.9, explosion(length: 1.6, depth: 1))
        case .hit:
            // Aufprall: Knirschen mit dumpfem Schlag
            let n = Noise(), o = Osc(), crackle = Noise()
            return (0.6, 0.8, { t in
                let grit = n.low(2400) * 3 * env(t, attack: 0.002, decay: 0.12)
                let flick = crackle.white() > 0.6 ? 1.0 : 0.25
                let thud = o.sine(lerp(85, 40, t / 0.25)) * env(t, attack: 0.002, decay: 0.14)
                return grit * flick + thud * 1.3
            })
        case .crack:
            let n = Noise(), o = Osc()
            return (0.4, 0.55, { t in
                n.low(lerp(3000, 600, t / 0.3)) * 3 * env(t, attack: 0.002, decay: 0.08)
                    + o.sine(lerp(140, 70, t / 0.2)) * 0.5 * env(t, attack: 0.002, decay: 0.06)
            })
        case .empty:
            // zwei kurze tiefe Brummer: keine Energie für die Waffe
            let o = Osc()
            return (0.26, 0.4, { t in
                let gate = (t < 0.08 || (t > 0.13 && t < 0.21)) ? 1.0 : 0
                return o.soft(110) * gate
            })
        case .warning:
            let o = Osc()
            return (0.36, 0.35, { t in
                let f = t < 0.16 ? 988.0 : 740.0
                let tt = t < 0.16 ? t : t - 0.18
                guard tt >= 0 else { return 0 }
                return o.sine(f) * env(tt, attack: 0.005, decay: 0.07)
            })
        case .gameOver:
            let down = Osc(), boom = explosion(length: 1.8, depth: 1)
            return (2.0, 0.9, { t in
                let fall = down.sine(lerp(440, 70, t / 1.4)) * env(t, attack: 0.01, decay: 0.6)
                return boom(t) + fall * 0.5
            })
        case .rescue:
            let o = Osc(), n = Noise()
            return (1.0, 0.75, { t in
                let rise = o.soft(lerp(180, 1100, t / 0.6)) * env(t, attack: 0.02, decay: 0.35)
                return rise * 0.6 + n.low(lerp(600, 5000, t / 0.5)) * 2.5 * env(t, attack: 0.05, decay: 0.3)
            })
        }
    }
}
