import SwiftUI
import SwiftData
import PhotosUI

/// Home: the examining desk. A perforated stamp mount is the camera
/// viewport; a perforation-gauge ruler sweeps the photo while the
/// identification runs, and the result arrives as a mounted stamp that gets
/// cancelled with a red date stamp.
struct ScanView: View {
    private enum Phase: Equatable {
        case idle
        case analyzing(UIImage)
        case revealed(StampResult)
    }

    @Environment(StoreManager.self) private var store
    @Environment(\.modelContext) private var modelContext
    @Query private var items: [StampItem]

    @State private var camera = CameraService()
    @State private var permissionGranted = false
    @State private var cameraSetupFailed = false

    @State private var phase: Phase = .idle
    @State private var captionIndex = 0
    @State private var errorMessage: String?
    @State private var showPaywall = false
    @State private var pickerItem: PhotosPickerItem?
    @State private var detailItem: StampItem?
    @State private var lastSavedItem: StampItem?
    @State private var lastPhoto: UIImage?

    private static let captions = [
        "Measuring perforations…",
        "Reading the engraving…",
        "Checking watermarks…",
        "Comparing catalog plates…",
        "Pricing used and mint…",
    ]

    var body: some View {
        ZStack {
            BaizeBackdrop()

            VStack(spacing: 0) {
                header
                Spacer(minLength: 10)
                mount
                statusLine
                    .padding(.top, 24)
                Spacer(minLength: 10)
                controls
                    .padding(.bottom, 16)
            }
            .padding(.horizontal, 22)
        }
        .overlay { revealOverlay }
        .overlay(alignment: .bottom) { errorToast }
        .task { await setUpCameraIfAuthorized() }
        .onDisappear { camera.stop() }
        .onChange(of: pickerItem) { _, newValue in
            guard let newValue else { return }
            pickerItem = nil
            handlePickedItem(newValue)
        }
        .sheet(isPresented: $showPaywall) { PaywallView() }
        .navigationDestination(item: $detailItem) { item in
            StampDetailView(item: item)
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("POSTMARK")
                    .font(PostmarkTheme.heading(32, weight: .bold))
                    .tracking(4)
                    .foregroundStyle(PostmarkTheme.cream)
                Text("every stamp has a price.")
                    .font(PostmarkTheme.catalog(12))
                    .foregroundStyle(PostmarkTheme.cream.opacity(0.55))
            }
            Spacer()
            NavigationLink {
                AlbumView()
            } label: {
                ZStack(alignment: .topTrailing) {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(PostmarkTheme.gilt, lineWidth: 1.5)
                        .frame(width: 48, height: 48)
                        .overlay(
                            Image(systemName: "book.closed")
                                .font(.system(size: 19))
                                .foregroundStyle(PostmarkTheme.gilt)
                        )
                    if !items.isEmpty {
                        Text("\(items.count)")
                            .font(PostmarkTheme.catalog(11, weight: .bold))
                            .foregroundStyle(PostmarkTheme.cream)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(PostmarkTheme.red))
                            .offset(x: 7, y: -6)
                    }
                }
            }
            .buttonStyle(PressStyle())
            .accessibilityLabel("Your album, \(items.count) stamps")
        }
        .padding(.top, 8)
    }

    // MARK: Mount viewport

    private var mount: some View {
        ZStack {
            viewportContent
                .frame(maxWidth: 370)
                .aspectRatio(0.86, contentMode: .fit)
                .padding(13)
                .stampMount()
                .shadow(color: PostmarkTheme.baizeDeep.opacity(0.8), radius: 20, y: 10)
        }
    }

    @ViewBuilder
    private var viewportContent: some View {
        switch phase {
        case .analyzing(let image):
            ZStack {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                GaugeSweepView()
            }
            .clipShape(RoundedRectangle(cornerRadius: 4))
        case .idle, .revealed:
            if permissionGranted && camera.isConfigured {
                CameraPreview(session: camera.session)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            } else {
                idleMount
            }
        }
    }

    private var idleMount: some View {
        ZStack {
            Rectangle()
                .fill(PostmarkTheme.creamDeep.opacity(0.55))
            VStack(spacing: 12) {
                Image(systemName: "seal")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(PostmarkTheme.red.opacity(0.75))
                Text(idleText)
                    .font(PostmarkTheme.catalog(12))
                    .foregroundStyle(PostmarkTheme.ink.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 30)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private var idleText: String {
        if cameraSetupFailed {
            return "NO CAMERA HERE.\nPICK A PHOTO BELOW."
        }
        if !permissionGranted && CameraService.authorizationStatus == .denied {
            return "CAMERA ACCESS OFF.\nSETTINGS, OR A PHOTO BELOW."
        }
        return "LAY THE STAMP FLAT.\nFILL THE FRAME."
    }

    // MARK: Status line

    @ViewBuilder
    private var statusLine: some View {
        switch phase {
        case .analyzing:
            Text(Self.captions[captionIndex % Self.captions.count])
                .font(PostmarkTheme.catalog(13))
                .foregroundStyle(PostmarkTheme.lamp.opacity(0.9))
                .id(captionIndex)
        default:
            Text(freeLooksText)
                .font(PostmarkTheme.catalog(11, weight: .semibold))
                .tracking(1.5)
                .foregroundStyle(PostmarkTheme.gilt)
                .padding(.vertical, 7)
                .padding(.horizontal, 16)
                .background(
                    Capsule().strokeBorder(PostmarkTheme.gilt.opacity(0.55), lineWidth: 1)
                )
        }
    }

    private var freeLooksText: String {
        if store.isPro { return "PRO · EVERY PAGE OPEN" }
        let n = store.freeScansRemaining
        return n == 1 ? "1 FREE LOOK LEFT" : "\(n) FREE LOOKS LEFT"
    }

    // MARK: Controls

    private var controls: some View {
        HStack {
            PhotosPicker(selection: $pickerItem, matching: .images) {
                controlIcon("photo.on.rectangle.angled", label: "Photos")
            }
            .disabled(isBusy)

            Spacer()

            Button(action: scanTapped) {
                ZStack {
                    Circle()
                        .fill(PostmarkTheme.red)
                        .frame(width: 80, height: 80)
                        .shadow(color: PostmarkTheme.red.opacity(0.4), radius: 14, y: 6)
                    Circle()
                        .strokeBorder(PostmarkTheme.cream.opacity(0.55), lineWidth: 1.5)
                        .frame(width: 64, height: 64)
                    if isBusy {
                        ProgressView().tint(PostmarkTheme.cream)
                    } else {
                        Image(systemName: "seal.fill")
                            .font(.system(size: 26))
                            .foregroundStyle(PostmarkTheme.cream)
                    }
                }
            }
            .buttonStyle(PressStyle())
            .disabled(isBusy)
            .accessibilityLabel("Scan stamp")

            Spacer()

            Button {
                PostmarkHaptics.tap()
                do { try camera.switchCamera() } catch { errorMessage = error.localizedDescription }
            } label: {
                controlIcon("arrow.triangle.2.circlepath.camera", label: "Flip")
            }
            .disabled(isBusy || !camera.isConfigured)
        }
        .padding(.horizontal, 12)
    }

    private func controlIcon(_ systemName: String, label: String) -> some View {
        VStack(spacing: 5) {
            Image(systemName: systemName)
                .font(.system(size: 21))
            Text(label)
                .font(PostmarkTheme.catalog(10))
        }
        .foregroundStyle(PostmarkTheme.cream.opacity(0.6))
        .frame(width: 58)
    }

    private var isBusy: Bool {
        if case .analyzing = phase { return true }
        return false
    }

    // MARK: Reveal overlay

    @ViewBuilder
    private var revealOverlay: some View {
        if case .revealed(let result) = phase {
            ZStack {
                PostmarkTheme.baizeDeep.opacity(0.78)
                    .ignoresSafeArea()
                StampRevealView(
                    result: result,
                    photo: lastPhoto,
                    onAlbum: {
                        phase = .idle
                        detailItem = lastSavedItem
                    },
                    onNext: {
                        phase = .idle
                        if !store.isPro && store.freeScansRemaining == 0 {
                            showPaywall = true
                        }
                    }
                )
                .padding(.horizontal, 22)
            }
            .transition(.opacity)
        }
    }

    // MARK: Error toast

    @ViewBuilder
    private var errorToast: some View {
        if let errorMessage {
            Text(errorMessage)
                .font(PostmarkTheme.text(13, weight: .medium))
                .foregroundStyle(PostmarkTheme.ink)
                .padding(.vertical, 10)
                .padding(.horizontal, 16)
                .background(RoundedRectangle(cornerRadius: 10).fill(PostmarkTheme.cream))
                .padding(.horizontal, 28)
                .padding(.bottom, 114)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .onTapGesture { self.errorMessage = nil }
                .task {
                    try? await Task.sleep(for: .seconds(5))
                    withAnimation { self.errorMessage = nil }
                }
        }
    }

    // MARK: Camera lifecycle (never prompts at launch)

    private func setUpCameraIfAuthorized() async {
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
            PostmarkHaptics.warning()
            showPaywall = true
            return
        }
        guard permissionGranted else {
            Task {
                permissionGranted = await CameraService.requestPermission()
                if permissionGranted {
                    startCameraSession()
                } else {
                    withAnimation {
                        errorMessage = "Camera access is off. Pick a photo below instead."
                    }
                }
            }
            return
        }
        guard camera.isConfigured else {
            errorMessage = "No camera here. Pick a photo below instead."
            return
        }
        PostmarkHaptics.tap()
        Task {
            do {
                let photoData = try await camera.capturePhoto()
                await identify(photoData: photoData)
            } catch {
                withAnimation { errorMessage = error.localizedDescription }
            }
        }
    }

    private func handlePickedItem(_ item: PhotosPickerItem) {
        guard store.canScan else {
            PostmarkHaptics.warning()
            showPaywall = true
            return
        }
        Task {
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    withAnimation { errorMessage = "Could not read that photo." }
                    return
                }
                await identify(photoData: data)
            } catch {
                withAnimation { errorMessage = error.localizedDescription }
            }
        }
    }

    @MainActor
    private func identify(photoData: Data) async {
        guard let uiImage = UIImage(data: photoData) else {
            withAnimation { errorMessage = "Could not read that photo." }
            return
        }
        lastPhoto = uiImage
        withAnimation { phase = .analyzing(uiImage) }
        captionIndex = 0
        let captionTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1.7))
                guard !Task.isCancelled else { break }
                withAnimation(.easeInOut(duration: 0.35)) { captionIndex += 1 }
            }
        }
        defer { captionTask.cancel() }

        guard let api = PostmarkAPI.makeDefault() else {
            withAnimation {
                phase = .idle
                errorMessage = PostmarkAPI.APIError.notConfigured.localizedDescription
            }
            return
        }
        do {
            let result = try await api.identify(images: [photoData])
            let item = StampItem(result: result, photoData: photoData)
            modelContext.insert(item)
            lastSavedItem = item
            store.recordScan()
            withAnimation(.easeOut(duration: 0.25)) { phase = .revealed(result) }
        } catch {
            PostmarkHaptics.warning()
            withAnimation {
                phase = .idle
                errorMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - Reveal card

/// The identified stamp, mounted on cream with perforated edges, then
/// cancelled with the red date stamp (thunk haptic).
struct StampRevealView: View {
    let result: StampResult
    let photo: UIImage?
    var onAlbum: () -> Void
    var onNext: () -> Void

    @State private var mounted = false
    @State private var cancelled = false

    var body: some View {
        VStack(spacing: 22) {
            card
                .scaleEffect(mounted ? 1 : 0.86)
                .opacity(mounted ? 1 : 0)

            HStack(spacing: 14) {
                Button(action: onAlbum) {
                    Text("In the Album")
                        .font(PostmarkTheme.text(16, weight: .semibold))
                        .foregroundStyle(PostmarkTheme.cream)
                        .padding(.vertical, 13)
                        .padding(.horizontal, 20)
                        .background(Capsule().strokeBorder(PostmarkTheme.gilt, lineWidth: 1.5))
                }
                Button {
                    PostmarkHaptics.tap()
                    onNext()
                } label: {
                    Text("Scan next")
                        .font(PostmarkTheme.text(16, weight: .bold))
                        .foregroundStyle(PostmarkTheme.cream)
                        .padding(.vertical, 13)
                        .padding(.horizontal, 26)
                        .background(Capsule().fill(PostmarkTheme.red))
                }
                .buttonStyle(PressStyle())
            }
            .opacity(cancelled ? 1 : 0)
        }
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.75).delay(0.05)) {
                mounted = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.5)) {
                    cancelled = true
                }
                PostmarkHaptics.cancel()
            }
        }
    }

    private var card: some View {
        VStack(spacing: 14) {
            if let photo {
                Image(uiImage: photo)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 190)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }

            VStack(spacing: 5) {
                Text(headline)
                    .font(PostmarkTheme.heading(21, weight: .bold))
                    .foregroundStyle(PostmarkTheme.ink)
                    .multilineTextAlignment(.center)
                if !result.variety.isEmpty {
                    Text(result.variety)
                        .font(PostmarkTheme.catalog(12))
                        .foregroundStyle(PostmarkTheme.inkSoft)
                }
            }

            valueTable

            VStack(spacing: 3) {
                Text("CONFIDENCE \(confidenceLabel)")
                    .font(PostmarkTheme.catalog(10, weight: .semibold))
                    .tracking(1.5)
                Text("An estimate, not an appraisal.")
                    .font(PostmarkTheme.text(11).italic())
            }
            .foregroundStyle(PostmarkTheme.inkSoft)
        }
        .padding(20)
        .frame(maxWidth: 340)
        .stampMount()
        .overlay(alignment: .topTrailing) {
            if cancelled {
                CancellationMark()
                    .rotationEffect(.degrees(-12))
                    .scaleEffect(cancelled ? 1 : 1.7)
                    .offset(x: 26, y: -26)
                    .transition(.scale(scale: 1.7).combined(with: .opacity))
            }
        }
        .shadow(color: PostmarkTheme.baizeDeep.opacity(0.9), radius: 26, y: 12)
    }

    private var headline: String {
        var parts: [String] = []
        if result.year > 0 { parts.append(String(result.year)) }
        if !result.country.isEmpty { parts.append(result.country) }
        if !result.denomination.isEmpty { parts.append(result.denomination) }
        if !result.issue.isEmpty { parts.append(result.issue) }
        return parts.isEmpty ? "Unidentified stamp" : parts.joined(separator: " ")
    }

    private var valueTable: some View {
        HStack(spacing: 0) {
            valueColumn("USED", low: result.valueLowUsed, high: result.valueHighUsed)
            Rectangle()
                .fill(PostmarkTheme.inkSoft.opacity(0.3))
                .frame(width: 1)
            valueColumn("MINT", low: result.valueLowMint, high: result.valueHighMint)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(PostmarkTheme.inkSoft.opacity(0.35), lineWidth: 1)
        )
    }

    private func valueColumn(_ label: String, low: Double, high: Double) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(PostmarkTheme.catalog(10, weight: .bold))
                .tracking(2)
                .foregroundStyle(PostmarkTheme.inkSoft)
            Text(rangeText(low: low, high: high))
                .font(PostmarkTheme.heading(19, weight: .bold))
                .foregroundStyle(PostmarkTheme.red)
        }
        .frame(maxWidth: .infinity)
    }

    private func rangeText(low: Double, high: Double) -> String {
        guard high > 0 else { return "—" }
        let l = low.formatted(.currency(code: "USD").precision(.fractionLength(0)))
        let h = high.formatted(.currency(code: "USD").precision(.fractionLength(0)))
        return "\(l)-\(h)"
    }

    private var confidenceLabel: String {
        switch result.confidence {
        case 0.7...: return "HIGH"
        case 0.4..<0.7: return "FAIR"
        default: return "LOW"
        }
    }
}
