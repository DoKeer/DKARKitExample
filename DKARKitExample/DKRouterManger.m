//
//  DKRouterManger.m
//  DKShortVideo
//
//  Created by Keer_LGQ on 2018/3/30.
//  Copyright © 2018年 DK. All rights reserved.
//

#import "DKRouterManger.h"
#import "DKRootViewController.h"
#import "DKARPlayerController.h"

@interface DKRouterManger ()

@end

@implementation DKRouterManger

static DKRouterManger *_shareInstance = nil;

+ (instancetype)shareInstance
{
    static dispatch_once_t predicate;
    
    dispatch_once(&predicate, ^{
        _shareInstance = [[DKRouterManger alloc] init];
    });
    return _shareInstance;
}

#pragma mark public

- (void)onARVideoView:(BOOL)isShow
{
    if (isShow) {
        DKARPlayerController *controller = [[DKARPlayerController alloc] init];
        [self rootViewControllerPresentViewController:controller inContext:NO];

    }else {
        [self rootViewControllerDismissPresentedViewControllerAnimated:YES];
    }
}

#pragma mark navgation
- (void)rootViewControllerPushViewController:(id)viewController
{
    if ([viewController isKindOfClass:[UIViewController class]]) {
        [self.rootViewController.navigationController pushViewController:viewController animated:YES];
    }
}

- (void)rootViewControllerPopPushedViewController
{
    [self.rootViewController.navigationController popViewControllerAnimated:YES];
}
// Present a view controller using the root view controller (eaglViewController)
- (void)rootViewControllerPresentViewController:(id)viewController inContext:(BOOL)currentContext
{
    if ([viewController isKindOfClass:[UIViewController class]]) {
        [self.rootViewController presentViewController:viewController animated:YES completion:nil];
    }
}

// Dismiss a view controller presented by the root view controller
// (eaglViewController)
- (void)rootViewControllerDismissPresentedViewControllerAnimated:(BOOL)animated
{
    [self.rootViewController dismissViewControllerAnimated:YES completion:nil];
}


#pragma mark lazy
- (DKRootViewController *)rootViewController
{
    if (!_rootViewController) {
        _rootViewController = [[DKRootViewController alloc] init];
    }
    return _rootViewController;
}


@end
