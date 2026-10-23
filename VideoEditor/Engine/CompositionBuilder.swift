import Foundation
import AVFoundation
import CoreMedia
import QuartzCore
import CoreText
import CoreGraphics

struct BuiltComposition {
    let composition: AVComposition
    let videoComposition: AVMutableVideoComposition
    let audioMix: AVMutableAudioMix
    let duration: CMTime
    let renderSize: CGSize
}

enum BuildError: LocalizedError {
    case noClips
    case noVideoTrack(String)
    case cannotCreateTrack

    var errorDescription: String? {
        switch self {
        case .noClips: return "No hay clips en la línea de tiempo."
        case .noVideoTrack(let name): return "El archivo \(name) no tiene pista de video."
        case .cannotCreateTrack: return "No se pudo crear la composición."
        }
    }
}

/// Arma la AVComposition (video + audio), la AVVideoComposition con el compositor de transiciones y
/// la mezcla de audio a partir del estado del editor.
enum CompositionBuilder {

    static func renderSize(for clips: [Clip]) -> CGSize {
        guard let first = clips.first else { return CGSize(width: 1920, height: 1080) }
        var size = first.displaySize
        let maxSide: CGFloat = 1920
        let longest = max(size.width, size.height)
        if longest > maxSide {
            let s = maxSide / longest
            size = CGSize(width: size.width * s, height: size.height * s)
        }
        // Dimensiones pares (requisito de los codificadores H.264).
        return CGSize(width: floor(size.width / 2) * 2, height: floor(size.height / 2) * 2)
    }

    static func build(clips: [Clip],
                      audioTracks: [AudioTrack],
                      originalVolume: Float,
                      filter: VideoFilter,
                      texts: [TextOverlay],
                      forExport: Bool,
                      outputSize: CGSize? = nil) async throws -> BuiltComposition {
        guard !clips.isEmpty else { throw BuildError.noClips }

        let composition = AVMutableComposition()
        guard
            let videoA = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
            let videoB = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
            let audioA = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid),
            let audioB = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        else { throw BuildError.cannotCreateTrack }

        let videoTracks = [videoA, videoB]
        let originalAudioTracks = [audioA, audioB]
        let placements = Timeline.placements(for: clips)
        let total = placements.last?.end ?? .zero

        // Los clips se alternan entre dos pistas (A/B) para poder solaparlos en las transiciones.
        var layouts: [UUID: ClipLayout] = [:]
        for (i, p) in placements.enumerated() {
            let asset = AVURLAsset(url: p.clip.url)
            guard let sourceVideo = try await asset.loadTracks(withMediaType: .video).first else {
                throw BuildError.noVideoTrack(p.clip.name)
            }
            let range = CMTimeRange(start: p.clip.start, duration: p.clip.duration)
            let videoTrack = videoTracks[i % 2]
            try videoTrack.insertTimeRange(range, of: sourceVideo, at: p.start)
            layouts[p.clip.id] = ClipLayout(trackID: videoTrack.trackID,
                                            naturalSize: p.clip.naturalSize,
                                            preferredTransform: p.clip.preferredTransform)

            if let sourceAudio = try await asset.loadTracks(withMediaType: .audio).first {
                try originalAudioTracks[i % 2].insertTimeRange(range, of: sourceAudio, at: p.start)
            }
        }

        // Instrucciones de video: una por tramo, con o sin transición.
        var sorted: [CMTime] = []
        for t in placements.flatMap({ [$0.start, $0.end] }).sorted() where sorted.last != t {
            sorted.append(t)
        }
        var instructions: [TransitionInstruction] = []
        for (a, b) in zip(sorted, sorted.dropFirst()) where b > a {
            let mid = a + CMTimeMultiplyByFloat64(b - a, multiplier: 0.5)
            let active = placements.filter { $0.start <= mid && mid < $0.end }.sorted { $0.start < $1.start }
            guard let fg = active.last, let fgLayout = layouts[fg.clip.id] else { continue }
            let range = CMTimeRange(start: a, end: b)
            if active.count >= 2, let bg = active.first, let bgLayout = layouts[bg.clip.id] {
                instructions.append(TransitionInstruction(timeRange: range, foreground: fgLayout, background: bgLayout,
                                                          transition: bg.clip.transitionOut, filter: filter))
            } else {
                instructions.append(TransitionInstruction(timeRange: range, foreground: fgLayout, background: nil,
                                                          transition: .none, filter: filter))
            }
        }

        // Las instrucciones deben cubrir exactamente la duración de la composición.
        let compositionDuration = try await composition.load(.duration)
        if let last = instructions.last, compositionDuration > last.timeRange.end {
            instructions[instructions.count - 1] = TransitionInstruction(
                timeRange: CMTimeRange(start: last.timeRange.start, end: compositionDuration),
                foreground: last.foreground, background: last.background,
                transition: last.transition, filter: last.filter)
        }

        // Mezcla de audio: volumen del audio original y fundidos en las transiciones.
        var inputParameters: [AVMutableAudioMixInputParameters] = []
        let originalParams = originalAudioTracks.map { AVMutableAudioMixInputParameters(track: $0) }
        for (i, p) in placements.enumerated() {
            let params = originalParams[i % 2]
            let hasTransitionIn = i > 0 && Timeline.transitionDuration(clips: clips, at: i - 1) > 0
            if hasTransitionIn {
                let overlap = CMTimeRange(start: p.start, end: placements[i - 1].end)
                params.setVolumeRamp(fromStartVolume: 0, toEndVolume: originalVolume, timeRange: overlap)
            } else {
                params.setVolume(originalVolume, at: p.start)
            }
            if i < placements.count - 1, Timeline.transitionDuration(clips: clips, at: i) > 0 {
                let overlap = CMTimeRange(start: placements[i + 1].start, end: p.end)
                params.setVolumeRamp(fromStartVolume: originalVolume, toEndVolume: 0, timeRange: overlap)
            }
        }
        inputParameters.append(contentsOf: originalParams)

        // Pistas de audio agregadas (música, voz, etc.).
        for track in audioTracks {
            let startTime = Timeline.time(track.start)
            guard startTime < total else { continue }
            let asset = AVURLAsset(url: track.url)
            guard let source = try await asset.loadTracks(withMediaType: .audio).first,
                  let compTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
            else { continue }
            let available = total - startTime
            let length = min(track.assetDuration, available)
            try compTrack.insertTimeRange(CMTimeRange(start: .zero, duration: length), of: source, at: startTime)
            let params = AVMutableAudioMixInputParameters(track: compTrack)
            params.setVolume(track.volume, at: .zero)
            inputParameters.append(params)
        }

        let audioMix = AVMutableAudioMix()
        audioMix.inputParameters = inputParameters

        let size = outputSize ?? renderSize(for: clips)
        let videoComposition = AVMutableVideoComposition()
        videoComposition.customVideoCompositorClass = TransitionCompositor.self
        videoComposition.renderSize = size
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
        videoComposition.instructions = instructions

        if forExport, !texts.isEmpty {
            videoComposition.animationTool = makeAnimationTool(texts: texts, renderSize: size)
        }

        let immutable = composition.copy() as! AVComposition
        return BuiltComposition(composition: immutable, videoComposition: videoComposition,
                                audioMix: audioMix, duration: compositionDuration, renderSize: size)
    }

    // MARK: - Textos para exportación (Core Animation)

    static func makeAnimationTool(texts: [TextOverlay], renderSize: CGSize) -> AVVideoCompositionCoreAnimationTool {
        let frame = CGRect(origin: .zero, size: renderSize)
        let videoLayer = CALayer()
        videoLayer.frame = frame
        let parent = CALayer()
        parent.frame = frame
        parent.isGeometryFlipped = false
        parent.addSublayer(videoLayer)

        for t in texts {
            let layer = CATextLayer()
            let size = CGFloat(t.fontSize) * renderSize.height
            layer.string = t.text
            layer.font = CTFontCreateWithName("HelveticaNeue-Bold" as CFString, size, nil)
            layer.fontSize = size
            layer.foregroundColor = t.color.cgColor
            layer.alignmentMode = .center
            layer.isWrapped = true
            layer.contentsScale = 1
            layer.shadowColor = CGColor(red: 0, green: 0, blue: 0, alpha: 1)
            layer.shadowOpacity = 0.85
            layer.shadowRadius = size * 0.06
            layer.shadowOffset = CGSize(width: 0, height: -size * 0.03)

            let width = renderSize.width * 0.9
            let estimatedLines = max(1, ceil(CGFloat(t.text.count) * size * 0.55 / width))
            let explicitLines = CGFloat(t.text.split(separator: "\n", omittingEmptySubsequences: false).count)
            let height = size * 1.3 * max(estimatedLines, explicitLines)
            // Core Animation usa el origen abajo a la izquierda en la exportación.
            layer.frame = CGRect(x: t.position.x * renderSize.width - width / 2,
                                 y: (1 - t.position.y) * renderSize.height - height / 2,
                                 width: width, height: height)
            layer.opacity = 0

            let fade = CAKeyframeAnimation(keyPath: "opacity")
            fade.values = [0, 1, 1, 0]
            fade.keyTimes = [0, 0.08, 0.92, 1]
            fade.beginTime = max(t.start, AVCoreAnimationBeginTimeAtZero)
            fade.duration = max(0.1, t.duration)
            fade.isRemovedOnCompletion = false
            fade.fillMode = .forwards
            layer.add(fade, forKey: "fade")
            parent.addSublayer(layer)
        }

        return AVVideoCompositionCoreAnimationTool(postProcessingAsVideoLayer: videoLayer, in: parent)
    }
}
