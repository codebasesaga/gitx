//
//  NSApplication+GitXScripting.m
//  GitX
//
//  Created by Nathan Kinsinger on 8/15/10.
//  Copyright 2010 Nathan Kinsinger. All rights reserved.
//

#import "NSApplication+GitXScripting.h"
#import "GitXScriptingConstants.h"
#import "PBDiffWindowController.h"
#import "PBGitRepository.h"
#import "PBGitBinary.h"
#import "PBTask.h"


@implementation NSApplication (GitXScripting)

- (void)showDiffScriptCommand:(NSScriptCommand *)command
{
	NSString *diffText = [command directParameter];
	if (diffText) {
		PBDiffWindowController *diffController = [[PBDiffWindowController alloc] initWithDiff:diffText];
		[diffController showWindow:nil];
	}
}

- (void)performDiffScriptCommand:(NSScriptCommand *)command
{
    NSURL *repositoryURL = command.directParameter;
    NSArray *diffOptions = command.arguments[@"diffOptions"];

	diffOptions = [@[@"diff", @"--no-ext-diff"] arrayByAddingObjectsFromArray:diffOptions];

	NSError *error = nil;
	NSString *diffOutput = [PBTask outputForCommand:[PBGitBinary path] arguments:diffOptions inDirectory:repositoryURL.path error:&error];
	if (!diffOutput) {
		// if there is an error diffOutput should have the error output from git
		NSLog(@"Invalid diff command: %@", error);
        return;
	}

	PBDiffWindowController *diffController = [[PBDiffWindowController alloc] initWithDiff:diffOutput];
	[diffController showWindow:self];
}

@end
