import SwiftUI
import AVFoundation
#if os(macOS)
import AppKit
#endif

/// Pantalla final de la exportación: vista previa del video listo, guardar y compartir.
struct ShareResultView: View {
    @Bindable var model: EditorModel
    let url: URL
    @State private var poster: CGImage?
    @State private var info = ""
    @State private var savedMessage: String?
    @State private var isSaving = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ZStack {
                if let poster {
                    Image(decorative: poster, scale: 1).resizable().aspectRatio(contentMode: .fit)
                } else {
                    Rectangle().fill(Studio.card).aspectRatio(16 / 9, contentMode: .fit)
                }
                Image(systemName: "checkmark")
                    .font(.system(size: 22, weight: .heavy))
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(Circle().fill(Studio.gradient))
                    .shadow(color: Studio.violet.opacity(0.6), radius: 12)
            }
            .frame(maxWidth: .infinity, maxHeight: 220)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text("¡Tu video está listo!").font(.title3.bold())
                Text(info).font(.caption).foregroundStyle(.secondary)
            }

            #if os(iOS)
            Button {
                Task { await saveToPhotos() }
            } label: {
                HStack {
                    if isSaving { ProgressView().tint(.white) } else { Image(systemName: "photo.on.rectangle.angled") }
                    Text(savedMessage == nil ? "Guardar en Fotos" : "Guardado en Fotos")
                }
            }
            .buttonStyle(StudioButtonStyle())
            .disabled(isSaving || savedMessage != nil)
            #else
            Button {
                saveOnMac()
            } label: {
                Label("Guardar como…", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(StudioButtonStyle())
            #endif

            ShareLink(item: url, preview: SharePreview(model.projectName)) {
                Label("Compartir", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(StudioButtonStyle(gradient: Studio.musicGradient))

            VStack(alignment: .leading, spacing: 8) {
                Text("Al tocar Compartir elige la app:").font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    destination("WhatsApp", "message.fill", Color(red: 0.15, green: 0.8, blue: 0.4))
                    destination("Instagram", "camera.fill", Color(red: 0.88, green: 0.25, blue: 0.55))
                    destination("TikTok", "music.note", Color(white: 0.9))
                    #if os(iOS)
                    destination("AirDrop", "airplayaudio", Color(red: 0.3, green: 0.6, blue: 1))
                    #else
                    destination("Mensajes", "bubble.left.fill", Color(red: 0.3, green: 0.6, blue: 1))
                    #endif
                }
                #if os(iOS)
                Text("¿No aparece Instagram o TikTok? Guarda primero en Fotos y súbelo desde la app. Si no ves una app, toca «Más» en la hoja de compartir.")
                    .font(.caption2).foregroundStyle(.secondary)
                #endif
            }

            if let savedMessage {
                Text(savedMessage).font(.footnote).foregroundStyle(Studio.teal)
            }
        }
        #if os(iOS)
        .listRowBackground(Color.clear)
        #endif
        .task(id: url) { await loadInfo() }
    }

    private func destination(_ name: String, _ symbol: String, _ color: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 40, height: 40)
                .background(Circle().fill(color.opacity(0.16)))
            Text(name).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }

    private func loadInfo() async {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 800, height: 800)
        poster = try? await generator.image(at: CMTime(seconds: 0.5, preferredTimescale: 600)).image
        var parts: [String] = []
        if let seconds = try? await asset.load(.duration).seconds { parts.append(formatTime(seconds)) }
        if let track = try? await asset.loadTracks(withMediaType: .video).first,
           let loaded = try? await track.load(.naturalSize, .preferredTransform) {
            let r = CGRect(origin: .zero, size: loaded.0).applying(loaded.1)
            parts.append("\(Int(abs(r.width)))×\(Int(abs(r.height)))")
        }
        if let bytes = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize {
            parts.append(ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file))
        }
        parts.append(url.pathExtension.uppercased())
        info = parts.joined(separator: " · ")
    }

    #if os(iOS)
    private func saveToPhotos() async {
        isSaving = true
        defer { isSaving = false }
        do {
            try await Exporter.saveToPhotos(url)
            savedMessage = "Guardado en tu galería de Fotos."
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }
    #else
    private func saveOnMac() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(model.projectName).\(url.pathExtension)"
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let dest = panel.url {
            do {
                try? FileManager.default.removeItem(at: dest)
                try FileManager.default.copyItem(at: url, to: dest)
                savedMessage = "Guardado en \(dest.path)"
            } catch {
                model.errorMessage = error.localizedDescription
            }
        }
    }
    #endif
}
