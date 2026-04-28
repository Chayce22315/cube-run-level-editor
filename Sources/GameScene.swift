import SpriteKit
import QuartzCore

#if canImport(UIKit)
import UIKit
#endif

/// Playtest: auto-run cube, jump, spikes kill, right grid edge = goal.
final class GameScene: SKScene, SKPhysicsContactDelegate {
    private weak var levelRef: LevelModel?
    var onExitToEditor: (() -> Void)?

    /// When set, level is from Firestore: do not write `UserDefaults`, do not mark verified locally, increment plays once.
    var isRemoteLevel = false
    var remoteDocumentId: String?
    private var didIncrementRemotePlays = false

    private static let physicsTileSize: CGFloat = 40

    private let worldNode = SKNode()
    private var playerNode: SKShapeNode!
    private var playStartMonotonicMs: Int64 = 0

    private let playerCategory: UInt32 = 1
    private let solidCategory: UInt32 = 2
    private let spikeCategory: UInt32 = 4
    private let goalCategory: UInt32 = 8

    private var runSpeed: CGFloat = 180
    private var jumpImpulse: CGFloat = 320
    private var standingOnSolids = Set<ObjectIdentifier>()
    private var finished = false

    private var playerHalf: CGFloat { Self.physicsTileSize * 0.36 }

    convenience init(size: CGSize, level: LevelModel) {
        self.init(size: size)
        self.scaleMode = .resizeFill
        self.levelRef = level
    }

    override func didMove(to view: SKView) {
        backgroundColor = SKColor(red: 0.06, green: 0.07, blue: 0.1, alpha: 1)
        physicsWorld.gravity = CGVector(dx: 0, dy: -22)
        physicsWorld.contactDelegate = self

        removeAllChildren()
        addChild(worldNode)
        worldNode.removeAllChildren()

        guard let level = levelRef else { return }

        level.beginPlaytestRecording()
        playStartMonotonicMs = Self.nowMs()

        if isRemoteLevel, let docId = remoteDocumentId, !didIncrementRemotePlays {
            didIncrementRemotePlays = true
            FirestoreLevelsService.shared.incrementPlays(documentId: docId, completion: nil)
        }

        let ts = Self.physicsTileSize
        let cols = LevelModel.columns
        let rows = LevelModel.rows

        for row in 0..<rows {
            for col in 0..<cols {
                let t = level.tileAt(col: col, row: row)
                let x = CGFloat(col) * ts + ts / 2
                let y = CGFloat(row) * ts + ts / 2
                if t == 1 {
                    let n = SKShapeNode(rectOf: CGSize(width: ts - 2, height: ts - 2), cornerRadius: 4)
                    n.position = CGPoint(x: x, y: y)
                    n.fillColor = SKColor(red: 0.35, green: 0.65, blue: 0.95, alpha: 1)
                    n.strokeColor = .clear
                    n.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: ts - 2, height: ts - 2))
                    n.physicsBody?.isDynamic = false
                    n.physicsBody?.categoryBitMask = solidCategory
                    n.physicsBody?.contactTestBitMask = playerCategory
                    n.physicsBody?.collisionBitMask = playerCategory
                    worldNode.addChild(n)
                } else if t == 2 {
                    let n = SKShapeNode()
                    let path = CGMutablePath()
                    path.move(to: CGPoint(x: -ts / 2 + 2, y: -ts / 2 + 2))
                    path.addLine(to: CGPoint(x: ts / 2 - 2, y: -ts / 2 + 2))
                    path.addLine(to: CGPoint(x: 0, y: ts / 2 - 2))
                    path.closeSubpath()
                    n.path = path
                    n.position = CGPoint(x: x, y: y)
                    n.fillColor = SKColor(red: 0.95, green: 0.35, blue: 0.35, alpha: 1)
                    n.strokeColor = .clear
                    n.physicsBody = SKPhysicsBody(polygonFrom: path as CGPath)
                    n.physicsBody?.isDynamic = false
                    n.physicsBody?.categoryBitMask = spikeCategory
                    n.physicsBody?.contactTestBitMask = playerCategory
                    n.physicsBody?.collisionBitMask = 0
                    worldNode.addChild(n)
                }
            }
        }

        // Goal: vertical strip at the right edge of the grid (column 19's right boundary).
        let goalCenterX = CGFloat(cols) * ts - 4
        let goalH = CGFloat(rows) * ts
        let goal = SKNode()
        goal.position = CGPoint(x: goalCenterX, y: goalH / 2)
        goal.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: 12, height: goalH))
        goal.physicsBody?.isDynamic = false
        goal.physicsBody?.categoryBitMask = goalCategory
        goal.physicsBody?.contactTestBitMask = playerCategory
        goal.physicsBody?.collisionBitMask = 0
        worldNode.addChild(goal)

        let side = ts * 0.72
        playerNode = SKShapeNode(rectOf: CGSize(width: side, height: side), cornerRadius: 4)
        playerNode.fillColor = SKColor(red: 0.95, green: 0.92, blue: 0.35, alpha: 1)
        playerNode.strokeColor = .clear
        playerNode.position = CGPoint(x: ts * 0.5, y: ts * 2.5)
        playerNode.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: side, height: side))
        playerNode.physicsBody?.allowsRotation = false
        playerNode.physicsBody?.restitution = 0
        playerNode.physicsBody?.friction = 0.2
        playerNode.physicsBody?.categoryBitMask = playerCategory
        playerNode.physicsBody?.contactTestBitMask = solidCategory | spikeCategory | goalCategory
        playerNode.physicsBody?.collisionBitMask = solidCategory
        worldNode.addChild(playerNode)

        addEditorExitHint()
        layoutWorldVertically()
        centerWorldOnPlayer()
    }

    private func addEditorExitHint() {
        let back = SKLabelNode(text: "Editor")
        back.fontName = "Helvetica"
        back.fontSize = 16
        back.fontColor = SKColor(white: 0.85, alpha: 1)
        back.horizontalAlignmentMode = .right
        back.verticalAlignmentMode = .center
        back.position = CGPoint(x: size.width - 16, y: size.height - 28)
        back.name = "hud:back"
        back.zPosition = 2000
        addChild(back)
    }

    private static func nowMs() -> Int64 {
        Int64(CACurrentMediaTime() * 1000)
    }

    private func elapsedPlayMs() -> Int64 {
        Self.nowMs() - playStartMonotonicMs
    }

    override func update(_ currentTime: TimeInterval) {
        guard !finished, let body = playerNode.physicsBody else { return }
        body.velocity.dx = runSpeed

        let ts = Self.physicsTileSize
        let goalLine = CGFloat(LevelModel.columns) * ts - playerHalf
        if playerNode.position.x >= goalLine {
            completeLevel()
            return
        }

        centerWorldOnPlayer()
    }

    private func layoutWorldVertically() {
        let ts = Self.physicsTileSize
        let rows = LevelModel.rows
        let gridH = CGFloat(rows) * ts
        let bottomPad = max(32, size.height * 0.1)
        worldNode.position.y = bottomPad - 0
        let lift = max(0, (size.height - bottomPad - gridH) * 0.35)
        worldNode.position.y += lift
    }

    private func centerWorldOnPlayer() {
        let margin: CGFloat = max(80, size.width * 0.28)
        let px = playerNode.position.x
        let target = margin - px
        let worldWidth = CGFloat(LevelModel.columns) * Self.physicsTileSize + 24
        let minX = size.width - worldWidth - margin * 0.5
        let maxX: CGFloat = 48
        worldNode.position.x = min(maxX, max(minX, target))
    }

    #if canImport(UIKit)
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard !finished, let t = touches.first, let view else { return }
        let p = convertPoint(fromView: t.location(in: view))
        let picked = nodes(at: p)
        if picked.contains(where: { node in
            var n: SKNode? = node
            while let c = n {
                if c.name == "hud:back" { return true }
                n = c.parent
            }
            return false
        }) {
            exitToEditor()
            return
        }
        jumpIfPossible()
    }
    #endif

    private var isGrounded: Bool { !standingOnSolids.isEmpty }

    private func jumpIfPossible() {
        guard isGrounded, let body = playerNode.physicsBody else { return }
        body.velocity.dy = jumpImpulse
        standingOnSolids.removeAll()
        levelRef?.recordJumpTap(elapsedMs: elapsedPlayMs())
    }

    func didBegin(_ contact: SKPhysicsContact) {
        guard !finished else { return }

        let bodies = [contact.bodyA, contact.bodyB]
        let masks = bodies.map { $0.categoryBitMask }

        if masks.contains(where: { $0 == spikeCategory }) {
            die()
            return
        }
        if masks.contains(where: { $0 == goalCategory }) {
            completeLevel()
            return
        }
        if let solidBody = bodies.first(where: { $0.categoryBitMask == solidCategory }),
           let playerBody = bodies.first(where: { $0.categoryBitMask == playerCategory }),
           let solidNode = solidBody.node,
           let playerSk = playerBody.node,
           isPlayerOnTopOfSolid(playerBody: playerSk, solidBody: solidNode)
        {
            standingOnSolids.insert(ObjectIdentifier(solidNode))
        }
    }

    func didEnd(_ contact: SKPhysicsContact) {
        let bodies = [contact.bodyA, contact.bodyB]
        let masks = bodies.map { $0.categoryBitMask }
        if masks.contains(where: { $0 == spikeCategory }) || masks.contains(where: { $0 == goalCategory }) { return }

        if let solidBody = bodies.first(where: { $0.categoryBitMask == solidCategory }),
           let solidNode = solidBody.node
        {
            standingOnSolids.remove(ObjectIdentifier(solidNode))
        }
    }

    private func isPlayerOnTopOfSolid(playerBody: SKNode?, solidBody: SKNode?) -> Bool {
        guard let p = playerBody, let s = solidBody else { return false }
        let ts = Self.physicsTileSize
        let halfBlock = (ts - 2) / 2
        let footY = p.position.y - playerHalf
        let topY = s.position.y + halfBlock
        let dx = abs(p.position.x - s.position.x)
        return dx < ts * 0.48 && footY >= topY - 6 && footY <= topY + 10
    }

    private func die() {
        guard !finished else { return }
        finished = true
        playerNode.physicsBody?.velocity = .zero
        persistAndExit()
    }

    private func completeLevel() {
        guard !finished else { return }
        finished = true
        if !isRemoteLevel {
            levelRef?.markVerified()
        }
        persistAndExit()
    }

    private func exitToEditor() {
        guard !finished else { return }
        finished = true
        persistAndExit()
    }

    private func persistAndExit() {
        if !isRemoteLevel {
            levelRef?.saveToDisk()
        }
        onExitToEditor?()
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        layoutWorldVertically()
        childNode(withName: "//hud:back")?.position = CGPoint(x: size.width - 16, y: size.height - 28)
        centerWorldOnPlayer()
    }
}
