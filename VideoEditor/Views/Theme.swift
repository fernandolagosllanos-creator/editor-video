import SwiftUI

/// Identidad visual de la app: fondo azul noche, acentos en degradado violeta → coral y
/// superficies de "vidrio" con bordes suaves.
enum Theme {
    // Fondos
    static let background = Color(red: 0.043, green: 0.043, blue: 0.078)      // #0B0B14
    static let surface = Color(red: 0.086, green: 0.086, blue: 0.141)         // #161624
    static let surfaceRaised = Color(red: 0.133, green: 0.133, blue: 0.212)   // #222236
    static let stroke = Color.white.opacity(0.09)
    static let textSecondary = Color.white.opacity(0.6)

    // Acentos
    static let accent = Color(red: 0.486, green: 0.361, blue: 1.0)            // #7C5CFF violeta
    static let accent2 = Color(red: 1.0, green: 0.42, blue: 0.545)            // #FF6B8B coral
    static let accent3 = Color(red: 1.0, green: 0.722, blue: 0.42)            // #FFB86B ámbar suave

    // Colores por tipo de pista
    static let audio = Color(red: 0.24, green: 0.86, blue: 0.85)              // turquesa
    static let text = Color(red: 0.78, green: 0.6, blue: 1.0)                 // lila
    static let sticker = accent3

    static let gradient = LinearGradient(colors: [accent, accent2],
                                         startPoint: .topLeading, endPoint: .bottomTrailing)
    static let warmGradient = LinearGradient(colors: [accent, accent2, accent3],
                                             startPoint: .topLeading, endPoint: .bottomTrailing)

    static let spring = Animation.spring(response: 0.38, dampingFraction: 0.82)
}

// MARK: - Fondo con brillos de color

/// Fondo oscuro con dos manchas de luz difusas (violeta y coral) que le dan profundidad.
struct AuroraBackground: View {
    var intensity: Double = 1

    var body: some View {
        ZStack {
            Theme.background
            GeometryReader { geo in
                let s = max(geo.size.width, geo.size.height)
                Circle()
                    .fill(Theme.accent.opacity(0.28 * intensity))
                    .frame(width: s * 0.8, height: s * 0.8)
                    .blur(radius: s * 0.18)
                    .offset(x: -s * 0.3, y: -s * 0.35)
                Circle()
                    .fill(Theme.accent2.opacity(0.18 * intensity))
                    .frame(width: s * 0.7, height: s * 0.7)
                    .blur(radius: s * 0.2)
                    .offset(x: geo.size.width - s * 0.35, y: geo.size.height - s * 0.3)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

// MARK: - Superficie de vidrio

struct GlassCard: ViewModifier {
    var cornerRadius: CGFloat = 18

    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .background(Theme.surface.opacity(0.55), in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).strokeBorder(Theme.stroke))
    }
}

extension View {
    func glassCard(cornerRadius: CGFloat = 18) -> some View {
        modifier(GlassCard(cornerRadius: cornerRadius))
    }
}

// MARK: - Botones

/// Botón principal en cápsula con el degradado de la marca.
struct GradientButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(Theme.gradient, in: Capsule())
            .shadow(color: Theme.accent2.opacity(isEnabled ? 0.35 : 0), radius: 10, y: 4)
            .opacity(isEnabled ? 1 : 0.4)
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// Botón redondo secundario (atrás, ajustes…).
struct ChipButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white)
            .frame(minWidth: 36, minHeight: 36)
            .padding(.horizontal, 4)
            .background(Theme.surfaceRaised.opacity(configuration.isPressed ? 1 : 0.8), in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.stroke))
            .opacity(isEnabled ? 1 : 0.4)
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Logo

/// Logo de la app dibujado en código: cuadrado redondeado con degradado, un triángulo de
/// reproducción y un destello. Se usa en la bienvenida y en la pantalla de inicio.
struct AppLogo: View {
    var size: CGFloat = 96

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
                .fill(Theme.warmGradient)
            RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
                .fill(LinearGradient(colors: [.white.opacity(0.28), .clear], startPoint: .top, endPoint: .center))
            Image(systemName: "play.fill")
                .font(.system(size: size * 0.42, weight: .black))
                .foregroundStyle(.white)
                .offset(x: size * 0.03)
                .shadow(color: .black.opacity(0.2), radius: size * 0.04, y: size * 0.02)
            Image(systemName: "sparkle")
                .font(.system(size: size * 0.2, weight: .bold))
                .foregroundStyle(.white)
                .offset(x: size * 0.25, y: -size * 0.25)
        }
        .frame(width: size, height: size)
        .shadow(color: Theme.accent.opacity(0.5), radius: size * 0.2, y: size * 0.08)
    }
}
