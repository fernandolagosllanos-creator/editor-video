import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

enum ActiveSheet: Identifiable {
    case trim, transition, audio, color, speed, canvas, stickers, export
    case voiceOver, captions
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
        case .voiceOver: return "voiceOver"
        case .captions: return "captions"
        case .text(let t): return "text-\(t.id)"
        case .sticker(let s): return "sticker-\(s.id)"
        }
    }
}

struct EditorView: View {
    @Bindable var model: EditorModel
    /// Volver a la pantalla de inicio (nil = no se muestra el botón).
    var onClose: (() -> Void)?

    @State private var sheet: ActiveSheet?
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var showPhotoPicker = false
    @State private var showVideoImporter = false
    @State private var pixelsPerSecond: CGFloat = 60
    @State private var isRenaming = false
    @State private var newName = ""

    var body: some View {
        ZStack {
            AuroraBackground(intensity: 0.55)
            VStack(spacing: 10) {
                topBar
                    .padding(.horizontal, 14)
                    .padding(.top, 6)
                PreviewView(model: model, onImportPhotos: { showPhotoPicker = true },
                            onImportFiles: { showVideoImporter = true })
                    .padding(.horizontal, 14)
                transport
                    .padding(.horizontal, 16)
                TimelineView(model: model, pixelsPerSecond: $pixelsPerSecond,
                             onEditText: { text in sheet = .text(text) },
                             onTransition: { id in
                                 model.select(clipID: id)
                                 sheet = .transition
                             },
                             onAddClip: addMedia)
                    .frame(height: TimelineView.height(for: model))
                    .animation(Theme.spring, value: TimelineView.height(for: model))
                EditorToolbar(mainTools: mainTools, clipTools: clipTools,
                              isClipMode: model.selectedClip != nil,
                              onExitClipMode: { model.select(clipID: nil) })
                    .padding(.bottom, 6)
            }
        }
        .foregroundStyle(.white)
        .preferredColorScheme(.dark)
        .tint(Theme.accent)
        .sheet(item: $sheet) { item in
            Group {
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
                case .voiceOver: VoiceOverSheet(model: model)
                case .captions: CaptionsSheet(model: model)
                case .text(let t): TextSheet(model: model, text: t)
                }
            }
            .preferredColorScheme(.dark)
            .tint(Theme.accent)
            .presentationDetents([.medium, .large])
            .presentationCornerRadius(28)
            .presentationBackground(Theme.surface)
        }
        .alert("Atención", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
        .overlay {
            if model.isBusy {
                ZStack {
                    Color.black.opacity(0.45)
                    VStack(spacing: 12) {
                        if let p = model.busyProgress {
                            ProgressView(value: p).tint(Theme.accent2).frame(width: 200)
                        } else {
                            ProgressView().controlSize(.large).tint(.white)
                        }
                        Text(model.busyMessage).font(.system(.headline, design: .rounded))
                    }
                    .padding(26)
                    .glassCard(cornerRadius: 22)
                }
                .ignoresSafeArea()
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.2), value: model.isBusy)
        .onChange(of: model.editingStickerID) { _, id in
            guard let id, let s = model.stickers.first(where: { $0.id == id }) else { return }
            model.editingStickerID = nil
            sheet = .sticker(s)
        }
        .alert("Nombre del proyecto", isPresented: $isRenaming) {
            TextField("Nombre", text: $newName)
            Button("Cancelar", role: .cancel) {}
            Button("Guardar") { model.renameProject(newName) }
        }
        .photosPicker(isPresented: $showPhotoPicker, selection: $pickerItems, matching: .videos)
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

    /// En iPhone abre Fotos; en Mac, el Finder.
    private func addMedia() {
        #if os(iOS)
        showPhotoPicker = true
        #else
        showVideoImporter = true
        #endif
    }

    // MARK: - Barra superior

    private var topBar: some View {
        HStack(spacing: 12) {
            if let onClose {
                Button(action: onClose) {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(ChipButtonStyle())
            }
            Button {
                newName = model.projectName
                isRenaming = true
            } label: {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 5) {
                        Text(model.projectName)
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .lineLimit(1)
                        Image(systemName: "pencil")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Text(subtitle)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(Theme.textSecondary)
                }
                .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            Spacer()
            #if os(macOS)
            Button { showVideoImporter = true } label: { Image(systemName: "plus") }
                .buttonStyle(ChipButtonStyle())
                .help("Agregar video")
            #endif
            Button {
                sheet = .export
            } label: {
                Label("Exportar", systemImage: "arrow.up.circle.fill")
            }
            .buttonStyle(GradientButtonStyle())
            .disabled(model.clips.isEmpty)
        }
    }

    private var subtitle: String {
        let n = model.clips.count
        if n == 0 { return "Sin clips" }
        return "\(n) \(n == 1 ? "clip" : "clips") · \(formatTime(model.duration))"
    }

    // MARK: - Controles de reproducción

    private var transport: some View {
        ZStack {
            HStack {
                HStack(spacing: 4) {
                    Text(formatTime(model.currentTime)).foregroundStyle(.white)
                    Text("/ \(formatTime(model.duration))").foregroundStyle(Theme.textSecondary)
                }
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                Spacer()
                Button(action: fitTimeline) {
                    Image(systemName: "arrow.left.and.right.square")
                }
                .buttonStyle(ChipButtonStyle())
                .disabled(model.clips.isEmpty)
                .help("Ver todo el proyecto")
            }
            HStack(spacing: 18) {
                Button { model.step(-1) } label: { Image(systemName: "gobackward") }
                    .keyboardShortcut(.leftArrow, modifiers: [])
                Button { model.togglePlay() } label: {
                    Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 20, weight: .bold))
                        .contentTransition(.symbolEffect(.replace))
                        .frame(width: 50, height: 50)
                        .background(Theme.gradient, in: Circle())
                        .shadow(color: Theme.accent2.opacity(0.45), radius: 10, y: 3)
                }
                .keyboardShortcut(.space, modifiers: [])
                .disabled(model.clips.isEmpty)
                Button { model.step(1) } label: { Image(systemName: "goforward") }
                    .keyboardShortcut(.rightArrow, modifiers: [])
            }
            .font(.system(size: 17, weight: .semibold))
            .buttonStyle(.plain)
        }
        .foregroundStyle(.white)
    }

    /// Ajusta el zoom para que todo el proyecto quepa en pantalla.
    private func fitTimeline() {
        guard model.duration > 0 else { return }
        withAnimation(Theme.spring) {
            pixelsPerSecond = min(max(280 / CGFloat(model.duration), TimelineView.minZoom), TimelineView.maxZoom)
        }
    }

    // MARK: - Herramientas

    private var mainTools: [ToolItem] {
        let hasClips = !model.clips.isEmpty
        return [
            ToolItem("Agregar", "plus.rectangle.on.rectangle") { addMedia() },
            ToolItem("Cortar", "scissors", isEnabled: hasClips) { model.splitAtPlayhead() },
            ToolItem("Texto", "textformat", isEnabled: hasClips) {
                let t = model.addText()
                sheet = .text(t)
            },
            ToolItem("Stickers", "face.smiling", isEnabled: hasClips) { sheet = .stickers },
            ToolItem("Audio", "music.note", isEnabled: hasClips) { sheet = .audio },
            ToolItem("Voz", "mic.fill", isEnabled: hasClips) { sheet = .voiceOver },
            ToolItem("Subtítulos", "captions.bubble", isEnabled: hasClips) { sheet = .captions },
            ToolItem("Filtros", "camera.filters", isEnabled: hasClips) {
                if selectClipUnderPlayhead() { sheet = .color }
            },
            ToolItem("Efectos", "sparkles", isEnabled: hasClips) {
                if selectClipUnderPlayhead() { sheet = .transition }
            },
            ToolItem("Formato", "aspectratio", isEnabled: hasClips) { sheet = .canvas },
            ToolItem("Congelar", "snowflake", isEnabled: hasClips) { Task { await model.freezeFrame() } },
        ]
    }

    private var clipTools: [ToolItem] {
        let index = model.selectedClipIndex ?? 0
        return [
            ToolItem("Dividir", "scissors") { model.splitAtPlayhead() },
            ToolItem("Recortar", "crop") { sheet = .trim },
            ToolItem("Velocidad", "speedometer") { sheet = .speed },
            ToolItem("Color", "camera.filters") { sheet = .color },
            ToolItem("Transición", "square.on.square.dashed") { sheet = .transition },
            ToolItem("Congelar", "snowflake") { Task { await model.freezeFrame() } },
            ToolItem("Duplicar", "plus.square.on.square") { model.duplicateSelectedClip() },
            ToolItem("Mover ←", "arrow.left", isEnabled: index > 0) { model.moveSelectedClip(by: -1) },
            ToolItem("Mover →", "arrow.right", isEnabled: index < model.clips.count - 1) { model.moveSelectedClip(by: 1) },
            ToolItem("Eliminar", "trash", isDestructive: true) {
                withAnimation(Theme.spring) { model.deleteSelectedClip() }
            },
        ]
    }

    /// Si no hay clip seleccionado, selecciona el que está bajo el cabezal.
    private func selectClipUnderPlayhead() -> Bool {
        if model.selectedClip != nil { return true }
        let t = Timeline.time(model.currentTime)
        let target = model.placements.last { $0.start <= t } ?? model.placements.first
        model.select(clipID: target?.clip.id)
        return target != nil
    }
}
