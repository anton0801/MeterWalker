//
//  CameraCaptureView.swift
//  MeterWalk
//
//  Live camera with a frame to line the number window up in. The shot is
//  cropped to the frame and read on the device.
//

import SwiftUI

struct CameraCaptureView: View {
    let meter: MeterItem
    let register: Register
    let onClose: () -> Void
    let onCaptured: (ScanFlowView.Capture) -> Void

    @StateObject private var camera = CameraController()
    @State private var reading = false
    @State private var showingLibrary = false
    /// Full-screen preview size and the frame in full-screen coordinates,
    /// kept for cropping the photo to what was inside the frame.
    @State private var previewSize: CGSize = .zero
    @State private var frameOnScreen: CGRect = .zero
    @Environment(\.openURL) private var openURL

    var body: some View {
        GeometryReader { proxy in
            let insets = proxy.safeAreaInsets
            let full = CGSize(width: proxy.size.width + insets.leading + insets.trailing,
                              height: proxy.size.height + insets.top + insets.bottom)
            let frame = frameRect(in: proxy.size).offsetBy(dx: insets.leading, dy: insets.top)

            ZStack {
                Color.black.ignoresSafeArea()

                if camera.status == .running {
                    Group {
                        CameraPreview(session: camera.session)
                        FrameMask(frame: frame)
                            .fill(Color.black.opacity(0.55), style: FillStyle(eoFill: true))
                            .allowsHitTesting(false)
                        FrameCorners(frame: frame)
                            .stroke(Palette.yellow, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                            .allowsHitTesting(false)
                    }
                    .ignoresSafeArea()
                } else {
                    unavailableContent
                        .padding(.horizontal, Metrics.gutter)
                }

                VStack(spacing: 0) {
                    topBar
                    if camera.status == .running {
                        guidance
                            .padding(.top, max(12, frame.minY - insets.top - 120))
                    }
                    Spacer()
                    bottomBar
                }
                .padding(.horizontal, Metrics.gutter)

                if reading {
                    readingOverlay
                }
            }
            .onAppear {
                previewSize = full
                frameOnScreen = frame
            }
            .onChange(of: proxy.size) { _ in
                previewSize = full
                frameOnScreen = frame
            }
        }
        .onAppear { camera.start() }
        .onDisappear { camera.stop() }
        .statusBarHidden()
        .sheet(isPresented: $showingLibrary) {
            PhotoLibraryPicker { image, date in
                showingLibrary = false
                guard let image else { return }
                recognize(photo: image, crop: nil, photoDate: date)
            }
            .ignoresSafeArea()
        }
    }

    /// The framing box inside the safe area.
    private func frameRect(in size: CGSize) -> CGRect {
        let width = min(size.width - 40, 420)
        let height = width * 0.36
        return CGRect(x: (size.width - width) / 2, y: size.height * 0.4 - height / 2, width: width, height: height)
    }

    // MARK: Pieces

    private var topBar: some View {
        HStack {
            IconButton(symbol: "xmark", label: "Close", action: onClose)
            Spacer()
            VStack(spacing: 2) {
                Text(meter.name)
                    .font(TypeScale.bodyEmphasis)
                    .foregroundStyle(Palette.white)
                if register != .total {
                    Text("\(register.title) register \(register.meterLabel)")
                        .font(TypeScale.captionEmphasis)
                        .foregroundStyle(Palette.utility(meter.utility))
                }
            }
            Spacer()
            if camera.status == .running && camera.hasTorch {
                IconButton(
                    symbol: camera.torchOn ? "flashlight.on.fill" : "flashlight.off.fill",
                    label: camera.torchOn ? "Turn torch off" : "Turn torch on",
                    color: camera.torchOn ? Palette.yellow : Palette.white
                ) { camera.toggleTorch() }
            } else {
                Color.clear.frame(width: 40, height: 40)
            }
        }
        .padding(.top, 8)
    }

    private var guidance: some View {
        VStack(spacing: 6) {
            Text("Fit the numbers inside the frame")
                .font(TypeScale.bodyEmphasis)
                .foregroundStyle(Palette.white)
            HStack(spacing: 6) {
                Text("This dial:")
                    .font(TypeScale.caption)
                    .foregroundStyle(Palette.secondaryText)
                Text(meter.ghostText)
                    .font(TypeScale.mono(13))
                    .foregroundStyle(Palette.yellow)
                Text("\(meter.digitsBeforeDecimal) + \(meter.digitsAfterDecimal) digits")
                    .font(TypeScale.caption)
                    .foregroundStyle(Palette.secondaryText)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Palette.lcd.opacity(0.75)))
        .accessibilityElement(children: .combine)
    }

    private var bottomBar: some View {
        HStack(alignment: .center) {
            sideButton(symbol: "photo.on.rectangle", title: "Photo", accessibility: "Choose a photo") {
                showingLibrary = true
            }
            Spacer()
            if camera.status == .running {
                Button(action: shoot) {
                    ZStack {
                        Circle().strokeBorder(Palette.white, lineWidth: 4).frame(width: 78, height: 78)
                        Circle().fill(Palette.yellow).frame(width: 64, height: 64)
                    }
                }
                .buttonStyle(.plain)
                .disabled(camera.isCapturing || reading)
                .accessibilityLabel("Take photo")
            }
            Spacer()
            sideButton(symbol: "keyboard", title: "Type", accessibility: "Type the number without a photo") {
                onCaptured(.init(meterID: meter.id, register: register, photo: nil, photoDate: nil, recognized: nil, recognitionFailed: false))
            }
        }
        .padding(.bottom, 20)
    }

    private func sideButton(symbol: String, title: String, accessibility: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 20, weight: .semibold))
                    .frame(width: 52, height: 52)
                    .background(Circle().fill(Palette.panel.opacity(0.9)))
                    .overlay(Circle().strokeBorder(Palette.ghost, lineWidth: 2))
                Text(title)
                    .font(TypeScale.captionEmphasis)
            }
            .foregroundStyle(Palette.white)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibility)
    }

    @ViewBuilder
    private var unavailableContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Spacer()
            switch camera.status {
            case .denied:
                EmptyStatePanel(
                    symbol: "camera.fill",
                    title: "Camera access is off",
                    message: "Allow the camera in Settings to photograph the meter. You can also choose a photo you already took, or type the number.",
                    actionTitle: "Open Settings"
                ) {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
            case .unavailable, .failed:
                EmptyStatePanel(
                    symbol: "camera.fill",
                    title: "No camera here",
                    message: "This device has no camera Meter Walk can use. Choose a photo of the meter, or type the number."
                )
            case .idle, .running:
                ProgressView().tint(Palette.yellow).frame(maxWidth: .infinity)
            }
            Spacer()
            Spacer()
        }
    }

    private var readingOverlay: some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()
            VStack(spacing: 14) {
                LCDReadout(text: meter.dialText(0), size: 32, color: Palette.ghost, rollFromZero: false)
                ProgressView().tint(Palette.yellow)
                Text("Reading the dial on this iPhone…")
                    .font(TypeScale.bodyEmphasis)
                    .foregroundStyle(Palette.white)
            }
            .padding(24)
            .background(RoundedRectangle(cornerRadius: Metrics.panelRadius).fill(Palette.panel))
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Actions

    private func shoot() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        let size = previewSize
        let frame = frameOnScreen
        camera.capture { image in
            guard let image else { return }
            let crop = FrameCropper.crop(image, previewSize: size, frame: frame)
            recognize(photo: image, crop: crop, photoDate: Date())
        }
    }

    private func recognize(photo: UIImage, crop: UIImage?, photoDate: Date?) {
        reading = true
        DigitRecognizer.recognize(
            image: crop ?? photo,
            digitsBefore: meter.digitsBeforeDecimal,
            digitsAfter: meter.digitsAfterDecimal
        ) { result in
            reading = false
            onCaptured(.init(
                meterID: meter.id,
                register: register,
                photo: photo,
                photoDate: photoDate,
                recognized: result,
                recognitionFailed: result == nil
            ))
        }
    }
}

/// Everything except the frame, for dimming around it.
private struct FrameMask: Shape {
    let frame: CGRect

    func path(in rect: CGRect) -> Path {
        var path = Path(rect.insetBy(dx: -50, dy: -50))
        path.addRoundedRect(in: frame, cornerSize: CGSize(width: 10, height: 10))
        return path
    }
}

/// Four corner brackets around the frame.
private struct FrameCorners: Shape {
    let frame: CGRect

    func path(in rect: CGRect) -> Path {
        let f = frame
        let arm = min(28, f.height * 0.35)
        var path = Path()
        path.move(to: CGPoint(x: f.minX, y: f.minY + arm))
        path.addLine(to: CGPoint(x: f.minX, y: f.minY))
        path.addLine(to: CGPoint(x: f.minX + arm, y: f.minY))
        path.move(to: CGPoint(x: f.maxX - arm, y: f.minY))
        path.addLine(to: CGPoint(x: f.maxX, y: f.minY))
        path.addLine(to: CGPoint(x: f.maxX, y: f.minY + arm))
        path.move(to: CGPoint(x: f.maxX, y: f.maxY - arm))
        path.addLine(to: CGPoint(x: f.maxX, y: f.maxY))
        path.addLine(to: CGPoint(x: f.maxX - arm, y: f.maxY))
        path.move(to: CGPoint(x: f.minX + arm, y: f.maxY))
        path.addLine(to: CGPoint(x: f.minX, y: f.maxY))
        path.addLine(to: CGPoint(x: f.minX, y: f.maxY - arm))
        return path
    }
}
