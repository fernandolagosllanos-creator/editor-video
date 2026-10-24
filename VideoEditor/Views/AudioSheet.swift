import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

// MARK: - Audio: sonido original, música y voces

struct AudioSheet: View {
    @Bindable var model: EditorModel
    @Environment(\.dismiss) private var dismiss
    @State private var showImporter = false
    @State private var videoItem: PhotosPickerItem?
    @State private var originalVolume: Float = 1
    @State private var isLoading = false

    private var music: [AudioTrack] { model.audioTracks.filter { $0.kind == .music } }
    private var voices: [AudioTrack] { model.audioTracks.filter { $0.kind == .voice } }

    var body: some View {
        StudioSheet(title: "Audio", symbol: "music.note",
                    subtitle: "Música de fondo, voces y sonido del video") {
            originalCard

            HStack {
                StudioSectionTitle(text: "Música", symbol: "music.note.list")
                Spacer()
                if isLoading { ProgressView().controlSize(.small) }
            }
            HStack(spacing: 10) {
                addButton("Archivo", "folder.fill") { showImporter = true }
                PhotosPicker(selection: $videoItem, matching: .videos) {
                    addLabel("De un video", "film.fill")
                }
                .buttonStyle(.plain)
            }
            if music.isEmpty {
                Text("Agrega una canción desde Archivos, o saca el audio de cualquier video de tu galería. Usa música propia o libre de derechos (por ejemplo la Biblioteca de audio de YouTube, que es gratis). Las canciones de Apple Music están protegidas y no se pueden usar.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            ForEach(music) { track in
                AudioTrackCard(model: model, track: track)
            }

            if !voices.isEmpty {
                StudioSectionTitle(text: "Voces en off", symbol: "mic.fill").padding(.top, 4)
                ForEach(voices) { track in
                    AudioTrackCard(model: model, track: track)
                }
            }
        } actions: {
            Spacer()
            Button("Listo") { dismiss() }
                .buttonStyle(StudioButtonStyle())
                .frame(maxWidth: 160)
                .keyboardShortcut(.defaultAction)
        }
        .onAppear { originalVolume = model.originalVolume }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.audio, .mp3, .mpeg4Audio, .wav, .aiff, .movie],
                      allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let url = urls.first {
                Task {
                    isLoading = true
                    defer { isLoading = false }
                    do {
                        let copy = try MediaStore.importCopy(from: url)
                        await model.addAudio(from: copy, kind: .music, name: url.deletingPathExtension().lastPathComponent)
                    } catch {
                        model.errorMessage = error.localizedDescription
                    }
                }
            }
        }
        .onChange(of: videoItem) { _, item in
            guard let item else { return }
            Task {
                isLoading = true
                defer { isLoading = false; videoItem = nil }
                do {
                    if let movie = try await item.loadTransferable(type: MovieFile.self) {
                        await model.addAudio(from: movie.url, kind: .music, name: "Audio de video")
                    }
                } catch {
                    model.errorMessage = error.localizedDescription
                }
            }
        }
    }

    private var originalCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "video.fill").foregroundStyle(Studio.violet)
                Text("Sonido original del video").font(.subheadline.weight(.semibold))
                Spacer()
                Button {
                    originalVolume = originalVolume == 0 ? 1 : 0
                    model.setOriginalVolume(originalVolume)
                } label: {
                    Label(originalVolume == 0 ? "Silenciado" : "Silenciar",
                          systemImage: originalVolume == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Capsule().fill(originalVolume == 0 ? Studio.coral.opacity(0.35) : Studio.card))
                }
                .buttonStyle(.plain)
            }
            PercentSlider(value: $originalVolume) { model.setOriginalVolume(originalVolume) }
        }
        .studioCard()
    }

    private func addButton(_ title: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { addLabel(title, symbol) }.buttonStyle(.plain)
    }

    private func addLabel(_ title: String, _ symbol: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
            Text(title)
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.white)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Studio.musicGradient).opacity(0.85))
    }
}

// MARK: - Tarjeta de una pista

private struct AudioTrackCard: View {
    @Bindable var model: EditorModel
    @State var track: AudioTrack
    @State private var expanded = true

    private var isMusic: Bool { track.kind == .music }
    private var fileLength: Double { track.assetDuration.seconds }
    private var maxFade: Double { max(0.5, min(5, track.playedDuration(total: model.duration) / 2)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: track.kind.symbol)
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(isMusic ? Studio.musicGradient : Studio.voiceGradient))
                VStack(alignment: .leading, spacing: 2) {
                    Text(track.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                    Text("Desde \(formatTime(track.start)) · \(formatTime(track.playedDuration(total: model.duration)))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button { withAnimation(.snappy) { expanded.toggle() } } label: {
                    Image(systemName: "chevron.down").rotationEffect(.degrees(expanded ? 0 : -90))
                }
                .buttonStyle(.borderless)
                Button(role: .destructive) { model.removeAudio(id: track.id) } label: { Image(systemName: "trash") }
                    .buttonStyle(.borderless)
            }

            if expanded {
                labeled("Volumen", symbol: "speaker.wave.2.fill") {
                    PercentSlider(value: $track.volume) { commit() }
                }
                labeled("Empieza en \(formatTime(track.start))", symbol: "arrow.right.to.line") {
                    HStack {
                        Slider(value: $track.start, in: 0...max(0.1, model.duration)) { if !$0 { commit() } }
                        Button("Cabezal") { track.start = model.currentTime; commit() }
                            .font(.caption).buttonStyle(.bordered)
                    }
                }
                if isMusic, fileLength > 1 {
                    labeled("Parte de la canción: desde \(formatTime(track.sourceOffset))", symbol: "scissors") {
                        Slider(value: $track.sourceOffset, in: 0...max(0.1, fileLength - 1)) { if !$0 { commit() } }
                    }
                }
                HStack(spacing: 14) {
                    labeled("Entrada \(String(format: "%.1f", track.fadeIn)) s", symbol: "waveform.path.ecg") {
                        Slider(value: $track.fadeIn, in: 0...maxFade) { if !$0 { commit() } }
                    }
                    labeled("Salida \(String(format: "%.1f", track.fadeOut)) s", symbol: "waveform.path") {
                        Slider(value: $track.fadeOut, in: 0...maxFade) { if !$0 { commit() } }
                    }
                }
                if isMusic {
                    HStack(spacing: 8) {
                        chip("Repetir hasta el final", "repeat", isOn: track.loops) { track.loops.toggle(); commit() }
                        chip("Bajar con la voz", "person.wave.2.fill", isOn: track.ducking) { track.ducking.toggle(); commit() }
                    }
                }
            }
        }
        .studioCard()
        .onChange(of: model.audioTracks.first(where: { $0.id == track.id })?.start) { _, newStart in
            if let newStart, newStart != track.start { track.start = newStart }
        }
    }

    private func commit() { model.update(track) }

    private func labeled<C: View>(_ title: String, symbol: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: symbol).font(.caption).foregroundStyle(.secondary)
            content()
        }
    }

    private func chip(_ title: String, _ symbol: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(Capsule().fill(isOn ? AnyShapeStyle(Studio.musicGradient) : AnyShapeStyle(Studio.card)))
                .overlay(Capsule().stroke(Studio.stroke))
                .foregroundStyle(isOn ? AnyShapeStyle(Color.white) : AnyShapeStyle(.secondary))
        }
        .buttonStyle(.plain)
    }
}

/// Control deslizante de volumen con el porcentaje a la derecha. `onCommit` se llama al soltarlo.
struct PercentSlider: View {
    @Binding var value: Float
    var range: ClosedRange<Float> = 0...1
    var onCommit: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "speaker.fill").font(.caption).foregroundStyle(.secondary)
            Slider(value: $value, in: range) { editing in if !editing { onCommit() } }
                .tint(Studio.violet)
            Text("\(Int((value * 100).rounded()))%")
                .font(.caption.monospacedDigit())
                .frame(width: 44, alignment: .trailing)
        }
    }
}
