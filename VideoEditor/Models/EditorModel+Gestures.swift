import Foundation
import CoreMedia

/// Operaciones que usan los gestos de la línea de tiempo (arrastrar bordes, mantener y mover).
extension EditorModel {
    /// Mueve un clip a otra posición de la lista (mantener pulsado y arrastrar).
    func moveClip(id: UUID, to newIndex: Int) {
        guard let from = clips.firstIndex(where: { $0.id == id }) else { return }
        let to = min(max(0, newIndex), clips.count - 1)
        guard from != to else { return }
        let clip = clips.remove(at: from)
        clips.insert(clip, at: to)
        selectedClipID = id
        rebuild()
    }

    /// Recorta un clip a partir de los bordes arrastrados (segundos dentro del archivo original).
    func trimClip(id: UUID, start: Double, end: Double) {
        selectedClipID = id
        selectedTextID = nil
        trimSelectedClip(start: start, end: end)
    }

    /// Mueve el inicio de una pista de audio en la línea de tiempo.
    func moveAudio(id: UUID, to start: Double) {
        guard var track = audioTracks.first(where: { $0.id == id }) else { return }
        track.start = max(0, start)
        update(track)
    }

    /// Mueve el momento en que aparece un texto.
    func moveTextStart(id: UUID, to start: Double) {
        guard var text = texts.first(where: { $0.id == id }) else { return }
        text.start = min(max(0, start), max(0, duration - 0.2))
        update(text)
    }

    /// Selecciona un clip (o ninguno) y quita la selección de texto.
    func select(clipID: UUID?) {
        selectedClipID = clipID
        if clipID != nil { selectedTextID = nil }
    }
}

extension Clip {
    /// Segundo del archivo original que se ve a `offset` segundos del inicio del clip en la línea
    /// de tiempo. (Si en el futuro hay velocidad por clip, se multiplica aquí.)
    func sourceSeconds(atTimelineOffset offset: Double) -> Double {
        start.seconds + offset
    }

    /// Cuántos segundos del archivo equivalen a `delta` segundos de línea de tiempo.
    func sourceDelta(forTimelineDelta delta: Double) -> Double {
        delta
    }
}
