import SwiftUI

/// Subtítulos automáticos: escucha la voz del video (y las voces en off) y crea los textos con su tiempo.
struct CaptionsSheet: View {
    @Bindable var model: EditorModel
    @Environment(\.dismiss) private var dismiss

    @AppStorage("captionLanguage") private var languageID = CaptionGenerator.defaultLanguageID
    @State private var style: CaptionStyle = .boxed
    @State private var position: CaptionPosition = .bottom
    @State private var phase: Phase = .idle
    @State private var progress: Double = 0
    @State private var job: Task<Void, Never>?

    enum Phase: Equatable { case idle, preparing, listening, done(Int) }

    private var isWorking: Bool { phase == .preparing || phase == .listening }
    private var languageLabel: String {
        CaptionGenerator.languages.first { $0.id == languageID }?.label ?? languageID
    }

    var body: some View {
        StudioSheet(title: "Subtítulos automáticos", symbol: "captions.bubble.fill",
                    subtitle: "Gratis, con el reconocimiento de voz de Apple") {
            languageCard
            StudioSectionTitle(text: "Estilo", symbol: "paintpalette.fill")
            styleGrid
            StudioSectionTitle(text: "Posición", symbol: "arrow.up.and.down")
            positionPicker
            statusCard
        } actions: {
            if !model.captions.isEmpty && !isWorking {
                Button(role: .destructive) { model.removeCaptions(); phase = .idle } label: {
                    Label("Borrar", systemImage: "trash")
                }
            }
            Spacer()
            if isWorking {
                Button("Cancelar") { job?.cancel() }
            } else {
                Button("Listo") { dismiss() }
                Button { generate() } label: {
                    Label(model.captions.isEmpty ? "Generar" : "Volver a generar", systemImage: "sparkles")
                }
                .buttonStyle(StudioButtonStyle())
                .frame(maxWidth: 220)
                .keyboardShortcut(.defaultAction)
            }
        }
        .interactiveDismissDisabled(isWorking)
        .onAppear {
            if let first = model.captions.first {
                style = CaptionStyle.matching(first)
                position = CaptionPosition.matching(Double(first.position.y))
            }
        }
        .onDisappear { job?.cancel() }
    }

    // MARK: - Idioma

    private var languageCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "globe").font(.title3).foregroundStyle(Studio.violet)
            VStack(alignment: .leading, spacing: 3) {
                Text("Idioma de la voz").font(.caption).foregroundStyle(.secondary)
                Picker("Idioma", selection: $languageID) {
                    ForEach(CaptionGenerator.languages) { Text($0.label).tag($0.id) }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .disabled(isWorking)
            }
            Spacer()
            let offline = CaptionGenerator.supportsOffline(languageID)
            Label(offline ? "Sin internet" : "Usa internet", systemImage: offline ? "checkmark.seal.fill" : "wifi")
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(Capsule().fill(offline ? Studio.teal.opacity(0.25) : Studio.amber.opacity(0.25)))
                .foregroundStyle(offline ? Studio.teal : Studio.amber)
        }
        .studioCard()
    }

    // MARK: - Estilos

    private var styleGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 10)], spacing: 10) {
            ForEach(CaptionStyle.allCases) { s in
                Button {
                    style = s
                    if !model.captions.isEmpty { model.applyCaptionStyle(s, position: position) }
                } label: {
                    StylePreview(style: s, isSelected: s == style)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var positionPicker: some View {
        HStack(spacing: 8) {
            ForEach(CaptionPosition.allCases) { p in
                Button {
                    position = p
                    if !model.captions.isEmpty { model.applyCaptionStyle(style, position: p) }
                } label: {
                    Label(p.label, systemImage: p.symbol)
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .fill(p == position ? AnyShapeStyle(Studio.gradient) : AnyShapeStyle(Studio.card)))
                        .foregroundStyle(p == position ? AnyShapeStyle(Color.white) : AnyShapeStyle(.secondary))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Estado

    @ViewBuilder
    private var statusCard: some View {
        switch phase {
        case .idle:
            if model.captions.isEmpty {
                tip("Escucharemos el audio de tus clips y las voces en off (la música no) y crearemos los subtítulos con su tiempo exacto. Después puedes tocar cualquiera en la línea de tiempo para corregirlo.")
            } else {
                tip("Hay \(model.captions.count) subtítulos. Cambia el estilo o la posición y se aplica a todos al instante.")
            }
        case .preparing:
            working("Preparando el audio…", value: nil)
        case .listening:
            working("Escuchando en \(languageLabel)… \(Int(progress * 100))%", value: progress)
        case .done(let n):
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill").font(.title2).foregroundStyle(Studio.teal)
                VStack(alignment: .leading, spacing: 2) {
                    Text("¡Listo! \(n) subtítulos creados").font(.subheadline.weight(.semibold))
                    Text("Dale ▶ para verlos. Toca uno en la línea de tiempo para editar el texto.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .studioCard()
        }
    }

    private func tip(_ text: String) -> some View {
        Label(text, systemImage: "lightbulb.fill")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .studioCard()
    }

    private func working(_ title: String, value: Double?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.subheadline.weight(.semibold))
            if let value {
                ProgressView(value: value).tint(Studio.coral)
            } else {
                ProgressView().progressViewStyle(.linear).tint(Studio.coral)
            }
        }
        .studioCard()
    }

    // MARK: - Generar

    private func generate() {
        model.player.pause()
        progress = 0
        phase = .preparing
        let clips = model.clips, tracks = model.audioTracks, duration = model.duration
        let language = languageID, style = style, position = position
        job = Task {
            do {
                let audio = try await CaptionGenerator.exportSpeechAudio(clips: clips, audioTracks: tracks)
                defer { try? FileManager.default.removeItem(at: audio) }
                try Task.checkCancellation()
                phase = .listening
                let words = try await CaptionGenerator.transcribe(url: audio, languageID: language, duration: duration) { p in
                    progress = p
                }
                let items = CaptionGenerator.makeCaptions(from: words)
                model.setCaptions(items, style: style, position: position)
                phase = .done(items.count)
                model.seek(to: items.first?.start ?? 0)
            } catch is CancellationError {
                phase = .idle
            } catch {
                phase = .idle
                if !Task.isCancelled { model.errorMessage = error.localizedDescription }
            }
        }
    }
}

/// Muestra de un estilo de subtítulo sobre un fondo tipo video.
private struct StylePreview: View {
    let style: CaptionStyle
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                LinearGradient(colors: [Color(red: 0.2, green: 0.25, blue: 0.4), Color(red: 0.45, green: 0.3, blue: 0.5)],
                               startPoint: .top, endPoint: .bottom)
                Text("Hola a todos")
                    .font(.system(size: 13 * style.fontSize / 0.055, weight: .bold))
                    .foregroundStyle(style.color.color)
                    .shadow(color: .black.opacity(style.hasBackground ? 0 : 0.9), radius: 1.5, y: 1)
                    .padding(.horizontal, style.hasBackground ? 7 : 0)
                    .padding(.vertical, style.hasBackground ? 3 : 0)
                    .background {
                        if style.hasBackground {
                            RoundedRectangle(cornerRadius: 5).fill(Color.black.opacity(0.62))
                        }
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.horizontal, 6)
            }
            .frame(height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isSelected ? AnyShapeStyle(Studio.gradient) : AnyShapeStyle(Studio.stroke), lineWidth: isSelected ? 2.5 : 1))

            Text(style.label)
                .font(.caption.weight(isSelected ? .bold : .regular))
                .foregroundStyle(isSelected ? .primary : .secondary)
        }
    }
}
