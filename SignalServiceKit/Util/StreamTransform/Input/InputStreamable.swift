//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public protocol InputStreamable: Streamable {

    // Read up to maxLength bytes from the inpu stream
    func read(maxLength len: Int) throws -> Data

    // Return false if all bytes have been returned and no further
    // data should be expected.
    var hasBytesAvailable: Bool { get }
}

extension InputStream: InputStreamable {
    public func read(maxLength len: Int) throws -> Data {
        if len == 0 {
            return Data()
        }
        var buffer = Data(count: len)
        let bytesRead = buffer.withUnsafeMutableBytes { self.read($0.baseAddress!, maxLength: len) }
        return buffer.prefix(bytesRead)
    }
}
