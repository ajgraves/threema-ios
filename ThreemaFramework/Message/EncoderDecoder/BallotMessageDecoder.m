//  _____ _
// |_   _| |_  _ _ ___ ___ _ __  __ _
//   | | | ' \| '_/ -_) -_) '  \/ _` |_
//   |_| |_||_|_| \___\___|_|_|_\__,_(_)
//
// Threema iOS Client
// Copyright (c) 2014-2023 Threema GmbH
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License, version 3,
// as published by the Free Software Foundation.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program. If not, see <https://www.gnu.org/licenses/>.

#import "BallotMessageDecoder.h"
#import "BallotKeys.h"
#import "EntityCreator.h"
#import "ThreemaFramework/ThreemaFramework-Swift.h"
#import "NSString+Hex.h"

#ifdef DEBUG
static const DDLogLevel ddLogLevel = DDLogLevelVerbose;
#else
static const DDLogLevel ddLogLevel = DDLogLevelWarning;
#endif

@interface BallotMessageDecoder ()

@property EntityManager *entityManager;
@property BallotManager *ballotManager;

@end

@implementation BallotMessageDecoder

- (instancetype)initWith:(NSObject *)entityManagerObject {
    NSAssert([entityManagerObject isKindOfClass:[EntityManager class]], @"");
    
    self = [super init];
    if (self) {
        _entityManager = (EntityManager *)entityManagerObject;
        _ballotManager = [[BallotManager alloc] initWithEntityManager: _entityManager];
    }
    return self;
}

- (nullable BallotMessage *)decodeCreateBallotFromBox:(nonnull BoxBallotCreateMessage *)boxMessage sender:(nullable ContactEntity *)sender conversation:(nonnull Conversation *)conversation {
    return [self decodeBallotCreateMessage:boxMessage sender:sender conversation:conversation];
}


- (nullable BallotMessage *)decodeCreateBallotFromGroupBox:(nonnull GroupBallotCreateMessage *)boxMessage sender:(nullable ContactEntity *)sender conversation:(nonnull Conversation *)conversation {
    return [self decodeBallotCreateMessage:boxMessage sender:sender conversation:conversation];
}

+ (NSString *)decodeCreateBallotTitleFromBox:(BoxBallotCreateMessage *)boxMessage {
    NSError *error;
    NSDictionary *json = (NSDictionary *)[NSJSONSerialization JSONObjectWithData:boxMessage.jsonData options:0 error:&error];
    if (json == nil) {
        DDLogError(@"[Ballot] Error parsing ballot json data %@, %@", error, [error userInfo]);
        return nil;
    }
    
    return [json objectForKey: JSON_KEY_TITLE];
}

+ (NSNumber *)decodeNotificationCreateBallotStateFromBox:(BoxBallotCreateMessage *)boxMessage {
    NSData *jsonData;
    if ([boxMessage isKindOfClass:[BoxBallotCreateMessage class]]) {
        jsonData = ((BoxBallotCreateMessage *)boxMessage).jsonData;
    } else if ([boxMessage isKindOfClass:[GroupBallotCreateMessage class]]) {
        jsonData = ((GroupBallotCreateMessage *)boxMessage).jsonData;
    } else {
        DDLogError(@"[Ballot] Ballot decode: invalid message type");
        return nil;
    }
    
    NSError *error;
    NSDictionary *json = (NSDictionary *)[NSJSONSerialization JSONObjectWithData:jsonData options:0 error:&error];
    return [json objectForKey: JSON_KEY_STATE];
}

- (BallotMessage *)decodeBallotCreateMessage:(AbstractMessage *)boxMessage sender:(nullable ContactEntity *)sender conversation:(nonnull Conversation *)conversation {
    
    NSData *ballotId;
    NSData *jsonData;
    if ([boxMessage isKindOfClass:[BoxBallotCreateMessage class]]) {
        ballotId = ((BoxBallotCreateMessage *)boxMessage).ballotId;
        jsonData = ((BoxBallotCreateMessage *)boxMessage).jsonData;
    } else if ([boxMessage isKindOfClass:[GroupBallotCreateMessage class]]) {
        ballotId = ((GroupBallotCreateMessage *)boxMessage).ballotId;
        jsonData = ((GroupBallotCreateMessage *)boxMessage).jsonData;
    } else {
        DDLogError(@"[Ballot] Ballot decode: invalid message type");
        return nil;
    }
    
    /* Create Message in DB */
    __block BallotMessage *message = (BallotMessage *)[_entityManager getOrCreateMessageFor:boxMessage sender:sender conversation:conversation thumbnail:nil];
    if (message == nil) {
        DDLogError(@"[Ballot] Could not find/create ballot message");
        return message;
    }

    [_entityManager performSyncBlockAndSafe:^{
        Ballot *ballot = [_entityManager.entityFetcher ballotForBallotId:ballotId];
        NSDate *conversationLastUpdate = conversation.lastUpdate;
        if (ballot != nil) {
            [self updateExistingBallot:ballot jsonData:jsonData];
        } else {
            ballot = [self createNewBallotWithId:ballotId creatorId:boxMessage.fromIdentity jsonData:jsonData];
        }

        // error parsing data
        if (ballot == nil) {
            if (message) {
                DDLogError(@"[Ballot] Parsing of ballot failed, message will be deleted");
                [[_entityManager entityDestroyer] deleteObjectWithObject:message];
                
                // do not use the conversation function 'updateLastMessageWith', because we are already in a perform block
                MessageFetcher *messageFetcher = [[MessageFetcher alloc] initFor:conversation with:_entityManager];
                BaseMessage *lastMessage = messageFetcher.lastMessage;
                
                if (lastMessage != conversation.lastMessage) {
                    conversation.lastMessage = lastMessage;
                }
                
                // Set lastUpdate to the old value
                conversation.lastUpdate = conversationLastUpdate;
            }
            message = nil;
            return;
        }

        ballot.modifyDate = [NSDate date];
        ballot.conversation = conversation;
        message.ballot = ballot;
    }];

    return message;
}


- (BOOL)decodeVoteFromGroupBox:(GroupBallotVoteMessage *)boxMessage {
    return [self decodeVoteForIdentity:boxMessage.fromIdentity ballotId:boxMessage.ballotId jsonData:boxMessage.jsonChoiceData];
}

- (BOOL)decodeVoteFromBox:(BoxBallotVoteMessage *)boxMessage {
    return [self decodeVoteForIdentity:boxMessage.fromIdentity ballotId:boxMessage.ballotId jsonData:boxMessage.jsonChoiceData];
}

- (BOOL)decodeVoteForIdentity:(NSString *)contactId ballotId:(NSData *)ballotId jsonData:(NSData *)jsonData {
    
    Ballot *ballot = [_entityManager.entityFetcher ballotForBallotId:ballotId];
    
    if (ballot == nil) {
        DDLogError(@"[Ballot] No ballot found for vote");
        return NO;
    }
    
    if (ballot.isClosed) {
        DDLogError(@"[Ballot] [%@] Ballot already closed, ignore vote from %@", [NSString stringWithHexData:ballot.id], contactId);
        return NO;
    }
    
    ballot.modifyDate = [NSDate date];
    [ballot incrementUnreadUpdateCount];
    
    return [self parseJsonVoteData:jsonData forContact:contactId inBallot:ballot];
}

- (void)updateExistingBallot:(Ballot *)ballot jsonData:(NSData *)jsonData {
    DDLogInfo(@"[Ballot] [%@] Update existing ballot", [NSString stringWithHexData:ballot.id]);
    if ([self parseJsonCreateData:jsonData forBallot:ballot update:true]) {
        ballot.modifyDate = [NSDate date];
        [ballot incrementUnreadUpdateCount];
    }
}

- (Ballot *)createNewBallotWithId:(NSData *)ballotId creatorId:(NSString *)creatorId jsonData:(NSData *)jsonData {
    Ballot *ballot = [_entityManager.entityCreator ballot];
    ballot.id = ballotId;
    ballot.creatorId = creatorId;
    ballot.createDate = [NSDate date];
    
    if ([self parseJsonCreateData:jsonData forBallot:ballot update:false]) {
        DDLogInfo(@"[Ballot] [%@] Created new ballot", [NSString stringWithHexData:ballot.id]);
        return ballot;
    }
    
    // parse failed: remove the ballot we just created
    [[_entityManager entityDestroyer] deleteObjectWithObject:ballot];
    return nil;
}

- (BOOL)parseJsonVoteData:(NSData *)jsonData forContact:(NSString *)contactId inBallot:(Ballot *)ballot {
    NSError *error;
    NSArray *choiceArray = (NSArray *)[NSJSONSerialization JSONObjectWithData:jsonData options:0 error:&error];
    if (choiceArray == nil) {
        DDLogError(@"[Ballot] [%@] Error parsing ballot vote data %@, %@", [NSString stringWithHexData:ballot.id], error, [error userInfo]);
        return NO;
    }
    
    BOOL updatedVote = [ballot hasVotesForIdentity:contactId];
    
    for (NSArray *choice in choiceArray) {
        if ([choice count] != 2) {
            //ignore invalid entries
            continue;
        }
        
        NSNumber *choiceId = [choice objectAtIndex:0];
        NSNumber *value = [choice objectAtIndex:1];
        [_ballotManager updateBallot:ballot choiceID:choiceId with:value for:contactId];
    }
    
    // We add votes system messages for ballots that are intermediate, or for those that the local identity created.
    if (ballot.isIntermediate == YES) {
        DDLogInfo(@"[Ballot] [%@] New vote [%@] received", [NSString stringWithHexData:ballot.id], contactId);
        [_ballotManager addVoteSystemMessageWithBallotTitle:ballot.title conversation:ballot.conversation contactID:contactId showIntermediateResults:ballot.isIntermediate updatedVote:updatedVote];
    }
    else if (ballot.creatorId == MyIdentityStore.sharedMyIdentityStore.identity && !updatedVote) {
        // Do not show updated votes if ballot is not intermediate
        DDLogInfo(@"[Ballot] [%@] New vote [%@] received", [NSString stringWithHexData:ballot.id], contactId);
        [_ballotManager addVoteSystemMessageWithBallotTitle:ballot.title conversation:ballot.conversation contactID:contactId showIntermediateResults:ballot.isIntermediate updatedVote:updatedVote];
    }
    
    return YES;
}

- (BOOL)parseJsonCreateData:(NSData *)jsonData forBallot:(Ballot *)ballot update:(BOOL)update {
    NSError *error;
    NSDictionary *json = (NSDictionary *)[NSJSONSerialization JSONObjectWithData:jsonData options:0 error:&error];
    if (json == nil) {
        DDLogError(@"[Ballot] [%@] Error parsing ballot json data %@, %@", [NSString stringWithHexData:ballot.id], error, [error userInfo]);
        return NO;
    }
    
    NSNumber *state = [json objectForKey: JSON_KEY_STATE];
    NSNumber *displayMode = [json objectForKey: JSON_KEY_DISPLAYMODE];
    
    if (update == true) {
        // only update the state of the ballot
        
        if ([ballot.state isEqualToNumber:@1]) {
            DDLogError(@"[Ballot] [%@] Error can't update ballot, because ballot is already closed", [NSString stringWithHexData:ballot.id]);
            return NO;
        }
        if ([state isEqualToNumber:@1]) {
            ballot.state = state;
        }
        
    } else {
        if ([state isEqualToNumber:@1]) {
            DDLogError(@"[Ballot] [%@] Error ballot not found and state is closed", [NSString stringWithHexData:ballot.id]);
            return NO;
        }
        ballot.title = [json objectForKey: JSON_KEY_TITLE];
        ballot.type = [json objectForKey: JSON_KEY_TYPE];
        ballot.state = state;
        ballot.assessmentType = [json objectForKey: JSON_KEY_ASSESSMENT_TYPE];
        ballot.choicesType = [json objectForKey: JSON_KEY_CHOICES_TYPE];
        
        // Get Display-Mode, if no value is present use DisplayModeList
        if (displayMode != NULL && [displayMode isEqualToNumber: [[NSNumber alloc] initWithInteger:BallotDisplayModeSummary]]) {
            ballot.ballotDisplayMode = BallotDisplayModeSummary;
        } else {
            ballot.ballotDisplayMode = BallotDisplayModeList;
        }
    }
        
    return [self updateParticipants:ballot json:json update:update];
}

- (BOOL)updateParticipants:(Ballot *)ballot json:(NSDictionary *)json update:(BOOL)update {
    NSArray *choicesArray = [json objectForKey: JSON_KEY_CHOICES];
    NSArray *participantIds = [json objectForKey: JSON_KEY_PARTICIPANTS];
    
    NSMutableSet *choices = [NSMutableSet set];
    for (NSDictionary *choiceData in choicesArray) {
        BallotChoice *choice = [self handleChoiceData: choiceData participantIds: participantIds forBallot: ballot update:update];
        if (choice == nil) {
            return false;
        }
        [choices addObject: choice];
    }
    
    ballot.choices = choices;
    return true;
}

- (BallotChoice *)handleChoiceData:(NSDictionary *)choiceData participantIds: (NSArray *) participantIds forBallot:(Ballot *)ballot update:(BOOL)update {
    NSNumber *choiceId = [choiceData objectForKeyedSubscript: JSON_CHOICE_KEY_ID];
    
    BallotChoice *choice = [_entityManager.entityFetcher ballotChoiceForBallotId:ballot.id choiceId:choiceId];
    
    if (choice == nil) {
        if (!update) {
            choice = [_entityManager.entityCreator ballotChoice];
            choice.id = [choiceData objectForKeyedSubscript: JSON_CHOICE_KEY_ID];
        } else {
            DDLogError(@"[Ballot] [%@] Invalid choice for create message: choice result array count does not match participant array count", [NSString stringWithHexData:ballot.id]);
            return choice;
        }
    }
    
    // We update choices when we receive the final result.
    choice.ballot = ballot;
    choice.name = [choiceData objectForKeyedSubscript: JSON_CHOICE_KEY_NAME];
    choice.orderPosition = [choiceData objectForKeyedSubscript: JSON_CHOICE_KEY_ORDER_POSITION];
    
    NSArray *choiceResult = [choiceData objectForKeyedSubscript: JSON_CHOICE_KEY_RESULT];
    
    // TotalVotes must only be present in DisplayModeSummary, also choice results must be ignored
    if (ballot.ballotDisplayMode == BallotDisplayModeSummary) {
        choice.totalVotes = [choiceData objectForKeyedSubscript: JSON_CHOICE_KEY_TOTALVOTES];
        return choice;
    }
    
    if ([choiceResult count] != [participantIds count]) {
        DDLogError(@"[Ballot] [%@] Invalid ballot create message: choice result array count does not match participant array count", [NSString stringWithHexData:ballot.id]);
        return choice;
    }
    
    if ([choiceResult count] != [_ballotManager choiceResultCount:ballot choiceID:choice.id]) {
        [_ballotManager removeInvalidChoiceResults:ballot choiceID:choice.id participantIDs:participantIds];
    }
        
    NSInteger i=0;
    for (NSNumber *value in choiceResult) {
        NSString *contactId = [participantIds objectAtIndex: i];
        
        [_ballotManager updateBallot:ballot choiceID:choice.id with:value for:contactId];
        
        i++;
    }
    
    return choice;
}

@end

