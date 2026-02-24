//
//  Recording.h
//  VRec3
//
//  Created by Andy Peter Liu Jr. on 2025-08-12.
//

#import <Foundation/Foundation.h>

@interface Recording : NSObject

@property (strong, nonatomic) NSURL *fileURL;
@property (strong, nonatomic) NSString *name;
@property (strong, nonatomic) NSDate *createdAt;
@property (assign, nonatomic) NSTimeInterval duration;

- (instancetype)initWithURL:(NSURL *)url name:(NSString *)name createdAt:(NSDate *)createdAt duration:(NSTimeInterval)duration;

@end
