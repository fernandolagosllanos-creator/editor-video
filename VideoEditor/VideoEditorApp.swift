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

/// Bienvenida animada → pantalla de inicio con la galería → editor.
struct RootView: View {
    @Bindable var model: EditorModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var showSplash = true
    @State private var isEditing = false
    @State private var openFolderID: UUID?

    var body: some View {
        ZStack {
            if isEditing {
                EditorView(model: model, onClose: closeEditor)
                    .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                            removal: .move(edge: .trailing).combined(with: .opacity)))
            } else {
                HomeView(model: model, openFolderID: $openFolderID, onNew: newProject, onOpen: openProject)
                    .transition(.asymmetric(insertion: .move(edge: .leading).combined(with: .opacity),
                                            removal: .move(edge: .leading).combined(with: .opacity)))
            }
            if model.isBusy && !isEditing {
                ZStack {
                    Color.black.opacity(0.45)
                    VStack(spacing: 12) {
                        ProgressView().controlSize(.large).tint(.white)
                        Text("Abriendo proyecto…").font(.system(.headline, design: .rounded)).foregroundStyle(.white)
                    }
                    .padding(26)
                    .glassCard(cornerRadius: 22)
                }
                .ignoresSafeArea()
                .transition(.opacity)
            }
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
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { Task { await model.saveNow() } }
            // Las carpetas privadas se vuelven a cerrar al salir de la app.
            if phase == .background { FolderStore.shared.lockAll() }
        }
    }

    private func newProject(in folder: UUID?) {
        Task {
            await model.saveNow()
            model.newProject()
            if let folder { FolderStore.shared.move(model.projectID, to: folder) }
            withAnimation(Theme.spring) { isEditing = true }
        }
    }

    private func openProject(_ id: UUID) {
        Task {
            await model.openProject(id: id)
            model.select(clipID: nil)
            withAnimation(Theme.spring) { isEditing = true }
        }
    }

    private func closeEditor() {
        model.player.pause()
        Task { await model.saveNow() }
        withAnimation(Theme.spring) { isEditing = false }
    }
}
