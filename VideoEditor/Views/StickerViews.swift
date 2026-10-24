import SwiftUI
import CoreGraphics

// MARK: - Dibujo de un sticker

/// Dibujo de un sticker (emoji o forma). Es el mismo para la vista previa y para la exportación.
struct StickerArtwork: View {
    let content: StickerContent
    var color: TextColor = .yellow
    var filled: Bool = true
    let side: CGFloat

    var body: some View {
        Group {
            switch content {
            case .emoji(let emoji):
                Text(emoji)
                    .font(.system(size: side * 0.8))
                    .minimumScaleFactor(0.2)
                    .lineLimit(1)
            case .shape(let shape):
                let path = StickerPath(shape: shape)
                if filled {
                    path.fill(color.color)
                        .overlay(path.stroke(Color.white, style: StrokeStyle(lineWidth: side * 0.035, lineJoin: .round)))
                        .shadow(color: .black.opacity(0.35), radius: side * 0.03, y: side * 0.015)
                        .padding(side * 0.06)
                } else {
                    path.stroke(color.color, style: StrokeStyle(lineWidth: side * 0.07, lineCap: .round, lineJoin: .round))
                        .shadow(color: .black.opacity(0.35), radius: side * 0.03, y: side * 0.015)
                        .padding(side * 0.08)
                }
            }
        }
        .frame(width: side, height: side)
    }
}

/// Formas vectoriales propias (no se usan símbolos del sistema para poder exportarlas libremente).
struct StickerPath: Shape {
    let shape: StickerShape

    func path(in r: CGRect) -> Path {
        switch shape {
        case .circle:
            return Path(ellipseIn: r)
        case .square:
            return Path(roundedRect: r, cornerRadius: min(r.width, r.height) * 0.16)
        case .star:
            return star(in: r, points: 5, inner: 0.45)
        case .burst:
            return star(in: r, points: 12, inner: 0.68)
        case .heart:
            var p = Path()
            let w = r.width, h = r.height, x = r.minX, y = r.minY
            p.move(to: CGPoint(x: x + w * 0.5, y: y + h * 0.95))
            p.addCurve(to: CGPoint(x: x, y: y + h * 0.32),
                       control1: CGPoint(x: x + w * 0.18, y: y + h * 0.72),
                       control2: CGPoint(x: x, y: y + h * 0.55))
            p.addCurve(to: CGPoint(x: x + w * 0.5, y: y + h * 0.18),
                       control1: CGPoint(x: x, y: y + h * 0.02),
                       control2: CGPoint(x: x + w * 0.4, y: y))
            p.addCurve(to: CGPoint(x: x + w, y: y + h * 0.32),
                       control1: CGPoint(x: x + w * 0.6, y: y),
                       control2: CGPoint(x: x + w, y: y + h * 0.02))
            p.addCurve(to: CGPoint(x: x + w * 0.5, y: y + h * 0.95),
                       control1: CGPoint(x: x + w, y: y + h * 0.55),
                       control2: CGPoint(x: x + w * 0.82, y: y + h * 0.72))
            p.closeSubpath()
            return p
        case .arrow:
            var p = Path()
            let w = r.width, h = r.height, x = r.minX, y = r.minY
            p.move(to: CGPoint(x: x, y: y + h * 0.38))
            p.addLine(to: CGPoint(x: x + w * 0.55, y: y + h * 0.38))
            p.addLine(to: CGPoint(x: x + w * 0.55, y: y + h * 0.15))
            p.addLine(to: CGPoint(x: x + w, y: y + h * 0.5))
            p.addLine(to: CGPoint(x: x + w * 0.55, y: y + h * 0.85))
            p.addLine(to: CGPoint(x: x + w * 0.55, y: y + h * 0.62))
            p.addLine(to: CGPoint(x: x, y: y + h * 0.62))
            p.closeSubpath()
            return p
        case .bubble:
            var p = Path()
            let w = r.width, h = r.height, x = r.minX, y = r.minY
            let body = CGRect(x: x, y: y + h * 0.08, width: w, height: h * 0.68)
            p.addRoundedRect(in: body, cornerSize: CGSize(width: w * 0.22, height: w * 0.22))
            p.move(to: CGPoint(x: x + w * 0.22, y: body.maxY - 1))
            p.addLine(to: CGPoint(x: x + w * 0.16, y: y + h * 0.95))
            p.addLine(to: CGPoint(x: x + w * 0.45, y: body.maxY - 1))
            p.closeSubpath()
            return p
        case .bolt:
            var p = Path()
            let w = r.width, h = r.height, x = r.minX, y = r.minY
            p.move(to: CGPoint(x: x + w * 0.62, y: y))
            p.addLine(to: CGPoint(x: x + w * 0.15, y: y + h * 0.56))
            p.addLine(to: CGPoint(x: x + w * 0.45, y: y + h * 0.56))
            p.addLine(to: CGPoint(x: x + w * 0.35, y: y + h))
            p.addLine(to: CGPoint(x: x + w * 0.85, y: y + h * 0.4))
            p.addLine(to: CGPoint(x: x + w * 0.55, y: y + h * 0.4))
            p.closeSubpath()
            return p
        }
    }

    private func star(in r: CGRect, points: Int, inner: CGFloat) -> Path {
        var p = Path()
        let center = CGPoint(x: r.midX, y: r.midY)
        let outer = min(r.width, r.height) / 2
        for i in 0..<(points * 2) {
            let radius = i.isMultiple(of: 2) ? outer : outer * inner
            let angle = Double(i) * .pi / Double(points) - .pi / 2
            let pt = CGPoint(x: center.x + CGFloat(cos(angle)) * radius, y: center.y + CGFloat(sin(angle)) * radius)
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        p.closeSubpath()
        return p
    }
}

/// Convierte los stickers en imágenes para "quemarlos" en el video al exportar.
@MainActor
enum StickerRenderer {
    static func images(for stickers: [StickerOverlay], canvasSize: CGSize) -> [UUID: CGImage] {
        var result: [UUID: CGImage] = [:]
        for s in stickers {
            let side = max(8, (CGFloat(s.size) * min(canvasSize.width, canvasSize.height)).rounded())
            let renderer = ImageRenderer(content: StickerArtwork(content: s.content, color: s.color,
                                                                 filled: s.filled, side: side))
            renderer.scale = 1
            renderer.isOpaque = false
            if let image = renderer.cgImage { result[s.id] = image }
        }
        return result
    }
}

// MARK: - Stickers sobre la vista previa

/// Capa de stickers sobre el reproductor: se arrastran para moverlos, se pellizcan para cambiar el
/// tamaño y se giran con dos dedos. Doble toque (o el lápiz) abre su edición.
struct StickerCanvas: View {
    @Bindable var model: EditorModel
    let size: CGSize

    var body: some View {
        ZStack {
            ForEach(model.visibleStickers) { sticker in
                StickerItemView(model: model, sticker: sticker, canvas: size)
            }
        }
        .frame(width: size.width, height: size.height)
    }
}

private struct StickerItemView: View {
    @Bindable var model: EditorModel
    let sticker: StickerOverlay
    let canvas: CGSize

    @GestureState private var drag: CGSize = .zero
    @GestureState private var pinch: CGFloat = 1
    @GestureState private var twist: Angle = .zero

    private var isSelected: Bool { model.selectedStickerID == sticker.id }

    var body: some View {
        let side = CGFloat(sticker.size) * min(canvas.width, canvas.height)
        // En pausa se muestra en reposo (para ubicarlo cómodo); al reproducir, animado.
        let st = model.isPlaying
            ? sticker.animation.state(at: model.currentTime - sticker.start, duration: sticker.duration)
            : (scale: 1.0, rotation: 0.0, opacity: 1.0, dy: 0.0)
        let center = CGPoint(x: sticker.position.x * canvas.width + drag.width,
                             y: sticker.position.y * canvas.height + drag.height)

        ZStack {
            StickerArtwork(content: sticker.content, color: sticker.color, filled: sticker.filled, side: side)
                .overlay {
                    if isSelected && !model.isPlaying {
                        RoundedRectangle(cornerRadius: side * 0.08)
                            .stroke(Color.white, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                            .shadow(color: .black.opacity(0.5), radius: 2)
                    }
                }
                .scaleEffect(CGFloat(st.scale) * pinch)
                .rotationEffect(.degrees(sticker.rotation + st.rotation + twist.degrees))
                .offset(y: CGFloat(st.dy) * side)
                .opacity(st.opacity)

            if isSelected && !model.isPlaying {
                HStack(spacing: 2) {
                    miniButton("pencil") { model.editingStickerID = sticker.id }
                    miniButton("plus.square.on.square") { duplicate() }
                    miniButton("trash") { model.removeSticker(id: sticker.id) }
                }
                .padding(3)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().stroke(Color.white.opacity(0.2)))
                .offset(y: -side * pinch / 2 - 26)
            }
        }
        .position(center)
        .gesture(
            DragGesture(minimumDistance: 2)
                .updating($drag) { value, state, _ in state = value.translation }
                .onEnded { value in
                    model.selectedStickerID = sticker.id
                    model.moveSticker(id: sticker.id, to: CGPoint(
                        x: (sticker.position.x * canvas.width + value.translation.width) / max(1, canvas.width),
                        y: (sticker.position.y * canvas.height + value.translation.height) / max(1, canvas.height)))
                }
        )
        .simultaneousGesture(
            MagnifyGesture()
                .updating($pinch) { value, state, _ in state = value.magnification }
                .onEnded { value in
                    var s = sticker
                    s.size = min(0.9, max(0.05, s.size * Double(value.magnification)))
                    model.update(s)
                }
        )
        .simultaneousGesture(
            RotateGesture()
                .updating($twist) { value, state, _ in state = value.rotation }
                .onEnded { value in
                    var s = sticker
                    s.rotation = (s.rotation + value.rotation.degrees).truncatingRemainder(dividingBy: 360)
                    model.update(s)
                }
        )
        .onTapGesture(count: 2) { model.editingStickerID = sticker.id }
        .onTapGesture {
            model.selectedStickerID = sticker.id
            model.selectedTextID = nil
        }
    }

    private func miniButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func duplicate() {
        var copy = sticker
        copy.id = UUID()
        copy.position = CGPoint(x: min(0.95, sticker.position.x + 0.05), y: min(0.95, sticker.position.y + 0.05))
        model.stickers.append(copy)
        model.selectedStickerID = copy.id
    }
}

// MARK: - Galería de stickers

struct StickerPickerSheet: View {
    @Bindable var model: EditorModel
    @Environment(\.dismiss) private var dismiss

    private enum Tab: Hashable { case emojis, shapes }
    @State private var tab: Tab = .emojis
    @State private var color: TextColor = .yellow
    @State private var filled = true

    var body: some View {
        FXSheet(title: "Stickers", symbol: "face.smiling") {
            FXSegmented(options: [(Tab.emojis, "Emojis", "face.smiling"), (Tab.shapes, "Formas", "star")],
                        selection: $tab)

            if tab == .emojis {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 58), spacing: 10)], spacing: 10) {
                    ForEach(StickerOverlay.emojis, id: \.self) { emoji in
                        cell { add(.emoji(emoji)) } label: {
                            Text(emoji).font(.system(size: 32))
                        }
                    }
                }
            } else {
                FXSectionTitle(text: "Color")
                HStack(spacing: 12) {
                    ForEach(TextColor.allCases) { c in
                        Button {
                            withAnimation(.spring(response: 0.3)) { color = c }
                        } label: {
                            Circle().fill(c.color)
                                .frame(width: 32, height: 32)
                                .overlay(Circle().stroke(Color.white.opacity(0.35)))
                                .overlay(Circle().stroke(color == c ? AnyShapeStyle(FXPalette.gradient) : AnyShapeStyle(Color.clear),
                                                         lineWidth: 3).padding(-4))
                        }
                        .buttonStyle(.plain)
                    }
                }
                // En una fila aparte para que quepa en la pantalla del iPhone.
                FXSegmented(options: [(true, "Relleno", "circle.fill"), (false, "Borde", "circle")],
                            selection: $filled)
                    .frame(maxWidth: 260)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 12)], spacing: 12) {
                    ForEach(StickerShape.allCases) { shape in
                        cell { add(.shape(shape)) } label: {
                            StickerArtwork(content: .shape(shape), color: color, filled: filled, side: 46)
                        }
                    }
                }
            }

            if !model.stickers.isEmpty {
                FXSectionTitle(text: "En tu video", trailing: "\(model.stickers.count)")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(model.stickers) { s in
                            Button {
                                dismiss()
                                model.seek(to: s.start + 0.05)
                                model.selectedStickerID = s.id
                                model.editingStickerID = s.id
                            } label: {
                                VStack(spacing: 4) {
                                    StickerArtwork(content: s.content, color: s.color, filled: s.filled, side: 40)
                                    Text(formatTime(s.start)).font(.caption2.monospacedDigit())
                                        .foregroundStyle(FXPalette.textSecondary)
                                }
                                .padding(8)
                                .background(FXPalette.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        } footer: {
            Text("Toca uno para agregarlo en el cabezal")
                .font(.caption).foregroundStyle(FXPalette.textSecondary)
            Spacer()
            Button("Cerrar") { dismiss() }.buttonStyle(FXSecondaryButtonStyle())
        }
    }

    private func cell<CellLabel: View>(action: @escaping () -> Void, @ViewBuilder label: () -> CellLabel) -> some View {
        Button(action: action) {
            label()
                .frame(maxWidth: .infinity)
                .frame(height: 64)
                .background(FXPalette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(FXPalette.stroke))
                .contentShape(Rectangle())
        }
        .buttonStyle(StickerCellStyle())
    }

    private func add(_ content: StickerContent) {
        var s = model.addSticker(content)
        if content.isShape {
            s.color = color
            s.filled = filled
            model.update(s)
        }
        model.player.pause()
        dismiss()
    }
}

private struct StickerCellStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.88 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

// MARK: - Editar un sticker

struct StickerSheet: View {
    @Bindable var model: EditorModel
    let original: StickerOverlay
    @Environment(\.dismiss) private var dismiss
    @State private var draft: StickerOverlay

    init(model: EditorModel, sticker: StickerOverlay) {
        self.model = model
        self.original = sticker
        _draft = State(initialValue: sticker)
    }

    var body: some View {
        FXSheet(title: "Sticker", symbol: "face.smiling") {
            // Vista previa animada en bucle.
            SwiftUI.TimelineView(.animation) { context in
                let loop = max(0.5, draft.duration)
                let t = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: loop)
                let st = draft.animation.state(at: t, duration: loop)
                StickerArtwork(content: draft.content, color: draft.color, filled: draft.filled, side: 120)
                    .scaleEffect(CGFloat(st.scale))
                    .rotationEffect(.degrees(draft.rotation + st.rotation))
                    .offset(y: CGFloat(st.dy) * 120)
                    .opacity(st.opacity)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 190)
            .background(
                RadialGradient(colors: [FXPalette.accent.opacity(0.35), FXPalette.background], center: .center,
                               startRadius: 10, endRadius: 220),
                in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(FXPalette.stroke))

            FXSectionTitle(text: "Animación", trailing: draft.animation.label)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(StickerAnimation.allCases) { a in animationChip(a) }
                }
                .padding(.vertical, 4)
            }

            FXSectionTitle(text: "Tamaño", trailing: "\(Int(draft.size * 100))%")
            FXSlider(value: $draft.size, range: 0.05...0.9, defaultValue: 0.28)
            FXSectionTitle(text: "Rotación", trailing: "\(Int(draft.rotation))°")
            FXSlider(value: $draft.rotation, range: -180...180, defaultValue: 0)

            if draft.content.isShape {
                FXSectionTitle(text: "Color")
                HStack(spacing: 12) {
                    ForEach(TextColor.allCases) { c in
                        Button {
                            withAnimation(.spring(response: 0.3)) { draft.color = c }
                        } label: {
                            Circle().fill(c.color).frame(width: 30, height: 30)
                                .overlay(Circle().stroke(Color.white.opacity(0.35)))
                                .overlay(Circle().stroke(draft.color == c ? AnyShapeStyle(FXPalette.gradient) : AnyShapeStyle(Color.clear),
                                                         lineWidth: 3).padding(-4))
                        }
                        .buttonStyle(.plain)
                    }
                }
                // En una fila aparte para que quepa en la pantalla del iPhone.
                FXSegmented(options: [(true, "Relleno", "circle.fill"), (false, "Borde", "circle")],
                            selection: $draft.filled)
                    .frame(maxWidth: 260)
            }

            FXCard {
                HStack {
                    Label("Aparece en \(formatTime(draft.start))", systemImage: "clock")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Button("Usar cabezal") { draft.start = model.currentTime }
                        .buttonStyle(FXSecondaryButtonStyle())
                }
                FXSlider(value: $draft.start, range: 0...max(0.1, model.duration), defaultValue: 0)
                Text("Dura \(String(format: "%.1f", draft.duration)) s")
                    .font(.subheadline.weight(.semibold))
                FXSlider(value: $draft.duration, range: 0.5...max(0.5, model.duration), defaultValue: 3)
            }
        } footer: {
            Button(role: .destructive) {
                model.removeSticker(id: original.id)
                dismiss()
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(FXSecondaryButtonStyle())
            Spacer()
            Button("Cancelar") { dismiss() }.buttonStyle(FXSecondaryButtonStyle())
            Button("Guardar") {
                model.update(draft)
                model.selectedStickerID = draft.id
                model.seek(to: draft.start + 0.05)
                dismiss()
            }
            .buttonStyle(FXPrimaryButtonStyle())
            .keyboardShortcut(.defaultAction)
        }
    }

    private func animationChip(_ a: StickerAnimation) -> some View {
        let selected = draft.animation == a
        return Button {
            withAnimation(.spring(response: 0.3)) { draft.animation = a }
        } label: {
            VStack(spacing: 6) {
                // Cada opción se anima a sí misma con una estrella pequeña.
                SwiftUI.TimelineView(.animation) { context in
                    let t = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 2.4)
                    let st = a.state(at: t, duration: 2.4)
                    StickerPath(shape: .star)
                        .fill(selected ? Color.white : FXPalette.amber)
                        .frame(width: 22, height: 22)
                        .scaleEffect(CGFloat(st.scale))
                        .rotationEffect(.degrees(st.rotation))
                        .offset(y: CGFloat(st.dy) * 22)
                        .opacity(max(0.25, st.opacity))
                }
                .frame(width: 40, height: 40)
                Text(a.label).font(.caption2.weight(selected ? .bold : .medium))
            }
            .frame(width: 74, height: 76)
            .background(selected ? AnyShapeStyle(FXPalette.gradient) : AnyShapeStyle(FXPalette.surface),
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(FXPalette.stroke))
        }
        .buttonStyle(.plain)
    }
}
