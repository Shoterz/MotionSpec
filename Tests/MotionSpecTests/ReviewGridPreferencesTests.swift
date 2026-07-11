import Testing
@testable import MotionSpec

@Suite
struct ReviewGridPreferencesTests {
    @Test("Grid column preferences clamp to readable thumbnail counts")
    func gridColumnsClampToReadableRange() {
        var preferences = ReviewGridPreferences()

        preferences.setColumns(1)
        #expect(preferences.columns == 2)

        preferences.setColumns(4)
        #expect(preferences.columns == 4)

        preferences.setColumns(12)
        #expect(preferences.columns == 8)
    }
}
