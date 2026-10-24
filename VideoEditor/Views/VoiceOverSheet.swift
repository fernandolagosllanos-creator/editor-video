import SwiftUI

/// Grabar voz en off: el video avanza en silencio mientras hablas, y la grabación queda en la línea de
/// tiempo justo donde empezaste.
struct VoiceOverSheet: View {
    @Bindable var model: EditorModel
    @Environment(\.dismiss) private var dismiss
    @State private var recorder = VoiceRecorder()
    @State private var useCountdown = true
    @State private var recordStart: Double = 0
    @State private var pulse = false

    private var voiceTracks: [AudioTrack] { model.audioTracks.filter { $0.kind == .voice } }

    var body: some View {
        StudioSheet(title: "Voz en off", symbol: "mic.fill",
                    subtitle: "Narra sobre tu video con el micrófono") {
            recorderCard
            if !voiceTracks.isEmpty {
                StudioSectionTitle(text: "Grabaciones", symbol: "waveform")
                ForEach(voiceTracks) { track in
                    takeRow(track)
                }
            }
        } actions: {
            Toggle(isOn: $useCountdown) { Label("3‑2‑1", systemImage: "timer") }
                .toggleStyle(.button)
                .disabled(recorder.state != .idle)
            Spacer()
            Button("Listo") {
                finish()
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
        }
        .onDisappear { finish() }
        #if os(iOS)
        .presentationDetents([.height(430), .large])
        .presentationBackgroundInteraction(.enabled(upThrough: .height(430)))
        #endif
    }

    // MARK: - Tarjeta principal

    private var recorderCard: some View {
        VStack(spacing: 16) {
            LevelBars(levels: recorder.levels, active: recorder.isRecording)
                .frame(height: 56)

            Group {
                switch recorder.state {
                case .countdown(let n):
                    Text("\(n)").font(.system(size: 40, weight: .heavy, design: .rounded))
                        .foregroundStyle(Studio.gradient)
                        .contentTransition(.numericText())
                case .recording:
                    Text(formatTime(recorder.elapsed))
                        .font(.system(size: 34, weight: .bold, design: .monospaced))
                case .idle:
                    Text("Empieza en \(formatTime(model.currentTime))")
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(height: 44)
            .animation(.snappy, value: recorder.state)

            Button(action: toggle) {
                ZStack {
                    Circle()
                        .stroke(Studio.coral.opacity(0.35), lineWidth: 6)
                        .frame(width: 92, height: 92)
                        .scaleEffect(recorder.isRecording && pulse ? 1.18 : 1)
                        .opacity(recorder.isRecording ? 1 : 0.6)
                    Circle()
                        .fill(Studio.voiceGradient)
                        .frame(width: 74, height: 74)
                        .shadow(color: Studio.coral.opacity(0.6), radius: recorder.isRecording ? 16 : 6)
                    if recorder.state == .idle {
                        Image(systemName: "mic.fill").font(.system(size: 28, weight: .bold)).foregroundStyle(.white)
                    } else {
                        RoundedRectangle(cornerRadius: 6).fill(.white).frame(width: 26, height: 26)
                    }
                }
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut("r", modifiers: [])
            .onAppear {
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) { pulse = true }
            }

            Text(hint)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .studioCard(padding: 18, cornerRadius: 22)
    }

    private var hint: String {
        switch recorder.state {
        case .idle: return "Toca el botón para grabar. El video se reproduce sin sonido mientras hablas para que no se cuele en la grabación."
        case .countdown: return "Prepárate…"
        case .recording: return "Grabando. Toca de nuevo para terminar."
        }
    }

    private func takeRow(_ track: AudioTrack) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "mic.fill")
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(Circle().fill(Studio.voiceGradient))
            VStack(alignment: .leading, spacing: 2) {
                Text(track.name).font(.subheadline.weight(.semibold))
                Text("\(formatTime(track.start)) · dura \(formatTime(track.assetDuration.seconds))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button { model.seek(to: track.start) } label: { Image(systemName: "play.circle.fill").font(.title2) }
                .buttonStyle(.borderless)
            Button(role: .destructive) { model.removeAudio(id: track.id) } label: { Image(systemName: "trash") }
                .buttonStyle(.borderless)
        }
        .studioCard(padding: 10, cornerRadius: 14)
    }

    // MARK: - Acciones

    private func toggle() {
        if recorder.state == .idle {
            Task { await begin() }
        } else {
            finish()
        }
    }

    private func begin() async {
        guard await VoiceRecorder.requestPermission() else {
            model.errorMessage = RecorderError.noPermission.errorDescription
            return
        }
        do {
            try recorder.start(countdown: useCountdown) {
                recordStart = model.currentTime
                model.player.isMuted = true
                model.player.play()
                model.isPlaying = true
            }
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }

    private func finish() {
        guard recorder.state != .idle else { return }
        let start = recordStart
        let url = recorder.stop()
        model.player.pause()
        model.player.isMuted = false
        model.isPlaying = false
        guard let url else { return }
        let number = voiceTracks.count + 1
        Task {
            await model.addAudio(from: url, kind: .voice, name: "Voz \(number)", start: start)
            model.seek(to: start)
        }
    }
}

/// Barras de nivel del micrófono.
struct LevelBars: View {
    let levels: [Float]
    let active: Bool

    var body: some View {
        GeometryReader { geo in
            let count = levels.count
            let spacing: CGFloat = 3
            let width = max(1, (geo.size.width - spacing * CGFloat(count - 1)) / CGFloat(count))
            HStack(alignment: .center, spacing: spacing) {
                ForEach(Array(levels.enumerated()), id: \.offset) { _, level in
                    Capsule()
                        .fill(active ? AnyShapeStyle(Studio.voiceGradient) : AnyShapeStyle(Color.white.opacity(0.18)))
                        .frame(width: width, height: max(4, CGFloat(level) * geo.size.height))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.linear(duration: 0.05), value: levels)
        }
    }
}
