//
//  Recording.m
//  VRec3
//
//  Created by Andy Peter Liu Jr. on 2025-08-12.
//

#import "Recording.h"

@implementation Recording

- (instancetype)initWithURL:(NSURL *)url name:(NSString *)name createdAt:(NSDate *)createdAt duration:(NSTimeInterval)duration {
    self = [super init];
    if (self) {
        _fileURL = url;
        _name = name;
        _createdAt = createdAt;
        _duration = duration;
    }
    return self;
}

@end
