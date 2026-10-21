import Foundation

public struct TikTokProfile: Codable, Equatable, Sendable {
    public var openID: String
    public var displayName: String?
    public var username: String?
    public var avatarURL: URL?
    public var bioDescription: String?
    public var profileDeepLink: URL?
    public var followerCount: Int64?
    public var followingCount: Int64?
    public var likesCount: Int64?
    public var videoCount: Int64?

    public init(openID: String, displayName: String? = nil, username: String? = nil,
                avatarURL: URL? = nil, bioDescription: String? = nil,
                profileDeepLink: URL? = nil, followerCount: Int64? = nil,
                followingCount: Int64? = nil, likesCount: Int64? = nil, videoCount: Int64? = nil) {
        self.openID = openID; self.displayName = displayName; self.username = username
        self.avatarURL = avatarURL; self.bioDescription = bioDescription; self.profileDeepLink = profileDeepLink
        self.followerCount = followerCount; self.followingCount = followingCount
        self.likesCount = likesCount; self.videoCount = videoCount
    }

    enum CodingKeys: String, CodingKey {
        case openID = "open_id", displayName = "display_name", username
        case avatarURL = "avatar_url", bioDescription = "bio_description", profileDeepLink = "profile_deep_link"
        case followerCount = "follower_count", followingCount = "following_count"
        case likesCount = "likes_count", videoCount = "video_count"
    }
}

public struct TikTokVideo: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var createTime: Int64?
    public var title: String?
    public var videoDescription: String?
    public var coverImageURL: URL?
    public var shareURL: URL?
    public var duration: Int?
    public var viewCount: Int64?
    public var likeCount: Int64?
    public var commentCount: Int64?
    public var shareCount: Int64?

    public init(id: String, createTime: Int64? = nil, title: String? = nil,
                videoDescription: String? = nil, coverImageURL: URL? = nil,
                shareURL: URL? = nil, duration: Int? = nil, viewCount: Int64? = nil,
                likeCount: Int64? = nil, commentCount: Int64? = nil, shareCount: Int64? = nil) {
        self.id = id; self.createTime = createTime; self.title = title
        self.videoDescription = videoDescription; self.coverImageURL = coverImageURL
        self.shareURL = shareURL; self.duration = duration; self.viewCount = viewCount
        self.likeCount = likeCount; self.commentCount = commentCount; self.shareCount = shareCount
    }

    public var postedAt: Date? { createTime.map { Date(timeIntervalSince1970: TimeInterval($0)) } }
    public var displayTitle: String {
        [title, videoDescription].compactMap { $0 }.first { !$0.isEmpty } ?? "Untitled video"
    }
    public var interactions: Int64? {
        guard let likes = likeCount, let comments = commentCount, let shares = shareCount else { return nil }
        return likes + comments + shares
    }
    public var engagementRate: Double? {
        guard let views = viewCount, views > 0, let interactions else { return nil }
        return Double(interactions) / Double(views)
    }
    enum CodingKeys: String, CodingKey {
        case id, title, duration
        case createTime = "create_time", videoDescription = "video_description"
        case coverImageURL = "cover_image_url", shareURL = "share_url", viewCount = "view_count"
        case likeCount = "like_count", commentCount = "comment_count", shareCount = "share_count"
    }
}

public struct VideoPage: Decodable, Sendable {
    public var videos: [TikTokVideo]
    public var cursor: Int64?
    public var hasMore: Bool
    public init(videos: [TikTokVideo], cursor: Int64? = nil, hasMore: Bool = false) {
        self.videos = videos; self.cursor = cursor; self.hasMore = hasMore
    }
    enum CodingKeys: String, CodingKey { case videos, cursor, hasMore = "has_more" }
}

public struct AccountObservation: Codable, Equatable, Identifiable, Sendable {
    public var date: Date
    public var followers: Int64?
    public var likes: Int64?
    public var id: Date { date }
    public init(date: Date, followers: Int64?, likes: Int64?) {
        self.date = date; self.followers = followers; self.likes = likes
    }
}

public struct AnalyticsArchive: Codable, Sendable {
    public var profile: TikTokProfile
    public var videos: [TikTokVideo]
    public var observations: [AccountObservation]
    public var updatedAt: Date
    public var cursor: Int64?
    public var hasMore: Bool
    public init(profile: TikTokProfile, videos: [TikTokVideo], observations: [AccountObservation] = [],
                updatedAt: Date = Date(), cursor: Int64? = nil, hasMore: Bool = false) {
        self.profile = profile; self.videos = videos; self.observations = observations
        self.updatedAt = updatedAt; self.cursor = cursor; self.hasMore = hasMore
    }

    public mutating func recordObservation(at date: Date, calendar: Calendar = .current) {
        let day = calendar.startOfDay(for: date)
        observations.removeAll { calendar.startOfDay(for: $0.date) == day }
        observations.append(.init(date: date, followers: profile.followerCount, likes: profile.likesCount))
        observations.sort { $0.date < $1.date }
        observations = Array(observations.suffix(366))
    }
}

public enum SampleData {
    public static func archive(now: Date = Date()) -> AnalyticsArchive {
        let profile = TikTokProfile(openID: "sample-account", displayName: "Poochi & Friends · Sample",
            username: "sample_account", bioDescription: "A sample workspace for exploring your analytics.",
            followerCount: 1280, followingCount: 82, likesCount: 28400, videoCount: 8)
        let titles = ["Poochi discovers the camera", "A very serious afternoon nap", "Friends at the window",
                      "The treat negotiation", "Morning adventures", "The smallest supervisor", "A little mischief", "Together again"]
        let videos = titles.enumerated().map { index, title in
            TikTokVideo(id: "sample-\(index)", createTime: Int64(now.addingTimeInterval(-Double(index + 1) * 86400).timeIntervalSince1970),
                title: title, duration: 18 + index * 3, viewCount: Int64(1200 + (7 - index) * 1120),
                likeCount: Int64(88 + (7 - index) * 70), commentCount: Int64(6 + index * 3), shareCount: Int64(4 + index * 4))
        }
        let observations = (0..<7).map { index in
            AccountObservation(date: now.addingTimeInterval(Double(index - 6) * 86400),
                followers: Int64(1160 + index * 20), likes: Int64(26000 + index * 400))
        }
        return AnalyticsArchive(profile: profile, videos: videos, observations: observations, updatedAt: now)
    }
}
