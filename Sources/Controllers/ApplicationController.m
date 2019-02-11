//
//  GitTest_AppDelegate.m
//  GitTest
//
//  Created by Pieter de Bie on 13-06-08.
//  Copyright __MyCompanyName__ 2008 . All rights reserved.
//

#import "ApplicationController.h"
#import "PBRepositoryDocumentController.h"
#import "PBGitRevisionCell.h"
#import "PBGitWindowController.h"
#import "PBServicesController.h"
#import "PBGitXProtocol.h"
#import "PBGitBinary.h"
#import "PBGitRepositoryDocument.h"
#import "PBRepositoryFinder.h"

@interface ApplicationController ()
@end

@implementation ApplicationController

- (ApplicationController*)init
{
#ifdef DEBUG_BUILD
	[NSApp activateIgnoringOtherApps:YES];
#endif

	if (!(self = [super init]))
		return nil;

	started = NO;

	return self;
}

- (void)registerServices
{
	// Register URL
	[NSURLProtocol registerClass:[PBGitXProtocol class]];

	// Register the service class
	PBServicesController *services = [[PBServicesController alloc] init];
	[NSApp setServicesProvider:services];

	// Force update the services menu if we have a new services version
	NSInteger serviceVersion = [[NSUserDefaults standardUserDefaults] integerForKey:@"Services Version"];
	if (serviceVersion < 2)
	{
		NSLog(@"Updating services menu…");
		NSUpdateDynamicServices();
		[[NSUserDefaults standardUserDefaults] setInteger:2 forKey:@"Services Version"];
	}
}

- (void)application:(NSApplication *)sender openFiles:(NSArray <NSString *> *)filenames {
	PBRepositoryDocumentController * controller = [PBRepositoryDocumentController sharedDocumentController];

	NSScriptCommand *command = [NSScriptCommand currentCommand];
	for (NSString * filename in filenames) {
		NSURL * repository = [NSURL fileURLWithPath:filename];
		[controller openDocumentWithContentsOfURL:repository display:YES completionHandler:^(NSDocument *_document, BOOL documentWasAlreadyOpen, NSError *error) {
			if (!_document) {
				NSLog(@"Error opening repository \"%@\": %@", repository.path, error);
				[controller presentError:error];
				[sender replyToOpenOrPrint:NSApplicationDelegateReplyFailure];
			} else {
				[sender replyToOpenOrPrint:NSApplicationDelegateReplySuccess];
			}

			if (command) {
				PBGitRepositoryDocument *document = (id)_document;
				NSURL *repoURL = [command directParameter];

				// on app launch there may be many repositories opening, so double check that this is the right repo
				if (repoURL) {
					repoURL = [PBRepositoryFinder gitDirForURL:repoURL];
					if ([repoURL isEqual:[document.fileURL URLByAppendingPathComponent:@".git"]]) {
						NSArray *arguments = command.arguments[@"openOptions"];
						[document handleGitXScriptingArguments:arguments];
					}
				}
			}
		}];
	}
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
	return YES;
}

- (void)applicationDidFinishLaunching:(NSNotification*)notification {
	[self registerServices];
	started = YES;
}

//Override the default behavior
- (IBAction)openDocument:(id)sender {
	NSOpenPanel* panel = [NSOpenPanel new];
	
	[panel setCanChooseFiles:false];
	[panel setCanChooseDirectories:true];
	
	[panel beginWithCompletionHandler:^(NSInteger result) {
		if (result == NSModalResponseOK) {
			PBRepositoryDocumentController* controller = [PBRepositoryDocumentController sharedDocumentController];
			[controller openDocumentWithContentsOfURL:panel.URL display:true completionHandler:^(NSDocument * _Nullable document, BOOL documentWasAlreadyOpen, NSError * _Nullable error) {
				if (!document) {
					NSLog(@"Error opening repository \"%@\": %@", panel.URL.path, error);
					[controller presentError:error];
				}
			}];
		}
	}];
}

- (IBAction)showAboutPanel:(id)sender
{
	NSString *gitversion = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleGitVersion"];
	NSMutableDictionary *dict = [[NSMutableDictionary alloc] init];
	if (gitversion)
		[dict addEntriesFromDictionary:[[NSDictionary alloc] initWithObjectsAndKeys:gitversion, @"Version", nil]];

	#ifdef DEBUG_BUILD
		[dict addEntriesFromDictionary:[[NSDictionary alloc] initWithObjectsAndKeys:@"GitX (DEBUG)", @"ApplicationName", nil]];
	#endif

	[dict addEntriesFromDictionary:[[NSDictionary alloc] initWithObjectsAndKeys:@"GitX (ft. Codebase)", @"ApplicationName", nil]];

	[NSApp orderFrontStandardAboutPanelWithOptions:dict];
}

@end
