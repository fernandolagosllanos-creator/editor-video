import SwiftUI

@main
struct VideoEditorApp: App {
    @State private var model = EditorModel()

    var body: some Scene {
        #if os(macOS)
        WindowGroup {
            EditorView(model: model)
        }
        .defaultSize(width: 1100, height: 720)
        #else
        WindowGroup {
            EditorView(model: model)
        }
        #endif
    }
}
