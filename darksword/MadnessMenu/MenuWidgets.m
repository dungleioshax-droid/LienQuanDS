#import "MenuWidgets.h"

/* IDA looadmenu: 152/161 colorWithRed = rgba(0,0,0,0.5) */
UIColor *MADPanelFill(void) { return [UIColor colorWithRed:0 green:0 blue:0 alpha:0.5]; }
UIColor *MADCardFill(void)  { return [UIColor colorWithRed:0 green:0 blue:0 alpha:0.5]; }
/* UITextField: yellowColor colorWithAlphaComponent:0.7 */
UIColor *MADFieldYellow(void){ return [[UIColor yellowColor] colorWithAlphaComponent:0.7]; }
UIColor *MADBlack50(void)   { return [UIColor colorWithRed:0 green:0 blue:0 alpha:0.5]; }
UIFont *MADBtnFont(void) { return [UIFont boldSystemFontOfSize:11.0]; }
UIFont *MADItalicFont(CGFloat size) {
    UIFont *f = [UIFont fontWithName:@"Helvetica-BoldOblique" size:size];
    if (!f) f = [UIFont italicSystemFontOfSize:size];
    if (!f) f = [UIFont boldSystemFontOfSize:size];
    return f;
}

@implementation MenuToggleButton
- (instancetype)initWithTitle:(NSString *)title frame:(CGRect)frame {
    return [self initWithTitle:title frame:frame italic:YES];
}
- (instancetype)initWithTitle:(NSString *)title frame:(CGRect)frame italic:(BOOL)italic {
    if (!(self = [super initWithFrame:frame])) return nil;
    self.backgroundColor = MADBlack50();
    self.layer.cornerRadius = 5.0;
    self.layer.borderWidth = 0.8;
    self.layer.borderColor = UIColor.darkGrayColor.CGColor;
    [self setTitle:title forState:UIControlStateNormal];
    [self setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    self.titleLabel.font = italic ? MADItalicFont(10.5) : MADBtnFont();
    self.titleLabel.adjustsFontSizeToFitWidth = YES;
    self.titleLabel.minimumScaleFactor = 0.6;
    [self addTarget:self action:@selector(tap) forControlEvents:UIControlEventTouchUpInside];
    return self;
}
- (void)setOn:(BOOL)on {
    _on = on;
    self.layer.borderColor = (on ? UIColor.yellowColor : UIColor.darkGrayColor).CGColor;
}
- (void)tap {
    /* IDA: tap via UITapGestureRecognizer on buttons → border darkGray↔yellow + medium haptic */
    self.on = !self.on;
    UIImpactFeedbackGenerator *g = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
    [g impactOccurred];
    if (self.onToggle) self.onToggle(self.on);
    NSLog(@"[MadnessMenu] toggle %@ -> %d", self.currentTitle, self.on);
}
@end

@implementation MenuSliderRow {
    UISlider *_s;
    UILabel *_bubble;
    UILabel *_name;
}
- (instancetype)initWithFrame:(CGRect)frame min:(float)min max:(float)max value:(float)value name:(NSString *)name {
    if (!(self = [super initWithFrame:frame])) return nil;
    _displayMode = MenuSliderDisplayRaw;
    CGFloat sliderW = frame.size.width - 70;
    _s = [[UISlider alloc] initWithFrame:CGRectMake(0, 3, sliderW, 14)];
    _s.minimumValue = min; _s.maximumValue = max; _s.value = value;
    _s.minimumTrackTintColor = UIColor.yellowColor;
    _s.maximumTrackTintColor = [UIColor colorWithWhite:0.35 alpha:1.0];
    _s.thumbTintColor = UIColor.clearColor; /* IDA setThumbTintColor: clearColor */
    _s.continuous = YES;
    [_s addTarget:self action:@selector(changed) forControlEvents:UIControlEventValueChanged];
    [self addSubview:_s];
    _bubble = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, 32, 14)];
    _bubble.backgroundColor = UIColor.yellowColor;
    _bubble.textColor = UIColor.blackColor;
    _bubble.font = [UIFont boldSystemFontOfSize:9.5];
    _bubble.textAlignment = NSTextAlignmentCenter;
    _bubble.layer.cornerRadius = 3.5;
    _bubble.clipsToBounds = YES;
    [self addSubview:_bubble];
    _name = [[UILabel alloc] initWithFrame:CGRectMake(frame.size.width - 66, 1, 64, 18)];
    _name.text = name;
    _name.textColor = UIColor.yellowColor;
    _name.font = MADItalicFont(10.0);
    _name.textAlignment = NSTextAlignmentRight;
    _name.adjustsFontSizeToFitWidth = YES;
    [self addSubview:_name];
    [self syncBubble];
    return self;
}
- (int)displayInt {
    float v = _s.value;
    switch (_displayMode) {
        case MenuSliderDisplayTimes001: return (int)(v * 0.001f); /* sbeebulletlvalueActionmat */
        case MenuSliderDisplayMinus80:  return (int)(v - 80.0f);  /* changeviewvalueActionmat */
        default: return (int)v; /* recoilvalueActionmat / dist etc CFSTR("%d") */
    }
}
- (void)syncBubble {
    _bubble.text = [NSString stringWithFormat:@"%d", [self displayInt]]; /* IDA CFSTR("%d") */
    CGFloat trackW = _s.bounds.size.width - 28;
    CGFloat t = (_s.maximumValue > _s.minimumValue) ? ((_s.value - _s.minimumValue) / (_s.maximumValue - _s.minimumValue)) : 0;
    _bubble.center = CGPointMake(14 + t * trackW, _s.center.y);
}
- (void)changed { [self syncBubble]; if (self.onChange) self.onChange(_s.value); }
- (void)setSliderValue:(float)v { _s.value = v; [self syncBubble]; }
- (void)setDisplayMode:(MenuSliderDisplay)displayMode { _displayMode = displayMode; [self syncBubble]; }
@end

@implementation MenuYellowField
- (instancetype)initWithFrame:(CGRect)frame placeholder:(NSString *)ph {
    if (!(self = [super initWithFrame:frame])) return nil;
    /* IDA: borderStyle 3 (RoundedRect), bg yellow@0.7, font AvenirNextCondensed-HeavyItalic 12, textColor black,
       attributedPlaceholder black, autocapitalizationType 3 (all), clearButtonMode 1 (while editing) */
    self.borderStyle = UITextBorderStyleRoundedRect;
    self.backgroundColor = MADFieldYellow();
    self.textColor = UIColor.blackColor;
    self.font = [UIFont fontWithName:@"AvenirNextCondensed-HeavyItalic" size:12.0] ?: [UIFont boldSystemFontOfSize:12];
    self.attributedPlaceholder = [[NSAttributedString alloc] initWithString:ph attributes:@{NSForegroundColorAttributeName: UIColor.blackColor}];
    self.autocapitalizationType = UITextAutocapitalizationTypeAllCharacters;
    self.clearButtonMode = UITextFieldViewModeWhileEditing;
    self.layer.cornerRadius = 0; /* borderStyle provides chrome */
    return self;
}
@end

@implementation MenuSectionHeader
- (instancetype)initWithTitle:(NSString *)title origin:(CGPoint)origin {
    /* IDA: chevron label (2,y,15,18) boldSystem 25 yellow + title (20,y,…) boldSystem 12 white */
    if (!(self = [super initWithFrame:CGRectMake(origin.x, origin.y, 240, 28)])) return nil;
    UILabel *chev = [[UILabel alloc] initWithFrame:CGRectMake(2, 0, 15, 18)];
    chev.text = @"⋗";
    chev.textColor = UIColor.yellowColor;
    chev.font = [UIFont boldSystemFontOfSize:25.0];
    chev.textAlignment = NSTextAlignmentCenter;
    [self addSubview:chev];
    UILabel *tit = [[UILabel alloc] initWithFrame:CGRectMake(20, 0, 200, 25)];
    tit.text = title;
    tit.textColor = UIColor.whiteColor;
    tit.font = [UIFont boldSystemFontOfSize:12.0];
    [self addSubview:tit];
    return self;
}
@end
