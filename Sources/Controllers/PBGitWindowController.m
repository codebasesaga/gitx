//
//  PBDetailController.m
//  GitX
//
//  Created by Pieter de Bie on 16-06-08.
//  Copyright 2008 __MyCompanyName__. All rights reserved.
//

#import "PBGitWindowController.h"
#import "PBGitHistoryController.h"
#import "PBGitCommitController.h"
#import "PBTerminalUtil.h"
#import "PBCommitHookFailedSheet.h"
#import "PBGitXMessageSheet.h"
#import "PBGitSidebarController.h"
#import "PBCreateBranchSheet.h"
#import "PBCreateTagSheet.h"
#import "PBSourceViewItem.h"
#import "PBGitRevSpecifier.h"
#import "PBGitRef.h"
#import "PBError.h"
#import "PBRepositoryDocumentController.h"
#import "PBGitRepositoryDocument.h"
#import "PBRemoteProgressSheet.h"
#import "PBDiffWindowController.h"
#import "PBGitStash.h"
#import "PBGitCommit.h"

@implementation PBGitWindowController

@dynamic document;

- (instancetype)init
{
	self = [super initWithWindowNibName:@"RepositoryWindow"];
	if (!self)
		return nil;

	return self;
}

- (PBGitRepository *)repository
{
	return [self.document repository];
}

- (void)synchronizeWindowTitleWithDocumentName
{
    [super synchronizeWindowTitleWithDocumentName];

	if ([self isWindowLoaded]) {
		// Point window proxy icon at project directory, not internal .git dir
		[[self window] setRepresentedURL:self.repository.workingDirectoryURL];
	}
}

- (void)windowWillClose:(NSNotification *)notification
{
//	NSLog(@"Window will close!");

	if (sidebarController)
		[sidebarController closeView];

	[self.historyViewController closeView];
	[self.commitViewController closeView];

	if (contentController)
		[contentController removeObserver:self forKeyPath:@"status"];
}

- (BOOL)validateMenuItem:(NSMenuItem *)menuItem
{
	if ([menuItem action] == @selector(showCommitView:)) {
		[menuItem setState:(contentController == _commitViewController) ? YES : NO];
		return ![self.repository isBareRepository];
	} else if ([menuItem action] == @selector(showHistoryView:)) {
		[menuItem setState:(contentController != _commitViewController) ? YES : NO];
		return ![self.repository isBareRepository];
	} else if (menuItem.action == @selector(fetchRemote:)) {
		return [self validateMenuItem:menuItem remoteTitle:@"Fetch “%@”" plainTitle:@"Fetch"];
	} else if (menuItem.action == @selector(pullRemote:)) {
		return [self validateMenuItem:menuItem remoteTitle:@"Pull From “%@”" plainTitle:@"Pull"];
	} else if (menuItem.action == @selector(pullRebaseRemote:)) {
		return [self validateMenuItem:menuItem remoteTitle:@"Pull From “%@” and Rebase" plainTitle:@"Pull and Rebase"];
	}
	
	return YES;
}

- (BOOL) validateMenuItem:(NSMenuItem *)menuItem remoteTitle:(NSString *)localisationKeyWithRemote plainTitle:(NSString *)localizationKeyWithoutRemote
{
	PBGitRef *ref = [self selectedRef];
	if (!ref)
		return NO;

	PBGitRef *remoteRef = [self.repository remoteRefForBranch:ref error:NULL];
	if (ref.isRemote || remoteRef) {
		menuItem.title = [NSString stringWithFormat:NSLocalizedString(localisationKeyWithRemote, @""), (!remoteRef ? ref.remoteName : remoteRef.remoteName)];
		menuItem.representedObject = ref;
		return YES;
	}

	menuItem.title = NSLocalizedString(localizationKeyWithoutRemote, @"");
	return NO;
}


- (void) windowDidLoad
{
	[super windowDidLoad];

	// Explicitly set the frame using the autosave name
	// Opening the first and second documents works fine, but the third and subsequent windows aren't positioned correctly
	[[self window] setFrameUsingName:@"GitX"];
	[[self window] setRepresentedURL:self.repository.workingDirectoryURL];

	sidebarController = [[PBGitSidebarController alloc] initWithRepository:self.repository superController:self];
	_historyViewController = [[PBGitHistoryController alloc] initWithRepository:self.repository superController:self];
	_commitViewController = [[PBGitCommitController alloc] initWithRepository:self.repository superController:self];

	[[sidebarController view] setFrame:[sourceSplitView bounds]];
	[sourceSplitView addSubview:[sidebarController view]];
	[sourceListControlsView addSubview:sidebarController.sourceListControlsView];

	[[statusField cell] setBackgroundStyle:NSBackgroundStyleRaised];
	[progressIndicator setUsesThreadedAnimation:YES];
}

- (void) removeAllContentSubViews
{
	if ([contentSplitView subviews])
		while ([[contentSplitView subviews] count] > 0)
			[[[contentSplitView subviews] lastObject] removeFromSuperviewWithoutNeedingDisplay];
}

- (void) changeContentController:(PBViewController *)controller
{
	if (!controller || (contentController == controller))
		return;

	if (contentController)
		[contentController removeObserver:self forKeyPath:@"status"];

	[self removeAllContentSubViews];

	contentController = controller;
	
	[[contentController view] setFrame:[contentSplitView bounds]];
	[contentSplitView addSubview:[contentController view]];

//	[self setNextResponder: contentController];
	[[self window] makeFirstResponder:[contentController firstResponder]];
	[contentController updateView];
	[contentController addObserver:self forKeyPath:@"status" options:NSKeyValueObservingOptionInitial context:@"statusChange"];
}

- (void)showCommitView:(id)sender {
	segmentedControl.integerValue = 1;
	[sidebarController selectStage];
}

- (void)showHistoryView:(id)sender {
	segmentedControl.integerValue = 0;
	[sidebarController selectCurrentBranch];
}

- (IBAction)segmentedControlValueChanged:(NSSegmentedControl *)sender {
	if (sender.integerValue == 0) {
		[self showHistoryView:sender];
	} else {
		[self showCommitView:sender];
	}
}

- (void)showCommitHookFailedSheet:(NSString *)messageText infoText:(NSString *)infoText commitController:(PBGitCommitController *)controller
{
	[PBCommitHookFailedSheet beginWithMessageText:messageText
										 infoText:infoText
								 commitController:controller
	 completionHandler:^(id  _Nonnull sheet, NSModalResponse returnCode) {
		 if (returnCode != NSModalResponseOK) return;

		 [self->_commitViewController forceCommit:self];
	 }];
}

- (void)showMessageSheet:(NSString *)messageText infoText:(NSString *)infoText
{
	[PBGitXMessageSheet beginSheetWithMessage:messageText info:infoText windowController:self];
}

- (void)showErrorSheet:(NSError *)error
{
	if ([[error domain] isEqualToString:PBGitXErrorDomain])
	{
		[PBGitXMessageSheet beginSheetWithError:error windowController:self];
	}
	else
	{
		[[NSAlert alertWithError:error] beginSheetModalForWindow:[self window]
												   modalDelegate:self
												  didEndSelector:nil
													 contextInfo:nil];
	}
}

- (void) updateStatus
{
	NSString *status = contentController.status;
	BOOL isBusy = contentController.isBusy;

	if (!status) {
		status = @"";
		isBusy = NO;
	}

	[statusField setStringValue:status];

	if (isBusy) {
		[progressIndicator startAnimation:self];
		[progressIndicator setHidden:NO];
	}
	else {
		[progressIndicator stopAnimation:self];
		[progressIndicator setHidden:YES];
	}
}

- (void) observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    if ([(__bridge NSString *)context isEqualToString:@"statusChange"]) {
		[self updateStatus];
		return;
	}

	[super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
}

- (void)setHistorySearch:(NSString *)searchString mode:(PBHistorySearchMode)mode
{
	[_historyViewController setHistorySearch:searchString mode:mode];
}

- (void)openURLs:(NSArray <NSURL *> *)fileURLs
{
	if (fileURLs.count == 0) return;

	NSMutableArray *nonSubmoduleURLs = [NSMutableArray array];

	for (NSURL *fileURL in fileURLs) {
		GTSubmodule *submodule = [self.repository submoduleAtPath:fileURL.path error:NULL];
		if (!submodule) {
			[nonSubmoduleURLs addObject:fileURL];
		} else {
			NSURL *submoduleURL = [submodule.parentRepository.fileURL URLByAppendingPathComponent:submodule.path isDirectory:YES];
			[[NSDocumentController sharedDocumentController] openDocumentWithContentsOfURL:submoduleURL
																				   display:YES
																		 completionHandler:^(NSDocument * _Nullable document, BOOL documentWasAlreadyOpen, NSError * _Nullable error) {
																			 // Do nothing on completion.
																			 return;
																		 }];
		}
	}

	[[NSWorkspace sharedWorkspace] openURLs:nonSubmoduleURLs
					withAppBundleIdentifier:nil
									options:0
			 additionalEventParamDescriptor:nil
						  launchIdentifiers:NULL];
}

- (void)revealURLsInFinder:(NSArray <NSURL *> *)fileURLs
{
	if (fileURLs.count == 0) return;

	[[NSWorkspace sharedWorkspace] activateFileViewerSelectingURLs:fileURLs];
}

- (NSArray <NSURL *> *)selectedURLsFromSender:(id)sender {
	NSArray *selectedFiles = [sender representedObject];
	if (![selectedFiles isKindOfClass:[NSArray class]] || [selectedFiles count] == 0)
		return nil;

	NSMutableArray *URLs = [NSMutableArray array];
	for (id file in selectedFiles) {
		NSString *path = file;
		// Those can be PBChangedFiles sent by PBGitIndexController. Get their path.
		if ([file respondsToSelector:@selector(path)]) {
			path = [file path];
		}

		if (![path isKindOfClass:[NSString class]])
			continue;
		[URLs addObject:[self.repository.workingDirectoryURL URLByAppendingPathComponent:path]];
	}

	return URLs;
}

#pragma mark IBActions

- (id <PBGitRefish>)refishForSender:(id)sender refishTypes:(NSArray *)types
{
	if ([sender isKindOfClass:[NSMenuItem class]]) {
		id <PBGitRefish> refish = nil;
		if ([(refish = [(NSMenuItem *)sender representedObject]) conformsToProtocol:@protocol(PBGitRefish)]) {
			if (!types || [types indexOfObject:[refish refishType]] != NSNotFound)
				return refish;
		}
		NSString *remoteName = nil;
		if ([(remoteName = [(NSMenuItem *)sender representedObject]) isKindOfClass:[NSString class]]) {
			if ([types indexOfObject:kGitXRemoteType] != NSNotFound
				&& [self.repository.remotes indexOfObject:remoteName] != NSNotFound) {
				return [PBGitRef refFromString:[kGitXRemoteRefPrefix stringByAppendingString:remoteName]];
			}
		}

		return nil;
	}

	if ([types indexOfObject:kGitXCommitType] == NSNotFound)
		return nil;

	return _historyViewController.selectedCommits.firstObject;
}

- (PBGitRef *)selectedRef {
	id firstResponder = self.window.firstResponder;
	if (firstResponder == sidebarController.sourceView) {
		NSOutlineView *sourceView = sidebarController.sourceView;
		PBSourceViewItem *item = [sourceView itemAtRow:sourceView.selectedRow];
		PBGitRef *ref = item.ref;
		if (ref && (item.parent == sidebarController.remotes)) {
			ref = [PBGitRef refFromString:[kGitXRemoteRefPrefix stringByAppendingString:item.title]];
		}
		return ref;
	} else if (firstResponder == _historyViewController.commitList && _historyViewController.singleCommitSelected) {
		NSMutableArray *branchCommits = [NSMutableArray array];
		for (PBGitRef *ref in _historyViewController.selectedCommits.firstObject.refs) {
			if (!ref.isBranch) continue;
			[branchCommits addObject:ref];
		}
		return (branchCommits.count == 1 ? branchCommits.firstObject : nil);
	}
	return nil;
}

- (IBAction)checkout:(id)sender
{
	id <PBGitRefish> refish = [self refishForSender:sender refishTypes:@[kGitXBranchType, kGitXRemoteBranchType, kGitXCommitType, kGitXTagType]];
	if (!refish) return;

	NSError *error = nil;
	BOOL success = [self.repository checkoutRefish:refish error:&error];
	if (!success) {
		[self showErrorSheet:error];
	}
}

- (IBAction)openFiles:(id)sender {
	NSArray <NSURL *> *fileURLs = [self selectedURLsFromSender:sender];
	[self openURLs:fileURLs];
}

- (IBAction)revealInFinder:(id)sender
{
	[self revealURLsInFinder:@[self.repository.workingDirectoryURL]];
}

- (IBAction)openInTerminal:(id)sender
{
	[PBTerminalUtil runCommand:@"git status" inDirectory:self.repository.workingDirectoryURL];
}

- (IBAction)refresh:(id)sender
{
	[contentController refresh:self];
}

- (IBAction)diffWithHEAD:(id)sender
{
	id <PBGitRefish> refish = [self refishForSender:sender refishTypes:nil];
	if (!refish)
		return;

	PBGitCommit *commit = [self.repository commitForRef:refish];

	NSString *diff = [self.repository performDiff:commit against:nil forFiles:nil];

	[PBDiffWindowController showDiff:diff];
}

- (IBAction)stashViewDiff:(id)sender
{
	id <PBGitRefish> refish = [self refishForSender:sender refishTypes:@[kGitXStashType]];
	PBGitStash *stash = [self.repository stashForRef:refish];
	[PBDiffWindowController showDiffWindowWithFiles:nil fromCommit:stash.ancestorCommit diffCommit:stash.commit];
}

- (IBAction)showTagInfoSheet:(id)sender
{
	id <PBGitRefish> refish = [self refishForSender:sender refishTypes:@[kGitXTagType]];
	if (!refish)
		return;

	PBGitRef *ref = (PBGitRef *)refish;

	NSError *error = nil;
	NSString *tagName = [ref tagName];
	NSString *tagRef = [@"refs/tags/" stringByAppendingString:tagName];
	GTObject *object = [self.repository.gtRepo lookUpObjectByRevParse:tagRef error:&error];
	if (!object) {
		NSLog(@"Couldn't look up ref %@:%@", tagRef, [error debugDescription]);
		return;
	}
	NSString *title = [NSString stringWithFormat:@"Info for tag: %@", tagName];
	NSString *info = @"";
	if ([object isKindOfClass:[GTTag class]]) {
		GTTag *tag = (GTTag*)object;
		info = tag.message;
	}

	[self showMessageSheet:title infoText:info];
}

@end
