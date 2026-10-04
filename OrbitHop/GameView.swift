import SwiftUI
import QuartzCore

struct GameView: View {
    @State private var game = Game()
    @State private var showShop = false
    @State private var showMissions = false
    @State private var world: World3D?
    @State private var loop = GameLoop()
    @State private var sample = HUDSample()
    @AppStorage(SoundFX.enabledKey) private var soundOn = true

    private let signal = Color(red: 79 / 255, green: 227 / 255, blue: 193 / 255)
    private let warn = Color(red: 1, green: 0.42, blue: 0.37)
    private let gold = Color(red: 1, green: 0.85, blue: 0.42)
    private let dim = Color(red: 0.55, green: 0.6, blue: 0.72)
    private let panel = Color(red: 0.02, green: 0.07, blue: 0.11)
    private let daily = Color(red: 0.72, green: 0.6, blue: 1)

    var body: some View {
        GeometryReader { geo in
            let insets = geo.safeAreaInsets
            let full = CGSize(width: geo.size.width + insets.leading + insets.trailing,
                              height: geo.size.height + insets.top + insets.bottom)

            // Simulation und 3D-Welt laufen im Bildschirmtakt (GameLoop). Früher hingen sie an der TimelineView,
            // und jedes Bild, das SwiftUI ausließ, stand die Welt still, obwohl SceneKit weiterzeichnete: Ruckeln.
            let _ = loop.configure(size: full, insets: insets, paused: worldCovered)
            // Werft und Missionen liegen als Vollbild darüber: dann steht die Welt still, statt unsichtbar
            // weiterzurechnen und neben der Werft-Vorschau eine zweite 3D-Szene zu zeichnen
            ZStack {
                if let world {
                    WorldView(world: world, paused: worldCovered)
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                }

                // Markierungen und Ziel-Labels sitzen auf 3D-Objekten und laufen deshalb mit jedem Bild mit.
                // frameDate muss im Closure stehen, sonst hält SwiftUI den Canvas
                // für unverändert und zeichnet ihn nie neu.
                // rendersAsynchronously: RenderBox zeichnete den Canvas sonst im CA-Commit auf dem Hauptthread
                // und wartete dort auf den Metal-Treiber
                TimelineView(.animation(minimumInterval: nil, paused: worldCovered || PerfLog.noCanvas)) { timeline in
                    let frameDate = timeline.date
                    Canvas(rendersAsynchronously: true) { context, size in
                        _ = frameDate
                        game.drawTracked(context, size: size)
                    }
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { game.tap() }
                }

                Canvas { context, size in
                    game.drawStaticFrame(context, size: size)
                }
                .ignoresSafeArea()
                .allowsHitTesting(false)

                // HUD und Menüs: 15 Bilder pro Sekunde reichen für Leisten und Blinken, fortlaufende Zahlen
                // übernimmt HUDSample nur zweimal pro Sekunde. Das Textlayout war der größte Posten auf dem
                // Hauptthread und hat zusammen mit dem Canvas regelmäßig Bilder auslassen lassen.
                TimelineView(.animation(minimumInterval: 1.0 / 15, paused: worldCovered)) { hudTimeline in
                    let hudDate = hudTimeline.date
                    let _ = (PerfLog.uiFrames += 1)
                    let _ = sample.update(game)
                    let loading = (world?.framesSynced ?? 0) < 3
                    ZStack {
                        if !PerfLog.noHUD {
                            Canvas(rendersAsynchronously: true) { context, size in
                                _ = hudDate
                                game.drawChrome(context, size: size)
                            }
                            .ignoresSafeArea()
                            .allowsHitTesting(false)
                            // vor dem Start keine Anzeigen, sie blenden beim Abheben ein
                            hud
                                .opacity(Double(game.hudAlpha))
                                .allowsHitTesting(false)
                        }
                        if !game.started {
                            titleView
                        }
                        if game.started && game.phase != .over && !game.paused && !game.stationOpen && game.hudAlpha > 0 {
                            pauseButton
                        }
                        if game.dodgeAvailable {
                            dodgeButtons
                        }
                        if game.paused {
                            pauseMenu
                        }
                        if game.stationOpen {
                            stationMenu
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
        }
        .background(Color.black.ignoresSafeArea())
        .onAppear {
            SoundFX.shared.prepare()
            // Nur für Tests: Missionsübersicht direkt öffnen
            if ProcessInfo.processInfo.arguments.contains("-missions") { showMissions = true }
            if ProcessInfo.processInfo.arguments.contains("-renderShips") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { Ship3D.renderGallery() }
            }
            // Welt erst nach dem ersten Bild aufbauen, damit der Ladebildschirm sichtbar ist
            loop.start(game)
            if world == nil {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    let w = World3D()
                    world = w
                    loop.world = w
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
            // iOS beendet speicherhungrige Apps ohne Absturzbericht; vorher alles abgeben, was sich neu erzeugen lässt
            Ship3D.purgeCaches()
            WorldTextures.purge()
        }
        .task {
            // gekaufte Schiffsteile gutschreiben (auch Käufe, die erst später bestätigt werden)
            Store.shared.onCredit = { game.profile.addShipParts($0) }
        }
        .fullScreenCover(isPresented: $showMissions) {
            MissionsView(log: game.missions, parts: game.profile.parts) { showMissions = false }
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

    private var worldCovered: Bool { showShop || showMissions }

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
        if game.dockArriving { return ("ANFLUG · STATION \(game.currentStationName ?? "")", signal) }
        if game.atStation { return ("STATION \(game.currentStationName ?? "") · ANGEDOCKT", signal) }
        if game.phase == .docked { return ("HANGAR · STARTFREIGABE", signal) }
        if game.inHorizon { return ("EREIGNISHORIZONT · PANZERUNG REISST", warn) }
        if let c = game.horizonCountdown {
            return ("SCHWARZES LOCH · BAHN ZERFÄLLT · \(Int(c.rounded(.up))) S", Color(red: 1, green: 0.6, blue: 0.3))
        }
        if game.phase == .orbiting && game.currentKind == .binary && game.solarPool > 0 {
            return ("DOPPELSTERN · SONNENENERGIE", gold)
        }
        if let kind = game.chargingKind, game.chargeFraction != nil {
            return ("BONUS LADEN · \(sample.charge) %", hsl(kind.hue, 0.85, 0.65))
        }
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
            // unsichtbare Texte nicht jedes Bild neu setzen lassen (Textlayout ist der größte Posten im Profil)
            if game.time - game.lastLaunchTime < 1.4 && game.phase != .over && !game.dockLaunch {
                precisionBadge
            } else {
                Color.clear.frame(height: 42)
            }
            Spacer()
            if game.hintShown && game.started && game.phase != .docked && !game.dodgeAvailable {
                hint
            }
            // im Stationsmenü liegt das Panel unten, Telemetrie würde durchscheinen
            // in der Hindernispassage sitzen dort die Ausweichknöpfe
            bottomBar.opacity(game.stationOpen || game.dodgeAvailable ? 0 : 1)
        }
        .padding(.horizontal, 14)
        .padding(.top, 6)
        .padding(.bottom, 12)
    }

    private var topBar: some View {
        let fraction = max(0, min(1, game.energy / game.maxEnergy))
        let lit = Int(ceil(fraction * 20))
        let chargeColor = game.chargingKind.map { hsl($0.hue, 0.85, 0.62) }
        let barColor = chargeColor ?? hsl(Double(fraction) * 160, 0.8, 0.58)
        let low = game.energy < 25 && game.started && game.phase != .over && chargeColor == nil
        let blink = low && Int(game.time * 4) % 2 == 0
        // beim Laden pulsiert die Leiste sanft in der Bonusfarbe
        let chargePulse = chargeColor == nil ? 1 : 0.75 + 0.25 * sin(Double(game.time) * 5)

        return HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                label("PLANETEN").foregroundStyle(dim)
                Text(String(format: "%03d", game.score))
                    .font(.system(size: 32, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                    .shadow(color: signal.opacity(0.7), radius: 8)
                if game.dailyMode {
                    label("HEUTE \(String(format: "%03d", game.dailyBest))")
                        .foregroundStyle(daily)
                } else {
                    label("REKORD \(String(format: "%03d", game.best))")
                        .foregroundStyle(signal.opacity(0.8))
                }
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
                    label(String(format: "%03d %%", sample.energy))
                }
                .foregroundStyle(blink ? warn : dim)

                HStack(spacing: 3) {
                    ForEach(0..<20, id: \.self) { i in
                        Slant().fill(i < lit ? barColor.opacity(chargePulse) : Color.white.opacity(0.08))
                    }
                }
                .frame(height: 14)
                .shadow(color: barColor.opacity(0.5), radius: 6)

                // Panzerung: schmale Leiste, wird bei wenig Panzerung rot und pulsiert, blinkt bei Treffern
                let hullLow = game.hull <= 25
                let hullPulse = hullLow ? 0.55 + 0.45 * abs(sin(Double(game.time) * 5)) : 1
                let hitBlink = game.brakeFlash > 0 && Int(game.brakeFlash * 10) % 2 == 0
                HStack(spacing: 6) {
                    label("PANZ").foregroundStyle(dim)
                    HStack(spacing: 2) {
                        ForEach(0..<10, id: \.self) { i in
                            Rectangle().fill(CGFloat(i) < (game.hull / 10).rounded(.up)
                                             ? (hullLow || hitBlink ? warn : gold) : Color.white.opacity(0.08))
                        }
                    }
                    .frame(height: 5)
                    .opacity(hullPulse)
                    .shadow(color: warn.opacity(hullLow ? 0.6 : 0), radius: 4)
                    label(String(format: "%03d", sample.hull)).foregroundStyle(hullLow || hitBlink ? warn : dim)
                }

                HStack(alignment: .bottom, spacing: 6) {
                    if let chargeColor {
                        label("LADEN · KEIN VERBRAUCH").foregroundStyle(chargeColor)
                    } else {
                        label(low ? "RESERVE · WARNUNG" : "ZELLE A · NOMINAL")
                            .foregroundStyle(low ? warn : signal.opacity(0.75))
                    }
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

    /// Ausweichknöpfe links und rechts, nur in der Hindernispassage
    private var dodgeButtons: some View {
        VStack {
            Spacer(minLength: 0)
            HStack {
                DodgeButton(side: -1, color: signal, fill: panel) { game.dodge(-1) }
                Spacer()
                DodgeButton(side: 1, color: signal, fill: panel) { game.dodge(1) }
            }
            .padding(.horizontal, 18)
            // an der Stelle von Telemetrie und Radar
            Spacer().frame(height: 14)
        }
        .transition(.opacity)
    }

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
                if SoundFX.available {
                    menuButton(soundOn ? "TON AN" : "TON AUS", soundOn ? "speaker.wave.2.fill" : "speaker.slash.fill", dim) {
                        soundOn.toggle()
                    }
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
                Text("OrbiX")
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
            if game.combo >= 2 { comboChip }
            if game.wideConeLaunches > 0 { chip("×\(game.wideConeLaunches)", .wideCone) }
            if game.superBombs > 0 { chip("×\(game.superBombs)", .superBomb) }
            if game.rescueCharges > 0 { chip("×\(game.rescueCharges)", .rescue) }
            if game.overflow > 0 { chip("\(Int(game.overflow))%", .tech) }
            Spacer()
        }
        .frame(height: 20)
    }

    /// Combo-Anzeige: blinkt kurz auf, wenn sie wächst
    private var comboChip: some View {
        let col = Color(red: 1, green: 0.62, blue: 0.95)
        let flash = max(0, 1 - (game.time - game.comboChangedAt) / 0.5)
        return HStack(spacing: 4) {
            Image(systemName: "flame.fill").font(.system(size: 9, weight: .bold))
            label("COMBO ×\(game.combo) · +\(Int(((game.comboMultiplier - 1) * 100).rounded())) % ENERGIE")
        }
            .foregroundStyle(col)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Chamfer(cut: 5).fill(col.opacity(0.12 + 0.3 * Double(flash))))
            .overlay(Chamfer(cut: 5).stroke(col.opacity(0.6 + 0.4 * Double(flash)), lineWidth: 1))
            .scaleEffect(1 + 0.12 * flash)
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
        let tier = precisionTier(game.lastAccuracy)
        return Text("\(tier.0) · \(Int(game.lastAccuracy * 100)) %")
            .font(.system(size: 18, weight: .bold, design: .monospaced))
            .tracking(2)
            .foregroundStyle(tier.1)
            .shadow(color: tier.1.opacity(0.6), radius: 8)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .overlay(Brackets(len: 8).stroke(tier.1.opacity(0.8), lineWidth: 1.5))
            .padding(.top, 4)
    }

    private var hint: some View {
        Text("Tippe, wenn das Schiff im Kegel ist: je genauer in der Mitte, desto schneller. Außerhalb des Kegels und im Flug feuert ein Tipp die Bordwaffe, das kostet Energie.")
            .font(.system(size: 11, design: .monospaced))
            .multilineTextAlignment(.center)
            .foregroundStyle(dim)
            .padding(10)
            .background(panelBackground(cut: 8, edge: dim))
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
                readout("VEL", String(format: "%04d", sample.speed), "M/S")
                readout("ZIEL", String(format: "%05d", sample.distance), "KM")
                readout("KURS", String(format: "%03d", sample.heading), "GRD")
                readout("WAFFE", game.weapon.title, "\(Int(game.weaponCost))E")
                readout("TECH", "+\(game.runParts)", "⚙")
                if game.runShipParts > 0 { readout("SCHIFF", "+\(game.runShipParts)", "TEIL") }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(panelBackground(cut: 8, edge: signal))
            Spacer()
            // Platz für das Radar, das im Canvas gezeichnet wird
            Color.clear.frame(width: 104, height: 100)
        }
    }

    // MARK: Raumstation

    private var stationMenu: some View {
        let cost = game.repairCost
        let canRepair = cost > 0 && game.profile.parts >= cost
        return VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 12) {
                label("RAUMSTATION · PLANET \(game.score) · ANDOCKEN BESTÄTIGT").foregroundStyle(dim)
                Text(game.currentStationName ?? "RAUMSTATION")
                    .font(.system(size: 30, weight: .heavy, design: .monospaced))
                    .tracking(5)
                    .foregroundStyle(.white)
                    .shadow(color: signal.opacity(0.6), radius: 12)
                label("⚙ \(game.profile.parts) TECH-TEILE · \(game.profile.shipParts) SCHIFFSTEILE")
                    .foregroundStyle(dim)
                    .padding(.bottom, 8)
                menuButton(cost == 0 ? "SCHIFF INTAKT" : "REPARIEREN · ⚙ \(cost)",
                           "wrench.and.screwdriver.fill", canRepair ? signal : dim) {
                    game.repair()
                }
                .disabled(!canRepair)
                menuButton("WERFT", "airplane", gold) { showShop = true }
                menuButton("WEITERFLIEGEN", "arrow.up.forward", signal) { game.leaveStation() }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 26)
            .background(Chamfer(cut: 14).fill(panel.opacity(0.92)))
            .overlay(Chamfer(cut: 14).stroke(signal.opacity(0.45), lineWidth: 1))
            .overlay(Brackets(len: 14).stroke(signal, lineWidth: 2).padding(-6))
            .padding(.bottom, 36)
        }
        // nur unten abdunkeln, damit die Station oben frei bleibt
        .background(
            LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .center, endPoint: .bottom)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        )
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
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Chamfer(cut: 8).fill(panel.opacity(0.85)))
            .overlay(Chamfer(cut: 8).stroke(gold.opacity(0.7), lineWidth: 1.2))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Missionen und Erfolge; zeigt, wie nah die nächste Mission ist
    private var missionsButton: some View {
        let closest = game.missions.missions.map(\.fraction).max() ?? 0
        return Button {
            showMissions = true
        } label: {
            VStack(spacing: 3) {
                Image(systemName: "flag.checkered")
                    .font(.system(size: 14, weight: .bold))
                label("\(game.missions.unlocked.count)/\(Achievement.all.count)")
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Rectangle().fill(signal.opacity(0.2))
                        Rectangle().fill(signal).frame(width: g.size.width * closest)
                    }
                }
                .frame(height: 2)
                .padding(.horizontal, 10)
            }
            .foregroundStyle(signal)
            .frame(width: 56, height: 48)
            .background(Chamfer(cut: 8).fill(panel.opacity(0.85)))
            .overlay(Chamfer(cut: 8).stroke(signal.opacity(0.7), lineWidth: 1.2))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Missionen und Erfolge")
    }

    /// Tagesflug ein- oder ausschalten, im Tagesflug zusätzlich die Bestenliste
    /// Startpunkt: Hangar oder eine schon erreichte Raumstation, mit Pfeilen durchschalten
    private var startRow: some View {
        let k = min(game.profile.startStation, game.profile.stationsReached - 1)
        let title = k < 0 ? "START: HANGAR" : "START: \(Game.stationName(k))"
        let detail = k < 0 ? "PLANET 0 · \(game.profile.stationsReached) \(game.profile.stationsReached == 1 ? "STATION" : "STATIONEN") FREI"
                           : "STATION \(k + 1) · AB PLANET \(Game.stationPlanet(k))"
        return HStack(spacing: 8) {
            arrowButton("chevron.left", enabled: k > -1) { game.setStartStation(k - 1) }
            VStack(spacing: 1) {
                Text(title)
                    .font(.system(size: 13, weight: .heavy, design: .monospaced))
                    .tracking(2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                label(detail).foregroundStyle(dim)
            }
            .foregroundStyle(signal)
            .frame(maxWidth: .infinity)
            arrowButton("chevron.right", enabled: k < game.profile.stationsReached - 1) { game.setStartStation(k + 1) }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Chamfer(cut: 8).fill(panel.opacity(0.85)))
        .overlay(Chamfer(cut: 8).stroke(signal.opacity(0.6), lineWidth: 1.2))
    }

    private func arrowButton(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(enabled ? signal : dim.opacity(0.4))
                .frame(width: 40, height: 40)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private var dailyRow: some View {
        HStack(spacing: 10) {
            Button {
                let on = !game.dailyMode
                game.setDaily(on)
                if on { GameCenter.shared.authenticate() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: game.dailyMode ? "infinity" : "calendar")
                        .font(.system(size: 12, weight: .bold))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(game.dailyMode ? "FREIES SPIEL" : "TAGESFLUG \(DailyChallenge.todayLabel)")
                            .font(.system(size: 13, weight: .heavy, design: .monospaced))
                            .tracking(2)
                        label(game.dailyMode ? "ZUFÄLLIGE STRECKE · REKORD \(game.best)"
                                             : "GLEICHE STRECKE FÜR ALLE · HEUTE \(DailyChallenge.best(for: DailyChallenge.today))")
                            .foregroundStyle(dim)
                    }
                }
                .foregroundStyle(game.dailyMode ? signal : daily)
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Chamfer(cut: 8).fill(panel.opacity(0.85)))
                .overlay(Chamfer(cut: 8).stroke((game.dailyMode ? signal : daily).opacity(0.7), lineWidth: 1.2))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if game.dailyMode {
                Button {
                    GameCenter.shared.showDailyLeaderboard()
                } label: {
                    Image(systemName: "list.number")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(daily)
                        .frame(width: 48, height: 48)
                        .background(Chamfer(cut: 8).fill(panel.opacity(0.85)))
                        .overlay(Chamfer(cut: 8).stroke(daily.opacity(0.7), lineWidth: 1.2))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Bestenliste des Tages")
            }
        }
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

    /// Breite der Knopfzeilen auf Start- und Endbildschirm (passt auch aufs kleinste iPhone)
    private static let menuRowWidth: CGFloat = 330

    private var titleView: some View {
        VStack(spacing: 14) {
            titleTexts
                .allowsHitTesting(false)
            Spacer()
            // unter dem Startplaneten
            tapPrompt
                .allowsHitTesting(false)
            // alle Zeilen gleich breit
            HStack(spacing: 10) {
                shipsButton
                missionsButton
                if SoundFX.available { soundButton }
            }
            .frame(width: Self.menuRowWidth)
            if !game.dailyMode && game.profile.stationsReached > 0 { startRow.frame(width: Self.menuRowWidth) }
            // Tagesflug ist ein eigener Spielmodus: mit Abstand abgesetzt
            dailyRow.frame(width: Self.menuRowWidth)
                .padding(.top, 18)
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 150)
        .padding(.bottom, 178)
    }

    private var tapPrompt: some View {
        let pulse = 0.75 + 0.25 * sin(Double(game.time) * 4)
        // dunkles Feld dahinter, damit der Text auch auf der hellen Startplattform lesbar bleibt
        return Text(game.dailyMode ? "TIPPEN ZUM STARTEN · TAGESFLUG" : "TIPPEN ZUM STARTEN")
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
            Text("OrbiX")
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
                HStack(spacing: 10) {
                    shipsButton
                    missionsButton
                }
                .frame(width: Self.menuRowWidth)
                dailyRow.frame(width: Self.menuRowWidth)
                    .padding(.top, 18)
            }
        }
    }

    private var gameOverPanel: some View {
        VStack(spacing: 14) {
            label("SYSTEM OFFLINE · T+\(missionClock)").foregroundStyle(warn.opacity(0.8))
            Text(game.destroyed ? "SCHIFF ZERSTÖRT" : "ENERGIE LEER")
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
                    Text(String(format: "%03d", game.dailyMode ? game.dailyBest : game.best))
                        .font(.system(size: 32, weight: .bold, design: .monospaced))
                        .foregroundStyle(game.dailyMode ? daily : gold)
                    label(game.dailyMode ? "HEUTE BESTER" : "REKORD").foregroundStyle(dim)
                }
            }
            .foregroundStyle(.white)
            if game.dailyMode {
                label(game.dailyNewBest ? "TAGESFLUG \(DailyChallenge.todayLabel) · NEUER TAGESBESTWERT"
                                        : "TAGESFLUG \(DailyChallenge.todayLabel) · VERSUCH \(DailyChallenge.tries(for: game.dailyDay))")
                    .foregroundStyle(daily)
            }
            label("BESTE COMBO ×\(game.runBestCombo) · REKORD ×\(game.bestCombo)")
                .foregroundStyle(Color(red: 1, green: 0.62, blue: 0.95))
            label("+\(game.runParts) TECH-TEILE · GESAMT ⚙ \(game.profile.parts)")
                .foregroundStyle(gold)
            if game.runShipParts > 0 {
                label("+\(game.runShipParts) SCHIFFSTEILE · GESAMT \(game.profile.shipParts)")
                    .foregroundStyle(hsl(ItemKind.shipPart.hue, 0.8, 0.68))
            }
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

/// Fortlaufende HUD-Zahlen, zweimal pro Sekunde übernommen: jede geänderte Zahl kostet ein neues Textlayout,
/// und Tempo, Entfernung oder Energie änderten sich vorher in jedem Bild.
final class HUDSample {
    private var tick = -1
    private(set) var energy = 0
    private(set) var hull = 0
    private(set) var charge = 0
    private(set) var speed = 0
    private(set) var distance = 0
    private(set) var heading = 0

    func update(_ game: Game) {
        let t = Int(game.uiTime * 2)
        guard t != tick else { return }
        tick = t
        energy = Int(ceil(game.energy))
        hull = Int(ceil(game.hull))
        charge = Int((game.chargeFraction ?? 0) * 100)
        speed = Int(game.speed)
        distance = Int(game.targetDistance)
        heading = game.headingDegrees
    }
}

/// Treibt Simulation und Abgleich der 3D-Welt mit jedem Bildschirmbild an, unabhängig davon, wann SwiftUI die
/// Oberfläche neu auswertet. SceneKit zeichnet ohnehin jedes Bild; bekommt es keinen neuen Spielstand, steht
/// die Welt für ein Bild still, und das sieht man vor allem bei der Kamerafahrt im Orbit als Ruckeln.
final class GameLoop: NSObject {
    private var link: CADisplayLink?
    private weak var game: Game?
    weak var world: World3D?
    private var size: CGSize = .zero
    private var insets = EdgeInsets()
    private var paused = false

    func start(_ game: Game) {
        self.game = game
        guard link == nil else { return }
        let l = CADisplayLink(target: self, selector: #selector(tick(_:)))
        l.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 60, preferred: 60)
        l.add(to: .main, forMode: .common)
        link = l
    }

    /// aus dem View-Body: Bildgröße, Ränder und ob ein Vollbild-Menü die Welt verdeckt
    func configure(size: CGSize, insets: EdgeInsets, paused: Bool) {
        self.size = size
        self.insets = insets
        self.paused = paused
    }

    @objc private func tick(_ link: CADisplayLink) {
        guard let game, !paused, size.width > 0 else { return }
        let start = CACurrentMediaTime()
        game.insets = insets
        // Zeitpunkt, zu dem das Bild erscheint: gleichmäßigere Schritte als die Aufrufzeit
        game.step(date: Date(timeIntervalSinceReferenceDate: link.targetTimestamp), size: size)
        if let world {
            game.project = world.project
            world.sync(game, size: size)
        }
        PerfLog.frame(main: CACurrentMediaTime() - start, orbiting: game.phase == .orbiting)
    }
}

#Preview {
    GameView()
        .preferredColorScheme(.dark)
}


/// Ausweichknopf: löst schon beim Berühren aus, nicht erst beim Loslassen
private struct DodgeButton: View {
    let side: CGFloat
    let color: Color
    let fill: Color
    let action: () -> Void
    @State private var pressed = false

    var body: some View {
        Image(systemName: side < 0 ? "chevron.left.2" : "chevron.right.2")
            .font(.system(size: 28, weight: .heavy))
            .foregroundStyle(color)
            .frame(width: 84, height: 84)
            .background(Circle().fill(fill.opacity(pressed ? 0.95 : 0.7)))
            .overlay(Circle().stroke(color.opacity(pressed ? 1 : 0.6), lineWidth: pressed ? 2 : 1))
            .scaleEffect(pressed ? 0.92 : 1)
            .contentShape(Circle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !pressed else { return }
                    pressed = true
                    action()
                }
                .onEnded { _ in pressed = false })
    }
}
