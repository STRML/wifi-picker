import AppKit

enum Metrics {
    static let columns = 3
    static let panelWidth: CGFloat = 750
    static let gridInset: CGFloat = 12
    static let columnSpacing: CGFloat = 6
    static let cellHeight: CGFloat = 30
    static let rowPitch: CGFloat = 34
    static let columnHeaderHeight: CGFloat = 26
    static let gridVerticalInset: CGFloat = 8
    static let headerHeight: CGFloat = 86
    static let footerHeight: CGFloat = 34
    static let separatorHeight: CGFloat = 1
    static let minContentHeight: CGFloat = 176
    static let maxHeightFraction: CGFloat = 0.7
    static let statusItemGap: CGFloat = 4
    static let screenMargin: CGFloat = 8
    static let cornerRadius: CGFloat = 12

    static let scrollerReserve: CGFloat = MainActor.assumeIsolated {
        NSScroller.scrollerWidth(for: .regular, scrollerStyle: .legacy).rounded(.up)
    }

    static var cellWidth: CGFloat {
        let free = panelWidth - 2 * gridInset - scrollerReserve - CGFloat(columns - 1) * columnSpacing
        return (free / CGFloat(columns)).rounded(.down)
    }

    static var chromeHeight: CGFloat {
        headerHeight + footerHeight + 2 * separatorHeight
    }

    static func contentHeight(tallestColumnCount: Int) -> CGFloat {
        2 * gridVerticalInset + columnHeaderHeight + CGFloat(max(1, tallestColumnCount)) * rowPitch
    }

    static func panelHeight(tallestColumnCount: Int, maxHeight: CGFloat) -> CGFloat {
        let maxContent = max(minContentHeight, maxHeight - chromeHeight)
        let content = min(max(contentHeight(tallestColumnCount: tallestColumnCount), minContentHeight), maxContent)
        return chromeHeight + content
    }
}
