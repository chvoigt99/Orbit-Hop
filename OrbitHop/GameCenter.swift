import GameKit
import UIKit

/// Anmeldung bei Game Center, Ergebnisse melden und Bestenliste zeigen.
/// Alles ist optional: ohne Anmeldung läuft das Spiel normal weiter, nur ohne Bestenliste.
final class GameCenter: NSObject, GKGameCenterControllerDelegate {
    static let shared = GameCenter()

    private(set) var isAuthenticated = false

    /// Einmal beim Start: zeigt bei Bedarf Apples Anmeldefenster
    func authenticate() {
        GKLocalPlayer.local.authenticateHandler = { [weak self] controller, _ in
            if let controller {
                Self.topController()?.present(controller, animated: true)
                return
            }
            self?.isAuthenticated = GKLocalPlayer.local.isAuthenticated
        }
    }

    func submitDaily(_ score: Int) {
        guard GKLocalPlayer.local.isAuthenticated, score > 0 else { return }
        GKLeaderboard.submitScore(score, context: 0, player: GKLocalPlayer.local,
                                  leaderboardIDs: [DailyChallenge.leaderboardID]) { _ in }
    }

    /// Tägliche Bestenliste; ohne Anmeldung startet erst die Anmeldung
    func showDailyLeaderboard() {
        guard GKLocalPlayer.local.isAuthenticated else {
            authenticate()
            return
        }
        let vc = GKGameCenterViewController(leaderboardID: DailyChallenge.leaderboardID,
                                            playerScope: .global, timeScope: .today)
        vc.gameCenterDelegate = self
        Self.topController()?.present(vc, animated: true)
    }

    func gameCenterViewControllerDidFinish(_ gameCenterViewController: GKGameCenterViewController) {
        gameCenterViewController.dismiss(animated: true)
    }

    private static func topController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        var vc = scene?.windows.first { $0.isKeyWindow }?.rootViewController ?? scene?.windows.first?.rootViewController
        while let presented = vc?.presentedViewController { vc = presented }
        return vc
    }
}
