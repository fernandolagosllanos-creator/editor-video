import Foundation
import AVFoundation
import CoreGraphics

/// Guardado automático y apertura de proyectos.
extension EditorModel {

    func connectProjectStore() {
        projectName = Self.defaultProjectName()
        let store = ProjectStore.shared
        store.didDelete = { [weak self] id in
            guard let self, id == self.projectID else { return }
            self.newProject()
        }
        store.filesInUse = { [weak self] in
            guard let self else { return [] }
            var names = Set(self.clips.map { MediaReference.encode($0.url) })
            names.formUnion(self.clips.compactMap { $0.reversedURL.map(MediaReference.encode) })
            names.formUnion(self.audioTracks.map { MediaReference.encode($0.url) })
            return names
        }
    }

    /// Proyecto tal como se guardará en disco.
    func makeProjectFile() -> ProjectFile {
        var file = ProjectFile()
        file.id = projectID
        file.name = projectName
        file.createdAt = projectCreatedAt
        file.modifiedAt = Date()
        file.duration = duration
        file.clips = clips
        file.texts = texts
        file.audioTracks = audioTracks
        file.originalVolume = originalVolume
        file.stickers = stickers
        file.aspect = aspect
        file.canvasBackground = canvasBackground
        return file
    }

    /// Guarda poco después del último cambio (agrupa cambios seguidos, como al arrastrar un texto).
    func scheduleSave() {
        guard !isRestoringProject else { return }
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled else { return }
            await self?.saveNow()
        }
    }

    /// Guarda de inmediato (también se llama al pasar la app a segundo plano).
    func saveNow() async {
        saveTask?.cancel()
        // Un proyecto vacío que nunca se guardó no aparece en la galería.
        guard !clips.isEmpty || ProjectStore.exists(projectID) else { return }
        let file = makeProjectFile()
        let thumbnail = await projectThumbnailIfChanged()
        do {
            try await Task.detached(priority: .utility) {
                try ProjectStore.write(file, thumbnail: thumbnail)
            }.value
            ProjectStore.shared.refresh()
        } catch {
            errorMessage = "No se pudo guardar el proyecto: \(error.localizedDescription)"
        }
    }

    /// Miniatura de la galería (del primer clip). Solo se vuelve a generar si cambió el primer clip.
    private func projectThumbnailIfChanged() async -> CGImage? {
        guard let first = clips.first else { return nil }
        let key = "\(projectID)-\(first.id)-\(first.start.seconds)"
        if key == savedThumbnailKey, FileManager.default.fileExists(atPath: ProjectStore.thumbnailURL(for: projectID).path) {
            return nil
        }
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: first.url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 480, height: 480)
        let time = first.start + Timeline.time(min(1, first.duration.seconds / 2))
        guard let image = try? await generator.image(at: time).image else {
            return first.thumbnails.first
        }
        savedThumbnailKey = key
        return image
    }

    /// Empieza un proyecto vacío (el anterior ya quedó guardado).
    func newProject() {
        player.pause()
        isRestoringProject = true
        projectID = UUID()
        projectName = Self.defaultProjectName()
        projectCreatedAt = Date()
        clips = []
        texts = []
        audioTracks = []
        originalVolume = 1
        stickers = []
        aspect = .original
        canvasBackground = .blur
        selectedClipID = nil
        selectedStickerID = nil
        selectedTextID = nil
        exportedURL = nil
        currentTime = 0
        rebuild()
        isRestoringProject = false
    }

    /// Abre un proyecto guardado. Guarda antes el que está abierto.
    func openProject(id: UUID) async {
        guard id != projectID else { return }
        await saveNow()
        player.pause()
        isBusy = true
        defer { isBusy = false }
        let file: ProjectFile
        do {
            file = try await Task.detached { try ProjectStore.read(id) }.value
        } catch {
            errorMessage = "No se pudo abrir el proyecto: \(error.localizedDescription)"
            return
        }
        var restored = file.clips
        for i in restored.indices {
            let asset = AVURLAsset(url: restored[i].url)
            restored[i].thumbnails = await Thumbnails.generate(asset: asset, duration: restored[i].assetDuration, count: 8)
        }
        isRestoringProject = true
        projectID = file.id
        projectName = file.name
        projectCreatedAt = file.createdAt
        clips = restored
        texts = file.texts
        audioTracks = file.audioTracks
        originalVolume = file.originalVolume
        stickers = file.stickers
        aspect = file.aspect
        canvasBackground = file.canvasBackground
        selectedStickerID = nil
        selectedClipID = restored.first?.id
        selectedTextID = nil
        exportedURL = nil
        currentTime = 0
        rebuild()
        isRestoringProject = false
    }

    func renameProject(_ name: String) {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        projectName = clean
        scheduleSave()
    }

    static func defaultProjectName() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "es")
        f.dateFormat = "d MMM, HH:mm"
        return "Proyecto \(f.string(from: Date()))"
    }
}
