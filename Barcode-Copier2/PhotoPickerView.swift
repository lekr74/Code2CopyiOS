import SwiftUI
import PhotosUI
import Vision

struct PhotoPickerView: UIViewControllerRepresentable {
    var completion: (ScannedCode?) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration()
        configuration.filter = .images // Limite à la sélection des images
        configuration.selectionLimit = 1

        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(completion: completion)
    }

    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        var completion: (ScannedCode?) -> Void

        init(completion: @escaping (ScannedCode?) -> Void) {
            self.completion = completion
        }
        
        private func extractWiFiPassword(from qrCodeContent: String) -> String? {
            // Le format attendu : WIFI:S:<SSID>;T:<authType>;P:<password>;H:<hidden>;
            guard qrCodeContent.starts(with: "WIFI:") else { return nil }
            
            let components = qrCodeContent
                .dropFirst(5) // Supprime "WIFI:"
                .split(separator: ";")
                .reduce(into: [String: String]()) { result, item in
                    let pair = item.split(separator: ":", maxSplits: 1).map(String.init)
                    if pair.count == 2 {
                        result[pair[0]] = pair[1]
                    }
                }

            // Retourne le mot de passe si disponible
            return components["P"]
        }
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)

            guard let provider = results.first?.itemProvider, provider.canLoadObject(ofClass: UIImage.self) else {
                completion(nil)
                return
            }

            provider.loadObject(ofClass: UIImage.self) { (object, error) in
                if let image = object as? UIImage {
                    self.detectBarcode(in: image)
                }
            }
        }

        private func detectBarcode(in image: UIImage) {
            guard let cgImage = image.cgImage else {
                completion(nil)
                return
            }

            let request = VNDetectBarcodesRequest { (request, error) in
                guard let results = request.results as? [VNBarcodeObservation],
                      let payload = results.first?.payloadStringValue else {
                    self.completion(nil)
                    return
                }

                // Vérifie si le QR code contient des informations WiFi
                if let wifiPassword = self.extractWiFiPassword(from: payload) {
                    // Copie uniquement le mot de passe dans le presse-papiers
                    UIPasteboard.general.string = wifiPassword

                    // Crée un objet ScannedCode pour l'historique
                    let scannedCode = ScannedCode(content: wifiPassword, type: "WiFi Password")
                    self.completion(scannedCode)
                } else {
                    // Si ce n'est pas un QR code WiFi, copie tout le contenu
                    UIPasteboard.general.string = payload

                    // Crée un objet ScannedCode pour l'historique
                    let scannedCode = ScannedCode(content: payload, type: "Photo Barcode")
                    self.completion(scannedCode)
                }
            }

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                completion(nil)
            }
        }
    }
}
