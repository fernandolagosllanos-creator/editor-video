import Foundation
import AVFoundation
import Speech

/// Subtítulos automáticos con el reconocimiento de voz de Apple (framework Speech).
/// Es gratuito. Si el idioma está descargado en el dispositivo funciona sin internet.
enum CaptionGenerator {

    struct Word {
        let text: String
        let start: Double
        let end: Double
    }

    struct Language: Identifiable, Hashable {
        let id: String
        let label: String
    }

    static let languages: [Language] = [
        Language(id: "es-CL", label: "Español (Chile)"),
        Language(id: "es-ES", label: "Español (España)"),
        Language(id: "es-MX", label: "Español (México)"),
        Language(id: "es-US", label: "Español (EE. UU.)"),
        Language(id: "en-US", label: "Inglés (EE. UU.)"),
        Language(id: "pt-BR", label: "Portugués (Brasil)"),
        Language(id: "fr-FR", label: "Francés"),
        Language(id: "it-IT", label: "Italiano")
    ]

    /// Idioma por defecto: el del dispositivo si está en la lista, si no español de Chile.
    static var defaultLanguageID: String {
        let current = Locale.current.identifier.replacingOccurrences(of: "_", with: "-")
        if languages.contains(where: { $0.id == current }) { return current }
        if Locale.current.language.languageCode?.identifier == "en" { return "en-US" }
        return "es-CL"
    }

    enum CaptionError: LocalizedError {
        case notAuthorized, unavailable(String), noAudio, noSpeech, exportFailed(String)

        var errorDescription: String? {
            switch self {
            case .notAuthorized:
                return "Sin permiso para el reconocimiento de voz. Actívalo en Ajustes > Privacidad y seguridad > Reconocimiento de voz."
            case .unavailable(let lang):
                return "El reconocimiento de voz para \(lang) no está disponible ahora en este dispositivo. Prueba con otro idioma o revisa la conexión."
            case .noAudio:
                return "El video no tiene audio con voz. Graba una voz en off o usa un clip con sonido."
            case .noSpeech:
                return "No se detectó voz en el audio."
            case .exportFailed(let msg):
                return "No se pudo preparar el audio: \(msg)"
            }
        }
    }

    // MARK: - Permiso

    static func requestAuthorization() async -> Bool {
        let status: SFSpeechRecognizerAuthorizationStatus = await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0) }
        }
        return status == .authorized
    }

    /// true si el idioma se puede reconocer sin internet en este dispositivo.
    static func supportsOffline(_ languageID: String) -> Bool {
        SFSpeechRecognizer(locale: Locale(identifier: languageID))?.supportsOnDeviceRecognition ?? false
    }

    // MARK: - Audio a transcribir

    /// Exporta a .m4a el audio del video y de las voces en off (sin música), en el tiempo de la línea de tiempo.
    static func exportSpeechAudio(clips: [Clip], audioTracks: [AudioTrack]) async throws -> URL {
        let voices = audioTracks.filter { $0.kind == .voice }
        guard clips.contains(where: \.hasAudio) || !voices.isEmpty else { throw CaptionError.noAudio }
        let built = try await CompositionBuilder.build(clips: clips, audioTracks: voices, originalVolume: 1,
                                                       filter: .none, texts: [], forExport: false)
        guard let session = AVAssetExportSession(asset: built.composition, presetName: AVAssetExportPresetAppleM4A) else {
            throw CaptionError.exportFailed("formato no disponible")
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("subtitulos-\(UUID().uuidString)").appendingPathExtension("m4a")
        session.audioMix = built.audioMix
        if #available(iOS 18.0, macOS 15.0, *) {
            try await session.export(to: url, as: .m4a)
        } else {
            session.outputURL = url
            session.outputFileType = .m4a
            await session.export()
            guard session.status == .completed else {
                throw CaptionError.exportFailed(session.error?.localizedDescription ?? "error desconocido")
            }
        }
        return url
    }

    // MARK: - Reconocimiento

    /// Devuelve las palabras reconocidas con su tiempo. `progress` va de 0 a 1 (aproximado).
    @MainActor
    static func transcribe(url: URL, languageID: String, duration: Double,
                           progress: @escaping (Double) -> Void) async throws -> [Word] {
        guard await requestAuthorization() else { throw CaptionError.notAuthorized }
        let label = languages.first { $0.id == languageID }?.label ?? languageID
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: languageID)), recognizer.isAvailable else {
            throw CaptionError.unavailable(label)
        }
        let request = SFSpeechURLRecognitionRequest(url: url)
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        request.addsPunctuation = true
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        let listener = RecognitionListener(duration: duration, progress: progress)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { cont in
                listener.continuation = cont
                listener.task = recognizer.recognitionTask(with: request, delegate: listener)
            }
        } onCancel: {
            listener.cancel()
        }
    }

    // MARK: - Agrupar palabras en subtítulos

    /// Junta palabras en frases cortas y legibles (máx. ~5 palabras o 3 segundos).
    static func makeCaptions(from words: [Word], maxWords: Int = 5, maxDuration: Double = 3.0) -> [(text: String, start: Double, end: Double)] {
        var groups: [[Word]] = []
        var current: [Word] = []
        for word in words {
            if let first = current.first, let last = current.last {
                let gap = word.start - last.end
                let endsSentence = last.text.last.map { ".?!…".contains($0) } ?? false
                if current.count >= maxWords || word.end - first.start > maxDuration || gap > 0.7 || endsSentence {
                    groups.append(current)
                    current = []
                }
            }
            current.append(word)
        }
        if !current.isEmpty { groups.append(current) }

        var out: [(text: String, start: Double, end: Double)] = []
        for (i, g) in groups.enumerated() {
            let start = g.first!.start
            var end = max(g.last!.end + 0.25, start + 0.8)
            if i + 1 < groups.count { end = min(end, groups[i + 1].first!.start) }
            out.append((g.map(\.text).joined(separator: " "), start, max(end, start + 0.3)))
        }
        return out
    }
}

/// Recibe los resultados del reconocimiento. En audios largos Apple entrega varios resultados finales
/// (uno por tramo), así que se van juntando hasta que termina.
private final class RecognitionListener: NSObject, SFSpeechRecognitionTaskDelegate {
    var continuation: CheckedContinuation<[CaptionGenerator.Word], Error>?
    var task: SFSpeechRecognitionTask?
    private var words: [CaptionGenerator.Word] = []
    private let duration: Double
    private let progress: (Double) -> Void
    private var finished = false

    init(duration: Double, progress: @escaping (Double) -> Void) {
        self.duration = duration
        self.progress = progress
    }

    func cancel() {
        task?.cancel()
    }

    func speechRecognitionTask(_ task: SFSpeechRecognitionTask, didHypothesizeTranscription transcription: SFTranscription) {
        guard duration > 0, let last = transcription.segments.last else { return }
        progress(min(0.99, (last.timestamp + last.duration) / duration))
    }

    func speechRecognitionTask(_ task: SFSpeechRecognitionTask, didFinishRecognition result: SFSpeechRecognitionResult) {
        let lastEnd = words.last?.end ?? -1
        for seg in result.bestTranscription.segments {
            let text = seg.substring.trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { continue }
            // Se descartan palabras repetidas de un tramo anterior.
            guard seg.timestamp >= lastEnd - 0.05 else { continue }
            words.append(.init(text: text, start: seg.timestamp, end: seg.timestamp + seg.duration))
        }
        if duration > 0, let last = words.last { progress(min(0.99, last.end / duration)) }
    }

    func speechRecognitionTask(_ task: SFSpeechRecognitionTask, didFinishSuccessfully successfully: Bool) {
        guard !finished else { return }
        finished = true
        if !words.isEmpty {
            progress(1)
            continuation?.resume(returning: words)
        } else if successfully {
            continuation?.resume(throwing: CaptionGenerator.CaptionError.noSpeech)
        } else if let error = task.error as NSError?, error.domain == "kAFAssistantErrorDomain", error.code == 1110 {
            continuation?.resume(throwing: CaptionGenerator.CaptionError.noSpeech)
        } else if task.isCancelled {
            continuation?.resume(throwing: CancellationError())
        } else {
            continuation?.resume(throwing: task.error ?? CaptionGenerator.CaptionError.noSpeech)
        }
        continuation = nil
    }
}
