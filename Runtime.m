#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <WebKit/WebKit.h>
#import <objc/runtime.h>

static NSString * const kAddSpeedHackVersion = @"1.2.0";
static NSString * const kAddSpeedHackLogDirectory = @"AddSpeedHackLogs";
static NSString * const kAddSpeedHackLogPrefix = @"addspeedhack_v1.2";

static dispatch_queue_t AddSpeedHackLogQueue(void)
{
    static dispatch_queue_t queue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        queue = dispatch_queue_create("com.addspeedhack.log", DISPATCH_QUEUE_SERIAL);
    });
    return queue;
}

static NSString *AddSpeedHackLogDirectoryPath(void)
{
    NSArray<NSString *> *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documents = paths.firstObject;
    if (documents.length == 0) return nil;
    return [documents stringByAppendingPathComponent:kAddSpeedHackLogDirectory];
}

static NSString *AddSpeedHackCounterPath(void)
{
    NSString *directory = AddSpeedHackLogDirectoryPath();
    return directory.length ? [directory stringByAppendingPathComponent:@".addspeedhack_v1.2_counter"] : nil;
}

static NSUInteger AddSpeedHackNextLogNumber(void)
{
    NSString *counterPath = AddSpeedHackCounterPath();
    NSUInteger last = 0;
    if (counterPath.length) {
        NSString *s = [NSString stringWithContentsOfFile:counterPath encoding:NSUTF8StringEncoding error:nil];
        last = (NSUInteger)MAX(0, s.integerValue);
    }
    NSUInteger next = last + 1;
    [[NSString stringWithFormat:@"%lu", (unsigned long)next]
        writeToFile:counterPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
    return next;
}

static NSString *AddSpeedHackNewLogPath(void)
{
    NSString *directory = AddSpeedHackLogDirectoryPath();
    if (directory.length == 0) return nil;

    [[NSFileManager defaultManager] createDirectoryAtPath:directory
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];

    NSUInteger number = AddSpeedHackNextLogNumber();
    NSString *name = [NSString stringWithFormat:@"%@-%lu.jsonl",
                      kAddSpeedHackLogPrefix, (unsigned long)number];
    return [directory stringByAppendingPathComponent:name];
}

static NSString *gAddSpeedHackActiveLogPath = nil;
static NSTimeInterval gAddSpeedHackLastActivity = 0;
static const NSTimeInterval kAddSpeedHackAdGapSeconds = 4.0;

static void AddSpeedHackPruneNumberedLogs(void)
{
    NSString *directory = AddSpeedHackLogDirectoryPath();
    NSArray<NSString *> *files = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:directory error:nil];
    if (!files) return;

    NSRegularExpression *rx =
        [NSRegularExpression regularExpressionWithPattern:@"^addspeedhack_v1\\.2-(\\d+)\\.jsonl$"
                                                  options:0 error:nil];
    NSMutableArray<NSDictionary *> *numbered = [NSMutableArray array];

    for (NSString *name in files) {
        NSTextCheckingResult *m = [rx firstMatchInString:name options:0 range:NSMakeRange(0, name.length)];
        if (!m || m.numberOfRanges < 2) continue;
        NSString *n = [name substringWithRange:[m rangeAtIndex:1]];
        [numbered addObject:@{@"name": name, @"number": @([n integerValue])}];
    }

    [numbered sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return [a[@"number"] compare:b[@"number"]];
    }];

    while (numbered.count > 10) {
        NSString *name = numbered.firstObject[@"name"];
        [[NSFileManager defaultManager] removeItemAtPath:[directory stringByAppendingPathComponent:name] error:nil];
        [numbered removeObjectAtIndex:0];
    }
}

static NSString *AddSpeedHackEnsureActiveLogPath(BOOL beginNewAd)
{
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    BOOL activeMissing = (gAddSpeedHackActiveLogPath.length > 0 &&
                          ![[NSFileManager defaultManager] fileExistsAtPath:gAddSpeedHackActiveLogPath]);

    if (activeMissing) gAddSpeedHackActiveLogPath = nil;

    if (beginNewAd &&
        gAddSpeedHackActiveLogPath.length > 0 &&
        gAddSpeedHackLastActivity > 0 &&
        (now - gAddSpeedHackLastActivity) >= kAddSpeedHackAdGapSeconds) {
        gAddSpeedHackActiveLogPath = nil;
    }

    if (gAddSpeedHackActiveLogPath.length == 0) {
        gAddSpeedHackActiveLogPath = AddSpeedHackNewLogPath();
        AddSpeedHackPruneNumberedLogs();
    }

    gAddSpeedHackLastActivity = now;
    return gAddSpeedHackActiveLogPath;
}
static NSString *AddSpeedHackTimestamp(void)
{
    static NSISO8601DateFormatter *formatter;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        formatter = [[NSISO8601DateFormatter alloc] init];
        formatter.formatOptions = NSISO8601DateFormatWithInternetDateTime | NSISO8601DateFormatWithFractionalSeconds;
    });
    return [formatter stringFromDate:[NSDate date]];
}

static void AddSpeedHackWriteLogInternal(NSDictionary *fields, BOOL beginNewAd)
{
    if (![fields isKindOfClass:[NSDictionary class]]) return;

    NSMutableDictionary *record = [NSMutableDictionary dictionaryWithDictionary:fields];
    record[@"timestamp"] = AddSpeedHackTimestamp();
    record[@"version"] = kAddSpeedHackVersion;

    NSString *bundleID = NSBundle.mainBundle.bundleIdentifier;
    if (bundleID.length > 0) record[@"bundle_id"] = bundleID;

    NSString *processName = NSProcessInfo.processInfo.processName;
    if (processName.length > 0) record[@"process"] = processName;

    dispatch_async(AddSpeedHackLogQueue(), ^{
        @autoreleasepool {
            NSError *jsonError = nil;
            NSData *json = [NSJSONSerialization dataWithJSONObject:record options:0 error:&jsonError];
            if (!json || jsonError) return;

            NSString *path = AddSpeedHackEnsureActiveLogPath(beginNewAd);
            if (path.length == 0) return;

            NSString *directory = [path stringByDeletingLastPathComponent];
            NSError *directoryError = nil;
            [[NSFileManager defaultManager] createDirectoryAtPath:directory
                                      withIntermediateDirectories:YES
                                                       attributes:nil
                                                            error:&directoryError];
            if (directoryError) return;

            NSMutableData *line = [NSMutableData dataWithData:json];
            const char newline = '\n';
            [line appendBytes:&newline length:1];

            if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
                [line writeToFile:path atomically:YES];
                return;
            }

            NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:path];
            if (!handle) return;

            @try {
                [handle seekToEndOfFile];
                [handle writeData:line];
                [handle closeFile];
            } @catch (__unused NSException *exception) {
                @try { [handle closeFile]; } @catch (__unused NSException *closeException) {}
            }
        }
    });
}


static void AddSpeedHackWriteLog(NSDictionary *fields)
{
    AddSpeedHackWriteLogInternal(fields, NO);
}

static void AddSpeedHackBeginAdLog(NSDictionary *fields)
{
    AddSpeedHackWriteLogInternal(fields, YES);
}

static const float kAVPlayerMultiplier = 600.0f;
static const double kHTML5PlaybackRate = 16.0;
static const double kVideoSeekStep = 0.75;
static const double kVideoSeekIntervalMs = 100.0;
static const double kPlayableTimerSpeed = 8.0;
static const BOOL kEnablePlayableCanvasPoke = YES;
static const double kPlayablePokeDelayMs = 1800.0;

static const NSTimeInterval kProbeDelays[] = {
    0.0, 0.5, 1.0, 2.0, 3.0, 5.0, 8.0, 12.0, 18.0, 25.0
};
static const NSUInteger kProbeDelayCount =
    sizeof(kProbeDelays) / sizeof(kProbeDelays[0]);

static NSString *AdSpeedHTML5Script(void)
{
    return [NSString stringWithFormat:
        @"(function(){"
        "try{"
        "var VIDEO_RATE=%0.3f;"
        "var SEEK_STEP=%0.3f;"
        "var SEEK_INTERVAL=%0.3f;"
        "var TIMER_SPEED=%0.3f;"
        "var ENABLE_POKE=%@;"
        "var POKE_DELAY=%0.3f;"
        "var KEY='__adspeed_runtime_v2';"

        "function isVideo(v){"
        "return !!v && String(v.tagName).toUpperCase()==='VIDEO';"
        "}"

        "function applyVideo(v){"
        "if(!isVideo(v))return;"
        "try{v.defaultPlaybackRate=VIDEO_RATE;}catch(e){}"
        "try{"
        "if(Math.abs((v.playbackRate||1)-VIDEO_RATE)>0.001){"
        "v.playbackRate=VIDEO_RATE;"
        "}"
        "}catch(e){}"
        "}"

        "function scan(root){"
        "try{"
        "if(!root)return;"
        "if(root.nodeType===1 && isVideo(root))applyVideo(root);"
        "if(root.querySelectorAll){"
        "var vs=root.querySelectorAll('video');"
        "for(var i=0;i<vs.length;i++)applyVideo(vs[i]);"
        "}"
        "}catch(e){}"
        "}"

        "function installVideoSeekBoost(){"
        "if(window.__adspeed_seek_timer)return;"
        "window.__adspeed_seek_timer=window.setInterval(function(){"
        "try{"
        "var vs=document.querySelectorAll('video');"
        "for(var i=0;i<vs.length;i++){"
        "var v=vs[i];"
        "if(v.paused||v.ended)continue;"
        "if(!isFinite(v.duration)||v.duration<=0)continue;"
        "var safeEnd=Math.max(0,v.duration-0.35);"
        "if(v.currentTime>=safeEnd)continue;"
        "var next=Math.min(v.currentTime+SEEK_STEP,safeEnd);"
        "if(next>v.currentTime)v.currentTime=next;"
        "}"
        "}catch(e){}"
        "},SEEK_INTERVAL);"
        "}"

        "function installTimerAcceleration(){"
        "if(window.__adspeed_timers_installed)return;"
        "window.__adspeed_timers_installed=true;"
        "var nativeSetTimeout=window.setTimeout.bind(window);"
        "var nativeSetInterval=window.setInterval.bind(window);"
        "window.__adspeed_nativeSetTimeout=nativeSetTimeout;"
        "window.__adspeed_nativeSetInterval=nativeSetInterval;"

        "window.setTimeout=function(fn,delay){"
        "var args=Array.prototype.slice.call(arguments,2);"
        "var d=Number(delay);"
        "if(!isFinite(d))d=0;"
        "if(d>20)d=Math.max(4,d/TIMER_SPEED);"
        "return nativeSetTimeout(function(){"
        "if(typeof fn==='function')return fn.apply(window,args);"
        "try{return (0,eval)(String(fn));}catch(e){}"
        "},d);"
        "};"

        "window.setInterval=function(fn,delay){"
        "var args=Array.prototype.slice.call(arguments,2);"
        "var d=Number(delay);"
        "if(!isFinite(d))d=0;"
        "if(d>20)d=Math.max(8,d/TIMER_SPEED);"
        "return nativeSetInterval(function(){"
        "if(typeof fn==='function')return fn.apply(window,args);"
        "try{return (0,eval)(String(fn));}catch(e){}"
        "},d);"
        "};"
        "}"

        "function findPlayableCanvas(){"
        "try{"
        "var cs=document.querySelectorAll('canvas');"
        "var best=null,bestArea=0;"
        "for(var i=0;i<cs.length;i++){"
        "var c=cs[i];"
        "var r=c.getBoundingClientRect();"
        "var area=Math.max(0,r.width)*Math.max(0,r.height);"
        "if(area>bestArea && r.width>=120 && r.height>=120){"
        "best=c;bestArea=area;"
        "}"
        "}"
        "return best;"
        "}catch(e){return null;}"
        "}"

        "function pokePlayableCanvas(){"
        "if(!ENABLE_POKE||window.__adspeed_canvas_poked)return;"
        "try{"
        "if(document.querySelector('video'))return;"
        "var c=findPlayableCanvas();"
        "if(!c)return;"
        "window.__adspeed_canvas_poked=true;"
        "var r=c.getBoundingClientRect();"
        "var x=r.left+r.width*0.5;"
        "var y=r.top+r.height*0.5;"
        "var common={bubbles:true,cancelable:true,clientX:x,clientY:y,screenX:x,screenY:y};"
        "try{c.dispatchEvent(new PointerEvent('pointerdown',Object.assign({pointerId:1,pointerType:'touch',isPrimary:true},common)));}catch(e){}"
        "try{c.dispatchEvent(new MouseEvent('mousedown',common));}catch(e){}"
        "try{c.dispatchEvent(new PointerEvent('pointerup',Object.assign({pointerId:1,pointerType:'touch',isPrimary:true},common)));}catch(e){}"
        "try{c.dispatchEvent(new MouseEvent('mouseup',common));}catch(e){}"
        "try{c.dispatchEvent(new MouseEvent('click',common));}catch(e){}"
        "}catch(e){}"
        "}"

        "if(!window[KEY]){"
        "window[KEY]=true;"
        "installTimerAcceleration();"
        "installVideoSeekBoost();"

        "var events=['play','playing','loadedmetadata','loadeddata','canplay','canplaythrough'];"
        "for(var i=0;i<events.length;i++){"
        "document.addEventListener(events[i],function(e){applyVideo(e.target);},true);"
        "}"

        "document.addEventListener('ratechange',function(e){"
        "var v=e.target;"
        "if(!isVideo(v))return;"
        "try{"
        "if(Math.abs((v.playbackRate||1)-VIDEO_RATE)>0.001){"
        "var st=window.__adspeed_nativeSetTimeout||window.setTimeout;"
        "st(function(){applyVideo(v);},0);"
        "}"
        "}catch(err){}"
        "},true);"

        "try{"
        "new MutationObserver(function(records){"
        "for(var i=0;i<records.length;i++){"
        "var nodes=records[i].addedNodes||[];"
        "for(var j=0;j<nodes.length;j++)scan(nodes[j]);"
        "}"
        "}).observe(document.documentElement||document,{childList:true,subtree:true});"
        "}catch(e){}"

        "window.__adspeed_scan=function(){scan(document);};"
        "var st=window.__adspeed_nativeSetTimeout||window.setTimeout;"
        "st(pokePlayableCanvas,POKE_DELAY);"
        "}"

        "if(window.__adspeed_scan)window.__adspeed_scan();"
        "return true;"
        "}catch(e){"
        "return false;"
        "}"
        "})();",
        kHTML5PlaybackRate,
        kVideoSeekStep,
        kVideoSeekIntervalMs,
        kPlayableTimerSpeed,
        kEnablePlayableCanvasPoke ? @"true" : @"false",
        kPlayablePokeDelayMs
    ];
}

static NSString *AdSpeedDiagnosticScript(void)
{
    return @"(function(){"
    "try{"
    "var videos=[];"
    "var vs=document.querySelectorAll('video');"
    "for(var i=0;i<vs.length;i++){"
    "var v=vs[i];"
    "videos.push({"
    "src:String(v.currentSrc||v.src||''),"
    "duration:(isFinite(v.duration)?Number(v.duration):null),"
    "currentTime:(isFinite(v.currentTime)?Number(v.currentTime):null),"
    "playbackRate:(isFinite(v.playbackRate)?Number(v.playbackRate):null),"
    "paused:!!v.paused,"
    "ended:!!v.ended"
    "});"
    "}"
    "var canvasCount=0;"
    "try{canvasCount=document.querySelectorAll('canvas').length;}catch(e){}"
    "var iframeCount=0;"
    "var iframes=[];"
    "try{"
    "var fs=document.querySelectorAll('iframe');"
    "iframeCount=fs.length;"
    "for(var j=0;j<fs.length;j++){"
    "var f=fs[j],r=null;"
    "try{r=f.getBoundingClientRect();}catch(e){}"
    "var sameOrigin=false,childVideoCount=null,childCanvasCount=null,childIframeCount=null,childURL='';"
    "try{"
    "var d=f.contentDocument;"
    "if(d){"
    "sameOrigin=true;"
    "childVideoCount=d.querySelectorAll('video').length;"
    "childCanvasCount=d.querySelectorAll('canvas').length;"
    "childIframeCount=d.querySelectorAll('iframe').length;"
    "try{childURL=String(f.contentWindow.location.href||'');}catch(e){}"
    "}"
    "}catch(e){}"
    "iframes.push({"
    "src:String(f.src||''),"
    "same_origin:sameOrigin,"
    "child_url:childURL,"
    "child_video_count:childVideoCount,"
    "child_canvas_count:childCanvasCount,"
    "child_iframe_count:childIframeCount,"
    "width:r?Number(r.width):null,"
    "height:r?Number(r.height):null"
    "});"
    "}"
    "}catch(e){}"
    "return {"
    "page_url:String(location.href||''),"
    "video_count:vs.length,"
    "canvas_count:canvasCount,"
    "iframe_count:iframeCount,"
    "iframes:iframes,"
    "videos:videos,"
    "runtime_installed:!!window.__adspeed_runtime_v2,"
    "timer_acceleration_installed:!!window.__adspeed_timers_installed,"
    "video_seek_installed:!!window.__adspeed_seek_timer,"
    "canvas_poke_applied:!!window.__adspeed_canvas_poked"
    "};"
    "}catch(e){return {diagnostic_error:String(e)};}"
    "})();";
}

static const void *kAddSpeedHackWKHandledSurfaceKey = &kAddSpeedHackWKHandledSurfaceKey;
static const void *kAddSpeedHackWKSessionKey = &kAddSpeedHackWKSessionKey;
static const void *kAddSpeedHackAVLoggedKey = &kAddSpeedHackAVLoggedKey;

static void AddSpeedHackProbeWKWebView(WKWebView *webView, NSTimeInterval delay, NSString *sessionID)
{
    if (!webView) return;

    [webView evaluateJavaScript:AdSpeedDiagnosticScript()
              completionHandler:^(id result, NSError *error) {
        NSMutableDictionary *record = [NSMutableDictionary dictionary];
        record[@"event"] = @"wk_probe";
        record[@"probe_delay_seconds"] = @(delay);
        record[@"session_id"] = sessionID ?: @"";

        NSString *currentSessionID = objc_getAssociatedObject(webView, kAddSpeedHackWKSessionKey);
        BOOL isCurrentSession = (sessionID.length > 0 && [currentSessionID isEqualToString:sessionID]);
        record[@"current_navigation_session"] = @(isCurrentSession);

        NSString *nativeURL = webView.URL.absoluteString;
        if (nativeURL.length > 0) record[@"native_page_url"] = nativeURL;

        BOOL knownSurface = NO;
        if ([result isKindOfClass:[NSDictionary class]]) {
            NSDictionary *snapshot = (NSDictionary *)result;
            [record addEntriesFromDictionary:snapshot];

            NSInteger videoCount = [snapshot[@"video_count"] integerValue];
            NSInteger canvasCount = [snapshot[@"canvas_count"] integerValue];
            NSInteger iframeCount = [snapshot[@"iframe_count"] integerValue];
            BOOL runtimeInstalled = [snapshot[@"runtime_installed"] boolValue];
            BOOL canvasPokeApplied = [snapshot[@"canvas_poke_applied"] boolValue];

            record[@"html5_video_detected"] = @(videoCount > 0);
            record[@"html5_acceleration_applied"] = @(videoCount > 0 && runtimeInstalled);
            record[@"canvas_playable_detected"] = @(canvasCount > 0);
            record[@"canvas_processing_applied"] = @(canvasPokeApplied);
            record[@"iframe_detected"] = @(iframeCount > 0);

            knownSurface = (videoCount > 0 || canvasCount > 0);
            record[@"handled_html_surface_detected_this_probe"] = @(knownSurface);
            record[@"iframe_only_candidate"] = @(iframeCount > 0 && videoCount == 0 && canvasCount == 0);

            if (knownSurface && isCurrentSession) {
                objc_setAssociatedObject(webView,
                                         kAddSpeedHackWKHandledSurfaceKey,
                                         @YES,
                                         OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
        } else if (error) {
            record[@"diagnostic_error"] = error.localizedDescription ?: @"unknown";
        }

        record[@"known_surface_detected_this_probe"] = @(knownSurface);
        AddSpeedHackWriteLog(record);

        if (delay >= kProbeDelays[kProbeDelayCount - 1] && isCurrentSession) {
            BOOL everSawHandledSurface = [objc_getAssociatedObject(webView, kAddSpeedHackWKHandledSurfaceKey) boolValue];
            AddSpeedHackWriteLog(@{
                @"event": @"wk_coverage_summary",
                @"session_id": sessionID ?: @"",
                @"native_page_url": nativeURL ?: @"",
                @"handled_html_surface_seen": @(everSawHandledSurface),
                @"no_handled_html_surface_observed": @(!everSawHandledSurface),
                @"note": @"Observation only. This is not a reward-success or reward-failure judgment."
            });
        }
    }];
}

static void InjectIntoWKWebView(WKWebView *webView, NSTimeInterval delay, NSString *sessionID)
{
    if (!webView) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        [webView evaluateJavaScript:AdSpeedHTML5Script()
                  completionHandler:^(__unused id result, __unused NSError *error) {
            AddSpeedHackProbeWKWebView(webView, delay, sessionID);
        }];
    });
}

static void ScheduleWKWebViewInjection(WKWebView *webView)
{
    if (!webView) return;
    __weak WKWebView *weakWebView = webView;

    NSString *sessionID = NSUUID.UUID.UUIDString;
    objc_setAssociatedObject(webView,
                             kAddSpeedHackWKSessionKey,
                             sessionID,
                             OBJC_ASSOCIATION_COPY_NONATOMIC);
    objc_setAssociatedObject(webView,
                             kAddSpeedHackWKHandledSurfaceKey,
                             @NO,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    AddSpeedHackBeginAdLog(@{
        @"event": @"wk_navigation_scheduled",
        @"session_id": sessionID,
        @"native_page_url": webView.URL.absoluteString ?: @""
    });

    for (NSUInteger i = 0; i < kProbeDelayCount; i++) {
        NSTimeInterval delay = kProbeDelays[i];
        dispatch_after(
            dispatch_time(DISPATCH_TIME_NOW,
                          (int64_t)(delay * NSEC_PER_SEC)),
            dispatch_get_main_queue(),
            ^{
                WKWebView *strongWebView = weakWebView;
                if (strongWebView) InjectIntoWKWebView(strongWebView, delay, sessionID);
            }
        );
    }
}

static void SwizzleInstanceMethod(Class cls, SEL originalSEL, SEL replacementSEL)
{
    Method originalMethod = class_getInstanceMethod(cls, originalSEL);
    Method replacementMethod = class_getInstanceMethod(cls, replacementSEL);
    if (!originalMethod || !replacementMethod) return;

    BOOL added = class_addMethod(
        cls,
        originalSEL,
        method_getImplementation(replacementMethod),
        method_getTypeEncoding(replacementMethod)
    );

    if (added) {
        class_replaceMethod(
            cls,
            replacementSEL,
            method_getImplementation(originalMethod),
            method_getTypeEncoding(originalMethod)
        );
    } else {
        method_exchangeImplementations(originalMethod, replacementMethod);
    }
}

@interface AVPlayer (AdSpeedRuntimeV2)
- (void)adspeed_setRate:(float)rate;
- (float)adspeed_rate;
@end

@implementation AVPlayer (AdSpeedRuntimeV2)

- (void)adspeed_setRate:(float)rate
{
    if (rate != 0.0f && ![objc_getAssociatedObject(self, kAddSpeedHackAVLoggedKey) boolValue]) {
        objc_setAssociatedObject(self,
                                 kAddSpeedHackAVLoggedKey,
                                 @YES,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        AddSpeedHackWriteLog(@{
            @"event": @"avplayer_acceleration_applied",
            @"requested_rate": @(rate),
            @"multiplier": @(kAVPlayerMultiplier),
            @"applied_rate": @(rate * kAVPlayerMultiplier)
        });
    }

    [self adspeed_setRate:(rate * kAVPlayerMultiplier)];
}

- (float)adspeed_rate
{
    float originalRate = [self adspeed_rate];
    return originalRate * 0.5f;
}
@end

@interface WKWebView (AdSpeedRuntimeV2)
- (WKNavigation *)adspeed_loadRequest:(NSURLRequest *)request;
- (WKNavigation *)adspeed_loadHTMLString:(NSString *)string baseURL:(NSURL *)baseURL;
- (WKNavigation *)adspeed_loadData:(NSData *)data MIMEType:(NSString *)MIMEType characterEncodingName:(NSString *)characterEncodingName baseURL:(NSURL *)baseURL;
- (WKNavigation *)adspeed_loadFileURL:(NSURL *)URL allowingReadAccessToURL:(NSURL *)readAccessURL;
- (WKNavigation *)adspeed_reload;
- (WKNavigation *)adspeed_reloadFromOrigin;
@end

@implementation WKWebView (AdSpeedRuntimeV2)

- (WKNavigation *)adspeed_loadRequest:(NSURLRequest *)request
{
    WKNavigation *navigation = [self adspeed_loadRequest:request];
    ScheduleWKWebViewInjection(self);
    return navigation;
}

- (WKNavigation *)adspeed_loadHTMLString:(NSString *)string baseURL:(NSURL *)baseURL
{
    WKNavigation *navigation = [self adspeed_loadHTMLString:string baseURL:baseURL];
    ScheduleWKWebViewInjection(self);
    return navigation;
}

- (WKNavigation *)adspeed_loadData:(NSData *)data MIMEType:(NSString *)MIMEType characterEncodingName:(NSString *)characterEncodingName baseURL:(NSURL *)baseURL
{
    WKNavigation *navigation = [self adspeed_loadData:data MIMEType:MIMEType characterEncodingName:characterEncodingName baseURL:baseURL];
    ScheduleWKWebViewInjection(self);
    return navigation;
}

- (WKNavigation *)adspeed_loadFileURL:(NSURL *)URL allowingReadAccessToURL:(NSURL *)readAccessURL
{
    WKNavigation *navigation = [self adspeed_loadFileURL:URL allowingReadAccessToURL:readAccessURL];
    ScheduleWKWebViewInjection(self);
    return navigation;
}

- (WKNavigation *)adspeed_reload
{
    WKNavigation *navigation = [self adspeed_reload];
    ScheduleWKWebViewInjection(self);
    return navigation;
}

- (WKNavigation *)adspeed_reloadFromOrigin
{
    WKNavigation *navigation = [self adspeed_reloadFromOrigin];
    ScheduleWKWebViewInjection(self);
    return navigation;
}
@end

__attribute__((constructor))
static void AdSpeedInit(void)
{
    @autoreleasepool {
        AddSpeedHackWriteLog(@{
            @"event": @"runtime_loaded",
            @"log_file": @"Documents/AddSpeedHackLogs/addspeedhack_v1.2-N.jsonl",
            @"reward_inference_enabled": @NO,
            @"rolling_numbered_logs": @YES,
            @"numbered_logs_kept": @10,
            @"iframe_diagnostics": @"read_only_main_frame_observation"
        });

        Class avPlayerClass = objc_getClass("AVPlayer");
        if (avPlayerClass) {
            SwizzleInstanceMethod(avPlayerClass, @selector(setRate:), @selector(adspeed_setRate:));
            SwizzleInstanceMethod(avPlayerClass, @selector(rate), @selector(adspeed_rate));
        }

        Class wkWebViewClass = objc_getClass("WKWebView");
        if (wkWebViewClass) {
            SwizzleInstanceMethod(wkWebViewClass, @selector(loadRequest:), @selector(adspeed_loadRequest:));
            SwizzleInstanceMethod(wkWebViewClass, @selector(loadHTMLString:baseURL:), @selector(adspeed_loadHTMLString:baseURL:));
            SwizzleInstanceMethod(wkWebViewClass, @selector(loadData:MIMEType:characterEncodingName:baseURL:), @selector(adspeed_loadData:MIMEType:characterEncodingName:baseURL:));
            SwizzleInstanceMethod(wkWebViewClass, @selector(loadFileURL:allowingReadAccessToURL:), @selector(adspeed_loadFileURL:allowingReadAccessToURL:));
            SwizzleInstanceMethod(wkWebViewClass, @selector(reload), @selector(adspeed_reload));
            SwizzleInstanceMethod(wkWebViewClass, @selector(reloadFromOrigin), @selector(adspeed_reloadFromOrigin));
        }
    }
}
