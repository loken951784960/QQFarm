#import "QQFarmFloatingBall.h"
#import "QQFarmOverlay.h"
#import "../utils/QQFarmUtils.h"

static const CGFloat kBallSize = 48.0;
static NSString *const kBallPosKey = @"QQFarmFloatingBallCenter";

@interface QQFarmFloatingBall ()
@property (nonatomic, strong) UIButton *ball;
@property (nonatomic, assign) CGPoint startCenter;
@end

@implementation QQFarmFloatingBall

+ (instancetype)sharedInstance {
    static QQFarmFloatingBall *inst = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        inst = [[self alloc] init];
    });
    return inst;
}

- (instancetype)init {
    CGRect initial = CGRectMake([UIScreen mainScreen].bounds.size.width - kBallSize - 12,
                                 [UIScreen mainScreen].bounds.size.height / 2 - kBallSize / 2,
                                 kBallSize, kBallSize);
    self = [super initWithFrame:initial];
    if (self) {
        self.windowLevel = UIWindowLevelAlert + 200;
        self.backgroundColor = [UIColor clearColor];
        self.hidden = NO;
        self.rootViewController = [[UIViewController alloc] init];
        self.rootViewController.view.backgroundColor = [UIColor clearColor];

        if (@available(iOS 13.0, *)) {
            for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
                if ([scene isKindOfClass:[UIWindowScene class]]) {
                    self.windowScene = (UIWindowScene *)scene;
                    break;
                }
            }
        }

        _ball = [UIButton buttonWithType:UIButtonTypeCustom];
        _ball.frame = self.bounds;
        _ball.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        _ball.layer.cornerRadius = kBallSize / 2;
        _ball.backgroundColor = [UIColor colorWithRed:0.0 green:0.48 blue:1.0 alpha:0.85];
        [_ball setTitle:@"农" forState:UIControlStateNormal];
        [_ball setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        _ball.titleLabel.font = [UIFont boldSystemFontOfSize:18];
        _ball.layer.shadowColor = [UIColor blackColor].CGColor;
        _ball.layer.shadowOpacity = 0.3;
        _ball.layer.shadowOffset = CGSizeMake(0, 2);
        _ball.layer.shadowRadius = 4;
        [self addSubview:_ball];

        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(onPan:)];
        [_ball addGestureRecognizer:pan];

        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(onTap:)];
        [tap requireGestureRecognizerToFail:pan];
        [_ball addGestureRecognizer:tap];

        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(onOverlayDidHide:)
                                                     name:kQQFarmOverlayDidHideNotification
                                                   object:nil];

        [self restorePosition];
    }
    return self;
}

- (void)ensureScene {
    if (@available(iOS 13.0, *)) {
        if (!self.windowScene) {
            for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
                if ([scene isKindOfClass:[UIWindowScene class]]) {
                    self.windowScene = (UIWindowScene *)scene;
                    break;
                }
            }
        }
    }
}

- (void)onTap:(UITapGestureRecognizer *)g {
    [self ensureScene];
    QQFarmOverlay *overlay = [QQFarmOverlay sharedInstance];
    if (@available(iOS 13.0, *)) {
        if (!overlay.windowScene) {
            for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
                if ([scene isKindOfClass:[UIWindowScene class]]) {
                    overlay.windowScene = (UIWindowScene *)scene;
                    break;
                }
            }
        }
    }
    if (overlay.hidden) {
        self.hidden = YES; // 展开面板时先藏起小球，避免遮挡
        [overlay showWithCode:[QQFarmUtils getLastCapturedCode]];
    } else {
        [overlay hide];
    }
}

- (void)onPan:(UIPanGestureRecognizer *)g {
    if (g.state == UIGestureRecognizerStateBegan) {
        _startCenter = self.center;
    } else if (g.state == UIGestureRecognizerStateChanged) {
        CGPoint t = [g translationInView:_ball];
        CGFloat x = _startCenter.x + t.x;
        CGFloat y = _startCenter.y + t.y;
        CGRect b = [UIScreen mainScreen].bounds;
        x = MAX(kBallSize / 2, MIN(x, b.size.width - kBallSize / 2));
        y = MAX(kBallSize / 2, MIN(y, b.size.height - kBallSize / 2));
        self.center = CGPointMake(x, y);
    } else if (g.state == UIGestureRecognizerStateEnded ||
               g.state == UIGestureRecognizerStateCancelled) {
        [self savePosition];
    }
}

- (void)onOverlayDidHide:(NSNotification *)note {
    [self ensureScene];
    self.hidden = NO;
}

- (void)restorePosition {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    NSString *str = [ud stringForKey:kBallPosKey];
    if (str.length) {
        NSArray *parts = [str componentsSeparatedByString:@","];
        if (parts.count == 2) {
            CGFloat x = [parts[0] floatValue];
            CGFloat y = [parts[1] floatValue];
            CGRect b = [UIScreen mainScreen].bounds;
            x = MAX(kBallSize / 2, MIN(x, b.size.width - kBallSize / 2));
            y = MAX(kBallSize / 2, MIN(y, b.size.height - kBallSize / 2));
            self.center = CGPointMake(x, y);
        }
    }
}

- (void)savePosition {
    NSString *str = [NSString stringWithFormat:@"%.1f,%.1f", self.center.x, self.center.y];
    [[NSUserDefaults standardUserDefaults] setObject:str forKey:kBallPosKey];
}

@end
