//
//  Media.swift
//  MeterWalk
//
//  Photo thumbnails, a full-screen photo viewer, the photo library picker
//  and the system share sheet.
//

import PhotosUI
import SwiftUI
import UIKit

/// A stored photo, or a clear placeholder when the file is missing.
struct PhotoThumb: View {
    @EnvironmentObject private var store: AppStore
    let fileName: String?
    var size: CGFloat = 56
    var cornerRadius: CGFloat = 8

    var body: some View {
        Group {
            if let image = store.photos.thumbnail(fileName, size: size) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Palette.lcd
                    Image(systemName: fileName == nil ? "camera" : "exclamationmark.triangle")
                        .font(.system(size: size * 0.3, weight: .semibold))
                        .foregroundStyle(fileName == nil ? Palette.ghost : Palette.red)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Palette.ghost, lineWidth: 1.5)
        )
        .accessibilityLabel(fileName == nil ? "No photo" : "Photo")
    }
}

/// A large photo that opens full screen when tapped.
struct PhotoPanel: View {
    @EnvironmentObject private var store: AppStore
    let fileName: String?
    var caption: String? = nil
    var height: CGFloat = 220
    @State private var viewing = false

    var body: some View {
        if let fileName {
            VStack(alignment: .leading, spacing: 8) {
                if let image = store.photos.thumbnail(fileName, size: 700) {
                    Button {
                        viewing = true
                    } label: {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(maxWidth: .infinity)
                            .frame(height: height)
                            .clipShape(RoundedRectangle(cornerRadius: Metrics.displayRadius, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: Metrics.displayRadius, style: .continuous)
                                    .strokeBorder(Palette.ghost, lineWidth: 2)
                            )
                            .overlay(alignment: .bottomTrailing) {
                                Image(systemName: "arrow.up.left.and.arrow.down.right")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(Palette.white)
                                    .padding(8)
                                    .background(Circle().fill(Palette.lcd.opacity(0.8)))
                                    .padding(8)
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Open photo")
                } else {
                    AssumptionNote(text: "The photo file is missing from this device.", symbol: "exclamationmark.triangle", color: Palette.red)
                }
                if let caption {
                    Text(caption)
                        .font(TypeScale.caption)
                        .foregroundStyle(Palette.tertiaryText)
                }
            }
            .fullScreenCover(isPresented: $viewing) {
                PhotoViewer(image: store.photos.image(fileName)) { viewing = false }
            }
        }
    }
}

struct PhotoViewer: View {
    let image: UIImage?
    let dismiss: () -> Void
    @State private var scale: CGFloat = 1

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(scale)
                    .gesture(MagnificationGesture().onChanged { scale = max(1, min(5, $0)) }.onEnded { _ in
                        withAnimation(.spring()) { if scale < 1.2 { scale = 1 } }
                    })
                    .onTapGesture(count: 2) { withAnimation(.spring()) { scale = scale > 1 ? 1 : 2.5 } }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Palette.white)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Palette.panel))
            }
            .padding()
            .accessibilityLabel("Close")
        }
    }
}

/// Picks one image from the library without needing library access.
struct PhotoLibraryPicker: UIViewControllerRepresentable {
    let onPick: (UIImage?, Date?) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 1
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let onPick: (UIImage?, Date?) -> Void
        init(onPick: @escaping (UIImage?, Date?) -> Void) { self.onPick = onPick }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            guard let provider = results.first?.itemProvider else {
                onPick(nil, nil)
                return
            }
            provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                let image = data.flatMap(UIImage.init(data:))?.normalizedUp()
                let date = data.flatMap(PhotoStore.captureDate(from:))
                DispatchQueue.main.async { self.onPick(image, date) }
            }
        }
    }
}

/// Still camera for simple photos (bills, meter faces) using the system UI.
struct SystemCameraPicker: UIViewControllerRepresentable {
    let onPick: (UIImage?) -> Void

    static var isAvailable: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onPick: (UIImage?) -> Void
        init(onPick: @escaping (UIImage?) -> Void) { self.onPick = onPick }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            onPick((info[.originalImage] as? UIImage)?.normalizedUp())
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onPick(nil)
        }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// A file ready to be shared, for `.sheet(item:)`.
struct SharedFile: Identifiable {
    let id = UUID()
    let url: URL
}
