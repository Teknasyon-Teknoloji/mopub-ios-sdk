//
//  MPRewardedAdsTests.m
//
//  Copyright 2018-2021 Twitter, Inc.
//  Licensed under the MoPub SDK License Agreement
//  http://www.mopub.com/legal/sdk-license-agreement/
//

#import <XCTest/XCTest.h>
#import "MoPub.h"
#import "MPAdConfiguration.h"
#import "MPAdServerKeys.h"
#import "MPFullscreenAdAdapter.h"
#import "MPMockAdServerCommunicator.h"
#import "MPMoPubFullscreenAdAdapter.h"
#import "MPProxy.h"
#import "MPRewardedAds+Testing.h"
#import "MPRewardedAdsDelegateMock.h"
#import "MPURL.h"
#import "NSURLComponents+Testing.h"

static NSString * const kTestAdUnitId    = @"967f82c7-c059-4ae8-8cb6-41c34265b1ef";
static const NSTimeInterval kTestTimeout = 2; // seconds

@interface MPRewardedAdsTests : XCTestCase

@property (nonatomic, strong) MPRewardedAdsDelegateMock *delegateMock;
@property (nonatomic, strong) MPProxy *mockProxy;

@end

@implementation MPRewardedAdsTests

- (void)setUp {
    [super setUp];

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        MPMoPubConfiguration * config = [[MPMoPubConfiguration alloc] initWithAdUnitIdForAppInitialization:kTestAdUnitId];
        config.additionalNetworks = nil;
        config.globalMediationSettings = nil;
        [MoPub.sharedInstance initializeSdkWithConfiguration:config completion:nil];
    });

    self.mockProxy = [[MPProxy alloc] initWithTarget:[MPRewardedAdsDelegateMock new]];
    self.delegateMock = (MPRewardedAdsDelegateMock *)self.mockProxy;
}

- (void)tearDown {
    [super tearDown];

    self.mockProxy = nil;
    self.delegateMock = nil;
}

#pragma mark - Delegates

- (void)testRewardedSuccessfulDelegateSetUnset {
    // Fake ad unit ID
    NSString * adUnitId = [NSString stringWithFormat:@"%@:%s", kTestAdUnitId, __FUNCTION__];

    // Set the delegate handler

    [MPRewardedAds setDelegate:self.delegateMock forAdUnitId:adUnitId];

    id<MPRewardedAdsDelegate> handler = [MPRewardedAds.sharedInstance.delegateTable objectForKey:adUnitId];
    XCTAssertNotNil(handler);
    XCTAssert(handler == self.delegateMock);

    // Unset the delegate handler
    [MPRewardedAds removeDelegateForAdUnitId:adUnitId];
    handler = [MPRewardedAds.sharedInstance.delegateTable objectForKey:adUnitId];
    XCTAssertNil(handler);
}

- (void)testRewardedSuccessfulDelegateSetUnsetMultiple {
    // Fake ad unit ID
    NSString * adUnitId1 = [NSString stringWithFormat:@"%@:%s_1", kTestAdUnitId, __FUNCTION__];
    NSString * adUnitId2 = [NSString stringWithFormat:@"%@:%s_2", kTestAdUnitId, __FUNCTION__];

    // Set the delegate handler
    [MPRewardedAds setDelegate:self.delegateMock forAdUnitId:adUnitId1];
    [MPRewardedAds setDelegate:self.delegateMock forAdUnitId:adUnitId2];

    id<MPRewardedAdsDelegate> handler1 = [MPRewardedAds.sharedInstance.delegateTable objectForKey:adUnitId1];
    XCTAssertNotNil(handler1);
    XCTAssert(handler1 == self.delegateMock);

    id<MPRewardedAdsDelegate> handler2 = [MPRewardedAds.sharedInstance.delegateTable objectForKey:adUnitId2];
    XCTAssertNotNil(handler2);
    XCTAssert(handler2 == self.delegateMock);

    // Unset the delegate handler
    [MPRewardedAds removeDelegate:self.delegateMock];
    handler1 = [MPRewardedAds.sharedInstance.delegateTable objectForKey:adUnitId1];
    XCTAssertNil(handler1);

    handler2 = [MPRewardedAds.sharedInstance.delegateTable objectForKey:adUnitId2];
    XCTAssertNil(handler2);
}

- (void)testRewardedSuccessfulDelegateSetAutoNil {
    // Fake ad unit ID
    NSString * adUnitId = [NSString stringWithFormat:@"%@:%s", kTestAdUnitId, __FUNCTION__];

    // Use autorelease pool to force memory cleanup
    @autoreleasepool {
        // Set the delegate handler
        MPRewardedAdsDelegateMock *delegateHandler = [MPRewardedAdsDelegateMock new];
        [MPRewardedAds setDelegate:delegateHandler forAdUnitId:adUnitId];

        id<MPRewardedAdsDelegate> handler = [MPRewardedAds.sharedInstance.delegateTable objectForKey:adUnitId];
        XCTAssertNotNil(handler);
        XCTAssert(handler == delegateHandler);

        delegateHandler = nil;
    }

    // Verify no handler
    id<MPRewardedAdsDelegate> handler = [MPRewardedAds.sharedInstance.delegateTable objectForKey:adUnitId];
    XCTAssertNil(handler);
}

- (void)testRewardedSetNilDelegate {
    // Fake ad unit ID
    NSString * adUnitId = nil;

    // Set the delegate handler
    [MPRewardedAds setDelegate:self.delegateMock forAdUnitId:adUnitId];

    id<MPRewardedAdsDelegate> handler = [MPRewardedAds.sharedInstance.delegateTable objectForKey:adUnitId];
    XCTAssertNil(handler);
}

- (void)testRewardedSetNilDelegateHandler {
    // Fake ad unit ID
    NSString * adUnitId = [NSString stringWithFormat:@"%@:%s", kTestAdUnitId, __FUNCTION__];

    // Set the delegate handler
    [MPRewardedAds setDelegate:nil forAdUnitId:adUnitId];

    id<MPRewardedAdsDelegate> handler = [MPRewardedAds.sharedInstance.delegateTable objectForKey:adUnitId];
    XCTAssertNil(handler);
}

#pragma mark - Single Currency

- (void)testRewardedSingleCurrencyPresentationSuccess {
    // Setup rewarded ad configuration
    NSDictionary * headers = @{
        kFormatMetadataKey: kAdTypeFullscreen,
        kRewardedVideoCurrencyNameMetadataKey: @"Diamonds",
        kRewardedVideoCurrencyAmountMetadataKey: @"3",
    };
    MPAdConfiguration * config = [[MPAdConfiguration alloc] initWithMetadata:headers data:nil isFullscreenAd:YES isRewarded:YES];

    // Semaphore to wait for asynchronous method to finish before continuing the test.
    XCTestExpectation * expectation = [self expectationWithDescription:@"Wait for reward completion block to fire."];

    // Configure delegate handler to listen for the reward event.
    __block MPReward *rewardForUser = nil;
    [self.mockProxy registerSelector:@selector(rewardedAdShouldRewardForAdUnitID:reward:)
                       forPostAction:^(NSInvocation *invocation) {
        __unsafe_unretained MPReward *reward;
        [invocation getArgument:&reward atIndex:3];
        rewardForUser = reward;
        [expectation fulfill];
    }];

    NSString * adUnitId = [NSString stringWithFormat:@"%@:%s", kTestAdUnitId, __FUNCTION__];
    [MPRewardedAds setDelegate:self.delegateMock forAdUnitId:adUnitId];
    [MPRewardedAds loadRewardedAdWithAdUnitID:adUnitId withTestConfiguration:config];

    MPReward *singleReward = ({
        NSArray<MPReward *> * rewards = [MPRewardedAds availableRewardsForAdUnitID:adUnitId];
        rewards.firstObject;
    });
    [MPRewardedAds presentRewardedAdForAdUnitID:adUnitId
                                    fromViewController:[UIViewController new]
                                            withReward:singleReward];

    [self waitForExpectationsWithTimeout:kTestTimeout handler:^(NSError * _Nullable error) {
        XCTAssertNil(error);
    }];

    XCTAssertNotNil(rewardForUser);
    XCTAssert([rewardForUser.currencyType isEqualToString:@"Diamonds"]);
    XCTAssert(rewardForUser.amount.integerValue == 3);

    [MPRewardedAds removeDelegateForAdUnitId:adUnitId];
}

- (void)testRewardedSingleItemInMultiCurrencyPresentationSuccess {
    // {
    //   "rewards": [
    //     { "name": "Coins", "amount": 8 }
    //   ]
    // }
    NSDictionary * headers = @{
        kFormatMetadataKey: kAdTypeFullscreen,
        kRewardedCurrenciesMetadataKey: @{ @"rewards": @[ @{ @"name": @"Coins", @"amount": @(8) } ] }
    };
    MPAdConfiguration * config = [[MPAdConfiguration alloc] initWithMetadata:headers data:nil isFullscreenAd:YES isRewarded:YES];

    // Semaphore to wait for asynchronous method to finish before continuing the test.
    XCTestExpectation * expectation = [self expectationWithDescription:@"Wait for reward completion block to fire."];

    // Configure delegate handler to listen for the reward event.
    __block MPReward *rewardForUser = nil;
    [self.mockProxy registerSelector:@selector(rewardedAdShouldRewardForAdUnitID:reward:)
                       forPostAction:^(NSInvocation *invocation) {
        __unsafe_unretained MPReward *reward;
        [invocation getArgument:&reward atIndex:3];
        rewardForUser = reward;
        [expectation fulfill];
    }];

    NSString * adUnitId = [NSString stringWithFormat:@"%@:%s", kTestAdUnitId, __FUNCTION__];
    [MPRewardedAds setDelegate:self.delegateMock forAdUnitId:adUnitId];
    [MPRewardedAds loadRewardedAdWithAdUnitID:adUnitId withTestConfiguration:config];

    MPReward *singleReward = ({
        NSArray<MPReward *> * rewards = [MPRewardedAds availableRewardsForAdUnitID:adUnitId];
        rewards.firstObject;
    });
    [MPRewardedAds presentRewardedAdForAdUnitID:adUnitId
                                    fromViewController:[UIViewController new]
                                            withReward:singleReward];

    [self waitForExpectationsWithTimeout:kTestTimeout handler:^(NSError * _Nullable error) {
        XCTAssertNil(error);
    }];

    XCTAssertNotNil(rewardForUser);
    XCTAssert([rewardForUser.currencyType isEqualToString:@"Coins"]);
    XCTAssert(rewardForUser.amount.integerValue == 8);

    [MPRewardedAds removeDelegateForAdUnitId:adUnitId];
}

- (void)testRewardedSingleItemInMultiCurrencyPresentationS2SSuccess {
    // {
    //   "rewards": [
    //     { "name": "Coins", "amount": 8 }
    //   ]
    // }
    NSDictionary * headers = @{
        kFormatMetadataKey: kAdTypeFullscreen,
        kRewardedVideoCompletionUrlMetadataKey: @"https://test.com?verifier=123",
        kRewardedCurrenciesMetadataKey: @{ @"rewards": @[ @{ @"name": @"Coins", @"amount": @(8) } ] }
    };
    MPAdConfiguration * config = [[MPAdConfiguration alloc] initWithMetadata:headers data:nil isFullscreenAd:YES isRewarded:YES];

    // Semaphore to wait for asynchronous method to finish before continuing the test.
    XCTestExpectation * expectation = [self expectationWithDescription:@"Wait for reward completion block to fire."];

    // Configure delegate handler to listen for the reward event.
    __block MPReward *rewardForUser = nil;
    [self.mockProxy registerSelector:@selector(rewardedAdShouldRewardForAdUnitID:reward:)
                       forPostAction:^(NSInvocation *invocation) {
        __unsafe_unretained MPReward *reward;
        [invocation getArgument:&reward atIndex:3];
        rewardForUser = reward;
    }];

    // Configure delegate that listens for S2S connection event.
    __block NSURL * s2sUrl = nil;
    MPRewardedAds.didSendServerToServerCallbackUrl = ^(NSURL * url) {
        s2sUrl = url;
        [expectation fulfill];
    };

    NSString * adUnitId = [NSString stringWithFormat:@"%@:%s", kTestAdUnitId, __FUNCTION__];
    [MPRewardedAds setDelegate:self.delegateMock forAdUnitId:adUnitId];
    [MPRewardedAds loadRewardedAdWithAdUnitID:adUnitId withTestConfiguration:config];

    MPReward *singleReward = ({
        NSArray<MPReward *> * rewards = [MPRewardedAds availableRewardsForAdUnitID:adUnitId];
        rewards.firstObject;
    });
    [MPRewardedAds presentRewardedAdForAdUnitID:adUnitId
                                    fromViewController:[UIViewController new]
                                            withReward:singleReward];

    [self waitForExpectationsWithTimeout:kTestTimeout handler:^(NSError * _Nullable error) {
        XCTAssertNil(error);
    }];

    XCTAssertNotNil(rewardForUser);
    XCTAssertNotNil(s2sUrl);

    MPURL * s2sMoPubUrl = [s2sUrl isKindOfClass:[MPURL class]] ? (MPURL *)s2sUrl : nil;
    XCTAssertNotNil(s2sMoPubUrl);
    XCTAssert([[s2sMoPubUrl stringForPOSTDataKey:kRewardedCurrencyNameKey] isEqualToString:@"Coins"]);
    XCTAssert([[s2sMoPubUrl stringForPOSTDataKey:kRewardedCurrencyAmountKey] isEqualToString:@"8"]);

    [MPRewardedAds removeDelegateForAdUnitId:adUnitId];
}

#pragma mark - Multiple Currency

- (void)testRewardedMultiCurrencyPresentationSuccess {
    // {
    //   "rewards": [
    //     { "name": "Coins", "amount": 8 },
    //     { "name": "Diamonds", "amount": 1 },
    //     { "name": "Energy", "amount": 20 }
    //   ]
    // }
    NSDictionary * headers = @{
        kFormatMetadataKey: kAdTypeFullscreen,
        kRewardedCurrenciesMetadataKey: @{ @"rewards": @[ @{ @"name": @"Coins", @"amount": @(8) }, @{ @"name": @"Diamonds", @"amount": @(1) }, @{ @"name": @"Energy", @"amount": @(20) } ] }
    };
    MPAdConfiguration * config = [[MPAdConfiguration alloc] initWithMetadata:headers data:nil isFullscreenAd:YES isRewarded:YES];

    // Semaphore to wait for asynchronous method to finish before continuing the test.
    XCTestExpectation * expectation = [self expectationWithDescription:@"Wait for reward completion block to fire."];

    // Configure delegate handler to listen for the reward event.
    __block MPReward *rewardForUser = nil;
    [self.mockProxy registerSelector:@selector(rewardedAdShouldRewardForAdUnitID:reward:)
                       forPostAction:^(NSInvocation *invocation) {
        __unsafe_unretained MPReward *reward;
        [invocation getArgument:&reward atIndex:3];
        rewardForUser = reward;
        [expectation fulfill];
    }];

    NSString * adUnitId = [NSString stringWithFormat:@"%@:%s", kTestAdUnitId, __FUNCTION__];
    [MPRewardedAds setDelegate:self.delegateMock forAdUnitId:adUnitId];
    [MPRewardedAds loadRewardedAdWithAdUnitID:adUnitId withTestConfiguration:config];
    NSArray * availableRewards = [MPRewardedAds availableRewardsForAdUnitID:adUnitId];
    [MPRewardedAds presentRewardedAdForAdUnitID:adUnitId fromViewController:[UIViewController new] withReward:availableRewards[1]];

    [self waitForExpectationsWithTimeout:kTestTimeout handler:^(NSError * _Nullable error) {
        XCTAssertNil(error);
    }];

    XCTAssertNotNil(rewardForUser);
    XCTAssert([rewardForUser.currencyType isEqualToString:@"Diamonds"]);
    XCTAssert(rewardForUser.amount.integerValue == 1);

    [MPRewardedAds removeDelegateForAdUnitId:adUnitId];
}

- (void)testRewardedMultiCurrencyPresentationNilParameterAutoSelectionFailure {
    // {
    //   "rewards": [
    //     { "name": "Coins", "amount": 8 },
    //     { "name": "Diamonds", "amount": 1 },
    //     { "name": "Energy", "amount": 20 }
    //   ]
    // }
    NSDictionary * headers = @{
        kFormatMetadataKey: kAdTypeFullscreen,
        kRewardedCurrenciesMetadataKey: @{ @"rewards": @[ @{ @"name": @"Coins", @"amount": @(8) }, @{ @"name": @"Diamonds", @"amount": @(1) }, @{ @"name": @"Energy", @"amount": @(20) } ] }
    };
    MPAdConfiguration * config = [[MPAdConfiguration alloc] initWithMetadata:headers data:nil isFullscreenAd:YES isRewarded:YES];

    // Semaphore to wait for asynchronous method to finish before continuing the test.
    XCTestExpectation * expectation = [self expectationWithDescription:@"Wait for reward completion block to fire."];

    // Configure delegate handler to listen for the reward event.
    __block MPReward *rewardForUser = nil;
    __block BOOL didFail = NO;
    [self.mockProxy registerSelector:@selector(rewardedAdShouldRewardForAdUnitID:reward:)
                       forPostAction:^(NSInvocation *invocation) {
        __unsafe_unretained MPReward *reward;
        [invocation getArgument:&reward atIndex:3];
        rewardForUser = reward;
        didFail = NO;
        [expectation fulfill];
    }];

    [self.mockProxy registerSelector:@selector(rewardedAdDidFailToShowForAdUnitID:error:)
                       forPostAction:^(NSInvocation *invocation) {
        rewardForUser = nil;
        didFail = YES;
        [expectation fulfill];
    }];

    NSString * adUnitId = [NSString stringWithFormat:@"%@:%s", kTestAdUnitId, __FUNCTION__];
    [MPRewardedAds setDelegate:self.delegateMock forAdUnitId:adUnitId];
    [MPRewardedAds loadRewardedAdWithAdUnitID:adUnitId withTestConfiguration:config];
    [MPRewardedAds presentRewardedAdForAdUnitID:adUnitId fromViewController:[UIViewController new] withReward:nil];

    [self waitForExpectationsWithTimeout:kTestTimeout handler:^(NSError * _Nullable error) {
        XCTAssertNil(error);
    }];

    XCTAssertNil(rewardForUser);
    XCTAssertTrue(didFail);

    [MPRewardedAds removeDelegateForAdUnitId:adUnitId];
}

- (void)testRewardedMultiCurrencyPresentationUnknownSelectionFail {
    // {
    //   "rewards": [
    //     { "name": "Coins", "amount": 8 },
    //     { "name": "Diamonds", "amount": 1 },
    //     { "name": "Energy", "amount": 20 }
    //   ]
    // }
    NSDictionary * headers = @{
        kFormatMetadataKey: kAdTypeFullscreen,
        kRewardedCurrenciesMetadataKey: @{ @"rewards": @[ @{ @"name": @"Coins", @"amount": @(8) }, @{ @"name": @"Diamonds", @"amount": @(1) }, @{ @"name": @"Energy", @"amount": @(20) } ] }
    };
    MPAdConfiguration * config = [[MPAdConfiguration alloc] initWithMetadata:headers data:nil isFullscreenAd:YES isRewarded:YES];

    // Semaphore to wait for asynchronous method to finish before continuing the test.
    XCTestExpectation * expectation = [self expectationWithDescription:@"Wait for reward completion block to fire."];

    // Configure delegate handler to listen for the reward event.
    __block MPReward *rewardForUser = nil;
    __block BOOL didFail = NO;
    [self.mockProxy registerSelector:@selector(rewardedAdShouldRewardForAdUnitID:reward:)
                       forPostAction:^(NSInvocation *invocation) {
        __unsafe_unretained MPReward *reward;
        [invocation getArgument:&reward atIndex:3];
        rewardForUser = reward;
        didFail = NO;
        [expectation fulfill];
    }];

    [self.mockProxy registerSelector:@selector(rewardedAdDidFailToShowForAdUnitID:error:)
                       forPostAction:^(NSInvocation *invocation) {
        rewardForUser = nil;
        didFail = YES;
        [expectation fulfill];
    }];

    // Create a malicious reward
    MPReward *badReward = [[MPReward alloc] initWithCurrencyType:@"$$$" amount:@(100)];

    NSString * adUnitId = [NSString stringWithFormat:@"%@:%s", kTestAdUnitId, __FUNCTION__];
    [MPRewardedAds setDelegate:self.delegateMock forAdUnitId:adUnitId];
    [MPRewardedAds loadRewardedAdWithAdUnitID:adUnitId withTestConfiguration:config];
    [MPRewardedAds presentRewardedAdForAdUnitID:adUnitId
                                    fromViewController:[UIViewController new]
                                            withReward:badReward];

    [self waitForExpectationsWithTimeout:kTestTimeout handler:^(NSError * _Nullable error) {
        XCTAssertNil(error);
    }];

    XCTAssertNil(rewardForUser);
    XCTAssertTrue(didFail);

    [MPRewardedAds removeDelegateForAdUnitId:adUnitId];
}

- (void)testRewardedMultiCurrencyS2SPresentationSuccess {
    // {
    //   "rewards": [
    //     { "name": "Coins", "amount": 8 },
    //     { "name": "Diamonds", "amount": 1 },
    //     { "name": "Energy", "amount": 20 }
    //   ]
    // }
    NSDictionary * headers = @{
        kFormatMetadataKey: kAdTypeFullscreen,
        kRewardedVideoCompletionUrlMetadataKey: @"https://test.com?verifier=123",
        kRewardedCurrenciesMetadataKey: @{ @"rewards": @[ @{ @"name": @"Coins", @"amount": @(8) }, @{ @"name": @"Diamonds", @"amount": @(1) }, @{ @"name": @"Energy", @"amount": @(20) } ] }
    };
    MPAdConfiguration * config = [[MPAdConfiguration alloc] initWithMetadata:headers data:nil isFullscreenAd:YES isRewarded:YES];

    // Semaphore to wait for asynchronous method to finish before continuing the test.
    XCTestExpectation * expectation = [self expectationWithDescription:@"Wait for reward completion block to fire."];

    // Configure delegate handler to listen for the reward event.
    __block MPReward *rewardForUser = nil;
    [self.mockProxy registerSelector:@selector(rewardedAdShouldRewardForAdUnitID:reward:)
                       forPostAction:^(NSInvocation *invocation) {
        __unsafe_unretained MPReward *reward;
        [invocation getArgument:&reward atIndex:3];
        rewardForUser = reward;
    }];

    // Configure delegate that listens for S2S connection event.
    __block NSURL * s2sUrl = nil;
    MPRewardedAds.didSendServerToServerCallbackUrl = ^(NSURL * url) {
        s2sUrl = url;
        [expectation fulfill];
    };

    NSString * adUnitId = [NSString stringWithFormat:@"%@:%s", kTestAdUnitId, __FUNCTION__];
    [MPRewardedAds setDelegate:self.delegateMock forAdUnitId:adUnitId];
    [MPRewardedAds loadRewardedAdWithAdUnitID:adUnitId withTestConfiguration:config];
    NSArray * availableRewards = [MPRewardedAds availableRewardsForAdUnitID:adUnitId];
    [MPRewardedAds presentRewardedAdForAdUnitID:adUnitId fromViewController:[UIViewController new] withReward:availableRewards[1]];

    [self waitForExpectationsWithTimeout:kTestTimeout handler:^(NSError * _Nullable error) {
        XCTAssertNil(error);
    }];

    XCTAssertNotNil(rewardForUser);
    XCTAssertNotNil(s2sUrl);

    MPURL * s2sMoPubUrl = [s2sUrl isKindOfClass:[MPURL class]] ? (MPURL *)s2sUrl : nil;
    XCTAssertNotNil(s2sMoPubUrl);
    XCTAssert([[s2sMoPubUrl stringForPOSTDataKey:kRewardedCurrencyNameKey] isEqualToString:@"Diamonds"]);
    XCTAssert([[s2sMoPubUrl stringForPOSTDataKey:kRewardedCurrencyAmountKey] isEqualToString:@"1"]);

    [MPRewardedAds removeDelegateForAdUnitId:adUnitId];
}

- (void)testRewardedS2SNoRewardSpecified {
    NSDictionary *headers = @{
        kFormatMetadataKey: kAdTypeFullscreen,
        kRewardedVideoCompletionUrlMetadataKey: @"https://test.com?verifier=123"
    };
    MPAdConfiguration * config = [[MPAdConfiguration alloc] initWithMetadata:headers data:nil isFullscreenAd:YES isRewarded:YES];

    // Semaphore to wait for asynchronous method to finish before continuing the test.
    XCTestExpectation * expectation = [self expectationWithDescription:@"Wait for reward completion block to fire."];

    // Configure delegate handler to listen for the reward event.
    __block MPReward *rewardForUser = nil;
    [self.mockProxy registerSelector:@selector(rewardedAdShouldRewardForAdUnitID:reward:)
                       forPostAction:^(NSInvocation *invocation) {
        __unsafe_unretained MPReward *reward;
        [invocation getArgument:&reward atIndex:3];
        rewardForUser = reward;
    }];

    // Configure delegate that listens for S2S connection event.
    __block NSURL * s2sUrl = nil;
    MPRewardedAds.didSendServerToServerCallbackUrl = ^(NSURL * url) {
        s2sUrl = url;
        [expectation fulfill];
    };

    NSString * adUnitId = [NSString stringWithFormat:@"%@:%s", kTestAdUnitId, __FUNCTION__];
    [MPRewardedAds setDelegate:self.delegateMock forAdUnitId:adUnitId];
    [MPRewardedAds loadRewardedAdWithAdUnitID:adUnitId withTestConfiguration:config];
    NSArray * availableRewards = [MPRewardedAds availableRewardsForAdUnitID:kTestAdUnitId];
    [MPRewardedAds presentRewardedAdForAdUnitID:adUnitId fromViewController:[UIViewController new] withReward:availableRewards[0]];

    [self waitForExpectationsWithTimeout:kTestTimeout handler:^(NSError * _Nullable error) {
        XCTAssertNil(error);
    }];

    XCTAssertNotNil(rewardForUser);
    XCTAssertNotNil(s2sUrl);

    NSURLComponents * s2sUrlComponents = [NSURLComponents componentsWithURL:s2sUrl resolvingAgainstBaseURL:NO];
    XCTAssertFalse([s2sUrlComponents hasQueryParameter:@"rcn"]);
    XCTAssertFalse([s2sUrlComponents valueForQueryParameter:@"rca"]);

    [MPRewardedAds removeDelegateForAdUnitId:adUnitId];
}

#pragma mark - Custom Data

- (void)testCustomDataNormalDataLength {
    // Generate a custom data string that is well under 8196 characters
    NSString * customData = [@"" stringByPaddingToLength:512 withString:@"test" startingAtIndex:0];

    // Setup rewarded ad configuration
    NSDictionary * headers = @{
        kFormatMetadataKey: kAdTypeFullscreen,
        kRewardedVideoCurrencyNameMetadataKey: @"Diamonds",
        kRewardedVideoCurrencyAmountMetadataKey: @"3",
        kRewardedVideoCompletionUrlMetadataKey: @"https://test.com?verifier=123",
    };
    MPAdConfiguration * config = [[MPAdConfiguration alloc] initWithMetadata:headers data:nil isFullscreenAd:YES isRewarded:YES];

    // Semaphore to wait for asynchronous method to finish before continuing the test.
    XCTestExpectation * expectation = [self expectationWithDescription:@"Wait for reward completion block to fire."];

    // Configure delegate that listens for S2S connection event.
    __block NSURL * s2sUrl = nil;
    MPRewardedAds.didSendServerToServerCallbackUrl = ^(NSURL * url) {
        s2sUrl = url;
        [expectation fulfill];
    };

    NSString * adUnitId = [NSString stringWithFormat:@"%@:%s", kTestAdUnitId, __FUNCTION__];
    [MPRewardedAds loadRewardedAdWithAdUnitID:adUnitId withTestConfiguration:config];
    MPReward *reward = [MPRewardedAds availableRewardsForAdUnitID:kTestAdUnitId][0];
    [MPRewardedAds presentRewardedAdForAdUnitID:adUnitId
                                    fromViewController:[UIViewController new]
                                            withReward:reward
                                            customData:customData];

    [self waitForExpectationsWithTimeout:kTestTimeout handler:^(NSError * _Nullable error) {
        XCTAssertNil(error);
    }];

    XCTAssertNotNil(s2sUrl);

    MPURL * s2sMoPubUrl = [s2sUrl isKindOfClass:[MPURL class]] ? (MPURL *)s2sUrl : nil;
    XCTAssertNotNil(s2sMoPubUrl);
    XCTAssert([[s2sMoPubUrl stringForPOSTDataKey:kRewardedCustomDataKey] isEqualToString:customData]);
}

- (void)testCustomDataExcessiveDataLength {
    // Generate a custom data string that exceeds 8196 characters
    NSString * customData = [@"" stringByPaddingToLength:8200 withString:@"test" startingAtIndex:0];

    // Setup rewarded ad configuration
    NSDictionary * headers = @{
        kFormatMetadataKey: kAdTypeFullscreen,
        kRewardedVideoCurrencyNameMetadataKey: @"Diamonds",
        kRewardedVideoCurrencyAmountMetadataKey: @"3",
        kRewardedVideoCompletionUrlMetadataKey: @"https://test.com?verifier=123",
    };
    MPAdConfiguration * config = [[MPAdConfiguration alloc] initWithMetadata:headers data:nil isFullscreenAd:YES isRewarded:YES];

    // Semaphore to wait for asynchronous method to finish before continuing the test.
    XCTestExpectation * expectation = [self expectationWithDescription:@"Wait for reward completion block to fire."];

    // Configure delegate that listens for S2S connection event.
    __block NSURL * s2sUrl = nil;
    MPRewardedAds.didSendServerToServerCallbackUrl = ^(NSURL * url) {
        s2sUrl = url;
        [expectation fulfill];
    };

    NSString * adUnitId = [NSString stringWithFormat:@"%@:%s", kTestAdUnitId, __FUNCTION__];
    [MPRewardedAds loadRewardedAdWithAdUnitID:adUnitId withTestConfiguration:config];
    MPReward *reward = [MPRewardedAds availableRewardsForAdUnitID:kTestAdUnitId][0];
    [MPRewardedAds presentRewardedAdForAdUnitID:adUnitId
                                    fromViewController:[UIViewController new]
                                            withReward:reward
                                            customData:customData];

    [self waitForExpectationsWithTimeout:kTestTimeout handler:^(NSError * _Nullable error) {
        XCTAssertNil(error);
    }];

    XCTAssertNotNil(s2sUrl);

    MPURL * s2sMoPubUrl = [s2sUrl isKindOfClass:[MPURL class]] ? (MPURL *)s2sUrl : nil;
    XCTAssertNotNil(s2sMoPubUrl);
    XCTAssert([[s2sMoPubUrl stringForPOSTDataKey:kRewardedCustomDataKey] isEqualToString:customData]);

    [MPRewardedAds removeDelegateForAdUnitId:adUnitId];
}

- (void)testCustomDataNil {
    // Setup rewarded ad configuration
    NSDictionary * headers = @{
        kFormatMetadataKey: kAdTypeFullscreen,
        kRewardedVideoCurrencyNameMetadataKey: @"Diamonds",
        kRewardedVideoCurrencyAmountMetadataKey: @"3",
        kRewardedVideoCompletionUrlMetadataKey: @"https://test.com?verifier=123",
    };
    MPAdConfiguration * config = [[MPAdConfiguration alloc] initWithMetadata:headers data:nil isFullscreenAd:YES isRewarded:YES];

    // Semaphore to wait for asynchronous method to finish before continuing the test.
    XCTestExpectation * expectation = [self expectationWithDescription:@"Wait for reward completion block to fire."];

    // Configure delegate that listens for S2S connection event.
    __block NSURL * s2sUrl = nil;
    MPRewardedAds.didSendServerToServerCallbackUrl = ^(NSURL * url) {
        s2sUrl = url;
        [expectation fulfill];
    };

    NSString * adUnitId = [NSString stringWithFormat:@"%@:%s", kTestAdUnitId, __FUNCTION__];
    [MPRewardedAds loadRewardedAdWithAdUnitID:adUnitId withTestConfiguration:config];
    MPReward *reward = [MPRewardedAds availableRewardsForAdUnitID:kTestAdUnitId][0];
    [MPRewardedAds presentRewardedAdForAdUnitID:adUnitId
                                    fromViewController:[UIViewController new]
                                            withReward:reward
                                            customData:nil];

    [self waitForExpectationsWithTimeout:kTestTimeout handler:^(NSError * _Nullable error) {
        XCTAssertNil(error);
    }];

    XCTAssertNotNil(s2sUrl);
    XCTAssert(![s2sUrl.absoluteString containsString:@"rcd="]);
}

- (void)testCustomDataEmpty {
    // Setup rewarded ad configuration
    NSDictionary * headers = @{
        kFormatMetadataKey: kAdTypeFullscreen,
        kRewardedVideoCurrencyNameMetadataKey: @"Diamonds",
        kRewardedVideoCurrencyAmountMetadataKey: @"3",
        kRewardedVideoCompletionUrlMetadataKey: @"https://test.com?verifier=123",
    };
    MPAdConfiguration * config = [[MPAdConfiguration alloc] initWithMetadata:headers data:nil isFullscreenAd:YES isRewarded:YES];

    // Semaphore to wait for asynchronous method to finish before continuing the test.
    XCTestExpectation * expectation = [self expectationWithDescription:@"Wait for reward completion block to fire."];

    // Configure delegate that listens for S2S connection event.
    __block NSURL * s2sUrl = nil;
    MPRewardedAds.didSendServerToServerCallbackUrl = ^(NSURL * url) {
        s2sUrl = url;
        [expectation fulfill];
    };

    NSString * adUnitId = [NSString stringWithFormat:@"%@:%s", kTestAdUnitId, __FUNCTION__];
    [MPRewardedAds loadRewardedAdWithAdUnitID:adUnitId withTestConfiguration:config];
    MPReward *reward = [MPRewardedAds availableRewardsForAdUnitID:kTestAdUnitId][0];
    [MPRewardedAds presentRewardedAdForAdUnitID:adUnitId
                                    fromViewController:[UIViewController new]
                                            withReward:reward
                                            customData:@""];

    [self waitForExpectationsWithTimeout:kTestTimeout handler:^(NSError * _Nullable error) {
        XCTAssertNil(error);
    }];

    XCTAssertNotNil(s2sUrl);
    XCTAssert(![s2sUrl.absoluteString containsString:@"rcd="]);
}

- (void)testCustomDataInPOSTData {
    // Custom data in need of URI encoding
    NSString * customData = @"{ \"key\": \"some value with spaces\" }";

    // Setup rewarded ad configuration
    NSDictionary * headers = @{
        kFormatMetadataKey: kAdTypeFullscreen,
        kRewardedVideoCurrencyNameMetadataKey: @"Diamonds",
        kRewardedVideoCurrencyAmountMetadataKey: @"3",
        kRewardedVideoCompletionUrlMetadataKey: @"https://test.com?verifier=123",
    };
    MPAdConfiguration * config = [[MPAdConfiguration alloc] initWithMetadata:headers data:nil isFullscreenAd:YES isRewarded:YES];

    // Semaphore to wait for asynchronous method to finish before continuing the test.
    XCTestExpectation * expectation = [self expectationWithDescription:@"Wait for reward completion block to fire."];

    // Configure delegate that listens for S2S connection event.
    __block NSURL * s2sUrl = nil;
    MPRewardedAds.didSendServerToServerCallbackUrl = ^(NSURL * url) {
        s2sUrl = url;
        [expectation fulfill];
    };

    NSString * adUnitId = [NSString stringWithFormat:@"%@:%s", kTestAdUnitId, __FUNCTION__];
    [MPRewardedAds loadRewardedAdWithAdUnitID:adUnitId withTestConfiguration:config];
    MPReward *reward = [MPRewardedAds availableRewardsForAdUnitID:kTestAdUnitId][0];
    [MPRewardedAds presentRewardedAdForAdUnitID:adUnitId
                                    fromViewController:[UIViewController new]
                                            withReward:reward
                                            customData:customData];

    [self waitForExpectationsWithTimeout:kTestTimeout handler:^(NSError * _Nullable error) {
        XCTAssertNil(error);
    }];

    XCTAssertNotNil(s2sUrl);

    MPURL * s2sMoPubUrl = [s2sUrl isKindOfClass:[MPURL class]] ? (MPURL *)s2sUrl : nil;
    XCTAssertNotNil(s2sMoPubUrl);
    XCTAssert([[s2sMoPubUrl stringForPOSTDataKey:kRewardedCustomDataKey] isEqualToString:customData]);
}

- (void)testCustomDataLocalReward {
    // Generate a custom data string that is well under 8196 characters
    NSString * customData = [@"" stringByPaddingToLength:512 withString:@"test" startingAtIndex:0];

    // Setup rewarded ad configuration
    NSDictionary * headers = @{
        kFormatMetadataKey: kAdTypeFullscreen,
        kRewardedVideoCurrencyNameMetadataKey: @"Diamonds",
        kRewardedVideoCurrencyAmountMetadataKey: @"3",
    };
    MPAdConfiguration * config = [[MPAdConfiguration alloc] initWithMetadata:headers data:nil isFullscreenAd:YES isRewarded:YES];

    // Semaphore to wait for asynchronous method to finish before continuing the test.
    XCTestExpectation * expectation = [self expectationWithDescription:@"Wait for reward completion block to fire."];

    // Configure delegate that listens for S2S connection event.
    __block NSURL * s2sUrl = nil;
    MPRewardedAds.didSendServerToServerCallbackUrl = ^(NSURL * url) {
        s2sUrl = url;
    };

    // Configure delegate handler to listen for the reward event.
    __block MPReward *rewardForUser = nil;
    [self.mockProxy registerSelector:@selector(rewardedAdShouldRewardForAdUnitID:reward:)
                       forPostAction:^(NSInvocation *invocation) {
        __unsafe_unretained MPReward *reward;
        [invocation getArgument:&reward atIndex:3];
        rewardForUser = reward;
        [expectation fulfill];
    }];

    NSString * adUnitId = [NSString stringWithFormat:@"%@:%s", kTestAdUnitId, __FUNCTION__];
    [MPRewardedAds setDelegate:self.delegateMock forAdUnitId:adUnitId];
    [MPRewardedAds loadRewardedAdWithAdUnitID:adUnitId withTestConfiguration:config];
    MPReward *reward = [MPRewardedAds availableRewardsForAdUnitID:kTestAdUnitId][0];

    MPRewardedAdManager * manager = [MPRewardedAds adManagerForAdUnitId:adUnitId];
    MPFullscreenAdAdapter* adapter = manager.adapter;

    [MPRewardedAds presentRewardedAdForAdUnitID:adUnitId
                                    fromViewController:[UIViewController new]
                                            withReward:reward
                                            customData:customData];

    [self waitForExpectationsWithTimeout:kTestTimeout handler:^(NSError * _Nullable error) {
        XCTAssertNil(error);
    }];

    XCTAssertNil(s2sUrl);
    XCTAssertNotNil(adapter);
    XCTAssertNil(adapter.customData);

    [MPRewardedAds removeDelegateForAdUnitId:adUnitId];
}

- (void)testNetworkIdentifierInRewardCallback {
    // Setup rewarded ad configuration
    NSDictionary * headers = @{
        kFormatMetadataKey: kAdTypeFullscreen,
        kCustomEventClassNameMetadataKey: @"MPMockChartboostRewardedVideoCustomEvent",
        kRewardedVideoCurrencyNameMetadataKey: @"Diamonds",
        kRewardedVideoCurrencyAmountMetadataKey: @"3",
        kRewardedVideoCompletionUrlMetadataKey: @"https://test.com?verifier=123",
    };
    MPAdConfiguration * config = [[MPAdConfiguration alloc] initWithMetadata:headers data:nil isFullscreenAd:YES isRewarded:YES];

    // Semaphore to wait for asynchronous method to finish before continuing the test.
    XCTestExpectation * expectation = [self expectationWithDescription:@"Wait for reward completion block to fire."];

    // Configure delegate that listens for S2S connection event.
    __block NSURL * s2sUrl = nil;
    MPRewardedAds.didSendServerToServerCallbackUrl = ^(NSURL * url) {
        s2sUrl = url;
        [expectation fulfill];
    };

    NSString * adUnitId = [NSString stringWithFormat:@"%@:%s", kTestAdUnitId, __FUNCTION__];
    [MPRewardedAds loadRewardedAdWithAdUnitID:adUnitId withTestConfiguration:config];
    MPReward *reward = [MPRewardedAds availableRewardsForAdUnitID:kTestAdUnitId][0];
    [MPRewardedAds presentRewardedAdForAdUnitID:adUnitId
                                    fromViewController:[UIViewController new]
                                            withReward:reward
                                            customData:nil];

    [self waitForExpectationsWithTimeout:kTestTimeout handler:^(NSError * _Nullable error) {
        XCTAssertNil(error);
    }];

    XCTAssertNotNil(s2sUrl);

    MPURL * s2sMoPubUrl = [s2sUrl isKindOfClass:[MPURL class]] ? (MPURL *)s2sUrl : nil;
    XCTAssertNotNil(s2sMoPubUrl);
    XCTAssert([[s2sMoPubUrl stringForPOSTDataKey:kRewardedAdapterClassNameKey] isEqualToString:@"MPMockChartboostRewardedVideoCustomEvent"]);
}

- (void)testMoPubNetworkIdentifierInRewardCallback {
    // Setup rewarded ad configuration
    NSDictionary * headers = @{
        kAdTypeMetadataKey: kAdTypeInterstitial,
        kFullAdTypeMetadataKey: kAdTypeVAST,
        kFormatMetadataKey: kAdTypeFullscreen,
        kCustomEventClassNameMetadataKey: kAdTypeFullscreen,
        kRewardedVideoCurrencyNameMetadataKey: @"Diamonds",
        kRewardedVideoCurrencyAmountMetadataKey: @"3",
        kRewardedVideoCompletionUrlMetadataKey: @"https://test.com?verifier=123",
    };
    MPAdConfiguration * config = [[MPAdConfiguration alloc] initWithMetadata:headers data:nil isFullscreenAd:YES isRewarded:YES];

    // Semaphore to wait for asynchronous method to finish before continuing the test.
    XCTestExpectation * expectation = [self expectationWithDescription:@"Wait for reward completion block to fire."];

    // Configure delegate that listens for S2S connection event.
    __block NSURL * s2sUrl = nil;
    MPRewardedAds.didSendServerToServerCallbackUrl = ^(NSURL * url) {
        s2sUrl = url;
        [expectation fulfill];
    };

    NSString * adUnitId = [NSString stringWithFormat:@"%@:%s", kTestAdUnitId, __FUNCTION__];
    [MPRewardedAds loadRewardedAdWithAdUnitID:adUnitId withTestConfiguration:config];
    MPReward *reward = [MPRewardedAds availableRewardsForAdUnitID:kTestAdUnitId][0];
    [MPRewardedAds presentRewardedAdForAdUnitID:adUnitId
                                    fromViewController:[UIViewController new]
                                            withReward:reward
                                            customData:nil];

    [self waitForExpectationsWithTimeout:kTestTimeout handler:^(NSError * _Nullable error) {
        XCTAssertNil(error);
    }];

    XCTAssertNotNil(s2sUrl);

    MPURL * s2sMoPubUrl = [s2sUrl isKindOfClass:[MPURL class]] ? (MPURL *)s2sUrl : nil;
    XCTAssertNotNil(s2sMoPubUrl);
    XCTAssert([[s2sMoPubUrl stringForPOSTDataKey:kRewardedAdapterClassNameKey] isEqualToString:NSStringFromClass(MPMoPubFullscreenAdAdapter.class)]);
}

#pragma mark - Ad Sizing

- (void)testRewardedCreativeSizeSent {
    // Semaphore to wait for asynchronous method to finish before continuing the test.
    XCTestExpectation * expectation = [self expectationWithDescription:@"Wait for reward completion block to fire."];

    // Configure delegate handler to listen for the reward event.
    [self.mockProxy registerSelector:@selector(rewardedAdDidFailToLoadForAdUnitID:error:)
                       forPostAction:^(NSInvocation *invocation) {
        // Expecting load failure due to no configuration response.
        // This doesn't matter since we are just verifying the URL that
        // is being sent to the Ad Server communicator.
        [expectation fulfill];
    }];

    NSString * adUnitId = [NSString stringWithFormat:@"%@:%s", kTestAdUnitId, __FUNCTION__];

    MPMockAdServerCommunicator * mockAdServerCommunicator = nil;
    MPRewardedAdManager * manager = [MPRewardedAds makeAdManagerForAdUnitId:adUnitId];
    manager.communicator = ({
        MPMockAdServerCommunicator * mock = [[MPMockAdServerCommunicator alloc] initWithDelegate:manager];
        mockAdServerCommunicator = mock;
        mock;
    });
    [MPRewardedAds setDelegate:self.delegateMock forAdUnitId:adUnitId];
    [MPRewardedAds loadRewardedAdWithAdUnitID:adUnitId withMediationSettings:nil];

    [self waitForExpectationsWithTimeout:kTestTimeout handler:^(NSError * _Nullable error) {
        XCTAssertNil(error);
    }];

    [MPRewardedAds removeDelegateForAdUnitId:adUnitId];

    XCTAssertNotNil(mockAdServerCommunicator);
    XCTAssertNotNil(mockAdServerCommunicator.lastUrlLoaded);

    MPURL * url = [mockAdServerCommunicator.lastUrlLoaded isKindOfClass:[MPURL class]] ? (MPURL *)mockAdServerCommunicator.lastUrlLoaded : nil;
    XCTAssertNotNil(url);

    NSNumber * sc = [url numberForPOSTDataKey:kScaleFactorKey];
    NSNumber * cw = [url numberForPOSTDataKey:kCreativeSafeWidthKey];
    NSNumber * ch = [url numberForPOSTDataKey:kCreativeSafeHeightKey];
    CGRect frame = MPApplicationFrame(YES);
    XCTAssert(cw.floatValue == frame.size.width * sc.floatValue);
    XCTAssert(ch.floatValue == frame.size.height * sc.floatValue);
}

@end
