import CoreGraphics

struct ReviewGridPreferences: Equatable, Sendable {
    static let defaultColumns = 4
    static let minimumColumns = 2
    static let maximumColumns = 8

    private(set) var columns: Int

    init(columns: Int = Self.defaultColumns) {
        self.columns = Self.clampedColumns(columns)
    }

    mutating func setColumns(_ columns: Int) {
        self.columns = Self.clampedColumns(columns)
    }

    static func clampedColumns(_ columns: Int) -> Int {
        min(max(columns, minimumColumns), maximumColumns)
    }

    static func imageHeight(forColumns columns: Int) -> CGFloat {
        switch clampedColumns(columns) {
        case 2:
            return 340
        case 3:
            return 290
        case 4:
            return 250
        case 5...6:
            return 190
        default:
            return 150
        }
    }
}
