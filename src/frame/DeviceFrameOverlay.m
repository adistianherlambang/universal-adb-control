#import <Cocoa/Cocoa.h>
#import <objc/runtime.h>
#import <signal.h>
#import <sys/stat.h>
#import <QuartzCore/QuartzCore.h>

// MARK: - Swizzle NSApplication to force Accessory activation policy
// Memastikan display helper TIDAK PERNAH muncul di macOS Dock atau App Switcher (Cmd+Tab)
@implementation NSApplication (UniversalControlStealth)

- (BOOL)uac_setActivationPolicy:(NSApplicationActivationPolicy)policy {
    // Selalu paksa mode Accessory (tidak ada ikon di Dock, tidak ada menu bar scrcpy)
    return [self uac_setActivationPolicy:NSApplicationActivationPolicyAccessory];
}

@end

// MARK: - Swizzle NSWindow to allow borderless window to become Key & Main window
// Memastikan keyboard dan trackpad/mouse masuk penuh ke layar Android tanpa bocor ke Mac
@implementation NSWindow (UniversalControlWindowFocus)

- (BOOL)uac_canBecomeKeyWindow {
    return YES;
}

- (BOOL)uac_canBecomeMainWindow {
    return YES;
}

- (void)uac_sendEvent:(NSEvent *)event {
    if (event.type == NSEventTypeLeftMouseDown ||
        event.type == NSEventTypeRightMouseDown ||
        event.type == NSEventTypeOtherMouseDown ||
        event.type == NSEventTypeScrollWheel) {
        if (![NSApp isActive]) {
            [NSApp activateIgnoringOtherApps:YES];
        }
        if (![self isKeyWindow]) {
            [self makeKeyAndOrderFront:nil];
        }
    }
    [self uac_sendEvent:event];
}

@end

static void swizzleActivationPolicy(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Method orig = class_getInstanceMethod([NSApplication class], @selector(setActivationPolicy:));
        Method swiz = class_getInstanceMethod([NSApplication class], @selector(uac_setActivationPolicy:));
        if (orig && swiz) {
            method_exchangeImplementations(orig, swiz);
        }
    });
}

static void swizzleWindowFocus(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Method origKey = class_getInstanceMethod([NSWindow class], @selector(canBecomeKeyWindow));
        Method swizKey = class_getInstanceMethod([NSWindow class], @selector(uac_canBecomeKeyWindow));
        if (origKey && swizKey) {
            method_exchangeImplementations(origKey, swizKey);
        }

        Method origMain = class_getInstanceMethod([NSWindow class], @selector(canBecomeMainWindow));
        Method swizMain = class_getInstanceMethod([NSWindow class], @selector(uac_canBecomeMainWindow));
        if (origMain && swizMain) {
            method_exchangeImplementations(origMain, swizMain);
        }

        Method origSend = class_getInstanceMethod([NSWindow class], @selector(sendEvent:));
        Method swizSend = class_getInstanceMethod([NSWindow class], @selector(uac_sendEvent:));
        if (origSend && swizSend) {
            method_exchangeImplementations(origSend, swizSend);
        }
    });
}

// MARK: - Lubang kamera di atas layar (mode terintegrasi)

@interface UACCameraDotView : NSView
@end

@implementation UACCameraDotView
- (NSView *)hitTest:(NSPoint)point { return nil; }
- (void)drawRect:(NSRect)dirtyRect {
    NSRect r = NSInsetRect(self.bounds, 1.0, 1.0);
    [[NSColor colorWithCalibratedWhite:0.18 alpha:1.0] setStroke];
    [[NSColor colorWithCalibratedWhite:0.02 alpha:1.0] setFill];
    NSBezierPath *p = [NSBezierPath bezierPathWithOvalInRect:r];
    [p fill];
    [p setLineWidth:1.0];
    [p stroke];
}
@end

// MARK: - Window Management (Embedded vs Standalone)

static pid_t gParentPid = 0;
static BOOL gIsEmbedded = NO;
static NSTimer *gSyncTimer = nil;

// Geometri area layar di jendela GUI (dibaca dari host_rect.json)
static CGFloat gOffsetX = 76.0;
static CGFloat gOffsetY = 92.0;
static CGFloat gWidth = 288.0;
static CGFloat gHeight = 640.0;
static CGFloat gRadius = 38.0;
static BOOL gHostHidden = NO;
static struct timespec gHostMtime = {0, 0};

static const void *kUACConfiguredKey = &kUACConfiguredKey;

static void refreshHostRect(void) {
    static NSString *path = nil;
    if (!path) path = [@"~/.universal-adb-control/host_rect.json" stringByExpandingTildeInPath];
    struct stat st;
    if (stat(path.fileSystemRepresentation, &st) != 0) return;
    if (st.st_mtimespec.tv_sec == gHostMtime.tv_sec && st.st_mtimespec.tv_nsec == gHostMtime.tv_nsec) return;
    gHostMtime = st.st_mtimespec;

    NSData *data = [NSData dataWithContentsOfFile:path];
    if (!data) return;
    NSDictionary *d = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (![d isKindOfClass:[NSDictionary class]]) return;
    if (d[@"offsetX"]) gOffsetX = [d[@"offsetX"] doubleValue];
    if (d[@"offsetY"]) gOffsetY = [d[@"offsetY"] doubleValue];
    if (d[@"width"]) gWidth = [d[@"width"] doubleValue];
    if (d[@"height"]) gHeight = [d[@"height"] doubleValue];
    if (d[@"radius"]) gRadius = [d[@"radius"] doubleValue];
    gHostHidden = [d[@"hidden"] boolValue];
}

typedef struct {
    BOOL found;
    CGRect bounds;
    CGWindowID number;
    BOOL directlyAbove; // jendela kita tepat di atas jendela GUI
} UACParentInfo;

static UACParentInfo queryParent(CGWindowID mine) {
    UACParentInfo info = {NO, CGRectZero, 0, NO};
    CFArrayRef list = CGWindowListCopyWindowInfo(kCGWindowListOptionOnScreenOnly | kCGWindowListExcludeDesktopElements, kCGNullWindowID);
    if (!list) return info;

    CFIndex count = CFArrayGetCount(list);
    CFIndex lastLayer0 = -1; // indeks jendela layer-0 sebelumnya (urutan depan ke belakang)
    CGWindowID prevNumber = 0;
    for (CFIndex i = 0; i < count; i++) {
        NSDictionary *w = (__bridge NSDictionary *)CFArrayGetValueAtIndex(list, i);
        if ([w[(id)kCGWindowLayer] intValue] != 0) continue;
        CGWindowID num = [w[(id)kCGWindowNumber] unsignedIntValue];
        pid_t pid = [w[(id)kCGWindowOwnerPID] intValue];
        if (pid == gParentPid) {
            CGRect b;
            CGRectMakeWithDictionaryRepresentation((__bridge CFDictionaryRef)w[(id)kCGWindowBounds], &b);
            // Jendela utama GUI (abaikan popover / menu kecil)
            if (b.size.width >= 300 && b.size.height >= 500) {
                info.found = YES;
                info.bounds = b;
                info.number = num;
                info.directlyAbove = (lastLayer0 >= 0 && prevNumber == mine);
                break;
            }
        }
        lastLayer0 = i;
        prevNumber = num;
    }
    CFRelease(list);
    return info;
}

static void layoutCameraDot(NSWindow *window) {
    NSView *content = window.contentView;
    if (!content) return;
    UACCameraDotView *dot = nil;
    for (NSView *sub in content.subviews) {
        if ([sub isKindOfClass:[UACCameraDotView class]]) { dot = (UACCameraDotView *)sub; break; }
    }
    if (!dot) {
        dot = [[UACCameraDotView alloc] initWithFrame:NSZeroRect];
        [content addSubview:dot positioned:NSWindowAbove relativeTo:nil];
    }
    CGFloat scale = content.bounds.size.width / 288.0;
    CGFloat d = 10.0 * scale;
    dot.frame = NSMakeRect((content.bounds.size.width - d) / 2.0,
                           content.bounds.size.height - d - 12.0 * scale, d, d);
    content.layer.cornerRadius = gRadius;
}

static void syncEmbeddedWindow(NSWindow *window) {
    // GUI sudah ditutup -> helper ikut berhenti
    if (kill(gParentPid, 0) != 0) {
        [gSyncTimer invalidate];
        gSyncTimer = nil;
        [NSApp terminate:nil];
        return;
    }

    refreshHostRect();
    UACParentInfo parent = queryParent((CGWindowID)window.windowNumber);
    BOOL visible = parent.found && !gHostHidden;

    if (visible) {
        NSScreen *primary = [NSScreen screens].firstObject;
        CGFloat screenH = primary ? primary.frame.size.height : 1080.0;
        // Koordinat CG (kiri atas) -> Cocoa (kiri bawah)
        CGFloat parentX = parent.bounds.origin.x;
        CGFloat parentY = screenH - (parent.bounds.origin.y + parent.bounds.size.height);
        NSRect target = NSMakeRect(round(parentX + gOffsetX), round(parentY + gOffsetY), round(gWidth), round(gHeight));
        if (!NSEqualRects(window.frame, target)) {
            [window setFrame:target display:NO animate:NO];
            layoutCameraDot(window);
        }

        // Urutan jendela: selalu tepat di atas GUI, tapi tidak menutupi aplikasi lain
        pid_t front = NSWorkspace.sharedWorkspace.frontmostApplication.processIdentifier;
        BOOL ours = (front == gParentPid || front == getpid());
        NSWindowLevel level = ours ? NSFloatingWindowLevel : NSNormalWindowLevel;
        if (window.level != level) window.level = level;
        if (!ours && !parent.directlyAbove) {
            [window orderWindow:NSWindowAbove relativeTo:(NSInteger)parent.number];
        }
    }

    CGFloat alpha = visible ? 1.0 : 0.0;
    if (window.alphaValue != alpha) {
        window.alphaValue = alpha;
        window.ignoresMouseEvents = !visible;
    }
}

static void applyEmbeddedMode(NSWindow *window) {
    window.styleMask = NSWindowStyleMaskBorderless;
    window.opaque = NO;
    window.backgroundColor = [NSColor clearColor];
    window.hasShadow = NO;
    window.level = NSFloatingWindowLevel;
    window.acceptsMouseMovedEvents = YES;
    window.collectionBehavior |= NSWindowCollectionBehaviorTransient | NSWindowCollectionBehaviorIgnoresCycle;

    NSView *content = window.contentView;
    if (content) {
        content.wantsLayer = YES;
        content.layer.cornerRadius = gRadius;
        content.layer.cornerCurve = kCACornerCurveContinuous;
        content.layer.masksToBounds = YES;
        content.layer.backgroundColor = [NSColor blackColor].CGColor;
    }
    layoutCameraDot(window);

    if (!gSyncTimer) {
        __weak NSWindow *weakWindow = window;
        gSyncTimer = [NSTimer timerWithTimeInterval:1.0 / 60.0 repeats:YES block:^(NSTimer *timer) {
            NSWindow *w = weakWindow;
            if (w) syncEmbeddedWindow(w);
        }];
        // Tetap berjalan saat GUI sedang di-resize / di-drag
        [[NSRunLoop mainRunLoop] addTimer:gSyncTimer forMode:NSRunLoopCommonModes];
    }
}

static void configureDisplayWindow(NSWindow *window) {
    if (!window || !window.contentView) return;
    // Konfigurasi hanya sekali per jendela (NSWindowDidUpdate dipanggil sangat sering)
    if (objc_getAssociatedObject(window, kUACConfiguredKey)) return;
    objc_setAssociatedObject(window, kUACConfiguredKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    [window setTitle:@"Universal ADB Control"];
    if (gIsEmbedded) {
        applyEmbeddedMode(window);
    } else {
        // Layar HANYA diizinkan muncul di dalam GUI Universal ADB Control
        // Jangan pernah memunculkan jendela scrcpy terpisah di luar GUI
        [window orderOut:nil];
        [NSApp terminate:nil];
        exit(0);
    }
}

static void scheduleWindowCheck(int attemptsLeft) {
    if (attemptsLeft <= 0) return;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.15 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        BOOL configured = NO;
        for (NSWindow *w in [NSApp windows]) {
            if (w.contentView != nil) {
                configureDisplayWindow(w);
                configured = YES;
            }
        }
        if (!configured) {
            scheduleWindowCheck(attemptsLeft - 1);
        }
    });
}

__attribute__((constructor))
static void initUniversalControlFrame(void) {
    swizzleActivationPolicy();
    swizzleWindowFocus();
    
    // Selalu set process name ke "Universal ADB Control"
    [[NSProcessInfo processInfo] setValue:@"Universal ADB Control" forKey:@"processName"];
    
    // Mode terintegrasi (layar menempel di dalam jendela GUI)
    const char *parentPidStr = getenv("UAC_PARENT_PID");
    if (parentPidStr && strlen(parentPidStr) > 0) {
        gParentPid = (pid_t)atoi(parentPidStr);
        gIsEmbedded = gParentPid > 0;
    }

    // Tangkap mouse down & scroll wheel agar fokus keyboard & trackpad 100% masuk ke scrcpy tanpa bocor ke Mac
    [NSEvent addLocalMonitorForEventsMatchingMask:(NSEventMaskLeftMouseDown |
                                                   NSEventMaskRightMouseDown |
                                                   NSEventMaskOtherMouseDown |
                                                   NSEventMaskScrollWheel)
                                          handler:^NSEvent * _Nullable(NSEvent * _Nonnull event) {
        if (![NSApp isActive]) {
            [NSApp activateIgnoringOtherApps:YES];
        }
        NSWindow *w = event.window;
        if (w && ![w isKeyWindow]) {
            [w makeKeyAndOrderFront:nil];
        }
        return event;
    }];

    // Intersepsi Cmd+Q dan Cmd+W saat fokus berada di dalam layar scrcpy
    [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown handler:^NSEvent * _Nullable(NSEvent * _Nonnull event) {
        NSEventModifierFlags flags = (event.modifierFlags & NSEventModifierFlagDeviceIndependentFlagsMask);
        if ((flags & NSEventModifierFlagCommand) != 0) {
            NSString *chars = [event charactersIgnoringModifiers].lowercaseString;
            if ([chars isEqualToString:@"q"]) {
                if (gParentPid > 0) {
                    kill(gParentPid, SIGTERM);
                }
                [NSApp terminate:nil];
                exit(0);
                return nil;
            }
            if ([chars isEqualToString:@"w"]) {
                if (gParentPid > 0) {
                    kill(gParentPid, SIGTERM);
                }
                [NSApp terminate:nil];
                exit(0);
                return nil;
            }
        }
        return event;
    }];
    
    [[NSNotificationCenter defaultCenter] addObserverForName:NSWindowDidBecomeKeyNotification
                                                      object:nil
                                                       queue:[NSOperationQueue mainQueue]
                                                  usingBlock:^(NSNotification *note) {
        if ([note.object isKindOfClass:[NSWindow class]]) {
            configureDisplayWindow((NSWindow *)note.object);
        }
    }];
    
    [[NSNotificationCenter defaultCenter] addObserverForName:NSWindowDidUpdateNotification
                                                      object:nil
                                                       queue:[NSOperationQueue mainQueue]
                                                  usingBlock:^(NSNotification *note) {
        if ([note.object isKindOfClass:[NSWindow class]]) {
            configureDisplayWindow((NSWindow *)note.object);
        }
    }];
    
    scheduleWindowCheck(30);
}
