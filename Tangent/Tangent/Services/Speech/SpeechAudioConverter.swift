import AVFoundation
import Speech

/// Continuous sample conversion using APIs available on iOS 26. Access is
/// serialized by LiveSpeechSession; each input is consumed before returning.
final class SpeechAudioConverter {
    private let analyzerFormat: AVAudioFormat
    private var converter: AVAudioConverter?
    private var finished = false

    init(analyzerFormat: AVAudioFormat) {
        self.analyzerFormat = analyzerFormat
    }

    func convert(_ buffer: AVAudioPCMBuffer) throws -> [AnalyzerInput] {
        guard !finished else { throw TranscriptionError.recognitionInterrupted }
        guard buffer.frameLength > 0 else { return [] }
        if converter == nil {
            guard let converter = AVAudioConverter(from: buffer.format, to: analyzerFormat) else {
                throw TranscriptionError.recognizerUnavailable
            }
            self.converter = converter
        }
        guard let converter, converter.inputFormat == buffer.format else {
            // Route changes end the recording rather than silently losing the
            // previous converter's held-over samples.
            throw TranscriptionError.recognitionInterrupted
        }
        return try drain(converter, input: buffer, endOfStream: false)
    }

    func flush() throws -> [AnalyzerInput] {
        guard !finished else { return [] }
        finished = true
        guard let converter else { return [] }
        return try drain(converter, input: nil, endOfStream: true)
    }

    private func drain(_ converter: AVAudioConverter, input: AVAudioPCMBuffer?, endOfStream: Bool) throws -> [AnalyzerInput] {
        var suppliedInput = false
        var result: [AnalyzerInput] = []
        while true {
            guard let output = AVAudioPCMBuffer(pcmFormat: analyzerFormat, frameCapacity: 4096) else {
                throw TranscriptionError.recognitionFellBehind
            }
            var error: NSError?
            let status = converter.convert(to: output, error: &error) { _, inputStatus in
                if let input, !suppliedInput {
                    suppliedInput = true
                    inputStatus.pointee = .haveData
                    return input
                }
                inputStatus.pointee = endOfStream ? .endOfStream : .noDataNow
                return nil
            }
            if let error { throw error }
            if output.frameLength > 0 { result.append(AnalyzerInput(buffer: output)) }
            switch status {
            case .haveData: continue
            case .inputRanDry, .endOfStream: return result
            case .error: throw TranscriptionError.recognitionInterrupted
            @unknown default: throw TranscriptionError.recognitionInterrupted
            }
        }
    }
}
