// GymLogApp.swift — @main. Root TabView per spec §5 information architecture.
// Opening the app defaults to the Workout tab; the voice capture overlay is a
// sheet reachable from both the in-app mic and the App Intent (via AppRouter).

import SwiftUI
import GymLogCore

@main
struct GymLogApp: App {
    @StateObject private var coordinator = SessionCoordinator.shared
    @StateObject private var router = AppRouter.shared
    @AppStorage("theme") private var theme = "system"

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(coordinator)
                .environmentObject(router)
                .preferredColorScheme(colorScheme)
        }
    }

    private var colorScheme: ColorScheme? {
        switch theme {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }
}

struct RootView: View {
    @EnvironmentObject var coordinator: SessionCoordinator
    @EnvironmentObject var router: AppRouter

    var body: some View {
        TabView(selection: $router.selectedTab) {
            WorkoutView()
                .tabItem { Label("Workout", systemImage: "figure.strengthtraining.traditional") }
                .tag(AppRouter.Tab.workout)

            RoutineListView()
                .tabItem { Label("Routines", systemImage: "list.bullet.rectangle") }
                .tag(AppRouter.Tab.routines)

            DashboardView()
                .tabItem { Label("Dashboard", systemImage: "chart.bar.fill") }
                .tag(AppRouter.Tab.dashboard)

            ProfileView()
                .tabItem { Label("Profile", systemImage: "person.crop.circle") }
                .tag(AppRouter.Tab.profile)
        }
        .sheet(isPresented: $router.showVoiceCapture) {
            VoiceCaptureView(autoRecord: router.autoRecord)
                .presentationDetents([.medium])
        }
        // Confirmation toast (§7.7, mockup A4) — auto-clears.
        .overlay(alignment: .top) {
            if let toast = coordinator.lastToast {
                ToastView(text: toast)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .task {
                        try? await Task.sleep(for: .seconds(2))
                        withAnimation { coordinator.lastToast = nil }
                    }
            }
        }
        .tint(GymTheme.accent)
        .animation(.snappy, value: coordinator.lastToast)
    }
}
