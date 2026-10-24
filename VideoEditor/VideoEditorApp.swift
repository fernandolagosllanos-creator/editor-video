import SwiftUI

@main
struct VideoEditorApp: App {
    @State private var model = EditorModel()

    var body: some Scene {
        #if os(macOS)
        WindowGroup {
            RootView(model: model)
        }
        .defaultSize(width: 1100, height: 760)
        #else
        WindowGroup {
            RootView(model: model)
        }
        #endif
    }
}

/// Muestra la bienvenida animada y después el editor.
struct RootView: View {
    @Bindable var model: EditorModel
    @State private var showSplash = true

    var body: some View {
        ZStack {
            EditorView(model: model)
                .opacity(showSplash ? 0 : 1)
                .scaleEffect(showSplash ? 0.96 : 1)
            if showSplash {
                SplashView {
                    withAnimation(.easeInOut(duration: 0.45)) { showSplash = false }
                }
                .transition(.opacity)
                .zIndex(1)
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }
}
