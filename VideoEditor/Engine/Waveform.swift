import Foundation
import AVFoundation
import CoreMedia
import Observation

/// Forma de onda del audio de un archivo: picos normalizados (0...1), `samplesPerSecond` por segundo.
struct WaveformData {
    static let samplesPerSecond = 40
    let peaks: [Float]

    /// Pico máximo entre dos instantes del archivo (en segundos).
    func peak(from a: Double, to b: Double) -> Float {
        guard !peaks.isEmpty else { return 0 }
        let sps = Double(Self.samplesPerSecond)
        let i0 = max(0, min(peaks.count - 1, Int(a * sps)))
        let i1 = max(i0, min(peaks.count - 1, Int(b * sps)))
        var m: Float = 0
        for i in i0...i1 where peaks[i] > m { m = peaks[i] }
        return m
    }
}

/// Calcula y guarda en memoria la forma de onda de cada archivo, una sola vez por archivo.
@MainActor
@Observable
final class WaveformStore {
    static let shared = WaveformStore()

    private(set) var waveforms: [URL: WaveformData] = [:]
    @ObservationIgnored private var loading: Set<URL> = []

    func waveform(for url: URL) -> WaveformData? { waveforms[url] }

    func load(_ url: URL) {
        guard waveforms[url] == nil, !loading.contains(url) else { return }
        loading.insert(url)
        Task {
            let peaks = await Task.detached(priority: .utility) { await Self.extractPeaks(url: url) }.value
            self.waveforms[url] = WaveformData(peaks: peaks)
            self.loading.remove(url)
        }
    }

    /// Lee el audio como PCM mono de 16 bits a baja frecuencia y guarda el pico de cada tramo.
    nonisolated static func extractPeaks(url: URL) async -> [Float] {
        let asset = AVURLAsset(url: url)
        guard let track = try? await asset.loadTracks(withMediaType: .audio).first,
              let reader = try? AVAssetReader(asset: asset) else { return [] }
        let sampleRate = 8000
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { return [] }
        reader.add(output)
        guard reader.startReading() else { return [] }

        let perBucket = sampleRate / WaveformData.samplesPerSecond
        var peaks: [Float] = []
        var current: Int32 = 0
        var count = 0
        while let buffer = output.copyNextSampleBuffer() {
            guard let block = CMSampleBufferGetDataBuffer(buffer) else { continue }
            let length = CMBlockBufferGetDataLength(block)
            guard length > 1 else { continue }
            let sampleCount = length / 2
            var samples = [Int16](repeating: 0, count: sampleCount)
            samples.withUnsafeMutableBytes { raw in
                if let base = raw.baseAddress {
                    _ = CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: sampleCount * 2, destination: base)
                }
            }
            for s in samples {
                let v = abs(Int32(s))
                if v > current { current = v }
                count += 1
                if count >= perBucket {
                    peaks.append(Float(current) / 32768)
                    current = 0
                    count = 0
                }
            }
        }
        if count > 0 { peaks.append(Float(current) / 32768) }

        // Normaliza para que los audios bajos también se vean.
        let maxPeak = peaks.max() ?? 0
        if maxPeak > 0.001 {
            peaks = peaks.map { min(1, $0 / maxPeak) }
        }
        return peaks
    }
}
