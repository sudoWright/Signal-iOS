//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import GRDB

/// A convenience wrapper around a disappearing message timer duration value that
/// 1) handles seconds/millis conversion
/// 2) deals internally with the fact that `0` means "not enabled".
///
/// See also ``VersionedDisappearingMessageToken``, which is the same thing but
/// with an attached version that, at time of writing, used by 1:1 conversations (TSContactThread)
/// which are subject to races in setting their DM timer config.
@objc
public final class DisappearingMessageToken: NSObject, NSSecureCoding, NSCopying {
    public static var supportsSecureCoding: Bool { true }

    public init?(coder: NSCoder) {
        self.durationSeconds = coder.decodeObject(of: NSNumber.self, forKey: "durationSeconds")?.uint32Value ?? 0
    }

    public func encode(with coder: NSCoder) {
        coder.encode(NSNumber(value: self.durationSeconds), forKey: "durationSeconds")
    }

    override public var hash: Int {
        var hasher = Hasher()
        hasher.combine(durationSeconds)
        return hasher.finalize()
    }

    override public func isEqual(_ object: Any?) -> Bool {
        guard let object = object as? Self else { return false }
        guard type(of: self) == type(of: object) else { return false }
        guard self.durationSeconds == object.durationSeconds else { return false }
        return true
    }

    public func copy(with zone: NSZone? = nil) -> Any {
        return self
    }

    @objc
    public var isEnabled: Bool {
        return durationSeconds > 0
    }

    public let durationSeconds: UInt32

    @objc
    public init(isEnabled: Bool, durationSeconds: UInt32) {
        // Consider disabled if duration is zero.
        // Use zero duration if not enabled.
        self.durationSeconds = isEnabled ? durationSeconds : 0

        super.init()
    }

    // MARK: -

    public static var disabledToken: DisappearingMessageToken {
        return DisappearingMessageToken(isEnabled: false, durationSeconds: 0)
    }

    public class func token(forProtoExpireTimerSeconds expireTimerSeconds: UInt32?) -> DisappearingMessageToken {
        if let expireTimerSeconds, expireTimerSeconds > 0 {
            return DisappearingMessageToken(isEnabled: true, durationSeconds: expireTimerSeconds)
        } else {
            return .disabledToken
        }
    }
}

// MARK: -

@objc(OWSDisappearingMessagesConfiguration)
public final class DisappearingMessagesConfigurationRecord: NSObject, SDSCodableModel, Decodable, NSSecureCoding, NSCopying {
    public static var databaseTableName: String = "model_OWSDisappearingMessagesConfiguration"
    public static var recordType: UInt = SDSRecordType.disappearingMessagesConfiguration.rawValue

    public var id: Int64?
    public let threadUniqueId: String
    public var uniqueId: String { threadUniqueId }
    public let durationSeconds: UInt32
    public let isEnabled: Bool
    public let timerVersion: UInt32

    public enum CodingKeys: String, CodingKey, ColumnExpression, CaseIterable {
        case id
        case recordType
        case threadUniqueId = "uniqueId"
        case durationSeconds
        case isEnabled = "enabled"
        case timerVersion
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(Int64.self, forKey: .id)
        self.threadUniqueId = try container.decode(String.self, forKey: .threadUniqueId)
        self.durationSeconds = try container.decode(UInt32.self, forKey: .durationSeconds)
        self.isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
        self.timerVersion = try container.decode(UInt32.self, forKey: .timerVersion)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(self.id, forKey: .id)
        try container.encode(Self.recordType, forKey: .recordType)
        try container.encode(self.threadUniqueId, forKey: .threadUniqueId)
        try container.encode(self.durationSeconds, forKey: .durationSeconds)
        try container.encode(self.isEnabled, forKey: .isEnabled)
        try container.encode(self.timerVersion, forKey: .timerVersion)
    }

    public static var supportsSecureCoding: Bool { true }

    public func encode(with coder: NSCoder) {
        if let id {
            coder.encode(NSNumber(value: id), forKey: "grdbId")
        }
        coder.encode(self.threadUniqueId, forKey: "uniqueId")
        coder.encode(NSNumber(value: self.durationSeconds), forKey: "durationSeconds")
        coder.encode(NSNumber(value: self.isEnabled), forKey: "enabled")
        coder.encode(NSNumber(value: self.timerVersion), forKey: "timerVersion")
    }

    public init?(coder: NSCoder) {
        self.id = coder.decodeObject(of: NSNumber.self, forKey: "grdbId")?.int64Value ?? 0
        guard let threadUniqueId = coder.decodeObject(of: NSString.self, forKey: "uniqueId") as String? else {
            return nil
        }
        self.threadUniqueId = threadUniqueId
        self.durationSeconds = coder.decodeObject(of: NSNumber.self, forKey: "durationSeconds")?.uint32Value ?? 0
        self.isEnabled = coder.decodeObject(of: NSNumber.self, forKey: "enabled")?.boolValue ?? false
        self.timerVersion = coder.decodeObject(of: NSNumber.self, forKey: "timerVersion")?.uint32Value ?? 0
    }

    override public var hash: Int {
        var hasher = Hasher()
        hasher.combine(self.id)
        hasher.combine(self.threadUniqueId)
        hasher.combine(self.durationSeconds)
        hasher.combine(self.isEnabled)
        // [Mantle] TODO: It's wrong to include this based on isEqual:'s implementation.
        hasher.combine(self.timerVersion)
        return hasher.finalize()
    }

    override public func isEqual(_ object: Any?) -> Bool {
        guard let object = object as? Self else { return false }
        // [Mantle] TODO: This is wrong because it ignores id & uniqueId.
        guard self.isEnabled == object.isEnabled else { return false }
        // Don't bother comparing durationSeconds if not enabled.
        // [Mantle] TODO: This is wrong because it violates the requirements for hash.
        guard self.isEnabled else { return true }
        guard self.durationSeconds == object.durationSeconds else { return false }
        guard self.timerVersion == object.timerVersion else { return false }
        return true
    }

    public func copy(with zone: NSZone? = nil) -> Any {
        return Self(
            id: self.id,
            threadUniqueId: self.threadUniqueId,
            isEnabled: self.isEnabled,
            durationSeconds: self.durationSeconds,
            timerVersion: self.timerVersion,
        )
    }

    init(
        id: Int64? = nil,
        threadUniqueId: String,
        isEnabled: Bool,
        durationSeconds: UInt32,
        timerVersion: UInt32,
    ) {
        owsAssertDebug(!threadUniqueId.isEmpty)
        self.id = id
        self.threadUniqueId = threadUniqueId
        self.isEnabled = isEnabled
        self.durationSeconds = durationSeconds
        self.timerVersion = timerVersion
    }

    public static func presetDurationsSeconds() -> [UInt32] {
        return [
            UInt32(30 * .second),
            UInt32(5 * .minute),
            UInt32(1 * .hour),
            UInt32(8 * .hour),
            UInt32(24 * .hour),
            UInt32(1 * .week),
            UInt32(4 * .week),
        ]
    }

    public func durationString() -> String {
        return String.formatDurationLossless(durationSeconds: self.durationSeconds)
    }

    public func copyWith(isEnabled: Bool, timerVersion: UInt32) -> Self {
        return Self(
            id: self.id,
            threadUniqueId: self.threadUniqueId,
            isEnabled: isEnabled,
            durationSeconds: isEnabled ? self.durationSeconds : 0,
            timerVersion: timerVersion,
        )
    }

    func copyWith(durationSeconds: UInt32, timerVersion: UInt32) -> Self {
        return Self(
            id: self.id,
            threadUniqueId: self.threadUniqueId,
            isEnabled: self.isEnabled,
            durationSeconds: durationSeconds,
            timerVersion: timerVersion,
        )
    }

    public func copyAsEnabledWith(durationSeconds: UInt32, timerVersion: UInt32) -> Self {
        return Self(
            id: self.id,
            threadUniqueId: self.threadUniqueId,
            isEnabled: true,
            durationSeconds: durationSeconds,
            timerVersion: timerVersion,
        )
    }

    /// Returns true if two configs have the same duration and enabled state, regardless of timer version.
    func hasSameDurationAs(_ other: DisappearingMessagesConfigurationRecord) -> Bool {
        return self.isEnabled == other.isEnabled && self.durationSeconds == other.durationSeconds
    }

    public var asToken: DisappearingMessageToken {
        return DisappearingMessageToken(isEnabled: isEnabled, durationSeconds: durationSeconds)
    }

    public var asVersionedToken: VersionedDisappearingMessageToken {
        return VersionedDisappearingMessageToken(
            isEnabled: isEnabled,
            durationSeconds: durationSeconds,
            version: timerVersion,
        )
    }
}
