import SwiftUI

/// Colores y piezas visuales de las hojas de audio, voz, subtítulos, proyectos y compartir.
/// (Paleta violeta + coral, alineada con el rediseño de la interfaz.)
enum Studio {
    static let violet = Color(red: 0.55, green: 0.36, blue: 0.98)
    static let coral = Color(red: 1.0, green: 0.42, blue: 0.42)
    static let teal = Color(red: 0.18, green: 0.83, blue: 0.75)
    static let amber = Color(red: 1.0, green: 0.72, blue: 0.25)
    static let card = Color.white.opacity(0.06)
    static let stroke = Color.white.opacity(0.10)
    static let gradient = LinearGradient(colors: [violet, coral], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let musicGradient = LinearGradient(colors: [teal, violet], startPoint: .leading, endPoint: .trailing)
    static let voiceGradient = LinearGradient(colors: [coral, amber], startPoint: .leading, endPoint: .trailing)
}

extension View {
    /// Tarjeta oscura translúcida con borde suave.
    func studioCard(padding: CGFloat = 14, cornerRadius: CGFloat = 16) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).fill(Studio.card))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).stroke(Studio.stroke, lineWidth: 1))
    }
}

/// Botón con degradado, para la acción principal de cada hoja.
struct StudioButtonStyle: ButtonStyle {
    var gradient: LinearGradient = Studio.gradient

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity)
            .background(Capsule().fill(gradient))
            .opacity(configuration.isPressed ? 0.8 : 1)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// Título de sección pequeño en mayúsculas.
struct StudioSectionTitle: View {
    let text: String
    var symbol: String?

    var body: some View {
        HStack(spacing: 6) {
            if let symbol { Image(systemName: symbol) }
            Text(text.uppercased())
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .tracking(0.6)
    }
}

/// Hoja con encabezado propio (ícono en degradado + título), contenido desplazable y barra inferior.
struct StudioSheet<Content: View, Actions: View>: View {
    let title: String
    let symbol: String
    var subtitle: String?
    @ViewBuilder var content: () -> Content
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Studio.gradient))
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.title3.bold())
                    if let subtitle {
                        Text(subtitle).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)
            .padding(.bottom, 10)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    content()
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 12)
            }

            HStack(spacing: 10) { actions() }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(.ultraThinMaterial)
        }
        .background(Color(red: 0.07, green: 0.06, blue: 0.10))
        .preferredColorScheme(.dark)
        #if os(macOS)
        .frame(minWidth: 460, idealWidth: 500, minHeight: 420, idealHeight: 560)
        #endif
    }
}
