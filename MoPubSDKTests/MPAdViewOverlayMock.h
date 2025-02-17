//
//  MPAdViewOverlayMock.h
//
//  Copyright 2018-2021 Twitter, Inc.
//  Licensed under the MoPub SDK License Agreement
//  http://www.mopub.com/legal/sdk-license-agreement/
//

#import <Foundation/Foundation.h>
#import "MPAdViewOverlay.h"

NS_ASSUME_NONNULL_BEGIN

@interface MPAdViewOverlayMock : MPAdViewOverlay
@property (nonatomic, assign, readonly) BOOL isPaused;
@end

NS_ASSUME_NONNULL_END
