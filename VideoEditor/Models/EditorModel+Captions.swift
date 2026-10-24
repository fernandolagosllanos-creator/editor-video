import Foundation
import CoreGraphics

/// Estilos prediseñados para los subtítulos.
enum CaptionStyle: String, CaseIterable, Identifiable {
    case classic, boxed, yellow, bold, minimal

    var id: String { rawValue }

    var label: String {
        switch self {
        case .classic: return "Clásico"
        case .boxed: return "Caja"
        case .yellow: return "Amarillo"
        case .bold: return "Grande"
        case .minimal: return "Mínimo"
        }
    }

    var color: TextColor {
        self == .yellow ? .yellow : .white
    }

    var fontSize: Double {
        switch self {
        case .classic, .boxed: return 0.055
        case .yellow: return 0.065
        case .bold: return 0.08
        case .minimal: return 0.04
        }
    }

    var hasBackground: Bool { self == .boxed || self == .minimal }

    func apply(to t: inout TextOverlay) {
        t.color = color
        t.fontSize = fontSize
        t.hasBackground = hasBackground
    }

    /// Estilo que mejor describe un subtítulo existente.
    static func matching(_ t: TextOverlay) -> CaptionStyle {
        allCases.first { $0.color == t.color && abs($0.fontSize - t.fontSize) < 0.001 && $0.hasBackground == t.hasBackground } ?? .classic
    }
}

enum CaptionPosition: String, CaseIterable, Identifiable {
    case top, middle, bottom

    var id: String { rawValue }
    var label: String {
        switch self {
        case .top: return "Arriba"
        case .middle: return "Centro"
        case .bottom: return "Abajo"
        }
    }
    var symbol: String {
        switch self {
        case .top: return "rectangle.tophalf.inset.filled"
        case .middle: return "rectangle.center.inset.filled"
        case .bottom: return "rectangle.bottomhalf.inset.filled"
        }
    }
    var y: Double {
        switch self {
        case .top: return 0.14
        case .middle: return 0.5
        case .bottom: return 0.84
        }
    }

    static func matching(_ y: Double) -> CaptionPosition {
        allCases.min { abs($0.y - y) < abs($1.y - y) } ?? .bottom
    }
}

extension EditorModel {
    var captions: [TextOverlay] { texts.filter(\.isCaption) }

    /// Reemplaza los subtítulos automáticos (los textos normales no se tocan).
    func setCaptions(_ items: [(text: String, start: Double, end: Double)], style: CaptionStyle, position: CaptionPosition) {
        texts.removeAll(where: \.isCaption)
        for item in items {
            var t = TextOverlay()
            t.text = item.text
            t.start = item.start
            t.duration = max(0.3, item.end - item.start)
            t.position = CGPoint(x: 0.5, y: position.y)
            t.isCaption = true
            style.apply(to: &t)
            texts.append(t)
        }
        selectedTextID = nil
        scheduleSave()
    }

    func applyCaptionStyle(_ style: CaptionStyle, position: CaptionPosition) {
        for i in texts.indices where texts[i].isCaption {
            style.apply(to: &texts[i])
            texts[i].position = CGPoint(x: 0.5, y: position.y)
        }
        scheduleSave()
    }

    func removeCaptions() {
        texts.removeAll(where: \.isCaption)
        if let id = selectedTextID, !texts.contains(where: { $0.id == id }) { selectedTextID = nil }
        scheduleSave()
    }
}
