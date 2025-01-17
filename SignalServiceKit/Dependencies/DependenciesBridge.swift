//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalCoreKit

/// Temporary bridge between [legacy code that uses global accessors for manager instances]
/// and [new code that expects references to instances to be explicitly passed around].
///
/// Ideally, all references to dependencies (singletons or otherwise) are passed to a class
/// in its initializer. Most existing code is not written that way, and expects to pull dependencies
/// from global static state (e.g. `SSKEnvironment` and `Dependencies`)
///
/// This lets you put off piping through references many layers deep to the usage site,
/// and access global state but with a few advantages over legacy methods:
/// 1) Not a protocol + extension; you must explicitly access members via the shared instance
/// 2) Swift-only, no need for @objc
/// 3) Classes within this container should themselves adhere to modern design principles: NOT accessing
///   global state or `Dependencies`, being protocolized, taking all dependencies
///   explicitly on initialization, and encapsulated for easy testing.
///
/// It is preferred **NOT** to use this class, and to take dependencies on init instead, but it is
/// better to use this class than to use `Dependencies`.
public class DependenciesBridge {

    /// Only available after calling `setupSingleton(...)`.
    public static var shared: DependenciesBridge {
        guard let _shared else {
            owsFail("DependenciesBridge has not yet been set up!")
        }

        return _shared
    }
    private static var _shared: DependenciesBridge?

    static func setShared(_ dependenciesBridge: DependenciesBridge) {
        Self._shared = dependenciesBridge
    }

    public let accountAttributesUpdater: AccountAttributesUpdater
    public let appExpiry: AppExpiry
    public let attachmentDownloadManager: AttachmentDownloadManager
    public let attachmentManager: AttachmentManager
    public let attachmentStore: AttachmentStore
    public let authorMergeHelper: AuthorMergeHelper
    public let badgeCountFetcher: BadgeCountFetcher
    public let callRecordDeleteManager: CallRecordDeleteManager
    let callRecordIncomingSyncMessageManager: CallRecordIncomingSyncMessageManager
    public let callRecordMissedCallManager: CallRecordMissedCallManager
    public let callRecordQuerier: CallRecordQuerier
    public let callRecordStore: CallRecordStore
    public let changePhoneNumberPniManager: ChangePhoneNumberPniManager
    public let chatColorSettingStore: ChatColorSettingStore
    public let db: DB
    public let deletedCallRecordCleanupManager: DeletedCallRecordCleanupManager
    let deletedCallRecordStore: DeletedCallRecordStore
    public let deviceManager: OWSDeviceManager
    public let disappearingMessagesConfigurationStore: DisappearingMessagesConfigurationStore
    public let editManager: EditManager
    public let externalPendingIDEALDonationStore: ExternalPendingIDEALDonationStore
    public let groupCallRecordManager: GroupCallRecordManager
    public let groupMemberStore: GroupMemberStore
    public let groupMemberUpdater: GroupMemberUpdater
    public let groupUpdateInfoMessageInserter: GroupUpdateInfoMessageInserter
    public let identityManager: OWSIdentityManager
    public let incomingPniChangeNumberProcessor: IncomingPniChangeNumberProcessor
    public let individualCallRecordManager: IndividualCallRecordManager
    public let interactionStore: InteractionStore
    public let keyValueStoreFactory: KeyValueStoreFactory
    public let learnMyOwnPniManager: LearnMyOwnPniManager
    public let linkedDevicePniKeyManager: LinkedDevicePniKeyManager
    let localProfileChecker: LocalProfileChecker
    public let localUsernameManager: LocalUsernameManager
    public let masterKeySyncManager: MasterKeySyncManager
    public let mediaBandwidthPreferenceStore: MediaBandwidthPreferenceStore
    public let messageBackupManager: MessageBackupManager
    public let phoneNumberDiscoverabilityManager: PhoneNumberDiscoverabilityManager
    public let phoneNumberVisibilityFetcher: any PhoneNumberVisibilityFetcher
    public let pinnedThreadManager: PinnedThreadManager
    public let pinnedThreadStore: PinnedThreadStore
    public let pniHelloWorldManager: PniHelloWorldManager
    public let preKeyManager: PreKeyManager
    public let receiptCredentialResultStore: ReceiptCredentialResultStore
    public let recipientDatabaseTable: RecipientDatabaseTable
    public let recipientFetcher: RecipientFetcher
    public let recipientHidingManager: RecipientHidingManager
    public let recipientIdFinder: RecipientIdFinder
    public let recipientManager: any SignalRecipientManager
    public let recipientMerger: RecipientMerger
    public let registrationSessionManager: RegistrationSessionManager
    public let registrationStateChangeManager: RegistrationStateChangeManager
    public let schedulers: Schedulers
    public let searchableNameIndexer: SearchableNameIndexer
    public let sentMessageTranscriptReceiver: SentMessageTranscriptReceiver
    public let signalProtocolStoreManager: SignalProtocolStoreManager
    public let socketManager: SocketManager
    public let svr: SecureValueRecovery
    public let svrCredentialStorage: SVRAuthCredentialStorage
    public let threadAssociatedDataStore: ThreadAssociatedDataStore
    public let threadRemover: ThreadRemover
    public let threadReplyInfoStore: ThreadReplyInfoStore
    public let threadStore: ThreadStore
    public let tsAccountManager: TSAccountManager
    public let tsResourceDownloadManager: TSResourceDownloadManager
    public let tsResourceManager: TSResourceManager
    public let tsResourceStore: TSResourceStore
    public let uploadManager: UploadManager
    public let usernameApiClient: UsernameApiClient
    public let usernameEducationManager: UsernameEducationManager
    public let usernameLinkManager: UsernameLinkManager
    public let usernameLookupManager: UsernameLookupManager
    public let usernameValidationManager: UsernameValidationManager
    public let wallpaperStore: WallpaperStore

    init(
        accountAttributesUpdater: AccountAttributesUpdater,
        appExpiry: AppExpiry,
        attachmentDownloadManager: AttachmentDownloadManager,
        attachmentManager: AttachmentManager,
        attachmentStore: AttachmentStore,
        authorMergeHelper: AuthorMergeHelper,
        badgeCountFetcher: BadgeCountFetcher,
        callRecordDeleteManager: CallRecordDeleteManager,
        callRecordIncomingSyncMessageManager: CallRecordIncomingSyncMessageManager,
        callRecordMissedCallManager: CallRecordMissedCallManager,
        callRecordQuerier: CallRecordQuerier,
        callRecordStore: CallRecordStore,
        changePhoneNumberPniManager: ChangePhoneNumberPniManager,
        chatColorSettingStore: ChatColorSettingStore,
        db: DB,
        deletedCallRecordCleanupManager: DeletedCallRecordCleanupManager,
        deletedCallRecordStore: DeletedCallRecordStore,
        deviceManager: OWSDeviceManager,
        disappearingMessagesConfigurationStore: DisappearingMessagesConfigurationStore,
        editManager: EditManager,
        externalPendingIDEALDonationStore: ExternalPendingIDEALDonationStore,
        groupCallRecordManager: GroupCallRecordManager,
        groupMemberStore: GroupMemberStore,
        groupMemberUpdater: GroupMemberUpdater,
        groupUpdateInfoMessageInserter: GroupUpdateInfoMessageInserter,
        identityManager: OWSIdentityManager,
        incomingPniChangeNumberProcessor: IncomingPniChangeNumberProcessor,
        individualCallRecordManager: IndividualCallRecordManager,
        interactionStore: InteractionStore,
        keyValueStoreFactory: KeyValueStoreFactory,
        learnMyOwnPniManager: LearnMyOwnPniManager,
        linkedDevicePniKeyManager: LinkedDevicePniKeyManager,
        localProfileChecker: LocalProfileChecker,
        localUsernameManager: LocalUsernameManager,
        masterKeySyncManager: MasterKeySyncManager,
        mediaBandwidthPreferenceStore: MediaBandwidthPreferenceStore,
        messageBackupManager: MessageBackupManager,
        phoneNumberDiscoverabilityManager: PhoneNumberDiscoverabilityManager,
        phoneNumberVisibilityFetcher: any PhoneNumberVisibilityFetcher,
        pinnedThreadManager: PinnedThreadManager,
        pinnedThreadStore: PinnedThreadStore,
        pniHelloWorldManager: PniHelloWorldManager,
        preKeyManager: PreKeyManager,
        receiptCredentialResultStore: ReceiptCredentialResultStore,
        recipientDatabaseTable: RecipientDatabaseTable,
        recipientFetcher: RecipientFetcher,
        recipientHidingManager: RecipientHidingManager,
        recipientIdFinder: RecipientIdFinder,
        recipientManager: any SignalRecipientManager,
        recipientMerger: RecipientMerger,
        registrationSessionManager: RegistrationSessionManager,
        registrationStateChangeManager: RegistrationStateChangeManager,
        schedulers: Schedulers,
        searchableNameIndexer: SearchableNameIndexer,
        sentMessageTranscriptReceiver: SentMessageTranscriptReceiver,
        signalProtocolStoreManager: SignalProtocolStoreManager,
        socketManager: SocketManager,
        svr: SecureValueRecovery,
        svrCredentialStorage: SVRAuthCredentialStorage,
        threadAssociatedDataStore: ThreadAssociatedDataStore,
        threadRemover: ThreadRemover,
        threadReplyInfoStore: ThreadReplyInfoStore,
        threadStore: ThreadStore,
        tsAccountManager: TSAccountManager,
        tsResourceDownloadManager: TSResourceDownloadManager,
        tsResourceManager: TSResourceManager,
        tsResourceStore: TSResourceStore,
        uploadManager: UploadManager,
        usernameApiClient: UsernameApiClient,
        usernameEducationManager: UsernameEducationManager,
        usernameLinkManager: UsernameLinkManager,
        usernameLookupManager: UsernameLookupManager,
        usernameValidationManager: UsernameValidationManager,
        wallpaperStore: WallpaperStore
    ) {
        self.accountAttributesUpdater = accountAttributesUpdater
        self.appExpiry = appExpiry
        self.attachmentDownloadManager = attachmentDownloadManager
        self.attachmentManager = attachmentManager
        self.attachmentStore = attachmentStore
        self.authorMergeHelper = authorMergeHelper
        self.badgeCountFetcher = badgeCountFetcher
        self.callRecordDeleteManager = callRecordDeleteManager
        self.callRecordIncomingSyncMessageManager = callRecordIncomingSyncMessageManager
        self.callRecordMissedCallManager = callRecordMissedCallManager
        self.callRecordQuerier = callRecordQuerier
        self.callRecordStore = callRecordStore
        self.changePhoneNumberPniManager = changePhoneNumberPniManager
        self.chatColorSettingStore = chatColorSettingStore
        self.db = db
        self.deletedCallRecordCleanupManager = deletedCallRecordCleanupManager
        self.deletedCallRecordStore = deletedCallRecordStore
        self.deviceManager = deviceManager
        self.disappearingMessagesConfigurationStore = disappearingMessagesConfigurationStore
        self.editManager = editManager
        self.externalPendingIDEALDonationStore = externalPendingIDEALDonationStore
        self.groupCallRecordManager = groupCallRecordManager
        self.groupMemberStore = groupMemberStore
        self.groupMemberUpdater = groupMemberUpdater
        self.groupUpdateInfoMessageInserter = groupUpdateInfoMessageInserter
        self.identityManager = identityManager
        self.incomingPniChangeNumberProcessor = incomingPniChangeNumberProcessor
        self.individualCallRecordManager = individualCallRecordManager
        self.interactionStore = interactionStore
        self.keyValueStoreFactory = keyValueStoreFactory
        self.learnMyOwnPniManager = learnMyOwnPniManager
        self.linkedDevicePniKeyManager = linkedDevicePniKeyManager
        self.localProfileChecker = localProfileChecker
        self.localUsernameManager = localUsernameManager
        self.masterKeySyncManager = masterKeySyncManager
        self.mediaBandwidthPreferenceStore = mediaBandwidthPreferenceStore
        self.messageBackupManager = messageBackupManager
        self.phoneNumberDiscoverabilityManager = phoneNumberDiscoverabilityManager
        self.phoneNumberVisibilityFetcher = phoneNumberVisibilityFetcher
        self.pinnedThreadManager = pinnedThreadManager
        self.pinnedThreadStore = pinnedThreadStore
        self.pniHelloWorldManager = pniHelloWorldManager
        self.preKeyManager = preKeyManager
        self.receiptCredentialResultStore = receiptCredentialResultStore
        self.recipientDatabaseTable = recipientDatabaseTable
        self.recipientFetcher = recipientFetcher
        self.recipientHidingManager = recipientHidingManager
        self.recipientIdFinder = recipientIdFinder
        self.recipientManager = recipientManager
        self.recipientMerger = recipientMerger
        self.registrationSessionManager = registrationSessionManager
        self.registrationStateChangeManager = registrationStateChangeManager
        self.schedulers = schedulers
        self.searchableNameIndexer = searchableNameIndexer
        self.sentMessageTranscriptReceiver = sentMessageTranscriptReceiver
        self.signalProtocolStoreManager = signalProtocolStoreManager
        self.socketManager = socketManager
        self.svr = svr
        self.svrCredentialStorage = svrCredentialStorage
        self.threadAssociatedDataStore = threadAssociatedDataStore
        self.threadRemover = threadRemover
        self.threadReplyInfoStore = threadReplyInfoStore
        self.threadStore = threadStore
        self.tsAccountManager = tsAccountManager
        self.tsResourceDownloadManager = tsResourceDownloadManager
        self.tsResourceManager = tsResourceManager
        self.tsResourceStore = tsResourceStore
        self.uploadManager = uploadManager
        self.usernameApiClient = usernameApiClient
        self.usernameEducationManager = usernameEducationManager
        self.usernameLinkManager = usernameLinkManager
        self.usernameLookupManager = usernameLookupManager
        self.usernameValidationManager = usernameValidationManager
        self.wallpaperStore = wallpaperStore
    }
}
