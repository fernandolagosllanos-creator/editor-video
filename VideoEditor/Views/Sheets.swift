import SwiftUI

// MARK: - Recortar

struct TrimSheet: View {
    @Bindable var model: EditorModel
    @Environment(\.dismiss) private var dismiss
    @State private var start: Double = 0
    @State private var end: Double = 1
    @State private var total: Double = 1

    var body: some View {
        SheetContainer(title: "Recortar clip") {
            VStack(alignment: .leading, spacing: 18) {
                LabeledContent("Inicio", value: formatTime(start))
                Slider(value: $start, in: 0...max(0.1, total))
                    .onChange(of: start) { _, v in if v > end - 0.1 { end = min(total, v + 0.1) } }
                LabeledContent("Fin", value: formatTime(end))
                Slider(value: $end, in: 0...max(0.1, total))
                    .onChange(of: end) { _, v in if v < start + 0.1 { start = max(0, v - 0.1) } }
                LabeledContent("Duración resultante", value: formatTime(max(0, end - start)))
                    .foregroundStyle(.secondary)
            }
        } actions: {
            Button("Cancelar") { dismiss() }
            Button("Aplicar") {
                model.trimSelectedClip(start: start, end: end)
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
        }
        .onAppear {
            if let clip = model.selectedClip {
                total = clip.assetDuration.seconds
                start = clip.start.seconds
                end = clip.end.seconds
            }
        }
    }
}

// La hoja de transiciones está en TransitionSheet.swift.

// MARK: - Texto

struct TextSheet: View {
    @Bindable var model: EditorModel
    let original: TextOverlay
    @Environment(\.dismiss) private var dismiss
    @State private var draft: TextOverlay

    init(model: EditorModel, text: TextOverlay) {
        self.model = model
        self.original = text
        _draft = State(initialValue: text)
    }

    var body: some View {
        SheetContainer(title: "Texto") {
            VStack(alignment: .leading, spacing: 16) {
                TextField("Escribe el texto", text: $draft.text, axis: .vertical)
                    .lineLimit(1...4)
                    .textFieldStyle(.roundedBorder)

                LabeledContent("Aparece en", value: formatTime(draft.start))
                HStack {
                    Slider(value: $draft.start, in: 0...max(0.1, model.duration))
                    Button("Usar cabezal") { draft.start = model.currentTime }
                        .buttonStyle(.bordered)
                }
                LabeledContent("Duración", value: String(format: "%.1f s", draft.duration))
                Slider(value: $draft.duration, in: 0.5...max(0.5, model.duration))

                LabeledContent("Tamaño", value: "\(Int(draft.fontSize * 100))%")
                Slider(value: $draft.fontSize, in: 0.03...0.25)

                Picker("Color", selection: $draft.color) {
                    ForEach(TextColor.allCases) { c in
                        HStack {
                            Circle().fill(c.color).frame(width: 12, height: 12)
                            Text(c.label)
                        }
                        .tag(c)
                    }
                }
                #if os(iOS)
                .pickerStyle(.navigationLink)
                #endif

                Text("Tip: arrastra el texto sobre la vista previa para ubicarlo.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        } actions: {
            Button("Eliminar", role: .destructive) {
                model.removeText(id: original.id)
                dismiss()
            }
            Spacer()
            Button("Cancelar") { dismiss() }
            Button("Guardar") {
                model.update(draft)
                model.seek(to: draft.start + 0.05)
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
            .disabled(draft.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }
}

// MARK: - Audio
// La hoja de audio está en AudioSheet.swift.

// MARK: - Exportar

struct ExportSheet: View {
    @Bindable var model: EditorModel
    @Environment(\.dismiss) private var dismiss

    private var originalSize: CGSize { model.canvasSize }

    var body: some View {
        SheetContainer(title: "Exportar video") {
            VStack(alignment: .leading, spacing: 16) {
                if model.isExporting {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Exportando… \(Int(model.exportProgress * 100))%")
                        ProgressView(value: model.exportProgress)
                    }
                } else if let url = model.exportedURL {
                    ShareResultView(model: model, url: url)
                } else {
                    Picker("Formato", selection: $model.exportSettings.container) {
                        ForEach(ExportContainer.allCases) { Text($0.label).tag($0) }
                    }
                    Picker("Códec", selection: $model.exportSettings.codec) {
                        ForEach(ExportCodec.allCases) { Text($0.label).tag($0) }
                    }
                    Picker("Resolución", selection: $model.exportSettings.resolution) {
                        ForEach(ExportResolution.allCases) { r in
                            Text(r == .original ? "Original (\(Int(originalSize.width))×\(Int(originalSize.height)))" : r.label).tag(r)
                        }
                    }
                    Picker("Calidad", selection: $model.exportSettings.quality) {
                        ForEach(ExportQuality.allCases) { Text($0.label).tag($0) }
                    }
                    let out = model.exportSettings.outputSize(from: originalSize)
                    Text("Salida: \(Int(out.width))×\(Int(out.height)) · \(model.exportSettings.container.label) · \(model.exportSettings.codec == .hevc ? "HEVC" : "H.264")")
                        .font(.footnote).foregroundStyle(.secondary)
                    if model.exportSettings.resolution.shortSide ?? 0 > min(originalSize.width, originalSize.height) {
                        Text("La resolución elegida es mayor que la original: el video se escalará, pero no ganará nitidez.")
                            .font(.footnote).foregroundStyle(.orange)
                    }
                }
            }
        } actions: {
            Spacer()
            if model.isExporting {
                ProgressView().controlSize(.small)
            } else if model.exportedURL != nil {
                Button("Exportar otro") { model.exportedURL = nil }
                Button("Cerrar") { dismiss() }.keyboardShortcut(.defaultAction)
            } else {
                Button("Cancelar") { dismiss() }
                Button("Exportar") { Task { await model.export() } }.keyboardShortcut(.defaultAction)
            }
        }
        .interactiveDismissDisabled(model.isExporting)
    }
}

// MARK: - Contenedor común de hojas

struct SheetContainer<Content: View, Actions: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        #if os(macOS)
        VStack(alignment: .leading, spacing: 16) {
            Text(title).font(.title2.bold())
            ScrollView { content().frame(maxWidth: .infinity, alignment: .leading) }
            HStack { actions() }
        }
        .padding(20)
        .frame(minWidth: 420, idealWidth: 460, minHeight: 300)
        #else
        NavigationStack {
            Form {
                content()
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                HStack { actions() }
                    .padding()
                    .background(.bar)
            }
        }
        #endif
    }
}
