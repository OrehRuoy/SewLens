#import <Foundation/Foundation.h>

// Reads sewlens_events.jsonl from the Godot user folder and forwards each
// line to Firebase Analytics when that SDK is linked. Crashlytics is started
// the same way. Without the pods this file still compiles and discards events.

static NSString * const kEventFileName = @"sewlens_events.jsonl";

#if __has_include(<FirebaseCore/FirebaseCore.h>)
#import <FirebaseCore/FirebaseCore.h>
#import <FirebaseAnalytics/FirebaseAnalytics.h>
#import <FirebaseCrashlytics/FirebaseCrashlytics.h>
#define SEWLENS_FIREBASE 1
#endif

static NSString *sln_find_events(void) {
	NSArray<NSString *> *roots = @[
		NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject ?: @"",
		NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES).firstObject ?: @"",
	];
	NSFileManager *files = [NSFileManager defaultManager];
	for (NSString *root in roots) {
		if (root.length == 0) continue;
		NSDirectoryEnumerator *walker = [files enumeratorAtPath:root];
		NSString *name = nil;
		while ((name = [walker nextObject])) {
			if ([name.lastPathComponent isEqualToString:kEventFileName]) {
				return [root stringByAppendingPathComponent:name];
			}
		}
	}
	return @"";
}

static void sln_log_event(NSDictionary *event) {
	NSString *name = [event[@"name"] isKindOfClass:[NSString class]] ? event[@"name"] : @"";
	NSDictionary *params = [event[@"params"] isKindOfClass:[NSDictionary class]] ? event[@"params"] : @{};
	if (name.length == 0) return;
#ifdef SEWLENS_FIREBASE
	NSMutableDictionary *clean = [NSMutableDictionary dictionary];
	[params enumerateKeysAndObjectsUsingBlock:^(id key, id obj, __unused BOOL *stop) {
		if ([obj isKindOfClass:[NSString class]] || [obj isKindOfClass:[NSNumber class]]) {
			clean[key] = obj;
		}
	}];
	[FIRAnalytics logEventWithName:name parameters:clean];
	NSString *locale = [params[@"locale"] isKindOfClass:[NSString class]] ? params[@"locale"] : @"";
	[[FIRCrashlytics crashlytics] setCustomValue:locale forKey:@"locale"];
#else
	(void)params;
#endif
}

static void sln_drain_events(void) {
	NSString *path = sln_find_events();
	if (path.length == 0) return;
	NSString *text = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
	[[NSFileManager defaultManager] removeItemAtPath:path error:nil];
	for (NSString *line in [text componentsSeparatedByString:@"\n"]) {
		if (line.length == 0) continue;
		NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];
		id obj = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
		if ([obj isKindOfClass:[NSDictionary class]]) sln_log_event(obj);
	}
}

__attribute__((constructor, used))
static void sln_firebase_boot(void) {
#ifdef SEWLENS_FIREBASE
	if ([FIRApp defaultApp] == nil) {
		[FIRApp configure];
	}
#endif
	dispatch_async(dispatch_get_main_queue(), ^{
		[NSTimer scheduledTimerWithTimeInterval:0.5 repeats:YES block:^(__unused NSTimer *timer) {
			sln_drain_events();
		}];
	});
}
