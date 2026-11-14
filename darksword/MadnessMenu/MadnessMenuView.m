#import "MadnessMenuView.h"
#import "MADSW.h"
#import "MenuWidgets.h"
#import "MadnessMascotData.h"
#import <QuartzCore/QuartzCore.h>

@interface MadnessMenuView () <UIScrollViewDelegate>
@property (nonatomic, strong) UIButton *panel;
@property (nonatomic, strong) UIView *titleBox;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UIImageView *mascotView;
@property (nonatomic, strong) UIView *tabBarHost;
@property (nonatomic, strong) MADSW *pageSwitch;
@property (nonatomic, strong) MADSW *socialSwitch;
@property (nonatomic, strong) UIScrollView *scroll;
@property (nonatomic, strong) UILabel *clockLabel;
@property (nonatomic, strong) UILabel *batteryLabel;
@property (nonatomic, strong) UILabel *moreFutureLabel;
@property (nonatomic, strong) UIButton *handle;
@property (nonatomic, strong) UILabel *handleGlyph;
@property (nonatomic, strong) UITapGestureRecognizer *handleTap;
@property (nonatomic, strong) UILongPressGestureRecognizer *handleLong;
@property (nonatomic, strong) UIView *rightColumnHost;
@property (nonatomic, strong) NSDateFormatter *ttime;
@property (nonatomic, strong) NSTimer *clockTimer;
@property (nonatomic, strong) CAShapeLayer *triangleMaskLayer;
@property (nonatomic, strong) CAShapeLayer *radacircle;
@property (nonatomic, strong) CAShapeLayer *radacircle2;
@property (nonatomic, strong) CAShapeLayer *radacircle3;
@property (nonatomic, strong) CAShapeLayer *ViewLine;
@property (nonatomic, strong) UIButton *dragMap;
@property (nonatomic) NSInteger cosview;
@property (nonatomic) BOOL asize;
@property (nonatomic, strong) UIImpactFeedbackGenerator *haptic;

// Live widgets for DarkPubg ESP state
@property (nonatomic, strong) MenuToggleButton *btnBox;
@property (nonatomic, strong) MenuToggleButton *btnLine;
@property (nonatomic, strong) MenuToggleButton *btnBone;
@property (nonatomic, strong) MenuToggleButton *btnInfo;
@property (nonatomic, strong) MenuToggleButton *btn3D;
@property (nonatomic, strong) MenuToggleButton *btnArrow;
@property (nonatomic, strong) MenuToggleButton *btnRadar;
@property (nonatomic, strong) MenuSliderRow *sliderEspDist;

@property (nonatomic, strong) MenuToggleButton *btnVeh;
@property (nonatomic, strong) MenuToggleButton *btnWeapon;
@property (nonatomic, strong) MenuToggleButton *btnArmor;
@property (nonatomic, strong) MenuToggleButton *btnScope;
@property (nonatomic, strong) MenuToggleButton *btnBag;
@property (nonatomic, strong) MenuToggleButton *btnDrop;
@property (nonatomic, strong) MenuToggleButton *btnLootBox;
@property (nonatomic, strong) MenuToggleButton *btnGrenade;
@property (nonatomic, strong) MenuSliderRow *sliderItemDist;

@property (nonatomic, strong) MenuSliderRow *sliderThickness;
@end

@implementation MadnessMenuView

- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    self.backgroundColor = UIColor.clearColor;
    self.userInteractionEnabled = YES;
    self.haptic = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
    self.cosview = 0;

    // Load persisted settings
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    if ([defaults objectForKey:@"pubg_box"] != nil) g_pubgEspBox = [defaults boolForKey:@"pubg_box"];
    if ([defaults objectForKey:@"pubg_skeleton"] != nil) g_pubgEspSkeleton = [defaults boolForKey:@"pubg_skeleton"];
    if ([defaults objectForKey:@"pubg_line"] != nil) g_pubgEspLine = [defaults boolForKey:@"pubg_line"];
    if ([defaults objectForKey:@"pubg_health"] != nil) g_pubgEspHealth = [defaults boolForKey:@"pubg_health"];
    if ([defaults objectForKey:@"pubg_name"] != nil) g_pubgEspName = [defaults boolForKey:@"pubg_name"];
    if ([defaults objectForKey:@"pubg_dist"] != nil) g_pubgEspDist = [defaults boolForKey:@"pubg_dist"];
    if ([defaults objectForKey:@"pubg_bot"] != nil) g_pubgEspBot = [defaults boolForKey:@"pubg_bot"];
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
    if ([defaults objectForKey:@"pubg_zoom_dist"] != nil) g_dspubgMaxDistance = [defaults floatForKey:@"pubg_zoom_dist"];
    if ([defaults objectForKey:@"pubg_item_dist"] != nil) g_pubgItemMaxDistance = [defaults floatForKey:@"pubg_item_dist"];
    if ([defaults objectForKey:@"pubg_thickness"] != nil) {
        g_pubgEspThickness = [defaults floatForKey:@"pubg_thickness"];
        if (g_pubgEspThickness < 0.8f) g_pubgEspThickness = 0.8f;
        if (g_pubgEspThickness > 3.5f) g_pubgEspThickness = 3.5f;
    }

    [self buildChrome];
    [self buildRadarLayersHidden];
    [self buildLeftColumn];
    [self buildRightColumn];
    [self startClock];
    return self;
}

#pragma mark - Helpers

- (UIView *)cardAt:(CGRect)f {
    UIView *c = [[UIView alloc] initWithFrame:f];
    c.backgroundColor = MADCardFill();
    c.layer.cornerRadius = 10.0;
    return c;
}
- (UIView *)cardAt5:(CGRect)f {
    UIView *c = [[UIView alloc] initWithFrame:f];
    c.backgroundColor = MADCardFill();
    c.layer.cornerRadius = 5.0;
    return c;
}
- (MenuToggleButton *)btn:(NSString *)t frame:(CGRect)f inView:(UIView *)p italic:(BOOL)it {
    MenuToggleButton *b = [[MenuToggleButton alloc] initWithTitle:t frame:f italic:it];
    [p addSubview:b];
    return b;
}
- (MADSW *)madsw:(NSArray *)strings frame:(CGRect)f parent:(UIView *)p {
    MADSW *s = [[MADSW alloc] initWithStringsArray:strings];
    s.frame = f; s.cornerRadius = 5.0;
    s.backgroundColor = UIColor.clearColor;
    s.sliderColor = UIColor.yellowColor;
    s.labelTextColorInsideSlider = UIColor.blackColor;
    s.labelTextColorOutsideSlider = UIColor.whiteColor;
    s.font = [UIFont boldSystemFontOfSize:10.0];
    __weak typeof(self) weakSelf = self;
    [s setPressedHandler:^(NSUInteger idx) {
        [weakSelf.haptic impactOccurred];
        NSLog(@"[MadnessMenu] MADSW %@ -> %lu", strings, (unsigned long)idx);
    }];
    [p addSubview:s];
    return s;
}
- (void)addHeader:(NSString *)t at:(CGPoint)o {
    [self.scroll addSubview:[[MenuSectionHeader alloc] initWithTitle:t origin:o]];
}

#pragma mark - Chrome

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
            startY = y - 15.0;
        }
    }

    self.panel = [UIButton buttonWithType:UIButtonTypeCustom];
    self.panel.frame = CGRectMake(startX, startY, 210, 30);
    self.panel.backgroundColor = UIColor.clearColor;
    self.panel.layer.cornerRadius = 5.0;
    self.panel.clipsToBounds = YES;
    [self.panel addTarget:self action:@selector(wasDragged:withEvent:) forControlEvents:UIControlEventTouchDragInside | UIControlEventTouchDragOutside];
    [self addSubview:self.panel];

    self.titleBox = [[UIView alloc] initWithFrame:CGRectMake(40, 5, 105, 25)];
    self.titleBox.backgroundColor = MADBlack50();
    self.titleBox.layer.cornerRadius = 5.0;
    self.titleBox.clipsToBounds = YES;
    self.titleBox.userInteractionEnabled = NO;
    [self.panel addSubview:self.titleBox];

    /* labelobgos (5,3.5,70,18): looadmenu boldSystem 12; visual/FACTS last-writer HeavyItalic */
    self.titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(5, 3.5, 70, 18)];
    self.titleLabel.text = @"MADNESS";
    self.titleLabel.textColor = UIColor.yellowColor;
    self.titleLabel.font = [UIFont fontWithName:@"AvenirNextCondensed-HeavyItalic" size:12.0]
                           ?: [UIFont boldSystemFontOfSize:12.0];
    self.titleLabel.textAlignment = NSTextAlignmentLeft;
    self.titleLabel.lineBreakMode = NSLineBreakByClipping;
    self.titleLabel.numberOfLines = 1;
    self.titleLabel.userInteractionEnabled = NO;
    [self.titleBox addSubview:self.titleLabel];

    /* Mascot icon after title — MadnessMascotData */
    self.mascotView = [[UIImageView alloc] initWithFrame:CGRectMake(72, 1.5, 22, 22)];
    self.mascotView.image = MadnessMascotImage();
    self.mascotView.contentMode = UIViewContentModeScaleAspectFit;
    self.mascotView.userInteractionEnabled = NO;
    [self.titleBox addSubview:self.mascotView];

    self.tabBarHost = [[UIView alloc] initWithFrame:CGRectMake(135, 7.5, 105, 20)];
    self.tabBarHost.backgroundColor = MADBlack50();
    self.tabBarHost.layer.cornerRadius = 7.5;
    self.tabBarHost.clipsToBounds = YES;
    self.tabBarHost.hidden = YES;
    [self.panel addSubview:self.tabBarHost];

    self.pageSwitch = [[MADSW alloc] initWithStringsArray:@[@"E̷S̷P̷", @"O̷T̷H̷E̷R̷"]];
    self.pageSwitch.frame = CGRectMake(0, 0, 100, 20);
    self.pageSwitch.cornerRadius = 5.0;
    self.pageSwitch.backgroundColor = UIColor.clearColor;
    self.pageSwitch.sliderColor = UIColor.yellowColor;
    self.pageSwitch.labelTextColorInsideSlider = UIColor.blackColor;
    self.pageSwitch.labelTextColorOutsideSlider = UIColor.whiteColor;
    self.pageSwitch.font = [UIFont boldSystemFontOfSize:10.0];
    __weak typeof(self) weakSelf = self;
    [self.pageSwitch setPressedHandler:^(NSUInteger index) { [weakSelf applyTabSwitchToIndex:index]; }];
    [self.tabBarHost addSubview:self.pageSwitch];

    self.socialSwitch = [[MADSW alloc] initWithStringsArray:@[@"CONTACT->", @"@LuBaiUwU", @"MADNESS-CHANNEL"]];
    self.socialSwitch.frame = CGRectMake(120, 0, 230, 20);
    self.socialSwitch.cornerRadius = 5.0;
    self.socialSwitch.backgroundColor = UIColor.clearColor;
    self.socialSwitch.sliderColor = UIColor.yellowColor;
    self.socialSwitch.labelTextColorInsideSlider = UIColor.blackColor;
    self.socialSwitch.labelTextColorOutsideSlider = UIColor.whiteColor;
    self.socialSwitch.font = [UIFont boldSystemFontOfSize:10.0];
    self.socialSwitch.hidden = YES;
    [self.socialSwitch setPressedHandler:^(NSUInteger index) { NSLog(@"[MadnessMenu] social %lu", (unsigned long)index); }];
    [self.tabBarHost addSubview:self.socialSwitch];

    self.scroll = [[UIScrollView alloc] initWithFrame:CGRectMake(0, 30, 250, 315)];
    self.scroll.contentSize = CGSizeMake(250, 890);
    self.scroll.alwaysBounceHorizontal = NO;
    self.scroll.showsHorizontalScrollIndicator = NO;
    self.scroll.directionalLockEnabled = YES;
    self.scroll.delegate = self;
    self.scroll.backgroundColor = UIColor.clearColor;
    self.scroll.layer.cornerRadius = 10.0;
    self.scroll.layer.borderColor = UIColor.darkGrayColor.CGColor;
    self.scroll.layer.borderWidth = 0.2;
    self.scroll.clipsToBounds = YES;
    self.scroll.hidden = YES;
    self.scroll.showsVerticalScrollIndicator = YES;
    self.scroll.indicatorStyle = UIScrollViewIndicatorStyleWhite;
    [self.panel addSubview:self.scroll];

    self.clockLabel = [[UILabel alloc] initWithFrame:CGRectMake(17.5, 0, 205, 18)];
    self.clockLabel.backgroundColor = UIColor.clearColor;
    self.clockLabel.layer.cornerRadius = 15.0;
    self.clockLabel.layer.masksToBounds = YES;
    self.clockLabel.layer.borderColor = UIColor.darkGrayColor.CGColor;
    self.clockLabel.layer.borderWidth = 0.2;
    self.clockLabel.textColor = UIColor.whiteColor;
    self.clockLabel.font = [UIFont boldSystemFontOfSize:12.0];
    self.clockLabel.textAlignment = NSTextAlignmentCenter;
    self.clockLabel.userInteractionEnabled = NO;
    [self.scroll addSubview:self.clockLabel];

    self.batteryLabel = [[UILabel alloc] initWithFrame:CGRectMake(215, 0, 30, 18)];
    self.batteryLabel.backgroundColor = UIColor.clearColor;
    self.batteryLabel.layer.cornerRadius = 5.0;
    self.batteryLabel.layer.masksToBounds = YES;
    self.batteryLabel.layer.borderColor = UIColor.darkGrayColor.CGColor;
    self.batteryLabel.layer.borderWidth = 0.2;
    self.batteryLabel.textColor = UIColor.yellowColor;
    self.batteryLabel.font = [UIFont boldSystemFontOfSize:12.0];
    self.batteryLabel.userInteractionEnabled = NO;
    [self.scroll addSubview:self.batteryLabel];

    self.moreFutureLabel = [[UILabel alloc] initWithFrame:CGRectMake(255, 0, 235, 18)];
    self.moreFutureLabel.text = @"MORE FUTURE SOON INJOY ;)";
    self.moreFutureLabel.textColor = UIColor.yellowColor;
    self.moreFutureLabel.font = [UIFont boldSystemFontOfSize:11.0];
    self.moreFutureLabel.textAlignment = NSTextAlignmentRight;
    self.moreFutureLabel.hidden = YES;
    [self.scroll addSubview:self.moreFutureLabel];

    /* Handle: cornerRadius 10.0 */
    self.handle = [UIButton buttonWithType:UIButtonTypeCustom];
    self.handle.frame = CGRectMake(5, 5, 25, 25);
    self.handle.backgroundColor = MADBlack50();
    self.handle.layer.cornerRadius = 10.0;
    self.handle.layer.masksToBounds = YES;
    self.handle.layer.borderWidth = 0.8;
    self.handle.layer.borderColor = UIColor.darkGrayColor.CGColor;
    [self.panel addSubview:self.handle];
    self.handleTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(controllview)];
    [self.handle addGestureRecognizer:self.handleTap];
    self.handleLong = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPress:)];
    self.handleLong.minimumPressDuration = 0.5;
    [self.handle addGestureRecognizer:self.handleLong];
    [self.handle addTarget:self action:@selector(handleTapped:) forControlEvents:UIControlEventTouchUpInside];

    self.handleGlyph = [[UILabel alloc] initWithFrame:CGRectMake(6, 0, 15, 18)];
    self.handleGlyph.text = @"⋗";
    self.handleGlyph.font = [UIFont boldSystemFontOfSize:25.0];
    self.handleGlyph.textColor = UIColor.yellowColor;
    self.handleGlyph.textAlignment = NSTextAlignmentCenter;
    self.handleGlyph.userInteractionEnabled = NO;
    self.handleGlyph.backgroundColor = UIColor.clearColor;
    [self.handle addSubview:self.handleGlyph];

    self.ttime = [[NSDateFormatter alloc] init];
    self.ttime.dateFormat = @"yyyy/MM/dd • hh:mm:ss";

    self.rightColumnHost = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 500, 890)];
    self.rightColumnHost.hidden = YES;
    [self.scroll addSubview:self.rightColumnHost];
}

#pragma mark - Radar (hidden)

- (void)buildRadarLayersHidden {
    CGFloat rx = 47, ry = 47;
    UIBezierPath *tri = [UIBezierPath bezierPath];
    [tri moveToPoint:CGPointMake(rx - 5, ry + 5)];
    [tri addLineToPoint:CGPointMake(rx + 5, ry + 5)];
    [tri addLineToPoint:CGPointMake(rx, ry - 5)];
    [tri closePath];
    self.triangleMaskLayer = [CAShapeLayer layer];
    self.triangleMaskLayer.path = tri.CGPath;
    self.triangleMaskLayer.strokeColor = UIColor.greenColor.CGColor;
    self.triangleMaskLayer.fillColor = UIColor.greenColor.CGColor;
    self.triangleMaskLayer.hidden = YES;
    [self.layer addSublayer:self.triangleMaskLayer];

    UIBezierPath *line = [UIBezierPath bezierPath];
    [line moveToPoint:CGPointMake(rx, ry)];
    [line addLineToPoint:CGPointMake(rx + 15, ry + 15)];
    [line moveToPoint:CGPointMake(rx, ry)];
    [line addLineToPoint:CGPointMake(rx + 95 - 15, ry + 15)];
    self.ViewLine = [CAShapeLayer layer];
    self.ViewLine.path = line.CGPath;
    self.ViewLine.strokeColor = [UIColor colorWithRed:0 green:0 blue:0 alpha:0.5].CGColor;
    self.ViewLine.fillColor = [UIColor colorWithRed:0 green:0 blue:0 alpha:0.5].CGColor;
    self.ViewLine.hidden = YES;
    [self.layer addSublayer:self.ViewLine];

    self.radacircle = [CAShapeLayer layer];
    self.radacircle.path = [UIBezierPath bezierPathWithArcCenter:CGPointMake(rx, ry) radius:17 startAngle:0 endAngle:(CGFloat)(2*M_PI) clockwise:YES].CGPath;
    self.radacircle.strokeColor = UIColor.redColor.CGColor;
    self.radacircle.fillColor = UIColor.clearColor.CGColor;
    self.radacircle.hidden = YES;
    [self.layer addSublayer:self.radacircle];

    self.radacircle2 = [CAShapeLayer layer];
    self.radacircle2.path = [UIBezierPath bezierPathWithArcCenter:CGPointMake(rx, ry) radius:32 startAngle:0 endAngle:(CGFloat)(2*M_PI) clockwise:YES].CGPath;
    self.radacircle2.strokeColor = UIColor.orangeColor.CGColor;
    self.radacircle2.fillColor = UIColor.clearColor.CGColor;
    self.radacircle2.hidden = YES;
    [self.layer addSublayer:self.radacircle2];

    self.radacircle3 = [CAShapeLayer layer];
    self.radacircle3.path = [UIBezierPath bezierPathWithArcCenter:CGPointMake(rx, ry) radius:47 startAngle:0 endAngle:(CGFloat)(2*M_PI) clockwise:YES].CGPath;
    self.radacircle3.strokeColor = UIColor.greenColor.CGColor;
    self.radacircle3.fillColor = UIColor.clearColor.CGColor;
    self.radacircle3.hidden = YES;
    [self.layer addSublayer:self.radacircle3];

    self.dragMap = [UIButton buttonWithType:UIButtonTypeCustom];
    self.dragMap.frame = CGRectMake(rx, ry, 95, 95);
    self.dragMap.backgroundColor = UIColor.clearColor;
    self.dragMap.layer.cornerRadius = 47.5;
    self.dragMap.hidden = YES;
    [self.dragMap addTarget:self action:@selector(wasDraggedm:withEventm:) forControlEvents:UIControlEventTouchDragInside];
    [self addSubview:self.dragMap];
}

#pragma mark - Clock

- (void)startClock {
    [UIDevice currentDevice].batteryMonitoringEnabled = YES;
    [self tickClock];
    self.clockTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(tickClock) userInfo:nil repeats:YES];
}
- (void)tickClock {
    NSString *ds = [self.ttime stringFromDate:[NSDate date]];
    self.clockLabel.text = [NSString stringWithFormat:@"  %@  ", ds];
    float lvl = [UIDevice currentDevice].batteryLevel;
    if (lvl < 0) lvl = 1;
    self.batteryLabel.text = [NSString stringWithFormat:@" %0.0f ", lvl * 100.0];
}

#pragma mark - Columns

- (void)buildLeftColumn {
    const CGFloat BH = 18;
    __weak typeof(self) weakSelf = self;

    [self addHeader:@"ESP PANEL" at:CGPointMake(2, 17)];
    UIView *esp = [self cardAt:CGRectMake(5, 45, 240, 175)];
    [self.scroll addSubview:esp];

    self.btnBox = [self btn:@"𝘿𝙍𝘼𝙒 𝙀𝙎𝙋" frame:CGRectMake(5,15,100,BH) inView:esp italic:YES];
    self.btnBox.on = g_pubgEspBox;
    self.btnBox.onToggle = ^(BOOL isOn) {
        g_pubgEspBox = isOn;
        [NSUserDefaults.standardUserDefaults setBool:isOn forKey:@"pubg_box"];
    };

    self.btnLine = [self btn:@"𝘿𝙍𝘼𝙒 𝙇𝙄𝙉𝙀" frame:CGRectMake(135,15,100,BH) inView:esp italic:YES];
    self.btnLine.on = g_pubgEspLine;
    self.btnLine.onToggle = ^(BOOL isOn) {
        g_pubgEspLine = isOn;
        [NSUserDefaults.standardUserDefaults setBool:isOn forKey:@"pubg_line"];
    };

    self.btnBone = [self btn:@"𝘿𝙍𝘼𝙒 𝘽𝙊𝙉𝙀" frame:CGRectMake(5,50,100,BH) inView:esp italic:YES];
    self.btnBone.on = g_pubgEspSkeleton;
    self.btnBone.onToggle = ^(BOOL isOn) {
        g_pubgEspSkeleton = isOn;
        [NSUserDefaults.standardUserDefaults setBool:isOn forKey:@"pubg_skeleton"];
    };

    self.btnInfo = [self btn:@"𝙎𝙃𝙊𝙒 𝙄𝙉𝙁𝙊" frame:CGRectMake(135,50,100,BH) inView:esp italic:YES];
    self.btnInfo.on = g_pubgEspName;
    self.btnInfo.onToggle = ^(BOOL isOn) {
        g_pubgEspName = isOn;
        g_pubgEspDist = isOn;
        [NSUserDefaults.standardUserDefaults setBool:isOn forKey:@"pubg_name"];
        [NSUserDefaults.standardUserDefaults setBool:isOn forKey:@"pubg_dist"];
    };

    self.btn3D = [self btn:@"3𝘿 𝘽𝙊𝙓" frame:CGRectMake(5,85,100,BH) inView:esp italic:YES];
    self.btn3D.on = g_pubgEspHealth;
    self.btn3D.onToggle = ^(BOOL isOn) {
        g_pubgEspHealth = isOn;
        [NSUserDefaults.standardUserDefaults setBool:isOn forKey:@"pubg_health"];
    };

    self.btnArrow = [self btn:@"𝘿𝙍𝘼𝙒 𝘼𝙍𝙍𝙊𝙒" frame:CGRectMake(135,85,100,BH) inView:esp italic:YES];
    self.btnArrow.on = g_pubgEspArrow;
    self.btnArrow.onToggle = ^(BOOL isOn) {
        g_pubgEspArrow = isOn;
        [NSUserDefaults.standardUserDefaults setBool:isOn forKey:@"pubg_arrow"];
    };

    self.btnRadar = [self btn:@"𝘿𝙍𝘼𝙒 𝙎𝙍𝘼𝘿𝘼𝙍" frame:CGRectMake(75,120,100,BH) inView:esp italic:YES];
    self.btnRadar.on = g_pubgEspBot;
    self.btnRadar.onToggle = ^(BOOL isOn) {
        g_pubgEspBot = isOn;
        [NSUserDefaults.standardUserDefaults setBool:isOn forKey:@"pubg_bot"];
    };

    self.sliderEspDist = [[MenuSliderRow alloc] initWithFrame:CGRectMake(5,148,230,22) min:50 max:500 value:g_dspubgMaxDistance name:@"𝘿𝙄𝙎𝙏𝘼𝙉𝘾𝙀"];
    self.sliderEspDist.displayMode = MenuSliderDisplayRaw;
    self.sliderEspDist.onChange = ^(float v) {
        g_dspubgMaxDistance = v;
        [NSUserDefaults.standardUserDefaults setFloat:v forKey:@"pubg_zoom_dist"];
    };
    [esp addSubview:self.sliderEspDist];

    [self addHeader:@"AIMBOT PANEL" at:CGPointMake(2, 222)];
    UIView *aim = [self cardAt:CGRectMake(5, 250, 240, 240)];
    [self.scroll addSubview:aim];
    NSArray *ab = @[
        @[@"𝘼𝙄𝙈𝘽𝙊𝙏", @5, @15], @[@"𝘼𝙄𝙈 𝙎𝘾𝙊𝙋𝙀", @135, @15],
        @[@"𝘼𝙑𝙊𝙄𝘿 𝙆𝙉𝙊𝘾𝙆", @5, @50], @[@"𝘼𝙐𝙏𝙊 𝘼𝙄𝙈", @135, @50],
        @[@"𝘼𝙐𝙏𝙊 𝙁𝙄𝙍𝙀", @5, @85], @[@"𝘽𝙐𝙇𝙇𝙀𝙏 𝙏𝙍", @135, @85],
        @[@"𝙉𝙊 𝙍𝙀𝘾𝙊𝙄𝙇", @5, @120], @[@"𝙉𝙊 𝙎𝙋𝙍𝙀𝘼𝘿", @135, @120],
        @[@"𝙁𝘼𝙎𝙏 𝘽𝙐𝙇𝙇𝙀𝙏", @5, @155], @[@"𝘼𝙐𝙏𝙊 𝘽𝙐𝙇𝙇𝙀𝙏", @135, @155],
    ];
    for (NSArray *b in ab)
        [self btn:b[0] frame:CGRectMake([b[1] floatValue],[b[2] floatValue],100,BH) inView:aim italic:YES];
    [self madsw:@[@"𝘾𝙃𝙀𝙎𝙏 ", @"𝙉𝙀𝘾𝙆 ", @"𝙃𝙀𝘼𝘿", @"𝘼𝙐𝙏𝙊"] frame:CGRectMake(45,190,150,18) parent:aim];
    MenuSliderRow *rad = [[MenuSliderRow alloc] initWithFrame:CGRectMake(5,212,230,22) min:10 max:405 value:150 name:@"𝙍𝘼𝘿𝙄𝙐𝙎"];
    [aim addSubview:rad];

    [self addHeader:@"MATERIAL PANEL" at:CGPointMake(2, 492)];
    UIView *mat = [self cardAt:CGRectMake(5, 520, 240, 255)];
    [self.scroll addSubview:mat];

    MenuToggleButton *bDrawMat = [self btn:@"𝘿𝙍𝘼𝙒 𝙈𝘼𝙏" frame:CGRectMake(5, 15, 100, BH) inView:mat italic:YES];
    bDrawMat.on = g_pubgEspWeapon || g_pubgEspArmor;

    self.btnVeh = [self btn:@"𝙑𝙀𝙃𝙄𝘾𝙇𝙀" frame:CGRectMake(135, 15, 100, BH) inView:mat italic:YES];
    self.btnVeh.on = g_pubgEspVehicle;
    self.btnVeh.onToggle = ^(BOOL isOn) {
        g_pubgEspVehicle = isOn;
        g_pubgEspVehicleHp = isOn;
        g_pubgEspVehicleFuel = isOn;
        [NSUserDefaults.standardUserDefaults setBool:isOn forKey:@"pubg_vehicle"];
        [NSUserDefaults.standardUserDefaults setBool:isOn forKey:@"pubg_vehicle_hp"];
        [NSUserDefaults.standardUserDefaults setBool:isOn forKey:@"pubg_vehicle_fuel"];
    };

    self.btnWeapon = [self btn:@"𝙒𝙀𝘼𝙋𝙊𝙉" frame:CGRectMake(5, 50, 100, BH) inView:mat italic:YES];
    self.btnWeapon.on = g_pubgEspWeapon;
    self.btnWeapon.onToggle = ^(BOOL isOn) {
        g_pubgEspWeapon = isOn;
        [NSUserDefaults.standardUserDefaults setBool:isOn forKey:@"pubg_weapon"];
    };

    self.btnArmor = [self btn:@"𝘼𝙍𝙈𝙊𝙍" frame:CGRectMake(135, 50, 100, BH) inView:mat italic:YES];
    self.btnArmor.on = g_pubgEspArmor;
    self.btnArmor.onToggle = ^(BOOL isOn) {
        g_pubgEspArmor = isOn;
        [NSUserDefaults.standardUserDefaults setBool:isOn forKey:@"pubg_armor"];
    };

    self.btnScope = [self btn:@"𝙎𝘾𝙊𝙋𝙀" frame:CGRectMake(5, 85, 100, BH) inView:mat italic:YES];
    self.btnScope.on = g_pubgEspScope;
    self.btnScope.onToggle = ^(BOOL isOn) {
        g_pubgEspScope = isOn;
        [NSUserDefaults.standardUserDefaults setBool:isOn forKey:@"pubg_scope"];
    };

    self.btnBag = [self btn:@"𝘽𝙐𝙇𝙇𝙀𝙏" frame:CGRectMake(135, 85, 100, BH) inView:mat italic:YES];
    self.btnBag.on = g_pubgEspBag;
    self.btnBag.onToggle = ^(BOOL isOn) {
        g_pubgEspBag = isOn;
        [NSUserDefaults.standardUserDefaults setBool:isOn forKey:@"pubg_bag"];
    };

    [self btn:@"𝘼𝘾𝘾𝙀𝙎𝙎𝙊𝙍𝙔" frame:CGRectMake(5, 120, 100, BH) inView:mat italic:YES];
    [self btn:@"𝘿𝙍𝙐𝙂" frame:CGRectMake(135, 120, 100, BH) inView:mat italic:YES];
    [self btn:@"𝙁𝙇𝘼𝙍𝙀 𝙂𝙐𝙉" frame:CGRectMake(5, 155, 100, BH) inView:mat italic:YES];

    self.btnDrop = [self btn:@"𝘼𝙄𝙍𝘿𝙍𝙊𝙋" frame:CGRectMake(135, 155, 100, BH) inView:mat italic:YES];
    self.btnDrop.on = g_pubgEspCrate;
    self.btnDrop.onToggle = ^(BOOL isOn) {
        g_pubgEspCrate = isOn;
        [NSUserDefaults.standardUserDefaults setBool:isOn forKey:@"pubg_crate"];
    };

    self.btnLootBox = [self btn:@"𝙇𝙊𝙊𝙏 𝘽𝙊𝙓" frame:CGRectMake(5, 190, 100, BH) inView:mat italic:YES];
    self.btnLootBox.on = g_pubgEspCrate;
    self.btnLootBox.onToggle = ^(BOOL isOn) {
        g_pubgEspCrate = isOn;
        [NSUserDefaults.standardUserDefaults setBool:isOn forKey:@"pubg_crate"];
    };

    self.btnGrenade = [self btn:@"𝙂𝙍𝙀𝙉𝘼𝘿𝙀 𝙒𝘼𝙍𝙉" frame:CGRectMake(135, 190, 100, BH) inView:mat italic:YES];
    self.btnGrenade.on = g_pubgEspGrenade;
    self.btnGrenade.onToggle = ^(BOOL isOn) {
        g_pubgEspGrenade = isOn;
        [NSUserDefaults.standardUserDefaults setBool:isOn forKey:@"pubg_grenade"];
    };

    self.sliderItemDist = [[MenuSliderRow alloc] initWithFrame:CGRectMake(5,220,230,22) min:50 max:500 value:g_pubgItemMaxDistance name:@"𝘿𝙄𝙎𝙏𝘼𝙉𝘾𝙀"];
    self.sliderItemDist.displayMode = MenuSliderDisplayRaw;
    self.sliderItemDist.onChange = ^(float v) {
        g_pubgItemMaxDistance = v;
        [NSUserDefaults.standardUserDefaults setFloat:v forKey:@"pubg_item_dist"];
    };
    [mat addSubview:self.sliderItemDist];

    bDrawMat.onToggle = ^(BOOL isOn) {
        weakSelf.btnWeapon.on = isOn;
        weakSelf.btnArmor.on = isOn;
        weakSelf.btnScope.on = isOn;
        weakSelf.btnBag.on = isOn;
        weakSelf.btnDrop.on = isOn;
        weakSelf.btnLootBox.on = isOn;
        g_pubgEspWeapon = isOn;
        g_pubgEspArmor = isOn;
        g_pubgEspScope = isOn;
        g_pubgEspBag = isOn;
        g_pubgEspCrate = isOn;
        NSUserDefaults *def = NSUserDefaults.standardUserDefaults;
        [def setBool:isOn forKey:@"pubg_weapon"];
        [def setBool:isOn forKey:@"pubg_armor"];
        [def setBool:isOn forKey:@"pubg_scope"];
        [def setBool:isOn forKey:@"pubg_bag"];
        [def setBool:isOn forKey:@"pubg_crate"];
    };

    [self addHeader:@"MOVE PANEL" at:CGPointMake(2, 778)];
    UIView *mv = [self cardAt:CGRectMake(5, 805, 240, 80)];
    [self.scroll addSubview:mv];
    [self btn:@"𝙁𝘼𝙎𝙏 𝘾𝘼𝙍" frame:CGRectMake(5,12,100,BH) inView:mv italic:YES];
    [self btn:@"𝙅𝙐𝙈𝙋 𝘾𝘼𝙍" frame:CGRectMake(135,12,100,BH) inView:mv italic:YES];
    [self btn:@"𝙁𝘼𝙎𝙏 𝙎𝙒𝙄𝙏𝘾𝙃" frame:CGRectMake(5,44,100,BH) inView:mv italic:YES];
    [self btn:@"𝙂𝙊𝘿 𝙑𝙄𝙀𝙒" frame:CGRectMake(135,44,100,BH) inView:mv italic:YES];
}

- (void)buildRightColumn {
    UIView *host = self.rightColumnHost;
    const CGFloat BH = 18;
    __weak typeof(self) weakSelf = self;

    [host addSubview:[[MenuSectionHeader alloc] initWithTitle:@"CUSTOM IGG" origin:CGPointMake(252, 18)]];
    UIView *igg = [self cardAt5:CGRectMake(255, 46, 240, 175)];
    [host addSubview:igg];
    [igg addSubview:[[MenuYellowField alloc] initWithFrame:CGRectMake(5,10,170,20) placeholder:@"VALUE OR NEARBY OR BATCH"]];
    MenuYellowField *hx = [[MenuYellowField alloc] initWithFrame:CGRectMake(185,10,50,20) placeholder:@"0x20"];
    hx.textAlignment = NSTextAlignmentCenter;
    [igg addSubview:hx];
    [self btn:@"SEARCH" frame:CGRectMake(5,42,100,BH) inView:igg italic:NO];
    [self btn:@"NEARBY" frame:CGRectMake(135,42,100,BH) inView:igg italic:NO];
    [self btn:@"BATCH ALL" frame:CGRectMake(70,72,100,BH) inView:igg italic:NO];
    [self madsw:@[@"F32",@"F64",@"I8",@"I16",@"I32",@"I64",@"U8",@"U16",@"U32",@"U64"]
          frame:CGRectMake(5,108,230,20) parent:igg];

    [host addSubview:[[MenuSectionHeader alloc] initWithTitle:@"CUSTOM OFFSET" origin:CGPointMake(252, 222)]];
    UIView *off = [self cardAt5:CGRectMake(255, 250, 240, 240)];
    [host addSubview:off];
    [off addSubview:[[MenuYellowField alloc] initWithFrame:CGRectMake(5,10,230,20) placeholder:@"OFFSET"]];
    [off addSubview:[[MenuYellowField alloc] initWithFrame:CGRectMake(5,40,230,20) placeholder:@"BYTE"]];
    [self btn:@"𝙍𝙀𝙏" frame:CGRectMake(16,68,48,BH) inView:off italic:YES];
    [self btn:@"𝙋𝘼𝙏𝘾𝙃" frame:CGRectMake(72,68,96,BH) inView:off italic:YES];
    [self btn:@"𝙉𝙊𝙋" frame:CGRectMake(176,68,48,BH) inView:off italic:YES];
    NSMutableArray *sArr=[NSMutableArray array]; for(int i=0;i<=10;i++)[sArr addObject:[NSString stringWithFormat:@"S%d",i]];
    [self madsw:sArr frame:CGRectMake(5,100,230,18) parent:off];
    NSMutableArray *wArr=[NSMutableArray array]; for(int i=0;i<=10;i++)[wArr addObject:[NSString stringWithFormat:@"W%d",i]];
    [self madsw:wArr frame:CGRectMake(5,148,230,18) parent:off];
    [self madsw:@[@"𝙈𝘼𝙓",@"𝙈𝙄𝙉"] frame:CGRectMake(80,123,80,18) parent:off];
    [self madsw:@[@"𝙊𝙉",@"𝙊𝙁𝙁"] frame:CGRectMake(80,170,80,18) parent:off];
    UILabel *jail=[[UILabel alloc] initWithFrame:CGRectMake(5,194,230,36)];
    jail.text=@"CUSTOM OFFSET FOR JAILBREAK USER ONLY >";
    jail.textColor=UIColor.yellowColor; jail.font=MADItalicFont(9);
    jail.numberOfLines=2; jail.textAlignment=NSTextAlignmentCenter;
    [off addSubview:jail];

    [host addSubview:[[MenuSectionHeader alloc] initWithTitle:@"ADVANCED PANEL" origin:CGPointMake(252, 492)]];
    UIView *adv=[self cardAt:CGRectMake(255,520,240,255)];
    [host addSubview:adv];
    MenuToggleButton *bReset = [self btn:@"𝙍𝙀𝙎𝙀𝙏 𝙂𝘼𝙈𝙀" frame:CGRectMake(5,15,100,BH) inView:adv italic:YES];
    bReset.onToggle = ^(BOOL isOn) {
        [weakSelf resetToDefaults];
    };
    [self btn:@"𝙉𝙊𝙏 𝙃𝘼𝘾𝙆" frame:CGRectMake(135,15,100,BH) inView:adv italic:YES];
    [self madsw:@[@"DRAW1s",@"DRAW2s"] frame:CGRectMake(5,50,100,20) parent:adv];
    [self madsw:@[@" ENGLISH ",@"عربي"] frame:CGRectMake(135,50,100,18) parent:adv];
    [self btn:@"𝙎𝙋𝙀𝙀𝘿 𝙆𝙉𝙊𝘾𝙆" frame:CGRectMake(5,85,100,BH) inView:adv italic:YES];
    [self btn:@"𝙁𝘼𝙎𝙏 𝘿𝙍𝙊𝙋" frame:CGRectMake(135,85,100,BH) inView:adv italic:YES];
    MenuSliderRow *s1=[[MenuSliderRow alloc] initWithFrame:CGRectMake(5,120,230,22) min:0 max:500 value:500 name:@"𝘼𝙄𝙈 𝘿𝙄𝙎"];
    s1.displayMode = MenuSliderDisplayRaw;
    s1.onChange=^(float v){ weakSelf.aimdis=v; }; [adv addSubview:s1];
    MenuSliderRow *s2=[[MenuSliderRow alloc] initWithFrame:CGRectMake(5,148,230,22) min:100000 max:800000 value:800000 name:@"𝙁𝘼𝙎𝙏 𝘽𝙐𝙇𝙇𝙀𝙏"];
    s2.displayMode = MenuSliderDisplayTimes001;
    s2.onChange=^(float v){ weakSelf.fastbulletval=v; }; [adv addSubview:s2];
    self.sliderThickness = [[MenuSliderRow alloc] initWithFrame:CGRectMake(5,176,230,22) min:80 max:170 value:80 + (g_pubgEspThickness - 0.8f) * 33.0f name:@"𝘾𝘼𝙈 𝙁𝙊𝙑"];
    self.sliderThickness.displayMode = MenuSliderDisplayMinus80;
    self.sliderThickness.onChange=^(float v){
        float th = 0.8f + ((v - 80.0f) / 90.0f) * 2.7f;
        if (th < 0.8f) th = 0.8f;
        if (th > 3.5f) th = 3.5f;
        g_pubgEspThickness = th;
        [NSUserDefaults.standardUserDefaults setFloat:th forKey:@"pubg_thickness"];
    };
    [adv addSubview:self.sliderThickness];
    MenuSliderRow *s4=[[MenuSliderRow alloc] initWithFrame:CGRectMake(5,204,230,22) min:0 max:0.098f value:0 name:@"𝙁𝙄𝙍𝙀 𝙍𝘼𝙏𝙀"];
    s4.displayMode = MenuSliderDisplayRaw;
    [adv addSubview:s4];

    [host addSubview:[[MenuSectionHeader alloc] initWithTitle:@"IGG PANEL" origin:CGPointMake(252, 778)]];
    UIView *ig=[self cardAt:CGRectMake(255,805,240,80)];
    [host addSubview:ig];
    [self btn:@"𝙎𝙀𝙏 𝙎𝘾𝙊𝙋𝙀" frame:CGRectMake(5,12,100,BH) inView:ig italic:YES];
    [self btn:@"𝙁𝙇𝙔 𝙋𝙇𝘼𝙔𝙀𝙍" frame:CGRectMake(135,12,100,BH) inView:ig italic:YES];
    [self btn:@"𝙃𝙄𝙂𝙃 𝙅𝙐𝙈𝙋" frame:CGRectMake(5,44,100,BH) inView:ig italic:YES];
    [self btn:@"𝙈𝘼𝙂𝙄𝘾 𝘽𝙐𝙇𝙇𝙀𝙏" frame:CGRectMake(135,44,100,BH) inView:ig italic:YES];
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
    g_pubgEspArrow = YES;
    g_pubgEspGrenade = YES;
    g_dspubgMaxDistance = 400.0f;
    g_pubgEspWeapon = YES;
    g_pubgEspArmor = YES;
    g_pubgEspBag = YES;
    g_pubgEspScope = YES;
    g_pubgEspCrate = YES;
    g_pubgItemMaxDistance = 150.0f;
    g_pubgEspVehicle = YES;
    g_pubgEspVehicleHp = YES;
    g_pubgEspVehicleFuel = YES;
    g_pubgEspThickness = 1.5f;

    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    [defaults setBool:YES forKey:@"pubg_box"];
    [defaults setBool:YES forKey:@"pubg_line"];
    [defaults setBool:YES forKey:@"pubg_skeleton"];
    [defaults setBool:YES forKey:@"pubg_name"];
    [defaults setBool:YES forKey:@"pubg_dist"];
    [defaults setBool:YES forKey:@"pubg_health"];
    [defaults setBool:YES forKey:@"pubg_bot"];
    [defaults setBool:YES forKey:@"pubg_arrow"];
    [defaults setBool:YES forKey:@"pubg_grenade"];
    [defaults setFloat:400.0f forKey:@"pubg_zoom_dist"];
    [defaults setBool:YES forKey:@"pubg_weapon"];
    [defaults setBool:YES forKey:@"pubg_armor"];
    [defaults setBool:YES forKey:@"pubg_bag"];
    [defaults setBool:YES forKey:@"pubg_scope"];
    [defaults setBool:YES forKey:@"pubg_crate"];
    [defaults setFloat:150.0f forKey:@"pubg_item_dist"];
    [defaults setBool:YES forKey:@"pubg_vehicle"];
    [defaults setBool:YES forKey:@"pubg_vehicle_hp"];
    [defaults setBool:YES forKey:@"pubg_vehicle_fuel"];
    [defaults setFloat:1.5f forKey:@"pubg_thickness"];

    self.btnBox.on = YES;
    self.btnLine.on = YES;
    self.btnBone.on = YES;
    self.btnInfo.on = YES;
    self.btn3D.on = YES;
    self.btnArrow.on = YES;
    self.btnRadar.on = YES;
    [self.sliderEspDist setSliderValue:400.0f];

    self.btnVeh.on = YES;
    self.btnWeapon.on = YES;
    self.btnArmor.on = YES;
    self.btnScope.on = YES;
    self.btnBag.on = YES;
    self.btnDrop.on = YES;
    self.btnLootBox.on = YES;
    self.btnGrenade.on = YES;
    [self.sliderItemDist setSliderValue:150.0f];
    [self.sliderThickness setSliderValue:80.0f + (1.5f - 0.8f) / 2.7f * 90.0f];
}

#pragma mark - Open / close / tab (controllview order)

- (void)applyTabSwitchToIndex:(NSUInteger)index {
    self.cosview = (NSInteger)index;
    CGRect pf = self.panel.frame;
    CGRect tb = self.titleBox.frame;

    // Clamp horizontally if expanding to 500 would overflow
    if (self.superview && self.superview.bounds.size.width > 200) {
        CGFloat maxW = (index == 0) ? 250.0 : 500.0;
        if (pf.origin.x + maxW > self.superview.bounds.size.width) {
            pf.origin.x = MAX(10.0, self.superview.bounds.size.width - maxW - 10.0);
        }
    }

    if (index == 0) {
        self.panel.frame = CGRectMake(pf.origin.x, pf.origin.y, 250, 350);
        self.titleBox.frame = CGRectMake(tb.origin.x, tb.origin.y, 205, 25);
        self.scroll.frame = CGRectMake(0, 30, 250, 315);
        self.tabBarHost.frame = CGRectMake(135, 7.5, 105, 20);
        self.socialSwitch.hidden = YES;
        self.rightColumnHost.hidden = YES;
        self.moreFutureLabel.hidden = YES;
    } else {
        self.panel.frame = CGRectMake(pf.origin.x, pf.origin.y, 500, 350);
        self.titleBox.frame = CGRectMake(tb.origin.x, tb.origin.y, 455, 25);
        self.scroll.frame = CGRectMake(0, 30, 500, 315);
        self.tabBarHost.frame = CGRectMake(135, 7.5, 360, 20);
        self.socialSwitch.hidden = NO;
        self.rightColumnHost.hidden = NO;
        self.moreFutureLabel.hidden = NO;
    }
    self.scroll.contentSize = CGSizeMake(250, 890);
    NSLog(@"[MadnessMenu] Did switch to index %lu", (unsigned long)index);
}

- (void)controllview {
    [self.haptic impactOccurred];
    self.asize = YES;
    self.isShowMenu = YES;
    g_hostedMenuExpanded = YES;
    self.panel.backgroundColor = MADPanelFill();
    [self.handle removeGestureRecognizer:self.handleTap];
    self.handleTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(controllview1)];
    [self.handle addGestureRecognizer:self.handleTap];

    /* Open glyph: CFSTR U+27C7 */
    self.handleGlyph.frame = CGRectMake(5, 1, 16, 20);
    self.handleGlyph.text = @"\u27C7";
    self.handleGlyph.font = [UIFont boldSystemFontOfSize:20.0];
    self.scroll.hidden = NO;
    self.tabBarHost.hidden = NO;
    CGRect tb = self.titleBox.frame;
    self.titleBox.frame = CGRectMake(tb.origin.x, tb.origin.y, 205, 25);
    CGRect pf = self.panel.frame;

    if (self.superview && self.superview.bounds.size.width > 200) {
        CGFloat maxW = (self.cosview == 0) ? 250.0 : 500.0;
        if (pf.origin.x + maxW > self.superview.bounds.size.width) {
            pf.origin.x = MAX(10.0, self.superview.bounds.size.width - maxW - 10.0);
        }
        if (pf.origin.y + 350.0 > self.superview.bounds.size.height) {
            pf.origin.y = MAX(10.0, self.superview.bounds.size.height - 350.0 - 10.0);
        }
    }

    if (self.cosview == 0) {
        self.panel.frame = CGRectMake(pf.origin.x, pf.origin.y, 250, 350);
        self.scroll.frame = CGRectMake(0, 30, 250, 315);
        self.tabBarHost.frame = CGRectMake(135, 7.5, 105, 20);
        self.socialSwitch.hidden = YES;
        self.rightColumnHost.hidden = YES;
        self.moreFutureLabel.hidden = YES;
    } else {
        self.titleBox.frame = CGRectMake(tb.origin.x, tb.origin.y, 455, 25);
        self.tabBarHost.frame = CGRectMake(135, 7.5, 360, 20);
        self.panel.frame = CGRectMake(pf.origin.x, pf.origin.y, 500, 350);
        self.scroll.frame = CGRectMake(0, 30, 500, 315);
        self.socialSwitch.hidden = NO;
        self.rightColumnHost.hidden = NO;
        self.moreFutureLabel.hidden = NO;
    }
}

- (void)controllview1 {
    [self.haptic impactOccurred];
    self.asize = NO;
    self.isShowMenu = NO;
    g_hostedMenuExpanded = NO;
    CGRect tb = self.titleBox.frame;
    self.titleBox.frame = CGRectMake(tb.origin.x, tb.origin.y, 205, 25);
    CGRect pf = self.panel.frame;
    self.panel.frame = CGRectMake(pf.origin.x, pf.origin.y, 210, 30);
    self.scroll.hidden = YES;
    self.tabBarHost.hidden = YES;
    self.socialSwitch.hidden = YES;
    self.rightColumnHost.hidden = YES;
    self.moreFutureLabel.hidden = YES;
    self.panel.backgroundColor = UIColor.clearColor;
    [self.handle removeGestureRecognizer:self.handleTap];
    self.handleTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(controllview)];
    [self.handle addGestureRecognizer:self.handleTap];
    self.handleGlyph.frame = CGRectMake(6, 0, 15, 18);
    self.handleGlyph.text = @"⋗";
    self.handleGlyph.font = [UIFont boldSystemFontOfSize:25.0];
    tb = self.titleBox.frame;
    self.titleBox.frame = CGRectMake(tb.origin.x, tb.origin.y, 105, 25);
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
    CGPoint prev = [t previousLocationInView:sender];
    CGPoint loc  = [t locationInView:sender];
    CGPoint c = sender.center;
    sender.center = CGPointMake(c.x + (loc.x - prev.x), c.y + (loc.y - prev.y));
}

#pragma mark - Preview hooks

- (void)previewResetUIState {
    [self resetToDefaults];
}

- (void)previewOpen { [self controllview]; }
- (void)previewClose { [self controllview1]; }
- (void)previewSelectTab:(NSUInteger)index {
    [self.pageSwitch selectIndex:index animated:YES];
    [self applyTabSwitchToIndex:index];
}
- (void)previewLongPressToggle {
    if (self.asize) [self controllview1]; else [self controllview];
}
- (void)previewNudgePanel:(CGPoint)delta {
    CGPoint c = self.panel.center;
    self.panel.center = CGPointMake(c.x + delta.x, c.y + delta.y);
}
- (UIView *)menuPanel { return self.panel; }
- (id)previewPageSwitch { return self.pageSwitch; }
- (UIScrollView *)previewScroll { return self.scroll; }
- (void)previewSetScrollOffset:(CGPoint)o { self.scroll.contentOffset = o; }
- (void)previewToggleFirstButton {
    [self.btnBox sendActionsForControlEvents:UIControlEventTouchUpInside];
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
