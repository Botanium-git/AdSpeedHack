#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <WebKit/WebKit.h>
#import <objc/runtime.h>

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

static void InjectIntoWKWebView(WKWebView *webView)
{
    if (!webView) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        [webView evaluateJavaScript:AdSpeedHTML5Script()
                  completionHandler:nil];
    });
}

static void ScheduleWKWebViewInjection(WKWebView *webView)
{
    if (!webView) return;
    __weak WKWebView *weakWebView = webView;

    for (NSUInteger i = 0; i < kProbeDelayCount; i++) {
        NSTimeInterval delay = kProbeDelays[i];
        dispatch_after(
            dispatch_time(DISPATCH_TIME_NOW,
                          (int64_t)(delay * NSEC_PER_SEC)),
            dispatch_get_main_queue(),
            ^{
                WKWebView *strongWebView = weakWebView;
                if (strongWebView) InjectIntoWKWebView(strongWebView);
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
