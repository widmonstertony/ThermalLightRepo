#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>
#import <MediaPlayer/MediaPlayer.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <os/log.h>
#import <dlfcn.h>
#import <math.h>

typedef WKWebView * _Nullable (*CreateWebViewIMP)(
    id,
    SEL,
    WKWebView *,
    WKWebViewConfiguration *,
    WKNavigationAction *,
    WKWindowFeatures *
);

typedef void (*DecidePolicyIMP)(
    id,
    SEL,
    WKWebView *,
    WKNavigationAction *,
    void (^)(WKNavigationActionPolicy)
);

static BOOL HyaaBrowserVisible = NO;

static NSString * const NTFMediaMessageName = @"newtTouchBarMedia";
static NSString * const NTFVidCatchEndpoint = @"http://127.0.0.1:17368";
static NSString * const NTFVidCatchToken = @"vsl_4fd6bdb89fcd4d40a6e724f94908213e";
static const void *NTFMediaScriptInstalledKey = &NTFMediaScriptInstalledKey;
static const void *NTFTrackpadGestureInstalledKey = &NTFTrackpadGestureInstalledKey;

extern unsigned char NTFVidCatchBridgeScriptBytes[];
extern unsigned int NTFVidCatchBridgeScriptBytes_len;

static NSString *NTFVidCatchBridgeScript(void) {
    return [[NSString alloc]
        initWithBytes:NTFVidCatchBridgeScriptBytes
        length:NTFVidCatchBridgeScriptBytes_len
        encoding:NSUTF8StringEncoding
    ] ?: @"";
}

@interface NTFMediaBridge : NSObject <WKScriptMessageHandler>
@property(nonatomic, weak) WKWebView *activeWebView;
@property(nonatomic) BOOL paused;
@property(nonatomic) BOOL pictureInPicture;
@property(nonatomic) BOOL pictureInPictureAvailable;
@property(nonatomic) BOOL fullscreen;
@property(nonatomic) NSTimeInterval elapsed;
@property(nonatomic) NSTimeInterval duration;
@property(nonatomic, strong) id touchBar;
@property(nonatomic, strong) id touchBarProvider;
@property(nonatomic, strong) id timing;
@property(nonatomic, copy) NSArray *seekableTimeRanges;
@property(nonatomic) double defaultPlaybackRate;
@property(nonatomic) float rate;
@property(nonatomic, strong) id touchBarSliderItem;
@property(nonatomic, strong) id touchBarSlider;
@property(nonatomic, strong) id touchBarPlayPauseItem;
@property(nonatomic, strong) id touchBarPictureInPictureItem;
@property(nonatomic, strong) id touchBarFullscreenItem;
@property(nonatomic, strong) id touchBarExitFullscreenItem;
@property(nonatomic, strong) id touchBarWindow;
@property(nonatomic, strong) id previousTouchBar;
+ (instancetype)sharedBridge;
- (void)clear;
@end

@interface NTFVidCatchManager : NSObject
@property(nonatomic, weak) WKWebView *webView;
@property(nonatomic, strong) WKFrameInfo *frameInfo;
@property(nonatomic, strong) NSURLSession *session;
@property(nonatomic, copy) NSString *jobID;
+ (instancetype)sharedManager;
- (void)startDownloadWithMessage:(NSDictionary *)message
                         webView:(WKWebView *)webView
                       frameInfo:(WKFrameInfo *)frameInfo;
@end

@interface NTFiPadDownloadManager : NSObject <NSURLSessionDownloadDelegate, AVAssetDownloadDelegate>
@property(nonatomic, weak) WKWebView *webView;
@property(nonatomic, strong) WKFrameInfo *frameInfo;
@property(nonatomic, strong) NSURLSession *directSession;
@property(nonatomic, strong) AVAssetDownloadURLSession *assetSession;
@property(nonatomic, strong) NSURLSessionTask *activeTask;
@property(nonatomic, strong) AVAssetExportSession *exportSession;
@property(nonatomic, strong) NSURL *assetLocation;
@property(nonatomic, copy) NSString *title;
@property(nonatomic, copy) NSString *kind;
+ (instancetype)sharedManager;
- (void)startDownloadWithMessage:(NSDictionary *)message
                         webView:(WKWebView *)webView
                       frameInfo:(WKFrameInfo *)frameInfo;
@end

@interface NTFMediaBridge ()
- (void)installRemoteCommands;
- (void)sendCommand:(NSString *)command value:(NSNumber *)value;
- (void)refreshAVKitTimingWithRate:(double)rate;
- (BOOL)installSafariTouchBarIfAvailable;
- (void)installSafariFullscreenItemIfNeeded;
- (void)installTouchBarIfNeeded;
- (void)installFallbackTouchBarIfNeeded;
- (void)updateFullscreenButton;
- (void)updateSafariEscapeKey;
- (void)updateTouchBarControls;
- (void)publishNowPlayingTitle:(NSString *)title rate:(double)rate;
@end

static NSString *NTFVideoBridgeScript(void) {
    return
    @"(function(){"
     "if(window.__newtTouchBarInstalled)return;"
     "window.__newtTouchBarInstalled=true;"
     "var bound=new WeakSet(),active=null,lastSent=0;"
     "function finite(v){return Number.isFinite(v)?v:0;}"
     "function post(v,force){"
       "if(!v)return;"
       "var now=Date.now();if(!force&&now-lastSent<450)return;lastSent=now;"
       "try{window.webkit.messageHandlers.newtTouchBarMedia.postMessage({"
         "type:'state',currentTime:finite(v.currentTime),duration:finite(v.duration),"
         "paused:!!v.paused,ended:!!v.ended,rate:finite(v.playbackRate)||1,"
         "pip:(document.pictureInPictureElement===v)||v.webkitPresentationMode==='picture-in-picture',"
         "pipAvailable:!!document.pictureInPictureEnabled||"
           "(typeof v.webkitSupportsPresentationMode==='function'&&v.webkitSupportsPresentationMode('picture-in-picture')),"
         "fullscreen:!!document.fullscreenElement||!!v.webkitDisplayingFullscreen||v.webkitPresentationMode==='fullscreen',"
         "title:document.title||'\u5c0f\u8349\u89c6\u9891',src:v.currentSrc||v.src||location.href"
       "});}catch(e){}"
     "}"
     "function bind(v){"
       "if(!v||bound.has(v))return;bound.add(v);"
       "['loadedmetadata','durationchange','play','pause','ended','ratechange','seeking','seeked',"
         "'webkitpresentationmodechanged','webkitbeginfullscreen','webkitendfullscreen',"
         "'enterpictureinpicture','leavepictureinpicture']"
         ".forEach(function(n){v.addEventListener(n,function(){active=v;post(v,true);},true);});"
       "v.addEventListener('timeupdate',function(){active=v;post(v,false);},true);"
       "if(!v.paused||v.currentTime>0){active=v;post(v,true);}"
     "}"
     "function scan(root){"
       "if(!root)return;if(root.tagName==='VIDEO')bind(root);"
       "if(root.querySelectorAll)root.querySelectorAll('video').forEach(bind);"
     "}"
     "function current(){"
       "if(active&&document.contains(active))return active;"
       "var all=Array.from(document.querySelectorAll('video'));"
       "return all.find(function(v){return !v.paused&&!v.ended;})||all[0]||null;"
     "}"
     "window.addEventListener('message',function(e){"
       "var d=e.data;if(!d||d.__newtTouchBarCommand!==true)return;"
       "var v=current();if(!v)return;active=v;"
       "if(d.command==='play'){var p=v.play();if(p&&p.catch)p.catch(function(){});}"
       "else if(d.command==='pause')v.pause();"
       "else if(d.command==='toggle'){if(v.paused){var q=v.play();if(q&&q.catch)q.catch(function(){});}else v.pause();}"
       "else if(d.command==='seek'&&Number.isFinite(d.value)){"
         "var t=Math.max(0,d.value);if(Number.isFinite(v.duration))t=Math.min(t,v.duration);v.currentTime=t;"
       "}"
       "else if(d.command==='pip'){"
         "if(typeof v.webkitSetPresentationMode==='function'&&typeof v.webkitSupportsPresentationMode==='function'&&"
            "v.webkitSupportsPresentationMode('picture-in-picture')){"
           "v.webkitSetPresentationMode(v.webkitPresentationMode==='picture-in-picture'?'inline':'picture-in-picture');"
         "}else if(document.pictureInPictureElement&&document.exitPictureInPicture){"
           "var x=document.exitPictureInPicture();if(x&&x.catch)x.catch(function(){});"
         "}else if(v.requestPictureInPicture){"
           "var y=v.requestPictureInPicture();if(y&&y.catch)y.catch(function(){});"
         "}"
       "}"
       "else if(d.command==='fullscreen'){"
         "var isFull=!!document.fullscreenElement||!!v.webkitDisplayingFullscreen||v.webkitPresentationMode==='fullscreen';"
         "if(isFull){"
           "if(document.fullscreenElement&&document.exitFullscreen){"
             "var ef=document.exitFullscreen();if(ef&&ef.catch)ef.catch(function(){});"
           "}else if(typeof v.webkitExitFullscreen==='function')v.webkitExitFullscreen();"
           "else if(typeof v.webkitSetPresentationMode==='function')v.webkitSetPresentationMode('inline');"
         "}else if(typeof v.webkitSetPresentationMode==='function'&&"
           "(typeof v.webkitSupportsPresentationMode!=='function'||v.webkitSupportsPresentationMode('fullscreen'))){"
           "v.webkitSetPresentationMode('fullscreen');"
         "}else if(typeof v.webkitEnterFullscreen==='function')v.webkitEnterFullscreen();"
         "else if(v.requestFullscreen){var rf=v.requestFullscreen();if(rf&&rf.catch)rf.catch(function(){});}"
         "else if(v.webkitRequestFullscreen)v.webkitRequestFullscreen();"
       "}"
       "else if(d.command==='exitFullscreen'){"
         "if(document.fullscreenElement&&document.exitFullscreen){"
           "var z=document.exitFullscreen();if(z&&z.catch)z.catch(function(){});"
         "}else if(typeof v.webkitExitFullscreen==='function')v.webkitExitFullscreen();"
         "else if(typeof v.webkitSetPresentationMode==='function')v.webkitSetPresentationMode('inline');"
       "}"
       "post(v,true);"
     "},false);"
     "document.addEventListener('fullscreenchange',function(){post(current(),true);},true);"
     "scan(document);"
     "new MutationObserver(function(ms){ms.forEach(function(m){m.addedNodes.forEach(scan);});})"
       ".observe(document.documentElement||document,{childList:true,subtree:true});"
     "window.addEventListener('pagehide',function(){"
       "try{window.webkit.messageHandlers.newtTouchBarMedia.postMessage({type:'clear'});}catch(e){}"
     "});"
    "})();";
}

static void NTFSendObject(id receiver, SEL selector, id value) {
    ((void (*)(id, SEL, id))objc_msgSend)(receiver, selector, value);
}

static id NTFGetObject(id receiver, SEL selector) {
    return ((id (*)(id, SEL))objc_msgSend)(receiver, selector);
}

static void NTFSendDouble(id receiver, SEL selector, double value) {
    ((void (*)(id, SEL, double))objc_msgSend)(receiver, selector, value);
}

static double NTFGetDouble(id receiver, SEL selector) {
    return ((double (*)(id, SEL))objc_msgSend)(receiver, selector);
}

static NSUInteger NTFGetUnsignedInteger(id receiver, SEL selector) {
    return ((NSUInteger (*)(id, SEL))objc_msgSend)(receiver, selector);
}

static BOOL NTFGetBool(id receiver, SEL selector) {
    return ((BOOL (*)(id, SEL))objc_msgSend)(receiver, selector);
}

static void NTFSendBool(id receiver, SEL selector, BOOL value) {
    ((void (*)(id, SEL, BOOL))objc_msgSend)(receiver, selector, value);
}

static id NTFImageNamed(NSString *name) {
    Class imageClass = NSClassFromString(@"NSImage");
    if (imageClass == Nil) return nil;
    return ((id (*)(id, SEL, id))objc_msgSend)(
        imageClass,
        NSSelectorFromString(@"imageNamed:"),
        name
    );
}

static id NTFSymbolImage(NSString *symbolName, NSString *fallbackName) {
    Class imageClass = NSClassFromString(@"NSImage");
    SEL selector = NSSelectorFromString(@"imageWithSystemSymbolName:accessibilityDescription:");
    if (imageClass != Nil && [imageClass respondsToSelector:selector]) {
        id image = ((id (*)(id, SEL, id, id))objc_msgSend)(
            imageClass,
            selector,
            symbolName,
            nil
        );
        if (image != nil) return image;
    }
    return NTFImageNamed(fallbackName);
}

static id NTFCreateTouchBarButton(
    Class buttonItemClass,
    NSString *identifier,
    id image,
    id target,
    SEL action
) {
    SEL selector = NSSelectorFromString(@"buttonTouchBarItemWithIdentifier:image:target:action:");
    return ((id (*)(id, SEL, id, id, id, SEL))objc_msgSend)(
        buttonItemClass,
        selector,
        identifier,
        image,
        target,
        action
    );
}

static BOOL NTFLoadMacAVKit(void) {
    static void *avKitHandle;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        avKitHandle = dlopen(
            "/System/Library/Frameworks/AVKit.framework/AVKit",
            RTLD_LAZY | RTLD_LOCAL
        );
    });
    return avKitHandle != NULL &&
        NSClassFromString(@"AVTouchBarPlaybackControlsProvider") != Nil &&
        NSClassFromString(@"AVValueTiming") != Nil;
}

static BOOL NTFCookieMatchesURL(NSHTTPCookie *cookie, NSURL *url) {
    NSString *host = url.host.lowercaseString ?: @"";
    NSString *domain = cookie.domain.lowercaseString ?: @"";
    while ([domain hasPrefix:@"."]) domain = [domain substringFromIndex:1];
    BOOL domainMatches = [host isEqualToString:domain] ||
        (domain.length > 0 && [host hasSuffix:[@"." stringByAppendingString:domain]]);
    if (!domainMatches) return NO;

    NSString *path = url.path.length > 0 ? url.path : @"/";
    NSString *cookiePath = cookie.path.length > 0 ? cookie.path : @"/";
    if (![path hasPrefix:cookiePath]) return NO;
    if (cookie.isSecure && ![url.scheme.lowercaseString isEqualToString:@"https"]) return NO;
    return YES;
}

static BOOL NTFIsMacRuntime(void) {
    NSProcessInfo *processInfo = NSProcessInfo.processInfo;
    BOOL iOSAppOnMac = NO;
    if (@available(iOS 14.0, *)) iOSAppOnMac = processInfo.iOSAppOnMac;
    return processInfo.macCatalystApp || iOSAppOnMac;
}

static void NTFSendDownloadStatus(
    WKWebView *webView,
    WKFrameInfo *frameInfo,
    NSDictionary *status
) {
    if (webView == nil || ![NSJSONSerialization isValidJSONObject:status]) return;
    NSError *error = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:status options:0 error:&error];
    if (data == nil || error != nil) return;
    NSString *json = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (json.length == 0) return;
    NSString *script = [NSString stringWithFormat:
        @"window.__newtVidCatchStatus&&window.__newtVidCatchStatus(%@);", json];
    dispatch_async(dispatch_get_main_queue(), ^{
        if (@available(iOS 14.0, *)) {
            [webView evaluateJavaScript:script
                                inFrame:frameInfo
                          inContentWorld:WKContentWorld.pageWorld
                       completionHandler:nil];
        } else {
            [webView evaluateJavaScript:script completionHandler:nil];
        }
    });
}

static NSDictionary<NSString *, NSString *> *NTFRequestHeaders(
    NSDictionary *message,
    NSURL *mediaURL,
    NSArray<NSHTTPCookie *> *cookies
) {
    NSMutableDictionary<NSString *, NSString *> *headers = [NSMutableDictionary dictionary];
    NSString *pageURL = [message[@"pageUrl"] isKindOfClass:NSString.class]
        ? message[@"pageUrl"]
        : @"";
    NSString *userAgent = [message[@"userAgent"] isKindOfClass:NSString.class]
        ? message[@"userAgent"]
        : @"";
    if (pageURL.length > 0) headers[@"Referer"] = pageURL;
    if (userAgent.length > 0) headers[@"User-Agent"] = userAgent;

    NSMutableArray<NSHTTPCookie *> *matchingCookies = [NSMutableArray array];
    for (NSHTTPCookie *cookie in cookies ?: @[]) {
        if (NTFCookieMatchesURL(cookie, mediaURL)) [matchingCookies addObject:cookie];
    }
    NSString *cookieHeader = [NSHTTPCookie requestHeaderFieldsWithCookies:matchingCookies][@"Cookie"];
    if (cookieHeader.length > 0) headers[@"Cookie"] = cookieHeader;
    return headers;
}

static NSString *NTFSafeFileStem(NSString *rawTitle) {
    NSString *value = [rawTitle isKindOfClass:NSString.class] ? rawTitle : @"";
    NSCharacterSet *forbidden = [NSCharacterSet characterSetWithCharactersInString:
        @"/:\\?%*|\"<>\r\n\t"];
    NSArray<NSString *> *parts = [value componentsSeparatedByCharactersInSet:forbidden];
    value = [[parts componentsJoinedByString:@"-"]
        stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    while ([value containsString:@"--"]) value = [value stringByReplacingOccurrencesOfString:@"--" withString:@"-"];
    if (value.length == 0) value = @"小草视频";
    if (value.length > 96) value = [value substringToIndex:96];
    return value;
}

static NSURL *NTFiPadVidCatchDirectory(void) {
    NSURL *documents = [NSFileManager.defaultManager URLsForDirectory:NSDocumentDirectory
                                                            inDomains:NSUserDomainMask].firstObject;
    if (documents == nil) return nil;
    NSURL *directory = [documents URLByAppendingPathComponent:@"VidCatch" isDirectory:YES];
    [NSFileManager.defaultManager createDirectoryAtURL:directory
                           withIntermediateDirectories:YES
                                            attributes:nil
                                                 error:nil];
    return directory;
}

static NSURL *NTFUniqueOutputURL(NSString *title, NSString *extension) {
    NSURL *directory = NTFiPadVidCatchDirectory();
    if (directory == nil) return nil;
    NSString *stem = NTFSafeFileStem(title);
    NSString *fileExtension = extension.length > 0 ? extension.lowercaseString : @"mp4";
    NSURL *candidate = [directory URLByAppendingPathComponent:
        [[stem stringByAppendingPathExtension:fileExtension] lastPathComponent]];
    NSUInteger suffix = 2;
    while ([NSFileManager.defaultManager fileExistsAtPath:candidate.path]) {
        NSString *next = [NSString stringWithFormat:@"%@-%lu", stem, (unsigned long)suffix++];
        candidate = [directory URLByAppendingPathComponent:[next stringByAppendingPathExtension:fileExtension]];
    }
    return candidate;
}

@implementation NTFVidCatchManager

+ (instancetype)sharedManager {
    static NTFVidCatchManager *manager;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        manager = [[self alloc] init];
        NSURLSessionConfiguration *configuration =
            NSURLSessionConfiguration.ephemeralSessionConfiguration;
        configuration.timeoutIntervalForRequest = 12.0;
        configuration.timeoutIntervalForResource = 30.0;
        manager.session = [NSURLSession sessionWithConfiguration:configuration];
    });
    return manager;
}

- (void)sendStatus:(NSDictionary *)status {
    NTFSendDownloadStatus(self.webView, self.frameInfo, status);
}

- (void)failWithMessage:(NSString *)message {
    self.jobID = nil;
    [self sendStatus:@{
        @"status": @"error",
        @"message": message.length > 0 ? message : @"VidCatch 下载失败"
    }];
}

- (NSDictionary *)JSONDictionaryFromData:(NSData *)data error:(NSError **)error {
    if (data.length == 0) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:@"NTFVidCatch"
                                         code:1
                                     userInfo:@{NSLocalizedDescriptionKey: @"VidCatch 返回了空响应"}];
        }
        return nil;
    }
    id object = [NSJSONSerialization JSONObjectWithData:data options:0 error:error];
    return [object isKindOfClass:NSDictionary.class] ? object : nil;
}

- (NSMutableURLRequest *)requestWithPath:(NSString *)path method:(NSString *)method {
    NSURL *url = [NSURL URLWithString:[NTFVidCatchEndpoint stringByAppendingString:path]];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = method;
    [request setValue:NTFVidCatchToken forHTTPHeaderField:@"X-Video-Scout-Token"];
    [request setValue:@"application/json; charset=utf-8" forHTTPHeaderField:@"Content-Type"];
    return request;
}

- (void)pollJobAfterDelay:(NSTimeInterval)delay {
    NSString *jobID = self.jobID;
    if (jobID.length == 0) return;
    dispatch_after(
        dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)),
        dispatch_get_main_queue(),
        ^{
            if (![self.jobID isEqualToString:jobID]) return;
            NSString *path = [@"/jobs/" stringByAppendingString:jobID];
            NSMutableURLRequest *request = [self requestWithPath:path method:@"GET"];
            NSURLSessionDataTask *task = [self.session
                dataTaskWithRequest:request
                completionHandler:^(NSData *data, NSURLResponse *response, NSError *networkError) {
                    if (![self.jobID isEqualToString:jobID]) return;
                    if (networkError != nil) {
                        [self failWithMessage:@"VidCatch companion 已断开，请确认本地服务仍在运行"];
                        return;
                    }
                    NSHTTPURLResponse *http = [response isKindOfClass:NSHTTPURLResponse.class]
                        ? (NSHTTPURLResponse *)response
                        : nil;
                    NSError *jsonError = nil;
                    NSDictionary *json = [self JSONDictionaryFromData:data error:&jsonError];
                    NSDictionary *job = [json[@"job"] isKindOfClass:NSDictionary.class]
                        ? json[@"job"]
                        : nil;
                    if (http.statusCode != 200 || job == nil) {
                        NSString *message = [json[@"error"] isKindOfClass:NSString.class]
                            ? json[@"error"]
                            : jsonError.localizedDescription;
                        [self failWithMessage:message ?: @"无法读取 VidCatch 下载状态"];
                        return;
                    }

                    NSString *status = [job[@"status"] isKindOfClass:NSString.class]
                        ? job[@"status"]
                        : @"queued";
                    NSString *message = [job[@"message"] isKindOfClass:NSString.class]
                        ? job[@"message"]
                        : @"";
                    NSNumber *progress = [job[@"progress"] isKindOfClass:NSNumber.class]
                        ? job[@"progress"]
                        : @0;
                    [self sendStatus:@{
                        @"status": status,
                        @"message": message,
                        @"progress": progress
                    }];

                    if ([status isEqualToString:@"complete"] ||
                        [status isEqualToString:@"error"] ||
                        [status isEqualToString:@"cancelled"]) {
                        self.jobID = nil;
                        return;
                    }
                    [self pollJobAfterDelay:1.0];
                }
            ];
            [task resume];
        }
    );
}

- (void)submitMessage:(NSDictionary *)message cookies:(NSArray<NSHTTPCookie *> *)cookies {
    NSString *rawURL = [message[@"url"] isKindOfClass:NSString.class] ? message[@"url"] : @"";
    NSURL *mediaURL = [NSURL URLWithString:rawURL];
    if (mediaURL == nil ||
        (![[mediaURL.scheme lowercaseString] isEqualToString:@"http"] &&
         ![[mediaURL.scheme lowercaseString] isEqualToString:@"https"])) {
        [self failWithMessage:@"没有检测到可下载的 HTTP(S) 视频地址"];
        return;
    }

    NSMutableDictionary *headers = [NSMutableDictionary dictionary];
    NSString *pageURL = [message[@"pageUrl"] isKindOfClass:NSString.class]
        ? message[@"pageUrl"]
        : @"";
    NSString *userAgent = [message[@"userAgent"] isKindOfClass:NSString.class]
        ? message[@"userAgent"]
        : @"";
    if (pageURL.length > 0) headers[@"Referer"] = pageURL;
    if (userAgent.length > 0) headers[@"User-Agent"] = userAgent;

    NSMutableArray *matchingCookies = [NSMutableArray array];
    for (NSHTTPCookie *cookie in cookies ?: @[]) {
        if (NTFCookieMatchesURL(cookie, mediaURL)) [matchingCookies addObject:cookie];
    }
    NSString *cookieHeader = [NSHTTPCookie requestHeaderFieldsWithCookies:matchingCookies][@"Cookie"];
    if (cookieHeader.length > 0) headers[@"Cookie"] = cookieHeader;

    NSString *title = [message[@"title"] isKindOfClass:NSString.class]
        ? message[@"title"]
        : @"小草视频";
    NSDictionary *payload = @{
        @"url": mediaURL.absoluteString,
        @"title": title.length > 0 ? title : @"小草视频",
        @"headers": headers,
        @"options": @{
            @"container": @"mp4",
            @"audioOnly": @NO,
            @"historyEnabled": @YES,
            @"maxConcurrent": @6,
            @"filenameTemplate": @"{title}"
        }
    };
    NSError *bodyError = nil;
    NSData *body = [NSJSONSerialization dataWithJSONObject:payload options:0 error:&bodyError];
    if (body == nil || bodyError != nil) {
        [self failWithMessage:@"无法生成 VidCatch 下载请求"];
        return;
    }

    NSMutableURLRequest *request = [self requestWithPath:@"/jobs" method:@"POST"];
    request.HTTPBody = body;
    [self sendStatus:@{
        @"status": @"queued",
        @"message": @"正在连接 VidCatch companion…",
        @"progress": @0
    }];

    NSURLSessionDataTask *task = [self.session
        dataTaskWithRequest:request
        completionHandler:^(NSData *data, NSURLResponse *response, NSError *networkError) {
            if (networkError != nil) {
                [self failWithMessage:
                    @"VidCatch companion 未运行。请安装并启动 VidCatch v0.3.0，本按钮才能下载和合并视频。"];
                return;
            }
            NSHTTPURLResponse *http = [response isKindOfClass:NSHTTPURLResponse.class]
                ? (NSHTTPURLResponse *)response
                : nil;
            NSError *jsonError = nil;
            NSDictionary *json = [self JSONDictionaryFromData:data error:&jsonError];
            NSDictionary *job = [json[@"job"] isKindOfClass:NSDictionary.class]
                ? json[@"job"]
                : nil;
            NSString *jobID = [job[@"id"] isKindOfClass:NSString.class] ? job[@"id"] : nil;
            if (http.statusCode != 202 || jobID.length == 0) {
                NSString *message = [json[@"error"] isKindOfClass:NSString.class]
                    ? json[@"error"]
                    : jsonError.localizedDescription;
                [self failWithMessage:message ?: @"VidCatch 拒绝了下载任务"];
                return;
            }
            self.jobID = jobID;
            [self sendStatus:@{
                @"status": @"probing",
                @"message": @"正在分析视频轨道…",
                @"progress": @0
            }];
            [self pollJobAfterDelay:0.5];
        }
    ];
    [task resume];
}

- (void)startDownloadWithMessage:(NSDictionary *)message
                         webView:(WKWebView *)webView
                       frameInfo:(WKFrameInfo *)frameInfo {
    self.webView = webView;
    self.frameInfo = frameInfo;
    if (self.jobID.length > 0) {
        [self sendStatus:@{
            @"status": @"downloading",
            @"message": @"已有一个 VidCatch 下载任务正在进行",
            @"progress": @0
        }];
        return;
    }

    WKHTTPCookieStore *cookieStore = webView.configuration.websiteDataStore.httpCookieStore;
    if (cookieStore == nil) {
        NSArray *cookies = [NSHTTPCookieStorage.sharedHTTPCookieStorage cookiesForURL:
            [NSURL URLWithString:message[@"url"] ?: @""]
        ];
        [self submitMessage:message cookies:cookies ?: @[]];
        return;
    }
    [cookieStore getAllCookies:^(NSArray<NSHTTPCookie *> *cookies) {
        [self submitMessage:message cookies:cookies ?: @[]];
    }];
}

@end

@implementation NTFiPadDownloadManager

+ (instancetype)sharedManager {
    static NTFiPadDownloadManager *manager;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ manager = [[self alloc] init]; });
    return manager;
}

- (void)sendStatus:(NSDictionary *)status {
    NTFSendDownloadStatus(self.webView, self.frameInfo, status);
}

- (void)resetDownloadState {
    self.activeTask = nil;
    self.assetLocation = nil;
    self.exportSession = nil;
    self.kind = nil;
}

- (void)failWithMessage:(NSString *)message {
    [self sendStatus:@{
        @"status": @"error",
        @"message": message.length > 0 ? message : @"iPad 下载失败"
    }];
    [self resetDownloadState];
}

- (void)finishAtURL:(NSURL *)url {
    NSString *relativePath = [@"VidCatch" stringByAppendingPathComponent:url.lastPathComponent ?: @""];
    [self sendStatus:@{
        @"status": @"complete",
        @"message": [NSString stringWithFormat:
            @"已保存到“文件”App：在我的 iPad 上 > 小草补丁V8 > %@", relativePath]
    }];
    [self resetDownloadState];
}

- (void)startDirectDownload:(NSURL *)url headers:(NSDictionary<NSString *, NSString *> *)headers {
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.timeoutInterval = 60.0;
    [headers enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSString *value, BOOL *stop) {
        (void)stop;
        [request setValue:value forHTTPHeaderField:key];
    }];

    NSURLSessionConfiguration *configuration = NSURLSessionConfiguration.defaultSessionConfiguration;
    configuration.timeoutIntervalForRequest = 60.0;
    configuration.timeoutIntervalForResource = 60.0 * 60.0;
    self.directSession = [NSURLSession sessionWithConfiguration:configuration
                                                       delegate:self
                                                  delegateQueue:nil];
    self.activeTask = [self.directSession downloadTaskWithRequest:request];
    [self sendStatus:@{
        @"status": @"downloading",
        @"message": @"正在下载到 iPad 的“文件”App…",
        @"progress": @0
    }];
    [self.activeTask resume];
}

- (void)startHLSDownload:(NSURL *)url headers:(NSDictionary<NSString *, NSString *> *)headers {
    NSString *identifier = [NSString stringWithFormat:@"%@.vidcatch.hls",
        NSBundle.mainBundle.bundleIdentifier ?: @"com.cl.NewT66y"];
    NSURLSessionConfiguration *configuration =
        [NSURLSessionConfiguration backgroundSessionConfigurationWithIdentifier:identifier];
    configuration.discretionary = NO;
    configuration.sessionSendsLaunchEvents = YES;
    configuration.HTTPAdditionalHeaders = headers;
    self.assetSession = [AVAssetDownloadURLSession
        sessionWithConfiguration:configuration
        assetDownloadDelegate:self
        delegateQueue:nil
    ];

    NSDictionary *assetOptions = headers.count > 0
        ? @{@"AVURLAssetHTTPHeaderFieldsKey": headers}
        : nil;
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:url options:assetOptions];
    AVAssetDownloadTask *task = [self.assetSession
        assetDownloadTaskWithURLAsset:asset
        assetTitle:self.title ?: @"小草视频"
        assetArtworkData:nil
        options:nil
    ];
    if (task == nil) {
        [self failWithMessage:@"iPad 无法创建 HLS 离线下载任务"];
        return;
    }
    self.activeTask = task;
    [self sendStatus:@{
        @"status": @"downloading",
        @"message": @"正在下载 HLS 视频到 iPad…",
        @"progress": @0
    }];
    [task resume];
}

- (void)beginWithMessage:(NSDictionary *)message cookies:(NSArray<NSHTTPCookie *> *)cookies {
    NSString *rawURL = [message[@"url"] isKindOfClass:NSString.class] ? message[@"url"] : @"";
    NSURL *mediaURL = [NSURL URLWithString:rawURL];
    if (mediaURL == nil ||
        (![[mediaURL.scheme lowercaseString] isEqualToString:@"http"] &&
         ![[mediaURL.scheme lowercaseString] isEqualToString:@"https"])) {
        [self failWithMessage:@"没有检测到可下载的 HTTP(S) 视频地址"];
        return;
    }

    self.title = [message[@"title"] isKindOfClass:NSString.class]
        ? message[@"title"]
        : @"小草视频";
    self.kind = [message[@"kind"] isKindOfClass:NSString.class]
        ? [message[@"kind"] lowercaseString]
        : @"direct";
    if ([self.kind isEqualToString:@"dash"] ||
        [[mediaURL.pathExtension lowercaseString] isEqualToString:@"mpd"]) {
        [self failWithMessage:@"这个视频是 DASH 格式；iPad 系统不能原生合并，请在 Mac 上用 VidCatch 下载"];
        return;
    }

    NSDictionary<NSString *, NSString *> *headers = NTFRequestHeaders(message, mediaURL, cookies);
    for (NSHTTPCookie *cookie in cookies ?: @[]) {
        if (NTFCookieMatchesURL(cookie, mediaURL)) {
            [NSHTTPCookieStorage.sharedHTTPCookieStorage setCookie:cookie];
        }
    }

    if ([self.kind isEqualToString:@"hls"] ||
        [[mediaURL.pathExtension lowercaseString] isEqualToString:@"m3u8"]) {
        [self startHLSDownload:mediaURL headers:headers];
    } else {
        [self startDirectDownload:mediaURL headers:headers];
    }
}

- (void)startDownloadWithMessage:(NSDictionary *)message
                         webView:(WKWebView *)webView
                       frameInfo:(WKFrameInfo *)frameInfo {
    self.webView = webView;
    self.frameInfo = frameInfo;
    if (self.activeTask != nil || self.exportSession != nil) {
        [self sendStatus:@{
            @"status": @"downloading",
            @"message": @"已有一个 iPad 下载任务正在进行",
            @"progress": @0
        }];
        return;
    }
    WKHTTPCookieStore *cookieStore = webView.configuration.websiteDataStore.httpCookieStore;
    if (cookieStore == nil) {
        NSArray *cookies = [NSHTTPCookieStorage.sharedHTTPCookieStorage cookiesForURL:
            [NSURL URLWithString:message[@"url"] ?: @""]];
        [self beginWithMessage:message cookies:cookies ?: @[]];
        return;
    }
    [cookieStore getAllCookies:^(NSArray<NSHTTPCookie *> *cookies) {
        [self beginWithMessage:message cookies:cookies ?: @[]];
    }];
}

- (void)URLSession:(NSURLSession *)session
      downloadTask:(NSURLSessionDownloadTask *)downloadTask
      didWriteData:(int64_t)bytesWritten
 totalBytesWritten:(int64_t)totalBytesWritten
 totalBytesExpectedToWrite:(int64_t)totalBytesExpectedToWrite {
    (void)bytesWritten;
    if (session != self.directSession || totalBytesExpectedToWrite <= 0) return;
    double percent = MIN(99.0, MAX(0.0,
        (double)totalBytesWritten * 100.0 / (double)totalBytesExpectedToWrite));
    [self sendStatus:@{
        @"status": @"downloading",
        @"message": @"正在下载到 iPad…",
        @"progress": @(percent)
    }];
}

- (void)URLSession:(NSURLSession *)session
      downloadTask:(NSURLSessionDownloadTask *)downloadTask
 didFinishDownloadingToURL:(NSURL *)location {
    if (session != self.directSession) return;
    NSString *extension = downloadTask.response.suggestedFilename.pathExtension.lowercaseString;
    if (extension.length == 0) extension = downloadTask.originalRequest.URL.pathExtension.lowercaseString;
    NSSet *allowed = [NSSet setWithArray:@[@"mp4", @"m4v", @"mov", @"webm", @"mkv", @"mp3", @"m4a", @"aac"]];
    if (![allowed containsObject:extension]) extension = @"mp4";
    NSURL *destination = NTFUniqueOutputURL(self.title, extension);
    NSError *moveError = nil;
    if (destination == nil ||
        ![NSFileManager.defaultManager moveItemAtURL:location toURL:destination error:&moveError]) {
        [self failWithMessage:moveError.localizedDescription ?: @"无法把视频保存到“文件”App"];
        return;
    }
    [self finishAtURL:destination];
    [self.directSession finishTasksAndInvalidate];
    self.directSession = nil;
}

- (void)URLSession:(NSURLSession *)session
 assetDownloadTask:(AVAssetDownloadTask *)assetDownloadTask
 didLoadTimeRange:(CMTimeRange)timeRange
 totalTimeRangesLoaded:(NSArray<NSValue *> *)loadedTimeRanges
 timeRangeExpectedToLoad:(CMTimeRange)timeRangeExpectedToLoad {
    (void)timeRange;
    if (session != self.assetSession) return;
    double expected = CMTimeGetSeconds(timeRangeExpectedToLoad.duration);
    double loaded = 0.0;
    for (NSValue *value in loadedTimeRanges) {
        loaded += CMTimeGetSeconds(value.CMTimeRangeValue.duration);
    }
    double percent = expected > 0.0 ? MIN(99.0, MAX(0.0, loaded * 100.0 / expected)) : 0.0;
    [self sendStatus:@{
        @"status": @"downloading",
        @"message": @"正在下载 HLS 视频到 iPad…",
        @"progress": @(percent)
    }];
}

- (void)URLSession:(NSURLSession *)session
 assetDownloadTask:(AVAssetDownloadTask *)assetDownloadTask
 didFinishDownloadingToURL:(NSURL *)location {
    (void)assetDownloadTask;
    if (session == self.assetSession) self.assetLocation = location;
}

- (void)URLSession:(NSURLSession *)session
 assetDownloadTask:(AVAssetDownloadTask *)assetDownloadTask
 willDownloadToURL:(NSURL *)location API_AVAILABLE(ios(18.0)) {
    (void)assetDownloadTask;
    if (session == self.assetSession) self.assetLocation = location;
}

- (void)exportDownloadedHLS {
    NSURL *location = self.assetLocation;
    if (location == nil) {
        [self failWithMessage:@"HLS 下载完成，但系统没有返回离线文件位置"];
        return;
    }
    AVURLAsset *localAsset = [AVURLAsset URLAssetWithURL:location options:nil];
    AVAssetExportSession *exportSession = [AVAssetExportSession
        exportSessionWithAsset:localAsset
        presetName:AVAssetExportPresetPassthrough
    ];
    if (exportSession == nil) {
        [self failWithMessage:@"iPad 无法把离线 HLS 整理成视频文件"];
        return;
    }
    NSString *extension = [exportSession.supportedFileTypes containsObject:AVFileTypeMPEG4]
        ? @"mp4"
        : @"mov";
    AVFileType outputType = [extension isEqualToString:@"mp4"]
        ? AVFileTypeMPEG4
        : AVFileTypeQuickTimeMovie;
    NSURL *destination = NTFUniqueOutputURL(self.title, extension);
    if (destination == nil) {
        [self failWithMessage:@"无法打开 iPad 的 Documents/VidCatch 文件夹"];
        return;
    }
    exportSession.outputURL = destination;
    exportSession.outputFileType = outputType;
    exportSession.shouldOptimizeForNetworkUse = YES;
    self.exportSession = exportSession;
    self.activeTask = nil;
    [self sendStatus:@{
        @"status": @"probing",
        @"message": @"下载完成，正在整理为可在“文件”中打开的视频…",
        @"progress": @99
    }];
    [exportSession exportAsynchronouslyWithCompletionHandler:^{
        dispatch_async(dispatch_get_main_queue(), ^{
            if (exportSession.status == AVAssetExportSessionStatusCompleted) {
                [self finishAtURL:destination];
            } else {
                [self failWithMessage:exportSession.error.localizedDescription ?:
                    @"HLS 已下载，但无法整理成 MP4/MOV 文件"];
            }
            [self.assetSession finishTasksAndInvalidate];
            self.assetSession = nil;
        });
    }];
}

- (void)URLSession:(NSURLSession *)session
              task:(NSURLSessionTask *)task
didCompleteWithError:(NSError *)error {
    if (session == self.directSession) {
        if (error != nil && task == self.activeTask) {
            [self failWithMessage:error.localizedDescription ?: @"iPad 直链下载失败"];
            [self.directSession finishTasksAndInvalidate];
            self.directSession = nil;
        }
        return;
    }
    if (session == self.assetSession && task == self.activeTask) {
        if (error != nil) {
            [self failWithMessage:error.localizedDescription ?: @"iPad HLS 下载失败"];
            [self.assetSession finishTasksAndInvalidate];
            self.assetSession = nil;
        } else {
            [self exportDownloadedHLS];
        }
    }
}

@end

@implementation NTFMediaBridge

+ (instancetype)sharedBridge {
    static NTFMediaBridge *bridge;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        bridge = [[self alloc] init];
    });
    return bridge;
}

- (instancetype)init {
    self = [super init];
    if (self != nil) {
        _paused = YES;
        _defaultPlaybackRate = 1.0;
        _rate = 1.0f;
        _seekableTimeRanges = @[];
        [self installRemoteCommands];
    }
    return self;
}

- (void)installRemoteCommands {
    MPRemoteCommandCenter *commands = MPRemoteCommandCenter.sharedCommandCenter;
    commands.playCommand.enabled = YES;
    commands.pauseCommand.enabled = YES;
    commands.togglePlayPauseCommand.enabled = YES;
    commands.changePlaybackPositionCommand.enabled = YES;

    __weak typeof(self) weakSelf = self;
    [commands.playCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *event) {
        (void)event;
        [weakSelf sendCommand:@"play" value:nil];
        return weakSelf.activeWebView != nil
            ? MPRemoteCommandHandlerStatusSuccess
            : MPRemoteCommandHandlerStatusNoActionableNowPlayingItem;
    }];
    [commands.pauseCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *event) {
        (void)event;
        [weakSelf sendCommand:@"pause" value:nil];
        return weakSelf.activeWebView != nil
            ? MPRemoteCommandHandlerStatusSuccess
            : MPRemoteCommandHandlerStatusNoActionableNowPlayingItem;
    }];
    [commands.togglePlayPauseCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *event) {
        (void)event;
        [weakSelf sendCommand:@"toggle" value:nil];
        return weakSelf.activeWebView != nil
            ? MPRemoteCommandHandlerStatusSuccess
            : MPRemoteCommandHandlerStatusNoActionableNowPlayingItem;
    }];
    [commands.changePlaybackPositionCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *event) {
        if (![event isKindOfClass:MPChangePlaybackPositionCommandEvent.class]) {
            return MPRemoteCommandHandlerStatusCommandFailed;
        }
        NSTimeInterval position = ((MPChangePlaybackPositionCommandEvent *)event).positionTime;
        [weakSelf sendCommand:@"seek" value:@(position)];
        return weakSelf.activeWebView != nil
            ? MPRemoteCommandHandlerStatusSuccess
            : MPRemoteCommandHandlerStatusNoActionableNowPlayingItem;
    }];
}

- (void)sendCommand:(NSString *)command value:(NSNumber *)value {
    dispatch_async(dispatch_get_main_queue(), ^{
        WKWebView *webView = self.activeWebView;
        if (webView == nil) return;
        NSDictionary *payload = @{
            @"__newtTouchBarCommand": @YES,
            @"command": command,
            @"value": value ?: NSNull.null
        };
        NSData *data = [NSJSONSerialization dataWithJSONObject:payload options:0 error:nil];
        NSString *json = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        NSString *script = [NSString stringWithFormat:
            @"(function(){var d=%@;function s(w){try{w.postMessage(d,'*');for(var i=0;i<w.frames.length;i++)s(w.frames[i]);}catch(e){try{w.postMessage(d,'*');}catch(x){}}}s(window);})();",
            json
        ];
        [webView evaluateJavaScript:script completionHandler:nil];
    });
}

// Safari's macOS WebKit does not build its media Touch Bar from ordinary
// NSSliderTouchBarItems. It supplies a WebPlaybackControlsManager-compatible
// object to AVTouchBarPlaybackControlsProvider. The methods below mirror that
// adapter so AVKit itself creates and drives the exact system control surface.

+ (NSSet<NSString *> *)keyPathsForValuesAffectingContentDuration {
    return [NSSet setWithObjects:@"duration", @"seekableTimeRanges", nil];
}

+ (NSSet<NSString *> *)keyPathsForValuesAffectingPlaying {
    return [NSSet setWithObject:@"paused"];
}

+ (NSSet<NSString *> *)keyPathsForValuesAffectingCanSeek {
    return [NSSet setWithObjects:@"duration", @"seekableTimeRanges", nil];
}

+ (NSSet<NSString *> *)keyPathsForValuesAffectingCanBeginTouchBarScrubbing {
    return [NSSet setWithObjects:@"duration", @"seekableTimeRanges", nil];
}

+ (NSSet<NSString *> *)keyPathsForValuesAffectingPictureInPictureActive {
    return [NSSet setWithObject:@"pictureInPicture"];
}

+ (NSSet<NSString *> *)keyPathsForValuesAffectingCanTogglePictureInPicture {
    return [NSSet setWithObject:@"pictureInPictureAvailable"];
}

+ (NSSet<NSString *> *)keyPathsForValuesAffectingAllowsPictureInPicturePlayback {
    return [NSSet setWithObject:@"pictureInPictureAvailable"];
}

- (id)newAVValueTimingWithValue:(double)value rate:(double)rate {
    if (!NTFLoadMacAVKit()) return nil;
    Class timingClass = NSClassFromString(@"AVValueTiming");
    NSTimeInterval timeStamp = NSProcessInfo.processInfo.systemUptime;
    return ((id (*)(id, SEL, double, double, double))objc_msgSend)(
        [timingClass alloc],
        NSSelectorFromString(@"initWithAnchorValue:anchorTimeStamp:rate:"),
        value,
        timeStamp,
        rate
    );
}

- (void)refreshAVKitTimingWithRate:(double)rate {
    self.rate = (float)rate;
    self.timing = [self newAVValueTimingWithValue:self.elapsed rate:rate];
    if (self.duration > 0.0 && isfinite(self.duration)) {
        CMTime durationTime = CMTimeMakeWithSeconds(self.duration, 1000);
        self.seekableTimeRanges = @[
            [NSValue valueWithCMTimeRange:CMTimeRangeMake(kCMTimeZero, durationTime)]
        ];
    } else {
        self.seekableTimeRanges = @[];
    }
}

- (NSTimeInterval)contentDuration {
    return self.seekableTimeRanges.count > 0 ? self.duration : INFINITY;
}

- (NSTimeInterval)contentDurationWithinEndTimes {
    return [self contentDuration];
}

- (BOOL)isPlaying {
    return !self.paused;
}

- (void)setPlaying:(BOOL)playing {
    if (playing == [self isPlaying]) return;
    self.paused = !playing;
    [self refreshAVKitTimingWithRate:playing ? MAX(self.defaultPlaybackRate, 0.1) : 0.0];
    [self sendCommand:playing ? @"play" : @"pause" value:nil];
}

- (void)togglePlayback {
    [self setPlaying:self.paused];
}

- (void)togglePlayback:(id)sender {
    (void)sender;
    [self togglePlayback];
}

- (BOOL)canTogglePlayback {
    return self.activeWebView != nil;
}

- (BOOL)canSeek {
    return self.duration > 0.0 && isfinite(self.duration);
}

- (BOOL)isSeeking {
    return NO;
}

- (BOOL)isCompletelySeekable {
    return [self canSeek];
}

- (BOOL)hasSeekableLiveStreamingContent {
    return NO;
}

- (BOOL)hasLiveStreamingContent {
    return NO;
}

- (NSTimeInterval)minTime {
    return 0.0;
}

- (NSTimeInterval)maxTime {
    return self.duration;
}

- (id)minTiming {
    return [self newAVValueTimingWithValue:0.0 rate:0.0];
}

- (id)maxTiming {
    return [self newAVValueTimingWithValue:self.duration rate:0.0];
}

- (NSTimeInterval)seekToTime {
    return self.elapsed;
}

- (void)setSeekToTime:(NSTimeInterval)time {
    [self seekToTime:time toleranceBefore:0.0 toleranceAfter:0.0];
}

- (void)seekToTime:(NSTimeInterval)time
    toleranceBefore:(NSTimeInterval)toleranceBefore
    toleranceAfter:(NSTimeInterval)toleranceAfter {
    (void)toleranceBefore;
    (void)toleranceAfter;
    if (!isfinite(time) || ![self canSeek]) return;
    self.elapsed = MIN(MAX(time, 0.0), self.duration);
    [self refreshAVKitTimingWithRate:self.paused ? 0.0 : MAX(self.defaultPlaybackRate, 0.1)];
    [self sendCommand:@"seek" value:@(self.elapsed)];
}

- (BOOL)canBeginTouchBarScrubbing {
    return [self canSeek] && isfinite([self contentDuration]);
}

- (void)beginTouchBarScrubbing {
}

- (void)endTouchBarScrubbing {
}

- (BOOL)hasEnabledAudio {
    return YES;
}

- (BOOL)hasEnabledVideo {
    return YES;
}

- (id)currentAudioTrack {
    return nil;
}

- (id)audioWaveform {
    return nil;
}

- (void)cancelThumbnailAndAudioAmplitudeSampleGeneration {
}

- (void)cancelThumbnailGeneration {
}

- (void)cancelThumbnailGenerationForRequestType:(NSInteger)requestType {
    (void)requestType;
}

- (void)generateTouchBarThumbnailsForTimes:(NSArray *)thumbnailTimes
    tolerance:(NSTimeInterval)tolerance
    size:(CGSize)size
    thumbnailHandler:(void (^)(NSArray *, BOOL))thumbnailHandler {
    (void)thumbnailTimes;
    (void)tolerance;
    (void)size;
    if (thumbnailHandler != nil) thumbnailHandler(@[], YES);
}

- (void)generateTouchBarThumbnailsForTimes:(NSArray *)thumbnailTimes
    tolerance:(NSTimeInterval)tolerance
    size:(CGSize)size
    requestType:(NSInteger)requestType
    thumbnailHandler:(id)thumbnailHandler {
    (void)thumbnailTimes;
    (void)tolerance;
    (void)size;
    (void)requestType;
    (void)thumbnailHandler;
}

- (void)generateTouchBarAudioAmplitudeSamples:(NSInteger)numberOfSamples
    completionHandler:(void (^)(NSArray *))completionHandler {
    (void)numberOfSamples;
    if (completionHandler != nil) completionHandler(@[]);
}

- (NSArray *)audioTouchBarMediaSelectionOptions {
    return @[];
}

- (NSArray *)legibleTouchBarMediaSelectionOptions {
    return @[];
}

- (id)currentAudioTouchBarMediaSelectionOption {
    return nil;
}

- (id)currentLegibleTouchBarMediaSelectionOption {
    return nil;
}

- (void)setCurrentAudioTouchBarMediaSelectionOption:(id)option {
    (void)option;
}

- (void)setCurrentLegibleTouchBarMediaSelectionOption:(id)option {
    (void)option;
}

- (BOOL)hasTouchBarMediaSelectionOptions {
    return NO;
}

- (BOOL)hasAudioTouchBarMediaSelectionOptions {
    return NO;
}

- (BOOL)hasLegibleTouchBarMediaSelectionOptions {
    return NO;
}

- (BOOL)allowsPictureInPicturePlayback {
    return self.pictureInPictureAvailable;
}

- (BOOL)isPictureInPictureActive {
    return self.pictureInPicture;
}

- (void)setPictureInPictureActive:(BOOL)active {
    if (active != self.pictureInPicture) [self sendCommand:@"pip" value:nil];
}

- (BOOL)canTogglePictureInPicture {
    return self.pictureInPictureAvailable;
}

- (void)togglePictureInPicture {
    if (self.pictureInPictureAvailable) [self sendCommand:@"pip" value:nil];
}

- (void)togglePictureInPicture:(id)sender {
    (void)sender;
    [self togglePictureInPicture];
}

- (void)skipBackwardThirtySeconds:(id)sender {
    (void)sender;
    [self seekToTime:self.elapsed - 30.0 toleranceBefore:0.0 toleranceAfter:0.0];
}

- (void)gotoEndOfSeekableRanges:(id)sender {
    (void)sender;
    [self seekToTime:self.duration toleranceBefore:0.0 toleranceAfter:0.0];
}

- (BOOL)canScanForward {
    return NO;
}

- (BOOL)canScanBackward {
    return NO;
}

- (void)scanForward:(id)sender {
    (void)sender;
}

- (void)scanBackward:(id)sender {
    (void)sender;
}

- (void)controlsViewWillAppear {
}

- (void)controlsViewDidDisappear {
}

- (NSURL *)assetURL {
    return nil;
}

- (BOOL)installSafariTouchBarIfAvailable {
    if (!NTFLoadMacAVKit()) return NO;

    Protocol *controllerProtocol = objc_getProtocol("AVTouchBarPlaybackControlsControlling");
    if (controllerProtocol != nil) class_addProtocol(self.class, controllerProtocol);

    Class providerClass = NSClassFromString(@"AVTouchBarPlaybackControlsProvider");
    id provider = [[providerClass alloc] init];
    SEL controllerSelector = NSSelectorFromString(@"setPlaybackControlsController:");
    if (provider == nil || ![provider respondsToSelector:controllerSelector]) return NO;
    NTFSendObject(provider, controllerSelector, self);

    id touchBar = NTFGetObject(provider, NSSelectorFromString(@"touchBar"));
    Class applicationClass = NSClassFromString(@"NSApplication");
    if (touchBar == nil || applicationClass == Nil) return NO;

    id application = NTFGetObject(applicationClass, NSSelectorFromString(@"sharedApplication"));
    id window = NTFGetObject(application, NSSelectorFromString(@"keyWindow"));
    if (window == nil) {
        NSArray *windows = NTFGetObject(application, NSSelectorFromString(@"windows"));
        window = windows.firstObject;
    }
    if (window == nil || ![window respondsToSelector:NSSelectorFromString(@"setTouchBar:")]) {
        NTFSendObject(provider, controllerSelector, nil);
        return NO;
    }

    self.previousTouchBar = [window respondsToSelector:NSSelectorFromString(@"touchBar")]
        ? NTFGetObject(window, NSSelectorFromString(@"touchBar"))
        : nil;
    self.touchBarProvider = provider;
    self.touchBar = touchBar;
    self.touchBarWindow = window;
    [self installSafariFullscreenItemIfNeeded];
    [self updateSafariEscapeKey];
    NTFSendObject(window, NSSelectorFromString(@"setTouchBar:"), touchBar);
    os_log(OS_LOG_DEFAULT, "[NewTWebFixV8] Safari AVKit Touch Bar provider installed");
    return YES;
}

- (void)installSafariFullscreenItemIfNeeded {
    if (self.touchBarProvider == nil || self.touchBar == nil ||
        self.touchBarFullscreenItem != nil) return;

    Class buttonItemClass = NSClassFromString(@"NSButtonTouchBarItem");
    if (buttonItemClass == Nil) return;
    NSString *identifier = @"com.newt66y.touchbar.fullscreen-toggle";
    id item = NTFCreateTouchBarButton(
        buttonItemClass,
        identifier,
        NTFImageNamed(@"NSTouchBarEnterFullScreenTemplate"),
        self,
        @selector(touchBarFullscreenPressed:)
    );
    if (item == nil) return;
    NTFSendObject(item, NSSelectorFromString(@"setCustomizationLabel:"), @"全屏/退出全屏");

    NSSet *existingTemplateItems = [self.touchBar respondsToSelector:NSSelectorFromString(@"templateItems")]
        ? NTFGetObject(self.touchBar, NSSelectorFromString(@"templateItems"))
        : nil;
    NSMutableSet *templateItems = existingTemplateItems != nil
        ? [existingTemplateItems mutableCopy]
        : [NSMutableSet set];
    [templateItems addObject:item];
    NTFSendObject(self.touchBar, NSSelectorFromString(@"setTemplateItems:"), templateItems);

    NSArray *existingIdentifiers = [self.touchBar respondsToSelector:NSSelectorFromString(@"defaultItemIdentifiers")]
        ? NTFGetObject(self.touchBar, NSSelectorFromString(@"defaultItemIdentifiers"))
        : nil;
    NSMutableArray *identifiers = existingIdentifiers != nil
        ? [existingIdentifiers mutableCopy]
        : [NSMutableArray array];
    if (![identifiers containsObject:identifier]) [identifiers addObject:identifier];
    NTFSendObject(self.touchBar, NSSelectorFromString(@"setDefaultItemIdentifiers:"), identifiers);

    self.touchBarFullscreenItem = item;
    [self updateFullscreenButton];
}

- (void)installTouchBarIfNeeded {
    if (self.touchBar != nil) return;
    if (![self installSafariTouchBarIfAvailable]) {
        [self installFallbackTouchBarIfNeeded];
        os_log_error(OS_LOG_DEFAULT, "[NewTWebFixV8] AVKit provider unavailable; using fallback");
    }
}

- (void)installFallbackTouchBarIfNeeded {
    if (self.touchBar != nil) return;

    Class touchBarClass = NSClassFromString(@"NSTouchBar");
    Class sliderItemClass = NSClassFromString(@"NSSliderTouchBarItem");
    Class buttonItemClass = NSClassFromString(@"NSButtonTouchBarItem");
    Class applicationClass = NSClassFromString(@"NSApplication");
    if (touchBarClass == Nil || sliderItemClass == Nil ||
        buttonItemClass == Nil || applicationClass == Nil) return;

    id application = NTFGetObject(applicationClass, NSSelectorFromString(@"sharedApplication"));
    id window = NTFGetObject(application, NSSelectorFromString(@"keyWindow"));
    if (window == nil) {
        NSArray *windows = NTFGetObject(application, NSSelectorFromString(@"windows"));
        window = windows.firstObject;
    }
    if (window == nil || ![window respondsToSelector:NSSelectorFromString(@"setTouchBar:")]) return;

    NSString *fullscreenIdentifier = @"com.newt66y.touchbar.fullscreen-toggle";
    NSString *playIdentifier = @"com.newt66y.touchbar.play-pause";
    NSString *sliderIdentifier = @"com.newt66y.touchbar.video-scrubber";
    NSString *pipIdentifier = @"com.newt66y.touchbar.picture-in-picture";
    id touchBar = [[touchBarClass alloc] init];
    id sliderItem = ((id (*)(id, SEL, id))objc_msgSend)(
        [sliderItemClass alloc],
        NSSelectorFromString(@"initWithIdentifier:"),
        sliderIdentifier
    );
    NTFSendObject(sliderItem, NSSelectorFromString(@"setLabel:"), nil);
    NTFSendObject(sliderItem, NSSelectorFromString(@"setCustomizationLabel:"), @"\u89c6\u9891\u65f6\u95f4\u8f74");
    NTFSendObject(sliderItem, NSSelectorFromString(@"setTarget:"), self);
    ((void (*)(id, SEL, SEL))objc_msgSend)(
        sliderItem,
        NSSelectorFromString(@"setAction:"),
        @selector(touchBarSliderChanged:)
    );
    NTFSendDouble(sliderItem, NSSelectorFromString(@"setMinimumSliderWidth:"), 360.0);
    NTFSendDouble(sliderItem, NSSelectorFromString(@"setMaximumSliderWidth:"), 720.0);

    id slider = NTFGetObject(sliderItem, NSSelectorFromString(@"slider"));
    NTFSendDouble(slider, NSSelectorFromString(@"setMinValue:"), 0.0);
    NTFSendDouble(slider, NSSelectorFromString(@"setMaxValue:"), MAX(self.duration, 1.0));
    NTFSendDouble(slider, NSSelectorFromString(@"setDoubleValue:"), self.elapsed);
    NTFSendBool(slider, NSSelectorFromString(@"setContinuous:"), YES);

    id playItem = NTFCreateTouchBarButton(
        buttonItemClass,
        playIdentifier,
        NTFImageNamed(@"NSTouchBarPlayTemplate"),
        self,
        @selector(touchBarPlayPausePressed:)
    );
    NTFSendObject(playItem, NSSelectorFromString(@"setCustomizationLabel:"), @"\u64ad\u653e/\u6682\u505c");

    id pipItem = NTFCreateTouchBarButton(
        buttonItemClass,
        pipIdentifier,
        NTFSymbolImage(@"pip.enter", @"NSTouchBarEnterFullScreenTemplate"),
        self,
        @selector(touchBarPictureInPicturePressed:)
    );
    NTFSendObject(pipItem, NSSelectorFromString(@"setCustomizationLabel:"), @"\u753b\u4e2d\u753b");

    id fullscreenItem = NTFCreateTouchBarButton(
        buttonItemClass,
        fullscreenIdentifier,
        NTFImageNamed(@"NSTouchBarEnterFullScreenTemplate"),
        self,
        @selector(touchBarFullscreenPressed:)
    );
    NTFSendObject(fullscreenItem, NSSelectorFromString(@"setCustomizationLabel:"), @"\u5168\u5c4f/\u9000\u51fa\u5168\u5c4f");

    NSMutableSet *templateItems = [NSMutableSet setWithObject:sliderItem];
    if (playItem != nil) [templateItems addObject:playItem];
    if (pipItem != nil) [templateItems addObject:pipItem];
    if (fullscreenItem != nil) [templateItems addObject:fullscreenItem];
    NTFSendObject(touchBar, NSSelectorFromString(@"setTemplateItems:"), templateItems);
    NTFSendObject(touchBar, NSSelectorFromString(@"setPrincipalItemIdentifier:"), sliderIdentifier);

    self.previousTouchBar = [window respondsToSelector:NSSelectorFromString(@"touchBar")]
        ? NTFGetObject(window, NSSelectorFromString(@"touchBar"))
        : nil;
    self.touchBar = touchBar;
    self.touchBarSliderItem = sliderItem;
    self.touchBarSlider = slider;
    self.touchBarPlayPauseItem = playItem;
    self.touchBarPictureInPictureItem = pipItem;
    self.touchBarFullscreenItem = fullscreenItem;
    self.touchBarWindow = window;
    [self updateTouchBarControls];
    NTFSendObject(window, NSSelectorFromString(@"setTouchBar:"), touchBar);
    os_log(OS_LOG_DEFAULT, "[NewTWebFixV8] fallback Touch Bar media controls installed");
}

- (void)updateSafariEscapeKey {
    if (self.touchBarProvider == nil || self.touchBar == nil) return;
    SEL escapeSelector = NSSelectorFromString(@"setEscapeKeyReplacementItem:");
    if (![self.touchBar respondsToSelector:escapeSelector]) return;

    if (!self.fullscreen) {
        NTFSendObject(self.touchBar, escapeSelector, nil);
        self.touchBarExitFullscreenItem = nil;
        return;
    }
    if (self.touchBarExitFullscreenItem == nil) {
        Class itemClass = NSClassFromString(@"NSCustomTouchBarItem");
        Class buttonClass = NSClassFromString(@"NSButton");
        id image = NTFImageNamed(@"NSTouchBarExitFullScreenTemplate");
        if (itemClass == Nil || buttonClass == Nil || image == nil) return;

        id item = ((id (*)(id, SEL, id))objc_msgSend)(
            [itemClass alloc],
            NSSelectorFromString(@"initWithIdentifier:"),
            @"WKMediaExitFullScreenItem"
        );
        NTFSendBool(image, NSSelectorFromString(@"setTemplate:"), YES);
        id button = ((id (*)(id, SEL, id, id, id, SEL))objc_msgSend)(
            buttonClass,
            NSSelectorFromString(@"buttonWithTitle:image:target:action:"),
            @"",
            image,
            self,
            @selector(touchBarExitFullscreenPressed:)
        );
        if (item == nil || button == nil) return;
        NTFSendObject(button, NSSelectorFromString(@"setAccessibilityTitle:"), @"退出全屏");
        id widthAnchor = NTFGetObject(button, NSSelectorFromString(@"widthAnchor"));
        if ([widthAnchor respondsToSelector:NSSelectorFromString(@"constraintLessThanOrEqualToConstant:")]) {
            id constraint = ((id (*)(id, SEL, double))objc_msgSend)(
                widthAnchor,
                NSSelectorFromString(@"constraintLessThanOrEqualToConstant:"),
                64.0
            );
            NTFSendBool(constraint, NSSelectorFromString(@"setActive:"), YES);
        }
        NTFSendObject(item, NSSelectorFromString(@"setView:"), button);
        self.touchBarExitFullscreenItem = item;
    }
    NTFSendObject(self.touchBar, escapeSelector, self.touchBarExitFullscreenItem);
}

- (void)updateTouchBarControls {
    [self updateFullscreenButton];
    // The AVKit provider owns the identifiers, imagery and layout. Mutating its
    // NSTouchBar here would turn the native Safari bar back into the V5 replica.
    if (self.touchBarProvider != nil) return;
    if (self.touchBar == nil) return;

    id playImage = NTFImageNamed(
        self.paused ? @"NSTouchBarPlayTemplate" : @"NSTouchBarPauseTemplate"
    );
    if (playImage != nil) {
        NTFSendObject(self.touchBarPlayPauseItem, NSSelectorFromString(@"setImage:"), playImage);
    }

    id pipImage = NTFSymbolImage(
        self.pictureInPicture ? @"pip.exit" : @"pip.enter",
        self.pictureInPicture
            ? @"NSTouchBarExitFullScreenTemplate"
            : @"NSTouchBarEnterFullScreenTemplate"
    );
    if (pipImage != nil) {
        NTFSendObject(
            self.touchBarPictureInPictureItem,
            NSSelectorFromString(@"setImage:"),
            pipImage
        );
    }

    NSMutableArray<NSString *> *identifiers = [NSMutableArray array];
    if (self.touchBarPlayPauseItem != nil) {
        [identifiers addObject:@"com.newt66y.touchbar.play-pause"];
    }
    [identifiers addObject:@"com.newt66y.touchbar.video-scrubber"];
    if (self.pictureInPictureAvailable && self.touchBarPictureInPictureItem != nil) {
        [identifiers addObject:@"com.newt66y.touchbar.picture-in-picture"];
    }
    if (self.touchBarFullscreenItem != nil) {
        [identifiers addObject:@"com.newt66y.touchbar.fullscreen-toggle"];
    }
    NTFSendObject(
        self.touchBar,
        NSSelectorFromString(@"setDefaultItemIdentifiers:"),
        identifiers
    );
}

- (void)updateFullscreenButton {
    if (self.touchBarFullscreenItem == nil) return;
    id image = NTFImageNamed(
        self.fullscreen
            ? @"NSTouchBarExitFullScreenTemplate"
            : @"NSTouchBarEnterFullScreenTemplate"
    );
    if (image != nil) {
        NTFSendObject(self.touchBarFullscreenItem, NSSelectorFromString(@"setImage:"), image);
    }
}

- (void)touchBarPlayPausePressed:(id)sender {
    (void)sender;
    self.paused = !self.paused;
    [self updateTouchBarControls];
    [self sendCommand:@"toggle" value:nil];
}

- (void)touchBarPictureInPicturePressed:(id)sender {
    (void)sender;
    [self sendCommand:@"pip" value:nil];
}

- (void)touchBarFullscreenPressed:(id)sender {
    (void)sender;
    [self sendCommand:@"fullscreen" value:nil];
}

- (void)touchBarExitFullscreenPressed:(id)sender {
    (void)sender;
    [self sendCommand:@"exitFullscreen" value:nil];
}

- (void)touchBarSliderChanged:(id)sender {
    double value = NTFGetDouble(sender, NSSelectorFromString(@"doubleValue"));
    self.elapsed = value;
    [self sendCommand:@"seek" value:@(value)];
    [self publishNowPlayingTitle:nil rate:self.paused ? 0.0 : 1.0];
}

- (void)publishNowPlayingTitle:(NSString *)title rate:(double)rate {
    if (self.duration <= 0.0) return;
    NSMutableDictionary *info = [NSMutableDictionary dictionary];
    info[MPMediaItemPropertyTitle] = title.length > 0 ? title : @"\u5c0f\u8349\u89c6\u9891";
    info[MPMediaItemPropertyPlaybackDuration] = @(self.duration);
    info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = @(self.elapsed);
    info[MPNowPlayingInfoPropertyPlaybackRate] = @(rate);
    info[MPNowPlayingInfoPropertyDefaultPlaybackRate] = @1.0;
    info[MPNowPlayingInfoPropertyMediaType] = @(MPNowPlayingInfoMediaTypeVideo);
    info[MPNowPlayingInfoPropertyPlaybackProgress] = @(MIN(MAX(self.elapsed / self.duration, 0.0), 1.0));
    MPNowPlayingInfoCenter.defaultCenter.nowPlayingInfo = info;
    MPNowPlayingInfoCenter.defaultCenter.playbackState = self.paused
        ? MPNowPlayingPlaybackStatePaused
        : MPNowPlayingPlaybackStatePlaying;
}

- (void)userContentController:(WKUserContentController *)userContentController
      didReceiveScriptMessage:(WKScriptMessage *)message {
    if (![message.body isKindOfClass:NSDictionary.class]) return;
    NSDictionary *body = (NSDictionary *)message.body;
    NSString *type = [body[@"type"] isKindOfClass:NSString.class] ? body[@"type"] : @"";
    if ([type isEqualToString:@"download"]) {
        if (NTFIsMacRuntime()) {
            [NTFVidCatchManager.sharedManager
                startDownloadWithMessage:body
                webView:message.webView
                frameInfo:message.frameInfo
            ];
        } else {
            [NTFiPadDownloadManager.sharedManager
                startDownloadWithMessage:body
                webView:message.webView
                frameInfo:message.frameInfo
            ];
        }
        return;
    }
    if ([type isEqualToString:@"clear"]) {
        if (message.webView == self.activeWebView) [self clear];
        return;
    }
    if (![type isEqualToString:@"state"]) return;

    double duration = [body[@"duration"] doubleValue];
    double elapsed = [body[@"currentTime"] doubleValue];
    if (!isfinite(duration) || !isfinite(elapsed) || duration <= 0.0) return;

    self.activeWebView = message.webView;
    self.duration = duration;
    self.elapsed = MIN(MAX(elapsed, 0.0), duration);
    self.paused = [body[@"paused"] boolValue];
    self.pictureInPicture = [body[@"pip"] boolValue];
    self.pictureInPictureAvailable = [body[@"pipAvailable"] boolValue];
    self.fullscreen = [body[@"fullscreen"] boolValue];
    double playbackRate = MAX([body[@"rate"] doubleValue], 0.0);
    if (playbackRate > 0.0) self.defaultPlaybackRate = playbackRate;
    double rate = self.paused ? 0.0 : playbackRate;
    NSString *title = [body[@"title"] isKindOfClass:NSString.class] ? body[@"title"] : nil;

    dispatch_async(dispatch_get_main_queue(), ^{
        [self refreshAVKitTimingWithRate:rate];
        [self installTouchBarIfNeeded];
        [self updateSafariEscapeKey];
        NTFSendDouble(self.touchBarSlider, NSSelectorFromString(@"setMaxValue:"), self.duration);
        NTFSendDouble(self.touchBarSlider, NSSelectorFromString(@"setDoubleValue:"), self.elapsed);
        [self updateTouchBarControls];
        [self publishNowPlayingTitle:title rate:rate];
    });
}

- (void)clear {
    dispatch_async(dispatch_get_main_queue(), ^{
        MPNowPlayingInfoCenter.defaultCenter.nowPlayingInfo = nil;
        MPNowPlayingInfoCenter.defaultCenter.playbackState = MPNowPlayingPlaybackStateStopped;
        if (self.touchBarWindow != nil &&
            [self.touchBarWindow respondsToSelector:NSSelectorFromString(@"setTouchBar:")]) {
            NTFSendObject(
                self.touchBarWindow,
                NSSelectorFromString(@"setTouchBar:"),
                self.previousTouchBar
            );
        }
        if (self.touchBarProvider != nil &&
            [self.touchBarProvider respondsToSelector:NSSelectorFromString(@"setPlaybackControlsController:")]) {
            NTFSendObject(
                self.touchBarProvider,
                NSSelectorFromString(@"setPlaybackControlsController:"),
                nil
            );
        }
        self.activeWebView = nil;
        self.touchBar = nil;
        self.touchBarProvider = nil;
        self.timing = nil;
        self.seekableTimeRanges = @[];
        self.touchBarSliderItem = nil;
        self.touchBarSlider = nil;
        self.touchBarPlayPauseItem = nil;
        self.touchBarPictureInPictureItem = nil;
        self.touchBarFullscreenItem = nil;
        self.touchBarExitFullscreenItem = nil;
        self.touchBarWindow = nil;
        self.previousTouchBar = nil;
        self.duration = 0.0;
        self.elapsed = 0.0;
        self.rate = 1.0f;
        self.defaultPlaybackRate = 1.0;
        self.paused = YES;
        self.pictureInPicture = NO;
        self.pictureInPictureAvailable = NO;
        self.fullscreen = NO;
    });
}

@end

@interface NTFTrackpadBackController : NSObject <UIGestureRecognizerDelegate>
@property(nonatomic, strong) id eventMonitor;
@property(nonatomic) NSTimeInterval lastBackTime;
@property(nonatomic) double horizontalScrollAccumulator;
@property(nonatomic) BOOL horizontalScrollTriggered;
+ (instancetype)sharedController;
- (void)installMacTrackpadMonitor;
- (void)installGestureOnWebView:(WKWebView *)webView;
@end

static UIViewController *NTFTopViewController(UIViewController *controller) {
    if (controller == nil) return nil;
    UIViewController *presented = controller.presentedViewController;
    if (presented != nil && !presented.isBeingDismissed) {
        return NTFTopViewController(presented);
    }
    if ([controller isKindOfClass:UINavigationController.class]) {
        return NTFTopViewController(((UINavigationController *)controller).topViewController);
    }
    if ([controller isKindOfClass:UITabBarController.class]) {
        return NTFTopViewController(((UITabBarController *)controller).selectedViewController);
    }
    return controller;
}

static WKWebView *NTFFindWebView(UIView *view) {
    if ([view isKindOfClass:WKWebView.class]) return (WKWebView *)view;
    for (UIView *subview in view.subviews) {
        WKWebView *found = NTFFindWebView(subview);
        if (found != nil) return found;
    }
    return nil;
}

@implementation NTFTrackpadBackController

+ (instancetype)sharedController {
    static NTFTrackpadBackController *controller;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        controller = [[self alloc] init];
    });
    return controller;
}

- (BOOL)performBackFromWebView:(WKWebView *)sourceWebView {
    NSTimeInterval now = NSProcessInfo.processInfo.systemUptime;
    if (now - self.lastBackTime < 0.65) return YES;

    UIWindow *window = nil;
    for (UIWindow *candidate in UIApplication.sharedApplication.windows) {
        if (candidate.isKeyWindow) {
            window = candidate;
            break;
        }
        if (window == nil && !candidate.hidden && candidate.alpha > 0.0) {
            window = candidate;
        }
    }
    UIViewController *top = NTFTopViewController(window.rootViewController);
    WKWebView *webView = sourceWebView ?: NTFFindWebView(top.view);
    if (webView.canGoBack) {
        self.lastBackTime = now;
        [webView goBack];
        os_log(OS_LOG_DEFAULT, "[NewTWebFixV8] trackpad gesture: web history back");
        return YES;
    }

    UINavigationController *navigation = top.navigationController;
    if (navigation != nil && navigation.viewControllers.count > 1) {
        self.lastBackTime = now;
        [navigation popViewControllerAnimated:YES];
        os_log(OS_LOG_DEFAULT, "[NewTWebFixV8] trackpad gesture: navigation pop");
        return YES;
    }

    UIViewController *dismissTarget = navigation ?: top;
    if (dismissTarget.presentingViewController != nil) {
        self.lastBackTime = now;
        if ([NSStringFromClass(top.class) containsString:@"NTFBrowserController"]) {
            HyaaBrowserVisible = NO;
            [NTFMediaBridge.sharedBridge clear];
        }
        [dismissTarget dismissViewControllerAnimated:YES completion:nil];
        os_log(OS_LOG_DEFAULT, "[NewTWebFixV8] trackpad gesture: modal dismiss");
        return YES;
    }
    return NO;
}

- (void)trackpadSwipeRecognized:(UISwipeGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateRecognized) return;
    [self performBackFromWebView:[gesture.view isKindOfClass:WKWebView.class]
        ? (WKWebView *)gesture.view
        : nil];
}

- (void)installGestureOnWebView:(WKWebView *)webView {
    if (webView == nil || objc_getAssociatedObject(webView, NTFTrackpadGestureInstalledKey) != nil) {
        return;
    }
    // Own both horizontal directions so a literal left swipe and the standard
    // left-edge/right swipe both mean Back rather than accidentally going Forward.
    for (NSNumber *direction in @[@(UISwipeGestureRecognizerDirectionLeft),
                                   @(UISwipeGestureRecognizerDirectionRight)]) {
        UISwipeGestureRecognizer *gesture = [[UISwipeGestureRecognizer alloc]
            initWithTarget:self
            action:@selector(trackpadSwipeRecognized:)
        ];
        gesture.direction = direction.unsignedIntegerValue;
        gesture.cancelsTouchesInView = NO;
        gesture.delegate = self;
        [webView addGestureRecognizer:gesture];
    }
    webView.allowsBackForwardNavigationGestures = NO;
    objc_setAssociatedObject(
        webView,
        NTFTrackpadGestureInstalledKey,
        @YES,
        OBJC_ASSOCIATION_RETAIN_NONATOMIC
    );
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer
    shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    (void)gestureRecognizer;
    (void)otherGestureRecognizer;
    return YES;
}

- (void)installMacTrackpadMonitor {
    if (self.eventMonitor != nil) return;
    dlopen("/System/Library/Frameworks/AppKit.framework/AppKit", RTLD_LAZY | RTLD_LOCAL);
    Class eventClass = NSClassFromString(@"NSEvent");
    SEL selector = NSSelectorFromString(@"addLocalMonitorForEventsMatchingMask:handler:");
    if (eventClass == Nil || ![eventClass respondsToSelector:selector]) return;

    __weak typeof(self) weakSelf = self;
    id (^handler)(id) = ^id(id event) {
        NTFTrackpadBackController *strongSelf = weakSelf;
        if (strongSelf == nil) return event;
        NSUInteger eventType = [event respondsToSelector:NSSelectorFromString(@"type")]
            ? NTFGetUnsignedInteger(event, NSSelectorFromString(@"type"))
            : 0;

        if (eventType == 31) { // NSEventTypeSwipe
            double deltaX = NTFGetDouble(event, NSSelectorFromString(@"deltaX"));
            double deltaY = NTFGetDouble(event, NSSelectorFromString(@"deltaY"));
            if (fabs(deltaX) > fabs(deltaY) && fabs(deltaX) >= 0.5 &&
                [strongSelf performBackFromWebView:nil]) {
                return nil;
            }
            return event;
        }

        if (eventType == 22) { // NSEventTypeScrollWheel: two-finger page swipe.
            NSUInteger phase = [event respondsToSelector:NSSelectorFromString(@"phase")]
                ? NTFGetUnsignedInteger(event, NSSelectorFromString(@"phase"))
                : 0;
            const NSUInteger beganOrMayBegin = (1u << 0) | (1u << 5);
            const NSUInteger endedOrCancelled = (1u << 3) | (1u << 4);
            if ((phase & beganOrMayBegin) != 0) {
                strongSelf.horizontalScrollAccumulator = 0.0;
                strongSelf.horizontalScrollTriggered = NO;
            }

            double deltaX = NTFGetDouble(event, NSSelectorFromString(@"scrollingDeltaX"));
            double deltaY = NTFGetDouble(event, NSSelectorFromString(@"scrollingDeltaY"));
            if ([event respondsToSelector:NSSelectorFromString(@"isDirectionInvertedFromDevice")] &&
                NTFGetBool(event, NSSelectorFromString(@"isDirectionInvertedFromDevice"))) {
                deltaX = -deltaX;
                deltaY = -deltaY;
            }
            if (phase != 0 && fabs(deltaX) > fabs(deltaY) * 1.8) {
                strongSelf.horizontalScrollAccumulator += deltaX;
            }

            // A deliberate physical swipe to the left. UI swipe recognizers
            // below also accept the standard left-edge/right-back direction.
            if (!strongSelf.horizontalScrollTriggered &&
                strongSelf.horizontalScrollAccumulator <= -160.0 &&
                [strongSelf performBackFromWebView:nil]) {
                strongSelf.horizontalScrollTriggered = YES;
            }
            BOOL swallow = strongSelf.horizontalScrollTriggered;
            if ((phase & endedOrCancelled) != 0) {
                strongSelf.horizontalScrollAccumulator = 0.0;
                strongSelf.horizontalScrollTriggered = NO;
            }
            return swallow ? nil : event;
        }
        return event;
    };
    const NSUInteger swipeEventMask = ((NSUInteger)1 << 31);
    const NSUInteger scrollWheelEventMask = ((NSUInteger)1 << 22);
    self.eventMonitor = ((id (*)(id, SEL, NSUInteger, id))objc_msgSend)(
        eventClass,
        selector,
        swipeEventMask | scrollWheelEventMask,
        handler
    );
    if (self.eventMonitor != nil) {
        os_log(OS_LOG_DEFAULT, "[NewTWebFixV8] native trackpad swipe monitor installed");
    }
}

@end

typedef WKWebView * _Nullable (*WKInitIMP)(
    id,
    SEL,
    CGRect,
    WKWebViewConfiguration *
);

static WKInitIMP OriginalWKWebViewInit = NULL;

static WKWebView * _Nullable PatchedWKWebViewInit(
    id self,
    SEL command,
    CGRect frame,
    WKWebViewConfiguration *configuration
) {
    WKUserContentController *controller = configuration.userContentController;
    if (controller != nil &&
        objc_getAssociatedObject(controller, NTFMediaScriptInstalledKey) == nil) {
        [controller addScriptMessageHandler:NTFMediaBridge.sharedBridge name:NTFMediaMessageName];
        NSString *bridgeSource = [NTFVideoBridgeScript()
            stringByAppendingString:NTFVidCatchBridgeScript()
        ];
        WKUserScript *script = [[WKUserScript alloc]
            initWithSource:bridgeSource
            injectionTime:WKUserScriptInjectionTimeAtDocumentEnd
            forMainFrameOnly:NO
        ];
        [controller addUserScript:script];
        objc_setAssociatedObject(
            controller,
            NTFMediaScriptInstalledKey,
            @YES,
            OBJC_ASSOCIATION_RETAIN_NONATOMIC
        );
    }
    WKWebView *webView = OriginalWKWebViewInit(self, command, frame, configuration);
    [NTFTrackpadBackController.sharedController installGestureOnWebView:webView];
    return webView;
}

static void InstallWKWebViewMediaHook(void) {
    Method method = class_getInstanceMethod(
        WKWebView.class,
        @selector(initWithFrame:configuration:)
    );
    if (method == NULL) {
        os_log_error(OS_LOG_DEFAULT, "[NewTWebFixV8] WKWebView initializer missing");
        return;
    }
    OriginalWKWebViewInit = (WKInitIMP)method_setImplementation(
        method,
        (IMP)PatchedWKWebViewInit
    );
    os_log(OS_LOG_DEFAULT, "[NewTWebFixV8] HTML5 video media bridge installed");
}

@interface NTFBrowserController : UIViewController <WKNavigationDelegate, WKUIDelegate>
@property(nonatomic, strong) NSURL *initialURL;
@property(nonatomic, strong) WKWebView *webView;
@property(nonatomic, strong) UIBarButtonItem *backItem;
- (instancetype)initWithURL:(NSURL *)url;
@end

@implementation NTFBrowserController

- (instancetype)initWithURL:(NSURL *)url {
    self = [super initWithNibName:nil bundle:nil];
    if (self != nil) {
        _initialURL = url;
        self.title = @"外部链接";
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.systemBackgroundColor;

    WKWebViewConfiguration *configuration = [[WKWebViewConfiguration alloc] init];
    WKWebView *webView = [[WKWebView alloc] initWithFrame:CGRectZero configuration:configuration];
    webView.translatesAutoresizingMaskIntoConstraints = NO;
    webView.navigationDelegate = self;
    webView.UIDelegate = self;
    webView.allowsBackForwardNavigationGestures = NO;
    self.webView = webView;
    [self.view addSubview:webView];

    [NSLayoutConstraint activateConstraints:@[
        [webView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [webView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [webView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [webView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
    ]];

    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc]
        initWithTitle:@"关闭"
        style:UIBarButtonItemStylePlain
        target:self
        action:@selector(closeBrowser)
    ];
    self.backItem = [[UIBarButtonItem alloc]
        initWithTitle:@"后退"
        style:UIBarButtonItemStylePlain
        target:self
        action:@selector(goBack)
    ];
    self.backItem.enabled = NO;
    self.navigationItem.rightBarButtonItem = self.backItem;

    [webView loadRequest:[NSURLRequest requestWithURL:self.initialURL]];
}

- (void)closeBrowser {
    HyaaBrowserVisible = NO;
    [NTFMediaBridge.sharedBridge clear];
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)goBack {
    if (self.webView.canGoBack) {
        [self.webView goBack];
    }
}

- (void)updateNavigationButtons {
    self.backItem.enabled = self.webView.canGoBack;
    NSString *title = self.webView.title;
    self.title = title.length > 0 ? title : @"外部链接";
}

- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
    [self updateNavigationButtons];
}

- (void)webView:(WKWebView *)webView
    didFailNavigation:(WKNavigation *)navigation
    withError:(NSError *)error {
    [self updateNavigationButtons];
}

- (void)webView:(WKWebView *)webView
    didFailProvisionalNavigation:(WKNavigation *)navigation
    withError:(NSError *)error {
    [self updateNavigationButtons];
}

- (WKWebView *)webView:(WKWebView *)webView
    createWebViewWithConfiguration:(WKWebViewConfiguration *)configuration
    forNavigationAction:(WKNavigationAction *)navigationAction
    windowFeatures:(WKWindowFeatures *)windowFeatures {
    // Keep any further target="_blank" navigation inside this isolated browser.
    if (navigationAction.targetFrame == nil && navigationAction.request.URL != nil) {
        [webView loadRequest:navigationAction.request];
    }
    return nil;
}

@end

static BOOL IsHyaaURL(NSURL *url) {
    NSString *host = url.host.lowercaseString;
    return [host isEqualToString:@"hyaa20.com"] || [host hasSuffix:@".hyaa20.com"];
}

static BOOL PresentHyaaBrowser(id owner, NSURL *url, NSString *source) {
    UIViewController *presenter = [owner isKindOfClass:UIViewController.class]
        ? (UIViewController *)owner
        : nil;
    if (presenter == nil) {
        return NO;
    }
    if (HyaaBrowserVisible) {
        return YES;
    }
    if (presenter.presentedViewController != nil) {
        return NO;
    }

    HyaaBrowserVisible = YES;
    os_log_with_type(
        OS_LOG_DEFAULT,
        OS_LOG_TYPE_DEFAULT,
        "[NewTWebFixV8] %{public}@ intercepted: %{public}@",
        source,
        url.absoluteString
    );
    NTFBrowserController *browser = [[NTFBrowserController alloc] initWithURL:url];
    UINavigationController *navigation = [[UINavigationController alloc]
        initWithRootViewController:browser
    ];
    navigation.modalPresentationStyle = UIModalPresentationFullScreen;
    dispatch_async(dispatch_get_main_queue(), ^{
        [presenter presentViewController:navigation animated:YES completion:nil];
    });
    return YES;
}

static SEL CreateWebViewSelector(void) {
    return NSSelectorFromString(
        @"webView:createWebViewWithConfiguration:forNavigationAction:windowFeatures:"
    );
}

static SEL DecidePolicySelector(void) {
    return NSSelectorFromString(
        @"webView:decidePolicyForNavigationAction:decisionHandler:"
    );
}

static CreateWebViewIMP OriginalOpenThreadCreate = NULL;
static DecidePolicyIMP OriginalOpenThreadPolicy = NULL;

static WKWebView * _Nullable PatchedOpenThreadCreate(
    id self,
    SEL command,
    WKWebView *webView,
    WKWebViewConfiguration *configuration,
    WKNavigationAction *navigationAction,
    WKWindowFeatures *windowFeatures
) {
    NSURL *url = navigationAction.request.URL;
    if (navigationAction.targetFrame == nil &&
        IsHyaaURL(url) &&
        PresentHyaaBrowser(self, url, @"createWebView")) {
        return nil;
    }

    // Every non-hyaa20 link follows the stock 2.3.7 implementation.  This is
    // important because the app creates its own OpenOutside controller and
    // owns the back stack for ordinary links such as yuese99.com.
    if (OriginalOpenThreadCreate != NULL) {
        return OriginalOpenThreadCreate(
            self,
            command,
            webView,
            configuration,
            navigationAction,
            windowFeatures
        );
    }
    return nil;
}

static void PatchedOpenThreadPolicy(
    id self,
    SEL command,
    WKWebView *webView,
    WKNavigationAction *navigationAction,
    void (^decisionHandler)(WKNavigationActionPolicy)
) {
    NSURL *url = navigationAction.request.URL;
    if (IsHyaaURL(url) && PresentHyaaBrowser(self, url, @"decidePolicy")) {
        // Cancel the stock same-frame navigation before OpenThread can alter
        // or pop its own controller under PlayCover.
        decisionHandler(WKNavigationActionPolicyCancel);
        return;
    }

    if (OriginalOpenThreadPolicy != NULL) {
        OriginalOpenThreadPolicy(self, command, webView, navigationAction, decisionHandler);
        return;
    }
    decisionHandler(WKNavigationActionPolicyAllow);
}

static BOOL InstallOpenThreadHook(void) {
    Class cls = NSClassFromString(@"NewT66y.OpenThread");
    if (cls == Nil) {
        return NO;
    }

    Method createMethod = class_getInstanceMethod(cls, CreateWebViewSelector());
    Method policyMethod = class_getInstanceMethod(cls, DecidePolicySelector());
    if (createMethod == NULL || policyMethod == NULL) {
        os_log_error(OS_LOG_DEFAULT, "[NewTWebFixV8] OpenThread navigation method missing");
        return YES;
    }

    IMP createReplacement = (IMP)PatchedOpenThreadCreate;
    if (method_getImplementation(createMethod) != createReplacement) {
        OriginalOpenThreadCreate = (CreateWebViewIMP)method_setImplementation(
            createMethod,
            createReplacement
        );
    }

    IMP policyReplacement = (IMP)PatchedOpenThreadPolicy;
    if (method_getImplementation(policyMethod) != policyReplacement) {
        OriginalOpenThreadPolicy = (DecidePolicyIMP)method_setImplementation(
            policyMethod,
            policyReplacement
        );
    }
    os_log(OS_LOG_DEFAULT, "[NewTWebFixV8] installed hyaa20 create + policy hooks");
    return YES;
}

static void TryInstallHook(NSUInteger attempt) {
    if (!InstallOpenThreadHook() && attempt < 20) {
        dispatch_after(
            dispatch_time(DISPATCH_TIME_NOW, (int64_t)(250 * NSEC_PER_MSEC)),
            dispatch_get_main_queue(),
            ^{
                TryInstallHook(attempt + 1);
            }
        );
    }
}

__attribute__((constructor))
static void NewTWebFixV8Initialize(void) {
    InstallWKWebViewMediaHook();
    dispatch_async(dispatch_get_main_queue(), ^{
        [NTFTrackpadBackController.sharedController installMacTrackpadMonitor];
        TryInstallHook(0);
    });
}
