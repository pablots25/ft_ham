//
//  FreeTextMessageTests.swift
//  ft8_hamTests
//
//  Created by Pablo Turrion on 11/09/26.
//

import XCTest
@testable import ft8_ham

final class FreeTextMessageTests: XCTestCase {

    // MARK: - sanitize

    func test_sanitize_uppercasesAndKeepsAlphabet() {
        XCTAssertEqual(FreeTextMessage.sanitize("hello world"), "HELLO WORLD")
        XCTAssertEqual(FreeTextMessage.sanitize("73 de ea4iql"), "73 DE EA4IQL")
        XCTAssertEqual(FreeTextMessage.sanitize("+-./?"), "+-./?")
    }

    func test_sanitize_dropsCharactersOutsideAlphabet() {
        XCTAssertEqual(FreeTextMessage.sanitize("¡hóla! ñ_#@"), "HLA")
        XCTAssertEqual(FreeTextMessage.sanitize("😀 QRT 😀"), "QRT")
    }

    func test_sanitize_collapsesAndTrimsSpaces() {
        XCTAssertEqual(FreeTextMessage.sanitize("   TNX   QSO   "), "TNX QSO")
        XCTAssertEqual(FreeTextMessage.sanitize("     "), "")
    }

    func test_sanitize_truncatesTo13() {
        XCTAssertEqual(FreeTextMessage.sanitize("ABCDEFGHIJKLMNOPQ"), "ABCDEFGHIJKLM")
        // Cutting "ABCDEFGHIJKL Z" at 13 leaves a trailing space, which is trimmed.
        XCTAssertEqual(FreeTextMessage.sanitize("ABCDEFGHIJKL Z"), "ABCDEFGHIJKL")
        XCTAssertEqual(FreeTextMessage.sanitize("ABCDEFGHIJKL  Z"), "ABCDEFGHIJKL")
        XCTAssertEqual(FreeTextMessage.sanitize("ABCDEFGHIJK ZZ"), "ABCDEFGHIJK Z")
    }

    // MARK: - validate

    func test_validate_acceptsGoodText() {
        XCTAssertEqual(FreeTextMessage.validate("TNX 73 GL"), .success("TNX 73 GL"))
        XCTAssertEqual(FreeTextMessage.validate("ABCDEFGHIJKLM"), .success("ABCDEFGHIJKLM"))
    }

    func test_validate_rejectsEmptyTooLongAndBadCharacters() {
        XCTAssertEqual(FreeTextMessage.validate(""), .failure(.empty))
        XCTAssertEqual(FreeTextMessage.validate("ABCDEFGHIJKLMN"), .failure(.tooLong))
        XCTAssertEqual(FreeTextMessage.validate("hello"), .failure(.invalidCharacter("h")))
        XCTAssertEqual(FreeTextMessage.validate("A,B"), .failure(.invalidCharacter(",")))
    }
}
