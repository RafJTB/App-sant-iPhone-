import SwiftUI
import VisionKit

/// Écran de scan : caméra (VisionKit) + saisie manuelle du code en secours.
struct ScanBarcodeView: View {
    let onFound: (FoodItem) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var manualCode = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var scannerID = UUID()

    private var scannerAvailable: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ZStack {
                    if scannerAvailable {
                        BarcodeScannerRepresentable(onScan: lookUp)
                            .id(scannerID)
                    } else {
                        ContentUnavailableView(
                            "Caméra indisponible",
                            systemImage: "barcode.viewfinder",
                            description: Text("Autorise l'accès à la caméra (Réglages › Confidentialité et sécurité › Caméra) ou saisis le code-barres ci-dessous. Le scan nécessite un iPhone XS / XR ou plus récent.")
                        )
                    }
                    if isLoading {
                        ProgressView("Recherche du produit…")
                            .padding()
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    }
                }
                .frame(maxHeight: .infinity)

                VStack(spacing: 12) {
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.subheadline)
                            .foregroundStyle(.orange)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if scannerAvailable {
                            Button("Scanner à nouveau") {
                                self.errorMessage = nil
                                scannerID = UUID()
                            }
                        }
                    } else {
                        Text("Vise le code-barres de l'emballage.")
                            .font(.subheadline).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    HStack {
                        TextField("Ou tape le code (ex. 3017620422003)", text: $manualCode)
                            .keyboardType(.numberPad)
                            .textFieldStyle(.roundedBorder)
                        Button("OK") { lookUp(manualCode) }
                            .buttonStyle(.borderedProminent)
                            .disabled(manualCode.filter(\.isNumber).count < 8 || isLoading)
                    }
                    Text("Données : Open Food Facts (base collaborative, à vérifier avec l'étiquette).")
                        .font(.caption2).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding()
                .background(Color(.secondarySystemBackground))
            }
            .navigationTitle("Scanner")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { dismiss() }
                }
            }
        }
    }

    private func lookUp(_ code: String) {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        Task {
            do {
                let product = try await OpenFoodFactsClient.shared.product(barcode: code)
                isLoading = false
                onFound(product.asFoodItem)
                dismiss()
            } catch {
                isLoading = false
                errorMessage = error.localizedDescription
            }
        }
    }
}

/// Pont UIKit → SwiftUI pour le scanner de VisionKit.
private struct BarcodeScannerRepresentable: UIViewControllerRepresentable {
    let onScan: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let controller = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.ean13, .ean8, .upce])],
            qualityLevel: .balanced,
            isHighlightingEnabled: true
        )
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: DataScannerViewController, context: Context) {
        if !controller.isScanning && !context.coordinator.didScan {
            try? controller.startScanning()
        }
    }

    static func dismantleUIViewController(_ controller: DataScannerViewController, coordinator: Coordinator) {
        controller.stopScanning()
    }

    func makeCoordinator() -> Coordinator { Coordinator(onScan: onScan) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onScan: (String) -> Void
        var didScan = false

        init(onScan: @escaping (String) -> Void) {
            self.onScan = onScan
        }

        func dataScanner(_ dataScanner: DataScannerViewController,
                         didAdd addedItems: [RecognizedItem],
                         allItems: [RecognizedItem]) {
            guard !didScan else { return }
            for item in addedItems {
                if case .barcode(let barcode) = item, let code = barcode.payloadStringValue {
                    didScan = true
                    dataScanner.stopScanning()
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    onScan(code)
                    return
                }
            }
        }
    }
}
