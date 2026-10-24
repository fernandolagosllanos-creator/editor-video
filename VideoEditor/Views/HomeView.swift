import SwiftUI

/// Pantalla de inicio: botón grande para crear un proyecto, carpetas y galería con los proyectos guardados.
struct HomeView: View {
    @Bindable var model: EditorModel
    private var store: ProjectStore { .shared }
    private var folders: FolderStore { .shared }
    /// Carpeta abierta (vive en RootView para que siga abierta al volver del editor).
    @Binding var openFolderID: UUID?
    /// Crea un proyecto; si se pasa una carpeta, queda guardado dentro de ella.
    var onNew: (UUID?) -> Void
    var onOpen: (UUID) -> Void

    @State private var renaming: ProjectSummary?
    @State private var newName = ""
    @State private var deleting: ProjectSummary?
    @State private var appeared = false
    @State private var folderSheet: FolderSheet?
    @State private var unlocking: ProjectFolder?
    @State private var deletingFolder: ProjectFolder?

    private enum FolderSheet: Identifiable {
        case new
        case edit(ProjectFolder)
        var id: String {
            switch self {
            case .new: return "new"
            case .edit(let f): return f.id.uuidString
            }
        }
    }

    private let columns = [GridItem(.adaptive(minimum: 158, maximum: 260), spacing: 14)]

    /// La carpeta abierta, solo si existe y no está bloqueada.
    private var openFolder: ProjectFolder? {
        guard let id = openFolderID, let f = folders.folder(id), !folders.isLocked(f) else { return nil }
        return f
    }

    var body: some View {
        ZStack {
            AuroraBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if let folder = openFolder {
                        folderContent(folder)
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    } else {
                        rootContent
                            .transition(.move(edge: .leading).combined(with: .opacity))
                    }
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
            var existing = Set(store.projects.map(\.id))
            existing.insert(model.projectID)
            folders.prune(existing: existing)
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
        .confirmationDialog("¿Eliminar la carpeta «\(deletingFolder?.name ?? "")»?",
                            isPresented: Binding(get: { deletingFolder != nil }, set: { if !$0 { deletingFolder = nil } }),
                            titleVisibility: .visible) {
            Button("Eliminar carpeta", role: .destructive) {
                if let f = deletingFolder {
                    withAnimation(Theme.spring) {
                        openFolderID = nil
                        folders.delete(f.id)
                    }
                }
                deletingFolder = nil
            }
        } message: {
            Text("Los proyectos que tiene no se borran: vuelven a la pantalla principal.")
        }
        .sheet(item: $folderSheet) { target in
            switch target {
            case .new:
                FolderEditorSheet(existing: nil)
            case .edit(let f):
                FolderEditorSheet(existing: f)
            }
        }
        .sheet(item: $unlocking) { folder in
            UnlockFolderSheet(folder: folder) {
                withAnimation(Theme.spring) { openFolderID = folder.id }
            }
        }
    }

    // MARK: - Pantalla principal

    @ViewBuilder
    private var rootContent: some View {
        header
        newProjectCard(folder: nil)
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 20)
        foldersSection
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 25)
        projectsSection
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 30)
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

    private func newProjectCard(folder: ProjectFolder?) -> some View {
        Button { onNew(folder?.id) } label: {
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
                    Text(folder.map { "Se guardará en «\($0.name)»" } ?? "Importa tus clips y empieza a editar")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .opacity(0.85)
                        .lineLimit(1)
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
                    .fill(folder.map { FolderPalette.gradient($0.colorIndex) } ?? Theme.warmGradient)
                    .overlay(
                        RoundedRectangle(cornerRadius: 26, style: .continuous)
                            .fill(LinearGradient(colors: [.white.opacity(0.25), .clear], startPoint: .top, endPoint: .center))
                    )
            }
            .shadow(color: (folder.map { FolderPalette.color($0.colorIndex) } ?? Theme.accent2).opacity(0.4), radius: 22, y: 10)
        }
        .buttonStyle(PressableStyle())
    }

    // MARK: - Carpetas

    @ViewBuilder
    private var foldersSection: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Carpetas")
                .font(.system(size: 20, weight: .bold, design: .rounded))
            if !folders.folders.isEmpty {
                Text("\(folders.folders.count)")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background(Theme.surfaceRaised, in: Capsule())
            }
            Spacer()
        }

        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 14) {
                ForEach(folders.folders) { folder in
                    let locked = folders.isLocked(folder)
                    Button { open(folder) } label: {
                        FolderTile(folder: folder,
                                   projects: locked ? [] : folders.projects(in: folder.id, from: store.projects),
                                   locked: locked)
                    }
                    .buttonStyle(PressableStyle())
                    .contextMenu { folderMenu(folder) }
                    .transition(.scale(scale: 0.85).combined(with: .opacity))
                }
                Button { folderSheet = .new } label: { NewFolderTile() }
                    .buttonStyle(PressableStyle())
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 2)
        }
        .padding(.horizontal, -2)
    }

    @ViewBuilder
    private func folderMenu(_ folder: ProjectFolder) -> some View {
        Button { open(folder) } label: {
            Label("Abrir", systemImage: folder.isPrivate ? "lock.open" : "folder")
        }
        // Las privadas solo se editan o eliminan desde dentro (después de poner la contraseña).
        if !folders.isLocked(folder) {
            Button { folderSheet = .edit(folder) } label: { Label("Editar", systemImage: "slider.horizontal.3") }
            Button(role: .destructive) { deletingFolder = folder } label: { Label("Eliminar carpeta", systemImage: "trash") }
        }
    }

    private func open(_ folder: ProjectFolder) {
        if folders.isLocked(folder) {
            unlocking = folder
        } else {
            withAnimation(Theme.spring) { openFolderID = folder.id }
        }
    }

    private func closeFolder() {
        withAnimation(Theme.spring) {
            if let id = openFolderID, folders.folder(id)?.isPrivate == true {
                folders.lock(id)
            }
            openFolderID = nil
        }
    }

    // MARK: - Dentro de una carpeta

    @ViewBuilder
    private func folderContent(_ folder: ProjectFolder) -> some View {
        HStack(spacing: 12) {
            Button(action: closeFolder) {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(ChipButtonStyle())
            .keyboardShortcut(.cancelAction)

            FolderBadge(folder: folder, size: 46)
            VStack(alignment: .leading, spacing: 2) {
                Text(folder.name)
                    .font(.system(size: 24, weight: .heavy, design: .rounded))
                    .lineLimit(1)
                HStack(spacing: 5) {
                    if folder.isPrivate {
                        Image(systemName: "lock.open.fill").foregroundStyle(Studio.coral)
                        Text("Privada ·")
                    }
                    Text(countText(folders.projects(in: folder.id, from: store.projects).count))
                }
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            if folder.isPrivate {
                Button(action: closeFolder) {
                    Label("Bloquear", systemImage: "lock.fill")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(ChipButtonStyle())
                .help("Bloquear y salir")
            }
            Menu {
                Button { folderSheet = .edit(folder) } label: { Label("Editar carpeta", systemImage: "slider.horizontal.3") }
                Button(role: .destructive) { deletingFolder = folder } label: { Label("Eliminar carpeta", systemImage: "trash") }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(Theme.surfaceRaised.opacity(0.8), in: Capsule())
                    .overlay(Capsule().strokeBorder(Theme.stroke))
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(.top, 8)

        newProjectCard(folder: folder)

        let inside = folders.projects(in: folder.id, from: store.projects)
        if inside.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "tray.and.arrow.down")
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundStyle(FolderPalette.gradient(folder.colorIndex))
                Text("Esta carpeta está vacía")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                Text("Crea un proyecto aquí, o mantén presionado (clic derecho en el Mac) un proyecto de la pantalla principal y elige «Mover a carpeta».")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(28)
            .frame(maxWidth: .infinity)
            .glassCard(cornerRadius: 22)
        } else {
            projectGrid(inside)
        }
    }

    private func countText(_ n: Int) -> String {
        n == 1 ? "1 proyecto" : "\(n) proyectos"
    }

    // MARK: - Proyectos sueltos

    @ViewBuilder
    private var projectsSection: some View {
        let loose = folders.unfiled(store.projects)
        HStack(alignment: .firstTextBaseline) {
            Text("Tus proyectos")
                .font(.system(size: 20, weight: .bold, design: .rounded))
            if !loose.isEmpty {
                Text("\(loose.count)")
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
        } else if loose.isEmpty {
            Label("Todos tus proyectos están ordenados en carpetas.", systemImage: "checkmark.seal.fill")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
                .padding(.vertical, 6)
        } else {
            projectGrid(loose)
        }
    }

    private func projectGrid(_ projects: [ProjectSummary]) -> some View {
        LazyVGrid(columns: columns, spacing: 16) {
            ForEach(projects) { project in
                Button { onOpen(project.id) } label: {
                    GalleryCard(project: project)
                }
                .buttonStyle(PressableStyle())
                .contextMenu { projectMenu(project) }
                .transition(.scale(scale: 0.85).combined(with: .opacity))
            }
        }
    }

    @ViewBuilder
    private func projectMenu(_ project: ProjectSummary) -> some View {
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

        let current = folders.folderID(of: project.id)
        Menu {
            ForEach(folders.folders.filter { $0.id != current }) { folder in
                Button {
                    withAnimation(Theme.spring) { folders.move(project.id, to: folder.id) }
                } label: {
                    Label(folder.name, systemImage: folder.isPrivate ? "lock.fill" : folder.symbol)
                }
            }
            if current != nil {
                Divider()
                Button {
                    withAnimation(Theme.spring) { folders.move(project.id, to: nil) }
                } label: { Label("Sacar de la carpeta", systemImage: "tray.and.arrow.up") }
            }
            Divider()
            Button { folderSheet = .new } label: { Label("Nueva carpeta…", systemImage: "folder.badge.plus") }
        } label: {
            Label("Mover a carpeta", systemImage: "folder")
        }

        Button(role: .destructive) {
            deleting = project
        } label: { Label("Eliminar", systemImage: "trash") }
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
