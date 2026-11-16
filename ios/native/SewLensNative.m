#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <StoreKit/StoreKit.h>
#import <QuickLook/QuickLook.h>

// GDScript (scripts/autoload/native_bridge.gd) writes sewlens_native_request.json
// into the Godot user folder. This file polls for it, shows the share sheet or
// the photo picker, and writes the outcome to the "result" path in the request.
// No Godot headers, so it builds inside the exported Xcode project as-is.

static NSString * const kRequestFileName = @"sewlens_native_request.json";
static const CGFloat kMaxPhotoSide = 1600.0;
static BOOL sBusy = NO;

@interface SLNPhotoDelegate : NSObject <UIImagePickerControllerDelegate, UINavigationControllerDelegate>
@property (nonatomic, copy) NSDictionary *request;
@end

static SLNPhotoDelegate *sPhotoDelegate = nil;

static UIViewController *sln_root_vc(void) {
	UIWindow *window = nil;
	for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
		if (![scene isKindOfClass:[UIWindowScene class]]) {
			continue;
		}
		for (UIWindow *w in ((UIWindowScene *)scene).windows) {
			if (w.rootViewController == nil || w.isHidden) {
				continue;
			}
			if (w.isKeyWindow) {
				window = w;
				break;
			}
			if (window == nil) {
				window = w;
			}
		}
		if (window != nil && window.isKeyWindow) {
			break;
		}
	}
	if (window == nil) {
		return nil;
	}
	UIViewController *vc = window.rootViewController;
	while (vc.presentedViewController != nil) {
		vc = vc.presentedViewController;
	}
	return vc;
}

static NSString *sln_string(NSDictionary *dict, NSString *key) {
	id value = dict[key];
	return [value isKindOfClass:[NSString class]] ? value : @"";
}

static void sln_write_result(NSDictionary *request, NSString *status, NSString *path) {
	NSString *resultPath = sln_string(request, @"result");
	if (resultPath.length == 0) {
		return;
	}
	NSDictionary *payload = @{
		@"id": request[@"id"] ?: @0,
		@"action": sln_string(request, @"action"),
		@"status": status,
		@"path": path ?: @"",
	};
	NSData *data = [NSJSONSerialization dataWithJSONObject:payload options:0 error:nil];
	NSString *tmp = [resultPath stringByAppendingString:@".tmp"];
	[data writeToFile:tmp atomically:YES];
	[[NSFileManager defaultManager] removeItemAtPath:resultPath error:nil];
	[[NSFileManager defaultManager] moveItemAtPath:tmp toPath:resultPath error:nil];
}

static void sln_finish(NSDictionary *request, NSString *status, NSString *path) {
	sln_write_result(request, status, path);
	sPhotoDelegate = nil;
	sBusy = NO;
}

static void sln_anchor_popover(UIPopoverPresentationController *pop, UIViewController *root) {
	if (pop == nil) {
		return;
	}
	pop.sourceView = root.view;
	pop.sourceRect = CGRectMake(CGRectGetMidX(root.view.bounds), CGRectGetMidY(root.view.bounds), 1.0, 1.0);
	pop.permittedArrowDirections = 0;
}

static UIImage *sln_scaled(UIImage *image) {
	CGSize size = image.size;
	CGFloat longest = MAX(size.width, size.height);
	CGFloat scale = longest > kMaxPhotoSide ? kMaxPhotoSide / longest : 1.0;
	CGSize target = CGSizeMake(floor(size.width * scale), floor(size.height * scale));
	UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat defaultFormat];
	format.scale = 1.0;
	UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:target format:format];
	// drawInRect applies imageOrientation, so the saved JPEG is upright.
	return [renderer imageWithActions:^(__unused UIGraphicsImageRendererContext *context) {
		[image drawInRect:CGRectMake(0, 0, target.width, target.height)];
	}];
}

@implementation SLNPhotoDelegate

- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary<UIImagePickerControllerInfoKey, id> *)info {
	NSDictionary *request = self.request;
	UIImage *image = info[UIImagePickerControllerOriginalImage];
	[picker dismissViewControllerAnimated:YES completion:^{
		if (image == nil) {
			sln_finish(request, @"error", @"");
			return;
		}
		NSString *output = sln_string(request, @"output");
		dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
			NSData *jpeg = UIImageJPEGRepresentation(sln_scaled(image), 0.85);
			BOOL ok = jpeg != nil && output.length > 0 && [jpeg writeToFile:output atomically:YES];
			dispatch_async(dispatch_get_main_queue(), ^{
				sln_finish(request, ok ? @"ok" : @"error", ok ? output : @"");
			});
		});
	}];
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker {
	NSDictionary *request = self.request;
	[picker dismissViewControllerAnimated:YES completion:^{
		sln_finish(request, @"cancelled", @"");
	}];
}

@end

static void sln_present_share(NSDictionary *request) {
	UIViewController *root = sln_root_vc();
	NSString *path = sln_string(request, @"path");
	if (root == nil || ![[NSFileManager defaultManager] fileExistsAtPath:path]) {
		sln_finish(request, @"error", @"");
		return;
	}
	NSURL *url = [NSURL fileURLWithPath:path];
	UIActivityViewController *avc = [[UIActivityViewController alloc] initWithActivityItems:@[url] applicationActivities:nil];
	avc.completionWithItemsHandler = ^(__unused UIActivityType type, BOOL completed, __unused NSArray *returned, NSError *error) {
		if (error != nil) {
			sln_finish(request, @"error", @"");
		} else {
			sln_finish(request, completed ? @"ok" : @"cancelled", @"");
		}
	};
	sln_anchor_popover(avc.popoverPresentationController, root);
	[root presentViewController:avc animated:YES completion:nil];
}

static void sln_present_photo(NSDictionary *request) {
	UIViewController *root = sln_root_vc();
	if (root == nil) {
		sln_finish(request, @"error", @"");
		return;
	}
	BOOL camera = [sln_string(request, @"source") isEqualToString:@"camera"];
	UIImagePickerControllerSourceType source = camera ? UIImagePickerControllerSourceTypeCamera : UIImagePickerControllerSourceTypePhotoLibrary;
	if (![UIImagePickerController isSourceTypeAvailable:source]) {
		sln_finish(request, @"unavailable", @"");
		return;
	}
	UIImagePickerController *picker = [[UIImagePickerController alloc] init];
	picker.sourceType = source;
	sPhotoDelegate = [[SLNPhotoDelegate alloc] init];
	sPhotoDelegate.request = request;
	picker.delegate = sPhotoDelegate;
	if (!camera) {
		sln_anchor_popover(picker.popoverPresentationController, root);
	}
	[root presentViewController:picker animated:YES completion:nil];
}

@interface SLNPrintRenderer : UIPrintPageRenderer
@property (nonatomic, assign) CGPDFDocumentRef document;
@end

@implementation SLNPrintRenderer
- (NSInteger)numberOfPages {
	return self.document == NULL ? 0 : (NSInteger)CGPDFDocumentGetNumberOfPages(self.document);
}

- (CGRect)paperRect {
	CGPDFPageRef page = self.document == NULL ? NULL : CGPDFDocumentGetPage(self.document, 1);
	if (page == NULL) {
		return [super paperRect];
	}
	return CGPDFPageGetBoxRect(page, kCGPDFMediaBox);
}

- (CGRect)printableRect {
	return self.paperRect;
}

- (void)drawPageAtIndex:(NSInteger)pageIndex inRect:(CGRect)printableRect {
	CGPDFPageRef page = CGPDFDocumentGetPage(self.document, pageIndex + 1);
	if (page == NULL) {
		return;
	}
	CGRect media = CGPDFPageGetBoxRect(page, kCGPDFMediaBox);
	CGContextRef ctx = UIGraphicsGetCurrentContext();
	CGContextSaveGState(ctx);
	CGContextTranslateCTM(ctx, printableRect.origin.x, printableRect.origin.y + media.size.height);
	CGContextScaleCTM(ctx, 1.0, -1.0);
	CGContextDrawPDFPage(ctx, page);
	CGContextRestoreGState(ctx);
}
@end

static CGPDFDocumentRef sPrintDocument = NULL;
static SLNPrintRenderer *sPrintRenderer = nil;

static void sln_release_print(void) {
	sPrintRenderer = nil;
	if (sPrintDocument != NULL) {
		CGPDFDocumentRelease(sPrintDocument);
		sPrintDocument = NULL;
	}
}

static void sln_present_print(NSDictionary *request) {
	UIViewController *root = sln_root_vc();
	NSString *path = sln_string(request, @"path");
	if (root == nil || ![[NSFileManager defaultManager] fileExistsAtPath:path]) {
		sln_finish(request, @"error", @"");
		return;
	}
	sln_release_print();
	sPrintDocument = CGPDFDocumentCreateWithURL((__bridge CFURLRef)[NSURL fileURLWithPath:path]);
	if (sPrintDocument == NULL || CGPDFDocumentGetNumberOfPages(sPrintDocument) < 1) {
		sln_release_print();
		sln_finish(request, @"error", @"");
		return;
	}
	sPrintRenderer = [[SLNPrintRenderer alloc] init];
	sPrintRenderer.document = sPrintDocument;
	UIPrintInteractionController *controller = [UIPrintInteractionController sharedPrintController];
	UIPrintInfo *info = [UIPrintInfo printInfo];
	info.outputType = UIPrintInfoOutputGeneral;
	NSString *title = sln_string(request, @"title");
	info.jobName = title.length > 0 ? title : path.lastPathComponent;
	controller.printInfo = info;
	controller.printingItem = nil;
	controller.printPageRenderer = sPrintRenderer;
	void (^done)(UIPrintInteractionController *, BOOL, NSError *) = ^(UIPrintInteractionController *pic, BOOL completed, NSError *error) {
		(void)pic;
		sln_release_print();
		if (error != nil) {
			sln_finish(request, @"error", @"");
		} else if (completed) {
			sln_finish(request, @"ok", @"");
		} else {
			sln_finish(request, @"cancelled", @"");
		}
	};
	if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) {
		CGRect anchor = CGRectMake(CGRectGetMidX(root.view.bounds), CGRectGetMidY(root.view.bounds), 1.0, 1.0);
		[controller presentFromRect:anchor inView:root.view animated:YES completionHandler:done];
	} else {
		[controller presentAnimated:YES completionHandler:done];
	}
}

@interface SLNPreview : NSObject <QLPreviewControllerDataSource, QLPreviewControllerDelegate>
@property (nonatomic, copy) NSURL *url;
@property (nonatomic, copy) NSDictionary *request;
@end

static SLNPreview *sPreview = nil;

@implementation SLNPreview
- (NSInteger)numberOfPreviewItemsInPreviewController:(QLPreviewController *)controller {
	(void)controller;
	return 1;
}

- (id<QLPreviewItem>)previewController:(QLPreviewController *)controller previewItemAtIndex:(NSInteger)index {
	(void)controller;
	(void)index;
	return self.url;
}

- (void)previewControllerDidDismiss:(QLPreviewController *)controller {
	(void)controller;
	NSDictionary *request = self.request;
	sPreview = nil;
	sln_finish(request, @"ok", @"");
}
@end

static void sln_present_open(NSDictionary *request) {
	UIViewController *root = sln_root_vc();
	NSString *path = sln_string(request, @"path");
	if (root == nil || ![[NSFileManager defaultManager] fileExistsAtPath:path]) {
		sln_finish(request, @"error", @"");
		return;
	}
	sPreview = [[SLNPreview alloc] init];
	sPreview.url = [NSURL fileURLWithPath:path];
	sPreview.request = request;
	QLPreviewController *preview = [[QLPreviewController alloc] init];
	preview.dataSource = sPreview;
	preview.delegate = sPreview;
	[root presentViewController:preview animated:YES completion:nil];
}

static void sln_walk(NSString *dir, int depth, NSMutableArray<NSString *> *out) {
	if (depth < 0 || dir.length == 0) {
		return;
	}
	NSFileManager *fm = NSFileManager.defaultManager;
	for (NSString *name in [fm contentsOfDirectoryAtPath:dir error:nil]) {
		NSString *full = [dir stringByAppendingPathComponent:name];
		BOOL isDir = NO;
		if (![fm fileExistsAtPath:full isDirectory:&isDir]) {
			continue;
		}
		if (!isDir && [name isEqualToString:kRequestFileName]) {
			[out addObject:full];
		} else if (isDir && depth > 0) {
			sln_walk(full, depth - 1, out);
		}
	}
}

static NSString *sln_find_request(void) {
	NSString *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
	NSString *support = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES).firstObject;
	for (NSString *dir in @[docs ?: @"", support ?: @""]) {
		NSString *direct = [dir stringByAppendingPathComponent:kRequestFileName];
		if (dir.length > 0 && [[NSFileManager defaultManager] fileExistsAtPath:direct]) {
			return direct;
		}
	}
	NSMutableArray<NSString *> *found = [NSMutableArray array];
	sln_walk(docs, 4, found);
	if (found.count == 0) {
		sln_walk(support, 4, found);
	}
	return found.firstObject;
}

static BOOL sln_is_billing(NSString *action) {
	return [action isEqualToString:@"products"]
		|| [action isEqualToString:@"purchase"]
		|| [action isEqualToString:@"restore"]
		|| [action isEqualToString:@"finish"]
		|| [action isEqualToString:@"offer"];
}

static void sln_poll(void) {
	if (sBusy) {
		return;
	}
	NSString *path = sln_find_request();
	if (path.length == 0) {
		return;
	}
	NSData *data = [NSData dataWithContentsOfFile:path];
	id obj = data.length > 0 ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
	if (![obj isKindOfClass:[NSDictionary class]]) {
		[[NSFileManager defaultManager] removeItemAtPath:path error:nil];
		return;
	}
	NSDictionary *request = (NSDictionary *)obj;
	NSString *action = sln_string(request, @"action");
	// StoreKit 2 lives in SewLensStore.swift, which polls the same file.
	if (sln_is_billing(action)) {
		return;
	}
	[[NSFileManager defaultManager] removeItemAtPath:path error:nil];
	sBusy = YES;
	if ([action isEqualToString:@"share"]) {
		sln_present_share(request);
	} else if ([action isEqualToString:@"print"]) {
		sln_present_print(request);
	} else if ([action isEqualToString:@"open"]) {
		sln_present_open(request);
	} else if ([action isEqualToString:@"photo"]) {
		sln_present_photo(request);
	} else if ([action isEqualToString:@"review"]) {
		UIWindowScene *scene = sln_root_vc().view.window.windowScene;
		if (scene != nil) {
			[SKStoreReviewController requestReviewInScene:scene];
		}
		sln_finish(request, @"ok", @"");
	} else if ([action isEqualToString:@"crash"]) {
		sln_finish(request, @"ok", @"");
		@throw [NSException exceptionWithName:@"SewLensTestCrash" reason:@"SewLens test crash" userInfo:nil];
	} else {
		sln_finish(request, @"error", @"");
	}
}

// Defined in SewLensStore.swift. The boot call writes the marker file and the
// poll call is what keeps the StoreKit request alive on the main thread.
extern void sewlens_store_boot(void);
extern void sewlens_store_poll(void);

/// constructor+used so Xcode dead-strip cannot drop this .o (nothing else references it).
__attribute__((constructor, used))
static void sln_boot(void) {
	dispatch_async(dispatch_get_main_queue(), ^{
		sewlens_store_boot();
		[NSTimer scheduledTimerWithTimeInterval:0.2 repeats:YES block:^(__unused NSTimer *timer) {
			sewlens_store_poll();
			sln_poll();
		}];
	});
}
