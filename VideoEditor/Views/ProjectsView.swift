import SwiftUI
import ImageIO

/// Galería de proyectos guardados: abrir, crear, renombrar, duplicar y borrar.
struct ProjectsView: View {
    @Bindable var model: EditorModel
    @Environment(\.dismiss) private var dismiss
    @State private var store = ProjectStore.shared
    @State private var renaming: ProjectSummary?
    @State private var newName = ""
    @State private var deleting: ProjectSummary?

    var body: some View {
        StudioSheet(title: "Mis proyectos", symbol: "square.grid.2x2.fill",
                    subtitle: "Se guardan solos en este dispositivo") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 14)], spacing: 16) {
                newProjectCard
                ForEach(store.projects) { p in
                    ProjectCard(project: p, isCurrent: p.id == model.projectID)
                        .onTapGesture { open(p) }
                        .contextMenu { menu(for: p) }
                }
            }
            if store.projects.isEmpty {
                Text("Aún no hay proyectos guardados. En cuanto agregues un video, el proyecto se guarda automáticamente.")
                    .font(.footnote).foregroundStyle(.secondary)
            } else {
                Label("Mantén presionado (o clic derecho) un proyecto para renombrarlo, duplicarlo o borrarlo.",
                      systemImage: "hand.tap")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        } actions: {
            Spacer()
            Button("Cerrar") { dismiss() }.keyboardShortcut(.cancelAction)
        }
        .onAppear { store.refresh() }
        .alert("Renombrar proyecto", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Nombre", text: $newName)
            Button("Cancelar", role: .cancel) { renaming = nil }
            Button("Guardar") {
                if let p = renaming {
                    if p.id == model.projectID { model.renameProject(newName) } else { store.rename(id: p.id, to: newName) }
                }
                renaming = nil
            }
        }
        .confirmationDialog("¿Borrar \"\(deleting?.name ?? "")\"?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                            titleVisibility: .visible) {
            Button("Borrar proyecto", role: .destructive) {
                if let p = deleting { store.delete(id: p.id) }
                deleting = nil
            }
        } message: {
            Text("No se puede deshacer. Los videos originales de tu galería no se borran.")
        }
    }

    private var newProjectCard: some View {
        Button {
            Task {
                await model.saveNow()
                model.newProject()
                dismiss()
            }
        } label: {
            VStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Studio.gradient)
                    Image(systemName: "plus").font(.system(size: 30, weight: .bold)).foregroundStyle(.white)
                }
                .aspectRatio(16 / 10, contentMode: .fit)
                Text("Nuevo proyecto").font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(" ").font(.caption)
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func menu(for p: ProjectSummary) -> some View {
        Button { open(p) } label: { Label("Abrir", systemImage: "play.rectangle") }
        Button { newName = p.name; renaming = p } label: { Label("Renombrar", systemImage: "pencil") }
        Button {
            Task { await model.saveNow(); store.duplicate(id: p.id) }
        } label: { Label("Duplicar", systemImage: "plus.square.on.square") }
        Button(role: .destructive) { deleting = p } label: { Label("Borrar", systemImage: "trash") }
    }

    private func open(_ p: ProjectSummary) {
        Task {
            await model.openProject(id: p.id)
            dismiss()
        }
    }
}

/// Tarjeta con la miniatura, el nombre, la duración y cuándo se editó.
struct ProjectCard: View {
    let project: ProjectSummary
    var isCurrent = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .bottomTrailing) {
                Group {
                    if let image = ProjectThumbnail.load(project.thumbnailURL, modified: project.modifiedAt) {
                        Image(decorative: image, scale: 1).resizable().aspectRatio(contentMode: .fill)
                    } else {
                        ZStack {
                            Studio.card
                            Image(systemName: "film").font(.title).foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                .clipped()

                Text(formatTime(project.duration))
                    .font(.caption2.weight(.bold).monospacedDigit())
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(Capsule().fill(.black.opacity(0.6)))
                    .padding(6)
            }
            .aspectRatio(16 / 10, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(isCurrent ? AnyShapeStyle(Studio.gradient) : AnyShapeStyle(Studio.stroke), lineWidth: isCurrent ? 2.5 : 1))
            .shadow(color: .black.opacity(0.35), radius: 8, y: 4)

            Text(project.name).font(.subheadline.weight(.semibold)).lineLimit(1)
            Text(isCurrent ? "Abierto ahora" : project.modifiedAt.formatted(.relative(presentation: .named)))
                .font(.caption)
                .foregroundStyle(isCurrent ? AnyShapeStyle(Studio.coral) : AnyShapeStyle(.secondary))
        }
        .contentShape(Rectangle())
    }
}

/// Carga y guarda en memoria las miniaturas de la galería.
enum ProjectThumbnail {
    @MainActor private static var cache: [String: CGImage] = [:]

    @MainActor
    static func load(_ url: URL?, modified: Date) -> CGImage? {
        guard let url else { return nil }
        let key = "\(url.path)#\(modified.timeIntervalSince1970)"
        if let cached = cache[key] { return cached }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        cache[key] = image
        return image
    }
}
