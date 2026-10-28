import Foundation
import Security

/// Envoie les mesures à l'intégration Home Assistant « HomeTrainer To Home Assistant » par webhook.
///
/// Un seul `POST <adresse du webhook>` en JSON à chaque intervalle, avec toutes les
/// mesures connues : l'intégration crée et garde les entités (puissance, cadence,
/// vitesse, zone, « sur le vélo »…). Plus besoin de jeton d'accès.
final class HomeAssistantClient: ObservableObject {
    @Published var lastError: String?
    @Published var lastSent: Date?
    /// Infos renvoyées par Home Assistant à chaque envoi.
    @Published var zone: Int?
    @Published var ftp: Int?
    @Published var onBike: Bool?

    private var lastPush = Date.distantPast
    private var inFlight = false
    private let session = URLSession(configuration: .ephemeral)

    var webhookURL: String { Keychain.get("haWebhook") ?? "" }
    var minInterval: TimeInterval { max(0.5, UserDefaults.standard.double(forKey: "haInterval").nonZero ?? 1) }

    /// Envoie les mesures (au plus une fois par intervalle, jamais deux requêtes en parallèle).
    func push(_ m: BikeMetrics, device: String?) {
        guard Date().timeIntervalSince(lastPush) >= minInterval, !inFlight,
              let url = URL(string: webhookURL.trimmingCharacters(in: .whitespaces)) else { return }
        lastPush = Date()
        var body: [String: Any] = [:]
        if let v = m.power { body["power"] = v }
        if let v = m.cadence { body["cadence"] = v }
        if let v = m.speed { body["speed"] = (v * 10).rounded() / 10 }
        if let v = m.heartRate { body["heart_rate"] = v }
        if let v = m.distance { body["distance"] = v }
        if let v = m.energy { body["energy"] = v }
        if let device { body["device"] = device }
        inFlight = true
        post(url, body) { [weak self] result in
            self?.inFlight = false
            switch result {
            case .success(let json):
                self?.lastError = nil
                self?.lastSent = Date()
                self?.zone = json["zone"] as? Int
                self?.ftp = json["ftp"] as? Int
                self?.onBike = json["on_bike"] as? Bool
            case .failure(let error):
                self?.lastError = error.localizedDescription
            }
        }
    }

    /// Vérifie l'adresse du webhook sans modifier les mesures (`{"test": true}`).
    func test() async -> String {
        guard let url = URL(string: webhookURL.trimmingCharacters(in: .whitespaces)), url.scheme != nil else {
            return "Adresse invalide"
        }
        return await withCheckedContinuation { cont in
            post(url, ["test": true]) { result in
                switch result {
                case .success(let json):
                    let name = json["name"] as? String ?? "Home trainer"
                    let ftp = (json["ftp"] as? Int).map { " · FTP \($0) W" } ?? ""
                    cont.resume(returning: "Connecté à « \(name) »\(ftp) ✅")
                case .failure(let error):
                    cont.resume(returning: error.localizedDescription)
                }
            }
        }
    }

    private func post(_ url: URL, _ body: [String: Any], completion: @escaping (Result<[String: Any], Error>) -> Void) {
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 5
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        session.dataTask(with: req) { data, resp, err in
            let result: Result<[String: Any], Error>
            if let err {
                result = .failure(err)
            } else {
                let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
                let json = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
                if (200..<300).contains(code), json["ok"] as? Bool == true {
                    result = .success(json)
                } else if (200..<300).contains(code) {
                    // HA répond 200 sans contenu quand le webhook n'existe pas.
                    result = .failure(ClientError("Webhook inconnu : vérifiez l'adresse et l'intégration HomeTrainer To Home Assistant"))
                } else {
                    result = .failure(ClientError("HTTP \(code)" + ((json["error"] as? String).map { " : \($0)" } ?? "")))
                }
            }
            DispatchQueue.main.async { completion(result) }
        }.resume()
    }
}

struct ClientError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

private extension Double { var nonZero: Double? { self == 0 ? nil : self } }

enum Keychain {
    static func set(_ value: String, for key: String) {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrAccount as String: key]
        SecItemDelete(q as CFDictionary)
        guard !value.isEmpty else { return }
        SecItemAdd(q.merging([kSecValueData as String: Data(value.utf8)]) { $1 } as CFDictionary, nil)
    }
    static func get(_ key: String) -> String? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrAccount as String: key,
                                kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }
}
