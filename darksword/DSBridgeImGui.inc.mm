// DSBridgeImGui.inc.mm
// Hardware-accelerated Metal + Dear ImGui Overlay for DarkPubg.
// 120 FPS continuous background GPU rendering, automatic landscape orientation,
// full Vietnamese font support with diacritics, and 100% pass-through touch.

#import <Metal/Metal.h>
#import <MetalKit/MetalKit.h>
#import <UIKit/UIKit.h>
#import <CoreText/CoreText.h>

#import "BackboardServices.h"
#import "AXEventRepresentation.h"

#define IMGUI_DEFINE_MATH_OPERATORS
#include "../imgui/imgui.h"
#include "../imgui/imgui_internal.h"
#include "../imgui/imgui_impl_metal.h"

// Compile ImGui Unity source bundle directly into this translation unit
#include "../imgui/imgui.cpp"
#include "../imgui/imgui_draw.cpp"
#include "../imgui/imgui_tables.cpp"
#include "../imgui/imgui_widgets.cpp"
#include "../imgui/imgui_impl_metal.mm"

#pragma mark - Settings & State

struct DSPUBGImGuiSettings {
    bool espEnabled = true;
    bool drawBox = true;
    int boxType = 0; // 0 = Corner, 1 = Full
    bool drawSkeleton = true;
    bool drawLine = true;
    int lineOrigin = 0; // 0 = Top, 1 = Center, 2 = Bottom
    bool drawHealth = true;
    bool drawName = true;
    bool drawDistance = true;
    bool drawTeamId = true;
    bool drawBot = true;
    bool drawWeapon = true;

    // Grenade
    bool drawGrenade = true;
    bool drawGrenadeLine = true;
    bool drawGrenadeCircle = true;
    bool drawGrenadeTimer = true;

    // Items & Vehicles
    bool drawItems = true;
    bool drawVehicles = true;
    float itemMaxDist = 120.0f;
    float playerMaxDist = 400.0f;

    // Style
    float strokeThickness = 1.5f;
    float fontSize = 14.0f;
};

static DSPUBGImGuiSettings g_imguiSettings;
static bool g_imguiMenuOpen = false;
static ImVec2 g_floatingButtonPos = ImVec2(70.0f, 100.0f);
static CGRect g_floatingButtonRect = CGRectMake(46.0, 76.0, 48.0, 48.0);
static CGRect g_imguiMenuRect = CGRectZero;

static bool g_isDraggingButtonGlobal = false;
static CGPoint g_globalTouchStart = CGPointZero;
static CFAbsoluteTime g_globalTouchStartTime = 0;
static bool g_isInteractingWithMenuGlobal = false;
static bool g_imguiHIDRegistered = false;
static unsigned g_imguiContextId = 0;
static bool g_imguiInited = false;
static int g_imguiLastOrientation = -1;

@interface DSImGuiView : MTKView <MTKViewDelegate>
- (void)updateOrientationIfNeeded;
@end

@interface DSImGuiWindow : UIWindow
@end

static DSImGuiView *g_imguiView = nil;
static DSImGuiWindow *g_imguiWindow = nil;
static id<MTLCommandQueue> g_imguiCommandQueue = nil;

#pragma mark - Forward Declarations

static void ds_imgui_render_pubg_esp(ImDrawList *draw, CGSize screenSize);
static void ds_imgui_render_floating_button(ImDrawList *draw);
static void ds_imgui_render_menu(void);
static void ds_imgui_handle_global_touch(CGPoint screenPt, UITouchPhase phase);
static void ds_imgui_hid_callback(void *target, void *refcon, IOHIDServiceRef service, IOHIDEventRef event);

#pragma mark - Window with 100% Touch Pass-through

@implementation DSImGuiWindow
+ (BOOL)_isSystemWindow { return YES; }
- (BOOL)_isWindowServerHostingManaged { return NO; }
- (BOOL)_ignoresHitTest { return YES; } // 100% touches pass through to PUBG Mobile
- (BOOL)_isSecure { return YES; }
- (BOOL)_shouldCreateContextAsSecure { return YES; }
- (BOOL)keepContextInBackground { return YES; }
@end

#pragma mark - Metal View & Delegate

@implementation DSImGuiView

- (instancetype)initWithFrame:(CGRect)frame device:(id<MTLDevice>)device {
    self = [super initWithFrame:frame device:device];
    if (self) {
        self.delegate = self;
        self.paused = NO; // DO NOT pause; lets MTKView continuously request drawables
        self.enableSetNeedsDisplay = NO;
        self.framebufferOnly = NO;
        self.opaque = NO;
        self.userInteractionEnabled = NO;
        self.clearColor = MTLClearColorMake(0.0, 0.0, 0.0, 0.0);
        self.backgroundColor = [UIColor clearColor];
        self.colorPixelFormat = MTLPixelFormatBGRA8Unorm;
        self.sampleCount = 1;
        self.preferredFramesPerSecond = 120;

        g_imguiCommandQueue = [device newCommandQueue];
        [self setupImGuiWithDevice:device];
    }
    return self;
}

- (void)setupImGuiWithDevice:(id<MTLDevice>)device {
    if (g_imguiInited) return;

    IMGUI_CHECKVERSION();
    ImGui::CreateContext();
    ImGuiIO &io = ImGui::GetIO();
    io.IniFilename = NULL;
    io.LogFilename = NULL;
    io.BackendFlags |= ImGuiBackendFlags_RendererHasVtxOffset;

    // Load Vietnamese system font (Arial / Helvetica) with full glyphs
    NSString *fontPath = nil;
    UIFont *sysFont = [UIFont systemFontOfSize:15.0];
    if (sysFont) {
        CTFontRef ctFont = (__bridge CTFontRef)sysFont;
        CFURLRef fontURL = (CFURLRef)CTFontCopyAttribute(ctFont, kCTFontURLAttribute);
        if (fontURL) {
            fontPath = [(__bridge NSURL *)fontURL path];
            CFRelease(fontURL);
        }
    }
    if (!fontPath || ![[NSFileManager defaultManager] fileExistsAtPath:fontPath]) {
        NSArray *candidates = @[
            @"/System/Library/Fonts/CoreAddition/ArialBold.ttf",
            @"/System/Library/Fonts/CoreAddition/Arial.ttf",
            @"/System/Library/Fonts/Core/Arial.ttf",
            @"/System/Library/Fonts/Core/Helvetica.ttc",
            @"/System/Library/Fonts/Cache/Arial.ttf",
            @"/System/Library/Fonts/LanguageSupport/PingFang.ttc"
        ];
        for (NSString *c in candidates) {
            if ([[NSFileManager defaultManager] fileExistsAtPath:c]) {
                fontPath = c;
                break;
            }
        }
    }

    if (fontPath && [[NSFileManager defaultManager] fileExistsAtPath:fontPath]) {
        ImFontConfig cfg;
        cfg.SizePixels = 15.0f;
        cfg.OversampleH = 2;
        cfg.OversampleV = 2;
        io.Fonts->AddFontFromFileTTF([fontPath UTF8String], 15.0f, &cfg, io.Fonts->GetGlyphRangesVietnamese());
    } else {
        io.Fonts->AddFontDefault();
    }

    // Modern dark styling
    ImGui::StyleColorsDark();
    ImGuiStyle &style = ImGui::GetStyle();
    style.WindowRounding = 8.0f;
    style.FrameRounding = 5.0f;
    style.GrabRounding = 4.0f;
    style.PopupRounding = 6.0f;
    style.ScrollbarRounding = 6.0f;
    style.WindowBorderSize = 1.0f;
    style.FrameBorderSize = 0.5f;
    style.Colors[ImGuiCol_WindowBg] = ImVec4(0.08f, 0.08f, 0.10f, 0.94f);
    style.Colors[ImGuiCol_Border] = ImVec4(0.35f, 0.35f, 0.40f, 0.60f);
    style.Colors[ImGuiCol_Header] = ImVec4(0.20f, 0.50f, 0.85f, 0.55f);
    style.Colors[ImGuiCol_HeaderHovered] = ImVec4(0.25f, 0.55f, 0.90f, 0.80f);
    style.Colors[ImGuiCol_HeaderActive] = ImVec4(0.30f, 0.60f, 0.95f, 1.00f);
    style.Colors[ImGuiCol_Button] = ImVec4(0.20f, 0.50f, 0.85f, 0.60f);
    style.Colors[ImGuiCol_ButtonHovered] = ImVec4(0.25f, 0.55f, 0.90f, 0.85f);
    style.Colors[ImGuiCol_ButtonActive] = ImVec4(0.30f, 0.60f, 0.95f, 1.00f);
    style.Colors[ImGuiCol_CheckMark] = ImVec4(0.30f, 0.85f, 0.35f, 1.00f);
    style.Colors[ImGuiCol_SliderGrab] = ImVec4(0.25f, 0.60f, 0.95f, 0.85f);
    style.Colors[ImGuiCol_SliderGrabActive] = ImVec4(0.35f, 0.70f, 1.00f, 1.00f);

    ImGui_ImplMetal_Init(device);
    g_imguiInited = true;
}

- (void)updateOrientationIfNeeded {
    UIInterfaceOrientation orientation = (UIInterfaceOrientation)g_activeOrientation.load();
    if (!UIInterfaceOrientationIsLandscape(orientation)) {
        orientation = UIInterfaceOrientationLandscapeRight;
    }
    if ((int)orientation == g_imguiLastOrientation && g_imguiWindow) return;
    g_imguiLastOrientation = (int)orientation;

    CGRect screenBounds = UIScreen.mainScreen.bounds;
    CGFloat landW = MAX(screenBounds.size.width, screenBounds.size.height);
    CGFloat landH = MIN(screenBounds.size.width, screenBounds.size.height);
    CGRect landscapeBounds = CGRectMake(0, 0, landW, landH);

    [CATransaction begin];
    [CATransaction setDisableActions:YES];

    if (g_imguiWindow) {
        g_imguiWindow.bounds = landscapeBounds;
        g_imguiWindow.center = CGPointMake(CGRectGetMidX(screenBounds), CGRectGetMidY(screenBounds));

        SEL setOrientSel = NSSelectorFromString(@"_setInterfaceOrientation:");
        if ([g_imguiWindow respondsToSelector:setOrientSel]) {
            NSMethodSignature *sig = [g_imguiWindow methodSignatureForSelector:setOrientSel];
            if (sig) {
                NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
                [inv setSelector:setOrientSel];
                [inv setTarget:g_imguiWindow];
                NSInteger orientVal = (NSInteger)orientation;
                [inv setArgument:&orientVal atIndex:2];
                [inv invoke];
            }
        }

        CGAffineTransform rot = (orientation == UIInterfaceOrientationLandscapeLeft) ? CGAffineTransformMakeRotation(-M_PI_2) : CGAffineTransformMakeRotation(M_PI_2);
        g_imguiWindow.transform = rot;
        g_imguiWindow.frame = screenBounds;
    }

    self.frame = landscapeBounds;
    [CATransaction commit];

    ImGuiIO &io = ImGui::GetIO();
    io.DisplaySize = ImVec2(landW, landH);
}

- (void)mtkView:(MTKView *)view drawableSizeWillChange:(CGSize)size {
}

- (void)drawInMTKView:(MTKView *)view {
    if (!g_imguiInited) return;

    [self updateOrientationIfNeeded];

    id<CAMetalDrawable> drawable = view.currentDrawable;
    MTLRenderPassDescriptor *rpd = view.currentRenderPassDescriptor;
    if (!drawable || !rpd) return;

    ImGuiIO &io = ImGui::GetIO();
    io.DisplaySize = ImVec2(view.bounds.size.width, view.bounds.size.height);
    io.DeltaTime = 1.0f / 120.0f;

    id<MTLCommandBuffer> cb = [g_imguiCommandQueue commandBuffer];
    id<MTLRenderCommandEncoder> enc = [cb renderCommandEncoderWithDescriptor:rpd];

    ImGui_ImplMetal_NewFrame(rpd);
    ImGui::NewFrame();

    ImDrawList *draw = ImGui::GetBackgroundDrawList();

    // 1. Draw PUBG ESP
    ds_imgui_render_pubg_esp(draw, view.bounds.size);

    // 2. Draw Floating Button
    ds_imgui_render_floating_button(draw);

    // 3. Draw ImGui Menu if opened
    if (g_imguiMenuOpen) {
        ds_imgui_render_menu();
    }

    ImGui::Render();
    ImGui_ImplMetal_RenderDrawData(ImGui::GetDrawData(), cb, enc);
    [enc endEncoding];
    [cb presentDrawable:drawable];
    [cb commit];
}

@end

#pragma mark - Global HID Touch Handling

static void ds_imgui_handle_global_touch(CGPoint screenPt, UITouchPhase phase) {
    if (!g_imguiView || !g_imguiWindow || g_imguiWindow.hidden) return;

    UIInterfaceOrientation orient = (UIInterfaceOrientation)g_activeOrientation.load();
    if (!UIInterfaceOrientationIsLandscape(orient)) {
        orient = UIInterfaceOrientationLandscapeRight;
    }

    CGRect bounds = UIScreen.mainScreen.bounds;
    CGFloat sw = MIN(bounds.size.width, bounds.size.height);
    CGFloat sh = MAX(bounds.size.width, bounds.size.height);

    CGPoint viewPt;
    if (orient == UIInterfaceOrientationLandscapeLeft) {
        viewPt = CGPointMake(sh - screenPt.y, screenPt.x);
    } else {
        viewPt = CGPointMake(screenPt.y, sw - screenPt.x);
    }

    ImGuiIO &io = ImGui::GetIO();

    if (phase == UITouchPhaseBegan) {
        g_globalTouchStart = viewPt;
        g_globalTouchStartTime = CFAbsoluteTimeGetCurrent();

        // 1. Check if tap lands on Floating Button D3S (32px radius tolerance)
        float dx = viewPt.x - g_floatingButtonPos.x;
        float dy = viewPt.y - g_floatingButtonPos.y;
        if (dx * dx + dy * dy <= 34.0f * 34.0f) {
            g_isDraggingButtonGlobal = true;
            return;
        }

        // 2. If menu is open, check if touch is inside menu window
        if (g_imguiMenuOpen && !CGRectIsEmpty(g_imguiMenuRect) && CGRectContainsPoint(g_imguiMenuRect, viewPt)) {
            g_isInteractingWithMenuGlobal = true;
            io.AddMousePosEvent(viewPt.x, viewPt.y);
            io.AddMouseButtonEvent(0, true);
            return;
        }

        g_isInteractingWithMenuGlobal = false;
        g_isDraggingButtonGlobal = false;

    } else if (phase == UITouchPhaseMoved) {
        if (g_isDraggingButtonGlobal) {
            float ddx = viewPt.x - g_globalTouchStart.x;
            float ddy = viewPt.y - g_globalTouchStart.y;
            if (ddx * ddx + ddy * ddy > 16.0f) {
                g_floatingButtonPos = ImVec2(viewPt.x, viewPt.y);
                if (g_floatingButtonPos.x < 30.0f) g_floatingButtonPos.x = 30.0f;
                if (g_floatingButtonPos.x > sh - 30.0f) g_floatingButtonPos.x = sh - 30.0f;
                if (g_floatingButtonPos.y < 30.0f) g_floatingButtonPos.y = 30.0f;
                if (g_floatingButtonPos.y > sw - 30.0f) g_floatingButtonPos.y = sw - 30.0f;
                g_floatingButtonRect = CGRectMake(g_floatingButtonPos.x - 24.0, g_floatingButtonPos.y - 24.0, 48.0, 48.0);
            }
            return;
        }

        if (g_isInteractingWithMenuGlobal) {
            io.AddMousePosEvent(viewPt.x, viewPt.y);
            return;
        }

    } else if (phase == UITouchPhaseEnded || phase == UITouchPhaseCancelled) {
        if (g_isDraggingButtonGlobal) {
            float ddx = viewPt.x - g_globalTouchStart.x;
            float ddy = viewPt.y - g_globalTouchStart.y;
            if (ddx * ddx + ddy * ddy < 36.0f && (CFAbsoluteTimeGetCurrent() - g_globalTouchStartTime) < 0.8) {
                g_imguiMenuOpen = !g_imguiMenuOpen; // Toggle menu!
            }
            g_isDraggingButtonGlobal = false;
            return;
        }

        if (g_isInteractingWithMenuGlobal) {
            io.AddMousePosEvent(viewPt.x, viewPt.y);
            io.AddMouseButtonEvent(0, false);
            g_isInteractingWithMenuGlobal = false;
            return;
        }
    }
}

static void ds_imgui_hid_callback(void *target, void *refcon, IOHIDServiceRef service, IOHIDEventRef event) {
    static Class AXEventRepresentationCls = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        [[NSBundle bundleWithPath:@"/System/Library/PrivateFrameworks/AccessibilityUtilities.framework"] load];
        AXEventRepresentationCls = objc_getClass("AXEventRepresentation");
    });
    if (!AXEventRepresentationCls) return;

    AXEventRepresentation *rep = [AXEventRepresentationCls representationWithHIDEvent:event hidStreamIdentifier:@"UIApplicationEvents"];
    if (!rep) return;

    CGPoint loc = [rep location];
    UITouchPhase phase = UITouchPhaseEnded;
    if ([rep isTouchDown])
        phase = UITouchPhaseBegan;
    else if ([rep isMove])
        phase = UITouchPhaseMoved;
    else if ([rep isCancel])
        phase = UITouchPhaseCancelled;
    else if ([rep isLift] || [rep isInRange] || [rep isInRangeLift])
        phase = UITouchPhaseEnded;

    dispatch_async(dispatch_get_main_queue(), ^{
        ds_imgui_handle_global_touch(loc, phase);
    });
}

#pragma mark - Helper Drawing Functions

static inline void Circle3D(ImDrawList *draw, const CGPoint points[32], const bool valids[32], ImU32 col, float thickness) {
    for (int i = 0; i < 31; ++i) {
        if (valids[i] && valids[i + 1]) {
            draw->AddLine(ImVec2(points[i].x, points[i].y),
                          ImVec2(points[i + 1].x, points[i + 1].y), col, thickness);
        }
    }
    if (valids[31] && valids[0]) {
        draw->AddLine(ImVec2(points[31].x, points[31].y),
                      ImVec2(points[0].x, points[0].y), col, thickness);
    }
}

#pragma mark - ESP Render Logic

static void ds_imgui_render_pubg_esp(ImDrawList *draw, CGSize screenSize) {
    if (!g_imguiSettings.espEnabled) return;

    DSPUBGProjectedPlayer localPlayers[kDSPUBGMaxPlayers];
    int localPlayerCount = 0;
    int totalEnemies = 0;
    int totalBots = 0;

    DSPUBGProjectedGrenade localGrenades[kDSPUBGMaxGrenades];
    int localGrenadeCount = 0;

    DSPUBGProjectedItem localItems[kDSPUBGMaxItems];
    int localItemCount = 0;

    os_unfair_lock_lock(&g_dspubgSnapshotLock);
    localPlayerCount = g_dspubgPlayerCount > kDSPUBGMaxPlayers ? kDSPUBGMaxPlayers : g_dspubgPlayerCount;
    if (localPlayerCount > 0) {
        memcpy(localPlayers, g_dspubgPlayers, localPlayerCount * sizeof(DSPUBGProjectedPlayer));
    }
    totalEnemies = g_dspubgTotal360EnemyCount;
    totalBots = g_dspubgTotal360BotCount;

    localGrenadeCount = g_dspubgGrenadeCount > kDSPUBGMaxGrenades ? kDSPUBGMaxGrenades : g_dspubgGrenadeCount;
    if (localGrenadeCount > 0) {
        memcpy(localGrenades, g_dspubgGrenades, localGrenadeCount * sizeof(DSPUBGProjectedGrenade));
    }

    localItemCount = g_dspubgItemCount > kDSPUBGMaxItems ? kDSPUBGMaxItems : g_dspubgItemCount;
    if (localItemCount > 0) {
        memcpy(localItems, g_dspubgItems, localItemCount * sizeof(DSPUBGProjectedItem));
    }
    os_unfair_lock_unlock(&g_dspubgSnapshotLock);

    // 1. 360 Alert / Enemy Count Top Banner
    {
        char alertBuf[64];
        snprintf(alertBuf, sizeof(alertBuf), "Enemies: %d | Bots: %d", totalEnemies, totalBots);
        ImVec2 txtSz = ImGui::CalcTextSize(alertBuf);
        ImVec2 alertPos = ImVec2((screenSize.width - txtSz.x) * 0.5f, 26.0f);
        draw->AddRectFilled(ImVec2(alertPos.x - 12, alertPos.y - 4),
                            ImVec2(alertPos.x + txtSz.x + 12, alertPos.y + txtSz.y + 4),
                            IM_COL32(0, 0, 0, 160), 6.0f);
        ImU32 colBorder = (totalEnemies > 0) ? IM_COL32(255, 60, 60, 220) : IM_COL32(60, 220, 60, 220);
        draw->AddRect(ImVec2(alertPos.x - 12, alertPos.y - 4),
                      ImVec2(alertPos.x + txtSz.x + 12, alertPos.y + txtSz.y + 4),
                      colBorder, 6.0f, 0, 1.5f);
        draw->AddText(alertPos, IM_COL32(255, 255, 255, 255), alertBuf);
    }

    // 2. Player ESP
    for (int p = 0; p < localPlayerCount; p++) {
        const DSPUBGProjectedPlayer &pl = localPlayers[p];
        if (pl.isDead || pl.distanceMeters > g_imguiSettings.playerMaxDist) continue;
        if (pl.isAI && !g_imguiSettings.drawBot) continue;

        ImU32 colBox = pl.isAI ? IM_COL32(60, 230, 60, 255) :
                       (pl.isKnocked ? IM_COL32(255, 160, 20, 255) : IM_COL32(255, 50, 50, 255));
        if (pl.isVisible) {
            colBox = IM_COL32(255, 230, 0, 255);
        }

        float bx = pl.screenX - pl.boxWidth * 0.5f;
        float by = pl.screenY - pl.boxHeight;
        float bw = pl.boxWidth;
        float bh = pl.boxHeight;

        // Box 2D
        if (g_imguiSettings.drawBox) {
            float thick = g_imguiSettings.strokeThickness;
            if (g_imguiSettings.boxType == 0) {
                // Corner Box
                float lineW = bw * 0.25f;
                float lineH = bh * 0.20f;
                draw->AddLine(ImVec2(bx, by), ImVec2(bx + lineW, by), colBox, thick);
                draw->AddLine(ImVec2(bx, by), ImVec2(bx, by + lineH), colBox, thick);
                draw->AddLine(ImVec2(bx + bw, by), ImVec2(bx + bw - lineW, by), colBox, thick);
                draw->AddLine(ImVec2(bx + bw, by), ImVec2(bx + bw, by + lineH), colBox, thick);
                draw->AddLine(ImVec2(bx, by + bh), ImVec2(bx + lineW, by + bh), colBox, thick);
                draw->AddLine(ImVec2(bx, by + bh), ImVec2(bx, by + bh - lineH), colBox, thick);
                draw->AddLine(ImVec2(bx + bw, by + bh), ImVec2(bx + bw - lineW, by + bh), colBox, thick);
                draw->AddLine(ImVec2(bx + bw, by + bh), ImVec2(bx + bw, by + bh - lineH), colBox, thick);
            } else {
                // Full Box with drop-shadow
                draw->AddRect(ImVec2(bx - 1, by - 1), ImVec2(bx + bw + 1, by + bh + 1), IM_COL32(0, 0, 0, 180), 0, 0, thick + 1.0f);
                draw->AddRect(ImVec2(bx, by), ImVec2(bx + bw, by + bh), colBox, 0, 0, thick);
            }
        }

        // Skeleton
        if (g_imguiSettings.drawSkeleton && pl.hasSkeleton) {
            static const int bonePairs[][2] = {
                {0, 1}, {1, 2}, {2, 3},
                {2, 4}, {4, 5}, {5, 6},
                {2, 7}, {7, 8}, {8, 9},
                {3, 10}, {10, 11}, {11, 12},
                {3, 13}, {13, 14}, {14, 15}
            };
            ImU32 colSkel = IM_COL32(255, 255, 255, 210);
            float thick = g_imguiSettings.strokeThickness;
            for (size_t b = 0; b < sizeof(bonePairs) / sizeof(bonePairs[0]); b++) {
                int i1 = bonePairs[b][0];
                int i2 = bonePairs[b][1];
                if (pl.skeleton[i1].valid && pl.skeleton[i2].valid) {
                    draw->AddLine(ImVec2(pl.skeleton[i1].x, pl.skeleton[i1].y),
                                  ImVec2(pl.skeleton[i2].x, pl.skeleton[i2].y), colSkel, thick);
                }
            }
            if (pl.skeleton[0].valid && pl.skeleton[1].valid) {
                float headRadius = fabsf(pl.skeleton[1].y - pl.skeleton[0].y) * 0.9f;
                if (headRadius < 3.0f) headRadius = 3.0f;
                if (headRadius > 16.0f) headRadius = 16.0f;
                draw->AddCircle(ImVec2(pl.skeleton[0].x, pl.skeleton[0].y), headRadius, colSkel, 16, thick);
            }
        }

        // Snapline
        if (g_imguiSettings.drawLine) {
            ImVec2 startPt = (g_imguiSettings.lineOrigin == 0) ? ImVec2(screenSize.width * 0.5f, 0.0f) :
                             (g_imguiSettings.lineOrigin == 1) ? ImVec2(screenSize.width * 0.5f, screenSize.height * 0.5f) :
                                                                 ImVec2(screenSize.width * 0.5f, screenSize.height);
            draw->AddLine(startPt, ImVec2(pl.screenX, pl.screenY - pl.boxHeight), colBox, 1.0f);
        }

        // Health Bar
        if (g_imguiSettings.drawHealth) {
            float barW = 3.5f;
            float barH = bh;
            float barX = bx - 6.0f;
            float hpPct = pl.healthMax > 0.0f ? (pl.health / pl.healthMax) : 1.0f;
            if (hpPct < 0.0f) hpPct = 0.0f;
            if (hpPct > 1.0f) hpPct = 1.0f;

            draw->AddRectFilled(ImVec2(barX - 1, by - 1), ImVec2(barX + barW + 1, by + barH + 1), IM_COL32(0, 0, 0, 180));
            ImU32 colHp = (hpPct > 0.6f) ? IM_COL32(40, 220, 60, 255) :
                          (hpPct > 0.25f) ? IM_COL32(240, 200, 30, 255) : IM_COL32(240, 40, 40, 255);
            float fillH = barH * hpPct;
            draw->AddRectFilled(ImVec2(barX, by + barH - fillH), ImVec2(barX + barW, by + barH), colHp);
        }

        // Information Text (Name / Distance / Team)
        char infoBuf[128] = {0};
        if (g_imguiSettings.drawName) {
            if (g_imguiSettings.drawTeamId && pl.teamId > 0) {
                snprintf(infoBuf, sizeof(infoBuf), "[%d] %s [%dM]", pl.teamId, (pl.isAI ? "BOT" : pl.name), (int)pl.distanceMeters);
            } else {
                snprintf(infoBuf, sizeof(infoBuf), "%s [%dM]", (pl.isAI ? "BOT" : pl.name), (int)pl.distanceMeters);
            }
        } else if (g_imguiSettings.drawDistance) {
            snprintf(infoBuf, sizeof(infoBuf), "[%dM]", (int)pl.distanceMeters);
        }
        if (infoBuf[0]) {
            ImVec2 tSz = ImGui::CalcTextSize(infoBuf);
            ImVec2 tPos = ImVec2(pl.screenX - tSz.x * 0.5f, by - tSz.y - 2.0f);
            draw->AddText(ImVec2(tPos.x + 1, tPos.y + 1), IM_COL32(0, 0, 0, 220), infoBuf);
            draw->AddText(tPos, IM_COL32(255, 255, 255, 255), infoBuf);
        }

        // Weapon name under box
        if (g_imguiSettings.drawWeapon && pl.weaponName[0]) {
            ImVec2 wSz = ImGui::CalcTextSize(pl.weaponName);
            ImVec2 wPos = ImVec2(pl.screenX - wSz.x * 0.5f, by + bh + 2.0f);
            draw->AddText(ImVec2(wPos.x + 1, wPos.y + 1), IM_COL32(0, 0, 0, 220), pl.weaponName);
            draw->AddText(wPos, IM_COL32(255, 230, 100, 240), pl.weaponName);
        }
    }

    // 3. Grenade ESP
    if (g_imguiSettings.drawGrenade) {
        for (int g = 0; g < localGrenadeCount; g++) {
            const DSPUBGProjectedGrenade &gren = localGrenades[g];
            if (gren.distanceMeters > 100.0f) continue;

            // Damage Circles 3D
            if (g_imguiSettings.drawGrenadeCircle) {
                Circle3D(draw, gren.circlePoints, gren.circlePointsValid, IM_COL32(255, 255, 255, 220), 1.5f);
                Circle3D(draw, gren.circlePointsMid, gren.circlePointsMidValid, IM_COL32(255, 240, 20, 230), 1.8f);
                Circle3D(draw, gren.circlePointsInner, gren.circlePointsInnerValid, IM_COL32(255, 40, 40, 240), 2.0f);
            }

            // Flight Trail Line
            if (g_imguiSettings.drawGrenadeLine && gren.trajCount > 1) {
                for (int k = 0; k < gren.trajCount - 1; k++) {
                    draw->AddLine(ImVec2(gren.trajPoints[k].x, gren.trajPoints[k].y),
                                  ImVec2(gren.trajPoints[k + 1].x, gren.trajPoints[k + 1].y),
                                  IM_COL32(255, 80, 80, 220), 2.0f);
                }
            }

            // Bomb Marker Icon & Countdown Timer
            if (g_imguiSettings.drawGrenadeTimer && gren.isVisible) {
                float total = (gren.totalFuseSeconds > 0.1f) ? gren.totalFuseSeconds : 5.0f;
                float progress = 1.0f - (gren.cookSeconds / total);
                if (progress < 0.0f) progress = 0.0f;
                if (progress > 1.0f) progress = 1.0f;

                float gVal = 0.95f - (0.87f * progress);
                if (gVal < 0.08f) gVal = 0.08f;
                if (gVal > 0.95f) gVal = 0.95f;
                ImU32 colBomb = IM_COL32(255, (int)(gVal * 255.0f), 20, 255);

                ImVec2 mPos = ImVec2(gren.screenX, gren.screenY);
                draw->AddCircleFilled(mPos, 14.0f, colBomb);
                draw->AddCircle(mPos, 14.0f, IM_COL32(255, 255, 255, 255), 24, 2.0f);
                draw->AddLine(ImVec2(mPos.x + 8, mPos.y - 12), ImVec2(mPos.x + 13, mPos.y - 15), IM_COL32(255, 255, 100, 255), 2.5f);

                char gText[64];
                snprintf(gText, sizeof(gText), "%s %.1fs [%dM]", gren.name, gren.cookSeconds, (int)gren.distanceMeters);
                ImVec2 gSz = ImGui::CalcTextSize(gText);
                ImVec2 gtPos = ImVec2(mPos.x - gSz.x * 0.5f, mPos.y + 18.0f);
                draw->AddText(ImVec2(gtPos.x + 1, gtPos.y + 1), IM_COL32(0, 0, 0, 220), gText);
                draw->AddText(gtPos, IM_COL32(255, 255, 255, 255), gText);

                if (gren.distanceMeters <= 15.0f) {
                    const char *warn = "MOVE! MOVE! MOVE!";
                    ImVec2 wSz = ImGui::CalcTextSize(warn);
                    ImVec2 wPos = ImVec2(mPos.x - wSz.x * 0.5f, mPos.y - 28.0f);
                    draw->AddText(ImVec2(wPos.x + 1, wPos.y + 1), IM_COL32(0, 0, 0, 220), warn);
                    draw->AddText(wPos, IM_COL32(255, 50, 50, 255), warn);
                }
            }
        }
    }

    // 4. Items & Vehicles
    if (g_imguiSettings.drawItems || g_imguiSettings.drawVehicles) {
        for (int i = 0; i < localItemCount; i++) {
            const DSPUBGProjectedItem &it = localItems[i];
            if (!it.isVisible || it.distanceMeters > g_imguiSettings.itemMaxDist) continue;

            if (it.category == DSPUBGItemCategoryVehicle) {
                if (!g_imguiSettings.drawVehicles) continue;
                char vBuf[64];
                snprintf(vBuf, sizeof(vBuf), "%s [%dM]", it.name, (int)it.distanceMeters);
                ImVec2 vSz = ImGui::CalcTextSize(vBuf);
                ImVec2 vPos = ImVec2(it.screenX - vSz.x * 0.5f, it.screenY);
                draw->AddText(ImVec2(vPos.x + 1, vPos.y + 1), IM_COL32(0, 0, 0, 220), vBuf);
                draw->AddText(vPos, IM_COL32(0, 230, 255, 240), vBuf);
            } else {
                if (!g_imguiSettings.drawItems) continue;
                char iBuf[64];
                snprintf(iBuf, sizeof(iBuf), "%s [%dM]", it.name, (int)it.distanceMeters);
                ImVec2 iSz = ImGui::CalcTextSize(iBuf);
                ImVec2 iPos = ImVec2(it.screenX - iSz.x * 0.5f, it.screenY);
                ImU32 colItem = (it.category == DSPUBGItemCategoryWeapon) ? IM_COL32(255, 215, 0, 230) :
                                (it.category == DSPUBGItemCategoryArmor)  ? IM_COL32(180, 100, 255, 230) :
                                (it.category == DSPUBGItemCategoryCrate)  ? IM_COL32(255, 70, 70, 255) :
                                                                           IM_COL32(100, 240, 150, 220);
                draw->AddText(ImVec2(iPos.x + 1, iPos.y + 1), IM_COL32(0, 0, 0, 220), iBuf);
                draw->AddText(iPos, colItem, iBuf);
            }
        }
    }
}

#pragma mark - Floating Button & Menu

static void ds_imgui_render_floating_button(ImDrawList *draw) {
    ImVec2 c = g_floatingButtonPos;
    float r = 22.0f;

    draw->AddCircleFilled(c, r + 2.0f, IM_COL32(0, 0, 0, 120), 32);
    ImU32 colBtn = g_imguiMenuOpen ? IM_COL32(40, 150, 240, 230) : IM_COL32(30, 30, 35, 220);
    draw->AddCircleFilled(c, r, colBtn, 32);
    draw->AddCircle(c, r, IM_COL32(255, 255, 255, 220), 32, 1.8f);

    const char *label = "D3S";
    ImVec2 lSz = ImGui::CalcTextSize(label);
    draw->AddText(ImVec2(c.x - lSz.x * 0.5f, c.y - lSz.y * 0.5f), IM_COL32(255, 255, 255, 255), label);
}

static void ds_imgui_render_menu(void) {
    ImGui::SetNextWindowSize(ImVec2(340, 420), ImGuiCond_FirstUseEver);
    if (ImGui::Begin("DarkPubg Menu", &g_imguiMenuOpen, ImGuiWindowFlags_NoCollapse)) {
        ImVec2 pos = ImGui::GetWindowPos();
        ImVec2 size = ImGui::GetWindowSize();
        g_imguiMenuRect = CGRectMake(pos.x, pos.y, size.x, size.y);

        if (ImGui::BeginTabBar("MenuTabs")) {
            if (ImGui::BeginTabItem("ESP Người Chơi")) {
                ImGui::Checkbox("Bật ESP", &g_imguiSettings.espEnabled);
                ImGui::Separator();
                ImGui::Checkbox("Khung (Box 2D)", &g_imguiSettings.drawBox);
                if (g_imguiSettings.drawBox) {
                    ImGui::RadioButton("Khung Góc", &g_imguiSettings.boxType, 0); ImGui::SameLine();
                    ImGui::RadioButton("Khung Đầy Đủ", &g_imguiSettings.boxType, 1);
                }
                ImGui::Checkbox("Khung Xương (Skeleton)", &g_imguiSettings.drawSkeleton);
                ImGui::Checkbox("Đường Kẻ (Snapline)", &g_imguiSettings.drawLine);
                if (g_imguiSettings.drawLine) {
                    ImGui::RadioButton("Từ Trên", &g_imguiSettings.lineOrigin, 0); ImGui::SameLine();
                    ImGui::RadioButton("Từ Giữa", &g_imguiSettings.lineOrigin, 1); ImGui::SameLine();
                    ImGui::RadioButton("Từ Dưới", &g_imguiSettings.lineOrigin, 2);
                }
                ImGui::Checkbox("Thanh Máu (Health Bar)", &g_imguiSettings.drawHealth);
                ImGui::Checkbox("Tên Người Chơi", &g_imguiSettings.drawName);
                ImGui::Checkbox("Khoảng Cách (Meters)", &g_imguiSettings.drawDistance);
                ImGui::Checkbox("Hiện Số Đội (Team ID)", &g_imguiSettings.drawTeamId);
                ImGui::Checkbox("Hiện Tên Súng (Weapon)", &g_imguiSettings.drawWeapon);
                ImGui::Checkbox("Hiện Bot (AI)", &g_imguiSettings.drawBot);
                ImGui::SliderFloat("Tầm Quét (M)", &g_imguiSettings.playerMaxDist, 50.0f, 600.0f, "%.0f M");
                ImGui::EndTabItem();
            }
            if (ImGui::BeginTabItem("Lựu Đạn")) {
                ImGui::Checkbox("Bật ESP Bom", &g_imguiSettings.drawGrenade);
                ImGui::Separator();
                ImGui::Checkbox("Đường Bay Bom (Line)", &g_imguiSettings.drawGrenadeLine);
                ImGui::Checkbox("Vòng Tròn Sát Thương 3D", &g_imguiSettings.drawGrenadeCircle);
                ImGui::Checkbox("Icon Quả Bom & Đếm Giây", &g_imguiSettings.drawGrenadeTimer);
                ImGui::EndTabItem();
            }
            if (ImGui::BeginTabItem("Vật Phẩm & Xe")) {
                ImGui::Checkbox("Hiện Vật Phẩm (Items)", &g_imguiSettings.drawItems);
                ImGui::Checkbox("Hiện Phương Tiện (Vehicles)", &g_imguiSettings.drawVehicles);
                ImGui::SliderFloat("Tầm Nhìn Vật Phẩm (M)", &g_imguiSettings.itemMaxDist, 20.0f, 200.0f, "%.0f M");
                ImGui::EndTabItem();
            }
            if (ImGui::BeginTabItem("Cài Đặt")) {
                ImGui::SliderFloat("Độ Dày Nét Vẽ", &g_imguiSettings.strokeThickness, 1.0f, 3.5f, "%.1f px");
                ImGui::SliderFloat("Cỡ Chữ", &g_imguiSettings.fontSize, 10.0f, 22.0f, "%.0f px");
                ImGui::Separator();
                if (ImGui::Button("Đóng Menu", ImVec2(120, 30))) {
                    g_imguiMenuOpen = false;
                }
                ImGui::EndTabItem();
            }
            ImGui::EndTabBar();
        }
    }
    ImGui::End();
}

#pragma mark - Window Management & SpringBoard Setup

static unsigned ds_imgui_setup_on_main(void) {
    if (g_imguiWindow) {
        g_imguiWindow.hidden = NO;
        return g_imguiContextId;
    }

    CGRect screenBounds = UIScreen.mainScreen.bounds;
    CGFloat landW = MAX(screenBounds.size.width, screenBounds.size.height);
    CGFloat landH = MIN(screenBounds.size.width, screenBounds.size.height);

    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    if (!device) {
        return 0;
    }

    DSImGuiWindow *window = [[DSImGuiWindow alloc] initWithFrame:screenBounds];
    window.backgroundColor = [UIColor clearColor];
    window.windowLevel = 10000010.0;

    UIViewController *vc = [[UIViewController alloc] init];
    vc.view = [[UIView alloc] initWithFrame:screenBounds];
    vc.view.backgroundColor = [UIColor clearColor];
    vc.view.userInteractionEnabled = NO;
    window.rootViewController = vc;

    DSImGuiView *view = [[DSImGuiView alloc] initWithFrame:CGRectMake(0, 0, landW, landH) device:device];
    [vc.view addSubview:view];

    g_imguiWindow = window;
    g_imguiView = view;
    [view updateOrientationIfNeeded];

    window.hidden = NO;
    [window makeKeyAndVisible];

    unsigned contextId = ((unsigned (*)(id, SEL))objc_msgSend)(window, NSSelectorFromString(@"_contextId"));
    if (!contextId) {
        window.hidden = YES;
        return 0;
    }

    g_imguiContextId = contextId;

    // Register in-process SBSAccessibilityWindowHostingController
    Class hostClass = objc_getClass("SBSAccessibilityWindowHostingController");
    if (hostClass) {
        id hostController = [[hostClass alloc] init];
        double windowLevel = [window windowLevel];
        SEL regSel = NSSelectorFromString(@"registerWindowWithContextID:atLevel:");
        if ([hostController respondsToSelector:regSel]) {
            NSMethodSignature *sig = [hostController methodSignatureForSelector:regSel];
            if (sig) {
                NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
                [inv setTarget:hostController];
                [inv setSelector:regSel];
                [inv setArgument:&contextId atIndex:2];
                [inv setArgument:&windowLevel atIndex:3];
                [inv invoke];
            }
        }
    }

    // Register global HID event callback for background touch handling
    if (!g_imguiHIDRegistered) {
        BKSHIDEventRegisterEventCallback(ds_imgui_hid_callback);
        g_imguiHIDRegistered = true;
    }

    return contextId;
}

static void ds_imgui_pause(void) {
    if (g_imguiWindow) {
        g_imguiWindow.hidden = YES;
    }
}

static void ds_imgui_resume(void) {
    if (g_imguiWindow) {
        g_imguiWindow.hidden = NO;
    }
}
