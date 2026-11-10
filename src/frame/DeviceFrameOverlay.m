#import <Cocoa/Cocoa.h>

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
    // Area bezel atas (32pt) dapat digunakan untuk men-drag jendela di layar Mac
    NSRect topBezel = NSMakeRect(0, self.bounds.size.height - 32, self.bounds.size.width, 32);
    if (NSPointInRect(point, topBezel)) {
        return self;
    }
    // Area layar tembus langsung ke scrcpy di bawahnya (mouse & touch interaktif)
    return nil;
}

- (void)mouseDown:(NSEvent *)event {
    [self.window performWindowDragWithEvent:event];
}

- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];
    
    NSRect bounds = self.bounds;
    
    // 1. Gambar Bezel Border luar halus dengan kurva sudut modern (R: 36)
    NSBezierPath *bezelPath = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(bounds, 2.0, 2.0) xRadius:36.0 yRadius:36.0];
    [[NSColor colorWithCalibratedWhite:0.12 alpha:0.95] setStroke];
    [bezelPath setLineWidth:4.0];
    [bezelPath stroke];
    
    // 2. Punch-Hole Camera di bagian tengah atas
    CGFloat camDiameter = 13.0;
    CGFloat camX = (bounds.size.width - camDiameter) / 2.0;
    CGFloat camY = bounds.size.height - camDiameter - 10.0;
    NSRect camRect = NSMakeRect(camX, camY, camDiameter, camDiameter);
    
    // Ring luar lensa kamera (aksen titanium/dark metallic)
    NSBezierPath *ringPath = [NSBezierPath bezierPathWithOvalInRect:NSInsetRect(camRect, -1.5, -1.5)];
    [[NSColor colorWithCalibratedWhite:0.22 alpha:0.95] setFill];
    [ringPath fill];
    
    // Lensa kamera depan hitam pekat
    NSBezierPath *camPath = [NSBezierPath bezierPathWithOvalInRect:camRect];
    [[NSColor blackColor] setFill];
    [camPath fill];
    
    // Titik refleksi kaca lensa (pantulan cahaya realistis)
    NSRect glintRect = NSMakeRect(camX + 3.0, camY + camDiameter - 5.5, 3.2, 3.2);
    NSBezierPath *glintPath = [NSBezierPath bezierPathWithOvalInRect:glintRect];
    [[NSColor colorWithCalibratedWhite:0.55 alpha:0.85] setFill];
    [glintPath fill];
    
    // 3. Speaker Ear-Piece Grill di tepi atas
    CGFloat speakerW = 46.0;
    CGFloat speakerH = 3.5;
    CGFloat speakerX = (bounds.size.width - speakerW) / 2.0;
    CGFloat speakerY = bounds.size.height - speakerH - 3.5;
    NSBezierPath *speakerPath = [NSBezierPath bezierPathWithRoundedRect:NSMakeRect(speakerX, speakerY, speakerW, speakerH) xRadius:1.75 yRadius:1.75];
    [[NSColor colorWithCalibratedWhite:0.25 alpha:0.95] setFill];
    [speakerPath fill];
}

@end

static void applyDeviceFrame(NSWindow *window) {
    if (!window) return;
    
    dispatch_async(dispatch_get_main_queue(), ^{
        window.titlebarAppearsTransparent = YES;
        window.titleVisibility = NSWindowTitleHidden;
        window.styleMask |= NSWindowStyleMaskFullSizeContentView;
        [window setMovableByWindowBackground:YES];
        
        NSView *contentView = window.contentView;
        if (!contentView) return;
        
        contentView.wantsLayer = YES;
        contentView.layer.cornerRadius = 36.0;
        contentView.layer.masksToBounds = YES;
        
        // Hindari penambahan ganda jika sudah ada
        for (NSView *sub in contentView.subviews) {
            if ([sub isKindOfClass:[DeviceFrameOverlayView class]]) return;
        }
        
        DeviceFrameOverlayView *overlay = [[DeviceFrameOverlayView alloc] initWithFrame:contentView.bounds];
        overlay.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        [contentView addSubview:overlay positioned:NSWindowAbove relativeTo:nil];
        
        NSLog(@"[UniversalControlFrame] Android emulator device frame & punch-hole camera applied to window: %@", window);
    });
}

static void scheduleFrameCheck(int attemptsLeft) {
    if (attemptsLeft <= 0) return;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        BOOL applied = NO;
        for (NSWindow *w in [NSApp windows]) {
            if (w.contentView != nil) {
                applyDeviceFrame(w);
                applied = YES;
            }
        }
        if (!applied) {
            scheduleFrameCheck(attemptsLeft - 1);
        }
    });
}

__attribute__((constructor))
static void initFrameObserver(void) {
    [[NSNotificationCenter defaultCenter] addObserverForName:NSWindowDidBecomeKeyNotification
                                                      object:nil
                                                       queue:[NSOperationQueue mainQueue]
                                                  usingBlock:^(NSNotification *note) {
        if ([note.object isKindOfClass:[NSWindow class]]) {
            applyDeviceFrame((NSWindow *)note.object);
        }
    }];
    
    [[NSNotificationCenter defaultCenter] addObserverForName:NSWindowDidUpdateNotification
                                                      object:nil
                                                       queue:[NSOperationQueue mainQueue]
                                                  usingBlock:^(NSNotification *note) {
        if ([note.object isKindOfClass:[NSWindow class]]) {
            applyDeviceFrame((NSWindow *)note.object);
        }
    }];
    
    scheduleFrameCheck(25);
}
