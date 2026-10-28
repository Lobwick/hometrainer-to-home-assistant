import SwiftUI

@main
struct HomeTrainerHAApp: App {
    @StateObject private var bike = BikeManager()
    @StateObject private var ha = HomeAssistantClient()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(bike)
                .environmentObject(ha)
                .onAppear {
                    bike.onMetrics = { [weak bike] m in ha.push(m, device: bike?.connectedName) }
                    UIApplication.shared.isIdleTimerDisabled = true   // écran allumé pendant la séance
                }
        }
    }
}
