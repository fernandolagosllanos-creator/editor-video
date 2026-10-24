import SwiftUI
import CoreGraphics

// MARK: - Transición al siguiente clip

/// Galería de transiciones: cada tarjeta se anima mostrando el efecto con miniaturas de tus clips.
struct TransitionSheet: View {
    @Bindable var model: EditorModel
    @Environment(\.dismiss) private var dismiss
    @State private var type: TransitionType = .crossfade
    @State private var seconds: Double = 0.6
    @State private var applyToAll = false

    /// Último cuadro del clip seleccionado y primero del siguiente (o colores si no hay miniaturas).
    private var frames: (CGImage?, CGImage?) {
        guard let index = model.selectedClipIndex else { return (nil, nil) }
        let current = model.clips[index]
        let next = index + 1 < model.clips.count ? model.clips[index + 1] : nil
        return (current.thumbnails.last, next?.thumbnails.first ?? current.thumbnails.first)
    }

    private var isLastClip: Bool { model.selectedClipIndex == model.clips.count - 1 }

    var body: some View {
        let pair = frames
        let from = pair.0
        let to = pair.1
        FXSheet(title: "Transición", symbol: "square.on.square.dashed") {
            TransitionPreview(type: type, from: from, to: to, seconds: seconds)
                .frame(height: 210)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(FXPalette.stroke))
                .overlay(alignment: .bottomLeading) {
                    Label(type.label, systemImage: type.symbol)
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(12)
                }
            Text(type.detail)
                .font(.footnote)
                .foregroundStyle(FXPalette.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            FXSectionTitle(text: "Efecto")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 12)], spacing: 12) {
                ForEach(TransitionType.allCases) { t in
                    card(t, from: from, to: to)
                }
            }

            if type != .none {
                FXSectionTitle(text: "Duración", trailing: String(format: "%.1f s", seconds))
                FXSlider(value: Binding(get: { seconds }, set: { seconds = ($0 * 10).rounded() / 10 }),
                         range: 0.2...2.0, defaultValue: 0.6)
            }

            if isLastClip && !applyToAll {
                Label("Es el último clip: la transición se verá cuando agregues otro después.", systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(FXPalette.amber)
            }
        } footer: {
            Toggle(isOn: $applyToAll) {
                Text("A todos los clips").font(.footnote.weight(.semibold))
            }
            .toggleStyle(.switch)
            .fixedSize()
            Spacer()
            Button("Cancelar") { dismiss() }.buttonStyle(FXSecondaryButtonStyle())
            Button("Aplicar") {
                if applyToAll {
                    model.setTransitionForAll(type, duration: seconds)
                } else {
                    model.setTransition(type, duration: seconds)
                }
                dismiss()
            }
            .buttonStyle(FXPrimaryButtonStyle())
            .keyboardShortcut(.defaultAction)
        }
        .onAppear {
            if let clip = model.selectedClip {
                type = clip.transitionOut == .none ? .crossfade : clip.transitionOut
                seconds = clip.transitionDuration
            }
        }
    }

    private func card(_ t: TransitionType, from: CGImage?, to: CGImage?) -> some View {
        let selected = t == type
        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { type = t }
        } label: {
            VStack(spacing: 7) {
                TransitionPreview(type: t, from: from, to: to, seconds: 0.8)
                    .frame(height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(selected ? AnyShapeStyle(FXPalette.gradient) : AnyShapeStyle(FXPalette.stroke),
                                          lineWidth: selected ? 3 : 1)
                    }
                HStack(spacing: 5) {
                    Image(systemName: t.symbol).font(.system(size: 11, weight: .bold))
                    Text(t.label).font(.caption.weight(selected ? .bold : .medium)).lineLimit(1)
                }
                .foregroundStyle(selected ? .white : FXPalette.textSecondary)
            }
            .padding(6)
            .background(selected ? FXPalette.surfaceRaised : FXPalette.surface,
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .scaleEffect(selected ? 1.03 : 1)
        }
        .buttonStyle(.plain)
    }
}

/// Animación en bucle de una transición entre dos imágenes: pausa en A, efecto, pausa en B.
/// Imita lo que hace el compositor al exportar.
struct TransitionPreview: View {
    let type: TransitionType
    let from: CGImage?
    let to: CGImage?
    /// Duración del efecto dentro del bucle.
    let seconds: Double

    var body: some View {
        SwiftUI.TimelineView(.animation) { context in
            let hold = 0.7
            let cycle = hold * 2 + seconds
            let t = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: cycle)
            let raw = min(1, max(0, (t - hold) / max(0.05, seconds)))
            // El mismo suavizado (ease in-out) que usa el compositor.
            let p = CGFloat(raw * raw * (3 - 2 * raw))
            GeometryReader { geo in
                frame(for: geo.size, progress: p)
            }
        }
        .background(Color.black)
    }

    @ViewBuilder
    private func frame(for size: CGSize, progress p: CGFloat) -> some View {
        let w = size.width, h = size.height
        let a = picture(from, fallback: [FXPalette.accent, Color(red: 0.25, green: 0.18, blue: 0.6)], label: "A", size: size)
        let b = picture(to, fallback: [FXPalette.accent2, FXPalette.amber], label: "B", size: size)
        ZStack {
            switch type {
            case .none:
                if p < 0.5 { a } else { b }
            case .crossfade:
                a
                b.opacity(Double(p))
            case .fadeBlack:
                Color.black
                if p < 0.5 { a.opacity(Double(1 - p * 2)) } else { b.opacity(Double(p * 2 - 1)) }
            case .slideLeft:
                a.offset(x: -p * w)
                b.offset(x: (1 - p) * w)
            case .slideUp:
                a.offset(y: -p * h)
                b.offset(y: (1 - p) * h)
            case .zoom:
                a.scaleEffect(1 + 0.4 * p).opacity(Double(1 - p))
                b.scaleEffect(1.3 - 0.3 * p).opacity(Double(p))
            case .wipe:
                a
                b.mask(alignment: .leading) { Rectangle().frame(width: w * p) }
            case .iris:
                let d = hypot(w, h) * p
                a
                b.mask { Circle().frame(width: d, height: d) }
            }
        }
        .frame(width: w, height: h)
        .clipped()
    }

    private func picture(_ image: CGImage?, fallback: [Color], label: String, size: CGSize) -> some View {
        ZStack {
            if let image {
                Image(decorative: image, scale: 1).resizable().aspectRatio(contentMode: .fill)
            } else {
                LinearGradient(colors: fallback, startPoint: .topLeading, endPoint: .bottomTrailing)
                Text(label).font(.system(size: min(size.width, size.height) * 0.4, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
    }
}
