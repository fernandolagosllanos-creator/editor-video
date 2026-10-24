import SwiftUI

/// Animación de bienvenida: el logo aparece con un rebote, brilla y se desvanece.
struct SplashView: View {
    var onFinish: () -> Void

    @State private var logoScale: CGFloat = 0.4
    @State private var logoOpacity: Double = 0
    @State private var glow = false
    @State private var titleOffset: CGFloat = 16
    @State private var titleOpacity: Double = 0
    @State private var ringScale: CGFloat = 0.6
    @State private var ringOpacity: Double = 0

    var body: some View {
        ZStack {
            AuroraBackground(intensity: glow ? 1.2 : 0.4)
            VStack(spacing: 22) {
                ZStack {
                    Circle()
                        .strokeBorder(Theme.gradient, lineWidth: 2)
                        .frame(width: 170, height: 170)
                        .scaleEffect(ringScale)
                        .opacity(ringOpacity)
                    AppLogo(size: 110)
                        .scaleEffect(logoScale)
                        .opacity(logoOpacity)
                }
                VStack(spacing: 6) {
                    Text("Editor de Video")
                        .font(.system(size: 30, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                    Text("Crea. Corta. Comparte.")
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(Theme.gradient)
                }
                .offset(y: titleOffset)
                .opacity(titleOpacity)
            }
        }
        .preferredColorScheme(.dark)
        .task {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.6)) {
                logoScale = 1
                logoOpacity = 1
            }
            withAnimation(.easeOut(duration: 1.1)) {
                ringScale = 1.5
                ringOpacity = 0.9
                glow = true
            }
            withAnimation(.easeOut(duration: 0.6).delay(0.35)) {
                titleOffset = 0
                titleOpacity = 1
            }
            withAnimation(.easeIn(duration: 0.5).delay(0.7)) {
                ringOpacity = 0
            }
            try? await Task.sleep(for: .seconds(1.6))
            onFinish()
        }
    }
}
