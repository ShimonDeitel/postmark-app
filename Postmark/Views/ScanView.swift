import SwiftUI
import SwiftData
import PhotosUI

// PLACEHOLDER UI — engineering skeleton only, no visual design.
/// Home: camera preview + Scan button + raw result readout.
/// Permission is asked in context on the FIRST scan tap (Attic's lazy
/// pattern): launch never prompts; first tap requests, the live preview
/// appearing is that tap's payoff, the next tap scans.
struct ScanView: View {
    private enum Phase: Equatable {
        case idle
        case analyzing
        case revealed(StampResult)
    }

    @Environment(StoreManager.self) private var store
    @Environment(\.modelContext) private var modelContext
    @Query private var items: [StampItem]

    @State private var camera = CameraService()
    @State private var permissionGranted = false
    @State private var cameraSetupFailed = false

    @State private var phase: Phase = .idle
    @State private var errorMessage: String?
    @State private var showPaywall = false
    @State private var pickerItem: PhotosPickerItem?
    @State private var lastSavedItem: StampItem?

    var body: some View {
        VStack(spacing: 16) {
            viewport
                .frame(height: 320)
                .clipShape(RoundedRectangle(cornerRadius: 12))

            statusLine

            resultReadout

            controls
        }
        .padding()
        .navigationTitle("Postmark")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink("Album (\(items.count))") {
                    AlbumView()
                }
            }
        }
        .task { await setUpCamera() }
        .onDisappear { camera.stop() }
        .onChange(of: pickerItem) { _, newValue in
            guard let newValue else { return }
            pickerItem = nil
            handlePickedItem(newValue)
        }
        .sheet(isPresented: $showPaywall) { PaywallView() }
    }

    // MARK: Viewport (PLACEHOLDER UI)

    @ViewBuilder
    private var viewport: some View {
        if permissionGranted && camera.isConfigured {
            CameraPreview(session: camera.session)
        } else {
            ZStack {
                Rectangle().fill(.secondary.opacity(0.2))
                Text(emptyViewportText)
                    .multilineTextAlignment(.center)
                    .padding()
            }
        }
    }

    private var emptyViewportText: String {
        if cameraSetupFailed {
            return "No camera here.\nPick a photo below instead."
        }
        if !permissionGranted && CameraService.authorizationStatus == .denied {
            return "Camera access is off.\nEnable it in Settings, or pick a photo."
        }
        return "Point at a stamp.\nTap Scan to start."
    }

    // MARK: Status line (PLACEHOLDER UI)

    @ViewBuilder
    private var statusLine: some View {
        switch phase {
        case .analyzing:
            ProgressView("Identifying…")
        default:
            if store.isPro {
                Text("Postmark Pro")
            } else {
                Text("\(store.freeScansRemaining) free identifications left")
            }
        }
    }

    // MARK: Raw result readout (PLACEHOLDER UI)

    @ViewBuilder
    private var resultReadout: some View {
        if case .revealed(let result) = phase {
            VStack(alignment: .leading, spacing: 4) {
                Text("country: \(result.country)")
                Text("issue: \(result.issue)")
                Text("year: \(String(result.year))")
                Text("denomination: \(result.denomination)")
                Text("variety: \(result.variety)")
                Text("used: $\(Int(result.valueLowUsed))-$\(Int(result.valueHighUsed))")
                Text("mint: $\(Int(result.valueLowMint))-$\(Int(result.valueHighMint))")
                Text("confidence: \(result.confidence, format: .percent.precision(.fractionLength(0)))")
                Text("search_term: \(result.searchTerm)")
                if let item = lastSavedItem {
                    NavigationLink("Open saved stamp") {
                        StampDetailView(item: item)
                    }
                }
            }
            .font(.footnote.monospaced())
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Controls (PLACEHOLDER UI)

    private var controls: some View {
        HStack(spacing: 24) {
            PhotosPicker(selection: $pickerItem, matching: .images) {
                Label("Photos", systemImage: "photo.on.rectangle.angled")
            }
            .disabled(isBusy)

            Button(action: scanTapped) {
                if isBusy {
                    ProgressView()
                } else {
                    Label("Scan", systemImage: "camera.viewfinder")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isBusy)

            Button {
                do { try camera.switchCamera() } catch { errorMessage = error.localizedDescription }
            } label: {
                Label("Flip", systemImage: "arrow.triangle.2.circlepath.camera")
            }
            .disabled(isBusy || !camera.isConfigured)
        }
        .overlay(alignment: .bottom) {
            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .offset(y: 28)
                    .onTapGesture { self.errorMessage = nil }
            }
        }
    }

    private var isBusy: Bool { phase == .analyzing }

    // MARK: Camera lifecycle

    /// Never prompts at launch: the permission ask happens in context, on the
    /// first scan tap. Here we only wire up a camera we're already allowed.
    private func setUpCamera() async {
        guard CameraService.authorizationStatus == .authorized else { return }
        permissionGranted = true
        startCameraSession()
    }

    private func startCameraSession() {
        do {
            try camera.configure()
            camera.start()
        } catch {
            cameraSetupFailed = true
        }
    }

    // MARK: Scan flow

    private func scanTapped() {
        guard store.canScan else {
            showPaywall = true
            return
        }
        // First tap asks for the camera in context; the live preview
        // appearing is that tap's payoff, the next tap scans.
        guard permissionGranted else {
            Task {
                permissionGranted = await CameraService.requestPermission()
                if permissionGranted {
                    startCameraSession()
                } else {
                    errorMessage = "Camera access is off. Pick a photo instead."
                }
            }
            return
        }
        guard camera.isConfigured else {
            errorMessage = "No camera here. Pick a photo instead."
            return
        }
        Task {
            do {
                let photoData = try await camera.capturePhoto()
                await identify(photoData: photoData)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func handlePickedItem(_ item: PhotosPickerItem) {
        guard store.canScan else {
            showPaywall = true
            return
        }
        Task {
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    errorMessage = "Could not read that photo."
                    return
                }
                await identify(photoData: data)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    @MainActor
    private func identify(photoData: Data) async {
        errorMessage = nil
        phase = .analyzing

        guard let api = PostmarkAPI.makeDefault() else {
            phase = .idle
            errorMessage = PostmarkAPI.APIError.notConfigured.localizedDescription
            return
        }
        do {
            let result = try await api.identify(images: [photoData])
            let item = StampItem(result: result, photoData: photoData)
            modelContext.insert(item)
            lastSavedItem = item
            store.recordScan()
            phase = .revealed(result)
            if !store.isPro && store.freeScansRemaining == 0 {
                showPaywall = true
            }
        } catch {
            phase = .idle
            errorMessage = error.localizedDescription
        }
    }
}
