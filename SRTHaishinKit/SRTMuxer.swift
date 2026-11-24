import AVFoundation
import Foundation
import HaishinKit

final class SRTMuxer: IOMuxer {
    // Sideline patch (build 8 review): pass straight through to the writer,
    // which keeps them under its lock. Stored copies here were written from
    // the audio queue, VideoToolbox's callback thread and the stream's queue
    // with no lock at all.
    var audioFormat: AVAudioFormat? {
        get { writer.audioFormat }
        set { writer.audioFormat = newValue }
    }
    var videoFormat: CMFormatDescription? {
        get { writer.videoFormat }
        set { writer.videoFormat = newValue }
    }
    var expectedMedias: Set<AVMediaType> {
        get { writer.expectedMedias }
        set { writer.expectedMedias = newValue }
    }
    private weak var stream: SRTStream?
    private(set) var isRunning: Atomic<Bool> = .init(false)
    // Not lazy: a lazy var is not thread-safe, and the formats above are now
    // read and written through it from several threads.
    private let writer = TSWriter<SRTMuxer>()
    private lazy var reader = {
        var reader = TSReader<SRTMuxer>()
        reader.delegate = self
        return reader
    }()

    init(_ stream: SRTStream) {
        self.stream = stream
        writer.delegate = self
    }

    func append(_ audioBuffer: AVAudioBuffer, when: AVAudioTime) {
        writer.append(audioBuffer, when: when)
        stream?.publishStats.set(writer.stats)
    }

    func append(_ sampleBuffer: CMSampleBuffer) {
        writer.append(sampleBuffer)
        stream?.publishStats.set(writer.stats, announcedSPS: writer.announcedSPS)
    }

    func read(_ data: Data) {
        _ = reader.read(data)
    }
}

extension SRTMuxer: Running {
    // MARK: Running
    func startRunning() {
        guard !isRunning.value else {
            return
        }
        isRunning.mutate { $0 = true }
    }

    func stopRunning() {
        guard isRunning.value else {
            return
        }
        reader.clear()
        writer.clear()
        stream?.publishStats.set(writer.stats, announcedSPS: nil)
        isRunning.mutate { $0 = false }
    }
}

extension SRTMuxer: TSWriterDelegate {
    // MARK: TSWriterDelegate
    func writer(_ writer: TSWriter<SRTMuxer>, didOutput data: Data) {
        stream?.doOutput(data)
    }

    func writer(_ writer: TSWriter<SRTMuxer>, didRotateFileHandle timestamp: CMTime) {
    }
}

extension SRTMuxer: TSReaderDelegate {
    // MARK: TSReaderDelegate
    func reader(_ reader: TSReader<SRTMuxer>, id: UInt16, didRead formatDescription: CMFormatDescription) {
    }

    func reader(_ reader: TSReader<SRTMuxer>, id: UInt16, didRead sampleBuffer: CMSampleBuffer) {
        stream?.append(sampleBuffer)
    }
}
