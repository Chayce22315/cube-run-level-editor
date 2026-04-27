import SpriteKit

#if canImport(UIKit)
import UIKit
#endif

/// Build mode: paint grid, pan horizontally, play / save / clear.
final class EditorScene: SKScene {
    private weak var levelRef: LevelModel?
    var onPlay: (() -> Void)?

    private let gridContainer = SKNode()
    private var panOffsetX: CGFloat = 0
    private var lastTouchX: CGFloat?
    private var isPanning = false

    /// 0 erase, 1 block, 2 spike
    private var selectedTool = 1

    private var layoutTopInset: CGFloat = 56
    private var layoutBottomInset: CGFloat = 72
    private var layoutGridRect = CGRect.zero
    private var tileSize: CGFloat = 32

    private var playButton: SKNode!
    private var saveButton: SKNode!
    private var clearButton: SKNode!
    private var blockButton: SKNode!
    private var spikeButton: SKNode!
    private var eraseButton: SKNode!

    convenience init(size: CGSize, level: LevelModel) {
        self.init(size: size)
        self.scaleMode = .resizeFill
        self.levelRef = level
    }

    override func didMove(to view: SKView) {
        backgroundColor = SKColor(red: 0.08, green: 0.09, blue: 0.12, alpha: 1)
        removeAllChildren()
        addChild(gridContainer)
        rebuildLayout()
        rebuildGridVisuals()
        updateToolHighlight()
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        rebuildLayout()
        rebuildGridVisuals()
        updateToolHighlight()
    }

    func bind(level: LevelModel) {
        levelRef = level
        rebuildGridVisuals()
    }

    func syncFromModel() {
        rebuildGridVisuals()
    }

    private func rebuildLayout() {
        let w = size.width
        let h = size.height
        layoutGridRect = CGRect(x: 0, y: layoutBottomInset, width: w, height: h - layoutTopInset - layoutBottomInset)

        let tw = layoutGridRect.width / CGFloat(LevelModel.columns)
        let th = layoutGridRect.height / CGFloat(LevelModel.rows)
        tileSize = min(tw, th)

        [playButton, saveButton, clearButton, blockButton, spikeButton, eraseButton].compactMap { $0 }.forEach { $0.removeFromParent() }

        playButton = makeBarButton(text: "▶️ Play", position: CGPoint(x: w * 0.2, y: h - 28), name: "hud:play")
        saveButton = makeBarButton(text: "💾 Save", position: CGPoint(x: w * 0.5, y: h - 28), name: "hud:save")
        clearButton = makeBarButton(text: "🗑️ Clear", position: CGPoint(x: w * 0.8, y: h - 28), name: "hud:clear")
        addChild(playButton)
        addChild(saveButton)
        addChild(clearButton)

        blockButton = makeToolButton(label: "Block", position: CGPoint(x: w * 0.22, y: 36), name: "tool:block")
        spikeButton = makeToolButton(label: "Spike", position: CGPoint(x: w * 0.5, y: 36), name: "tool:spike")
        eraseButton = makeToolButton(label: "Erase", position: CGPoint(x: w * 0.78, y: 36), name: "tool:erase")
        addChild(blockButton)
        addChild(spikeButton)
        addChild(eraseButton)

        zPositionHUD()
    }

    private func zPositionHUD() {
        let hz: CGFloat = 1000
        playButton.zPosition = hz
        saveButton.zPosition = hz
        clearButton.zPosition = hz
        blockButton.zPosition = hz
        spikeButton.zPosition = hz
        eraseButton.zPosition = hz
    }

    private func makeBarButton(text: String, position: CGPoint, name: String) -> SKNode {
        let root = SKNode()
        root.position = position
        root.name = name
        let bg = SKShapeNode(rect: CGRect(x: -52, y: -18, width: 104, height: 36), cornerRadius: 8)
        bg.name = name
        bg.fillColor = SKColor(white: 0.22, alpha: 1)
        bg.strokeColor = .clear
        let label = SKLabelNode(text: text)
        label.name = name
        label.fontName = "Helvetica"
        label.fontSize = 14
        label.verticalAlignmentMode = .center
        label.horizontalAlignmentMode = .center
        label.fontColor = .white
        root.addChild(bg)
        root.addChild(label)
        return root
    }

    private func makeToolButton(label: String, position: CGPoint, name: String) -> SKNode {
        let root = SKNode()
        root.position = position
        root.name = name
        let bg = SKShapeNode(rect: CGRect(x: -54, y: -22, width: 108, height: 44), cornerRadius: 10)
        bg.name = name
        bg.fillColor = SKColor(white: 0.2, alpha: 1)
        bg.strokeColor = .clear
        let ln = SKLabelNode(text: label)
        ln.name = name
        ln.fontName = "Helvetica-Bold"
        ln.fontSize = 15
        ln.verticalAlignmentMode = .center
        ln.horizontalAlignmentMode = .center
        ln.fontColor = .white
        root.addChild(bg)
        root.addChild(ln)
        return root
    }

    private func gridOriginInScene() -> CGPoint {
        let gridW = tileSize * CGFloat(LevelModel.columns)
        let gridH = tileSize * CGFloat(LevelModel.rows)
        let ox = (size.width - gridW) / 2 + panOffsetX
        let oy = layoutBottomInset + (layoutGridRect.height - gridH) / 2
        return CGPoint(x: ox, y: oy)
    }

    private func rebuildGridVisuals() {
        gridContainer.removeAllChildren()
        guard let level = levelRef else { return }

        let origin = gridOriginInScene()

        for row in 0..<LevelModel.rows {
            for col in 0..<LevelModel.columns {
                let x = origin.x + CGFloat(col) * tileSize
                let y = origin.y + CGFloat(row) * tileSize
                let cell = CGRect(x: x, y: y, width: tileSize, height: tileSize)
                let border = SKShapeNode(rect: cell)
                border.fillColor = .clear
                border.strokeColor = SKColor(white: 0.25, alpha: 1)
                border.lineWidth = 1
                gridContainer.addChild(border)

                let t = level.tileAt(col: col, row: row)
                if t != 0 {
                    let fill = SKShapeNode(rect: cell.insetBy(dx: 2, dy: 2), cornerRadius: 3)
                    fill.strokeColor = .clear
                    if t == 1 {
                        fill.fillColor = SKColor(red: 0.35, green: 0.65, blue: 0.95, alpha: 1)
                    } else {
                        fill.fillColor = SKColor(red: 0.95, green: 0.35, blue: 0.35, alpha: 1)
                    }
                    gridContainer.addChild(fill)
                }
            }
        }
    }

    private func updateToolHighlight() {
        func style(_ root: SKNode?, selected: Bool) {
            guard let bg = root?.children.first as? SKShapeNode else { return }
            bg.fillColor = selected ? SKColor(red: 0.25, green: 0.45, blue: 0.75, alpha: 1) : SKColor(white: 0.2, alpha: 1)
        }
        style(blockButton, selected: selectedTool == 1)
        style(spikeButton, selected: selectedTool == 2)
        style(eraseButton, selected: selectedTool == 0)
    }

    #if canImport(UIKit)
    private func locationInScene(from touches: Set<UITouch>) -> CGPoint? {
        guard let t = touches.first, let view else { return nil }
        return convertPoint(fromView: t.location(in: view))
    }
    #endif

    #if canImport(UIKit)
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let p = locationInScene(from: touches) else { return }
        lastTouchX = p.x
        isPanning = false

        if handleHUDTap(at: p) { return }

        if layoutGridRect.contains(p) {
            applyPaint(at: p)
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let p = locationInScene(from: touches), let lx = lastTouchX else { return }
        let dx = p.x - lx
        lastTouchX = p.x

        if layoutGridRect.contains(p) || isPanning {
            if abs(dx) > 2 {
                isPanning = true
                panOffsetX += dx
                rebuildGridVisuals()
            }
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        lastTouchX = nil
        isPanning = false
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        touchesEnded(touches, with: event)
    }
    #endif

    private func hudId(startingAt node: SKNode?) -> String? {
        var n: SKNode? = node
        while let c = n {
            if let name = c.name {
                if name.hasPrefix("hud:") { return name }
                if name.hasPrefix("tool:") { return name }
            }
            n = c.parent
        }
        return nil
    }

    private func handleHUDTap(at p: CGPoint) -> Bool {
        for n in nodes(at: p) {
            guard let id = hudId(startingAt: n) else { continue }
            switch id {
            case "hud:play":
                onPlay?()
                return true
            case "hud:save":
                levelRef?.saveToDisk()
                return true
            case "hud:clear":
                levelRef?.clearGrid()
                rebuildGridVisuals()
                return true
            case "tool:block":
                selectedTool = 1
                updateToolHighlight()
                return true
            case "tool:spike":
                selectedTool = 2
                updateToolHighlight()
                return true
            case "tool:erase":
                selectedTool = 0
                updateToolHighlight()
                return true
            default:
                break
            }
        }
        return false
    }

    private func applyPaint(at p: CGPoint) {
        guard let level = levelRef else { return }
        let origin = gridOriginInScene()
        let localX = p.x - origin.x
        let localY = p.y - origin.y
        guard localX >= 0, localY >= 0 else { return }
        let col = Int(localX / tileSize)
        let row = Int(localY / tileSize)
        guard col >= 0, col < LevelModel.columns, row >= 0, row < LevelModel.rows else { return }
        level.setTile(col: col, row: row, value: selectedTool)
        rebuildGridVisuals()
    }
}
