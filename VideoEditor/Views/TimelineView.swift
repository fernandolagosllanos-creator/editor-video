import SwiftUI
import CoreMedia

/// Línea de tiempo con el cabezal fijo al centro: arrastrar mueve el video bajo el cabezal,
/// pellizcar acerca o aleja, los bordes del clip seleccionado recortan y mantener pulsado un clip
/// permite moverlo a otra posición.
struct TimelineView: View {
    @Bindable var model: EditorModel
    @Binding var pixelsPerSecond: CGFloat
    var onEditText: (TextOverlay) -> Void
    var onTransition: (UUID) -> Void
    var onAddClip: () -> Void

    static let rulerHeight: CGFloat = 22
    static let clipHeight: CGFloat = 60
    static let rowHeight: CGFloat = 30
    static let spacing: CGFloat = 8
    static let minZoom: CGFloat = 8
    static let maxZoom: CGFloat = 320

    /// Alto necesario según la cantidad de pistas.
    static func height(for model: EditorModel) -> CGFloat {
        var h = rulerHeight + clipHeight + spacing + 18
        if !model.texts.isEmpty { h += rowHeight + spacing }
        if !model.stickers.isEmpty { h += rowHeight + spacing }
        h += CGFloat(min(model.audioTracks.count, 4)) * (rowHeight + spacing)
        return h
    }

    // Estado de los gestos
    @State private var scrubOrigin: Double?
    @State private var pinchOrigin: CGFloat?
    @State private var trim: TrimDraft?
    @State private var reorder: ReorderState?
    @State private var textDrag: ItemDrag?
    @State private var audioDrag: ItemDrag?
    @State private var stickerDrag: ItemDrag?
    @State private var selectedAudioID: UUID?

    private let tile: CGFloat = 54
    private let tileGap: CGFloat = 8

    var body: some View {
        GeometryReader { geo in
            let center = geo.size.width / 2
            ZStack(alignment: .topLeading) {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        reorder = nil
                        selectedAudioID = nil
                        model.select(clipID: nil)
                        model.selectedTextID = nil
                        model.selectedStickerID = nil
                    }

                if model.clips.isEmpty {
                    emptyState.frame(width: geo.size.width, height: geo.size.height)
                } else {
                    VStack(alignment: .leading, spacing: Self.spacing) {
                        ruler(center: center)
                        videoTrack(center: center)
                            .frame(width: geo.size.width, height: Self.clipHeight, alignment: .topLeading)
                        if !model.texts.isEmpty {
                            textsRow(center: center)
                                .frame(width: geo.size.width, height: Self.rowHeight, alignment: .topLeading)
                        }
                        if !model.stickers.isEmpty {
                            stickersRow(center: center)
                                .frame(width: geo.size.width, height: Self.rowHeight, alignment: .topLeading)
                        }
                        ForEach(model.audioTracks.prefix(4)) { track in
                            audioRow(track, center: center)
                                .frame(width: geo.size.width, height: Self.rowHeight, alignment: .topLeading)
                        }
                    }
                    .padding(.top, 6)
                    .frame(width: geo.size.width, alignment: .topLeading)

                    playhead(height: geo.size.height)
                        .position(x: center, y: geo.size.height / 2)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
            .contentShape(Rectangle())
            .gesture(scrubGesture)
            .simultaneousGesture(pinchGesture)
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: reorder?.id)
        .sensoryFeedback(.selection, trigger: reorder?.target)
    }

    // MARK: - Conversión tiempo ↔ posición

    private func x(_ seconds: Double, center: CGFloat) -> CGFloat {
        center + CGFloat(seconds - model.currentTime) * pixelsPerSecond
    }

    // MARK: - Gestos generales

    private var scrubGesture: some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { value in
                guard reorder == nil, !model.clips.isEmpty else { return }
                if scrubOrigin == nil {
                    scrubOrigin = model.currentTime
                    if model.isPlaying { model.togglePlay() }
                }
                model.seek(to: (scrubOrigin ?? 0) - Double(value.translation.width / pixelsPerSecond))
            }
            .onEnded { _ in scrubOrigin = nil }
    }

    private var pinchGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                if pinchOrigin == nil { pinchOrigin = pixelsPerSecond }
                let next = (pinchOrigin ?? pixelsPerSecond) * value.magnification
                pixelsPerSecond = min(max(next, Self.minZoom), Self.maxZoom)
            }
            .onEnded { _ in pinchOrigin = nil }
    }

    // MARK: - Vacío

    private var emptyState: some View {
        VStack(spacing: 10) {
            Button(action: onAddClip) {
                Label("Agregar video", systemImage: "plus")
            }
            .buttonStyle(GradientButtonStyle())
            Text("Tus clips aparecerán aquí")
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
        }
    }

    // MARK: - Regla

    private func ruler(center: CGFloat) -> some View {
        let current = model.currentTime
        let pps = Double(pixelsPerSecond)
        let label = Self.labelStep(pps: pps)
        let ratio = label * pps / 4 >= 10 ? 4 : 2
        let minor = label / Double(ratio)
        return Canvas { ctx, size in
            let t0 = max(0, current - Double(center) / pps)
            let t1 = current + Double(size.width - center) / pps
            var k = Int(floor(t0 / minor))
            let kEnd = Int(ceil(t1 / minor))
            while k <= kEnd {
                let t = Double(k) * minor
                let px = center + CGFloat((t - current) * pps)
                let major = k % ratio == 0
                let tickH: CGFloat = major ? 7 : 4
                ctx.fill(Path(CGRect(x: px - 0.5, y: size.height - tickH, width: 1, height: tickH)),
                         with: .color(.white.opacity(major ? 0.45 : 0.2)))
                if major {
                    ctx.draw(Text(Self.shortTime(t))
                                .font(.system(size: 9, weight: .medium, design: .rounded))
                                .foregroundColor(.white.opacity(0.5)),
                             at: CGPoint(x: px + 3, y: 6), anchor: .leading)
                }
                k += 1
            }
        }
        .frame(height: Self.rulerHeight)
    }

    private static func labelStep(pps: Double) -> Double {
        for step in [0.5, 1, 2, 5, 10, 15, 30, 60, 120] where step * pps >= 60 { return step }
        return 300
    }

    private static func shortTime(_ t: Double) -> String {
        let m = Int(t) / 60
        let s = t - Double(m * 60)
        if t.truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%d:%02d", m, Int(s))
        }
        return String(format: "%d:%04.1f", m, s)
    }

    // MARK: - Pista de video

    private func videoTrack(center: CGFloat) -> some View {
        let placements = model.placements
        let endX = x(Timeline.totalDuration(for: model.clips).seconds, center: center)
        return ZStack(alignment: .topLeading) {
            ForEach(Array(placements.enumerated()), id: \.element.id) { index, p in
                clipItem(p, index: index, count: placements.count, center: center)
            }

            if reorder == nil && trim == nil {
                ForEach(Array(placements.dropLast().enumerated()), id: \.element.id) { index, p in
                    let next = placements[index + 1]
                    let overlap = (p.end - next.start).seconds
                    transitionMarker(p.clip)
                        .position(x: x(next.start.seconds + overlap / 2, center: center), y: Self.clipHeight / 2)
                }

                Button(action: onAddClip) {
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(Theme.gradient, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .shadow(color: Theme.accent.opacity(0.5), radius: 8, y: 3)
                }
                .buttonStyle(.plain)
                .offset(x: endX + 14, y: (Self.clipHeight - 44) / 2)
            }
        }
        .frame(height: Self.clipHeight, alignment: .topLeading)
    }

    @ViewBuilder
    private func clipItem(_ p: Placement, index: Int, count: Int, center: CGFloat) -> some View {
        let layout = clipLayout(p, index: index, count: count, center: center)
        let isSelected = p.clip.id == model.selectedClipID
        let isLifted = reorder?.id == p.clip.id
        let waveform = WaveformStore.shared.waveform(for: p.clip.url)

        ClipView(clip: layout.clip, width: layout.width, height: layout.height,
                 pixelsPerSecond: pixelsPerSecond, isSelected: isSelected && reorder == nil,
                 compact: reorder != nil, waveform: waveform, muted: model.originalVolume == 0)
            .overlay {
                if isSelected && reorder == nil {
                    trimHandles(for: p.clip, width: layout.width)
                }
            }
            .scaleEffect(isLifted ? 1.12 : 1)
            .shadow(color: isLifted ? Theme.accent.opacity(0.7) : .clear, radius: 12)
            .onTapGesture {
                if reorder != nil { reorder = nil; return }
                model.select(clipID: isSelected ? nil : p.clip.id)
            }
            .gesture(reorderGesture(for: p.clip.id, index: index, count: count))
            .offset(x: layout.x, y: (Self.clipHeight - layout.height) / 2)
            .zIndex(isLifted ? 3 : (isSelected ? 2 : 0))
            .animation(isLifted ? nil : Theme.spring, value: reorder?.target)
            .animation(Theme.spring, value: reorder == nil)
            .task(id: p.clip.url) { WaveformStore.shared.load(p.clip.url) }
    }

    private struct ClipLayout {
        var clip: Clip
        var x: CGFloat
        var width: CGFloat
        var height: CGFloat
    }

    private func clipLayout(_ p: Placement, index: Int, count: Int, center: CGFloat) -> ClipLayout {
        // Modo reordenar: los clips se vuelven cuadrados en fila, centrados bajo el cabezal.
        if let reorder {
            let rowWidth = CGFloat(count) * tile + CGFloat(count - 1) * tileGap
            let startX = center - rowWidth / 2
            let slot: Int
            if p.clip.id == reorder.id {
                return ClipLayout(clip: p.clip, x: startX + CGFloat(reorder.origin) * (tile + tileGap) + reorder.dx,
                                  width: tile, height: tile)
            } else if reorder.origin < reorder.target, index > reorder.origin, index <= reorder.target {
                slot = index - 1
            } else if reorder.origin > reorder.target, index >= reorder.target, index < reorder.origin {
                slot = index + 1
            } else {
                slot = index
            }
            return ClipLayout(clip: p.clip, x: startX + CGFloat(slot) * (tile + tileGap), width: tile, height: tile)
        }

        // Recorte en curso: el clip se dibuja con los bordes provisorios.
        var clip = p.clip
        var startX = x(p.start.seconds, center: center)
        if let trim, trim.id == clip.id {
            clip.start = Timeline.time(trim.start)
            clip.end = Timeline.time(trim.end)
            if trim.edge == .leading {
                startX += CGFloat(p.clip.duration.seconds - clip.duration.seconds) * pixelsPerSecond
            }
        }
        let width = max(6, CGFloat(clip.duration.seconds) * pixelsPerSecond)
        return ClipLayout(clip: clip, x: startX, width: width, height: Self.clipHeight)
    }

    // MARK: Recortar arrastrando los bordes

    private enum Edge { case leading, trailing }

    private struct TrimDraft {
        let id: UUID
        let edge: Edge
        let originStart: Double
        let originEnd: Double
        var start: Double
        var end: Double
    }

    private func trimHandles(for clip: Clip, width: CGFloat) -> some View {
        HStack(spacing: 0) {
            trimHandle(clip, edge: .leading)
            Spacer(minLength: 0)
            trimHandle(clip, edge: .trailing)
        }
        .overlay(alignment: .top) {
            if let trim, trim.id == clip.id {
                Text(formatTime(Timeline.time(trim.end - trim.start).seconds / max(clip.speed, 0.01)))
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Theme.gradient, in: Capsule())
                    .offset(y: -14)
                    .fixedSize()
            }
        }
    }

    private func trimHandle(_ clip: Clip, edge: Edge) -> some View {
        let shape = UnevenRoundedRectangle(topLeadingRadius: edge == .leading ? 8 : 0,
                                           bottomLeadingRadius: edge == .leading ? 8 : 0,
                                           bottomTrailingRadius: edge == .trailing ? 8 : 0,
                                           topTrailingRadius: edge == .trailing ? 8 : 0,
                                           style: .continuous)
        return shape
            .fill(Color.white)
            .frame(width: 14)
            .overlay {
                Capsule().fill(Theme.accent).frame(width: 3, height: 18)
            }
            .contentShape(Rectangle().inset(by: -8))
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .global)
                    .onChanged { value in
                        if trim == nil {
                            trim = TrimDraft(id: clip.id, edge: edge, originStart: clip.start.seconds,
                                             originEnd: clip.end.seconds, start: clip.start.seconds, end: clip.end.seconds)
                        }
                        guard var draft = trim else { return }
                        let delta = clip.sourceDelta(forTimelineDelta: Double(value.translation.width / pixelsPerSecond))
                        // En un clip en reversa, el borde izquierdo de la línea de tiempo es el final del archivo.
                        let movesStart = (edge == .leading) != clip.isReversed
                        let change = clip.isReversed ? -delta : delta
                        if movesStart {
                            draft.start = min(max(0, draft.originStart + change), draft.originEnd - 0.2)
                        } else {
                            draft.end = max(min(clip.assetDuration.seconds, draft.originEnd + change), draft.originStart + 0.2)
                        }
                        trim = draft
                    }
                    .onEnded { _ in
                        if let draft = trim {
                            model.trimClip(id: draft.id, start: draft.start, end: draft.end)
                        }
                        trim = nil
                    }
            )
    }

    // MARK: Reordenar manteniendo pulsado

    private struct ReorderState {
        let id: UUID
        let origin: Int
        var target: Int
        var dx: CGFloat
    }

    private func reorderGesture(for id: UUID, index: Int, count: Int) -> some Gesture {
        LongPressGesture(minimumDuration: 0.35)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .global))
            .onChanged { value in
                guard case .second(true, let drag) = value, count > 1 else { return }
                if reorder == nil {
                    withAnimation(Theme.spring) {
                        reorder = ReorderState(id: id, origin: index, target: index, dx: 0)
                        model.select(clipID: id)
                    }
                }
                guard var state = reorder, state.id == id else { return }
                state.dx = drag?.translation.width ?? 0
                let shift = Int((state.dx / (tile + tileGap)).rounded())
                state.target = min(max(0, state.origin + shift), count - 1)
                reorder = state
            }
            .onEnded { _ in
                guard let state = reorder, state.id == id else { return }
                withAnimation(Theme.spring) {
                    reorder = nil
                    model.moveClip(id: state.id, to: state.target)
                }
            }
    }

    // MARK: Transiciones entre clips

    private func transitionMarker(_ clip: Clip) -> some View {
        Button {
            onTransition(clip.id)
        } label: {
            Image(systemName: clip.transitionOut == .none ? "plus" : clip.transitionOut.symbol)
                .font(.system(size: 9, weight: .heavy))
                .foregroundStyle(clip.transitionOut == .none ? Theme.background : .white)
                .frame(width: 20, height: 20)
                .background {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(clip.transitionOut == .none ? AnyShapeStyle(Color.white) : AnyShapeStyle(Theme.gradient))
                }
                .shadow(color: .black.opacity(0.4), radius: 3, y: 1)
        }
        .buttonStyle(.plain)
        .zIndex(4)
    }

    // MARK: - Textos

    private struct ItemDrag {
        let id: UUID
        var delta: Double
    }

    private func textsRow(center: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            Color.clear.frame(height: Self.rowHeight)
            ForEach(model.texts) { t in
                let isSelected = t.id == model.selectedTextID
                let delta = textDrag?.id == t.id ? textDrag?.delta ?? 0 : 0
                HStack(spacing: 5) {
                    Image(systemName: isSelected ? "pencil" : (t.isCaption ? "captions.bubble" : "textformat"))
                        .font(.system(size: 10, weight: .bold))
                    Text(t.text).font(.system(size: 11, weight: .semibold, design: .rounded)).lineLimit(1)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .frame(width: max(34, CGFloat(t.duration) * pixelsPerSecond), height: Self.rowHeight - 4, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.text.opacity(0.55)))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(isSelected ? Color.white : Theme.text.opacity(0.8), lineWidth: isSelected ? 2 : 1))
                .contentShape(Rectangle())
                .onTapGesture {
                    if isSelected {
                        onEditText(t)
                    } else {
                        model.selectedTextID = t.id
                        model.seek(to: t.start + 0.05)
                    }
                }
                .gesture(
                    DragGesture(minimumDistance: 3, coordinateSpace: .global)
                        .onChanged { v in textDrag = ItemDrag(id: t.id, delta: Double(v.translation.width / pixelsPerSecond)) }
                        .onEnded { _ in
                            model.moveTextStart(id: t.id, to: t.start + (textDrag?.delta ?? 0))
                            textDrag = nil
                        },
                    including: isSelected ? .all : .subviews
                )
                .offset(x: x(t.start + delta, center: center), y: 2)
            }
        }
        .frame(height: Self.rowHeight)
    }

    // MARK: - Stickers

    private func stickersRow(center: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            Color.clear.frame(height: Self.rowHeight)
            ForEach(model.stickers) { s in
                let isSelected = s.id == model.selectedStickerID
                let delta = stickerDrag?.id == s.id ? stickerDrag?.delta ?? 0 : 0
                HStack(spacing: 5) {
                    switch s.content {
                    case .emoji(let e): Text(e).font(.system(size: 13))
                    case .shape: Image(systemName: "star.fill").font(.system(size: 10, weight: .bold))
                    }
                    if isSelected {
                        Image(systemName: "pencil").font(.system(size: 10, weight: .bold))
                    }
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .frame(width: max(34, CGFloat(s.duration) * pixelsPerSecond), height: Self.rowHeight - 4, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.sticker.opacity(0.45)))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(isSelected ? Color.white : Theme.sticker.opacity(0.8), lineWidth: isSelected ? 2 : 1))
                .contentShape(Rectangle())
                .onTapGesture {
                    model.seek(to: s.start + 0.05)
                    if isSelected {
                        model.editingStickerID = s.id
                    } else {
                        model.selectedStickerID = s.id
                        model.selectedTextID = nil
                    }
                }
                .gesture(
                    DragGesture(minimumDistance: 3, coordinateSpace: .global)
                        .onChanged { v in stickerDrag = ItemDrag(id: s.id, delta: Double(v.translation.width / pixelsPerSecond)) }
                        .onEnded { _ in
                            var moved = s
                            moved.start = min(max(0, s.start + (stickerDrag?.delta ?? 0)), max(0, model.duration - 0.2))
                            model.update(moved)
                            stickerDrag = nil
                        },
                    including: isSelected ? .all : .subviews
                )
                .offset(x: x(s.start + delta, center: center), y: 2)
            }
        }
        .frame(height: Self.rowHeight)
    }

    // MARK: - Audio

    private func audioRow(_ track: AudioTrack, center: CGFloat) -> some View {
        let isSelected = selectedAudioID == track.id
        let delta = audioDrag?.id == track.id ? audioDrag?.delta ?? 0 : 0
        let visible = max(0.5, track.playedDuration(total: model.duration))
        let tint = track.kind == .voice ? Theme.accent2 : Theme.audio
        let width = max(34, CGFloat(visible) * pixelsPerSecond)
        let waveform = WaveformStore.shared.waveform(for: track.url)
        return ZStack(alignment: .topLeading) {
            Color.clear.frame(height: Self.rowHeight)
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 8, style: .continuous).fill(tint.opacity(0.22))
                if let waveform {
                    WaveformShape(waveform: waveform, sourceStart: track.sourceOffset, pixelsPerSecond: pixelsPerSecond)
                        .fill(tint.opacity(0.85))
                        .padding(.vertical, 3)
                }
                HStack(spacing: 4) {
                    Image(systemName: track.kind.symbol).font(.system(size: 10, weight: .bold))
                    Text(track.name).font(.system(size: 10, weight: .semibold, design: .rounded)).lineLimit(1)
                    if track.loops { Image(systemName: "repeat").font(.system(size: 9, weight: .bold)) }
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 6).padding(.vertical, 1)
                .background(Theme.background.opacity(0.55), in: Capsule())
                .padding(.leading, 4)
            }
            .frame(width: width, height: Self.rowHeight - 4)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(isSelected ? Color.white : tint.opacity(0.7), lineWidth: isSelected ? 2 : 1))
            .contentShape(Rectangle())
            .onTapGesture { selectedAudioID = isSelected ? nil : track.id }
            .gesture(
                DragGesture(minimumDistance: 3, coordinateSpace: .global)
                    .onChanged { v in audioDrag = ItemDrag(id: track.id, delta: Double(v.translation.width / pixelsPerSecond)) }
                    .onEnded { _ in
                        model.moveAudio(id: track.id, to: track.start + (audioDrag?.delta ?? 0))
                        audioDrag = nil
                    },
                including: isSelected ? .all : .subviews
            )
            .offset(x: x(track.start + delta, center: center), y: 2)
        }
        .frame(height: Self.rowHeight)
        .task(id: track.url) { WaveformStore.shared.load(track.url) }
    }

    // MARK: - Cabezal

    private func playhead(height: CGFloat) -> some View {
        VStack(spacing: 0) {
            Circle().fill(Color.white).frame(width: 9, height: 9)
            Rectangle().fill(Color.white).frame(width: 2)
        }
        .frame(height: height - 4)
        .shadow(color: Theme.accent2.opacity(0.9), radius: 4)
        .allowsHitTesting(false)
    }
}

// MARK: - Clip

struct ClipView: View {
    let clip: Clip
    let width: CGFloat
    let height: CGFloat
    let pixelsPerSecond: CGFloat
    let isSelected: Bool
    var compact = false
    var waveform: WaveformData?
    var muted = false

    private var waveHeight: CGFloat { compact || !clip.hasAudio ? 0 : 16 }

    private var tileWidth: CGFloat {
        let size = clip.displaySize
        let aspect = size.height > 0 ? size.width / size.height : 16 / 9
        return (height - waveHeight) * min(max(aspect, 0.56), 1.78)
    }

    var body: some View {
        let radius: CGFloat = compact ? 12 : 9
        VStack(spacing: 0) {
            thumbnails
            if waveHeight > 0 {
                ZStack {
                    Theme.background.opacity(0.85)
                    if let waveform {
                        WaveformShape(waveform: waveform, sourceStart: clip.start.seconds,
                                      pixelsPerSecond: pixelsPerSecond / CGFloat(max(clip.speed, 0.01)))
                            .fill(muted ? Color.white.opacity(0.2) : Theme.audio.opacity(0.9))
                            .padding(.vertical, 2)
                    }
                }
                .frame(height: waveHeight)
            }
        }
        .frame(width: width, height: height, alignment: .leading)
        .overlay(alignment: .topLeading) {
            if !compact && width > 44 {
                HStack(spacing: 3) {
                    Text(formatTime(clip.duration.seconds))
                    if clip.speed != 1 {
                        Text(clip.speed < 1 ? String(format: "%.2gx", clip.speed) : String(format: "%gx", clip.speed))
                            .foregroundStyle(Theme.accent3)
                    }
                    if clip.isReversed { Image(systemName: "backward.fill").foregroundStyle(Theme.accent3) }
                    if clip.isFreezeFrame { Image(systemName: "snowflake") }
                    if muted && clip.hasAudio { Image(systemName: "speaker.slash.fill") }
                }
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, 5).padding(.vertical, 2)
                .background(.black.opacity(0.55), in: Capsule())
                .padding(.leading, isSelected ? 18 : 4).padding(.top, 4)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(isSelected ? Color.white : Color.white.opacity(0.14), lineWidth: isSelected ? 2.5 : 1)
        )
        .contentShape(Rectangle())
    }

    private var thumbnails: some View {
        let tileW = compact ? width : tileWidth
        let count = compact ? 1 : min(200, max(1, Int(ceil(width / max(tileW, 1)))))
        return HStack(spacing: 0) {
            if clip.thumbnails.isEmpty {
                LinearGradient(colors: [Theme.surfaceRaised, Theme.surface], startPoint: .top, endPoint: .bottom)
            } else {
                ForEach(0..<count, id: \.self) { i in
                    Image(decorative: thumbnail(at: i, tileWidth: tileW), scale: 1)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: tileW, height: height - waveHeight)
                        .clipped()
                }
            }
        }
        .frame(width: width, height: height - waveHeight, alignment: .leading)
        .clipped()
    }

    /// Elige la miniatura que corresponde al momento del archivo que se ve en cada cuadro.
    private func thumbnail(at i: Int, tileWidth: CGFloat) -> CGImage {
        let images = clip.thumbnails
        let total = max(clip.assetDuration.seconds, 0.001)
        let offset = compact ? 0 : Double((CGFloat(i) + 0.5) * tileWidth / max(pixelsPerSecond, 1))
        let source = min(clip.sourceSeconds(atTimelineOffset: offset), total)
        let index = min(images.count - 1, max(0, Int(source / total * Double(images.count))))
        return images[index]
    }
}

// MARK: - Forma de onda

/// Barras simétricas a partir de los picos del audio. `sourceStart` es el segundo del archivo
/// que corresponde al borde izquierdo.
struct WaveformShape: Shape {
    let waveform: WaveformData
    let sourceStart: Double
    let pixelsPerSecond: CGFloat
    var barWidth: CGFloat = 2
    var gap: CGFloat = 1

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let step = barWidth + gap
        let secondsPerBar = Double(step / max(pixelsPerSecond, 1))
        var x: CGFloat = 0
        var t = sourceStart
        while x < rect.width {
            let peak = CGFloat(waveform.peak(from: t, to: t + secondsPerBar))
            let h = max(1.5, peak * rect.height)
            path.addRoundedRect(in: CGRect(x: rect.minX + x, y: rect.midY - h / 2, width: barWidth, height: h),
                                cornerSize: CGSize(width: barWidth / 2, height: barWidth / 2))
            x += step
            t += secondsPerBar
        }
        return path
    }
}
