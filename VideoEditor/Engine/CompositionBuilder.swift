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

    static func renderSize(for clips: [Clip], aspect: CanvasAspect = .original) -> CGSize {
        if let fixed = aspect.pixelSize { return fixed }
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
                      texts: [TextOverlay],
                      stickers: [StickerOverlay] = [],
                      stickerImages: [UUID: CGImage] = [:],
                      aspect: CanvasAspect = .original,
                      canvas: CanvasBackground = .black,
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
            let clip = p.clip
            let asset = AVURLAsset(url: clip.sourceURL)
            guard let sourceVideo = try await asset.loadTracks(withMediaType: .video).first else {
                throw BuildError.noVideoTrack(clip.name)
            }
            // El tramo nunca debe salirse del archivo (el invertido puede durar un cuadro menos).
            var range = clip.sourceRange
            let available = try await sourceVideo.load(.timeRange)
            if range.end > available.end {
                range = CMTimeRange(start: max(.zero, available.end - range.duration), duration: range.duration)
            }
            let videoTrack = videoTracks[i % 2]
            try videoTrack.insertTimeRange(range, of: sourceVideo, at: p.start)
            // Velocidad: se estira o se comprime el tramo recién insertado.
            let inserted = CMTimeRange(start: p.start, duration: range.duration)
            if clip.speed != 1 {
                videoTrack.scaleTimeRange(inserted, toDuration: clip.duration)
            }
            layouts[clip.id] = ClipLayout(trackID: videoTrack.trackID,
                                          naturalSize: clip.naturalSize,
                                          preferredTransform: clip.preferredTransform,
                                          look: clip.look,
                                          framing: clip.framing)

            // El archivo invertido no tiene audio, así que un clip en reversa queda en silencio.
            if let sourceAudio = try await asset.loadTracks(withMediaType: .audio).first {
                let audioTrack = originalAudioTracks[i % 2]
                try audioTrack.insertTimeRange(range, of: sourceAudio, at: p.start)
                if clip.speed != 1 {
                    audioTrack.scaleTimeRange(inserted, toDuration: clip.duration)
                }
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
                                                          transition: bg.clip.transitionOut, canvas: canvas))
            } else {
                instructions.append(TransitionInstruction(timeRange: range, foreground: fgLayout, background: nil,
                                                          transition: .none, canvas: canvas))
            }
        }

        // Las instrucciones deben cubrir exactamente la duración de la composición.
        let compositionDuration = try await composition.load(.duration)
        if let last = instructions.last, compositionDuration > last.timeRange.end {
            instructions[instructions.count - 1] = TransitionInstruction(
                timeRange: CMTimeRange(start: last.timeRange.start, end: compositionDuration),
                foreground: last.foreground, background: last.background,
                transition: last.transition, canvas: last.canvas)
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

        // Pistas de audio agregadas (música, voz en off, etc.).
        let totalSeconds = total.seconds
        let voiceRanges = audioTracks.filter { $0.kind == .voice }.map { v -> (Double, Double) in
            (v.start, v.start + v.playedDuration(total: totalSeconds))
        }
        for track in audioTracks {
            let startTime = Timeline.time(track.start)
            guard startTime < total else { continue }
            let asset = AVURLAsset(url: track.url)
            guard let source = try await asset.loadTracks(withMediaType: .audio).first,
                  let compTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
            else { continue }
            let offset = min(max(0, track.sourceOffset), max(0, track.assetDuration.seconds - 0.1))
            let pieceLength = track.assetDuration.seconds - offset
            guard pieceLength > 0.05 else { continue }
            let played = track.playedDuration(total: totalSeconds)
            // Se inserta el audio (repetido si `loops`) hasta cubrir el tiempo que debe sonar.
            var cursor = 0.0
            while cursor < played - 0.01 {
                let length = min(pieceLength, played - cursor)
                try compTrack.insertTimeRange(CMTimeRange(start: Timeline.time(offset), duration: Timeline.time(length)),
                                              of: source, at: Timeline.time(track.start + cursor))
                cursor += length
                if !track.loops { break }
            }
            let params = AVMutableAudioMixInputParameters(track: compTrack)
            applyEnvelope(to: params, track: track, played: played,
                          voiceRanges: track.kind == .music && track.ducking ? voiceRanges : [])
            inputParameters.append(params)
        }

        let audioMix = AVMutableAudioMix()
        audioMix.inputParameters = inputParameters

        let size = outputSize ?? renderSize(for: clips, aspect: aspect)
        let videoComposition = AVMutableVideoComposition()
        videoComposition.customVideoCompositorClass = TransitionCompositor.self
        videoComposition.renderSize = size
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
        videoComposition.instructions = instructions

        if forExport, !texts.isEmpty || !stickers.isEmpty {
            videoComposition.animationTool = makeAnimationTool(texts: texts, stickers: stickers,
                                                               stickerImages: stickerImages, renderSize: size)
        }

        let immutable = composition.copy() as! AVComposition
        return BuiltComposition(composition: immutable, videoComposition: videoComposition,
                                audioMix: audioMix, duration: compositionDuration, renderSize: size)
    }

    // MARK: - Volumen de pistas agregadas (fundidos y atenuación bajo la voz)

    /// Volumen al que baja la música mientras suena una voz en off (fracción del volumen normal).
    static let duckLevel: Float = 0.25
    static let duckRamp: Double = 0.35

    /// Calcula el volumen como una curva por tramos (fundidos × atenuación) y la aplica con rampas.
    static func applyEnvelope(to params: AVMutableAudioMixInputParameters, track: AudioTrack,
                              played: Double, voiceRanges: [(Double, Double)]) {
        let s = track.start
        let e = track.start + played
        let fadeIn = min(max(0, track.fadeIn), played / 2)
        let fadeOut = min(max(0, track.fadeOut), played / 2)

        func gain(_ t: Double) -> Float {
            var g = track.volume
            if fadeIn > 0, t < s + fadeIn { g *= Float(max(0, (t - s) / fadeIn)) }
            if fadeOut > 0, t > e - fadeOut { g *= Float(max(0, (e - t) / fadeOut)) }
            var duck: Float = 1
            for (a, b) in voiceRanges {
                var w = 0.0
                if t >= a && t <= b { w = 1 }
                else if t < a && t > a - duckRamp { w = 1 - (a - t) / duckRamp }
                else if t > b && t < b + duckRamp { w = 1 - (t - b) / duckRamp }
                duck = min(duck, 1 - (1 - duckLevel) * Float(w))
            }
            return g * duck
        }

        var points: [Double] = [s, e]
        if fadeIn > 0 { points.append(s + fadeIn) }
        if fadeOut > 0 { points.append(e - fadeOut) }
        for (a, b) in voiceRanges {
            points.append(contentsOf: [a - duckRamp, a, b, b + duckRamp])
        }
        var sorted: [Double] = []
        for p in points.filter({ $0 >= s && $0 <= e }).sorted() where sorted.last.map({ p - $0 > 0.01 }) ?? true {
            sorted.append(p)
        }

        if s > 0.01 { params.setVolume(gain(s), at: .zero) }
        for (a, b) in zip(sorted, sorted.dropFirst()) {
            let ga = gain(a), gb = gain(b)
            let range = CMTimeRange(start: Timeline.time(a), end: Timeline.time(b))
            if abs(ga - gb) < 0.001 {
                params.setVolume(ga, at: range.start)
            } else {
                params.setVolumeRamp(fromStartVolume: ga, toEndVolume: gb, timeRange: range)
            }
        }
    }

    // MARK: - Textos para exportación (Core Animation)

    static func makeAnimationTool(texts: [TextOverlay], stickers: [StickerOverlay] = [],
                                  stickerImages: [UUID: CGImage] = [:],
                                  renderSize: CGSize) -> AVVideoCompositionCoreAnimationTool {
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

            // Con caja de fondo: se mide el texto y se envuelve en una capa redondeada oscura.
            var animated: CALayer = layer
            if t.hasBackground {
                let font = CTFontCreateWithName("HelveticaNeue-Bold" as CFString, size, nil)
                let attributed = NSAttributedString(string: t.text,
                                                    attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font])
                let setter = CTFramesetterCreateWithAttributedString(attributed)
                let measured = CTFramesetterSuggestFrameSizeWithConstraints(
                    setter, CFRange(location: 0, length: 0), nil,
                    CGSize(width: width, height: .greatestFiniteMagnitude), nil)
                let padX = size * 0.35, padY = size * 0.18
                let textSize = CGSize(width: ceil(measured.width) + 2, height: ceil(measured.height) + 2)
                let box = CALayer()
                box.backgroundColor = CGColor(red: 0, green: 0, blue: 0, alpha: 0.62)
                box.cornerRadius = size * 0.28
                box.frame = CGRect(x: t.position.x * renderSize.width - textSize.width / 2 - padX,
                                   y: (1 - t.position.y) * renderSize.height - textSize.height / 2 - padY,
                                   width: textSize.width + padX * 2, height: textSize.height + padY * 2)
                layer.shadowOpacity = 0
                layer.opacity = 1
                layer.frame = CGRect(x: padX, y: padY, width: textSize.width, height: textSize.height)
                box.addSublayer(layer)
                box.opacity = 0
                animated = box
            }

            let fade = CAKeyframeAnimation(keyPath: "opacity")
            fade.values = [0, 1, 1, 0]
            fade.keyTimes = [0, 0.08, 0.92, 1]
            fade.beginTime = max(t.start, AVCoreAnimationBeginTimeAtZero)
            fade.duration = max(0.1, t.duration)
            fade.isRemovedOnCompletion = false
            fade.fillMode = .forwards
            animated.add(fade, forKey: "fade")
            parent.addSublayer(animated)
        }

        for sticker in stickers {
            guard let image = stickerImages[sticker.id] else { continue }
            parent.addSublayer(makeStickerLayer(sticker, image: image, renderSize: renderSize))
        }

        return AVVideoCompositionCoreAnimationTool(postProcessingAsVideoLayer: videoLayer, in: parent)
    }

    /// Capa de un sticker con su animación, muestreada de la misma función que usa la vista previa.
    static func makeStickerLayer(_ sticker: StickerOverlay, image: CGImage, renderSize: CGSize) -> CALayer {
        let side = CGFloat(sticker.size) * min(renderSize.width, renderSize.height)
        let layer = CALayer()
        layer.contents = image
        layer.contentsGravity = .resizeAspect
        layer.bounds = CGRect(x: 0, y: 0, width: side, height: side)
        // Core Animation usa el origen abajo a la izquierda en la exportación.
        layer.position = CGPoint(x: sticker.position.x * renderSize.width,
                                 y: (1 - sticker.position.y) * renderSize.height)
        layer.opacity = 0

        let duration = max(0.1, sticker.duration)
        let fps = 30.0
        let steps = max(2, Int(duration * fps))
        var transforms: [NSValue] = []
        var opacities: [NSNumber] = []
        var keyTimes: [NSNumber] = []
        for k in 0...steps {
            let t = duration * Double(k) / Double(steps)
            let st = sticker.animation.state(at: t, duration: duration)
            // En pantalla la rotación positiva es horaria; aquí (Y hacia arriba) se invierte.
            let radians = -(sticker.rotation + st.rotation) * .pi / 180
            var transform = CATransform3DMakeTranslation(0, -CGFloat(st.dy) * side, 0)
            transform = CATransform3DRotate(transform, CGFloat(radians), 0, 0, 1)
            transform = CATransform3DScale(transform, CGFloat(st.scale), CGFloat(st.scale), 1)
            transforms.append(NSValue(caTransform3D: transform))
            opacities.append(NSNumber(value: st.opacity))
            keyTimes.append(NSNumber(value: Double(k) / Double(steps)))
        }

        let begin = sticker.start > 0 ? sticker.start : AVCoreAnimationBeginTimeAtZero
        let move = CAKeyframeAnimation(keyPath: "transform")
        move.values = transforms
        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = opacities
        for animation in [move, fade] {
            animation.keyTimes = keyTimes
            animation.beginTime = begin
            animation.duration = duration
            animation.calculationMode = .linear
            animation.isRemovedOnCompletion = false
            animation.fillMode = .both
        }
        // Antes de aparecer y después de terminar el sticker queda invisible (opacidad 0 en los extremos).
        layer.add(move, forKey: "move")
        layer.add(fade, forKey: "fade")
        return layer
    }
}
