import SwiftUI
import Charts
#if SWIFT_PACKAGE
import PoochiCore
#endif

enum PoochiStyle {
    static let teal = Color(red: 0.08, green: 0.36, blue: 0.34)
    static let cream = Color(red: 0.97, green: 0.96, blue: 0.93)
    static let coral = Color(red: 0.82, green: 0.39, blue: 0.28)
}
private enum WorkspacePage: String, CaseIterable, Identifiable {
    case overview = "Overview", videos = "Videos", compare = "Compare"
    var id: Self { self }
    var icon: String {
        switch self { case .overview: return "chart.xyaxis.line"; case .videos: return "play.rectangle"; case .compare: return "rectangle.split.3x1" }
    }
}

struct ContentView: View {
    @EnvironmentObject private var store: AnalyticsStore
    @State private var page: WorkspacePage? = .overview
    @State private var selected = Set<String>()
    @State private var settings = false
    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 10) {
                    Image(systemName: "pawprint.fill").font(.system(size: 30)).foregroundStyle(PoochiStyle.teal)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Poochi").font(.title2.bold())
                        Text("ANALYTICS").font(.system(size: 9, weight: .semibold)).tracking(2).foregroundStyle(.secondary)
                    }
                }.padding(.horizontal, 20).padding(.top, 24)
                List(selection: $page) {
                    Section("YOUR WORKSPACE") {
                        ForEach(WorkspacePage.allCases) { item in
                            NavigationLink(value: item) { Label(item.rawValue, systemImage: item.icon).padding(.vertical, 5) }
                                .accessibilityIdentifier("nav.\(item.rawValue.lowercased())")
                        }
                    }
                }.listStyle(.sidebar)
                VStack(alignment: .leading, spacing: 12) {
                    Label(store.isSample ? "Sample workspace" : store.isConnected ? "TikTok connected" : "Ready to connect",
                          systemImage: store.isSample ? "sparkles" : store.isConnected ? "checkmark.circle.fill" : "link")
                        .font(.caption).foregroundStyle(store.isConnected && !store.isSample ? PoochiStyle.teal : .secondary)
                    Text("Private. Local. Yours.").font(.caption).foregroundStyle(.secondary)
                    Button("Settings…") { settings = true }.buttonStyle(.plain)
                    Link("Privacy policy", destination: URL(string: "https://hoover2x.github.io/poochi-analytics-pages/privacy.html")!)
                        .font(.caption)
                }.padding(20)
            }.navigationSplitViewColumnWidth(min: 195, ideal: 210, max: 240)
        } detail: {
            VStack(spacing: 0) {
                if store.isSample {
                    HStack {
                        Label("Sample data · These are example numbers, not your TikTok results.", systemImage: "sparkles")
                        Spacer()
                        Button("Exit sample") { store.leaveSample(); selected = [] }
                    }.font(.caption).padding(12).background(Color.orange.opacity(0.12))
                }
                if let error = store.errorMessage { message(error, isError: true) }
                if let notice = store.notice { message(notice, isError: false) }
                Group {
                    if let archive = store.archive {
                        switch page ?? .overview {
                        case .overview: OverviewView(archive: archive)
                        case .videos: VideosView(archive: archive, selected: $selected)
                        case .compare: ComparisonView(videos: archive.videos.filter { selected.contains($0.id) }) { page = .videos }
                        }
                    } else { WelcomeView { settings = true } }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(PoochiStyle.cream)
            .navigationTitle((page ?? .overview).rawValue)
            .toolbar {
                ToolbarItemGroup {
                    if store.isBusy { ProgressView().controlSize(.small) }
                    if store.isLoggingIn { Button("Cancel login") { store.cancelLogin() } }
                    else if store.isConnected && !store.isSample {
                        Button { Task { await store.refresh() } } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                            .disabled(store.isBusy).keyboardShortcut("r", modifiers: .command)
                    } else if !store.isSample {
                        Button("Connect TikTok") {
                            if store.hasConfiguration { Task { await store.connect() } } else { settings = true }
                        }.disabled(store.isBusy)
                    }
                    Button { settings = true } label: { Label("Settings", systemImage: "gearshape") }
                }
            }
        }
        .sheet(isPresented: $settings) { SettingsView().environmentObject(store) }
        .onChange(of: store.archive?.profile.openID) { _ in selected = [] }
    }
    private func message(_ text: String, isError: Bool) -> some View {
        HStack(alignment: .top) {
            Image(systemName: isError ? "exclamationmark.circle" : "checkmark.circle")
            Text(text).textSelection(.enabled)
            Spacer()
            Button { if isError { store.errorMessage = nil } else { store.notice = nil } } label: { Image(systemName: "xmark") }
                .buttonStyle(.plain).accessibilityLabel("Dismiss message")
        }.font(.caption).padding(12).foregroundStyle(isError ? Color.red : PoochiStyle.teal)
            .background(isError ? Color.red.opacity(0.07) : PoochiStyle.teal.opacity(0.07))
    }
}

private struct WelcomeView: View {
    @EnvironmentObject private var store: AnalyticsStore
    let settings: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Label("POOCHI & FRIENDS", systemImage: "pawprint.fill")
                .font(.caption.weight(.semibold)).tracking(2).foregroundStyle(PoochiStyle.teal)
            Text("A little clarity.\nA lot of personality.").font(.system(size: 43, weight: .semibold, design: .serif))
            Text("Your TikTok account and video performance, together in a quiet workspace on your Mac.")
                .font(.title3).foregroundStyle(.secondary).frame(maxWidth: 560, alignment: .leading)
            HStack(spacing: 12) {
                Button("Set up TikTok connection", action: settings).buttonStyle(.borderedProminent).controlSize(.large)
                Button("Explore sample data") { store.showSample() }.controlSize(.large)
            }.padding(.vertical, 8)
            HStack(alignment: .top, spacing: 28) {
                feature("Account growth", "Follow your account from the first saved observation.", "chart.line.uptrend.xyaxis")
                feature("Video performance", "Review views, likes, comments, shares, and engagement.", "play.rectangle")
                feature("Made for your Mac", "Keep credentials in Keychain and analytics on this device.", "lock.shield")
            }
            Text("TikTok authorization is read-only. Use your TikTok sandbox app keys while the app is awaiting approval.")
                .font(.caption).foregroundStyle(.secondary).padding(.top, 12)
        }.padding(48).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
    private func feature(_ title: String, _ text: String, _ icon: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon).font(.title2).foregroundStyle(PoochiStyle.teal)
            Text(title).font(.headline)
            Text(text).font(.callout).foregroundStyle(.secondary)
        }.frame(maxWidth: 180, alignment: .leading)
    }
}

private struct MetricCard: View {
    let title: String
    let value: String
    let subtitle: String
    let icon: String
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Text(title).font(.callout).foregroundStyle(.secondary); Spacer(); Image(systemName: icon).foregroundStyle(PoochiStyle.teal) }
            Text(value).font(.system(size: 28, weight: .semibold, design: .rounded)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
            Text(subtitle).font(.caption).foregroundStyle(.secondary)
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(.background, in: RoundedRectangle(cornerRadius: 14))
    }
}
private func countText(_ value: Int64?) -> String { value?.formatted(.number) ?? "—" }
private func rateText(_ value: Double?) -> String { value?.formatted(.percent.precision(.fractionLength(1))) ?? "—" }

private struct OverviewView: View {
    let archive: AnalyticsArchive
    private var summary: VideoSummary { VideoSummary(videos: archive.videos) }
    private var history: [AccountObservation] { archive.observations.filter { $0.followers != nil } }
    private var ranked: [TikTokVideo] { Array(VideoSort.views.sorted(archive.videos).filter { $0.viewCount != nil }.prefix(6)) }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text(archive.profile.displayName ?? "Your TikTok account").font(.system(size: 30, weight: .semibold, design: .serif))
                        if let username = archive.profile.username { Text("@\(username)").foregroundStyle(.secondary) }
                        if let bio = archive.profile.bioDescription, !bio.isEmpty { Text(bio).font(.callout).foregroundStyle(.secondary) }
                    }
                    Spacer()
                    Text("Observed \(archive.updatedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.trailing)
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 12) {
                    MetricCard(title: "Followers", value: countText(archive.profile.followerCount), subtitle: "Current account total", icon: "person.2")
                    MetricCard(title: "Account likes", value: countText(archive.profile.likesCount), subtitle: "Current account total", icon: "heart")
                    MetricCard(title: "Public videos", value: countText(archive.profile.videoCount), subtitle: "Current account total", icon: "play.rectangle")
                    MetricCard(title: "Following", value: countText(archive.profile.followingCount), subtitle: "Current account total", icon: "person.badge.plus")
                }
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Growing together").font(.title3.weight(.semibold))
                        Text("Followers · locally saved observations").font(.caption).foregroundStyle(.secondary)
                        if history.count > 1 {
                            Chart(history) { observation in
                                LineMark(x: .value("Date", observation.date), y: .value("Followers", observation.followers ?? 0))
                                    .foregroundStyle(PoochiStyle.teal).interpolationMethod(.linear)
                                PointMark(x: .value("Date", observation.date), y: .value("Followers", observation.followers ?? 0))
                                    .foregroundStyle(PoochiStyle.teal)
                            }.chartYScale(domain: .automatic(includesZero: false)).frame(height: 200)
                        } else {
                            VStack(spacing: 12) {
                                Image(systemName: "leaf").font(.largeTitle).foregroundStyle(PoochiStyle.teal)
                                Text("Your history starts here").font(.headline)
                                Text("Refresh on another day to see account growth. Earlier history is not supplied by this connection.")
                                    .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                            }.frame(maxWidth: .infinity, minHeight: 200)
                        }
                    }.padding(22).frame(maxWidth: .infinity).background(.background, in: RoundedRectangle(cornerRadius: 14))
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Videos finding their people").font(.title3.weight(.semibold))
                        Text("Lifetime views · top loaded videos").font(.caption).foregroundStyle(.secondary)
                        if ranked.isEmpty {
                            Text("Video view counts will appear after they are available from TikTok.").foregroundStyle(.secondary).frame(height: 200)
                        } else {
                            Chart(ranked) { video in
                                BarMark(x: .value("Views", video.viewCount ?? 0), y: .value("Video", video.id))
                                    .foregroundStyle(PoochiStyle.teal.gradient).cornerRadius(4)
                            }.chartYAxis {
                                AxisMarks { value in
                                    AxisValueLabel {
                                        if let id = value.as(String.self), let video = ranked.first(where: { $0.id == id }) {
                                            Text(String(video.displayTitle.prefix(25)))
                                        }
                                    }
                                }
                            }.frame(height: 200)
                        }
                    }.padding(22).frame(maxWidth: .infinity).background(.background, in: RoundedRectangle(cornerRadius: 14))
                }
                HStack(spacing: 12) {
                    MetricCard(title: "Loaded video views", value: countText(summary.views), subtitle: "Lifetime total across \(summary.videoCount) loaded videos", icon: "eye")
                    MetricCard(title: "Engagement by views", value: rateText(summary.engagementRate), subtitle: "(Likes + comments + shares) ÷ views", icon: "bubble.left.and.bubble.right")
                }
                Text("— means unavailable. Video totals describe the videos currently loaded. \(archive.hasMore ? "Load more in Videos to include older posts." : "All returned public videos are loaded.")")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(28)
        }
    }
}

private struct VideosView: View {
    @EnvironmentObject private var store: AnalyticsStore
    let archive: AnalyticsArchive
    @Binding var selected: Set<String>
    @State private var search = ""
    @State private var sort: VideoSort = .newest
    @State private var days = 0
    private var filtered: [TikTokVideo] {
        sort.sorted(archive.videos.filter { video in
            let matches = search.isEmpty || video.displayTitle.localizedCaseInsensitiveContains(search)
            let dateMatches = days == 0 || (video.postedAt.map { $0 >= Date().addingTimeInterval(-Double(days) * 86400) } ?? false)
            return matches && dateMatches
        })
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Every post has a story").font(.system(size: 28, weight: .semibold, design: .serif))
                    Text("\(filtered.count) shown · \(archive.videos.count) loaded · select up to 3 videos to compare")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button { store.exportCSV(filtered) } label: { Label("Export CSV", systemImage: "square.and.arrow.up") }.disabled(filtered.isEmpty)
            }
            HStack {
                TextField("Search video titles", text: $search).textFieldStyle(.roundedBorder).frame(maxWidth: 260)
                Picker("Posted", selection: $days) {
                    Text("All dates").tag(0); Text("Last 7 days").tag(7); Text("Last 30 days").tag(30); Text("Last 90 days").tag(90)
                }.frame(width: 190)
                Spacer()
                Picker("Sort", selection: $sort) { ForEach(VideoSort.allCases) { Text($0.rawValue).tag($0) } }.frame(width: 190)
            }
            Text("Counts are lifetime totals for videos posted in the selected dates; they are not views earned during that date range.")
                .font(.caption).foregroundStyle(.secondary)
            Table(filtered, selection: $selected) {
                TableColumn("Video") { video in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(video.displayTitle).lineLimit(2).font(.callout.weight(.medium))
                        if let date = video.postedAt { Text(date, style: .date).font(.caption).foregroundStyle(.secondary) }
                    }.padding(.vertical, 5)
                }.width(min: 190, ideal: 260)
                TableColumn("Views") { Text(countText($0.viewCount)).monospacedDigit() }
                TableColumn("Likes") { Text(countText($0.likeCount)).monospacedDigit() }
                TableColumn("Comments") { Text(countText($0.commentCount)).monospacedDigit() }
                TableColumn("Shares") { Text(countText($0.shareCount)).monospacedDigit() }
                TableColumn("Engagement") { Text(rateText($0.engagementRate)).monospacedDigit() }
            }.frame(minHeight: 300).clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay {
                    if filtered.isEmpty { Text("No videos match. Check your filters and TikTok video permission.").foregroundStyle(.secondary) }
                }
            HStack {
                if archive.hasMore {
                    Button("Load older videos") { Task { await store.loadMore() } }.disabled(store.isBusy || store.isSample)
                } else { Text("All returned videos loaded").font(.caption).foregroundStyle(.secondary) }
                Spacer()
                if selected.count == 1, let video = archive.videos.first(where: { selected.contains($0.id) }),
                   let url = video.shareURL, url.scheme == "https", let host = url.host,
                   host == "tiktok.com" || host.hasSuffix(".tiktok.com") { Link("Open selected video on TikTok ↗", destination: url) }
                Text("\(selected.count) selected").font(.caption).foregroundStyle(.secondary)
            }
        }.padding(28)
        .onChange(of: selected) { values in
            if values.count > 3 { selected = Set(values.sorted().prefix(3)) }
        }
    }
}

private struct ComparisonView: View {
    let videos: [TikTokVideo]
    let choose: () -> Void
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Side by side").font(.system(size: 30, weight: .semibold, design: .serif))
                Text("Compare the lifetime results of up to three loaded videos.").foregroundStyle(.secondary)
                if videos.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "rectangle.split.3x1").font(.system(size: 42)).foregroundStyle(PoochiStyle.teal)
                        Text("Choose your videos").font(.title2)
                        Text("Select two or three rows in Videos. Use Command-click to select multiple rows.").foregroundStyle(.secondary)
                        Button("Go to Videos", action: choose).buttonStyle(.borderedProminent)
                    }.frame(maxWidth: .infinity, minHeight: 320).background(.background, in: RoundedRectangle(cornerRadius: 14))
                } else {
                    HStack(alignment: .top, spacing: 16) {
                        ForEach(videos) { video in
                            VStack(alignment: .leading, spacing: 20) {
                                Text(video.displayTitle).font(.title3.weight(.semibold)).frame(minHeight: 52, alignment: .top)
                                Divider()
                                comparisonMetric("Views", countText(video.viewCount))
                                comparisonMetric("Likes", countText(video.likeCount))
                                comparisonMetric("Comments", countText(video.commentCount))
                                comparisonMetric("Shares", countText(video.shareCount))
                                comparisonMetric("Engagement by views", rateText(video.engagementRate))
                                if let date = video.postedAt { Text("Posted \(date.formatted(date: .abbreviated, time: .omitted))").font(.caption).foregroundStyle(.secondary) }
                            }.padding(24).frame(maxWidth: .infinity, alignment: .leading).background(.background, in: RoundedRectangle(cornerRadius: 14))
                        }
                    }
                    Text("Engagement = (likes + comments + shares) ÷ views. Unavailable values and zero-view rates appear as —.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Change selection", action: choose)
                }
            }.padding(28)
        }
    }
    private func comparisonMetric(_ name: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(name).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.system(size: 24, weight: .semibold, design: .rounded)).monospacedDigit()
        }
    }
}
