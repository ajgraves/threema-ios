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

#import "AvatarMaker.h"
#import "ContactEntity.h"
#import "Conversation.h"
#import "ImageData.h"
#import "UIImage+Mask.h"
#import "UserSettings.h"
#import "GatewayAvatarMaker.h"
#import "BundleUtil.h"
#import "UIImage+ColoredImage.h"
#import "UIImage+Resize.h"
#import "ThreemaFramework/ThreemaFramework-swift.h"

static AvatarMaker *sharedInstance = nil;

@interface AvatarMaker ()

@property NSCache *avatarCache;
@property NSCache *maskedImageCache;
@property EntityManager *backgroundEntityManager;
@property NSNumber* invalidatedBackgroundEntityManager;

@end

@implementation AvatarMaker

+ (AvatarMaker* _Nonnull)sharedAvatarMaker {
    static dispatch_once_t pred;
    
    dispatch_once(&pred, ^{
        sharedInstance = [[AvatarMaker alloc] init];
    });
    
    return sharedInstance;
}

+ (void)clearCache {
    [sharedInstance.avatarCache removeAllObjects];
}

+ (UIImage *_Nonnull)avatarWithString:(NSString *_Nullable)string size:(CGFloat)size {
    CGSize canvasSize = CGSizeMake(size, size);
    UIColor *fontColor = Colors.textLight;
    UIFont *initialsFont = [UIFont fontWithName:@"Helvetica" size:0.4*size];
    
    UIGraphicsBeginImageContextWithOptions(canvasSize, NO, 1);
    CGContextRef context = UIGraphicsGetCurrentContext();
    UIGraphicsPushContext(context);
    
    /* Circle */
    CGFloat lineWidth = 0.018f * size;
    CGContextSetLineWidth(context, lineWidth);
    CGContextSetStrokeColorWithColor(context, fontColor.CGColor);
    CGContextSetFillColorWithColor(context, [UIColor clearColor].CGColor);
    
    CGRect circleRect = CGRectMake(0, 0, canvasSize.width, canvasSize.height);
    circleRect = CGRectInset(circleRect, lineWidth/2, lineWidth/2);
    
    CGContextFillEllipseInRect(context, circleRect);
    CGContextStrokeEllipseInRect(context, circleRect);
    
    /* Initials */
    if (string) {
        [fontColor set];
        CGSize textSize = [string sizeWithAttributes:@{NSFontAttributeName: initialsFont}];
        [string drawAtPoint:CGPointMake((canvasSize.width - textSize.width)/2, (canvasSize.height - textSize.height)/2) withAttributes:@{NSFontAttributeName: initialsFont, NSForegroundColorAttributeName: fontColor}];
    }
    UIGraphicsPopContext();
    UIImage *avatar = UIGraphicsGetImageFromCurrentImageContext();
    
    UIGraphicsEndImageContext();
    
    return avatar;
}


- (instancetype)init {
    self = [super init];
    if (self) {
        _avatarCache = [[NSCache alloc] init];
        _maskedImageCache = [[NSCache alloc] init];
        _backgroundEntityManager = [[EntityManager alloc] initWithChildContextForBackgroundProcess:YES];
        _invalidatedBackgroundEntityManager = @NO;
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationDidReceiveMemoryWarning:) name:UIApplicationDidReceiveMemoryWarningNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(managedObjectImageChanged:) name:kNotificationContactImageChanged object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(managedObjectImageChanged:) name:kNotificationGroupConversationImageChanged object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(managedObjectContextObjectsDidChange:) name:NSManagedObjectContextDidSaveObjectIDsNotification object:nil];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)applicationDidReceiveMemoryWarning:(NSNotification*)notification {
    [_avatarCache removeAllObjects];
    [_maskedImageCache removeAllObjects];
}

- (void)managedObjectContextObjectsDidChange:(NSNotification*)notification {
    if ([notification.userInfo[NSInsertedObjectIDsKey] isKindOfClass:NSSet.class]) {
        NSSet *insertedObjects = (NSSet *)notification.userInfo[NSInsertedObjectIDsKey];
        for (NSManagedObject *object in insertedObjects) {
            // isKindOf:Conversation.class would always return nil. Thus we use string comparison here
            if([[[object entity] name] isEqualToString:Conversation.entity.name] || [[[object entity] name] isEqualToString:ContactEntity.entity.name]) {
                [self setInvalidateBackgroundEntityManager:@YES];
            }
        }
    }
}

- (NSNumber *)invalidateBackgroundEntityManager {
    @synchronized (_invalidatedBackgroundEntityManager) {
        return _invalidatedBackgroundEntityManager;
    }
}

- (void)setInvalidateBackgroundEntityManager:(NSNumber *)code {
    @synchronized (_invalidatedBackgroundEntityManager) {
        _invalidatedBackgroundEntityManager = code;
    }
}

- (void)performOnCurrentEntityManager:(void (^)(void))block {
    // Waiting for locks on the main thread is a bad idea in general
    // But especially bad here because in order to leave the critical section
    // `_backgroundEntityManager` might need to synchronously call into main thread
    // itself causing this to deadlock.
    if ([NSThread isMainThread] ) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
            [self performOnCurrentEntityManager:block];
        });
    } else {
        @synchronized (_backgroundEntityManager) {
            if ([[self invalidatedBackgroundEntityManager] isEqualToNumber:@YES]) {
                _backgroundEntityManager = [[EntityManager alloc] initWithChildContextForBackgroundProcess:YES];
                [self setInvalidateBackgroundEntityManager:@NO];

                [_backgroundEntityManager performBlockAndWait:block];

            } else {
                [_backgroundEntityManager performBlockAndWait:block];
            }
        }
    }
}

- (void)clearCacheForProfilePicture {
    [sharedInstance.maskedImageCache removeObjectForKey:@"myProfilePicture"];
    [_maskedImageCache removeAllObjects];
}

- (void)resetContext {
    [self setInvalidateBackgroundEntityManager:@YES];
}

- (void)managedObjectImageChanged:(NSNotification*)notification {
    NSManagedObject *managedObject = notification.object;
    [_maskedImageCache removeObjectForKey:managedObject.objectID];
}

- (void)avatarForContactEntity:(ContactEntity*)contact size:(CGFloat)size masked:(BOOL)masked onCompletion:(void (^)(UIImage *avatarImage, NSString *identity))onCompletion {
    if (contact) {
        [self performOnCurrentEntityManager:^{
            ContactEntity *privateContact = [_backgroundEntityManager.entityFetcher existingObjectWithID:contact.objectID];
            __block NSString *identity = privateContact.identity;
            __block UIImage *avatarImage = [self avatarForContactEntity:privateContact size:size masked:masked];
            dispatch_async(dispatch_get_main_queue(), ^{
                onCompletion(avatarImage, identity);
            });
        }];
    }
    else {
        dispatch_async(dispatch_get_main_queue(), ^{
            onCompletion(nil, nil);
        });
    }
}

- (UIImage*)avatarForContactEntity:(ContactEntity*)contact size:(CGFloat)size masked:(BOOL)masked {
    return [self avatarForContactEntity:contact size:size masked:masked scaled:YES];
}

- (UIImage*)avatarForContactEntity:(ContactEntity*)contact size:(CGFloat)size masked:(BOOL)masked scaled:(BOOL)scaled {
    /* If this contact has sent us an image, we'll use that and not make an avatar */
    CGFloat sizeScaled = size;
    if (scaled)
        sizeScaled = sizeScaled * [UIScreen mainScreen].scale;
    if (contact.contactImage != nil && [UserSettings sharedUserSettings].showProfilePictures) {
        if (contact.contactImage.data != nil) {
            UIImage *avatar;
            if (masked) {
                avatar = [self maskedImageForContactEntity:contact ownImage:NO];
            } else {
                avatar = [UIImage imageWithData:contact.contactImage.data];
            }
            if (avatar != nil) {
                return [avatar resizedImageWithContentMode:UIViewContentModeScaleAspectFit bounds:CGSizeMake(sizeScaled, sizeScaled) interpolationQuality:kCGInterpolationHigh];
            }
        }
    }
    
    /* If this contact has an image (but not from abRecord), we'll use that and not the received image */
    if (contact.imageData != nil && (contact.cnContactId == nil)) {
        UIImage *avatar;
        if (masked) {
            avatar = [self maskedImageForContactEntity:contact ownImage:YES];
        } else {
            avatar = [UIImage imageWithData:contact.imageData];
        }
        if (avatar != nil) {
            return [avatar resizedImageWithContentMode:UIViewContentModeScaleAspectFit bounds:CGSizeMake(sizeScaled, sizeScaled) interpolationQuality:kCGInterpolationHigh];
        }
    }
    
    /* If this contact has an image from abRecord, we'll use that and not a generic icon */
    if (contact.imageData != nil && contact.cnContactId != nil) {
        UIImage *avatar;
        if (masked) {
            avatar = [self maskedImageForContactEntity:contact ownImage:YES];
        } else {
            avatar = [UIImage imageWithData:contact.imageData];
        }
        if (avatar != nil) {
            return [avatar resizedImageWithContentMode:UIViewContentModeScaleAspectFit bounds:CGSizeMake(sizeScaled, sizeScaled) interpolationQuality:kCGInterpolationHigh];
        }
    }
    
    if (contact.isGatewayId) {
        UIImage *avatar = [BundleUtil imageNamed:@"Asterisk"];
        avatar = [avatar resizedImageWithContentMode:UIViewContentModeScaleAspectFit bounds:CGSizeMake(sizeScaled, sizeScaled) interpolationQuality:kCGInterpolationHigh];
        return [avatar imageWithTint:Colors.textLight];
    }
    
    /* If there is no contact, then use a generic icon */
    if (contact == nil) {
        UIImage *avatar = [self unknownPersonImage];
        avatar = [avatar resizedImageWithContentMode:UIViewContentModeScaleAspectFit bounds:CGSizeMake(sizeScaled, sizeScaled) interpolationQuality:kCGInterpolationHigh];
        return [avatar imageWithTint:Colors.textLight];
    }
    
    UIImage *avatar = [self initialsAvatarForContactEntity:contact size:sizeScaled masked:masked scaled:NO];
    
    return avatar;
}

- (UIImage *)initialsAvatarForContactEntity:(nonnull ContactEntity *)contact size:(CGFloat)size masked:(BOOL)masked {
    return [self initialsAvatarForContactEntity:contact size:size masked:masked scaled:YES];
}

- (UIImage *)initialsAvatarForContactEntity:(nonnull ContactEntity *)contact size:(CGFloat)size masked:(BOOL)masked scaled:(BOOL)scaled {
    CGFloat sizeScaled = size;
    if (scaled)
        sizeScaled = sizeScaled * [UIScreen mainScreen].scale;
    
    NSString *initials = [self initialsForContactEntity:contact];
    
    /* check cache first */
    NSString *cacheKey = [NSString stringWithFormat:@"%@-%.0f", initials, sizeScaled];
    UIImage *cachedImage = [_avatarCache objectForKey:cacheKey];
    if (cachedImage != nil) {
        return cachedImage;
    }
    
    UIImage *avatar = [AvatarMaker avatarWithString:initials size:sizeScaled];
    
    /* Put in cache */
    [_avatarCache setObject:avatar forKey:cacheKey];
    
    return avatar;
}

- (void)avatarForConversation:(Conversation*)conversation size:(CGFloat)size masked:(BOOL)masked onCompletion:(void (^)(UIImage *avatarImage, NSManagedObjectID *objectID))onCompletion {
    __block NSManagedObjectID *objectId = conversation.objectID;
    [self performOnCurrentEntityManager:^{
        Conversation *privateConversation = [_backgroundEntityManager.entityFetcher existingObjectWithID:objectId];
        UIImage *avatarImage = [self avatarForConversation:privateConversation size:size masked:masked];
        dispatch_async(dispatch_get_main_queue(), ^{
            onCompletion(avatarImage, objectId);
        });
    }];
}

- (UIImage* _Nullable)avatarForConversation:(Conversation* _Nonnull)conversation size:(CGFloat)size masked:(BOOL)masked {
    return [self avatarForConversation:conversation size:size masked:masked scaled:YES];
}

- (UIImage* _Nullable)avatarForConversation:(Conversation* _Nonnull)conversation size:(CGFloat)size masked:(BOOL)masked scaled:(BOOL)scaled {
    if (conversation.groupId != nil || conversation.distributionList != nil) {
        /* For groups, use the group image if available, or a default image otherwise */
        if (conversation.groupImage != nil) {
            UIImage *avatar;
            if (masked) {
                avatar = [self maskedImageForGroupConversation:conversation];
            } else {
                avatar = [UIImage imageWithData:conversation.groupImage.data];
            }
            if (scaled)
                size = size * [UIScreen mainScreen].scale;
            return [avatar resizedImageWithContentMode:UIViewContentModeScaleAspectFit bounds:CGSizeMake(size, size) interpolationQuality:kCGInterpolationHigh];
        } else {
            if (conversation.distributionList != nil) {
                UIImage *groupImage = [BundleUtil imageNamed:@"UnknownDistributionList"];
                if (scaled)
                    size = size * [UIScreen mainScreen].scale;
                groupImage = [groupImage resizedImageWithContentMode:UIViewContentModeScaleAspectFit bounds:CGSizeMake(size, size) interpolationQuality:kCGInterpolationHigh];
                return [groupImage imageWithTint:Colors.textLight];
            } else {
                UIImage *groupImage = [BundleUtil imageNamed:@"UnknownGroup"];
                if (scaled)
                    size = size * [UIScreen mainScreen].scale;
                groupImage = [groupImage resizedImageWithContentMode:UIViewContentModeScaleAspectFit bounds:CGSizeMake(size, size) interpolationQuality:kCGInterpolationHigh];
                return [groupImage imageWithTint:Colors.textLight];
            }
        }
    }
    else {
        return [self avatarForContactEntity:conversation.contact size:size masked:masked];
    }
}

- (UIImage * _Nullable)avatarForFirstName:(NSString * _Nullable)firstName lastName:(NSString *_Nullable)lastName size:(CGFloat)size {
    CGFloat sizeScaled = size * [UIScreen mainScreen].scale;;
    
    NSString *initials = nil;
    
    if (firstName.length > 0 && lastName.length > 0) {
        if ([UserSettings sharedUserSettings].displayOrderFirstName)
            initials = [NSString stringWithFormat:@"%@%@", [firstName substringToIndex:1], [lastName substringToIndex:1]];
        else
            initials = [NSString stringWithFormat:@"%@%@", [lastName substringToIndex:1], [firstName substringToIndex:1]];
    } else {
        return [self unknownPersonImage];
    }
    
    /* check cache first */
    NSString *cacheKey = [NSString stringWithFormat:@"%@-%.0f", initials, sizeScaled];
    UIImage *cachedImage = [_avatarCache objectForKey:cacheKey];
    if (cachedImage != nil) {
        return cachedImage;
    }
    
    UIImage *avatar = [AvatarMaker avatarWithString:initials size:sizeScaled];
    
    /* Put in cache */
    [_avatarCache setObject:avatar forKey:cacheKey];
    
    return avatar;
}

- (UIImage* _Nullable)maskedProfilePicture:(UIImage * _Nonnull)image size:(CGFloat)size {
    
    if (image == nil) {
        return [self unknownPersonImage];
    }

    UIImage *maskedImage = [_maskedImageCache objectForKey:@"myProfilePicture"];
    
    if (maskedImage == nil) {
        maskedImage = [AvatarMaker maskImage:image];
        if (maskedImage) {
            [_maskedImageCache setObject:maskedImage forKey:@"myProfilePicture"];
        }
    }
    
    return maskedImage;
}

- (nullable UIImage *)callBackgroundForContactEntity:(nonnull ContactEntity *)contact {
    /* If this contact has send us a image, we'll use that and not make an avatar */
    if (contact.contactImage != nil && [UserSettings sharedUserSettings].showProfilePictures) {
        return [UIImage imageWithData:contact.contactImage.data];
    }
    
    /* If this contact has an image (but not from abRecord), we'll use that and not the received image */
    if (contact.imageData != nil && contact.cnContactId == nil) {
        return [UIImage imageWithData:contact.imageData];
    }
    
    /* If this contact has an image from abRecord, we'll use that and not a generic icon */
    if (contact.imageData != nil && contact.cnContactId != nil) {
        return [UIImage imageWithData:contact.imageData];
    }
    
    NSString *initials = [self initialsForContactEntity:contact];
    
    /* check cache first */
    NSString *cacheKey = [NSString stringWithFormat:@"%@-background", initials];
    UIImage *cachedImage = [_avatarCache objectForKey:cacheKey];
    if (cachedImage != nil) {
        return cachedImage;
    }
    
    UIImage *avatar = [AvatarMaker avatarWithString:initials size:[[UIScreen mainScreen] bounds].size.width];
    
    /* Put in cache */
    [_avatarCache setObject:avatar forKey:cacheKey];
    
    return avatar;
}

- (UIImage*)maskedImageForContactEntity:(ContactEntity*)contact ownImage:(BOOL)ownImage {
    if (ownImage) {
        return [self maskedImageForManagedObject:contact imageData:contact.imageData];
    }
    else {
        return [self maskedImageForManagedObject:contact imageData:contact.contactImage.data];
    }
}

- (UIImage*)maskedImageForGroupConversation:(Conversation*)conversation {
    return [self maskedImageForManagedObject:conversation imageData:conversation.groupImage.data];
}

- (UIImage*)maskedImageForManagedObject:(NSManagedObject*)managedObject imageData:(NSData*)imageData {
    if (imageData == nil) {
        return nil;
    }
    
    UIImage *maskedImage = [_maskedImageCache objectForKey:managedObject.objectID];
    
    if (maskedImage == nil) {
        maskedImage = [UIImage imageWithData:imageData];
        maskedImage = [AvatarMaker maskImage:maskedImage];
        if (maskedImage) {
            [_maskedImageCache setObject:maskedImage forKey:managedObject.objectID];
        }
    }
    
    return maskedImage;
}

+ (UIImage * _Nullable)maskImage:(UIImage * _Nonnull)image {
    UIImage *personMask = [BundleUtil imageNamed:@"PersonMask"];
    UIImage *maskedImage = [image maskWithImage:personMask];
    
    return maskedImage;
}

- (UIImage * _Nullable)companyImage {
    return [[BundleUtil imageNamed:@"Asterisk"] imageWithTint:UIColor.primary];
}

- (UIImage * _Nullable)unknownPersonImage {
    return [[BundleUtil imageNamed:@"UnknownPerson"] imageWithTint:Colors.textLight];
}

- (UIImage * _Nullable)unknownGroupImage {
    return [[BundleUtil imageNamed:@"UnknownGroup"] imageWithTint:Colors.textLight];
}

- (UIImage * _Nullable)unknownDistributionListImage {
    return [[BundleUtil imageNamed:@"UnknownDistributionList"] imageWithTint:Colors.textLight];
}

- (NSString*)initialsForContactEntity:(ContactEntity*)contact {
    if (contact.firstName.length > 0 && contact.lastName.length > 0) {
        if ([UserSettings sharedUserSettings].displayOrderFirstName)
            return [NSString stringWithFormat:@"%@%@", [contact.firstName substringToIndex:1], [contact.lastName substringToIndex:1]];
        else
            return [NSString stringWithFormat:@"%@%@", [contact.lastName substringToIndex:1], [contact.firstName substringToIndex:1]];
    } else if (contact.displayName.length >= 2) {
        return [contact.displayName substringToIndex:2];
    } else {
        return @"-";
    }
}

- (BOOL)isDefaultAvatarForContactEntity:(ContactEntity *_Nullable)contact {
    /* If this contact has send us a image, we'll use that and not make an avatar */
    if (contact.contactImage != nil && [UserSettings sharedUserSettings].showProfilePictures) {
        return false;
    }
    
    /* If this contact has an image (but not from abRecord), we'll use that and not the received image */
    if (contact.imageData != nil && contact.cnContactId == nil) {
        return false;
    }
    
    /* If this contact has an image from abRecord, we'll use that and not a generic icon */
    if (contact.imageData != nil && contact.cnContactId != nil) {
        return false;
    }
    
    return true;
}

@end
