import Foundation
import AVFoundation
import CoreGraphics
import CoreTransferable
import UniformTypeIdentifiers

/// Copia los archivos importados a una carpeta propia de la app para no depender de permisos
/// temporales (security-scoped URLs) ni de archivos que el usuario pueda mover.
enum MediaStore {
    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("VideoEditor/Media", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func makeURL(ext: String) -> URL {
        directory.appendingPathComponent(UUID().uuidString).appendingPathExtension(ext.isEmpty ? "mov" : ext)
    }

    /// Copia un archivo elegido por el usuario (Finder / Archivos) dentro de la app.
    static func importCopy(from url: URL) throws -> URL {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let dest = makeURL(ext: url.pathExtension)
        try FileManager.default.copyItem(at: url, to: dest)
        return dest
    }
}

/// Permite recibir videos desde el selector de Fotos (PhotosPicker).
struct MovieFile: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let dest = MediaStore.makeURL(ext: received.file.pathExtension)
            try FileManager.default.copyItem(at: received.file, to: dest)
            return MovieFile(url: dest)
        }
    }
}

enum Thumbnails {
    static func generate(asset: AVAsset, duration: CMTime, count: Int) async -> [CGImage] {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 180, height: 180)
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.5, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.5, preferredTimescale: 600)
        var images: [CGImage] = []
        for i in 0..<count {
            let seconds = duration.seconds * (Double(i) + 0.5) / Double(count)
            let time = CMTime(seconds: seconds, preferredTimescale: 600)
            if let result = try? await generator.image(at: time) {
                images.append(result.image)
            }
        }
        return images
    }
}
