import SwiftUI
import AVFoundation

/// Vista previa: capa del reproductor + textos superpuestos (arrastrables).
struct PreviewView: View {
    @Bindable var model: EditorModel
    var onImportPhotos: () -> Void = {}
    var onImportFiles: () -> Void = {}

    var body: some View {
        ZStack {
            if model.clips.isEmpty {
                emptyState
            } else {
                GeometryReader { geo in
                    ZStack {
                        PlayerLayerView(player: model.player)
                            .onTapGesture { model.togglePlay() }
                        ForEach(model.visibleTexts) { text in
                            TextOverlayView(text: text, size: geo.size, isSelected: text.id == model.selectedTextID) { point in
                                model.moveText(id: text.id, to: CGPoint(x: point.x / geo.size.width, y: point.y / geo.size.height))
                            } onTap: {
                                model.selectedTextID = text.id
                            }
                        }
                        StickerCanvas(model: model, size: geo.size)
                    }
                    .overlay {
                        if !model.isPlaying && model.duration > 0 {
                            Image(systemName: "play.fill")
                                .font(.system(size: 26, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 62, height: 62)
                                .background(.ultraThinMaterial, in: Circle())
                                .opacity(0.85)
                                .allowsHitTesting(false)
                                .transition(.scale(scale: 0.6).combined(with: .opacity))
                        }
                    }
                    .animation(.easeOut(duration: 0.2), value: model.isPlaying)
                }
                .aspectRatio(model.renderAspect, contentMode: .fit)
                .background(Color.black)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.stroke))
                .shadow(color: Theme.accent.opacity(0.25), radius: 24, y: 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle().fill(Theme.gradient).frame(width: 92, height: 92).blur(radius: 30).opacity(0.7)
                Image(systemName: "film.stack.fill")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(Theme.gradient)
            }
            VStack(spacing: 6) {
                Text("Empieza tu historia")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                Text("Agrega videos desde tu galería o tus archivos")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
            }
            HStack(spacing: 10) {
                Button(action: onImportPhotos) {
                    Label("Fotos", systemImage: "photo.on.rectangle.angled")
                }
                .buttonStyle(GradientButtonStyle())
                Button(action: onImportFiles) {
                    Label("Archivos", systemImage: "folder")
                        .padding(.horizontal, 10)
                }
                .buttonStyle(ChipButtonStyle())
            }
        }
        .foregroundStyle(.white)
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassCard(cornerRadius: 24)
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
            .padding(.horizontal, text.hasBackground ? CGFloat(text.fontSize) * size.height * 0.35 : 4)
            .padding(.vertical, text.hasBackground ? CGFloat(text.fontSize) * size.height * 0.18 : 4)
            .background {
                if text.hasBackground {
                    RoundedRectangle(cornerRadius: CGFloat(text.fontSize) * size.height * 0.28)
                        .fill(Color.black.opacity(0.62))
                }
            }
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Theme.gradient, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
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
