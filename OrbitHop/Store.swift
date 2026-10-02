import SwiftUI
import StoreKit

// MARK: - In-App-Käufe: Schiffsteile

/// Schiffsteile werden genau in der fehlenden Menge gekauft: als Zehnerpakete plus Einzelteile,
/// jeweils mit Stückzahl (StoreKit erlaubt bis 10 Stück pro Kauf). Die Produkt-IDs müssen in
/// App Store Connect (und in OrbitHop.storekit für Tests) genau so angelegt sein.
enum ShipPartPack: String, CaseIterable {
    case single = "com.chv.OrbitHop.shipparts.1"
    case ten = "com.chv.OrbitHop.shipparts.10"

    var amount: Int { self == .ten ? 10 : 1 }

    /// Günstigste Aufteilung für mindestens n Teile in Käufe (Paket, Stückzahl), höchstens 10 Stück je Kauf.
    /// Ab 7 Einzelteilen ist ein Zehnerpaket billiger (7 × 0,29 € > 1,99 €); der Überschuss bleibt gutgeschrieben.
    static func split(_ n: Int) -> [(ShipPartPack, Int)] {
        var out: [(ShipPartPack, Int)] = []
        var tens = n / 10
        var rest = n % 10
        if rest >= 7 { tens += 1; rest = 0 }
        while tens > 0 { out.append((.ten, min(10, tens))); tens -= min(10, tens) }
        if rest > 0 { out.append((.single, rest)) }
        return out
    }

    /// Wie viele Teile man beim Kauf von mindestens n tatsächlich bekommt
    static func delivered(_ n: Int) -> Int {
        split(n).reduce(0) { $0 + $1.0.amount * $1.1 }
    }
}

@MainActor
@Observable
final class Store {
    static let shared = Store()

    private(set) var products: [String: Product] = [:]
    private(set) var loading = false
    private(set) var busy = false
    var message: String?

    /// Wird für gekaufte Teile aufgerufen (auch für Käufe, die erst später bestätigt werden)
    var onCredit: ((Int) -> Void)?

    private var updates: Task<Void, Never>?

    private init() {
        updates = Task { [weak self] in
            for await result in StoreKit.Transaction.updates {
                await self?.handle(result)
            }
        }
    }

    func load() async {
        guard products.isEmpty, !loading else { return }
        loading = true
        defer { loading = false }
        do {
            let list = try await Product.products(for: ShipPartPack.allCases.map(\.rawValue))
            products = Dictionary(uniqueKeysWithValues: list.map { ($0.id, $0) })
        } catch {
            message = "SHOP NICHT ERREICHBAR"
        }
    }

    /// Preis für genau n Schiffsteile, nil solange die Produkte nicht geladen sind
    func price(for n: Int) -> String? {
        guard n > 0 else { return nil }
        var total: Decimal = 0
        var style: Decimal.FormatStyle.Currency?
        for (pack, qty) in ShipPartPack.split(n) {
            guard let p = products[pack.rawValue] else { return nil }
            total += p.price * Decimal(qty)
            style = p.priceFormatStyle
        }
        return style.map { total.formatted($0) }
    }

    /// Kauft genau n Schiffsteile; true, wenn alles bezahlt wurde
    func buy(_ n: Int) async -> Bool {
        guard n > 0, !busy else { return false }
        busy = true
        defer { busy = false }
        for (pack, qty) in ShipPartPack.split(n) {
            guard let product = products[pack.rawValue] else { message = "SHOP NICHT ERREICHBAR"; return false }
            do {
                switch try await product.purchase(options: [.quantity(qty)]) {
                case .success(let result):
                    await handle(result)
                case .pending:
                    message = "KAUF WARTET AUF FREIGABE"
                    return false
                case .userCancelled:
                    return false
                @unknown default:
                    return false
                }
            } catch {
                message = "KAUF FEHLGESCHLAGEN"
                return false
            }
        }
        return true
    }

    private func handle(_ result: VerificationResult<StoreKit.Transaction>) async {
        guard case .verified(let transaction) = result else {
            message = "KAUF NICHT BESTÄTIGT"
            return
        }
        if transaction.revocationDate == nil, let pack = ShipPartPack(rawValue: transaction.productID) {
            onCredit?(pack.amount * transaction.purchasedQuantity)
            message = "+\(pack.amount * transaction.purchasedQuantity) SCHIFFSTEILE"
        }
        await transaction.finish()
    }
}

// MARK: - Kaufansicht

/// Kauf der fehlenden Schiffsteile für ein bestimmtes Schiff; schaltet es nach dem Kauf frei
struct ShipPartStoreView: View {
    let profile: Profile
    let model: ShipModel
    let onClose: () -> Void

    @State private var store = Store.shared

    private let signal = Color(red: 79 / 255, green: 227 / 255, blue: 193 / 255)
    private let dim = Color(red: 0.55, green: 0.6, blue: 0.72)
    private let partColor = hsl(ItemKind.shipPart.hue, 0.8, 0.68)
    private let panel = Color(red: 0.02, green: 0.07, blue: 0.11)

    private var missing: Int { max(0, model.grade.cost - profile.shipParts) }
    private var delivered: Int { ShipPartPack.delivered(missing) }

    private func label(_ text: String) -> Text {
        Text(text)
            .font(.system(size: 9, weight: .medium, design: .monospaced))
            .tracking(1.4)
    }

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    label("WERFT // NACHSCHUB").foregroundStyle(signal.opacity(0.8))
                    Text(model.name.uppercased())
                        .font(.system(size: 26, weight: .heavy, design: .monospaced))
                        .tracking(3)
                        .foregroundStyle(.white)
                }
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(signal)
                        .frame(width: 40, height: 40)
                        .background(Chamfer(cut: 8).fill(panel))
                        .overlay(Chamfer(cut: 8).stroke(signal.opacity(0.6), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }

            HStack {
                label("BENÖTIGT \(model.grade.cost) · VORHANDEN \(profile.shipParts)").foregroundStyle(dim)
                Spacer()
            }

            Button {
                Task {
                    if await store.buy(missing) {
                        profile.unlock(model)
                        onClose()
                    }
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "puzzlepiece.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(partColor)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(delivered) SCHIFFSTEILE")
                            .font(.system(size: 16, weight: .bold, design: .monospaced))
                            .foregroundStyle(.white)
                        label("KAUFEN UND SCHIFF FREISCHALTEN").foregroundStyle(dim)
                        if delivered > missing {
                            label("\(delivered - missing) BLEIBEN FÜR SPÄTER").foregroundStyle(partColor.opacity(0.8))
                        }
                    }
                    Spacer()
                    Text(store.price(for: missing) ?? "–")
                        .font(.system(size: 15, weight: .bold, design: .monospaced))
                        .foregroundStyle(partColor)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
                .background(Chamfer(cut: 8).fill(partColor.opacity(0.08)))
                .overlay(Chamfer(cut: 8).stroke(partColor.opacity(0.7), lineWidth: 1.2))
            }
            .buttonStyle(.plain)
            .disabled(missing == 0 || store.price(for: missing) == nil || store.busy)

            if store.loading || store.busy {
                ProgressView().tint(signal)
            } else if store.products.isEmpty {
                label("KEINE ANGEBOTE VERFÜGBAR").foregroundStyle(dim)
            }
            if let msg = store.message {
                label(msg).foregroundStyle(partColor)
            }
            Spacer()
        }
        .padding(20)
        .background(
            LinearGradient(colors: [Color(red: 0.03, green: 0.045, blue: 0.1), Color(red: 0.01, green: 0.015, blue: 0.04)],
                           startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
        )
        .task {
            store.message = nil
            await store.load()
        }
    }
}
