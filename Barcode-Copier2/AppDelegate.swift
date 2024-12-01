import UIKit

class AppDelegate: UIResponder, UIApplicationDelegate {
    var shouldOpenScanner = false // État pour l'ouverture du scanner
    
    func application(_ application: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey : Any] = [:]) -> Bool {
        guard let scheme = url.scheme, scheme == "barcodecopier", let host = url.host else {
            return false
        }
        
        // Si l'URL contient "scanner", active le drapeau
        if host == "scanner" {
            shouldOpenScanner = true
            NotificationCenter.default.post(name: Notification.Name("OpenScanner"), object: nil)
        }
        
        return true
    }
}
