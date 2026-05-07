import SwiftUI

struct DiffView: View {
    let original: String
    let current: [OutputBlock]?
    let palette: Palette

    var body: some View {
        ScrollView {
            Text(attributed())
                .font(.system(size: 14))
                .lineSpacing(14 * 0.55)
                .foregroundColor(palette.text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .textSelection(.enabled)
        }
    }

    private func attributed() -> AttributedString {
        guard let blocks = current else { return AttributedString("") }
        let currText = MockGenerator.plainText(from: blocks)
        let parts = DiffEngine.diff(original: original, current: currText)

        var out = AttributedString("")
        for part in parts {
            var seg = AttributedString(part.text)
            switch part.op {
            case .equal:
                break
            case .add:
                seg.foregroundColor = palette.diffAddText
                seg.backgroundColor = palette.diffAdd
            case .delete:
                seg.foregroundColor = palette.diffDelText
                seg.backgroundColor = palette.diffDel
                seg.strikethroughStyle = .single
            }
            out.append(seg)
        }
        return out
    }
}
