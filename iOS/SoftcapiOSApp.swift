import SwiftUI
import Preferences
import StatusUI

@main
struct SoftcapiOSApp: App {
    @StateObject private var model = PhoneModel()
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            LimitsScreen(model: model)
                .task { await model.start() }
        }
        // `.task` is tied to the view's lifetime, and a suspended app keeps its
        // view: coming back after an hour showed the hour-old figures with no
        // spinner and nothing to say they were old. The Mac has had the same
        // thought for the machine waking from sleep, and the same setting
        // decides it — one idea, two platforms.
        .onChange(of: phase) { _, now in
            guard now == .active else { return }
            Task { await model.refreshOnReturn() }
        }
    }
}
