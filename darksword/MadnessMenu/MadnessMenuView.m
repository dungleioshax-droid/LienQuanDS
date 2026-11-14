#import "MadnessMenuView.h"
#import "MADSW.h"
#import "MenuWidgets.h"
#import "MadnessMascotData.h"
#import <QuartzCore/QuartzCore.h>

static const CGFloat kMadnessPanelW = 640.0f;
static const CGFloat kMadnessPanelH = 325.0f;

@interface MadnessMenuView () <UIScrollViewDelegate>
@property (nonatomic, strong) UIButton *panel;
@property (nonatomic, strong) UIView *titleBox;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UIImageView *mascotView;

// Header top bar items
@property (nonatomic, strong) UILabel *lblEn;
@property (nonatomic, strong) UILabel *lblAr;
@property (nonatomic, strong) UILabel *lblRu;
@property (nonatomic, strong) UILabel *lblCh;
@property (nonatomic, strong) UIButton *contactBtn;
@property (nonatomic, strong) UILabel *handleMajed;
@property (nonatomic, strong) UILabel *handleChan;

// Subheader line items
@property (nonatomic, strong) UILabel *clockLabel;
@property (nonatomic, strong) UILabel *batteryLabel;
@property (nonatomic, strong) UILabel *sloganLabel;

// Scrolling & toggling
@property (nonatomic, strong) UIScrollView *scroll;
@property (nonatomic, strong) UIButton *handle;
@property (nonatomic, strong) UILabel *handleGlyph;
@property (nonatomic, strong) UITapGestureRecognizer *handleTap;
@property (nonatomic, strong) UILongPressGestureRecognizer *handleLong;
@property (nonatomic, strong) NSDateFormatter *ttime;
@property (nonatomic, strong) NSTimer *clockTimer;

// Circular Radar HUD
@property (nonatomic, strong) CAShapeLayer *triangleMaskLayer;
@property (nonatomic, strong) CAShapeLayer *radacircle;
@property (nonatomic, strong) CAShapeLayer *radacircle2;
@property (nonatomic, strong) CAShapeLayer *radacircle3;
@property (nonatomic, strong) CAShapeLayer *ViewLine;
@property (nonatomic, strong) UIButton *dragMap;
@property (nonatomic) BOOL asize;
@property (nonatomic, strong) UIImpactFeedbackGenerator *haptic;

// Live widgets for DarkPubg ESP state
@property (nonatomic, strong) MenuToggleButton *btnEspEnable;
@property (nonatomic, strong) MenuToggleButton *btnLine;
@property (nonatomic, strong) MenuToggleButton *btnEnemyNum;
@property (nonatomic, strong) MenuToggleButton *btnHealth;
@property (nonatomic, strong) MenuToggleButton *btnBone;
@property (nonatomic, strong) MenuToggleButton *btnRadar;
@property (nonatomic, strong) MenuToggleButton *btnName;
@property (nonatomic, strong) MenuToggleButton *btnDist;
@property (nonatomic, strong) MenuToggleButton *btn3D;
@property (nonatomic, strong) MenuToggleButton *btnArrow;
@property (nonatomic, strong) MenuToggleButton *btnTeam;
@property (nonatomic, strong) MenuToggleButton *btnFlag;
@property (nonatomic, strong) MenuSliderRow *sliderEspDist;

// Material widgets
@property (nonatomic, strong) MenuToggleButton *btnMatEnable;
@property (nonatomic, strong) MenuToggleButton *btnVeh;
@property (nonatomic, strong) MenuToggleButton *btnGrenade;
@property (nonatomic, strong) MenuToggleButton *btnLootBox;
@property (nonatomic, strong) MenuToggleButton *btnFlareGun;
@property (nonatomic, strong) MenuToggleButton *btnAirdrop;
@property (nonatomic, strong) MenuToggleButton *btnAccessory;
@property (nonatomic, strong) MenuToggleButton *btnDrug;
@property (nonatomic, strong) MenuToggleButton *btnVal;
@property (nonatomic, strong) MenuToggleButton *btnAkm;
@property (nonatomic, strong) MenuToggleButton *btnM416;
@property (nonatomic, strong) MenuToggleButton *btnScarl;
@property (nonatomic, strong) MenuSliderRow *sliderItemDist;

@end

@implementation MadnessMenuView

- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    self.backgroundColor = UIColor.clearColor;
    self.userInteractionEnabled = YES;
    self.haptic = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];

    // Load persisted settings
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    if ([defaults objectForKey:@"pubg_box"] != nil) g_pubgEspBox = [defaults boolForKey:@"pubg_box"];
    if ([defaults objectForKey:@"pubg_skeleton"] != nil) g_pubgEspSkeleton = [defaults boolForKey:@"pubg_skeleton"];
    if ([defaults objectForKey:@"pubg_line"] != nil) g_pubgEspLine = [defaults boolForKey:@"pubg_line"];
    if ([defaults objectForKey:@"pubg_health"] != nil) g_pubgEspHealth = [defaults boolForKey:@"pubg_health"];
    if ([defaults objectForKey:@"pubg_name"] != nil) g_pubgEspName = [defaults boolForKey:@"pubg_name"];
    if ([defaults objectForKey:@"pubg_dist"] != nil) g_pubgEspDist = [defaults boolForKey:@"pubg_dist"];
    if ([defaults objectForKey:@"pubg_bot"] != nil) g_pubgEspBot = [defaults boolForKey:@"pubg_bot"];
    if ([defaults objectForKey:@"pubg_enemy_num"] != nil) g_pubgEspEnemyNumber = [defaults boolForKey:@"pubg_enemy_num"];
    if ([defaults objectForKey:@"pubg_radar"] != nil) g_pubgEspRadar = [defaults boolForKey:@"pubg_radar"];
    if ([defaults objectForKey:@"pubg_team"] != nil) g_pubgEspTeam = [defaults boolForKey:@"pubg_team"];
    if ([defaults objectForKey:@"pubg_flag"] != nil) g_pubgEspFlag = [defaults boolForKey:@"pubg_flag"];
    if ([defaults objectForKey:@"pubg_arrow"] != nil) g_pubgEspArrow = [defaults boolForKey:@"pubg_arrow"];
    if ([defaults objectForKey:@"pubg_grenade"] != nil) g_pubgEspGrenade = [defaults boolForKey:@"pubg_grenade"];
    if ([defaults objectForKey:@"pubg_vehicle"] != nil) g_pubgEspVehicle = [defaults boolForKey:@"pubg_vehicle"];
    if ([defaults objectForKey:@"pubg_vehicle_hp"] != nil) g_pubgEspVehicleHp = [defaults boolForKey:@"pubg_vehicle_hp"];
    if ([defaults objectForKey:@"pubg_vehicle_fuel"] != nil) g_pubgEspVehicleFuel = [defaults boolForKey:@"pubg_vehicle_fuel"];
    if ([defaults objectForKey:@"pubg_weapon"] != nil) g_pubgEspWeapon = [defaults boolForKey:@"pubg_weapon"];
    if ([defaults objectForKey:@"pubg_armor"] != nil) g_pubgEspArmor = [defaults boolForKey:@"pubg_armor"];
    if ([defaults objectForKey:@"pubg_bag"] != nil) g_pubgEspBag = [defaults boolForKey:@"pubg_bag"];
    if ([defaults objectForKey:@"pubg_scope"] != nil) g_pubgEspScope = [defaults boolForKey:@"pubg_scope"];
    if ([defaults objectForKey:@"pubg_crate"] != nil) g_pubgEspCrate = [defaults boolForKey:@"pubg_crate"];
    if ([defaults objectForKey:@"pubg_flaregun"] != nil) g_pubgEspFlareGun = [defaults boolForKey:@"pubg_flaregun"];
    if ([defaults objectForKey:@"pubg_drug"] != nil) g_pubgEspDrug = [defaults boolForKey:@"pubg_drug"];
    if ([defaults objectForKey:@"pubg_val"] != nil) g_pubgEspVal = [defaults boolForKey:@"pubg_val"];
    if ([defaults objectForKey:@"pubg_akm"] != nil) g_pubgEspAkm = [defaults boolForKey:@"pubg_akm"];
    if ([defaults objectForKey:@"pubg_m416"] != nil) g_pubgEspM416 = [defaults boolForKey:@"pubg_m416"];
    if ([defaults objectForKey:@"pubg_scarl"] != nil) g_pubgEspScarl = [defaults boolForKey:@"pubg_scarl"];
    if ([defaults objectForKey:@"pubg_zoom_dist"] != nil) g_dspubgMaxDistance = [defaults floatForKey:@"pubg_zoom_dist"];
    if ([defaults objectForKey:@"pubg_item_dist"] != nil) g_pubgItemMaxDistance = [defaults floatForKey:@"pubg_item_dist"];
    if ([defaults objectForKey:@"pubg_thickness"] != nil) {
        g_pubgEspThickness = [defaults floatForKey:@"pubg_thickness"];
        if (g_pubgEspThickness < 0.8f) g_pubgEspThickness = 0.8f;
        if (g_pubgEspThickness > 3.5f) g_pubgEspThickness = 3.5f;
    }

    [self buildChrome];
    [self buildRadarHUD];
    [self buildHorizontalContent];
    [self startClock];
    return self;
}

#pragma mark - Helpers

- (MenuToggleButton *)btn:(NSString *)t frame:(CGRect)f inView:(UIView *)p italic:(BOOL)it {
    MenuToggleButton *b = [[MenuToggleButton alloc] initWithTitle:t frame:f italic:it];
    [p addSubview:b];
    return b;
}

- (void)addSectionHeader:(NSString *)title atY:(CGFloat)y {
    UILabel *chev = [[UILabel alloc] initWithFrame:CGRectMake(15, y, 14, 18)];
    chev.text = @"⋗";
    chev.textColor = UIColor.yellowColor;
    chev.font = [UIFont boldSystemFontOfSize:18.0];
    chev.textAlignment = NSTextAlignmentLeft;
    [self.scroll addSubview:chev];

    UILabel *tit = [[UILabel alloc] initWithFrame:CGRectMake(32, y, 220, 18)];
    tit.text = title;
    tit.textColor = UIColor.whiteColor;
    tit.font = [UIFont boldSystemFontOfSize:12.0];
    tit.textAlignment = NSTextAlignmentLeft;
    [self.scroll addSubview:tit];
}

#pragma mark - Chrome (Header & Panels)

- (void)buildChrome {
    CGFloat startX = 60.0;
    CGFloat startY = 15.0;
    id sx = [NSUserDefaults.standardUserDefaults objectForKey:@"madness_menu_x"];
    id sy = [NSUserDefaults.standardUserDefaults objectForKey:@"madness_menu_y"];
    if (sx && sy) {
        CGFloat x = [sx floatValue];
        CGFloat y = [sy floatValue];
        if (x > 20 && x < 1500 && y > 10 && y < 1000) {
            startX = x - 105.0;
            startY = y - 16.0;
        }
    }

    // Panel container: start collapsed
    self.panel = [UIButton buttonWithType:UIButtonTypeCustom];
    self.panel.frame = CGRectMake(startX, startY, 210, 32);
    self.panel.backgroundColor = UIColor.clearColor;
    self.panel.layer.cornerRadius = 12.0;
    self.panel.clipsToBounds = YES;
    [self.panel addTarget:self action:@selector(wasDragged:withEvent:) forControlEvents:UIControlEventTouchDragInside | UIControlEventTouchDragOutside];
    [self addSubview:self.panel];

    // Collapse / Expand handle button (Round circle [ V ])
    self.handle = [UIButton buttonWithType:UIButtonTypeCustom];
    self.handle.frame = CGRectMake(8, 3, 26, 26);
    self.handle.backgroundColor = MADBlack50();
    self.handle.layer.cornerRadius = 13.0;
    self.handle.layer.masksToBounds = YES;
    self.handle.layer.borderWidth = 0.8;
    self.handle.layer.borderColor = [UIColor colorWithWhite:0.4 alpha:0.8].CGColor;
    [self.panel addSubview:self.handle];

    self.handleTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(controllview)];
    [self.handle addGestureRecognizer:self.handleTap];
    self.handleLong = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPress:)];
    self.handleLong.minimumPressDuration = 0.5;
    [self.handle addGestureRecognizer:self.handleLong];
    [self.handle addTarget:self action:@selector(handleTapped:) forControlEvents:UIControlEventTouchUpInside];

    self.handleGlyph = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, 26, 26)];
    self.handleGlyph.text = @"⋗";
    self.handleGlyph.font = [UIFont boldSystemFontOfSize:22.0];
    self.handleGlyph.textColor = UIColor.yellowColor;
    self.handleGlyph.textAlignment = NSTextAlignmentCenter;
    self.handleGlyph.userInteractionEnabled = NO;
    self.handleGlyph.backgroundColor = UIColor.clearColor;
    [self.handle addSubview:self.handleGlyph];

    // Top Dark Header Capsule Bar: [ MADNESS (cat) EN عربي RU CH  CONTACT->  @Majed_aj  MADNESS~CHANNEL ]
    self.titleBox = [[UIView alloc] initWithFrame:CGRectMake(38, 3, 160, 26)];
    self.titleBox.backgroundColor = [UIColor colorWithWhite:0.08 alpha:0.90];
    self.titleBox.layer.cornerRadius = 13.0;
    self.titleBox.layer.borderColor = [UIColor colorWithWhite:0.25 alpha:0.8].CGColor;
    self.titleBox.layer.borderWidth = 0.5;
    self.titleBox.clipsToBounds = YES;
    self.titleBox.userInteractionEnabled = YES;
    [self.panel addSubview:self.titleBox];

    // 1. Title: MADNESS
    self.titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(10, 3, 62, 20)];
    self.titleLabel.text = @"MADNESS";
    self.titleLabel.textColor = UIColor.yellowColor;
    self.titleLabel.font = [UIFont fontWithName:@"AvenirNextCondensed-HeavyItalic" size:13.0]
                           ?: [UIFont boldSystemFontOfSize:13.0];
    self.titleLabel.textAlignment = NSTextAlignmentLeft;
    self.titleLabel.userInteractionEnabled = NO;
    [self.titleBox addSubview:self.titleLabel];

    // 2. Mascot icon
    self.mascotView = [[UIImageView alloc] initWithFrame:CGRectMake(74, 2.5, 21, 21)];
    self.mascotView.image = MadnessMascotImage();
    self.mascotView.contentMode = UIViewContentModeScaleAspectFit;
    self.mascotView.userInteractionEnabled = NO;
    [self.titleBox addSubview:self.mascotView];

    // 3. Language Selector: [ EN ]  عربي  RU  CH
    self.lblEn = [[UILabel alloc] initWithFrame:CGRectMake(100, 3.5, 24, 19)];
    self.lblEn.text = @"EN";
    self.lblEn.backgroundColor = UIColor.yellowColor;
    self.lblEn.textColor = UIColor.blackColor;
    self.lblEn.font = [UIFont boldSystemFontOfSize:10.0];
    self.lblEn.textAlignment = NSTextAlignmentCenter;
    self.lblEn.layer.cornerRadius = 4.0;
    self.lblEn.clipsToBounds = YES;
    [self.titleBox addSubview:self.lblEn];

    self.lblAr = [[UILabel alloc] initWithFrame:CGRectMake(128, 3.5, 28, 19)];
    self.lblAr.text = @"عربي";
    self.lblAr.textColor = UIColor.whiteColor;
    self.lblAr.font = [UIFont boldSystemFontOfSize:10.0];
    self.lblAr.textAlignment = NSTextAlignmentCenter;
    [self.titleBox addSubview:self.lblAr];

    self.lblRu = [[UILabel alloc] initWithFrame:CGRectMake(160, 3.5, 22, 19)];
    self.lblRu.text = @"RU";
    self.lblRu.textColor = UIColor.whiteColor;
    self.lblRu.font = [UIFont boldSystemFontOfSize:10.0];
    self.lblRu.textAlignment = NSTextAlignmentCenter;
    [self.titleBox addSubview:self.lblRu];

    self.lblCh = [[UILabel alloc] initWithFrame:CGRectMake(184, 3.5, 22, 19)];
    self.lblCh.text = @"CH";
    self.lblCh.textColor = UIColor.whiteColor;
    self.lblCh.font = [UIFont boldSystemFontOfSize:10.0];
    self.lblCh.textAlignment = NSTextAlignmentCenter;
    [self.titleBox addSubview:self.lblCh];

    // 4. Contact button: [ CONTACT-> ]
    self.contactBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    self.contactBtn.frame = CGRectMake(212, 3.5, 86, 19);
    self.contactBtn.backgroundColor = UIColor.yellowColor;
    self.contactBtn.layer.cornerRadius = 9.5;
    self.contactBtn.clipsToBounds = YES;
    [self.contactBtn setTitle:@"CONTACT->" forState:UIControlStateNormal];
    [self.contactBtn setTitleColor:UIColor.blackColor forState:UIControlStateNormal];
    self.contactBtn.titleLabel.font = [UIFont boldSystemFontOfSize:10.0];
    [self.contactBtn addTarget:self action:@selector(contactTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.titleBox addSubview:self.contactBtn];

    // 5. Handles: @Majed_aj  MADNESS~CHANNEL
    self.handleMajed = [[UILabel alloc] initWithFrame:CGRectMake(306, 3.5, 76, 19)];
    self.handleMajed.text = @"@Majed_aj";
    self.handleMajed.textColor = UIColor.whiteColor;
    self.handleMajed.font = [UIFont boldSystemFontOfSize:10.5];
    self.handleMajed.textAlignment = NSTextAlignmentLeft;
    [self.titleBox addSubview:self.handleMajed];

    self.handleChan = [[UILabel alloc] initWithFrame:CGRectMake(386, 3.5, 140, 19)];
    self.handleChan.text = @"MADNESS~CHANNEL";
    self.handleChan.textColor = [UIColor colorWithWhite:0.75 alpha:1.0];
    self.handleChan.font = [UIFont boldSystemFontOfSize:10.0];
    self.handleChan.textAlignment = NSTextAlignmentLeft;
    [self.titleBox addSubview:self.handleChan];

    // Subheader Line (Below top capsule bar, y = 35):
    // Left: Date & Time + Battery Level
    self.clockLabel = [[UILabel alloc] initWithFrame:CGRectMake(42, 35, 155, 16)];
    self.clockLabel.backgroundColor = UIColor.clearColor;
    self.clockLabel.textColor = UIColor.whiteColor;
    self.clockLabel.font = [UIFont boldSystemFontOfSize:11.0];
    self.clockLabel.textAlignment = NSTextAlignmentLeft;
    self.clockLabel.userInteractionEnabled = NO;
    self.clockLabel.hidden = YES;
    [self.panel addSubview:self.clockLabel];

    self.batteryLabel = [[UILabel alloc] initWithFrame:CGRectMake(202, 35, 30, 16)];
    self.batteryLabel.backgroundColor = UIColor.clearColor;
    self.batteryLabel.textColor = UIColor.yellowColor;
    self.batteryLabel.font = [UIFont boldSystemFontOfSize:11.0];
    self.batteryLabel.textAlignment = NSTextAlignmentLeft;
    self.batteryLabel.userInteractionEnabled = NO;
    self.batteryLabel.hidden = YES;
    [self.panel addSubview:self.batteryLabel];

    // Right: MORE FUTURE SOON INJOY ;)
    self.sloganLabel = [[UILabel alloc] initWithFrame:CGRectMake(240, 35, kMadnessPanelW - 252, 16)];
    self.sloganLabel.backgroundColor = UIColor.clearColor;
    self.sloganLabel.text = @"MORE FUTURE SOON INJOY ;)";
    self.sloganLabel.textColor = UIColor.yellowColor;
    self.sloganLabel.font = [UIFont boldSystemFontOfSize:11.0];
    self.sloganLabel.textAlignment = NSTextAlignmentRight;
    self.sloganLabel.userInteractionEnabled = NO;
    self.sloganLabel.hidden = YES;
    [self.panel addSubview:self.sloganLabel];

    // Content Scroll View (Horizontal menu grid): 0, 54, 640, 271
    self.scroll = [[UIScrollView alloc] initWithFrame:CGRectMake(0, 54, kMadnessPanelW, kMadnessPanelH - 54)];
    self.scroll.contentSize = CGSizeMake(kMadnessPanelW, 290);
    self.scroll.alwaysBounceHorizontal = NO;
    self.scroll.showsHorizontalScrollIndicator = NO;
    self.scroll.directionalLockEnabled = YES;
    self.scroll.delegate = self;
    self.scroll.backgroundColor = UIColor.clearColor;
    self.scroll.clipsToBounds = YES;
    self.scroll.hidden = YES;
    self.scroll.showsVerticalScrollIndicator = YES;
    self.scroll.indicatorStyle = UIScrollViewIndicatorStyleWhite;
    [self.panel addSubview:self.scroll];

    self.ttime = [[NSDateFormatter alloc] init];
    self.ttime.dateFormat = @"yyyy/MM/dd • HH:mm:ss";
}

#pragma mark - Circular Radar HUD (DRAW SRADAR)

- (void)buildRadarHUD {
    CGFloat rx = 47.0f, ry = 47.0f;
    self.dragMap = [UIButton buttonWithType:UIButtonTypeCustom];

    // Initial position on screen (can be dragged anywhere)
    CGFloat startX = 520.0f;
    CGFloat startY = 220.0f;
    id rxSaved = [NSUserDefaults.standardUserDefaults objectForKey:@"madness_radar_x"];
    id rySaved = [NSUserDefaults.standardUserDefaults objectForKey:@"madness_radar_y"];
    if (rxSaved && rySaved) {
        startX = [rxSaved floatValue] - rx;
        startY = [rySaved floatValue] - ry;
    }
    self.dragMap.frame = CGRectMake(startX, startY, 94.0f, 94.0f);
    self.dragMap.backgroundColor = UIColor.clearColor;
    self.dragMap.layer.cornerRadius = 47.0f;
    self.dragMap.clipsToBounds = NO;
    self.dragMap.hidden = !g_pubgEspRadar;
    [self.dragMap addTarget:self action:@selector(wasDraggedm:withEventm:) forControlEvents:UIControlEventTouchDragInside | UIControlEventTouchDragOutside];
    [self addSubview:self.dragMap];

    // 1. Center green triangle
    UIBezierPath *tri = [UIBezierPath bezierPath];
    [tri moveToPoint:CGPointMake(rx - 5.0f, ry + 5.0f)];
    [tri addLineToPoint:CGPointMake(rx + 5.0f, ry + 5.0f)];
    [tri addLineToPoint:CGPointMake(rx, ry - 5.0f)];
    [tri closePath];
    self.triangleMaskLayer = [CAShapeLayer layer];
    self.triangleMaskLayer.path = tri.CGPath;
    self.triangleMaskLayer.strokeColor = UIColor.greenColor.CGColor;
    self.triangleMaskLayer.fillColor = UIColor.greenColor.CGColor;
    [self.dragMap.layer addSublayer:self.triangleMaskLayer];

    // 2. FOV lines
    UIBezierPath *line = [UIBezierPath bezierPath];
    [line moveToPoint:CGPointMake(rx, ry)];
    [line addLineToPoint:CGPointMake(rx - 33.0f, ry - 33.0f)];
    [line moveToPoint:CGPointMake(rx, ry)];
    [line addLineToPoint:CGPointMake(rx + 33.0f, ry - 33.0f)];
    self.ViewLine = [CAShapeLayer layer];
    self.ViewLine.path = line.CGPath;
    self.ViewLine.strokeColor = [UIColor colorWithWhite:1.0 alpha:0.6].CGColor;
    self.ViewLine.lineWidth = 1.0f;
    [self.dragMap.layer addSublayer:self.ViewLine];

    // 3. Inner red circle (radius 17)
    self.radacircle = [CAShapeLayer layer];
    self.radacircle.path = [UIBezierPath bezierPathWithArcCenter:CGPointMake(rx, ry) radius:17.0f startAngle:0 endAngle:(CGFloat)(2*M_PI) clockwise:YES].CGPath;
    self.radacircle.strokeColor = UIColor.redColor.CGColor;
    self.radacircle.fillColor = UIColor.clearColor.CGColor;
    self.radacircle.lineWidth = 1.0f;
    [self.dragMap.layer addSublayer:self.radacircle];

    // 4. Middle orange circle (radius 32)
    self.radacircle2 = [CAShapeLayer layer];
    self.radacircle2.path = [UIBezierPath bezierPathWithArcCenter:CGPointMake(rx, ry) radius:32.0f startAngle:0 endAngle:(CGFloat)(2*M_PI) clockwise:YES].CGPath;
    self.radacircle2.strokeColor = UIColor.orangeColor.CGColor;
    self.radacircle2.fillColor = UIColor.clearColor.CGColor;
    self.radacircle2.lineWidth = 1.0f;
    [self.dragMap.layer addSublayer:self.radacircle2];

    // 5. Outer green circle (radius 47)
    self.radacircle3 = [CAShapeLayer layer];
    self.radacircle3.path = [UIBezierPath bezierPathWithArcCenter:CGPointMake(rx, ry) radius:47.0f startAngle:0 endAngle:(CGFloat)(2*M_PI) clockwise:YES].CGPath;
    self.radacircle3.strokeColor = UIColor.greenColor.CGColor;
    self.radacircle3.fillColor = UIColor.clearColor.CGColor;
    self.radacircle3.lineWidth = 1.0f;
    [self.dragMap.layer addSublayer:self.radacircle3];
}

#pragma mark - Clock & Contact

- (void)startClock {
    [UIDevice currentDevice].batteryMonitoringEnabled = YES;
    [self tickClock];
    self.clockTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(tickClock) userInfo:nil repeats:YES];
}

- (void)tickClock {
    NSString *ds = [self.ttime stringFromDate:[NSDate date]];
    self.clockLabel.text = ds ?: @"";
    float lvl = [UIDevice currentDevice].batteryLevel;
    if (lvl < 0) lvl = 1.0f;
    self.batteryLabel.text = [NSString stringWithFormat:@"%0.0f", lvl * 100.0];
}

- (void)contactTapped {
    [self.haptic impactOccurred];
    NSURL *u = [NSURL URLWithString:@"https://t.me/Majed_aj"];
    if ([[UIApplication sharedApplication] canOpenURL:u]) {
        [[UIApplication sharedApplication] openURL:u options:@{} completionHandler:nil];
    }
}

#pragma mark - Horizontal Content Grid (4 Columns x Pill Buttons)

- (void)buildHorizontalContent {
    __weak typeof(self) weakSelf = self;

    const CGFloat colW = 142.0f;
    const CGFloat colGap = 14.0f;
    const CGFloat startX = 15.0f;
    const CGFloat btnH = 22.0f;

    CGFloat x0 = startX + 0 * (colW + colGap); // 15
    CGFloat x1 = startX + 1 * (colW + colGap); // 171
    CGFloat x2 = startX + 2 * (colW + colGap); // 327
    CGFloat x3 = startX + 3 * (colW + colGap); // 483

    // =========================================================================
    // SECTION 1: > ESP PANEL
    // =========================================================================
    [self addSectionHeader:@"ESP PANEL" atY:6.0];

    // Row 0 (y = 28): [ ENABLE ], [ DRAW LINE ], [ ENEMY NUMBER ], [ PLAYER HEALTH ]
    self.btnEspEnable = [self btn:@"ENABLE" frame:CGRectMake(x0, 28, colW, btnH) inView:self.scroll italic:YES];
    self.btnEspEnable.on = ds_hosted_esp_enabled();
    self.btnEspEnable.onToggle = ^(BOOL isOn) {
        ds_hosted_esp_set_enabled(isOn);
        [NSUserDefaults.standardUserDefaults setBool:isOn forKey:kDSHostedEspEnabledKey];
    };

    self.btnLine = [self btn:@"DRAW LINE" frame:CGRectMake(x1, 28, colW, btnH) inView:self.scroll italic:YES];
    self.btnLine.on = g_pubgEspLine;
    self.btnLine.onToggle = ^(BOOL isOn) {
        g_pubgEspLine = isOn;
        [NSUserDefaults.standardUserDefaults setBool:isOn forKey:@"pubg_line"];
    };

    self.btnEnemyNum = [self btn:@"ENEMY NUMBER" frame:CGRectMake(x2, 28, colW, btnH) inView:self.scroll italic:YES];
    self.btnEnemyNum.on = g_pubgEspEnemyNumber;
    self.btnEnemyNum.onToggle = ^(BOOL isOn) {
        g_pubgEspEnemyNumber = isOn;
        [NSUserDefaults.standardUserDefaults setBool:isOn forKey:@"pubg_enemy_num"];
    };

    self.btnHealth = [self btn:@"PLAYER HEALTH" frame:CGRectMake(x3, 28, colW, btnH) inView:self.scroll italic:YES];
    self.btnHealth.on = g_pubgEspHealth;
    self.btnHealth.onToggle = ^(BOOL isOn) {
        g_pubgEspHealth = isOn;
        [NSUserDefaults.standardUserDefaults setBool:isOn forKey:@"pubg_health"];
    };

    // Row 1 (y = 54): [ DRAW BONE ], [ DRAW SRADAR ], [ PLAYER NAME ], [ PLAYER DIS ]
    self.btnBone = [self btn:@"DRAW BONE" frame:CGRectMake(x0, 54, colW, btnH) inView:self.scroll italic:YES];
    self.btnBone.on = g_pubgEspSkeleton;
    self.btnBone.onToggle = ^(BOOL isOn) {
        g_pubgEspSkeleton = isOn;
        [NSUserDefaults.standardUserDefaults setBool:isOn forKey:@"pubg_skeleton"];
    };

    self.btnRadar = [self btn:@"DRAW SRADAR" frame:CGRectMake(x1, 54, colW, btnH) inView:self.scroll italic:YES];
    self.btnRadar.on = g_pubgEspRadar;
    self.btnRadar.onToggle = ^(BOOL isOn) {
        g_pubgEspRadar = isOn;
        [NSUserDefaults.standardUserDefaults setBool:isOn forKey:@"pubg_radar"];
        weakSelf.dragMap.hidden = !isOn;
    };

    self.btnName = [self btn:@"PLAYER NAME" frame:CGRectMake(x2, 54, colW, btnH) inView:self.scroll italic:YES];
    self.btnName.on = g_pubgEspName;
    self.btnName.onToggle = ^(BOOL isOn) {
        g_pubgEspName = isOn;
        [NSUserDefaults.standardUserDefaults setBool:isOn forKey:@"pubg_name"];
    };

    self.btnDist = [self btn:@"PLAYER DIS" frame:CGRectMake(x3, 54, colW, btnH) inView:self.scroll italic:YES];
    self.btnDist.on = g_pubgEspDist;
    self.btnDist.onToggle = ^(BOOL isOn) {
        g_pubgEspDist = isOn;
        [NSUserDefaults.standardUserDefaults setBool:isOn forKey:@"pubg_dist"];
    };

    // Row 2 (y = 80): [ 3D BOX ], [ DRAW ARROW ], [ PLAYER TEAM ], [ PLAYER FLAG ]
    self.btn3D = [self btn:@"3D BOX" frame:CGRectMake(x0, 80, colW, btnH) inView:self.scroll italic:YES];
    self.btn3D.on = g_pubgEspBox;
    self.btn3D.onToggle = ^(BOOL isOn) {
        g_pubgEspBox = isOn;
        [NSUserDefaults.standardUserDefaults setBool:isOn forKey:@"pubg_box"];
    };

    self.btnArrow = [self btn:@"DRAW ARROW" frame:CGRectMake(x1, 80, colW, btnH) inView:self.scroll italic:YES];
    self.btnArrow.on = g_pubgEspArrow;
    self.btnArrow.onToggle = ^(BOOL isOn) {
        g_pubgEspArrow = isOn;
        [NSUserDefaults.standardUserDefaults setBool:isOn forKey:@"pubg_arrow"];
    };

    self.btnTeam = [self btn:@"PLAYER TEAM" frame:CGRectMake(x2, 80, colW, btnH) inView:self.scroll italic:YES];
    self.btnTeam.on = g_pubgEspTeam;
    self.btnTeam.onToggle = ^(BOOL isOn) {
        g_pubgEspTeam = isOn;
        [NSUserDefaults.standardUserDefaults setBool:isOn forKey:@"pubg_team"];
    };

    self.btnFlag = [self btn:@"PLAYER FLAG" frame:CGRectMake(x3, 80, colW, btnH) inView:self.scroll italic:YES];
    self.btnFlag.on = g_pubgEspFlag;
    self.btnFlag.onToggle = ^(BOOL isOn) {
        g_pubgEspFlag = isOn;
        [NSUserDefaults.standardUserDefaults setBool:isOn forKey:@"pubg_flag"];
    };

    // Distance Slider (y = 108): [ 500 ]  DISTANCE
    self.sliderEspDist = [[MenuSliderRow alloc] initWithFrame:CGRectMake(15, 108, 610, 24) min:50 max:500 value:g_dspubgMaxDistance name:@"DISTANCE"];
    self.sliderEspDist.displayMode = MenuSliderDisplayRaw;
    self.sliderEspDist.onChange = ^(float v) {
        g_dspubgMaxDistance = v;
        [NSUserDefaults.standardUserDefaults setFloat:v forKey:@"pubg_zoom_dist"];
    };
    [self.scroll addSubview:self.sliderEspDist];

    // =========================================================================
    // SECTION 2: > MATERIAL PANEL
    // =========================================================================
    [self addSectionHeader:@"MATERIAL PANEL" atY:140.0];

    // Row 0 (y = 162): [ ENABLE ], [ VEHICLE ], [ GRENADE WARN ], [ LOOT BOX ]
    self.btnMatEnable = [self btn:@"ENABLE" frame:CGRectMake(x0, 162, colW, btnH) inView:self.scroll italic:YES];
    self.btnMatEnable.on = (g_pubgEspWeapon || g_pubgEspArmor || g_pubgEspScope);
    self.btnMatEnable.onToggle = ^(BOOL isOn) {
        weakSelf.btnVeh.on = isOn;
        weakSelf.btnGrenade.on = isOn;
        weakSelf.btnLootBox.on = isOn;
        weakSelf.btnFlareGun.on = isOn;
        weakSelf.btnAirdrop.on = isOn;
        weakSelf.btnAccessory.on = isOn;
        weakSelf.btnDrug.on = isOn;
        weakSelf.btnVal.on = isOn;
        weakSelf.btnAkm.on = isOn;
        weakSelf.btnM416.on = isOn;
        weakSelf.btnScarl.on = isOn;

        g_pubgEspWeapon = isOn;
        g_pubgEspArmor = isOn;
        g_pubgEspScope = isOn;
        g_pubgEspBag = isOn;
        g_pubgEspCrate = isOn;
        g_pubgEspVehicle = isOn;
        g_pubgEspVehicleHp = isOn;
        g_pubgEspVehicleFuel = isOn;
        g_pubgEspGrenade = isOn;
        g_pubgEspFlareGun = isOn;
        g_pubgEspDrug = isOn;
        g_pubgEspVal = isOn;
        g_pubgEspAkm = isOn;
        g_pubgEspM416 = isOn;
        g_pubgEspScarl = isOn;

        NSUserDefaults *def = NSUserDefaults.standardUserDefaults;
        [def setBool:isOn forKey:@"pubg_weapon"];
        [def setBool:isOn forKey:@"pubg_armor"];
        [def setBool:isOn forKey:@"pubg_scope"];
        [def setBool:isOn forKey:@"pubg_bag"];
        [def setBool:isOn forKey:@"pubg_crate"];
        [def setBool:isOn forKey:@"pubg_vehicle"];
        [def setBool:isOn forKey:@"pubg_grenade"];
        [def setBool:isOn forKey:@"pubg_flaregun"];
        [def setBool:isOn forKey:@"pubg_drug"];
        [def setBool:isOn forKey:@"pubg_val"];
        [def setBool:isOn forKey:@"pubg_akm"];
        [def setBool:isOn forKey:@"pubg_m416"];
        [def setBool:isOn forKey:@"pubg_scarl"];
    };

    self.btnVeh = [self btn:@"VEHICLE" frame:CGRectMake(x1, 162, colW, btnH) inView:self.scroll italic:YES];
    self.btnVeh.on = g_pubgEspVehicle;
    self.btnVeh.onToggle = ^(BOOL isOn) {
        g_pubgEspVehicle = isOn;
        g_pubgEspVehicleHp = isOn;
        g_pubgEspVehicleFuel = isOn;
        [NSUserDefaults.standardUserDefaults setBool:isOn forKey:@"pubg_vehicle"];
    };

    self.btnGrenade = [self btn:@"GRENADE WARN" frame:CGRectMake(x2, 162, colW, btnH) inView:self.scroll italic:YES];
    self.btnGrenade.on = g_pubgEspGrenade;
    self.btnGrenade.onToggle = ^(BOOL isOn) {
        g_pubgEspGrenade = isOn;
        [NSUserDefaults.standardUserDefaults setBool:isOn forKey:@"pubg_grenade"];
    };

    self.btnLootBox = [self btn:@"LOOT BOX" frame:CGRectMake(x3, 162, colW, btnH) inView:self.scroll italic:YES];
    self.btnLootBox.on = g_pubgEspCrate;
    self.btnLootBox.onToggle = ^(BOOL isOn) {
        g_pubgEspCrate = isOn;
        [NSUserDefaults.standardUserDefaults setBool:isOn forKey:@"pubg_crate"];
    };

    // Row 1 (y = 188): [ FLARE GUN ], [ AIRDROP ], [ ACCESSORY ], [ DRUG ]
    self.btnFlareGun = [self btn:@"FLARE GUN" frame:CGRectMake(x0, 188, colW, btnH) inView:self.scroll italic:YES];
    self.btnFlareGun.on = g_pubgEspFlareGun;
    self.btnFlareGun.onToggle = ^(BOOL isOn) {
        g_pubgEspFlareGun = isOn;
        [NSUserDefaults.standardUserDefaults setBool:isOn forKey:@"pubg_flaregun"];
    };

    self.btnAirdrop = [self btn:@"AIRDROP" frame:CGRectMake(x1, 188, colW, btnH) inView:self.scroll italic:YES];
    self.btnAirdrop.on = g_pubgEspCrate;
    self.btnAirdrop.onToggle = ^(BOOL isOn) {
        g_pubgEspCrate = isOn;
        [NSUserDefaults.standardUserDefaults setBool:isOn forKey:@"pubg_crate"];
    };

    self.btnAccessory = [self btn:@"ACCESSORY" frame:CGRectMake(x2, 188, colW, btnH) inView:self.scroll italic:YES];
    self.btnAccessory.on = g_pubgEspScope;
    self.btnAccessory.onToggle = ^(BOOL isOn) {
        g_pubgEspScope = isOn;
        [NSUserDefaults.standardUserDefaults setBool:isOn forKey:@"pubg_scope"];
    };

    self.btnDrug = [self btn:@"DRUG" frame:CGRectMake(x3, 188, colW, btnH) inView:self.scroll italic:YES];
    self.btnDrug.on = g_pubgEspDrug;
    self.btnDrug.onToggle = ^(BOOL isOn) {
        g_pubgEspDrug = isOn;
        [NSUserDefaults.standardUserDefaults setBool:isOn forKey:@"pubg_drug"];
    };

    // Thin yellow separator line (y = 217)
    UIView *sep = [[UIView alloc] initWithFrame:CGRectMake(15, 217, 610, 1.0)];
    sep.backgroundColor = UIColor.yellowColor;
    [self.scroll addSubview:sep];

    // Row 2 (y = 224): [ VAL ], [ AKM ], [ M416 ], [ SCAR-L ]
    self.btnVal = [self btn:@"VAL" frame:CGRectMake(x0, 224, colW, btnH) inView:self.scroll italic:YES];
    self.btnVal.on = g_pubgEspVal;
    self.btnVal.onToggle = ^(BOOL isOn) {
        g_pubgEspVal = isOn;
        [NSUserDefaults.standardUserDefaults setBool:isOn forKey:@"pubg_val"];
    };

    self.btnAkm = [self btn:@"AKM" frame:CGRectMake(x1, 224, colW, btnH) inView:self.scroll italic:YES];
    self.btnAkm.on = g_pubgEspAkm;
    self.btnAkm.onToggle = ^(BOOL isOn) {
        g_pubgEspAkm = isOn;
        [NSUserDefaults.standardUserDefaults setBool:isOn forKey:@"pubg_akm"];
    };

    self.btnM416 = [self btn:@"M416" frame:CGRectMake(x2, 224, colW, btnH) inView:self.scroll italic:YES];
    self.btnM416.on = g_pubgEspM416;
    self.btnM416.onToggle = ^(BOOL isOn) {
        g_pubgEspM416 = isOn;
        [NSUserDefaults.standardUserDefaults setBool:isOn forKey:@"pubg_m416"];
    };

    self.btnScarl = [self btn:@"SCAR-L" frame:CGRectMake(x3, 224, colW, btnH) inView:self.scroll italic:YES];
    self.btnScarl.on = g_pubgEspScarl;
    self.btnScarl.onToggle = ^(BOOL isOn) {
        g_pubgEspScarl = isOn;
        [NSUserDefaults.standardUserDefaults setBool:isOn forKey:@"pubg_scarl"];
    };

    // Material Distance Slider (y = 252): [ 300 ]  DISTANCE
    self.sliderItemDist = [[MenuSliderRow alloc] initWithFrame:CGRectMake(15, 252, 610, 24) min:50 max:500 value:g_pubgItemMaxDistance name:@"DISTANCE"];
    self.sliderItemDist.displayMode = MenuSliderDisplayRaw;
    self.sliderItemDist.onChange = ^(float v) {
        g_pubgItemMaxDistance = v;
        [NSUserDefaults.standardUserDefaults setFloat:v forKey:@"pubg_item_dist"];
    };
    [self.scroll addSubview:self.sliderItemDist];

    self.scroll.contentSize = CGSizeMake(kMadnessPanelW, 290);
}

#pragma mark - Reset to Defaults

- (void)resetToDefaults {
    [self.haptic impactOccurred];
    g_pubgEspBox = YES;
    g_pubgEspLine = YES;
    g_pubgEspSkeleton = YES;
    g_pubgEspName = YES;
    g_pubgEspDist = YES;
    g_pubgEspHealth = YES;
    g_pubgEspBot = YES;
    g_pubgEspEnemyNumber = YES;
    g_pubgEspRadar = YES;
    g_pubgEspTeam = YES;
    g_pubgEspFlag = YES;
    g_pubgEspArrow = YES;
    g_pubgEspGrenade = YES;
    g_dspubgMaxDistance = 400.0f;

    g_pubgEspWeapon = YES;
    g_pubgEspArmor = YES;
    g_pubgEspBag = YES;
    g_pubgEspScope = YES;
    g_pubgEspCrate = YES;
    g_pubgEspFlareGun = YES;
    g_pubgEspDrug = YES;
    g_pubgEspVal = YES;
    g_pubgEspAkm = YES;
    g_pubgEspM416 = YES;
    g_pubgEspScarl = YES;
    g_pubgItemMaxDistance = 150.0f;
    g_pubgEspVehicle = YES;
    g_pubgEspVehicleHp = YES;
    g_pubgEspVehicleFuel = YES;

    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    [defaults setBool:YES forKey:@"pubg_box"];
    [defaults setBool:YES forKey:@"pubg_line"];
    [defaults setBool:YES forKey:@"pubg_skeleton"];
    [defaults setBool:YES forKey:@"pubg_name"];
    [defaults setBool:YES forKey:@"pubg_dist"];
    [defaults setBool:YES forKey:@"pubg_health"];
    [defaults setBool:YES forKey:@"pubg_bot"];
    [defaults setBool:YES forKey:@"pubg_enemy_num"];
    [defaults setBool:YES forKey:@"pubg_radar"];
    [defaults setBool:YES forKey:@"pubg_team"];
    [defaults setBool:YES forKey:@"pubg_flag"];
    [defaults setBool:YES forKey:@"pubg_arrow"];
    [defaults setBool:YES forKey:@"pubg_grenade"];
    [defaults setFloat:400.0f forKey:@"pubg_zoom_dist"];
    [defaults setBool:YES forKey:@"pubg_weapon"];
    [defaults setBool:YES forKey:@"pubg_armor"];
    [defaults setBool:YES forKey:@"pubg_bag"];
    [defaults setBool:YES forKey:@"pubg_scope"];
    [defaults setBool:YES forKey:@"pubg_crate"];
    [defaults setBool:YES forKey:@"pubg_flaregun"];
    [defaults setBool:YES forKey:@"pubg_drug"];
    [defaults setBool:YES forKey:@"pubg_val"];
    [defaults setBool:YES forKey:@"pubg_akm"];
    [defaults setBool:YES forKey:@"pubg_m416"];
    [defaults setBool:YES forKey:@"pubg_scarl"];
    [defaults setFloat:150.0f forKey:@"pubg_item_dist"];
    [defaults setBool:YES forKey:@"pubg_vehicle"];
    [defaults setBool:YES forKey:@"pubg_vehicle_hp"];
    [defaults setBool:YES forKey:@"pubg_vehicle_fuel"];

    self.btnEspEnable.on = YES;
    self.btnLine.on = YES;
    self.btnEnemyNum.on = YES;
    self.btnHealth.on = YES;
    self.btnBone.on = YES;
    self.btnRadar.on = YES;
    self.btnName.on = YES;
    self.btnDist.on = YES;
    self.btn3D.on = YES;
    self.btnArrow.on = YES;
    self.btnTeam.on = YES;
    self.btnFlag.on = YES;
    [self.sliderEspDist setSliderValue:400.0f];

    self.btnMatEnable.on = YES;
    self.btnVeh.on = YES;
    self.btnGrenade.on = YES;
    self.btnLootBox.on = YES;
    self.btnFlareGun.on = YES;
    self.btnAirdrop.on = YES;
    self.btnAccessory.on = YES;
    self.btnDrug.on = YES;
    self.btnVal.on = YES;
    self.btnAkm.on = YES;
    self.btnM416.on = YES;
    self.btnScarl.on = YES;
    [self.sliderItemDist setSliderValue:150.0f];
}

#pragma mark - Open / close (controllview order)

- (void)controllview {
    [self.haptic impactOccurred];
    self.asize = YES;
    self.isShowMenu = YES;
    g_hostedMenuExpanded = YES;

    CGFloat maxW = self.superview ? self.superview.bounds.size.width : [UIScreen mainScreen].bounds.size.width;
    CGFloat maxH = self.superview ? self.superview.bounds.size.height : [UIScreen mainScreen].bounds.size.height;
    if (maxW < maxH) { CGFloat tmp = maxW; maxW = maxH; maxH = tmp; }
    CGFloat targetW = MIN(kMadnessPanelW, maxW - 20.0f);
    CGFloat targetH = MIN(kMadnessPanelH, maxH - 20.0f);

    CGRect pf = self.panel.frame;
    if (pf.origin.x + targetW > maxW) pf.origin.x = MAX(10.0f, maxW - targetW - 10.0f);
    if (pf.origin.y + targetH > maxH) pf.origin.y = MAX(10.0f, maxH - targetH - 10.0f);

    self.panel.backgroundColor = [UIColor colorWithRed:0 green:0 blue:0 alpha:0.82];
    self.panel.layer.borderColor = [UIColor colorWithWhite:0.35 alpha:0.8].CGColor;
    self.panel.layer.borderWidth = 0.5;
    self.panel.layer.cornerRadius = 12.0;

    [self.handle removeGestureRecognizer:self.handleTap];
    self.handleTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(controllview1)];
    [self.handle addGestureRecognizer:self.handleTap];

    self.handleGlyph.frame = CGRectMake(0, 0, 26, 26);
    self.handleGlyph.text = @"V";
    self.handleGlyph.font = [UIFont boldSystemFontOfSize:14.0];

    self.titleBox.frame = CGRectMake(38, 3, targetW - 46, 26);
    self.clockLabel.hidden = NO;
    self.batteryLabel.hidden = NO;
    self.sloganLabel.hidden = NO;
    self.scroll.hidden = NO;

    self.panel.frame = CGRectMake(pf.origin.x, pf.origin.y, targetW, targetH);
    self.scroll.frame = CGRectMake(0, 54, targetW, targetH - 54);
}

- (void)controllview1 {
    [self.haptic impactOccurred];
    self.asize = NO;
    self.isShowMenu = NO;
    g_hostedMenuExpanded = NO;

    CGRect pf = self.panel.frame;
    self.panel.frame = CGRectMake(pf.origin.x, pf.origin.y, 210, 32);
    self.panel.backgroundColor = UIColor.clearColor;
    self.panel.layer.borderWidth = 0.0;
    self.scroll.hidden = YES;
    self.clockLabel.hidden = YES;
    self.batteryLabel.hidden = YES;
    self.sloganLabel.hidden = YES;

    [self.handle removeGestureRecognizer:self.handleTap];
    self.handleTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(controllview)];
    [self.handle addGestureRecognizer:self.handleTap];

    self.handleGlyph.frame = CGRectMake(0, 0, 26, 26);
    self.handleGlyph.text = @"⋗";
    self.handleGlyph.font = [UIFont boldSystemFontOfSize:22.0];
    self.titleBox.frame = CGRectMake(38, 3, 160, 26);
}

- (void)handleTapped:(UIButton *)sender {
    if (self.asize) [self controllview1]; else [self controllview];
}

- (void)handleLongPress:(UILongPressGestureRecognizer *)gr {
    if (gr.state != UIGestureRecognizerStateBegan) return;
    if (self.asize) [self controllview1]; else [self controllview];
}

- (void)wasDragged:(UIButton *)sender withEvent:(UIEvent *)event {
    UITouch *t = [[event touchesForView:sender] anyObject];
    if (!t) return;
    UIView *superView = sender.superview ?: self;
    CGPoint prev = [t previousLocationInView:superView];
    CGPoint loc  = [t locationInView:superView];
    CGFloat dx = loc.x - prev.x;
    CGFloat dy = loc.y - prev.y;
    CGPoint c = sender.center;
    CGPoint newCenter = CGPointMake(c.x + dx, c.y + dy);

    CGFloat halfW = sender.bounds.size.width * 0.5;
    CGFloat halfH = sender.bounds.size.height * 0.5;
    CGFloat maxW = superView.bounds.size.width;
    CGFloat maxH = superView.bounds.size.height;
    if (maxW > 100 && maxH > 100) {
        newCenter.x = MIN(MAX(newCenter.x, halfW), maxW - halfW);
        newCenter.y = MIN(MAX(newCenter.y, halfH), maxH - halfH);
    }
    sender.center = newCenter;

    [NSUserDefaults.standardUserDefaults setDouble:newCenter.x forKey:@"madness_menu_x"];
    [NSUserDefaults.standardUserDefaults setDouble:newCenter.y forKey:@"madness_menu_y"];
}

- (void)wasDraggedm:(UIButton *)sender withEventm:(UIEvent *)event {
    UITouch *t = [[event touchesForView:sender] anyObject];
    if (!t) return;
    UIView *superView = sender.superview ?: self;
    CGPoint prev = [t previousLocationInView:superView];
    CGPoint loc  = [t locationInView:superView];
    CGFloat dx = loc.x - prev.x;
    CGFloat dy = loc.y - prev.y;
    CGPoint c = sender.center;
    CGPoint newCenter = CGPointMake(c.x + dx, c.y + dy);

    CGFloat halfW = sender.bounds.size.width * 0.5;
    CGFloat halfH = sender.bounds.size.height * 0.5;
    CGFloat maxW = superView.bounds.size.width;
    CGFloat maxH = superView.bounds.size.height;
    if (maxW > 100 && maxH > 100) {
        newCenter.x = MIN(MAX(newCenter.x, halfW), maxW - halfW);
        newCenter.y = MIN(MAX(newCenter.y, halfH), maxH - halfH);
    }
    sender.center = newCenter;

    [NSUserDefaults.standardUserDefaults setDouble:newCenter.x forKey:@"madness_radar_x"];
    [NSUserDefaults.standardUserDefaults setDouble:newCenter.y forKey:@"madness_radar_y"];
}

#pragma mark - Preview hooks

- (void)previewResetUIState {
    [self resetToDefaults];
}

- (void)previewOpen { [self controllview]; }
- (void)previewClose { [self controllview1]; }
- (void)previewSelectTab:(NSUInteger)index { (void)index; }
- (void)previewLongPressToggle {
    if (self.asize) [self controllview1]; else [self controllview];
}
- (void)previewNudgePanel:(CGPoint)delta {
    CGPoint c = self.panel.center;
    self.panel.center = CGPointMake(c.x + delta.x, c.y + delta.y);
}
- (UIView *)menuPanel { return self.panel; }
- (id)previewPageSwitch { return nil; }
- (UIScrollView *)previewScroll { return self.scroll; }
- (void)previewSetScrollOffset:(CGPoint)o { self.scroll.contentOffset = o; }
- (void)previewToggleFirstButton {
    [self.btnEspEnable sendActionsForControlEvents:UIControlEventTouchUpInside];
}
- (void)previewNudgeSlider {
    [self.sliderEspDist setSliderValue:250];
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    if (fabs(scrollView.contentOffset.x) > 0.05) {
        scrollView.contentOffset = CGPointMake(0, scrollView.contentOffset.y);
    }
}

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    /* Touches on empty overlay must reach the app underneath */
    if (hit == self) return nil;
    return hit;
}

+ (instancetype)attachToWindow:(UIWindow *)window {
    for (UIView *sub in window.subviews) {
        if ([sub isKindOfClass:[MadnessMenuView class]]) return (MadnessMenuView *)sub;
    }
    MadnessMenuView *v = [[MadnessMenuView alloc] initWithFrame:window.bounds];
    v.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [window addSubview:v];
    return v;
}
- (void)loadMenu {}

@end
