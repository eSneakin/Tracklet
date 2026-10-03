// Diagnostic only; never link this file into the app or widget.
// IconServices is private and OS-dependent. Unlike a file-existence check, this
// reproduces the gallery's identifier lookup with the current macOS icon style.
// Run: xcrun clang -fobjc-arc -framework AppKit Scripts/check-installed-icon.m \
//        -o /tmp/tracklet-check-icon && /tmp/tracklet-check-icon
#import <AppKit/AppKit.h>
#import <dlfcn.h>

@interface NSObject (TrackletIconDiagnostic)
+ (id)genericApplicationIcon;
- (id)initWithApplicationBundleIdentifier:(NSString *)identifier;
- (id)initWithBundleURL:(NSURL *)url;
- (id)initWithSize:(CGSize)size scale:(double)scale;
- (id)currentIconAppearanceConfiguration;
- (void)applyIconAppearanceConfiguration:(id)configuration;
- (void)getCGImageForImageDescriptor:(id)descriptor completion:(void (^)(CGImageRef))completion;
@end

static NSData *render(id icon, id descriptor) {
    __block NSData *pixels;
    __block BOOL finished = NO;
    [icon getCGImageForImageDescriptor:descriptor completion:^(CGImageRef image) {
        if (image) {
            NSMutableData *bitmap = [NSMutableData dataWithLength:64 * 64 * 4];
            CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
            CGContextRef context = CGBitmapContextCreate(bitmap.mutableBytes, 64, 64, 8, 64 * 4,
                                                         space, (CGBitmapInfo)kCGImageAlphaPremultipliedLast);
            if (context) {
                CGContextDrawImage(context, CGRectMake(0, 0, 64, 64), image);
                pixels = bitmap;
                CGContextRelease(context);
            }
            CGColorSpaceRelease(space);
        }
        finished = YES;
    }];
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:5];
    while (!finished && deadline.timeIntervalSinceNow > 0) {
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    }
    return pixels;
}

static double difference(NSData *a, NSData *b) {
    if (!a || !b || a.length != b.length || !a.length) return 1;
    const unsigned char *lhs = a.bytes, *rhs = b.bytes;
    double sum = 0;
    for (NSUInteger i = 0; i < a.length; i++) sum += abs(lhs[i] - rhs[i]);
    return sum / (a.length * 255);
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc > 2) { fprintf(stderr, "Usage: check-installed-icon [bundle-identifier]\n"); return 2; }
        dlopen("/System/Library/PrivateFrameworks/IconServices.framework/IconServices", RTLD_NOW);
        Class iconClass = NSClassFromString(@"ISIcon");
        Class descriptorClass = NSClassFromString(@"ISImageDescriptor");
        if (![iconClass instancesRespondToSelector:@selector(getCGImageForImageDescriptor:completion:)] ||
            ![NSWorkspace.sharedWorkspace respondsToSelector:@selector(currentIconAppearanceConfiguration)]) {
            fprintf(stderr, "Unsupported macOS diagnostic API; verify the gallery manually.\n");
            return 2;
        }

        NSString *identifier = argc > 1 ? [NSString stringWithUTF8String:argv[1]] : @"com.tracklet.app";
        if (!identifier.length) { fprintf(stderr, "Invalid bundle identifier.\n"); return 2; }
        id icon = [[iconClass alloc] initWithApplicationBundleIdentifier:identifier];
        id generic = [iconClass genericApplicationIcon];
        NSURL *url = [NSWorkspace.sharedWorkspace URLForApplicationWithBundleIdentifier:identifier];
        if (!url) { fprintf(stderr, "Tracklet is not registered.\n"); return 1; }
        id fileIcon = [[NSClassFromString(@"ISBundleIcon") alloc] initWithBundleURL:url];
        NSUInteger failures = 0;
        for (NSNumber *size in @[@16, @20, @24, @26, @28, @30, @32, @40, @48, @64]) {
            for (NSNumber *scale in @[@1, @2]) {
                for (NSNumber *useSystemStyle in @[@NO, @YES]) {
                    id descriptor = [[descriptorClass alloc]
                        initWithSize:CGSizeMake(size.doubleValue, size.doubleValue) scale:scale.doubleValue];
                    if (useSystemStyle.boolValue) {
                        [descriptor applyIconAppearanceConfiguration:[NSWorkspace.sharedWorkspace currentIconAppearanceConfiguration]];
                    }
                    NSData *actual = render(icon, descriptor);
                    NSData *placeholder = render(generic, descriptor);
                    NSData *expected = render(fileIcon, descriptor);
                    // Allow small rasterization differences, not an unrelated fallback image.
                    if (!actual || !placeholder || !expected || difference(actual, placeholder) < 0.03 ||
                        difference(actual, expected) > 0.08) {
                        fprintf(stderr, "FAIL: %gpt @%gx (%s), bundle difference %.3f.\n",
                                size.doubleValue, scale.doubleValue,
                                useSystemStyle.boolValue ? "current system style" : "default style",
                                difference(actual, expected));
                        failures++;
                    }
                }
            }
        }
        if (failures) return 1;
        printf("PASS: %s resolves a non-generic icon by identifier in both styles.\n", identifier.UTF8String);
        puts("Still confirm the Widget Gallery visually; this checks its icon-loading path, not its UI.");
        return 0;
    }
}
