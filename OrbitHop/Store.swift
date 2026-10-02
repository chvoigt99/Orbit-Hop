import SwiftUI
import StoreKit

// MARK: - In-App-Käufe: Schiffsteile

/// Verbrauchbare Pakete mit Schiffsteilen. Die Produkt-IDs müssen in App Store Connect
/// (und in OrbitHop.storekit für Tests) genau so angelegt sein.
enum ShipPartPack: String, CaseIterable {
    case small = "com.chv.OrbitHop.shipparts.10"
    case medium = "com.chv.OrbitHop.shipparts.30"
    case large = "com.chv.OrbitHop.shipparts.80"

    var amount: Int {
        switch self {
        case .small: return 10
        case .medium: return 30
        case .large: return 80
        }
    }

    var title: String {
        switch self {
        case .small: return "KLEINES PAKET"
        case .medium: return "FRACHTKISTE"
        case .large: return "WERFT-CONTAINER"
        }
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

    func purchase(_ pack: ShipPartPack) async {
        guard let product = products[pack.rawValue], !busy else { return }
        busy = true
        defer { busy = false }
        do {
            switch try await product.purchase() {
            case .success(let result):
                await handle(result)
            case .pending:
                message = "KAUF WARTET AUF FREIGABE"
            case .userCancelled:
                break
            @unknown default:
                break
            }
        } catch {
            message = "KAUF FEHLGESCHLAGEN"
        }
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

struct ShipPartStoreView: View {
    let profile: Profile
    let onClose: () -> Void

    @State private var store = Store.shared

    private let signal = Color(red: 79 / 255, green: 227 / 255, blue: 193 / 255)
    private let dim = Color(red: 0.55, green: 0.6, blue: 0.72)
    private let partColor = hsl(ItemKind.shipPart.hue, 0.8, 0.68)
    private let panel = Color(red: 0.02, green: 0.07, blue: 0.11)

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
                    Text("SCHIFFSTEILE")
                        .font(.system(size: 26, weight: .heavy, design: .monospaced))
                        .tracking(3)
                        .foregroundStyle(.white)
                }
                Spacer()
                HStack(spacing: 5) {
                    Image(systemName: "puzzlepiece.fill").font(.system(size: 14))
                    Text("\(profile.shipParts)")
                        .font(.system(size: 20, weight: .bold, design: .monospaced))
                }
                .foregroundStyle(partColor)
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(signal)
                        .frame(width: 40, height: 40)
                        .background(Chamfer(cut: 8).fill(panel))
                        .overlay(Chamfer(cut: 8).stroke(signal.opacity(0.6), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .padding(.leading, 8)
            }

            label("SCHIFFSTEILE SCHALTEN NEUE SCHIFFE FREI").foregroundStyle(dim)

            ForEach(ShipPartPack.allCases, id: \.self) { pack in
                offer(pack)
            }

            if store.loading {
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

    private func offer(_ pack: ShipPartPack) -> some View {
        let product = store.products[pack.rawValue]
        return Button {
            Task { await store.purchase(pack) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "puzzlepiece.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(partColor)
                    .frame(width: 34)
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(pack.amount) SCHIFFSTEILE")
                        .font(.system(size: 16, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white)
                    label(pack.title).foregroundStyle(dim)
                }
                Spacer()
                Text(product?.displayPrice ?? "–")
                    .font(.system(size: 15, weight: .bold, design: .monospaced))
                    .foregroundStyle(product == nil ? dim : partColor)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Chamfer(cut: 8).fill(partColor.opacity(0.08)))
            .overlay(Chamfer(cut: 8).stroke(partColor.opacity(product == nil ? 0.25 : 0.7), lineWidth: 1.2))
        }
        .buttonStyle(.plain)
        .disabled(product == nil || store.busy)
    }
}
