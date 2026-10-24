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
    var filter: VideoFilter = .none

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

    // Estado de trabajo
    var isBusy = false
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

    var selectedText: TextOverlay? {
        guard let id = selectedTextID else { return nil }
        return texts.first { $0.id == id }
    }

    var visibleTexts: [TextOverlay] {
        texts.filter { currentTime >= $0.start && currentTime < $0.end }
    }

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
        isBusy = true
        defer { isBusy = false }
        do {
            let asset = AVURLAsset(url: url)
            guard let track = try await asset.loadTracks(withMediaType: .video).first else {
                errorMessage = "El archivo no contiene video."
                return
            }
            let assetDuration = try await asset.load(.duration)
            let (naturalSize, transform) = try await track.load(.naturalSize, .preferredTransform)
            let audioTracksInFile = try await asset.loadTracks(withMediaType: .audio)
            let hasAudio = !audioTracksInFile.isEmpty
            var clip = Clip(id: UUID(), url: url, name: url.lastPathComponent, assetDuration: assetDuration,
                            naturalSize: naturalSize, preferredTransform: transform, hasAudio: hasAudio,
                            start: .zero, end: assetDuration)
            clip.thumbnails = await Thumbnails.generate(asset: asset, duration: assetDuration, count: 8)
            clips.append(clip)
            selectedClipID = clip.id
            rebuild()
        } catch {
            errorMessage = error.localizedDescription
        }
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
        let t = Timeline.time(currentTime)
        let candidates = placements.filter { $0.start < t && t < $0.end }
        guard let target = candidates.first(where: { $0.clip.id == selectedClipID }) ?? candidates.first,
              let index = clips.firstIndex(where: { $0.id == target.clip.id })
        else {
            errorMessage = "Coloca el cabezal dentro de un clip para dividirlo."
            return
        }
        let local = target.clip.start + (t - target.start)
        let margin = Timeline.time(0.1)
        guard local > target.clip.start + margin, local < target.clip.end - margin else {
            errorMessage = "El corte queda demasiado cerca del borde del clip."
            return
        }
        let source = target.clip
        var first = source
        first.end = local
        first.transitionOut = .none
        let second = Clip(id: UUID(), url: source.url, name: source.name, assetDuration: source.assetDuration,
                          naturalSize: source.naturalSize, preferredTransform: source.preferredTransform,
                          hasAudio: source.hasAudio, start: local, end: source.end,
                          transitionOut: source.transitionOut, transitionDuration: source.transitionDuration,
                          thumbnails: source.thumbnails)
        clips[index] = first
        clips.insert(second, at: index + 1)
        selectedClipID = second.id
        rebuild()
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

    func duplicateSelectedClip() {
        guard let index = selectedClipIndex else { return }
        let c = clips[index]
        let copy = Clip(id: UUID(), url: c.url, name: c.name, assetDuration: c.assetDuration,
                        naturalSize: c.naturalSize, preferredTransform: c.preferredTransform, hasAudio: c.hasAudio,
                        start: c.start, end: c.end, transitionOut: c.transitionOut,
                        transitionDuration: c.transitionDuration, thumbnails: c.thumbnails)
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

    // MARK: - Filtro

    func setFilter(_ f: VideoFilter) {
        filter = f
        rebuild()
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
                                                           originalVolume: originalVolume, filter: filter,
                                                           texts: texts, forExport: false)
            if Task.isCancelled { return }
            let item = AVPlayerItem(asset: built.composition)
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
            let size = exportSettings.outputSize(from: CompositionBuilder.renderSize(for: clips))
            let built = try await CompositionBuilder.build(clips: clips, audioTracks: audioTracks,
                                                           originalVolume: originalVolume, filter: filter,
                                                           texts: texts, forExport: true, outputSize: size)
            let url = try await Exporter.export(built, settings: exportSettings) { [weak self] p in
                Task { @MainActor in self?.exportProgress = p }
            }
            exportedURL = url
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
