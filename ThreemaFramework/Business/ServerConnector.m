//  _____ _
// |_   _| |_  _ _ ___ ___ _ __  __ _
//   | | | ' \| '_/ -_) -_) '  \/ _` |_
//   |_| |_||_|_| \___\___|_|_|_\__,_(_)
//
// Threema iOS Client
// Copyright (c) 2012-2022 Threema GmbH
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

#include <CommonCrypto/CommonDigest.h>

#import "ThreemaFramework/ThreemaFramework-Swift.h"

#import "ServerConnector.h"
#import "NaClCrypto.h"
#import <ThreemaFramework/ChatTcpSocket.h>
#import <ThreemaFramework/NSData+ConvertUInt64.h>
#import "NSString+Hex.h"
#import "BoxedMessage.h"
#import "MyIdentityStore.h"
#import "ProtocolDefines.h"
#import "Reachability.h"
#import "ThreemaUtilityObjC.h"
#import "ContactStore.h"
#import "UserSettings.h"
#import "BundleUtil.h"
#import "AppGroup.h"
#import "LicenseStore.h"
#import "PushPayloadDecryptor.h"
#import "DataQueue.h"

#ifdef DEBUG
  static const DDLogLevel ddLogLevel = DDLogLevelAll;
#else
  static const DDLogLevel ddLogLevel = DDLogLevelNotice;
#endif
#define LOG_KEY_INFO 0

static const int MAX_BYTES_TO_DECRYPT_NO_LIMIT = 0;
static const int MAX_BYTES_TO_DECRYPT_NOTIFICATION_EXTENSION = 500000;

@implementation ServerConnector {
    NSData *clientTempKeyPub;
    NSData *clientTempKeySec;
    time_t clientTempKeyGenTime;
    NSData *clientCookie;
    
    NSData *serverCookie;
    NSData *serverTempKeyPub;
    
    NSData *chosenServerKeyPub;
    NSData *serverKeyPub;
    NSData *serverAltKeyPub;
    
    NSString *mediatorServerURL;

    BOOL webSocketConnection;
    
    dispatch_queue_t sendPushTokenQueue;
    BOOL isSentPushToken;
    
    dispatch_queue_t sendVoIPPushTokenQueue;
    BOOL isSentVoIPPushToken;
    
    dispatch_queue_t removeVoIPPushTokenQueue;
    BOOL isRemovedVoIPPushToken;
    
    uint64_t serverNonce;
    uint64_t clientNonce;
    dispatch_queue_t socketQueue;
    dispatch_queue_t sendMessageQueue;
    dispatch_source_t keepalive_timer;
    NSCondition *disconnectCondition;
    id<SocketProtocol> socket;
    int reconnectAttempts;

    NSMutableArray *connectionInitiators;
    dispatch_queue_t connectionInitiatorsQueue;

    ServerConnectorConnectionState *serverConnectorConnectionState;

    BOOL autoReconnect;
    CFTimeInterval lastRead;
    NSDate *lastErrorDisplay;

    CFTimeInterval lastEchoSendTime;
    uint64_t lastSentEchoSeq;
    uint64_t lastRcvdEchoSeq;

    Reachability *internetReachability;
    NetworkStatus lastInternetStatus;
    
    NSMutableSet *displayedServerAlerts;
    int anotherConnectionCount;
    BOOL chatServerInInitialQueueSend;
    BOOL mediatorServerInInitialQueueSend;
    BOOL isWaitingForReconnect;
    BOOL isRolePromotedToLeader;

    dispatch_queue_t queueConnectionStateDelegate;
    NSMutableSet *clientConnectionStateDelegates;

    dispatch_queue_t queueMessageListenerDelegate;
    NSMutableSet *clientMessageListenerDelegates;

    dispatch_queue_t queueMessageProcessorDelegate;
    id<MessageProcessorDelegate> clientMessageProcessorDelegate;
    
    dispatch_queue_t queueTaskExecutionTransactionDelegate;
    id<TaskExecutionTransactionDelegate> clientTaskExecutionTransactionDelegate;
}

@synthesize businessInjectorForMessageProcessing;
@synthesize lastRtt;
@synthesize deviceGroupPathKey;
@synthesize deviceId;
@synthesize isAppInBackground;

#pragma pack(push, 1)
#pragma pack(1)

struct pktClientHello {
    unsigned char client_tempkey_pub[kNaClCryptoPubKeySize];
    unsigned char client_cookie[kCookieLen];
};

struct pktServerHelloBox {
    unsigned char server_tempkey_pub[kNaClCryptoPubKeySize];
    unsigned char client_cookie[kCookieLen];
};

struct pktServerHello {
    unsigned char server_cookie[kCookieLen];
    char box[sizeof(struct pktServerHelloBox) + kNaClBoxOverhead];
};

struct pktVouch {
    unsigned char client_tempkey_pub[kNaClCryptoPubKeySize];
};

struct pktLogin {
    char identity[kIdentityLen];
    char client_version[kClientVersionLen];
    unsigned char server_cookie[kCookieLen];
    unsigned char vouch_nonce[kNaClCryptoNonceSize];
    char vouch_box[sizeof(struct pktVouch) + kNaClBoxOverhead];
};

struct pktLoginAck {
    char reserved[kLoginAckReservedLen];
};

struct pktPayload {
    uint8_t type;
    uint8_t reserved[3];
    char data[];
};

struct pktExtension {
    uint8_t type;
    uint16_t length;
    char data[];
};

#pragma pack(pop)

#define TAG_CLIENT_HELLO_SENT 1
#define TAG_SERVER_HELLO_READ 2
#define TAG_LOGIN_SENT 3
#define TAG_LOGIN_ACK_READ 4
#define TAG_PAYLOAD_SENT 5
#define TAG_PAYLOAD_LENGTH_READ 6
#define TAG_PAYLOAD_READ 7
#define TAG_PAYLOAD_MEDIATOR_TRIGGERED 8

#define EXTENSION_TYPE_CLIENT_INFO 0x00
#define EXTENSION_TYPE_DEVICE_ID 0x01
#define EXTENSION_TYPE_MESSAGE_PAYLOAD_VERSION 0x02

+ (ServerConnector*)sharedServerConnector {
    static ServerConnector *instance;
    
    @synchronized (self) {
        if (!instance)
            instance = [[ServerConnector alloc] init];
    }
    
    return instance;
}

- (id)init
{
    self = [super init];
    if (self) {
        mediatorServerURL = [BundleUtil objectForInfoDictionaryKey:@"ThreemaMediatorServerURL"];
        
        webSocketConnection = [[BundleUtil objectForInfoDictionaryKey:@"WebSocketConnection"] boolValue];
        
        sendPushTokenQueue = dispatch_queue_create("ch.threema.ServerConnector.sendPushTokenQueue", NULL);
        isSentPushToken = NO;
        
        sendVoIPPushTokenQueue = dispatch_queue_create("ch.threema.ServerConnector.sendVoIPPushTokenQueue", NULL);
        isSentVoIPPushToken = NO;
        
        removeVoIPPushTokenQueue = dispatch_queue_create("ch.threema.ServerConnector.removeVoIPPushTokenQueue", NULL);
        isRemovedVoIPPushToken = NO;
        
        connectionInitiators = [[NSMutableArray alloc] init];
        connectionInitiatorsQueue = dispatch_queue_create("ch.threema.ServerConnector.connectionInitiatorsQueue", NULL);

        socketQueue = dispatch_queue_create("ch.threema.ServerConnector.socketQueue", NULL);
        sendMessageQueue = dispatch_queue_create("ch.threema.ServerConnector.sendMessageQueue", NULL);
        disconnectCondition = [[NSCondition alloc] init];
        
        serverConnectorConnectionState = [[ServerConnectorConnectionState alloc]  initWithConnectionStateDelegate:self isMultiDeviceEnabled:webSocketConnection];
        reconnectAttempts = 0;
        lastSentEchoSeq = 0;
        lastRcvdEchoSeq = 0;

        displayedServerAlerts = [NSMutableSet set];
        
        /* register with reachability API */
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(networkStatusDidChange:) name:kReachabilityChangedNotification object:nil];
        
        internetReachability = [Reachability reachabilityForInternetConnection];
        lastInternetStatus = [internetReachability currentReachabilityStatus];
        [internetReachability startNotifier];
        
        isWaitingForReconnect = false;
        
        /* listen for identity changes */
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(identityCreated:) name:kNotificationCreatedIdentity object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(identityDestroyed:) name:kNotificationDestroyedIdentity object:nil];

        queueConnectionStateDelegate = dispatch_queue_create("ch.threema.ServerConnector.queueConnectionStateDelegate", NULL);
        queueMessageListenerDelegate = dispatch_queue_create("ch.threema.ServerConnector.queueMessageListenerDelegate", NULL);
        queueMessageProcessorDelegate = dispatch_queue_create("ch.threema.ServerConnector.queueMessageProcessorDelegate", NULL);
        queueTaskExecutionTransactionDelegate = dispatch_queue_create("ch.threema.ServerConnector.queueTaskExecutionTransactionDelegate", NULL);
    }
    return self;
}

#pragma mark - Register/unregister Message Listener delegate, Message Processor delegate and Task Manager transaction delegate

- (void)registerConnectionStateDelegate:(id<ConnectionStateDelegate>)delegate {
    dispatch_sync(queueConnectionStateDelegate, ^{
        if (clientConnectionStateDelegates == nil) {
            clientConnectionStateDelegates = [NSMutableSet new];
        }
        if ([clientConnectionStateDelegates containsObject:delegate] == NO) {
            [clientConnectionStateDelegates addObject:delegate];
        }
    });
}

- (void)unregisterConnectionStateDelegate:(id<ConnectionStateDelegate>)delegate {
    dispatch_sync(queueConnectionStateDelegate, ^{
        if (clientConnectionStateDelegates != nil && [clientConnectionStateDelegates containsObject:delegate] == YES) {
            [clientConnectionStateDelegates removeObject:delegate];
        }
    });
}

- (void)registerMessageListenerDelegate:(id<MessageListenerDelegate>)delegate {
    dispatch_sync(queueMessageListenerDelegate, ^{
        if (clientMessageListenerDelegates == nil) {
            clientMessageListenerDelegates = [NSMutableSet new];
        }
        if ([clientMessageListenerDelegates containsObject:delegate] == NO) {
            [clientMessageListenerDelegates addObject:delegate];
        }
    });
}

- (void)unregisterMessageListenerDelegate:(id<MessageListenerDelegate>)delegate {
    dispatch_sync(queueMessageListenerDelegate, ^{
        if (clientMessageListenerDelegates != nil && [clientMessageListenerDelegates containsObject:delegate] == YES) {
            [clientMessageListenerDelegates removeObject:delegate];
        }
    });
}

- (void)registerMessageProcessorDelegate:(id<MessageProcessorDelegate>)delegate {
    dispatch_async(queueMessageProcessorDelegate, ^{
        if (delegate != nil) {
            clientMessageProcessorDelegate = delegate;
        }
    });
}

- (void)unregisterMessageProcessorDelegate:(id<MessageProcessorDelegate>)delegate {
    dispatch_async(queueMessageProcessorDelegate, ^{
        if ([delegate isEqual:clientMessageProcessorDelegate]) {
            clientMessageProcessorDelegate = nil;
        }
    });
}

- (void)registerTaskExecutionTransactionDelegate:(id<TaskExecutionTransactionDelegate>)delegate {
    dispatch_sync(queueTaskExecutionTransactionDelegate, ^{
        if (delegate != nil) {
            clientTaskExecutionTransactionDelegate = delegate;
        }
    });
}

- (void)unregisterTaskExecutionTransactionDelegate:(id<TaskExecutionTransactionDelegate>)delegate {
    dispatch_sync(queueTaskExecutionTransactionDelegate, ^{
        if ([delegate isEqual:clientTaskExecutionTransactionDelegate]) {
            clientTaskExecutionTransactionDelegate = nil;
        }
    });
}

#pragma mark - Chat Server connection handling

- (void)connect:(ConnectionInitiator)initiator {
    dispatch_async(socketQueue, ^{
        dispatch_sync(connectionInitiatorsQueue, ^{
            [self connectBy:initiator];
        });

        lastErrorDisplay = nil;
        [self _connect];
    });
}

- (void)connectWait:(ConnectionInitiator)initiator {
    dispatch_sync(socketQueue, ^{
        dispatch_sync(connectionInitiatorsQueue, ^{
            [self connectBy:initiator];
        });

        lastErrorDisplay = nil;
        [self _connect];
    });
}

- (void)_connect {
    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"FASTLANE_SNAPSHOT"]) {
        return;
    }
    
    if (![[MyIdentityStore sharedMyIdentityStore] isProvisioned]) {
        DDLogNotice(@"Cannot connect - missing identity or key");
        return;
    }
    
    if (self.connectionState == ConnectionStateDisconnecting) {
        // The socketDidDisconnect callback has not been called yet; ensure that we reconnect
        // as soon as the previous disconnect has finished.
        reconnectAttempts = 1;
        autoReconnect = YES;
        return;
    } else if (self.connectionState != ConnectionStateDisconnected) {
        if (self.connectionState == ConnectionStateLoggedIn) {
            return;
        }
        DDLogNotice(@"Cannot connect - invalid connection state (actual state: %@)", [self nameForConnectionState:self.connectionState]);
        autoReconnect = YES;
        [self reconnectAfterDelay];
        return;
    }
    
    if ([AppGroup amIActive] == NO) {
        DDLogNotice(@"Not active -> don't connect now, retry later");
        // keep delay at constant rate to avoid too long waits when becoming active again
        reconnectAttempts = 1;
        autoReconnect = YES;
        [self reconnectAfterDelay];
        return;
    }

    LicenseStore *licenseStore = [LicenseStore sharedLicenseStore];
    if ([licenseStore isValid] == NO) {
        [licenseStore performLicenseCheckWithCompletion:^(BOOL success) {
            if (success) {
                [self _connect];
            } else {
                // don't show license warning for connection errors
                DDLogNotice(@"License check failed: %@", licenseStore.error);
                if ([licenseStore.error.domain hasPrefix:@"NSURL"] == NO && licenseStore.error.code != 256) {
                    // License check failed permanently; need to inform user and ask for new license username/password
                    [[NSNotificationCenter defaultCenter] postNotificationName:kNotificationLicenseMissing object:nil];
                } else {
                    // License check failed due to connection error – try again later
                    autoReconnect = YES;
                    [self reconnectAfterDelay];
                }
            }
        }];
        
        return;
    }
    
    [[LicenseStore sharedLicenseStore] performUpdateWorkInfo];

    [serverConnectorConnectionState connecting];
    autoReconnect = YES;
    self.lastRtt = -1;
    lastRead = CACurrentMediaTime();
    chatServerInInitialQueueSend = YES;
    mediatorServerInInitialQueueSend = YES;
    
    /* Reset nonces for new connection */
    clientNonce = 1;
    serverNonce = 1;
    
    /* Generate a new key pair for the server connection. */
    time_t uptime = [ThreemaUtilityObjC systemUptime];
    DDLogVerbose(@"System uptime is %ld", uptime);
    if (clientTempKeyPub == nil || clientTempKeySec == nil || uptime <= 0 || (uptime - clientTempKeyGenTime) > kClientTempKeyMaxAge) {
        NSData *publicKey, *secretKey;
        [[NaClCrypto sharedCrypto] generateKeyPairPublicKey:&publicKey secretKey:&secretKey];
        clientTempKeyPub = publicKey;
        clientTempKeySec = secretKey;
        clientTempKeyGenTime = uptime;
#if LOG_KEY_INFO
        DDLogVerbose(@"Client tempkey_pub = %@, tempkey_sec = %@", clientTempKeyPub, clientTempKeySec);
#endif
    }

    if (webSocketConnection == NO) {
        [self _connectDirect];
    } else {
        [self _connectViaMediator];
    }
}

- (void)_connectDirect {
    // Multi device is not activated, reset device ID
    deviceId = nil;
    
    UserSettings *settings = [UserSettings sharedUserSettings];
    
    // Obtain chat server host/ports/keys from ServerInfoProvider
    [[ServerInfoProviderFactory makeServerInfoProvider] chatServerWithIpv6:[UserSettings sharedUserSettings].enableIPv6 completionHandler:^(ChatServerInfo * _Nullable chatServerInfo, NSError *error) {
        dispatch_async(socketQueue, ^{
            if (chatServerInfo == nil) {
                // Could not get the info at the moment; try again later
                [serverConnectorConnectionState disconnected];
                [self reconnectAfterDelay];
                return;
            }
            
            NSString *serverHost;
            if (chatServerInfo.useServerGroups) {
                serverHost = [NSString stringWithFormat:@"%@%@%@", chatServerInfo.serverNamePrefix, [MyIdentityStore sharedMyIdentityStore].serverGroup, chatServerInfo.serverNameSuffix];
            } else {
                serverHost = chatServerInfo.serverNameSuffix;
            }
            
            serverKeyPub = chatServerInfo.publicKey;
            serverAltKeyPub = chatServerInfo.publicKeyAlt;
            
            NSError *socketError;
            socket = [[ChatTcpSocket alloc] initWithServer:serverHost ports:chatServerInfo.serverPorts preferIPv6:settings.enableIPv6 delegate:self queue:socketQueue error:&socketError];
            
            if (socketError != nil || ![socket connect]) {
                [serverConnectorConnectionState disconnected];
                [self reconnectAfterDelay];
                return;
            }
        });
    }];
}

- (void)_connectViaMediator {
    UserSettings *settings = [UserSettings sharedUserSettings];
    
    // Derive DGPK from SK
    MultiDeviceKey *multiDeviceKey = [[MultiDeviceKey alloc] init];
    deviceGroupPathKey = [multiDeviceKey deriveWithSecretKey:[[MyIdentityStore sharedMyIdentityStore] keySecret]];
    
    NSAssert([deviceGroupPathKey length] == kDeviceGroupPathKeyLen, @"Device Group Path Key has wrong length");

    // Convert hex string to int
    unsigned sg = 0;
    NSScanner *scanner = [NSScanner scannerWithString:[MyIdentityStore sharedMyIdentityStore].serverGroup];
    [scanner scanHexInt:&sg];
    
    NSString *clientUrlInfo = [MediatorMessageProtocol encodeClientURLInfoWithDgpkPublicKey:[[NaClCrypto sharedCrypto] derivePublicKeyFromSecretKey:deviceGroupPathKey] serverGroup:sg];
    
    // Multi device is activated, check device ID
    if ([settings deviceID] == nil || [[settings deviceID] length] != kDeviceIdLen) {
        settings.deviceID = [NSData dataWithBytes:[[NaClCrypto sharedCrypto] randomBytes:kDeviceIdLen].bytes length:kDeviceIdLen];
    }
    deviceId = settings.deviceID;

    NSAssert([deviceId length] == kDeviceIdLen, @"Device ID has wrong length");
    
    id<ServerInfoProvider> serverInfoProvider = [ServerInfoProviderFactory makeServerInfoProvider];
    [serverInfoProvider mediatorServerWithCompletionHandler:^(MediatorServerInfo * _Nullable mediatorServerInfo, NSError * _Nullable mediatorServerError) {
        // Obtain chat server info too (for public keys)
        [serverInfoProvider chatServerWithIpv6:[UserSettings sharedUserSettings].enableIPv6 completionHandler:^(ChatServerInfo * _Nullable chatServerInfo, NSError * _Nullable chatServerError) {
            if (mediatorServerInfo == nil || chatServerInfo == nil) {
                // Could not get the info at the moment; try again later
                [serverConnectorConnectionState disconnected];
                [self reconnectAfterDelay];
                return;
            }
            
            NSString *server = [NSString stringWithFormat:@"%@/%@", mediatorServerInfo.url, clientUrlInfo];
            serverKeyPub = chatServerInfo.publicKey;
            serverAltKeyPub = chatServerInfo.publicKeyAlt;
            
            NSError *socketError;
            socket = [[MediatorWebSocket alloc] initWithServer:server ports:@[] preferIPv6:settings.enableIPv6 delegate:self queue:socketQueue error:&socketError];
            
            if (socketError != nil || ![socket connect]) {
                [serverConnectorConnectionState disconnected];
                [self reconnectAfterDelay];
                return;
            }
        }];
    }];
}

- (void)_disconnect {
    if ([serverConnectorConnectionState connectionState] == ConnectionStateDisconnected) {
        return;
    }
    
    /* disconnect socket and make sure we don't reconnect */
    autoReconnect = NO;
    [serverConnectorConnectionState disconnecting];
    [socket disconnect];
}

- (void)disconnect:(ConnectionInitiator)initiator {
    dispatch_async(socketQueue, ^{
        if ([self isOthersConnectedDisconnectBy:initiator] == YES) {
            return;
        }

        [self _disconnect];
    });
}

- (void)disconnectWait:(ConnectionInitiator)initiator {
    if ([self isOthersConnectedDisconnectBy:initiator] == YES) {
        return;
    }

    dispatch_sync(socketQueue, ^{
        [self _disconnect];
    });
    
    [serverConnectorConnectionState waitForStateDisconnected];
}

- (void)reconnect {
    dispatch_async(socketQueue, ^{
        if ([serverConnectorConnectionState connectionState] == ConnectionStateDisconnected) {
            [self _connect];
        } else if ([serverConnectorConnectionState connectionState] == ConnectionStateConnecting) {
            DDLogVerbose(@"Connection already in progress, not reconnecting");
        } else {
            autoReconnect = YES;
            [serverConnectorConnectionState disconnecting];
            [socket disconnect];
        }
    });
}

- (ConnectionState)connectionState {
    return [serverConnectorConnectionState connectionState];
}

#pragma mark - Chat Server connection initiator handling

- (void)connectBy:(ConnectionInitiator)initiator {
    DDLogNotice(@"Connect initiated by (%@)", [self nameForConnectionInitiator:initiator]);
    if (![connectionInitiators containsObject:[NSNumber numberWithInteger:initiator]]) {
        [connectionInitiators addObject:[NSNumber numberWithInteger:initiator]];
    }
}

- (BOOL)isOthersConnectedDisconnectBy:(ConnectionInitiator)initiator {
    DDLogNotice(@"Disconnect initiated by (%@)", [self nameForConnectionInitiator:initiator]);
    [connectionInitiators removeObject:[NSNumber numberWithInteger:initiator]];
    if ([connectionInitiators count] != 0) {
        NSMutableString *initiators = [NSMutableString new];

        for (int i = 0; i < [connectionInitiators count]; i++) {
            ConnectionInitiator initiatorItem = (ConnectionInitiator)[(NSNumber *)[connectionInitiators objectAtIndex:i] intValue];
            if ([initiators length] > 0) {
                [initiators appendString:@", "];
            }
            [initiators appendString:[self nameForConnectionInitiator:initiatorItem]];
        }
        DDLogNotice(@"Do not disconnect because maybe others are still connected (%@)", initiators);
        return YES;
    }
    return NO;
}

- (NSString *)nameForConnectionInitiator:(ConnectionInitiator)initiator {
    switch (initiator) {
        case ConnectionInitiatorApp:
            return @"App";
        case ConnectionInitiatorNotificationExtension:
            return @"NotificationExtension";
        case ConnectionInitiatorNotificationHandler:
            return @"NotificationHandler";
        case ConnectionInitiatorShareExtension:
            return @"ShareExtension";
        case ConnectionInitiatorThreemaCall:
            return @"ThreemaCall";
        case ConnectionInitiatorThreemaWeb:
            return @"ThreemaWeb";
        default:
            return nil;
    }
}

#pragma mark - Processing incoming payloads

- (void)processPayload:(struct pktPayload*)pl datalen:(int)datalen {
    
    switch (pl->type) {
        case PLTYPE_ECHO_REPLY: {
            self.lastRtt = CACurrentMediaTime() - lastEchoSendTime;
            if (datalen == sizeof(lastRcvdEchoSeq)) {
                memcpy(&lastRcvdEchoSeq, pl->data, sizeof(lastRcvdEchoSeq));
            } else {
                DDLogError(@"Bad echo reply datalen %d", datalen);
                [socket disconnect];
                break;
            }
            DDLogInfo(@"Received echo reply (seq %llu, RTT %.1f ms)", lastRcvdEchoSeq, self.lastRtt * 1000);
            break;
        }
        case PLTYPE_ERROR: {
            if (datalen < sizeof(struct plError)) {
                DDLogError(@"Bad error payload datalen %d", datalen);
                [socket disconnect];
                break;
            }
            struct plError *plerr = (struct plError*)pl->data;
            NSData *errorMessageData = [NSData dataWithBytes:plerr->err_message length:datalen - sizeof(struct plError)];
            NSString *errorMessage = [[NSString alloc] initWithData:errorMessageData encoding:NSUTF8StringEncoding];
            DDLogError(@"Received error message from server: %@", errorMessage);
            
            BOOL anotherConnectionError = false;
            
            if ([errorMessage rangeOfString:@"Another connection"].location != NSNotFound) {
                // extension took over connection
                if ([AppGroup amIActive] == NO) {
                    break;
                }
                
                anotherConnectionError = true;
                
                // ignore first few occurrences of "Another connection" messages to gracefully handle network switches
                if (anotherConnectionCount < 5) {
                    anotherConnectionCount++;
                    break;
                }
            }
            
            if (!plerr->reconnect_allowed) {
                autoReconnect = NO;
            }
            
            if (lastErrorDisplay == nil || ((-[lastErrorDisplay timeIntervalSinceNow]) > kErrorDisplayInterval)) {
                lastErrorDisplay = [NSDate date];
                
                NSDictionary *info = nil;
                
                if (anotherConnectionError) {
                    NSBundle *bundle = [BundleUtil mainBundle];
                    errorMessage = [NSString stringWithFormat:[BundleUtil localizedStringForKey:@"error_other_connection_for_same_identity_message"], [bundle objectForInfoDictionaryKey:@"CFBundleDisplayName"]];
                    info = [NSDictionary dictionaryWithObjectsAndKeys: [BundleUtil localizedStringForKey:@"error_other_connection_for_same_identity_title"], kKeyTitle, errorMessage, kKeyMessage, nil];
                } else {
                    info = [NSDictionary dictionaryWithObjectsAndKeys: errorMessage, kKeyMessage, nil];
                }
                
                [[NSNotificationCenter defaultCenter] postNotificationName:kNotificationErrorConnectionFailed object:nil userInfo:info];
            }
            break;
        }
        case PLTYPE_ALERT: {
            NSData *alertData = [NSData dataWithBytes:pl->data length:datalen];
            NSString *alertText = [[NSString alloc] initWithData:alertData encoding:NSUTF8StringEncoding];
            [self displayServerAlert:alertText];
            break;
        }
        case PLTYPE_OUTGOING_MESSAGE_ACK: {
            if (datalen != sizeof(struct plMessageAck)) {
                DDLogError(@"Bad ACK payload datalen %d", datalen);
                [socket disconnect];
                break;
            }
            
            struct plOutgoingMessageAck *ack = (struct plOutgoingMessageAck*)pl->data;
            NSData *messageId = [NSData dataWithBytes:ack->message_id length:kMessageIdLen];
            NSString *toIdentity = [[NSString alloc] initWithData:[NSData dataWithBytes:ack->to_identity length:kIdentityLen] encoding:NSASCIIStringEncoding];
            [[NSNotificationCenter defaultCenter] postNotificationName:[TaskManager chatMessageAckObserverNameWithMessageID:messageId toIdentity:toIdentity] object:nil];
            break;
        }
        case PLTYPE_INCOMING_MESSAGE: {
            if (datalen <= sizeof(struct plMessage)) {
                DDLogError(@"Bad message payload datalen %d", datalen);
                [socket disconnect];
                break;
            }
            
            if ([AppGroup amIActive] && [AppGroup getActiveType] != AppGroupTypeShareExtension) {
                struct plMessage *plmsg = (struct plMessage*)pl->data;
                int minlen = (sizeof(struct plMessage) + kNonceLen + plmsg->metadata_len + kNaClBoxOverhead + 1);
                if (datalen <= minlen || (plmsg->metadata_len > 0 && plmsg->metadata_len <= kNaClBoxOverhead)) {
                    DDLogError(@"Bad message payload datalen %d, metadata_len %d", datalen, plmsg->metadata_len);
                    [socket disconnect];
                    break;
                }
                
                BoxedMessage *boxmsg = [[BoxedMessage alloc] init];
                boxmsg.fromIdentity = [[NSString alloc] initWithData:[NSData dataWithBytes:plmsg->from_identity length:kIdentityLen] encoding:NSASCIIStringEncoding];
                boxmsg.toIdentity = [[NSString alloc] initWithData:[NSData dataWithBytes:plmsg->to_identity length:kIdentityLen] encoding:NSASCIIStringEncoding];
                boxmsg.messageId = [NSData dataWithBytes:plmsg->message_id length:kMessageIdLen];
                boxmsg.date = [NSDate dateWithTimeIntervalSince1970:plmsg->date];
                boxmsg.flags = plmsg->flags;
                char pushFromNameT[kPushFromNameLen+1];
                memcpy(pushFromNameT, plmsg->push_from_name, kPushFromNameLen);
                pushFromNameT[kPushFromNameLen] = 0;
                boxmsg.pushFromName = [NSString stringWithCString:pushFromNameT encoding:NSUTF8StringEncoding];
                if (plmsg->metadata_len > 0) {
                    boxmsg.metadataBox = [NSData dataWithBytes:&plmsg->metadata_nonce_box length:plmsg->metadata_len];
                }
                boxmsg.nonce = [NSData dataWithBytes:&plmsg->metadata_nonce_box[plmsg->metadata_len] length:kNonceLen];
                boxmsg.box = [NSData dataWithBytes:&plmsg->metadata_nonce_box[plmsg->metadata_len + kNonceLen] length:(datalen - sizeof(struct plMessage) - kNonceLen - plmsg->metadata_len)];

                // Set time out for downloading thumbnail to 5s, if tha app in background or notification extension is running
                int timeoutDownloadThumbnail = isAppInBackground || [AppGroup getActiveType] == AppGroupTypeNotificationExtension ? 5 : 0;

                TaskDefinitionReceiveMessage *task = [[TaskDefinitionReceiveMessage alloc] initWithMessage:boxmsg receivedAfterInitialQueueSend:!chatServerInInitialQueueSend maxBytesToDecrypt:[AppGroup getActiveType] != AppGroupTypeNotificationExtension ? MAX_BYTES_TO_DECRYPT_NO_LIMIT : MAX_BYTES_TO_DECRYPT_NOTIFICATION_EXTENSION timeoutDownloadThumbnail:timeoutDownloadThumbnail];

                // Use `[self businessInjectorForMessageProcessing]` if is not nil (properly setted from Notification Extension), otherwise create new instance for in App processing
                TaskManager *tm = [[TaskManager alloc] initWithFrameworkInjectorObjc:[self businessInjectorForMessageProcessing] != nil ? [self businessInjectorForMessageProcessing] : [BusinessInjector new]];
                [tm addObjcWithTaskDefinition:task];
            }
            break;
        }
        case PLTYPE_QUEUE_SEND_COMPLETE:
            DDLogInfo(@"Queue send complete");
            chatServerInInitialQueueSend = NO;
            
            [self chatQueueDry];
             
            [[NSNotificationCenter defaultCenter] postNotificationName:kNotificationQueueSendComplete object:nil userInfo:nil];
            break;
        default:
            DDLogWarn(@"Unsupported payload type %d", pl->type);
            break;
    }
}

- (void)completedProcessingAbstractMessage:(AbstractMessage *)msg {
    if (!(msg.flags.intValue & MESSAGE_FLAG_NOACK)) {
        /* send ACK to server */
        [self ackMessage:msg.messageId fromIdentity:msg.fromIdentity];
    }
}

- (BOOL)completedProcessingMessage:(BoxedMessage *)boxmsg {
    if (!(boxmsg.flags & MESSAGE_FLAG_NOACK)) {
        /* send ACK to server */
        return [self ackMessage:boxmsg.messageId fromIdentity:boxmsg.fromIdentity];
    }
    return YES;
}

- (void)failedProcessingMessage:(BoxedMessage *)boxmsg error:(NSError *)err {
    if (err.code == kBlockUnknownContactErrorCode) {
        DDLogVerbose(@"Message processing error due to block contacts - acking anyway");
        [self ackMessage:boxmsg.messageId fromIdentity:boxmsg.fromIdentity];
    } else if (err.code == kBadMessageErrorCode) {
        DDLogVerbose(@"Message processing error due to bad message format or decryption failure - acking anyway");
        [self ackMessage:boxmsg.messageId fromIdentity:boxmsg.fromIdentity];
    } else if (err.code == kMessageProcessingErrorCode) {
        DDLogError(@"Message processing error due to being unable to handle message: %@", err);
   } else {
        DDLogInfo(@"Could not process incoming message: %@", err);
    }
}

- (void)reconnectAfterDelay {
    // Never reconnect for the notification extension
    if (!autoReconnect || [AppGroup getCurrentType] == AppGroupTypeNotificationExtension) {
        return;
    }
    
    /* calculate delay using bound exponential backoff */
    float reconnectDelay = powf(kReconnectBaseInterval, MIN(reconnectAttempts - 1, 10));
    if (reconnectDelay > kReconnectMaxInterval) {
        reconnectDelay = kReconnectMaxInterval;
    }
    
    if (!isWaitingForReconnect) {
        isWaitingForReconnect = true;
        reconnectAttempts++;
        DDLogNotice(@"Waiting %f seconds before reconnecting", reconnectDelay);
        dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, reconnectDelay * NSEC_PER_SEC);
        dispatch_after(popTime, socketQueue, ^(void){
            isWaitingForReconnect = false;
            [self _connect];
        });
    }
}

- (BOOL)sendPayloadWithType:(uint8_t)type data:(NSData*)data {
    if ([serverConnectorConnectionState connectionState] != ConnectionStateLoggedIn) {
        DDLogVerbose(@"Cannot send payload - not logged in");
        return NO;
    }
    
    /* Make encrypted box */
    unsigned long pllen = sizeof(struct pktPayload) + data.length;
    struct pktPayload *pl = malloc(pllen);
    if (!pl) {
        return NO;
    }
    
    bzero(pl, pllen);
    
    pl->type = type;
    memcpy(pl->data, data.bytes, data.length);
    
    NSData *plData = [NSData dataWithBytesNoCopy:pl length:pllen];
    
    __block BOOL isSent = NO;
    
    // Gets next client nonce not before the message was sent
    dispatch_barrier_sync(sendMessageQueue, ^{
        NSData *nextClientNonce = [self nextClientNonce];
        NSData *plBox = [[NaClCrypto sharedCrypto] encryptData:plData withPublicKey:serverTempKeyPub signKey:clientTempKeySec nonce:nextClientNonce];
        if (plBox == nil) {
            DDLogError(@"Payload encryption failed!");
            isSent = NO;
        }
        else {
            /* prepend length - make one NSData object to pass to socket to ensure it is sent
               in a single TCP segment */
            uint16_t pktlen = plBox.length;
            
            if (pktlen > kMaxPktLen) {
                DDLogError(@"Packet is too big (%d) - cannot send", pktlen);
                isSent = NO;
            }
            else {
                NSMutableData *sendData = [NSMutableData dataWithCapacity:plBox.length + sizeof(uint16_t)];
                [sendData appendBytes:&pktlen length:sizeof(uint16_t)];
                [sendData appendData:plBox];
                
                [socket writeWithData:sendData tag:TAG_PAYLOAD_SENT];
                
                isSent = YES;
            }
        }
    });
    
    return isSent;
}

- (BOOL)sendMessage:(BoxedMessage*)message {
    unsigned long msglen = sizeof(struct plMessage) + message.metadataBox.length + message.nonce.length + message.box.length;
    struct plMessage *plmsg = malloc(msglen);
    if (!plmsg) {
        return NO;
    }
    
    DDLogInfo(@"Sending message from %@ to %@ (ID %@), metadata box length %lu, box length %lu", message.fromIdentity,
          message.toIdentity, message.messageId, (unsigned long)message.metadataBox.length, (unsigned long)message.box.length);
    
    memcpy(plmsg->from_identity, [message.fromIdentity dataUsingEncoding:NSASCIIStringEncoding].bytes, kIdentityLen);
    memcpy(plmsg->to_identity, [message.toIdentity dataUsingEncoding:NSASCIIStringEncoding].bytes, kIdentityLen);
    memcpy(plmsg->message_id, message.messageId.bytes, kMessageIdLen);
    plmsg->date = [message.date timeIntervalSince1970];
    plmsg->flags = message.flags;
    plmsg->reserved = 0;
    plmsg->metadata_len = message.metadataBox.length;
    bzero(plmsg->push_from_name, kPushFromNameLen);
    if (message.pushFromName != nil) {
        NSData *encodedPushFromName = [ThreemaUtilityObjC truncatedUTF8String:message.pushFromName maxLength:kPushFromNameLen];
        strncpy(plmsg->push_from_name, encodedPushFromName.bytes, encodedPushFromName.length);
    }
    
    size_t offset = 0;
    if (message.metadataBox != nil) {
        memcpy(&plmsg->metadata_nonce_box[offset], message.metadataBox.bytes, message.metadataBox.length);
        offset += message.metadataBox.length;
    }
    memcpy(&plmsg->metadata_nonce_box[offset], message.nonce.bytes, message.nonce.length);
    offset += message.nonce.length;
    memcpy(&plmsg->metadata_nonce_box[offset], message.box.bytes, message.box.length);
    
    return [self sendPayloadWithType:PLTYPE_OUTGOING_MESSAGE data:[NSData dataWithBytesNoCopy:plmsg length:msglen]];
}

- (BOOL)reflectMessage:(NSData *)message {
    if (message == nil) {
        return NO;
    }
    
    if ([serverConnectorConnectionState connectionState] != ConnectionStateLoggedIn) {
        DDLogVerbose(@"Cannot reflect message - not logged in");
        return NO;
    }

    if (deviceGroupPathKey == nil) {
        DDLogError(@"Message could not be reflect, because mediator private key is missing");
        return NO;
    }

    [socket writeWithData:message];
    return YES;
}

- (BOOL)ackMessage:(NSData*)messageId fromIdentity:(NSString*)fromIdentity {
    int msglen = sizeof(struct plMessageAck);
    struct plMessageAck *plmsgack = malloc(msglen);
    if (!plmsgack)
        return NO;
    
    DDLogInfo(@"Sending ack for message ID %@ from %@", messageId, fromIdentity);
    
    memcpy(plmsgack->from_identity, [fromIdentity dataUsingEncoding:NSASCIIStringEncoding].bytes, kIdentityLen);
    memcpy(plmsgack->message_id, messageId.bytes, kMessageIdLen);
    
    return [self sendPayloadWithType:PLTYPE_INCOMING_MESSAGE_ACK data:[NSData dataWithBytesNoCopy:plmsgack length:msglen]];
}

- (void)ping {
    dispatch_async(socketQueue, ^{
        [self sendEchoRequest];
    });
}

- (void)sendEchoRequest {
    if ([serverConnectorConnectionState connectionState] != ConnectionStateLoggedIn)
        return;
    
    lastSentEchoSeq++;
    DDLogInfo(@"Sending echo request (seq %llu)", lastSentEchoSeq);
    
    lastEchoSendTime = CACurrentMediaTime();
    [self sendPayloadWithType:PLTYPE_ECHO_REQUEST data:[NSData dataWithBytes:&lastSentEchoSeq length:sizeof(lastSentEchoSeq)]];
    
    id<SocketProtocol> curSocket = socket;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, kReadTimeout * NSEC_PER_SEC), dispatch_get_main_queue(), ^(void){
        if (curSocket == socket && lastRcvdEchoSeq < lastSentEchoSeq) {
            DDLogInfo(@"No reply to echo payload; disconnecting");
            [socket disconnect];
        }
    });
}

- (BOOL)isMultiDeviceActivated {
    return deviceGroupPathKey != nil;
}

#pragma mark - Push Notification

- (BOOL)shouldRegisterPush {
    return [AppGroup getCurrentType] == AppGroupTypeApp && [serverConnectorConnectionState connectionState] == ConnectionStateLoggedIn;
}

- (void)setPushToken:(NSData *)pushToken {
    [[AppGroup userDefaults] setObject:pushToken forKey:kPushNotificationDeviceToken];
    [[AppGroup userDefaults] synchronize];
    [self sendPushToken];
}

- (void)setVoIPPushToken:(NSData *)voIPPushToken {
    [[AppGroup userDefaults] setObject:voIPPushToken forKey:kVoIPPushNotificationDeviceToken];
    [[AppGroup userDefaults] synchronize];
    [self sendVoIPPushToken];
}

- (void)sendPushToken {
    dispatch_sync(sendPushTokenQueue, ^{
        if (isSentPushToken == YES) {
            DDLogInfo(@"Already sent push notification token (apple mc)");
            return;
        }
        
        NSData *pushToken = [[AppGroup userDefaults] objectForKey:kPushNotificationDeviceToken];
        
        if ([self shouldRegisterPush] == NO || pushToken == nil) {
            return;
        }

        DDLogInfo(@"Sending push notification token (apple mc)");
        
#ifdef DEBUG
        uint8_t pushTokenType = PUSHTOKEN_TYPE_APPLE_SANDBOX_MC;
#else
        uint8_t pushTokenType = PUSHTOKEN_TYPE_APPLE_PROD_MC;
#endif
        
        NSMutableData *payloadData = [NSMutableData dataWithBytes:&pushTokenType length:1];
        [payloadData appendData:pushToken];
        [payloadData appendData:[@"|" dataUsingEncoding:NSUTF8StringEncoding]];
        [payloadData appendData:[[[NSBundle mainBundle] bundleIdentifier] dataUsingEncoding:NSASCIIStringEncoding]];
        [payloadData appendData:[@"|" dataUsingEncoding:NSUTF8StringEncoding]];
        [payloadData appendData:[PushPayloadDecryptor pushEncryptionKey]];
        [self sendPayloadWithType:PLTYPE_PUSH_NOTIFICATION_TOKEN data:payloadData];

        isSentPushToken = YES;
    });
}

- (void)sendVoIPPushToken {
    dispatch_sync(sendVoIPPushTokenQueue, ^{
        if (isSentVoIPPushToken == YES) {
            DDLogInfo(@"Already sent VoIP push notification token (apple)");
            return;
        }

        NSData *voIPPushToken = [[AppGroup userDefaults] objectForKey:kVoIPPushNotificationDeviceToken];

        if ([self shouldRegisterPush] == NO || voIPPushToken == nil) {
            return;
        }
        
        DDLogInfo(@"Sending VoIP push notification token (apple)");
        
    #ifdef DEBUG
        uint8_t voIPPushTokenType = PUSHTOKEN_TYPE_APPLE_SANDBOX;
    #else
        uint8_t voIPPushTokenType = PUSHTOKEN_TYPE_APPLE_PROD;
    #endif
        
        NSMutableData *payloadData = [NSMutableData dataWithBytes:&voIPPushTokenType length:1];
        [payloadData appendData:voIPPushToken];
        [payloadData appendData:[@"|" dataUsingEncoding:NSUTF8StringEncoding]];
        [payloadData appendData:[[[NSBundle mainBundle] bundleIdentifier] dataUsingEncoding:NSASCIIStringEncoding]];
        [payloadData appendData:[@"|" dataUsingEncoding:NSUTF8StringEncoding]];
        [payloadData appendData:[PushPayloadDecryptor pushEncryptionKey]];
        [self sendPayloadWithType:PLTYPE_VOIP_PUSH_NOTIFICATION_TOKEN data:payloadData];
        
        isSentVoIPPushToken = YES;
    });
}

- (void)removeVoIPPushToken {
    dispatch_sync(removeVoIPPushTokenQueue, ^{
        
        if (isRemovedVoIPPushToken == YES) {
            DDLogInfo(@"Already removed VoIP push token (apple)");
            return;
        }

        NSData *voIPPushToken = [[AppGroup userDefaults] objectForKey:kVoIPPushNotificationDeviceToken];

        if(voIPPushToken != nil) {
            [[AppGroup userDefaults] setObject:nil forKey:kVoIPPushNotificationDeviceToken];
            [[AppGroup userDefaults] synchronize];
            voIPPushToken = nil;
        }
 
        if ([self shouldRegisterPush] == NO) {
            return;
        }
        
        DDLogInfo(@"Removing VoIP push token (apple)");
        
        uint8_t voIPPushTokenType = PUSHTOKEN_TYPE_NONE;

        NSMutableData *payloadData = [NSMutableData dataWithBytes:&voIPPushTokenType length:1];
        [payloadData appendData:voIPPushToken];
        [payloadData appendData:[@"" dataUsingEncoding:NSUTF8StringEncoding]];
        [payloadData appendData:[@"|" dataUsingEncoding:NSUTF8StringEncoding]];
        [payloadData appendData:[[[NSBundle mainBundle] bundleIdentifier] dataUsingEncoding:NSASCIIStringEncoding]];
        [payloadData appendData:[@"|" dataUsingEncoding:NSUTF8StringEncoding]];
        [payloadData appendData:[PushPayloadDecryptor pushEncryptionKey]];
        [self sendPayloadWithType:PLTYPE_VOIP_PUSH_NOTIFICATION_TOKEN data:payloadData];
        
        isRemovedVoIPPushToken = YES;
    });
}

- (void)sendPushAllowedIdentities {
    if ([self shouldRegisterPush] == NO) {
        return;
    }
    
    // Disable filter by allowing all IDs; we filter pushes in our own logic now
    NSData *iddata = [NSData dataWithBytes:"\0" length:1];
    
    DDLogVerbose(@"Sending allowed identities: %@", iddata);
    [self sendPayloadWithType:PLTYPE_PUSH_ALLOWED_IDENTITIES data:iddata];
}

- (void)sendPushSound{
    if ([self shouldRegisterPush] == NO) {
        return;
    }
    
    NSString *pushSound = @"";
    DDLogInfo(@"Sending push sound: %@", pushSound);
    [self sendPayloadWithType:PLTYPE_PUSH_SOUND data:[pushSound dataUsingEncoding:NSASCIIStringEncoding]];
}

- (void)sendPushGroupSound {
    if ([self shouldRegisterPush] == NO) {
        return;
    }
    
    NSString *pushGroupSound = @"";
    
    DDLogInfo(@"Sending push group sound: %@", pushGroupSound);
    [self sendPayloadWithType:PLTYPE_PUSH_GROUP_SOUND data:[pushGroupSound dataUsingEncoding:NSASCIIStringEncoding]];
}

#pragma mark - Nonces and encryption

- (NSData*)nextClientNonce {
    char nonce[kNaClCryptoNonceSize];
    memcpy(nonce, clientCookie.bytes, kCookieLen);
    memcpy(&nonce[kCookieLen], &clientNonce, sizeof(clientNonce));
    clientNonce++;
    return [NSData dataWithBytes:nonce length:kNaClCryptoNonceSize];
}

- (NSData*)nextServerNonce {
    char nonce[kNaClCryptoNonceSize];
    memcpy(nonce, serverCookie.bytes, kCookieLen);
    memcpy(&nonce[kCookieLen], &serverNonce, sizeof(serverNonce));
    serverNonce++;
    return [NSData dataWithBytes:nonce length:kNaClCryptoNonceSize];
}

- (NSData *)encryptData:(NSData *)message key:(NSData *)key {
    if (message == nil) {
        return nil;
    }
    
    NSData *nonce = [[NaClCrypto sharedCrypto] randomBytes:kNonceLen];
    NSData *encryptedMessage = [[NaClCrypto sharedCrypto] symmetricEncryptData:message withKey:key nonce:nonce];

    NSMutableData *encryptedData = [[NSMutableData alloc] initWithData:nonce];
    [encryptedData appendData:encryptedMessage];
    
    return encryptedData;
}

#pragma mark - Connection state

- (NSString *)nameForConnectionState:(ConnectionState)state {
    return [serverConnectorConnectionState nameForConnectionState:state];
}

- (BOOL)isIPv6Connection {
    return [socket isIPv6];
}

- (BOOL)isProxyConnection {
    return [socket isProxyConnection];
}

- (void)displayServerAlert:(NSString*)alertText {
    
    if ([displayedServerAlerts containsObject:alertText])
        return;
    
    /* not shown before */
    NSDictionary *info = [NSDictionary dictionaryWithObjectsAndKeys:
                          alertText, kKeyMessage,
                          nil];
    
    [[NSNotificationCenter defaultCenter] postNotificationName:kNotificationServerMessage object:nil userInfo:info];
    
    [displayedServerAlerts addObject:alertText];
}

- (void)networkStatusDidChange:(NSNotification *)notice
{
    NetworkStatus internetStatus = [internetReachability currentReachabilityStatus];
    switch (internetStatus) {
        case NotReachable:
            DDLogNotice(@"Internet is not reachable");
            break;
        case ReachableViaWiFi:
            DDLogNotice(@"Internet is reachable via WiFi");
            break;
        case ReachableViaWWAN:
            DDLogNotice(@"Internet is reachable via WWAN");
            break;
    }
    
    if (internetStatus != lastInternetStatus) {
        DDLogNotice(@"Internet status changed - forcing reconnect");
        [self reconnect];
        lastInternetStatus = internetStatus;
    }
}

#pragma mark - SocketProtocolDelegate

- (void)didConnect {
    [serverConnectorConnectionState connected];

    /* Send client hello packet with temporary public key and client cookie */
    clientCookie = [[NaClCrypto sharedCrypto] randomBytes:kCookieLen];
    DDLogVerbose(@"Client cookie = %@", clientCookie);
    
    /* Make sure to pass everything in one writeData call, or we will get two separate TCP segments */
    struct pktClientHello clientHello;
    memcpy(clientHello.client_tempkey_pub, clientTempKeyPub.bytes, sizeof(clientHello.client_tempkey_pub));
    memcpy(clientHello.client_cookie, clientCookie.bytes, sizeof(clientHello.client_cookie));
    [socket writeWithData:[NSData dataWithBytes:&clientHello length:sizeof(clientHello)] tag:TAG_CLIENT_HELLO_SENT];
    
    /* Prepare to receive server hello packet */
    [socket readWithLength:sizeof(struct pktServerHello) timeout:kReadTimeout tag:TAG_SERVER_HELLO_READ];
}

- (void)didDisconnect {
    [serverConnectorConnectionState disconnected];

    DDLogWarn(@"Flushing incoming and interrupt outgoing queue on Task Manager");
    [TaskManager flushWithQueueType:TaskQueueTypeIncoming];
    [TaskManager interruptWithQueueType:TaskQueueTypeOutgoing];

    if (keepalive_timer != nil) {
        dispatch_source_cancel(keepalive_timer);
        keepalive_timer = nil;
    }

    [self reconnectAfterDelay];
}

- (void)didReadData:(NSData * _Nonnull)data tag:(int16_t)tag {
    switch (tag) {
        case TAG_SERVER_HELLO_READ: {
            DDLogVerbose(@"Got server hello!");
            const struct pktServerHello* serverHello = data.bytes;
            
            serverCookie = [NSData dataWithBytes:serverHello->server_cookie length:sizeof(serverHello->server_cookie)];
            DDLogVerbose(@"Server cookie = %@", serverCookie);
            
            /* decrypt server hello box */
            chosenServerKeyPub = serverKeyPub;
            NSData *serverHelloBox = [NSData dataWithBytes:serverHello->box length:sizeof(serverHello->box)];
            NSData *nonce = [self nextServerNonce];
            NSData *serverHelloBoxOpen = [[NaClCrypto sharedCrypto] decryptData:serverHelloBox withSecretKey:clientTempKeySec signKey:chosenServerKeyPub nonce:nonce];
            if (serverHelloBoxOpen == nil) {
                /* try alternate key */
                chosenServerKeyPub = serverAltKeyPub;
                serverHelloBoxOpen = [[NaClCrypto sharedCrypto] decryptData:serverHelloBox withSecretKey:clientTempKeySec signKey:chosenServerKeyPub nonce:nonce];
                if (serverHelloBoxOpen == nil) {
                    DDLogError(@"Decryption of server hello box failed");
                    [socket disconnect];
                    return;
                } else {
                    DDLogWarn(@"Using alternate server key!");
                }
            }
            
            const struct pktServerHelloBox *serverHelloBoxU = (struct pktServerHelloBox*)serverHelloBoxOpen.bytes;
            
            /* verify client cookie */
            NSData *clientCookieFromServer = [NSData dataWithBytes:serverHelloBoxU->client_cookie length:sizeof(serverHelloBoxU->client_cookie)];
            if (![clientCookieFromServer isEqualToData:clientCookie]) {
                DDLogError(@"Client cookie mismatch (mine: %@, server: %@)", clientCookie, clientCookieFromServer);
                [socket disconnect];
                return;
            }
            
            /* copy temporary server key */
            serverTempKeyPub = [NSData dataWithBytes:serverHelloBoxU->server_tempkey_pub length:sizeof(serverHelloBoxU->server_tempkey_pub)];
            
            DDLogInfo(@"Server hello successful, tempkey_pub = %@", serverTempKeyPub);
            
            /* prepare extension packet */
            NSMutableData *extensionsData = [NSMutableData data];
            
            /* client info (0x00) extension payload */
            NSData *clientVersion = [ThreemaUtility.clientVersion dataUsingEncoding:NSASCIIStringEncoding];
            [extensionsData appendData:[self makeExtensionWithType:EXTENSION_TYPE_CLIENT_INFO data:clientVersion]];
            
            /* message payload version (0x02) extension payload */
            uint8_t plv = 0x01;
            [extensionsData appendData:[self makeExtensionWithType:EXTENSION_TYPE_MESSAGE_PAYLOAD_VERSION data:[NSData dataWithBytes:&plv length:1]]];
            
            // Adding Device ID extension if is Multi Device activated
            if (deviceId != nil && [deviceId length] == kDeviceIdLen) {
                /* CSP device ID (0x01) extension payload */
                [extensionsData appendData:[self makeExtensionWithType:EXTENSION_TYPE_DEVICE_ID data:[UserSettings sharedUserSettings].deviceID]];
            }

            NSData *loginNonce = [self nextClientNonce];
            NSData *extensionsNonce = [self nextClientNonce];
            NSData *extensionsBox = [[NaClCrypto sharedCrypto] encryptData:extensionsData withPublicKey:serverTempKeyPub signKey:clientTempKeySec nonce:extensionsNonce];
            
            /* now prepare login packet */
            NSData *vouchNonce = [[NaClCrypto sharedCrypto] randomBytes:kNaClCryptoNonceSize];
            struct pktLogin login;
            memcpy(login.identity, [[MyIdentityStore sharedMyIdentityStore].identity dataUsingEncoding:NSASCIIStringEncoding].bytes, kIdentityLen);
            
            memcpy(login.client_version, "threema-clever-extension-field", 30);
            uint16_t extLen = extensionsBox.length;
            memcpy(&login.client_version[30], &extLen, sizeof(uint16_t));
            
            memcpy(login.server_cookie, serverCookie.bytes, kCookieLen);
            memcpy(login.vouch_nonce, vouchNonce.bytes, kNaClCryptoNonceSize);
            
            /* vouch subpacket */
            struct pktVouch vouch;
            memcpy(vouch.client_tempkey_pub, clientTempKeyPub.bytes, kNaClCryptoPubKeySize);
            NSData *vouchBox = [[MyIdentityStore sharedMyIdentityStore] encryptData:[NSData dataWithBytes:&vouch length:sizeof(vouch)] withNonce:vouchNonce publicKey:chosenServerKeyPub];
            memcpy(login.vouch_box, vouchBox.bytes, sizeof(login.vouch_box));
            
            /* encrypt login packet */
            NSData *loginBox = [[NaClCrypto sharedCrypto] encryptData:[NSData dataWithBytes:&login length:sizeof(login)] withPublicKey:serverTempKeyPub signKey:clientTempKeySec nonce:loginNonce];
            
            /* send it! */
            [socket writeWithData:loginBox tag:0];
            [socket writeWithData:extensionsBox tag:TAG_LOGIN_SENT];
            
            /* Prepare to receive login ack packet */
            [socket readWithLength:sizeof(struct pktLoginAck) + kNaClBoxOverhead timeout:kReadTimeout tag:TAG_LOGIN_ACK_READ];
            
            break;
        }
            
        case TAG_LOGIN_ACK_READ: {
            DDLogInfo(@"Login ack received");
            lastRead = CACurrentMediaTime();
            
            /* decrypt server hello box */
            NSData *loginAckBox = data;
            loginAckBox = [[NaClCrypto sharedCrypto] decryptData:loginAckBox withSecretKey:clientTempKeySec signKey:serverTempKeyPub nonce:[self nextServerNonce]];
            if (loginAckBox == nil) {
                DDLogError(@"Decryption of login ack failed");
                [socket disconnect];
                return;
            }
            
            /* Don't care about the contents of the login ACK for now; it only needs to decrypt correctly */
            
            reconnectAttempts = 0;
            [serverConnectorConnectionState loggedInChatServer];

            [self sendPushToken];
            
            [self sendPushAllowedIdentities];
            [self sendPushSound];
            [self sendPushGroupSound];
            
            // Remove VoIP toke if on iOS15 or above, add it if below
            if (@available(iOS 15, *)){
                [self removeVoIPPushToken];
            }
            else {
                [self sendVoIPPushToken];
            }
            
            /* Schedule task for keepalive */
            keepalive_timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, socketQueue);
            dispatch_source_set_event_handler(keepalive_timer, ^{
                [self sendEchoRequest];
            });
            dispatch_source_set_timer(keepalive_timer, dispatch_time(DISPATCH_TIME_NOW, kKeepAliveInterval * NSEC_PER_SEC),
                                      kKeepAliveInterval * NSEC_PER_SEC, NSEC_PER_SEC);
            dispatch_resume(keepalive_timer);
            
            /* Unblock incoming messages if not running multi device or already promoted to leader */
            if (deviceId == nil || [deviceId length] != kDeviceIdLen || isRolePromotedToLeader) {
                [self sendPayloadWithType:PLTYPE_UNBLOCK_INCOMING_MESSAGES data:[NSData data]];
            }
            
            /* Receive next payload header */
            [socket readWithLength:sizeof(uint16_t) timeout:-1 tag:TAG_PAYLOAD_LENGTH_READ];
            
            // Process all tasks
            TaskManager *tm = [[TaskManager alloc] init];
            [tm spool];
            
            break;
        }
            
        case TAG_PAYLOAD_LENGTH_READ: {
            uint16_t msglen = *((uint16_t*)data.bytes);
            [socket readWithLength:msglen timeout:-1 tag:TAG_PAYLOAD_READ];
            break;
        }
            
        case TAG_PAYLOAD_READ: {
            DDLogVerbose(@"Payload (%lu bytes) received", (unsigned long)data.length);
            
            lastRead = CACurrentMediaTime();
            
            dispatch_source_set_timer(keepalive_timer, dispatch_time(DISPATCH_TIME_NOW, kKeepAliveInterval * NSEC_PER_SEC),
                                      kKeepAliveInterval * NSEC_PER_SEC, NSEC_PER_SEC);
            
            /* Decrypt payload */
            NSData *plData = [[NaClCrypto sharedCrypto] decryptData:data withSecretKey:clientTempKeySec signKey:serverTempKeyPub nonce:[self nextServerNonce]];
            if (plData == nil) {
                DDLogError(@"Payload decryption failed");
                [socket disconnect];
                return;
            }
            
            struct pktPayload *pl = (struct pktPayload*)plData.bytes;
            int datalen = (int)plData.length - (int)sizeof(struct pktPayload);
            DDLogInfo(@"Decrypted payload (type %02x, data %@)", pl->type, [NSData dataWithBytes:pl->data length:datalen]);
            
            [self processPayload:pl datalen:datalen];
            
            /* Receive next payload header */
            [socket readWithLength:sizeof(uint16_t) timeout:-1 tag:TAG_PAYLOAD_LENGTH_READ];
            
            break;
        }
            
        case TAG_PAYLOAD_MEDIATOR_TRIGGERED: {
            int timeoutDownloadThumbnail = isAppInBackground || [AppGroup getActiveType] == AppGroupTypeNotificationExtension ? 20 : 0;

            TaskManager *taskManager = [[TaskManager alloc] init];
            
            MediatorMessageProcessor *processor = [[MediatorMessageProcessor alloc] initWithDeviceGroupPathKey:deviceGroupPathKey deviceID:deviceId maxBytesToDecrypt:[AppGroup getActiveType] != AppGroupTypeNotificationExtension ? MAX_BYTES_TO_DECRYPT_NO_LIMIT : MAX_BYTES_TO_DECRYPT_NOTIFICATION_EXTENSION timeoutDownloadThumbnail:timeoutDownloadThumbnail mediatorMessageProtocol:[[MediatorMessageProtocol alloc] initWithDeviceGroupPathKey:[self deviceGroupPathKey]] taskManager:taskManager messageProcessorDelegate:self];

            uint8_t type;
            NSData *result = [processor processWithMessage:data messageType:&type receivedAfterInitialQueueSend:!mediatorServerInInitialQueueSend];

            if (result != nil && (int)type == MediatorMessageProtocol.MEDIATOR_MESSAGE_TYPE_REFLECT_ACK) {
                [[NSNotificationCenter defaultCenter] postNotificationName:[TaskManager mediatorMessageAckObserverNameWithReflectID:result] object:result];
            }
            else if ((int)type == MediatorMessageProtocol.MEDIATOR_MESSAGE_TYPE_LOCK_ACK || (int)type == MediatorMessageProtocol.MEDIATOR_MESSAGE_TYPE_UNLOCK_ACK || (int)type == MediatorMessageProtocol.MEDIATOR_MESSAGE_TYPE_TRANSACTION_REJECT) {
                [self transactionResponse:type reason:result];
            }
            else if ((int)type == MediatorMessageProtocol.MEDIATOR_MESSAGE_TYPE_TRANSACTION_ENDED) {
                [taskManager spool];
            }
            else if (result != nil && (int)type == MediatorMessageProtocol.MEDIATOR_MESSAGE_TYPE_SERVER_HELLO) {
                DDLogInfo(@"Send server hello to mediator");
                [socket writeWithData:result];
            }
            else if ((int)type == MediatorMessageProtocol.MEDIATOR_MESSAGE_TYPE_SERVER_INFO) {
                DDLogInfo(@"Got mediator server info; client connected");
                [serverConnectorConnectionState loggedInMediatorServer];
            }
            else if ((int)type == MediatorMessageProtocol.MEDIATOR_MESSAGE_TYPE_REFLECTION_QUEUE_DRY) {
                mediatorServerInInitialQueueSend = NO;
            }
            else if ((int)type == MediatorMessageProtocol.MEDIATOR_MESSAGE_TYPE_ROLE_PROMOTED_TO_LEADER) {
                DDLogVerbose(@"Promoted to leader -> unblock incoming chat messages");

                if ([serverConnectorConnectionState connectionState] == ConnectionStateLoggedIn) {
                    /* Unblock incoming messages */
                    [self sendPayloadWithType:PLTYPE_UNBLOCK_INCOMING_MESSAGES data:[NSData data]];

                    /* Receive next payload header */
                    [socket readWithLength:sizeof(uint16_t) timeout:-1 tag:TAG_PAYLOAD_LENGTH_READ];
                }
                else {
                    // Queue message and send it when logged in
                    // Unblock incoming messages as soon as we're logged in
                    isRolePromotedToLeader = YES;
                }
            }
            else if (result != nil) {
                [self messageReceived:type data:result];
            }

            break;
        }
    }
}

- (NSData*)makeExtensionWithType:(uint8_t)type data:(NSData*)data {
    struct pktExtension *extension = malloc(sizeof(struct pktExtension) + data.length);
    if (!extension) {
        return nil;
    }
    extension->type = type;
    extension->length = data.length;
    memcpy(extension->data, data.bytes, data.length);
    return [NSData dataWithBytesNoCopy:extension length:(sizeof(struct pktExtension) + data.length) freeWhenDone:YES];
}

#pragma mark - ConnectionStateDelegate

- (void)connectionStateChanged:(ConnectionState)state {
    dispatch_sync(queueConnectionStateDelegate, ^{
        if (clientConnectionStateDelegates != nil && [clientConnectionStateDelegates count] > 0) {
            for (id<ConnectionStateDelegate> delegate in clientConnectionStateDelegates) {
                [delegate connectionStateChanged:state];
            }
        }
    });
}

#pragma mark - MessageListenerDelegate

- (void)messageReceived:(uint8_t)type data:(NSData * _Nonnull)data {
    dispatch_sync(queueMessageListenerDelegate, ^{
        if (clientMessageListenerDelegates != nil && [clientMessageListenerDelegates count] > 0) {
            for (id<MessageListenerDelegate> clientListener in clientMessageListenerDelegates) {
                [clientListener messageReceived:type data:data];
            }
        }
    });
}

#pragma mark - MessageProcessorDelegate

- (void)beforeDecode {
    dispatch_async(queueMessageProcessorDelegate, ^{
        [clientMessageProcessorDelegate beforeDecode];
    });
}

- (void)changedManagedObjectID:(NSManagedObjectID *)objectID {
    dispatch_async(queueMessageProcessorDelegate, ^{
        [clientMessageProcessorDelegate changedManagedObjectID:objectID];
    });
}

- (void)incomingMessageStarted:(AbstractMessage * _Nonnull)message {
    dispatch_async(queueMessageProcessorDelegate, ^{
        [clientMessageProcessorDelegate incomingMessageStarted:message];
    });
}

- (void)incomingMessageChanged:(BaseMessage * _Nonnull)message fromIdentity:(NSString * _Nonnull)fromIdentity {
    dispatch_async(queueMessageProcessorDelegate, ^{
        [clientMessageProcessorDelegate incomingMessageChanged:message fromIdentity:fromIdentity];
    });
}

- (void)incomingMessageFinished:(AbstractMessage * _Nonnull)message isPendingGroup:(BOOL)isPendingGroup {
    dispatch_async(queueMessageProcessorDelegate, ^{
        [clientMessageProcessorDelegate incomingMessageFinished:message isPendingGroup:isPendingGroup];
    });
}

- (void)taskQueueEmpty:(NSString * _Nonnull)queueTypeName {
    dispatch_async(queueMessageProcessorDelegate, ^{
        [clientMessageProcessorDelegate taskQueueEmpty:queueTypeName];
    });
}

- (void)outgoingMessageFinished:(AbstractMessage *)message {
    dispatch_async(queueMessageProcessorDelegate, ^{
        [clientMessageProcessorDelegate outgoingMessageFinished:message];
    });
}

- (void)chatQueueDry {
    dispatch_async(queueMessageProcessorDelegate, ^{
        [clientMessageProcessorDelegate chatQueueDry];
    });
}

- (void)reflectionQueueDry {
    dispatch_async(queueMessageProcessorDelegate, ^{
        [clientMessageProcessorDelegate reflectionQueueDry];
    });
}

- (void)pendingGroup:(AbstractMessage * _Nonnull)message {
    dispatch_async(queueMessageProcessorDelegate, ^{
        [clientMessageProcessorDelegate pendingGroup:message];
    });
}

- (void)processTypingIndicator:(TypingIndicatorMessage * _Nonnull)message {
    dispatch_async(queueMessageProcessorDelegate, ^{
        [clientMessageProcessorDelegate processTypingIndicator:message];
    });
}

- (void)processVoIPCall:(NSObject *)message identity:(NSString *)identity onCompletion:(void (^)(id<MessageProcessorDelegate> _Nonnull))onCompletion {
    dispatch_async(queueMessageProcessorDelegate, ^{
        [clientMessageProcessorDelegate processVoIPCall:message identity:identity onCompletion:onCompletion];
    });
}

#pragma mark - TaskExecutionTransactionDelegate

- (void)transactionResponse:(uint8_t)messageType reason:(NSData * _Nullable)reason {
    dispatch_sync(queueTaskExecutionTransactionDelegate, ^{
        [clientTaskExecutionTransactionDelegate transactionResponse:messageType reason:reason];
    });
}

#pragma mark - Notifications

- (void)identityCreated:(NSNotification*)notification {
    /* when the identity is created, we should connect */
    [self connectBy:ConnectionInitiatorApp];
    [self _connect];
}

- (void)identityDestroyed:(NSNotification*)notification {
    /* when the identity is destroyed, we must disconnect */
    if ([serverConnectorConnectionState connectionState] != ConnectionStateDisconnected) {
        DDLogInfo(@"Disconnecting because identity destroyed");
        
        /* Clear push token on server now to reduce occurrence of push messages being
           delivered to devices that don't use that particular identity anymore */
        DDLogInfo(@"Clearing push notification token");
        uint8_t pushTokenType;
#ifdef DEBUG
        pushTokenType = PUSHTOKEN_TYPE_APPLE_SANDBOX_MC;
#else
        pushTokenType = PUSHTOKEN_TYPE_APPLE_PROD_MC;
#endif
        
        NSMutableData *payloadData = [NSMutableData dataWithBytes:&pushTokenType length:1];
        NSData *pushToken = [[NaClCrypto sharedCrypto] zeroBytes:32];
        [payloadData appendData:pushToken];
        [self sendPayloadWithType:PLTYPE_PUSH_NOTIFICATION_TOKEN data:payloadData];
        
        DDLogInfo(@"Sending VoIP push notification token");
        
        uint8_t voIPPushTokenType;
#ifdef DEBUG
        voIPPushTokenType = PUSHTOKEN_TYPE_APPLE_SANDBOX;
#else
        voIPPushTokenType = PUSHTOKEN_TYPE_APPLE_PROD;
#endif
        
        NSMutableData *voipPayloadData = [NSMutableData dataWithBytes:&voIPPushTokenType length:1];
        NSData *voipPushToken = [[NaClCrypto sharedCrypto] zeroBytes:32];
        [voipPayloadData appendData:voipPushToken];
        [self sendPayloadWithType:PLTYPE_VOIP_PUSH_NOTIFICATION_TOKEN data:voipPayloadData];
        
        [self _disconnect];
    }
    
    /* destroy temporary keys, as we cannot reuse them for the new identity */
    dispatch_async(socketQueue, ^{
        clientTempKeyPub = nil;
        clientTempKeySec = nil;
    });

    /* also flush the queue so that messages stuck in it don't later cause problems
       because they have the wrong from identity */
    DDLogWarn(@"Flushing incoming and outgoing queue on Task Manager");
    [TaskManager flushWithQueueType:TaskQueueTypeIncoming];
    [TaskManager flushWithQueueType:TaskQueueTypeOutgoing];
}

@end
