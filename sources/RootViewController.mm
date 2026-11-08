//
//  RootViewController.mm
//  DarkPubg
//
//  Created by Lessica on 2024/1/24.
//  Redesigned by DLX07 on 2026/11/08.
//

#import <notify.h>
#import <sys/sysctl.h>

#ifdef __cplusplus
extern "C" {
#endif
#import "libproc.h"
#ifdef __cplusplus
}
#endif

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

static NSString *CurrentLanguage(void) {
    NSString *lang = [[NSUserDefaults standardUserDefaults] stringForKey:@"AppLanguage"];
    if (!lang || lang.length == 0) return @"vi";
    return lang;
}

static BOOL IsEnglish(void) {
    return [CurrentLanguage() isEqualToString:@"en"];
}

static BOOL CheckDarkSwordSupport(NSString **outVersionStr, NSString **outStatusStr) {
    NSString *version = [[UIDevice currentDevice] systemVersion];
    if (outVersionStr) *outVersionStr = [NSString stringWithFormat:@"iOS %@", version];

    BOOL supported = NO;
    if (version.length > 0) {
        // Supported ranges specified by user: 17.0 - 17.7, 18.0 - 18.7.1, 26.0 - 26.0.1
        if ([version compare:@"17.0" options:NSNumericSearch] != NSOrderedAscending &&
            [version compare:@"17.7.99" options:NSNumericSearch] == NSOrderedAscending) {
            supported = YES;
        }
        else if ([version compare:@"18.0" options:NSNumericSearch] != NSOrderedAscending &&
                 [version compare:@"18.7.1" options:NSNumericSearch] != NSOrderedDescending) {
            supported = YES;
        }
        else if ([version compare:@"26.0" options:NSNumericSearch] != NSOrderedAscending &&
                 [version compare:@"26.0.1" options:NSNumericSearch] != NSOrderedDescending) {
            supported = YES;
        }
    }

    if (outStatusStr) {
        if (supported) {
            *outStatusStr = IsEnglish() ? @"DarkSword: Supported" : @"DarkSword: Đã hỗ trợ";
        } else {
            *outStatusStr = IsEnglish() ? @"DarkSword: Unsupported" : @"DarkSword: Chưa hỗ trợ";
        }
    }
    return supported;
}

static BOOL IsPUBGProcessRunning(void) {
    // 1. Primary check via proc_listallpids
    int count = proc_listallpids(NULL, 0);
    if (count > 0 && count < 100000) {
        pid_t *pids = (pid_t *)malloc((size_t)count * sizeof(pid_t));
        if (pids) {
            int got = proc_listallpids(pids, count * (int)sizeof(pid_t));
            if (got > 0) {
                if (got > count) got = count;
                char name[1024];
                char path[1024];
                for (int i = 0; i < got; i++) {
                    pid_t p = pids[i];
                    if (p <= 0) continue;

                    memset(name, 0, sizeof(name));
                    if (proc_name(p, name, sizeof(name) - 1) > 0) {
                        if (strcasestr(name, "ShadowTracker") != NULL ||
                            strcasestr(name, "PUBG") != NULL) {
                            free(pids);
                            return YES;
                        }
                    }

                    memset(path, 0, sizeof(path));
                    if (proc_pidpath(p, path, sizeof(path) - 1) > 0) {
                        if (strcasestr(path, "ShadowTracker") != NULL ||
                            strcasestr(path, "PUBG") != NULL) {
                            free(pids);
                            return YES;
                        }
                    }
                }
            }
            free(pids);
        }
    }

    // 2. Secondary check with proc_listpids(PROC_ALL_PIDS)
    int bytes = proc_listpids(1 /* PROC_ALL_PIDS */, 0, NULL, 0);
    if (bytes > 0 && bytes < 400000) {
        pid_t *pids = (pid_t *)malloc((size_t)bytes);
        if (pids) {
            int gotBytes = proc_listpids(1, 0, pids, bytes);
            int got = gotBytes / (int)sizeof(pid_t);
            char name[1024];
            for (int i = 0; i < got; i++) {
                pid_t p = pids[i];
                if (p <= 0) continue;
                memset(name, 0, sizeof(name));
                if (proc_name(p, name, sizeof(name) - 1) > 0) {
                    if (strcasestr(name, "ShadowTracker") != NULL ||
                        strcasestr(name, "PUBG") != NULL) {
                        free(pids);
                        return YES;
                    }
                }
            }
            free(pids);
        }
    }

    return NO;
}

@implementation RootViewController {
    NSMutableDictionary *_userDefaults;
    MainButton *_mainButton;
    UILabel *_buttonSubLabel;

    // Tab Navigation Containers
    UIView *_homeView;
    UIView *_settingView;
    UIScrollView *_settingScrollView;
    UIView *_settingContentView;
    UIView *_bottomTabBar;
    UIButton *_homeTabButton;
    UIButton *_settingTabButton;
    NSInteger _selectedTabIndex;

    // Home localized labels
    UILabel *_homeTitleLabel;
    UILabel *_homeSubTitleLabel;
    UILabel *_iosVersionLabel;
    UILabel *_systemTagLabel;
    UIView *_statusDotView;
    UILabel *_dsStatusLabel;
    UIView *_dsStatusBadge;
    UILabel *_dsBadgeLabel;

    // Setting localized labels
    UILabel *_settingTitleLabel;
    UILabel *_settingSubTitleLabel;
    UILabel *_langHeaderLabel;
    UISegmentedControl *_langSegmentedControl;
    UILabel *_devHeaderLabel;
    UILabel *_devNameLabel;

    UILabel *_infoRow1Title;
    UILabel *_infoRow2Title;
    UILabel *_infoRow3Title;
    UILabel *_infoRow4Title;
    UILabel *_noteLabel;

    // Red warning popup
    UIView *_warningPopupOverlay;
    UILabel *_warningTitleLabel;
    UILabel *_warningSubLabel;
    UIButton *_warningDismissBtn;

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
    [self applyLanguageTexts];
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
    _homeTitleLabel = [[UILabel alloc] init];
    _homeTitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _homeTitleLabel.text = @"DarkPubg";
    _homeTitleLabel.textColor = UIColor.whiteColor;
    _homeTitleLabel.font = [UIFont systemFontOfSize:30 weight:UIFontWeightHeavy];
    _homeTitleLabel.textAlignment = NSTextAlignmentCenter;
    [_homeView addSubview:_homeTitleLabel];

    _homeSubTitleLabel = [[UILabel alloc] init];
    _homeSubTitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _homeSubTitleLabel.text = @"PUBG Mobile Edition";
    _homeSubTitleLabel.textColor = [UIColor colorWithRed:0/255.0 green:210/255.0 blue:180/255.0 alpha:1.0];
    _homeSubTitleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    _homeSubTitleLabel.textAlignment = NSTextAlignmentCenter;
    [_homeView addSubview:_homeSubTitleLabel];

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
    _iosVersionLabel.textColor = UIColor.whiteColor;
    _iosVersionLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightBold];
    [statusCard addSubview:_iosVersionLabel];

    _systemTagLabel = [[UILabel alloc] init];
    _systemTagLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _systemTagLabel.textColor = [UIColor colorWithRed:139/255.0 green:148/255.0 blue:158/255.0 alpha:1.0];
    _systemTagLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
    [statusCard addSubview:_systemTagLabel];

    // Card Separator
    UIView *cardSep = [[UIView alloc] init];
    cardSep.translatesAutoresizingMaskIntoConstraints = NO;
    cardSep.backgroundColor = [UIColor colorWithRed:33/255.0 green:38/255.0 blue:45/255.0 alpha:1.0];
    [statusCard addSubview:cardSep];

    // Row 2: DarkSword Support Indicator
    _statusDotView = [[UIView alloc] init];
    _statusDotView.translatesAutoresizingMaskIntoConstraints = NO;
    _statusDotView.backgroundColor = isSupported ? [UIColor colorWithRed:46/255.0 green:204/255.0 blue:113/255.0 alpha:1.0] : [UIColor colorWithRed:231/255.0 green:76/255.0 blue:60/255.0 alpha:1.0];
    _statusDotView.layer.cornerRadius = 4.0f;
    [statusCard addSubview:_statusDotView];

    _dsStatusLabel = [[UILabel alloc] init];
    _dsStatusLabel.translatesAutoresizingMaskIntoConstraints = NO;
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
    _buttonSubLabel.textColor = [UIColor colorWithRed:139/255.0 green:148/255.0 blue:158/255.0 alpha:1.0];
    _buttonSubLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    _buttonSubLabel.textAlignment = NSTextAlignmentCenter;
    [_homeView addSubview:_buttonSubLabel];

    // Layout Constraints for Home View
    [NSLayoutConstraint activateConstraints:@[
        [_homeTitleLabel.topAnchor constraintEqualToAnchor:_homeView.topAnchor constant:28.0f],
        [_homeTitleLabel.centerXAnchor constraintEqualToAnchor:_homeView.centerXAnchor],

        [_homeSubTitleLabel.topAnchor constraintEqualToAnchor:_homeTitleLabel.bottomAnchor constant:4.0f],
        [_homeSubTitleLabel.centerXAnchor constraintEqualToAnchor:_homeView.centerXAnchor],

        [statusCard.topAnchor constraintEqualToAnchor:_homeSubTitleLabel.bottomAnchor constant:28.0f],
        [statusCard.leadingAnchor constraintEqualToAnchor:_homeView.leadingAnchor constant:24.0f],
        [statusCard.trailingAnchor constraintEqualToAnchor:_homeView.trailingAnchor constant:-24.0f],
        [statusCard.heightAnchor constraintEqualToConstant:90.0f],

        [appleIcon.leadingAnchor constraintEqualToAnchor:statusCard.leadingAnchor constant:16.0f],
        [appleIcon.topAnchor constraintEqualToAnchor:statusCard.topAnchor constant:14.0f],
        [appleIcon.widthAnchor constraintEqualToConstant:18.0f],
        [appleIcon.heightAnchor constraintEqualToConstant:18.0f],

        [_iosVersionLabel.leadingAnchor constraintEqualToAnchor:appleIcon.trailingAnchor constant:8.0f],
        [_iosVersionLabel.centerYAnchor constraintEqualToAnchor:appleIcon.centerYAnchor],

        [_systemTagLabel.trailingAnchor constraintEqualToAnchor:statusCard.trailingAnchor constant:-16.0f],
        [_systemTagLabel.centerYAnchor constraintEqualToAnchor:appleIcon.centerYAnchor],

        [cardSep.topAnchor constraintEqualToAnchor:appleIcon.bottomAnchor constant:12.0f],
        [cardSep.leadingAnchor constraintEqualToAnchor:statusCard.leadingAnchor constant:16.0f],
        [cardSep.trailingAnchor constraintEqualToAnchor:statusCard.trailingAnchor constant:-16.0f],
        [cardSep.heightAnchor constraintEqualToConstant:1.0f],

        [_statusDotView.leadingAnchor constraintEqualToAnchor:statusCard.leadingAnchor constant:16.0f],
        [_statusDotView.topAnchor constraintEqualToAnchor:cardSep.bottomAnchor constant:14.0f],
        [_statusDotView.widthAnchor constraintEqualToConstant:8.0f],
        [_statusDotView.heightAnchor constraintEqualToConstant:8.0f],

        [_dsStatusLabel.leadingAnchor constraintEqualToAnchor:_statusDotView.trailingAnchor constant:8.0f],
        [_dsStatusLabel.centerYAnchor constraintEqualToAnchor:_statusDotView.centerYAnchor],

        [_dsStatusBadge.trailingAnchor constraintEqualToAnchor:statusCard.trailingAnchor constant:-16.0f],
        [_dsStatusBadge.centerYAnchor constraintEqualToAnchor:_statusDotView.centerYAnchor],
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

    _settingScrollView = [[UIScrollView alloc] init];
    _settingScrollView.translatesAutoresizingMaskIntoConstraints = NO;
    _settingScrollView.showsVerticalScrollIndicator = NO;
    [_settingView addSubview:_settingScrollView];

    _settingContentView = [[UIView alloc] init];
    _settingContentView.translatesAutoresizingMaskIntoConstraints = NO;
    [_settingScrollView addSubview:_settingContentView];

    [NSLayoutConstraint activateConstraints:@[
        [_settingScrollView.topAnchor constraintEqualToAnchor:_settingView.topAnchor],
        [_settingScrollView.leadingAnchor constraintEqualToAnchor:_settingView.leadingAnchor],
        [_settingScrollView.trailingAnchor constraintEqualToAnchor:_settingView.trailingAnchor],
        [_settingScrollView.bottomAnchor constraintEqualToAnchor:_settingView.bottomAnchor],

        [_settingContentView.topAnchor constraintEqualToAnchor:_settingScrollView.topAnchor],
        [_settingContentView.leadingAnchor constraintEqualToAnchor:_settingScrollView.leadingAnchor],
        [_settingContentView.trailingAnchor constraintEqualToAnchor:_settingScrollView.trailingAnchor],
        [_settingContentView.bottomAnchor constraintEqualToAnchor:_settingScrollView.bottomAnchor],
        [_settingContentView.widthAnchor constraintEqualToAnchor:_settingScrollView.widthAnchor],
    ]];

    // 1. Setting Header Title
    _settingTitleLabel = [[UILabel alloc] init];
    _settingTitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _settingTitleLabel.textColor = UIColor.whiteColor;
    _settingTitleLabel.font = [UIFont systemFontOfSize:30 weight:UIFontWeightHeavy];
    _settingTitleLabel.textAlignment = NSTextAlignmentCenter;
    [_settingContentView addSubview:_settingTitleLabel];

    _settingSubTitleLabel = [[UILabel alloc] init];
    _settingSubTitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _settingSubTitleLabel.textColor = [UIColor colorWithRed:139/255.0 green:148/255.0 blue:158/255.0 alpha:1.0];
    _settingSubTitleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    _settingSubTitleLabel.textAlignment = NSTextAlignmentCenter;
    [_settingContentView addSubview:_settingSubTitleLabel];

    // 2. Language Selection Card
    UIView *langCard = [[UIView alloc] init];
    langCard.translatesAutoresizingMaskIntoConstraints = NO;
    langCard.backgroundColor = [UIColor colorWithRed:22/255.0 green:27/255.0 blue:34/255.0 alpha:0.95];
    langCard.layer.cornerRadius = 16.0f;
    langCard.layer.borderColor = [UIColor colorWithRed:33/255.0 green:38/255.0 blue:45/255.0 alpha:1.0].CGColor;
    langCard.layer.borderWidth = 1.0f;
    [_settingContentView addSubview:langCard];

    UIImageView *globeIcon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"globe"]];
    globeIcon.translatesAutoresizingMaskIntoConstraints = NO;
    globeIcon.tintColor = [UIColor colorWithRed:0/255.0 green:210/255.0 blue:180/255.0 alpha:1.0];
    globeIcon.contentMode = UIViewContentModeScaleAspectFit;
    [langCard addSubview:globeIcon];

    _langHeaderLabel = [[UILabel alloc] init];
    _langHeaderLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _langHeaderLabel.textColor = [UIColor colorWithRed:139/255.0 green:148/255.0 blue:158/255.0 alpha:1.0];
    _langHeaderLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightBold];
    [langCard addSubview:_langHeaderLabel];

    _langSegmentedControl = [[UISegmentedControl alloc] initWithItems:@[ @"Tiếng Việt", @"English" ]];
    _langSegmentedControl.translatesAutoresizingMaskIntoConstraints = NO;
    _langSegmentedControl.selectedSegmentIndex = IsEnglish() ? 1 : 0;
    if (@available(iOS 13.0, *)) {
        _langSegmentedControl.selectedSegmentTintColor = [UIColor colorWithRed:0/255.0 green:210/255.0 blue:180/255.0 alpha:0.85];
    }
    NSDictionary *segNormal = @{
        NSForegroundColorAttributeName: [UIColor colorWithWhite:1.0 alpha:0.75],
        NSFontAttributeName: [UIFont systemFontOfSize:13 weight:UIFontWeightMedium],
    };
    NSDictionary *segSelected = @{
        NSForegroundColorAttributeName: UIColor.whiteColor,
        NSFontAttributeName: [UIFont systemFontOfSize:13 weight:UIFontWeightBold],
    };
    [_langSegmentedControl setTitleTextAttributes:segNormal forState:UIControlStateNormal];
    [_langSegmentedControl setTitleTextAttributes:segSelected forState:UIControlStateSelected];
    [_langSegmentedControl addTarget:self action:@selector(langSegmentChanged:) forControlEvents:UIControlEventValueChanged];
    [langCard addSubview:_langSegmentedControl];

    [NSLayoutConstraint activateConstraints:@[
        [globeIcon.leadingAnchor constraintEqualToAnchor:langCard.leadingAnchor constant:16.0f],
        [globeIcon.topAnchor constraintEqualToAnchor:langCard.topAnchor constant:14.0f],
        [globeIcon.widthAnchor constraintEqualToConstant:18.0f],
        [globeIcon.heightAnchor constraintEqualToConstant:18.0f],

        [_langHeaderLabel.leadingAnchor constraintEqualToAnchor:globeIcon.trailingAnchor constant:8.0f],
        [_langHeaderLabel.centerYAnchor constraintEqualToAnchor:globeIcon.centerYAnchor],

        [_langSegmentedControl.topAnchor constraintEqualToAnchor:globeIcon.bottomAnchor constant:10.0f],
        [_langSegmentedControl.leadingAnchor constraintEqualToAnchor:langCard.leadingAnchor constant:16.0f],
        [_langSegmentedControl.trailingAnchor constraintEqualToAnchor:langCard.trailingAnchor constant:-16.0f],
        [_langSegmentedControl.heightAnchor constraintEqualToConstant:32.0f],
        [_langSegmentedControl.bottomAnchor constraintEqualToAnchor:langCard.bottomAnchor constant:-14.0f],
    ]];

    // 3. Developer Card (DLX07)
    UIView *devCard = [[UIView alloc] init];
    devCard.translatesAutoresizingMaskIntoConstraints = NO;
    devCard.backgroundColor = [UIColor colorWithRed:22/255.0 green:27/255.0 blue:34/255.0 alpha:0.95];
    devCard.layer.cornerRadius = 16.0f;
    devCard.layer.borderColor = [UIColor colorWithRed:33/255.0 green:38/255.0 blue:45/255.0 alpha:1.0].CGColor;
    devCard.layer.borderWidth = 1.0f;
    [_settingContentView addSubview:devCard];

    UIImageView *devAvatar = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"person.crop.circle.fill"]];
    devAvatar.translatesAutoresizingMaskIntoConstraints = NO;
    devAvatar.tintColor = [UIColor colorWithRed:0/255.0 green:210/255.0 blue:180/255.0 alpha:1.0];
    devAvatar.contentMode = UIViewContentModeScaleAspectFit;
    [devCard addSubview:devAvatar];

    _devHeaderLabel = [[UILabel alloc] init];
    _devHeaderLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _devHeaderLabel.textColor = [UIColor colorWithRed:139/255.0 green:148/255.0 blue:158/255.0 alpha:1.0];
    _devHeaderLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightBold];
    [devCard addSubview:_devHeaderLabel];

    _devNameLabel = [[UILabel alloc] init];
    _devNameLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _devNameLabel.text = @"DLX07";
    _devNameLabel.textColor = UIColor.whiteColor;
    _devNameLabel.font = [UIFont systemFontOfSize:24 weight:UIFontWeightHeavy];
    [devCard addSubview:_devNameLabel];

    [NSLayoutConstraint activateConstraints:@[
        [devAvatar.leadingAnchor constraintEqualToAnchor:devCard.leadingAnchor constant:18.0f],
        [devAvatar.centerYAnchor constraintEqualToAnchor:devCard.centerYAnchor],
        [devAvatar.widthAnchor constraintEqualToConstant:48.0f],
        [devAvatar.heightAnchor constraintEqualToConstant:48.0f],

        [_devHeaderLabel.leadingAnchor constraintEqualToAnchor:devAvatar.trailingAnchor constant:16.0f],
        [_devHeaderLabel.topAnchor constraintEqualToAnchor:devCard.topAnchor constant:18.0f],

        [_devNameLabel.leadingAnchor constraintEqualToAnchor:devAvatar.trailingAnchor constant:16.0f],
        [_devNameLabel.topAnchor constraintEqualToAnchor:_devHeaderLabel.bottomAnchor constant:2.0f],
    ]];

    // 4. App Details Card
    UIView *infoCard = [[UIView alloc] init];
    infoCard.translatesAutoresizingMaskIntoConstraints = NO;
    infoCard.backgroundColor = [UIColor colorWithRed:22/255.0 green:27/255.0 blue:34/255.0 alpha:0.95];
    infoCard.layer.cornerRadius = 16.0f;
    infoCard.layer.borderColor = [UIColor colorWithRed:33/255.0 green:38/255.0 blue:45/255.0 alpha:1.0].CGColor;
    infoCard.layer.borderWidth = 1.0f;
    [_settingContentView addSubview:infoCard];

    auto makeRow = ^UIView *(UILabel *titleLbl, NSString *valStr, UIView *topView) {
        UIView *row = [[UIView alloc] init];
        row.translatesAutoresizingMaskIntoConstraints = NO;
        [infoCard addSubview:row];

        titleLbl.translatesAutoresizingMaskIntoConstraints = NO;
        titleLbl.textColor = [UIColor colorWithRed:139/255.0 green:148/255.0 blue:158/255.0 alpha:1.0];
        titleLbl.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
        [row addSubview:titleLbl];

        UILabel *vLabel = [[UILabel alloc] init];
        vLabel.translatesAutoresizingMaskIntoConstraints = NO;
        vLabel.text = valStr;
        vLabel.textColor = UIColor.whiteColor;
        vLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightBold];
        [row addSubview:vLabel];

        [NSLayoutConstraint activateConstraints:@[
            [row.leadingAnchor constraintEqualToAnchor:infoCard.leadingAnchor constant:16.0f],
            [row.trailingAnchor constraintEqualToAnchor:infoCard.trailingAnchor constant:-16.0f],
            [row.heightAnchor constraintEqualToConstant:32.0f],
            [titleLbl.leadingAnchor constraintEqualToAnchor:row.leadingAnchor],
            [titleLbl.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
            [vLabel.trailingAnchor constraintEqualToAnchor:row.trailingAnchor],
            [vLabel.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        ]];

        if (topView) {
            [row.topAnchor constraintEqualToAnchor:topView.bottomAnchor constant:8.0f].active = YES;
        } else {
            [row.topAnchor constraintEqualToAnchor:infoCard.topAnchor constant:12.0f].active = YES;
        }
        return row;
    };

    _infoRow1Title = [[UILabel alloc] init];
    _infoRow2Title = [[UILabel alloc] init];
    _infoRow3Title = [[UILabel alloc] init];
    _infoRow4Title = [[UILabel alloc] init];

    UIView *r1 = makeRow(_infoRow1Title, @"DarkPubg", nil);
    UIView *r2 = makeRow(_infoRow2Title, @"1.0-1", r1);
    UIView *r3 = makeRow(_infoRow3Title, @"PUBG Mobile", r2);
    UIView *r4 = makeRow(_infoRow4Title, @"DarkSword Kernel (TrollStore)", r3);

    // 5. Note Card
    UIView *noteCard = [[UIView alloc] init];
    noteCard.translatesAutoresizingMaskIntoConstraints = NO;
    noteCard.backgroundColor = [UIColor colorWithRed:22/255.0 green:27/255.0 blue:34/255.0 alpha:0.6];
    noteCard.layer.cornerRadius = 12.0f;
    [_settingContentView addSubview:noteCard];

    _noteLabel = [[UILabel alloc] init];
    _noteLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _noteLabel.textColor = [UIColor colorWithRed:139/255.0 green:148/255.0 blue:158/255.0 alpha:1.0];
    _noteLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightRegular];
    _noteLabel.numberOfLines = 0;
    _noteLabel.textAlignment = NSTextAlignmentCenter;
    [noteCard addSubview:_noteLabel];

    // Layout Constraints for Setting View
    [NSLayoutConstraint activateConstraints:@[
        [_settingTitleLabel.topAnchor constraintEqualToAnchor:_settingContentView.topAnchor constant:24.0f],
        [_settingTitleLabel.centerXAnchor constraintEqualToAnchor:_settingContentView.centerXAnchor],

        [_settingSubTitleLabel.topAnchor constraintEqualToAnchor:_settingTitleLabel.bottomAnchor constant:4.0f],
        [_settingSubTitleLabel.centerXAnchor constraintEqualToAnchor:_settingContentView.centerXAnchor],

        [langCard.topAnchor constraintEqualToAnchor:_settingSubTitleLabel.bottomAnchor constant:22.0f],
        [langCard.leadingAnchor constraintEqualToAnchor:_settingContentView.leadingAnchor constant:24.0f],
        [langCard.trailingAnchor constraintEqualToAnchor:_settingContentView.trailingAnchor constant:-24.0f],

        [devCard.topAnchor constraintEqualToAnchor:langCard.bottomAnchor constant:18.0f],
        [devCard.leadingAnchor constraintEqualToAnchor:_settingContentView.leadingAnchor constant:24.0f],
        [devCard.trailingAnchor constraintEqualToAnchor:_settingContentView.trailingAnchor constant:-24.0f],
        [devCard.heightAnchor constraintEqualToConstant:84.0f],

        [infoCard.topAnchor constraintEqualToAnchor:devCard.bottomAnchor constant:18.0f],
        [infoCard.leadingAnchor constraintEqualToAnchor:_settingContentView.leadingAnchor constant:24.0f],
        [infoCard.trailingAnchor constraintEqualToAnchor:_settingContentView.trailingAnchor constant:-24.0f],
        [infoCard.bottomAnchor constraintEqualToAnchor:r4.bottomAnchor constant:14.0f],

        [noteCard.topAnchor constraintEqualToAnchor:infoCard.bottomAnchor constant:18.0f],
        [noteCard.leadingAnchor constraintEqualToAnchor:_settingContentView.leadingAnchor constant:24.0f],
        [noteCard.trailingAnchor constraintEqualToAnchor:_settingContentView.trailingAnchor constant:-24.0f],
        [noteCard.bottomAnchor constraintEqualToAnchor:_settingContentView.bottomAnchor constant:-30.0f],

        [_noteLabel.topAnchor constraintEqualToAnchor:noteCard.topAnchor constant:12.0f],
        [_noteLabel.bottomAnchor constraintEqualToAnchor:noteCard.bottomAnchor constant:-12.0f],
        [_noteLabel.leadingAnchor constraintEqualToAnchor:noteCard.leadingAnchor constant:16.0f],
        [_noteLabel.trailingAnchor constraintEqualToAnchor:noteCard.trailingAnchor constant:-16.0f],
    ]];
}

#pragma mark - Language Change

- (void)langSegmentChanged:(UISegmentedControl *)sender
{
    NSString *newLang = (sender.selectedSegmentIndex == 1) ? @"en" : @"vi";
    [[NSUserDefaults standardUserDefaults] setObject:newLang forKey:@"AppLanguage"];
    [[NSUserDefaults standardUserDefaults] synchronize];

    if (_impactFeedbackGenerator) {
        [_impactFeedbackGenerator impactOccurred];
    }

    [UIView transitionWithView:self.view duration:0.25 options:UIViewAnimationOptionTransitionCrossDissolve animations:^{
        [self applyLanguageTexts];
    } completion:nil];
}

- (void)applyLanguageTexts
{
    BOOL isEN = IsEnglish();

    // Bottom tab bar
    if (@available(iOS 15.0, *)) {
        UIButtonConfiguration *cfgHome = _homeTabButton.configuration;
        cfgHome.title = isEN ? @"Home" : @"Trang chủ";
        _homeTabButton.configuration = cfgHome;

        UIButtonConfiguration *cfgSet = _settingTabButton.configuration;
        cfgSet.title = isEN ? @"Setting" : @"Cài đặt";
        _settingTabButton.configuration = cfgSet;
    } else {
        [_homeTabButton setTitle:isEN ? @"Home" : @"Trang chủ" forState:UIControlStateNormal];
        [_settingTabButton setTitle:isEN ? @"Setting" : @"Cài đặt" forState:UIControlStateNormal];
    }

    // Home tab
    _homeTitleLabel.text = @"DarkPubg";
    _homeSubTitleLabel.text = @"PUBG Mobile Edition";

    NSString *iosVer = @"";
    NSString *dsStatus = @"";
    BOOL isSupported = CheckDarkSwordSupport(&iosVer, &dsStatus);
    _iosVersionLabel.text = [NSString stringWithFormat:isEN ? @"Device OS: %@" : @"Phiên bản: %@", iosVer];
    _systemTagLabel.text = isEN ? @"Device" : @"Thiết bị";

    if (isSupported) {
        if (_statusDotView) _statusDotView.backgroundColor = [UIColor colorWithRed:46/255.0 green:204/255.0 blue:113/255.0 alpha:1.0];
        if (_dsStatusBadge) _dsStatusBadge.backgroundColor = [UIColor colorWithRed:28/255.0 green:58/255.0 blue:45/255.0 alpha:1.0];
        if (_dsBadgeLabel) _dsBadgeLabel.textColor = [UIColor colorWithRed:46/255.0 green:204/255.0 blue:113/255.0 alpha:1.0];
        _dsStatusLabel.text = isEN ? @"DarkSword: Supported" : @"DarkSword: Đã hỗ trợ";
        _dsBadgeLabel.text = isEN ? @"Compatible" : @"Tương thích";
    } else {
        if (_statusDotView) _statusDotView.backgroundColor = [UIColor colorWithRed:231/255.0 green:76/255.0 blue:60/255.0 alpha:1.0];
        if (_dsStatusBadge) _dsStatusBadge.backgroundColor = [UIColor colorWithRed:58/255.0 green:28/255.0 blue:28/255.0 alpha:1.0];
        if (_dsBadgeLabel) _dsBadgeLabel.textColor = [UIColor colorWithRed:231/255.0 green:76/255.0 blue:60/255.0 alpha:1.0];
        _dsStatusLabel.text = isEN ? @"DarkSword: Unsupported" : @"DarkSword: Chưa hỗ trợ";
        _dsBadgeLabel.text = isEN ? @"Unsupported" : @"Chưa hỗ trợ";
    }

    if (_isRemoteHUDActive) {
        [_mainButton setTitle:@"EXIT HUD" forState:UIControlStateNormal];
        _buttonSubLabel.text = isEN ? @"DarkPubg is currently active in game" : @"DarkPubg đang hoạt động trong game";
    } else {
        [_mainButton setTitle:@"OPEN HUD" forState:UIControlStateNormal];
        _buttonSubLabel.text = isEN ? @"Tap to launch in-game ESP menu" : @"Nhấn để bật menu ESP trong game";
    }

    // Setting tab
    _settingTitleLabel.text = isEN ? @"Settings" : @"Cài Đặt";
    _settingSubTitleLabel.text = isEN ? @"Information & Options" : @"Thông tin & Tuỳ chọn";
    _langHeaderLabel.text = isEN ? @"LANGUAGE" : @"NGÔN NGỮ";
    _devHeaderLabel.text = isEN ? @"DEVELOPER" : @"NGƯỜI PHÁT TRIỂN";
    _devNameLabel.text = @"DLX07";

    _infoRow1Title.text = isEN ? @"App Name" : @"Ứng dụng";
    _infoRow2Title.text = isEN ? @"Version" : @"Phiên bản";
    _infoRow3Title.text = isEN ? @"Target Game" : @"Trò chơi";
    _infoRow4Title.text = isEN ? @"Exploit Engine" : @"Kiểu can thiệp";

    _noteLabel.text = isEN ?
        @"DarkPubg runs directly via TrollStore on iOS without Jailbreak." :
        @"DarkPubg hoạt động trực tiếp thông qua TrollStore trên iOS mà không cần Jailbreak.";

    // Warning popup texts if initialized
    if (_warningTitleLabel) {
        _warningTitleLabel.text = isEN ? @"Please launch the game first" : @"Vui lòng vào game trước";
    }
    if (_warningSubLabel) {
        _warningSubLabel.text = isEN ?
            @"Please open PUBG Mobile before launching HUD." :
            @"Hãy mở PUBG Mobile trước khi bật HUD để hệ thống có thể kết nối vào game.";
    }
    if (_warningDismissBtn) {
        [_warningDismissBtn setTitle:isEN ? @"OK" : @"Đã hiểu" forState:UIControlStateNormal];
    }
}

#pragma mark - Red Warning Popup (Vui lòng vào game trước)

- (void)showGameNotRunningAlert
{
    UINotificationFeedbackGenerator *feedback = [[UINotificationFeedbackGenerator alloc] init];
    [feedback notificationOccurred:UINotificationFeedbackTypeWarning];

    if (!_warningPopupOverlay) {
        _warningPopupOverlay = [[UIView alloc] initWithFrame:self.view.bounds];
        _warningPopupOverlay.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        _warningPopupOverlay.backgroundColor = [UIColor colorWithWhite:0 alpha:0.75];
        _warningPopupOverlay.alpha = 0.0f;

        UIView *card = [[UIView alloc] init];
        card.translatesAutoresizingMaskIntoConstraints = NO;
        card.backgroundColor = [UIColor colorWithRed:22/255.0 green:20/255.0 blue:24/255.0 alpha:0.98];
        card.layer.cornerRadius = 22.0f;
        card.layer.borderColor = [UIColor colorWithRed:255/255.0 green:59/255.0 blue:48/255.0 alpha:0.85].CGColor; // Vibrant Red
        card.layer.borderWidth = 1.8f;
        card.layer.shadowColor = [UIColor colorWithRed:255/255.0 green:59/255.0 blue:48/255.0 alpha:0.4].CGColor;
        card.layer.shadowRadius = 18.0f;
        card.layer.shadowOffset = CGSizeMake(0, 8);
        card.layer.shadowOpacity = 0.8f;
        [_warningPopupOverlay addSubview:card];

        UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"exclamationmark.triangle.fill"]];
        icon.translatesAutoresizingMaskIntoConstraints = NO;
        icon.tintColor = [UIColor colorWithRed:255/255.0 green:59/255.0 blue:48/255.0 alpha:1.0]; // Bright Red
        icon.contentMode = UIViewContentModeScaleAspectFit;
        [card addSubview:icon];

        // RED TITLE (User requirement: chữ màu đỏ hiện lên vui lòng vào game trước)
        _warningTitleLabel = [[UILabel alloc] init];
        _warningTitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _warningTitleLabel.textColor = [UIColor colorWithRed:255/255.0 green:59/255.0 blue:48/255.0 alpha:1.0]; // Bright RED
        _warningTitleLabel.font = [UIFont systemFontOfSize:20 weight:UIFontWeightHeavy];
        _warningTitleLabel.textAlignment = NSTextAlignmentCenter;
        _warningTitleLabel.numberOfLines = 0;
        [card addSubview:_warningTitleLabel];

        _warningSubLabel = [[UILabel alloc] init];
        _warningSubLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _warningSubLabel.textColor = [UIColor colorWithRed:160/255.0 green:168/255.0 blue:178/255.0 alpha:1.0];
        _warningSubLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
        _warningSubLabel.textAlignment = NSTextAlignmentCenter;
        _warningSubLabel.numberOfLines = 0;
        [card addSubview:_warningSubLabel];

        _warningDismissBtn = [UIButton buttonWithType:UIButtonTypeSystem];
        _warningDismissBtn.translatesAutoresizingMaskIntoConstraints = NO;
        [_warningDismissBtn setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
        _warningDismissBtn.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightBold];
        _warningDismissBtn.backgroundColor = [UIColor colorWithRed:255/255.0 green:59/255.0 blue:48/255.0 alpha:1.0];
        _warningDismissBtn.layer.cornerRadius = 20.0f;
        [_warningDismissBtn addTarget:self action:@selector(dismissWarningPopup) forControlEvents:UIControlEventTouchUpInside];
        [card addSubview:_warningDismissBtn];

        [NSLayoutConstraint activateConstraints:@[
            [card.centerXAnchor constraintEqualToAnchor:_warningPopupOverlay.centerXAnchor],
            [card.centerYAnchor constraintEqualToAnchor:_warningPopupOverlay.centerYAnchor],
            [card.widthAnchor constraintEqualToConstant:300.0f],

            [icon.topAnchor constraintEqualToAnchor:card.topAnchor constant:22.0f],
            [icon.centerXAnchor constraintEqualToAnchor:card.centerXAnchor],
            [icon.widthAnchor constraintEqualToConstant:44.0f],
            [icon.heightAnchor constraintEqualToConstant:44.0f],

            [_warningTitleLabel.topAnchor constraintEqualToAnchor:icon.bottomAnchor constant:14.0f],
            [_warningTitleLabel.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:18.0f],
            [_warningTitleLabel.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-18.0f],

            [_warningSubLabel.topAnchor constraintEqualToAnchor:_warningTitleLabel.bottomAnchor constant:10.0f],
            [_warningSubLabel.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:20.0f],
            [_warningSubLabel.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-20.0f],

            [_warningDismissBtn.topAnchor constraintEqualToAnchor:_warningSubLabel.bottomAnchor constant:20.0f],
            [_warningDismissBtn.centerXAnchor constraintEqualToAnchor:card.centerXAnchor],
            [_warningDismissBtn.widthAnchor constraintEqualToConstant:140.0f],
            [_warningDismissBtn.heightAnchor constraintEqualToConstant:40.0f],
            [_warningDismissBtn.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-20.0f],
        ]];
    }

    [self applyLanguageTexts];

    if (!_warningPopupOverlay.superview) {
        [self.view addSubview:_warningPopupOverlay];
    }
    [self.view bringSubviewToFront:_warningPopupOverlay];

    _warningPopupOverlay.hidden = NO;
    _warningPopupOverlay.alpha = 0.0f;
    _warningPopupOverlay.transform = CGAffineTransformMakeScale(0.92, 0.92);

    [UIView animateWithDuration:0.25 delay:0 usingSpringWithDamping:0.85 initialSpringVelocity:1.0 options:UIViewAnimationOptionCurveEaseOut animations:^{
        self->_warningPopupOverlay.alpha = 1.0f;
        self->_warningPopupOverlay.transform = CGAffineTransformIdentity;
    } completion:nil];
}

- (void)dismissWarningPopup
{
    if (_impactFeedbackGenerator) [_impactFeedbackGenerator impactOccurred];
    [UIView animateWithDuration:0.2 delay:0 options:UIViewAnimationOptionCurveEaseIn animations:^{
        self->_warningPopupOverlay.alpha = 0.0f;
        self->_warningPopupOverlay.transform = CGAffineTransformMakeScale(0.92, 0.92);
    } completion:^(BOOL finished) {
        self->_warningPopupOverlay.hidden = YES;
    }];
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
        [self applyLanguageTexts];
        if (self->_isRemoteHUDActive) {
            self->_mainButton.backgroundColor = [UIColor colorWithRed:231/255.0 green:76/255.0 blue:60/255.0 alpha:1.0]; // Red
            self->_mainButton.layer.shadowColor = [UIColor colorWithRed:231/255.0 green:76/255.0 blue:60/255.0 alpha:0.5].CGColor;
        } else {
            self->_mainButton.backgroundColor = [UIColor colorWithRed:0/255.0 green:210/255.0 blue:180/255.0 alpha:1.0]; // Cyan
            self->_mainButton.layer.shadowColor = [UIColor colorWithRed:0/255.0 green:210/255.0 blue:180/255.0 alpha:0.45].CGColor;
        }
    });
}

- (void)tapMainButton:(UIButton *)sender
{
    BOOL isNowEnabled = [self isHUDEnabled];

    // If HUD is currently OFF and user taps to OPEN HUD:
    if (!isNowEnabled) {
        // Check if PUBG Mobile is running
        if (!IsPUBGProcessRunning()) {
            [self showGameNotRunningAlert];
            return;
        }
    }

    [self setHUDEnabled:!isNowEnabled];
    isNowEnabled = !isNowEnabled;

    if (isNowEnabled)
    {
#if USE_DARKSWORD
        [self showDSProgressOverlay];
#endif
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
#if USE_DARKSWORD
        [self hideDSProgressOverlay];
#endif
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
