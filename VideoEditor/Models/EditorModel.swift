import Foundation
import AVFoundation
import CoreMedia
import SwiftUI
import Observation

/// Estado del editor y todas las operaciones de edición. Cada cambio reconstruye la composición
/// que reproduce el `AVPlayer` de la vista previa.
@MainActor
@Observable
final class EditorModel {
    // Proyecto
    var clips: [Clip] = []
    var texts: [TextOverlay] = []
    var audioTracks: [AudioTrack] = []
    var originalVolume: Float = 1
    var stickers: [StickerOverlay] = []
    var aspect: CanvasAspect = .original
    var canvasBackground: CanvasBackground = .blur

    // Proyecto guardado (ver EditorModel+Project.swift)
    var projectID = UUID()
    var projectName = "Proyecto"
    var projectCreatedAt = Date()
    var isRestoringProject = false
    @ObservationIgnored var saveTask: Task<Void, Never>?
    @ObservationIgnored var savedThumbnailKey: String?

    // Reproducción
    let player = AVPlayer()
    var currentTime: Double = 0
    var duration: Double = 0
    var isPlaying = false
    var renderSize = CGSize(width: 1920, height: 1080)

    // Selección
    var selectedClipID: UUID?
    var selectedTextID: UUID?
    var selectedStickerID: UUID?
    /// Sticker cuya hoja de edición debe abrirse (lo pide la vista previa con doble toque).
    var editingStickerID: UUID?

    // Estado de trabajo
    var isBusy = false
    var busyMessage = "Importando…"
    /// Progreso (0...1) de una tarea larga como la reversa; nil si no se puede medir.
    var busyProgress: Double?
    var isExporting = false
    var exportProgress: Double = 0
    var exportedURL: URL?
    var errorMessage: String?
    var exportSettings = ExportSettings()

    private var rebuildTask: Task<Void, Never>?
    private var timeObserver: Any?

    init() {
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 30), queue: .main) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.currentTime = time.seconds
                self.isPlaying = self.player.rate > 0
            }
        }
        NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.isPlaying = false
            }
        }
        connectProjectStore()
    }

    // MARK: - Datos derivados

    var placements: [Placement] { Timeline.placements(for: clips) }

    var selectedClip: Clip? {
        guard let id = selectedClipID else { return nil }
        return clips.first { $0.id == id }
    }

    var selectedClipIndex: Int? {
        guard let id = selectedClipID else { return nil }
        return clips.firstIndex { $0.id == id }
    }

    /// Segundo (dentro del clip) que muestran las vistas previas de las hojas de efectos: el del
    /// cabezal si está sobre el clip, o su primer cuadro.
    func previewLocalTime(for clip: Clip) -> Double {
        guard let p = placements.first(where: { $0.clip.id == clip.id }) else { return 0 }
        let local = currentTime - p.start.seconds
        return local >= 0 && local < clip.duration.seconds ? local : 0
    }

    var selectedText: TextOverlay? {
        guard let id = selectedTextID else { return nil }
        return texts.first { $0.id == id }
    }

    var visibleTexts: [TextOverlay] {
        texts.filter { currentTime >= $0.start && currentTime < $0.end }
    }

    var visibleStickers: [StickerOverlay] {
        stickers.filter { currentTime >= $0.start && currentTime < $0.end }
    }

    var selectedSticker: StickerOverlay? {
        guard let id = selectedStickerID else { return nil }
        return stickers.first { $0.id == id }
    }

    /// Tamaño del lienzo según la relación de aspecto elegida (antes de la resolución de exportación).
    var canvasSize: CGSize { CompositionBuilder.renderSize(for: clips, aspect: aspect) }

    var renderAspect: CGFloat {
        renderSize.height > 0 ? renderSize.width / renderSize.height : 16 / 9
    }

    // MARK: - Reproducción

    func togglePlay() {
        if player.rate > 0 {
            player.pause()
        } else {
            if duration > 0, currentTime >= duration - 0.05 { seek(to: 0) }
            player.play()
        }
        isPlaying = player.rate > 0
    }

    func seek(to seconds: Double) {
        let clamped = min(max(0, seconds), max(0, duration))
        currentTime = clamped
        player.seek(to: Timeline.time(clamped), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func step(_ delta: Double) { seek(to: currentTime + delta) }

    // MARK: - Importar

    func addClip(from url: URL) async {
        busyMessage = "Importando…"
        busyProgress = nil
        isBusy = true
        defer { isBusy = false }
        do {
            let clip = try await loadClip(from: url)
            clips.append(clip)
            selectedClipID = clip.id
            rebuild()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadClip(from url: URL) async throws -> Clip {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw ClipProcessorError.noVideo
        }
        let assetDuration = try await asset.load(.duration)
        let (naturalSize, transform) = try await track.load(.naturalSize, .preferredTransform)
        let audioTracksInFile = try await asset.loadTracks(withMediaType: .audio)
        let hasAudio = !audioTracksInFile.isEmpty
        var clip = Clip(id: UUID(), url: url, name: url.lastPathComponent, assetDuration: assetDuration,
                        naturalSize: naturalSize, preferredTransform: transform, hasAudio: hasAudio,
                        start: .zero, end: assetDuration)
        clip.thumbnails = await Thumbnails.generate(asset: asset, duration: assetDuration, count: 8)
        return clip
    }

    func addAudio(from url: URL, kind: AudioKind = .music, name: String? = nil, start: Double? = nil) async {
        do {
            let asset = AVURLAsset(url: url)
            let found = try await asset.loadTracks(withMediaType: .audio)
            guard !found.isEmpty else {
                errorMessage = "El archivo no contiene audio."
                return
            }
            let assetDuration = try await asset.load(.duration)
            var track = AudioTrack(id: UUID(), url: url, name: name ?? url.deletingPathExtension().lastPathComponent,
                                   assetDuration: assetDuration, kind: kind, start: start ?? currentTime, volume: 1)
            if kind == .music {
                // Las canciones empiezan y terminan suave por defecto.
                track.fadeIn = min(1, assetDuration.seconds / 4)
                track.fadeOut = min(2, assetDuration.seconds / 4)
            }
            audioTracks.append(track)
            rebuild()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Edición de clips

    /// Divide el clip seleccionado (o el que esté bajo el cabezal) en el tiempo actual.
    func splitAtPlayhead() {
        guard let index = clipIndexUnderPlayhead() else {
            errorMessage = "Coloca el cabezal dentro de un clip para dividirlo."
            return
        }
        guard split(at: index, timelineTime: currentTime) else {
            errorMessage = "El corte queda demasiado cerca del borde del clip."
            return
        }
        selectedClipID = clips[index + 1].id
        rebuild()
    }

    /// Índice del clip bajo el cabezal (prefiere el seleccionado si hay dos por una transición).
    private func clipIndexUnderPlayhead() -> Int? {
        let t = Timeline.time(currentTime)
        let candidates = placements.filter { $0.start <= t && t < $0.end }
        guard let target = candidates.first(where: { $0.clip.id == selectedClipID }) ?? candidates.first else { return nil }
        return clips.firstIndex { $0.id == target.clip.id }
    }

    /// Corta el clip `index` en el segundo `timelineTime` de la línea de tiempo. Devuelve false si
    /// el corte queda pegado a un borde.
    @discardableResult
    private func split(at index: Int, timelineTime: Double) -> Bool {
        guard let placement = placements.first(where: { $0.clip.id == clips[index].id }) else { return false }
        let source = clips[index]
        let local = timelineTime - placement.start.seconds
        let cut = source.sourceSeconds(atLocal: local)
        let margin = 0.1
        guard cut > source.start.seconds + margin, cut < source.end.seconds - margin else { return false }
        var first = source
        var second = source.copyWithNewID()
        if source.isReversed {
            // En reversa lo primero que se ve es el final del archivo.
            first.start = Timeline.time(cut)
            second.end = Timeline.time(cut)
        } else {
            first.end = Timeline.time(cut)
            second.start = Timeline.time(cut)
        }
        first.transitionOut = .none
        clips[index] = first
        clips.insert(second, at: index + 1)
        return true
    }

    func deleteSelectedClip() {
        guard let index = selectedClipIndex else { return }
        clips.remove(at: index)
        selectedClipID = clips.isEmpty ? nil : clips[min(index, clips.count - 1)].id
        rebuild()
    }

    func moveSelectedClip(by offset: Int) {
        guard let index = selectedClipIndex else { return }
        let newIndex = index + offset
        guard newIndex >= 0, newIndex < clips.count else { return }
        clips.swapAt(index, newIndex)
        rebuild()
    }

    func trimSelectedClip(start: Double, end: Double) {
        guard let index = selectedClipIndex else { return }
        let clip = clips[index]
        let maxEnd = clip.assetDuration.seconds
        let s = min(max(0, start), maxEnd - 0.1)
        let e = max(min(end, maxEnd), s + 0.1)
        clips[index].start = Timeline.time(s)
        clips[index].end = Timeline.time(e)
        rebuild()
    }

    func setTransition(_ type: TransitionType, duration: Double) {
        guard let index = selectedClipIndex else { return }
        clips[index].transitionOut = type
        clips[index].transitionDuration = duration
        rebuild()
    }

    /// La misma transición entre todos los clips.
    func setTransitionForAll(_ type: TransitionType, duration: Double) {
        for i in clips.indices {
            clips[i].transitionOut = type
            clips[i].transitionDuration = duration
        }
        rebuild()
    }

    func duplicateSelectedClip() {
        guard let index = selectedClipIndex else { return }
        let copy = clips[index].copyWithNewID()
        clips.insert(copy, at: index + 1)
        selectedClipID = copy.id
        rebuild()
    }

    // MARK: - Textos

    func addText() -> TextOverlay {
        var t = TextOverlay()
        t.start = min(currentTime, max(0, duration - 1))
        t.duration = min(3, max(0.5, duration - t.start))
        texts.append(t)
        selectedTextID = t.id
        scheduleSave()
        return t
    }

    func update(_ text: TextOverlay) {
        guard let i = texts.firstIndex(where: { $0.id == text.id }) else { return }
        texts[i] = text
        scheduleSave()
    }

    func moveText(id: UUID, to position: CGPoint) {
        guard let i = texts.firstIndex(where: { $0.id == id }) else { return }
        texts[i].position = CGPoint(x: min(max(0.05, position.x), 0.95), y: min(max(0.05, position.y), 0.95))
        scheduleSave()
    }

    func removeText(id: UUID) {
        texts.removeAll { $0.id == id }
        if selectedTextID == id { selectedTextID = nil }
        scheduleSave()
    }

    // MARK: - Audio

    func update(_ track: AudioTrack) {
        guard let i = audioTracks.firstIndex(where: { $0.id == track.id }) else { return }
        audioTracks[i] = track
        rebuild()
    }

    func removeAudio(id: UUID) {
        audioTracks.removeAll { $0.id == id }
        rebuild()
    }

    func setOriginalVolume(_ v: Float) {
        originalVolume = v
        rebuild()
    }

    // MARK: - Efectos (color, velocidad, reversa, congelar, formato, stickers)

    /// Cambia el color del clip seleccionado, o de todos los clips.
    func setLook(_ look: ColorLook, applyToAll: Bool) {
        if applyToAll {
            for i in clips.indices { clips[i].look = look }
        } else if let index = selectedClipIndex {
            clips[index].look = look
        }
        rebuild()
    }

    func setSpeed(_ speed: Double) {
        guard let index = selectedClipIndex else { return }
        clips[index].speed = min(max(speed, 0.25), 4)
        rebuild()
    }

    /// Activa o quita la reversa del clip seleccionado. La primera vez genera la copia invertida.
    func setReversed(_ on: Bool) async {
        guard let id = selectedClipID, let index = selectedClipIndex else { return }
        if on, clips[index].reversedURL == nil {
            let url = clips[index].url
            busyMessage = "Invirtiendo el clip…"
            busyProgress = 0
            isBusy = true
            defer { isBusy = false; busyProgress = nil }
            do {
                let reversed = try await ClipProcessor.reversedCopy(of: url) { [weak self] p in
                    Task { @MainActor in self?.busyProgress = p }
                }
                // Todos los trozos del mismo archivo pueden reutilizar la copia.
                for i in clips.indices where clips[i].url == url { clips[i].reversedURL = reversed }
            } catch {
                errorMessage = error.localizedDescription
                return
            }
        }
        guard let i = clips.firstIndex(where: { $0.id == id }), clips[i].isReversed != on else { return }
        clips[i].isReversed = on
        clips[i].thumbnails.reverse()
        rebuild()
    }

    /// Congela el cuadro bajo el cabezal: corta el clip ahí e inserta una imagen fija de `seconds`.
    func freezeFrame(seconds: Double = 2) async {
        guard let index = clipIndexUnderPlayhead(),
              let placement = placements.first(where: { $0.clip.id == clips[index].id }) else {
            errorMessage = "Coloca el cabezal sobre un clip para congelar ese cuadro."
            return
        }
        player.pause()
        let source = clips[index]
        let timelineTime = currentTime
        let local = timelineTime - placement.start.seconds
        busyMessage = "Congelando fotograma…"
        busyProgress = nil
        isBusy = true
        defer { isBusy = false }
        do {
            let image = try await Thumbnails.frame(of: source, atLocal: local, maxSide: nil)
            let url = try await ClipProcessor.stillVideo(from: image, seconds: seconds)
            var still = try await loadClip(from: url)
            still.name = "Congelado"
            still.isFreezeFrame = true
            still.look = source.look
            still.framing = source.framing
            guard let i = clips.firstIndex(where: { $0.id == source.id }) else { return }
            // Al inicio del clip la imagen va antes; si no, se corta el clip y va entre las dos
            // partes (o después, si el cabezal está pegado al final).
            let insertAt: Int
            if local < 0.15 {
                insertAt = i
            } else {
                split(at: i, timelineTime: timelineTime)
                insertAt = i + 1
            }
            clips.insert(still, at: insertAt)
            selectedClipID = still.id
            rebuild()
            seek(to: timelineTime)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func setFraming(_ framing: ClipFraming, applyToAll: Bool) {
        if applyToAll {
            for i in clips.indices { clips[i].framing = framing }
        } else if let index = selectedClipIndex {
            clips[index].framing = framing
        }
        rebuild()
    }

    func setCanvas(aspect: CanvasAspect, background: CanvasBackground) {
        self.aspect = aspect
        canvasBackground = background
        rebuild()
    }

    func addSticker(_ content: StickerContent) -> StickerOverlay {
        var s = StickerOverlay()
        s.content = content
        s.color = content.isShape ? .yellow : .white
        s.start = min(currentTime, max(0, duration - 1))
        s.duration = min(3, max(0.5, duration - s.start))
        // Cada sticker nuevo un poco desplazado para que no queden todos encima.
        let n = Double(stickers.count % 5)
        s.position = CGPoint(x: 0.5 + (n - 2) * 0.06, y: 0.42 + (n - 2) * 0.04)
        stickers.append(s)
        selectedStickerID = s.id
        selectedTextID = nil
        return s
    }

    func update(_ sticker: StickerOverlay) {
        guard let i = stickers.firstIndex(where: { $0.id == sticker.id }) else { return }
        stickers[i] = sticker
        scheduleSave()
    }

    func moveSticker(id: UUID, to position: CGPoint) {
        guard let i = stickers.firstIndex(where: { $0.id == id }) else { return }
        stickers[i].position = CGPoint(x: min(max(0, position.x), 1), y: min(max(0, position.y), 1))
        scheduleSave()
    }

    func removeSticker(id: UUID) {
        stickers.removeAll { $0.id == id }
        if selectedStickerID == id { selectedStickerID = nil }
        scheduleSave()
    }

    // MARK: - Reconstruir la vista previa

    func rebuild() {
        scheduleSave()
        rebuildTask?.cancel()
        rebuildTask = Task { await performRebuild() }
    }

    private func performRebuild() async {
        guard !clips.isEmpty else {
            player.replaceCurrentItem(with: nil)
            duration = 0
            currentTime = 0
            return
        }
        do {
            let built = try await CompositionBuilder.build(clips: clips, audioTracks: audioTracks,
                                                           originalVolume: originalVolume,
                                                           texts: texts, aspect: aspect, canvas: canvasBackground,
                                                           forExport: false)
            if Task.isCancelled { return }
            let item = AVPlayerItem(asset: built.composition)
            // Conserva el tono de la voz en cámara lenta o acelerado.
            item.audioTimePitchAlgorithm = .spectral
            item.videoComposition = built.videoComposition
            item.audioMix = built.audioMix
            let wasPlaying = player.rate > 0
            let target = min(currentTime, built.duration.seconds)
            player.replaceCurrentItem(with: item)
            duration = built.duration.seconds
            renderSize = built.renderSize
            _ = await player.seek(to: Timeline.time(target), toleranceBefore: .zero, toleranceAfter: .zero)
            currentTime = target
            if wasPlaying { player.play() }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Exportar

    func export() async {
        guard !clips.isEmpty else {
            errorMessage = "Agrega al menos un clip antes de exportar."
            return
        }
        player.pause()
        isExporting = true
        exportProgress = 0
        exportedURL = nil
        defer { isExporting = false }
        do {
            let size = exportSettings.outputSize(from: canvasSize)
            let stickerImages = StickerRenderer.images(for: stickers, canvasSize: size)
            let built = try await CompositionBuilder.build(clips: clips, audioTracks: audioTracks,
                                                           originalVolume: originalVolume,
                                                           texts: texts, stickers: stickers,
                                                           stickerImages: stickerImages,
                                                           aspect: aspect, canvas: canvasBackground,
                                                           forExport: true, outputSize: size)
            let url = try await Exporter.export(built, settings: exportSettings) { [weak self] p in
                Task { @MainActor in self?.exportProgress = p }
            }
            exportedURL = url
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
