import SwiftUI
import CoreGraphics
import CoreImage

// MARK: - Estilo de las hojas de efectos

/// Colores de las hojas de efectos (los mismos tonos del tema de la app: violeta y coral).
enum FXPalette {
    static let background = Color(red: 0.06, green: 0.05, blue: 0.09)
    static let surface = Color.white.opacity(0.06)
    static let surfaceRaised = Color.white.opacity(0.11)
    static let stroke = Color.white.opacity(0.12)
    static let textSecondary = Color.white.opacity(0.6)
    static let accent = Color(red: 0.486, green: 0.361, blue: 1)       // #7C5CFF
    static let accent2 = Color(red: 1, green: 0.42, blue: 0.545)       // #FF6B8B
    static let amber = Color(red: 1, green: 0.74, blue: 0.27)
    static let gradient = LinearGradient(colors: [accent, accent2], startPoint: .topLeading, endPoint: .bottomTrailing)
}

/// Contenedor común: encabezado con ícono, contenido desplazable y barra de acciones abajo.
struct FXSheet<Content: View, Footer: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder var content: () -> Content
    @ViewBuilder var footer: () -> Footer

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(FXPalette.gradient, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                Text(title).font(.title3.weight(.bold))
                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)
            .padding(.bottom, 10)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    content()
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 18)
            }

            HStack(spacing: 10) { footer() }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(.ultraThinMaterial)
        }
        .background(FXPalette.background.ignoresSafeArea())
        .foregroundStyle(.white)
        .tint(FXPalette.accent)
        .preferredColorScheme(.dark)
        #if os(macOS)
        .frame(minWidth: 540, idealWidth: 580, minHeight: 600, idealHeight: 680)
        #else
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        #endif
    }
}

struct FXPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 11)
            .background(FXPalette.gradient, in: Capsule())
            .shadow(color: FXPalette.accent.opacity(0.45), radius: configuration.isPressed ? 2 : 10, y: 4)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

struct FXSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .background(FXPalette.surfaceRaised, in: Capsule())
            .overlay(Capsule().stroke(FXPalette.stroke))
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
    }
}

/// Título pequeño de sección.
struct FXSectionTitle: View {
    let text: String
    var trailing: String?

    var body: some View {
        HStack {
            Text(text.uppercased())
                .font(.caption.weight(.bold))
                .tracking(1.1)
                .foregroundStyle(FXPalette.textSecondary)
            Spacer()
            if let trailing {
                Text(trailing).font(.caption.monospacedDigit()).foregroundStyle(FXPalette.textSecondary)
            }
        }
    }
}

/// Tarjeta de fondo translúcido.
struct FXCard<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) { content() }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(FXPalette.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(FXPalette.stroke))
    }
}

/// Control de pestañas en forma de cápsula con el indicador deslizándose.
struct FXSegmented<Value: Hashable>: View {
    let options: [(Value, String, String)]
    @Binding var selection: Value
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options, id: \.0) { option in
                let selected = option.0 == selection
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { selection = option.0 }
                } label: {
                    Label(option.1, systemImage: option.2)
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .foregroundStyle(selected ? .white : FXPalette.textSecondary)
                        .background {
                            if selected {
                                Capsule().fill(FXPalette.gradient).matchedGeometryEffect(id: "pill", in: ns)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(FXPalette.surface, in: Capsule())
        .overlay(Capsule().stroke(FXPalette.stroke))
    }
}

/// Deslizador propio: pista con relleno degradado (desde el centro si el rango cruza el cero) y
/// doble toque para volver al valor por defecto.
struct FXSlider: View {
    @Binding var value: Double
    var range: ClosedRange<Double>
    var defaultValue: Double = 0
    var onEditingEnded: () -> Void = {}

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let span = range.upperBound - range.lowerBound
            let fraction = span > 0 ? (min(max(value, range.lowerBound), range.upperBound) - range.lowerBound) / span : 0
            let origin = span > 0 ? (min(max(defaultValue, range.lowerBound), range.upperBound) - range.lowerBound) / span : 0
            let x = CGFloat(fraction) * w
            let ox = CGFloat(origin) * w
            ZStack(alignment: .leading) {
                Capsule().fill(FXPalette.surfaceRaised).frame(height: 6)
                Capsule().fill(FXPalette.gradient)
                    .frame(width: abs(x - ox), height: 6)
                    .offset(x: min(x, ox))
                if origin > 0.001 && origin < 0.999 {
                    Capsule().fill(Color.white.opacity(0.5)).frame(width: 2, height: 12).offset(x: ox - 1)
                }
                Circle()
                    .fill(.white)
                    .frame(width: 24, height: 24)
                    .shadow(color: .black.opacity(0.35), radius: 4, y: 2)
                    .overlay(Circle().fill(FXPalette.gradient).frame(width: 8, height: 8))
                    .offset(x: x - 12)
            }
            .frame(height: 28)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        let f = min(max(0, g.location.x / max(1, w)), 1)
                        var v = range.lowerBound + Double(f) * span
                        // Se "pega" al valor por defecto al pasar cerca.
                        if abs(v - defaultValue) < span * 0.02 { v = defaultValue }
                        value = v
                    }
                    .onEnded { _ in onEditingEnded() }
            )
            .onTapGesture(count: 2) {
                withAnimation(.spring(response: 0.3)) { value = defaultValue }
                onEditingEnded()
            }
        }
        .frame(height: 28)
    }
}

/// Imagen de vista previa con esquinas redondeadas y botón "mantén para comparar".
struct FXPreviewImage: View {
    let image: CGImage?
    var aspect: CGFloat?
    var height: CGFloat = 250
    var onCompare: ((Bool) -> Void)?
    @State private var comparing = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.black)
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .padding(8)
                    .transition(.opacity)
            } else {
                ProgressView().tint(.white)
            }
        }
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(FXPalette.stroke))
        .overlay(alignment: .topTrailing) {
            if let onCompare {
                Label(comparing ? "Original" : "Mantén para comparar", systemImage: "square.split.2x1")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(12)
                    .onLongPressGesture(minimumDuration: 0, maximumDistance: 40, perform: {}, onPressingChanged: { pressing in
                        comparing = pressing
                        onCompare(pressing)
                    })
            }
        }
    }
}

// MARK: - Color (filtros + ajustes)

struct ColorSheet: View {
    @Bindable var model: EditorModel
    @Environment(\.dismiss) private var dismiss

    private enum Tab: Hashable { case filters, adjust }

    @State private var draft = ColorLook()
    @State private var base: CGImage?
    @State private var thumbs: [VideoFilter: CGImage] = [:]
    @State private var tab: Tab = .filters
    @State private var adjustment: ColorAdjustment = .brightness
    @State private var applyToAll = false
    @State private var comparing = false

    private var clip: Clip? { model.selectedClip ?? model.clips.first }

    private var rendered: CGImage? {
        guard let base else { return nil }
        return comparing ? base : FrameRenderer.preview(base, look: draft)
    }

    var body: some View {
        FXSheet(title: "Color", symbol: "camera.filters") {
            FXPreviewImage(image: rendered, onCompare: { comparing = $0 })

            FXSegmented(options: [(Tab.filters, "Filtros", "sparkles"), (Tab.adjust, "Ajustes", "slider.horizontal.3")],
                        selection: $tab)

            if tab == .filters {
                filters
            } else {
                adjustments
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
                model.setLook(draft, applyToAll: applyToAll)
                dismiss()
            }
            .buttonStyle(FXPrimaryButtonStyle())
            .keyboardShortcut(.defaultAction)
        }
        .task { await loadFrames() }
        .onAppear {
            if model.selectedClipID == nil { model.selectedClipID = model.clips.first?.id }
            draft = clip?.look ?? ColorLook()
            tab = draft.preset == .none && !draft.isIdentity ? .adjust : .filters
        }
    }

    // Filtros con miniaturas del propio video.
    private var filters: some View {
        VStack(alignment: .leading, spacing: 14) {
            FXSectionTitle(text: "Filtros", trailing: draft.preset == .none ? nil : draft.preset.label)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(VideoFilter.allCases) { f in
                        presetCell(f)
                    }
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 2)
            }
            if draft.preset != .none {
                FXSectionTitle(text: "Intensidad", trailing: "\(Int(draft.intensity * 100))%")
                FXSlider(value: $draft.intensity, range: 0...1, defaultValue: 1)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: draft.preset)
    }

    private func presetCell(_ f: VideoFilter) -> some View {
        let selected = draft.preset == f
        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                if draft.preset != f { draft.intensity = 1 }
                draft.preset = f
            }
        } label: {
            VStack(spacing: 7) {
                ZStack {
                    if let image = thumbs[f] {
                        Image(decorative: image, scale: 1).resizable().aspectRatio(contentMode: .fill)
                    } else {
                        FXPalette.surfaceRaised
                    }
                    if f == .none {
                        Image(systemName: "circle.slash").font(.title3).foregroundStyle(.white.opacity(0.9))
                            .shadow(radius: 3)
                    }
                }
                .frame(width: 72, height: 92)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(selected ? AnyShapeStyle(FXPalette.gradient) : AnyShapeStyle(FXPalette.stroke),
                                      lineWidth: selected ? 3 : 1)
                }
                .scaleEffect(selected ? 1.06 : 1)
                .shadow(color: selected ? FXPalette.accent.opacity(0.5) : .clear, radius: 8)

                Text(f.label)
                    .font(.caption2.weight(selected ? .bold : .medium))
                    .foregroundStyle(selected ? .white : FXPalette.textSecondary)
                    .lineLimit(1)
            }
            .frame(width: 78)
        }
        .buttonStyle(.plain)
    }

    // Ajustes manuales: una fila de diales y un deslizador para el elegido.
    private var adjustments: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                FXSectionTitle(text: "Ajustes")
                Button {
                    withAnimation { resetAdjustments() }
                } label: {
                    Label("Restablecer", systemImage: "arrow.counterclockwise").font(.caption.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(FXPalette.accent2)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(ColorAdjustment.allCases) { a in
                        adjustmentDial(a)
                    }
                }
                .padding(.vertical, 4)
            }
            let value = draft[keyPath: adjustment.keyPath]
            FXSectionTitle(text: adjustment.label, trailing: (value > 0.005 && adjustment.isBipolar ? "+" : "") + "\(Int((value * 100).rounded()))")
            let keyPath = adjustment.keyPath
            FXSlider(value: Binding(get: { draft[keyPath: keyPath] }, set: { draft[keyPath: keyPath] = $0 }),
                     range: adjustment.isBipolar ? -1...1 : 0...1, defaultValue: 0)
        }
    }

    private func adjustmentDial(_ a: ColorAdjustment) -> some View {
        let selected = a == adjustment
        let value = draft[keyPath: a.keyPath]
        return Button {
            withAnimation(.spring(response: 0.3)) { adjustment = a }
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    Circle().fill(selected ? AnyShapeStyle(FXPalette.gradient) : AnyShapeStyle(FXPalette.surfaceRaised))
                    // Anillo que muestra cuánto se movió el ajuste.
                    Circle()
                        .trim(from: 0, to: CGFloat(min(1, abs(value))))
                        .stroke(selected ? Color.white : FXPalette.accent2, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .padding(2)
                    Image(systemName: a.symbol).font(.system(size: 18, weight: .semibold))
                }
                .frame(width: 54, height: 54)
                Text(a.label)
                    .font(.caption2.weight(selected ? .bold : .medium))
                    .foregroundStyle(selected ? .white : FXPalette.textSecondary)
            }
            .frame(width: 70)
        }
        .buttonStyle(.plain)
    }

    private func resetAdjustments() {
        for a in ColorAdjustment.allCases { draft[keyPath: a.keyPath] = 0 }
    }

    private func loadFrames() async {
        guard let clip else { return }
        let local = model.previewLocalTime(for: clip)
        base = try? await Thumbnails.frame(of: clip, atLocal: local, maxSide: 640)
        guard let small = try? await Thumbnails.frame(of: clip, atLocal: local, maxSide: 200) else { return }
        var result: [VideoFilter: CGImage] = [:]
        for f in VideoFilter.allCases {
            var look = ColorLook()
            look.preset = f
            result[f] = FrameRenderer.preview(small, look: look)
        }
        thumbs = result
    }
}

// MARK: - Velocidad, reversa y congelar

struct SpeedSheet: View {
    @Bindable var model: EditorModel
    @Environment(\.dismiss) private var dismiss

    /// Velocidad en escala logarítmica: -2 = 0.25×, 0 = 1×, 2 = 4×.
    @State private var logSpeed: Double = 0
    @State private var reversed = false
    @State private var freezeSeconds: Double = 2

    private let presets: [(Double, String)] = [(0.25, "🐢"), (0.5, ""), (1, ""), (1.5, ""), (2, ""), (4, "⚡️")]

    private var speed: Double { (pow(2, logSpeed) * 100).rounded() / 100 }
    private var clip: Clip? { model.selectedClip }

    private var mood: String {
        switch speed {
        case ..<0.99: return "Cámara lenta"
        case 1.01...: return "Acelerado"
        default: return "Velocidad normal"
        }
    }

    var body: some View {
        FXSheet(title: "Velocidad", symbol: "speedometer") {
            if let clip {
                filmStrip(clip)

                VStack(spacing: 4) {
                    Text(String(format: speed < 1 ? "%.2g×" : "%.3g×", speed))
                        .font(.system(size: 54, weight: .heavy, design: .rounded))
                        .foregroundStyle(FXPalette.gradient)
                        .contentTransition(.numericText())
                        .animation(.snappy, value: speed)
                    Text(mood).font(.subheadline.weight(.semibold)).foregroundStyle(FXPalette.textSecondary)
                    let before = clip.sourceDuration.seconds
                    Text("Duración: \(String(format: "%.1f", before)) s → \(String(format: "%.1f", before / speed)) s")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(FXPalette.textSecondary)
                }
                .frame(maxWidth: .infinity)

                VStack(spacing: 8) {
                    FXSlider(value: $logSpeed, range: -2...2, defaultValue: 0)
                    HStack {
                        ForEach(["0.25×", "0.5×", "1×", "2×", "4×"], id: \.self) { label in
                            Text(label).font(.caption2.monospacedDigit()).foregroundStyle(FXPalette.textSecondary)
                            if label != "4×" { Spacer() }
                        }
                    }
                }

                HStack(spacing: 8) {
                    ForEach(presets, id: \.0) { preset in
                        let selected = abs(speed - preset.0) < 0.01
                        Button {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) { logSpeed = log2(preset.0) }
                        } label: {
                            Text("\(preset.1)\(preset.0 == 0.25 ? "0.25" : String(format: "%g", preset.0))×")
                                .font(.footnote.weight(.bold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 9)
                                .background(selected ? AnyShapeStyle(FXPalette.gradient) : AnyShapeStyle(FXPalette.surfaceRaised),
                                            in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }

                FXCard {
                    Toggle(isOn: $reversed) {
                        HStack(spacing: 12) {
                            iconBadge("backward.fill")
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Reversa").font(.headline)
                                Text("Reproduce el clip al revés. El sonido del clip se silencia.")
                                    .font(.caption).foregroundStyle(FXPalette.textSecondary)
                            }
                        }
                    }
                    .toggleStyle(.switch)
                    if reversed && clip.reversedURL == nil {
                        Text("La primera vez tarda unos segundos en preparar el clip invertido.")
                            .font(.caption2).foregroundStyle(FXPalette.amber)
                    }
                }

                FXCard {
                    HStack(spacing: 12) {
                        iconBadge("snowflake")
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Congelar fotograma").font(.headline)
                            Text("Detiene la imagen en el cuadro donde está el cabezal.")
                                .font(.caption).foregroundStyle(FXPalette.textSecondary)
                        }
                    }
                    HStack(spacing: 8) {
                        ForEach([1.0, 2, 3, 5], id: \.self) { s in
                            Button {
                                withAnimation(.snappy) { freezeSeconds = s }
                            } label: {
                                Text("\(Int(s)) s")
                                    .font(.footnote.weight(.bold))
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .background(freezeSeconds == s ? AnyShapeStyle(FXPalette.gradient) : AnyShapeStyle(FXPalette.surfaceRaised),
                                                in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                        Spacer()
                        Button {
                            let seconds = freezeSeconds
                            dismiss()
                            Task { await model.freezeFrame(seconds: seconds) }
                        } label: {
                            Label("Congelar", systemImage: "camera.metering.center.weighted")
                        }
                        .buttonStyle(FXPrimaryButtonStyle())
                    }
                }
            } else {
                Text("Selecciona un clip en la línea de tiempo.").foregroundStyle(FXPalette.textSecondary)
            }
        } footer: {
            Button {
                withAnimation { logSpeed = 0; reversed = false }
            } label: {
                Label("Restablecer", systemImage: "arrow.counterclockwise")
            }
            .buttonStyle(FXSecondaryButtonStyle())
            Spacer()
            Button("Cancelar") { dismiss() }.buttonStyle(FXSecondaryButtonStyle())
            Button("Aplicar") {
                let newSpeed = speed, newReversed = reversed
                let changedReverse = newReversed != (clip?.isReversed ?? false)
                model.setSpeed(newSpeed)
                dismiss()
                if changedReverse {
                    Task { await model.setReversed(newReversed) }
                }
            }
            .buttonStyle(FXPrimaryButtonStyle())
            .keyboardShortcut(.defaultAction)
            .disabled(clip == nil)
        }
        .onAppear {
            if let clip {
                logSpeed = log2(clip.speed)
                reversed = clip.isReversed
            }
        }
    }

    private func iconBadge(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 15, weight: .bold))
            .frame(width: 36, height: 36)
            .background(FXPalette.surfaceRaised, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    /// Tira de miniaturas del clip que se desplaza a la velocidad elegida (y al revés si hay reversa).
    private func filmStrip(_ clip: Clip) -> some View {
        let cell: CGFloat = 54
        let frames = clip.thumbnails
        let count = max(1, frames.count)
        let loop = cell * CGFloat(count)
        return SwiftUI.TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let travel = CGFloat((t * 40 * speed).truncatingRemainder(dividingBy: Double(loop)))
            let offset = reversed ? travel - loop : -travel
            HStack(spacing: 0) {
                ForEach(0..<(count * 3), id: \.self) { i in
                    Group {
                        if frames.isEmpty {
                            FXPalette.surfaceRaised
                        } else {
                            Image(decorative: frames[i % count], scale: 1).resizable().aspectRatio(contentMode: .fill)
                        }
                    }
                    .frame(width: cell, height: 70)
                    .clipped()
                    .overlay(Rectangle().stroke(Color.black.opacity(0.6), lineWidth: 1))
                }
            }
            .offset(x: offset)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: 70)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(FXPalette.stroke))
        .overlay {
            // Bordes que se desvanecen para dar sensación de movimiento continuo.
            LinearGradient(colors: [FXPalette.background, .clear, .clear, FXPalette.background],
                           startPoint: .leading, endPoint: .trailing)
                .allowsHitTesting(false)
        }
    }
}

// MARK: - Formato (relación de aspecto, encuadre y fondo)

struct CanvasSheet: View {
    @Bindable var model: EditorModel
    @Environment(\.dismiss) private var dismiss

    @State private var aspect: CanvasAspect = .original
    @State private var background: CanvasBackground = .blur
    @State private var framing = ClipFraming()
    @State private var applyToAll = false
    @State private var base: CGImage?
    @State private var blurSwatch: CGImage?
    @GestureState private var dragTranslation: CGSize = .zero
    @GestureState private var pinch: CGFloat = 1

    private var clip: Clip? { model.selectedClip ?? model.clips.first }

    /// Proporción del lienzo con la relación elegida.
    private var canvasRatio: CGFloat {
        let size = CompositionBuilder.renderSize(for: model.clips, aspect: aspect)
        return size.height > 0 ? size.width / size.height : 16 / 9
    }

    private var previewSize: CGSize {
        let long: CGFloat = 640
        return canvasRatio >= 1 ? CGSize(width: long, height: (long / canvasRatio).rounded())
                                : CGSize(width: (long * canvasRatio).rounded(), height: long)
    }

    /// Encuadre con el gesto en curso aplicado (para que la vista previa siga al dedo).
    private func liveFraming(viewSize: CGSize) -> ClipFraming {
        var f = framing
        if viewSize.width > 0, viewSize.height > 0 {
            f.offset.x = clampOffset(f.offset.x + dragTranslation.width / viewSize.width)
            f.offset.y = clampOffset(f.offset.y + dragTranslation.height / viewSize.height)
        }
        f.zoom = min(3, max(0.5, f.zoom * Double(pinch)))
        return f
    }

    var body: some View {
        FXSheet(title: "Formato", symbol: "aspectratio") {
            canvasPreview

            FXSectionTitle(text: "Relación de aspecto")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(CanvasAspect.allCases) { a in aspectChip(a) }
                }
                .padding(.vertical, 4)
            }

            FXSectionTitle(text: "Encuadre del clip", trailing: String(format: "Zoom %.1f×", framing.zoom))
            HStack(spacing: 10) {
                ForEach(FitMode.allCases) { mode in
                    let selected = framing.mode == mode
                    Button {
                        withAnimation(.spring(response: 0.35)) {
                            framing.mode = mode
                            framing.offset = .zero
                        }
                    } label: {
                        Label(mode.label, systemImage: mode.symbol)
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(selected ? AnyShapeStyle(FXPalette.gradient) : AnyShapeStyle(FXPalette.surfaceRaised),
                                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                Button {
                    withAnimation(.spring(response: 0.35)) { framing.mirrored.toggle() }
                } label: {
                    Image(systemName: "arrow.left.and.right.righttriangle.left.righttriangle.right")
                        .font(.subheadline.weight(.semibold))
                        .frame(width: 46)
                        .padding(.vertical, 10)
                        .background(framing.mirrored ? AnyShapeStyle(FXPalette.gradient) : AnyShapeStyle(FXPalette.surfaceRaised),
                                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .help("Espejo")
                Button {
                    withAnimation(.spring(response: 0.35)) { framing.offset = .zero; framing.zoom = 1 }
                } label: {
                    Image(systemName: "scope")
                        .font(.subheadline.weight(.semibold))
                        .frame(width: 46)
                        .padding(.vertical, 10)
                        .background(FXPalette.surfaceRaised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .help("Centrar")
            }
            FXSlider(value: $framing.zoom, range: 0.5...3, defaultValue: 1)

            FXSectionTitle(text: "Fondo")
            HStack(spacing: 12) {
                ForEach(CanvasBackground.allCases) { b in backgroundSwatch(b) }
            }
            if framing.mode == .fill && framing.zoom >= 1 && framing.offset == .zero {
                Text("Con «Llenar» el video cubre todo el lienzo, así que el fondo no se ve.")
                    .font(.caption).foregroundStyle(FXPalette.textSecondary)
            }
        } footer: {
            Toggle(isOn: $applyToAll) {
                Text("Encuadre a todos").font(.footnote.weight(.semibold))
            }
            .toggleStyle(.switch)
            .fixedSize()
            Spacer()
            Button("Cancelar") { dismiss() }.buttonStyle(FXSecondaryButtonStyle())
            Button("Aplicar") {
                model.setFraming(framing, applyToAll: applyToAll)
                model.setCanvas(aspect: aspect, background: background)
                dismiss()
            }
            .buttonStyle(FXPrimaryButtonStyle())
            .keyboardShortcut(.defaultAction)
        }
        .onAppear {
            if model.selectedClipID == nil { model.selectedClipID = model.clips.first?.id }
            aspect = model.aspect
            background = model.canvasBackground
            framing = clip?.framing ?? ClipFraming()
        }
        .task { await loadFrame() }
    }

    private var canvasPreview: some View {
        GeometryReader { geo in
            let maxW = geo.size.width - 16, maxH = geo.size.height - 16
            let w = min(maxW, maxH * canvasRatio)
            let h = w / canvasRatio
            let viewSize = CGSize(width: w, height: h)
            ZStack {
                if let base, let clip,
                   let image = FrameRenderer.preview(base, look: clip.look, framing: liveFraming(viewSize: viewSize),
                                                     canvas: background, renderSize: previewSize) {
                    Image(decorative: image, scale: 1).resizable()
                } else {
                    Color.black
                    ProgressView().tint(.white)
                }
                // Cuadrícula de tercios mientras se arrastra.
                if dragTranslation != .zero || pinch != 1 {
                    ThirdsGrid().stroke(Color.white.opacity(0.45), lineWidth: 1)
                }
            }
            .frame(width: w, height: h)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(FXPalette.gradient, lineWidth: 2))
            .shadow(color: FXPalette.accent.opacity(0.35), radius: 14)
            .contentShape(Rectangle())
            .gesture(
                DragGesture()
                    .updating($dragTranslation) { value, state, _ in state = value.translation }
                    .onEnded { value in
                        framing.offset.x = clampOffset(framing.offset.x + value.translation.width / w)
                        framing.offset.y = clampOffset(framing.offset.y + value.translation.height / h)
                    }
            )
            .simultaneousGesture(
                MagnifyGesture()
                    .updating($pinch) { value, state, _ in state = value.magnification }
                    .onEnded { value in framing.zoom = min(3, max(0.5, framing.zoom * Double(value.magnification))) }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: aspect)
        }
        .frame(height: 300)
        .overlay(alignment: .bottom) {
            Text("Arrastra para mover · pellizca para acercar")
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(.bottom, 14)
        }
    }

    private func aspectChip(_ a: CanvasAspect) -> some View {
        let selected = a == aspect
        let ratio = a.ratio ?? (model.clips.first.map { $0.displaySize.width / max(1, $0.displaySize.height) } ?? 16 / 9)
        let box: CGFloat = 30
        let w = ratio >= 1 ? box : box * ratio
        let h = ratio >= 1 ? box / ratio : box
        return Button {
            withAnimation(.spring(response: 0.35)) { aspect = a }
        } label: {
            VStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(selected ? Color.white : FXPalette.textSecondary, lineWidth: 2)
                    .frame(width: w, height: h)
                    .frame(width: box, height: box)
                Text(a.label).font(.footnote.weight(.bold))
                Text(a.subtitle).font(.system(size: 9, weight: .medium)).foregroundStyle(selected ? .white.opacity(0.85) : FXPalette.textSecondary)
            }
            .frame(width: 84, height: 92)
            .background(selected ? AnyShapeStyle(FXPalette.gradient) : AnyShapeStyle(FXPalette.surface),
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(FXPalette.stroke))
        }
        .buttonStyle(.plain)
    }

    private func backgroundSwatch(_ b: CanvasBackground) -> some View {
        let selected = b == background
        return Button {
            withAnimation(.spring(response: 0.3)) { background = b }
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    if b == .blur {
                        if let blurSwatch {
                            Image(decorative: blurSwatch, scale: 1).resizable().aspectRatio(contentMode: .fill)
                        } else {
                            FXPalette.gradient.blur(radius: 6)
                        }
                        Image(systemName: "drop.halffull").font(.caption.weight(.bold)).shadow(radius: 2)
                    } else {
                        b.color
                    }
                }
                .frame(width: 42, height: 42)
                .clipShape(Circle())
                .overlay(Circle().stroke(selected ? AnyShapeStyle(FXPalette.gradient) : AnyShapeStyle(FXPalette.stroke),
                                         lineWidth: selected ? 3 : 1).padding(-3))
                Text(b.label).font(.system(size: 9, weight: .medium))
                    .foregroundStyle(selected ? .white : FXPalette.textSecondary)
            }
        }
        .buttonStyle(.plain)
    }

    private func clampOffset(_ v: CGFloat) -> CGFloat { min(max(v, -1), 1) }

    private func loadFrame() async {
        guard let clip else { return }
        base = try? await Thumbnails.frame(of: clip, atLocal: model.previewLocalTime(for: clip), maxSide: 720)
        if let base {
            let swatch = CGSize(width: 84, height: 84)
            let input = CIImage(cgImage: base)
            let blurred = FrameRenderer.background(for: input, canvas: .blur, rect: CGRect(origin: .zero, size: swatch))
            blurSwatch = FrameRenderer.previewContext.createCGImage(blurred, from: CGRect(origin: .zero, size: swatch))
        }
    }
}

private struct ThirdsGrid: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        for i in 1...2 {
            let x = rect.width * CGFloat(i) / 3, y = rect.height * CGFloat(i) / 3
            p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: rect.height))
            p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: rect.width, y: y))
        }
        return p
    }
}
