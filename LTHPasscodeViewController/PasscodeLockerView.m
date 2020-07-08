//
//  PasscodeLockerView.m
//  LTHPasscodeViewController Demo
//
//  Created by Y.Rerikh on 14.05.2020.
//  Copyright © 2020 Roland Leth. All rights reserved.
//

#import "PasscodeLockerView.h"

@implementation PasscodeLockerView

- (IBAction)didPressButton:(UIButton *)sender {
    [self.passcodeButtonDelegate didPressPasscodeButton:sender];
}

-(NSArray<UITextField *> *) textFieldsArray {
    return @[self.firstDigitField, self.secondDigitField, self.thirdDigitField, self.fourthDigitField];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    if ((NSInteger)MAX(UIScreen.mainScreen.bounds.size.height, UIScreen.mainScreen.bounds.size.width) <= 568) {
        self.imageIcon.alpha = 0.0;
    }
}
-(void)configureWithBiometryType:(LABiometryType *)biometryType andFingerImage:(UIImage *)fingerImage andFaceImage:(UIImage *)faceImage {
    if (biometryType == LABiometryTypeTouchID) {
        [self.biometryButton setEnabled:YES];
        [self.biometryButton setImage:fingerImage forState:UIControlStateNormal];
    } else if (biometryType == LABiometryTypeFaceID) {
        [self.biometryButton setEnabled:YES];
        [self.biometryButton setImage:faceImage forState:UIControlStateNormal];
    } else {
        [self.biometryButton setEnabled:NO];
        [self.biometryButton setImage:nil forState:UIControlStateNormal];
    }
}

-(void)awakeFromNib {
    [super awakeFromNib];
    [self.biometryButton setEnabled:NO];
    [self.biometryButton setImage:nil forState:UIControlStateNormal];
}
@end
