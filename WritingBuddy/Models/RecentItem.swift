import Foundation

struct RecentItem: Identifiable, Hashable {
    let id: String
    let title: String
    let when: String
    let preview: String
    let actions: [String]
}

enum Recents {
    static let all: [RecentItem] = [
        RecentItem(id: "r1", title: "Q4 launch plan note",
                   when: "Just now",
                   preview: "Our team has been working on the new dashboard\u{2026}",
                   actions: ["Clean up", "Paragraphs"]),
        RecentItem(id: "r2", title: "Reply to Sarah re: pricing",
                   when: "2h ago",
                   preview: "Thanks for the thoughtful note \u{2014} a few quick reactions\u{2026}",
                   actions: ["Rephrase"]),
        RecentItem(id: "r3", title: "Postmortem section",
                   when: "Yesterday",
                   preview: "On Tuesday afternoon we observed elevated 5xx rates\u{2026}",
                   actions: ["Shorten", "Bullets"]),
        RecentItem(id: "r4", title: "Exec summary, board prep",
                   when: "Apr 28",
                   preview: "Three things to know going into Thursday\u{2026}",
                   actions: ["Expand", "Bullets"]),
        RecentItem(id: "r5", title: "Onboarding email v3",
                   when: "Apr 26",
                   preview: "Welcome to Beacon \u{2014} we built this so that\u{2026}",
                   actions: ["Clean up"]),
    ]
}
