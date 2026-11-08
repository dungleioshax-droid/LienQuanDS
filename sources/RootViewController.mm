//
//  RootViewController.mm
//  DarkPubg
//
//  Created by Lessica on 2024/1/24.
//  Redesigned by DLX07 on 2026/11/08.
//

#import <notify.h>
#import <sys/sysctl.h>

#import "HUDHelper.h"
#import "DSBridge.h"
#import "MainButton.h"
#import "MainApplication.h"
#import "HUDPresetPosition.h"
#import "RootViewController.h"
#import "UIApplication+Private.h"
#import "HUDRootViewController.h"

#define HUD_TRANSITION_DURATION 0.25

static BOOL _gShouldToggleHUDAfterLaunch = NO;

static BOOL CheckDarkSwordSupport(NSString **outVersionStr, NSString **outStatusStr) {
    NSString *version = [[UIDevice currentDevice] systemVersion];
    if (outVersionStr) *outVersionStr = [NSString stringWithFormat:@"iOS %@", version];

    NSOperatingSystemVersion os = [[NSProcessInfo processInfo] operatingSystemVersion];
    // DarkSword kexploit supports iOS 15.0 through iOS 26.0
    if (os.majorVersion >= 15 && os.majorVersion <= 26) {
        if (outStatusStr) *outStatusStr = @"DarkSword: Đã hỗ trợ";
        return YES;
    } else {
        if (outStatusStr) *outStatusStr = @"DarkSword: Chưa hỗ trợ";
        return NO;
    }
}

@implementation RootViewController {
    NSMutableDictionary *_userDefaults;
    MainButton *_mainButton;
    UILabel *_buttonSubLabel;

    // Tab Navigation Containers
    UIView *_homeView;
    UIView *_settingView;
    UIView *_bottomTabBar;
    UIButton *_homeTabButton;
    UIButton *_settingTabButton;
    NSInteger _selectedTabIndex;

    // Home status components
    UILabel *_iosVersionLabel;
    UILabel *_dsStatusLabel;
    UIView *_dsStatusBadge;
    UILabel *_dsBadgeLabel;

    BOOL _isRemoteHUDActive;
    UIImpactFeedbackGenerator *_impactFeedbackGenerator;

#if USE_DARKSWORD
    UIView *_dsProgressOverlay;
    UIProgressView *_dsProgressBar;
    UILabel *_dsProgressLabel;
#endif
}

+ (void)setShouldToggleHUDAfterLaunch:(BOOL)flag
{
    _gShouldToggleHUDAfterLaunch = flag;
}

+ (BOOL)shouldToggleHUDAfterLaunch
{
    return _gShouldToggleHUDAfterLaunch;
}

- (BOOL)isHUDEnabled
{
    return IsHUDEnabled();
}

- (void)setHUDEnabled:(BOOL)enabled
{
    SetHUDEnabled(enabled);
}

- (void)registerNotifications
{
    int token;
    notify_register_dispatch(NOTIFY_RELOAD_APP, &token, dispatch_get_main_queue(), ^(int token) {
        [self loadUserDefaults:YES];
        [self reloadMainButtonState];
#if USE_DARKSWORD
        if (DSBridgeLastError().length > 0) {
            [self showDSFailure:DSBridgeLastError()];
            [self.backgroundView setUserInteractionEnabled:YES];
        }
#endif
    });

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(toggleHUDNotificationReceived:) name:kToggleHUDAfterLaunchNotificationName object:nil];

#if USE_DARKSWORD
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(dsProgressDidChange:) name:DSBridgeProgressNotification object:nil];
#endif
}

- (void)loadView
{
    CGRect bounds = UIScreen.mainScreen.bounds;

    self.view = [[UIView alloc] initWithFrame:bounds];
    self.view.backgroundColor = [UIColor colorWithRed:13/255.0 green:17/255.0 blue:23/255.0 alpha:1.0]; // #0D1117

    self.backgroundView = [[UIView alloc] initWithFrame:bounds];
    self.backgroundView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.backgroundView.backgroundColor = [UIColor colorWithRed:15/255.0 green:20/255.0 blue:28/255.0 alpha:1.0]; // #0F141C
    [self.view addSubview:self.backgroundView];

    [self setupBottomTabBar];
    [self setupHomeView];
    [self setupSettingView];

    [self updateTabSelection:0];
    [self reloadMainButtonState];
}

#pragma mark - Bottom Tab Bar

- (void)setupBottomTabBar
{
    _bottomTabBar = [[UIView alloc] init];
    _bottomTabBar.translatesAutoresizingMaskIntoConstraints = NO;
    _bottomTabBar.backgroundColor = [UIColor colorWithRed:22/255.0 green:27/255.0 blue:34/255.0 alpha:0.98]; // #161B22

    UIView *topLine = [[UIView alloc] init];
    topLine.translatesAutoresizingMaskIntoConstraints = NO;
    topLine.backgroundColor = [UIColor colorWithRed:33/255.0 green:38/255.0 blue:45/255.0 alpha:1.0]; // #21262D
    [_bottomTabBar addSubview:topLine];

    _homeTabButton = [self createTabButtonWithTitle:@"Home" iconName:@"house.fill" tag:0];
    _settingTabButton = [self createTabButtonWithTitle:@"Setting" iconName:@"gearshape.fill" tag:1];

    [_bottomTabBar addSubview:_homeTabButton];
    [_bottomTabBar addSubview:_settingTabButton];

    [self.view addSubview:_bottomTabBar];

    [NSLayoutConstraint activateConstraints:@[
        [_bottomTabBar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_bottomTabBar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_bottomTabBar.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [_bottomTabBar.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-56.0f],

        [topLine.topAnchor constraintEqualToAnchor:_bottomTabBar.topAnchor],
        [topLine.leadingAnchor constraintEqualToAnchor:_bottomTabBar.leadingAnchor],
        [topLine.trailingAnchor constraintEqualToAnchor:_bottomTabBar.trailingAnchor],
        [topLine.heightAnchor constraintEqualToConstant:1.0f],

        [_homeTabButton.leadingAnchor constraintEqualToAnchor:_bottomTabBar.leadingAnchor],
        [_homeTabButton.topAnchor constraintEqualToAnchor:_bottomTabBar.topAnchor constant:4.0f],
        [_homeTabButton.widthAnchor constraintEqualToAnchor:_bottomTabBar.widthAnchor multiplier:0.5],
        [_homeTabButton.heightAnchor constraintEqualToConstant:48.0f],

        [_settingTabButton.leadingAnchor constraintEqualToAnchor:_homeTabButton.trailingAnchor],
        [_settingTabButton.topAnchor constraintEqualToAnchor:_bottomTabBar.topAnchor constant:4.0f],
        [_settingTabButton.trailingAnchor constraintEqualToAnchor:_bottomTabBar.trailingAnchor],
        [_settingTabButton.heightAnchor constraintEqualToConstant:48.0f],
    ]];
}

- (UIButton *)createTabButtonWithTitle:(NSString *)title iconName:(NSString *)iconName tag:(NSInteger)tag
{
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
    btn.translatesAutoresizingMaskIntoConstraints = NO;
    btn.tag = tag;
    [btn addTarget:self action:@selector(tabButtonTapped:) forControlEvents:UIControlEventTouchUpInside];

    UIImage *img = [UIImage systemImageNamed:iconName];
    if (@available(iOS 15.0, *)) {
        UIButtonConfiguration *config = [UIButtonConfiguration plainButtonConfiguration];
        config.image = img;
        config.title = title;
        config.imagePlacement = NSDirectionalRectEdgeTop;
        config.imagePadding = 3.0f;
        btn.configuration = config;
    } else {
        [btn setImage:img forState:UIControlStateNormal];
        [btn setTitle:title forState:UIControlStateNormal];
        btn.titleLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
    }
    return btn;
}

- (void)tabButtonTapped:(UIButton *)sender
{
    [self updateTabSelection:sender.tag];
}

- (void)updateTabSelection:(NSInteger)index
{
    _selectedTabIndex = index;
    if (_impactFeedbackGenerator) {
        [_impactFeedbackGenerator impactOccurred];
    }

    UIColor *activeColor = [UIColor colorWithRed:0/255.0 green:210/255.0 blue:180/255.0 alpha:1.0]; // Cyan
    UIColor *inactiveColor = [UIColor colorWithRed:139/255.0 green:148/255.0 blue:158/255.0 alpha:1.0]; // Muted

    if (@available(iOS 15.0, *)) {
        UIButtonConfiguration *cfgHome = _homeTabButton.configuration;
        cfgHome.baseForegroundColor = (index == 0) ? activeColor : inactiveColor;
        _homeTabButton.configuration = cfgHome;

        UIButtonConfiguration *cfgSet = _settingTabButton.configuration;
        cfgSet.baseForegroundColor = (index == 1) ? activeColor : inactiveColor;
        _settingTabButton.configuration = cfgSet;
    } else {
        [_homeTabButton setTitleColor:(index == 0) ? activeColor : inactiveColor forState:UIControlStateNormal];
        [_homeTabButton setTintColor:(index == 0) ? activeColor : inactiveColor];
        [_settingTabButton setTitleColor:(index == 1) ? activeColor : inactiveColor forState:UIControlStateNormal];
        [_settingTabButton setTintColor:(index == 1) ? activeColor : inactiveColor];
    }

    [UIView transitionWithView:self.backgroundView duration:0.2 options:UIViewAnimationOptionTransitionCrossDissolve animations:^{
        self->_homeView.hidden = (index != 0);
        self->_settingView.hidden = (index != 1);
    } completion:nil];
}

#pragma mark - Home View

- (void)setupHomeView
{
    _homeView = [[UIView alloc] init];
    _homeView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.backgroundView addSubview:_homeView];

    UILayoutGuide *safeArea = self.view.safeAreaLayoutGuide;

    [NSLayoutConstraint activateConstraints:@[
        [_homeView.topAnchor constraintEqualToAnchor:safeArea.topAnchor],
        [_homeView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_homeView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_homeView.bottomAnchor constraintEqualToAnchor:_bottomTabBar.topAnchor],
    ]];

    // 1. App Header Title
    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    titleLabel.text = @"DarkPubg";
    titleLabel.textColor = UIColor.whiteColor;
    titleLabel.font = [UIFont systemFontOfSize:30 weight:UIFontWeightHeavy];
    titleLabel.textAlignment = NSTextAlignmentCenter;
    [_homeView addSubview:titleLabel];

    UILabel *subTitleLabel = [[UILabel alloc] init];
    subTitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    subTitleLabel.text = @"PUBG Mobile Edition";
    subTitleLabel.textColor = [UIColor colorWithRed:0/255.0 green:210/255.0 blue:180/255.0 alpha:1.0];
    subTitleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    subTitleLabel.textAlignment = NSTextAlignmentCenter;
    [_homeView addSubview:subTitleLabel];

    // 2. iOS Version & DarkSword Support Card
    UIView *statusCard = [[UIView alloc] init];
    statusCard.translatesAutoresizingMaskIntoConstraints = NO;
    statusCard.backgroundColor = [UIColor colorWithRed:22/255.0 green:27/255.0 blue:34/255.0 alpha:0.9];
    statusCard.layer.cornerRadius = 16.0f;
    statusCard.layer.borderColor = [UIColor colorWithRed:33/255.0 green:38/255.0 blue:45/255.0 alpha:1.0].CGColor;
    statusCard.layer.borderWidth = 1.0f;
    [_homeView addSubview:statusCard];

    NSString *iosVer = @"";
    NSString *dsStatus = @"";
    BOOL isSupported = CheckDarkSwordSupport(&iosVer, &dsStatus);

    // Row 1: iOS Version
    UIImageView *appleIcon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"apple.logo"]];
    appleIcon.translatesAutoresizingMaskIntoConstraints = NO;
    appleIcon.tintColor = UIColor.whiteColor;
    appleIcon.contentMode = UIViewContentModeScaleAspectFit;
    [statusCard addSubview:appleIcon];

    _iosVersionLabel = [[UILabel alloc] init];
    _iosVersionLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _iosVersionLabel.text = [NSString stringWithFormat:@"Phiên bản: %@", iosVer];
    _iosVersionLabel.textColor = UIColor.whiteColor;
    _iosVersionLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightBold];
    [statusCard addSubview:_iosVersionLabel];

    UILabel *systemTag = [[UILabel alloc] init];
    systemTag.translatesAutoresizingMaskIntoConstraints = NO;
    systemTag.text = @"Thiết bị";
    systemTag.textColor = [UIColor colorWithRed:139/255.0 green:148/255.0 blue:158/255.0 alpha:1.0];
    systemTag.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
    [statusCard addSubview:systemTag];

    // Card Separator
    UIView *cardSep = [[UIView alloc] init];
    cardSep.translatesAutoresizingMaskIntoConstraints = NO;
    cardSep.backgroundColor = [UIColor colorWithRed:33/255.0 green:38/255.0 blue:45/255.0 alpha:1.0];
    [statusCard addSubview:cardSep];

    // Row 2: DarkSword Support Indicator
    UIView *dotView = [[UIView alloc] init];
    dotView.translatesAutoresizingMaskIntoConstraints = NO;
    dotView.backgroundColor = isSupported ? [UIColor colorWithRed:46/255.0 green:204/255.0 blue:113/255.0 alpha:1.0] : [UIColor colorWithRed:231/255.0 green:76/255.0 blue:60/255.0 alpha:1.0];
    dotView.layer.cornerRadius = 4.0f;
    [statusCard addSubview:dotView];

    _dsStatusLabel = [[UILabel alloc] init];
    _dsStatusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _dsStatusLabel.text = dsStatus;
    _dsStatusLabel.textColor = isSupported ? [UIColor colorWithRed:46/255.0 green:204/255.0 blue:113/255.0 alpha:1.0] : [UIColor colorWithRed:231/255.0 green:76/255.0 blue:60/255.0 alpha:1.0];
    _dsStatusLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    [statusCard addSubview:_dsStatusLabel];

    _dsStatusBadge = [[UIView alloc] init];
    _dsStatusBadge.translatesAutoresizingMaskIntoConstraints = NO;
    _dsStatusBadge.backgroundColor = isSupported ? [UIColor colorWithRed:28/255.0 green:58/255.0 blue:45/255.0 alpha:1.0] : [UIColor colorWithRed:60/255.0 green:25/255.0 blue:25/255.0 alpha:1.0];
    _dsStatusBadge.layer.cornerRadius = 6.0f;
    [statusCard addSubview:_dsStatusBadge];

    _dsBadgeLabel = [[UILabel alloc] init];
    _dsBadgeLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _dsBadgeLabel.text = isSupported ? @"Tương thích" : @"Không hỗ trợ";
    _dsBadgeLabel.textColor = isSupported ? [UIColor colorWithRed:46/255.0 green:204/255.0 blue:113/255.0 alpha:1.0] : [UIColor colorWithRed:231/255.0 green:76/255.0 blue:60/255.0 alpha:1.0];
    _dsBadgeLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightBold];
    [_dsStatusBadge addSubview:_dsBadgeLabel];

    // 3. Central OPEN HUD Button
    _mainButton = [MainButton buttonWithType:UIButtonTypeSystem];
    _mainButton.translatesAutoresizingMaskIntoConstraints = NO;
    [_mainButton addTarget:self action:@selector(tapMainButton:) forControlEvents:UIControlEventTouchUpInside];
    [_mainButton setTitle:@"OPEN HUD" forState:UIControlStateNormal];
    [_mainButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    _mainButton.titleLabel.font = [UIFont systemFontOfSize:22 weight:UIFontWeightHeavy];
    _mainButton.backgroundColor = [UIColor colorWithRed:0/255.0 green:210/255.0 blue:180/255.0 alpha:1.0];
    _mainButton.layer.cornerRadius = 32.0f;
    _mainButton.layer.shadowColor = [UIColor colorWithRed:0/255.0 green:210/255.0 blue:180/255.0 alpha:0.45].CGColor;
    _mainButton.layer.shadowOffset = CGSizeMake(0, 8);
    _mainButton.layer.shadowRadius = 16.0f;
    _mainButton.layer.shadowOpacity = 0.8f;
    [_homeView addSubview:_mainButton];

    _buttonSubLabel = [[UILabel alloc] init];
    _buttonSubLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _buttonSubLabel.text = @"Nhấn để bật menu ESP trong game";
    _buttonSubLabel.textColor = [UIColor colorWithRed:139/255.0 green:148/255.0 blue:158/255.0 alpha:1.0];
    _buttonSubLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    _buttonSubLabel.textAlignment = NSTextAlignmentCenter;
    [_homeView addSubview:_buttonSubLabel];

    // Layout Constraints for Home View
    [NSLayoutConstraint activateConstraints:@[
        [titleLabel.topAnchor constraintEqualToAnchor:_homeView.topAnchor constant:28.0f],
        [titleLabel.centerXAnchor constraintEqualToAnchor:_homeView.centerXAnchor],

        [subTitleLabel.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:4.0f],
        [subTitleLabel.centerXAnchor constraintEqualToAnchor:_homeView.centerXAnchor],

        [statusCard.topAnchor constraintEqualToAnchor:subTitleLabel.bottomAnchor constant:28.0f],
        [statusCard.leadingAnchor constraintEqualToAnchor:_homeView.leadingAnchor constant:24.0f],
        [statusCard.trailingAnchor constraintEqualToAnchor:_homeView.trailingAnchor constant:-24.0f],
        [statusCard.heightAnchor constraintEqualToConstant:90.0f],

        [appleIcon.leadingAnchor constraintEqualToAnchor:statusCard.leadingAnchor constant:16.0f],
        [appleIcon.topAnchor constraintEqualToAnchor:statusCard.topAnchor constant:14.0f],
        [appleIcon.widthAnchor constraintEqualToConstant:18.0f],
        [appleIcon.heightAnchor constraintEqualToConstant:18.0f],

        [_iosVersionLabel.leadingAnchor constraintEqualToAnchor:appleIcon.trailingAnchor constant:8.0f],
        [_iosVersionLabel.centerYAnchor constraintEqualToAnchor:appleIcon.centerYAnchor],

        [systemTag.trailingAnchor constraintEqualToAnchor:statusCard.trailingAnchor constant:-16.0f],
        [systemTag.centerYAnchor constraintEqualToAnchor:appleIcon.centerYAnchor],

        [cardSep.topAnchor constraintEqualToAnchor:appleIcon.bottomAnchor constant:12.0f],
        [cardSep.leadingAnchor constraintEqualToAnchor:statusCard.leadingAnchor constant:16.0f],
        [cardSep.trailingAnchor constraintEqualToAnchor:statusCard.trailingAnchor constant:-16.0f],
        [cardSep.heightAnchor constraintEqualToConstant:1.0f],

        [dotView.leadingAnchor constraintEqualToAnchor:statusCard.leadingAnchor constant:16.0f],
        [dotView.topAnchor constraintEqualToAnchor:cardSep.bottomAnchor constant:14.0f],
        [dotView.widthAnchor constraintEqualToConstant:8.0f],
        [dotView.heightAnchor constraintEqualToConstant:8.0f],

        [_dsStatusLabel.leadingAnchor constraintEqualToAnchor:dotView.trailingAnchor constant:8.0f],
        [_dsStatusLabel.centerYAnchor constraintEqualToAnchor:dotView.centerYAnchor],

        [_dsStatusBadge.trailingAnchor constraintEqualToAnchor:statusCard.trailingAnchor constant:-16.0f],
        [_dsStatusBadge.centerYAnchor constraintEqualToAnchor:dotView.centerYAnchor],
        [_dsStatusBadge.heightAnchor constraintEqualToConstant:22.0f],

        [_dsBadgeLabel.leadingAnchor constraintEqualToAnchor:_dsStatusBadge.leadingAnchor constant:8.0f],
        [_dsBadgeLabel.trailingAnchor constraintEqualToAnchor:_dsStatusBadge.trailingAnchor constant:-8.0f],
        [_dsBadgeLabel.centerYAnchor constraintEqualToAnchor:_dsStatusBadge.centerYAnchor],

        [_mainButton.centerXAnchor constraintEqualToAnchor:_homeView.centerXAnchor],
        [_mainButton.centerYAnchor constraintEqualToAnchor:_homeView.centerYAnchor constant:50.0f],
        [_mainButton.widthAnchor constraintEqualToConstant:240.0f],
        [_mainButton.heightAnchor constraintEqualToConstant:64.0f],

        [_buttonSubLabel.topAnchor constraintEqualToAnchor:_mainButton.bottomAnchor constant:18.0f],
        [_buttonSubLabel.centerXAnchor constraintEqualToAnchor:_homeView.centerXAnchor],
    ]];
}

#pragma mark - Setting View

- (void)setupSettingView
{
    _settingView = [[UIView alloc] init];
    _settingView.translatesAutoresizingMaskIntoConstraints = NO;
    _settingView.hidden = YES;
    [self.backgroundView addSubview:_settingView];

    UILayoutGuide *safeArea = self.view.safeAreaLayoutGuide;

    [NSLayoutConstraint activateConstraints:@[
        [_settingView.topAnchor constraintEqualToAnchor:safeArea.topAnchor],
        [_settingView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_settingView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_settingView.bottomAnchor constraintEqualToAnchor:_bottomTabBar.topAnchor],
    ]];

    // 1. Setting Header Title
    UILabel *settingTitle = [[UILabel alloc] init];
    settingTitle.translatesAutoresizingMaskIntoConstraints = NO;
    settingTitle.text = @"Cài Đặt";
    settingTitle.textColor = UIColor.whiteColor;
    settingTitle.font = [UIFont systemFontOfSize:30 weight:UIFontWeightHeavy];
    settingTitle.textAlignment = NSTextAlignmentCenter;
    [_settingView addSubview:settingTitle];

    UILabel *settingSubTitle = [[UILabel alloc] init];
    settingSubTitle.translatesAutoresizingMaskIntoConstraints = NO;
    settingSubTitle.text = @"Thông tin & Tác giả";
    settingSubTitle.textColor = [UIColor colorWithRed:139/255.0 green:148/255.0 blue:158/255.0 alpha:1.0];
    settingSubTitle.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    settingSubTitle.textAlignment = NSTextAlignmentCenter;
    [_settingView addSubview:settingSubTitle];

    // 2. Developer Card (DLX07)
    UIView *devCard = [[UIView alloc] init];
    devCard.translatesAutoresizingMaskIntoConstraints = NO;
    devCard.backgroundColor = [UIColor colorWithRed:22/255.0 green:27/255.0 blue:34/255.0 alpha:0.95];
    devCard.layer.cornerRadius = 16.0f;
    devCard.layer.borderColor = [UIColor colorWithRed:33/255.0 green:38/255.0 blue:45/255.0 alpha:1.0].CGColor;
    devCard.layer.borderWidth = 1.0f;
    [_settingView addSubview:devCard];

    UIImageView *devAvatar = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"person.crop.circle.fill"]];
    devAvatar.translatesAutoresizingMaskIntoConstraints = NO;
    devAvatar.tintColor = [UIColor colorWithRed:0/255.0 green:210/255.0 blue:180/255.0 alpha:1.0];
    devAvatar.contentMode = UIViewContentModeScaleAspectFit;
    [devCard addSubview:devAvatar];

    UILabel *devHeader = [[UILabel alloc] init];
    devHeader.translatesAutoresizingMaskIntoConstraints = NO;
    devHeader.text = @"NGƯỜI PHÁT TRIỂN";
    devHeader.textColor = [UIColor colorWithRed:139/255.0 green:148/255.0 blue:158/255.0 alpha:1.0];
    devHeader.font = [UIFont systemFontOfSize:12 weight:UIFontWeightBold];
    [devCard addSubview:devHeader];

    UILabel *devName = [[UILabel alloc] init];
    devName.translatesAutoresizingMaskIntoConstraints = NO;
    devName.text = @"DLX07";
    devName.textColor = UIColor.whiteColor;
    devName.font = [UIFont systemFontOfSize:24 weight:UIFontWeightHeavy];
    [devCard addSubview:devName];

    // 3. App Details Card
    UIView *infoCard = [[UIView alloc] init];
    infoCard.translatesAutoresizingMaskIntoConstraints = NO;
    infoCard.backgroundColor = [UIColor colorWithRed:22/255.0 green:27/255.0 blue:34/255.0 alpha:0.95];
    infoCard.layer.cornerRadius = 16.0f;
    infoCard.layer.borderColor = [UIColor colorWithRed:33/255.0 green:38/255.0 blue:45/255.0 alpha:1.0].CGColor;
    infoCard.layer.borderWidth = 1.0f;
    [_settingView addSubview:infoCard];

    auto addInfoRow = ^UIView *(NSString *title, NSString *value, UIView *topAnchorView) {
        UIView *row = [[UIView alloc] init];
        row.translatesAutoresizingMaskIntoConstraints = NO;
        [infoCard addSubview:row];

        UILabel *tLabel = [[UILabel alloc] init];
        tLabel.translatesAutoresizingMaskIntoConstraints = NO;
        tLabel.text = title;
        tLabel.textColor = [UIColor colorWithRed:139/255.0 green:148/255.0 blue:158/255.0 alpha:1.0];
        tLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
        [row addSubview:tLabel];

        UILabel *vLabel = [[UILabel alloc] init];
        vLabel.translatesAutoresizingMaskIntoConstraints = NO;
        vLabel.text = value;
        vLabel.textColor = UIColor.whiteColor;
        vLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightBold];
        [row addSubview:vLabel];

        [NSLayoutConstraint activateConstraints:@[
            [row.leadingAnchor constraintEqualToAnchor:infoCard.leadingAnchor constant:16.0f],
            [row.trailingAnchor constraintEqualToAnchor:infoCard.trailingAnchor constant:-16.0f],
            [row.heightAnchor constraintEqualToConstant:32.0f],
            [tLabel.leadingAnchor constraintEqualToAnchor:row.leadingAnchor],
            [tLabel.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
            [vLabel.trailingAnchor constraintEqualToAnchor:row.trailingAnchor],
            [vLabel.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        ]];

        if (topAnchorView) {
            [row.topAnchor constraintEqualToAnchor:topAnchorView.bottomAnchor constant:8.0f].active = YES;
        } else {
            [row.topAnchor constraintEqualToAnchor:infoCard.topAnchor constant:12.0f].active = YES;
        }
        return row;
    };

    UIView *r1 = addInfoRow(@"Ứng dụng", @"DarkPubg", nil);
    UIView *r2 = addInfoRow(@"Phiên bản", @"1.0-1", r1);
    UIView *r3 = addInfoRow(@"Trò chơi", @"PUBG Mobile", r2);
    UIView *r4 = addInfoRow(@"Kiểu can thiệp", @"DarkSword Kernel (TrollStore)", r3);

    // 4. Note Card
    UIView *noteCard = [[UIView alloc] init];
    noteCard.translatesAutoresizingMaskIntoConstraints = NO;
    noteCard.backgroundColor = [UIColor colorWithRed:22/255.0 green:27/255.0 blue:34/255.0 alpha:0.6];
    noteCard.layer.cornerRadius = 12.0f;
    [_settingView addSubview:noteCard];

    UILabel *noteLabel = [[UILabel alloc] init];
    noteLabel.translatesAutoresizingMaskIntoConstraints = NO;
    noteLabel.text = @"DarkPubg hoạt động trực tiếp thông qua TrollStore trên iOS mà không cần Jailbreak.";
    noteLabel.textColor = [UIColor colorWithRed:139/255.0 green:148/255.0 blue:158/255.0 alpha:1.0];
    noteLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightRegular];
    noteLabel.numberOfLines = 0;
    noteLabel.textAlignment = NSTextAlignmentCenter;
    [noteCard addSubview:noteLabel];

    // Layout Constraints for Setting View
    [NSLayoutConstraint activateConstraints:@[
        [settingTitle.topAnchor constraintEqualToAnchor:_settingView.topAnchor constant:28.0f],
        [settingTitle.centerXAnchor constraintEqualToAnchor:_settingView.centerXAnchor],

        [settingSubTitle.topAnchor constraintEqualToAnchor:settingTitle.bottomAnchor constant:4.0f],
        [settingSubTitle.centerXAnchor constraintEqualToAnchor:_settingView.centerXAnchor],

        [devCard.topAnchor constraintEqualToAnchor:settingSubTitle.bottomAnchor constant:28.0f],
        [devCard.leadingAnchor constraintEqualToAnchor:_settingView.leadingAnchor constant:24.0f],
        [devCard.trailingAnchor constraintEqualToAnchor:_settingView.trailingAnchor constant:-24.0f],
        [devCard.heightAnchor constraintEqualToConstant:84.0f],

        [devAvatar.leadingAnchor constraintEqualToAnchor:devCard.leadingAnchor constant:18.0f],
        [devAvatar.centerYAnchor constraintEqualToAnchor:devCard.centerYAnchor],
        [devAvatar.widthAnchor constraintEqualToConstant:48.0f],
        [devAvatar.heightAnchor constraintEqualToConstant:48.0f],

        [devHeader.leadingAnchor constraintEqualToAnchor:devAvatar.trailingAnchor constant:16.0f],
        [devHeader.topAnchor constraintEqualToAnchor:devCard.topAnchor constant:18.0f],

        [devName.leadingAnchor constraintEqualToAnchor:devAvatar.trailingAnchor constant:16.0f],
        [devName.topAnchor constraintEqualToAnchor:devHeader.bottomAnchor constant:2.0f],

        [infoCard.topAnchor constraintEqualToAnchor:devCard.bottomAnchor constant:20.0f],
        [infoCard.leadingAnchor constraintEqualToAnchor:_settingView.leadingAnchor constant:24.0f],
        [infoCard.trailingAnchor constraintEqualToAnchor:_settingView.trailingAnchor constant:-24.0f],
        [infoCard.bottomAnchor constraintEqualToAnchor:r4.bottomAnchor constant:14.0f],

        [noteCard.topAnchor constraintEqualToAnchor:infoCard.bottomAnchor constant:20.0f],
        [noteCard.leadingAnchor constraintEqualToAnchor:_settingView.leadingAnchor constant:24.0f],
        [noteCard.trailingAnchor constraintEqualToAnchor:_settingView.trailingAnchor constant:-24.0f],

        [noteLabel.topAnchor constraintEqualToAnchor:noteCard.topAnchor constant:12.0f],
        [noteLabel.bottomAnchor constraintEqualToAnchor:noteCard.bottomAnchor constant:-12.0f],
        [noteLabel.leadingAnchor constraintEqualToAnchor:noteCard.leadingAnchor constant:16.0f],
        [noteLabel.trailingAnchor constraintEqualToAnchor:noteCard.trailingAnchor constant:-16.0f],
    ]];
}

#pragma mark - Lifecycle

- (void)viewDidLoad
{
    [super viewDidLoad];

    _impactFeedbackGenerator = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];

    // Force active game to PUBG Mobile (AOV temporarily hidden)
    [[NSUserDefaults standardUserDefaults] setInteger:1 forKey:@"DSActiveGame"];
    [[NSUserDefaults standardUserDefaults] synchronize];
#if USE_DARKSWORD
    DSBridgeSetActiveGame(1);
#endif

    [self registerNotifications];
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    [self toggleHUDAfterLaunch];
}

- (void)reloadMainButtonState
{
    _isRemoteHUDActive = [self isHUDEnabled];

    dispatch_async(dispatch_get_main_queue(), ^{
        if (self->_isRemoteHUDActive) {
            [self->_mainButton setTitle:@"EXIT HUD" forState:UIControlStateNormal];
            self->_mainButton.backgroundColor = [UIColor colorWithRed:231/255.0 green:76/255.0 blue:60/255.0 alpha:1.0]; // Red
            self->_mainButton.layer.shadowColor = [UIColor colorWithRed:231/255.0 green:76/255.0 blue:60/255.0 alpha:0.5].CGColor;
            self->_buttonSubLabel.text = @"DarkPubg đang hoạt động trong game";
        } else {
            [self->_mainButton setTitle:@"OPEN HUD" forState:UIControlStateNormal];
            self->_mainButton.backgroundColor = [UIColor colorWithRed:0/255.0 green:210/255.0 blue:180/255.0 alpha:1.0]; // Cyan
            self->_mainButton.layer.shadowColor = [UIColor colorWithRed:0/255.0 green:210/255.0 blue:180/255.0 alpha:0.45].CGColor;
            self->_buttonSubLabel.text = @"Nhấn để bật menu ESP trong game";
        }
    });
}

- (void)tapMainButton:(UIButton *)sender
{
    BOOL isNowEnabled = [self isHUDEnabled];
#if USE_DARKSWORD
    if (!isNowEnabled) {
        [self showDSProgressOverlay];
    } else {
        [self hideDSProgressOverlay];
    }
#endif
    [self setHUDEnabled:!isNowEnabled];
    isNowEnabled = !isNowEnabled;

    if (isNowEnabled)
    {
        [_impactFeedbackGenerator prepare];
        int anyToken;
        __weak typeof(self) weakSelf = self;
        notify_register_dispatch(NOTIFY_LAUNCHED_HUD, &anyToken, dispatch_get_main_queue(), ^(int token) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            notify_cancel(token);
#if USE_DARKSWORD
            [strongSelf hideDSProgressOverlay];
#endif
            [strongSelf->_impactFeedbackGenerator impactOccurred];
            [strongSelf reloadMainButtonState];
            [strongSelf.backgroundView setUserInteractionEnabled:YES];
        });

        [self.backgroundView setUserInteractionEnabled:NO];
    }
    else
    {
        [self.backgroundView setUserInteractionEnabled:NO];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
            dispatch_async(dispatch_get_main_queue(), ^{
                [self reloadMainButtonState];
                [self.backgroundView setUserInteractionEnabled:YES];
            });
        });
    }
}

#pragma mark - DarkSword Progress Overlay

#if USE_DARKSWORD
- (void)showDSProgressOverlay
{
    if (!_dsProgressOverlay) {
        UIView *overlay = [[UIView alloc] initWithFrame:self.view.bounds];
        overlay.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        overlay.backgroundColor = [UIColor colorWithWhite:0.12 alpha:0.96];

        UIProgressView *bar = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleBar];
        bar.translatesAutoresizingMaskIntoConstraints = NO;
        bar.progressTintColor = [UIColor colorWithRed:0/255.0 green:210/255.0 blue:180/255.0 alpha:1.0];
        bar.trackTintColor = [UIColor colorWithWhite:1.0 alpha:0.15];
        bar.progress = 0.0;
        [overlay addSubview:bar];

        UILabel *label = [[UILabel alloc] init];
        label.translatesAutoresizingMaskIntoConstraints = NO;
        label.textColor = UIColor.whiteColor;
        label.font = [UIFont monospacedDigitSystemFontOfSize:15 weight:UIFontWeightSemibold];
        label.textAlignment = NSTextAlignmentCenter;
        label.numberOfLines = 0;
        label.lineBreakMode = NSLineBreakByWordWrapping;
        label.text = [NSString stringWithFormat:@"%@\n0%%", NSLocalizedString(@"Initializing DarkPubg", nil)];
        [overlay addSubview:label];

        [NSLayoutConstraint activateConstraints:@[
            [bar.centerYAnchor constraintEqualToAnchor:overlay.centerYAnchor constant:-12.0],
            [bar.leadingAnchor constraintEqualToAnchor:overlay.leadingAnchor constant:44.0],
            [bar.trailingAnchor constraintEqualToAnchor:overlay.trailingAnchor constant:-44.0],
            [bar.heightAnchor constraintEqualToConstant:4.0],
            [label.topAnchor constraintEqualToAnchor:bar.bottomAnchor constant:18.0],
            [label.leadingAnchor constraintEqualToAnchor:overlay.leadingAnchor constant:28.0],
            [label.trailingAnchor constraintEqualToAnchor:overlay.trailingAnchor constant:-28.0],
            [label.bottomAnchor constraintLessThanOrEqualToAnchor:overlay.bottomAnchor constant:-40.0],
        ]];
        _dsProgressOverlay = overlay;
        _dsProgressBar = bar;
        _dsProgressLabel = label;
    }

    if (!_dsProgressOverlay.superview) [self.view addSubview:_dsProgressOverlay];
    [self.view bringSubviewToFront:_dsProgressOverlay];
    _dsProgressOverlay.hidden = NO;
    _dsProgressBar.progressTintColor = [UIColor colorWithRed:0/255.0 green:210/255.0 blue:180/255.0 alpha:1.0];
    _dsProgressBar.progress = 0.0;
    _dsProgressLabel.numberOfLines = 0;
    _dsProgressLabel.lineBreakMode = NSLineBreakByWordWrapping;
    _dsProgressLabel.font = [UIFont monospacedDigitSystemFontOfSize:15 weight:UIFontWeightSemibold];
    _dsProgressLabel.textAlignment = NSTextAlignmentCenter;
    _dsProgressLabel.text = [NSString stringWithFormat:@"%@\n0%%", NSLocalizedString(@"Initializing DarkPubg", nil)];
}

- (void)hideDSProgressOverlay
{
    _dsProgressOverlay.hidden = YES;
}

- (void)showDSFailure:(NSString *)error
{
    if (!_dsProgressOverlay) [self showDSProgressOverlay];
    if (!_dsProgressOverlay.superview) [self.view addSubview:_dsProgressOverlay];
    [self.view bringSubviewToFront:_dsProgressOverlay];
    _dsProgressOverlay.hidden = NO;
    _dsProgressBar.progress = 1.0f;
    _dsProgressBar.progressTintColor = UIColor.systemRedColor;
    _dsProgressLabel.numberOfLines = 0;
    _dsProgressLabel.lineBreakMode = NSLineBreakByWordWrapping;
    _dsProgressLabel.font = [UIFont monospacedSystemFontOfSize:13 weight:UIFontWeightRegular];
    _dsProgressLabel.textAlignment = NSTextAlignmentLeft;
    _dsProgressLabel.text = [NSString stringWithFormat:@"%@\n\n%@",
        NSLocalizedString(@"DarkPubg initialization failed", nil),
        error.length > 0 ? error : NSLocalizedString(@"Unknown error", nil)];
}

- (void)dsProgressDidChange:(NSNotification *)note
{
    if (!DSBridgeIsRunning()) {
        if (DSBridgeHUDEnabled()) [self hideDSProgressOverlay];
        return;
    }
    double p = DSBridgeProgress();
    if (p < 0.0) p = 0.0;
    if (p > 1.0) p = 1.0;
    _dsProgressBar.progress = (float)p;
    NSString *stage = DSBridgeStage();
    if (stage.length == 0) stage = NSLocalizedString(@"Initializing DarkPubg", nil);
    _dsProgressLabel.text = [NSString stringWithFormat:@"%@\n%d%%", stage, (int)llround(p * 100.0)];
}
#endif

#pragma mark - TSSettingsControllerDelegate

- (BOOL)settingHighlightedWithKey:(NSString * _Nonnull)key
{
    [self loadUserDefaults:NO];
    NSNumber *mode = [_userDefaults objectForKey:key];
    return mode != nil ? [mode boolValue] : NO;
}

- (void)settingDidSelectWithKey:(NSString * _Nonnull)key
{
    BOOL highlighted = [self settingHighlightedWithKey:key];
    [_userDefaults setObject:@(!highlighted) forKey:key];
    [self saveUserDefaults];
}

#pragma mark - Rotation & Orientation

- (BOOL)shouldAutorotate { return NO; }
- (UIInterfaceOrientationMask)supportedInterfaceOrientations { return UIInterfaceOrientationMaskPortrait; }
- (UIInterfaceOrientation)preferredInterfaceOrientationForPresentation { return UIInterfaceOrientationPortrait; }

- (void)reloadModeButtonState {}
- (void)verticalSizeClassUpdated {}

- (void)toggleHUDNotificationReceived:(NSNotification *)notification {
    NSString *toggleAction = notification.userInfo[kToggleHUDAfterLaunchNotificationActionKey];
    if (!toggleAction) {
        [self toggleHUDAfterLaunch];
    } else if ([toggleAction isEqualToString:kToggleHUDAfterLaunchNotificationActionToggleOn]) {
        [self toggleOnHUDAfterLaunch];
    } else if ([toggleAction isEqualToString:kToggleHUDAfterLaunchNotificationActionToggleOff]) {
        [self toggleOffHUDAfterLaunch];
    }
}

- (void)toggleHUDAfterLaunch {
    if ([RootViewController shouldToggleHUDAfterLaunch]) {
        [RootViewController setShouldToggleHUDAfterLaunch:NO];
        [self tapMainButton:_mainButton];
    }
}

- (void)toggleOnHUDAfterLaunch {
    if ([RootViewController shouldToggleHUDAfterLaunch]) {
        [RootViewController setShouldToggleHUDAfterLaunch:NO];
        if (!_isRemoteHUDActive) {
            [self tapMainButton:_mainButton];
        }
    }
}

- (void)toggleOffHUDAfterLaunch {
    if ([RootViewController shouldToggleHUDAfterLaunch]) {
        [RootViewController setShouldToggleHUDAfterLaunch:NO];
        if (_isRemoteHUDActive) {
            [self tapMainButton:_mainButton];
        }
    }
}

- (void)motionEnded:(UIEventSubtype)motion withEvent:(UIEvent *)event {
    if (motion == UIEventSubtypeMotionShake) {
        UIAlertController *alertController = [UIAlertController alertControllerWithTitle:@"DarkPubg" message:@"Bạn có muốn đặt lại cài đặt không?" preferredStyle:UIAlertControllerStyleAlert];
        [alertController addAction:[UIAlertAction actionWithTitle:@"Huỷ" style:UIAlertActionStyleCancel handler:nil]];
        [alertController addAction:[UIAlertAction actionWithTitle:@"Đặt lại" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
            [self resetUserDefaults];
        }]];
        [self presentViewController:alertController animated:YES completion:nil];
    }
}

- (void)resetUserDefaults
{
    NSString *bundleIdentifier = [[NSBundle mainBundle] bundleIdentifier];
    if (bundleIdentifier) {
        [GetStandardUserDefaults() removePersistentDomainForName:bundleIdentifier];
        [GetStandardUserDefaults() synchronize];
    }
    BOOL removed = [[NSFileManager defaultManager] removeItemAtPath:(JBROOT_PATH_NSSTRING(USER_DEFAULTS_PATH)) error:nil];
    if (removed) {
        [self setHUDEnabled:NO];
        [[UIApplication sharedApplication] terminateWithSuccess];
    }
}

- (void)loadUserDefaults:(BOOL)forceReload
{
    if (forceReload || !_userDefaults) {
        _userDefaults = [[NSDictionary dictionaryWithContentsOfFile:(JBROOT_PATH_NSSTRING(USER_DEFAULTS_PATH))] mutableCopy] ?: [NSMutableDictionary dictionary];
    }
}

- (void)saveUserDefaults
{
    if (![_userDefaults writeToFile:(JBROOT_PATH_NSSTRING(USER_DEFAULTS_PATH)) atomically:YES]) return;
    notify_post(NOTIFY_RELOAD_HUD);
}

@end
