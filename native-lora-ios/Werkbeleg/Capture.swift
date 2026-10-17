import SwiftUI
import AVFoundation
import Speech
import CoreLocation
import UIKit

@MainActor final class Capture: NSObject, ObservableObject, CLLocationManagerDelegate, AVAudioRecorderDelegate {
    @Published var recording = false
    @Published var status = ""
    @Published var text = ""
    @Published var audio: Data? = nil
    @Published var location: CLLocation? = nil
    private let manager = CLLocationManager()
    private var recorder: AVAudioRecorder?
    private var recognition: SFSpeechRecognitionTask?
    private var audioURL: URL?
    override init() { super.init(); manager.delegate = self; manager.desiredAccuracy = kCLLocationAccuracyBest }
    func locate() {
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse: manager.requestLocation()
        default: status = L.t("Standortzugriff in Einstellungen erlauben", "Allow location in Settings", "Zezwól na lokalizację w Ustawieniach")
        }
    }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .authorizedWhenInUse { manager.requestLocation() }
    }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if let last = locations.last, last.horizontalAccuracy >= 0, abs(last.timestamp.timeIntervalSinceNow) < 60 {
            location = last; status = "GPS ±\(Int(last.horizontalAccuracy)) m"
        }
    }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) { status = error.localizedDescription }
    func toggleRecording() async {
        if recording {
            recorder?.stop(); recording = false
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            if let url = audioURL { audio = try? Data(contentsOf: url); await transcribe(url) }
            return
        }
        let allowed = await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { continuation.resume(returning: $0) }
        }
        guard allowed else { status = L.t("Mikrofon nicht erlaubt", "Microphone denied", "Brak dostępu do mikrofonu"); return }
        do {
            try AVAudioSession.sharedInstance().setCategory(.record, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".m4a")
            audioURL = url
            recorder = try AVAudioRecorder(url: url, settings: [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 22050, AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 64000])
            recorder?.delegate = self
            guard recorder?.record(forDuration: 120) == true else { throw TeamError.message("Aufnahme nicht gestartet") }
            recording = true; status = L.t("Aufnahme · maximal 2 Minuten. Zum Beenden tippen.", "Recording · 2 minute limit. Tap to stop.", "Nagrywanie · maks. 2 minuty. Dotknij, aby zakończyć.")
        } catch { status = error.localizedDescription }
    }
    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        guard recording else { return }
        recording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        if flag, let url = audioURL { audio = try? Data(contentsOf: url); Task { await transcribe(url) } }
    }
    func transcribe(_ url: URL) async {
        let auth = await withCheckedContinuation { continuation in SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) } }
        guard auth == .authorized else { status = L.t("Audio gespeichert. Spracherkennung nicht erlaubt.", "Audio saved. Speech recognition denied.", "Dźwięk zapisany. Brak zgody na rozpoznawanie mowy."); return }
        let lang = UserDefaults.standard.string(forKey: "language") ?? String(Locale.preferredLanguages.first?.prefix(2) ?? "de")
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: lang == "pl" ? "pl-PL" : lang == "en" ? "en-GB" : "de-DE")), recognizer.isAvailable else {
            status = "Audio gespeichert; Spracherkennung aktuell nicht verfügbar."; return
        }
        let request = SFSpeechURLRecognitionRequest(url: url)
        recognition = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                if let result = result { self?.text = result.bestTranscription.formattedString }
                if error != nil { self?.status = "Audio gespeichert. Erkennung fehlgeschlagen; Text bitte eingeben." }
                else if result?.isFinal == true { self?.status = L.t("Text bitte prüfen", "Please review the text", "Sprawdź tekst") }
            }
        }
    }
    func stop() {
        recorder?.stop(); recognition?.cancel(); recording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

struct Camera: UIViewControllerRepresentable {
    var result: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let c = UIImagePickerController(); c.sourceType = .camera; c.delegate = context.coordinator; return c
    }
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: Camera
        init(_ parent: Camera) { self.parent = parent }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage { parent.result(image) }; parent.dismiss()
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}
extension UIImage {
    func reportJPEG() -> Data? {
        let ratio = min(1, 1800 / max(size.width, size.height))
        let output = UIGraphicsImageRenderer(size: CGSize(width: size.width * ratio, height: size.height * ratio)).image { _ in self.draw(in: CGRect(x: 0, y: 0, width: size.width * ratio, height: size.height * ratio)) }
        return output.jpegData(compressionQuality: 0.78)
    }
}

enum ReportPDF {
    @MainActor static func make(_ report: Report, job: Job, customer: Customer, company: String) throws -> URL {
        let page = CGRect(x: 0, y: 0, width: 595, height: 842)
        let renderer = UIGraphicsPDFRenderer(bounds: page)
        let title = L.t("Arbeitsbericht", "Work report", "Raport z prac")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Werkbeleg-\(report.id.uuidString).pdf")
        try renderer.writePDF(to: url) { ctx in
            var y: CGFloat = 0
            var pageNumber = 0
            func newPage() {
                ctx.beginPage(); pageNumber += 1; UIColor.white.setFill(); ctx.cgContext.fill(page)
                UIColor.orange.setFill(); ctx.cgContext.fill(CGRect(x: 0, y: 0, width: 595, height: 10)); y = 42
                let footer = "Werkbeleg · \(report.id.uuidString.prefix(8)) · \(pageNumber)"
                footer.draw(at: CGPoint(x: 38, y: 810), withAttributes: [.font: UIFont.systemFont(ofSize: 9), .foregroundColor: UIColor.gray])
            }
            func line(_ text: String, bold: Bool = false) {
                let attrs: [NSAttributedString.Key: Any] = [.font: bold ? UIFont.boldSystemFont(ofSize: 16) : UIFont.systemFont(ofSize: 11), .foregroundColor: UIColor.black]
                // Paragraphs are bounded; exceptionally long text is split so it cannot fall off a page.
                for chunk in text.components(separatedBy: "\n").flatMap({ value -> [String] in
                    let chars = Array(value); return chars.isEmpty ? [""] : stride(from: 0, to: chars.count, by: 500).map { String(chars[$0..<min($0 + 500, chars.count)]) }
                }) {
                    let height = max(18, (chunk as NSString).boundingRect(with: CGSize(width: 519, height: 700), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attrs, context: nil).height + 10)
                    if y + height > 780 { newPage() }
                    (chunk as NSString).draw(in: CGRect(x: 38, y: y, width: 519, height: height), withAttributes: attrs); y += height
                }
            }
            newPage(); line(company.isEmpty ? "Werkbeleg" : company, bold: true); line(title + " · " + job.title, bold: true)
            line(customer.name + "\n" + job.address); line(report.createdAt.formatted(date: .long, time: .shortened) + " · " + report.author)
            if let lat = report.latitude, let lon = report.longitude {
                line(String(format: "GPS %.6f, %.6f · ±%.0f m", lat, lon, report.accuracy ?? 0))
                if let date = report.locationAt { line("GPS: " + date.formatted()) }
            }
            if !report.weather.isEmpty { line(L.t("Wetter (manuell): ", "Weather (manual): ", "Pogoda (ręcznie): ") + report.weather) }
            line(report.text)
            for photo in report.photos {
                guard let image = UIImage(data: photo.data) else { continue }
                if y + 310 > 780 { newPage() }
                let ratio = min(519 / image.size.width, 270 / image.size.height)
                image.draw(in: CGRect(x: 38, y: y, width: image.size.width * ratio, height: image.size.height * ratio)); y += image.size.height * ratio + 8
                line((photo.source == "camera" ? L.t("Aufnahme: ", "Captured: ", "Zdjęcie: ") : L.t("Importiert: ", "Imported: ", "Import: ")) + photo.capturedAt.formatted())
            }
            line(L.t("Dokumentation des Verfassers. Kein manipulationssicherer oder qualifiziert signierter Nachweis.", "Author documentation. Not tamper-proof or a qualified signed record.", "Dokumentacja autora. Brak kwalifikowanego podpisu i gwarancji niezmienności."))
        }
        return url
    }
}
