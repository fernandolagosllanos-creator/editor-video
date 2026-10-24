import Foundation
import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI

// MARK: - Color por clip (filtro + ajustes finos)

/// Aspecto de color de un clip: un filtro predefinido con su intensidad y ajustes manuales.
/// Todos los ajustes van de -1 a 1 (0 = sin cambio), salvo viñeta y nitidez que van de 0 a 1.
struct ColorLook: Codable, Equatable {
    var preset: VideoFilter = .none
    var intensity: Double = 1
    var brightness: Double = 0
    var contrast: Double = 0
    var saturation: Double = 0
    var warmth: Double = 0
    var vignette: Double = 0
    var sharpness: Double = 0

    var isIdentity: Bool { self == ColorLook() }

    func apply(to image: CIImage) -> CIImage {
        guard !isIdentity else { return image }
        let extent = image.extent
        var out = image

        if preset != .none, intensity > 0.001 {
            let filtered = preset.apply(to: image).cropped(to: extent)
            if intensity >= 0.999 {
                out = filtered
            } else {
                let mix = CIFilter.dissolveTransition()
                mix.inputImage = image
                mix.targetImage = filtered
                mix.time = Float(intensity)
                out = mix.outputImage?.cropped(to: extent) ?? filtered
            }
        }

        if brightness != 0 || contrast != 0 || saturation != 0 {
            let f = CIFilter.colorControls()
            f.inputImage = out
            f.brightness = Float(brightness * 0.25)
            f.contrast = Float(1 + contrast * 0.5)
            f.saturation = Float(max(0, 1 + saturation))
            out = f.outputImage ?? out
        }

        if warmth != 0 {
            // Más rojo y menos azul = más cálido (y al revés para frío).
            let f = CIFilter.colorMatrix()
            f.inputImage = out
            f.rVector = CIVector(x: 1 + 0.12 * warmth, y: 0, z: 0, w: 0)
            f.gVector = CIVector(x: 0, y: 1 + 0.02 * warmth, z: 0, w: 0)
            f.bVector = CIVector(x: 0, y: 0, z: 1 - 0.14 * warmth, w: 0)
            out = f.outputImage ?? out
        }

        if sharpness > 0 {
            let f = CIFilter.sharpenLuminance()
            f.inputImage = out
            f.sharpness = Float(sharpness * 1.2)
            out = f.outputImage ?? out
        }

        if vignette > 0 {
            let f = CIFilter.vignetteEffect()
            f.inputImage = out
            f.center = CGPoint(x: extent.midX, y: extent.midY)
            f.radius = Float(hypot(extent.width, extent.height) * 0.5 * (1.05 - 0.35 * vignette))
            f.intensity = Float(vignette)
            f.falloff = 0.6
            out = f.outputImage ?? out
        }

        return out.cropped(to: extent)
    }
}

/// Ajustes manuales que se muestran en la hoja de color.
enum ColorAdjustment: String, CaseIterable, Identifiable {
    case brightness, contrast, saturation, warmth, vignette, sharpness

    var id: String { rawValue }

    var label: String {
        switch self {
        case .brightness: return "Brillo"
        case .contrast: return "Contraste"
        case .saturation: return "Saturación"
        case .warmth: return "Temperatura"
        case .vignette: return "Viñeta"
        case .sharpness: return "Nitidez"
        }
    }

    var symbol: String {
        switch self {
        case .brightness: return "sun.max.fill"
        case .contrast: return "circle.lefthalf.filled"
        case .saturation: return "drop.fill"
        case .warmth: return "thermometer.medium"
        case .vignette: return "camera.aperture"
        case .sharpness: return "triangle.fill"
        }
    }

    /// Rango del ajuste: los de -1...1 tienen el cero al centro.
    var isBipolar: Bool { self != .vignette && self != .sharpness }

    var keyPath: WritableKeyPath<ColorLook, Double> {
        switch self {
        case .brightness: return \.brightness
        case .contrast: return \.contrast
        case .saturation: return \.saturation
        case .warmth: return \.warmth
        case .vignette: return \.vignette
        case .sharpness: return \.sharpness
        }
    }
}

// MARK: - Encuadre del clip

enum FitMode: String, Codable, CaseIterable, Identifiable {
    case fit, fill

    var id: String { rawValue }
    var label: String { self == .fit ? "Ajustar" : "Llenar" }
    var symbol: String { self == .fit ? "rectangle.inset.filled" : "rectangle.fill" }
}

/// Cómo se ubica el clip dentro del lienzo: ajustado (con bordes) o llenando (recortado), con zoom,
/// desplazamiento y espejo.
struct ClipFraming: Codable, Equatable {
    var mode: FitMode = .fit
    /// 1 = tamaño base; hasta 3 = acercar.
    var zoom: Double = 1
    /// Desplazamiento como fracción del lienzo (x a la derecha, y hacia abajo).
    var offset: CGPoint = .zero
    var mirrored: Bool = false
}

// MARK: - Relación de aspecto del proyecto

enum CanvasAspect: String, Codable, CaseIterable, Identifiable {
    case original, vertical, square, portrait, wide, classic

    var id: String { rawValue }

    var label: String {
        switch self {
        case .original: return "Original"
        case .vertical: return "9:16"
        case .square: return "1:1"
        case .portrait: return "4:5"
        case .wide: return "16:9"
        case .classic: return "4:3"
        }
    }

    var subtitle: String {
        switch self {
        case .original: return "Como el video"
        case .vertical: return "TikTok · Reels"
        case .square: return "Cuadrado"
        case .portrait: return "Instagram"
        case .wide: return "YouTube"
        case .classic: return "Clásico"
        }
    }

    /// Ancho / alto, o nil para usar el del primer clip.
    var ratio: CGFloat? {
        switch self {
        case .original: return nil
        case .vertical: return 9.0 / 16.0
        case .square: return 1
        case .portrait: return 4.0 / 5.0
        case .wide: return 16.0 / 9.0
        case .classic: return 4.0 / 3.0
        }
    }

    /// Tamaño del lienzo en píxeles.
    var pixelSize: CGSize? {
        switch self {
        case .original: return nil
        case .vertical: return CGSize(width: 1080, height: 1920)
        case .square: return CGSize(width: 1080, height: 1080)
        case .portrait: return CGSize(width: 1080, height: 1350)
        case .wide: return CGSize(width: 1920, height: 1080)
        case .classic: return CGSize(width: 1440, height: 1080)
        }
    }
}

/// Qué se ve detrás del clip cuando no llena todo el lienzo.
enum CanvasBackground: String, Codable, CaseIterable, Identifiable {
    case blur, black, white, violet, coral, mint

    var id: String { rawValue }

    var label: String {
        switch self {
        case .blur: return "Desenfoque"
        case .black: return "Negro"
        case .white: return "Blanco"
        case .violet: return "Violeta"
        case .coral: return "Coral"
        case .mint: return "Menta"
        }
    }

    var rgb: (CGFloat, CGFloat, CGFloat) {
        switch self {
        case .blur, .black: return (0, 0, 0)
        case .white: return (1, 1, 1)
        case .violet: return (0.486, 0.361, 1)
        case .coral: return (1, 0.42, 0.545)
        case .mint: return (0.30, 0.85, 0.72)
        }
    }

    var color: Color { Color(red: rgb.0, green: rgb.1, blue: rgb.2) }
}

// MARK: - Stickers

enum StickerShape: String, Codable, CaseIterable, Identifiable {
    case heart, star, circle, square, arrow, bubble, burst, bolt

    var id: String { rawValue }

    var label: String {
        switch self {
        case .heart: return "Corazón"
        case .star: return "Estrella"
        case .circle: return "Círculo"
        case .square: return "Cuadrado"
        case .arrow: return "Flecha"
        case .bubble: return "Globo"
        case .burst: return "Destello"
        case .bolt: return "Rayo"
        }
    }
}

enum StickerContent: Codable, Equatable {
    case emoji(String)
    case shape(StickerShape)

    var isShape: Bool {
        if case .shape = self { return true }
        return false
    }
}

enum StickerAnimation: String, Codable, CaseIterable, Identifiable {
    case none, pop, bounce, pulse, wiggle, spin, float

    var id: String { rawValue }

    var label: String {
        switch self {
        case .none: return "Ninguna"
        case .pop: return "Aparecer"
        case .bounce: return "Rebote"
        case .pulse: return "Latido"
        case .wiggle: return "Balanceo"
        case .spin: return "Girar"
        case .float: return "Flotar"
        }
    }

    /// Estado de la animación `t` segundos después de que el sticker aparece. Se usa igual en la
    /// vista previa y en la exportación, así que ambas se ven idénticas.
    /// - Returns: escala, rotación extra en grados, opacidad y desplazamiento vertical (fracción del
    ///   tamaño del sticker, positivo hacia abajo).
    func state(at t: Double, duration: Double) -> (scale: Double, rotation: Double, opacity: Double, dy: Double) {
        let fade = 0.15
        var opacity = 1.0
        if t < fade { opacity = max(0, t / fade) }
        if t > duration - fade { opacity = max(0, (duration - t) / fade) }

        switch self {
        case .none:
            return (1, 0, opacity, 0)
        case .pop:
            let p = min(1, max(0, t / 0.4))
            // "Ease out back": crece pasándose un poco y vuelve a su tamaño.
            let c1 = 1.70158, c3 = c1 + 1
            let s = 1 + c3 * pow(p - 1, 3) + c1 * pow(p - 1, 2)
            return (max(0, s), 0, t < fade ? 1 : opacity, 0)
        case .bounce:
            let dy = -abs(sin(t * .pi * 1.6)) * 0.22
            let squash = 1 + 0.06 * cos(t * .pi * 3.2)
            return (squash, 0, opacity, dy)
        case .pulse:
            return (1 + 0.12 * sin(t * 2 * .pi * 1.4), 0, opacity, 0)
        case .wiggle:
            return (1, 12 * sin(t * 2 * .pi * 1.8), opacity, 0)
        case .spin:
            return (1, t * 180, opacity, 0)
        case .float:
            return (1, 4 * sin(t * 2 * .pi * 0.5), opacity, 0.08 * sin(t * 2 * .pi * 0.7))
        }
    }
}

struct StickerOverlay: Identifiable, Codable, Equatable {
    var id = UUID()
    var content: StickerContent = .emoji("😍")
    /// Segundos dentro de la línea de tiempo.
    var start: Double = 0
    var duration: Double = 3
    /// Posición normalizada (0...1) con origen arriba a la izquierda.
    var position: CGPoint = CGPoint(x: 0.5, y: 0.45)
    /// Lado del sticker como fracción del lado corto del video.
    var size: Double = 0.28
    /// Rotación en grados (sentido horario).
    var rotation: Double = 0
    var color: TextColor = .yellow
    var filled: Bool = true
    var animation: StickerAnimation = .pop

    var end: Double { start + duration }

    static let emojis: [String] = [
        "😍", "😂", "🥳", "😎", "🤩", "😱", "🥹", "😘", "🤯", "😴",
        "🔥", "✨", "💥", "💯", "❤️", "💜", "👏", "🙌", "👍", "✌️",
        "🎉", "🎂", "🎵", "📸", "⭐️", "🌈", "☀️", "🌙", "⚡️", "💫",
        "🍕", "🍦", "☕️", "🏖️", "✈️", "🚗", "⚽️", "🐶", "🐱", "🌸"
    ]
}
