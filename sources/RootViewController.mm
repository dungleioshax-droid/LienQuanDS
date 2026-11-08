//
//  RootViewController.mm
//  DarkPubg
//
//  Created by Lessica on 2024/1/24.
//  Redesigned by DLX07 on 2026/11/08.
//

#import <notify.h>
#import <sys/sysctl.h>
#import <dlfcn.h>

#include <string>
#include <vector>
#include <chrono>
#include <thread>
#include <atomic>
#include <algorithm>

#include "../Auth/auth_types.h"
#include "../Auth/auth_manager.h"
#include "../Auth/auth_guard.h"
#include "../Auth/auth_storage.h"
#include "../Auth/auth_network.h"
#include "../Auth/auth_integrity.h"
#include "../Auth/setting.h"

#include "../Auth/auth_network.mm"
#include "../Auth/auth_chat.mm"
#include "../Auth/auth_manager.mm"

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

static NSString *GetFormattedExpiryString(time_t exp) {
    if (exp <= 0) {
        exp = auth::load_expiry();
    }
    std::string dispStr = auth::load_expiry_display();
    if (exp <= 0 && !dispStr.empty()) {
        return [NSString stringWithUTF8String:dispStr.c_str()];
    }
    if (exp <= 0) return IsEnglish() ? @"Not Activated" : @"Chưa kích hoạt";
    if (exp >= 2000000000) return IsEnglish() ? @"Lifetime (VIP)" : @"Vĩnh viễn (Trọn đời)";
    NSDate *date = [NSDate dateWithTimeIntervalSince1970:(NSTimeInterval)exp];
    NSDateFormatter *df = [[NSDateFormatter alloc] init];
    df.dateFormat = @"dd/MM/yyyy HH:mm";
    return [df stringFromDate:date];
}

static NSString *GetFormattedRemainingString(time_t exp) {
    if (exp <= 0) {
        exp = auth::load_expiry();
    }
    if (exp <= 0) {
        std::string dispStr = auth::load_expiry_display();
        if (!dispStr.empty()) {
            NSDateFormatter *df = [[NSDateFormatter alloc] init];
            NSArray *formats = @[
                @"yyyy-MM-dd HH:mm:ss",
                @"yyyy-MM-dd'T'HH:mm:ss",
                @"yyyy-MM-dd",
                @"dd/MM/yyyy HH:mm:ss",
                @"dd/MM/yyyy HH:mm",
                @"dd/MM/yyyy"
            ];
            for (NSString *fmt in formats) {
                df.dateFormat = fmt;
                NSDate *d = [df dateFromString:[NSString stringWithUTF8String:dispStr.c_str()]];
                if (d) {
                    exp = (time_t)[d timeIntervalSince1970];
                    break;
                }
            }
        }
    }
    if (exp <= 0) return IsEnglish() ? @"Please enter key" : @"Vui lòng nhập key";
    if (exp >= 2000000000) return IsEnglish() ? @"Lifetime (VIP)" : @"Vĩnh viễn (Trọn đời)";

    time_t now = time(nullptr);
    if (exp <= now) {
        return IsEnglish() ? @"Expired" : @"Đã hết hạn";
    }

    long diff = (long)(exp - now);
    long days = diff / 86400;
    long hours = (diff % 86400) / 3600;
    long minutes = (diff % 3600) / 60;

    BOOL isEN = IsEnglish();
    if (days > 0) {
        return [NSString stringWithFormat:(isEN ? @"%ldd %ldh remaining" : @"Còn %ld ngày %ld giờ"), days, hours];
    } else if (hours > 0) {
        return [NSString stringWithFormat:(isEN ? @"%ldh %ldm remaining" : @"Còn %ld giờ %ld phút"), hours, minutes];
    } else {
        if (minutes < 1) minutes = 1;
        return [NSString stringWithFormat:(isEN ? @"%ld minutes remaining" : @"Còn %ld phút"), minutes];
    }
}

static NSString *GetMaskedKeyString(NSString *rawKey) {
    if (!rawKey || rawKey.length == 0) return IsEnglish() ? @"No Key" : @"Chưa có key";
    if (rawKey.length <= 8) return rawKey;
    NSString *start = [rawKey substringToIndex:4];
    NSString *end = [rawKey substringFromIndex:rawKey.length - 4];
    return [NSString stringWithFormat:@"%@-****-****-%@", start, end];
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

static BOOL CheckPUBGViaSpringBoard(void) {
    static pid_t (*sbsFunc)(CFStringRef) = NULL;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        void *sbs = dlopen("/System/Library/PrivateFrameworks/SpringBoardServices.framework/SpringBoardServices", RTLD_NOW);
        if (sbs) {
            sbsFunc = (pid_t (*)(CFStringRef))dlsym(sbs, "SBSProcessIDForDisplayIdentifier");
        }
    });

    NSArray<NSString *> *bundleIDs = @[
        @"com.tencent.ig",
        @"com.vng.pubgmobile",
        @"com.pubg.krmobile",
        @"com.rekoo.pubgm",
        @"com.pubg.imobile",
        @"com.tencent.iglite",
        @"com.epicgames.ShadowTrackerExtra",
        @"com.tencent.tmgp.pubgm",
        @"com.tencent.tmgp.pubgmhd",
        @"com.tencent.igce"
    ];

    if (sbsFunc) {
        for (NSString *bundleID in bundleIDs) {
            pid_t pid = sbsFunc((__bridge CFStringRef)bundleID);
            if (pid > 0) {
                return YES;
            }
        }
    }

    Class bksClass = NSClassFromString(@"BKSApplicationStateMonitor");
    if (!bksClass) {
        void *bksLib = dlopen("/System/Library/PrivateFrameworks/AssertionServices.framework/AssertionServices", RTLD_NOW);
        if (bksLib) {
            bksClass = NSClassFromString(@"BKSApplicationStateMonitor");
        }
    }
    if (bksClass) {
        @try {
            id monitor = [[bksClass alloc] init];
            if ([monitor respondsToSelector:@selector(applicationStateForApplication:)]) {
                for (NSString *bundleID in bundleIDs) {
                    unsigned int state = (unsigned int)[monitor applicationStateForApplication:bundleID];
                    if (state & (2 | 4 | 8)) {
                        return YES;
                    }
                }
            }
        } @catch (id ex) {}
    }

    return NO;
}

static BOOL CheckPUBGViaSysctl(void) {
    int mib[4] = { CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0 };
    size_t size = 0;
    if (sysctl(mib, 4, NULL, &size, NULL, 0) < 0 || size == 0) {
        return NO;
    }
    struct kinfo_proc *procs = (struct kinfo_proc *)malloc(size);
    if (!procs) return NO;
    if (sysctl(mib, 4, procs, &size, NULL, 0) < 0) {
        free(procs);
        return NO;
    }
    int count = (int)(size / sizeof(struct kinfo_proc));
    BOOL found = NO;
    for (int i = 0; i < count; i++) {
        const char *name = procs[i].kp_proc.p_comm;
        if (!name || !name[0]) continue;
        if (strcasestr(name, "ShadowTracker") != NULL ||
            strcasestr(name, "Shadow") != NULL ||
            strcasestr(name, "PUBG") != NULL) {
            found = YES;
            break;
        }
    }
    free(procs);
    return found;
}

static BOOL CheckPUBGViaLibProc(void) {
    int count = proc_listallpids(NULL, 0);
    if (count <= 0 || count > 100000) return NO;
    pid_t *pids = (pid_t *)malloc((size_t)count * sizeof(pid_t));
    if (!pids) return NO;
    int got = proc_listallpids(pids, count * (int)sizeof(pid_t));
    BOOL found = NO;
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
                    strcasestr(name, "Shadow") != NULL ||
                    strcasestr(name, "PUBG") != NULL) {
                    found = YES;
                    break;
                }
            }
            memset(path, 0, sizeof(path));
            if (proc_pidpath(p, path, sizeof(path) - 1) > 0) {
                if (strcasestr(path, "ShadowTracker") != NULL ||
                    strcasestr(path, "Shadow") != NULL ||
                    strcasestr(path, "PUBG") != NULL) {
                    found = YES;
                    break;
                }
            }
        }
    }
    free(pids);
    return found;
}

static BOOL IsPUBGProcessRunning(void) {
    // 1. SpringBoardServices / AssertionServices check (Direct to SpringBoard on iOS)
    if (CheckPUBGViaSpringBoard()) return YES;

    // 2. Sysctl check (KERN_PROC_ALL)
    if (CheckPUBGViaSysctl()) return YES;

    // 3. Libproc check
    if (CheckPUBGViaLibProc()) return YES;

#if USE_DARKSWORD
    // 4. DarkSword kernel check (if kernel is ready)
    if (DSBridgeIsPUBGRunning()) return YES;
#endif

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

    // Home Console Terminal
    UIView *_consoleCard;
    UILabel *_consoleHeaderLabel;
    UIView *_consoleLiveDot;
    UILabel *_consoleLiveLabel;
    UITextView *_consoleTextView;
    NSMutableAttributedString *_consoleLogStorage;
    NSTimer *_consoleHeartbeatTimer;

    // Setting localized labels
    UILabel *_settingTitleLabel;
    UILabel *_settingSubTitleLabel;
    UILabel *_langHeaderLabel;
    UISegmentedControl *_langSegmentedControl;

    // Telegram Community Card
    UIView *_telegramCard;
    UILabel *_telegramHeaderLabel;
    UILabel *_telegramHandleLabel;
    UILabel *_telegramSubLabel;
    UIButton *_telegramJoinButton;

    // Developer Card
    UILabel *_devHeaderLabel;
    UILabel *_devNameLabel;

    // Security & Engine Card
    UIView *_securityCard;
    UILabel *_secHeaderLabel;
    UILabel *_secRow1Title;
    UILabel *_secRow1Val;
    UILabel *_secRow2Title;
    UILabel *_secRow2Val;
    UILabel *_secRow3Title;
    UILabel *_secRow3Val;

    // App Details Card
    UILabel *_infoRow1Title;
    UILabel *_infoRow2Title;
    UILabel *_infoRow3Title;
    UILabel *_infoRow4Title;

    // Quick Utilities Card
    UIView *_utilCard;
    UILabel *_utilHeaderLabel;
    UIButton *_clearCacheBtn;
    UIButton *_resetConfigBtn;

    UILabel *_noteLabel;

    // Red warning popup
    UIView *_warningPopupOverlay;
    UILabel *_warningTitleLabel;
    UILabel *_warningSubLabel;
    UIButton *_warningLaunchGameBtn;
    UIButton *_warningProceedBtn;
    UIButton *_warningDismissBtn;

    // Auth Gate UI
    UIView *_authGateOverlay;
    UIView *_authCardView;
    UITextField *_authKeyTextField;
    UILabel *_authTitleLabel;
    UILabel *_authSubTitleLabel;
    UILabel *_authKeyInputTitleLabel;
    UIButton *_authPasteKeyButton;
    UILabel *_authStatusLabel;
    UIButton *_authActivateBtn;
    UIActivityIndicatorView *_authSpinner;
    UIButton *_authTelegramBtn;
    UIButton *_authCloseBtn;
    BOOL _isAuthValidating;

    // Setting Tab License Card
    UIView *_licenseCard;
    UILabel *_licenseHeaderLabel;
    UIView *_licenseStatusBadge;
    UILabel *_licenseBadgeLabel;
    UILabel *_licenseKeyTitle;
    UILabel *_licenseKeyVal;
    UILabel *_licenseExpTitle;
    UILabel *_licenseExpVal;
    UILabel *_licenseRemainTitle;
    UILabel *_licenseRemainVal;
    UIButton *_changeKeyBtn;

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
    [self setupAuthGateOverlay];

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

    // 3. Central OPEN HUD Button (Placed high up)
    _mainButton = [MainButton buttonWithType:UIButtonTypeSystem];
    _mainButton.translatesAutoresizingMaskIntoConstraints = NO;
    [_mainButton addTarget:self action:@selector(tapMainButton:) forControlEvents:UIControlEventTouchUpInside];
    [_mainButton setTitle:@"OPEN HUD" forState:UIControlStateNormal];
    [_mainButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    _mainButton.titleLabel.font = [UIFont systemFontOfSize:20 weight:UIFontWeightHeavy];
    _mainButton.backgroundColor = [UIColor colorWithRed:0/255.0 green:210/255.0 blue:180/255.0 alpha:1.0];
    _mainButton.layer.cornerRadius = 25.0f;
    _mainButton.layer.shadowColor = [UIColor colorWithRed:0/255.0 green:210/255.0 blue:180/255.0 alpha:0.45].CGColor;
    _mainButton.layer.shadowOffset = CGSizeMake(0, 6);
    _mainButton.layer.shadowRadius = 14.0f;
    _mainButton.layer.shadowOpacity = 0.8f;
    [_homeView addSubview:_mainButton];

    _buttonSubLabel = [[UILabel alloc] init];
    _buttonSubLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _buttonSubLabel.textColor = [UIColor colorWithRed:139/255.0 green:148/255.0 blue:158/255.0 alpha:1.0];
    _buttonSubLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
    _buttonSubLabel.textAlignment = NSTextAlignmentCenter;
    [_homeView addSubview:_buttonSubLabel];

    // 4. Live Running Log (Terminal Console)
    _consoleCard = [[UIView alloc] init];
    _consoleCard.translatesAutoresizingMaskIntoConstraints = NO;
    _consoleCard.backgroundColor = [UIColor colorWithRed:11/255.0 green:15/255.0 blue:20/255.0 alpha:0.95]; // #0B0F14
    _consoleCard.layer.cornerRadius = 14.0f;
    _consoleCard.layer.borderColor = [UIColor colorWithRed:31/255.0 green:38/255.0 blue:48/255.0 alpha:1.0].CGColor;
    _consoleCard.layer.borderWidth = 1.0f;
    _consoleCard.clipsToBounds = YES;
    [_homeView addSubview:_consoleCard];

    // Console Top Bar
    UIView *consoleHeader = [[UIView alloc] init];
    consoleHeader.translatesAutoresizingMaskIntoConstraints = NO;
    consoleHeader.backgroundColor = [UIColor colorWithRed:19/255.0 green:25/255.0 blue:32/255.0 alpha:1.0];
    [_consoleCard addSubview:consoleHeader];

    UIView *dotRed = [[UIView alloc] init];
    dotRed.translatesAutoresizingMaskIntoConstraints = NO;
    dotRed.backgroundColor = [UIColor colorWithRed:255/255.0 green:95/255.0 blue:86/255.0 alpha:1.0];
    dotRed.layer.cornerRadius = 4.0f;
    [consoleHeader addSubview:dotRed];

    UIView *dotYellow = [[UIView alloc] init];
    dotYellow.translatesAutoresizingMaskIntoConstraints = NO;
    dotYellow.backgroundColor = [UIColor colorWithRed:255/255.0 green:189/255.0 blue:46/255.0 alpha:1.0];
    dotYellow.layer.cornerRadius = 4.0f;
    [consoleHeader addSubview:dotYellow];

    UIView *dotGreen = [[UIView alloc] init];
    dotGreen.translatesAutoresizingMaskIntoConstraints = NO;
    dotGreen.backgroundColor = [UIColor colorWithRed:39/255.0 green:201/255.0 blue:63/255.0 alpha:1.0];
    dotGreen.layer.cornerRadius = 4.0f;
    [consoleHeader addSubview:dotGreen];

    _consoleHeaderLabel = [[UILabel alloc] init];
    _consoleHeaderLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _consoleHeaderLabel.textColor = [UIColor colorWithRed:139/255.0 green:148/255.0 blue:158/255.0 alpha:1.0];
    _consoleHeaderLabel.font = [UIFont monospacedSystemFontOfSize:10.5 weight:UIFontWeightBold];
    _consoleHeaderLabel.text = @"CONSOLE LOG";
    [consoleHeader addSubview:_consoleHeaderLabel];

    _consoleLiveDot = [[UIView alloc] init];
    _consoleLiveDot.translatesAutoresizingMaskIntoConstraints = NO;
    _consoleLiveDot.backgroundColor = [UIColor colorWithRed:0/255.0 green:230/255.0 blue:118/255.0 alpha:1.0];
    _consoleLiveDot.layer.cornerRadius = 3.0f;
    [consoleHeader addSubview:_consoleLiveDot];

    _consoleLiveLabel = [[UILabel alloc] init];
    _consoleLiveLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _consoleLiveLabel.textColor = [UIColor colorWithRed:0/255.0 green:230/255.0 blue:118/255.0 alpha:1.0];
    _consoleLiveLabel.font = [UIFont monospacedSystemFontOfSize:9.5 weight:UIFontWeightBold];
    _consoleLiveLabel.text = @"LIVE";
    [consoleHeader addSubview:_consoleLiveLabel];

    UIView *consoleSep = [[UIView alloc] init];
    consoleSep.translatesAutoresizingMaskIntoConstraints = NO;
    consoleSep.backgroundColor = [UIColor colorWithRed:31/255.0 green:38/255.0 blue:48/255.0 alpha:1.0];
    [_consoleCard addSubview:consoleSep];

    _consoleTextView = [[UITextView alloc] init];
    _consoleTextView.translatesAutoresizingMaskIntoConstraints = NO;
    _consoleTextView.backgroundColor = UIColor.clearColor;
    _consoleTextView.editable = NO;
    _consoleTextView.selectable = NO;
    _consoleTextView.showsVerticalScrollIndicator = YES;
    _consoleTextView.indicatorStyle = UIScrollViewIndicatorStyleWhite;
    _consoleTextView.textContainerInset = UIEdgeInsetsMake(6, 8, 6, 8);
    [_consoleCard addSubview:_consoleTextView];

    // Layout Constraints for Home View
    [NSLayoutConstraint activateConstraints:@[
        [_homeTitleLabel.topAnchor constraintEqualToAnchor:_homeView.topAnchor constant:12.0f],
        [_homeTitleLabel.centerXAnchor constraintEqualToAnchor:_homeView.centerXAnchor],

        [_homeSubTitleLabel.topAnchor constraintEqualToAnchor:_homeTitleLabel.bottomAnchor constant:2.0f],
        [_homeSubTitleLabel.centerXAnchor constraintEqualToAnchor:_homeView.centerXAnchor],

        [statusCard.topAnchor constraintEqualToAnchor:_homeSubTitleLabel.bottomAnchor constant:12.0f],
        [statusCard.leadingAnchor constraintEqualToAnchor:_homeView.leadingAnchor constant:20.0f],
        [statusCard.trailingAnchor constraintEqualToAnchor:_homeView.trailingAnchor constant:-20.0f],
        [statusCard.heightAnchor constraintEqualToConstant:76.0f],

        [appleIcon.leadingAnchor constraintEqualToAnchor:statusCard.leadingAnchor constant:14.0f],
        [appleIcon.topAnchor constraintEqualToAnchor:statusCard.topAnchor constant:12.0f],
        [appleIcon.widthAnchor constraintEqualToConstant:16.0f],
        [appleIcon.heightAnchor constraintEqualToConstant:16.0f],

        [_iosVersionLabel.leadingAnchor constraintEqualToAnchor:appleIcon.trailingAnchor constant:8.0f],
        [_iosVersionLabel.centerYAnchor constraintEqualToAnchor:appleIcon.centerYAnchor],

        [_systemTagLabel.trailingAnchor constraintEqualToAnchor:statusCard.trailingAnchor constant:-14.0f],
        [_systemTagLabel.centerYAnchor constraintEqualToAnchor:appleIcon.centerYAnchor],

        [cardSep.topAnchor constraintEqualToAnchor:appleIcon.bottomAnchor constant:10.0f],
        [cardSep.leadingAnchor constraintEqualToAnchor:statusCard.leadingAnchor constant:14.0f],
        [cardSep.trailingAnchor constraintEqualToAnchor:statusCard.trailingAnchor constant:-14.0f],
        [cardSep.heightAnchor constraintEqualToConstant:1.0f],

        [_statusDotView.leadingAnchor constraintEqualToAnchor:statusCard.leadingAnchor constant:14.0f],
        [_statusDotView.topAnchor constraintEqualToAnchor:cardSep.bottomAnchor constant:11.0f],
        [_statusDotView.widthAnchor constraintEqualToConstant:8.0f],
        [_statusDotView.heightAnchor constraintEqualToConstant:8.0f],

        [_dsStatusLabel.leadingAnchor constraintEqualToAnchor:_statusDotView.trailingAnchor constant:8.0f],
        [_dsStatusLabel.centerYAnchor constraintEqualToAnchor:_statusDotView.centerYAnchor],

        [_dsStatusBadge.trailingAnchor constraintEqualToAnchor:statusCard.trailingAnchor constant:-14.0f],
        [_dsStatusBadge.centerYAnchor constraintEqualToAnchor:_statusDotView.centerYAnchor],
        [_dsStatusBadge.heightAnchor constraintEqualToConstant:20.0f],

        [_dsBadgeLabel.leadingAnchor constraintEqualToAnchor:_dsStatusBadge.leadingAnchor constant:8.0f],
        [_dsBadgeLabel.trailingAnchor constraintEqualToAnchor:_dsStatusBadge.trailingAnchor constant:-8.0f],
        [_dsBadgeLabel.centerYAnchor constraintEqualToAnchor:_dsStatusBadge.centerYAnchor],

        [_mainButton.topAnchor constraintEqualToAnchor:statusCard.bottomAnchor constant:12.0f],
        [_mainButton.centerXAnchor constraintEqualToAnchor:_homeView.centerXAnchor],
        [_mainButton.widthAnchor constraintEqualToConstant:230.0f],
        [_mainButton.heightAnchor constraintEqualToConstant:50.0f],

        [_buttonSubLabel.topAnchor constraintEqualToAnchor:_mainButton.bottomAnchor constant:6.0f],
        [_buttonSubLabel.centerXAnchor constraintEqualToAnchor:_homeView.centerXAnchor],

        [_consoleCard.topAnchor constraintEqualToAnchor:_buttonSubLabel.bottomAnchor constant:12.0f],
        [_consoleCard.leadingAnchor constraintEqualToAnchor:_homeView.leadingAnchor constant:20.0f],
        [_consoleCard.trailingAnchor constraintEqualToAnchor:_homeView.trailingAnchor constant:-20.0f],
        [_consoleCard.bottomAnchor constraintEqualToAnchor:_homeView.bottomAnchor constant:-12.0f],

        [consoleHeader.topAnchor constraintEqualToAnchor:_consoleCard.topAnchor],
        [consoleHeader.leadingAnchor constraintEqualToAnchor:_consoleCard.leadingAnchor],
        [consoleHeader.trailingAnchor constraintEqualToAnchor:_consoleCard.trailingAnchor],
        [consoleHeader.heightAnchor constraintEqualToConstant:30.0f],

        [dotRed.leadingAnchor constraintEqualToAnchor:consoleHeader.leadingAnchor constant:12.0f],
        [dotRed.centerYAnchor constraintEqualToAnchor:consoleHeader.centerYAnchor],
        [dotRed.widthAnchor constraintEqualToConstant:8.0f],
        [dotRed.heightAnchor constraintEqualToConstant:8.0f],

        [dotYellow.leadingAnchor constraintEqualToAnchor:dotRed.trailingAnchor constant:5.0f],
        [dotYellow.centerYAnchor constraintEqualToAnchor:consoleHeader.centerYAnchor],
        [dotYellow.widthAnchor constraintEqualToConstant:8.0f],
        [dotYellow.heightAnchor constraintEqualToConstant:8.0f],

        [dotGreen.leadingAnchor constraintEqualToAnchor:dotYellow.trailingAnchor constant:5.0f],
        [dotGreen.centerYAnchor constraintEqualToAnchor:consoleHeader.centerYAnchor],
        [dotGreen.widthAnchor constraintEqualToConstant:8.0f],
        [dotGreen.heightAnchor constraintEqualToConstant:8.0f],

        [_consoleHeaderLabel.leadingAnchor constraintEqualToAnchor:dotGreen.trailingAnchor constant:10.0f],
        [_consoleHeaderLabel.centerYAnchor constraintEqualToAnchor:consoleHeader.centerYAnchor],

        [_consoleLiveLabel.trailingAnchor constraintEqualToAnchor:consoleHeader.trailingAnchor constant:-12.0f],
        [_consoleLiveLabel.centerYAnchor constraintEqualToAnchor:consoleHeader.centerYAnchor],

        [_consoleLiveDot.trailingAnchor constraintEqualToAnchor:_consoleLiveLabel.leadingAnchor constant:-5.0f],
        [_consoleLiveDot.centerYAnchor constraintEqualToAnchor:consoleHeader.centerYAnchor],
        [_consoleLiveDot.widthAnchor constraintEqualToConstant:6.0f],
        [_consoleLiveDot.heightAnchor constraintEqualToConstant:6.0f],

        [consoleSep.topAnchor constraintEqualToAnchor:consoleHeader.bottomAnchor],
        [consoleSep.leadingAnchor constraintEqualToAnchor:_consoleCard.leadingAnchor],
        [consoleSep.trailingAnchor constraintEqualToAnchor:_consoleCard.trailingAnchor],
        [consoleSep.heightAnchor constraintEqualToConstant:1.0f],

        [_consoleTextView.topAnchor constraintEqualToAnchor:consoleSep.bottomAnchor],
        [_consoleTextView.leadingAnchor constraintEqualToAnchor:_consoleCard.leadingAnchor],
        [_consoleTextView.trailingAnchor constraintEqualToAnchor:_consoleCard.trailingAnchor],
        [_consoleTextView.bottomAnchor constraintEqualToAnchor:_consoleCard.bottomAnchor],
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

    // 2.5 License Info Card
    _licenseCard = [[UIView alloc] init];
    _licenseCard.translatesAutoresizingMaskIntoConstraints = NO;
    _licenseCard.backgroundColor = [UIColor colorWithRed:22/255.0 green:27/255.0 blue:34/255.0 alpha:0.95];
    _licenseCard.layer.cornerRadius = 16.0f;
    _licenseCard.layer.borderColor = [UIColor colorWithRed:0/255.0 green:210/255.0 blue:180/255.0 alpha:0.45].CGColor;
    _licenseCard.layer.borderWidth = 1.0f;
    [_settingContentView addSubview:_licenseCard];

    UIImageView *licIcon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"key.fill"]];
    licIcon.translatesAutoresizingMaskIntoConstraints = NO;
    licIcon.tintColor = [UIColor colorWithRed:0/255.0 green:210/255.0 blue:180/255.0 alpha:1.0];
    licIcon.contentMode = UIViewContentModeScaleAspectFit;
    [_licenseCard addSubview:licIcon];

    _licenseHeaderLabel = [[UILabel alloc] init];
    _licenseHeaderLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _licenseHeaderLabel.textColor = [UIColor colorWithRed:139/255.0 green:148/255.0 blue:158/255.0 alpha:1.0];
    _licenseHeaderLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightBold];
    [_licenseCard addSubview:_licenseHeaderLabel];

    _licenseStatusBadge = [[UIView alloc] init];
    _licenseStatusBadge.translatesAutoresizingMaskIntoConstraints = NO;
    _licenseStatusBadge.layer.cornerRadius = 10.0f;
    _licenseStatusBadge.backgroundColor = [UIColor colorWithRed:20/255.0 green:45/255.0 blue:35/255.0 alpha:1.0];
    [_licenseCard addSubview:_licenseStatusBadge];

    _licenseBadgeLabel = [[UILabel alloc] init];
    _licenseBadgeLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _licenseBadgeLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightBold];
    _licenseBadgeLabel.textColor = [UIColor colorWithRed:46/255.0 green:204/255.0 blue:113/255.0 alpha:1.0];
    [_licenseStatusBadge addSubview:_licenseBadgeLabel];

    // Row: Key
    UIView *keyRow = [[UIView alloc] init];
    keyRow.translatesAutoresizingMaskIntoConstraints = NO;
    [_licenseCard addSubview:keyRow];

    _licenseKeyTitle = [[UILabel alloc] init];
    _licenseKeyTitle.translatesAutoresizingMaskIntoConstraints = NO;
    _licenseKeyTitle.textColor = [UIColor colorWithRed:139/255.0 green:148/255.0 blue:158/255.0 alpha:1.0];
    _licenseKeyTitle.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    [keyRow addSubview:_licenseKeyTitle];

    _licenseKeyVal = [[UILabel alloc] init];
    _licenseKeyVal.translatesAutoresizingMaskIntoConstraints = NO;
    _licenseKeyVal.textColor = UIColor.whiteColor;
    _licenseKeyVal.font = [UIFont fontWithName:@"Menlo" size:12] ?: [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightBold];
    [keyRow addSubview:_licenseKeyVal];

    // Row: Expiry
    UIView *expRow = [[UIView alloc] init];
    expRow.translatesAutoresizingMaskIntoConstraints = NO;
    [_licenseCard addSubview:expRow];

    _licenseExpTitle = [[UILabel alloc] init];
    _licenseExpTitle.translatesAutoresizingMaskIntoConstraints = NO;
    _licenseExpTitle.textColor = [UIColor colorWithRed:139/255.0 green:148/255.0 blue:158/255.0 alpha:1.0];
    _licenseExpTitle.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    [expRow addSubview:_licenseExpTitle];

    _licenseExpVal = [[UILabel alloc] init];
    _licenseExpVal.translatesAutoresizingMaskIntoConstraints = NO;
    _licenseExpVal.textColor = [UIColor colorWithRed:0/255.0 green:210/255.0 blue:180/255.0 alpha:1.0];
    _licenseExpVal.font = [UIFont systemFontOfSize:13 weight:UIFontWeightBold];
    [expRow addSubview:_licenseExpVal];

    // Row: Remaining Duration
    UIView *remainRow = [[UIView alloc] init];
    remainRow.translatesAutoresizingMaskIntoConstraints = NO;
    [_licenseCard addSubview:remainRow];

    _licenseRemainTitle = [[UILabel alloc] init];
    _licenseRemainTitle.translatesAutoresizingMaskIntoConstraints = NO;
    _licenseRemainTitle.textColor = [UIColor colorWithRed:139/255.0 green:148/255.0 blue:158/255.0 alpha:1.0];
    _licenseRemainTitle.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    [remainRow addSubview:_licenseRemainTitle];

    _licenseRemainVal = [[UILabel alloc] init];
    _licenseRemainVal.translatesAutoresizingMaskIntoConstraints = NO;
    _licenseRemainVal.textColor = [UIColor colorWithRed:46/255.0 green:204/255.0 blue:113/255.0 alpha:1.0];
    _licenseRemainVal.font = [UIFont systemFontOfSize:13 weight:UIFontWeightBold];
    [remainRow addSubview:_licenseRemainVal];

    // Action button inside License Card (Full Width Change Key)
    _changeKeyBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    _changeKeyBtn.translatesAutoresizingMaskIntoConstraints = NO;
    _changeKeyBtn.backgroundColor = [UIColor colorWithRed:0/255.0 green:210/255.0 blue:180/255.0 alpha:0.18];
    [_changeKeyBtn setTitleColor:[UIColor colorWithRed:0/255.0 green:210/255.0 blue:180/255.0 alpha:1.0] forState:UIControlStateNormal];
    _changeKeyBtn.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightBold];
    _changeKeyBtn.layer.cornerRadius = 8.0f;
    _changeKeyBtn.layer.borderColor = [UIColor colorWithRed:0/255.0 green:210/255.0 blue:180/255.0 alpha:0.4].CGColor;
    _changeKeyBtn.layer.borderWidth = 1.0f;
    [_changeKeyBtn addTarget:self action:@selector(changeKeyTapped:) forControlEvents:UIControlEventTouchUpInside];
    [_licenseCard addSubview:_changeKeyBtn];

    [NSLayoutConstraint activateConstraints:@[
        [licIcon.leadingAnchor constraintEqualToAnchor:_licenseCard.leadingAnchor constant:16.0f],
        [licIcon.topAnchor constraintEqualToAnchor:_licenseCard.topAnchor constant:14.0f],
        [licIcon.widthAnchor constraintEqualToConstant:18.0f],
        [licIcon.heightAnchor constraintEqualToConstant:18.0f],

        [_licenseHeaderLabel.leadingAnchor constraintEqualToAnchor:licIcon.trailingAnchor constant:8.0f],
        [_licenseHeaderLabel.centerYAnchor constraintEqualToAnchor:licIcon.centerYAnchor],

        [_licenseStatusBadge.trailingAnchor constraintEqualToAnchor:_licenseCard.trailingAnchor constant:-14.0f],
        [_licenseStatusBadge.centerYAnchor constraintEqualToAnchor:licIcon.centerYAnchor],
        [_licenseStatusBadge.heightAnchor constraintEqualToConstant:20.0f],

        [_licenseBadgeLabel.leadingAnchor constraintEqualToAnchor:_licenseStatusBadge.leadingAnchor constant:8.0f],
        [_licenseBadgeLabel.trailingAnchor constraintEqualToAnchor:_licenseStatusBadge.trailingAnchor constant:-8.0f],
        [_licenseBadgeLabel.centerYAnchor constraintEqualToAnchor:_licenseStatusBadge.centerYAnchor],

        [keyRow.topAnchor constraintEqualToAnchor:licIcon.bottomAnchor constant:10.0f],
        [keyRow.leadingAnchor constraintEqualToAnchor:_licenseCard.leadingAnchor constant:16.0f],
        [keyRow.trailingAnchor constraintEqualToAnchor:_licenseCard.trailingAnchor constant:-16.0f],
        [keyRow.heightAnchor constraintEqualToConstant:24.0f],

        [_licenseKeyTitle.leadingAnchor constraintEqualToAnchor:keyRow.leadingAnchor],
        [_licenseKeyTitle.centerYAnchor constraintEqualToAnchor:keyRow.centerYAnchor],
        [_licenseKeyVal.trailingAnchor constraintEqualToAnchor:keyRow.trailingAnchor],
        [_licenseKeyVal.centerYAnchor constraintEqualToAnchor:keyRow.centerYAnchor],

        [expRow.topAnchor constraintEqualToAnchor:keyRow.bottomAnchor constant:4.0f],
        [expRow.leadingAnchor constraintEqualToAnchor:_licenseCard.leadingAnchor constant:16.0f],
        [expRow.trailingAnchor constraintEqualToAnchor:_licenseCard.trailingAnchor constant:-16.0f],
        [expRow.heightAnchor constraintEqualToConstant:24.0f],

        [_licenseExpTitle.leadingAnchor constraintEqualToAnchor:expRow.leadingAnchor],
        [_licenseExpTitle.centerYAnchor constraintEqualToAnchor:expRow.centerYAnchor],
        [_licenseExpVal.trailingAnchor constraintEqualToAnchor:expRow.trailingAnchor],
        [_licenseExpVal.centerYAnchor constraintEqualToAnchor:expRow.centerYAnchor],

        [remainRow.topAnchor constraintEqualToAnchor:expRow.bottomAnchor constant:4.0f],
        [remainRow.leadingAnchor constraintEqualToAnchor:_licenseCard.leadingAnchor constant:16.0f],
        [remainRow.trailingAnchor constraintEqualToAnchor:_licenseCard.trailingAnchor constant:-16.0f],
        [remainRow.heightAnchor constraintEqualToConstant:24.0f],

        [_licenseRemainTitle.leadingAnchor constraintEqualToAnchor:remainRow.leadingAnchor],
        [_licenseRemainTitle.centerYAnchor constraintEqualToAnchor:remainRow.centerYAnchor],
        [_licenseRemainVal.trailingAnchor constraintEqualToAnchor:remainRow.trailingAnchor],
        [_licenseRemainVal.centerYAnchor constraintEqualToAnchor:remainRow.centerYAnchor],

        [_changeKeyBtn.topAnchor constraintEqualToAnchor:remainRow.bottomAnchor constant:12.0f],
        [_changeKeyBtn.leadingAnchor constraintEqualToAnchor:_licenseCard.leadingAnchor constant:16.0f],
        [_changeKeyBtn.trailingAnchor constraintEqualToAnchor:_licenseCard.trailingAnchor constant:-16.0f],
        [_changeKeyBtn.heightAnchor constraintEqualToConstant:34.0f],
        [_changeKeyBtn.bottomAnchor constraintEqualToAnchor:_licenseCard.bottomAnchor constant:-14.0f],
    ]];

    // 3. Telegram Community Card
    _telegramCard = [[UIView alloc] init];
    _telegramCard.translatesAutoresizingMaskIntoConstraints = NO;
    _telegramCard.backgroundColor = [UIColor colorWithRed:16/255.0 green:28/255.0 blue:44/255.0 alpha:0.95];
    _telegramCard.layer.cornerRadius = 16.0f;
    _telegramCard.layer.borderColor = [UIColor colorWithRed:36/255.0 green:161/255.0 blue:222/255.0 alpha:0.55].CGColor;
    _telegramCard.layer.borderWidth = 1.2f;
    _telegramCard.layer.shadowColor = [UIColor colorWithRed:36/255.0 green:161/255.0 blue:222/255.0 alpha:0.25].CGColor;
    _telegramCard.layer.shadowOffset = CGSizeMake(0, 4);
    _telegramCard.layer.shadowRadius = 8.0f;
    _telegramCard.layer.shadowOpacity = 0.8f;
    _telegramCard.userInteractionEnabled = YES;
    UITapGestureRecognizer *tgTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(openTelegramLink)];
    [_telegramCard addGestureRecognizer:tgTap];
    [_settingContentView addSubview:_telegramCard];

    UIView *tgBadge = [[UIView alloc] init];
    tgBadge.translatesAutoresizingMaskIntoConstraints = NO;
    tgBadge.backgroundColor = [UIColor colorWithRed:36/255.0 green:161/255.0 blue:222/255.0 alpha:1.0];
    tgBadge.layer.cornerRadius = 21.0f;
    [_telegramCard addSubview:tgBadge];

    UIImageView *tgIcon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"paperplane.fill"]];
    tgIcon.translatesAutoresizingMaskIntoConstraints = NO;
    tgIcon.tintColor = UIColor.whiteColor;
    tgIcon.contentMode = UIViewContentModeScaleAspectFit;
    [tgBadge addSubview:tgIcon];

    _telegramHeaderLabel = [[UILabel alloc] init];
    _telegramHeaderLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _telegramHeaderLabel.textColor = [UIColor colorWithRed:36/255.0 green:161/255.0 blue:222/255.0 alpha:1.0];
    _telegramHeaderLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightBold];
    [_telegramCard addSubview:_telegramHeaderLabel];

    _telegramHandleLabel = [[UILabel alloc] init];
    _telegramHandleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _telegramHandleLabel.text = @"@ds_pubgmb";
    _telegramHandleLabel.textColor = UIColor.whiteColor;
    _telegramHandleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightHeavy];
    [_telegramCard addSubview:_telegramHandleLabel];

    _telegramSubLabel = [[UILabel alloc] init];
    _telegramSubLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _telegramSubLabel.textColor = [UIColor colorWithRed:139/255.0 green:148/255.0 blue:158/255.0 alpha:1.0];
    _telegramSubLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
    [_telegramCard addSubview:_telegramSubLabel];

    _telegramJoinButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _telegramJoinButton.translatesAutoresizingMaskIntoConstraints = NO;
    _telegramJoinButton.backgroundColor = [UIColor colorWithRed:36/255.0 green:161/255.0 blue:222/255.0 alpha:1.0];
    [_telegramJoinButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    _telegramJoinButton.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightBold];
    _telegramJoinButton.layer.cornerRadius = 16.0f;
    [_telegramJoinButton addTarget:self action:@selector(openTelegramLink) forControlEvents:UIControlEventTouchUpInside];
    [_telegramCard addSubview:_telegramJoinButton];

    [NSLayoutConstraint activateConstraints:@[
        [tgBadge.leadingAnchor constraintEqualToAnchor:_telegramCard.leadingAnchor constant:14.0f],
        [tgBadge.centerYAnchor constraintEqualToAnchor:_telegramCard.centerYAnchor],
        [tgBadge.widthAnchor constraintEqualToConstant:42.0f],
        [tgBadge.heightAnchor constraintEqualToConstant:42.0f],

        [tgIcon.centerXAnchor constraintEqualToAnchor:tgBadge.centerXAnchor constant:-1.0f],
        [tgIcon.centerYAnchor constraintEqualToAnchor:tgBadge.centerYAnchor],
        [tgIcon.widthAnchor constraintEqualToConstant:20.0f],
        [tgIcon.heightAnchor constraintEqualToConstant:20.0f],

        [_telegramJoinButton.trailingAnchor constraintEqualToAnchor:_telegramCard.trailingAnchor constant:-14.0f],
        [_telegramJoinButton.centerYAnchor constraintEqualToAnchor:_telegramCard.centerYAnchor],
        [_telegramJoinButton.widthAnchor constraintEqualToConstant:84.0f],
        [_telegramJoinButton.heightAnchor constraintEqualToConstant:32.0f],

        [_telegramHeaderLabel.leadingAnchor constraintEqualToAnchor:tgBadge.trailingAnchor constant:12.0f],
        [_telegramHeaderLabel.topAnchor constraintEqualToAnchor:_telegramCard.topAnchor constant:14.0f],
        [_telegramHeaderLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_telegramJoinButton.leadingAnchor constant:-8.0f],

        [_telegramHandleLabel.leadingAnchor constraintEqualToAnchor:_telegramHeaderLabel.leadingAnchor],
        [_telegramHandleLabel.topAnchor constraintEqualToAnchor:_telegramHeaderLabel.bottomAnchor constant:2.0f],
        [_telegramHandleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_telegramJoinButton.leadingAnchor constant:-8.0f],

        [_telegramSubLabel.leadingAnchor constraintEqualToAnchor:_telegramHeaderLabel.leadingAnchor],
        [_telegramSubLabel.topAnchor constraintEqualToAnchor:_telegramHandleLabel.bottomAnchor constant:2.0f],
        [_telegramSubLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_telegramJoinButton.leadingAnchor constant:-8.0f],
    ]];

    // 4. Developer Card (DLX07)
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

    // 5. Security & Protection Card
    _securityCard = [[UIView alloc] init];
    _securityCard.translatesAutoresizingMaskIntoConstraints = NO;
    _securityCard.backgroundColor = [UIColor colorWithRed:22/255.0 green:27/255.0 blue:34/255.0 alpha:0.95];
    _securityCard.layer.cornerRadius = 16.0f;
    _securityCard.layer.borderColor = [UIColor colorWithRed:33/255.0 green:38/255.0 blue:45/255.0 alpha:1.0].CGColor;
    _securityCard.layer.borderWidth = 1.0f;
    [_settingContentView addSubview:_securityCard];

    UIImageView *secIcon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"shield.lefthalf.filled"]];
    secIcon.translatesAutoresizingMaskIntoConstraints = NO;
    secIcon.tintColor = [UIColor colorWithRed:46/255.0 green:204/255.0 blue:113/255.0 alpha:1.0];
    secIcon.contentMode = UIViewContentModeScaleAspectFit;
    [_securityCard addSubview:secIcon];

    _secHeaderLabel = [[UILabel alloc] init];
    _secHeaderLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _secHeaderLabel.textColor = [UIColor colorWithRed:139/255.0 green:148/255.0 blue:158/255.0 alpha:1.0];
    _secHeaderLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightBold];
    [_securityCard addSubview:_secHeaderLabel];

    [NSLayoutConstraint activateConstraints:@[
        [secIcon.leadingAnchor constraintEqualToAnchor:_securityCard.leadingAnchor constant:16.0f],
        [secIcon.topAnchor constraintEqualToAnchor:_securityCard.topAnchor constant:14.0f],
        [secIcon.widthAnchor constraintEqualToConstant:18.0f],
        [secIcon.heightAnchor constraintEqualToConstant:18.0f],

        [_secHeaderLabel.leadingAnchor constraintEqualToAnchor:secIcon.trailingAnchor constant:8.0f],
        [_secHeaderLabel.centerYAnchor constraintEqualToAnchor:secIcon.centerYAnchor],
    ]];

    auto makeSecRow = ^UIView *(UILabel *tLbl, UILabel *vLbl, NSString *valStr, UIColor *vColor, UIView *topView) {
        UIView *row = [[UIView alloc] init];
        row.translatesAutoresizingMaskIntoConstraints = NO;
        [_securityCard addSubview:row];

        tLbl.translatesAutoresizingMaskIntoConstraints = NO;
        tLbl.textColor = [UIColor colorWithRed:139/255.0 green:148/255.0 blue:158/255.0 alpha:1.0];
        tLbl.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
        [row addSubview:tLbl];

        vLbl.translatesAutoresizingMaskIntoConstraints = NO;
        vLbl.text = valStr;
        vLbl.textColor = vColor ?: UIColor.whiteColor;
        vLbl.font = [UIFont systemFontOfSize:13 weight:UIFontWeightBold];
        [row addSubview:vLbl];

        [NSLayoutConstraint activateConstraints:@[
            [row.leadingAnchor constraintEqualToAnchor:_securityCard.leadingAnchor constant:16.0f],
            [row.trailingAnchor constraintEqualToAnchor:_securityCard.trailingAnchor constant:-16.0f],
            [row.heightAnchor constraintEqualToConstant:28.0f],
            [tLbl.leadingAnchor constraintEqualToAnchor:row.leadingAnchor],
            [tLbl.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
            [vLbl.trailingAnchor constraintEqualToAnchor:row.trailingAnchor],
            [vLbl.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        ]];

        if (topView) {
            [row.topAnchor constraintEqualToAnchor:topView.bottomAnchor constant:4.0f].active = YES;
        } else {
            [row.topAnchor constraintEqualToAnchor:secIcon.bottomAnchor constant:10.0f].active = YES;
        }
        return row;
    };

    _secRow1Title = [[UILabel alloc] init];
    _secRow1Val = [[UILabel alloc] init];
    _secRow2Title = [[UILabel alloc] init];
    _secRow2Val = [[UILabel alloc] init];
    _secRow3Title = [[UILabel alloc] init];
    _secRow3Val = [[UILabel alloc] init];

    UIView *secRow1 = makeSecRow(_secRow1Title, _secRow1Val, @"Active (Safe)", [UIColor colorWithRed:46/255.0 green:204/255.0 blue:113/255.0 alpha:1.0], nil);
    UIView *secRow2 = makeSecRow(_secRow2Title, _secRow2Val, @"120 FPS Metal", [UIColor colorWithRed:0/255.0 green:210/255.0 blue:180/255.0 alpha:1.0], secRow1);
    UIView *secRow3 = makeSecRow(_secRow3Title, _secRow3Val, @"DarkSword Kernel (R/W)", UIColor.whiteColor, secRow2);

    // 6. App Details Card
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
    UIView *r4 = makeRow(_infoRow4Title, @"DarkSword Kernel", r3);

    // 7. Quick Utilities Card
    _utilCard = [[UIView alloc] init];
    _utilCard.translatesAutoresizingMaskIntoConstraints = NO;
    _utilCard.backgroundColor = [UIColor colorWithRed:22/255.0 green:27/255.0 blue:34/255.0 alpha:0.95];
    _utilCard.layer.cornerRadius = 16.0f;
    _utilCard.layer.borderColor = [UIColor colorWithRed:33/255.0 green:38/255.0 blue:45/255.0 alpha:1.0].CGColor;
    _utilCard.layer.borderWidth = 1.0f;
    [_settingContentView addSubview:_utilCard];

    UIImageView *utilIcon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"slider.horizontal.3"]];
    utilIcon.translatesAutoresizingMaskIntoConstraints = NO;
    utilIcon.tintColor = [UIColor colorWithRed:0/255.0 green:210/255.0 blue:180/255.0 alpha:1.0];
    utilIcon.contentMode = UIViewContentModeScaleAspectFit;
    [_utilCard addSubview:utilIcon];

    _utilHeaderLabel = [[UILabel alloc] init];
    _utilHeaderLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _utilHeaderLabel.textColor = [UIColor colorWithRed:139/255.0 green:148/255.0 blue:158/255.0 alpha:1.0];
    _utilHeaderLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightBold];
    [_utilCard addSubview:_utilHeaderLabel];

    _clearCacheBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    _clearCacheBtn.translatesAutoresizingMaskIntoConstraints = NO;
    _clearCacheBtn.backgroundColor = [UIColor colorWithRed:31/255.0 green:38/255.0 blue:48/255.0 alpha:1.0];
    [_clearCacheBtn setTitleColor:[UIColor colorWithRed:0/255.0 green:210/255.0 blue:180/255.0 alpha:1.0] forState:UIControlStateNormal];
    _clearCacheBtn.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightBold];
    _clearCacheBtn.layer.cornerRadius = 10.0f;
    _clearCacheBtn.layer.borderColor = [UIColor colorWithRed:0/255.0 green:210/255.0 blue:180/255.0 alpha:0.35].CGColor;
    _clearCacheBtn.layer.borderWidth = 1.0f;
    [_clearCacheBtn addTarget:self action:@selector(clearCacheTapped:) forControlEvents:UIControlEventTouchUpInside];
    [_utilCard addSubview:_clearCacheBtn];

    _resetConfigBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    _resetConfigBtn.translatesAutoresizingMaskIntoConstraints = NO;
    _resetConfigBtn.backgroundColor = [UIColor colorWithRed:31/255.0 green:38/255.0 blue:48/255.0 alpha:1.0];
    [_resetConfigBtn setTitleColor:[UIColor colorWithRed:231/255.0 green:76/255.0 blue:60/255.0 alpha:1.0] forState:UIControlStateNormal];
    _resetConfigBtn.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightBold];
    _resetConfigBtn.layer.cornerRadius = 10.0f;
    _resetConfigBtn.layer.borderColor = [UIColor colorWithRed:231/255.0 green:76/255.0 blue:60/255.0 alpha:0.35].CGColor;
    _resetConfigBtn.layer.borderWidth = 1.0f;
    [_resetConfigBtn addTarget:self action:@selector(resetConfigTapped:) forControlEvents:UIControlEventTouchUpInside];
    [_utilCard addSubview:_resetConfigBtn];

    [NSLayoutConstraint activateConstraints:@[
        [utilIcon.leadingAnchor constraintEqualToAnchor:_utilCard.leadingAnchor constant:16.0f],
        [utilIcon.topAnchor constraintEqualToAnchor:_utilCard.topAnchor constant:14.0f],
        [utilIcon.widthAnchor constraintEqualToConstant:18.0f],
        [utilIcon.heightAnchor constraintEqualToConstant:18.0f],

        [_utilHeaderLabel.leadingAnchor constraintEqualToAnchor:utilIcon.trailingAnchor constant:8.0f],
        [_utilHeaderLabel.centerYAnchor constraintEqualToAnchor:utilIcon.centerYAnchor],

        [_clearCacheBtn.topAnchor constraintEqualToAnchor:utilIcon.bottomAnchor constant:12.0f],
        [_clearCacheBtn.leadingAnchor constraintEqualToAnchor:_utilCard.leadingAnchor constant:16.0f],
        [_clearCacheBtn.trailingAnchor constraintEqualToAnchor:_utilCard.trailingAnchor constant:-16.0f],
        [_clearCacheBtn.heightAnchor constraintEqualToConstant:36.0f],

        [_resetConfigBtn.topAnchor constraintEqualToAnchor:_clearCacheBtn.bottomAnchor constant:10.0f],
        [_resetConfigBtn.leadingAnchor constraintEqualToAnchor:_utilCard.leadingAnchor constant:16.0f],
        [_resetConfigBtn.trailingAnchor constraintEqualToAnchor:_utilCard.trailingAnchor constant:-16.0f],
        [_resetConfigBtn.heightAnchor constraintEqualToConstant:36.0f],
    ]];

    // 8. Note Card
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
        [_settingTitleLabel.topAnchor constraintEqualToAnchor:_settingContentView.topAnchor constant:20.0f],
        [_settingTitleLabel.centerXAnchor constraintEqualToAnchor:_settingContentView.centerXAnchor],

        [_settingSubTitleLabel.topAnchor constraintEqualToAnchor:_settingTitleLabel.bottomAnchor constant:4.0f],
        [_settingSubTitleLabel.centerXAnchor constraintEqualToAnchor:_settingContentView.centerXAnchor],

        [langCard.topAnchor constraintEqualToAnchor:_settingSubTitleLabel.bottomAnchor constant:16.0f],
        [langCard.leadingAnchor constraintEqualToAnchor:_settingContentView.leadingAnchor constant:20.0f],
        [langCard.trailingAnchor constraintEqualToAnchor:_settingContentView.trailingAnchor constant:-20.0f],

        [_licenseCard.topAnchor constraintEqualToAnchor:langCard.bottomAnchor constant:14.0f],
        [_licenseCard.leadingAnchor constraintEqualToAnchor:_settingContentView.leadingAnchor constant:20.0f],
        [_licenseCard.trailingAnchor constraintEqualToAnchor:_settingContentView.trailingAnchor constant:-20.0f],

        [_telegramCard.topAnchor constraintEqualToAnchor:_licenseCard.bottomAnchor constant:14.0f],
        [_telegramCard.leadingAnchor constraintEqualToAnchor:_settingContentView.leadingAnchor constant:20.0f],
        [_telegramCard.trailingAnchor constraintEqualToAnchor:_settingContentView.trailingAnchor constant:-20.0f],
        [_telegramCard.heightAnchor constraintEqualToConstant:84.0f],

        [devCard.topAnchor constraintEqualToAnchor:_telegramCard.bottomAnchor constant:14.0f],
        [devCard.leadingAnchor constraintEqualToAnchor:_settingContentView.leadingAnchor constant:20.0f],
        [devCard.trailingAnchor constraintEqualToAnchor:_settingContentView.trailingAnchor constant:-20.0f],
        [devCard.heightAnchor constraintEqualToConstant:80.0f],

        [_securityCard.topAnchor constraintEqualToAnchor:devCard.bottomAnchor constant:14.0f],
        [_securityCard.leadingAnchor constraintEqualToAnchor:_settingContentView.leadingAnchor constant:20.0f],
        [_securityCard.trailingAnchor constraintEqualToAnchor:_settingContentView.trailingAnchor constant:-20.0f],
        [_securityCard.bottomAnchor constraintEqualToAnchor:secRow3.bottomAnchor constant:14.0f],

        [infoCard.topAnchor constraintEqualToAnchor:_securityCard.bottomAnchor constant:14.0f],
        [infoCard.leadingAnchor constraintEqualToAnchor:_settingContentView.leadingAnchor constant:20.0f],
        [infoCard.trailingAnchor constraintEqualToAnchor:_settingContentView.trailingAnchor constant:-20.0f],
        [infoCard.bottomAnchor constraintEqualToAnchor:r4.bottomAnchor constant:14.0f],

        [_utilCard.topAnchor constraintEqualToAnchor:infoCard.bottomAnchor constant:14.0f],
        [_utilCard.leadingAnchor constraintEqualToAnchor:_settingContentView.leadingAnchor constant:20.0f],
        [_utilCard.trailingAnchor constraintEqualToAnchor:_settingContentView.trailingAnchor constant:-20.0f],
        [_utilCard.bottomAnchor constraintEqualToAnchor:_resetConfigBtn.bottomAnchor constant:14.0f],

        [noteCard.topAnchor constraintEqualToAnchor:_utilCard.bottomAnchor constant:14.0f],
        [noteCard.leadingAnchor constraintEqualToAnchor:_settingContentView.leadingAnchor constant:20.0f],
        [noteCard.trailingAnchor constraintEqualToAnchor:_settingContentView.trailingAnchor constant:-20.0f],
        [noteCard.bottomAnchor constraintEqualToAnchor:_settingContentView.bottomAnchor constant:-30.0f],

        [_noteLabel.topAnchor constraintEqualToAnchor:noteCard.topAnchor constant:12.0f],
        [_noteLabel.bottomAnchor constraintEqualToAnchor:noteCard.bottomAnchor constant:-12.0f],
        [_noteLabel.leadingAnchor constraintEqualToAnchor:noteCard.leadingAnchor constant:16.0f],
        [_noteLabel.trailingAnchor constraintEqualToAnchor:noteCard.trailingAnchor constant:-16.0f],
    ]];
}

#pragma mark - Telegram and Utility Actions

- (void)openTelegramLink
{
    if (_impactFeedbackGenerator) [_impactFeedbackGenerator impactOccurred];

    BOOL isEN = IsEnglish();
    [self appendConsoleLog:@"SYS" message:(isEN ? @"Opening Telegram channel: @ds_pubgmb" : @"Đang mở liên kết Telegram: @ds_pubgmb") tagColor:[UIColor colorWithRed:36/255.0 green:161/255.0 blue:222/255.0 alpha:1.0]];

    NSURL *url = [NSURL URLWithString:@"https://t.me/ds_pubgmb"];
    if ([[UIApplication sharedApplication] canOpenURL:url]) {
        [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
    }
}

- (void)clearCacheTapped:(UIButton *)sender
{
    if (_impactFeedbackGenerator) [_impactFeedbackGenerator impactOccurred];

    NSString *tmpDir = NSTemporaryDirectory();
    NSArray *tmpFiles = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:tmpDir error:nil];
    for (NSString *file in tmpFiles) {
        [[NSFileManager defaultManager] removeItemAtPath:[tmpDir stringByAppendingPathComponent:file] error:nil];
    }

    BOOL isEN = IsEnglish();
    [self appendConsoleLog:@"SYS" message:(isEN ? @"Memory cache purged successfully" : @"Đã giải phóng bộ nhớ đệm thành công") tagColor:[UIColor colorWithRed:46/255.0 green:204/255.0 blue:113/255.0 alpha:1.0]];

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:isEN ? @"Notice" : @"Thông báo"
                                                                   message:isEN ? @"Temporary memory cache cleaned successfully!" : @"Đã dọn dẹp bộ nhớ đệm thành công!"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:isEN ? @"OK" : @"Đã hiểu" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)resetConfigTapped:(UIButton *)sender
{
    if (_impactFeedbackGenerator) [_impactFeedbackGenerator impactOccurred];

    BOOL isEN = IsEnglish();
    UIAlertController *confirm = [UIAlertController alertControllerWithTitle:isEN ? @"Reset HUD Settings" : @"Đặt lại cài đặt HUD"
                                                                     message:isEN ? @"Are you sure you want to reset all HUD configurations to default?" : @"Bạn có chắc chắn muốn đặt lại toàn bộ cấu hình HUD về mặc định?"
                                                              preferredStyle:UIAlertControllerStyleAlert];
    [confirm addAction:[UIAlertAction actionWithTitle:isEN ? @"Cancel" : @"Huỷ" style:UIAlertActionStyleCancel handler:nil]];
    [confirm addAction:[UIAlertAction actionWithTitle:isEN ? @"Reset" : @"Đặt lại" style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
        NSDictionary *defaults = @{
            @"DarkPubg_ShowLine": @NO,
            @"DarkPubg_ShowBox": @YES,
            @"DarkPubg_ShowHealth": @YES,
            @"DarkPubg_ShowDistance": @YES,
            @"DarkPubg_ShowBones": @YES,
            @"DarkPubg_ShowWeapon": @YES,
            @"DarkPubg_ShowTotalEnemies": @YES,
            @"DarkPubg_ScanDistance": @300.0,
        };
        for (NSString *key in defaults) {
            [[NSUserDefaults standardUserDefaults] setObject:defaults[key] forKey:key];
        }
        [[NSUserDefaults standardUserDefaults] synchronize];

        [self appendConsoleLog:@"SYS" message:(isEN ? @"HUD configuration reset to defaults" : @"Đã khôi phục cài đặt HUD về mặc định") tagColor:[UIColor colorWithRed:241/255.0 green:196/255.0 blue:15/255.0 alpha:1.0]];

        UIAlertController *doneAlert = [UIAlertController alertControllerWithTitle:isEN ? @"Success" : @"Thành công"
                                                                           message:isEN ? @"HUD configuration restored to default settings!" : @"Đã đặt lại cấu hình HUD về mặc định!"
                                                                    preferredStyle:UIAlertControllerStyleAlert];
        [doneAlert addAction:[UIAlertAction actionWithTitle:isEN ? @"OK" : @"Đã hiểu" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:doneAlert animated:YES completion:nil];
    }]];
    [self presentViewController:confirm animated:YES completion:nil];
}

#pragma mark - Console Logging and Pulse Helpers

- (void)appendConsoleLog:(NSString *)tag message:(NSString *)msg tagColor:(UIColor *)color
{
    if (!_consoleTextView) return;

    dispatch_async(dispatch_get_main_queue(), ^{
        NSDateFormatter *df = [[NSDateFormatter alloc] init];
        [df setDateFormat:@"HH:mm:ss"];
        NSString *timeStr = [df stringFromDate:[NSDate date]];

        NSMutableAttributedString *line = [[NSMutableAttributedString alloc] init];

        // Timestamp [HH:mm:ss]
        NSDictionary *timeAttrs = @{
            NSForegroundColorAttributeName: [UIColor colorWithRed:110/255.0 green:118/255.0 blue:129/255.0 alpha:1.0],
            NSFontAttributeName: [UIFont monospacedSystemFontOfSize:10.5 weight:UIFontWeightRegular],
        };
        [line appendAttributedString:[[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"[%@] ", timeStr] attributes:timeAttrs]];

        // Tag [TAG]
        NSDictionary *tagAttrs = @{
            NSForegroundColorAttributeName: color ?: [UIColor colorWithRed:0/255.0 green:210/255.0 blue:180/255.0 alpha:1.0],
            NSFontAttributeName: [UIFont monospacedSystemFontOfSize:10.5 weight:UIFontWeightBold],
        };
        [line appendAttributedString:[[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"[%@] ", tag] attributes:tagAttrs]];

        // Message
        NSDictionary *msgAttrs = @{
            NSForegroundColorAttributeName: [UIColor colorWithRed:201/255.0 green:209/255.0 blue:217/255.0 alpha:1.0],
            NSFontAttributeName: [UIFont monospacedSystemFontOfSize:11.0 weight:UIFontWeightRegular],
        };
        [line appendAttributedString:[[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"%@\n", msg] attributes:msgAttrs]];

        if (!self->_consoleLogStorage) {
            self->_consoleLogStorage = [[NSMutableAttributedString alloc] init];
        }
        [self->_consoleLogStorage appendAttributedString:line];
        self->_consoleTextView.attributedText = self->_consoleLogStorage;

        if (self->_consoleTextView.text.length > 0) {
            NSRange bottom = NSMakeRange(self->_consoleTextView.text.length - 1, 1);
            [self->_consoleTextView scrollRangeToVisible:bottom];
        }
    });
}

- (void)startPulseAnimation:(UIView *)view
{
    if (!view) return;
    [UIView animateWithDuration:0.9 delay:0 options:UIViewAnimationOptionAutoreverse | UIViewAnimationOptionRepeat | UIViewAnimationOptionCurveEaseInOut animations:^{
        view.alpha = 0.25f;
    } completion:nil];
}

- (void)seedBootLogs
{
    BOOL isEN = IsEnglish();
    NSString *iosVer = @"";
    NSString *dsStatus = @"";
    BOOL isSupported = CheckDarkSwordSupport(&iosVer, &dsStatus);

    [self appendConsoleLog:@"SYS" message:(isEN ? @"DarkPubg Core Loader v1.0-1 initialized" : @"Hệ thống DarkPubg Core v1.0-1 khởi động") tagColor:[UIColor colorWithRed:88/255.0 green:166/255.0 blue:255/255.0 alpha:1.0]];
    [self appendConsoleLog:@"INFO" message:[NSString stringWithFormat:isEN ? @"Host OS: iOS %@ detected" : @"Thiết bị: iOS %@ đã nhận diện", [[UIDevice currentDevice] systemVersion]] tagColor:[UIColor colorWithRed:0/255.0 green:210/255.0 blue:180/255.0 alpha:1.0]];
    if (isSupported) {
        [self appendConsoleLog:@"OK" message:(isEN ? @"Kernel Compatibility: PASSED (DarkSword supported)" : @"Tương thích Kernel: ĐẠT (Hỗ trợ DarkSword)") tagColor:[UIColor colorWithRed:46/255.0 green:204/255.0 blue:113/255.0 alpha:1.0]];
    } else {
        [self appendConsoleLog:@"WARN" message:(isEN ? @"Kernel Compatibility: WARNING (iOS unsupported)" : @"Tương thích Kernel: CẢNH BÁO (iOS chưa hỗ trợ)") tagColor:[UIColor colorWithRed:255/255.0 green:59/255.0 blue:48/255.0 alpha:1.0]];
    }
    [self appendConsoleLog:@"KERN" message:(isEN ? @"DarkSword kernel driver: Direct R/W active" : @"DarkSword Kernel driver: Kích hoạt bộ nhớ R/W") tagColor:[UIColor colorWithRed:241/255.0 green:196/255.0 blue:15/255.0 alpha:1.0]];
    [self appendConsoleLog:@"ESP" message:(isEN ? @"Metal 120 FPS rendering pipeline ready" : @"Engine hiển thị đồ hoạ Metal 120 FPS sẵn sàng") tagColor:[UIColor colorWithRed:0/255.0 green:210/255.0 blue:180/255.0 alpha:1.0]];
    [self appendConsoleLog:@"PUBG" message:(isEN ? @"Target binary: ShadowTrackerExtra" : @"Mục tiêu gắn kết: ShadowTrackerExtra") tagColor:[UIColor colorWithRed:255/255.0 green:159/255.0 blue:67/255.0 alpha:1.0]];
    [self appendConsoleLog:@"INFO" message:(isEN ? @"Ready. Tap OPEN HUD to attach." : @"Hệ thống sẵn sàng. Nhấn OPEN HUD để bắt đầu.") tagColor:[UIColor colorWithRed:0/255.0 green:210/255.0 blue:180/255.0 alpha:1.0]];
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

    _consoleHeaderLabel.text = isEN ? @"CONSOLE LOG" : @"NHẬT KÝ HỆ THỐNG";
    _consoleLiveLabel.text = isEN ? @"LIVE" : @"HOẠT ĐỘNG";

    // Setting tab
    _settingTitleLabel.text = isEN ? @"Settings" : @"Cài Đặt";
    _settingSubTitleLabel.text = isEN ? @"Information & Options" : @"Thông tin & Tuỳ chọn";
    _langHeaderLabel.text = isEN ? @"LANGUAGE" : @"NGÔN NGỮ";

    // Telegram
    _telegramHeaderLabel.text = isEN ? @"TELEGRAM COMMUNITY" : @"CỘNG ĐỒNG TELEGRAM";
    _telegramSubLabel.text = isEN ? @"Official updates & support group" : @"Nhóm hỗ trợ & cập nhật chính thức";
    [_telegramJoinButton setTitle:isEN ? @"JOIN" : @"THAM GIA" forState:UIControlStateNormal];

    // Developer
    _devHeaderLabel.text = isEN ? @"DEVELOPER" : @"NGƯỜI PHÁT TRIỂN";
    _devNameLabel.text = @"DLX07";

    // Security & Protection
    _secHeaderLabel.text = isEN ? @"SECURITY & ENGINE" : @"BẢO MẬT & HỆ THỐNG";
    _secRow1Title.text = isEN ? @"Anti-Cheat Bypass" : @"Bỏ qua chống gian lận";
    _secRow1Val.text = isEN ? @"Active (Safe)" : @"Hoạt động (An toàn)";
    _secRow2Title.text = isEN ? @"Rendering Pipeline" : @"Luồng hiển thị ESP";
    _secRow2Val.text = @"120 FPS Metal";
    _secRow3Title.text = isEN ? @"Memory Privilege" : @"Đặc quyền bộ nhớ";
    _secRow3Val.text = @"DarkSword Kernel (R/W)";

    // App Details
    _infoRow1Title.text = isEN ? @"App Name" : @"Ứng dụng";
    _infoRow2Title.text = isEN ? @"Version" : @"Phiên bản";
    _infoRow3Title.text = isEN ? @"Target Game" : @"Trò chơi";
    _infoRow4Title.text = isEN ? @"Exploit Engine" : @"Kiểu can thiệp";

    // Utilities
    _utilHeaderLabel.text = isEN ? @"QUICK UTILITIES" : @"CÔNG CỤ TIỆN ÍCH";
    [_clearCacheBtn setTitle:isEN ? @"Clean Memory Cache" : @"Dọn dẹp bộ nhớ đệm" forState:UIControlStateNormal];
    [_resetConfigBtn setTitle:isEN ? @"Reset HUD Settings" : @"Đặt lại cấu hình HUD" forState:UIControlStateNormal];

    // License Card
    if (_licenseHeaderLabel) {
        _licenseHeaderLabel.text = isEN ? @"LICENSE & ACTIVATION" : @"BẢN QUYỀN & GIẤY PHÉP";
    }
    if (_licenseKeyTitle) {
        _licenseKeyTitle.text = isEN ? @"License Key:" : @"Mã Key:";
    }
    if (_licenseExpTitle) {
        _licenseExpTitle.text = isEN ? @"Expiration:" : @"Hạn dùng:";
    }
    if (_licenseRemainTitle) {
        _licenseRemainTitle.text = isEN ? @"Remaining:" : @"Thời hạn còn:";
    }
    if (_changeKeyBtn) {
        [_changeKeyBtn setTitle:isEN ? @"Change Key" : @"Đổi Key" forState:UIControlStateNormal];
    }
    [self updateLicenseCardUI];

    // Auth Gate Modal
    if (_authTitleLabel) {
        _authTitleLabel.text = isEN ? @"DARKPUBG ACTIVATION" : @"KÍCH HOẠT BẢN QUYỀN";
    }
    if (_authSubTitleLabel) {
        _authSubTitleLabel.text = isEN ?
            @"Enter your license key to unlock DarkPubg." :
            @"Nhập mã bản quyền để mở khoá ứng dụng DarkPubg.";
    }
    if (_authKeyTextField) {
        _authKeyTextField.placeholder = isEN ? @"Enter license key..." : @"Nhập mã key của bạn...";
    }
    if (_authPasteKeyButton) {
        [_authPasteKeyButton setTitle:isEN ? @"Paste" : @"Dán" forState:UIControlStateNormal];
    }
    if (_authActivateBtn && !_isAuthValidating) {
        [_authActivateBtn setTitle:isEN ? @"ACTIVATE" : @"KÍCH HOẠT" forState:UIControlStateNormal];
    }
    if (_authTelegramBtn) {
        [_authTelegramBtn setTitle:isEN ? @"Get Key / Telegram Support (@ds_pubgmb)" : @"Mua Key / Hỗ trợ Telegram (@ds_pubgmb)" forState:UIControlStateNormal];
    }

    // Note
    _noteLabel.text = isEN ?
        @"DarkPubg operates directly via DarkSword Kernel on iOS without Jailbreak." :
        @"DarkPubg hoạt động trực tiếp thông qua DarkSword Kernel trên iOS mà không cần Jailbreak.";

    // Warning popup texts if initialized
    if (_warningTitleLabel) {
        _warningTitleLabel.text = isEN ? @"Please launch the game first" : @"Vui lòng vào game trước";
    }
    if (_warningSubLabel) {
        _warningSubLabel.text = isEN ?
            @"Please open PUBG Mobile before launching HUD." :
            @"Hãy mở PUBG Mobile trước khi bật HUD để hệ thống có thể kết nối vào game.";
    }
    if (_warningLaunchGameBtn) {
        [_warningLaunchGameBtn setTitle:isEN ? @"Launch PUBG Mobile" : @"Vào Game PUBG" forState:UIControlStateNormal];
    }
    if (_warningProceedBtn) {
        [_warningProceedBtn setTitle:isEN ? @"Already In-Game (Enable HUD)" : @"Đã Trong Game (Bật HUD)" forState:UIControlStateNormal];
    }
    if (_warningDismissBtn) {
        [_warningDismissBtn setTitle:isEN ? @"Close" : @"Đóng" forState:UIControlStateNormal];
    }
}

#pragma mark - Red Warning Popup (Vui lòng vào game trước)

- (void)openPUBGGameApp
{
    if (_impactFeedbackGenerator) [_impactFeedbackGenerator impactOccurred];
    NSArray *schemes = @[@"pubgmobile://", @"shadowtracker://", @"vngpubg://", @"pubg://"];
    UIApplication *app = [UIApplication sharedApplication];
    for (NSString *s in schemes) {
        NSURL *url = [NSURL URLWithString:s];
        if ([app canOpenURL:url]) {
            [app openURL:url options:@{} completionHandler:nil];
            [self dismissWarningPopup];
            return;
        }
    }
    [app openURL:[NSURL URLWithString:@"pubgmobile://"] options:@{} completionHandler:nil];
    [self dismissWarningPopup];
}

- (void)proceedEnableHUDTapped:(UIButton *)sender
{
    [self dismissWarningPopup];
    [self doEnableHUD];
}

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
        _warningTitleLabel.font = [UIFont systemFontOfSize:19 weight:UIFontWeightHeavy];
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

        // Button 1: Launch game directly
        _warningLaunchGameBtn = [UIButton buttonWithType:UIButtonTypeSystem];
        _warningLaunchGameBtn.translatesAutoresizingMaskIntoConstraints = NO;
        [_warningLaunchGameBtn setTitleColor:[UIColor colorWithRed:13/255.0 green:17/255.0 blue:23/255.0 alpha:1.0] forState:UIControlStateNormal];
        _warningLaunchGameBtn.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightBold];
        _warningLaunchGameBtn.backgroundColor = [UIColor colorWithRed:0/255.0 green:210/255.0 blue:180/255.0 alpha:1.0];
        _warningLaunchGameBtn.layer.cornerRadius = 12.0f;
        [_warningLaunchGameBtn addTarget:self action:@selector(openPUBGGameApp) forControlEvents:UIControlEventTouchUpInside];
        [card addSubview:_warningLaunchGameBtn];

        // Button 2: Proceed anyway if user is already in game
        _warningProceedBtn = [UIButton buttonWithType:UIButtonTypeSystem];
        _warningProceedBtn.translatesAutoresizingMaskIntoConstraints = NO;
        [_warningProceedBtn setTitleColor:[UIColor colorWithRed:46/255.0 green:204/255.0 blue:113/255.0 alpha:1.0] forState:UIControlStateNormal];
        _warningProceedBtn.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightBold];
        _warningProceedBtn.backgroundColor = [UIColor colorWithRed:46/255.0 green:204/255.0 blue:113/255.0 alpha:0.15];
        _warningProceedBtn.layer.cornerRadius = 12.0f;
        _warningProceedBtn.layer.borderColor = [UIColor colorWithRed:46/255.0 green:204/255.0 blue:113/255.0 alpha:0.45].CGColor;
        _warningProceedBtn.layer.borderWidth = 1.0f;
        [_warningProceedBtn addTarget:self action:@selector(proceedEnableHUDTapped:) forControlEvents:UIControlEventTouchUpInside];
        [card addSubview:_warningProceedBtn];

        // Button 3: Close
        _warningDismissBtn = [UIButton buttonWithType:UIButtonTypeSystem];
        _warningDismissBtn.translatesAutoresizingMaskIntoConstraints = NO;
        [_warningDismissBtn setTitleColor:[UIColor colorWithRed:139/255.0 green:148/255.0 blue:158/255.0 alpha:1.0] forState:UIControlStateNormal];
        _warningDismissBtn.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
        [_warningDismissBtn addTarget:self action:@selector(dismissWarningPopup) forControlEvents:UIControlEventTouchUpInside];
        [card addSubview:_warningDismissBtn];

        [NSLayoutConstraint activateConstraints:@[
            [card.centerXAnchor constraintEqualToAnchor:_warningPopupOverlay.centerXAnchor],
            [card.centerYAnchor constraintEqualToAnchor:_warningPopupOverlay.centerYAnchor],
            [card.widthAnchor constraintEqualToConstant:310.0f],

            [icon.topAnchor constraintEqualToAnchor:card.topAnchor constant:20.0f],
            [icon.centerXAnchor constraintEqualToAnchor:card.centerXAnchor],
            [icon.widthAnchor constraintEqualToConstant:40.0f],
            [icon.heightAnchor constraintEqualToConstant:40.0f],

            [_warningTitleLabel.topAnchor constraintEqualToAnchor:icon.bottomAnchor constant:12.0f],
            [_warningTitleLabel.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:16.0f],
            [_warningTitleLabel.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-16.0f],

            [_warningSubLabel.topAnchor constraintEqualToAnchor:_warningTitleLabel.bottomAnchor constant:8.0f],
            [_warningSubLabel.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:18.0f],
            [_warningSubLabel.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-18.0f],

            [_warningLaunchGameBtn.topAnchor constraintEqualToAnchor:_warningSubLabel.bottomAnchor constant:18.0f],
            [_warningLaunchGameBtn.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:20.0f],
            [_warningLaunchGameBtn.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-20.0f],
            [_warningLaunchGameBtn.heightAnchor constraintEqualToConstant:40.0f],

            [_warningProceedBtn.topAnchor constraintEqualToAnchor:_warningLaunchGameBtn.bottomAnchor constant:10.0f],
            [_warningProceedBtn.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:20.0f],
            [_warningProceedBtn.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-20.0f],
            [_warningProceedBtn.heightAnchor constraintEqualToConstant:38.0f],

            [_warningDismissBtn.topAnchor constraintEqualToAnchor:_warningProceedBtn.bottomAnchor constant:6.0f],
            [_warningDismissBtn.centerXAnchor constraintEqualToAnchor:card.centerXAnchor],
            [_warningDismissBtn.heightAnchor constraintEqualToConstant:32.0f],
            [_warningDismissBtn.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-14.0f],
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

#pragma mark - Key Authentication Gate (Auth System)

- (void)setupAuthGateOverlay
{
    _authGateOverlay = [[UIView alloc] initWithFrame:self.view.bounds];
    _authGateOverlay.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _authGateOverlay.backgroundColor = [UIColor colorWithRed:10/255.0 green:14/255.0 blue:20/255.0 alpha:0.96];
    _authGateOverlay.hidden = YES;
    _authGateOverlay.alpha = 0.0f;

    UITapGestureRecognizer *tapBg = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dismissKeyboardTapped)];
    tapBg.cancelsTouchesInView = NO;
    [_authGateOverlay addGestureRecognizer:tapBg];

    _authCardView = [[UIView alloc] init];
    _authCardView.translatesAutoresizingMaskIntoConstraints = NO;
    _authCardView.backgroundColor = [UIColor colorWithRed:22/255.0 green:27/255.0 blue:34/255.0 alpha:0.98];
    _authCardView.layer.cornerRadius = 22.0f;
    _authCardView.layer.borderColor = [UIColor colorWithRed:0/255.0 green:210/255.0 blue:180/255.0 alpha:0.85].CGColor;
    _authCardView.layer.borderWidth = 1.5f;
    _authCardView.layer.shadowColor = [UIColor colorWithRed:0/255.0 green:210/255.0 blue:180/255.0 alpha:0.35].CGColor;
    _authCardView.layer.shadowOffset = CGSizeMake(0, 8);
    _authCardView.layer.shadowRadius = 18.0f;
    _authCardView.layer.shadowOpacity = 0.9f;
    [_authGateOverlay addSubview:_authCardView];

    // Close button (top right)
    _authCloseBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    _authCloseBtn.translatesAutoresizingMaskIntoConstraints = NO;
    UIImage *xImg = [UIImage systemImageNamed:@"xmark.circle.fill"];
    [_authCloseBtn setImage:xImg forState:UIControlStateNormal];
    _authCloseBtn.tintColor = [UIColor colorWithRed:139/255.0 green:148/255.0 blue:158/255.0 alpha:1.0];
    [_authCloseBtn addTarget:self action:@selector(authCloseButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
    [_authCardView addSubview:_authCloseBtn];

    // Icon (Lock shield)
    UIImageView *lockIcon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"lock.shield.fill"]];
    lockIcon.translatesAutoresizingMaskIntoConstraints = NO;
    lockIcon.tintColor = [UIColor colorWithRed:0/255.0 green:210/255.0 blue:180/255.0 alpha:1.0];
    lockIcon.contentMode = UIViewContentModeScaleAspectFit;
    [_authCardView addSubview:lockIcon];

    _authTitleLabel = [[UILabel alloc] init];
    _authTitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _authTitleLabel.textColor = UIColor.whiteColor;
    _authTitleLabel.font = [UIFont systemFontOfSize:20 weight:UIFontWeightHeavy];
    _authTitleLabel.textAlignment = NSTextAlignmentCenter;
    [_authCardView addSubview:_authTitleLabel];

    _authSubTitleLabel = [[UILabel alloc] init];
    _authSubTitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _authSubTitleLabel.textColor = [UIColor colorWithRed:139/255.0 green:148/255.0 blue:158/255.0 alpha:1.0];
    _authSubTitleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
    _authSubTitleLabel.textAlignment = NSTextAlignmentCenter;
    _authSubTitleLabel.numberOfLines = 2;
    [_authCardView addSubview:_authSubTitleLabel];

    // Key Input Container
    UIView *keyBox = [[UIView alloc] init];
    keyBox.translatesAutoresizingMaskIntoConstraints = NO;
    keyBox.backgroundColor = [UIColor colorWithRed:13/255.0 green:17/255.0 blue:23/255.0 alpha:1.0];
    keyBox.layer.cornerRadius = 12.0f;
    keyBox.layer.borderColor = [UIColor colorWithRed:48/255.0 green:54/255.0 blue:61/255.0 alpha:1.0].CGColor;
    keyBox.layer.borderWidth = 1.0f;
    [_authCardView addSubview:keyBox];

    UIImageView *keyIcon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"key.horizontal.fill"]];
    keyIcon.translatesAutoresizingMaskIntoConstraints = NO;
    keyIcon.tintColor = [UIColor colorWithRed:0/255.0 green:210/255.0 blue:180/255.0 alpha:1.0];
    keyIcon.contentMode = UIViewContentModeScaleAspectFit;
    [keyBox addSubview:keyIcon];

    _authKeyTextField = [[UITextField alloc] init];
    _authKeyTextField.translatesAutoresizingMaskIntoConstraints = NO;
    _authKeyTextField.textColor = UIColor.whiteColor;
    _authKeyTextField.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    _authKeyTextField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    _authKeyTextField.autocorrectionType = UITextAutocorrectionTypeNo;
    _authKeyTextField.clearButtonMode = UITextFieldViewModeWhileEditing;
    _authKeyTextField.returnKeyType = UIReturnKeyDone;
    [_authKeyTextField addTarget:self action:@selector(authTextFieldReturned:) forControlEvents:UIControlEventEditingDidEndOnExit];
    [keyBox addSubview:_authKeyTextField];

    _authPasteKeyButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _authPasteKeyButton.translatesAutoresizingMaskIntoConstraints = NO;
    _authPasteKeyButton.backgroundColor = [UIColor colorWithRed:0/255.0 green:210/255.0 blue:180/255.0 alpha:0.18];
    [_authPasteKeyButton setTitleColor:[UIColor colorWithRed:0/255.0 green:210/255.0 blue:180/255.0 alpha:1.0] forState:UIControlStateNormal];
    _authPasteKeyButton.titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightBold];
    _authPasteKeyButton.layer.cornerRadius = 8.0f;
    [_authPasteKeyButton addTarget:self action:@selector(pasteKeyTapped:) forControlEvents:UIControlEventTouchUpInside];
    [keyBox addSubview:_authPasteKeyButton];

    // Status Label
    _authStatusLabel = [[UILabel alloc] init];
    _authStatusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _authStatusLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
    _authStatusLabel.textAlignment = NSTextAlignmentCenter;
    _authStatusLabel.numberOfLines = 2;
    _authStatusLabel.textColor = [UIColor colorWithRed:139/255.0 green:148/255.0 blue:158/255.0 alpha:1.0];
    [_authCardView addSubview:_authStatusLabel];

    // Main Activate Button
    _authActivateBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    _authActivateBtn.translatesAutoresizingMaskIntoConstraints = NO;
    _authActivateBtn.backgroundColor = [UIColor colorWithRed:0/255.0 green:210/255.0 blue:180/255.0 alpha:1.0];
    [_authActivateBtn setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    _authActivateBtn.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightHeavy];
    _authActivateBtn.layer.cornerRadius = 22.0f;
    _authActivateBtn.layer.shadowColor = [UIColor colorWithRed:0/255.0 green:210/255.0 blue:180/255.0 alpha:0.45].CGColor;
    _authActivateBtn.layer.shadowOffset = CGSizeMake(0, 4);
    _authActivateBtn.layer.shadowRadius = 10.0f;
    _authActivateBtn.layer.shadowOpacity = 0.8f;
    [_authActivateBtn addTarget:self action:@selector(activateKeyTapped:) forControlEvents:UIControlEventTouchUpInside];
    [_authCardView addSubview:_authActivateBtn];

    _authSpinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhite];
    _authSpinner.translatesAutoresizingMaskIntoConstraints = NO;
    _authSpinner.hidesWhenStopped = YES;
    [_authActivateBtn addSubview:_authSpinner];

    // Telegram Buy/Support Button
    _authTelegramBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    _authTelegramBtn.translatesAutoresizingMaskIntoConstraints = NO;
    _authTelegramBtn.backgroundColor = [UIColor colorWithRed:36/255.0 green:161/255.0 blue:222/255.0 alpha:0.2];
    [_authTelegramBtn setTitleColor:[UIColor colorWithRed:36/255.0 green:161/255.0 blue:222/255.0 alpha:1.0] forState:UIControlStateNormal];
    _authTelegramBtn.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightBold];
    _authTelegramBtn.layer.cornerRadius = 12.0f;
    _authTelegramBtn.layer.borderColor = [UIColor colorWithRed:36/255.0 green:161/255.0 blue:222/255.0 alpha:0.45].CGColor;
    _authTelegramBtn.layer.borderWidth = 1.0f;
    [_authTelegramBtn addTarget:self action:@selector(openTelegramLink) forControlEvents:UIControlEventTouchUpInside];
    [_authCardView addSubview:_authTelegramBtn];

    [NSLayoutConstraint activateConstraints:@[
        [_authCardView.centerXAnchor constraintEqualToAnchor:_authGateOverlay.centerXAnchor],
        [_authCardView.centerYAnchor constraintEqualToAnchor:_authGateOverlay.centerYAnchor constant:-10.0f],
        [_authCardView.leadingAnchor constraintEqualToAnchor:_authGateOverlay.leadingAnchor constant:24.0f],
        [_authCardView.trailingAnchor constraintEqualToAnchor:_authGateOverlay.trailingAnchor constant:-24.0f],
        [_authCardView.widthAnchor constraintLessThanOrEqualToConstant:420.0f],

        [_authCloseBtn.topAnchor constraintEqualToAnchor:_authCardView.topAnchor constant:12.0f],
        [_authCloseBtn.trailingAnchor constraintEqualToAnchor:_authCardView.trailingAnchor constant:-12.0f],
        [_authCloseBtn.widthAnchor constraintEqualToConstant:32.0f],
        [_authCloseBtn.heightAnchor constraintEqualToConstant:32.0f],

        [lockIcon.topAnchor constraintEqualToAnchor:_authCardView.topAnchor constant:22.0f],
        [lockIcon.centerXAnchor constraintEqualToAnchor:_authCardView.centerXAnchor],
        [lockIcon.widthAnchor constraintEqualToConstant:40.0f],
        [lockIcon.heightAnchor constraintEqualToConstant:40.0f],

        [_authTitleLabel.topAnchor constraintEqualToAnchor:lockIcon.bottomAnchor constant:10.0f],
        [_authTitleLabel.leadingAnchor constraintEqualToAnchor:_authCardView.leadingAnchor constant:16.0f],
        [_authTitleLabel.trailingAnchor constraintEqualToAnchor:_authCardView.trailingAnchor constant:-16.0f],

        [_authSubTitleLabel.topAnchor constraintEqualToAnchor:_authTitleLabel.bottomAnchor constant:4.0f],
        [_authSubTitleLabel.leadingAnchor constraintEqualToAnchor:_authCardView.leadingAnchor constant:16.0f],
        [_authSubTitleLabel.trailingAnchor constraintEqualToAnchor:_authCardView.trailingAnchor constant:-16.0f],

        [keyBox.topAnchor constraintEqualToAnchor:_authSubTitleLabel.bottomAnchor constant:16.0f],
        [keyBox.leadingAnchor constraintEqualToAnchor:_authCardView.leadingAnchor constant:16.0f],
        [keyBox.trailingAnchor constraintEqualToAnchor:_authCardView.trailingAnchor constant:-16.0f],
        [keyBox.heightAnchor constraintEqualToConstant:46.0f],

        [keyIcon.leadingAnchor constraintEqualToAnchor:keyBox.leadingAnchor constant:12.0f],
        [keyIcon.centerYAnchor constraintEqualToAnchor:keyBox.centerYAnchor],
        [keyIcon.widthAnchor constraintEqualToConstant:18.0f],
        [keyIcon.heightAnchor constraintEqualToConstant:18.0f],

        [_authKeyTextField.leadingAnchor constraintEqualToAnchor:keyIcon.trailingAnchor constant:8.0f],
        [_authKeyTextField.trailingAnchor constraintEqualToAnchor:_authPasteKeyButton.leadingAnchor constant:-8.0f],
        [_authKeyTextField.topAnchor constraintEqualToAnchor:keyBox.topAnchor],
        [_authKeyTextField.bottomAnchor constraintEqualToAnchor:keyBox.bottomAnchor],

        [_authPasteKeyButton.trailingAnchor constraintEqualToAnchor:keyBox.trailingAnchor constant:-8.0f],
        [_authPasteKeyButton.centerYAnchor constraintEqualToAnchor:keyBox.centerYAnchor],
        [_authPasteKeyButton.widthAnchor constraintEqualToConstant:52.0f],
        [_authPasteKeyButton.heightAnchor constraintEqualToConstant:30.0f],

        [_authStatusLabel.topAnchor constraintEqualToAnchor:keyBox.bottomAnchor constant:10.0f],
        [_authStatusLabel.leadingAnchor constraintEqualToAnchor:_authCardView.leadingAnchor constant:16.0f],
        [_authStatusLabel.trailingAnchor constraintEqualToAnchor:_authCardView.trailingAnchor constant:-16.0f],
        [_authStatusLabel.heightAnchor constraintGreaterThanOrEqualToConstant:20.0f],

        [_authActivateBtn.topAnchor constraintEqualToAnchor:_authStatusLabel.bottomAnchor constant:12.0f],
        [_authActivateBtn.leadingAnchor constraintEqualToAnchor:_authCardView.leadingAnchor constant:16.0f],
        [_authActivateBtn.trailingAnchor constraintEqualToAnchor:_authCardView.trailingAnchor constant:-16.0f],
        [_authActivateBtn.heightAnchor constraintEqualToConstant:44.0f],

        [_authSpinner.centerXAnchor constraintEqualToAnchor:_authActivateBtn.centerXAnchor],
        [_authSpinner.centerYAnchor constraintEqualToAnchor:_authActivateBtn.centerYAnchor],

        [_authTelegramBtn.topAnchor constraintEqualToAnchor:_authActivateBtn.bottomAnchor constant:10.0f],
        [_authTelegramBtn.leadingAnchor constraintEqualToAnchor:_authCardView.leadingAnchor constant:16.0f],
        [_authTelegramBtn.trailingAnchor constraintEqualToAnchor:_authCardView.trailingAnchor constant:-16.0f],
        [_authTelegramBtn.heightAnchor constraintEqualToConstant:38.0f],
        [_authTelegramBtn.bottomAnchor constraintEqualToAnchor:_authCardView.bottomAnchor constant:-20.0f],
    ]];
}

- (void)showAuthGateOverlayWithAnimation:(BOOL)animated
{
    if (!_authGateOverlay.superview) {
        [self.view addSubview:_authGateOverlay];
    }
    [self.view bringSubviewToFront:_authGateOverlay];

    BOOL hasActiveSession = authguard::session_looks_active() && authguard::menu_access_ok(auth::api_instance);
    _authCloseBtn.hidden = !hasActiveSession;

    std::string saved = auth::load_key();
    if (_authKeyTextField.text.length == 0 && !saved.empty()) {
        _authKeyTextField.text = [NSString stringWithUTF8String:saved.c_str()];
    }

    [self applyLanguageTexts];

    _authGateOverlay.hidden = NO;
    if (animated) {
        _authGateOverlay.alpha = 0.0f;
        _authCardView.transform = CGAffineTransformMakeScale(0.9, 0.9);
        [UIView animateWithDuration:0.25 delay:0 usingSpringWithDamping:0.85 initialSpringVelocity:1.0 options:UIViewAnimationOptionCurveEaseOut animations:^{
            self->_authGateOverlay.alpha = 1.0f;
            self->_authCardView.transform = CGAffineTransformIdentity;
        } completion:nil];
    } else {
        _authGateOverlay.alpha = 1.0f;
        _authCardView.transform = CGAffineTransformIdentity;
    }
}

- (void)dismissAuthGateOverlayWithAnimation:(BOOL)animated
{
    [self.view endEditing:YES];
    if (animated) {
        [UIView animateWithDuration:0.2 delay:0 options:UIViewAnimationOptionCurveEaseIn animations:^{
            self->_authGateOverlay.alpha = 0.0f;
            self->_authCardView.transform = CGAffineTransformMakeScale(0.9, 0.9);
        } completion:^(BOOL finished) {
            self->_authGateOverlay.hidden = YES;
        }];
    } else {
        _authGateOverlay.alpha = 0.0f;
        _authGateOverlay.hidden = YES;
    }
}

- (void)authCloseButtonTapped:(UIButton *)sender
{
    if (authguard::session_looks_active() && authguard::menu_access_ok(auth::api_instance)) {
        [self dismissAuthGateOverlayWithAnimation:YES];
    }
}

- (void)activateKeyTapped:(UIButton *)sender
{
    if (_isAuthValidating) return;
    if (_impactFeedbackGenerator) [_impactFeedbackGenerator impactOccurred];
    [self.view endEditing:YES];

    NSString *rawKey = _authKeyTextField.text;
    NSString *trimmed = [rawKey stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length == 0) {
        UINotificationFeedbackGenerator *fb = [[UINotificationFeedbackGenerator alloc] init];
        [fb notificationOccurred:UINotificationFeedbackTypeError];
        _authStatusLabel.textColor = [UIColor colorWithRed:231/255.0 green:76/255.0 blue:60/255.0 alpha:1.0];
        _authStatusLabel.text = IsEnglish() ? @"Please enter a valid license key!" : @"Vui lòng nhập mã key của bạn!";
        [self shakeView:_authCardView];
        return;
    }

    _isAuthValidating = YES;
    _authActivateBtn.userInteractionEnabled = NO;
    [_authActivateBtn setTitle:@"" forState:UIControlStateNormal];
    [_authSpinner startAnimating];

    BOOL isEN = IsEnglish();
    _authStatusLabel.textColor = [UIColor colorWithRed:241/255.0 green:196/255.0 blue:15/255.0 alpha:1.0];
    _authStatusLabel.text = isEN ? @"Authenticating license with server..." : @"Đang xác thực bản quyền với máy chủ...";

    [self appendConsoleLog:@"AUTH" message:[NSString stringWithFormat:(isEN ? @"Validating key: %.8s..." : @"Đang kiểm tra key: %.8s..."), [trimmed UTF8String]] tagColor:[UIColor colorWithRed:88/255.0 green:166/255.0 blue:255/255.0 alpha:1.0]];

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        auth::v_chk_0x33 = false;
        auth::session_active = false;
        auth::vnp_token = 0;
        auth::api_instance.clear_license_state();

        auth::username = [trimmed UTF8String];
        auth::login();

        dispatch_async(dispatch_get_main_queue(), ^{
            self->_isAuthValidating = NO;
            self->_authActivateBtn.userInteractionEnabled = YES;
            [self->_authSpinner stopAnimating];
            [self->_authActivateBtn setTitle:(isEN ? @"ACTIVATE" : @"KÍCH HOẠT") forState:UIControlStateNormal];

            if (authguard::session_looks_active() && authguard::menu_access_ok(auth::api_instance)) {
                UINotificationFeedbackGenerator *fb = [[UINotificationFeedbackGenerator alloc] init];
                [fb notificationOccurred:UINotificationFeedbackTypeSuccess];

                self->_authStatusLabel.textColor = [UIColor colorWithRed:46/255.0 green:204/255.0 blue:113/255.0 alpha:1.0];
                self->_authStatusLabel.text = isEN ? @"Activated successfully! Starting..." : @"Kích hoạt thành công! Đang khởi động...";

                NSString *expStr = GetFormattedExpiryString(auth::api_instance.expiry);
                [self appendConsoleLog:@"OK" message:[NSString stringWithFormat:(isEN ? @"License activated! Valid until: %@" : @"Kích hoạt thành công! Hạn dùng: %@"), expStr] tagColor:[UIColor colorWithRed:46/255.0 green:204/255.0 blue:113/255.0 alpha:1.0]];

                [self updateLicenseCardUI];

                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    [self dismissAuthGateOverlayWithAnimation:YES];
                });
            } else {
                auth::v_chk_0x33 = false;
                auth::session_active = false;
                auth::vnp_token = 0;
                auth::api_instance.clear_license_state();
                auth::save_key("");
                self->_authCloseBtn.hidden = YES;
                [self updateLicenseCardUI];

                UINotificationFeedbackGenerator *fb = [[UINotificationFeedbackGenerator alloc] init];
                [fb notificationOccurred:UINotificationFeedbackTypeError];

                self->_authStatusLabel.textColor = [UIColor colorWithRed:231/255.0 green:76/255.0 blue:60/255.0 alpha:1.0];
                NSString *msg = [NSString stringWithUTF8String:auth::auth_text.c_str()];
                if (msg.length == 0) {
                    msg = isEN ? @"Invalid license key or server error." : @"Mã key không hợp lệ hoặc lỗi kết nối máy chủ.";
                }
                self->_authStatusLabel.text = msg;
                [self appendConsoleLog:@"ERR" message:[NSString stringWithFormat:(isEN ? @"Activation failed: %@" : @"Kích hoạt thất bại: %@"), msg] tagColor:[UIColor colorWithRed:255/255.0 green:59/255.0 blue:48/255.0 alpha:1.0]];
                [self shakeView:self->_authCardView];
            }
        });
    });
}

- (void)pasteKeyTapped:(UIButton *)sender
{
    if (_impactFeedbackGenerator) [_impactFeedbackGenerator impactOccurred];
    NSString *pasted = [UIPasteboard generalPasteboard].string;
    if (pasted && pasted.length > 0) {
        _authKeyTextField.text = [pasted stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    }
}

- (void)changeKeyTapped:(UIButton *)sender
{
    if (_impactFeedbackGenerator) [_impactFeedbackGenerator impactOccurred];
    auth::v_chk_0x33 = false;
    auth::session_active = false;
    auth::vnp_token = 0;
    auth::api_instance.clear_license_state();

    _authKeyTextField.text = @"";
    _authStatusLabel.text = @"";
    [self updateLicenseCardUI];
    [self showAuthGateOverlayWithAnimation:YES];
    _authCloseBtn.hidden = YES;
}

- (void)updateLicenseCardUI
{
    BOOL isEN = IsEnglish();
    BOOL isActive = authguard::session_looks_active() && authguard::menu_access_ok(auth::api_instance);

    if (isActive) {
        _licenseStatusBadge.backgroundColor = [UIColor colorWithRed:20/255.0 green:45/255.0 blue:35/255.0 alpha:1.0];
        _licenseBadgeLabel.textColor = [UIColor colorWithRed:46/255.0 green:204/255.0 blue:113/255.0 alpha:1.0];
        _licenseBadgeLabel.text = isEN ? @"Active" : @"Đã kích hoạt";

        std::string loaded = auth::load_key();
        if (loaded.empty()) loaded = auth::username;
        NSString *raw = [NSString stringWithUTF8String:loaded.c_str()];
        _licenseKeyVal.text = GetMaskedKeyString(raw);

        _licenseExpVal.text = GetFormattedExpiryString(auth::api_instance.expiry);
        _licenseExpVal.textColor = [UIColor colorWithRed:0/255.0 green:210/255.0 blue:180/255.0 alpha:1.0];

        _licenseRemainVal.text = GetFormattedRemainingString(auth::api_instance.expiry);
        _licenseRemainVal.textColor = [UIColor colorWithRed:46/255.0 green:204/255.0 blue:113/255.0 alpha:1.0];
    } else {
        _licenseStatusBadge.backgroundColor = [UIColor colorWithRed:58/255.0 green:28/255.0 blue:28/255.0 alpha:1.0];
        _licenseBadgeLabel.textColor = [UIColor colorWithRed:231/255.0 green:76/255.0 blue:60/255.0 alpha:1.0];
        _licenseBadgeLabel.text = isEN ? @"Inactive" : @"Chưa kích hoạt";

        _licenseKeyVal.text = isEN ? @"No Key" : @"Chưa có key";
        _licenseExpVal.text = isEN ? @"Locked" : @"Đang khoá";
        _licenseExpVal.textColor = [UIColor colorWithRed:231/255.0 green:76/255.0 blue:60/255.0 alpha:1.0];

        _licenseRemainVal.text = isEN ? @"Please enter key" : @"Vui lòng nhập key";
        _licenseRemainVal.textColor = [UIColor colorWithRed:139/255.0 green:148/255.0 blue:158/255.0 alpha:1.0];
    }
}

- (void)checkStoredLicenseOnBoot
{
    std::string savedKey = auth::load_key();
    if (savedKey.empty()) {
        BOOL isEN = IsEnglish();
        [self appendConsoleLog:@"AUTH" message:(isEN ? @"Welcome to DarkPubg. License key required to unlock." : @"Chào mừng đến với DarkPubg. Cần nhập key để vào ứng dụng.") tagColor:[UIColor colorWithRed:241/255.0 green:196/255.0 blue:15/255.0 alpha:1.0]];
        [self showAuthGateOverlayWithAnimation:NO];
    } else {
        BOOL isEN = IsEnglish();
        [self appendConsoleLog:@"AUTH" message:[NSString stringWithFormat:(isEN ? @"Found saved key (%.8s...). Verifying..." : @"Tìm thấy key đã lưu (%.8s...). Đang xác thực..."), savedKey.c_str()] tagColor:[UIColor colorWithRed:88/255.0 green:166/255.0 blue:255/255.0 alpha:1.0]];
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            auth::username = savedKey;
            auth::login();

            dispatch_async(dispatch_get_main_queue(), ^{
                if (authguard::session_looks_active() && authguard::menu_access_ok(auth::api_instance)) {
                    NSString *expStr = GetFormattedExpiryString(auth::api_instance.expiry);
                    [self appendConsoleLog:@"OK" message:[NSString stringWithFormat:(isEN ? @"License active! Valid until: %@" : @"Bản quyền hợp lệ! Hạn dùng: %@"), expStr] tagColor:[UIColor colorWithRed:46/255.0 green:204/255.0 blue:113/255.0 alpha:1.0]];
                    [self updateLicenseCardUI];
                } else {
                    auth::v_chk_0x33 = false;
                    auth::session_active = false;
                    auth::vnp_token = 0;
                    auth::api_instance.clear_license_state();
                    auth::save_key("");
                    [self updateLicenseCardUI];
                    [self appendConsoleLog:@"AUTH" message:(isEN ? @"Stored key failed validation. Please enter key." : @"Key đã lưu không hợp lệ. Vui lòng nhập lại key.") tagColor:[UIColor colorWithRed:255/255.0 green:59/255.0 blue:48/255.0 alpha:1.0]];
                    [self showAuthGateOverlayWithAnimation:YES];
                }
            });
        });
    }
}

- (void)authKeyboardWillShow:(NSNotification *)note
{
    NSDictionary *userInfo = note.userInfo;
    NSTimeInterval duration = [userInfo[UIKeyboardAnimationDurationUserInfoKey] doubleValue];
    UIViewAnimationCurve curve = (UIViewAnimationCurve)[userInfo[UIKeyboardAnimationCurveUserInfoKey] integerValue];

    [UIView animateWithDuration:duration delay:0 options:(UIViewAnimationOptions)(curve << 16) animations:^{
        self->_authCardView.transform = CGAffineTransformMakeTranslation(0, -65.0f);
    } completion:nil];
}

- (void)authKeyboardWillHide:(NSNotification *)note
{
    NSDictionary *userInfo = note.userInfo;
    NSTimeInterval duration = [userInfo[UIKeyboardAnimationDurationUserInfoKey] doubleValue];
    UIViewAnimationCurve curve = (UIViewAnimationCurve)[userInfo[UIKeyboardAnimationCurveUserInfoKey] integerValue];

    [UIView animateWithDuration:duration delay:0 options:(UIViewAnimationOptions)(curve << 16) animations:^{
        self->_authCardView.transform = CGAffineTransformIdentity;
    } completion:nil];
}

- (void)dismissKeyboardTapped
{
    [self.view endEditing:YES];
}

- (void)authTextFieldReturned:(UITextField *)sender
{
    [self activateKeyTapped:_authActivateBtn];
}

- (void)shakeView:(UIView *)view
{
    CAKeyframeAnimation *animation = [CAKeyframeAnimation animationWithKeyPath:@"transform.translation.x"];
    animation.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear];
    animation.duration = 0.4;
    animation.values = @[@(-12.0), @(12.0), @(-8.0), @(8.0), @(-4.0), @(4.0), @(0.0)];
    [view.layer addAnimation:animation forKey:@"shake"];
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
    [self seedBootLogs];
    [self startPulseAnimation:_consoleLiveDot];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(authKeyboardWillShow:) name:UIKeyboardWillShowNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(authKeyboardWillHide:) name:UIKeyboardWillHideNotification object:nil];

    [self checkStoredLicenseOnBoot];

    __weak typeof(self) weakSelf = self;
    _consoleHeartbeatTimer = [NSTimer scheduledTimerWithTimeInterval:30.0 repeats:YES block:^(NSTimer * _Nonnull timer) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf && !strongSelf->_homeView.hidden) {
            BOOL isEN = IsEnglish();
            [strongSelf appendConsoleLog:@"SYS" message:(isEN ? @"Kernel heartbeat: memory stable, zero leak" : @"Nhịp hoạt động: bộ nhớ ổn định, không rò rỉ") tagColor:[UIColor colorWithRed:88/255.0 green:166/255.0 blue:255/255.0 alpha:1.0]];
        }
    }];
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_consoleHeartbeatTimer invalidate];
    _consoleHeartbeatTimer = nil;
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

- (void)doEnableHUD
{
    BOOL isNowEnabled = [self isHUDEnabled];
    if (isNowEnabled) return;

    BOOL isEN = IsEnglish();
    [self appendConsoleLog:@"KERN" message:(isEN ? @"Attaching DarkSword kernel hooks..." : @"Đang nạp bộ nhớ qua DarkSword Kernel...") tagColor:[UIColor colorWithRed:241/255.0 green:196/255.0 blue:15/255.0 alpha:1.0]];

    [self setHUDEnabled:YES];

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

        BOOL isEN = IsEnglish();
        [strongSelf appendConsoleLog:@"OK" message:(isEN ? @"ESP Overlay successfully launched in-game!" : @"Menu ESP đã kích hoạt thành công trong game!") tagColor:[UIColor colorWithRed:46/255.0 green:204/255.0 blue:113/255.0 alpha:1.0]];
    });

    [self.backgroundView setUserInteractionEnabled:NO];
}

- (void)doDisableHUD
{
    BOOL isNowEnabled = [self isHUDEnabled];
    if (!isNowEnabled) return;

    BOOL isEN = IsEnglish();
    [self appendConsoleLog:@"INFO" message:(isEN ? @"User requested HUD stop" : @"Yêu cầu tắt HUD từ người dùng") tagColor:[UIColor colorWithRed:0/255.0 green:210/255.0 blue:180/255.0 alpha:1.0]];
    [self appendConsoleLog:@"KERN" message:(isEN ? @"Detaching DarkSword kernel hooks..." : @"Đang ngắt liên kết DarkSword Kernel...") tagColor:[UIColor colorWithRed:241/255.0 green:196/255.0 blue:15/255.0 alpha:1.0]];

    [self setHUDEnabled:NO];

#if USE_DARKSWORD
    [self hideDSProgressOverlay];
#endif
    [self.backgroundView setUserInteractionEnabled:NO];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        dispatch_async(dispatch_get_main_queue(), ^{
            [self reloadMainButtonState];
            [self.backgroundView setUserInteractionEnabled:YES];
            [self appendConsoleLog:@"SYS" message:(isEN ? @"HUD stopped. Standby mode active." : @"Đã tắt HUD. Chế độ chờ sẵn sàng.") tagColor:[UIColor colorWithRed:88/255.0 green:166/255.0 blue:255/255.0 alpha:1.0]];
        });
    });
}

- (void)tapMainButton:(UIButton *)sender
{
    BOOL isNowEnabled = [self isHUDEnabled];

    // If HUD is currently ON, turn it OFF:
    if (isNowEnabled) {
        [self doDisableHUD];
        return;
    }

    // If HUD is currently OFF:
    // 1. License authentication gate
    if (!authguard::session_looks_active() || !authguard::menu_access_ok(auth::api_instance)) {
        BOOL isEN = IsEnglish();
        [self appendConsoleLog:@"AUTH" message:(isEN ? @"Access denied: License key required to open HUD." : @"Từ chối: Cần kích hoạt bản quyền để mở HUD.") tagColor:[UIColor colorWithRed:255/255.0 green:59/255.0 blue:48/255.0 alpha:1.0]];
        [self showAuthGateOverlayWithAnimation:YES];
        return;
    }

    // 2. Check if PUBG Mobile is running
    if (!IsPUBGProcessRunning()) {
        BOOL isEN = IsEnglish();
        [self appendConsoleLog:@"WARN" message:(isEN ? @"Target process NOT running: ShadowTrackerExtra" : @"Tiến trình PUBG Mobile chưa khởi chạy!") tagColor:[UIColor colorWithRed:255/255.0 green:59/255.0 blue:48/255.0 alpha:1.0]];
        [self showGameNotRunningAlert];
        return;
    }

    BOOL isEN = IsEnglish();
    [self appendConsoleLog:@"OK" message:(isEN ? @"Target process found: ShadowTrackerExtra" : @"Đã kết nối tiến trình: ShadowTrackerExtra") tagColor:[UIColor colorWithRed:46/255.0 green:204/255.0 blue:113/255.0 alpha:1.0]];

    [self doEnableHUD];
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
