import SwiftUI
import AVFoundation

struct CameraScannerView: UIViewControllerRepresentable {
    @Binding var scannedCodes: [ScannedCode]
    @Binding var torchOn: Bool
    var dismiss: () -> Void

    func makeUIViewController(context: Context) -> ScannerViewController {
        let scannerViewController = ScannerViewController()
        scannerViewController.delegate = context.coordinator
        scannerViewController.torchOn = torchOn
        scannerViewController.onDismiss = dismiss
        return scannerViewController
    }

    func updateUIViewController(_ uiViewController: ScannerViewController, context: Context) {
        uiViewController.torchOn = torchOn
    }

    func makeCoordinator() -> Coordinator {
        return Coordinator(self)
    }

    class Coordinator: NSObject, ScannerViewControllerDelegate {
        var parent: CameraScannerView

        init(_ parent: CameraScannerView) {
            self.parent = parent
        }

        func didFindCode(_ code: String) {
            // Évite les doublons et ferme le scanner après un scan réussi
            if !parent.scannedCodes.contains(where: { $0.content == code }) {
                let scannedCode = ScannedCode(content: code, type: "org.iso.QRCode");                parent.scannedCodes.append(scannedCode)
                parent.dismiss()
                UIPasteboard.general.string = code
            }
        }
    }
}
