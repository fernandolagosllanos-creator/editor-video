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

// MARK: - Transición

struct TransitionSheet: View {
    @Bindable var model: EditorModel
    @Environment(\.dismiss) private var dismiss
    @State private var type: TransitionType = .crossfade
    @State private var seconds: Double = 0.6

    var body: some View {
        SheetContainer(title: "Transición al siguiente clip") {
            VStack(alignment: .leading, spacing: 18) {
                Picker("Tipo", selection: $type) {
                    ForEach(TransitionType.allCases) { t in
                        Label(t.label, systemImage: t.symbol).tag(t)
                    }
                }
                #if os(iOS)
                .pickerStyle(.navigationLink)
                #endif
                LabeledContent("Duración", value: String(format: "%.1f s", seconds))
                Slider(value: $seconds, in: 0.2...2.0, step: 0.1)
                    .disabled(type == .none)
                if model.selectedClipIndex == (model.clips.count - 1) {
                    Text("Este es el último clip: la transición se aplicará cuando agregues otro después.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
        } actions: {
            Button("Cancelar") { dismiss() }
            Button("Aplicar") {
                model.setTransition(type, duration: seconds)
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
        }
        .onAppear {
            if let clip = model.selectedClip {
                type = clip.transitionOut == .none ? .crossfade : clip.transitionOut
                seconds = clip.transitionDuration
            }
        }
    }
}

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

struct AudioSheet: View {
    @Bindable var model: EditorModel
    @Environment(\.dismiss) private var dismiss
    @State private var showImporter = false
    @State private var originalVolume: Float = 1

    var body: some View {
        SheetContainer(title: "Audio") {
            VStack(alignment: .leading, spacing: 18) {
                GroupBox("Audio original del video") {
                    VStack(alignment: .leading) {
                        Toggle("Silenciar", isOn: Binding(
                            get: { originalVolume == 0 },
                            set: { originalVolume = $0 ? 0 : 1; model.setOriginalVolume(originalVolume) }
                        ))
                        HStack {
                            Image(systemName: "speaker.wave.2")
                            Slider(value: $originalVolume, in: 0...1) { editing in
                                if !editing { model.setOriginalVolume(originalVolume) }
                            }
                        }
                    }
                }

                GroupBox("Pistas agregadas") {
                    if model.audioTracks.isEmpty {
                        Text("Sin pistas. Agrega música o una voz en off desde un archivo.")
                            .font(.footnote).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    ForEach(model.audioTracks) { track in
                        AudioTrackRow(model: model, track: track)
                        Divider()
                    }
                    Button {
                        showImporter = true
                    } label: {
                        Label("Agregar audio desde archivo…", systemImage: "plus")
                    }
                }
            }
        } actions: {
            Spacer()
            Button("Listo") { dismiss() }.keyboardShortcut(.defaultAction)
        }
        .onAppear { originalVolume = model.originalVolume }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.audio, .mp3, .mpeg4Audio, .wav, .aiff, .movie],
                      allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let url = urls.first {
                Task {
                    do {
                        let copy = try MediaStore.importCopy(from: url)
                        await model.addAudio(from: copy)
                    } catch {
                        model.errorMessage = error.localizedDescription
                    }
                }
            }
        }
    }
}

private struct AudioTrackRow: View {
    @Bindable var model: EditorModel
    @State var track: AudioTrack

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(track.name).font(.subheadline).lineLimit(1)
                Spacer()
                Button(role: .destructive) { model.removeAudio(id: track.id) } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
            }
            HStack {
                Text("Empieza en \(formatTime(track.start))").font(.caption).frame(width: 130, alignment: .leading)
                Slider(value: $track.start, in: 0...max(0.1, model.duration)) { editing in
                    if !editing { model.update(track) }
                }
            }
            HStack {
                Image(systemName: "speaker.wave.2").font(.caption).frame(width: 130, alignment: .leading)
                Slider(value: $track.volume, in: 0...1) { editing in
                    if !editing { model.update(track) }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Filtro

struct FilterSheet: View {
    @Bindable var model: EditorModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        SheetContainer(title: "Filtro de color") {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(VideoFilter.allCases) { f in
                    Button {
                        model.setFilter(f)
                    } label: {
                        HStack {
                            Text(f.label)
                            Spacer()
                            if model.filter == f { Image(systemName: "checkmark").foregroundStyle(Color.accentColor) }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 6)
                    Divider()
                }
                Text("El filtro se aplica a todo el video y se ve en la vista previa.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        } actions: {
            Spacer()
            Button("Listo") { dismiss() }.keyboardShortcut(.defaultAction)
        }
    }
}

// MARK: - Exportar

struct ExportSheet: View {
    @Bindable var model: EditorModel
    @Environment(\.dismiss) private var dismiss
    @State private var savedMessage: String?

    private var originalSize: CGSize { CompositionBuilder.renderSize(for: model.clips) }

    var body: some View {
        SheetContainer(title: "Exportar video") {
            VStack(alignment: .leading, spacing: 16) {
                if model.isExporting {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Exportando… \(Int(model.exportProgress * 100))%")
                        ProgressView(value: model.exportProgress)
                    }
                } else if let url = model.exportedURL {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Video exportado", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                        Text(url.lastPathComponent).font(.footnote).foregroundStyle(.secondary)
                        HStack {
                            #if os(iOS)
                            Button {
                                Task {
                                    do {
                                        try await Exporter.saveToPhotos(url)
                                        savedMessage = "Guardado en Fotos."
                                    } catch {
                                        model.errorMessage = error.localizedDescription
                                    }
                                }
                            } label: { Label("Guardar en Fotos", systemImage: "photo.on.rectangle") }
                            #else
                            Button {
                                saveOnMac(url)
                            } label: { Label("Guardar como…", systemImage: "square.and.arrow.down") }
                            #endif
                            ShareLink(item: url) { Label("Compartir", systemImage: "square.and.arrow.up") }
                        }
                        .buttonStyle(.borderedProminent)
                        if let savedMessage { Text(savedMessage).font(.footnote).foregroundStyle(.secondary) }
                    }
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
                Button("Exportar otro") { model.exportedURL = nil; savedMessage = nil }
                Button("Cerrar") { dismiss() }.keyboardShortcut(.defaultAction)
            } else {
                Button("Cancelar") { dismiss() }
                Button("Exportar") { Task { await model.export() } }.keyboardShortcut(.defaultAction)
            }
        }
        .interactiveDismissDisabled(model.isExporting)
    }

    #if os(macOS)
    private func saveOnMac(_ url: URL) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "video." + url.pathExtension
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let dest = panel.url {
            do {
                try? FileManager.default.removeItem(at: dest)
                try FileManager.default.copyItem(at: url, to: dest)
                savedMessage = "Guardado en \(dest.path)"
            } catch {
                model.errorMessage = error.localizedDescription
            }
        }
    }
    #endif
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
