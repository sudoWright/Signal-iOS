//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB

public struct RowIdAndDate: Codable, FetchableRecord {
    public var rowid: Int64
    public var receivedAtTimestamp: UInt64 // timestamp in milliseconds

    public var date: Date {
        return Date(millisecondsSince1970: receivedAtTimestamp)
    }

    public init(rowid: Int64, receivedAtTimestamp: UInt64) {
        self.rowid = rowid
        self.receivedAtTimestamp = receivedAtTimestamp
    }
}

@objc
public final class MediaGalleryManager: NSObject {
    public static func setup(database: GRDB.Database) {
        database.add(function: isVisualMediaContentTypeDatabaseFunction)
    }

    public static let isVisualMediaContentTypeDatabaseFunction = DatabaseFunction("IsVisualMediaContentType") { (args: [DatabaseValue]) -> DatabaseValueConvertible? in
        guard let contentType = String.fromDatabaseValue(args[0]) else {
            throw OWSAssertionError("unexpected arguments: \(args)")
        }

        return MIMETypeUtil.isVisualMedia(contentType)
    }

    private class func removeAnyGalleryRecord(attachmentStream: TSAttachmentStream, transaction: GRDBWriteTransaction) throws -> MediaGalleryRecord? {
        let sql = """
            DELETE FROM \(MediaGalleryRecord.databaseTableName) WHERE attachmentId = ? RETURNING *
        """
        guard let attachmentId = attachmentStream.grdbId else {
            owsFailDebug("attachmentId was unexpectedly nil")
            return nil
        }

        guard attachmentStream.albumMessageId != nil else {
            Logger.verbose("not a gallery attachment")
            return nil
        }

        return try MediaGalleryRecord.fetchOne(transaction.database, sql: sql, arguments: [attachmentId.int64Value])
    }

    public class func insertGalleryRecord(attachmentStream: TSAttachmentStream,
                                          transaction: GRDBWriteTransaction) throws {
        _ = try insertGalleryRecordPrivate(attachmentStream: attachmentStream, transaction: transaction)
    }

    private class func insertGalleryRecordPrivate(attachmentStream: TSAttachmentStream,
                                                  transaction: GRDBWriteTransaction) throws -> MediaGalleryRecord? {
        guard let attachmentRowId = attachmentStream.grdbId else {
            throw OWSAssertionError("attachmentRowId was unexpectedly nil")
        }

        guard let messageUniqueId = attachmentStream.albumMessageId else {
            Logger.verbose("not a gallery attachment")
            return nil
        }

        guard let message = TSMessage.anyFetchMessage(uniqueId: messageUniqueId, transaction: transaction.asAnyRead) else {
            owsFailDebug("message was unexpectedly nil")
            return nil
        }

        guard let messageRowId = message.grdbId else {
            owsFailDebug("message was unexpectedly nil")
            return nil
        }

        let thread = message.thread(transaction: transaction.asAnyRead)
        guard let threadId = thread.grdbId else {
            owsFailDebug("threadId was unexpectedly nil")
            return nil
        }

        guard let originalAlbumIndex = message.attachmentIds.firstIndex(of: attachmentStream.uniqueId) else {
            owsFailDebug("originalAlbumIndex was unexpectedly nil")
            return nil
        }

        let galleryRecord = MediaGalleryRecord(attachmentId: attachmentRowId.int64Value,
                                               albumMessageId: messageRowId.int64Value,
                                               threadId: threadId.int64Value,
                                               originalAlbumOrder: originalAlbumIndex)

        try galleryRecord.insert(transaction.database)

        return galleryRecord
    }

    public class func removeAllGalleryRecords(transaction: GRDBWriteTransaction) throws {
        try MediaGalleryRecord.deleteAll(transaction.database)
    }

    public struct ChangedAttachmentInfo {
        public var uniqueId: String
        public var threadGrdbId: Int64
        public var timestamp: UInt64
    }

    /// A notification for when an attachment stream becomes available (incoming attachment downloaded, or outgoing
    /// attachment loaded).
    ///
    /// The object of the notification is an array of ChangedAttachmentInfo values.
    /// When registering an observer for this notification, set the observed object to `nil`, meaning no filter.
    public static let newAttachmentsAvailableNotification =
        Notification.Name(rawValue: "SSKMediaGalleryFinderNewAttachmentsAvailable")

    private static let recentlyChangedMessageTimestampsByRowId = AtomicDictionary<Int64, UInt64>()
    private static let recentlyInsertedAttachments = AtomicArray<ChangedAttachmentInfo>()
    private static let recentlyRemovedAttachments = AtomicArray<ChangedAttachmentInfo>()

    @objc(didInsertAttachmentStream:transaction:)
    public class func didInsert(attachmentStream: TSAttachmentStream, transaction: SDSAnyWriteTransaction) {
        let insertedRecord: MediaGalleryRecord?

        switch transaction.writeTransaction {
        case .grdbWrite(let grdbWrite):
            do {
                insertedRecord = try insertGalleryRecordPrivate(attachmentStream: attachmentStream,
                                                                transaction: grdbWrite)
            } catch {
                owsFailDebug("error: \(error)")
                insertedRecord = nil
            }
        }

        guard let insertedRecord = insertedRecord else {
            return
        }

        do {
            let attachment = try changedAttachmentInfo(for: insertedRecord,
                                                       attachmentUniqueId: attachmentStream.uniqueId,
                                                       transaction: transaction.unwrapGrdbRead)
            recentlyInsertedAttachments.append(attachment)
        } catch {
            owsFailDebug("error: \(error)")
            return
        }

        transaction.addSyncCompletion {
            // Clear the "recentlyRemoved" fields synchronously, so we don't mess with a later transaction.
            Self.recentlyChangedMessageTimestampsByRowId.removeAllValues()
            let recentlyInsertedAttachments = Self.recentlyInsertedAttachments.removeAll()
            if !recentlyInsertedAttachments.isEmpty {
                NotificationCenter.default.postNotificationNameAsync(Self.newAttachmentsAvailableNotification,
                                                                     object: recentlyInsertedAttachments)
            }
        }
    }

    private static func changedAttachmentInfo(for record: MediaGalleryRecord,
                                              attachmentUniqueId: String,
                                              transaction: GRDBReadTransaction) throws -> ChangedAttachmentInfo {
        let timestamp: UInt64
        if let maybeTimestamp = recentlyChangedMessageTimestampsByRowId[record.albumMessageId] {
            timestamp = maybeTimestamp
        } else {
            let timestampQuery = """
                SELECT \(interactionColumn: .receivedAtTimestamp)
                FROM \(InteractionRecord.databaseTableName)
                WHERE id = ?
            """
            guard let maybeTimestamp = try UInt64.fetchOne(transaction.database,
                                                           sql: timestampQuery,
                                                           arguments: [record.albumMessageId]) else {
                throw OWSGenericError("interaction already removed")
            }
            timestamp = maybeTimestamp
            recentlyChangedMessageTimestampsByRowId[record.albumMessageId] = timestamp
        }

        return ChangedAttachmentInfo(uniqueId: attachmentUniqueId,
                                     threadGrdbId: record.threadId,
                                     timestamp: timestamp)

    }

    /// A notification for when a downloaded attachment is removed.
    ///
    /// The object of the notification is an array of ChangedAttachmentInfo values.
    /// When registering an observer for this notification, set the observed object to `nil`, meaning no filter.
    public static let didRemoveAttachmentsNotification =
        Notification.Name(rawValue: "SSKMediaGalleryFinderDidRemoveAttachments")

    @objc(didRemoveAttachmentStream:transaction:)
    public class func didRemove(attachmentStream: TSAttachmentStream, transaction: SDSAnyWriteTransaction) {
        let removedRecord: MediaGalleryRecord?
        switch transaction.writeTransaction {
        case .grdbWrite(let grdbWrite):
            do {
                removedRecord = try removeAnyGalleryRecord(attachmentStream: attachmentStream, transaction: grdbWrite)
            } catch {
                owsFailDebug("error: \(error)")
                removedRecord = nil
            }
        }

        guard let removedRecord = removedRecord else {
            return
        }

        do {
            let attachment = try changedAttachmentInfo(for: removedRecord,
                                                       attachmentUniqueId: attachmentStream.uniqueId,
                                                       transaction: transaction.unwrapGrdbRead)
            recentlyRemovedAttachments.append(attachment)
        } catch {
            owsFailDebug("error: \(error)")
            return
        }

        transaction.addSyncCompletion {
            // Clear the "recentlyRemoved" fields synchronously, so we don't mess with a later transaction.
            Self.recentlyChangedMessageTimestampsByRowId.removeAllValues()
            let recentlyRemovedAttachments = Self.recentlyRemovedAttachments.removeAll()
            if !recentlyRemovedAttachments.isEmpty {
                NotificationCenter.default.postNotificationNameAsync(Self.didRemoveAttachmentsNotification,
                                                                     object: recentlyRemovedAttachments)
            }
        }
    }

    @objc
    public class func recordTimestamp(forRemovedMessage message: TSMessage, transaction: SDSAnyWriteTransaction) {
        guard let messageRowId = message.grdbId?.int64Value else {
            return
        }
        Self.recentlyChangedMessageTimestampsByRowId[messageRowId] = message.receivedAtTimestamp
    }

    @objc
    public class func didRemoveAllContent(transaction: SDSAnyWriteTransaction) {
        switch transaction.writeTransaction {
        case .grdbWrite(let grdbWrite):
            do {
                try removeAllGalleryRecords(transaction: grdbWrite)
            } catch {
                owsFailDebug("error: \(error)")
            }
        }
    }
}

// MARK: - MediaGalleryFinder (GRDB only)

public enum AllMediaFileType: Int, CaseIterable {
    case media = 0
    case audio = 1
}

public struct MediaGalleryFinder {

    public let thread: TSThread

    public enum MediaType {
        case gifs
        case videos
        case photos
        case graphicMedia

        case voiceMessages
        case audioFiles
        case undownloadedAudio
        case audio

        public static func defaultMediaType(for fileType: AllMediaFileType) -> MediaType {
            switch fileType {
            case .media:
                return .graphicMedia
            case .audio:
                return .audio
            }
        }
    }

    /// If non-nil, media will be restricted to this type. Otherwise there is no filtering.
    public var allowedMediaType: MediaType?

    public init(thread: TSThread, allowedMediaType: MediaType?) {
        owsAssertDebug(thread.grdbId != 0, "only supports GRDB")
        self.thread = thread
        self.allowedMediaType = allowedMediaType
    }

    // MARK: - 

    public var threadId: Int64 {
        guard let rowId = thread.grdbId else {
            owsFailDebug("thread.grdbId was unexpectedly nil")
            return 0
        }
        return rowId.int64Value
    }
}

struct MediaGalleryRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "media_gallery_items"

    let attachmentId: Int64
    let albumMessageId: Int64
    let threadId: Int64
    let originalAlbumOrder: Int
}

extension MediaGalleryFinder {
    public enum EnumerationCompletion {
        /// Enumeration completed normally.
        case finished
        /// The query ran out of items.
        case reachedEnd
    }

    private enum Order: String, CustomStringConvertible {
        case ascending = "ASC"
        case descending = "DESC"

        var description: String { self.rawValue }
    }

    private struct QueryParts {
        let fromTableClauses: String
        let orderClauses: String
        let rangeClauses: String

        init(in dateInterval: DateInterval? = nil,
             excluding deletedAttachmentIds: Set<String>,
             order: Order = .ascending,
             limit: Int? = nil,
             offset: Int? = nil,
             allowedMediaType: MediaGalleryFinder.MediaType?) {

            let contentTypeClause: String
            switch allowedMediaType {
            case .gifs, .photos, .videos, .graphicMedia:
                contentTypeClause = "AND IsVisualMediaContentType(\(attachmentColumn: .contentType)) IS TRUE"
            case .voiceMessages, .audio, .undownloadedAudio, .audioFiles:
                contentTypeClause = "AND (\(attachmentColumn: .contentType) like 'audio/%')"
            case .none:
                contentTypeClause = ""
            }
            let whereCondition: String = dateInterval.map {
                let startMillis = $0.start.ows_millisecondsSince1970
                // Both DateInterval and SQL BETWEEN are closed ranges, but rounding to millisecond precision loses range
                // at the boundaries, leading to the first millisecond of a month being considered part of the previous
                // month as well. Subtract 1ms from the end timestamp to avoid this.
                let endMillis = $0.end.ows_millisecondsSince1970 - 1
                var clauses = ["AND \(interactionColumn: .receivedAtTimestamp) BETWEEN \(startMillis) AND \(endMillis)"]
                switch allowedMediaType {
                case .gifs:
                    // Note that this isn't quite the same as -[TSAttachmentStream
                    // hasAnimatedImageContent], which is used to label thumbnails as "GIF", because
                    // we don't try to test if the attachment is an animated sticker. Stickers are
                    // not supported. If we are unfortunate then image/webp and image/png are also
                    // *possibly* animated GIFs but you need to open the file to check.
                    // This code assumes that check is only needed for stickers.
                    clauses.append("AND (" + VideoAttachmentDetection.shared.attachmentStreamIsGIFOrLoopingVideoSQL + ") ")
                case .photos:
                    clauses.append("AND (" + VideoAttachmentDetection.shared.attachmentIsNonGIFImageSQL + ") ")
                case .videos:
                    clauses.append("AND (" + VideoAttachmentDetection.shared.attachmentIsNonLoopingVideoSQL + ") ")
                case .graphicMedia:
                    break
                case .audio:
                    break
                case .undownloadedAudio, .audioFiles, .voiceMessages:
                    break  // TODO(george): Filter content even more. Audio files are all downloaded audio except voice messages. Voice messages have attachmentType of .voicemessage. I have a truly marvelous demonstration of undownloaded audio which this margin is too narrow to contain.
                case .none:
                    // All media types.
                    break
                }
                return clauses.joined(separator: " ")
            } ?? ""

            let deletedAttachmentIdList = "(\"\(deletedAttachmentIds.joined(separator: "\",\""))\")"

            let limitModifier = "LIMIT \(limit ?? Int.max)"
            let offsetModifier = offset.map { "OFFSET \($0)" } ?? ""

            fromTableClauses = """
                FROM "media_gallery_items"
                INNER JOIN \(AttachmentRecord.databaseTableName)
                    ON media_gallery_items.attachmentId = \(attachmentColumnFullyQualified: .id)
                    \(contentTypeClause)
                INNER JOIN \(InteractionRecord.databaseTableName)
                    ON media_gallery_items.albumMessageId = \(interactionColumnFullyQualified: .id)
                    AND \(interactionColumn: .isViewOnceMessage) = FALSE
                WHERE media_gallery_items.threadId = ?
                    AND media_gallery_items.attachmentId NOT IN \(deletedAttachmentIdList)
                    \(whereCondition)
            """

            orderClauses = """
                ORDER BY
                    \(interactionColumn: .receivedAtTimestamp) \(order),
                    media_gallery_items.albumMessageId \(order),
                    media_gallery_items.originalAlbumOrder \(order)
            """

            rangeClauses = """
                \(limitModifier)
                \(offsetModifier)
            """
        }

        func select(_ result: String) -> String {
            return """
            SELECT \(result)
            \(fromTableClauses)
            \(orderClauses)
            \(rangeClauses)
            """
        }
    }

    /// An **unsanitized** interface for building queries against the `media_gallery_items` table
    /// and the associated AttachmentRecord and InteractionRecord tables.
    ///
    /// Contains one query parameter: the thread ID.
    private static func itemsQuery(result: String = "\(AttachmentRecord.databaseTableName).*",
                                   in dateInterval: DateInterval? = nil,
                                   excluding deletedAttachmentIds: Set<String> = Set(),
                                   order: Order = .ascending,
                                   limit: Int? = nil,
                                   offset: Int? = nil,
                                   allowedMediaType: MediaGalleryFinder.MediaType?) -> String {
        let queryParts = QueryParts(in: dateInterval,
                                    excluding: deletedAttachmentIds,
                                    order: order,
                                    limit: limit,
                                    offset: offset,
                                    allowedMediaType: allowedMediaType)
        return queryParts.select(result)
    }

    public func rowIds(in givenInterval: DateInterval? = nil,
                       excluding deletedAttachmentIds: Set<String>,
                       offset: Int,
                       ascending: Bool,
                       transaction: GRDBReadTransaction) -> [Int64] {
        let interval = givenInterval ?? DateInterval.init(start: Date(timeIntervalSince1970: 0),
                                                          end: .distantFutureForMillisecondTimestamp)
        let sql = Self.itemsQuery(result: "media_gallery_items.rowid",
                                  in: interval,
                                  excluding: deletedAttachmentIds,
                                  order: ascending ? .ascending : .descending,
                                  offset: offset,
                                  allowedMediaType: allowedMediaType)
        do {
            return try Int64.fetchAll(transaction.database, sql: sql, arguments: [threadId])
        } catch {
            DatabaseCorruptionState.flagDatabaseReadCorruptionIfNecessary(
                userDefaults: CurrentAppContext().appUserDefaults(),
                error: error
            )
            owsFail("Failed to fetch row ids")
        }
    }

    public func rowIdsAndDates(in givenInterval: DateInterval? = nil,
                               excluding deletedAttachmentIds: Set<String>,
                               offset: Int,
                               ascending: Bool,
                               transaction: GRDBReadTransaction) -> [RowIdAndDate] {
        let interval = givenInterval ?? DateInterval.init(start: Date(timeIntervalSince1970: 0),
                                                          end: .distantFutureForMillisecondTimestamp)
        let sql = Self.itemsQuery(result: "media_gallery_items.rowid, \(interactionColumnFullyQualified: .receivedAtTimestamp)",
                                  in: interval,
                                  excluding: deletedAttachmentIds,
                                  order: ascending ? .ascending : .descending,
                                  offset: offset,
                                  allowedMediaType: allowedMediaType)
        do {
            return try RowIdAndDate.fetchAll(transaction.database, sql: sql, arguments: [threadId])
        } catch {
            DatabaseCorruptionState.flagDatabaseReadCorruptionIfNecessary(
                userDefaults: CurrentAppContext().appUserDefaults(),
                error: error
            )
            owsFail("Missing instance.")
        }
    }

    public func recentMediaAttachments(limit: Int, transaction: GRDBReadTransaction) -> [TSAttachment] {
        let sql = Self.itemsQuery(order: .descending, limit: limit, allowedMediaType: allowedMediaType)
        let cursor = TSAttachment.grdbFetchCursor(sql: sql, arguments: [threadId], transaction: transaction)
        var attachments = [TSAttachment]()
        while let next = try! cursor.next() {
            attachments.append(next)
        }
        return attachments
    }

    public func enumerateMediaAttachments(in dateInterval: DateInterval,
                                          excluding deletedAttachmentIds: Set<String>,
                                          range: NSRange,
                                          transaction: GRDBReadTransaction,
                                          block: (Int, TSAttachment) -> Void) {
        let sql = Self.itemsQuery(in: dateInterval,
                                  excluding: deletedAttachmentIds,
                                  limit: range.length,
                                  offset: range.lowerBound,
                                  allowedMediaType: allowedMediaType)

        let cursor = TSAttachment.grdbFetchCursor(sql: sql, arguments: [threadId], transaction: transaction)
        var index = range.lowerBound
        while let next = try! cursor.next() {
            owsAssertDebug(range.contains(index))
            block(index, next)
            index += 1
        }
    }

    private func enumerateTimestamps(in interval: DateInterval,
                                     excluding deletedAttachmentIds: Set<String>,
                                     order: Order,
                                     count: Int,
                                     transaction: GRDBReadTransaction,
                                     block: (Date, Int64) -> Void) -> EnumerationCompletion {
        let sql = Self.itemsQuery(result: "media_gallery_items.rowid, \(interactionColumn: .receivedAtTimestamp)",
                                  in: interval,
                                  excluding: deletedAttachmentIds,
                                  order: order,
                                  limit: count,
                                  allowedMediaType: allowedMediaType)

        struct RowIDAndTimestamp: FetchableRecord {
            var rowid: Int64
            var timestamp: UInt64
            init(row: GRDB.Row) {
                rowid = row[0]
                timestamp = row[1]
            }
        }

        var actualCount = 0
        do {
            let cursor = try RowIDAndTimestamp.fetchCursor(transaction.database, sql: sql, arguments: [threadId])
            while let next = try cursor.next() {
                actualCount += 1
                block(Date(millisecondsSince1970: next.timestamp), next.rowid)
            }
        } catch {
            DatabaseCorruptionState.flagDatabaseReadCorruptionIfNecessary(
                userDefaults: CurrentAppContext().appUserDefaults(),
                error: error
            )
            owsFail("Failed to enumerate timestamps")
        }
        if actualCount < count {
            return .reachedEnd
        }
        return .finished
    }

    public func enumerateTimestamps(before date: Date,
                                    excluding deletedAttachmentIds: Set<String>,
                                    count: Int,
                                    transaction: GRDBReadTransaction,
                                    block: (Date, Int64) -> Void) -> EnumerationCompletion {
        let interval = DateInterval(start: Date(timeIntervalSince1970: 0), end: date)
        return enumerateTimestamps(in: interval,
                                   excluding: deletedAttachmentIds,
                                   order: .descending,
                                   count: count,
                                   transaction: transaction,
                                   block: block)
    }

    public func enumerateTimestamps(after date: Date,
                                    excluding deletedAttachmentIds: Set<String>,
                                    count: Int,
                                    transaction: GRDBReadTransaction,
                                    block: (Date, Int64) -> Void) -> EnumerationCompletion {
        let interval = DateInterval(start: date, end: .distantFutureForMillisecondTimestamp)
        return enumerateTimestamps(in: interval,
                                   excluding: deletedAttachmentIds,
                                   order: .ascending,
                                   count: count,
                                   transaction: transaction,
                                   block: block)
    }

    // Disregards allowedMediaType.
    public func rowid(of attachment: TSAttachmentStream,
                      in interval: DateInterval,
                      excluding deletedAttachmentIds: Set<String>,
                      transaction: GRDBReadTransaction) -> Int64? {
        guard let attachmentRowId = attachment.grdbId else {
            owsFailDebug("attachment.grdbId was unexpectedly nil")
            return nil
        }

        let queryParts = QueryParts(in: interval,
                                    excluding: deletedAttachmentIds,
                                    allowedMediaType: nil)
        let sql = """
            SELECT
                media_gallery_items.rowid
            \(queryParts.fromTableClauses)
                AND media_gallery_items.attachmentId = ?
        """

        do {
            return try Int64.fetchOne(transaction.database, sql: sql, arguments: [threadId, attachmentRowId])
        } catch {
            DatabaseCorruptionState.flagDatabaseReadCorruptionIfNecessary(
                userDefaults: CurrentAppContext().appUserDefaults(),
                error: error
            )
            owsFail("Failed to get row ID")
        }
    }

    /// Returns the number of attachments attached to `interaction`, whether or not they are media attachments. Disregards allowedMediaType.
    public func countAllAttachments(of interaction: TSInteraction, transaction: GRDBReadTransaction) throws -> UInt {
        let sql = """
            SELECT COUNT(*)
            FROM \(AttachmentRecord.databaseTableName)
            WHERE \(attachmentColumn: .albumMessageId) = ?
        """
        return try UInt.fetchOne(transaction.database, sql: sql, arguments: [interaction.uniqueId]) ?? 0
    }
}
