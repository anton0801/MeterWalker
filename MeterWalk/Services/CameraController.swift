//
//  CameraController.swift
//  MeterWalk
//
//  A still camera for photographing the meter, with the torch for dark
//  cupboards. Everything stays on the device.
//

import AVFoundation
import SwiftUI
import UIKit

final class CameraController: NSObject, ObservableObject {
    enum Status: Equatable {
        case idle
        case running
        case denied
        case unavailable
        case failed(String)
    }

    @Published private(set) var status: Status = .idle
    @Published private(set) var torchOn = false
    @Published private(set) var isCapturing = false

    let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()
    private let queue = DispatchQueue(label: "app.meterwalk.camera")
    private var device: AVCaptureDevice?
    private var configured = false
    private var completion: ((UIImage?) -> Void)?

    var hasTorch: Bool { device?.hasTorch ?? false }

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureAndRun()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    if granted {
                        self?.configureAndRun()
                    } else {
                        self?.status = .denied
                    }
                }
            }
        case .denied, .restricted:
            status = .denied
        @unknown default:
            status = .denied
        }
    }

    func stop() {
        queue.async { [session] in
            if session.isRunning { session.stopRunning() }
        }
        DispatchQueue.main.async { self.torchOn = false }
    }

    private func configureAndRun() {
        queue.async { [weak self] in
            guard let self else { return }
            if !self.configured {
                guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                      let input = try? AVCaptureDeviceInput(device: device) else {
                    DispatchQueue.main.async { self.status = .unavailable }
                    return
                }
                self.session.beginConfiguration()
                self.session.sessionPreset = .photo
                guard self.session.canAddInput(input), self.session.canAddOutput(self.output) else {
                    self.session.commitConfiguration()
                    DispatchQueue.main.async { self.status = .failed("The camera could not be set up.") }
                    return
                }
                self.session.addInput(input)
                self.session.addOutput(self.output)
                self.session.commitConfiguration()
                self.device = device
                self.configured = true

                if (try? device.lockForConfiguration()) != nil {
                    if device.isFocusModeSupported(.continuousAutoFocus) {
                        device.focusMode = .continuousAutoFocus
                    }
                    if device.isAutoFocusRangeRestrictionSupported {
                        device.autoFocusRangeRestriction = .near
                    }
                    device.unlockForConfiguration()
                }
            }
            if !self.session.isRunning { self.session.startRunning() }
            DispatchQueue.main.async { self.status = .running }
        }
    }

    func toggleTorch() {
        guard let device, device.hasTorch else { return }
        let newValue = !torchOn
        queue.async {
            guard (try? device.lockForConfiguration()) != nil else { return }
            device.torchMode = newValue ? .on : .off
            device.unlockForConfiguration()
            DispatchQueue.main.async { self.torchOn = newValue }
        }
    }

    func capture(completion: @escaping (UIImage?) -> Void) {
        guard status == .running, !isCapturing else {
            completion(nil)
            return
        }
        isCapturing = true
        self.completion = completion
        queue.async { [weak self] in
            guard let self else { return }
            let settings = AVCapturePhotoSettings()
            if self.output.supportedFlashModes.contains(.off) {
                settings.flashMode = .off
            }
            self.output.capturePhoto(with: settings, delegate: self)
        }
    }
}

extension CameraController: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let image = photo.fileDataRepresentation().flatMap(UIImage.init(data:))?.normalizedUp()
        DispatchQueue.main.async {
            self.isCapturing = false
            self.completion?(image)
            self.completion = nil
        }
    }
}

/// Live camera preview, filled to the view's bounds.
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        view.backgroundColor = .black
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}

enum FrameCropper {
    /// Maps the on-screen framing box onto the captured photo, for a preview
    /// that fills its view (aspect fill), and pads it a little.
    static func crop(_ image: UIImage, previewSize: CGSize, frame: CGRect, padding: CGFloat = 0.12) -> UIImage? {
        let size = image.size
        guard size.width > 0, size.height > 0, previewSize.width > 0, previewSize.height > 0 else { return nil }
        let scale = max(previewSize.width / size.width, previewSize.height / size.height)
        let offsetX = (size.width * scale - previewSize.width) / 2
        let offsetY = (size.height * scale - previewSize.height) / 2
        let padded = frame.insetBy(dx: -frame.width * padding, dy: -frame.height * padding * 1.5)
        let rect = CGRect(
            x: (padded.minX + offsetX) / scale,
            y: (padded.minY + offsetY) / scale,
            width: padded.width / scale,
            height: padded.height / scale
        )
        return image.cropped(to: rect)
    }
}
