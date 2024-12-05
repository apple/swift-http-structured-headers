//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftNIO open source project
//
// Copyright (c) 2020-2021 Apple Inc. and the SwiftNIO project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftNIO project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import Foundation
import RawStructuredFieldValues

struct Flags {
    var headerType: HeaderType

    init() {
        // Default to item
        self.headerType = .item
        let arguments = ProcessInfo.processInfo.arguments

        for argument in arguments.dropFirst() {
            switch argument {
            case "--dictionary":
                self.headerType = .dictionary

            case "--list":
                self.headerType = .list

            case "--item":
                self.headerType = .item

            default:
                Self.helpAndExit()
            }
        }
    }

    private static func helpAndExit() -> Never {
        print("Flags:")
        print("")
        print("\t--dictionary: Parse as dictionary field")
        print("\t--list: Parse as list field")
        print("\t--item: Parse as item field (default)")
        exit(2)
    }
}

extension Flags {
    enum HeaderType {
        case dictionary
        case list
        case item
    }
}

enum Header {
    case dictionary(OrderedMap<String, ItemOrInnerList>)
    case list([ItemOrInnerList])
    case item(Item)

    func prettyPrint() {
        switch self {
        case .dictionary(let dict):
            print("- dictionary (\(dict.count) entries):")
            dict.prettyPrint(depth: 1)
        case .list(let list):
            print("- list (\(list.count) entries):")
            list.prettyPrint(depth: 1)
        case .item(let item):
            print("- item:")
            item.prettyPrint(depth: 1)
        }
    }
}

extension Array where Element == ItemOrInnerList {
    func prettyPrint(depth: Int) {
        let tabs = String(repeating: "\t", count: depth)
        for (offset, element) in self.enumerated() {
            print("\(tabs)- [\(offset)]:")
            element.prettyPrint(depth: depth + 1)
        }
    }
}

extension OrderedMap where Key == String, Value == ItemOrInnerList {
    func prettyPrint(depth: Int) {
        let tabs = String(repeating: "\t", count: depth)
        for (key, value) in self {
            print("\(tabs)- \(key):")
            value.prettyPrint(depth: depth + 1)
        }
    }
}

extension OrderedMap where Key == String, Value == RFC9651BareItem {
    func prettyPrint(depth: Int) {
        let tabs = String(repeating: "\t", count: depth)

        for (key, value) in self {
            print("\(tabs)- \(key): \(value.prettyFormat())")
        }
    }
}

extension ItemOrInnerList {
    func prettyPrint(depth: Int) {
        switch self {
        case .item(let item):
            item.prettyPrint(depth: depth)
        case .innerList(let list):
            list.prettyPrint(depth: depth)
        }
    }
}

extension Item {
    func prettyPrint(depth: Int) {
        let tabs = String(repeating: "\t", count: depth)

        print("\(tabs)- item: \(self.rfc9651BareItem.prettyFormat())")
        print("\(tabs)- parameters (\(rfc9651Parameters.count) entries):")
        self.rfc9651Parameters.prettyPrint(depth: depth + 1)
    }
}

extension InnerList {
    func prettyPrint(depth: Int) {
        let tabs = String(repeating: "\t", count: depth)

        print("\(tabs)- innerList (\(rfc9651Parameters.count) entries):")
        self.bareInnerList.prettyPrint(depth: depth + 1)
        print("\(tabs)- parameters (\(rfc9651Parameters.count) entries):")
        self.rfc9651Parameters.prettyPrint(depth: depth + 1)
    }
}

extension BareInnerList {
    func prettyPrint(depth: Int) {
        let tabs = String(repeating: "\t", count: depth)
        for (offset, element) in self.enumerated() {
            print("\(tabs)- [\(offset)]:")
            element.prettyPrint(depth: depth + 1)
        }
    }
}

extension RFC9651BareItem {
    func prettyFormat() -> String {
        switch self {
        case .bool(let bool):
            return "boolean \(bool)"
        case .integer(let int):
            return "integer \(int)"
        case .string(let string):
            return "string \"\(string)\""
        case .token(let token):
            return "token \(token)"
        case .undecodedByteSequence(let bytes):
            return "byte sequence \(bytes)"
        case .decimal(let decimal):
            let d = Decimal(
                sign: decimal.mantissa > 0 ? .plus : .minus,
                exponent: Int(decimal.exponent),
                significand: Decimal(decimal.mantissa)
            )
            return "decimal \(d)"
        case .date(let date):
            return "date \(date)"
        case .displayString(let displayString):
            return "display string \(displayString)"
        }
    }
}

func main() {
    do {
        let flags = Flags()
        var data = FileHandle.standardInput.readDataToEndOfFile()

        // We need to strip trailing newlines.
        var index = data.endIndex
        while index > data.startIndex {
            data.formIndex(before: &index)
            if data[index] != UInt8(ascii: "\n") {
                break
            }
        }
        data = data[...index]
        var parser = StructuredFieldValueParser(data)

        let result: Header
        switch flags.headerType {
        case .dictionary:
            result = .dictionary(try parser.parseDictionaryFieldValue())
        case .list:
            result = .list(try parser.parseListFieldValue())
        case .item:
            result = .item(try parser.parseItemFieldValue())
        }

        result.prettyPrint()
    } catch {
        print("error: \(error)")
        exit(1)
    }
}

main()
