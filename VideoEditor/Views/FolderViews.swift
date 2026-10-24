import SwiftUI

// MARK: - Colores e íconos de carpetas

enum FolderPalette {
    static let pairs: [(Color, Color)] = [
        (Theme.accent, Theme.accent2),                                  // violeta → coral
        (Theme.accent2, Theme.accent3),                                 // coral → ámbar
        (Theme.audio, Theme.accent),                                    // turquesa → violeta
        (Color(red: 0.35, green: 0.6, blue: 1.0), Theme.audio),         // azul → turquesa
        (Color(red: 0.36, green: 0.85, blue: 0.55), Theme.audio),       // verde → turquesa
        (Theme.text, Theme.accent),                                     // lila → violeta
        (Theme.accent3, Color(red: 1.0, green: 0.85, blue: 0.45)),      // ámbar → dorado
    ]

    static let symbols = ["folder.fill", "film.stack.fill", "heart.fill", "star.fill", "airplane",
                          "figure.2.and.child.holdinghands", "pawprint.fill", "music.note", "briefcase.fill",
                          "gift.fill", "camera.fill", "sparkles"]

    static func gradient(_ index: Int) -> LinearGradient {
        let pair = pairs[((index % pairs.count) + pairs.count) % pairs.count]
        return LinearGradient(colors: [pair.0, pair.1], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    static func color(_ index: Int) -> Color {
        pairs[((index % pairs.count) + pairs.count) % pairs.count].0
    }
}

/// Ícono cuadrado de la carpeta con su degradado (y candado si es privada).
struct FolderBadge: View {
    let folder: ProjectFolder
    var size: CGFloat = 44
    var locked = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                .fill(FolderPalette.gradient(folder.colorIndex))
            RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                .fill(LinearGradient(colors: [.white.opacity(0.25), .clear], startPoint: .top, endPoint: .center))
            Image(systemName: locked ? "lock.fill" : folder.symbol)
                .font(.system(size: size * 0.42, weight: .bold))
                .foregroundStyle(.white)
                .contentTransition(.symbolEffect(.replace))
        }
        .frame(width: size, height: size)
        .shadow(color: FolderPalette.color(folder.colorIndex).opacity(0.45), radius: size * 0.2, y: size * 0.08)
    }
}

// MARK: - Tarjeta de carpeta (pantalla de inicio)

struct FolderTile: View {
    let folder: ProjectFolder
    let projects: [ProjectSummary]
    let locked: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            preview
            HStack(spacing: 10) {
                FolderBadge(folder: folder, size: 34, locked: locked)
                VStack(alignment: .leading, spacing: 1) {
                    Text(folder.name)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(10)
        .frame(width: 176)
        .glassCard(cornerRadius: 20)
        .foregroundStyle(.white)
        .contentShape(Rectangle())
    }

    private var subtitle: String {
        if folder.isPrivate && locked { return "Privada" }
        switch projects.count {
        case 0: return folder.isPrivate ? "Privada · vacía" : "Vacía"
        case 1: return folder.isPrivate ? "Privada · 1 proyecto" : "1 proyecto"
        default: return folder.isPrivate ? "Privada · \(projects.count) proyectos" : "\(projects.count) proyectos"
        }
    }

    /// Mosaico con hasta tres miniaturas. Las carpetas privadas cerradas no muestran nada de su contenido.
    @ViewBuilder
    private var preview: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        Color.clear
            .frame(height: 96)
            .overlay {
                if locked {
                    ZStack {
                        FolderPalette.gradient(folder.colorIndex).opacity(0.35)
                        LockPattern()
                        Image(systemName: "lock.fill")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(.white.opacity(0.9))
                            .shadow(color: .black.opacity(0.3), radius: 6, y: 3)
                    }
                } else {
                    let thumbs = projects.prefix(3).compactMap { ProjectThumbnail.load($0.thumbnailURL, modified: $0.modifiedAt) }
                    if thumbs.isEmpty {
                        ZStack {
                            FolderPalette.gradient(folder.colorIndex).opacity(0.22)
                            Image(systemName: folder.symbol)
                                .font(.system(size: 30, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.55))
                        }
                    } else {
                        HStack(spacing: 2) {
                            ForEach(Array(thumbs.enumerated()), id: \.offset) { _, image in
                                Image(decorative: image, scale: 1)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity)
                                    .clipped()
                            }
                        }
                    }
                }
            }
            .clipShape(shape)
            .overlay(shape.strokeBorder(Theme.stroke))
    }
}

/// Fondo decorativo de puntos para las carpetas bloqueadas.
private struct LockPattern: View {
    var body: some View {
        Canvas { context, size in
            let step: CGFloat = 14
            var y: CGFloat = 4
            var row = 0
            while y < size.height {
                var x: CGFloat = row.isMultiple(of: 2) ? 4 : 4 + step / 2
                while x < size.width {
                    context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 2.5, height: 2.5)), with: .color(.white.opacity(0.12)))
                    x += step
                }
                y += step
                row += 1
            }
        }
    }
}

/// Tarjeta para crear una carpeta nueva.
struct NewFolderTile: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(Theme.gradient)
            Text("Nueva carpeta")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
        }
        .frame(width: 130, height: 150)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                .foregroundStyle(Theme.textSecondary.opacity(0.6))
        }
        .foregroundStyle(.white)
        .contentShape(Rectangle())
    }
}

// MARK: - Crear / editar carpeta

struct FolderEditorSheet: View {
    /// nil = carpeta nueva.
    let existing: ProjectFolder?
    var onSaved: (ProjectFolder) -> Void = { _ in }

    @Environment(\.dismiss) private var dismiss
    @State private var folder: ProjectFolder
    @State private var password = ""
    @State private var confirm = ""
    @State private var changePassword = false
    @State private var error: String?

    init(existing: ProjectFolder?, onSaved: @escaping (ProjectFolder) -> Void = { _ in }) {
        self.existing = existing
        self.onSaved = onSaved
        _folder = State(initialValue: existing ?? ProjectFolder(name: ""))
    }

    /// Hay que pedir contraseña si se vuelve privada o si el usuario quiere cambiarla.
    private var needsPassword: Bool {
        folder.isPrivate && (existing?.isPrivate != true || changePassword)
    }

    private var canSave: Bool {
        !folder.name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        StudioSheet(title: existing == nil ? "Nueva carpeta" : "Editar carpeta",
                    symbol: existing == nil ? "folder.badge.plus" : "folder.fill",
                    subtitle: "Ordena tus proyectos a tu gusto") {
            HStack {
                Spacer()
                FolderBadge(folder: folder, size: 74, locked: folder.isPrivate)
                    .animation(Theme.spring, value: folder.isPrivate)
                    .animation(Theme.spring, value: folder.colorIndex)
                Spacer()
            }
            .padding(.vertical, 6)

            VStack(alignment: .leading, spacing: 8) {
                StudioSectionTitle(text: "Nombre", symbol: "textformat")
                TextField("Ej.: Vacaciones 2026", text: $folder.name)
                    .textFieldStyle(.plain)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .studioCard(padding: 12, cornerRadius: 12)
            }

            VStack(alignment: .leading, spacing: 10) {
                StudioSectionTitle(text: "Color", symbol: "paintpalette")
                HStack(spacing: 10) {
                    ForEach(FolderPalette.pairs.indices, id: \.self) { i in
                        Button { withAnimation(Theme.spring) { folder.colorIndex = i } } label: {
                            Circle()
                                .fill(FolderPalette.gradient(i))
                                .frame(width: 30, height: 30)
                                .overlay(Circle().strokeBorder(.white, lineWidth: folder.colorIndex == i ? 2.5 : 0))
                                .scaleEffect(folder.colorIndex == i ? 1.1 : 1)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                StudioSectionTitle(text: "Ícono", symbol: "square.grid.3x3")
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6), spacing: 8) {
                    ForEach(FolderPalette.symbols, id: \.self) { s in
                        Button { folder.symbol = s } label: {
                            Image(systemName: s)
                                .font(.system(size: 17, weight: .semibold))
                                .frame(maxWidth: .infinity, minHeight: 40)
                                .background {
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(folder.symbol == s ? AnyShapeStyle(FolderPalette.gradient(folder.colorIndex)) : AnyShapeStyle(Studio.card))
                                }
                                .foregroundStyle(.white)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            privacySection

            if let error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Studio.coral)
            }
        } actions: {
            Button("Cancelar") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Spacer()
            Button(existing == nil ? "Crear carpeta" : "Guardar") { save() }
                .buttonStyle(GradientButtonStyle())
                .disabled(!canSave)
                .keyboardShortcut(.defaultAction)
        }
        .animation(Theme.spring, value: folder.isPrivate)
        .animation(Theme.spring, value: changePassword)
    }

    private var privacySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: $folder.isPrivate) {
                HStack(spacing: 10) {
                    Image(systemName: "lock.fill")
                        .foregroundStyle(Studio.coral)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Carpeta privada").font(.subheadline.weight(.semibold))
                        Text("Pide contraseña para abrirla y oculta sus miniaturas")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .toggleStyle(.switch)
            .tint(Theme.accent)

            if folder.isPrivate {
                if existing?.isPrivate == true && !changePassword {
                    Button { changePassword = true } label: {
                        Label("Cambiar contraseña", systemImage: "key.fill")
                    }
                    .buttonStyle(ChipButtonStyle())
                }
                if needsPassword {
                    SecureField("Contraseña (mínimo 4 caracteres)", text: $password)
                        .textFieldStyle(.plain)
                        .studioCard(padding: 12, cornerRadius: 12)
                    SecureField("Repite la contraseña", text: $confirm)
                        .textFieldStyle(.plain)
                        .studioCard(padding: 12, cornerRadius: 12)
                    Text("Si la olvidas, podrás entrar con \(Biometrics.devicePasscodeName) y elegir otra.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if Biometrics.isAvailable {
                    Toggle(isOn: $folder.useBiometrics) {
                        Label("Abrir también con \(Biometrics.name)", systemImage: Biometrics.symbol)
                            .font(.subheadline.weight(.semibold))
                    }
                    .toggleStyle(.switch)
                    .tint(Theme.accent)
                }
            }
        }
        .studioCard()
    }

    private func save() {
        error = nil
        folder.name = folder.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if needsPassword {
            guard password.count >= 4 else { error = "La contraseña debe tener al menos 4 caracteres."; return }
            guard password == confirm else { error = "Las contraseñas no coinciden."; return }
        }
        if !folder.isPrivate { folder.useBiometrics = false }
        let store = FolderStore.shared
        let ok: Bool
        if existing == nil {
            ok = store.create(folder, password: needsPassword ? password : nil) != nil
        } else {
            ok = store.update(folder, password: needsPassword ? password : nil)
        }
        guard ok else { error = "No se pudo guardar la contraseña en el Llavero. Inténtalo de nuevo."; return }
        onSaved(folder)
        dismiss()
    }
}

// MARK: - Desbloquear carpeta privada

struct UnlockFolderSheet: View {
    let folder: ProjectFolder
    var onUnlocked: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var wrong = false
    @State private var shake: CGFloat = 0
    @State private var resetting = false
    @State private var newPassword = ""
    @State private var confirm = ""
    @State private var error: String?
    @FocusState private var focused: Bool

    var body: some View {
        ZStack {
            AuroraBackground(intensity: 0.8)
            VStack(spacing: 18) {
                HStack {
                    Spacer()
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .buttonStyle(ChipButtonStyle())
                        .keyboardShortcut(.cancelAction)
                }

                FolderBadge(folder: folder, size: 84, locked: true)
                    .padding(.top, 4)

                VStack(spacing: 4) {
                    Text(folder.name)
                        .font(.system(size: 22, weight: .heavy, design: .rounded))
                    Text(resetting ? "Elige una contraseña nueva" : "Carpeta privada")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(Theme.textSecondary)
                }

                if resetting { resetForm } else { unlockForm }
                Spacer(minLength: 0)
            }
            .padding(22)
        }
        .foregroundStyle(.white)
        .preferredColorScheme(.dark)
        #if os(macOS)
        .frame(width: 400, height: 470)
        #endif
        .task {
            if folder.useBiometrics && Biometrics.isAvailable {
                await tryDevice()
            } else {
                focused = true
            }
        }
    }

    private var unlockForm: some View {
        VStack(spacing: 14) {
            SecureField("Contraseña", text: $password)
                .textFieldStyle(.plain)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .multilineTextAlignment(.center)
                .focused($focused)
                .onSubmit(tryPassword)
                .padding(14)
                .background(Theme.surfaceRaised.opacity(0.8), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(wrong ? Studio.coral : Theme.stroke, lineWidth: wrong ? 1.5 : 1))
                .modifier(ShakeEffect(amount: shake))

            if wrong {
                Text("Contraseña incorrecta")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Studio.coral)
                    .transition(.opacity)
            }

            Button(action: tryPassword) {
                Label("Desbloquear", systemImage: "lock.open.fill").frame(maxWidth: .infinity)
            }
            .buttonStyle(GradientButtonStyle())
            .disabled(password.isEmpty)
            .keyboardShortcut(.defaultAction)

            if folder.useBiometrics && Biometrics.isAvailable {
                Button { Task { await tryDevice() } } label: {
                    Label("Usar \(Biometrics.name)", systemImage: Biometrics.symbol)
                }
                .buttonStyle(ChipButtonStyle())
            }

            Button("¿Olvidaste la contraseña?") {
                Task {
                    if await FolderStore.shared.unlockWithDevice(folder.id, allowDevicePasscode: true) {
                        withAnimation(Theme.spring) { resetting = true }
                    }
                }
            }
            .buttonStyle(.plain)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Theme.textSecondary)
        }
    }

    private var resetForm: some View {
        VStack(spacing: 12) {
            SecureField("Contraseña nueva (mínimo 4)", text: $newPassword)
                .textFieldStyle(.plain)
                .padding(13)
                .background(Theme.surfaceRaised.opacity(0.8), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            SecureField("Repítela", text: $confirm)
                .textFieldStyle(.plain)
                .padding(13)
                .background(Theme.surfaceRaised.opacity(0.8), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            if let error {
                Text(error).font(.footnote.weight(.semibold)).foregroundStyle(Studio.coral)
            }
            Button {
                guard newPassword.count >= 4 else { error = "Debe tener al menos 4 caracteres."; return }
                guard newPassword == confirm else { error = "Las contraseñas no coinciden."; return }
                guard FolderStore.shared.update(folder, password: newPassword) else {
                    error = "No se pudo guardar la contraseña."; return
                }
                finish()
            } label: {
                Label("Guardar y abrir", systemImage: "checkmark").frame(maxWidth: .infinity)
            }
            .buttonStyle(GradientButtonStyle())
            .keyboardShortcut(.defaultAction)
        }
    }

    private func tryPassword() {
        guard !password.isEmpty else { return }
        if FolderStore.shared.unlock(folder.id, password: password) {
            finish()
        } else {
            password = ""
            withAnimation(.default) { wrong = true }
            withAnimation(.linear(duration: 0.4)) { shake += 1 }
            focused = true
        }
    }

    private func tryDevice() async {
        if await FolderStore.shared.unlockWithDevice(folder.id) {
            finish()
        } else {
            focused = true
        }
    }

    private func finish() {
        dismiss()
        onUnlocked()
    }
}

/// Sacude horizontalmente (contraseña incorrecta).
private struct ShakeEffect: GeometryEffect {
    var amount: CGFloat
    var animatableData: CGFloat {
        get { amount }
        set { amount = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 10 * sin(amount * .pi * 6), y: 0))
    }
}
