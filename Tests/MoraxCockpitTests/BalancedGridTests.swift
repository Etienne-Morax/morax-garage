import Foundation
import Testing
@testable import MoraxCockpitKit

struct BalancedGridTests {
    @Test("an odd card out takes a full-width row instead of a half-empty column")
    func oddCardGetsItsOwnRow() {
        #expect(BalancedGrid.rowSizes(itemCount: 3, columns: 2) == [2, 1])
    }

    @Test("six dials split into balanced rows for every column count")
    func sixDialsStayBalanced() {
        #expect(BalancedGrid.rowSizes(itemCount: 6, columns: 6) == [6])
        #expect(BalancedGrid.rowSizes(itemCount: 6, columns: 5) == [3, 3])
        #expect(BalancedGrid.rowSizes(itemCount: 6, columns: 4) == [3, 3])
        #expect(BalancedGrid.rowSizes(itemCount: 6, columns: 2) == [2, 2, 2])
    }

    @Test("rows never exceed the column count and cover every item")
    func rowsCoverAllItems() {
        for itemCount in 1...12 {
            for columns in 1...6 {
                let rows = BalancedGrid.rowSizes(itemCount: itemCount, columns: columns)
                #expect(rows.reduce(0, +) == itemCount)
                #expect(rows.allSatisfy { $0 >= 1 && $0 <= columns })
            }
        }
    }

    @Test("returns no rows when there is nothing to lay out")
    func emptyGrid() {
        #expect(BalancedGrid.rowSizes(itemCount: 0, columns: 3).isEmpty)
    }

    @Test("column count follows the available width and its caps")
    func columnCountFollowsWidth() {
        let grid = BalancedGrid(minItemWidth: 100, maxColumns: 6, spacing: 10)
        #expect(grid.columnCount(for: 50, itemCount: 6) == 1)
        #expect(grid.columnCount(for: 300, itemCount: 6) == 2)
        #expect(grid.columnCount(for: 10_000, itemCount: 6) == 6)
        #expect(grid.columnCount(for: 10_000, itemCount: 2) == 2)
    }
}
