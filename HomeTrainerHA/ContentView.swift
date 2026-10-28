import SwiftUI

struct ContentView: View {
    @EnvironmentObject var bike: BikeManager
    @EnvironmentObject var ha: HomeAssistantClient
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    statusCard
                    metricsGrid
                    if bike.state == .scanning || !bike.discovered.isEmpty { deviceList }
                }
                .padding()
            }
            .navigationTitle("HomeTrainer → HA")
            .toolbar { Button { showSettings = true } label: { Image(systemName: "gearshape") } }
            .sheet(isPresented: $showSettings) { SettingsView() }
        }
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle().fill(color).frame(width: 10, height: 10)
                Text(label).font(.headline)
                Spacer()
                if bike.state == .connected { Button("Déconnecter", role: .destructive) { bike.disconnect() } }
                else if bike.state == .idle { Button("Scanner") { bike.startScan() }.buttonStyle(.borderedProminent) }
            }
            HStack {
                Image(systemName: ha.lastError == nil ? "house.fill" : "exclamationmark.triangle.fill")
                Text(haStatus).font(.footnote)
            }.foregroundStyle(ha.lastError == nil ? Color.secondary : Color.red)
            if ha.lastError == nil, let zone = ha.zone {
                HStack(spacing: 6) {
                    Text(zone == 0 ? "Arrêt" : "Zone \(zone)").font(.footnote.bold())
                    if let ftp = ha.ftp { Text("· FTP \(ftp) W").font(.footnote) }
                    if ha.onBike == true { Text("· sur le vélo").font(.footnote) }
                }.foregroundStyle(.secondary)
            }
        }
        .padding().background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private var metricsGrid: some View {
        let m = bike.metrics
        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            tile("Puissance", m.power.map(String.init), "W", big: true)
            tile("Cadence", m.cadence.map(String.init), "rpm")
            tile("Vitesse", m.speed.map { String(format: "%.1f", $0) }, "km/h")
            tile("Fréq. cardiaque", m.heartRate.map(String.init), "bpm")
            tile("Distance", m.distance.map { String(format: "%.2f", Double($0) / 1000) }, "km")
            tile("Énergie", m.energy.map(String.init), "kcal")
        }
    }

    private func tile(_ title: String, _ value: String?, _ unit: String, big: Bool = false) -> some View {
        VStack(spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value ?? "–").font(.system(size: big ? 56 : 34, weight: .bold, design: .rounded)).monospacedDigit()
            Text(unit).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity).padding(.vertical, big ? 20 : 12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .gridCellColumns(big ? 2 : 1)
    }

    private var deviceList: some View {
        VStack(alignment: .leading) {
            Text("Appareils détectés").font(.headline)
            ForEach(bike.discovered, id: \.identifier) { p in
                Button { bike.connect(p) } label: {
                    HStack { Image(systemName: "bicycle"); Text(p.name ?? "Inconnu"); Spacer(); Image(systemName: "chevron.right") }
                        .padding().background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
                }.buttonStyle(.plain)
            }
        }
    }

    private var haStatus: String {
        if ha.webhookURL.isEmpty { return "HA : adresse du webhook à renseigner (⚙︎)" }
        if let e = ha.lastError { return "HA : \(e)" }
        return ha.lastSent.map { "HA : envoyé \($0.formatted(date: .omitted, time: .standard))" } ?? "HA : en attente"
    }

    private var label: String {
        switch bike.state {
        case .idle: "Déconnecté"
        case .scanning: "Recherche…"
        case .connecting: "Connexion…"
        case .connected: "Connecté : \(bike.connectedName ?? "")"
        case .unavailable(let s): s
        }
    }
    private var color: Color {
        switch bike.state { case .connected: .green; case .scanning, .connecting: .orange; default: .red }
    }
}

struct SettingsView: View {
    @EnvironmentObject var ha: HomeAssistantClient
    @Environment(\.dismiss) private var dismiss
    @AppStorage("haInterval") private var interval = 1.0
    @State private var webhook = Keychain.get("haWebhook") ?? ""
    @State private var testResult = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Home Assistant") {
                    TextField("http://192.168.1.33:8123/api/webhook/…", text: $webhook, axis: .vertical)
                        .textInputAutocapitalization(.never).keyboardType(.URL).autocorrectionDisabled()
                        .font(.footnote.monospaced())
                    if webhook.isEmpty, UIPasteboard.general.hasURLs {
                        Button("Coller l'adresse copiée") { webhook = UIPasteboard.general.url?.absoluteString ?? "" }
                    }
                    Stepper("Envoi toutes les \(interval.formatted()) s", value: $interval, in: 0.5...10, step: 0.5)
                }
                Section {
                    Button("Tester la connexion") {
                        save()
                        Task { testResult = await ha.test() }
                    }
                    if !testResult.isEmpty { Text(testResult).font(.footnote) }
                } footer: {
                    Text("Ajoutez l'intégration « HomeTrainer To Home Assistant » dans Home Assistant (via HACS), puis copiez ici l'adresse du webhook affichée à la création ou avec le bouton « Configurer » de l'intégration. Utilisez l'adresse « Réseau local » à la maison et « Depuis Internet » ailleurs.")
                }
            }
            .navigationTitle("Réglages")
            .toolbar { Button("OK") { save(); dismiss() } }
        }
    }

    private func save() { Keychain.set(webhook.trimmingCharacters(in: .whitespacesAndNewlines), for: "haWebhook") }
}
