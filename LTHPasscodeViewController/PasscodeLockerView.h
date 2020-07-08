//
//  PasscodeLockerView.h
//  LTHPasscodeViewController Demo
//
//  Created by Y.Rerikh on 14.05.2020.
//  Copyright © 2020 Roland Leth. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <LocalAuthentication/LocalAuthentication.h>

NS_ASSUME_NONNULL_BEGIN

@protocol PasscodeLockerViewDelegate <NSObject>

- (void) didPressPasscodeButton:(UIButton *)sender;

@end

@interface PasscodeLockerView : UIView
@property (weak, nonatomic) IBOutlet UIImageView *imageIconView;
@property (weak, nonatomic) IBOutlet UITextField *firstDigitField;
@property (weak, nonatomic) IBOutlet UITextField *secondDigitField;
@property (weak, nonatomic) IBOutlet UITextField *thirdDigitField;
@property (weak, nonatomic) IBOutlet UITextField *fourthDigitField;
@property (weak, nonatomic) IBOutlet UIImageView *imageIcon;
@property (weak, nonatomic) IBOutlet UIButton *biometryButton;

@property (weak, nonatomic) id<PasscodeLockerViewDelegate> passcodeButtonDelegate;
@property (weak, nonatomic) IBOutlet UIView *passcodeContainerView;

-(NSArray<UITextField *> *) textFieldsArray;
-(void)configureWithBiometryType:(LABiometryType *)biometryType andFingerImage:(UIImage *)fingerImage andFaceImage:(UIImage *)faceImage;
@end

NS_ASSUME_NONNULL_END
