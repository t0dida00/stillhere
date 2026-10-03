import CoreImage.CIFilterBuiltins
import SwiftUI
import VisionKit

/// My invite as a QR code. It encodes `stillhere://invite/<code>`, so the system Camera app opens it too.
struct InviteQRView: View {
    let name: String
    let code: String

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Text("Ask your partner to scan this in Still Here (Users → Add partner → Scan QR code), or with the Camera app.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)

                if let image = Self.qrImage(for: IdentityService.inviteURL(for: code).absoluteString) {
                    Image(uiImage: image)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 260)
                        .padding(16)
                        .background(.white, in: RoundedRectangle(cornerRadius: 20))
                        .accessibilityLabel("QR code for invite code \(code)")
                }

                VStack(spacing: 4) {
                    Text(name).font(.headline)
                    Text(code)
                        .font(.title2.monospaced().weight(.semibold))
                        .textSelection(.enabled)
                }
                Spacer()
            }
            .padding(24)
            .navigationTitle("My invite")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    static func qrImage(for text: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 10, y: 10)),
              let cgImage = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

/// Camera sheet that reads a partner's invite QR code.
struct ScanInviteView: View {
    var onCode: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var rejected = false

    private var scannerAvailable: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }

    var body: some View {
        NavigationStack {
            Group {
                if scannerAvailable {
                    QRScannerView { payload in
                        if let code = IdentityService.code(fromScanned: payload) {
                            onCode(code)
                            dismiss()
                        } else {
                            rejected = true
                        }
                    }
                    .ignoresSafeArea(edges: .bottom)
                    .overlay(alignment: .bottom) {
                        Text(rejected ? "That QR code isn't a Still Here invite." as LocalizedStringKey : "Point the camera at your partner's invite QR code.")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(.regularMaterial, in: Capsule())
                            .padding(.bottom, 40)
                    }
                } else {
                    ContentUnavailableView("Camera not available",
                                           systemImage: "camera.fill",
                                           description: Text("Allow camera access for Still Here in the Settings app, or type the code instead."))
                }
            }
            .navigationTitle("Scan QR code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

/// VisionKit's live scanner, limited to QR codes. Calls `onPayload` for each newly seen code.
private struct QRScannerView: UIViewControllerRepresentable {
    var onPayload: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(recognizedDataTypes: [.barcode(symbologies: [.qr])],
                                                qualityLevel: .balanced,
                                                isHighlightingEnabled: true)
        scanner.delegate = context.coordinator
        // Scanning can only start once the view is on screen.
        DispatchQueue.main.async { try? scanner.startScanning() }
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        context.coordinator.onPayload = onPayload
    }

    static func dismantleUIViewController(_ scanner: DataScannerViewController, coordinator: Coordinator) {
        scanner.stopScanning()
    }

    func makeCoordinator() -> Coordinator { Coordinator(onPayload: onPayload) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var onPayload: (String) -> Void

        init(onPayload: @escaping (String) -> Void) { self.onPayload = onPayload }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            for case .barcode(let barcode) in addedItems {
                if let payload = barcode.payloadStringValue {
                    onPayload(payload)
                    return
                }
            }
        }
    }
}
