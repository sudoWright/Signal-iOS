//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "OWSOutgoingSenderKeyDistributionMessage.h"
#import <SignalServiceKit/SignalServiceKit-Swift.h>

@interface OWSOutgoingSenderKeyDistributionMessage ()
@property (strong, nonatomic, readonly) NSData *serializedSKDM;
@property (assign, atomic) BOOL isSentOnBehalfOfOnlineMessage;
@property (assign, atomic) BOOL isSentOnBehalfOfStoryMessage;
@end

@implementation OWSOutgoingSenderKeyDistributionMessage

- (instancetype)initWithThread:(TSContactThread *)destinationThread
    senderKeyDistributionMessageBytes:(NSData *)skdmBytes
                          transaction:(DBReadTransaction *)transaction
{
    OWSAssertDebug(destinationThread);
    OWSAssertDebug(skdmBytes);
    if (!destinationThread || !skdmBytes) {
        return nil;
    }

    TSOutgoingMessageBuilder *messageBuilder =
        [TSOutgoingMessageBuilder outgoingMessageBuilderWithThread:destinationThread];
    self = [super initOutgoingMessageWithBuilder:messageBuilder
                            additionalRecipients:@[]
                              explicitRecipients:@[]
                               skippedRecipients:@[]
                                     transaction:transaction];
    if (self) {
        _serializedSKDM = [skdmBytes copy];
    }
    return self;
}

+ (BOOL)supportsSecureCoding
{
    return YES;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
    OWSFail(@"Doesn't support serialization.");
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super initWithCoder:coder];
    // Doesn't support serialization.
    return nil;
}

- (NSUInteger)hash
{
    NSUInteger result = [super hash];
    result ^= self.isSentOnBehalfOfOnlineMessage;
    result ^= self.isSentOnBehalfOfStoryMessage;
    result ^= self.serializedSKDM.hash;
    return result;
}

- (BOOL)isEqual:(id)other
{
    if (![super isEqual:other]) {
        return NO;
    }
    OWSOutgoingSenderKeyDistributionMessage *typedOther = (OWSOutgoingSenderKeyDistributionMessage *)other;
    if (self.isSentOnBehalfOfOnlineMessage != typedOther.isSentOnBehalfOfOnlineMessage) {
        return NO;
    }
    if (self.isSentOnBehalfOfStoryMessage != typedOther.isSentOnBehalfOfStoryMessage) {
        return NO;
    }
    if (![NSObject isObject:self.serializedSKDM equalToObject:typedOther.serializedSKDM]) {
        return NO;
    }
    return YES;
}

- (BOOL)shouldBeSaved
{
    return NO;
}

- (BOOL)isUrgent
{
    return NO;
}

- (BOOL)isStorySend
{
    return self.isSentOnBehalfOfStoryMessage;
}

- (SealedSenderContentHint)contentHint
{
    return SealedSenderContentHintImplicit;
}

- (nullable SSKProtoContentBuilder *)contentBuilderWithThread:(TSThread *)thread
                                                  transaction:(DBReadTransaction *)transaction
{
    SSKProtoContentBuilder *builder = [SSKProtoContent builder];
    [builder setSenderKeyDistributionMessage:self.serializedSKDM];
    return builder;
}

- (void)configureAsSentOnBehalfOf:(TSOutgoingMessage *)message inThread:(TSThread *)thread
{
    self.isSentOnBehalfOfOnlineMessage = message.isOnline;
    self.isSentOnBehalfOfStoryMessage = message.isStorySend && !thread.isGroupThread;
}

@end
