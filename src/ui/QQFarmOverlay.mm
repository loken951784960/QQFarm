#import "QQFarmOverlay.h"
#import "../utils/QQFarmUtils.h"
#import <objc/runtime.h>

static char kAccountKey;

@interface QQFarmOverlay () <UITextFieldDelegate>
@property (nonatomic, strong) UIView *containerView;
@property (nonatomic, strong) UIButton *tabAccountBtn;
@property (nonatomic, strong) UIButton *tabSettingsBtn;
@property (nonatomic, strong) UIView *accountView;
@property (nonatomic, strong) UIView *settingsView;
@property (nonatomic, strong) UILabel *serverLabel;
@property (nonatomic, strong) UITextField *serverInput;
@property (nonatomic, strong) UILabel *tokenLabel;
@property (nonatomic, strong) UITextField *tokenInput;
@property (nonatomic, strong) UITextField *codeInput;
@property (nonatomic, strong) UIButton *saveConfigButton;
@property (nonatomic, strong) UIButton *closeButton;
@property (nonatomic, strong) UIButton *addAccountButton; // 添加账号按钮
@property (nonatomic, strong) UIScrollView *accountsScrollView; // 账号列表
@property (nonatomic, strong) UIRefreshControl *refreshControl; // 下拉刷新控件
@property (nonatomic, weak) UIView *currentAlertCover; // 当前显示的 Alert 遮罩
@end

@implementation QQFarmOverlay

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

+ (instancetype)sharedInstance {
    static QQFarmOverlay *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[self alloc] initWithFrame:[UIScreen mainScreen].bounds];
    });
    return sharedInstance;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.windowLevel = UIWindowLevelAlert + 100;
        self.backgroundColor = [UIColor clearColor]; // 透明背景，非模态
        self.hidden = YES;
        
        // 设置根视图控制器以支持 Alert 弹出和旋转
        self.rootViewController = [[UIViewController alloc] init];
        self.rootViewController.view.backgroundColor = [UIColor clearColor];
        
        // 容器视图
        _containerView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 300, 400)];
        _containerView.center = self.center;
        _containerView.backgroundColor = [UIColor whiteColor];
        _containerView.layer.cornerRadius = 12;
        _containerView.layer.masksToBounds = NO; // 允许阴影
        
        // 添加阴影以增强悬浮感
        _containerView.layer.shadowColor = [UIColor blackColor].CGColor;
        _containerView.layer.shadowOpacity = 0.3;
        _containerView.layer.shadowOffset = CGSizeMake(0, 2);
        _containerView.layer.shadowRadius = 4;
        
        [self.rootViewController.view addSubview:_containerView];
        
        // --- 顶部 Tabs ---
        _tabAccountBtn = [UIButton buttonWithType:UIButtonTypeSystem];
        _tabAccountBtn.frame = CGRectMake(10, 10, 120, 35);
        [_tabAccountBtn setTitle:@"账号" forState:UIControlStateNormal];
        _tabAccountBtn.backgroundColor = [UIColor systemBlueColor]; // 默认选中
        [_tabAccountBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        _tabAccountBtn.layer.cornerRadius = 8;
        _tabAccountBtn.tag = 0;
        [_tabAccountBtn addTarget:self action:@selector(onTabChanged:) forControlEvents:UIControlEventTouchUpInside];
        [_containerView addSubview:_tabAccountBtn];

        _tabSettingsBtn = [UIButton buttonWithType:UIButtonTypeSystem];
        _tabSettingsBtn.frame = CGRectMake(140, 10, 120, 35);
        [_tabSettingsBtn setTitle:@"设置" forState:UIControlStateNormal];
        _tabSettingsBtn.backgroundColor = [UIColor lightGrayColor]; // 默认未选中
        [_tabSettingsBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        _tabSettingsBtn.layer.cornerRadius = 8;
        _tabSettingsBtn.tag = 1;
        [_tabSettingsBtn addTarget:self action:@selector(onTabChanged:) forControlEvents:UIControlEventTouchUpInside];
        [_containerView addSubview:_tabSettingsBtn];

        // --- 账号视图 (Account View) ---
        _accountView = [[UIView alloc] initWithFrame:CGRectMake(0, 50, 300, 300)];
        [_containerView addSubview:_accountView];

        // 账号列表 ScrollView
        _accountsScrollView = [[UIScrollView alloc] initWithFrame:CGRectMake(10, 10, 280, 240)];
        _accountsScrollView.showsVerticalScrollIndicator = YES;
        _accountsScrollView.backgroundColor = [UIColor colorWithWhite:0.95 alpha:1.0];
        _accountsScrollView.layer.cornerRadius = 8;
        _accountsScrollView.alwaysBounceVertical = YES; // 允许始终可以垂直拖动以触发刷新
        [_accountView addSubview:_accountsScrollView];
        
        // 下拉刷新控件
        _refreshControl = [[UIRefreshControl alloc] init];
        [_refreshControl addTarget:self action:@selector(fetchAccounts) forControlEvents:UIControlEventValueChanged];
        [_accountsScrollView addSubview:_refreshControl];

        // 添加账号按钮
        _addAccountButton = [UIButton buttonWithType:UIButtonTypeSystem];
        _addAccountButton.frame = CGRectMake(10, 260, 280, 35);
        [_addAccountButton setTitle:@"添加账号" forState:UIControlStateNormal];
        _addAccountButton.backgroundColor = [UIColor systemGreenColor];
        [_addAccountButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        _addAccountButton.layer.cornerRadius = 8;
        [_addAccountButton addTarget:self action:@selector(onAddAccountTapped) forControlEvents:UIControlEventTouchUpInside];
        [_accountView addSubview:_addAccountButton];

        // --- 设置视图 (Settings View) ---
        _settingsView = [[UIView alloc] initWithFrame:CGRectMake(0, 50, 300, 300)];
        _settingsView.hidden = YES; // 默认隐藏
        [_containerView addSubview:_settingsView];

        // 服务器标签
        _serverLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 20, 60, 30)];
        _serverLabel.text = @"服务器:";
        _serverLabel.font = [UIFont systemFontOfSize:14];
        _serverLabel.textColor = [UIColor blackColor];
        [_settingsView addSubview:_serverLabel];

        // 服务器输入框
        _serverInput = [[UITextField alloc] initWithFrame:CGRectMake(80, 20, 200, 30)];
        _serverInput.borderStyle = UITextBorderStyleRoundedRect;
        _serverInput.placeholder = @"请输入服务器地址";
        _serverInput.font = [UIFont systemFontOfSize:14];
        _serverInput.textColor = [UIColor blackColor];
        _serverInput.autocapitalizationType = UITextAutocapitalizationTypeNone;
        _serverInput.autocorrectionType = UITextAutocorrectionTypeNo;
        [_settingsView addSubview:_serverInput];

        // Token 标签
        _tokenLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 70, 60, 30)];
        _tokenLabel.text = @"Token:";
        _tokenLabel.font = [UIFont systemFontOfSize:14];
        _tokenLabel.textColor = [UIColor blackColor];
        [_settingsView addSubview:_tokenLabel];

        // Token 输入框
        _tokenInput = [[UITextField alloc] initWithFrame:CGRectMake(80, 70, 200, 30)];
        _tokenInput.borderStyle = UITextBorderStyleRoundedRect;
        _tokenInput.placeholder = @"请输入 Token";
        _tokenInput.font = [UIFont systemFontOfSize:14];
        _tokenInput.textColor = [UIColor blackColor];
        _tokenInput.autocapitalizationType = UITextAutocapitalizationTypeNone;
        _tokenInput.autocorrectionType = UITextAutocorrectionTypeNo;
        _tokenInput.text = [self loadConfig][@"QQFarmToken"];
        [_settingsView addSubview:_tokenInput];
        
        // Code 标签
        UILabel *codeLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 120, 60, 30)];
        codeLabel.text = @"Code:";
        codeLabel.font = [UIFont systemFontOfSize:14];
        codeLabel.textColor = [UIColor blackColor];
        [_settingsView addSubview:codeLabel];
        
        // Code 输入框 (只读)
        _codeInput = [[UITextField alloc] initWithFrame:CGRectMake(80, 120, 200, 30)];
        _codeInput.borderStyle = UITextBorderStyleRoundedRect;
        _codeInput.placeholder = @"暂无获取到的 Code";
        _codeInput.font = [UIFont systemFontOfSize:14];
        _codeInput.textColor = [UIColor grayColor];
        _codeInput.enabled = NO; // 禁止输入
        _codeInput.text = [QQFarmUtils getLastCapturedCode]; // 填充获取到的 code
        [_settingsView addSubview:_codeInput];
        
        // 监听 Code 捕获通知
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(onCodeCaptured:) name:@"kQQFarmCodeCapturedNotification" object:nil];
        
        // 服务器输入框 (修改回使用配置文件)
        _serverInput.text = [self loadConfig][@"QQFarmServer"];
        
        // 保存配置按钮
        _saveConfigButton = [UIButton buttonWithType:UIButtonTypeSystem];
        _saveConfigButton.frame = CGRectMake(20, 170, 260, 40); // 调整位置
        [_saveConfigButton setTitle:@"保存配置" forState:UIControlStateNormal];
        _saveConfigButton.backgroundColor = [UIColor systemBlueColor];
        [_saveConfigButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        _saveConfigButton.layer.cornerRadius = 8;
        [_saveConfigButton addTarget:self action:@selector(saveSettings) forControlEvents:UIControlEventTouchUpInside];
        [_settingsView addSubview:_saveConfigButton];
        
        // --- 右上角关闭按钮 (✕) ---
        // 移到右上角，避免被弹起的键盘遮挡
        _closeButton = [UIButton buttonWithType:UIButtonTypeSystem];
        _closeButton.frame = CGRectMake(262, 6, 30, 32);
        [_closeButton setTitle:@"✕" forState:UIControlStateNormal];
        [_closeButton setTitleColor:[UIColor systemRedColor] forState:UIControlStateNormal];
        _closeButton.titleLabel.font = [UIFont boldSystemFontOfSize:18];
        [_closeButton addTarget:self action:@selector(hide) forControlEvents:UIControlEventTouchUpInside];
        [_containerView addSubview:_closeButton];

        // 监听键盘，弹起时上移面板避免遮挡
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardWillShow:) name:UIKeyboardWillShowNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardWillHide:) name:UIKeyboardWillHideNotification object:nil];
    }
    return self;
}

- (void)onAddAccountTapped {
    NSLog(@"添加账号");
    
    NSString *code = [QQFarmUtils getLastCapturedCode];
    if (!code || code.length == 0) {
        [self showCustomAlertWithTitle:@"错误" message:@"未获取到 Code，请先抓取 Code"];
        return;
    }
    
    [self showCustomConfirmAlertWithTitle:@"添加账号" message:@"是否将当前 Code 添加为新账号？" confirmHandler:^{
        NSString *server = self.serverInput.text;
        NSString *token = self.tokenInput.text;
        
        if (!server || server.length == 0) {
            [self showCustomAlertWithTitle:@"错误" message:@"请先配置服务器地址"];
            return;
        }
        
        // 构建请求参数
        NSDictionary *params = @{
            @"name": @"",
            @"code": code,
            @"platform": @"qq",
            @"loginType": @"manual"
        };
        
        // 处理 URL
        NSString *baseUrl = server;
        if ([baseUrl hasSuffix:@"/"]) {
            baseUrl = [baseUrl substringToIndex:baseUrl.length - 1];
        }
        NSString *urlString = [NSString stringWithFormat:@"%@/api/accounts", baseUrl];
        NSURL *url = [NSURL URLWithString:urlString];
        
        NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
        request.HTTPMethod = @"POST";
        [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
        if (token && token.length > 0) {
            [request setValue:token forHTTPHeaderField:@"x-admin-token"];
        }
        
        NSError *jsonError;
        NSData *jsonData = [NSJSONSerialization dataWithJSONObject:params options:0 error:&jsonError];
        if (jsonError) {
            [self showCustomAlertWithTitle:@"错误" message:@"构建请求数据失败"];
            return;
        }
        request.HTTPBody = jsonData;
        
        NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (error) {
                    [self showCustomAlertWithTitle:@"添加失败" message:error.localizedDescription];
                } else {
                    NSError *jsonError;
                    NSDictionary *respDict = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
                    if (jsonError) {
                         NSString *respStr = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
                         [self showCustomAlertWithTitle:@"添加失败" message:[NSString stringWithFormat:@"解析错误: %@", respStr]];
                    } else if ([respDict[@"ok"] boolValue]) {
                        [self showCustomAlertWithTitle:@"成功" message:@"账号添加成功"];
                    } else {
                        NSString *errMsg = respDict[@"message"] ?: @"未知错误";
                        [self showCustomAlertWithTitle:@"添加失败" message:errMsg];
                    }
                }
                
                // 无论成功失败，都刷新列表
                [self fetchAccounts];
            });
        }];
        [task resume];
    }];
}

- (void)onTabChanged:(UIButton *)sender {
    if (sender.tag == 0) { // 账号
        _accountView.hidden = NO;
        _settingsView.hidden = YES;
        
        _tabAccountBtn.backgroundColor = [UIColor systemBlueColor];
        _tabSettingsBtn.backgroundColor = [UIColor lightGrayColor];
        
        // [self fetchAccounts]; // 切换到账号页时刷新列表 (已移除，仅在显示和下拉时刷新)
    } else { // 设置
        _accountView.hidden = YES;
        _settingsView.hidden = NO;
        
        _tabAccountBtn.backgroundColor = [UIColor lightGrayColor];
        _tabSettingsBtn.backgroundColor = [UIColor systemBlueColor];
        
        // 切换到设置页时，刷新 Code 显示
        self.codeInput.text = [QQFarmUtils getLastCapturedCode];
    }
}

- (void)onCodeCaptured:(NSNotification *)notification {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString *code = notification.userInfo[@"code"];
        if (code) {
            self.codeInput.text = code;
        }
    });
}

// 重写 hitTest 实现点击透传
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    if (self.hidden || self.alpha < 0.01) {
        return nil;
    }
    
    // 优先处理 Alert
    if (self.currentAlertCover && !self.currentAlertCover.hidden) {
        CGPoint pointInCover = [self.currentAlertCover convertPoint:point fromView:self];
        if ([self.currentAlertCover pointInside:pointInCover withEvent:event]) {
            return [super hitTest:point withEvent:event];
        }
    }
    
    // 将点击坐标转换到 containerView
    CGPoint pointInContainer = [self.containerView convertPoint:point fromView:self];
    
    // 如果点击在 containerView 内部，则响应
    if ([self.containerView pointInside:pointInContainer withEvent:event]) {
        return [super hitTest:point withEvent:event];
    }
    
    // 否则返回 nil，透传给下层 Window
    return nil;
}

- (void)showWithCode:(NSString *)code {
    self.hidden = NO;
    // 复位面板位置（避免上次键盘上移后残留偏移）
    self.containerView.center = self.center;

    // 简单的弹出动画
    self.containerView.transform = CGAffineTransformMakeScale(0.8, 0.8);
    self.alpha = 0;
    [UIView animateWithDuration:0.2 animations:^{
        self.containerView.transform = CGAffineTransformIdentity;
        self.alpha = 1;
    }];
    
    // 显示时刷新列表
    if (!self.accountView.hidden) {
        [self fetchAccounts];
    }
}

- (void)hide {
    [UIView animateWithDuration:0.2 animations:^{
        self.alpha = 0;
    } completion:^(BOOL finished) {
        self.hidden = YES;
        self.alpha = 1; // 重置 alpha 以便下次显示
        [[NSNotificationCenter defaultCenter] postNotificationName:kQQFarmOverlayDidHideNotification object:nil];
    }];
}

#pragma mark - 键盘处理 (避免输入框/按钮被键盘遮挡)

- (void)keyboardWillShow:(NSNotification *)notification {
    NSDictionary *info = notification.userInfo;
    CGRect kbRect = [info[UIKeyboardFrameEndUserInfoKey] CGRectValue];
    CGFloat kbHeight = kbRect.size.height;
    if (kbHeight <= 0) return;

    CGFloat screenH = self.bounds.size.height;
    CGFloat containerH = self.containerView.frame.size.height;
    // 目标：面板底部落在键盘上方 10pt 处
    CGFloat desiredBottom = screenH - kbHeight - 10;
    CGFloat currentBottom = self.containerView.center.y + containerH / 2.0;
    CGFloat delta = currentBottom - desiredBottom;
    if (delta > 0) {
        CGFloat newCenterY = self.containerView.center.y - delta;
        // 限制上移幅度，保证面板顶部不超出屏幕
        CGFloat minCenterY = 10 + containerH / 2.0;
        if (newCenterY < minCenterY) newCenterY = minCenterY;
        [UIView animateWithDuration:0.25 animations:^{
            self.containerView.center = CGPointMake(self.containerView.center.x, newCenterY);
        }];
    }
}

- (void)keyboardWillHide:(NSNotification *)notification {
    [UIView animateWithDuration:0.25 animations:^{
        self.containerView.center = self.center;
    }];
}

- (void)saveSettings {
    NSString *server = self.serverInput.text ?: @"";
    NSString *token = self.tokenInput.text ?: @"";
    
    NSDictionary *config = @{
        @"QQFarmServer": server,
        @"QQFarmToken": token
    };
    
    [config writeToFile:[self configFilePath] atomically:YES];
    
    // 按钮提示已保存
    NSString *originalTitle = [self.saveConfigButton titleForState:UIControlStateNormal];
    [self.saveConfigButton setTitle:@"已保存" forState:UIControlStateNormal];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self.saveConfigButton setTitle:originalTitle forState:UIControlStateNormal];
    });
}

- (NSString *)configFilePath {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentsDirectory = [paths firstObject];
    NSString *qqFarmDir = [documentsDirectory stringByAppendingPathComponent:@"QQFarm"];
    
    // 确保目录存在
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if (![fileManager fileExistsAtPath:qqFarmDir]) {
        [fileManager createDirectoryAtPath:qqFarmDir withIntermediateDirectories:YES attributes:nil error:nil];
    }
    
    return [qqFarmDir stringByAppendingPathComponent:@"config.plist"];
}

- (NSDictionary *)loadConfig {
    NSString *path = [self configFilePath];
    if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
        return [NSDictionary dictionaryWithContentsOfFile:path] ?: @{};
    }
    return @{};
}

- (void)fetchAccounts {
    NSString *server = self.serverInput.text;
    NSString *token = self.tokenInput.text;
    
    if (server.length == 0 || token.length == 0) {
        [self renderAccounts:@[]];
        return;
    }
    
    NSString *urlString = [server stringByAppendingString:@"/api/accounts"];
    NSURL *url = [NSURL URLWithString:urlString];
    if (!url) {
        [self renderAccounts:@[]];
        return;
    }
    
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"GET";
    [request setValue:token forHTTPHeaderField:@"x-admin-token"];
    request.timeoutInterval = 10.0;
    
    [[NSURLSession.sharedSession dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self renderAccounts:@[]];
                [self.refreshControl endRefreshing];
            });
            return;
        }
        
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        if ([json isKindOfClass:[NSDictionary class]] && [json[@"ok"] boolValue]) {
            NSDictionary *dataDict = json[@"data"];
            if ([dataDict isKindOfClass:[NSDictionary class]]) {
                NSArray *accounts = dataDict[@"accounts"];
                if ([accounts isKindOfClass:[NSArray class]]) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [self renderAccounts:accounts];
                        [self.refreshControl endRefreshing];
                    });
                    return;
                }
            }
        }
        
        dispatch_async(dispatch_get_main_queue(), ^{
            [self renderAccounts:@[]];
            [self.refreshControl endRefreshing];
        });
    }] resume];
}

- (void)renderAccounts:(NSArray *)accounts {
    // 清除原有内容，但保留 refreshControl
    for (UIView *v in self.accountsScrollView.subviews) {
        if (v != self.refreshControl) {
            [v removeFromSuperview];
        }
    }
    
    if (accounts.count == 0) {
        UILabel *emptyLabel = [[UILabel alloc] initWithFrame:self.accountsScrollView.bounds];
        emptyLabel.text = @"暂无账号数据";
        emptyLabel.textAlignment = NSTextAlignmentCenter;
        emptyLabel.textColor = [UIColor grayColor];
        emptyLabel.font = [UIFont systemFontOfSize:14];
        [self.accountsScrollView addSubview:emptyLabel];
        self.accountsScrollView.contentSize = self.accountsScrollView.bounds.size;
        return;
    }
    
    CGFloat y = 10;
    CGFloat width = self.accountsScrollView.frame.size.width - 20;
    
    for (NSDictionary *acc in accounts) {
        // 卡片容器 (负责阴影)
        UIView *card = [[UIView alloc] initWithFrame:CGRectMake(10, y, width, 90)];
        card.backgroundColor = [UIColor clearColor];
        card.layer.shadowColor = [UIColor blackColor].CGColor;
        card.layer.shadowOpacity = 0.1;
        card.layer.shadowOffset = CGSizeMake(0, 1);
        card.layer.shadowRadius = 2;
        
        // 卡片内容视图 (负责圆角和裁剪)
        UIView *cardContent = [[UIView alloc] initWithFrame:card.bounds];
        cardContent.backgroundColor = [UIColor whiteColor];
        cardContent.layer.cornerRadius = 6;
        cardContent.layer.masksToBounds = YES;
        [card addSubview:cardContent];
        
        // 列表需要显示：name platform gid nick
        NSString *nameStr = [NSString stringWithFormat:@"%@", acc[@"name"] ?: @""];
        
        NSString *rawPlatform = acc[@"platform"] ?: @"";
        NSString *platformDisplay = @"未知";
        if ([rawPlatform isEqualToString:@"qq"]) {
            platformDisplay = @"QQ";
        } else if ([rawPlatform isEqualToString:@"wx"]) {
            platformDisplay = @"微信";
        }
        
        NSString *platformStr = [NSString stringWithFormat:@"平台: %@", platformDisplay];
        NSString *gidStr = [NSString stringWithFormat:@"GID: %@", acc[@"gid"] ?: @""];
        
        // 状态角标
        BOOL isRunning = [acc[@"running"] boolValue];
        UILabel *statusLabel = [[UILabel alloc] initWithFrame:CGRectMake(width - 50, 5, 40, 20)];
        statusLabel.text = isRunning ? @"运行" : @"停止";
        statusLabel.font = [UIFont boldSystemFontOfSize:12];
        statusLabel.textColor = [UIColor whiteColor];
        statusLabel.backgroundColor = isRunning ? [UIColor systemGreenColor] : [UIColor lightGrayColor]; // 停止使用灰色，运行使用绿色
        statusLabel.textAlignment = NSTextAlignmentCenter;
        statusLabel.layer.cornerRadius = 4;
        statusLabel.layer.masksToBounds = YES;
        [cardContent addSubview:statusLabel];
        
        UILabel *l1 = [[UILabel alloc] initWithFrame:CGRectMake(10, 5, width - 60, 20)]; // 调整宽度避免遮挡角标
        l1.text = [NSString stringWithFormat:@"%@（%@）", nameStr, acc[@"nick"] ?: @""];
        l1.font = [UIFont boldSystemFontOfSize:13];
        [cardContent addSubview:l1];
        
        UILabel *l2 = [[UILabel alloc] initWithFrame:CGRectMake(10, 25, width - 20, 20)];
        l2.text = [NSString stringWithFormat:@"%@ | %@", platformStr, gidStr];
        l2.font = [UIFont systemFontOfSize:12];
        l2.textColor = [UIColor darkGrayColor];
        [cardContent addSubview:l2];
        
        [self.accountsScrollView addSubview:card];
        
        // 按钮布局
        CGFloat btnW = (width - 40) / 3;
        CGFloat btnH = 30.0;
        CGFloat btnY = 50.0;
        
        // 更新按钮
        UIButton *updateBtn = [UIButton buttonWithType:UIButtonTypeSystem];
        updateBtn.frame = CGRectMake(10, btnY, btnW, btnH);
        [updateBtn setTitle:@"更新" forState:UIControlStateNormal];
        updateBtn.backgroundColor = [UIColor systemBlueColor];
        [updateBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        updateBtn.layer.cornerRadius = 4;
        updateBtn.titleLabel.font = [UIFont systemFontOfSize:12];
        objc_setAssociatedObject(updateBtn, &kAccountKey, acc, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [updateBtn addTarget:self action:@selector(onUpdateTapped:) forControlEvents:UIControlEventTouchUpInside];
        [cardContent addSubview:updateBtn];
        
        // 启动/停止按钮
        UIButton *toggleBtn = [UIButton buttonWithType:UIButtonTypeSystem];
        toggleBtn.frame = CGRectMake(10 + btnW + 10, btnY, btnW, btnH);
        [toggleBtn setTitle:isRunning ? @"停止" : @"启动" forState:UIControlStateNormal];
        toggleBtn.backgroundColor = isRunning ? [UIColor systemRedColor] : [UIColor systemGreenColor];
        [toggleBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        toggleBtn.layer.cornerRadius = 4;
        toggleBtn.titleLabel.font = [UIFont systemFontOfSize:12];
        objc_setAssociatedObject(toggleBtn, &kAccountKey, acc, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [toggleBtn addTarget:self action:@selector(onToggleTapped:) forControlEvents:UIControlEventTouchUpInside];
        [cardContent addSubview:toggleBtn];

        // 删除按钮
        UIButton *deleteBtn = [UIButton buttonWithType:UIButtonTypeSystem];
        deleteBtn.frame = CGRectMake(10 + btnW * 2 + 20, btnY, btnW, btnH);
        [deleteBtn setTitle:@"删除" forState:UIControlStateNormal];
        deleteBtn.backgroundColor = [UIColor grayColor];
        [deleteBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        deleteBtn.layer.cornerRadius = 4;
        deleteBtn.titleLabel.font = [UIFont systemFontOfSize:12];
        objc_setAssociatedObject(deleteBtn, &kAccountKey, acc, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [deleteBtn addTarget:self action:@selector(onDeleteTapped:) forControlEvents:UIControlEventTouchUpInside];
        [cardContent addSubview:deleteBtn];
        
        y += 100; // 90 (高度) + 10 (间距)
    }
    
    self.accountsScrollView.contentSize = CGSizeMake(self.accountsScrollView.frame.size.width, y);
}

- (void)onUpdateTapped:(UIButton *)sender {
    NSDictionary *acc = objc_getAssociatedObject(sender, &kAccountKey);
    // NSString *lastCode = [QQFarmUtils getLastCapturedCode];
    
    NSString *title = [NSString stringWithFormat:@"更新（%@）", acc[@"name"]];
    NSString *msg = @"是否上传 Code 到当前账号？";
    
    [self showCustomConfirmAlertWithTitle:title message:msg confirmHandler:^{
        NSLog(@"确认更新账号: %@", acc[@"name"]);
        
        NSString *server = self.serverInput.text;
        NSString *token = self.tokenInput.text;
        NSString *code = [QQFarmUtils getLastCapturedCode];
        
        if (!code || code.length == 0) {
            [self showCustomAlertWithTitle:@"错误" message:@"未获取到 Code，请先抓取 Code"];
            return;
        }
        
        if (!server || server.length == 0) {
            [self showCustomAlertWithTitle:@"错误" message:@"请先配置服务器地址"];
            return;
        }
        
        // 构建请求参数
        NSMutableDictionary *params = [NSMutableDictionary dictionary];
        if (acc[@"id"]) params[@"id"] = acc[@"id"];
        if (acc[@"name"]) params[@"name"] = acc[@"name"];
        params[@"code"] = code;
        if (acc[@"platform"]) params[@"platform"] = acc[@"platform"];
        // 继承 loginType，默认 manual
        params[@"loginType"] = acc[@"loginType"] ?: @"manual";
        
        // 处理 URL
        NSString *baseUrl = server;
        if ([baseUrl hasSuffix:@"/"]) {
            baseUrl = [baseUrl substringToIndex:baseUrl.length - 1];
        }
        NSString *urlString = [NSString stringWithFormat:@"%@/api/accounts", baseUrl];
        NSURL *url = [NSURL URLWithString:urlString];
        
        NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
        request.HTTPMethod = @"POST";
        [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
        if (token && token.length > 0) {
            [request setValue:token forHTTPHeaderField:@"x-admin-token"];
        }
        
        NSError *jsonError;
        NSData *jsonData = [NSJSONSerialization dataWithJSONObject:params options:0 error:&jsonError];
        if (jsonError) {
            [self showCustomAlertWithTitle:@"错误" message:@"构建请求数据失败"];
            return;
        }
        request.HTTPBody = jsonData;
        
        NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (error) {
                    [self showCustomAlertWithTitle:@"更新失败" message:error.localizedDescription];
                } else {
                    NSError *jsonError;
                    NSDictionary *respDict = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
                    if (jsonError) {
                         NSString *respStr = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
                         [self showCustomAlertWithTitle:@"更新失败" message:[NSString stringWithFormat:@"解析错误: %@", respStr]];
                    } else if ([respDict[@"ok"] boolValue]) {
                        [self showCustomAlertWithTitle:@"成功" message:@"账号 Code 已更新"];
                    } else {
                        // 如果 ok 为 false，尝试显示 message 或者整个 json
                        NSString *errMsg = respDict[@"message"] ?: @"未知错误";
                        [self showCustomAlertWithTitle:@"更新失败" message:errMsg];
                    }
                }
                
                // 无论成功失败，都刷新列表
                [self fetchAccounts];
            });
        }];
        [task resume];
    }];
}

- (void)onToggleTapped:(UIButton *)sender {
    NSDictionary *acc = objc_getAssociatedObject(sender, &kAccountKey);
    BOOL isRunning = [acc[@"running"] boolValue];
    // NSString *action = isRunning ? @"停止" : @"启动";
    
    NSString *title = [NSString stringWithFormat:@"操作（%@）", acc[@"name"]];
    NSString *msg = isRunning ? @"是否停止智能助手？" : @"是否启动智能助手？";
    
    [self showCustomConfirmAlertWithTitle:title message:msg confirmHandler:^{
        NSLog(@"确认%@账号: %@", isRunning ? @"停止" : @"启动", acc[@"name"]);
        
        NSString *server = self.serverInput.text;
        NSString *token = self.tokenInput.text;
        
        if (!server || server.length == 0) {
            [self showCustomAlertWithTitle:@"错误" message:@"请先配置服务器地址"];
            return;
        }
        
        // 处理 URL
        NSString *baseUrl = server;
        if ([baseUrl hasSuffix:@"/"]) {
            baseUrl = [baseUrl substringToIndex:baseUrl.length - 1];
        }
        
        NSString *accountId = [NSString stringWithFormat:@"%@", acc[@"id"]];
        NSString *actionPath = isRunning ? @"stop" : @"start";
        NSString *urlString = [NSString stringWithFormat:@"%@/api/accounts/%@/%@", baseUrl, accountId, actionPath];
        NSURL *url = [NSURL URLWithString:urlString];
        
        NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
        request.HTTPMethod = @"POST";
        [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
        if (token && token.length > 0) {
            [request setValue:token forHTTPHeaderField:@"x-admin-token"];
        }
        
        NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (error) {
                    [self showCustomAlertWithTitle:@"操作失败" message:error.localizedDescription];
                } else {
                    NSError *jsonError;
                    NSDictionary *respDict = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
                    if (jsonError) {
                         NSString *respStr = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
                         [self showCustomAlertWithTitle:@"操作失败" message:[NSString stringWithFormat:@"解析错误: %@", respStr]];
                    } else if ([respDict[@"ok"] boolValue]) {
                        NSString *successMsg = isRunning ? @"已停止" : @"已启动";
                        [self showCustomAlertWithTitle:@"成功" message:successMsg];
                    } else {
                        NSString *errMsg = respDict[@"message"] ?: @"未知错误";
                        [self showCustomAlertWithTitle:@"操作失败" message:errMsg];
                    }
                }
                // 刷新列表
                [self fetchAccounts];
            });
        }];
        [task resume];
    }];
}

- (void)onDeleteTapped:(UIButton *)sender {
    NSDictionary *acc = objc_getAssociatedObject(sender, &kAccountKey);
    NSString *title = [NSString stringWithFormat:@"删除（%@）", acc[@"name"]];
    NSString *msg = @"是否确认删除该账号？！";
    
    [self showCustomConfirmAlertWithTitle:title message:msg confirmHandler:^{
        NSLog(@"确认删除账号: %@", acc[@"name"]);
        
        NSString *server = self.serverInput.text;
        NSString *token = self.tokenInput.text;
        
        if (!server || server.length == 0) {
            [self showCustomAlertWithTitle:@"错误" message:@"请先配置服务器地址"];
            return;
        }
        
        // 处理 URL
        NSString *baseUrl = server;
        if ([baseUrl hasSuffix:@"/"]) {
            baseUrl = [baseUrl substringToIndex:baseUrl.length - 1];
        }
        
        NSString *accountId = [NSString stringWithFormat:@"%@", acc[@"id"]];
        NSString *urlString = [NSString stringWithFormat:@"%@/api/accounts/%@", baseUrl, accountId];
        NSURL *url = [NSURL URLWithString:urlString];
        
        NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
        request.HTTPMethod = @"DELETE";
        [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
        if (token && token.length > 0) {
            [request setValue:token forHTTPHeaderField:@"x-admin-token"];
        }
        
        NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (error) {
                    [self showCustomAlertWithTitle:@"删除失败" message:error.localizedDescription];
                } else {
                    NSError *jsonError;
                    NSDictionary *respDict = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
                    if (jsonError) {
                         NSString *respStr = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
                         [self showCustomAlertWithTitle:@"删除失败" message:[NSString stringWithFormat:@"解析错误: %@", respStr]];
                    } else if ([respDict[@"ok"] boolValue]) {
                        [self showCustomAlertWithTitle:@"成功" message:@"账号已删除"];
                    } else {
                        NSString *errMsg = respDict[@"message"] ?: @"未知错误";
                        [self showCustomAlertWithTitle:@"删除失败" message:errMsg];
                    }
                }
                // 刷新列表
                [self fetchAccounts];
            });
        }];
        [task resume];
    }];
}

#pragma mark - Custom Alert

- (void)showCustomConfirmAlertWithTitle:(NSString *)title message:(NSString *)message confirmHandler:(void (^)(void))confirmHandler {
    // 移除旧的 Alert
    if (self.currentAlertCover) {
        [self.currentAlertCover removeFromSuperview];
    }
    
    // 全屏遮罩
    UIView *cover = [[UIView alloc] initWithFrame:self.bounds];
    cover.backgroundColor = [UIColor colorWithWhite:0 alpha:0.4];
    [self.rootViewController.view addSubview:cover];
    self.currentAlertCover = cover;
    
    // Alert 容器
    UIView *alert = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 270, 160)];
    alert.center = cover.center;
    alert.backgroundColor = [UIColor whiteColor];
    alert.layer.cornerRadius = 14;
    alert.layer.masksToBounds = YES;
    [cover addSubview:alert];
    
    // 标题
    UILabel *tLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 20, 270, 22)];
    tLabel.text = title;
    tLabel.font = [UIFont boldSystemFontOfSize:17];
    tLabel.textAlignment = NSTextAlignmentCenter;
    tLabel.textColor = [UIColor blackColor];
    [alert addSubview:tLabel];
    
    // 内容
    UILabel *mLabel = [[UILabel alloc] initWithFrame:CGRectMake(15, 50, 240, 50)];
    mLabel.text = message;
    mLabel.font = [UIFont systemFontOfSize:13];
    mLabel.textAlignment = NSTextAlignmentCenter;
    mLabel.textColor = [UIColor blackColor];
    mLabel.numberOfLines = 0;
    [alert addSubview:mLabel];
    
    // 分割线（横向）
    UIView *hLine = [[UIView alloc] initWithFrame:CGRectMake(0, 110, 270, 0.5)];
    hLine.backgroundColor = [UIColor lightGrayColor];
    [alert addSubview:hLine];
    
    // 分割线（纵向）
    UIView *vLine = [[UIView alloc] initWithFrame:CGRectMake(135, 110, 0.5, 50)];
    vLine.backgroundColor = [UIColor lightGrayColor];
    [alert addSubview:vLine];
    
    // 取消按钮
    UIButton *cancelBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    cancelBtn.frame = CGRectMake(0, 110.5, 135, 49.5);
    [cancelBtn setTitle:@"取消" forState:UIControlStateNormal];
    [cancelBtn.titleLabel setFont:[UIFont systemFontOfSize:17]];
    [cancelBtn setTitleColor:[UIColor systemBlueColor] forState:UIControlStateNormal];
    [cancelBtn addTarget:self action:@selector(dismissCustomAlert:) forControlEvents:UIControlEventTouchUpInside];
    objc_setAssociatedObject(cancelBtn, "alert_cover", cover, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [alert addSubview:cancelBtn];
    
    // 确定按钮
    UIButton *confirmBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    confirmBtn.frame = CGRectMake(135, 110.5, 135, 49.5);
    [confirmBtn setTitle:@"确定" forState:UIControlStateNormal];
    [confirmBtn.titleLabel setFont:[UIFont boldSystemFontOfSize:17]];
    [confirmBtn setTitleColor:[UIColor systemBlueColor] forState:UIControlStateNormal];
    
    if (confirmHandler) {
        objc_setAssociatedObject(confirmBtn, "confirm_handler", confirmHandler, OBJC_ASSOCIATION_COPY_NONATOMIC);
    }
    [confirmBtn addTarget:self action:@selector(onConfirmTapped:) forControlEvents:UIControlEventTouchUpInside];
    objc_setAssociatedObject(confirmBtn, "alert_cover", cover, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [alert addSubview:confirmBtn];
    
    // 动画
    cover.alpha = 0;
    alert.transform = CGAffineTransformMakeScale(1.2, 1.2);
    [UIView animateWithDuration:0.2 animations:^{
        cover.alpha = 1;
        alert.transform = CGAffineTransformIdentity;
    }];
}

- (void)onConfirmTapped:(UIButton *)sender {
    void (^handler)(void) = objc_getAssociatedObject(sender, "confirm_handler");
    if (handler) {
        handler();
    }
    [self dismissCustomAlert:sender];
}

- (void)showCustomAlertWithTitle:(NSString *)title message:(NSString *)message {
    // 移除旧的 Alert
    if (self.currentAlertCover) {
        [self.currentAlertCover removeFromSuperview];
    }
    
    // 全屏遮罩
    UIView *cover = [[UIView alloc] initWithFrame:self.bounds];
    cover.backgroundColor = [UIColor colorWithWhite:0 alpha:0.4];
    [self.rootViewController.view addSubview:cover];
    self.currentAlertCover = cover;
    
    // Alert 容器
    UIView *alert = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 270, 160)];
    alert.center = cover.center;
    alert.backgroundColor = [UIColor whiteColor];
    alert.layer.cornerRadius = 14;
    alert.layer.masksToBounds = YES;
    [cover addSubview:alert];
    
    // 标题
    UILabel *tLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 20, 270, 22)];
    tLabel.text = title;
    tLabel.font = [UIFont boldSystemFontOfSize:17];
    tLabel.textAlignment = NSTextAlignmentCenter;
    tLabel.textColor = [UIColor blackColor];
    [alert addSubview:tLabel];
    
    // 内容
    UILabel *mLabel = [[UILabel alloc] initWithFrame:CGRectMake(15, 50, 240, 50)];
    mLabel.text = message;
    mLabel.font = [UIFont systemFontOfSize:13];
    mLabel.textAlignment = NSTextAlignmentCenter;
    mLabel.textColor = [UIColor blackColor];
    mLabel.numberOfLines = 0;
    [alert addSubview:mLabel];
    
    // 分割线
    UIView *line = [[UIView alloc] initWithFrame:CGRectMake(0, 110, 270, 0.5)];
    line.backgroundColor = [UIColor lightGrayColor];
    [alert addSubview:line];
    
    // 按钮
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
    btn.frame = CGRectMake(0, 110.5, 270, 49.5);
    [btn setTitle:@"确定" forState:UIControlStateNormal];
    [btn.titleLabel setFont:[UIFont boldSystemFontOfSize:17]];
    [btn setTitleColor:[UIColor systemBlueColor] forState:UIControlStateNormal];
    [btn addTarget:self action:@selector(dismissCustomAlert:) forControlEvents:UIControlEventTouchUpInside];
    objc_setAssociatedObject(btn, "alert_cover", cover, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [alert addSubview:btn];
    
    // 动画
    cover.alpha = 0;
    alert.transform = CGAffineTransformMakeScale(1.2, 1.2);
    [UIView animateWithDuration:0.2 animations:^{
        cover.alpha = 1;
        alert.transform = CGAffineTransformIdentity;
    }];
}

- (void)dismissCustomAlert:(UIButton *)sender {
    UIView *cover = objc_getAssociatedObject(sender, "alert_cover");
    if (cover) {
        [UIView animateWithDuration:0.2 animations:^{
            cover.alpha = 0;
        } completion:^(BOOL finished) {
            [cover removeFromSuperview];
            if (self.currentAlertCover == cover) {
                self.currentAlertCover = nil;
            }
        }];
    }
}

@end
