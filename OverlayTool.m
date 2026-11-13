// OverlayTool.m
// Dylib overlay: viền 7 màu, menu bật/tắt, FPS, ngày giờ, sáng/tối.
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>

#pragma mark - Rainbow border view

@interface OTRainbowView : UIView
@property (nonatomic, strong) CAGradientLayer *grad;
@property (nonatomic, strong) CAShapeLayer *ring;
@end

@implementation OTRainbowView

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.userInteractionEnabled = NO;
        self.backgroundColor = UIColor.clearColor;

        self.grad = [CAGradientLayer layer];
        self.grad.colors = @[
            (__bridge id)[UIColor colorWithRed:1.0 green:0.0 blue:0.0 alpha:1].CGColor,
            (__bridge id)[UIColor colorWithRed:1.0 green:0.5 blue:0.0 alpha:1].CGColor,
            (__bridge id)[UIColor colorWithRed:1.0 green:1.0 blue:0.0 alpha:1].CGColor,
            (__bridge id)[UIColor colorWithRed:0.0 green:1.0 blue:0.0 alpha:1].CGColor,
            (__bridge id)[UIColor colorWithRed:0.0 green:1.0 blue:1.0 alpha:1].CGColor,
            (__bridge id)[UIColor colorWithRed:0.0 green:0.0 blue:1.0 alpha:1].CGColor,
            (__bridge id)[UIColor colorWithRed:0.5 green:0.0 blue:1.0 alpha:1].CGColor,
            (__bridge id)[UIColor colorWithRed:1.0 green:0.0 blue:0.0 alpha:1].CGColor
        ];
        [self.layer addSublayer:self.grad];

        self.ring = [CAShapeLayer layer];
        self.ring.fillRule = kCAFillRuleEvenOdd;
        self.layer.mask = self.ring;
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];

    CGRect b = self.bounds;
    CGFloat d = hypot(b.size.width, b.size.height);

    self.grad.bounds = CGRectMake(0, 0, d, d);
    self.grad.position = CGPointMake(CGRectGetMidX(b), CGRectGetMidY(b));

    CGFloat w = 4.0;
    UIBezierPath *path = [UIBezierPath bezierPathWithRect:b];
    [path appendPath:[UIBezierPath bezierPathWithRect:CGRectInset(b, w, w)]];
    self.ring.frame = b;
    self.ring.path = path.CGPath;

    if (![self.grad animationForKey:@"ot_spin"]) {
        CABasicAnimation *spin = [CABasicAnimation animationWithKeyPath:@"transform.rotation.z"];
        spin.fromValue = @0;
        spin.toValue = @(2 * M_PI);
        spin.duration = 4.0;
        spin.repeatCount = HUGE_VALF;
        [self.grad addAnimation:spin forKey:@"ot_spin"];
    }
}

@end

#pragma mark - Manager

@interface OTManager : NSObject
@property (nonatomic, strong) UIWindow *window;
@property (nonatomic, strong) OTRainbowView *rainbowView;
@property (nonatomic, strong) UILabel *fpsLabel;
@property (nonatomic, strong) UILabel *clockLabel;
@property (nonatomic, strong) UIView *menuPanel;
@property (nonatomic, strong) UIButton *floatButton;
@property (nonatomic, strong) CADisplayLink *link;
@property (nonatomic, strong) NSTimer *clockTimer;
@property (nonatomic, strong) NSDateFormatter *formatter;
@property (nonatomic, assign) NSInteger frameCount;
@property (nonatomic, assign) CFTimeInterval lastTime;
@end

@implementation OTManager

+ (instancetype)shared {
    static OTManager *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [OTManager new]; });
    return s;
}

+ (NSArray<NSString *> *)keys {
    return @[@"ot_rainbow", @"ot_fps", @"ot_clock", @"ot_dark"];
}

+ (NSArray<NSString *> *)titles {
    return @[@"Viền 7 màu", @"Hiển thị FPS", @"Ngày & giờ", @"Chế độ tối"];
}

- (BOOL)on:(NSString *)key {
    return [[NSUserDefaults standardUserDefaults] boolForKey:key];
}

#pragma mark Attach

- (UIWindow *)findKeyWindow {
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]]) continue;
        for (UIWindow *w in ((UIWindowScene *)scene).windows) {
            if (w.isKeyWindow) return w;
        }
    }
    return nil;
}

- (void)attachIfNeeded {
    if (self.window) return;
    UIWindow *w = [self findKeyWindow];
    if (!w) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{ [self attachIfNeeded]; });
        return;
    }
    self.window = w;
    [self buildAll];
}

- (void)buildAll {
    CGRect wb = self.window.bounds;
    CGFloat top = self.window.safeAreaInsets.top + 6;

    self.rainbowView = [[OTRainbowView alloc] initWithFrame:wb];
    self.rainbowView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.window addSubview:self.rainbowView];

    self.fpsLabel = [self makeLabelWithFrame:CGRectMake(10, top, 90, 20)];
    self.fpsLabel.text = @"FPS --";
    self.fpsLabel.autoresizingMask = UIViewAutoresizingFlexibleRightMargin;
    [self.window addSubview:self.fpsLabel];

    self.link = [CADisplayLink displayLinkWithTarget:self selector:@selector(tick:)];
    [self.link addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];

    self.formatter = [NSDateFormatter new];
    self.formatter.dateFormat = @"HH:mm:ss  dd/MM/yyyy";
    self.clockLabel = [self makeLabelWithFrame:CGRectMake(CGRectGetWidth(wb) - 175, top, 165, 20)];
    self.clockLabel.textAlignment = NSTextAlignmentRight;
    self.clockLabel.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    [self.window addSubview:self.clockLabel];
    [self updateClock];
    self.clockTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 target:self
                                                     selector:@selector(updateClock)
                                                     userInfo:nil repeats:YES];

    [self buildMenu];
    [self buildFloatButton];
    [self applyAll];
}

- (UILabel *)makeLabelWithFrame:(CGRect)f {
    UILabel *l = [[UILabel alloc] initWithFrame:f];
    l.font = [UIFont monospacedDigitSystemFontOfSize:12 weight:UIFontWeightSemibold];
    l.textColor = UIColor.whiteColor;
    l.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.45];
    l.layer.cornerRadius = 6;
    l.layer.masksToBounds = YES;
    l.userInteractionEnabled = NO;
    return l;
}

- (void)buildMenu {
    CGFloat W = 230, H = 44 + 4 * 46 + 10;
    CGRect wb = self.window.bounds;
    self.menuPanel = [[UIView alloc] initWithFrame:CGRectMake(CGRectGetWidth(wb) - W - 12, 170, W, H)];
    self.menuPanel.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.85];
    self.menuPanel.layer.cornerRadius = 14;
    self.menuPanel.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    self.menuPanel.hidden = YES;

    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(14, 10, W - 28, 24)];
    title.text = @"Tiện ích";
    title.textColor = UIColor.whiteColor;
    title.font = [UIFont boldSystemFontOfSize:16];
    [self.menuPanel addSubview:title];

    NSArray *keys = [OTManager keys];
    NSArray *titles = [OTManager titles];
    for (NSInteger i = 0; i < keys.count; i++) {
        CGFloat y = 44 + i * 46;

        UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(14, y, 150, 31)];
        l.text = titles[i];
        l.textColor = UIColor.whiteColor;
        l.font = [UIFont systemFontOfSize:15];
        [self.menuPanel addSubview:l];

        UISwitch *sw = [[UISwitch alloc] init];
        sw.frame = CGRectMake(W - 51 - 12, y, 51, 31);
        sw.on = [self on:keys[i]];
        sw.tag = i;
        [sw addTarget:self action:@selector(switchChanged:) forControlEvents:UIControlEventValueChanged];
        [self.menuPanel addSubview:sw];
    }
    [self.window addSubview:self.menuPanel];
}

- (void)buildFloatButton {
    CGRect wb = self.window.bounds;
    self.floatButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.floatButton.frame = CGRectMake(CGRectGetWidth(wb) - 56, 120, 44, 44);
    self.floatButton.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.6];
    self.floatButton.layer.cornerRadius = 22;
    self.floatButton.layer.borderWidth = 1;
    self.floatButton.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.3].CGColor;
    self.floatButton.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    [self.floatButton setTitle:@"⚙️" forState:UIControlStateNormal];
    [self.floatButton addTarget:self action:@selector(toggleMenu) forControlEvents:UIControlEventTouchUpInside];

    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(dragButton:)];
    [self.floatButton addGestureRecognizer:pan];

    [self.window addSubview:self.floatButton];
}

#pragma mark Actions

- (void)toggleMenu {
    self.menuPanel.hidden = !self.menuPanel.hidden;
    [self.window bringSubviewToFront:self.floatButton];
}

- (void)dragButton:(UIPanGestureRecognizer *)pan {
    CGPoint t = [pan translationInView:self.window];
    self.floatButton.center = CGPointMake(self.floatButton.center.x + t.x,
                                          self.floatButton.center.y + t.y);
    [pan setTranslation:CGPointZero inView:self.window];
}

- (void)switchChanged:(UISwitch *)sw {
    NSString *key = [OTManager keys][sw.tag];
    [[NSUserDefaults standardUserDefaults] setBool:sw.on forKey:key];
    [self applyAll];
}

- (void)applyAll {
    self.rainbowView.hidden = ![self on:@"ot_rainbow"];
    self.fpsLabel.hidden = ![self on:@"ot_fps"];
    self.link.paused = self.fpsLabel.hidden;
    self.clockLabel.hidden = ![self on:@"ot_clock"];
    self.window.overrideUserInterfaceStyle = [self on:@"ot_dark"]
        ? UIUserInterfaceStyleDark
        : UIUserInterfaceStyleLight;
}

- (void)tick:(CADisplayLink *)link {
    if (self.lastTime == 0) self.lastTime = link.timestamp;
    self.frameCount++;
    CFTimeInterval dt = link.timestamp - self.lastTime;
    if (dt >= 1.0) {
        self.fpsLabel.text = [NSString stringWithFormat:@"FPS %.0f", self.frameCount / dt];
        self.frameCount = 0;
        self.lastTime = link.timestamp;
    }
}

- (void)updateClock {
    self.clockLabel.text = [NSString stringWithFormat:@" %@ ",
                            [self.formatter stringFromDate:[NSDate date]]];
}

@end

#pragma mark - Entry point

__attribute__((constructor))
static void OTInit(void) {
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification
                                                      object:nil
                                                       queue:NSOperationQueue.mainQueue
                                                  usingBlock:^(NSNotification *note) {
        [[OTManager shared] attachIfNeeded];
    }];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [[OTManager shared] attachIfNeeded];
    });
}
