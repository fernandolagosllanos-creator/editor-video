import SwiftUI
import AVFoundation

/// Vista previa: capa del reproductor + textos superpuestos (arrastrables).
struct PreviewView: View {
    @Bindable var model: EditorModel

    var body: some View {
        ZStack {
            Color.black
            if model.clips.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "film.stack")
                        .font(.system(size: 48))
                    Text("Importa un video para empezar")
                        .font(.headline)
                }
                .foregroundStyle(.secondary)
            } else {
                GeometryReader { geo in
                    ZStack {
                        PlayerLayerView(player: model.player)
                        ForEach(model.visibleTexts) { text in
                            TextOverlayView(text: text, size: geo.size, isSelected: text.id == model.selectedTextID) { point in
                                model.moveText(id: text.id, to: CGPoint(x: point.x / geo.size.width, y: point.y / geo.size.height))
                            } onTap: {
                                model.selectedTextID = text.id
                            }
                        }
                        StickerCanvas(model: model, size: geo.size)
                    }
                }
                .aspectRatio(model.renderAspect, contentMode: .fit)
            }
        }
    }
}

struct TextOverlayView: View {
    let text: TextOverlay
    let size: CGSize
    let isSelected: Bool
    let onMove: (CGPoint) -> Void
    let onTap: () -> Void

    var body: some View {
        Text(text.text)
            .font(.system(size: CGFloat(text.fontSize) * size.height, weight: .bold))
            .foregroundStyle(text.color.color)
            .multilineTextAlignment(.center)
            .shadow(color: .black.opacity(0.85), radius: CGFloat(text.fontSize) * size.height * 0.06, y: 1)
            .padding(4)
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 4).stroke(Color.accentColor, lineWidth: 1.5)
                }
            }
            .frame(maxWidth: size.width * 0.9)
            .position(x: text.position.x * size.width, y: text.position.y * size.height)
            .gesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { value in onMove(value.location) }
            )
            .onTapGesture { onTap() }
    }
}

#if os(macOS)
import AppKit

struct PlayerLayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> PlayerNSView {
        let view = PlayerNSView()
        view.playerLayer.player = player
        return view
    }

    func updateNSView(_ nsView: PlayerNSView, context: Context) {
        nsView.playerLayer.player = player
    }
}

final class PlayerNSView: NSView {
    let playerLayer = AVPlayerLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        playerLayer.videoGravity = .resizeAspect
        layer?.addSublayer(playerLayer)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) no implementado") }

    override func layout() {
        super.layout()
        playerLayer.frame = bounds
    }
}
#else
import UIKit

struct PlayerLayerView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerUIView {
        let view = PlayerUIView()
        view.playerLayer.player = player
        return view
    }

    func updateUIView(_ uiView: PlayerUIView, context: Context) {
        uiView.playerLayer.player = player
    }
}

final class PlayerUIView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }

    override init(frame: CGRect) {
        super.init(frame: frame)
        playerLayer.videoGravity = .resizeAspect
        backgroundColor = .black
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) no implementado") }
}
#endif
