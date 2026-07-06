import AVFoundation
import SwiftUI
import Observation

/// Thin AVFoundation capture-session wrapper: permission handling, still
/// capture, front/back switching. UI-agnostic; ScanView owns the lifecycle.
/// (Postmark: copied verbatim from Attic's proven CameraService.)
@Observable
final class CameraService {

    enum CameraError: LocalizedError {
        case permissionDenied
        case noCameraAvailable
        case configurationFailed
        case captureFailed

        var errorDescription: String? {
            switch self {
            case .permissionDenied: return "Camera access was denied. Enable it in Settings."
            case .noCameraAvailable: return "No camera is available on this device."
            case .configurationFailed: return "Could not configure the camera."
            case .captureFailed: return "Could not capture a photo."
            }
        }
    }

    let session = AVCaptureSession()
    private(set) var position: AVCaptureDevice.Position = .back
    private(set) var isConfigured = false

    private let photoOutput = AVCapturePhotoOutput()
    private var videoInput: AVCaptureDeviceInput?
    private let sessionQueue = DispatchQueue(label: "com.deitel.postmark.camera.session")
    private var inFlightProcessors: [Int64: PhotoCaptureProcessor] = [:]

    // MARK: Permission

    static var authorizationStatus: AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: .video)
    }

    /// Requests camera permission if not yet determined. Returns whether
    /// capture is authorized.
    static func requestPermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .video)
        default:
            return false
        }
    }

    // MARK: Session lifecycle

    /// Builds the session (input for `position` + photo output). Idempotent.
    func configure() throws {
        guard !isConfigured else { return }
        guard let device = Self.device(for: position) else {
            throw CameraError.noCameraAvailable
        }
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .photo

        guard let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input),
              session.canAddOutput(photoOutput)
        else {
            throw CameraError.configurationFailed
        }
        session.addInput(input)
        session.addOutput(photoOutput)
        videoInput = input
        isConfigured = true
    }

    func start() {
        sessionQueue.async { [session] in
            guard !session.isRunning else { return }
            session.startRunning()
        }
    }

    func stop() {
        sessionQueue.async { [session] in
            guard session.isRunning else { return }
            session.stopRunning()
        }
    }

    /// Flips between the back and front cameras.
    func switchCamera() throws {
        let newPosition: AVCaptureDevice.Position = position == .back ? .front : .back
        guard let device = Self.device(for: newPosition),
              let newInput = try? AVCaptureDeviceInput(device: device)
        else {
            throw CameraError.noCameraAvailable
        }
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        if let videoInput {
            session.removeInput(videoInput)
        }
        guard session.canAddInput(newInput) else {
            // Put the old input back so the session keeps working.
            if let videoInput, session.canAddInput(videoInput) {
                session.addInput(videoInput)
            }
            throw CameraError.configurationFailed
        }
        session.addInput(newInput)
        videoInput = newInput
        position = newPosition
    }

    private static func device(for position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position)
    }

    // MARK: Still capture

    /// Captures a single still photo and returns its JPEG/HEIC file data.
    func capturePhoto() async throws -> Data {
        guard isConfigured else { throw CameraError.configurationFailed }
        return try await withCheckedThrowingContinuation { continuation in
            let settings = AVCapturePhotoSettings()
            let id = settings.uniqueID
            let processor = PhotoCaptureProcessor(continuation: continuation) { [weak self] finishedID in
                self?.sessionQueue.async {
                    self?.inFlightProcessors.removeValue(forKey: finishedID)
                }
            }
            sessionQueue.async { [weak self] in
                guard let self else {
                    continuation.resume(throwing: CameraError.captureFailed)
                    return
                }
                self.inFlightProcessors[id] = processor
                self.photoOutput.capturePhoto(with: settings, delegate: processor)
            }
        }
    }
}

/// Bridges the AVCapturePhotoCaptureDelegate callback into async/await.
/// Kept alive by CameraService.inFlightProcessors until the capture finishes.
private final class PhotoCaptureProcessor: NSObject, AVCapturePhotoCaptureDelegate {
    private let continuation: CheckedContinuation<Data, Error>
    private let onFinish: (Int64) -> Void

    init(continuation: CheckedContinuation<Data, Error>, onFinish: @escaping (Int64) -> Void) {
        self.continuation = continuation
        self.onFinish = onFinish
    }

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        defer { onFinish(photo.resolvedSettings.uniqueID) }
        if let error {
            continuation.resume(throwing: error)
        } else if let data = photo.fileDataRepresentation() {
            continuation.resume(returning: data)
        } else {
            continuation.resume(throwing: CameraService.CameraError.captureFailed)
        }
    }
}

// PLACEHOLDER UI — bare AVCaptureVideoPreviewLayer host, no styling.
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}
}
