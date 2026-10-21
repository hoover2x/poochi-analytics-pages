import Foundation

public enum VideoSort: String, CaseIterable, Identifiable {
    case newest = "Newest", views = "Views", engagement = "Engagement", likes = "Likes"
    public var id: Self { self }
    public func sorted(_ videos: [TikTokVideo]) -> [TikTokVideo] {
        videos.sorted { left, right in
            switch self {
            case .newest: return (left.createTime ?? 0) > (right.createTime ?? 0)
            case .views: return (left.viewCount ?? -1) > (right.viewCount ?? -1)
            case .likes: return (left.likeCount ?? -1) > (right.likeCount ?? -1)
            case .engagement: return (left.engagementRate ?? -1) > (right.engagementRate ?? -1)
            }
        }
    }
}

public struct VideoSummary {
    public var videoCount: Int
    public var views: Int64?
    public var interactions: Int64?
    public var engagementRate: Double? {
        guard let views, views > 0, let interactions else { return nil }
        return Double(interactions) / Double(views)
    }
    public init(videos: [TikTokVideo]) {
        videoCount = videos.count
        views = Self.completeSum(videos.map(\.viewCount))
        interactions = Self.completeSum(videos.map(\.interactions))
    }
    private static func completeSum(_ values: [Int64?]) -> Int64? {
        guard !values.isEmpty, values.allSatisfy({ $0 != nil }) else { return nil }
        return values.compactMap { $0 }.reduce(0, +)
    }
}

public enum CSVExport {
    public static func videos(_ videos: [TikTokVideo], observedAt: Date) -> String {
        let iso = ISO8601DateFormatter()
        let header = "video_id,title,posted_at,views,likes,comments,shares,engagement_rate,video_url,observed_at"
        let rows: [String] = videos.map { video -> String in
            var fields: [String] = [video.id, video.displayTitle]
            fields.append(video.postedAt.map { iso.string(from: $0) } ?? "")
            fields.append(video.viewCount.map { String($0) } ?? "")
            fields.append(video.likeCount.map { String($0) } ?? "")
            fields.append(video.commentCount.map { String($0) } ?? "")
            fields.append(video.shareCount.map { String($0) } ?? "")
            let rate: String = video.engagementRate.map { value in
                String(format: "%.6f", locale: Locale(identifier: "en_US_POSIX"), value)
            } ?? ""
            fields.append(rate)
            fields.append(video.shareURL?.absoluteString ?? "")
            fields.append(iso.string(from: observedAt))
            return fields.map { escape($0) }.joined(separator: ",")
        }
        return ([header] + rows).joined(separator: "\r\n") + "\r\n"
    }
    public static func escape(_ value: String) -> String {
        // Spreadsheet apps may interpret creator-supplied titles as formulas.
        let first = value.drop(while: { $0.isWhitespace }).first
        let safe = first.map { "=+-@".contains($0) } == true ? "'" + value : value
        return "\"" + safe.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
