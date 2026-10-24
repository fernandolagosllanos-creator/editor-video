import Foundation
import CoreMedia
import CoreGraphics

// MARK: - Proyecto guardado

/// Lo que se escribe en disco para poder cerrar la app y continuar después.
///
/// Para agregar un campo nuevo: dale un valor por defecto y añade una línea en `encode(to:)` y otra en
/// `init(from:)` usando `decodeIfPresent`, así los proyectos guardados antes siguen abriendo.
struct ProjectFile: Codable {
    var version = 1
    var id = UUID()
    var name = "Proyecto"
    var createdAt = Date()
    var modifiedAt = Date()
    var duration: Double = 0
    var clips: [Clip] = []
    var texts: [TextOverlay] = []
    var audioTracks: [AudioTrack] = []
    var originalVolume: Float = 1
    var filter: VideoFilter = .none

    enum CodingKeys: String, CodingKey {
        case version, id, name, createdAt, modifiedAt, duration, clips, texts, audioTracks, originalVolume, filter
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Proyecto"
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        modifiedAt = try c.decodeIfPresent(Date.self, forKey: .modifiedAt) ?? createdAt
        duration = try c.decodeIfPresent(Double.self, forKey: .duration) ?? 0
        // Un clip o audio cuyo archivo ya no se puede leer se omite en vez de romper todo el proyecto.
        clips = (try c.decodeIfPresent([Lenient<Clip>].self, forKey: .clips) ?? []).compactMap(\.value)
        texts = (try c.decodeIfPresent([Lenient<TextOverlay>].self, forKey: .texts) ?? []).compactMap(\.value)
        audioTracks = (try c.decodeIfPresent([Lenient<AudioTrack>].self, forKey: .audioTracks) ?? []).compactMap(\.value)
        originalVolume = try c.decodeIfPresent(Float.self, forKey: .originalVolume) ?? 1
        filter = (try? c.decodeIfPresent(VideoFilter.self, forKey: .filter)) ?? VideoFilter.none
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(version, forKey: .version)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(modifiedAt, forKey: .modifiedAt)
        try c.encode(duration, forKey: .duration)
        try c.encode(clips, forKey: .clips)
        try c.encode(texts, forKey: .texts)
        try c.encode(audioTracks, forKey: .audioTracks)
        try c.encode(originalVolume, forKey: .originalVolume)
        try c.encode(filter, forKey: .filter)
    }
}

/// Decodifica un elemento de una lista sin fallar la lista completa si ese elemento está dañado.
struct Lenient<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws {
        value = try? T(from: decoder)
    }
}

enum ProjectDecodingError: LocalizedError {
    case missingMedia(String)

    var errorDescription: String? {
        switch self {
        case .missingMedia(let name): return "Falta el archivo \(name)."
        }
    }
}

/// Los archivos se guardan por nombre dentro de `MediaStore`, porque en el iPhone la ruta completa de la
/// carpeta de la app cambia cuando se reinstala desde Xcode.
enum MediaReference {
    static func encode(_ url: URL) -> String { url.lastPathComponent }

    static func decode(_ fileName: String) throws -> URL {
        let url = MediaStore.directory.appendingPathComponent(fileName)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ProjectDecodingError.missingMedia(fileName)
        }
        return url
    }
}

// MARK: - Clip

extension Clip: Codable {
    enum CodingKeys: String, CodingKey {
        case id, file, name, assetDuration, naturalWidth, naturalHeight, transform, hasAudio
        case start, end, transitionOut, transitionDuration
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let t = try c.decodeIfPresent([Double].self, forKey: .transform) ?? [1, 0, 0, 1, 0, 0]
        let transform = t.count == 6
            ? CGAffineTransform(a: t[0], b: t[1], c: t[2], d: t[3], tx: t[4], ty: t[5])
            : .identity
        self.init(id: try c.decode(UUID.self, forKey: .id),
                  url: try MediaReference.decode(try c.decode(String.self, forKey: .file)),
                  name: try c.decodeIfPresent(String.self, forKey: .name) ?? "Clip",
                  assetDuration: Timeline.time(try c.decode(Double.self, forKey: .assetDuration)),
                  naturalSize: CGSize(width: try c.decode(Double.self, forKey: .naturalWidth),
                                      height: try c.decode(Double.self, forKey: .naturalHeight)),
                  preferredTransform: transform,
                  hasAudio: try c.decodeIfPresent(Bool.self, forKey: .hasAudio) ?? true,
                  start: Timeline.time(try c.decode(Double.self, forKey: .start)),
                  end: Timeline.time(try c.decode(Double.self, forKey: .end)))
        transitionOut = (try? c.decodeIfPresent(TransitionType.self, forKey: .transitionOut)) ?? TransitionType.none
        transitionDuration = try c.decodeIfPresent(Double.self, forKey: .transitionDuration) ?? 0.6
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        let t = preferredTransform
        try c.encode(id, forKey: .id)
        try c.encode(MediaReference.encode(url), forKey: .file)
        try c.encode(name, forKey: .name)
        try c.encode(assetDuration.seconds, forKey: .assetDuration)
        try c.encode(Double(naturalSize.width), forKey: .naturalWidth)
        try c.encode(Double(naturalSize.height), forKey: .naturalHeight)
        try c.encode([t.a, t.b, t.c, t.d, t.tx, t.ty].map { Double($0) }, forKey: .transform)
        try c.encode(hasAudio, forKey: .hasAudio)
        try c.encode(start.seconds, forKey: .start)
        try c.encode(end.seconds, forKey: .end)
        try c.encode(transitionOut, forKey: .transitionOut)
        try c.encode(transitionDuration, forKey: .transitionDuration)
    }
}

// MARK: - Texto

extension TextOverlay: Codable {
    enum CodingKeys: String, CodingKey {
        case id, text, start, duration, fontSize, color, x, y, hasBackground, isCaption
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        var t = TextOverlay()
        t.id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        t.text = try c.decodeIfPresent(String.self, forKey: .text) ?? t.text
        t.start = try c.decodeIfPresent(Double.self, forKey: .start) ?? t.start
        t.duration = try c.decodeIfPresent(Double.self, forKey: .duration) ?? t.duration
        t.fontSize = try c.decodeIfPresent(Double.self, forKey: .fontSize) ?? t.fontSize
        t.color = (try? c.decodeIfPresent(TextColor.self, forKey: .color)) ?? t.color
        t.position = CGPoint(x: try c.decodeIfPresent(Double.self, forKey: .x) ?? Double(t.position.x),
                             y: try c.decodeIfPresent(Double.self, forKey: .y) ?? Double(t.position.y))
        t.hasBackground = try c.decodeIfPresent(Bool.self, forKey: .hasBackground) ?? false
        t.isCaption = try c.decodeIfPresent(Bool.self, forKey: .isCaption) ?? false
        self = t
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(text, forKey: .text)
        try c.encode(start, forKey: .start)
        try c.encode(duration, forKey: .duration)
        try c.encode(fontSize, forKey: .fontSize)
        try c.encode(color, forKey: .color)
        try c.encode(Double(position.x), forKey: .x)
        try c.encode(Double(position.y), forKey: .y)
        try c.encode(hasBackground, forKey: .hasBackground)
        try c.encode(isCaption, forKey: .isCaption)
    }
}

// MARK: - Pista de audio

extension AudioTrack: Codable {
    enum CodingKeys: String, CodingKey {
        case id, file, name, assetDuration, kind, start, volume, sourceOffset, fadeIn, fadeOut, loops, ducking
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(id: try c.decode(UUID.self, forKey: .id),
                  url: try MediaReference.decode(try c.decode(String.self, forKey: .file)),
                  name: try c.decodeIfPresent(String.self, forKey: .name) ?? "Audio",
                  assetDuration: Timeline.time(try c.decode(Double.self, forKey: .assetDuration)))
        kind = (try? c.decodeIfPresent(AudioKind.self, forKey: .kind)) ?? .music
        start = try c.decodeIfPresent(Double.self, forKey: .start) ?? 0
        volume = try c.decodeIfPresent(Float.self, forKey: .volume) ?? 1
        sourceOffset = try c.decodeIfPresent(Double.self, forKey: .sourceOffset) ?? 0
        fadeIn = try c.decodeIfPresent(Double.self, forKey: .fadeIn) ?? 0
        fadeOut = try c.decodeIfPresent(Double.self, forKey: .fadeOut) ?? 0
        loops = try c.decodeIfPresent(Bool.self, forKey: .loops) ?? false
        ducking = try c.decodeIfPresent(Bool.self, forKey: .ducking) ?? true
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(MediaReference.encode(url), forKey: .file)
        try c.encode(name, forKey: .name)
        try c.encode(assetDuration.seconds, forKey: .assetDuration)
        try c.encode(kind, forKey: .kind)
        try c.encode(start, forKey: .start)
        try c.encode(volume, forKey: .volume)
        try c.encode(sourceOffset, forKey: .sourceOffset)
        try c.encode(fadeIn, forKey: .fadeIn)
        try c.encode(fadeOut, forKey: .fadeOut)
        try c.encode(loops, forKey: .loops)
        try c.encode(ducking, forKey: .ducking)
    }
}
