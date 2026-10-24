import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import Observation

/// Resumen de un proyecto guardado, para la galería.
struct ProjectSummary: Identifiable, Hashable {
    let id: UUID
    var name: String
    var createdAt: Date
    var modifiedAt: Date
    var duration: Double
    var thumbnailURL: URL?
}

/// Proyectos guardados en el dispositivo (carpeta `Application Support/VideoEditor/Projects`).
/// Cada proyecto es una carpeta con `project.json` y `thumbnail.jpg`. Todo es local y gratuito.
@MainActor
@Observable
final class ProjectStore {
    static let shared = ProjectStore()

    /// Más recientes primero.
    private(set) var projects: [ProjectSummary] = []

    /// Lo asigna el editor: se llama cuando se borra un proyecto (por si es el que está abierto).
    var didDelete: (@MainActor (UUID) -> Void)?
    /// Lo asigna el editor: archivos de MediaStore que usa el proyecto abierto y no se deben borrar.
    var filesInUse: @MainActor () -> Set<String> = { [] }

    private init() {
        refresh()
    }

    // MARK: - Rutas

    nonisolated static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("VideoEditor/Projects", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    nonisolated static func folder(for id: UUID) -> URL {
        directory.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    nonisolated static func fileURL(for id: UUID) -> URL {
        folder(for: id).appendingPathComponent("project.json")
    }

    nonisolated static func thumbnailURL(for id: UUID) -> URL {
        folder(for: id).appendingPathComponent("thumbnail.jpg")
    }

    nonisolated static func exists(_ id: UUID) -> Bool {
        FileManager.default.fileExists(atPath: fileURL(for: id).path)
    }

    // MARK: - Lista

    func refresh() {
        let fm = FileManager.default
        let folders = (try? fm.contentsOfDirectory(at: Self.directory, includingPropertiesForKeys: nil)) ?? []
        var list: [ProjectSummary] = []
        for folder in folders {
            guard let id = UUID(uuidString: folder.lastPathComponent),
                  let data = try? Data(contentsOf: Self.fileURL(for: id)),
                  let header = try? JSONDecoder.project.decode(ProjectHeader.self, from: data)
            else { continue }
            let thumb = Self.thumbnailURL(for: id)
            list.append(ProjectSummary(id: id,
                                       name: header.name ?? "Proyecto",
                                       createdAt: header.createdAt ?? Date(),
                                       modifiedAt: header.modifiedAt ?? header.createdAt ?? Date(),
                                       duration: header.duration ?? 0,
                                       thumbnailURL: fm.fileExists(atPath: thumb.path) ? thumb : nil))
        }
        projects = list.sorted { $0.modifiedAt > $1.modifiedAt }
    }

    // MARK: - Guardar / abrir

    /// Escribe el proyecto y su miniatura. Se puede llamar desde cualquier hilo.
    nonisolated static func write(_ file: ProjectFile, thumbnail: CGImage?) throws {
        try FileManager.default.createDirectory(at: folder(for: file.id), withIntermediateDirectories: true)
        let data = try JSONEncoder.project.encode(file)
        try data.write(to: fileURL(for: file.id), options: .atomic)
        if let thumbnail {
            writeJPEG(thumbnail, to: thumbnailURL(for: file.id))
        }
    }

    nonisolated static func read(_ id: UUID) throws -> ProjectFile {
        let data = try Data(contentsOf: fileURL(for: id))
        return try JSONDecoder.project.decode(ProjectFile.self, from: data)
    }

    // MARK: - Acciones de la galería

    func rename(id: UUID, to name: String) {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        editJSON(id) { json in json["name"] = clean }
        refresh()
    }

    /// Crea una copia del proyecto y devuelve su id. Los archivos de video y audio se comparten.
    @discardableResult
    func duplicate(id: UUID) -> UUID? {
        let newID = UUID()
        let fm = FileManager.default
        do {
            try fm.copyItem(at: Self.folder(for: id), to: Self.folder(for: newID))
        } catch {
            return nil
        }
        let now = Self.isoString(Date())
        editJSON(newID) { json in
            json["id"] = newID.uuidString
            json["name"] = "\(json["name"] as? String ?? "Proyecto") (copia)"
            json["createdAt"] = now
            json["modifiedAt"] = now
        }
        refresh()
        return newID
    }

    func delete(id: UUID) {
        let fm = FileManager.default
        let doomed = Self.mediaFiles(in: id)
        try? fm.removeItem(at: Self.folder(for: id))
        // Se borran los videos y audios que ya no usa ningún otro proyecto.
        var stillUsed = filesInUse()
        for p in projects where p.id != id {
            stillUsed.formUnion(Self.mediaFiles(in: p.id))
        }
        for name in doomed.subtracting(stillUsed) {
            try? fm.removeItem(at: MediaStore.directory.appendingPathComponent(name))
        }
        didDelete?(id)
        refresh()
    }

    // MARK: - Utilidades

    /// Nombres de archivo de MediaStore que usa un proyecto guardado (busca cualquier campo "file").
    nonisolated static func mediaFiles(in id: UUID) -> Set<String> {
        guard let data = try? Data(contentsOf: fileURL(for: id)),
              let json = try? JSONSerialization.jsonObject(with: data)
        else { return [] }
        var out: Set<String> = []
        func walk(_ value: Any) {
            if let dict = value as? [String: Any] {
                for (k, v) in dict {
                    if k == "file", let s = v as? String { out.insert(s) } else { walk(v) }
                }
            } else if let array = value as? [Any] {
                array.forEach(walk)
            }
        }
        walk(json)
        return out
    }

    /// Edita el JSON conservando los campos que esta versión de la app no conoce.
    private func editJSON(_ id: UUID, _ change: (inout [String: Any]) -> Void) {
        let url = Self.fileURL(for: id)
        guard let data = try? Data(contentsOf: url),
              var json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return }
        change(&json)
        if let out = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted]) {
            try? out.write(to: url, options: .atomic)
        }
    }

    nonisolated static func isoString(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    nonisolated static func writeJPEG(_ image: CGImage, to url: URL) {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
        CGImageDestinationFinalize(dest)
    }
}

/// Solo los datos necesarios para la galería (no hace falta leer los clips).
private struct ProjectHeader: Decodable {
    var name: String?
    var createdAt: Date?
    var modifiedAt: Date?
    var duration: Double?
}

extension JSONEncoder {
    static var project: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }
}

extension JSONDecoder {
    static var project: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
