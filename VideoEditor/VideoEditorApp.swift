import SwiftUI

@main
struct VideoEditorApp: App {
    @State private var model = EditorModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        #if os(macOS)
        WindowGroup {
            EditorView(model: model)
                .onChange(of: scenePhase) { _, phase in
                    if phase != .active { Task { await model.saveNow() } }
                }
        }
        .defaultSize(width: 1100, height: 720)
        #else
        WindowGroup {
            EditorView(model: model)
                .onChange(of: scenePhase) { _, phase in
                    if phase != .active { Task { await model.saveNow() } }
                }
        }
        #endif
    }
}
