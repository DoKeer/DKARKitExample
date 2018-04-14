//
//  ViewController.m
//  DKShortVideo
//
//  Created by Keer_LGQ on 2018/3/29.
//  Copyright © 2018年 DK. All rights reserved.
//

#import "DKRootViewController.h"

@interface DKRootViewController ()

@end

@implementation DKRootViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"DK";
    CGFloat width = [[UIScreen mainScreen] bounds].size.width;

    UIButton *btnAR = [UIButton buttonWithType:UIButtonTypeCustom];
    [btnAR addTarget:self action:@selector(arPlayer) forControlEvents:UIControlEventTouchUpInside];
    [btnAR setBackgroundColor:[UIColor redColor]];
    [btnAR setTitle:@"AR看视频" forState:UIControlStateNormal];
    [btnAR setFrame:CGRectMake(0, 0, 150, 50)];
    [btnAR setCenter:CGPointMake(width/2, 250)];
    [self.view addSubview:btnAR];
}

#pragma mark - play control
- (void)arPlayer
{
    [[DKRouterManger shareInstance] onARVideoView:YES];
}

@end
