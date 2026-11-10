#import <Cocoa/Cocoa.h>
#import <objc/runtime.h>
#import <signal.h>

// MARK: - Swizzle NSApplication to force Accessory activation policy
// Memastikan display helper TIDAK PERNAH muncul di macOS Dock atau App Switcher (Cmd+Tab)
@implementation NSApplication (UniversalControlStealth)

- (BOOL)uac_setActivationPolicy:(NSApplicationActivationPolicy)policy {
    // Selalu paksa mode Accessory (tidak ada ikon di Dock, tidak ada menu bar scrcpy)
    return [self uac_setActivationPolicy:NSApplicationActivationPolicyAccessory];
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

// MARK: - Standalone Emulator Overlay View
@interface DeviceFrameOverlayView : NSView
@end

@implementation DeviceFrameOverlayView

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.wantsLayer = YES;
    }
    return self;
}

- (NSView *)hitTest:(NSPoint)point {
    // 1. Tombol Traffic Lights (Close, Minimize, Zoom) di pojok kiri atas
    NSRect trafficLightsArea = NSMakeRect(0, self.bounds.size.height - 34, 78, 34);
    if (NSPointInRect(point, trafficLightsArea)) {
        return nil;
    }
    
    // 2. Bezel Atas untuk drag window
    NSRect topBezel = NSMakeRect(0, self.bounds.size.height - 34, self.bounds.size.width, 34);
    if (NSPointInRect(point, topBezel)) {
        return self;
    }
    
    // 3. Seluruh area layar HP tembus langsung ke scrcpy
    return nil;
}

- (void)mouseDown:(NSEvent *)event {
    [self.window performWindowDragWithEvent:event];
}

- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];
    NSRect bounds = self.bounds;
    
    // Bezel bodi ponsel halus
    NSBezierPath *bezelPath = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(bounds, 2.0, 2.0) xRadius:32.0 yRadius:32.0];
    [[NSColor colorWithCalibratedWhite:0.12 alpha:0.95] setStroke];
    [bezelPath setLineWidth:4.0];
    [bezelPath stroke];
    
    // Punch-Hole Camera
    CGFloat camDiameter = 13.0;
    CGFloat camX = (bounds.size.width - camDiameter) / 2.0;
    CGFloat camY = bounds.size.height - camDiameter - 10.0;
    NSRect camRect = NSMakeRect(camX, camY, camDiameter, camDiameter);
    
    // Ring lensa kamera
    NSBezierPath *ringPath = [NSBezierPath bezierPathWithOvalInRect:NSInsetRect(camRect, -1.5, -1.5)];
    [[NSColor colorWithCalibratedWhite:0.22 alpha:0.95] setFill];
    [ringPath fill];
    
    // Lensa hitam
    NSBezierPath *camPath = [NSBezierPath bezierPathWithOvalInRect:camRect];
    [[NSColor blackColor] setFill];
    [camPath fill];
    
    // Pantulan cahaya lensa
    NSRect glintRect = NSMakeRect(camX + 3.0, camY + camDiameter - 5.5, 3.2, 3.2);
    NSBezierPath *glintPath = [NSBezierPath bezierPathWithOvalInRect:glintRect];
    [[NSColor colorWithCalibratedWhite:0.55 alpha:0.85] setFill];
    [glintPath fill];
    
    // Speaker grill
    CGFloat speakerW = 46.0;
    CGFloat speakerH = 3.5;
    CGFloat speakerX = (bounds.size.width - speakerW) / 2.0;
    CGFloat speakerY = bounds.size.height - speakerH - 3.5;
    NSBezierPath *speakerPath = [NSBezierPath bezierPathWithRoundedRect:NSMakeRect(speakerX, speakerY, speakerW, speakerH) xRadius:1.75 yRadius:1.75];
    [[NSColor colorWithCalibratedWhite:0.25 alpha:0.95] setFill];
    [speakerPath fill];
}

@end

// MARK: - Window Management (Embedded vs Standalone)

static pid_t gParentPid = 0;
static CGFloat gOffsetX = 693.0;
static CGFloat gOffsetY = 70.0;
static CGFloat gWidth = 334.0;
static CGFloat gHeight = 530.0;
static BOOL gIsEmbedded = NO;
static NSTimer *gSyncTimer = nil;

static BOOL getParentWindowBounds(pid_t pid, CGRect *outBounds) {
    CFArrayRef list = CGWindowListCopyWindowInfo(kCGWindowListOptionOnScreenOnly | kCGWindowListExcludeDesktopElements, kCGNullWindowID);
    if (!list) return NO;
    
    BOOL found = NO;
    CFIndex count = CFArrayGetCount(list);
    for (CFIndex i = 0; i < count; i++) {
        CFDictionaryRef dict = (CFDictionaryRef)CFArrayGetValueAtIndex(list, i);
        CFNumberRef pidNum = (CFNumberRef)CFDictionaryGetValue(dict, kCGWindowOwnerPID);
        if (pidNum) {
            pid_t p = 0;
            CFNumberGetValue(pidNum, kCFNumberIntType, &p);
            if (p == pid) {
                CFDictionaryRef boundsDict = (CFDictionaryRef)CFDictionaryGetValue(dict, kCGWindowBounds);
                if (boundsDict) {
                    CGRect b;
                    CGRectMakeWithDictionaryRepresentation(boundsDict, &b);
                    // Filter: hanya ambil jendela aplikasi utama (bukan menu bar status item atau dialog kecil)
                    if (b.size.width >= 500 && b.size.height >= 400) {
                        *outBounds = b;
                        found = YES;
                        break;
                    }
                }
            }
        }
    }
    CFRelease(list);
    return found;
}

static void readHostRectFile(CGFloat *outX, CGFloat *outY, CGFloat *outW, CGFloat *outH) {
    NSString *path = [@"~/.universal-adb-control/host_rect.json" stringByExpandingTildeInPath];
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (data) {
        NSDictionary *dict = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        if ([dict isKindOfClass:[NSDictionary class]]) {
            NSNumber *x = dict[@"offsetX"];
            NSNumber *y = dict[@"offsetY"];
            NSNumber *w = dict[@"width"];
            NSNumber *h = dict[@"height"];
            if (x && y && w && h) {
                *outX = [x doubleValue];
                *outY = [y doubleValue];
                *outW = [w doubleValue];
                *outH = [h doubleValue];
            }
        }
    }
}

static void applyEmbeddedMode(NSWindow *window) {
    window.styleMask = NSWindowStyleMaskBorderless;
    window.backgroundColor = [NSColor blackColor];
    window.hasShadow = NO;
    window.level = NSFloatingWindowLevel;
    window.opaque = YES;
    
    NSView *contentView = window.contentView;
    if (contentView) {
        contentView.wantsLayer = YES;
        contentView.layer.cornerRadius = 20.0;
        contentView.layer.masksToBounds = YES;
    }
    
    // Mulai sinkronisasi posisi dengan jendela GUI utama (60 Hz)
    if (!gSyncTimer) {
        __block int missedFrames = 0;
        gSyncTimer = [NSTimer scheduledTimerWithTimeInterval:0.016 repeats:YES block:^(NSTimer * _Nonnull timer) {
            // Periksa apakah proses GUI utama masih hidup
            if (kill(gParentPid, 0) != 0) {
                [timer invalidate];
                gSyncTimer = nil;
                [NSApp terminate:nil];
                return;
            }
            
            CGRect parentCGBounds;
            if (getParentWindowBounds(gParentPid, &parentCGBounds)) {
                missedFrames = 0;
                NSScreen *primaryScreen = [NSScreen screens].firstObject;
                CGFloat screenHeight = primaryScreen ? primaryScreen.frame.size.height : 1080.0;
                
                // Konversi koordinat CG (top-left) ke Cocoa (bottom-left)
                CGFloat parentCocoaY = screenHeight - (parentCGBounds.origin.y + parentCGBounds.size.height);
                CGFloat parentCocoaX = parentCGBounds.origin.x;
                
                CGFloat offsetX = gOffsetX;
                CGFloat offsetY = gOffsetY;
                CGFloat width = gWidth;
                CGFloat height = gHeight;
                readHostRectFile(&offsetX, &offsetY, &width, &height);
                
                CGFloat targetX = parentCocoaX + offsetX;
                CGFloat targetY = parentCocoaY + offsetY;
                
                NSRect currentFrame = window.frame;
                NSRect targetFrame = NSMakeRect(targetX, targetY, width, height);
                
                if (fabs(currentFrame.origin.x - targetFrame.origin.x) > 0.5 ||
                    fabs(currentFrame.origin.y - targetFrame.origin.y) > 0.5 ||
                    fabs(currentFrame.size.width - targetFrame.size.width) > 0.5 ||
                    fabs(currentFrame.size.height - targetFrame.size.height) > 0.5) {
                    [window setFrame:targetFrame display:NO animate:NO];
                }
                
                if (window.alphaValue < 1.0) {
                    window.alphaValue = 1.0;
                }
            } else {
                missedFrames++;
                if (missedFrames > 60 && window.alphaValue > 0.0) {
                    window.alphaValue = 0.0;
                }
            }
        }];
    }
}

static void applyStandaloneMode(NSWindow *window) {
    window.styleMask |= (NSWindowStyleMaskTitled |
                         NSWindowStyleMaskClosable |
                         NSWindowStyleMaskMiniaturizable |
                         NSWindowStyleMaskResizable |
                         NSWindowStyleMaskFullSizeContentView);
    
    window.titlebarAppearsTransparent = YES;
    window.titleVisibility = NSWindowTitleHidden;
    [window setMovableByWindowBackground:YES];
    
    NSButton *closeBtn = [window standardWindowButton:NSWindowCloseButton];
    NSButton *minBtn = [window standardWindowButton:NSWindowMiniaturizeButton];
    NSButton *zoomBtn = [window standardWindowButton:NSWindowZoomButton];
    
    [closeBtn setHidden:NO];
    [minBtn setHidden:NO];
    [zoomBtn setHidden:NO];
    
    NSView *contentView = window.contentView;
    if (!contentView) return;
    
    contentView.wantsLayer = YES;
    contentView.layer.cornerRadius = 32.0;
    contentView.layer.masksToBounds = YES;
    
    for (NSView *sub in contentView.subviews) {
        if ([sub isKindOfClass:[DeviceFrameOverlayView class]]) return;
    }
    
    DeviceFrameOverlayView *overlay = [[DeviceFrameOverlayView alloc] initWithFrame:contentView.bounds];
    overlay.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [contentView addSubview:overlay positioned:NSWindowAbove relativeTo:nil];
    
    if (closeBtn) [closeBtn.superview addSubview:closeBtn positioned:NSWindowAbove relativeTo:nil];
    if (minBtn) [minBtn.superview addSubview:minBtn positioned:NSWindowAbove relativeTo:nil];
    if (zoomBtn) [zoomBtn.superview addSubview:zoomBtn positioned:NSWindowAbove relativeTo:nil];
}

static void configureDisplayWindow(NSWindow *window) {
    if (!window) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        [window setTitle:@"Universal ADB Control"];
        if (gIsEmbedded) {
            applyEmbeddedMode(window);
        } else {
            applyStandaloneMode(window);
        }
    });
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
    
    // Selalu set process name ke "Universal ADB Control"
    [[NSProcessInfo processInfo] setValue:@"Universal ADB Control" forKey:@"processName"];
    
    // Periksa apakah berjalan dalam mode terintegrasi (Embedded dalam GUI)
    const char *parentPidStr = getenv("UAC_PARENT_PID");
    if (parentPidStr && strlen(parentPidStr) > 0) {
        gParentPid = (pid_t)atoi(parentPidStr);
        if (gParentPid > 0) {
            gIsEmbedded = YES;
            
            const char *offXStr = getenv("UAC_OFFSET_X");
            if (offXStr) gOffsetX = (CGFloat)atof(offXStr);
            
            const char *offYStr = getenv("UAC_OFFSET_Y");
            if (offYStr) gOffsetY = (CGFloat)atof(offYStr);
            
            const char *wStr = getenv("UAC_WIDTH");
            if (wStr) gWidth = (CGFloat)atof(wStr);
            
            const char *hStr = getenv("UAC_HEIGHT");
            if (hStr) gHeight = (CGFloat)atof(hStr);
        }
    }
    
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
