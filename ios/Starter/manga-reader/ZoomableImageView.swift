import SwiftUI
import UIKit

private final class LayoutAwareScrollView: UIScrollView {
    var onLayout: (() -> Void)?

    override func layoutSubviews() {
        super.layoutSubviews()
        onLayout?()
    }
}

struct ZoomableImageView: UIViewRepresentable {
    let image: UIImage
    let mode: ReaderZoomMode

    func makeCoordinator() -> Coordinator {
        Coordinator(mode: mode)
    }

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = LayoutAwareScrollView()
        scrollView.delegate = context.coordinator
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.bouncesZoom = true
        scrollView.bounces = false
        scrollView.decelerationRate = .fast
        scrollView.onLayout = { [weak coordinator = context.coordinator] in
            coordinator?.updateLayoutIfNeeded()
        }

        let imageView = context.coordinator.imageView
        imageView.contentMode = .scaleAspectFit
        imageView.image = image
        scrollView.addSubview(imageView)

        context.coordinator.attach(scrollView: scrollView)
        DispatchQueue.main.async {
            context.coordinator.updateLayoutIfNeeded()
        }
        return scrollView
    }

    func updateUIView(_ uiView: UIScrollView, context: Context) {
        context.coordinator.mode = mode
        context.coordinator.imageView.image = image
        context.coordinator.updateLayoutIfNeeded()
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        fileprivate let imageView = UIImageView()
        fileprivate weak var scrollView: UIScrollView?
        fileprivate var mode: ReaderZoomMode

        private var hasAppliedInitialZoom = false
        private var lastBoundsSize: CGSize = .zero
        private var lastImageIdentity: ObjectIdentifier?
        private var lastMode: ReaderZoomMode?

        init(mode: ReaderZoomMode) {
            self.mode = mode
        }

        func attach(scrollView: UIScrollView) {
            self.scrollView = scrollView
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            imageView
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            centerImageIfNeeded()
        }

        func updateLayoutIfNeeded() {
            guard let scrollView, let image = imageView.image else { return }
            guard scrollView.bounds.width > 0, scrollView.bounds.height > 0 else { return }

            let boundsSize = scrollView.bounds.size
            let imageSize = image.size
            let imageIdentity = ObjectIdentifier(image)
            let imageChanged = imageIdentity != lastImageIdentity
            let modeChanged = mode != lastMode
            let boundsChanged = abs(boundsSize.width - lastBoundsSize.width) > 0.5 || abs(boundsSize.height - lastBoundsSize.height) > 0.5
            let needsReset = imageChanged || modeChanged || boundsChanged || !hasAppliedInitialZoom

            guard needsReset else { return }

            let widthScale = boundsSize.width / max(imageSize.width, 1)
            let heightScale = boundsSize.height / max(imageSize.height, 1)
            let fitMargin: CGFloat = 2
            let availableWidth = max(boundsSize.width - (fitMargin * 2), 1)
            let availableHeight = max(boundsSize.height - (fitMargin * 2), 1)
            let marginWidthScale = availableWidth / max(imageSize.width, 1)
            let marginHeightScale = availableHeight / max(imageSize.height, 1)
            let baseScale: CGFloat = mode == .fitWidth ? min(widthScale, marginWidthScale) : min(widthScale, heightScale, marginWidthScale, marginHeightScale)
            let safeBaseScale = max(baseScale.isFinite ? baseScale : 1.0, 0.01)

            let fittedSize = CGSize(
                width: imageSize.width * safeBaseScale,
                height: imageSize.height * safeBaseScale
            )
            imageView.frame = CGRect(origin: .zero, size: fittedSize)
            scrollView.contentSize = fittedSize
            scrollView.minimumZoomScale = 1.0
            scrollView.maximumZoomScale = 4.0

            hasAppliedInitialZoom = false
            scrollView.setZoomScale(1.0, animated: false)
            centerImageIfNeeded()
            scrollView.contentOffset = .zero
            hasAppliedInitialZoom = true

            lastBoundsSize = boundsSize
            lastImageIdentity = imageIdentity
            lastMode = mode
            centerImageIfNeeded()
        }

        private func centerImageIfNeeded() {
            guard let scrollView else { return }

            var frame = imageView.frame
            frame.origin.x = frame.width < scrollView.bounds.width
                ? (scrollView.bounds.width - frame.width) * 0.5
                : 0
            frame.origin.y = frame.height < scrollView.bounds.height
                ? (scrollView.bounds.height - frame.height) * 0.5
                : 0
            imageView.frame = frame
        }
    }
}

@MainActor
struct ZoomablePageContainerView: View {
    let localImage: UIImage?
    let remoteURL: URL?
    let mode: ReaderZoomMode
    let showDebugOverlay: Bool
    let debugPageIndex: Int
    let debugLocalPath: String?
    let debugLocalFileExists: Bool
    let debugLocalDecoded: Bool

    @State private var loadedRemoteImage: UIImage?
    @State private var hasLoadError = false
    @State private var remoteStatusCode: Int?
    @State private var remoteByteCount: Int?
    @State private var debugMessage: String = "init"
    @State private var showFallbackChrome = false

    var body: some View {
        Group {
            if let image = localImage ?? loadedRemoteImage {
                ZoomableImageView(image: image, mode: mode)
            } else if hasLoadError {
                UnavailableStateView(title: "Image failed", systemImage: "xmark.octagon")
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(
            Group {
                if showFallbackChrome || hasLoadError {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(AppChrome.card)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(AppChrome.border, lineWidth: 1)
                        )
                }
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(alignment: .topLeading) {
            if showDebugOverlay {
                Text(debugText)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white)
                    .padding(8)
                    .background(Color.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .padding(8)
                    .allowsHitTesting(false)
            }
        }
        .task(id: remoteURL) {
            loadedRemoteImage = nil
            hasLoadError = false
            remoteStatusCode = nil
            remoteByteCount = nil
            showFallbackChrome = false

            let fallbackTask = Task {
                try? await Task.sleep(nanoseconds: 200_000_000)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    if localImage == nil && loadedRemoteImage == nil && !hasLoadError {
                        showFallbackChrome = true
                    }
                }
            }

            if localImage != nil {
                debugMessage = "local image ready"
                fallbackTask.cancel()
                showFallbackChrome = false
                return
            }

            if remoteURL == nil {
                debugMessage = "no source image available"
                fallbackTask.cancel()
                hasLoadError = true
                showFallbackChrome = true
                return
            }

            await loadRemoteImage()
            fallbackTask.cancel()
            showFallbackChrome = hasLoadError
        }
        .transaction { transaction in
            transaction.animation = nil
        }
    }

    private var debugText: String {
        let status = remoteStatusCode.map(String.init) ?? "-"
        let bytes = remoteByteCount.map(String.init) ?? "-"
        let remote = remoteURL?.absoluteString ?? "-"
        let localPath = debugLocalPath ?? "-"
        let rendered = (localImage ?? loadedRemoteImage).map { "\(Int($0.size.width))x\(Int($0.size.height))" } ?? "-"

        return """
        page=\(debugPageIndex + 1)
        local.exists=\(debugLocalFileExists) local.decoded=\(debugLocalDecoded)
        local.file=\(localPath)
        remote.status=\(status) bytes=\(bytes)
        image.size=\(rendered)
        remote.url=\(remote)
        state=\(debugMessage)
        """
    }

    private func loadRemoteImage() async {
        guard let remoteURL else { return }
        debugMessage = "fetching remote"
        do {
            let (data, response) = try await URLSession.shared.data(from: remoteURL)
            guard let http = response as? HTTPURLResponse else {
                debugMessage = "invalid HTTP response"
                hasLoadError = true
                return
            }
            remoteStatusCode = http.statusCode
            remoteByteCount = data.count

            guard (200...299).contains(http.statusCode) else {
                debugMessage = "HTTP \(http.statusCode)"
                hasLoadError = true
                return
            }

            guard let image = UIImage(data: data) else {
                debugMessage = "decode failed"
                hasLoadError = true
                return
            }
            loadedRemoteImage = image
            hasLoadError = false
            debugMessage = "remote image ready"
        } catch {
            debugMessage = "network error: \(error.localizedDescription)"
            hasLoadError = true
        }
    }
}
