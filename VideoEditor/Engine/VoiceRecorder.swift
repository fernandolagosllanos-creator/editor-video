import Foundation
import AVFoundation
import Observation

/// Graba la voz en off con el micrófono del iPhone o del Mac (archivo .m4a dentro de MediaStore).
@MainActor
@Observable
final class VoiceRecorder {
    enum State: Equatable {
        case idle, countdown(Int), recording
    }

    private(set) var state: State = .idle
    private(set) var elapsed: Double = 0
    /// Nivel de entrada 0...1 de las últimas mediciones (para dibujar las barras).
    private(set) var levels: [Float] = Array(repeating: 0, count: 40)

    @ObservationIgnored private var recorder: AVAudioRecorder?
    @ObservationIgnored private var meterTask: Task<Void, Never>?
    @ObservationIgnored private var countdownTask: Task<Void, Never>?
    @ObservationIgnored private(set) var currentURL: URL?

    var isRecording: Bool { state == .recording }

    // MARK: - Permiso

    static func requestPermission() async -> Bool {
        #if os(iOS)
        return await AVAudioApplication.requestRecordPermission()
        #else
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .audio)
        default: return false
        }
        #endif
    }

    // MARK: - Grabar

    /// Cuenta 3‑2‑1 y luego llama a `onStart` justo cuando empieza a grabar.
    func start(countdown: Bool, onStart: @escaping @MainActor () -> Void) throws {
        let url = MediaStore.makeURL(ext: "m4a")
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
        try session.setActive(true)
        #endif
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        let recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder.isMeteringEnabled = true
        guard recorder.prepareToRecord() else { throw RecorderError.cannotStart }
        self.recorder = recorder
        currentURL = url
        elapsed = 0
        levels = Array(repeating: 0, count: levels.count)

        let begin = { [weak self] in
            guard let self, let recorder = self.recorder else { return }
            guard recorder.record() else {
                self.state = .idle
                return
            }
            self.state = .recording
            onStart()
            self.startMetering()
        }

        if countdown {
            countdownTask = Task { [weak self] in
                for n in stride(from: 3, through: 1, by: -1) {
                    self?.state = .countdown(n)
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    if Task.isCancelled { return }
                }
                begin()
            }
        } else {
            begin()
        }
    }

    /// Detiene la grabación y devuelve el archivo (nil si se canceló o duró menos de medio segundo).
    func stop() -> URL? {
        countdownTask?.cancel()
        meterTask?.cancel()
        let duration = recorder?.currentTime ?? 0
        let wasRecording = state == .recording
        recorder?.stop()
        recorder = nil
        state = .idle
        restoreSession()
        guard wasRecording, duration > 0.5, let url = currentURL else {
            if let url = currentURL { try? FileManager.default.removeItem(at: url) }
            currentURL = nil
            return nil
        }
        currentURL = nil
        return url
    }

    func cancel() {
        _ = stop()
    }

    private func startMetering() {
        meterTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, let recorder = self.recorder else { return }
                recorder.updateMeters()
                let db = recorder.averagePower(forChannel: 0)
                // -50 dB = silencio, 0 dB = máximo.
                let level = max(0, min(1, (db + 50) / 50))
                self.levels.removeFirst()
                self.levels.append(level)
                self.elapsed = recorder.currentTime
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
        }
    }

    private func restoreSession() {
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        #endif
    }
}

enum RecorderError: LocalizedError {
    case cannotStart
    case noPermission

    var errorDescription: String? {
        switch self {
        case .cannotStart: return "No se pudo iniciar la grabación."
        case .noPermission:
            #if os(iOS)
            return "Sin permiso para usar el micrófono. Actívalo en Ajustes > Privacidad y seguridad > Micrófono."
            #else
            return "Sin permiso para usar el micrófono. Actívalo en Ajustes del Sistema > Privacidad y seguridad > Micrófono."
            #endif
        }
    }
}
