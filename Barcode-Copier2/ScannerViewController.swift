import UIKit
import AVFoundation

protocol ScannerViewControllerDelegate: AnyObject {
    func didFindCode(_ code: String)
}

class ScannerViewController: UIViewController {
    weak var delegate: ScannerViewControllerDelegate?
    var torchOn: Bool = false
    var scannedCodes: [ScannedCode] = [] // Correction précédente
    var onDismiss: (() -> Void)? // Correction précédente

    private var captureSession: AVCaptureSession?
    private var videoPreviewLayer: AVCaptureVideoPreviewLayer?
    private var currentDevice: AVCaptureDevice?
    private var notificationLabel: UILabel?
    private var switchCameraButton: UIButton?
    private var isProcessingScan = false

    override func viewDidLoad() {
        super.viewDidLoad()
        setupCamera()
        setupUI()
        setupTapToFocus()
    }

    private func setupCamera() {
        captureSession = AVCaptureSession()

        // Récupérer l'appareil photo principal
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else { return }
        currentDevice = device

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            do {
                let input = try AVCaptureDeviceInput(device: device)
                if self.captureSession!.canAddInput(input) {
                    self.captureSession!.addInput(input)
                }

                let metadataOutput = AVCaptureMetadataOutput()
                if self.captureSession!.canAddOutput(metadataOutput) {
                    self.captureSession!.addOutput(metadataOutput)
                    metadataOutput.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
                    metadataOutput.metadataObjectTypes = metadataOutput.availableMetadataObjectTypes
                }

                DispatchQueue.main.async {
                    self.videoPreviewLayer = AVCaptureVideoPreviewLayer(session: self.captureSession!)
                    self.videoPreviewLayer?.videoGravity = .resizeAspectFill
                    self.videoPreviewLayer?.frame = self.view.layer.bounds
                    self.view.layer.addSublayer(self.videoPreviewLayer!)

                    // Démarrer la session
                    DispatchQueue.global(qos: .userInitiated).async {
                        self.captureSession?.startRunning()
                    }

                    // Amener la vue des boutons au premier plan
                    self.view.bringSubviewToFront(self.view.subviews.last!)
                }
            } catch {
                print("Erreur lors de la configuration de l'appareil photo : \(error)")
            }
        }
    }

    private func setupUI() {
        let torchButton = createButton(
            imageName: "flashlight.on.fill",
            backgroundColor: .systemYellow,
            action: #selector(toggleTorch)
        )

        switchCameraButton = createButton(
            imageName: "arrow.triangle.2.circlepath.camera",
            backgroundColor: .systemBlue,
            action: #selector(switchCamera),
            title: "1x" // Initialement grand angle
        )

        let stackView = UIStackView(arrangedSubviews: [torchButton, switchCameraButton!])
        stackView.axis = .horizontal
        stackView.spacing = 20
        stackView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stackView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20)
        ])
    }

    private func createButton(imageName: String, backgroundColor: UIColor, action: Selector) -> UIButton {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: imageName), for: .normal)
        button.tintColor = .white
        button.backgroundColor = backgroundColor
        button.layer.cornerRadius = 40
        button.layer.shadowColor = UIColor.black.cgColor
        button.layer.shadowOpacity = 0.3
        button.layer.shadowOffset = CGSize(width: 0, height: 2)
        button.layer.shadowRadius = 4
        button.addTarget(self, action: action, for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 80),
            button.heightAnchor.constraint(equalToConstant: 80)
        ])

        return button
    }

    private func setupTapToFocus() {
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleFocusTap(_:)))
        view.addGestureRecognizer(tapGesture)
    }

    @objc private func handleFocusTap(_ gesture: UITapGestureRecognizer) {
        let location = gesture.location(in: view)
        guard let device = currentDevice else { return }

        do {
            try device.lockForConfiguration()

            if device.isFocusPointOfInterestSupported {
                let focusPoint = videoPreviewLayer?.captureDevicePointConverted(fromLayerPoint: location) ?? CGPoint(x: 0.5, y: 0.5)
                device.focusPointOfInterest = focusPoint
                device.focusMode = .autoFocus
            }

            if device.isExposurePointOfInterestSupported {
                let exposurePoint = videoPreviewLayer?.captureDevicePointConverted(fromLayerPoint: location) ?? CGPoint(x: 0.5, y: 0.5)
                device.exposurePointOfInterest = exposurePoint
                device.exposureMode = .autoExpose
            }

            device.unlockForConfiguration()

            showFocusIndicator(at: location)
        } catch {
            print("Erreur lors de la mise au point : \(error)")
        }
    }

    private func formatCodeType(_ rawType: String) -> String {
        // Supprime les préfixes comme "org.iso." ou autres inutiles
        if rawType.hasPrefix("org.iso.") {
            return String(rawType.dropFirst("org.iso.".count))
        }
        return rawType
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
    
    private func showFocusIndicator(at point: CGPoint) {
        let focusIndicator = UIView(frame: CGRect(x: 0, y: 0, width: 80, height: 80))
        focusIndicator.center = point
        focusIndicator.layer.borderColor = UIColor.yellow.cgColor
        focusIndicator.layer.borderWidth = 2
        focusIndicator.layer.cornerRadius = 40
        focusIndicator.backgroundColor = UIColor.clear
        view.addSubview(focusIndicator)

        UIView.animate(withDuration: 0.3, animations: {
            focusIndicator.transform = CGAffineTransform(scaleX: 0.7, y: 0.7)
        }) { _ in
            UIView.animate(withDuration: 0.3, delay: 0.5, options: [], animations: {
                focusIndicator.alpha = 0.0
            }) { _ in
                focusIndicator.removeFromSuperview()
            }
        }
    }

    @objc private func toggleTorch() {
        guard let device = currentDevice, device.hasTorch else { return }
        do {
            try device.lockForConfiguration()
            device.torchMode = torchOn ? .off : .on
            torchOn.toggle()
            device.unlockForConfiguration()
        } catch {
            print("Erreur lors de l'activation de la torche.")
        }
    }
}



extension ScannerViewController: AVCaptureMetadataOutputObjectsDelegate {
    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard !isProcessingScan,
              let metadataObject = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let scannedCodeString = metadataObject.stringValue else { return }
        
        isProcessingScan = true // Bloque le traitement d'autres scans
        
        // Variable pour contenir ce qui sera copié dans le presse-papiers
        var contentToCopy = scannedCodeString
        
        // Vérifie si le contenu scanné est un QR code WiFi
        if let wifiPassword = extractWiFiPassword(from: scannedCodeString) {
            contentToCopy = wifiPassword // Met à jour la variable avec le mot de passe
            scannedCodes.append(ScannedCode(content: wifiPassword, type: "WiFi Password"))
        } else {
            scannedCodes.append(ScannedCode(content: scannedCodeString, type: metadataObject.type.rawValue))
        }
        
        // Copie le contenu final (mot de passe ou contenu brut) dans le presse-papiers
        UIPasteboard.general.string = contentToCopy
        
        // Notifie le délégué avec le contenu correct
        delegate?.didFindCode(contentToCopy)
        
        // Confirmation haptique unique
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
        
        // Ferme la vue après le scan
        onDismiss?()
        
        // Réinitialise le drapeau après un délai
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.isProcessingScan = false
        }
    }
    
    private func showNotification(_ message: String) {
        // Supprime l'ancienne notification si elle existe
        notificationLabel?.removeFromSuperview()

        // Crée une nouvelle notification
        let label = UILabel()
        label.text = message
        label.textColor = .white
        label.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        label.textAlignment = .center
        label.font = UIFont.boldSystemFont(ofSize: 16)
        label.layer.cornerRadius = 10
        label.layer.masksToBounds = true
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)

        // Positionne la notification en haut de l'écran
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 10),
            label.widthAnchor.constraint(equalToConstant: 200),
            label.heightAnchor.constraint(equalToConstant: 40)
        ])

        // Animation pour supprimer la notification après 2 secondes
        UIView.animate(withDuration: 0.3, delay: 2.0, options: [], animations: {
            label.alpha = 0
        }) { _ in
            label.removeFromSuperview()
        }

        // Garde une référence pour éviter les duplications
        notificationLabel = label
    }
    
    private func createButton(imageName: String, backgroundColor: UIColor, action: Selector, title: String? = nil) -> UIButton {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: imageName), for: .normal)
        button.setTitle(title, for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 14, weight: .bold)
        button.setTitleColor(.white, for: .normal)
        button.tintColor = .white
        button.backgroundColor = backgroundColor
        button.layer.cornerRadius = 40
        button.layer.shadowColor = UIColor.black.cgColor
        button.layer.shadowOpacity = 0.3
        button.layer.shadowOffset = CGSize(width: 0, height: 2)
        button.layer.shadowRadius = 4
        button.addTarget(self, action: action, for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 80),
            button.heightAnchor.constraint(equalToConstant: 80)
        ])

        return button
    }
    
    @objc private func switchCamera() {
        guard let session = captureSession else { return }

        session.stopRunning()

        let currentDeviceType = currentDevice?.deviceType
        let nextDeviceType: AVCaptureDevice.DeviceType = {
            switch currentDeviceType {
            case .builtInWideAngleCamera:
                return .builtInUltraWideCamera
            case .builtInUltraWideCamera:
                return .builtInTelephotoCamera
            case .builtInTelephotoCamera:
                return .builtInWideAngleCamera
            default:
                return .builtInWideAngleCamera
            }
        }()

        guard let newDevice = AVCaptureDevice.default(nextDeviceType, for: .video, position: .back) else { return }
        currentDevice = newDevice

        do {
            session.beginConfiguration()
            session.inputs.forEach { session.removeInput($0) }
            let newInput = try AVCaptureDeviceInput(device: newDevice)
            session.addInput(newInput)
            session.commitConfiguration()

            // Démarrer la session sur un thread en arrière-plan
            DispatchQueue.global(qos: .userInitiated).async {
                session.startRunning()
            }

            // Affiche le message de notification
            let message: String
            switch nextDeviceType {
            case .builtInWideAngleCamera:
                message = "Grand Angle (1x)"
                switchCameraButton?.setTitle("1x", for: .normal)
            case .builtInUltraWideCamera:
                message = "Ultra Grand Angle (0,5x)"
                switchCameraButton?.setTitle("0,5x", for: .normal)
            case .builtInTelephotoCamera:
                message = "Telephoto (5x)"
                switchCameraButton?.setTitle("5x", for: .normal)
            default:
                message = "Objectif Inconnu"
                switchCameraButton?.setTitle("-", for: .normal)
            }
            showNotification(message)

        } catch {
            print("Erreur lors du changement d'objectif : \(error)")
        }
    }
    
}

