import XCTest
import SwiftTreeSitter
import TreeSitterHemar

final class TreeSitterHemarTests: XCTestCase {
    func testCanLoadGrammar() throws {
        let parser = Parser()
        let language = Language(language: tree_sitter_hemar())
        XCTAssertNoThrow(try parser.setLanguage(language),
                         "Error loading Hemar grammar")
    }
}
