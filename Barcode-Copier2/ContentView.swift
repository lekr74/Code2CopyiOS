import SwiftUI
import UIKit


struct ContentView: View {
    @State private var isScannerPresented = false
    @State private var scannedCodes: [ScannedCode] = []
    @State private var torchOn = false
    @State private var showDeleteConfirmation = false
    @State private var isPhotoPickerPresented = false

    var body: some View {
        NavigationView {
            VStack {
                List {
                    ForEach(scannedCodesGroupedByDate(), id: \.0) { section in
                        Section(header: Text(section.0)) {
                            ForEach(section.1) { code in
                                HStack {
                                    // Détermine si c'est un QR Code Wi-Fi et affiche uniquement le mot de passe
                                    Text(code.type == "org.iso.QRCode" && extractWiFiPassword(from: code.content) != nil ?
                                         extractWiFiPassword(from: code.content)! :
                                         code.content)
                                        .font(.body)
                                        .lineLimit(1)

                                    Spacer()
                                    
                                    
                                    Button(action: {
                                        UIPasteboard.general.string = code.type == "org.iso.QRCode" && extractWiFiPassword(from: code.content) != nil ?
                                            extractWiFiPassword(from: code.content)! :
                                            code.content
                                    }) {
                                        Image(systemName: "doc.on.clipboard")
                                    }
                                    .buttonStyle(BorderlessButtonStyle())
                                }
                            }
                            .onDelete { indexSet in
                                deleteScannedCode(at: indexSet, in: section.1)
                            }
                        }
                    }
                }
                Spacer()
                HStack {
                    Button(action: {
                        isScannerPresented = true
                    }) {
                        Text("Scanner")
                            .font(.title2)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    }

                    Button(action: {
                        isPhotoPickerPresented = true
                    }) {
                        Text("Photo")
                            .font(.title2)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.green)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    }
                }
                .padding()
            }
            .navigationTitle("Historique")
            .navigationBarItems(
                leading: Button(action: {
                    openNotesApp()
                }) {
                    HStack {
                        Image(systemName: "note.text")
                        Text("Ouvrir Notes")
                    }
                },
                trailing: Button(action: {
                    showDeleteConfirmation = true
                }) {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                }
            )
            
            .onAppear {
                loadScannedCodes()
            }
            .onDisappear(perform: saveScannedCodes)
            .alert(isPresented: $showDeleteConfirmation) {
                Alert(
                    title: Text("Confirmation"),
                    message: Text("Voulez-vous vraiment supprimer tous les codes scannés ?"),
                    primaryButton: .destructive(Text("Supprimer")) {
                        deleteAllScannedCodes()
                    },
                    secondaryButton: .cancel(Text("Annuler"))
                )
            }
            .sheet(isPresented: $isPhotoPickerPresented) {
                PhotoPickerView { result in
                    if let scannedCode = result {
                        scannedCodes.append(scannedCode)
                        saveScannedCodes()
                    }
                }
            }
            .sheet(isPresented: $isScannerPresented) {
                CameraScannerView(
                    scannedCodes: $scannedCodes,
                    torchOn: $torchOn,
                    dismiss: { isScannerPresented = false }
                )
            }
        }
    }

    private func extractWiFiPassword(from qrContent: String) -> String? {
        if qrContent.hasPrefix("WIFI:") {
            let components = qrContent.dropFirst(5).components(separatedBy: ";")
            for component in components {
                if component.hasPrefix("P:") {
                    return String(component.dropFirst(2)) // Retourne le mot de passe
                }
            }
        }
        return nil // Retourne nil si ce n'est pas un QR Wi-Fi
    }
    
    private func deleteAllScannedCodes() {
        scannedCodes.removeAll()
        saveScannedCodes() // Mettez à jour les données persistées
    }
    
    private func scannedCodesGroupedByDate() -> [(String, [ScannedCode])] {
        let grouped = Dictionary(grouping: scannedCodes) { code -> String in
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .none

            if Calendar.current.isDateInToday(code.timestamp) {
                return "Aujourd'hui"
            } else if Calendar.current.isDateInYesterday(code.timestamp) {
                return "Hier"
            } else {
                return formatter.string(from: code.timestamp)
            }
        }

        // Trier les groupes en traitant "Aujourd'hui" et "Hier" en priorité
        let sortedGroups = grouped
            .map { (key: $0.key, value: $0.value.sorted { $0.timestamp > $1.timestamp }) } // Trier à l'intérieur du groupe
            .sorted { (lhs, rhs) -> Bool in
                if lhs.key == "Aujourd'hui" {
                    return true // "Aujourd'hui" en haut
                } else if rhs.key == "Aujourd'hui" {
                    return false
                } else if lhs.key == "Hier" {
                    return true // "Hier" juste après
                } else if rhs.key == "Hier" {
                    return false
                } else {
                    // Comparer les dates des autres jours
                    let formatter = DateFormatter()
                    formatter.dateStyle = .medium
                    formatter.timeStyle = .none

                    let lhsDate = formatter.date(from: lhs.key) ?? Date.distantPast
                    let rhsDate = formatter.date(from: rhs.key) ?? Date.distantPast
                    return lhsDate > rhsDate
                }
            }

        return sortedGroups
    }
    
    private func deleteScannedCode(at indexSet: IndexSet, in codes: [ScannedCode]) {
        for index in indexSet {
            if let removeIndex = scannedCodes.firstIndex(of: codes[index]) {
                scannedCodes.remove(at: removeIndex)
            }
        }
    }

    private func saveScannedCodes() {
        if let data = try? JSONEncoder().encode(scannedCodes) {
            UserDefaults.standard.set(data, forKey: "scannedCodes")
        }
    }

    private func formatCodeType(_ rawType: String) -> String {
        switch rawType {
        case "org.iso.QRCode": return "QR Code"
        case "org.gs1.EAN-13": return "EAN-13"
        case "org.gs1.EAN-8": return "EAN-8"
        case "org.iso.DataMatrix": return "Data Matrix"
        default: return "Autre"
        }
    }
    
    private func openNotesApp() {
        if let notesURL = URL(string: "mobilenotes://") {
            UIApplication.shared.open(notesURL, options: [:]) { success in
                if !success {
                    print("Impossible d'ouvrir l'application Notes.")
                }
            }
        }
    }
    
    private func loadScannedCodes() {
        if let data = UserDefaults.standard.data(forKey: "scannedCodes"),
           let decoded = try? JSONDecoder().decode([ScannedCode].self, from: data) {
            scannedCodes = decoded
        }
    }
}
