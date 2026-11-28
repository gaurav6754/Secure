import SwiftUI
import AVFoundation
import UIKit

enum WallpaperKind: String, Codable, CaseIterable {
    case off = "none"
    case photo = "static"
    case live = "live"
}

struct WallpaperItem: Identifiable, Codable, Hashable {
    let id: String
    let title: String
    let category: String
    let kind: WallpaperKind
    let source: String
    let url: String
    let fallbackUrl: String?
    let meta: String?

    var thumbnailURL: URL? {
        if kind == .photo, url.contains("images.pexels.com") {
            let sep = url.contains("?") ? "&" : "?"
            return URL(string: "\(url)\(sep)auto=compress&cs=tinysrgb&w=420")
        }
        return URL(string: url)
    }

    var displayURL: URL? {
        if kind == .photo, url.contains("images.pexels.com") {
            let sep = url.contains("?") ? "&" : "?"
            return URL(string: "\(url)\(sep)auto=compress&cs=tinysrgb&w=1080")
        }
        return URL(string: url)
    }
}

struct WallpaperCatalogFile: Codable {
    let version: Int
    let curatedLive: [WallpaperItem]
    let lively108: [WallpaperItem]
    let staticPhotos: [WallpaperItem]
}

final class WallpaperCatalog {
    static let shared = WallpaperCatalog()

    let curatedLive: [WallpaperItem]
    let lively108: [WallpaperItem]
    let staticPhotos: [WallpaperItem]

    private init() {
        if let url = Bundle.main.url(forResource: "wallpapers_catalog", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode(WallpaperCatalogFile.self, from: data) {
            self.curatedLive = decoded.curatedLive
            self.lively108 = decoded.lively108
            self.staticPhotos = decoded.staticPhotos
        } else {
            self.curatedLive = []
            self.lively108 = []
            self.staticPhotos = []
        }
    }
}

// MARK: - 120Hz Off-Main-Thread Image Cache (Zero Scroll Hitches)
final class WallpaperImageCache {
    static let shared = WallpaperImageCache()

    private let cache: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.countLimit = 90
        c.totalCostLimit = 64 * 1024 * 1024
        return c
    }()

    private let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.urlCache = URLCache(memoryCapacity: 32 * 1024 * 1024, diskCapacity: 180 * 1024 * 1024, diskPath: "secure_ai_wallpaper_cache")
        cfg.requestCachePolicy = .returnCacheDataElseLoad
        cfg.timeoutIntervalForRequest = 18
        return URLSession(configuration: cfg)
    }()

    func cached(for key: String) -> UIImage? {
        cache.object(forKey: key as NSString)
    }

    func load(url: URL) async -> UIImage? {
        let key = url.absoluteString
        if let hit = cache.object(forKey: key as NSString) {
            return hit
        }
        do {
            let (data, _) = try await session.data(from: url)
            guard let raw = UIImage(data: data) else { return nil }
            // Decompress image off the main thread so 120Hz ProMotion scrolling never drops a frame
            let decoded = await Task.detached(priority: .utility) { () -> UIImage in
                raw.preparingForDisplay() ?? raw
            }.value
            let cost = Int(decoded.size.width * decoded.size.height * decoded.scale * decoded.scale * 4)
            cache.setObject(decoded, forKey: key as NSString, cost: max(cost, 1))
            return decoded
        } catch {
            return nil
        }
    }
}

/// Hardware-decompressed cached static wallpaper view (keeps ProMotion locked at 120fps)
struct StaticWallpaperImageView: View {
    let urlString: String
    let isThumbnail: Bool
    @State private var image: UIImage? = nil

    private var resolvedURL: URL? {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.contains("images.pexels.com") {
            let sep = trimmed.contains("?") ? "&" : "?"
            let w = isThumbnail ? 420 : 1080
            return URL(string: "\(trimmed)\(sep)auto=compress&cs=tinysrgb&w=\(w)")
        }
        return URL(string: trimmed)
    }

    var body: some View {
        Group {
            if let img = image {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
            } else {
                Color.clear
            }
        }
        .task(id: resolvedURL?.absoluteString ?? "") {
            guard let url = resolvedURL else {
                image = nil
                return
            }
            if let hit = WallpaperImageCache.shared.cached(for: url.absoluteString) {
                image = hit
                return
            }
            let loaded = await WallpaperImageCache.shared.load(url: url)
            if !Task.isCancelled {
                image = loaded
            }
        }
    }
}

// MARK: - 120Hz Hardware VideoToolbox Live MP4 Wallpaper Player (AVPlayerLayer + AVPlayerLooper)
@MainActor
final class LoopingPlayerContainerView: UIView {
    private let playerLayer = AVPlayerLayer()
    private var queuePlayer: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var currentURLString: String = ""
    private var fallbackURLString: String = ""
    private var statusObserver: NSKeyValueObservation?
    private var triedFallback: Bool = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isUserInteractionEnabled = false
        clipsToBounds = true
        playerLayer.videoGravity = .resizeAspectFill
        layer.addSublayer(playerLayer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.frame = bounds
        CATransaction.commit()
    }

    func configure(urlString: String, fallbackUrlString: String, isActive: Bool) {
        if urlString != currentURLString {
            currentURLString = urlString
            fallbackURLString = fallbackUrlString
            triedFallback = false
            loadStream(urlString: urlString, isActive: isActive)
        } else {
            setPlaying(isActive)
        }
    }

    private func loadStream(urlString: String, isActive: Bool) {
        tearDown()
        guard let url = URL(string: urlString) else { return }

        let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: false])
        let item = AVPlayerItem(asset: asset)
        item.preferredForwardBufferDuration = 2.0

        let player = AVQueuePlayer()
        player.isMuted = true
        player.volume = 0
        player.allowsExternalPlayback = false
        player.preventsDisplaySleepDuringVideoPlayback = false
        player.automaticallyWaitsToMinimizeStalling = true
        player.actionAtItemEnd = .none

        let playerLooper = AVPlayerLooper(player: player, templateItem: item)
        self.queuePlayer = player
        self.looper = playerLooper
        playerLayer.player = player

        // Automatic fallback to original 4K download.mp4 if /hd.mp4 is unavailable on CDN
        statusObserver = item.observe(\.status, options: [.new]) { [weak self] observed, _ in
            let failed = (observed.status == .failed)
            guard failed else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                if !self.triedFallback && !self.fallbackURLString.isEmpty && self.fallbackURLString != urlString {
                    self.triedFallback = true
                    self.loadStream(urlString: self.fallbackURLString, isActive: isActive)
                }
            }
        }

        if isActive {
            player.play()
        }
    }

    func setPlaying(_ active: Bool) {
        guard let player = queuePlayer else { return }
        if active {
            if player.rate == 0 {
                player.play()
            }
        } else {
            if player.rate != 0 {
                player.pause()
            }
        }
    }

    func tearDown() {
        statusObserver?.invalidate()
        statusObserver = nil
        queuePlayer?.pause()
        looper?.disableLooping()
        looper = nil
        queuePlayer?.removeAllItems()
        queuePlayer = nil
        playerLayer.player = nil
    }
}

struct LiveWallpaperPlayerView: UIViewRepresentable {
    let urlString: String
    let fallbackUrlString: String
    let isActive: Bool

    func makeUIView(context: Context) -> LoopingPlayerContainerView {
        let view = LoopingPlayerContainerView()
        view.configure(urlString: urlString, fallbackUrlString: fallbackUrlString, isActive: isActive)
        return view
    }

    func updateUIView(_ uiView: LoopingPlayerContainerView, context: Context) {
        uiView.configure(urlString: urlString, fallbackUrlString: fallbackUrlString, isActive: isActive)
    }

    static func dismantleUIView(_ uiView: LoopingPlayerContainerView, coordinator: ()) {
        uiView.tearDown()
    }
}

// MARK: - Searchable HD Photo & Live MP4 Wallpaper Picker Sheet
enum WallpaperGalleryTab: String, CaseIterable, Identifiable {
    case curatedLive = "Curated Live"
    case lively108 = "108 Live MP4"
    case staticPhotos = "HD Photos"
    case customURL = "Custom URL"

    var id: String { rawValue }
}

struct WallpaperGallerySheet: View {
    @EnvironmentObject var theme: ThemeManager
    @Environment(\.dismiss) private var dismiss

    @State private var selectedTab: WallpaperGalleryTab = .curatedLive
    @State private var searchText: String = ""
    @State private var selectedCategory: String = "All"
    @State private var customURLInput: String = ""
    @State private var customKind: WallpaperKind = .live

    private var pal: AppThemePalette { theme.palette }
    private let catalog = WallpaperCatalog.shared

    private var currentLivePool: [WallpaperItem] {
        selectedTab == .curatedLive ? catalog.curatedLive : catalog.lively108
    }

    private var availableCategories: [String] {
        var seen = Set<String>()
        var out = ["All"]
        for item in currentLivePool {
            if !seen.contains(item.category) {
                seen.insert(item.category)
                out.append(item.category)
            }
        }
        return out
    }

    private var filteredLiveItems: [WallpaperItem] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return currentLivePool.filter { item in
            let catOk = (selectedCategory == "All" || item.category == selectedCategory)
            let qOk = q.isEmpty || item.title.lowercased().contains(q) || item.category.lowercased().contains(q)
            return catOk && qOk
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                // Active Wallpaper Status Bar
                HStack(spacing: 10) {
                    Image(systemName: theme.customWallpaperKind == .live ? "play.rectangle.fill" : (theme.customWallpaperKind == .photo ? "photo.fill" : "sparkles"))
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(pal.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(theme.customWallpaperKind == .off ? "Using Built-in \(theme.wallpaper.rawValue)" : theme.customWallpaperTitle)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(pal.fg)
                            .lineLimit(1)
                        Text("120Hz Hardware Compositing • Auto-pauses when sidebar hides")
                            .font(.system(size: 10.5))
                            .foregroundColor(pal.muted)
                    }
                    Spacer()
                    if theme.customWallpaperKind != .off {
                        Button("Reset") {
                            theme.clearCustomWallpaper()
                        }
                        .font(.system(size: 11.5, weight: .bold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(SecureTheme.red.opacity(0.18))
                        .foregroundColor(SecureTheme.red)
                        .cornerRadius(8)
                    }
                }
                .padding(11)
                .background(pal.card)
                .cornerRadius(11)
                .overlay(RoundedRectangle(cornerRadius: 11).stroke(pal.line.opacity(0.7), lineWidth: 1))
                .padding(.horizontal, 16)

                Picker("Gallery", selection: $selectedTab) {
                    ForEach(WallpaperGalleryTab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .onChange(of: selectedTab) { _ in
                    selectedCategory = "All"
                }

                if selectedTab == .curatedLive || selectedTab == .lively108 {
                    liveGalleryBody
                } else if selectedTab == .staticPhotos {
                    staticPhotoGalleryBody
                } else {
                    customURLBody
                }
            }
            .padding(.top, 10)
            .background(pal.bg.ignoresSafeArea())
            .navigationTitle("Wallpapers & Live MP4 (\(catalog.curatedLive.count + catalog.lively108.count + catalog.staticPhotos.count))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .font(.system(size: 14, weight: .bold))
                }
            }
        }
        .preferredColorScheme(pal.isLight ? .light : .dark)
    }

    private var liveGalleryBody: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(pal.muted)
                TextField("Search live wallpapers (e.g. galaxy, anime, car, rain)...", text: $searchText)
                    .font(.system(size: 13))
                    .foregroundColor(pal.fg)
                    .autocorrectionDisabled(true)
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundColor(pal.muted)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(pal.card)
            .cornerRadius(10)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(pal.line.opacity(0.6), lineWidth: 1))
            .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    ForEach(availableCategories, id: \.self) { cat in
                        Button {
                            selectedCategory = cat
                        } label: {
                            Text(cat)
                                .font(.system(size: 11.5, weight: .semibold))
                                .padding(.horizontal, 11)
                                .padding(.vertical, 6)
                                .background(selectedCategory == cat ? pal.accent : pal.card)
                                .foregroundColor(selectedCategory == cat ? .white : pal.fg)
                                .cornerRadius(16)
                                .overlay(RoundedRectangle(cornerRadius: 16).stroke(pal.line.opacity(0.6), lineWidth: 1))
                        }
                    }
                }
                .padding(.horizontal, 16)
            }

            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 10)], spacing: 10) {
                    ForEach(filteredLiveItems) { item in
                        let isSelected = (theme.customWallpaperURL == item.url && theme.customWallpaperKind == .live)
                        Button {
                            theme.applyCustomWallpaper(item)
                        } label: {
                            HStack(spacing: 10) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 9)
                                        .fill(
                                            LinearGradient(
                                                colors: [pal.orb1.opacity(0.75), pal.orb2.opacity(0.65)],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                        .frame(width: 46, height: 46)
                                    Image(systemName: isSelected ? "checkmark.circle.fill" : "play.fill")
                                        .font(.system(size: 17, weight: .bold))
                                        .foregroundColor(.white)
                                }
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(item.title)
                                        .font(.system(size: 12.5, weight: .bold))
                                        .foregroundColor(pal.fg)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.leading)
                                    HStack(spacing: 5) {
                                        Text(item.category)
                                            .font(.system(size: 10, weight: .semibold))
                                            .foregroundColor(pal.accent)
                                            .lineLimit(1)
                                        if let meta = item.meta {
                                            Text("• \(meta)")
                                                .font(.system(size: 9.5))
                                                .foregroundColor(pal.muted)
                                                .lineLimit(1)
                                        }
                                    }
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(10)
                            .background(isSelected ? pal.accent.opacity(0.16) : pal.card)
                            .cornerRadius(11)
                            .overlay(
                                RoundedRectangle(cornerRadius: 11)
                                    .stroke(isSelected ? pal.accent : pal.line.opacity(0.65), lineWidth: isSelected ? 1.8 : 1)
                            )
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
            }
        }
    }

    private var staticPhotoGalleryBody: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 10)], spacing: 10) {
                ForEach(catalog.staticPhotos) { item in
                    let isSelected = (theme.customWallpaperURL == item.url && theme.customWallpaperKind == .photo)
                    Button {
                        theme.applyCustomWallpaper(item)
                    } label: {
                        ZStack(alignment: .bottomLeading) {
                            StaticWallpaperImageView(urlString: item.url, isThumbnail: true)
                                .frame(height: 112)
                                .frame(maxWidth: .infinity)
                                .background(pal.panel)
                                .clipped()

                            LinearGradient(
                                colors: [.clear, .black.opacity(0.65)],
                                startPoint: .center,
                                endPoint: .bottom
                            )

                            HStack {
                                Text(item.title)
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.white)
                                Spacer()
                                if isSelected {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 14))
                                        .foregroundColor(SecureTheme.green)
                                }
                            }
                            .padding(7)
                        }
                        .frame(height: 112)
                        .cornerRadius(11)
                        .overlay(
                            RoundedRectangle(cornerRadius: 11)
                                .stroke(isSelected ? pal.accent : pal.line.opacity(0.5), lineWidth: isSelected ? 2.2 : 1)
                        )
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 20)
        }
    }

    private var customURLBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Apply Any Direct Wallpaper Link")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(pal.fg)
                Text("Paste any direct .mp4 live wallpaper link or .jpg / .png / .webp static wallpaper link.")
                    .font(.system(size: 12))
                    .foregroundColor(pal.muted)

                Picker("Type", selection: $customKind) {
                    Text("Live MP4 Video").tag(WallpaperKind.live)
                    Text("Static Photo").tag(WallpaperKind.photo)
                }
                .pickerStyle(.segmented)

                TextField("https://... (.mp4 or .jpg)", text: $customURLInput)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .font(.system(size: 12.5, design: .monospaced))

                Button {
                    let trimmed = customURLInput.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard trimmed.lowercased().hasPrefix("http") else { return }
                    let detectedKind: WallpaperKind = trimmed.lowercased().contains(".mp4") || trimmed.lowercased().contains(".mov") ? .live : customKind
                    let item = WallpaperItem(
                        id: "custom_\(abs(trimmed.hashValue))",
                        title: detectedKind == .live ? "Custom Live MP4" : "Custom HD Photo",
                        category: "Custom",
                        kind: detectedKind,
                        source: "custom",
                        url: trimmed,
                        fallbackUrl: nil,
                        meta: "Direct Link"
                    )
                    theme.applyCustomWallpaper(item)
                    dismiss()
                } label: {
                    Label("Apply Custom Wallpaper", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 13, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(pal.accent)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
                .disabled(!customURLInput.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().hasPrefix("http"))
            }
            .padding(16)
            .background(pal.card)
            .cornerRadius(12)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(pal.line.opacity(0.6), lineWidth: 1))
            .padding(.horizontal, 16)
        }
    }
}
