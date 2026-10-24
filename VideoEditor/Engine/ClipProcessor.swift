import Foundation
import AVFoundation
import CoreGraphics
import CoreVideo

enum ClipProcessorError: LocalizedError {
    case noVideo
    case cannotRead
    case cannotWrite(String)

    var errorDescription: String? {
        switch self {
        case .noVideo: return "El archivo no contiene video."
        case .cannotRead: return "No se pudo leer el video."
        case .cannotWrite(let msg): return "No se pudo crear el video: \(msg)"
        }
    }
}

/// Genera archivos auxiliares: la copia invertida de un video (para la reversa) y los clips de
/// imagen fija (para congelar un fotograma). Todo queda en la carpeta de la app (MediaStore).
enum ClipProcessor {

    // MARK: - Reversa

    /// Devuelve una copia del video completo reproducida al revés (sin audio). Si ya existe, la
    /// reutiliza. En la copia, el segundo x del original queda en (duración - x).
    static func reversedCopy(of url: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        let dest = MediaStore.directory
            .appendingPathComponent(url.deletingPathExtension().lastPathComponent + "-reversa")
            .appendingPathExtension("mov")
        if FileManager.default.fileExists(atPath: dest.path) { return dest }

        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else { throw ClipProcessorError.noVideo }
        let duration = try await asset.load(.duration)
        let (natural, transform, nominalFPS) = try await track.load(.naturalSize, .preferredTransform, .nominalFrameRate)
        let fps = Double(nominalFPS > 0 ? nominalFPS : 30)

        let temp = MediaStore.directory.appendingPathComponent(UUID().uuidString).appendingPathExtension("mov")
        let writer = try AVAssetWriter(outputURL: temp, fileType: .mov)
        let width = Int(natural.width), height = Int(natural.height)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: max(4_000_000, width * height * 6)]
        ])
        input.expectsMediaDataInRealTime = false
        input.transform = transform
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: nil)
        guard writer.canAdd(input) else { throw ClipProcessorError.cannotWrite("formato no compatible") }
        writer.add(input)
        guard writer.startWriting() else {
            throw ClipProcessorError.cannotWrite(writer.error?.localizedDescription ?? "error desconocido")
        }
        writer.startSession(atSourceTime: .zero)

        // Se lee el video por tramos cortos desde el final hacia el inicio, y cada tramo se escribe
        // al revés. Así nunca hay más de unos pocos cuadros en memoria (menos aún si es 4K).
        let framesPerSegment: Double = width * height > 2_300_000 ? 12 : 30
        let segment = CMTime(seconds: framesPerSegment / fps, preferredTimescale: 600)
        var segmentEnd = duration
        var lastPTS: CMTime?          // tiempo (en el original) del último cuadro del video
        var lastWritten = CMTime.negativeInfinity

        do {
            while segmentEnd > .zero {
                try Task.checkCancellation()
                let segmentStart = max(.zero, segmentEnd - segment)
                let reader = try AVAssetReader(asset: asset)
                let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
                    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
                ])
                output.alwaysCopiesSampleData = true
                guard reader.canAdd(output) else { throw ClipProcessorError.cannotRead }
                reader.add(output)
                reader.timeRange = CMTimeRange(start: segmentStart, end: segmentEnd)
                guard reader.startReading() else { throw ClipProcessorError.cannotRead }

                var frames: [(CMTime, CVPixelBuffer)] = []
                while let sample = output.copyNextSampleBuffer() {
                    let pts = CMSampleBufferGetPresentationTimeStamp(sample)
                    // Cada cuadro pertenece a un solo tramo: [inicio, fin).
                    guard pts >= segmentStart, pts < segmentEnd,
                          let buffer = CMSampleBufferGetImageBuffer(sample) else { continue }
                    frames.append((pts, buffer))
                }
                reader.cancelReading()

                for (pts, buffer) in frames.sorted(by: { $0.0 > $1.0 }) {
                    if lastPTS == nil { lastPTS = pts }
                    let newTime = lastPTS! - pts
                    guard newTime > lastWritten else { continue }
                    while !input.isReadyForMoreMediaData {
                        try await Task.sleep(nanoseconds: 3_000_000)
                    }
                    guard adaptor.append(buffer, withPresentationTime: newTime) else {
                        throw ClipProcessorError.cannotWrite(writer.error?.localizedDescription ?? "error al escribir")
                    }
                    lastWritten = newTime
                }

                segmentEnd = segmentStart
                if duration.seconds > 0 { progress(1 - segmentEnd.seconds / duration.seconds) }
            }
        } catch {
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: temp)
            throw error
        }

        input.markAsFinished()
        writer.endSession(atSourceTime: duration)
        await writer.finishWriting()
        guard writer.status == .completed else {
            try? FileManager.default.removeItem(at: temp)
            throw ClipProcessorError.cannotWrite(writer.error?.localizedDescription ?? "error desconocido")
        }
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.moveItem(at: temp, to: dest)
        progress(1)
        return dest
    }

    // MARK: - Congelar fotograma

    /// Crea un video de `seconds` segundos que muestra siempre la misma imagen.
    static func stillVideo(from image: CGImage, seconds: Double) async throws -> URL {
        let url = MediaStore.makeURL(ext: "mov")
        // Dimensiones pares (requisito de H.264).
        let width = max(2, image.width / 2 * 2), height = max(2, image.height / 2 * 2)
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height
        ])
        guard writer.canAdd(input) else { throw ClipProcessorError.cannotWrite("formato no compatible") }
        writer.add(input)
        guard writer.startWriting() else {
            throw ClipProcessorError.cannotWrite(writer.error?.localizedDescription ?? "error desconocido")
        }
        writer.startSession(atSourceTime: .zero)

        guard let buffer = makePixelBuffer(from: image, width: width, height: height) else {
            writer.cancelWriting()
            throw ClipProcessorError.cannotWrite("no se pudo preparar la imagen")
        }
        let total = CMTime(seconds: seconds, preferredTimescale: 600)
        // Un cuadro al inicio y otro justo antes del final: el reproductor mantiene la imagen entre ambos.
        for time in [CMTime.zero, total - CMTime(value: 1, timescale: 30)] {
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 3_000_000)
            }
            _ = adaptor.append(buffer, withPresentationTime: time)
        }
        input.markAsFinished()
        writer.endSession(atSourceTime: total)
        await writer.finishWriting()
        guard writer.status == .completed else {
            throw ClipProcessorError.cannotWrite(writer.error?.localizedDescription ?? "error desconocido")
        }
        return url
    }

    private static func makePixelBuffer(from image: CGImage, width: Int, height: Int) -> CVPixelBuffer? {
        var buffer: CVPixelBuffer?
        let attrs: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
        ]
        guard CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA,
                                  attrs as CFDictionary, &buffer) == kCVReturnSuccess,
              let buffer else { return nil }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let context = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return buffer
    }
}
