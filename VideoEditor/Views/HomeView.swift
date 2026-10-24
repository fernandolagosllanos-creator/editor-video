import SwiftUI

/// Pantalla de inicio: botón grande para crear un proyecto y galería con los proyectos guardados.
struct HomeView: View {
    @Bindable var model: EditorModel
    private var store: ProjectStore { .shared }
    var onNew: () -> Void
    var onOpen: (UUID) -> Void

    @State private var renaming: ProjectSummary?
    @State private var newName = ""
    @State private var deleting: ProjectSummary?
    @State private var appeared = false

    private let columns = [GridItem(.adaptive(minimum: 158, maximum: 260), spacing: 14)]

    var body: some View {
        ZStack {
            AuroraBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    newProjectCard
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 20)
                    projectsSection
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 30)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
                .frame(maxWidth: 980)
                .frame(maxWidth: .infinity)
            }
        }
        .foregroundStyle(.white)
        .preferredColorScheme(.dark)
        .tint(Theme.accent)
        .onAppear {
            store.refresh()
            withAnimation(.spring(response: 0.6, dampingFraction: 0.85).delay(0.05)) { appeared = true }
        }
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
        .confirmationDialog("¿Eliminar este proyecto?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                            titleVisibility: .visible) {
            Button("Eliminar", role: .destructive) {
                if let p = deleting {
                    withAnimation(Theme.spring) { store.delete(id: p.id) }
                }
                deleting = nil
            }
        } message: {
            Text("Los videos originales en tu galería no se borran.")
        }
    }

    // MARK: - Encabezado

    private var header: some View {
        HStack(spacing: 14) {
            AppLogo(size: 46)
            VStack(alignment: .leading, spacing: 2) {
                Text("Editor de Video")
                    .font(.system(size: 26, weight: .heavy, design: .rounded))
                Text(greeting)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
        }
        .padding(.top, 8)
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "Buenos días, ¿qué vamos a crear hoy?"
        case 12..<20: return "Buenas tardes, ¿qué vamos a crear hoy?"
        default: return "Buenas noches, ¿qué vamos a crear hoy?"
        }
    }

    // MARK: - Nuevo proyecto

    private var newProjectCard: some View {
        Button(action: onNew) {
            HStack(spacing: 18) {
                Image(systemName: "plus")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 62, height: 62)
                    .background(Color.white, in: Circle())
                    .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Nuevo proyecto")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                    Text("Importa tus clips y empieza a editar")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .opacity(0.85)
                }
                Spacer(minLength: 0)
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 34, weight: .semibold))
                    .opacity(0.35)
            }
            .foregroundStyle(.white)
            .padding(22)
            .frame(maxWidth: .infinity, minHeight: 120)
            .background {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(Theme.warmGradient)
                    .overlay(
                        RoundedRectangle(cornerRadius: 26, style: .continuous)
                            .fill(LinearGradient(colors: [.white.opacity(0.25), .clear], startPoint: .top, endPoint: .center))
                    )
            }
            .shadow(color: Theme.accent2.opacity(0.4), radius: 22, y: 10)
        }
        .buttonStyle(PressableStyle())
    }

    // MARK: - Proyectos

    @ViewBuilder
    private var projectsSection: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Tus proyectos")
                .font(.system(size: 20, weight: .bold, design: .rounded))
            if !store.projects.isEmpty {
                Text("\(store.projects.count)")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background(Theme.surfaceRaised, in: Capsule())
            }
            Spacer()
        }

        if store.projects.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "sparkles.rectangle.stack")
                    .font(.system(size: 38, weight: .semibold))
                    .foregroundStyle(Theme.gradient)
                Text("Aún no tienes proyectos")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                Text("Se guardan solos mientras editas, así nunca pierdes tu trabajo.")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(28)
            .frame(maxWidth: .infinity)
            .glassCard(cornerRadius: 22)
        } else {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(store.projects) { project in
                    Button { onOpen(project.id) } label: {
                        GalleryCard(project: project)
                    }
                    .buttonStyle(PressableStyle())
                    .contextMenu {
                        Button {
                            newName = project.name
                            renaming = project
                        } label: { Label("Renombrar", systemImage: "pencil") }
                        Button {
                            Task {
                                await model.saveNow()
                                withAnimation(Theme.spring) { _ = store.duplicate(id: project.id) }
                            }
                        } label: { Label("Duplicar", systemImage: "plus.square.on.square") }
                        Button(role: .destructive) {
                            deleting = project
                        } label: { Label("Eliminar", systemImage: "trash") }
                    }
                    .transition(.scale(scale: 0.85).combined(with: .opacity))
                }
            }
        }
    }
}

// MARK: - Tarjeta de proyecto

private struct GalleryCard: View {
    let project: ProjectSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .bottomTrailing) {
                Color.clear
                    .aspectRatio(4 / 5, contentMode: .fit)
                    .overlay {
                        if let image = ProjectThumbnail.load(project.thumbnailURL, modified: project.modifiedAt) {
                            Image(decorative: image, scale: 1)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        } else {
                            ZStack {
                                LinearGradient(colors: [Theme.surfaceRaised, Theme.surface], startPoint: .top, endPoint: .bottom)
                                Image(systemName: "film")
                                    .font(.system(size: 28))
                                    .foregroundStyle(Theme.textSecondary)
                            }
                        }
                    }
                    .overlay(LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .center, endPoint: .bottom))
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                Text(formatDuration(project.duration))
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(8)
            }
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.stroke))
            .shadow(color: .black.opacity(0.35), radius: 10, y: 6)

            VStack(alignment: .leading, spacing: 2) {
                Text(project.name)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                Text(project.modifiedAt.formatted(.relative(presentation: .named)))
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(.horizontal, 4)
        }
        .foregroundStyle(.white)
        .contentShape(Rectangle())
    }

    private func formatDuration(_ seconds: Double) -> String {
        let s = Int(seconds.rounded())
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

/// Se achica levemente al presionar.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .brightness(configuration.isPressed ? -0.04 : 0)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}
