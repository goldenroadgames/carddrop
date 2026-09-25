import SwiftUI
import PhotosUI

/// Wraps PHPickerViewController directly (rather than SwiftUI's built-in
/// `.photosPicker` modifier) so it can be presented through our own
/// `.sheet(isPresented:)` with an explicit `.presentationDetents` — the
/// built-in modifier gives no control over sheet height. See
/// [[project_camera_library_picker_plan]] for why: pairing this with a
/// "Take a Photo" control above requires the library sheet to stop short of
/// covering the whole screen.
struct PhotoLibraryPickerView: UIViewControllerRepresentable {
    var onPick: (UIImage) -> Void
    var onCancel: () -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 1
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: PhotoLibraryPickerView
        init(_ parent: PhotoLibraryPickerView) { self.parent = parent }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            guard let provider = results.first?.itemProvider, provider.canLoadObject(ofClass: UIImage.self) else {
                parent.onCancel()
                return
            }
            provider.loadObject(ofClass: UIImage.self) { [self] object, _ in
                DispatchQueue.main.async {
                    if let image = object as? UIImage {
                        self.parent.onPick(image)
                    } else {
                        self.parent.onCancel()
                    }
                }
            }
        }
    }
}
