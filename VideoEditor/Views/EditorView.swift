import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

enum ActiveSheet: Identifiable {
    case trim, transition, audio, color, speed, canvas, stickers, export
    case text(TextOverlay)
    case sticker(StickerOverlay)

    var id: String {
        switch self {
        case .trim: return "trim"
        case .transition: return "transition"
        case .audio: return "audio"
        case .color: return "color"
        case .speed: return "speed"
        case .canvas: return "canvas"
        case .stickers: return "stickers"
        case .export: return "export"
        case .text(let t): return "text-\(t.id)"
        case .sticker(let s): return "sticker-\(s.id)"
        }
    }
}

struct EditorView: View {
    @Bindable var model: EditorModel
    @State private var sheet: ActiveSheet?
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var showVideoImporter = false
    @State private var pixelsPerSecond: CGFloat = 60

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                PreviewView(model: model)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                transport
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                tools
                    .padding(.horizontal, 8)
                    .padding(.bottom, 6)
                TimelineView(model: model, pixelsPerSecond: $pixelsPerSecond) { text in
                    sheet = .text(text)
                }
                .frame(height: timelineHeight)
            }
            .background(Color(white: 0.1))
            .navigationTitle("Editor de Video")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            #endif
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    PhotosPicker(selection: $pickerItems, matching: .videos) {
                        Label("Fotos", systemImage: "photo.on.rectangle")
                    }
                    Button {
                        showVideoImporter = true
                    } label: {
                        Label("Archivo", systemImage: "folder")
                    }
                    Button {
                        sheet = .export
                    } label: {
                        Label("Exportar", systemImage: "square.and.arrow.up")
                    }
                    .disabled(model.clips.isEmpty)
                }
            }
        }
        .preferredColorScheme(.dark)
        .sheet(item: $sheet) { item in
            switch item {
            case .trim: TrimSheet(model: model)
            case .transition: TransitionSheet(model: model)
            case .audio: AudioSheet(model: model)
            case .color: ColorSheet(model: model)
            case .speed: SpeedSheet(model: model)
            case .canvas: CanvasSheet(model: model)
            case .stickers: StickerPickerSheet(model: model)
            case .sticker(let s): StickerSheet(model: model, sticker: s)
            case .export: ExportSheet(model: model)
            case .text(let t): TextSheet(model: model, text: t)
            }
        }
        .alert("Atención", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
        .overlay {
            if model.isBusy {
                ZStack {
                    Color.black.opacity(0.4)
                    Group {
                        if let p = model.busyProgress {
                            ProgressView(model.busyMessage, value: p)
                                .frame(width: 220)
                        } else {
                            ProgressView(model.busyMessage)
                        }
                    }
                    .padding(20).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
                .ignoresSafeArea()
            }
        }
        .onChange(of: model.editingStickerID) { _, id in
            guard let id, let s = model.stickers.first(where: { $0.id == id }) else { return }
            model.editingStickerID = nil
            sheet = .sticker(s)
        }
        .onChange(of: pickerItems) { _, items in
            guard !items.isEmpty else { return }
            Task {
                for item in items {
                    do {
                        if let movie = try await item.loadTransferable(type: MovieFile.self) {
                            await model.addClip(from: movie.url)
                        }
                    } catch {
                        model.errorMessage = error.localizedDescription
                    }
                }
                pickerItems = []
            }
        }
        .fileImporter(isPresented: $showVideoImporter,
                      allowedContentTypes: [.movie, .mpeg4Movie, .quickTimeMovie, .video],
                      allowsMultipleSelection: true) { result in
            if case .success(let urls) = result {
                Task {
                    for url in urls {
                        do {
                            let copy = try MediaStore.importCopy(from: url)
                            await model.addClip(from: copy)
                        } catch {
                            model.errorMessage = error.localizedDescription
                        }
                    }
                }
            }
        }
    }

    private var timelineHeight: CGFloat {
        #if os(macOS)
        return 190
        #else
        return 170
        #endif
    }

    // MARK: - Controles de reproducción

    private var transport: some View {
        HStack(spacing: 12) {
            Button { model.step(-1) } label: { Image(systemName: "gobackward") }
            Button { model.togglePlay() } label: {
                Image(systemName: model.isPlaying ? "pause.fill" : "play.fill").font(.title2)
            }
            .keyboardShortcut(.space, modifiers: [])
            .disabled(model.clips.isEmpty)
            Button { model.step(1) } label: { Image(systemName: "goforward") }
            Text("\(formatTime(model.currentTime)) / \(formatTime(model.duration))")
                .font(.system(.caption, design: .monospaced))
                .frame(width: 110, alignment: .leading)
            Slider(value: Binding(get: { model.currentTime }, set: { model.seek(to: $0) }),
                   in: 0...max(0.1, model.duration))
            Image(systemName: "minus.magnifyingglass").font(.caption)
            Slider(value: $pixelsPerSecond, in: 15...200).frame(width: 90)
            Image(systemName: "plus.magnifyingglass").font(.caption)
        }
        .buttonStyle(.borderless)
    }

    // MARK: - Herramientas

    private var tools: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                toolButton("Dividir", "scissors") { model.splitAtPlayhead() }
                    .disabled(model.clips.isEmpty)
                toolButton("Recortar", "crop") { sheet = .trim }
                    .disabled(model.selectedClip == nil)
                toolButton("Transición", "square.on.square.dashed") { sheet = .transition }
                    .disabled(model.selectedClip == nil)
                toolButton("Texto", "textformat") {
                    let t = model.addText()
                    sheet = .text(t)
                }
                .disabled(model.clips.isEmpty)
                toolButton("Audio", "music.note") { sheet = .audio }
                    .disabled(model.clips.isEmpty)
                toolButton("Color", "camera.filters") { sheet = .color }
                    .disabled(model.clips.isEmpty)
                toolButton("Velocidad", "speedometer") { sheet = .speed }
                    .disabled(model.selectedClip == nil)
                toolButton("Congelar", "snowflake") { Task { await model.freezeFrame() } }
                    .disabled(model.clips.isEmpty)
                toolButton("Stickers", "face.smiling") { sheet = .stickers }
                    .disabled(model.clips.isEmpty)
                toolButton("Formato", "aspectratio") { sheet = .canvas }
                    .disabled(model.clips.isEmpty)
                Divider().frame(height: 28)
                toolButton("Atrás", "arrow.left") { model.moveSelectedClip(by: -1) }
                    .disabled(model.selectedClip == nil)
                toolButton("Adelante", "arrow.right") { model.moveSelectedClip(by: 1) }
                    .disabled(model.selectedClip == nil)
                toolButton("Duplicar", "plus.square.on.square") { model.duplicateSelectedClip() }
                    .disabled(model.selectedClip == nil)
                toolButton("Eliminar", "trash") { model.deleteSelectedClip() }
                    .disabled(model.selectedClip == nil)
            }
        }
    }

    private func toolButton(_ title: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: symbol).font(.system(size: 18))
                Text(title).font(.system(size: 10))
            }
            .frame(width: 66, height: 44)
        }
        .buttonStyle(.bordered)
    }
}
