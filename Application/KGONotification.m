#import "KGONotification.h"
#import "KGOAppDelegate.h"

@implementation KGONotification

@synthesize moduleName;

+ (KGONotification *)notificationWithDictionary:(NSDictionary *)userInfo {
    if ([userInfo objectForKey:@"module"]) {
        KGONotification *notification = (KGONotification *)[NSNotification notificationWithName:@"KGORemoteNotification" object:nil userInfo:userInfo];
        return notification;
    }
    return nil;
}

- (NSString *)moduleName {
    return [self.userInfo objectForKey:@"module"];
}

- (void)markAsRead {
    NSMutableArray *unreadNotifications = [(KGOAppDelegate *)[[UIApplication sharedApplication] delegate] unreadNotifications];
    [unreadNotifications removeObject:self];
}

@end