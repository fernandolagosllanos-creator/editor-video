import Foundation
import AVFoundation
import CoreImage
import CoreImage.CIFilterBuiltins
import CoreVideo

/// Cómo dibujar una pista: tamaño natural y rotación del archivo original, más el color y el
/// encuadre del clip.
struct ClipLayout {
    let trackID: CMPersistentTrackID
    let naturalSize: CGSize
    let preferredTransform: CGAffineTransform
    var look = ColorLook()
    var framing = ClipFraming()
}

/// Instrucción de composición: un clip en primer plano, opcionalmente otro de fondo con el que
/// se hace la transición, y el fondo del lienzo.
final class TransitionInstruction: NSObject, AVVideoCompositionInstructionProtocol, @unchecked Sendable {
    let timeRange: CMTimeRange
    let enablePostProcessing: Bool = false
    let containsTweening: Bool = true
    let requiredSourceTrackIDs: [NSValue]?
    let passthroughTrackID: CMPersistentTrackID = kCMPersistentTrackID_Invalid

    let foreground: ClipLayout
    let background: ClipLayout?
    let transition: TransitionType
    let canvas: CanvasBackground

    init(timeRange: CMTimeRange, foreground: ClipLayout, background: ClipLayout?, transition: TransitionType,
         canvas: CanvasBackground) {
        self.timeRange = timeRange
        self.foreground = foreground
        self.background = background
        self.transition = transition
        self.canvas = canvas
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

/// Compositor personalizado: rota y encuadra cada cuadro, le aplica su color, mezcla dos pistas
/// durante una transición. Se usa tanto para la vista previa como para la exportación.
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
                image = Self.render(fgBuffer, layout: instruction.foreground, into: renderSize,
                                    canvas: instruction.canvas)
            }

            if let bgLayout = instruction.background,
               let bgBuffer = request.sourceFrame(byTrackID: bgLayout.trackID) {
                let bgImage = Self.render(bgBuffer, layout: bgLayout, into: renderSize, canvas: instruction.canvas)
                let progress = Self.progress(of: request.compositionTime, in: instruction.timeRange)
                image = Self.blend(foreground: image, background: bgImage, transition: instruction.transition,
                                   progress: progress, renderRect: renderRect)
            }

            image = image
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

    /// Cuadro listo para el lienzo: orientado, con su color y encuadre, sobre el fondo elegido.
    static func render(_ buffer: CVPixelBuffer, layout: ClipLayout, into renderSize: CGSize,
                       canvas: CanvasBackground) -> CIImage {
        let oriented = orient(buffer, layout: layout)
        return FrameRenderer.compose(oriented, look: layout.look, framing: layout.framing,
                                     canvas: canvas, renderSize: renderSize)
    }

    /// Convierte el cuadro a CIImage y aplica la rotación del archivo (origen en 0,0).
    static func orient(_ buffer: CVPixelBuffer, layout: ClipLayout) -> CIImage {
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
        return image
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
        case .slideUp:
            // Core Image tiene la Y hacia arriba: "abajo" es la Y negativa.
            let h = renderRect.height
            let fgMoved = fg.transformed(by: CGAffineTransform(translationX: 0, y: -(1 - p) * h))
            let bgMoved = bg.transformed(by: CGAffineTransform(translationX: 0, y: p * h))
            return fgMoved.composited(over: bgMoved.composited(over: black))
        case .iris:
            let radius = hypot(renderRect.width, renderRect.height) / 2 * p
            let mask = CIFilter.radialGradient()
            mask.center = center
            mask.radius0 = Float(max(0, radius - 1.5))
            mask.radius1 = Float(radius + 1.5)
            mask.color0 = CIColor.white
            mask.color1 = CIColor.black
            let blend = CIFilter.blendWithMask()
            blend.inputImage = fg
            blend.backgroundImage = bg
            blend.maskImage = mask.outputImage?.cropped(to: renderRect)
            return blend.outputImage?.cropped(to: renderRect) ?? fg
        }
    }
}

// MARK: - Color + encuadre (compartido con las vistas previas de las hojas)

enum FrameRenderer {
    /// Contexto compartido para las miniaturas y vistas previas de las hojas de efectos.
    static let previewContext = CIContext(options: [.cacheIntermediates: false])

    /// Aplica el color del clip, lo ubica en el lienzo según su encuadre y rellena lo que quede
    /// libre con el fondo. `image` debe venir ya orientada y con origen en (0,0).
    static func compose(_ image: CIImage, look: ColorLook, framing: ClipFraming,
                        canvas: CanvasBackground, renderSize: CGSize) -> CIImage {
        let rect = CGRect(origin: .zero, size: renderSize)
        var img = look.apply(to: image)
        let src = img.extent.size
        guard src.width > 0, src.height > 0 else { return CIImage(color: .black).cropped(to: rect) }

        if framing.mirrored {
            img = img.transformed(by: CGAffineTransform(scaleX: -1, y: 1).translatedBy(x: -src.width, y: 0))
        }

        let fitScale = min(renderSize.width / src.width, renderSize.height / src.height)
        let fillScale = max(renderSize.width / src.width, renderSize.height / src.height)
        let scale = (framing.mode == .fit ? fitScale : fillScale) * CGFloat(max(0.2, framing.zoom))
        let scaled = CGSize(width: src.width * scale, height: src.height * scale)
        // offset.y es positivo hacia abajo (como en pantalla); Core Image tiene la Y hacia arriba.
        let tx = (renderSize.width - scaled.width) / 2 + framing.offset.x * renderSize.width
        let ty = (renderSize.height - scaled.height) / 2 - framing.offset.y * renderSize.height
        let placed = img
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            .transformed(by: CGAffineTransform(translationX: tx, y: ty))

        // Si el clip ya cubre todo el lienzo no hace falta dibujar fondo.
        if placed.extent.insetBy(dx: 0.5, dy: 0.5).contains(rect) {
            return placed.cropped(to: rect)
        }
        return placed.composited(over: background(for: img, canvas: canvas, rect: rect)).cropped(to: rect)
    }

    /// Fondo del lienzo. El desenfoque usa el mismo cuadro ampliado y difuminado (se calcula a
    /// baja resolución para que sea rápido).
    static func background(for image: CIImage, canvas: CanvasBackground, rect: CGRect) -> CIImage {
        guard canvas == .blur else {
            let c = canvas.rgb
            return CIImage(color: CIColor(red: c.0, green: c.1, blue: c.2)).cropped(to: rect)
        }
        let src = image.extent.size
        let down: CGFloat = 0.125
        let cover = max(rect.width / src.width, rect.height / src.height) * 1.15 * down
        let small = CGSize(width: rect.width * down, height: rect.height * down)
        let tx = (small.width - src.width * cover) / 2
        let ty = (small.height - src.height * cover) / 2
        let smallRect = CGRect(origin: .zero, size: small)
        let blurred = image
            .transformed(by: CGAffineTransform(scaleX: cover, y: cover))
            .transformed(by: CGAffineTransform(translationX: tx, y: ty))
            .clampedToExtent()
            .applyingGaussianBlur(sigma: 5)
            .cropped(to: smallRect)
            .applyingFilter("CIColorControls", parameters: [kCIInputBrightnessKey: -0.08,
                                                            kCIInputSaturationKey: 1.1])
            .clampedToExtent()
            .transformed(by: CGAffineTransform(scaleX: 1 / down, y: 1 / down))
            .cropped(to: rect)
        return blurred.composited(over: CIImage(color: .black).cropped(to: rect))
    }

    /// Versión para las hojas: parte de un CGImage ya orientado y devuelve otro CGImage.
    static func preview(_ cgImage: CGImage, look: ColorLook, framing: ClipFraming = ClipFraming(),
                        canvas: CanvasBackground = .black, renderSize: CGSize? = nil) -> CGImage? {
        let input = CIImage(cgImage: cgImage)
        let size = renderSize ?? input.extent.size
        let output = compose(input, look: look, framing: framing, canvas: canvas, renderSize: size)
        return previewContext.createCGImage(output, from: CGRect(origin: .zero, size: size))
    }
}
