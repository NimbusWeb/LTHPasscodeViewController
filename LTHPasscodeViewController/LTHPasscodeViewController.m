//
//  PasscodeViewController.m
//  LTHPasscodeViewController
//
//  Created by Roland Leth on 9/6/13.
//  Copyright (c) 2013 Roland Leth. All rights reserved.
//

#import "LTHPasscodeViewController.h"
#import "LTHKeychainUtils.h"
#import <LocalAuthentication/LocalAuthentication.h>
#import "PasscodeLockerView.h"

#define LTHiPad ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad)

#if __IPHONE_OS_VERSION_MIN_REQUIRED >= 70000
#define LTHFailedAttemptLabelHeight [_failedAttemptLabel.text sizeWithAttributes: @{NSFontAttributeName : _labelFont}].height
#else
// Thanks to Kent Nguyen - https://github.com/kentnguyen
#define LTHFailedAttemptLabelHeight [_failedAttemptLabel.text sizeWithFont:_labelFont].height
#endif

@interface PasscodeWindow : UIWindow

@end

@implementation PasscodeWindow

-(void) dismiss {
    self.hidden = YES;
    if (@available(iOS 13.0, *)) {
        self.windowScene = nil;
    }
}

@end

// MARK: Please read
/*
 Using windows[0] instead of keyWindow due to an issue with UIAlertViews / UIActionSheets - displaying the lockscreen when an alertView / actionSheet is visible, or displaying one after the lockscreen is visible results in a few cases:
 * the lockscreen and the keyboard appear on top the av/as, but
   * the dimming of the av/as appears on top the lockscreen;
   * if the app is closed and reopened, the order becomes av/as - lockscreen - dimming - keyboard.
 * the lockscreen always appears behind the av/as, while the keyboard
   * doesn't appear until the av/as is dismissed;
   * appears on top on the av/as - if the app is closed and reopened with the av/as visible.
 * the lockscreen appears above the av/as, while the keyboard appears below, so there's no way to enter the passcode.

 The current implementation shows the lockscreen behind the av/as.

 Relevant links:
 * https://github.com/rolandleth/LTHPasscodeViewController/issues/16
 * https://github.com/rolandleth/LTHPasscodeViewController/issues/164 (the description found above)
 * https://stackoverflow.com/questions/19816142/uialertviews-uiactionsheets-and-keywindow-problems

 Any help would be greatly appreciated.
 */

#ifdef LTH_IS_APP_EXTENSION
#define LTHMainWindow [UIApplication sharedApplication].keyWindow
#else
#define LTHMainWindow [UIApplication sharedApplication].windows.firstObject
#endif

@interface LTHPasscodeViewController () <UITextFieldDelegate, PasscodeLockerViewDelegate>
@property (nonatomic, strong) UIView      *coverView;
@property (nonatomic, strong) UIView      *animatingView;
@property (nonatomic, strong) UIView      *complexPasscodeOverlayView;
@property (nonatomic, strong) UIView      *simplePasscodeView;
@property (nonatomic, strong) UIImageView *backgroundImageView;

@property (nonatomic, strong) UITextField *passcodeTextField;
@property (nonatomic, strong) UILabel     *enterPasscodeInfoLabel;

@property (nonatomic, strong) NSMutableArray<UITextField *> *digitTextFieldsArray;

@property (nonatomic, strong) UILabel     *failedAttemptLabel;
@property (nonatomic, strong) UILabel     *enterPasscodeLabel;
@property (nonatomic, strong) UIButton    *OKButton;

@property (nonatomic, strong) NSString    *tempPasscode;
@property (nonatomic, assign) NSInteger   failedAttempts;

@property (nonatomic, assign) CGFloat     modifierForBottomVerticalGap;
@property (nonatomic, assign) CGFloat     fontSizeModifier;

@property (nonatomic, assign) BOOL        newPasscodeEqualsOldPasscode;
@property (nonatomic, assign) BOOL        passcodeAlreadyExists;
@property (nonatomic, assign) BOOL        usesKeychain;
@property (nonatomic, assign) BOOL        displayedAsModal;
@property (nonatomic, assign) BOOL        displayedAsLockScreen;
@property (nonatomic, assign) BOOL        isUsingNavBar;
@property (nonatomic, assign) BOOL        isSimple; // YES by default
@property (nonatomic, assign) BOOL        isUserConfirmingPasscode;
@property (nonatomic, assign) BOOL        isUserBeingAskedForNewPasscode;
@property (nonatomic, assign) BOOL        isUserTurningPasscodeOff;
@property (nonatomic, assign) BOOL        isUserChangingPasscode;
@property (nonatomic, assign) BOOL        isUserEnablingPasscode;
@property (nonatomic, assign) BOOL        isUserSwitchingBetweenPasscodeModes; // simple/complex
@property (nonatomic, assign) BOOL        timerStartInSeconds;
@property (nonatomic, assign) BOOL        isUsingBiometrics;
@property (nonatomic, assign) BOOL        useFallbackPasscode;
@property (nonatomic, assign) BOOL        isAppNotificationsObserved;
@property (nonatomic, strong) LAContext   *biometricsContext;

@property (weak, nonatomic) IBOutlet UITextField *updatedPasscodeField1;
@property (weak, nonatomic) IBOutlet UITextField *updatedPasscodeField2;
@property (weak, nonatomic) IBOutlet UITextField *updatedPasscodeField3;
@property (weak, nonatomic) IBOutlet UITextField *updatedPasscodeField4;

@property (copy, nonatomic) NSString * updatedEnteringPasscode;
@property (weak, nonatomic) PasscodeLockerView * internalPasscodeView;
@property (assign, nonatomic) BOOL isTempararlyDisabled;
@property (strong, nonatomic) PasscodeWindow * internalWindow;
@end

@implementation LTHPasscodeViewController

static const NSInteger LTHMinPasscodeDigits = 4;
static const NSInteger LTHMaxPasscodeDigits = 10;

#pragma mark - Public, class methods

+ (BOOL)doesPasscodeExist {
    return [[self sharedUser] _doesPasscodeExist];
}


+ (NSTimeInterval)timerDuration {
    return [[self sharedUser] _timerDuration];
}


+ (void)saveTimerDuration:(NSTimeInterval)duration {
    [[self sharedUser] _saveTimerDuration:duration];
}


+ (NSTimeInterval)timerStartTime {
    return [[self sharedUser] _timerStartTime];
}


+ (void)saveTimerStartTime {
    [[self sharedUser] _saveTimerStartTime];
}


+ (BOOL)didPasscodeTimerEnd {
    return [[self sharedUser] _didPasscodeTimerEnd];
}


+ (void)deletePasscodeAndClose {
    [self deletePasscode];
    [self close];
}


+ (void)close {
    [[self sharedUser] _close];
}


+ (void)deletePasscode {
    [[self sharedUser] _deletePasscode];
}


+ (void)useKeychain:(BOOL)useKeychain {
    [[self sharedUser] _useKeychain:useKeychain];
}

- (UIImage *)imageForFingerPrint {
    return nil;
}

- (UIImage *)imageForFaceId {
    return nil;
}

#pragma mark - Private methods
- (void)_close {
    if (_displayedAsLockScreen) [self _dismissMe];
    else [self _cancelAndDismissMe];
}


- (void)_useKeychain:(BOOL)useKeychain {
    _usesKeychain = useKeychain;
}


- (BOOL)_doesPasscodeExist {
    if ([LTHKeychainUtils getPasswordForUsername:_keychainPasscodeIsSimpleUsername
                                  andServiceName:_keychainServiceName
                                           error:nil]) {
        _isSimple = [[LTHKeychainUtils getPasswordForUsername:_keychainPasscodeIsSimpleUsername
                                               andServiceName:_keychainServiceName
                                                        error:nil] boolValue];
    } else {
        _isSimple = YES;
    }

    return [self _passcode].length != 0;
}


- (NSTimeInterval)_timerDuration {
    if (!_usesKeychain &&
        [self.delegate respondsToSelector:@selector(timerDuration)]) {
        return [self.delegate timerDuration];
    }

    NSString *keychainValue =
    [LTHKeychainUtils getPasswordForUsername:_keychainTimerDurationUsername
                              andServiceName:_keychainServiceName
                                       error:nil];
    if (!keychainValue) return -1;
    return keychainValue.doubleValue;
}


- (void)_saveTimerDuration:(NSTimeInterval) duration {
    if (!_usesKeychain &&
        [self.delegate respondsToSelector:@selector(saveTimerDuration:)]) {
        [self.delegate saveTimerDuration:duration];

        return;
    }

    [LTHKeychainUtils storeUsername:_keychainTimerDurationUsername
                        andPassword:[NSString stringWithFormat: @"%.6f", duration]
                     forServiceName:_keychainServiceName
                     updateExisting:YES
                              error:nil];
}


- (NSTimeInterval)_timerStartTime {
    if (!_usesKeychain &&
        [self.delegate respondsToSelector:@selector(timerStartTime)]) {
        return [self.delegate timerStartTime];
    }

    NSString *keychainValue =
    [LTHKeychainUtils getPasswordForUsername:_keychainTimerStartUsername
                              andServiceName:_keychainServiceName
                                       error:nil];
    if (!keychainValue) return -1;
    return keychainValue.doubleValue;
}


- (void)_saveTimerStartTime {
    if (!_usesKeychain &&
        [self.delegate respondsToSelector:@selector(saveTimerStartTime)]) {
        [self.delegate saveTimerStartTime];

        return;
    }

    [LTHKeychainUtils storeUsername:_keychainTimerStartUsername
                        andPassword:[NSString stringWithFormat: @"%.6f",
                                     [NSDate timeIntervalSinceReferenceDate]]
                     forServiceName:_keychainServiceName
                     updateExisting:YES
                              error:nil];
}


- (BOOL)_didPasscodeTimerEnd {
    if (!_usesKeychain &&
        [self.delegate respondsToSelector:@selector(didPasscodeTimerEnd)]) {
        return [self.delegate didPasscodeTimerEnd];
    }

    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    // startTime wasn't saved yet (first app use and it crashed, phone force
    // closed, etc) if it returns -1.
    return (int64_t) (now - [self _timerStartTime]) >= (int64_t)([self _timerDuration])
            || (int64_t)([self _timerStartTime]) == (int64_t)-1
            || (int64_t)now <= (int64_t)([self _timerStartTime]);
    // If the date was set in the past, this would return false.
    // It won't register as false, even right as it is being enabled,
    // because the saving alone takes 0.002+ seconds on a MBP 2.6GHz i7.
}


- (void)_deletePasscode {
    if (!_usesKeychain &&
        [self.delegate respondsToSelector:@selector(deletePasscode)]) {
        [self.delegate deletePasscode];

        return;
    }

    [LTHKeychainUtils deleteItemForUsername:_keychainPasscodeUsername
                             andServiceName:_keychainServiceName
                                      error:nil];
}


- (void)_savePasscode:(NSString *)passcode {
    if (!_passcodeAlreadyExists &&
        [self.delegate respondsToSelector:@selector(passcodeWasEnabled)]) {
        [self.delegate passcodeWasEnabled];
    }

    _passcodeAlreadyExists = YES;

    if (!_usesKeychain &&
        [self.delegate respondsToSelector:@selector(savePasscode:)]) {
        [self.delegate savePasscode:passcode];

        return;
    }

    [LTHKeychainUtils storeUsername:_keychainPasscodeUsername
                        andPassword:passcode
                     forServiceName:_keychainServiceName
                     updateExisting:YES
                              error:nil];

    [LTHKeychainUtils storeUsername:_keychainPasscodeIsSimpleUsername
                        andPassword:[NSString stringWithFormat:@"%@", [self isSimple] ? @"YES" : @"NO"]
                     forServiceName:_keychainServiceName
                     updateExisting:YES
                              error:nil];
}


- (NSString *)_passcode {
    if (!_usesKeychain &&
        [self.delegate respondsToSelector:@selector(passcode)]) {
        return [self.delegate passcode];
    }

    return [LTHKeychainUtils getPasswordForUsername:_keychainPasscodeUsername
                                     andServiceName:_keychainServiceName
                                              error:nil];
}


- (void)resetPasscode {
    if ([self _doesPasscodeExist]) {
        NSString *passcode = [self _passcode];
        [self _deletePasscode];
        [self _savePasscode:passcode];
    }
}

//- (void)_handleBiometricsFailureAndDisableIt:(BOOL)disableBiometrics {
//    dispatch_async(dispatch_get_main_queue(), ^{
//        if (disableBiometrics) {
//            self.isUsingBiometrics = NO;
//            self.allowUnlockWithBiometrics = NO;
//        }
//
//        self.useFallbackPasscode = YES;
//        self.animatingView.hidden = NO;
//
//        BOOL usingNavBar = self.isUsingNavBar;
//        NSString *logoutTitle = usingNavBar ? self.navBar.items.firstObject.leftBarButtonItem.title : @"";
//
//        [self _resetUI];
//
//        if (usingNavBar) {
//            self.isUsingNavBar = usingNavBar;
//            [self _setupNavBarWithLogoutTitle:logoutTitle];
//        }
//    });
//
//    self.biometricsContext = nil;
//}

- (void)_setupFingerPrint {
    if (!self.biometricsContext && _allowUnlockWithBiometrics && !_useFallbackPasscode) {
        self.biometricsContext = [[LAContext alloc] init];

        NSError *error = nil;
        if ([self.biometricsContext canEvaluatePolicy:LAPolicyDeviceOwnerAuthenticationWithBiometrics error:&error]) {
            if (error) {
                return;
            }

            if (@available(iOS 11.0, *)) {
                if (self.biometricsContext.biometryType == LABiometryTypeFaceID) {
                    self.biometricsDetailsString = @"Unlock using Face ID";
                }
            }

            _isUsingBiometrics = YES;
            [_passcodeTextField resignFirstResponder];
            _animatingView.hidden = YES;

            // Authenticate User
            [self.biometricsContext evaluatePolicy:LAPolicyDeviceOwnerAuthenticationWithBiometrics
                                localizedReason:self.biometricsDetailsString
                                          reply:^(BOOL success, NSError *error) {

                                              if (error || !success) {
//                                                  [self _handleBiometricsFailureAndDisableIt:false];
//
//                                                  if ([self.delegate respondsToSelector: @selector(biometricsAuthenticationFailed)]) {
//                                                      [self.delegate performSelector: @selector(biometricsAuthenticationFailed)];
//                                                  }
                                                  self.biometricsContext = nil;
                                                  return;
                                              }

                                              dispatch_async(dispatch_get_main_queue(), ^{
//                                                  [self _validatePasscode: self._passcode];
                                                  [self _dismissMe];

                                                  if ([self.delegate respondsToSelector: @selector(passcodeWasEnteredSuccessfully)]) {
                                                      [self.delegate performSelector: @selector(passcodeWasEnteredSuccessfully)];
                                                  }
                                              });

                                              self.biometricsContext = nil;
                                          }];
        }
        else {
             self.biometricsContext = nil;
//            [self _handleBiometricsFailureAndDisableIt:true];
        }
    }
    else {
         self.biometricsContext = nil;
//        [self _handleBiometricsFailureAndDisableIt:true];
    }
}


- (void)_saveAllowUnlockWithBiometrics {
    if (!_usesKeychain &&
        [self.delegate respondsToSelector:@selector(saveAllowUnlockWithBiometrics:)]) {
        [self.delegate saveAllowUnlockWithBiometrics:_allowUnlockWithBiometrics];

        return;
    }

    [LTHKeychainUtils storeUsername:_keychainAllowUnlockWithBiometrics
                        andPassword:[NSString stringWithFormat: @"%d",
                                     _allowUnlockWithBiometrics]
                     forServiceName:_keychainServiceName
                     updateExisting:YES
                              error:nil];
}



- (BOOL)_allowUnlockWithBiometrics {
    if (!_usesKeychain &&
        [self.delegate respondsToSelector:@selector(allowUnlockWithBiometrics)]) {
        return [self.delegate allowUnlockWithBiometrics];
    }

    NSString *keychainValue = [LTHKeychainUtils getPasswordForUsername:_keychainAllowUnlockWithBiometrics
                                                        andServiceName:_keychainServiceName
                                                                 error:nil];
    if (!keychainValue) return YES;
    return keychainValue.boolValue;
}


- (void)setAllowUnlockWithBiometrics:(BOOL)setAllowUnlockWithBiometrics {
    _allowUnlockWithBiometrics = setAllowUnlockWithBiometrics;
    [self _saveAllowUnlockWithBiometrics];
}


- (void)setDigitsCount:(NSInteger)digitsCount {
    // If a passcode exists, don't allow the changing of the number of digits.
    if ([self _doesPasscodeExist]) { return; }

    if (digitsCount < LTHMinPasscodeDigits) {
        digitsCount = LTHMinPasscodeDigits;
    }
    else if (digitsCount > LTHMaxPasscodeDigits) {
        digitsCount = LTHMaxPasscodeDigits;
    }

    _digitsCount = digitsCount;

    // If we haven't loaded yet, do nothing,
    // _setupDigitFields will be called in viewDidLoad.
    if (!self.isViewLoaded) { return; }
    [self _setupDigitFields];
}


#pragma mark - View life
- (void)viewDidLoad {
    [super viewDidLoad];
    self.updatedEnteringPasscode = @"";
    self.view.backgroundColor = _backgroundColor;

    _backgroundImageView = [[UIImageView alloc] initWithFrame:self.view.frame];
    [self.view addSubview:_backgroundImageView];
    _backgroundImageView.image = _backgroundImage;

    _failedAttempts = 0;
    _animatingView = [[UIView alloc] initWithFrame: self.view.frame];
    [self.view addSubview: _animatingView];

    [self _setupViews];
    [self _setupLabels];
    [self _setupOKButton];

    // If on first launch we have a passcode, the number of digits should equal that.
    if ([self _doesPasscodeExist]) {
        _digitsCount = [self _passcode].length;
    }
    [self _setupDigitFields];

    _passcodeTextField = [[UITextField alloc] initWithFrame: CGRectZero];
    _passcodeTextField.delegate = self;
    _passcodeTextField.translatesAutoresizingMaskIntoConstraints = NO;

    [self.view setNeedsUpdateConstraints];
}


- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];

    if (!self.isAppNotificationsObserved) {
        [self _addObservers];
        self.isAppNotificationsObserved = YES;
    }

    _animatingView.hidden = NO;
    _backgroundImageView.image = _backgroundImage;

    if (!_passcodeTextField.isFirstResponder && (!_isUsingBiometrics || _isUserChangingPasscode || _isUserBeingAskedForNewPasscode || _isUserConfirmingPasscode || _isUserEnablingPasscode || _isUserSwitchingBetweenPasscodeModes || _isUserTurningPasscodeOff)) {
        if (self.internalPasscodeView == nil) {
            [_passcodeTextField resignFirstResponder];
        }
        _animatingView.hidden = NO;
    }
    if (_isUsingBiometrics && !_isUserChangingPasscode && !_isUserBeingAskedForNewPasscode && !_isUserConfirmingPasscode && !_isUserEnablingPasscode && !_isUserSwitchingBetweenPasscodeModes && !_isUserTurningPasscodeOff) {
        if (self.internalPasscodeView == nil) {
            [_passcodeTextField resignFirstResponder];
        }
        _animatingView.hidden = _isUsingBiometrics;
    }
}

- (void)viewWillLayoutSubviews {
    [super viewWillLayoutSubviews];
    _animatingView.frame = self.view.bounds;
    self.internalPasscodeView.frame = self.view.bounds;
}


- (void)viewDidDisappear:(BOOL)animated {
    // If _isCurrentlyOnScreen is true at this point,
    // it means the back button was tapped, so we need to reset.
    if ([self isMovingFromParentViewController] && !_hidesBackButton && _isCurrentlyOnScreen) {
        [self _close];
        return;
    }

    [super viewDidDisappear:animated];

    if (!_displayedAsModal && !_displayedAsLockScreen) {
        [self textFieldShouldEndEditing:_passcodeTextField];
    }
}


- (void)_cancelAndDismissMe {
    _isCurrentlyOnScreen = NO;
    _isUserBeingAskedForNewPasscode = NO;
    _isUserChangingPasscode = NO;
    _isUserConfirmingPasscode = NO;
    _isUserEnablingPasscode = NO;
    _isUserTurningPasscodeOff = NO;
    _isUserSwitchingBetweenPasscodeModes = NO;
    [self _resetUI];
    [_passcodeTextField resignFirstResponder];

    if ([self.delegate respondsToSelector: @selector(passcodeViewControllerWillClose:)]) {
        [self.delegate passcodeViewControllerWillClose:YES];
    }

    if (_displayedAsModal) [self dismissViewControllerAnimated:YES completion:nil];
    else if (!_displayedAsLockScreen && !self.isMovingFromParentViewController) { [self.navigationController popViewControllerAnimated:YES]; }
}


- (void)_dismissMe {
    _failedAttempts = 0;
    _isCurrentlyOnScreen = NO;
    [self _resetUI];
    [_passcodeTextField resignFirstResponder];
    [UIView animateWithDuration:_lockAnimationDuration delay:0.0 options:UIViewAnimationOptionCurveLinear animations:^{
        if (self.displayedAsLockScreen) {
            self.view.center = CGPointMake(self.view.center.x, self.view.center.y * 4.f);
        }
        else {
            // Delete from Keychain
            if (self.isUserTurningPasscodeOff) {
                [self _deletePasscode];
            }
            // Update the Keychain if adding or changing passcode
            else {
                [self _savePasscode:self.tempPasscode];
                //finalize type switching
                if (self.isUserSwitchingBetweenPasscodeModes) {
                    self.isUserConfirmingPasscode = NO;
                    [self setIsSimple:!self.isSimple
                     inViewController:nil
                              asModal:self.displayedAsModal];
                }
            }
        }
    } completion: ^(BOOL finished) {
        if ([self.delegate respondsToSelector: @selector(passcodeViewControllerWillClose:)]) {
            [self.delegate passcodeViewControllerWillClose:self.displayedAsLockScreen];
        }

        if (self.displayedAsLockScreen) {
            [self.digitTextFieldsArray removeAllObjects];
            self.updatedEnteringPasscode = @"";
            [self.internalPasscodeView removeFromSuperview];
            [self.view removeFromSuperview];
            [self removeFromParentViewController];
            [[self internalWindow] dismiss];
            self.internalWindow = nil;
        }
        else if (self.displayedAsModal) {
            [self dismissViewControllerAnimated:YES
                                     completion:nil];
        }
        else if (!self.displayedAsLockScreen) {
            [self.navigationController popViewControllerAnimated:NO];
        }
    }];
}


#pragma mark - UI setup
- (void)_setupNavBarWithLogoutTitle:(NSString *)logoutTitle {
    // Navigation Bar with custom UI
    UIView *patchView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, LTHMainWindow.frame.size.width, [LTHPasscodeViewController getStatusBarHeight])];
    patchView.backgroundColor = [UIColor whiteColor];
    patchView.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [self.view addSubview:patchView];

    self.navBar =
    [[UINavigationBar alloc] initWithFrame:CGRectMake(0, patchView.frame.size.height,
                                                          LTHMainWindow.frame.size.width, 44)];
    self.navBar.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    self.navBar.tintColor = self.navigationTintColor;
    if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)]) {
        self.navBar.barTintColor = self.navigationBarTintColor;
        self.navBar.translucent  = self.navigationBarTranslucent;
    }
    if (self.navigationTitleColor) {
        self.navBar.titleTextAttributes =
        @{ NSForegroundColorAttributeName : self.navigationTitleColor };
    }

    // Navigation item
    UIBarButtonItem *leftButton =
    [[UIBarButtonItem alloc] initWithTitle:logoutTitle
                                     style:UIBarButtonItemStyleDone
                                    target:self
                                    action:@selector(_logoutWasPressed)];
    [leftButton setTitlePositionAdjustment:UIOffsetMake(10, 0) forBarMetrics:UIBarMetricsDefault];

    UINavigationItem *item =
    [[UINavigationItem alloc] initWithTitle:self.title];
    item.leftBarButtonItem = leftButton;
    item.hidesBackButton = YES;

    [self.navBar pushNavigationItem:item animated:NO];
    [self.view addSubview:self.navBar];
}

- (void)_setupViews {
    _coverView = [[UIView alloc] initWithFrame: CGRectZero];
    _coverView.backgroundColor = _coverViewBackgroundColor;
    _coverView.frame = self.view.frame;
    _coverView.userInteractionEnabled = NO;
    _coverView.tag = _coverViewTag;
    _coverView.hidden = YES;
    [LTHMainWindow addSubview: _coverView];

    _complexPasscodeOverlayView = [[UIView alloc] initWithFrame:CGRectZero];
    _complexPasscodeOverlayView.backgroundColor = [UIColor whiteColor];
    _complexPasscodeOverlayView.translatesAutoresizingMaskIntoConstraints = NO;

    _simplePasscodeView = [[UIView alloc] initWithFrame:CGRectZero];
    _simplePasscodeView.translatesAutoresizingMaskIntoConstraints = NO;

    [_animatingView addSubview:_complexPasscodeOverlayView];
    [_animatingView addSubview:_simplePasscodeView];
}


- (void)_setupLabels {
    _enterPasscodeLabel = [[UILabel alloc] initWithFrame: CGRectZero];
    _enterPasscodeLabel.backgroundColor = _enterPasscodeLabelBackgroundColor;
    _enterPasscodeLabel.numberOfLines = 0;
    _enterPasscodeLabel.textColor = _labelTextColor;
    _enterPasscodeLabel.font = _labelFont;
    _enterPasscodeLabel.textAlignment = NSTextAlignmentCenter;
    [_animatingView addSubview: _enterPasscodeLabel];

    _enterPasscodeInfoLabel = [[UILabel alloc] initWithFrame: CGRectZero];
    _enterPasscodeInfoLabel.backgroundColor = _enterPasscodeLabelBackgroundColor;
    _enterPasscodeInfoLabel.numberOfLines = 0;
    _enterPasscodeInfoLabel.textColor = _labelTextColor;
    _enterPasscodeInfoLabel.font = _labelFont;
    _enterPasscodeInfoLabel.textAlignment = NSTextAlignmentCenter;
    _enterPasscodeInfoLabel.hidden = !_displayAdditionalInfoDuringSettingPasscode;
    [_animatingView addSubview: _enterPasscodeInfoLabel];

    // It is also used to display the "Passcodes did not match" error message
    // if the user fails to confirm the passcode.
    _failedAttemptLabel = [[UILabel alloc] initWithFrame: CGRectZero];
    _failedAttemptLabel.text = self.errorPasscodeString;
    _failedAttemptLabel.numberOfLines = 0;
    _failedAttemptLabel.backgroundColor    = _failedAttemptLabelBackgroundColor;
    _failedAttemptLabel.hidden = YES;
    _failedAttemptLabel.textColor = _failedAttemptLabelTextColor;
    _failedAttemptLabel.font = _labelFont;
    _failedAttemptLabel.textAlignment = NSTextAlignmentCenter;
    [_animatingView addSubview: _failedAttemptLabel];

    _enterPasscodeLabel.text = _isUserChangingPasscode ? self.enterOldPasscodeString : self.enterPasscodeString;
    _enterPasscodeInfoLabel.text = self.enterPasscodeInfoString;

    _enterPasscodeLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _enterPasscodeInfoLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _failedAttemptLabel.translatesAutoresizingMaskIntoConstraints = NO;
}


- (void)_setupDigitFields {
    [_digitTextFieldsArray enumerateObjectsUsingBlock:^(UITextField * _Nonnull textField, NSUInteger idx, BOOL * _Nonnull stop) {
        if (![[self.internalPasscodeView textFieldsArray] containsObject:textField]) {
            [textField removeFromSuperview];
        }
    }];
    [_digitTextFieldsArray removeAllObjects];

    for (int i = 0; i < _digitsCount; i++) {
        if (self.internalPasscodeView != nil) {
            UITextField * textField = [self.internalPasscodeView textFieldsArray][i];
            [self preparedTextField:textField];
            [_digitTextFieldsArray addObject:textField];
            continue;
        }
        UITextField *digitTextField = [self _makeDigitField];
        [_digitTextFieldsArray addObject:digitTextField];
        [_simplePasscodeView addSubview:digitTextField];
    }
    [self.view setNeedsUpdateConstraints];
}


- (UITextField *)_makeDigitField{
    UITextField *field = [[UITextField alloc] initWithFrame:CGRectZero];
    field.backgroundColor = _passcodeBackgroundColor;
    field.textAlignment = NSTextAlignmentCenter;
    field.text = _passcodeCharacter;
    field.textColor = _passcodeTextColor;
    field.font = _passcodeFont;
    field.delegate = self;
    field.secureTextEntry = NO;
    field.tintColor = [UIColor clearColor];
    field.translatesAutoresizingMaskIntoConstraints = NO;
    [field setBorderStyle:UITextBorderStyleNone];
    return field;
}

-(void) preparedTextField:(UITextField *) field {
    field.backgroundColor = _passcodeBackgroundColor;
    field.textAlignment = NSTextAlignmentCenter;
    field.text = _passcodeCharacter;
    field.textColor = _passcodeTextColor;
    field.font = _passcodeFont;
    field.secureTextEntry = NO;
    field.tintColor = [UIColor clearColor];
    [field setBorderStyle:UITextBorderStyleNone];
}

- (void)_setupOKButton {
    _OKButton = [UIButton buttonWithType:UIButtonTypeCustom];
    [_OKButton setTitle:@"OK"
               forState:UIControlStateNormal];
    _OKButton.titleLabel.font = _labelFont;
    _OKButton.backgroundColor = _enterPasscodeLabelBackgroundColor;
    [_OKButton setTitleColor:_labelTextColor forState:UIControlStateNormal];
    [_OKButton setTitleColor:[UIColor blackColor] forState:UIControlStateHighlighted];
    [_OKButton addTarget:self
                  action:@selector(_validateComplexPasscode)
        forControlEvents:UIControlEventTouchUpInside];
    [_complexPasscodeOverlayView addSubview:_OKButton];

    _OKButton.hidden = YES;
    _OKButton.translatesAutoresizingMaskIntoConstraints = NO;
}


- (void)updateViewConstraints {
    [super updateViewConstraints];
    [self.view removeConstraints:self.view.constraints];
    [_animatingView removeConstraints:_animatingView.constraints];

    _simplePasscodeView.hidden = !self.isSimple;

    _complexPasscodeOverlayView.hidden = self.isSimple;
    _passcodeTextField.alpha = 0.0;
    // This would make the existing text to be cleared after dismissing
    // the keyboard, then focusing the text field again.
    // When simple, the text field only acts as a proxy and is hidden anyway.
    _passcodeTextField.secureTextEntry = !self.isSimple;
    _passcodeTextField.textColor = _passcodeTextField.isSecureTextEntry ? self.passcodeColor : self.passcodeTextColor;
    _passcodeTextField.keyboardType = self.isSimple ? UIKeyboardTypeNumberPad : UIKeyboardTypeASCIICapable;

    if (self.isSimple) {
        [_animatingView addSubview:_passcodeTextField];
    }
    else {
        [_complexPasscodeOverlayView addSubview:_passcodeTextField];

        // If we come from simple state some constraints are added even if
        // translatesAutoresizingMaskIntoConstraints = NO,
        // because no constraints are added manually in that case
        [_passcodeTextField removeConstraints:_passcodeTextField.constraints];
    }

    NSLayoutConstraint *enterPasscodeConstraintCenterX =
    [NSLayoutConstraint constraintWithItem: _enterPasscodeLabel
                                 attribute: NSLayoutAttributeCenterX
                                 relatedBy: NSLayoutRelationEqual
                                    toItem: _animatingView
                                 attribute: NSLayoutAttributeCenterX
                                multiplier: 1.0f
                                  constant: 0.0f];
    NSLayoutConstraint *enterPasscodeConstraintCenterY =
    [NSLayoutConstraint constraintWithItem: _enterPasscodeLabel
                                 attribute: NSLayoutAttributeCenterY
                                 relatedBy: NSLayoutRelationEqual
                                    toItem: _animatingView
                                 attribute: NSLayoutAttributeCenterY
                                multiplier: 0.5f
                                  constant: 0];
    [self.view addConstraint: enterPasscodeConstraintCenterX];
    [self.view addConstraint: enterPasscodeConstraintCenterY];

    NSLayoutConstraint *enterPasscodeInfoConstraintCenterX =
    [NSLayoutConstraint constraintWithItem: _enterPasscodeInfoLabel
                                 attribute: NSLayoutAttributeCenterX
                                 relatedBy: NSLayoutRelationEqual
                                    toItem: _animatingView
                                 attribute: NSLayoutAttributeCenterX
                                multiplier: 1.0f
                                  constant: 0.0f];
    NSLayoutConstraint *enterPasscodeInfoConstraintCenterY =
    [NSLayoutConstraint constraintWithItem: _enterPasscodeInfoLabel
                                 attribute: NSLayoutAttributeCenterY
                                 relatedBy: NSLayoutRelationEqual
                                    toItem: _simplePasscodeView
                                 attribute: NSLayoutAttributeCenterY
                                multiplier: 1.0f
                                  constant: 50];
    [self.view addConstraint: enterPasscodeInfoConstraintCenterX];
    [self.view addConstraint: enterPasscodeInfoConstraintCenterY];

    if (self.isSimple && self.internalPasscodeView == nil) {
        [_digitTextFieldsArray enumerateObjectsUsingBlock:^(UITextField * _Nonnull textField, NSUInteger idx, BOOL * _Nonnull stop) {
            CGFloat constant = idx == 0 ? 0 : self.horizontalGap;
            UIView *toItem = idx == 0 ? self.simplePasscodeView : self.digitTextFieldsArray[idx - 1];
            [textField.widthAnchor constraintEqualToConstant:34].active = YES;
            NSLayoutConstraint *digitX =
            [NSLayoutConstraint constraintWithItem: textField
                                         attribute: NSLayoutAttributeLeft
                                         relatedBy: NSLayoutRelationEqual
                                            toItem: toItem
                                         attribute: NSLayoutAttributeLeft
                                        multiplier: 1.0f
                                          constant: constant];

            NSLayoutConstraint *top =
            [NSLayoutConstraint constraintWithItem: textField
                                         attribute: NSLayoutAttributeTop
                                         relatedBy: NSLayoutRelationEqual
                                            toItem: self.simplePasscodeView
                                         attribute: NSLayoutAttributeTop
                                        multiplier: 1.0f
                                          constant: 0];

            NSLayoutConstraint *bottom =
            [NSLayoutConstraint constraintWithItem: textField
                                         attribute: NSLayoutAttributeBottom
                                         relatedBy: NSLayoutRelationEqual
                                            toItem: self.simplePasscodeView
                                         attribute: NSLayoutAttributeBottom
                                        multiplier: 1.0f
                                          constant: 0];

            [self.view addConstraint:digitX];
            [self.view addConstraint:top];
            [self.view addConstraint:bottom];

            if (idx == self.digitTextFieldsArray.count - 1) {
                NSLayoutConstraint *trailing =
                [NSLayoutConstraint constraintWithItem: textField
                                             attribute: NSLayoutAttributeTrailing
                                             relatedBy: NSLayoutRelationEqual
                                                toItem: self.simplePasscodeView
                                             attribute: NSLayoutAttributeTrailing
                                            multiplier: 1.0f
                                              constant: 0];

                [self.view addConstraint:trailing];
            }
        }];

        NSLayoutConstraint *simplePasscodeViewX =
        [NSLayoutConstraint constraintWithItem: _simplePasscodeView
                                     attribute: NSLayoutAttributeCenterX
                                     relatedBy: NSLayoutRelationEqual
                                        toItem: _animatingView
                                     attribute: NSLayoutAttributeCenterX
                                    multiplier: 1.0
                                      constant: 0];

        NSLayoutConstraint *simplePasscodeViewY =
        [NSLayoutConstraint constraintWithItem: _simplePasscodeView
                                     attribute: NSLayoutAttributeCenterY
                                     relatedBy: NSLayoutRelationEqual
                                        toItem: _enterPasscodeLabel
                                     attribute: NSLayoutAttributeBottom
                                    multiplier: 1.0
                                      constant: _verticalGap];


        [self.view addConstraint:simplePasscodeViewX];
        [self.view addConstraint:simplePasscodeViewY];

    }
    else if (!self.isSimple && self.internalPasscodeView == nil) {
        NSDictionary *viewsDictionary = NSDictionaryOfVariableBindings(_passcodeTextField, _OKButton);

        //TODO: specify different offsets through metrics
        NSArray *constraints =
        [NSLayoutConstraint constraintsWithVisualFormat:@"H:|-10-[_passcodeTextField]-5-[_OKButton]-10-|"
                                                options:0
                                                metrics:nil
                                                  views:viewsDictionary];

        [self.view addConstraints:constraints];

        constraints =
        [NSLayoutConstraint constraintsWithVisualFormat:@"V:|-5-[_passcodeTextField]-5-|"
                                                options:0
                                                metrics:nil
                                                  views:viewsDictionary];

        [self.view addConstraints:constraints];

        NSLayoutConstraint *buttonY =
        [NSLayoutConstraint constraintWithItem: _OKButton
                                     attribute: NSLayoutAttributeCenterY
                                     relatedBy: NSLayoutRelationEqual
                                        toItem: _passcodeTextField
                                     attribute: NSLayoutAttributeCenterY
                                    multiplier: 1.0f
                                      constant: 0.0f];

        [self.view addConstraint:buttonY];

        NSLayoutConstraint *buttonHeight =
        [NSLayoutConstraint constraintWithItem: _OKButton
                                     attribute: NSLayoutAttributeHeight
                                     relatedBy: NSLayoutRelationEqual
                                        toItem: _passcodeTextField
                                     attribute: NSLayoutAttributeHeight
                                    multiplier: 1.0f
                                      constant: 0.0f];

        [self.view addConstraint:buttonHeight];

        NSLayoutConstraint *overlayViewLeftConstraint =
        [NSLayoutConstraint constraintWithItem: _complexPasscodeOverlayView
                                     attribute: NSLayoutAttributeLeft
                                     relatedBy: NSLayoutRelationEqual
                                        toItem: _animatingView
                                     attribute: NSLayoutAttributeLeft
                                    multiplier: 1.0f
                                      constant: 0.0f];

        NSLayoutConstraint *overlayViewY =
        [NSLayoutConstraint constraintWithItem: _complexPasscodeOverlayView
                                     attribute: NSLayoutAttributeCenterY
                                     relatedBy: NSLayoutRelationEqual
                                        toItem: _enterPasscodeLabel
                                     attribute: NSLayoutAttributeBottom
                                    multiplier: 1.0f
                                      constant: _verticalGap];

        NSLayoutConstraint *overlayViewHeight =
        [NSLayoutConstraint constraintWithItem: _complexPasscodeOverlayView
                                     attribute: NSLayoutAttributeHeight
                                     relatedBy: NSLayoutRelationEqual
                                        toItem: nil
                                     attribute: NSLayoutAttributeNotAnAttribute
                                    multiplier: 1.0f
                                      constant: _passcodeOverlayHeight];

        NSLayoutConstraint *overlayViewWidth =
        [NSLayoutConstraint constraintWithItem: _complexPasscodeOverlayView
                                     attribute: NSLayoutAttributeWidth
                                     relatedBy: NSLayoutRelationEqual
                                        toItem: _animatingView
                                     attribute: NSLayoutAttributeWidth
                                    multiplier: 1.0f
                                      constant: 0.0f];
        [self.view addConstraints:@[overlayViewLeftConstraint, overlayViewY, overlayViewHeight, overlayViewWidth]];
    }

    NSLayoutConstraint *failedAttemptLabelCenterX =
    [NSLayoutConstraint constraintWithItem: _failedAttemptLabel
                                 attribute: NSLayoutAttributeCenterX
                                 relatedBy: NSLayoutRelationEqual
                                    toItem: _animatingView
                                 attribute: NSLayoutAttributeCenterX
                                multiplier: 1.0f
                                  constant: 0.0f];
    NSLayoutConstraint *failedAttemptLabelCenterY =
    [NSLayoutConstraint constraintWithItem: _failedAttemptLabel
                                 attribute: NSLayoutAttributeCenterY
                                 relatedBy: NSLayoutRelationEqual
                                    toItem: _enterPasscodeLabel
                                 attribute: NSLayoutAttributeBottom
                                multiplier: 1.0f
                                  constant: _failedAttemptLabelGap];
    NSLayoutConstraint *failedAttemptLabelHeight =
    [NSLayoutConstraint constraintWithItem: _failedAttemptLabel
                                 attribute: NSLayoutAttributeHeight
                                 relatedBy: NSLayoutRelationEqual
                                    toItem: nil
                                 attribute: NSLayoutAttributeNotAnAttribute
                                multiplier: 1.0f
                                  constant: LTHFailedAttemptLabelHeight + 6.0f];
    [self.view addConstraint:failedAttemptLabelCenterX];
    [self.view addConstraint:failedAttemptLabelCenterY];
    [self.view addConstraint:failedAttemptLabelHeight];
}


#pragma mark - Displaying
- (void)showLockscreenWithoutAnimation {
    [self showLockScreenWithAnimation:NO withLogout:NO andLogoutTitle:nil];
}

- (void)showLockScreenWithAnimation:(BOOL)animated withLogout:(BOOL)hasLogout andLogoutTitle:(NSString*)logoutTitle {
    [self showLockScreenOver:LTHMainWindow withAnimation:animated withLogout:hasLogout andLogoutTitle:logoutTitle];
}

- (void)showLockScreenOver:(UIView *)superview withAnimation:(BOOL)animated withLogout:(BOOL)hasLogout andLogoutTitle:(NSString*)logoutTitle {
    [self _prepareAsLockScreen];

    // In case the user leaves the app while the lockscreen is already active.
    if (_isCurrentlyOnScreen) { return; }
    _isCurrentlyOnScreen = YES;

    PasscodeLockerView * passcodeView = [[[UINib nibWithNibName:@"PasscodeLocker" bundle:nil] instantiateWithOwner:nil options:nil] objectAtIndex:0];
    LAContext* biometricsCtx = [[LAContext alloc] init];
    if (_allowUnlockWithBiometrics && @available(iOS 11.0, *)) {
        [passcodeView configureWithBiometryType:biometricsCtx.biometryType andFingerImage:[self imageForFingerPrint] andFaceImage:[self imageForFaceId]];
    }
    passcodeView.passcodeButtonDelegate = self;
    self.internalPasscodeView = passcodeView;
    [self.view addSubview:passcodeView];
    PasscodeWindow * passcodeWindow;
    if (@available(iOS 13.0, *)) {
        passcodeWindow = [[PasscodeWindow alloc] initWithWindowScene:[(UIWindow *)superview windowScene]];
    } else {
        passcodeWindow = [[PasscodeWindow alloc] initWithFrame:superview.bounds];
    }
    passcodeWindow.backgroundColor = [UIColor clearColor];
    passcodeWindow.windowLevel = UIWindowLevelStatusBar + 1;
    passcodeWindow.rootViewController = self;
    self.internalWindow = passcodeWindow;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    [passcodeWindow makeKeyAndVisible];
    [CATransaction commit];
    //[superview addSubview: self.view];
    [self _setupDigitFields];

    // All this hassle because a view added to UIWindow does not rotate automatically
    // and if we would have added the view anywhere else, it wouldn't display properly
    // (having a modal on screen when the user leaves the app, for example).
    [self rotateAccordingToStatusBarOrientationAndSupportedOrientations];

    /*CGPoint superviewCenter = CGPointMake(superview.center.x, superview.center.y);
    CGPoint newCenter;

    self.view.center = CGPointMake(self.view.center.x, self.view.center.y * -1.f);
    newCenter = CGPointMake(superviewCenter.x,
                            superviewCenter.y + self.navigationController.navigationBar.frame.size.height / 2);

    [UIView animateWithDuration: animated ? _lockAnimationDuration : 0 animations: ^{
        self.view.center = newCenter;
    }];*/

    // Add nav bar & logout button if specified
    if (hasLogout) {
        _isUsingNavBar = hasLogout;
        [self _setupNavBarWithLogoutTitle:logoutTitle];
    }
}


- (void)_prepareNavigationControllerWithController:(UIViewController *)viewController {
    if (!_hidesCancelButton) {
        self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
                                                      target:self
                                                      action:@selector(_cancelAndDismissMe)];
    }

    if (!_displayedAsModal) {
        CATransition *transition = [CATransition animation];
        [viewController.navigationController pushViewController:self animated:NO];
        [transition setType: kCATransitionPush];
        [transition setSubtype: kCATransitionFromRight];
        [transition setDuration: 0.3];
        [transition setTimingFunction:[CAMediaTimingFunction functionWithName: kCAMediaTimingFunctionEaseInEaseOut]];
        [[_animatingView layer] addAnimation: transition forKey: @"push"];
        self.navigationItem.hidesBackButton = _hidesBackButton;
        return;
    }

    UINavigationController *navController = [[UINavigationController alloc] initWithRootViewController:self];
    navController.modalPresentationStyle = UIModalPresentationFullScreen;

    // Make sure nav bar for logout is off the screen
    [self.navBar removeFromSuperview];
    self.navBar = nil;

    // Customize navigation bar
    // Make sure UITextAttributeTextColor is not set to nil
    // barTintColor & translucent is only called on iOS7+
    navController.navigationBar.tintColor = self.navigationTintColor;

    if ([self respondsToSelector:@selector(setEdgesForExtendedLayout:)]) {
        navController.navigationBar.barTintColor = self.navigationBarTintColor;
        navController.navigationBar.translucent = self.navigationBarTranslucent;
    }

    if (self.navigationTitleColor) {
        navController.navigationBar.titleTextAttributes =
        @{ NSForegroundColorAttributeName : self.navigationTitleColor };
    }

    [viewController presentViewController:navController
                                 animated:YES
                               completion:nil];
}


- (void)showForEnablingPasscodeInViewController:(UIViewController *)viewController
                                        asModal:(BOOL)isModal {
    _displayedAsModal = isModal;
    _passcodeAlreadyExists = NO;
    [self _setupDigitFields];
    [self _prepareForEnablingPasscode];
    [self _prepareNavigationControllerWithController:viewController];
    self.title = self.enablePasscodeString;
}


- (void)showForChangingPasscodeInViewController:(UIViewController *)viewController
                                        asModal:(BOOL)isModal {
    _displayedAsModal = isModal;
    [self _prepareForChangingPasscode];
    [self _setupDigitFields];
    [self _prepareNavigationControllerWithController:viewController];
    self.title = self.changePasscodeString;
}


- (void)showForDisablingPasscodeInViewController:(UIViewController *)viewController
                                         asModal:(BOOL)isModal {
    _displayedAsModal = isModal;
    [self _setupDigitFields];
    [self _prepareForTurningOffPasscode];
    [self _prepareNavigationControllerWithController:viewController];
    self.title = self.turnOffPasscodeString;
}


#pragma mark - Preparing
- (void)_prepareAsLockScreen {
    // In case the user leaves the app while changing/disabling Passcode.
    if (_isCurrentlyOnScreen && !_displayedAsLockScreen) {
        [self _cancelAndDismissMe];
    }

    _displayedAsLockScreen = YES;
    _isUserTurningPasscodeOff = NO;
    _isUserChangingPasscode = NO;
    _isUserConfirmingPasscode = NO;
    _isUserEnablingPasscode = NO;
    _isUserSwitchingBetweenPasscodeModes = NO;

    self.title = @"";
    [self _resetUI];
    [self _setupFingerPrint];
}


- (void)_prepareForChangingPasscode {
    _isCurrentlyOnScreen = YES;
    _displayedAsLockScreen = NO;
    _isUserTurningPasscodeOff = NO;
    _isUserChangingPasscode = YES;
    _isUserConfirmingPasscode = NO;
    _isUserEnablingPasscode = NO;

    [self _resetUI];
}


- (void)_prepareForTurningOffPasscode {
    _isCurrentlyOnScreen = YES;
    _displayedAsLockScreen = NO;
    _isUserTurningPasscodeOff = YES;
    _isUserChangingPasscode = NO;
    _isUserConfirmingPasscode = NO;
    _isUserEnablingPasscode = NO;
    _isUserSwitchingBetweenPasscodeModes = NO;

    [self _resetUI];
}


- (void)_prepareForEnablingPasscode {
    _isCurrentlyOnScreen = YES;
    _displayedAsLockScreen = NO;
    _isUserTurningPasscodeOff = NO;
    _isUserChangingPasscode = NO;
    _isUserConfirmingPasscode = NO;
    _isUserEnablingPasscode = YES;
    _isUserSwitchingBetweenPasscodeModes = NO;

    [self _resetUI];
}


#pragma mark - UITextFieldDelegate
- (BOOL)textFieldShouldBeginEditing:(UITextField *)textField {
    if (self.displayedAsLockScreen) { return NO; }
    if (textField == _passcodeTextField) { return YES; }

    [_passcodeTextField becomeFirstResponder];

    UITextPosition *end = _passcodeTextField.endOfDocument;
    UITextRange *range = [_passcodeTextField textRangeFromPosition:end toPosition:end];

    [_passcodeTextField setSelectedTextRange:range];

    return false;
}

- (BOOL)textFieldShouldEndEditing:(UITextField *)textField {
    if ((!_displayedAsLockScreen && !_displayedAsModal) || (_isUsingBiometrics || !_useFallbackPasscode)) {
        return YES;
    }
    return !_isCurrentlyOnScreen;
}

- (BOOL)textField:(UITextField *)textField shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString *)string {

    if ([string isEqualToString: @"\n"] || self.isTempararlyDisabled) return NO;

    NSString *typedString = [textField.text stringByReplacingCharactersInRange: range
                                                                    withString: string];

    if (self.isSimple) {

        [_digitTextFieldsArray enumerateObjectsUsingBlock:^(UITextField * _Nonnull textField, NSUInteger idx, BOOL * _Nonnull stop) {
            textField.secureTextEntry = typedString.length > idx;
            textField.textColor = typedString.length > idx ? self.passcodeColor : self.passcodeTextColor;
        }];

        if (typedString.length == _digitsCount) {
            // Make the last bullet show up
            [self performSelector: @selector(_validatePasscode:)
                       withObject: typedString
                       afterDelay: 0.15];
        }

        if (typedString.length > _digitsCount) return NO;
    }
    else {
        _OKButton.hidden = [typedString length] == 0;
    }

    return YES;
}

#pragma mark - Validation
- (void)_validateComplexPasscode {
    [self _validatePasscode:_passcodeTextField.text];
}


- (BOOL)_validatePasscode:(NSString *)typedString {
    NSString *savedPasscode = [self _passcode];
    // Entering from Settings. If savedPasscode is empty, it means
    // the user is setting a new Passcode now, or is changing his current Passcode.
    if ((_isUserChangingPasscode  || savedPasscode.length == 0) && !_isUserTurningPasscodeOff) {
        // Either the user is being asked for a new passcode, confirmation comes next,
        // either he is setting up a new passcode, confirmation comes next, still.
        // We need the !_isUserConfirmingPasscode condition, because if he's adding a new Passcode,
        // then savedPasscode is still empty and the condition will always be true, not passing this point.
        if ((_isUserBeingAskedForNewPasscode || savedPasscode.length == 0) && !_isUserConfirmingPasscode) {
            _tempPasscode = typedString;
            // The delay is to give time for the last bullet to appear
            [self performSelector:@selector(_askForConfirmationPasscode)
                       withObject:nil
                       afterDelay:0.15f];
        }
        // User entered his Passcode correctly and we are at the confirming screen.
        else if (_isUserConfirmingPasscode) {
            // User entered the confirmation Passcode incorrectly, or the passcode is the same as the old one, start over.
            _newPasscodeEqualsOldPasscode = [typedString isEqualToString:savedPasscode];
            if (![typedString isEqualToString:_tempPasscode] || _newPasscodeEqualsOldPasscode) {
                [self performSelector:@selector(_reAskForNewPasscode)
                           withObject:nil
                           afterDelay:_slideAnimationDuration];
            }
            // User entered the confirmation Passcode correctly.
            else {
                [self _dismissMe];
            }
        }
        // Changing Passcode and the entered Passcode is correct.
        else if ([typedString isEqualToString:savedPasscode]){
            [self performSelector:@selector(_askForNewPasscode)
                       withObject:nil
                       afterDelay:_slideAnimationDuration];
            _failedAttempts = 0;
        }
        // Acting as lockscreen and the entered Passcode is incorrect.
        else {
            [self performSelector: @selector(_denyAccess)
                       withObject: nil
                       afterDelay: _slideAnimationDuration];
            return NO;
        }
    }
    // App launch/Turning passcode off: Passcode OK -> dismiss, Passcode incorrect -> deny access.
    else {
        if ([typedString isEqualToString: savedPasscode]) {
            [self _dismissMe];
            _useFallbackPasscode = NO;
            if ([self.delegate respondsToSelector: @selector(passcodeWasEnteredSuccessfully)]) {
                [self.delegate performSelector: @selector(passcodeWasEnteredSuccessfully)];
            }
        }
        else {
            [self performSelector: @selector(_denyAccess)
                       withObject: nil
                       afterDelay: _slideAnimationDuration];
            return NO;
        }
    }

    return YES;
}


#pragma mark - Actions
- (void)_askForNewPasscode {
    _isUserBeingAskedForNewPasscode = YES;
    _isUserConfirmingPasscode = NO;

    // Update layout considering type
    [self.view setNeedsUpdateConstraints];

    _failedAttemptLabel.hidden = YES;

    CATransition *transition = [CATransition animation];
    [self performSelector: @selector(_resetUI) withObject: nil afterDelay: 0.1f];
    [transition setType: kCATransitionPush];
    [transition setSubtype: kCATransitionFromRight];
    [transition setDuration: _slideAnimationDuration];
    [transition setTimingFunction:
     [CAMediaTimingFunction functionWithName: kCAMediaTimingFunctionEaseInEaseOut]];
    [[_animatingView layer] addAnimation: transition forKey: @"swipe"];
}


- (void)_reAskForNewPasscode {
    _isUserBeingAskedForNewPasscode = YES;
    _isUserConfirmingPasscode = NO;
    _tempPasscode = @"";

    CATransition *transition = [CATransition animation];
    [self performSelector: @selector(_resetUIForReEnteringNewPasscode)
               withObject: nil
               afterDelay: 0.1f];
    [transition setType: kCATransitionPush];
    [transition setSubtype: kCATransitionFromRight];
    [transition setDuration: _slideAnimationDuration];
    [transition setTimingFunction:
     [CAMediaTimingFunction functionWithName: kCAMediaTimingFunctionEaseInEaseOut]];
    [[_animatingView layer] addAnimation: transition forKey: @"swipe"];
}


- (void)_askForConfirmationPasscode {
    _isUserBeingAskedForNewPasscode = NO;
    _isUserConfirmingPasscode = YES;
    _failedAttemptLabel.hidden = YES;

    CATransition *transition = [CATransition animation];
    [self performSelector: @selector(_resetUI) withObject: nil afterDelay: 0.1f];
    [transition setType: kCATransitionPush];
    [transition setSubtype: kCATransitionFromRight];
    [transition setDuration: _slideAnimationDuration];
    [transition setTimingFunction:
     [CAMediaTimingFunction functionWithName: kCAMediaTimingFunctionEaseInEaseOut]];
    [[_animatingView layer] addAnimation: transition forKey: @"swipe"];
}


- (void)_denyAccess {
    [self _resetTextFields];
    _passcodeTextField.text = @"";
    _OKButton.hidden = YES;

    CAKeyframeAnimation *animation = [CAKeyframeAnimation animationWithKeyPath: @"transform.translation.x"];
    animation.duration = 0.6;
    animation.timingFunction = [CAMediaTimingFunction functionWithName: kCAAnimationLinear];
    animation.values = @[@-12, @12, @-12, @12, @-6, @6, @-3, @3, @0];

    self.isTempararlyDisabled = YES;
    [CATransaction begin];
    [CATransaction setCompletionBlock:^{
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            self.isTempararlyDisabled = NO;
        });
    }];
    UIColor * passcodeDigitColor = self.passcodeTextColor;
    [_digitTextFieldsArray enumerateObjectsUsingBlock:^(UITextField * _Nonnull textField, NSUInteger idx, BOOL * _Nonnull stop) {
        [CATransaction begin];
        [CATransaction setCompletionBlock:^{
            textField.textColor = passcodeDigitColor;
            textField.secureTextEntry = NO;
        }];
        textField.textColor = UIColor.redColor;
        [textField.layer addAnimation:animation forKey:@"shake"];
        [CATransaction commit];
    }];
    [CATransaction commit];

    _failedAttempts++;

    if (_maxNumberOfAllowedFailedAttempts > 0 &&
        _failedAttempts >= _maxNumberOfAllowedFailedAttempts &&
        [self.delegate respondsToSelector: @selector(maxNumberOfFailedAttemptsReached)]) {
        [self.delegate maxNumberOfFailedAttemptsReached];
    }

    NSString *translationText = self.errorPasscodeString;
    // To give it some padding. Since it's center-aligned,
    // it will automatically distribute the extra space.
    // Ironically enough, I found 5 spaces to be the best looking.
    _failedAttemptLabel.text = [NSString stringWithFormat:@"%@     ", translationText];

    _failedAttemptLabel.layer.cornerRadius = LTHiPad ? 19 : 14;
    _failedAttemptLabel.clipsToBounds = true;
    _failedAttemptLabel.hidden = YES;

    self.updatedEnteringPasscode = @"";
}


- (void)_logoutWasPressed {
    // Notify delegate that logout button was pressed
    if ([self.delegate respondsToSelector: @selector(logoutButtonWasPressed)]) {
        [self.delegate logoutButtonWasPressed];
    }
}


- (void)_resetTextFields {
    // If _allowUnlockWithBiometrics == true, but _isUsingBiometrics == false,
    // it means we're just launching, and we don't want the keyboard to show.
    if (![_passcodeTextField isFirstResponder]) {
        // It seems like there's a glitch with how the alert gets removed when hitting
        // cancel in the Touch ID prompt. In some cases, the keyboard is present, but invisible
        // after dismissing the alert unless we call becomeFirstResponder with a short delay
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (self.internalPasscodeView != nil) { return; }
            [self.passcodeTextField becomeFirstResponder];
        });
    }

    [_digitTextFieldsArray enumerateObjectsUsingBlock:^(UITextField * _Nonnull textField, NSUInteger idx, BOOL * _Nonnull stop) {
        textField.secureTextEntry = NO;
        textField.textColor = self.passcodeTextColor;
    }];
}


- (void)_resetUI {
    [self _resetTextFields];
    _failedAttemptLabel.backgroundColor    = _failedAttemptLabelBackgroundColor;
    _failedAttemptLabel.textColor = _failedAttemptLabelTextColor;
    if (_failedAttempts == 0) _failedAttemptLabel.hidden = YES;

    _passcodeTextField.text = @"";
    if (_isUserConfirmingPasscode) {
        if (_isUserEnablingPasscode) {
            _enterPasscodeLabel.text = self.reenterPasscodeString;
            _enterPasscodeInfoLabel.hidden = YES;
        }
        else if (_isUserChangingPasscode) {
            _enterPasscodeLabel.text = self.reenterNewPasscodeString;
            _enterPasscodeInfoLabel.hidden = YES;
        }
    }
    else if (_isUserBeingAskedForNewPasscode) {
        if (_isUserEnablingPasscode || _isUserChangingPasscode) {
            _enterPasscodeLabel.text = self.enterNewPasscodeString;
            _enterPasscodeInfoLabel.hidden = YES; //hidden for changing PIN
        }
    }
    else {
        if (_isUserChangingPasscode) {
            _enterPasscodeLabel.text = self.enterOldPasscodeString;
            _enterPasscodeInfoLabel.hidden = YES;
        } else {
            _enterPasscodeLabel.text = self.enterPasscodeString;
            //hidden for enabling PIN
            _enterPasscodeInfoLabel.hidden = !(_isUserEnablingPasscode && _displayAdditionalInfoDuringSettingPasscode);
        }
    }

    _enterPasscodeInfoLabel.text = self.enterPasscodeInfoString;

    // Make sure nav bar for logout is off the screen
    if (_isUsingNavBar) {
        [self.navBar removeFromSuperview];
        self.navBar = nil;
    }
    _isUsingNavBar = NO;

    _OKButton.hidden = YES;
}


- (void)_resetUIForReEnteringNewPasscode {
    [self _resetTextFields];
    _passcodeTextField.text = @"";
    // If there's no passcode saved in Keychain,
    // the user is adding one for the first time, otherwise he's changing his passcode.
    NSString *savedPasscode = [LTHKeychainUtils getPasswordForUsername: _keychainPasscodeUsername
                                                        andServiceName: _keychainServiceName
                                                                 error: nil];
    _enterPasscodeLabel.text = savedPasscode.length == 0 ? self.enterPasscodeString : self.enterNewPasscodeString;
    _failedAttemptLabel.hidden = NO;
    _failedAttemptLabel.text = _newPasscodeEqualsOldPasscode ? self.errorSamePasscodeString : self.errorPasscodeString;
    _newPasscodeEqualsOldPasscode = NO;
    _failedAttemptLabel.backgroundColor = [UIColor clearColor];
    _failedAttemptLabel.layer.borderWidth = 0;
    _failedAttemptLabel.layer.borderColor = [UIColor clearColor].CGColor;
    _failedAttemptLabel.textColor = _labelTextColor;
}


- (void)setIsSimple:(BOOL)isSimple inViewController:(UIViewController *)viewController asModal:(BOOL)isModal{
    if (!_isUserSwitchingBetweenPasscodeModes &&
        !_isUserBeingAskedForNewPasscode &&
        [self _doesPasscodeExist]) {
        // User trying to change passcode type while having passcode already
        _isUserSwitchingBetweenPasscodeModes = YES;
        // Display modified change passcode flow starting with input once passcode
        // of current type and then 2 times new one of another type
        [self showForChangingPasscodeInViewController:viewController
                                              asModal:isModal];
    }
    else {
        _isUserSwitchingBetweenPasscodeModes = NO;
        _isSimple = isSimple;
        [self.view setNeedsUpdateConstraints];
    }
}

- (BOOL)isSimple {
    // Is in process of changing, but not finished ->
    // we need to display UI accordingly
    return (_isUserSwitchingBetweenPasscodeModes &&
            (_isUserBeingAskedForNewPasscode || _isUserConfirmingPasscode)) == !_isSimple;
}

#pragma mark - Notification Observers
- (void)_applicationDidEnterBackground {
    if ([self _doesPasscodeExist]) {
        if ([_passcodeTextField isFirstResponder]) {
            _useFallbackPasscode = NO;
            [_passcodeTextField resignFirstResponder];
        }

        if (_isCurrentlyOnScreen && !_displayedAsModal) return;

        _coverView.hidden = NO;
        if (![LTHMainWindow viewWithTag: _coverViewTag]) {
            [LTHMainWindow addSubview: _coverView];
        }
    }
}


- (void)_applicationDidBecomeActive {
    // If we are not being displayed as lockscreen, it means the biometrics alert
    // just closed - it also calls UIApplicationDidBecomeActiveNotification
    // and if we open for changing / turning off really fast, it will call this
    // after viewWillAppear, and it will hide the UI.
    if (_isUsingBiometrics && !_useFallbackPasscode && _displayedAsLockScreen) {
        _animatingView.hidden = YES;
        [_passcodeTextField resignFirstResponder];
    }
    _coverView.hidden = YES;
}


- (void)_applicationWillEnterForeground {
    if ([self _doesPasscodeExist] &&
        [self _didPasscodeTimerEnd]) {
        _useFallbackPasscode = NO;

        if (!_displayedAsModal && !_displayedAsLockScreen && _isCurrentlyOnScreen) {
            [_passcodeTextField resignFirstResponder];
            [self.navigationController popViewControllerAnimated:NO];
            // This is like this because it screws up the navigation stack otherwise
            [self performSelector:@selector(showLockscreenWithoutAnimation)
                       withObject:nil
                       afterDelay:0.0];
        }
        else {
            [self showLockScreenWithAnimation:NO
                                   withLogout:NO
                               andLogoutTitle:nil];
        }
    }
}


- (void)_applicationWillResignActive {
    if ([self _doesPasscodeExist] && !([self isCurrentlyOnScreen] && [self displayedAsLockScreen])) {
        _useFallbackPasscode = NO;
        [self _saveTimerStartTime];
    }
    if (self.internalPasscodeView != nil) {
        self.updatedEnteringPasscode = @"";
        UIColor * passcodeDigitColor = self.passcodeTextColor;
        [_digitTextFieldsArray enumerateObjectsUsingBlock:^(UITextField * _Nonnull textField, NSUInteger idx, BOOL * _Nonnull stop) {
            textField.secureTextEntry = NO;
            textField.textColor = passcodeDigitColor;
        }];
    }
}


#pragma mark - Init
+ (instancetype)sharedUser {
    __strong static LTHPasscodeViewController *sharedObject = nil;

    static dispatch_once_t pred;
    dispatch_once(&pred, ^{
        sharedObject = [[self alloc] init];
    });

    return sharedObject;
}


- (id)init {
    self = [super init];

    if (self) {
        [self _commonInit];
    }
    return self;
}


- (id)initWithCoder:(NSCoder *)aDecoder {
    self = [super initWithCoder:aDecoder];
    if (self) {
        [self _commonInit];
    }
    return self;
}


- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil {
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        [self _commonInit];
    }
    return self;
}


- (void)_commonInit {
    [self _loadDefaults];
}


- (void)_loadDefaults {
    [self _loadMiscDefaults];
    [self _loadStringDefaults];
    [self _loadGapDefaults];
    [self _loadFontDefaults];
    [self _loadColorDefaults];
    [self _loadKeychainDefaults];
}


- (void)_loadMiscDefaults {
    _digitsCount = LTHMinPasscodeDigits;
    _digitTextFieldsArray = [NSMutableArray new];
    _coverViewTag = 994499;
    _lockAnimationDuration = 0.25;
    _slideAnimationDuration = 0.15;
    _maxNumberOfAllowedFailedAttempts = 0;
    _usesKeychain = YES;
    _isSimple = YES;
    _displayedAsModal = YES;
    _hidesBackButton = YES;
    _hidesCancelButton = YES;
    _passcodeAlreadyExists = YES;
    _newPasscodeEqualsOldPasscode = NO;
    _allowUnlockWithBiometrics = [self _allowUnlockWithBiometrics];
    _passcodeCharacter = @"\u2022"; // A longer "-";
    _localizationTableName = @"LTHPasscodeViewController";
    _displayAdditionalInfoDuringSettingPasscode = NO;
}


- (void)_loadStringDefaults {
    self.enterOldPasscodeString = @"Enter your old passcode";
    self.enterPasscodeString = @"Enter your passcode";
    self.enterPasscodeInfoString = @"Passcode info";
    self.enablePasscodeString = @"Enable Passcode";
    self.changePasscodeString = @"Change Passcode";
    self.turnOffPasscodeString = @"Turn Off Passcode";
    self.reenterPasscodeString = @"Re-enter your passcode";
    self.reenterNewPasscodeString = @"Re-enter your new passcode";
    self.enterNewPasscodeString = @"Enter your new passcode";
    self.biometricsDetailsString = @"Unlock using Touch ID";
}


- (void)_loadGapDefaults {
    _fontSizeModifier = LTHiPad ? 1.5 : 1;
    _horizontalGap = 40 * _fontSizeModifier;
    _verticalGap = LTHiPad ? 60.0f : 25.0f;
    _modifierForBottomVerticalGap = LTHiPad ? 2.6f : 3.0f;
    _failedAttemptLabelGap = _verticalGap * _modifierForBottomVerticalGap - 2.0f;
    _passcodeOverlayHeight = LTHiPad ? 96.0f : 40.0f;
}


- (void)_loadFontDefaults {
    _labelFontSize = 15.0;
    _passcodeFontSize = 33.0;
    _labelFont = [UIFont fontWithName: @"AvenirNext-Regular"
                                 size: _labelFontSize * _fontSizeModifier];
    _passcodeFont = [UIFont fontWithName: @"AvenirNext-Regular"
                                    size: _passcodeFontSize * _fontSizeModifier];
}


- (void)_loadColorDefaults {
    // Backgrounds
    _backgroundColor = [UIColor colorWithRed:0.97f green:0.97f blue:1.0f alpha:1.00f];
    _passcodeBackgroundColor = [UIColor clearColor];
    _coverViewBackgroundColor = [UIColor colorWithRed:0.97f green:0.97f blue:1.0f alpha:1.00f];
    _failedAttemptLabelBackgroundColor =  [UIColor colorWithRed:0.8f green:0.1f blue:0.2f alpha:1.000f];
    _enterPasscodeLabelBackgroundColor = [UIColor clearColor];

    // Text
    _labelTextColor = [UIColor colorWithWhite:0.31f alpha:1.0f];
    _passcodeTextColor = [UIColor colorWithWhite:0.31f alpha:1.0f];
    _passcodeColor = [UIColor colorWithRed:0x08/255.0 green:0xA0/255.0 blue:0xB6 alpha:1.0];
    _failedAttemptLabelTextColor = [UIColor whiteColor];
}


- (void)_loadKeychainDefaults {
    _keychainPasscodeUsername = @"demoPasscode";
    _keychainTimerStartUsername = @"demoPasscodeTimerStart";
    _keychainServiceName = @"demoServiceName";
    _keychainTimerDurationUsername = @"passcodeTimerDuration";
    _keychainPasscodeIsSimpleUsername = @"passcodeIsSimple";
    _keychainAllowUnlockWithBiometrics = @"allowUnlockWithTouchID";
}


- (void)_addObservers {
    [[NSNotificationCenter defaultCenter]
     addObserver: self
     selector: @selector(_applicationDidEnterBackground)
     name: UIApplicationDidEnterBackgroundNotification
     object: nil];
    [[NSNotificationCenter defaultCenter]
     addObserver: self
     selector: @selector(_applicationWillResignActive)
     name: UIApplicationWillResignActiveNotification
     object: nil];
    [[NSNotificationCenter defaultCenter]
     addObserver: self
     selector: @selector(_applicationDidBecomeActive)
     name: UIApplicationDidBecomeActiveNotification
     object: nil];
    [[NSNotificationCenter defaultCenter]
     addObserver: self
     selector: @selector(_applicationWillEnterForeground)
     name: UIApplicationWillEnterForegroundNotification
     object: nil];
}


#pragma mark - Handling rotation

// Internal method for fetching the current orientation
+ (UIInterfaceOrientation)currentOrientation {
    // statusBarOrientation is deprecated in iOS 13 and windowScene isn't available before iOS 13
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 130000
    if (@available(iOS 13.0, *)) {
        return LTHMainWindow.windowScene.interfaceOrientation;
    }
    else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
#endif
        return [[UIApplication sharedApplication] statusBarOrientation];
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 130000
#pragma clang diagnostic pop
    }
#endif
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    // I'll be honest and mention I have no idea why this line of code below works.
    // Without it, if you present the passcode view as lockscreen (directly on the window)
    // and then inside of a modal, the orientation will be wrong.

    // If you could explain why, I'd be more than grateful :)
    return UIInterfaceOrientationMaskPortrait;
}


// And to his AGWindowView: https://github.com/hfossli/AGWindowView
// Without the 'desiredOrientation' method, using showLockscreen in one orientation,
// then presenting it inside a modal in another orientation would display
// the view in the first orientation.
- (UIInterfaceOrientation)desiredOrientation {
    UIInterfaceOrientation statusBarOrientation = [LTHPasscodeViewController currentOrientation];
    UIInterfaceOrientationMask statusBarOrientationAsMask = UIInterfaceOrientationMaskFromOrientation(statusBarOrientation);

    if (self.supportedInterfaceOrientations & statusBarOrientationAsMask) {
        return statusBarOrientation;
    }
    else {
        if (self.supportedInterfaceOrientations & UIInterfaceOrientationMaskPortrait) {
            return UIInterfaceOrientationPortrait;
        }
        else if (self.supportedInterfaceOrientations & UIInterfaceOrientationMaskLandscapeLeft) {
            return UIInterfaceOrientationLandscapeLeft;
        }
        else if (self.supportedInterfaceOrientations & UIInterfaceOrientationMaskLandscapeRight) {
            return UIInterfaceOrientationLandscapeRight;
        }
        else {
            return UIInterfaceOrientationPortraitUpsideDown;
        }
    }
}


- (void)rotateAccordingToStatusBarOrientationAndSupportedOrientations {
    UIInterfaceOrientation orientation = [self desiredOrientation];
    CGFloat angle = UIInterfaceOrientationAngleOfOrientation(orientation);
    CGAffineTransform transform = CGAffineTransformMakeRotation(angle);
    CGRect frame = self.view.superview.frame;

    if (!CGAffineTransformEqualToTransform(self.view.transform, transform)) {
        self.view.transform = transform;
    }

    if (!CGRectEqualToRect(self.view.frame, frame)) {
        self.view.frame = frame;
    }
}

- (void)disablePasscodeWhenApplicationEntersBackground {
    [[NSNotificationCenter defaultCenter]
     removeObserver:self
     name:UIApplicationDidEnterBackgroundNotification
     object:nil];
    [[NSNotificationCenter defaultCenter]
     removeObserver:self
     name:UIApplicationWillEnterForegroundNotification
     object:nil];
}

- (void)enablePasscodeWhenApplicationEntersBackground {
    // To avoid double registering.
    [self disablePasscodeWhenApplicationEntersBackground];

    [[NSNotificationCenter defaultCenter]
     addObserver:self
     selector:@selector(_applicationDidEnterBackground)
     name:UIApplicationDidEnterBackgroundNotification
     object:nil];
    [[NSNotificationCenter defaultCenter]
     addObserver:self
     selector:@selector(_applicationWillEnterForeground)
     name:UIApplicationWillEnterForegroundNotification
     object:nil];
}


+ (CGFloat)getStatusBarHeight {
    UIInterfaceOrientation orientation = [LTHPasscodeViewController currentOrientation];

    // statusBarFrame is deprecated in iOS 13 and windowScene isn't available before iOS 13
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 130000
    if (@available(iOS 13.0, *)) {
        if (UIInterfaceOrientationIsLandscape(orientation)) {
            return LTHMainWindow.windowScene.statusBarManager.statusBarFrame.size.width;
        }
        else {
            return LTHMainWindow.windowScene.statusBarManager.statusBarFrame.size.height;
        }
    }
    else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
#endif
        if (UIInterfaceOrientationIsLandscape(orientation)) {
            return [UIApplication sharedApplication].statusBarFrame.size.width;
        }
        else {
            return [UIApplication sharedApplication].statusBarFrame.size.height;
        }
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 130000
#pragma clang diagnostic pop
    }
#endif
}


CGFloat UIInterfaceOrientationAngleOfOrientation(UIInterfaceOrientation orientation) {
    CGFloat angle;

    switch (orientation) {
        case UIInterfaceOrientationPortraitUpsideDown:
            angle = M_PI;
            break;
        case UIInterfaceOrientationLandscapeLeft:
            angle = -M_PI_2;
            break;
        case UIInterfaceOrientationLandscapeRight:
            angle = M_PI_2;
            break;
        default:
            angle = 0.0;
            break;
    }

    return angle;
}

UIInterfaceOrientationMask UIInterfaceOrientationMaskFromOrientation(UIInterfaceOrientation orientation) {
    return 1 << orientation;
}

- (void)dealloc {
    [_internalWindow dismiss];
    _internalWindow = nil;
}

#pragma mark - Passcode buttons

- (BOOL) canBecomeFirstResponder {
    return self.internalPasscodeView == nil;
}

- (void) didPressPasscodeButton:(UIButton *)sender {
    if (self.isTempararlyDisabled) { return; }
    // Delete button
    if (sender.tag == 1000) {
        if (self.updatedEnteringPasscode.length < 1) { return; }
        for (UITextField * textField in self.digitTextFieldsArray.reverseObjectEnumerator) {
            if (textField.isSecureTextEntry) {
                textField.secureTextEntry = NO;
                textField.textColor = self.passcodeTextColor;
                self.updatedEnteringPasscode = [self.updatedEnteringPasscode substringToIndex:self.updatedEnteringPasscode.length - 1];
                break;
            }
        }
        return;
    }
    if (sender.tag == 1001) {
        [self _setupFingerPrint];
        return;
    }

    NSString * symbol = [[sender titleLabel] text];
    NSInteger digit = [symbol integerValue];
    for (UITextField * textField in self.digitTextFieldsArray) {
        if (textField.isSecureTextEntry) {
            continue;
        }
        textField.secureTextEntry = YES;
        textField.textColor = self.passcodeColor;
        self.updatedEnteringPasscode = [NSString stringWithFormat:@"%@%ld", self.updatedEnteringPasscode, (long)digit];
        break;
    }
    if (self.updatedEnteringPasscode.length >= 4) {
        NSString * typedString = self.updatedEnteringPasscode;
        // Make the last bullet show up
        [self _validatePasscode:typedString];
    }
}

@end

