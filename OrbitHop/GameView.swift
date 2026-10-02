import SwiftUI

struct GameView: View {
    @State private var game = Game()
    @State private var showShop = false
    @State private var world: World3D?
    @AppStorage(SoundFX.enabledKey) private var soundOn = true

    private let signal = Color(red: 79 / 255, green: 227 / 255, blue: 193 / 255)
    private let warn = Color(red: 1, green: 0.42, blue: 0.37)
    private let gold = Color(red: 1, green: 0.85, blue: 0.42)
    private let dim = Color(red: 0.55, green: 0.6, blue: 0.72)
    private let panel = Color(red: 0.02, green: 0.07, blue: 0.11)

    var body: some View {
        GeometryReader { geo in
            let insets = geo.safeAreaInsets
            let full = CGSize(width: geo.size.width + insets.leading + insets.trailing,
                              height: geo.size.height + insets.top + insets.bottom)

            TimelineView(.animation) { timeline in
                let _ = (game.insets = insets)
                let _ = game.step(date: timeline.date, size: full)
                let _ = world.map { w in
                    game.project = w.project
                    w.sync(game, size: full)
                }
                let loading = (world?.framesSynced ?? 0) < 3
                let frameDate = timeline.date
                ZStack {
                    if let world {
                        WorldView(world: world)
                            .ignoresSafeArea()
                            .allowsHitTesting(false)
                    }

                    // frameDate muss im Closure stehen, sonst hält SwiftUI den Canvas
                    // für unverändert und zeichnet ihn nie neu.
                    Canvas { context, size in
                        _ = frameDate
                        game.draw(context, size: size)
                    }
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { game.tap() }

                    hud
                        .allowsHitTesting(false)
                    if !game.started {
                        titleView
                    }
                    if game.started && game.phase != .over && !game.paused {
                        pauseButton
                    }
                    if game.paused {
                        pauseMenu
                    }
                    if game.phase == .over {
                        gameOverView
                    }
                    if loading {
                        loadingView
                    }
                }
            }
        }
        .background(Color.black.ignoresSafeArea())
        .onAppear {
            SoundFX.shared.prepare()
            // Welt erst nach dem ersten Bild aufbauen, damit der Ladebildschirm sichtbar ist
            if world == nil {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { world = World3D() }
            }
        }
        .fullScreenCover(isPresented: $showShop) {
            ShipShopView(profile: game.profile) {
                game.equip()
                showShop = false
            }
        }
        #if os(iOS)
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        #endif
    }

    // MARK: Hilfen

    private func label(_ text: String) -> Text {
        Text(text)
            .font(.system(size: 9, weight: .medium, design: .monospaced))
            .tracking(1.6)
    }

    private func precisionTier(_ accuracy: CGFloat) -> (String, Color) {
        if accuracy >= 0.9 { return ("PERFEKT", gold) }
        if accuracy >= 0.7 { return ("SEHR GUT", signal) }
        if accuracy >= 0.4 { return ("GUT", Color.white) }
        return ("KNAPP", dim)
    }

    private var status: (String, Color) {
        if !game.started { return ("SYSTEM BEREIT", signal) }
        if game.phase == .over { return ("SIGNAL VERLOREN", warn) }
        if game.departElapsed != nil { return ("ABHEBEN · TRIEBWERKE HOCHFAHREN", gold) }
        if game.phase == .docked { return ("HANGAR · STARTFREIGABE", signal) }
        if game.energy < 25 { return ("ENERGIE KRITISCH", warn) }
        if game.brakeFlash > 0 { return ("KOLLISION · TEMPO GEDROSSELT", warn) }
        if game.phase == .flying { return ("TRANSIT · SCHUB AKTIV", gold) }
        if game.inCone { return ("STARTFENSTER OFFEN", signal) }
        return ("ORBIT STABIL", Color(red: 0.45, green: 0.85, blue: 1))
    }

    private var missionClock: String {
        let t = Int(game.missionTime)
        return String(format: "%02d:%02d", t / 60, t % 60)
    }

    private func panelBackground(cut: CGFloat, edge: Color) -> some View {
        Chamfer(cut: cut)
            .fill(panel.opacity(0.72))
            .overlay(Chamfer(cut: cut).stroke(edge.opacity(0.45), lineWidth: 1))
    }

    // MARK: HUD

    private var hud: some View {
        VStack(spacing: 8) {
            topBar
            statusLine
            effectsRow
            precisionBadge
            Spacer()
            hint
            bottomBar
        }
        .padding(.horizontal, 14)
        .padding(.top, 6)
        .padding(.bottom, 12)
    }

    private var topBar: some View {
        let fraction = max(0, min(1, game.energy / game.maxEnergy))
        let lit = Int(ceil(fraction * 20))
        let barColor = hsl(Double(fraction) * 160, 0.8, 0.58)
        let low = game.energy < 25 && game.started && game.phase != .over
        let blink = low && Int(game.time * 4) % 2 == 0

        return HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                label("PLANETEN").foregroundStyle(dim)
                Text(String(format: "%03d", game.score))
                    .font(.system(size: 32, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                    .shadow(color: signal.opacity(0.7), radius: 8)
                label("REKORD \(String(format: "%03d", game.best))")
                    .foregroundStyle(signal.opacity(0.8))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(panelBackground(cut: 10, edge: signal))
            .overlay(alignment: .topTrailing) {
                Rectangle().fill(signal).frame(width: 16, height: 2)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    label("ENERGIE")
                    Spacer()
                    label(String(format: "%03d %%", Int(ceil(game.energy))))
                }
                .foregroundStyle(blink ? warn : dim)

                HStack(spacing: 3) {
                    ForEach(0..<20, id: \.self) { i in
                        Slant().fill(i < lit ? barColor : Color.white.opacity(0.08))
                    }
                }
                .frame(height: 14)
                .shadow(color: barColor.opacity(0.5), radius: 6)

                HStack(alignment: .bottom, spacing: 6) {
                    label(low ? "RESERVE · WARNUNG" : "ZELLE A · NOMINAL")
                        .foregroundStyle(low ? warn : signal.opacity(0.75))
                    Spacer()
                    HStack(alignment: .bottom, spacing: 2) {
                        ForEach(0..<8, id: \.self) { i in
                            Rectangle()
                                .fill(signal.opacity(0.6))
                                .frame(width: 2, height: 3 + 7 * abs(sin(game.time * 3 + CGFloat(i) * 0.9)))
                        }
                    }
                    .frame(height: 10, alignment: .bottom)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(panelBackground(cut: 10, edge: blink ? warn : signal))
            // Platz für den Pause-Knopf oben rechts
            if game.started && game.phase != .over {
                Color.clear.frame(width: 44, height: 44)
            }
        }
    }

    private var statusLine: some View {
        let (text, color) = status
        let dot = Int(game.time * 2) % 2 == 0
        return HStack(spacing: 6) {
            Rectangle().fill(color).frame(width: 6, height: 6).rotationEffect(.degrees(45)).opacity(dot ? 1 : 0.35)
            label(text).foregroundStyle(color).lineLimit(1).fixedSize()
            Rectangle().fill(color.opacity(0.3)).frame(height: 1)
            label("SEKTOR \(String(format: "%02d", game.score / 5 + 1)) · T+\(missionClock)")
                .foregroundStyle(dim)
                .lineLimit(1)
                .fixedSize()
        }
        .padding(.horizontal, 2)
    }

    // MARK: Pause

    private var pauseButton: some View {
        VStack {
            HStack {
                Spacer()
                Button {
                    game.paused = true
                } label: {
                    Image(systemName: "pause.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(signal)
                        .frame(width: 44, height: 44)
                        .background(Chamfer(cut: 8).fill(panel.opacity(0.8)))
                        .overlay(Chamfer(cut: 8).stroke(signal.opacity(0.6), lineWidth: 1))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.top, 6)
    }

    private func menuButton(_ title: String, _ icon: String, _ color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon).font(.system(size: 14, weight: .bold))
                Text(title)
                    .font(.system(size: 15, weight: .heavy, design: .monospaced))
                    .tracking(3)
            }
            .foregroundStyle(color)
            .frame(width: 230, height: 50)
            .background(Chamfer(cut: 10).fill(color.opacity(0.1)))
            .overlay(Chamfer(cut: 10).stroke(color.opacity(0.8), lineWidth: 1.2))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var pauseMenu: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
            VStack(spacing: 14) {
                label("SYSTEM ANGEHALTEN · T+\(missionClock)").foregroundStyle(dim)
                Text("PAUSE")
                    .font(.system(size: 34, weight: .heavy, design: .monospaced))
                    .tracking(6)
                    .foregroundStyle(.white)
                    .shadow(color: signal.opacity(0.6), radius: 12)
                    .padding(.bottom, 8)
                menuButton("WEITER", "play.fill", signal) { game.paused = false }
                menuButton("NEUSTART", "arrow.counterclockwise", gold) { game.restart() }
                menuButton("ABBRECHEN", "xmark", warn) { game.abort() }
                menuButton(soundOn ? "TON AN" : "TON AUS", soundOn ? "speaker.wave.2.fill" : "speaker.slash.fill", dim) {
                    soundOn.toggle()
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 26)
            .background(Chamfer(cut: 14).fill(panel.opacity(0.92)))
            .overlay(Chamfer(cut: 14).stroke(signal.opacity(0.45), lineWidth: 1))
            .overlay(Brackets(len: 14).stroke(signal, lineWidth: 2).padding(-6))
        }
    }

    private var loadingView: some View {
        ZStack {
            Color(red: 0.01, green: 0.015, blue: 0.04).ignoresSafeArea()
            VStack(spacing: 14) {
                label("NAV-SYSTEM // ORBITALTRANSFER").foregroundStyle(signal.opacity(0.8))
                Text("ORBIT HOP")
                    .font(.system(size: 46, weight: .heavy, design: .monospaced))
                    .tracking(4)
                    .foregroundStyle(.white)
                    .shadow(color: signal.opacity(0.7), radius: 14)
                Text("SYSTEME WERDEN GELADEN")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .tracking(3)
                    .foregroundStyle(signal)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .overlay(Brackets(len: 8).stroke(signal, lineWidth: 1.5))
            }
        }
    }

    private var effectsRow: some View {
        HStack(spacing: 6) {
            if game.wideConeLaunches > 0 { chip("×\(game.wideConeLaunches)", .wideCone) }
            if game.superBombs > 0 { chip("×\(game.superBombs)", .superBomb) }
            if game.rescueCharges > 0 { chip("×\(game.rescueCharges)", .rescue) }
            if game.overflow > 0 { chip("\(Int(game.overflow))%", .tech) }
            Spacer()
        }
        .frame(height: 20)
    }

    private func chip(_ text: String, _ kind: ItemKind) -> some View {
        let col = hsl(kind.hue, 0.85, 0.65)
        return HStack(spacing: 4) {
            Image(systemName: kind.symbol).font(.system(size: 9, weight: .bold))
            label(text)
        }
            .foregroundStyle(col)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Chamfer(cut: 5).fill(col.opacity(0.12)))
            .overlay(Chamfer(cut: 5).stroke(col.opacity(0.6), lineWidth: 1))
    }

    private var precisionBadge: some View {
        let show = game.time - game.lastLaunchTime < 1.4 && game.phase != .over && !game.dockLaunch
        let tier = precisionTier(game.lastAccuracy)
        return Text("\(tier.0) · \(Int(game.lastAccuracy * 100)) %")
            .font(.system(size: 18, weight: .bold, design: .monospaced))
            .tracking(2)
            .foregroundStyle(tier.1)
            .shadow(color: tier.1.opacity(0.6), radius: 8)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .overlay(Brackets(len: 8).stroke(tier.1.opacity(0.8), lineWidth: 1.5))
            .opacity(show ? 1 : 0)
            .padding(.top, 4)
    }

    private var hint: some View {
        Text("Tippe, wenn das Schiff im Kegel ist: je genauer in der Mitte, desto schneller. Außerhalb des Kegels und im Flug feuert ein Tipp die Bordwaffe, das kostet Energie.")
            .font(.system(size: 11, design: .monospaced))
            .multilineTextAlignment(.center)
            .foregroundStyle(dim)
            .padding(10)
            .background(panelBackground(cut: 8, edge: dim))
            .opacity(game.hintShown && game.started && game.phase != .docked ? 1 : 0)
    }

    private func readout(_ key: String, _ value: String, _ unit: String) -> some View {
        HStack(spacing: 6) {
            label(key).foregroundStyle(dim).frame(width: 36, alignment: .leading)
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white)
            label(unit).foregroundStyle(signal.opacity(0.75))
        }
    }

    private var bottomBar: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                label("TELEMETRIE").foregroundStyle(signal.opacity(0.8))
                Rectangle().fill(signal.opacity(0.3)).frame(width: 110, height: 1)
                readout("VEL", String(format: "%04d", Int(game.speed)), "M/S")
                readout("ZIEL", String(format: "%05d", Int(game.targetDistance)), "KM")
                readout("KURS", String(format: "%03d", game.headingDegrees), "GRD")
                readout("WAFFE", game.weapon.title, "\(Int(game.weaponCost))E")
                readout("TECH", "+\(game.runParts)", "⚙")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(panelBackground(cut: 8, edge: signal))
            Spacer()
            // Platz für das Radar, das im Canvas gezeichnet wird
            Color.clear.frame(width: 104, height: 100)
        }
    }

    // MARK: Titel und Game Over

    private var shipsButton: some View {
        Button {
            showShop = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "airplane")
                    .font(.system(size: 12, weight: .bold))
                    .rotationEffect(.degrees(-45))
                VStack(alignment: .leading, spacing: 1) {
                    Text("SCHIFFE")
                        .font(.system(size: 13, weight: .heavy, design: .monospaced))
                        .tracking(2)
                    label("\(game.ship.name) · STUFE \(game.ship.level) · ⚙ \(game.profile.parts)")
                        .foregroundStyle(dim)
                }
            }
            .foregroundStyle(gold)
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(Chamfer(cut: 8).fill(panel.opacity(0.85)))
            .overlay(Chamfer(cut: 8).stroke(gold.opacity(0.7), lineWidth: 1.2))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var soundButton: some View {
        Button {
            soundOn.toggle()
        } label: {
            Image(systemName: soundOn ? "speaker.wave.2.fill" : "speaker.slash.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(soundOn ? signal : dim)
                .frame(width: 48, height: 48)
                .background(Chamfer(cut: 8).fill(panel.opacity(0.85)))
                .overlay(Chamfer(cut: 8).stroke((soundOn ? signal : dim).opacity(0.7), lineWidth: 1.2))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(soundOn ? "Ton ausschalten" : "Ton einschalten")
    }

    private var titleView: some View {
        VStack(spacing: 14) {
            titleTexts
                .allowsHitTesting(false)
            Spacer()
            // unter dem Startplaneten
            tapPrompt
                .allowsHitTesting(false)
            HStack(spacing: 10) {
                shipsButton
                soundButton
            }
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 150)
        .padding(.bottom, 178)
    }

    private var tapPrompt: some View {
        let pulse = 0.75 + 0.25 * sin(Double(game.time) * 4)
        // dunkles Feld dahinter, damit der Text auch auf der hellen Startplattform lesbar bleibt
        return Text("TIPPEN ZUM STARTEN")
            .font(.system(size: 13, weight: .semibold, design: .monospaced))
            .tracking(3)
            .foregroundStyle(signal)
            .opacity(pulse)
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(Chamfer(cut: 6).fill(panel.opacity(0.8)))
            .overlay(Brackets(len: 8).stroke(signal.opacity(pulse), lineWidth: 1.5))
    }

    private var titleTexts: some View {
        VStack(spacing: 12) {
            label("NAV-SYSTEM // ORBITALTRANSFER")
                .foregroundStyle(signal.opacity(0.8))
            Text("ORBIT HOP")
                .font(.system(size: 50, weight: .heavy, design: .monospaced))
                .tracking(4)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .foregroundStyle(.white)
                .shadow(color: signal.opacity(0.7), radius: 14)
            HStack(spacing: 8) {
                Rectangle().fill(signal.opacity(0.5)).frame(width: 44, height: 1)
                label("V 2.0 · ALLE SYSTEME BEREIT").foregroundStyle(dim)
                Rectangle().fill(signal.opacity(0.5)).frame(width: 44, height: 1)
            }
        }
    }

    private var gameOverView: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .allowsHitTesting(false)
            VStack(spacing: 18) {
                gameOverPanel
                    .allowsHitTesting(false)
                shipsButton
            }
        }
    }

    private var gameOverPanel: some View {
        VStack(spacing: 14) {
            label("SYSTEM OFFLINE · T+\(missionClock)").foregroundStyle(warn.opacity(0.8))
            Text("ENERGIE LEER")
                .font(.system(size: 28, weight: .heavy, design: .monospaced))
                .tracking(2)
                .foregroundStyle(warn)
                .shadow(color: warn.opacity(0.6), radius: 10)
            Rectangle().fill(warn.opacity(0.35)).frame(height: 1)
            HStack(spacing: 34) {
                VStack(spacing: 3) {
                    Text(String(format: "%03d", game.score))
                        .font(.system(size: 32, weight: .bold, design: .monospaced))
                    label("PLANETEN").foregroundStyle(dim)
                }
                VStack(spacing: 3) {
                    Text(String(format: "%03d", game.best))
                        .font(.system(size: 32, weight: .bold, design: .monospaced))
                        .foregroundStyle(gold)
                    label("REKORD").foregroundStyle(dim)
                }
            }
            .foregroundStyle(.white)
            label("+\(game.runParts) TECH-TEILE · GESAMT ⚙ \(game.profile.parts)")
                .foregroundStyle(gold)
            Text("TIPPEN FÜR NEUSTART")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .tracking(2.5)
                .foregroundStyle(signal)
                .padding(.top, 4)
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 26)
        .background(Chamfer(cut: 14).fill(panel.opacity(0.92)))
        .overlay(Chamfer(cut: 14).stroke(warn.opacity(0.5), lineWidth: 1))
        .overlay(Brackets(len: 14).stroke(warn, lineWidth: 2).padding(-6))
    }
}

// MARK: - HUD-Formen

/// Rechteck mit abgeschrägter oberer linker und unterer rechter Ecke.
struct Chamfer: Shape {
    var cut: CGFloat = 10

    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX + cut, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - cut))
        p.addLine(to: CGPoint(x: r.maxX - cut, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.minY + cut))
        p.closeSubpath()
        return p
    }
}

/// Parallelogramm für die Segmente der Energieleiste.
struct Slant: Shape {
    func path(in r: CGRect) -> Path {
        let s = r.height * 0.35
        var p = Path()
        p.move(to: CGPoint(x: r.minX + s, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - s, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        p.closeSubpath()
        return p
    }
}

/// Vier Eckklammern.
struct Brackets: Shape {
    var len: CGFloat = 10

    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY + len))
        p.addLine(to: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.minX + len, y: r.minY))
        p.move(to: CGPoint(x: r.maxX - len, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY + len))
        p.move(to: CGPoint(x: r.maxX, y: r.maxY - len))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX - len, y: r.maxY))
        p.move(to: CGPoint(x: r.minX + len, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY - len))
        return p
    }
}

#Preview {
    GameView()
        .preferredColorScheme(.dark)
}
