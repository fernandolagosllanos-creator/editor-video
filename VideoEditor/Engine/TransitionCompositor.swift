import Foundation
import AVFoundation
import CoreImage
import CoreVideo

/// Cómo dibujar una pista: tamaño natural y rotación del archivo original.
struct ClipLayout {
    let trackID: CMPersistentTrackID
    let naturalSize: CGSize
    let preferredTransform: CGAffineTransform
}

/// Instrucción de composición: un clip en primer plano, opcionalmente otro de fondo con el que
/// se hace la transición, y el filtro de color global.
final class TransitionInstruction: NSObject, AVVideoCompositionInstructionProtocol, @unchecked Sendable {
    let timeRange: CMTimeRange
    let enablePostProcessing: Bool = false
    let containsTweening: Bool = true
    let requiredSourceTrackIDs: [NSValue]?
    let passthroughTrackID: CMPersistentTrackID = kCMPersistentTrackID_Invalid

    let foreground: ClipLayout
    let background: ClipLayout?
    let transition: TransitionType
    let filter: VideoFilter

    init(timeRange: CMTimeRange, foreground: ClipLayout, background: ClipLayout?, transition: TransitionType, filter: VideoFilter) {
        self.timeRange = timeRange
        self.foreground = foreground
        self.background = background
        self.transition = transition
        self.filter = filter
        var ids: [NSValue] = [NSNumber(value: foreground.trackID)]
        if let background { ids.append(NSNumber(value: background.trackID)) }
        self.requiredSourceTrackIDs = ids
        super.init()
    }
}

enum CompositorError: Error {
    case badInstruction
    case noOutputBuffer
}

/// Compositor personalizado: rota y encaja cada cuadro, mezcla dos pistas durante una transición y
/// aplica el filtro de color. Se usa tanto para la vista previa como para la exportación.
final class TransitionCompositor: NSObject, AVVideoCompositing {
    private let ciContext = CIContext(options: [.cacheIntermediates: false])
    private let colorSpace = CGColorSpaceCreateDeviceRGB()

    let sourcePixelBufferAttributes: [String: any Sendable]? = [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferIOSurfacePropertiesKey as String: [String: String]()
    ]

    let requiredPixelBufferAttributesForRenderContext: [String: any Sendable] = [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferIOSurfacePropertiesKey as String: [String: String]()
    ]

    func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {}

    func cancelAllPendingVideoCompositionRequests() {}

    func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
        autoreleasepool {
            guard let instruction = request.videoCompositionInstruction as? TransitionInstruction else {
                request.finish(with: CompositorError.badInstruction)
                return
            }
            guard let output = request.renderContext.newPixelBuffer() else {
                request.finish(with: CompositorError.noOutputBuffer)
                return
            }

            let renderSize = request.renderContext.size
            let renderRect = CGRect(origin: .zero, size: renderSize)
            let black = CIImage(color: .black).cropped(to: renderRect)

            var image = black
            if let fgBuffer = request.sourceFrame(byTrackID: instruction.foreground.trackID) {
                image = Self.fit(fgBuffer, layout: instruction.foreground, into: renderSize)
            }

            if let bgLayout = instruction.background,
               let bgBuffer = request.sourceFrame(byTrackID: bgLayout.trackID) {
                let bgImage = Self.fit(bgBuffer, layout: bgLayout, into: renderSize)
                let progress = Self.progress(of: request.compositionTime, in: instruction.timeRange)
                image = Self.blend(foreground: image, background: bgImage, transition: instruction.transition,
                                   progress: progress, renderRect: renderRect)
            }

            image = instruction.filter.apply(to: image)
                .cropped(to: renderRect)
                .composited(over: black)

            ciContext.render(image, to: output, bounds: renderRect, colorSpace: colorSpace)
            request.finish(withComposedVideoFrame: output)
        }
    }

    // MARK: - Helpers

    private static func progress(of time: CMTime, in range: CMTimeRange) -> CGFloat {
        guard range.duration.seconds > 0 else { return 1 }
        let p = (time - range.start).seconds / range.duration.seconds
        let clamped = CGFloat(min(max(p, 0), 1))
        // Suavizado (ease in-out) para que la transición se sienta natural.
        return clamped * clamped * (3 - 2 * clamped)
    }

    /// Convierte el cuadro a CIImage, aplica la rotación del archivo y lo encaja (aspect fit) en el
    /// tamaño de salida, centrado.
    static func fit(_ buffer: CVPixelBuffer, layout: ClipLayout, into renderSize: CGSize) -> CIImage {
        var image = CIImage(cvPixelBuffer: buffer)
        let natural = image.extent.size

        // preferredTransform está definido con el eje Y hacia abajo (coordenadas de video);
        // Core Image usa Y hacia arriba, así que se conjuga con un volteo vertical.
        let display = CGRect(origin: .zero, size: natural).applying(layout.preferredTransform)
        let displaySize = CGSize(width: abs(display.width), height: abs(display.height))
        let flipNatural = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: natural.height)
        let flipDisplay = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: displaySize.height)
        let transform = flipNatural.concatenating(layout.preferredTransform).concatenating(flipDisplay)
        image = image.transformed(by: transform)
        // Normaliza el origen a (0,0) por si la transformación dejó un desplazamiento.
        image = image.transformed(by: CGAffineTransform(translationX: -image.extent.origin.x, y: -image.extent.origin.y))

        let scale = min(renderSize.width / displaySize.width, renderSize.height / displaySize.height)
        let scaled = CGSize(width: displaySize.width * scale, height: displaySize.height * scale)
        let tx = (renderSize.width - scaled.width) / 2
        let ty = (renderSize.height - scaled.height) / 2
        image = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        image = image.transformed(by: CGAffineTransform(translationX: tx, y: ty))
        return image.cropped(to: CGRect(origin: .zero, size: renderSize))
    }

    private static func alpha(_ image: CIImage, _ a: CGFloat) -> CIImage {
        image.applyingFilter("CIColorMatrix", parameters: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: a)])
    }

    private static func scaled(_ image: CIImage, by s: CGFloat, around center: CGPoint) -> CIImage {
        let t = CGAffineTransform(translationX: center.x, y: center.y)
            .scaledBy(x: s, y: s)
            .translatedBy(x: -center.x, y: -center.y)
        return image.transformed(by: t)
    }

    static func blend(foreground fg: CIImage, background bg: CIImage, transition: TransitionType,
                      progress p: CGFloat, renderRect: CGRect) -> CIImage {
        let black = CIImage(color: .black).cropped(to: renderRect)
        let w = renderRect.width
        let center = CGPoint(x: renderRect.midX, y: renderRect.midY)

        switch transition {
        case .none:
            return fg
        case .crossfade:
            return alpha(fg, p).composited(over: bg)
        case .fadeBlack:
            if p < 0.5 {
                return alpha(bg, 1 - p * 2).composited(over: black)
            } else {
                return alpha(fg, (p - 0.5) * 2).composited(over: black)
            }
        case .slideLeft:
            let fgMoved = fg.transformed(by: CGAffineTransform(translationX: (1 - p) * w, y: 0))
            let bgMoved = bg.transformed(by: CGAffineTransform(translationX: -p * w, y: 0))
            return fgMoved.composited(over: bgMoved.composited(over: black))
        case .zoom:
            let bgZoom = alpha(scaled(bg, by: 1 + 0.4 * p, around: center), 1 - p)
            let fgZoom = alpha(scaled(fg, by: 1.3 - 0.3 * p, around: center), p)
            return fgZoom.composited(over: bgZoom.composited(over: black))
        case .wipe:
            let reveal = CGRect(x: 0, y: 0, width: w * p, height: renderRect.height)
            return fg.cropped(to: reveal).composited(over: bg)
        }
    }
}
