//  _____ _
// |_   _| |_  _ _ ___ ___ _ __  __ _
//   | | | ' \| '_/ -_) -_) '  \/ _` |_
//   |_| |_||_|_| \___\___|_|_|_\__,_(_)
//
// Threema iOS Client
// Copyright (c) 2015-2024 Threema GmbH
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

#import "SplashViewController.h"
#import "FLAnimatedImageView.h"
#import "FLAnimatedImage.h"
#import "BundleUtil.h"
#import "RectUtil.h"
#import <QuartzCore/QuartzCore.h>
#import "NibUtil.h"
#import "RandomSeedViewController.h"
#import "MyIdentityStore.h"
#import "IdentityBackupStore.h"
#import "ServerAPIConnector.h"
#import <MBProgressHUD/MBProgressHUD.h>
#import "AppDelegate.h"
#import "UIDefines.h"
#import "UserSettings.h"
#import "NibUtil.h"
#import "ThreemaFramework.h"

#import "ConfirmIDViewController.h"
#import "PickNicknameViewController.h"
#import "LinkIDViewController.h"
#import "SyncContactsViewController.h"
#import "CompletedIDViewController.h"
#import "RestoreIdentityViewController.h"

#import "IntroQuestionView.h"
#import "LicenseStore.h"
#import "EnterLicenseViewController.h"
#import "MDMSetup.h"
#import "ContactStore.h"
#import "GatewayAvatarMaker.h"
#import "Threema-Swift.h"
#import "WorkDataFetcher.h"
#import <StoreKit/StoreKit.h>

#ifdef DEBUG
  static const DDLogLevel ddLogLevel = DDLogLevelAll;
#else
  static const DDLogLevel ddLogLevel = DDLogLevelNotice;
#endif

@interface SplashViewController () <FLAnimatedImageViewDelegate, RandomSeedViewControllerDelegate, CompletedIDDelegate, RestoreOptionDataViewControllerDelegate, RestoreOptionBackupViewControllerDelegate, RestoreSafeViewControllerDelegate, RestoreIdentityViewControllerDelegate, IntroQuestionDelegate, EnterLicenseDelegate, ZSWTappableLabelTapDelegate>

@property FLAnimatedImageView *animatedView;
@property RandomSeedViewController *randomSeedViewController;
@property RestoreOptionDataViewController *restoreOptionDataViewController;
@property RestoreOptionBackupViewController *restoreOptionBackupViewController;
@property RestoreSafeViewController *restoreSafeViewController;
@property RestoreIdentityViewController *restoreIdentityViewController;

@property IntroQuestionView *acceptPrivacyPolicyQuestionView;
@property IntroQuestionView *existingBackupQuestionView;
@property IntroQuestionView *existingIdQuestionView;

@property CGFloat parallaxDeltaX;
@property CGFloat bgImagescale;

@property NSString *idBackup;

@property BOOL triggeredSetup;
@property BOOL isRestoreOptionBackupDisplayed;

@property (assign) BOOL hasDataOnDevice;

@end

@implementation SplashViewController {
    MDMSetup *mdmSetup;
    BOOL didWorkApiFetch;
}

- (instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super initWithCoder:coder];
    if (self) {
        mdmSetup = [[MDMSetup alloc] initWithSetup:YES];
        didWorkApiFetch = NO;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    if (AppSetup.shouldDirectlyShowSetupWizard) {
        _bgImagescale = 1.5;
    } else {
        // during intro image will be zoomed
        _bgImagescale = 1.2;
    }

    [self setupControls];

    [self setupBackgroundView];

    [self setNeedsStatusBarAppearanceUpdate];

    [mdmSetup loadIDCreationValues];
    [mdmSetup loadRenewableValues];

    _threemaLogoView.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    _threemaLogoView.image = [Colors threemaLogo];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];

    _threemaLogoView.hidden = YES;
}

- (void)setupBackgroundView {
    CGFloat width = self.view.frame.size.width;
    CGFloat height = self.view.frame.size.height;

    _parallaxDeltaX = - width*_bgImagescale/20.0;

    CGRect bgRect = CGRectMake(0.0, 0.0, width*(_bgImagescale*2), height*_bgImagescale);
    bgRect = [RectUtil rect:bgRect centerIn:self.view.frame];
    // fix for iPad landscape
    _bgView.frame = CGRectMake(bgRect.origin.x, bgRect.origin.y, bgRect.size.width, bgRect.size.height);

    [self.view sendSubviewToBack:_bgView];
}

- (void)setupAnimatedView {
    if (_animatedView == nil) {
        CGFloat logoScale = 2.2;
        CGRect rect = CGRectMake(0, 0, 250.0/logoScale, 300.0/logoScale);
        rect = [RectUtil rect:rect centerIn:self.view.frame round:YES];

        _animatedView = [[FLAnimatedImageView alloc] initWithFrame:rect];
        
        NSString *animationName = @"logoAnimation";
        if (ThreemaAppObjc.current == ThreemaAppOnPrem) {
            animationName = [NSString stringWithFormat:@"%@_onprem", animationName];
        }
        else if (ThreemaAppObjc.current == ThreemaAppWork || ThreemaAppObjc.current == ThreemaAppBlue) {
            animationName = [NSString stringWithFormat:@"%@_work", animationName];
        }

        NSURL *url = [BundleUtil URLForResource:animationName withExtension:@"gif"];
        if (url != nil) {
            FLAnimatedImage *image = [FLAnimatedImage animatedImageWithGIFData:[NSData dataWithContentsOfURL:url]];
            _animatedView.animatedImage = image;
            _animatedView.delegate = self;
        }
    }
}

- (void)setupControls {
    
    _privacyView.hidden = YES;
    _privacyView.frame = [RectUtil rect:_privacyView.frame centerHorizontalIn:_containerView.frame];
    _controlsView.hidden = YES;
    _controlsView.frame = [RectUtil rect:_controlsView.frame centerHorizontalIn:_containerView.frame];
    
    _setupButton.backgroundColor = Colors.primaryWizard;
    _setupButton.layer.cornerRadius = 5;
    _setupButton.accessibilityIdentifier = @"SplashViewControllerSetupButton";
    [_setupButton setTitleColor:Colors.textSetup forState:UIControlStateNormal];
    
    _restoreButton.backgroundColor = Colors.primaryWizard;
    _restoreButton.layer.borderWidth = 1;
    _restoreButton.layer.borderColor = _setupButton.backgroundColor.CGColor;
    _restoreButton.layer.cornerRadius = 5;
    _restoreButton.titleLabel.adjustsFontSizeToFitWidth = YES;
    _restoreButton.titleLabel.minimumScaleFactor = 0.6;
    _restoreButton.accessibilityIdentifier = @"SplashViewControllerRestoreButton";
    [_restoreButton setTitleColor:Colors.textSetup forState:UIControlStateNormal];

    _setupTitleLabel.textColor = Colors.textSetup;
    _setupTitleLabel.accessibilityElementsHidden = true;
    
    _restoreTitleLabel.textColor = Colors.textSetup;
    _restoreTitleLabel.accessibilityElementsHidden = true;
    
    _welcomeLabel.text = [BundleUtil localizedStringForKey:@"lets_get_started"];
    
    _restoreTitleLabel.text = [NSString stringWithFormat:[BundleUtil localizedStringForKey:@"restore_title_text"], [ThreemaAppObjc appName]];
    _setupTitleLabel.text = [NSString stringWithFormat:[BundleUtil localizedStringForKey:@"setup_title_text"], [ThreemaAppObjc appName]];
    
    [_setupButton setTitle:[BundleUtil localizedStringForKey:@"setup_threema"] forState:UIControlStateNormal];
    [_restoreButton setTitle:[BundleUtil localizedStringForKey:@"restore_id"] forState:UIControlStateNormal];
    
    if (ThreemaAppObjc.current == ThreemaAppOnPrem) {
        _privacyPolicyInfo.hidden = true;
    }
    else {
        NSString *privacyPolicyText;

        if ([LicenseStore requiresLicenseKey]) {
            privacyPolicyText = [NSString stringWithFormat:[BundleUtil localizedStringForKey:@"privacy_policy_about_work"], [ThreemaAppObjc appName]];
        } else {
            privacyPolicyText = [BundleUtil localizedStringForKey:@"privacy_policy_about"];
        }
        
        _privacyPolicyInfo.font = [UIFont systemFontOfSize:16.0];
        _privacyPolicyInfo.tapDelegate = self;
        NSDictionary *normalAttributes = @{NSFontAttributeName: _privacyPolicyInfo.font, NSForegroundColorAttributeName: [UIColor whiteColor]};
        NSDictionary *linkAttributes = @{@"ZSWTappableLabelTappableRegionAttributeName": @YES,
                                         @"ZSWTappableLabelHighlightedForegroundAttributeName": Colors.red,
                                         NSForegroundColorAttributeName: Colors.textWizardLink,
                                         NSUnderlineStyleAttributeName: @(NSUnderlineStyleSingle),
                                         @"NSTextCheckingResult": @1
        };
        
        NSMutableAttributedString *attributedString = [[NSMutableAttributedString alloc] initWithString:privacyPolicyText attributes:normalAttributes];
        CGRect infoRect = [attributedString boundingRectWithSize:CGSizeMake(_privacyView.frame.size.width, 400.0) options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading context:nil];
        if (MAX([UIScreen mainScreen].bounds.size.height, [UIScreen mainScreen].bounds.size.width) <= 480) {
            /* iPhone 4s */
            _welcomeLabel.frame = CGRectMake(_welcomeLabel.frame.origin.x, _welcomeLabel.frame.origin.y - 20.0, _welcomeLabel.frame.size.width, _welcomeLabel.frame.size.height);
            _privacyPolicyInfo.frame = CGRectMake(_privacyPolicyInfo.frame.origin.x, _privacyPolicyInfo.frame.origin.y - 50.0, infoRect.size.width, infoRect.size.height + 20.0);
        } else {
            _privacyPolicyInfo.frame = CGRectMake(_privacyPolicyInfo.frame.origin.x, _privacyPolicyInfo.frame.origin.y, infoRect.size.width, infoRect.size.height + 20.0);
        }
        [attributedString addAttributes:linkAttributes range:[privacyPolicyText rangeOfString:[BundleUtil localizedStringForKey:@"privacy_policy_about_link"]]];
        _privacyPolicyInfo.attributedText = attributedString;
        _privacyPolicyInfo.isAccessibilityElement = YES;
    }
    
    [self setHasDataOnDevice:[AppSetup hasPreexistingDatabaseFile]];
}

- (BOOL)prefersStatusBarHidden {
    return YES;
}

- (BOOL)shouldAutorotate {
    return NO;
}

-(UIInterfaceOrientationMask)supportedInterfaceOrientations {
    if (SYSTEM_IS_IPAD) {
        return UIInterfaceOrientationMaskAll;
    } else {
        return UIInterfaceOrientationMaskPortrait;
    }
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];

    _threemaLogoView.frame = CGRectMake(_threemaLogoView.frame.origin.x, self.view.safeAreaLayoutGuide.layoutFrame.origin.y + 26.0, _threemaLogoView.frame.size.width, _threemaLogoView.frame.size.height);
    
    [self checkLicenseAndThreemaMDM];
}

- (void)checkLicenseAndThreemaMDM {
    if (didWorkApiFetch == NO) {
        if ([[LicenseStore sharedLicenseStore] isValid] == NO) {
            [self performLicenseCheck];
        }
        else {
            [WorkDataFetcher checkUpdateThreemaMDM:^{
                // Reload MDM parameter, could be changed after work data fetch
                [mdmSetup loadIDCreationValues];
                [mdmSetup loadRenewableValues];

                didWorkApiFetch = YES;

                [self presentUI];
            } onError:^(NSError *error) {
                [UIAlertTemplate showAlertWithOwner:self title:[BundleUtil localizedStringForKey:@"work_data_fetch_failed_title"] message:[BundleUtil localizedStringForKey:@"work_data_fetch_failed_message"] actionOk:^(UIAlertAction *action __unused)  {
                    exit(0);
                }];
                return;
            }];
        }
    }
    else {
        [self presentUI];
    }
}

- (void)presentUI {
    _restoreButton.hidden = [mdmSetup disableBackups];

    if ([mdmSetup isSafeRestoreForce]) {
        [self showRestoreSafeViewController:[self hasDataOnDevice]];
        [self slideOut:self fromRightToLeft:YES onCompletion:nil];
        [self slideIn:_restoreSafeViewController fromLeftToRight:YES  onCompletion:nil];
    } else if ([mdmSetup hasIDBackup] && AppSetup.isCompleted == false) {
        // TODO: (IOS-4531) This will run a full Safe restore again even if the restore completed and only the steps for `.identitySetupComplete` (i.e. app setup steps) are left to run
        [self restoreIDFromMDM];
    } else if (AppSetup.shouldDirectlyShowSetupWizard) {
        [self presentPageViewController];
    } else {
        // Show logo if `shouldDirectlyShowSetupWizard` is false
        _threemaLogoView.hidden = NO;

        [self setupAnimatedView];
        [self checkRefreshStoreReceipt];

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1200 * NSEC_PER_MSEC)), dispatch_get_main_queue(), ^{
            if (_animatedView.superview == nil) {
                [_containerView addSubview:_animatedView];
            }
        });
    }
}

- (void)slidePrivacyControlsIn {
    CGRect viewFrame = self.view.safeAreaLayoutGuide.layoutFrame;
    
    CGRect privacyTargetRect;
    
    if (MAX([UIScreen mainScreen].bounds.size.height, [UIScreen mainScreen].bounds.size.width) <= 480) {
        /* iPhone 4s */
        privacyTargetRect = [RectUtil setYPositionOf:_privacyView.frame y:120.0];
    } else {
        privacyTargetRect = [RectUtil setYPositionOf:_privacyView.frame y:170.0];
    }
    
    CGRect animationTargetRect = [RectUtil setYPositionOf:_animatedView.frame y:privacyTargetRect.origin.y - _animatedView.frame.size.height];

    CGRect privacySourceRect = [RectUtil setYPositionOf:_privacyView.frame y:_privacyView.frame.origin.y];

    CGRect controlsTargetRect;
    if (MAX([UIScreen mainScreen].bounds.size.height, [UIScreen mainScreen].bounds.size.width) <= 480) {
        /* iPhone 4s */
        controlsTargetRect = [RectUtil setYPositionOf:_controlsView.frame y:privacyTargetRect.origin.y + privacyTargetRect.size.height - 40.0];
    } else {
        controlsTargetRect = [RectUtil setYPositionOf:_controlsView.frame y:privacyTargetRect.origin.y + privacyTargetRect.size.height];
    }
    
    CGRect controlsSourceRect = [RectUtil setYPositionOf:_controlsView.frame y:viewFrame.size.height];

    _privacyView.hidden = NO;
    _privacyView.alpha = 0.0;
    _privacyView.frame = privacySourceRect;
    _controlsView.hidden = NO;
    _controlsView.alpha = 0.0;
    _controlsView.frame = controlsSourceRect;

    [UIView animateWithDuration:1.2 delay:0.0 usingSpringWithDamping:0.9 initialSpringVelocity:10.0 options:0 animations:^{
        _privacyView.alpha = 1.0;
        _privacyView.frame = privacyTargetRect;
        _animatedView.frame = animationTargetRect;
        _controlsView.alpha = 1.0;
        _controlsView.frame = controlsTargetRect;
    } completion:^(BOOL finished) {
        UIAccessibilityPostNotification(UIAccessibilityScreenChangedNotification, self.welcomeLabel);
        
        // Deactivate Multi Device if is enabled
        if ([[UserSettings sharedUserSettings] enableMultiDevice] == YES) {
            [[ServerConnector sharedServerConnector] deactivateMultiDevice];
            
            NSString *title = [BundleUtil localizedStringForKey:@"multi_device_linked_id_missing_title"];
            NSString *message = [BundleUtil localizedStringForKey:@"multi_device_linked_id_missing_message"];
            NSString *linkButton = [BundleUtil localizedStringForKey:@"multi_device_linked_id_missing_reset_button"];
            [UIAlertTemplate showAlertWithOwner:self title:title message:message titleOk:linkButton actionOk:^(UIAlertAction * _Nonnull action) {
                NSURL *url = [NSURL URLWithString:@"https://threema.ch/faq/md_reset"];
                [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
            }];
        }
    }];
}

- (void)restoreIDFromMDM {
    [self setAcceptPrivacyPolicyValues:AcceptPrivacyPolicyVariantImplicitly];
    [mdmSetup restoreIDBackupOnCompletion:^{
        [self presentPageViewController];
    } onError:^(NSError *error) {
        _restoreIdentityViewController = [self.storyboard instantiateViewControllerWithIdentifier:@"RestoreIdentityViewController"];
        _restoreIdentityViewController.delegate = self;
        _restoreIdentityViewController.backupData = mdmSetup.idBackup;
        _restoreIdentityViewController.passwordData = mdmSetup.idBackupPassword;
        [_restoreIdentityViewController setup];

        [self slideOut:self fromRightToLeft:YES onCompletion:nil];
        [self slideIn:_restoreIdentityViewController fromLeftToRight:YES onCompletion:^{
            // make sure controls are visible
            _privacyView.alpha = 1.0;
            _privacyView.hidden = NO;
            _privacyView.frame = [RectUtil rect:_privacyView.frame centerIn:self.view.frame];

            // show error message
            [_restoreIdentityViewController handleError:error];
        }];
    }];
}

- (void)performLicenseCheck {
    LicenseStore *licenseStore = [LicenseStore sharedLicenseStore];
    [licenseStore performLicenseCheckWithCompletion:^(BOOL success) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (success) {
                [self checkLicenseAndThreemaMDM];
            } else {
                // present anyway, to also fail early if there is no network connection
                [self presentLicenseViewController];
            }
        });
    }];
}

- (void)presentLicenseViewController {
    BOOL showInfoView = false;
    LicenseStore *licenseStore = [LicenseStore sharedLicenseStore];
    if (licenseStore.licenseUsername == nil && licenseStore.licensePassword == nil && licenseStore.onPremConfigUrl == nil) {
        showInfoView = true;
    }
    
    EnterLicenseViewController *viewController = [EnterLicenseViewController instantiate];
    viewController.delegate = self;
    viewController.doWorkApiFetch = NO;
    viewController.modalPresentationStyle = UIModalPresentationFullScreen;
    viewController.view.hidden = true;
    
    EnterLicenseInfoViewController *ec = [EnterLicenseInfoViewController new];
    
    if (showInfoView) {
        UIViewController *enterLicenseInfoViewController = [ec viewControllerWithDismiss:^{
            [viewController dismissViewControllerAnimated:YES completion:nil];
        }];
        enterLicenseInfoViewController.modalPresentationStyle = SYSTEM_IS_IPAD ? UIModalPresentationFormSheet : UIModalPresentationFullScreen;
        
        [self presentViewController:viewController animated:NO completion:^{
            [viewController presentViewController:enterLicenseInfoViewController animated:NO completion:^{
                viewController.view.hidden = false;
            }];
        }];
    }
    else {
        [self presentViewController:viewController animated:NO completion:^{
            viewController.view.hidden = false;
        }];
    }
}

- (void)presentPageViewController {
    ConfirmIDViewController *confirmVc = [self.storyboard instantiateViewControllerWithIdentifier:@"ConfirmIDViewController"];
    SafeViewController *safeVc = [self.storyboard instantiateViewControllerWithIdentifier:@"SafeSetup"];
    PickNicknameViewController *pickNicknameVc = [self.storyboard instantiateViewControllerWithIdentifier:@"PickNicknameViewController"];
    LinkIDViewController *linkIdVc = [self.storyboard instantiateViewControllerWithIdentifier:@"LinkIDViewController"];
    SyncContactsViewController *syncVc = [self.storyboard instantiateViewControllerWithIdentifier:@"SyncContactsViewController"];
    CompletedIDViewController *complededVc = [self.storyboard instantiateViewControllerWithIdentifier:@"CompletedIDViewController"];
    complededVc.delegate = self;

    ParallaxPageViewController *pageVc = [self.storyboard instantiateViewControllerWithIdentifier:@"ParallaxPageViewController"];

    if ([mdmSetup skipWizard]) {
        pageVc.viewControllers = @[complededVc];
    } else {
        if ([mdmSetup isSafeBackupDisable] || ([mdmSetup isSafeBackupForce] && [mdmSetup isSafeBackupPasswordPreset])) {
            pageVc.viewControllers = @[confirmVc, pickNicknameVc, linkIdVc, syncVc, complededVc];
        } else {
            pageVc.viewControllers = @[confirmVc, safeVc, pickNicknameVc, linkIdVc, syncVc, complededVc];
        }
    }

    pageVc.bgView = _bgView;
    pageVc.parallaxFactor = [NSNumber numberWithDouble: fabs(_parallaxDeltaX/self.view.frame.size.width)];
    pageVc.modalPresentationStyle = UIModalPresentationFullScreen;
    
    // make sure to clean up
    [_randomSeedViewController willMoveToParentViewController:nil];
    [_restoreIdentityViewController willMoveToParentViewController:nil];
    [self presentViewController:pageVc animated:NO completion:^{
        [_randomSeedViewController.view removeFromSuperview];
        [_randomSeedViewController removeFromParentViewController];

        [_restoreIdentityViewController.view removeFromSuperview];
        [_restoreIdentityViewController removeFromParentViewController];
    }];
}

- (void)showApplicaitonUI {
    [[AppDelegate sharedAppDelegate] completedIDSetup];
}

#pragma mark - IntroQuestionView

- (void)hideAcceptPrivacyPolicyQuestion {
    [self hideMessageView:_acceptPrivacyPolicyQuestionView];
}

- (void)showIDBackupQuestion {
    
    if (_existingBackupQuestionView == nil) {
        _existingBackupQuestionView = (IntroQuestionView *)[NibUtil loadViewFromNibWithName:@"IntroQuestionView"];
        _existingBackupQuestionView.tag = 1;
        _existingBackupQuestionView.questionLabel.text = [BundleUtil localizedStringForKey:@"backup_found_message"];;
        _existingBackupQuestionView.delegate = self;
        _existingBackupQuestionView.frame = [RectUtil rect:_existingBackupQuestionView.frame centerIn:self.view.frame round:YES];
        
        [self.view addSubview:_existingBackupQuestionView];
    }
    
    [self showMessageView:_existingBackupQuestionView];
}

- (void)hideIDBackupQuestion {
    [self hideMessageView:_existingBackupQuestionView];
}

- (void)showIDExistsQuestion {
    
    if (_existingIdQuestionView == nil) {
        _existingIdQuestionView = (IntroQuestionView *)[NibUtil loadViewFromNibWithName:@"IntroQuestionView"];
        _existingIdQuestionView.tag = 2;
        _existingIdQuestionView.questionLabel.text = [[NSString alloc] initWithFormat:[BundleUtil localizedStringForKey:@"id_exists"], [[MyIdentityStore sharedMyIdentityStore] identity]];
        _existingIdQuestionView.delegate = self;
        _existingIdQuestionView.frame = [RectUtil rect:_existingIdQuestionView.frame centerIn:self.view.frame round:YES];
        
        [self.view addSubview:_existingIdQuestionView];
    }
    
    [self showMessageView:_existingIdQuestionView];
}

- (void)hideIDExistsQuestion {
    [self hideMessageView:_existingIdQuestionView];
}


#pragma mark - FLAnimatedImageViewDelegate

- (void)animatedImageViewWillDrawFrame:(NSUInteger)frameIndex {
    if ((int)frameIndex == 0 && _privacyView.hidden == NO) {
        // stay at last frame
        _animatedView.currentFrameIndex = 98;
    }
    else if ((int)frameIndex == 0) {
        CGFloat duration = 1.0;
        UIViewAnimationOptions options = UIViewAnimationOptionCurveEaseInOut;
        [UIView animateWithDuration:duration delay:0.0 options:options animations:^{
            _bgImagescale = 1.5;
            [self setupBackgroundView];
        } completion:nil];
    }
    else if (ThreemaAppObjc.current == ThreemaAppOnPrem) {
        if ((int)frameIndex == 62  && _privacyView.hidden == YES) {
            [self slidePrivacyControlsIn];
        }
        else if ((int)frameIndex == 88 && _privacyView.hidden == NO) {
            // go back for jumping dots
            _animatedView.currentFrameIndex = 73;
        }
    }
    else if ((int)frameIndex == 72  && _privacyView.hidden == YES) {
        [self slidePrivacyControlsIn];
    }
    else if ((int)frameIndex == 98 && _privacyView.hidden == NO) {
        // go back for jumping dots
        _animatedView.currentFrameIndex = 83;
    }
}

#pragma mark - manage views

- (void)showSetupViewController {
    _randomSeedViewController = [self.storyboard instantiateViewControllerWithIdentifier:@"RandomSeedViewController"];
    _randomSeedViewController.delegate = self;
    [_randomSeedViewController setup];

    [self setAcceptPrivacyPolicyValues:AcceptPrivacyPolicyVariantExplicitly];
}

- (void)showRestoreOptionDataViewController {
    _restoreOptionDataViewController = [self.storyboard instantiateViewControllerWithIdentifier:@"RestoreOptionDataViewController"];
    _restoreOptionDataViewController.delegate = self;

    [self setAcceptPrivacyPolicyValues:AcceptPrivacyPolicyVariantExplicitly];
}

- (void)showRestoreOptionBackupViewController {
    _restoreOptionBackupViewController = [self.storyboard instantiateViewControllerWithIdentifier:@"RestoreOptionBackupViewController"];
    _restoreOptionBackupViewController.delegate = self;
    _restoreOptionBackupViewController.hasDataOnDevice = [self hasDataOnDevice];

    [self setAcceptPrivacyPolicyValues:AcceptPrivacyPolicyVariantExplicitly];
}

- (void)showRestoreSafeViewController:(BOOL)doRestoreIdentityOnly {
    _restoreSafeViewController = [self.storyboard instantiateViewControllerWithIdentifier:@"RestoreSafeViewController"];
    _restoreSafeViewController.delegate = self;
    _restoreSafeViewController.restoreIdentityOnly = doRestoreIdentityOnly;
}

- (void)showRestoreIdentityViewController:(NSString *)backupData {
    _restoreIdentityViewController = [self.storyboard instantiateViewControllerWithIdentifier:@"RestoreIdentityViewController"];
    _restoreIdentityViewController.delegate = self;
    _restoreIdentityViewController.backupData = backupData;
}

- (void)showRestoreIdentityViewController {
    _triggeredSetup = NO;
    
    _isRestoreOptionBackupDisplayed = ([self.childViewControllers count] > 0 && [self.childViewControllers[0] isKindOfClass:[RestoreOptionBackupViewController class]]) != 0 ? YES : NO;
    
    if (_isRestoreOptionBackupDisplayed) {
        [self showRestoreIdentityViewController:nil];
        [self slideOut:_restoreOptionBackupViewController fromRightToLeft:YES onCompletion:nil];
        [self slideIn:_restoreIdentityViewController fromLeftToRight:YES onCompletion:nil];
    } else if ([self.childViewControllers count] == 0) {
        [self showRestoreIdentityViewController:nil];
        [self slideOut:self fromRightToLeft:YES onCompletion:nil];
        [self slideIn:_restoreIdentityViewController fromLeftToRight:YES onCompletion:nil];
    }
}

- (void)slideIn:(UIViewController *)child fromLeftToRight:(BOOL)toRight onCompletion:(void(^)(void))onCompletion {
    UIView *childView;
    if ([child isKindOfClass:[SplashViewController class]]) {
        childView = _containerView;
    } else {
        [self addChildViewController:child];

        childView = child.view;
        [self.view addSubview:childView];
    }

    //start position
    if (toRight) {
        childView.frame = [RectUtil setXPositionOf:childView.frame x:self.view.frame.size.width];
    } else {
        childView.frame = [RectUtil setXPositionOf:childView.frame x:self.view.frame.size.width * -1.0];
    }

    [child beginAppearanceTransition:YES animated:YES];
    [UIView animateWithDuration:0.5 animations:^{
        //end position
        childView.frame = [RectUtil setXPositionOf:childView.frame x:0];

        CGFloat parallaxFactor = toRight == YES ? 1.0 : -1.0;
        _bgView.frame = [RectUtil offsetRect:_bgView.frame byX:_parallaxDeltaX*parallaxFactor byY:0.0];
    } completion:^(BOOL finished) {
        [child endAppearanceTransition];
        [child didMoveToParentViewController:self];

        if (onCompletion) {
            onCompletion();
        }
    }];
}

- (void)slideOut:(UIViewController *)child fromRightToLeft:(BOOL)toLeft onCompletion:(void(^)(void))onCompletion {
    UIView *childView;
    if ([child isKindOfClass:[SplashViewController class]]) {
        childView = _containerView;
    } else {
        childView = child.view;
    }

    //start position
    childView.frame = [RectUtil setXPositionOf:childView.frame x:0];

    [child beginAppearanceTransition:NO animated:YES];
    [UIView animateWithDuration:0.5 animations:^{
        //end position
        if (toLeft) {
            childView.frame = [RectUtil setXPositionOf:childView.frame x:self.view.frame.size.width * -1.0];
        } else {
            childView.frame = [RectUtil setXPositionOf:childView.frame x:self.view.frame.size.width];
        }
    } completion:^(BOOL finished) {
        [child endAppearanceTransition];
        if (![child isKindOfClass:[SplashViewController class]]) {
            [childView removeFromSuperview];
            [child removeFromParentViewController];
        }

        if (onCompletion) {
            onCompletion();
        }
    }];
}

- (void)createIdentity {    
    if (self.view != nil) {
        [MBProgressHUD showHUDAddedTo:self.view animated:YES];
    }
    
    [[[ServerAPIConnector alloc] init] createIdentityWithStore:[MyIdentityStore sharedMyIdentityStore] onCompletion:^(MyIdentityStore *store) {
        [AppSetup setState:AppSetupStateIdentityAdded];

        [[LicenseStore sharedLicenseStore] performUpdateWorkInfo];

        [MBProgressHUD hideHUDForView:self.view animated:YES];

        [self presentPageViewController];
    } onError:^(NSError *error) {
        [MBProgressHUD hideHUDForView:self.view animated:YES];
        UIAlertController *errAlert = [UIAlertController alertControllerWithTitle:error.localizedDescription message:error.localizedFailureReason preferredStyle:UIAlertControllerStyleAlert];
        [errAlert addAction:[UIAlertAction actionWithTitle:[BundleUtil localizedStringForKey:@"try_again"] style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction * action) {
            [self createIdentity];
        }]];
        switch (ThreemaAppObjc.current) {
            case ThreemaAppThreema:
            case ThreemaAppGreen:
                break;
            case ThreemaAppWork:
            case ThreemaAppOnPrem:
            case ThreemaAppBlue:
                [errAlert addAction:[UIAlertAction actionWithTitle:[BundleUtil localizedStringForKey:@"enter_license_enter_new_credentials"] style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction * action) {
                    [self cancelPressed];
                    [self presentLicenseViewController];
                }]];
                break;
        }
        [[[AppDelegate sharedAppDelegate] currentTopViewController] presentViewController:errAlert animated:YES completion:nil];
    }];
}


- (void)setAcceptPrivacyPolicyValues:(int)variant {
    [[UserSettings sharedUserSettings] setAcceptedPrivacyPolicyDate:[NSDate date]];
    [[UserSettings sharedUserSettings] setAcceptedPrivacyPolicyVariant:variant];
}

#pragma mark - private

- (NSString *)getIDBackup {
    NSString *backupData = [IdentityBackupStore loadIdentityBackup];
    if (backupData != nil && [[MyIdentityStore sharedMyIdentityStore] isValidBackupFormat:backupData]) {
        return backupData;
    }

    return nil;
}

- (BOOL)checkForIDBackup {
    _idBackup = [self getIDBackup];

    if (_idBackup) {
        [self showIDBackupQuestion];
        return YES;
    }

    return NO;
}

- (BOOL)checkForIDExists {
    if (AppSetup.isIdentityProvisioned) {
        [self showIDExistsQuestion];
        return YES;
    }
    return NO;
}

- (void)checkRefreshStoreReceipt {
    if ([LicenseStore requiresLicenseKey]) {
        return;
    }
    
    NSURL *receiptUrl = [[NSBundle mainBundle] appStoreReceiptURL];
    if (receiptUrl && ![[NSFileManager defaultManager] fileExistsAtPath:receiptUrl.path]) {
        // No receipt available; try to refresh
        SKReceiptRefreshRequest *refreshRequest = [[SKReceiptRefreshRequest alloc] initWithReceiptProperties:nil];
        [refreshRequest start];        
    }
}

#pragma mark - IBActions

- (IBAction)setupAction:(id)sender {
    _triggeredSetup = YES;
    // Check for ID Export, if Threema Work or if Threema and has no existing ID
    if ([LicenseStore requiresLicenseKey] || (![LicenseStore requiresLicenseKey] && ![self checkForIDExists])) {
        if ([self checkForIDBackup] == NO) {
            [self showSetupViewController];
            [self slideOut:self fromRightToLeft:YES onCompletion:nil];
            [self slideIn:_randomSeedViewController fromLeftToRight:YES onCompletion:nil];
        }
    }
}

- (IBAction)restoreAction:(id)sender {
    _triggeredSetup = NO;
    
    if ([mdmSetup isSafeRestoreDisable]) {
        if ([self checkForIDBackup] == NO) {
            [self showRestoreIdentityViewController:nil];
            [self slideOut:self fromRightToLeft:YES onCompletion:nil];
            [self slideIn:_restoreIdentityViewController fromLeftToRight:YES onCompletion:nil];
        }
    } else {
        if ([self hasDataOnDevice] == YES) {
            [self showRestoreOptionDataViewController];
            [self slideOut:self fromRightToLeft:YES onCompletion:nil];
            [self slideIn:_restoreOptionDataViewController fromLeftToRight:YES onCompletion:nil];
        } else {
            [self showRestoreOptionBackupViewController];
            [self slideOut:self fromRightToLeft:YES onCompletion:nil];
            [self slideIn:_restoreOptionBackupViewController fromLeftToRight:YES onCompletion:nil];
        }
    }
}


#pragma mark - IntroQuestionViewDelegate

- (void)selectedYes:(IntroQuestionView *)sender {
    if (sender.tag == 1) {
        [self hideIDBackupQuestion];

        [self showRestoreIdentityViewController:_idBackup];
        [self slideOut:self fromRightToLeft:YES onCompletion:nil];
        [self slideIn:_restoreIdentityViewController fromLeftToRight:YES onCompletion:nil];
    }
    else if (sender.tag == 2) {
        [self hideIDExistsQuestion];
        [self presentPageViewController];
    }
}

- (void)selectedNo:(IntroQuestionView *)sender {
    if (sender.tag == 1) {
        [self hideIDBackupQuestion];

        if (_triggeredSetup) {
            [self showSetupViewController];
            [self slideOut:self fromRightToLeft:YES onCompletion:nil];
            [self slideIn:_randomSeedViewController fromLeftToRight:YES onCompletion:nil];
        } else {
            [self showRestoreIdentityViewController:nil];
            [self slideOut:self fromRightToLeft:YES onCompletion:nil];
            [self slideIn:_restoreIdentityViewController fromLeftToRight:YES onCompletion:nil];
        }
    }
    else if (sender.tag == 2) {
        [self hideIDExistsQuestion];
        
        [self showSetupViewController];
        [self slideOut:self fromRightToLeft:YES onCompletion:nil];
        [self slideIn:_randomSeedViewController fromLeftToRight:YES onCompletion:nil];
    }
}

- (void)selectedOk:(IntroQuestionView *)sender {
    [self hideAcceptPrivacyPolicyQuestion];
}


#pragma mark - RandomSeedViewControllerDelegate

- (void)generatedRandomSeed:(NSData *)seed {
    [[MyIdentityStore sharedMyIdentityStore] generateKeyPairWithSeed:seed];

    [self createIdentity];
}

#pragma mark - CompletedIDDelegate

- (void)completedIDSetup {
    if ([[DatabaseManager dbManager] shouldUpdateProtection]) {
        MyIdentityStore *myIdentityStore = [MyIdentityStore sharedMyIdentityStore];
        [myIdentityStore updateConnectionRights];
        [[DatabaseManager dbManager] updateProtection];
    }
    
    // Delete decrypted backup data from application documents folder
    [[FileUtility shared]  deleteAt: [[[FileUtility shared] appDocumentsDirectory] URLByAppendingPathComponent:@"safe-backup.json"]];
    
    // The App Setup Steps should be called as the last step of the onboarding and if they fail they need to be retried.
    // We log the steps (incl. retries) to a separate file in the document directory such that this can be requested in
    // support inquiries.
    
    NSURL *appSetupStepsLogFile = [LogManager appSetupStepsLogFile];
    [LogManager deleteLogFile:appSetupStepsLogFile];
    [LogManager addFileLogger:appSetupStepsLogFile];
    
    [self runAppSetupStepsWithCompletion:^{
        [LogManager removeFileLogger:appSetupStepsLogFile];
        
        // The setup is only completed if the App Setup Steps are successfully completed
        [AppSetup setState:AppSetupStateComplete];
        
        [[AppDelegate sharedAppDelegate] setIsWorkContactsLoading:true];
        [WorkDataFetcher checkUpdateWorkDataForce:YES onCompletion:^{
            [[AppDelegate sharedAppDelegate] setIsWorkContactsLoading:false];
        } onError:^(NSError *error) {
            [[AppDelegate sharedAppDelegate] setIsWorkContactsLoading:false];
        }];
        
        [self showApplicaitonUI];
        
        // Delete log file again
        [LogManager deleteLogFile:appSetupStepsLogFile];
    }];
}

/// Run the App Setup Steps and show a retry alert if they fail
/// - Parameter onCompletion: Called when App Setup Steps are successfully completed
- (void)runAppSetupStepsWithCompletion:(nonnull void(^)(void))onCompletion {
    if ([AppDelegate sharedAppDelegate].currentTopViewController.view) {
        [MBProgressHUD showHUDAddedTo:[AppDelegate sharedAppDelegate].currentTopViewController.view animated:YES];
    }
    
    AppSetupStepsObjC *appSetupSteps = [[AppSetupStepsObjC alloc] init];
    [appSetupSteps runWithCompletionHandler:^(NSError * _Nullable error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if ([AppDelegate sharedAppDelegate].currentTopViewController.view) {
                [MBProgressHUD hideHUDForView:[AppDelegate sharedAppDelegate].currentTopViewController.view animated:YES];
            }
            
            if (error != nil) {
                DDLogError(@"App Setup Steps failed: %@", error);
                UIViewController *currentTopViewController = [[AppDelegate sharedAppDelegate] currentTopViewController];
                [UIAlertTemplate showAlertWithOwner:currentTopViewController title:[BundleUtil localizedStringForKey:@"app_setup_steps_failed_title"] message:[BundleUtil localizedStringForKey:@"app_setup_steps_failed_message"] titleOk:[BundleUtil localizedStringForKey:@"try_again"] actionOk:^(UIAlertAction * _Nonnull action) {
                    DDLogNotice(@"Retry App Setup Steps...");
                    [self runAppSetupStepsWithCompletion:onCompletion];
                }];
            }
            else {
                onCompletion();
            }
        });
    }];
}

- (void)cancelPressed {
    [self slideOut:_randomSeedViewController fromRightToLeft:NO onCompletion:nil];
    [self slideIn:self fromLeftToRight:NO onCompletion:nil];
}

#pragma mark - RestoreOptionDataViewControllerDelegate

- (void)optionDataKeepLocal {
    _restoreOptionDataViewController.delegate = nil;
    [self showRestoreOptionBackupViewController];
    [self slideOut:_restoreOptionDataViewController fromRightToLeft:YES onCompletion:nil];
    [self slideIn:_restoreOptionBackupViewController fromLeftToRight:YES onCompletion:nil];
}

- (void)optionDataCancelled {
    _restoreOptionDataViewController.delegate = nil;
    [self slideOut:_restoreOptionDataViewController fromRightToLeft:NO onCompletion:nil];
    [self slideIn:self fromLeftToRight:NO onCompletion:nil];
}

#pragma mark - RestoreOptionBackupViewControllerDelegate

- (void)restoreSafe {
    _restoreOptionBackupViewController.delegate = nil;
    [self showRestoreSafeViewController:NO];
    [self slideOut:_restoreOptionBackupViewController fromRightToLeft:YES onCompletion:nil];
    [self slideIn:_restoreSafeViewController fromLeftToRight:YES  onCompletion:nil];
}

- (void)restoreIdentityFromSafe {
    _restoreOptionBackupViewController.delegate = nil;
    [self showRestoreSafeViewController:YES];
    [self slideOut:_restoreOptionBackupViewController fromRightToLeft:YES onCompletion:nil];
    [self slideIn:_restoreSafeViewController fromLeftToRight:YES  onCompletion:nil];
}

- (void)restoreIdentity {
    _restoreOptionBackupViewController.delegate = nil;
    [self slideOut:_restoreOptionBackupViewController fromRightToLeft:YES onCompletion:nil];

    _isRestoreOptionBackupDisplayed = YES;

    if ([self checkForIDBackup] == NO) {
        [self showRestoreIdentityViewController:nil];
        [self slideIn:_restoreIdentityViewController fromLeftToRight:YES onCompletion:nil];
    }
}

- (void)restoreCancelled {
    _isRestoreOptionBackupDisplayed = NO;
    _restoreOptionBackupViewController.delegate = nil;
    [self slideOut:_restoreOptionBackupViewController fromRightToLeft:NO onCompletion:nil];

    if ([self hasDataOnDevice]) {
        [self showRestoreOptionDataViewController];
        [self slideIn:_restoreOptionDataViewController fromLeftToRight:NO onCompletion:nil];
    } else {
        [self slideIn:self fromLeftToRight:NO  onCompletion:nil];
    }
}

#pragma mark - RestoreSafeViewControllerDelegate

- (void)restoreSafeCancelled {
    _restoreSafeViewController.delegate = nil;
    [self showRestoreOptionBackupViewController];
    [self slideOut:_restoreSafeViewController fromRightToLeft:NO onCompletion:nil];
    [self slideIn:_restoreOptionBackupViewController fromLeftToRight:NO onCompletion:nil];
}

- (void)restoreSafeDone {
    _restoreSafeViewController.delegate = nil;
    
    [self completedIDSetup];
}

#pragma mark - RestoreIdentityViewControllerDelegate

- (void)restoreIdentityCancelled {
    _restoreIdentityViewController.delegate = nil;
    [self slideOut:_restoreIdentityViewController fromRightToLeft:NO onCompletion:nil];

    if (!_triggeredSetup && _isRestoreOptionBackupDisplayed) {
        [self showRestoreOptionBackupViewController];
        [self slideIn:_restoreOptionBackupViewController fromLeftToRight:NO onCompletion:nil];
    } else if (!_isRestoreOptionBackupDisplayed) {
        [self slideIn:self fromLeftToRight:NO onCompletion:nil];
    }
}

- (void)restoreIdentityDone {
    _restoreIdentityViewController.delegate = nil;
    
    [AppSetup setState:AppSetupStateIdentityAdded];
    
    [self presentPageViewController];
}

#pragma mark - EnterLicenseDelegate

- (void)licenseConfirmed {
    [self dismissViewControllerAnimated:YES completion:nil];
    [self checkLicenseAndThreemaMDM];
}

#pragma mark - ZSWTappableLabel delegate

- (void)tappableLabel:(ZSWTappableLabel *)tappableLabel tappedAtIndex:(NSInteger)idx withAttributes:(NSDictionary *)attributes {
    UIViewController *vc = [[PrivacyPolicyViewController alloc]init];
    UINavigationController *nc = [[UINavigationController alloc] initWithRootViewController:vc];
    [self presentViewController:nc animated:YES completion:nil];
}

@end
