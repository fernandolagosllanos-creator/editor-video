import Foundation
import AVFoundation
import CoreMedia
import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI

// MARK: - Transiciones

enum TransitionType: String, CaseIterable, Identifiable, Codable {
    case none, crossfade, fadeBlack, slideLeft, zoom, wipe

    var id: String { rawValue }

    var label: String {
        switch self {
        case .none: return "Ninguna"
        case .crossfade: return "Fundido cruzado"
        case .fadeBlack: return "Fundido a negro"
        case .slideLeft: return "Deslizar"
        case .zoom: return "Zoom"
        case .wipe: return "Barrido"
        }
    }

    var symbol: String {
        switch self {
        case .none: return "xmark"
        case .crossfade: return "circle.lefthalf.filled"
        case .fadeBlack: return "moon.fill"
        case .slideLeft: return "arrow.left.square"
        case .zoom: return "plus.magnifyingglass"
        case .wipe: return "rectangle.lefthalf.inset.filled"
        }
    }
}

// MARK: - Filtros de color

enum VideoFilter: String, CaseIterable, Identifiable, Codable {
    case none, mono, noir, sepia, vivid, warm, cool, fade, chrome, instant

    var id: String { rawValue }

    var label: String {
        switch self {
        case .none: return "Normal"
        case .mono: return "Blanco y negro"
        case .noir: return "Noir"
        case .sepia: return "Sepia"
        case .vivid: return "Vívido"
        case .warm: return "Cálido"
        case .cool: return "Frío"
        case .fade: return "Desvanecido"
        case .chrome: return "Chrome"
        case .instant: return "Instantánea"
        }
    }

    func apply(to image: CIImage) -> CIImage {
        switch self {
        case .none:
            return image
        case .mono:
            let f = CIFilter.photoEffectMono(); f.inputImage = image
            return f.outputImage ?? image
        case .noir:
            let f = CIFilter.photoEffectNoir(); f.inputImage = image
            return f.outputImage ?? image
        case .sepia:
            let f = CIFilter.sepiaTone(); f.inputImage = image; f.intensity = 0.9
            return f.outputImage ?? image
        case .vivid:
            let f = CIFilter.colorControls(); f.inputImage = image
            f.saturation = 1.6; f.contrast = 1.1; f.brightness = 0.02
            return f.outputImage ?? image
        case .warm:
            let f = CIFilter.temperatureAndTint(); f.inputImage = image
            f.neutral = CIVector(x: 6500, y: 0); f.targetNeutral = CIVector(x: 4500, y: 0)
            return f.outputImage ?? image
        case .cool:
            let f = CIFilter.temperatureAndTint(); f.inputImage = image
            f.neutral = CIVector(x: 6500, y: 0); f.targetNeutral = CIVector(x: 9000, y: 0)
            return f.outputImage ?? image
        case .fade:
            let f = CIFilter.photoEffectFade(); f.inputImage = image
            return f.outputImage ?? image
        case .chrome:
            let f = CIFilter.photoEffectChrome(); f.inputImage = image
            return f.outputImage ?? image
        case .instant:
            let f = CIFilter.photoEffectInstant(); f.inputImage = image
            return f.outputImage ?? image
        }
    }
}

// MARK: - Colores de texto

enum TextColor: String, CaseIterable, Identifiable, Codable {
    case white, yellow, red, blue, green, black

    var id: String { rawValue }

    var label: String {
        switch self {
        case .white: return "Blanco"
        case .yellow: return "Amarillo"
        case .red: return "Rojo"
        case .blue: return "Azul"
        case .green: return "Verde"
        case .black: return "Negro"
        }
    }

    private var rgb: (CGFloat, CGFloat, CGFloat) {
        switch self {
        case .white: return (1, 1, 1)
        case .yellow: return (1, 0.85, 0.1)
        case .red: return (0.95, 0.2, 0.2)
        case .blue: return (0.25, 0.55, 1)
        case .green: return (0.3, 0.85, 0.4)
        case .black: return (0, 0, 0)
        }
    }

    var color: Color {
        let c = rgb
        return Color(red: c.0, green: c.1, blue: c.2)
    }

    var cgColor: CGColor {
        let c = rgb
        return CGColor(red: c.0, green: c.1, blue: c.2, alpha: 1)
    }
}

// MARK: - Clip de video

struct Clip: Identifiable {
    let id: UUID
    let url: URL
    let name: String
    let assetDuration: CMTime
    let naturalSize: CGSize
    let preferredTransform: CGAffineTransform
    let hasAudio: Bool

    /// Punto de inicio y fin dentro del archivo original (recorte).
    var start: CMTime
    var end: CMTime
    /// Transición hacia el clip siguiente.
    var transitionOut: TransitionType = .none
    var transitionDuration: Double = 0.6
    var thumbnails: [CGImage] = []

    var duration: CMTime { end - start }

    /// Tamaño del video ya rotado (los videos de iPhone suelen venir "acostados" con una transformación).
    var displaySize: CGSize {
        let r = CGRect(origin: .zero, size: naturalSize).applying(preferredTransform)
        return CGSize(width: abs(r.width), height: abs(r.height))
    }
}

// MARK: - Texto sobre el video

struct TextOverlay: Identifiable {
    var id = UUID()
    var text: String = "Texto"
    /// Segundos dentro de la línea de tiempo.
    var start: Double = 0
    var duration: Double = 3
    /// Tamaño de letra como fracción de la altura del video (0.08 = 8%).
    var fontSize: Double = 0.08
    var color: TextColor = .white
    /// Posición normalizada (0...1) con origen arriba a la izquierda, como en SwiftUI.
    var position: CGPoint = CGPoint(x: 0.5, y: 0.82)
    /// Caja oscura redondeada detrás del texto (estilo subtítulo).
    var hasBackground: Bool = false
    /// Creado por los subtítulos automáticos.
    var isCaption: Bool = false

    var end: Double { start + duration }
}

// MARK: - Pista de audio adicional

enum AudioKind: String, Codable {
    case music, voice

    var symbol: String { self == .music ? "music.note" : "mic.fill" }
}

struct AudioTrack: Identifiable {
    let id: UUID
    let url: URL
    var name: String
    let assetDuration: CMTime
    var kind: AudioKind = .music
    /// Segundos dentro de la línea de tiempo donde empieza a sonar.
    var start: Double = 0
    var volume: Float = 1
    /// Segundos que se saltan al principio del archivo (elegir qué parte de la canción suena).
    var sourceOffset: Double = 0
    /// Duración de los fundidos de entrada y salida, en segundos.
    var fadeIn: Double = 0
    var fadeOut: Double = 0
    /// Repetir el audio hasta el final del video.
    var loops: Bool = false
    /// Bajar el volumen automáticamente mientras suena una voz en off.
    var ducking: Bool = true

    /// Segundos que suena en una línea de tiempo de duración `total`.
    func playedDuration(total: Double) -> Double {
        let available = max(0, total - start)
        if loops { return available }
        return min(max(0, assetDuration.seconds - sourceOffset), available)
    }
}

// MARK: - Ubicación de cada clip en la línea de tiempo

struct Placement: Identifiable {
    let clip: Clip
    let start: CMTime
    var id: UUID { clip.id }
    var end: CMTime { start + clip.duration }
    var range: CMTimeRange { CMTimeRange(start: start, end: end) }
}

enum Timeline {
    static let timescale: CMTimeScale = 600

    static func time(_ seconds: Double) -> CMTime {
        CMTime(seconds: max(0, seconds), preferredTimescale: timescale)
    }

    /// Duración efectiva de la transición entre el clip `i` y el siguiente (limitada para que nunca
    /// sea mayor a la mitad del clip más corto).
    static func transitionDuration(clips: [Clip], at i: Int) -> Double {
        guard i < clips.count - 1, clips[i].transitionOut != .none else { return 0 }
        let shortest = min(clips[i].duration.seconds, clips[i + 1].duration.seconds)
        return min(clips[i].transitionDuration, shortest / 2)
    }

    /// Coloca los clips uno tras otro, solapándolos cuando hay transición.
    static func placements(for clips: [Clip]) -> [Placement] {
        var t = CMTime.zero
        var out: [Placement] = []
        for (i, clip) in clips.enumerated() {
            out.append(Placement(clip: clip, start: t))
            t = t + clip.duration
            let td = transitionDuration(clips: clips, at: i)
            if td > 0 { t = t - time(td) }
        }
        return out
    }

    static func totalDuration(for clips: [Clip]) -> CMTime {
        placements(for: clips).last?.end ?? .zero
    }
}

func formatTime(_ seconds: Double) -> String {
    guard seconds.isFinite, seconds >= 0 else { return "0:00.0" }
    let m = Int(seconds) / 60
    let s = seconds - Double(m * 60)
    return String(format: "%d:%04.1f", m, s)
}
