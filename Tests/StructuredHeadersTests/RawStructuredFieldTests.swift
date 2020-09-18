//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftNIO open source project
//
// Copyright (c) 2020 Apple Inc. and the SwiftNIO project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftNIO project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

@testable import StructuredHeaders
import XCTest

let asciiSpace = UInt8(ascii: " ")
let asciiTab = UInt8(ascii: "\t")

// Mimic StructuredFiedlParser for testing purposes
extension RandomAccessCollection where Element == UInt8, SubSequence == Self {
    mutating func stripLeadingSpaces() {
        self = drop(while: { $0 == asciiSpace })
    }

    mutating func stripLeadingOWS() {
        self = drop(while: { $0 == asciiSpace || $0 == asciiTab })
    }

    mutating func consumeFirst() {
        self = dropFirst()
    }
}

extension Character {
    func unicodeScalarCodePoint() -> UInt32 {
        let characterString = String(self)
        let scalars = characterString.unicodeScalars
        return scalars[scalars.startIndex].value
    }
}

final class RawStructuredFieldTests: XCTestCase {
    func testSfConstruction() {
        let sf: RawStructuredField = ["test"]
        XCTAssertNotNil(sf)
    }

    func testFragmentedSfConstruction() {
        let sf: RawStructuredField = ["test", "hello", "a"]
        XCTAssertNotNil(sf)
    }

    func testEmptySfConstruction() {
        do {
            _ = try RawStructuredField(fragments: [])
        } catch {
            XCTAssertTrue(true)
        }
    }

    func testEquivalentSf() {
        let fieldValue = "TestSf"
        let sf1: RawStructuredField = [fieldValue]
        let sf2: RawStructuredField = [fieldValue]
        XCTAssertTrue(sf1 == sf2)
    }

    func testEquivalentFragmentedSf() {
        let sf1: RawStructuredField = ["TestSf1,TestSf2,TestSf3"]
        let sf2 = try! RawStructuredField(fragments: ["TestSf1", "TestSf2", "TestSf3"], fragmentSeparator: UInt8(Character(",").unicodeScalarCodePoint()))
        XCTAssertTrue(sf1 == sf2)
    }

    func testNonEquivalentSf() {
        let sf1: RawStructuredField = ["sf1"]
        let sf2: RawStructuredField = ["sf2"]
        XCTAssertFalse(sf1 == sf2)
    }

    func testNonEquivalentFragmentedSf() {
        let sf1: RawStructuredField = ["sf1", "test"]
        let sf2: RawStructuredField = ["sf2", "example"]
        XCTAssertFalse(sf1 == sf2)
    }

    func testHashEquivalentSf() {
        let sf1: RawStructuredField = ["TestSf"]
        let sf2: RawStructuredField = ["TestSf"]
        var sf1Hasher = Hasher()
        sf1.hash(into: &sf1Hasher)
        var sf2Hasher = Hasher()
        sf2.hash(into: &sf2Hasher)
        XCTAssertTrue(sf1 == sf2)
        XCTAssertTrue(sf1Hasher.finalize() == sf2Hasher.finalize())
    }

    func testHashEquivalentFragmentedSf() {
        let sf1: RawStructuredField = ["TestSf1,TestSf2"]
        let sf2 = try! RawStructuredField(fragments: ["TestSf1", "TestSf2"], fragmentSeparator: UInt8(Character(",").unicodeScalarCodePoint()))
        var sf1Hasher = Hasher()
        sf1.hash(into: &sf1Hasher)
        var sf2Hasher = Hasher()
        sf2.hash(into: &sf2Hasher)
        XCTAssertTrue(sf1 == sf2)
        XCTAssertTrue(sf1Hasher.finalize() == sf2Hasher.finalize())
    }

    func testHashNonEquivalentSf() {
        let sf1: RawStructuredField = ["TestSf1"]
        let sf2: RawStructuredField = ["TestSf2"]
        var sf1Hasher = Hasher()
        sf1.hash(into: &sf1Hasher)
        var sf2Hasher = Hasher()
        sf2.hash(into: &sf2Hasher)
        XCTAssertFalse(sf1 == sf2)
        XCTAssertFalse(sf1Hasher.finalize() == sf2Hasher.finalize())
    }

    func testHashNonEquivalentFragmentedSf() {
        let sf1: RawStructuredField = ["Test", "Sf1"]
        let sf2: RawStructuredField = ["Test", "Sf2"]
        var sf1Hasher = Hasher()
        sf1.hash(into: &sf1Hasher)
        var sf2Hasher = Hasher()
        sf2.hash(into: &sf2Hasher)
        XCTAssertFalse(sf1 == sf2)
        XCTAssertFalse(sf1Hasher.finalize() == sf2Hasher.finalize())
    }

    func testSfDistance() {
        var sf: RawStructuredField = ["TestSf1"]
        let sIdx = sf.startIndex
        let eIdx = sf.endIndex
        XCTAssertEqual(sf.distance(from: sIdx, to: sIdx), 0)
        XCTAssertEqual(sf.distance(from: sIdx, to: eIdx), sf.count)
        for _ in 0 ..< 5 {
            _ = sf.popFirst()
        }
        let rIdx = sf.readIndex
        XCTAssertEqual(sf.distance(from: sIdx, to: rIdx), 5)
        XCTAssertEqual(sf.distance(from: rIdx, to: sIdx), -5)
        XCTAssertEqual(sf.distance(from: rIdx, to: eIdx), sf.count - 5)
    }

    func testFragmentedSfDistance() {
        var sf: RawStructuredField = ["test", "hello", "a"]
        let sIdx = sf.startIndex
        let eIdx = sf.endIndex
        XCTAssertEqual(sf.distance(from: sIdx, to: sIdx), 0)
        XCTAssertEqual(sf.distance(from: sIdx, to: eIdx), sf.count)
        for _ in 0 ..< 10 {
            _ = sf.popFirst()
        }
        let rIdx = sf.readIndex
        XCTAssertEqual(sf.distance(from: sIdx, to: rIdx), 10)
        XCTAssertEqual(sf.distance(from: rIdx, to: sIdx), -10)
        XCTAssertEqual(sf.distance(from: rIdx, to: eIdx), sf.count - 10)
    }

    func testSfIndex() {
        let sf: RawStructuredField = ["TestSf1"]
        let sIdx = sf.startIndex
        let aIdx = sf.index(sIdx, offsetBy: 4)
        XCTAssertEqual(sf.distance(from: sIdx, to: aIdx), 4)
        let bIdx = sf.index(aIdx, offsetBy: -2)
        XCTAssertEqual(sf.distance(from: aIdx, to: bIdx), -2)
        XCTAssertEqual(sf.distance(from: sIdx, to: bIdx), 2)
    }

    func testFragmentedSfIndex() {
        let sf: RawStructuredField = ["test", "hello", "a"]
        let sIdx = sf.startIndex
        let aIdx = sf.index(sIdx, offsetBy: 7)
        XCTAssertEqual(sf.distance(from: sIdx, to: aIdx), 7)
        let bIdx = sf.index(aIdx, offsetBy: -2)
        XCTAssertEqual(sf.distance(from: aIdx, to: bIdx), -2)
        XCTAssertEqual(sf.distance(from: sIdx, to: bIdx), 5)
    }

    func testRemoveFirstSf() {
        let exampleSf = "test"
        var sf: RawStructuredField = [exampleSf]
        XCTAssertFalse(sf.isEmpty)
        XCTAssertEqual(sf.count, exampleSf.count)
        for element in exampleSf.utf8 {
            XCTAssertEqual(sf.removeFirst(), element)
        }
        XCTAssertTrue(sf.isEmpty)
    }

    func testRemoveFirstNSf() {
        let exampleSf = "test"
        var sf: RawStructuredField = [exampleSf]
        XCTAssertFalse(sf.isEmpty)
        XCTAssertEqual(sf.count, exampleSf.count)
        sf.removeFirst(2)
        for element in exampleSf.utf8.dropFirst(2) {
            XCTAssertEqual(sf.removeFirst(), element)
        }
        XCTAssertTrue(sf.isEmpty)
    }

    func testRemoveFirstOneCharSf() {
        let exampleSf = "a"
        var sf: RawStructuredField = [exampleSf]
        XCTAssertFalse(sf.isEmpty)
        XCTAssertEqual(sf.count, exampleSf.count)
        for element in exampleSf.utf8 {
            XCTAssertEqual(sf.removeFirst(), element)
        }
        XCTAssertTrue(sf.isEmpty)
    }

    func testRemoveFirstLargeSf() {
        let exampleSf = String(repeating: "a", count: 4096)
        var sf: RawStructuredField = [exampleSf]
        XCTAssertFalse(sf.isEmpty)
        XCTAssertEqual(sf.count, exampleSf.count)
        for element in exampleSf.utf8 {
            XCTAssertEqual(sf.removeFirst(), element)
        }
        XCTAssertTrue(sf.isEmpty)
    }

    func testRemoveFirstFragmentedSf() {
        let exampleSf1 = "example"
        let exampleSf2 = "test"
        var sf: RawStructuredField = [exampleSf1, exampleSf2]
        XCTAssertFalse(sf.isEmpty)
        XCTAssertEqual(sf.count, exampleSf1.count + exampleSf2.count + 1)
        for element in exampleSf1.utf8 {
            XCTAssertEqual(sf.removeFirst(), element)
        }
        XCTAssertFalse(sf.isEmpty)
        XCTAssertEqual(sf.removeFirst(), RawStructuredField.defaultFragmentSeparator)
        XCTAssertFalse(sf.isEmpty)
        for element in exampleSf2.utf8 {
            XCTAssertEqual(sf.removeFirst(), element)
        }
        XCTAssertTrue(sf.isEmpty)
    }

    func testRemoveFirstNFragmentedSf() {
        let exampleSf1 = "example"
        let exampleSf2 = "test"
        var sf: RawStructuredField = [exampleSf1, exampleSf2]
        XCTAssertFalse(sf.isEmpty)
        XCTAssertEqual(sf.count, exampleSf1.count + exampleSf2.count + 1)
        sf.removeFirst(4)
        for element in exampleSf1.utf8.dropFirst(4) {
            XCTAssertEqual(sf.removeFirst(), element)
        }
        XCTAssertFalse(sf.isEmpty)
        XCTAssertEqual(sf.removeFirst(), RawStructuredField.defaultFragmentSeparator)
        XCTAssertFalse(sf.isEmpty)
        for element in exampleSf2.utf8 {
            XCTAssertEqual(sf.removeFirst(), element)
        }
        XCTAssertTrue(sf.isEmpty)
    }

    func testRemoveFirstOneCharFragmentSf() {
        let exampleSf1 = "a"
        let exampleSf2 = "b"
        var sf: RawStructuredField = [exampleSf1, exampleSf2]
        XCTAssertFalse(sf.isEmpty)
        XCTAssertEqual(sf.count, exampleSf1.count + exampleSf2.count + 1)
        for element in exampleSf1.utf8 {
            XCTAssertEqual(sf.removeFirst(), element)
        }
        XCTAssertFalse(sf.isEmpty)
        XCTAssertEqual(sf.removeFirst(), RawStructuredField.defaultFragmentSeparator)
        XCTAssertFalse(sf.isEmpty)
        for element in exampleSf2.utf8 {
            XCTAssertEqual(sf.removeFirst(), element)
        }
        XCTAssertTrue(sf.isEmpty)
    }

    func testRemoveFirstSfLeadingWhitespace() {
        let exampleSf = "test"
        let exampleSfLeadingWs = "    " + exampleSf
        var sf: RawStructuredField = [exampleSfLeadingWs]
        sf.stripLeadingSpaces()
        XCTAssertFalse(sf.isEmpty)
        XCTAssertEqual(sf.count, exampleSf.count)
        for element in exampleSf.utf8 {
            XCTAssertEqual(sf.removeFirst(), element)
        }
        XCTAssertTrue(sf.isEmpty)
    }

    func testRemoveFirstSfLeadingOWS() {
        let exampleSf = "test"
        let exampleSfLeadingWs = "\t    \t" + exampleSf
        var sf: RawStructuredField = [exampleSfLeadingWs]
        sf.stripLeadingOWS()
        XCTAssertFalse(sf.isEmpty)
        XCTAssertEqual(sf.count, exampleSf.count)
        for element in exampleSf.utf8 {
            XCTAssertEqual(sf.removeFirst(), element)
        }
        XCTAssertTrue(sf.isEmpty)
    }

    func testPopFirstSf() {
        let exampleSf = "test"
        var sf: RawStructuredField = [exampleSf]
        XCTAssertFalse(sf.isEmpty)
        XCTAssertEqual(sf.count, exampleSf.count)
        for element in exampleSf.utf8 {
            XCTAssertEqual(sf.popFirst(), element)
        }
        XCTAssertTrue(sf.isEmpty)
        XCTAssertNil(sf.popFirst())
    }

    func testPopFirstFragmentedSf() {
        let exampleSf1 = "example"
        let exampleSf2 = "test"
        var sf: RawStructuredField = [exampleSf1, exampleSf2]
        XCTAssertFalse(sf.isEmpty)
        XCTAssertEqual(sf.count, exampleSf1.count + exampleSf2.count + 1)
        for element in exampleSf1.utf8 {
            XCTAssertEqual(sf.popFirst(), element)
        }
        XCTAssertFalse(sf.isEmpty)
        XCTAssertEqual(sf.removeFirst(), RawStructuredField.defaultFragmentSeparator)
        XCTAssertFalse(sf.isEmpty)
        for element in exampleSf2.utf8 {
            XCTAssertEqual(sf.popFirst(), element)
        }
        XCTAssertTrue(sf.isEmpty)
    }

    static var allTests = [
        ("Test construction of a non-fragmented Structured Field", testSfConstruction),
        ("Test construction of a fragmented Structured Field", testFragmentedSfConstruction),
        ("Test construction of an empty Structured Field", testEmptySfConstruction),
        ("Test equivalence of non-fragmentwd  Structured Fields", testEquivalentSf),
        ("Test equivalence of fragmented Structured Fields", testEquivalentFragmentedSf),
        ("Test non-equivalence of non-fragmented Structured Field", testNonEquivalentSf),
        ("Test non-equivalence of fragmented Structured Field", testNonEquivalentFragmentedSf),
        ("Test hash equivalence of non-fragmented Structured Field", testHashEquivalentSf),
        ("Test hash equivalence of fragmented Structured Field", testHashEquivalentFragmentedSf),
        ("Test hash non-equivalence of non-fragmented Structured Field", testHashNonEquivalentSf),
        ("Test hash non-equivalence of fragmented Structured Field", testHashNonEquivalentFragmentedSf),
        ("Test distance() on non-fragmented Structured Field", testSfDistance),
        ("Test distance() on fragmented Structured Field", testFragmentedSfDistance),
        ("Test index() on non-fragmented Structured Field", testSfIndex),
        ("Test index() on fragmented Structured Field", testFragmentedSfIndex),
        ("Test removeFirst() on non-fragmented Structured Field", testRemoveFirstSf),
        ("Test removeFirst(n) on non-fragmented Structured Field", testRemoveFirstNSf),
        ("Test removeFirst() on non-fragmented, one-character Structured Field", testRemoveFirstOneCharSf),
        ("Test removeFirst() on non-fragmented, large Structured Field", testRemoveFirstLargeSf),
        ("Test removeFirst() on fragmented Structured Field", testRemoveFirstFragmentedSf),
        ("Test removeFirst(n) on fragmented Structured Field", testRemoveFirstNFragmentedSf),
        ("Test removeFirst() on fragmented, one-character Structured Field", testRemoveFirstOneCharFragmentSf),
        ("Test removeFirst() on non-fragmented Structured Field with leading OWS (spaces)", testRemoveFirstSfLeadingWhitespace),
        ("Test removeFirst() on fragmented Structured Field with leading OWS (tabs+spaces)", testRemoveFirstSfLeadingOWS),
        ("Test popFirst() on non-fragmented Structured Field", testRemoveFirstSf),
    ]
}
