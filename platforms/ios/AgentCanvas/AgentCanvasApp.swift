import SwiftUI
import BackgroundTasks

@main
struct AgentCanvasApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var oauth = VeloxOAuthSession.shared
    @StateObject private var sync = SubscriptionSync.shared
    @StateObject private var router = DeepLinkRouter()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(oauth)
                .environmentObject(sync)
                .environmentObject(router)
                .onOpenURL { url in
                    handleOpenURL(url)
                }
                .onAppear {
                    sync.scheduleBackgroundRefresh()
                    Task { await sync.syncAll(reason: .launch) }
                }
                .onChange(of: oauth.isSignedIn) { signedIn in
                    if signedIn {
                        Task { await sync.syncAll(reason: .signIn) }
                    }
                }
        }
    }

    private func handleOpenURL(_ url: URL) {
        if VeloxOAuthSession.isOAuthCallback(url) {
            oauth.handleCallbackURL(url)
            return
        }
        router.handle(url)
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        SubscriptionSync.registerBackgroundTask()
        return true
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        Task { @MainActor in
            await SubscriptionSync.shared.syncAll(reason: .foreground)
            SubscriptionSync.shared.startForegroundPolling()
        }
    }

    func applicationWillResignActive(_ application: UIApplication) {
        Task { @MainActor in
            SubscriptionSync.shared.stopForegroundPolling()
            SubscriptionSync.shared.scheduleBackgroundRefresh()
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var oauth: VeloxOAuthSession
    @EnvironmentObject private var router: DeepLinkRouter

    var body: some View {
        Group {
            if oauth.isSignedIn {
                NavigationStack {
                    SlotsListView()
                        .navigationDestination(item: $router.detailAddress) { address in
                            CanvasDetailView(address: address)
                        }
                }
                .sheet(item: $router.subscribeSlug) { slug in
                    SubscribeSheet(initialSlug: slug.value)
                }
            } else {
                SignInView()
            }
        }
        .sheet(isPresented: Binding(
            get: { router.showHowTo },
            set: { router.showHowTo = $0 }
        )) {
            NavigationStack {
                HowToView()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { router.showHowTo = false }
                        }
                    }
            }
        }
    }
}

/// String wrapper so subscribe slugs work with `.sheet(item:)`.
struct IdentifiableSlug: Identifiable, Hashable {
    var value: String
    var id: String { value }
}

@MainActor
final class DeepLinkRouter: ObservableObject {
    @Published var detailAddress: CanvasAddress?
    @Published var subscribeSlug: IdentifiableSlug?
    @Published var showHowTo = false

    func handle(_ url: URL) {
        let outcome = IOSActionDispatcher.handleOpenURL(url)
        switch outcome {
        case let .expand(id):
            detailAddress = CanvasAddress(rawValue: id)
        case .showHowTo:
            showHowTo = true
        case let .subscribe(slug):
            subscribeSlug = IdentifiableSlug(value: slug)
        case .handledExternally:
            break
        }
    }

    func openDetail(_ address: CanvasAddress) {
        detailAddress = address
    }
}
