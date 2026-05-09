import Foundation

enum MockGenerator {
    static let sampleInput = "our team has been working on the new dashboard for several weeks now and i think we're finally getting somewhere. the engineering side is mostly done but design is still iterating on a few things. we should probably ship a beta to a small group of customers next week to gather feedback before the full launch. let me know what you think and if there are any blockers i should know about."

    static func generate(input: String,
                         operation: Operation,
                         mode: WritingMode = .writing,
                         fmts: Set<OutputFormat>,
                         containerFormat: OutputContainerFormat = .markdown,
                         model: AIModel) -> [OutputBlock] {
        guard !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return []
        }

        let wantBullets = fmts.contains(.bullets)
        let wantTable   = fmts.contains(.tables)
        let wantParas   = fmts.contains(.paragraphs) || (!wantBullets && !wantTable)

        let cleaned = "Our team has been heads-down on the new dashboard for several weeks, and we're finally hitting a stride. Engineering is largely complete; design is still iterating on a handful of details. I'd like to ship a closed beta to a small cohort of customers next week so we can gather feedback before the full launch. Let me know your read \u{2014} and flag any blockers I should be tracking."

        let expanded = cleaned + " Specifically, the beta would cover the redesigned activity feed, the new filter rail, and the saved-views feature. We'd target roughly 25 accounts across our three core segments and run it for five business days before deciding on go/no-go for GA."

        let shortened = "Dashboard's nearly there \u{2014} eng is done, design is finishing details. Proposing a closed beta next week before GA. Flag any blockers."

        let rephrased = "Quick update on the dashboard: after several weeks of focused work, we're close. Engineering has wrapped most of its scope while design refines a few remaining details. My recommendation is to roll out a small customer beta next week, gather feedback, then green-light the broader launch. Happy to address any blockers you've spotted."

        var body = cleaned
        if mode == .writing, let writingOp = operation as? WritingOp {
            switch writingOp {
            case .expand:   body = expanded
            case .shorten:  body = shortened
            case .rephrase: body = rephrased
            case .cleanup:  body = cleaned
            }
        } else if mode == .chat, let chatOp = operation as? ChatOp {
            body = chatStub(for: chatOp, input: input)
        }

        var out: [OutputBlock] = []
        if wantParas {
            out.append(.paragraph(text: containerFormat == .slack ? slackifyInline(body) : body))
        }

        if wantBullets {
            out.append(.heading(text: "Key points"))
            out.append(.bulletList(items: [
                containerFormat == .slack ? "*Engineering* is largely complete; design is finalizing details." : "Engineering is largely complete; design is finalizing details.",
                "Closed beta proposed for next week with ~25 customers.",
                "Beta covers activity feed, filter rail, and saved views.",
                "Five-day window, then go/no-go on GA.",
            ]))
        }

        if wantTable {
            out.append(.heading(text: "Status by workstream"))
            out.append(.table(
                head: ["Workstream", "Owner", "Status", "Risk"],
                rows: [
                    ["Engineering", "Priya",  "Code complete",       "Low"],
                    ["Design",      "Marcus", "Polish in flight",    "Low"],
                    ["Beta cohort", "Jen",    "18 / 25 confirmed",   "Med"],
                    ["Docs & FAQ",  "Theo",   "Drafting",            "Med"],
                ]
            ))
        }

        return out
    }

    private static func slackifyInline(_ text: String) -> String {
        text.replacingOccurrences(of: "Dashboard", with: "*Dashboard*")
    }

    private static func chatStub(for op: ChatOp, input: String) -> String {
        switch op {
        case .ask:
            return "Here's a quick answer based on what you asked. (Mock response — wire up an API key for live answers.)"
        case .plan:
            return "Here's a rough plan: (1) define the scope, (2) draft the steps, (3) identify owners, (4) set checkpoints, (5) review and ship. (Mock response.)"
        case .summarize:
            return "Summary: the input describes a piece of work, its current status, and what's needed next. (Mock response.)"
        case .compare:
            return "Tradeoffs: option A is faster to ship; option B is more flexible long-term. Default to A unless flexibility is load-bearing. (Mock response.)"
        case .translate:
            return "[Translated text would appear here. Specify a target language in the input or context.]"
        }
    }

    /// Flatten output blocks to plain text (used by diff view).
    static func plainText(from blocks: [OutputBlock]) -> String {
        blocks.map { block -> String in
            switch block {
            case .paragraph(let t):    return t
            case .heading:             return ""
            case .bulletList(let it):  return it.joined(separator: " ")
            case .table(_, let rows):  return rows.flatMap { $0 }.joined(separator: " ")
            case .codeBlock(_, let c): return c
            case .toolCall:            return ""
            case .toolResult(_, let content, _): return content
            case .unknown:             return ""
            }
        }.joined(separator: " ")
    }
}
