import SwiftUI

// Vorlage: Apps/_tools/BuildInfo.swift – unverändert in jedes App-Target kopieren.
// Die Schlüssel CHVBuildID und CHVBuildSource schreibt die Run-Script-Phase „Build-ID setzen“
// bei jedem Build ins Info.plist (siehe _tools/add-build-id-phase.py), CHVBuildSource immer "Claude/Xcode".
// Nur nas-build.sh setzt beim Export für die Website "Website".

/// Woher dieser Build stammt: 4-stellige Build-ID, Installationsweg und Version
enum BuildInfo {
    /// 4 Zeichen aus A–Z und 0–9, bei jedem Build neu
    static let id = info("CHVBuildID") ?? "----"
    static let version = info("CFBundleShortVersionString") ?? "?"
    static let build = info("CFBundleVersion") ?? "?"

    /// "Website" (Ad-hoc über nas-build.sh und die Download-Seite), "Claude/Xcode", "TestFlight" oder "App Store"
    static let source: String = {
        #if os(iOS) && !targetEnvironment(simulator)
        // Store-signierte Builds haben kein embedded.mobileprovision; dasselbe Archiv kann
        // Ad-hoc (Website) oder TestFlight/App Store werden, das lässt sich nur zur Laufzeit erkennen
        if Bundle.main.path(forResource: "embedded", ofType: "mobileprovision") == nil {
            return Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt" ? "TestFlight" : "App Store"
        }
        #elseif os(macOS)
        if let receipt = Bundle.main.appStoreReceiptURL, FileManager.default.fileExists(atPath: receipt.path) {
            return receipt.lastPathComponent == "sandboxReceipt" ? "TestFlight" : "App Store"
        }
        #endif
        // ältere Builds schrieben "Xcode"
        let src = info("CHVBuildSource") ?? "Claude/Xcode"
        return src == "Xcode" ? "Claude/Xcode" : src
    }()

    /// im App Store keine Testinfo zeigen
    static let isVisible = source != "App Store"

    /// eine Zeile, z. B. "Website · Build 7K2Q · 1.0 (3)"
    static var summary: String { "\(source) · Build \(id) · \(version) (\(build))" }

    private static func info(_ key: String) -> String? {
        Bundle.main.object(forInfoDictionaryKey: key) as? String
    }
}

/// Unauffälliges „?“ für den Startbildschirm; Tippen klappt darunter Installationsweg, Build-ID und Version auf.
struct BuildInfoButton: View {
    var tint: Color = .white.opacity(0.55)
    var size: CGFloat = 18

    @State private var shown = false

    var body: some View {
        if BuildInfo.isVisible {
            VStack(alignment: .trailing, spacing: 0) {
                Button { withAnimation(.easeOut(duration: 0.15)) { shown.toggle() } } label: {
                    Image(systemName: shown ? "questionmark.circle.fill" : "questionmark.circle")
                        .font(.system(size: size, weight: .semibold))
                        .foregroundStyle(tint)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(verbatim: "Build-Info"))

                if shown {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(verbatim: "Installiert über: \(BuildInfo.source)")
                        Text(verbatim: "Build: \(BuildInfo.id)").monospaced()
                        Text(verbatim: "Version \(BuildInfo.version) (\(BuildInfo.build))").opacity(0.7)
                    }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
                    .fixedSize()
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
                    .padding(.trailing, 8)
                    .onTapGesture { withAnimation(.easeOut(duration: 0.15)) { shown = false } }
                    .transition(.opacity)
                }
            }
        }
    }
}
