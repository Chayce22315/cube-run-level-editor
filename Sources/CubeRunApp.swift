import SwiftUI
import SpriteKit
import UIKit

@main
struct CubeRunApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        FirebaseBootstrap.configureIfAvailable()
    }

    var body: some Scene {
        WindowGroup {
            CubeRunRootView()
        }
    }
}

/// Owns local editor level, optional remote play copy, and SpriteKit scene switching.
final class CubeRunSession: ObservableObject {
    /// Level used in the editor and local playtest (persisted).
    let levelLocal: LevelModel

    /// Snapshot loaded from Firestore for online playtest only.
    private(set) var remotePlayLevel: LevelModel?
    private(set) var remoteDocumentId: String?

    @Published private(set) var activeScene: SKScene?

    @Published var showBrowseOnline = false
    @Published var showPublishSheet = false
    @Published var browseLoadError: String?

    /// Prevents overlapping scene swaps (e.g. double-tap Play) which can destabilize SpriteKit.
    private var isSwappingScene = false

    init() {
        levelLocal = LevelModel.loadFromDisk() ?? LevelModel()
    }

    func attachEditor(scene: EditorScene) {
        scene.onPlay = { [weak self, weak scene] in
            guard let self, let scene else { return }
            self.clearRemotePlay()
            // Touch may arrive on a SpriteKit-internal path; always hop to main explicitly.
            DispatchQueue.main.async {
                self.presentLocalPlaytest(size: scene.size)
            }
        }
        scene.onBrowseOnline = { [weak self] in
            self?.showBrowseOnline = true
        }
        scene.onPublish = { [weak self] in
            self?.showPublishSheet = true
        }
    }

    func presentEditor(size: CGSize) {
        clearRemotePlay()
        let scene = EditorScene(size: size, level: levelLocal)
        scene.scaleMode = .resizeFill
        attachEditor(scene: scene)
        commitSceneSwitch(scene)
    }

    func presentLocalPlaytest(size: CGSize) {
        guard !isSwappingScene else { return }
        isSwappingScene = true
        clearRemotePlay()
        let scene = GameScene(size: size, level: levelLocal)
        scene.scaleMode = .resizeFill
        scene.isRemoteLevel = false
        scene.remoteDocumentId = nil
        scene.onExitToEditor = { [weak self, weak scene] in
            guard let self, let scene else { return }
            DispatchQueue.main.async {
                self.presentEditor(size: scene.size)
            }
        }
        commitSceneSwitch(scene)
    }

    func presentRemotePlaytest(size: CGSize, level: LevelModel, documentId: String) {
        guard !isSwappingScene else { return }
        isSwappingScene = true
        remotePlayLevel = level
        remoteDocumentId = documentId
        let scene = GameScene(size: size, level: level)
        scene.scaleMode = .resizeFill
        scene.isRemoteLevel = true
        scene.remoteDocumentId = documentId
        scene.onExitToEditor = { [weak self, weak scene] in
            guard let self, let scene else { return }
            self.clearRemotePlay()
            DispatchQueue.main.async {
                self.presentEditor(size: scene.size)
            }
        }
        commitSceneSwitch(scene)
    }

    /// Apply scene after current run-loop work (SwiftUI layout + SpriteKit touch) finishes.
    private func commitSceneSwitch(_ scene: SKScene) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.activeScene = scene
            self.isSwappingScene = false
        }
    }

    func startOnlineLevel(documentId: String, size: CGSize) {
        browseLoadError = nil
        let playSize: CGSize = (size.width > 1 && size.height > 1) ? size : UIScreen.main.bounds.size
        FirestoreLevelsService.shared.loadLevelForPlay(documentId: documentId) { [weak self] result in
            guard let self else { return }
            DispatchQueue.main.async {
                switch result {
                case let .success(level):
                    self.showBrowseOnline = false
                    // Let SwiftUI finish dismissing the sheet before swapping scenes.
                    DispatchQueue.main.async { [weak self] in
                        self?.presentRemotePlaytest(size: playSize, level: level, documentId: documentId)
                    }
                case let .failure(err):
                    self.browseLoadError = err.localizedDescription
                }
            }
        }
    }

    private func clearRemotePlay() {
        remotePlayLevel = nil
        remoteDocumentId = nil
    }
}

struct CubeRunRootView: View {
    @StateObject private var session = CubeRunSession()
    @State private var containerSize: CGSize = .zero

    var body: some View {
        GeometryReader { geo in
            ZStack {
                SpriteKitHost(scene: session.activeScene)
                    .onAppear {
                        containerSize = geo.size
                        if session.activeScene == nil {
                            session.presentEditor(size: geo.size)
                        }
                    }
                    .onChange(of: geo.size) { newSize in
                        containerSize = newSize
                        session.activeScene?.size = newSize
                    }

                if let msg = session.browseLoadError {
                    VStack {
                        Text(msg)
                            .padding(12)
                            .background(.ultraThinMaterial)
                            .cornerRadius(10)
                            .padding()
                        Spacer()
                    }
                }
            }
        }
        .ignoresSafeArea()
        .sheet(isPresented: $session.showBrowseOnline) {
            BrowseLevelsView { docId in
                session.startOnlineLevel(documentId: docId, size: containerSize)
            }
        }
        .sheet(isPresented: $session.showPublishSheet) {
            PublishLevelView(level: session.levelLocal)
        }
    }
}

/// Hosts a single `SKView` and presents the active scene when it changes.
struct SpriteKitHost: UIViewRepresentable {
    final class Coordinator {
        weak var view: SKView?
        var lastPresentedScene: SKScene?
    }

    var scene: SKScene?

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> SKView {
        let view = SKView()
        view.ignoresSiblingOrder = true
        view.isMultipleTouchEnabled = false
        view.showsFPS = false
        view.showsNodeCount = false
        context.coordinator.view = view
        if let scene {
            view.presentScene(scene)
            context.coordinator.lastPresentedScene = scene
        }
        return view
    }

    func updateUIView(_ uiView: SKView, context: Context) {
        guard let scene else { return }
        guard uiView.scene !== scene || context.coordinator.lastPresentedScene !== scene else { return }
        // Never call presentScene synchronously from UIViewRepresentable updates — defer one turn.
        uiView.scene?.isPaused = true
        let coordinator = context.coordinator
        DispatchQueue.main.async { [weak uiView] in
            guard let uiView, !uiView.isHidden else { return }
            if uiView.scene !== scene {
                uiView.presentScene(scene)
            }
            coordinator.lastPresentedScene = scene
        }
    }
}
