//
//  QRScannerView.swift
//  LegadoUI
//
//  The QR scanner — upstream `ui/qrcode/QrCodeActivity.kt`.
//
//  The upstream scans a QR code with the camera and hands the text back, so
//  that a book source (or a book URL) can be imported by pointing the phone
//  at a code. iOS offers the same through `AVCaptureSession`; the scanner
//  below is Apple-only and the Linux build gets a text field instead.
//

#if canImport(SwiftUI)
import SwiftUI
#else
import LegadoUIShim
#endif

import Foundation
import LegadoCore

#if canImport(AVFoundation) && canImport(UIKit)
import AVFoundation
import UIKit

/// The camera preview that scans the QR codes.
public struct QRScannerView: View {

    /// The scanned text.
    @Binding var result: String?

    /// The scanner controller.
    @State private var controller = QRScannerController()

    public init(result: Binding<String?>) {
        self._result = result
    }

    public var body: some View {
        ZStack {
            QRScannerPreview(controller: controller)
                .ignoresSafeArea()
            VStack {
                Spacer()
                Text("把二维码放进取景框")
                    .font(.system(size: 14))
                    .foregroundColor(.white)
                    .padding(8)
                    .background(Color.black.opacity(0.5))
                    .cornerRadius(8)
                    .padding(.bottom, 40)
            }
        }
        .onAppear {
            controller.onScan = { value in
                result = value
            }
            controller.start()
        }
        .onDisappear {
            controller.stop()
        }
    }
}

/// The `AVCaptureSession` wrapper.
final class QRScannerController: NSObject, AVCaptureMetadataOutputObjectsDelegate, @unchecked Sendable {

    /// The session.
    let session = AVCaptureSession()

    /// Called with the scanned text.
    var onScan: ((String) -> Void)?

    /// The queue that owns the session — `AVCaptureSession` is not `Sendable`
    /// and must only be touched from one queue.
    private let sessionQueue = DispatchQueue(label: "com.legado.qrscanner.session")
    private var configured = false

    /// Starts the session.
    func start() {
        configureIfNeeded()
        guard !session.isRunning else { return }
        sessionQueue.async { [session] in session.startRunning() }
    }

    /// Stops the session.
    func stop() {
        guard session.isRunning else { return }
        sessionQueue.async { [session] in session.stopRunning() }
    }

    private func configureIfNeeded() {
        guard !configured else { return }
        configured = true
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else { return }
        session.addInput(input)
        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else { return }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        output.metadataObjectTypes = [.qr]
    }

    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let value = object.stringValue else { return }
        stop()
        onScan?(value)
    }
}

/// The `UIViewRepresentable` of the preview.
struct QRScannerPreview: UIViewRepresentable {

    let controller: QRScannerController

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.videoPreviewLayer.session = controller.session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}

    /// The preview view.
    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var videoPreviewLayer: AVCaptureVideoPreviewLayer {
            layer as! AVCaptureVideoPreviewLayer
        }
    }
}
#else

/// The QR scanner — the Apple implementation needs the camera, so the Linux
/// build offers a text field.
public struct QRScannerView: View {

    /// The scanned text.
    @Binding var result: String?

    public init(result: Binding<String?>) {
        self._result = result
    }

    public var body: some View {
        VStack(spacing: 12) {
            Text("在此输入二维码的内容")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
            TextField("二维码内容", text: Binding(get: { result ?? "" }, set: { result = $0.isEmpty ? nil : $0 }))
                .textFieldStyle(.roundedBorder)
            Spacer()
        }
        .padding(16)
    }
}
#endif
