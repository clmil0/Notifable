import AVFoundation
import Foundation
import Speech

/// Micrófono → texto, en el teléfono, partido en frases por los silencios.
///
/// Cada vez que el usuario calla un momento, lo dicho se entrega por
/// `onPhrase` y el reconocimiento vuelve a empezar vacío. Así cada frase se
/// entiende por separado («24 en el almuerzo» … «y 8 en el taxi»), y además se
/// esquiva el límite de un minuto por petición de `SFSpeechRecognizer`.
@MainActor
final class SpeechDictation: ObservableObject {

    enum Phase: Equatable {
        case idle
        case starting
        case listening
        /// Sin permiso de micrófono o de reconocimiento.
        case denied
        case unavailable(String)
    }

    @Published private(set) var phase: Phase = .idle
    /// Lo que se va entendiendo de la frase en curso.
    @Published private(set) var partial = ""
    /// Volumen del micrófono, 0…1, suavizado. Mueve las barras.
    @Published private(set) var level: Double = 0

    var onPhrase: ((String) -> Void)?

    /// Cuánto silencio cierra una frase.
    var pause: Duration = .milliseconds(1_300)

    private let engine = AVAudioEngine()
    private let recognizer: SFSpeechRecognizer?
    private let feed = RequestFeed()
    private var task: SFSpeechRecognitionTask?
    /// Invalida los callbacks de una petición ya reemplazada.
    private var generation = 0
    private var silence: Task<Void, Never>?
    /// Se consulta una vez y fuera del hilo principal: la primera lectura de
    /// `supportsOnDeviceRecognition` busca los modelos en disco y llegó a
    /// congelar la app casi 5 s.
    private var onDevice = false

    init() {
        recognizer = ["es-PE", "es-419", "es-US", "es-MX", "es-ES"].lazy
            .compactMap { SFSpeechRecognizer(locale: Locale(identifier: $0)) }
            .first { $0.isAvailable } ?? SFSpeechRecognizer(locale: Locale(identifier: "es-ES"))
    }

    // MARK: - Arranque y parada

    func start() async {
        guard phase == .idle || phase == .denied || phase.isUnavailable else { return }
        phase = .starting

        guard await Self.requestPermissions() else {
            phase = .denied
            return
        }
        guard let recognizer, recognizer.isAvailable else {
            phase = .unavailable("El reconocimiento de voz en español no está disponible ahora.")
            return
        }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            input.removeTap(onBus: 0)
            let feed = self.feed
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
                feed.append(buffer)
                let level = Self.level(of: buffer)
                Task { @MainActor [weak self] in self?.updateLevel(level) }
            }
            engine.prepare()
            try engine.start()
        } catch {
            phase = .unavailable("No se pudo abrir el micrófono.")
            return
        }

        let candidate = recognizer
        onDevice = await Task.detached(priority: .userInitiated) {
            candidate.supportsOnDeviceRecognition
        }.value

        phase = .listening
        beginRequest()
    }

    /// Entrega lo que quedara a medias y apaga el micrófono.
    func stop(flush: Bool = true) {
        silence?.cancel()
        if flush { closePhrase() }
        generation += 1
        task?.cancel()
        task = nil
        feed.set(nil)
        if engine.isRunning {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
        }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        partial = ""
        level = 0
        phase = .idle
    }

    // MARK: - Frases

    private func beginRequest() {
        generation += 1
        let current = generation
        task?.cancel()

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        request.addsPunctuation = false
        // En el teléfono cuando se puede: más rápido y nada sale a la red.
        request.requiresOnDeviceRecognition = onDevice
        request.contextualStrings = ["soles", "lucas", "Yape", "Plin", "Tambo", "Rappi", "Metro", "Plaza Vea"]
        feed.set(request)

        task = recognizer?.recognitionTask(with: request) { [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            Task { @MainActor [weak self] in
                guard let self, current == self.generation else { return }
                if let text, !text.isEmpty {
                    self.partial = text
                    self.scheduleSilence()
                }
                if isFinal || error != nil {
                    self.closePhrase()
                    guard self.phase == .listening else { return }
                    // Tras un error («no se detectó voz») se espera un poco:
                    // reintentar en el acto puede entrar en bucle.
                    if error != nil {
                        self.generation += 1
                        let retry = self.generation
                        Task { @MainActor [weak self] in
                            try? await Task.sleep(for: .milliseconds(400))
                            guard let self, retry == self.generation, self.phase == .listening else { return }
                            self.beginRequest()
                        }
                    } else {
                        self.beginRequest()
                    }
                }
            }
        }
    }

    private func scheduleSilence() {
        silence?.cancel()
        let pause = self.pause
        silence = Task { [weak self] in
            try? await Task.sleep(for: pause)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, self.phase == .listening else { return }
                self.closePhrase()
                self.beginRequest()
            }
        }
    }

    private func closePhrase() {
        silence?.cancel()
        let text = partial.trimmingCharacters(in: .whitespacesAndNewlines)
        partial = ""
        guard !text.isEmpty else { return }
        onPhrase?(text)
    }

    // MARK: - Volumen

    private func updateLevel(_ value: Double) {
        // Sube rápido y baja despacio: las barras no tiemblan entre sílabas.
        level = value > level ? value : level * 0.82 + value * 0.18
    }

    nonisolated private static func level(of buffer: AVAudioPCMBuffer) -> Double {
        guard let channel = buffer.floatChannelData?[0] else { return 0 }
        let count = Int(buffer.frameLength)
        guard count > 0 else { return 0 }
        var sum: Float = 0
        for i in 0..<count { sum += channel[i] * channel[i] }
        let rms = sqrt(sum / Float(count))
        let db = 20 * log10(max(rms, 0.000_01))
        // -55 dB es silencio de habitación; -15 dB, voz cerca del teléfono.
        return Double(min(1, max(0, (db + 55) / 40)))
    }

    // MARK: - Permisos

    static func requestPermissions() async -> Bool {
        let speech = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard speech == .authorized else { return false }
        return await AVAudioApplication.requestRecordPermission()
    }
}

private extension SpeechDictation.Phase {
    var isUnavailable: Bool {
        if case .unavailable = self { return true }
        return false
    }
}

/// La petición en curso, compartida con el hilo de audio. El tap del
/// micrófono no puede tocar el estado del actor principal.
private final class RequestFeed: @unchecked Sendable {
    private let lock = NSLock()
    private var request: SFSpeechAudioBufferRecognitionRequest?

    func set(_ request: SFSpeechAudioBufferRecognitionRequest?) {
        lock.withLock {
            self.request?.endAudio()
            self.request = request
        }
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        lock.withLock { request?.append(buffer) }
    }
}
