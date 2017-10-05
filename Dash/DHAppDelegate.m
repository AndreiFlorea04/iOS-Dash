//
//  Copyright (C) 2016  Kapeli
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program.  If not, see <http://www.gnu.org/licenses/>.
//

#import "DHAppDelegate.h"
#import "DHDocsetDownloader.h"
#import "DHUserRepo.h"
#import "DHCheatRepo.h"
#import "DHDocsetTransferrer.h"
#import "DHDocsetManager.h"
#import "DHTarixProtocol.h"
#import "DHBlockProtocol.h"
#import "DHCSS.h"
#import "DHWebViewController.h"
#import "DHAppUpdateChecker.h"
#import "DHDocsetBrowser.h"
#ifdef APP_STORE
#import <HockeySDK/HockeySDK.h>
#endif
#import "DHRemoteServer.h"
#import "DHRemoteProtocol.h"

@implementation DHAppDelegate

+ (DHAppDelegate *)sharedDelegate
{
    return (id)[[UIApplication sharedApplication] delegate];
}

+ (UIStoryboard *)mainStoryboard
{
    return [self sharedDelegate].window.rootViewController.storyboard;
}

- (BOOL)application:(UIApplication *)application willFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    [self setDoNotBackUp]; // this needs to be first because it deletes the preferences after a backup restore
    NSLog(@"Home Path: %@", homePath);
    [self.window makeKeyAndVisible];
    
    NSString *cacheDir = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) lastObject];
    if(cacheDir)
    {
        [[NSFileManager defaultManager] removeItemAtPath:[cacheDir stringByAppendingPathComponent:@"com.apple.nsurlsessiond/Downloads"] error:nil];
    }
    
#ifdef APP_STORE
#ifndef DEBUG
    [[BITHockeyManager sharedHockeyManager] configureWithIdentifier:@"40091a11e4b749fcb7808992057b165a"];
    [[BITHockeyManager sharedHockeyManager].crashManager setCrashManagerStatus:BITCrashManagerStatusAutoSend];
    [[BITHockeyManager sharedHockeyManager] startManager];
    [[BITHockeyManager sharedHockeyManager].authenticator authenticateInstallation];
#endif
#endif
    
#ifdef DEBUG
    [self checkCommitHashes];
#endif
//    NSDictionary *dictionary = [NSDictionary dictionaryWithObjectsAndKeys:@"Mozilla/5.0 (iPhone; CPU iPhone OS 10_10 like Mac OS X) AppleWebKit/600.1.4 (KHTML, like Gecko) Mobile/12B411 Xcode/6.1.0", @"UserAgent", nil];
//    [[NSUserDefaults standardUserDefaults] registerDefaults:dictionary];
    
//    NSLog(@"%@", [[NSUserDefaults standardUserDefaults] dictionaryRepresentation]);

    NSURLCache *sharedCache = [[NSURLCache alloc] initWithMemoryCapacity:4*1024*1024 diskCapacity:32*1024*1024 diskPath:@"dh_nsurlcache"];
    [sharedCache removeAllCachedResponses];
    [NSURLCache setSharedURLCache:sharedCache];
    [NSURLProtocol registerClass:[DHTarixProtocol class]];
    [NSURLProtocol registerClass:[DHRemoteProtocol class]];
    [NSURLProtocol registerClass:[DHBlockProtocol class]];
    [[NSUserDefaults standardUserDefaults] registerDefaults:[NSDictionary dictionaryWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"Defaults" ofType:@"plist"]]];
    [DHDocset stepLock];
    [DHDocsetManager sharedManager];
    [DHCSS sharedCSS];
    [DHDBResultSorter sharedSorter];
    [DHDBNestedResultSorter sharedSorter];
//    self.window.tintColor = [UIColor purpleColor];
    [DHDocsetDownloader sharedDownloader];
    [DHDocsetTransferrer sharedTransferrer];
    [DHUserRepo sharedUserRepo];
    [DHCheatRepo sharedCheatRepo];
    [DHRemoteServer sharedServer];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(clipboardChanged:) name:UIPasteboardChangedNotification object:nil];
    return YES;
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    UITextField *lagFreeField = [[UITextField alloc] init];
    [self.window addSubview:lagFreeField];
    [lagFreeField becomeFirstResponder];
    [lagFreeField resignFirstResponder];
    [lagFreeField setHidden:YES];
    return YES;
}

- (BOOL)application:(UIApplication *)application openURL:(NSURL *)actualURL sourceApplication:(NSString *)sourceApplication annotation:(id)annotation
{
    if([[actualURL absoluteString] hasCaseInsensitivePrefix:@"dash://"] || [[actualURL absoluteString] hasCaseInsensitivePrefix:@"dash-plugin://"])
    {
        [[NSNotificationCenter defaultCenter] postNotificationName:DHPrepareForURLSearch object:nil];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter] postNotificationName:DHPerformURLSearch object:[actualURL absoluteString]];
        });
    }
    else
    {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            
            NSError *regexError;
            NSRegularExpression* regex = [NSRegularExpression regularExpressionWithPattern:@"Inbox/.+[\\.docset]$" options:0 error:&regexError];
            NSArray *matches;
            if (regexError) {
                NSLog(@"%@", regexError.localizedDescription);
            }else{
                matches = [regex matchesInString:[actualURL absoluteString] options:0 range:NSMakeRange(0, [actualURL absoluteString].length)];
            }
            if (matches.count) {
                [self moveInboxContentsToDocuments];
            }
        });
    }
    return YES;
}

- (UINavigationController *)navigationController
{
    if([self.window.rootViewController isKindOfClass:[UINavigationController class]])
    {
        return (UINavigationController*)self.window.rootViewController;
    }
    return self.window.rootViewController.navigationController;
}

- (void)applicationWillResignActive:(UIApplication *)application
{
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (void)applicationDidEnterBackground:(UIApplication *)application
{
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (void)applicationWillEnterForeground:(UIApplication *)application
{

}

- (void)applicationDidBecomeActive:(UIApplication *)application
{
    if(![[DHAppUpdateChecker sharedUpdateChecker] alertIfUpdatesAreScheduled])
    {
        [[DHAppUpdateChecker sharedUpdateChecker] backgroundCheckForUpdatesIfNeeded];
        if(![[DHDocsetDownloader sharedDownloader] alertIfUpdatesAreScheduled])
        {
            [[DHDocsetDownloader sharedDownloader] backgroundCheckForUpdatesIfNeeded];
            if(![[DHUserRepo sharedUserRepo] alertIfUpdatesAreScheduled])
            {
                [[DHUserRepo sharedUserRepo] backgroundCheckForUpdatesIfNeeded];
                if(![[DHCheatRepo sharedCheatRepo] alertIfUpdatesAreScheduled])
                {
                    [[DHCheatRepo sharedCheatRepo] backgroundCheckForUpdatesIfNeeded];
                }
            }
        }
    }
}

- (void)applicationWillTerminate:(UIApplication *)application
{
    // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
}

- (void)applicationDidReceiveMemoryWarning:(UIApplication *)application
{
    [[NSURLCache sharedURLCache] removeAllCachedResponses];
    NSLog(@"did receive memory warning");
}

- (void)application:(UIApplication *)application handleEventsForBackgroundURLSession:(NSString *)identifier completionHandler:(void (^)())completionHandler
{
    [[NSOperationQueue mainQueue] addOperationWithBlock:^{
        completionHandler();
    }];
}

#pragma mark - UIStateRestoration

- (BOOL)application:(UIApplication *)application shouldSaveApplicationState:(NSCoder *)coder {
    return YES;
}

- (BOOL)application:(UIApplication *)application shouldRestoreApplicationState:(NSCoder *)coder {
    return YES;
}

- (void)setDoNotBackUp
{
    NSString *path = [homePath stringByAppendingPathComponent:@"Docsets"];
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if(![fileManager fileExistsAtPath:path])
    {
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        for(NSString *key in @[@"DHDocsetDownloaderScheduledUpdate", @"DHDocsetDownloader", @"DHDocsetTransferrer", @"docsets"])
        {
            [defaults removeObjectForKey:key];
        }
        [fileManager createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:nil];
    }
    NSURL *url = [NSURL fileURLWithPath:path];
    [url setResourceValue:@YES forKey: NSURLIsExcludedFromBackupKey error:nil];
}

- (void)clipboardChanged:(NSNotification*)notification
{
    NSString *string = [UIPasteboard generalPasteboard].string;
    if(string && string.length && [DHRemoteServer sharedServer].connectedRemote)
    {
        self.clipboardChangedTimer = [self.clipboardChangedTimer invalidateTimer];
        self.clipboardChangedTimer = [NSTimer scheduledTimerWithTimeInterval:0.1 block:^{
            [[DHRemoteServer sharedServer] sendObject:@{@"string": string} forRequestName:@"syncClipboard" encrypted:YES toMacName:[DHRemoteServer sharedServer].connectedRemote.name];
        } repeats:NO];
    }
}

- (void)checkCommitHashes
{
    NSDictionary *hashes = @{@"DHDBSearcher": @"f3a251f7",
                             @"DHDBResult": @"cd091ec9",
                             @"DHDBUnifiedResult": @"b332793c",
                             @"DHQueuedDB": @"0199255c",
                             @"DHUnifiedQueuedDB": @"dd42266b",
                             @"DHDBUnifiedOperation": @"1671a905",
                             @"DHWebViewController": @"b2c622af",
                             @"DHWebPreferences": @"cd091ec9",
                             @"DHDocsetDownloader": @"20471843",
                             @"PlatformIcons": @"20471843",
                             @"DHTypes": @"fe8fc727",
                             @"Types": @"fe8fc727",
                             @"CSS": @"b32c0412",
                             };
    [hashes enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
        NSString *plistHash = [[NSBundle mainBundle] infoDictionary][[key stringByAppendingString:@"Commit"]];
        if(![plistHash isEqualToString:@"not set"] && ![plistHash isEqualToString:obj])
        {
            NSLog(@"Wrong git hash %@ for %@. Maybe you forgot to sync something or update this list?", plistHash, key);
        }
    }];
}

- (DHWindow *)window
{
    if(self._window)
    {
        return self._window;
    }
    self._window = [[DHWindow alloc] init];
    return self._window;
}

- (void)moveInboxContentsToDocuments {
    
    NSError *fileManagerError;
    
    NSString *inboxDirectory = [NSString stringWithFormat:@"%@/Inbox", transfersPath];
    NSArray *inboxContents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:inboxDirectory error:&fileManagerError];
    
    //move all the files over
    for (int i = 0; i != [inboxContents count]; i++) {
        NSString *oldPath = [NSString stringWithFormat:@"%@/%@", inboxDirectory, [inboxContents objectAtIndex:i]];
        NSString *newPath = [NSString stringWithFormat:@"%@/%@", transfersPath, [inboxContents objectAtIndex:i]];
        [[NSFileManager defaultManager] moveItemAtPath:oldPath toPath:newPath error:&fileManagerError];
        if (fileManagerError) {
            NSLog(@"%@",fileManagerError.localizedDescription);
        }
    }
}

@end
