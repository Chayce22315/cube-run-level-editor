import SwiftUI
import SpriteKit

@main
struct CubeRunApp: App {
    var body: some Scene {
        WindowGroup {
            CubeRunRootView()
        }
    }
}

/// Owns the shared `LevelModel` and swaps SpriteKit scenes for build vs playtest.
final class CubeRunSession: ObservableObject {
    let level: LevelModel
    @Published private(set) var activeScene: SKScene?

    init() {
        level = LevelModel.loadFromDisk() ?? LevelModel()
    }

    func attachEditor(scene: EditorScene) {
        scene.onPlay = { [weak self, weak scene] in
            guard let self, let scene else { return }
            self.presentPlaytest(size: scene.size)
        }
    }

    func presentEditor(size: CGSize) {
        let scene = EditorScene(size: size, level: level)
        scene.scaleMode = .resizeFill
        attachEditor(scene: scene)
        activeScene = scene
    }

    func presentPlaytest(size: CGSize) {
        let scene = GameScene(size: size, level: level)
        scene.scaleMode = .resizeFill
        scene.onExitToEditor = { [weak self, weak scene] in
            guard let self, let scene else { return }
            self.presentEditor(size: scene.size)
        }
        activeScene = scene
    }
}

struct CubeRunRootView: View {
    @StateObject private var session = CubeRunSession()

    var body: some View {
        GeometryReader { geo in
            SpriteKitHost(scene: session.activeScene)
                .onAppear {
                    if session.activeScene == nil {
                        session.presentEditor(size: geo.size)
                    }
                }
                .onChange(of: geo.size) { newSize in
                    session.activeScene?.size = newSize
                }
        }
        .ignoresSafeArea()
    }
}

/// Hosts a single `SKView` and presents the active scene when it changes.
struct SpriteKitHost: UIViewRepresentable {
    final class Coordinator {
        weak var view: SKView?
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
        }
        return view
    }

    func updateUIView(_ uiView: SKView, context: Context) {
        guard let scene else { return }
        if uiView.scene !== scene {
            uiView.presentScene(scene)
        }
    }
}
