import Foundation
import AVFoundation
import CoreGraphics
#if os(iOS)
import Photos
#endif

// MARK: - Opciones de exportación

enum ExportContainer: String, CaseIterable, Identifiable {
    case mp4, mov

    var id: String { rawValue }
    var label: String {
        switch self {
        case .mp4: return "MP4"
        case .mov: return "MOV (QuickTime)"
        }
    }
    var fileType: AVFileType { self == .mp4 ? .mp4 : .mov }
    var fileExtension: String { rawValue }
}

enum ExportCodec: String, CaseIterable, Identifiable {
    case h264, hevc

    var id: String { rawValue }
    var label: String {
        switch self {
        case .h264: return "H.264 (compatible con todo)"
        case .hevc: return "HEVC / H.265 (más liviano)"
        }
    }
}

enum ExportResolution: String, CaseIterable, Identifiable {
    case original, p480, p720, p1080, p2160

    var id: String { rawValue }
    var label: String {
        switch self {
        case .original: return "Original"
        case .p480: return "480p (SD)"
        case .p720: return "720p (HD)"
        case .p1080: return "1080p (Full HD)"
        case .p2160: return "2160p (4K)"
        }
    }

    /// Lado corto objetivo (la orientación se conserva).
    var shortSide: CGFloat? {
        switch self {
        case .original: return nil
        case .p480: return 480
        case .p720: return 720
        case .p1080: return 1080
        case .p2160: return 2160
        }
    }
}

enum ExportQuality: String, CaseIterable, Identifiable {
    case high, medium, low

    var id: String { rawValue }
    var label: String {
        switch self {
        case .high: return "Alta"
        case .medium: return "Media"
        case .low: return "Baja (archivo pequeño)"
        }
    }
}

struct ExportSettings {
    var container: ExportContainer = .mp4
    var codec: ExportCodec = .h264
    var resolution: ExportResolution = .original
    var quality: ExportQuality = .high

    /// Tamaño de salida a partir del tamaño original, manteniendo la proporción.
    func outputSize(from original: CGSize) -> CGSize {
        guard let target = resolution.shortSide else { return original }
        let short = min(original.width, original.height)
        let scale = target / short
        let w = floor(original.width * scale / 2) * 2
        let h = floor(original.height * scale / 2) * 2
        return CGSize(width: w, height: h)
    }

    /// Preset de AVAssetExportSession que mejor corresponde a códec + calidad + resolución.
    var presetName: String {
        switch codec {
        case .hevc:
            switch resolution {
            case .p2160: return AVAssetExportPresetHEVC3840x2160
            case .p1080: return AVAssetExportPresetHEVC1920x1080
            default: return AVAssetExportPresetHEVCHighestQuality
            }
        case .h264:
            switch quality {
            case .low: return AVAssetExportPresetLowQuality
            case .medium: return AVAssetExportPresetMediumQuality
            case .high:
                switch resolution {
                case .p480: return AVAssetExportPreset640x480
                case .p720: return AVAssetExportPreset1280x720
                case .p1080: return AVAssetExportPreset1920x1080
                case .p2160: return AVAssetExportPreset3840x2160
                case .original: return AVAssetExportPresetHighestQuality
                }
            }
        }
    }
}

enum ExportError: LocalizedError {
    case cannotCreateSession
    case failed(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .cannotCreateSession: return "No se pudo iniciar la exportación con ese formato en este dispositivo."
        case .failed(let msg): return "La exportación falló: \(msg)"
        case .cancelled: return "Exportación cancelada."
        }
    }
}

// MARK: - Exportador

enum Exporter {
    /// Exporta la composición y devuelve la URL del archivo generado (en la carpeta temporal).
    static func export(_ built: BuiltComposition,
                       settings: ExportSettings,
                       progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        var preset = settings.presetName
        let compatible = AVAssetExportSession.allExportPresets()
        if !compatible.contains(preset) {
            preset = settings.codec == .hevc ? AVAssetExportPresetHEVCHighestQuality : AVAssetExportPresetHighestQuality
        }
        guard let session = AVAssetExportSession(asset: built.composition, presetName: preset) else {
            throw ExportError.cannotCreateSession
        }

        let stamp = Int(Date().timeIntervalSince1970)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("video-\(stamp)")
            .appendingPathExtension(settings.container.fileExtension)
        try? FileManager.default.removeItem(at: url)

        session.videoComposition = built.videoComposition
        session.audioMix = built.audioMix
        // Conserva el tono de la voz en los clips con velocidad cambiada.
        session.audioTimePitchAlgorithm = .spectral
        session.shouldOptimizeForNetworkUse = true

        if #available(iOS 18.0, macOS 15.0, *) {
            let monitor = Task {
                for await state in session.states(updateInterval: 0.25) {
                    if case .exporting(let p) = state { progress(p.fractionCompleted) }
                }
            }
            defer { monitor.cancel() }
            try await session.export(to: url, as: settings.container.fileType)
        } else {
            session.outputURL = url
            session.outputFileType = settings.container.fileType
            let monitor = Task {
                while !Task.isCancelled {
                    progress(Double(session.progress))
                    try? await Task.sleep(nanoseconds: 250_000_000)
                }
            }
            defer { monitor.cancel() }
            await session.export()
            switch session.status {
            case .completed: break
            case .cancelled: throw ExportError.cancelled
            default: throw ExportError.failed(session.error?.localizedDescription ?? "error desconocido")
            }
        }
        progress(1)
        return url
    }

    #if os(iOS)
    /// Guarda el archivo en la biblioteca de Fotos del iPhone.
    static func saveToPhotos(_ url: URL) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            throw ExportError.failed("Sin permiso para guardar en Fotos. Revísalo en Ajustes > Privacidad > Fotos.")
        }
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
        }
    }
    #endif
}
