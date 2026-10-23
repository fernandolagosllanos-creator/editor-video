import SwiftUI
import CoreMedia

/// Línea de tiempo: regla, pista de video (con miniaturas y transiciones), textos y pistas de audio.
struct TimelineView: View {
    @Bindable var model: EditorModel
    @Binding var pixelsPerSecond: CGFloat
    var onEditText: (TextOverlay) -> Void

    private let clipHeight: CGFloat = 64
    private let rowHeight: CGFloat = 26
    private let leadingPad: CGFloat = 12

    private var contentWidth: CGFloat {
        max(model.duration, 10) * pixelsPerSecond + 400
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: true) {
            ZStack(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 6) {
                    ruler
                    videoTrack
                    textsTrack
                    audioTracks
                }
                .padding(.leading, leadingPad)
                .frame(width: contentWidth, alignment: .leading)

                playhead
            }
        }
        .background(Color(white: 0.12))
    }

    // MARK: - Regla (arrastrar para desplazar el cabezal)

    private var ruler: some View {
        let seconds = Int(ceil(max(model.duration, 10)))
        let step = pixelsPerSecond < 40 ? 5 : (pixelsPerSecond < 90 ? 2 : 1)
        return ZStack(alignment: .topLeading) {
            Rectangle().fill(Color(white: 0.18))
            ForEach(Array(stride(from: 0, through: seconds, by: step)), id: \.self) { s in
                VStack(spacing: 1) {
                    Text(formatTime(Double(s)))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Rectangle().fill(Color.secondary).frame(width: 1, height: 5)
                }
                .offset(x: CGFloat(s) * pixelsPerSecond)
            }
        }
        .frame(height: 20)
        .contentShape(Rectangle())
        .highPriorityGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in model.seek(to: Double(value.location.x / pixelsPerSecond)) }
        )
    }

    // MARK: - Video

    private var videoTrack: some View {
        ZStack(alignment: .topLeading) {
            Rectangle().fill(Color(white: 0.16)).frame(height: clipHeight)
            ForEach(model.placements) { p in
                ClipView(clip: p.clip, width: max(8, CGFloat(p.clip.duration.seconds) * pixelsPerSecond),
                         height: clipHeight, isSelected: p.clip.id == model.selectedClipID)
                    .offset(x: CGFloat(p.start.seconds) * pixelsPerSecond)
                    .onTapGesture {
                        model.selectedClipID = p.clip.id
                        model.selectedTextID = nil
                    }
            }
        }
        .frame(height: clipHeight)
    }

    // MARK: - Textos

    @ViewBuilder
    private var textsTrack: some View {
        if !model.texts.isEmpty {
            ZStack(alignment: .topLeading) {
                Rectangle().fill(Color(white: 0.16)).frame(height: rowHeight)
                ForEach(model.texts) { t in
                    HStack(spacing: 4) {
                        Image(systemName: "textformat").font(.caption2)
                        Text(t.text).font(.caption).lineLimit(1)
                    }
                    .padding(.horizontal, 6)
                    .frame(width: max(30, CGFloat(t.duration) * pixelsPerSecond), height: rowHeight - 4, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 5).fill(Color.purple.opacity(0.75)))
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(t.id == model.selectedTextID ? Color.white : .clear, lineWidth: 1.5))
                    .offset(x: CGFloat(t.start) * pixelsPerSecond, y: 2)
                    .onTapGesture {
                        model.selectedTextID = t.id
                        model.seek(to: t.start + 0.05)
                        onEditText(t)
                    }
                }
            }
            .frame(height: rowHeight)
        }
    }

    // MARK: - Audio

    @ViewBuilder
    private var audioTracks: some View {
        ForEach(model.audioTracks) { track in
            ZStack(alignment: .topLeading) {
                Rectangle().fill(Color(white: 0.16)).frame(height: rowHeight)
                HStack(spacing: 4) {
                    Image(systemName: "music.note").font(.caption2)
                    Text(track.name).font(.caption).lineLimit(1)
                }
                .padding(.horizontal, 6)
                .frame(width: max(30, CGFloat(min(track.assetDuration.seconds, max(0, model.duration - track.start))) * pixelsPerSecond),
                       height: rowHeight - 4, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 5).fill(Color.teal.opacity(0.75)))
                .offset(x: CGFloat(track.start) * pixelsPerSecond, y: 2)
            }
            .frame(height: rowHeight)
        }
    }

    // MARK: - Cabezal

    private var playhead: some View {
        Rectangle()
            .fill(Color.red)
            .frame(width: 2)
            .offset(x: leadingPad + CGFloat(model.currentTime) * pixelsPerSecond - 1)
            .allowsHitTesting(false)
    }
}

struct ClipView: View {
    let clip: Clip
    let width: CGFloat
    let height: CGFloat
    let isSelected: Bool

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            HStack(spacing: 0) {
                if clip.thumbnails.isEmpty {
                    Rectangle().fill(Color.gray)
                } else {
                    ForEach(Array(clip.thumbnails.enumerated()), id: \.offset) { _, image in
                        Image(decorative: image, scale: 1)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: height * 0.9, height: height)
                            .clipped()
                    }
                }
            }
            .frame(width: width, height: height, alignment: .leading)
            .clipped()

            HStack(spacing: 4) {
                Text(formatTime(clip.duration.seconds))
                if clip.transitionOut != .none {
                    Image(systemName: clip.transitionOut.symbol)
                }
            }
            .font(.system(size: 9, weight: .semibold))
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 3))
            .padding(3)
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(isSelected ? Color.yellow : Color.white.opacity(0.25), lineWidth: isSelected ? 2.5 : 1))
        .contentShape(Rectangle())
    }
}
