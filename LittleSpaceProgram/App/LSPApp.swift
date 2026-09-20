import SwiftUI

@main
struct LittleSpaceProgramApp: App {
    @StateObject private var app = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(app)
                .preferredColorScheme(.dark)
        }
    }
}

struct RootView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        Group {
            switch app.screen {
            case .menu:
                MainMenuView()
            case .builder(let design):
                BuilderView(design: design)
                    .id(design.id)
            case .flight:
                if let flight = app.flight {
                    FlightView(model: flight)
                        .id(ObjectIdentifier(flight))
                } else {
                    MainMenuView()
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isFlight)
    }

    /// Only animate the transition in and out of flight; swapping between the menu and
    /// the builder is a full-screen change where a cross-fade just looks like a stutter.
    private var isFlight: Bool {
        if case .flight = app.screen { return true }
        return false
    }
}
