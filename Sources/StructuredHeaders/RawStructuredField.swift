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

/// Modified binary search to find the value that is closest and strictly less than the target value
/// The input array must be ordered as monotically increasing, this is ensured by the
/// RawStructuredField initialization.
///
/// - returns: The closest value that is strictly less than the targetValue.
fileprivate func closestValueStrictlyLessThan(_ arr: [Int],_ targetValue: Int) -> (Int, Int) {
    assert(arr.count > 0, "Array must not be empty")

    // If array has only 1 element, that element is the closest
    guard arr.count > 1 else {
         return (0, arr[0])
    }

    // If the targetValue is outside of the range of the array, return the edges of the array
    guard arr.first! <= targetValue else {
        return  (arr.startIndex, arr.first!)
    }
    guard targetValue <= arr.last! else {
        return (arr.endIndex - 1, arr.last!)
    }

    // Perform binary serach on the to find the desired closest target value
    var left = 0
    var right = arr.count - 1

    while left < right {
        if left == right - 1 {
            return targetValue >= arr[right] ? (right, arr[right]) : (left, arr[left])
        }

        let middle = (left + right) / 2
        switch arr[middle] {
        case targetValue:
            return (middle, targetValue)
        case ..<targetValue:
            left = middle
        default:
            right = middle
        }
    }

    fatalError("This line should be unreachable")
}

/// A representation of the raw, unparsed structured field value (Structured Field Values for HTTP,
/// draft-ietf-httpbis-header-structure-latest).
/// Lists, Dictionaries and Strings can have their members split across multiple lines inside a header or trailer
/// section, as per Soection 3.2.2 of [RFC7230]; for example, the following are equivalent:
///
/// Example-Hdr: foo bar
///
/// Example-Hdr: foo
/// Example-Hdr: bar
///
/// This Collection stores the raw, unparsed represention of a *potentially* fragmented StructuredField
/// inserting a defined separator charater. This allows a parser to ensure that a split
/// StructuredField is permissible and also reject SF values where the spec defines such
/// splitting as optional.
struct RawStructuredField {

    /// Elements within the raw, unparsed StructuredField (aka UTF8.CodeUnit aka UInt8)
    /// Note that Unicode is not directly supported in String items due to interoperability concerns.
    typealias Element = String.UTF8View.Element

    enum RawStructuredFieldError : Error {
        /// Thrown if the Structured Field is initialized with an empty array
        case EmptyFieldValue
    }

    /// The Index is in either of these two defined states.
    /// The first - SfFragmentIndex - indictaes that the Index identifies a valid fragment of the
    /// Structured Field and a valid index within the fragment.
    /// The second - SfSeperatorIndex - indicates that the Index identifies the seperator eleement
    /// between fragment
    enum IndexState {
        case SfFragmentIndex
        case SfSeparatorIndex
    }

    /// Index value type abstracting the complexity of indexing across fragments of the Structured Field
    struct Index: Comparable {

        typealias Stride = Array<Element>.Index.Stride

        var fragment: Array<Indices>.Index
        var fragmentIndex: Array<Element>.Index
        var state: IndexState

        init(fragment: Array<Indices>.Index, fragmentIndex: Array<Element>.Index, state: IndexState = IndexState.SfFragmentIndex) {
            self.state = state
            self.fragment = fragment
            self.fragmentIndex = fragmentIndex
        }

        static func < (lhs: Self, rhs: Self) -> Bool {
            return lhs.fragment < rhs.fragment || (lhs.fragment == rhs.fragment && lhs.fragmentIndex < rhs.fragmentIndex)
        }

        static func == (lhs: Self, rhs: Self) -> Bool {
            return lhs.fragment == rhs.fragment && lhs.fragmentIndex == rhs.fragmentIndex && lhs.state == rhs.state
        }
    }

    /// Default separator value output between fragments in a Structured Field
    static let defaultFragmentSeparator: Element = asciiComma | 0x80

    var startIndex: Self.Index
    var endIndex: Self.Index

    var isEmpty: Bool {
        return self.readIndex == self.endIndex
    }

    var count: Int {
        return self.distance(from: self.startIndex, to: self.endIndex)
    }
  
    /// Index of next element (returned by popFirst()/removeFirst()) wihtin the Structured Field 
    var readIndex: Self.Index

    /// One or more fragments of the HTTP StructureField
    var fragments: Array<Array<Element>> = []

    /// Separator value output between fragments of the StructuredField
    let fragmentSeparator: Element

    /// Cummulatitve sum of the fragment indices's upperBound
    var fragmentLowerBounds: Array<Array<Element>.Index> = []

    /// The last fragment
    let lastFragment: Array<Array<Element>>.Index

    /// Construct a new RawStructuredField collection.
    /// 
    /// - thows: If the fragments are an empty array 
    init(fragments: Array<String>, fragmentSeparator: Element = defaultFragmentSeparator) throws {
        guard !fragments.isEmpty else {
            throw RawStructuredFieldError.EmptyFieldValue
        }

        self.fragments.reserveCapacity(fragments.count)
        var cummLowerBound: Array<Element>.Index = 0
        var cummUpperBound: Array<Element>.Index = 0
        for element in fragments {
            let elementAsUtf8 = Array(element.utf8)
            self.fragments.append(elementAsUtf8)

            // Compute the cummlative upper bound and store indexed by fragment
            cummUpperBound += elementAsUtf8.indices.upperBound
            self.fragmentLowerBounds.append(cummLowerBound)
            cummLowerBound = cummUpperBound + 1
            cummUpperBound = cummLowerBound
        }

        self.fragmentSeparator = fragmentSeparator

        // Construct the start index; the index of the first Element in the first fragment
        let firstFragment = self.fragments.startIndex
        let firstFragmentIndex = self.fragments[firstFragment].startIndex
        self.startIndex = Index(fragment: firstFragment, fragmentIndex: firstFragmentIndex)

        // Read from the start of the Collection
        self.readIndex = self.startIndex

        // Construct the start index; the index of the last Element in the last fragment
        self.lastFragment = self.fragments.endIndex - 1
        let lastFragmentIndex = self.fragments[self.lastFragment].endIndex
        self.endIndex = Index(fragment: lastFragment, fragmentIndex: lastFragmentIndex)
    }
}

extension RawStructuredField: Collection, RandomAccessCollection {

    typealias SubSequence = RawStructuredField
    typealias Stride = SignedInteger
        
    fileprivate func checkIndex(index: Self.Index) {
        precondition(index <= self.endIndex, "Index is out of bounds \(index)")
        precondition(index >= self.startIndex, "Negative index is out of bounds \(index)")
    }

    fileprivate func checkSubscript(index: Self.Index) {
        precondition(index < self.endIndex, "Index is out of bounds \(index)")
        precondition(index >= self.startIndex, "Negative index is out of bounds \(index)")
    }

    func index(before: Self.Index) -> Self.Index {
        return self.index(before, offsetBy: -1)
    }

    func index(after: Self.Index) -> Self.Index {
        return self.index(after, offsetBy: 1)
    }

    func index(_ index: Self.Index, offsetBy offset: Int) -> Self.Index {
        // Perform search on fragment bounds to find the fragment; O(k) where k = no. of fragments
        let (offsetFragment, offsetFragmentLowerBound) = closestValueStrictlyLessThan(self.fragmentLowerBounds, self.fragmentLowerBounds[index.fragment] + index.fragmentIndex + offset)
        let offsetFragmentIndex = (self.fragmentLowerBounds[index.fragment] + index.fragmentIndex + offset) - offsetFragmentLowerBound

        // Construct a new Index with the correct state transition
        if offsetFragmentIndex == self.fragments[offsetFragment].endIndex && offsetFragment != self.lastFragment {
            return Index(fragment: offsetFragment, fragmentIndex: offsetFragmentIndex, state: IndexState.SfSeparatorIndex)
        } else {
            if index.state == IndexState.SfSeparatorIndex {
                return Index(fragment: offsetFragment, fragmentIndex: offsetFragmentIndex)
            } else {
                return Index(fragment: offsetFragment, fragmentIndex: offsetFragmentIndex)
            }
        }
    }

    func distance(from: Self.Index, to: Self.Index) -> Int {
        if (to.fragment == from.fragment) {
            return to.fragmentIndex - from.fragmentIndex
        } else {
            return (self.fragmentLowerBounds[to.fragment] + to.fragmentIndex) -
                (self.fragmentLowerBounds[from.fragment] + from.fragmentIndex)
        }
    }

    mutating func popFirst() -> Element? {
        guard !isEmpty else {
            return nil
        }

        return removeFirst()
    }

    mutating func removeFirst() -> Element {
        defer { self.readIndex = self.index(after: readIndex) }
        return self[self.readIndex]
    }

    mutating func removeFirst(_ k: Int) {
        self.readIndex = self.index(self.readIndex, offsetBy: k)
    }

    subscript(position: Self.Index) -> Self.Element {
        checkSubscript(index: position)
        switch (position.state) {
        case IndexState.SfFragmentIndex:
            return self.fragments[position.fragment][position.fragmentIndex]
        case IndexState.SfSeparatorIndex:
            return fragmentSeparator
        }
    }

    subscript(bounds: Range<Self.Index>) -> Self {
        checkIndex(index: bounds.lowerBound)
        checkIndex(index: bounds.upperBound)
        var sf = self
        sf.startIndex = bounds.lowerBound
        sf.readIndex = bounds.lowerBound
        sf.endIndex = bounds.upperBound
        return sf
    }
}

extension RawStructuredField: Equatable {

    static func ==(lhs: RawStructuredField, rhs: RawStructuredField) -> Bool {
        return lhs.count == rhs.count && zip(lhs, rhs).allSatisfy(==)
    }
}

extension RawStructuredField: Hashable {

    func hash(into hasher: inout Hasher) {
        for element in self {
            hasher.combine(element)
        }
    }
}

extension RawStructuredField: CustomStringConvertible {

    var description: String {
        return """
        {
            Count: \(self.count)
            IsEmpty: \(self.isEmpty),
            FieldValue (UTF8): \(Array(self.fragments.joined(separator: [self.fragmentSeparator]))),
            FieldValue (String): \(String(decoding: Array(self.fragments.joined(separator: [self.fragmentSeparator])), as: UTF8.self)),
        }
        """
    }
}

/// Convenience for debugging and testing
extension RawStructuredField: ExpressibleByArrayLiteral {

    init(arrayLiteral elements: String...) {
        try! self.init(fragments: elements)
    }
}
