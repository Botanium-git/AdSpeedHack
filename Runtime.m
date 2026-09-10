#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <WebKit/WebKit.h>
#import <objc/runtime.h>

static NSString * const kAddSpeedHackVersion = @"1.7.0";
static NSString * const kAddSpeedHackLogDirectory = @"AdSpeedHackLogs";
static NSString * const kAddSpeedHackVersionDirectory = @"ver.1.7.0";
static NSString * const kAddSpeedHackLogStem = @"ASH_ver.1.7.0_log";
static NSString * const kAddSpeedHackBatchStem = @"ASH_ver.1.7.0_batch";

static dispatch_queue_t AddSpeedHackLogQueue(void)
{
    static dispatch_queue_t queue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        queue = dispatch_queue_create("com.adspeedhack.log", DISPATCH_QUEUE_SERIAL);
    });
    return queue;
}

static NSString *AddSpeedHackRootLogDirectoryPath(void)
{
    NSArray<NSString *> *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documents = paths.firstObject;
    if (documents.length == 0) return nil;
    return [documents stringByAppendingPathComponent:kAddSpeedHackLogDirectory];
}

static NSString *AddSpeedHackLogDirectoryPath(void)
{
    NSString *root = AddSpeedHackRootLogDirectoryPath();
    return root.length ? [root stringByAppendingPathComponent:kAddSpeedHackVersionDirectory] : nil;
}

static NSString *AddSpeedHackArchiveDirectoryPath(void)
{
    NSString *directory = AddSpeedHackLogDirectoryPath();
    return directory.length ? [directory stringByAppendingPathComponent:@"Archive"] : nil;
}

static NSString *AddSpeedHackCounterPath(void)
{
    NSString *directory = AddSpeedHackLogDirectoryPath();
    return directory.length ? [directory stringByAppendingPathComponent:@".last_log_number"] : nil;
}

static NSString *AddSpeedHackBatchCounterPath(void)
{
    NSString *directory = AddSpeedHackArchiveDirectoryPath();
    return directory.length ? [directory stringByAppendingPathComponent:@".last_batch_number"] : nil;
}

static NSString *AddSpeedHackNumberedLogName(NSUInteger number)
{
    return [NSString stringWithFormat:@"%@_%02lu.jsonl", kAddSpeedHackLogStem, (unsigned long)number];
}

static NSString *AddSpeedHackNumberedLogPath(NSUInteger number)
{
    NSString *directory = AddSpeedHackLogDirectoryPath();
    return directory.length ? [directory stringByAppendingPathComponent:AddSpeedHackNumberedLogName(number)] : nil;
}

static NSUInteger AddSpeedHackReadUnsignedCounter(NSString *path)
{
    if (path.length == 0) return 0;
    NSString *s = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
    NSInteger value = s.integerValue;
    return value > 0 ? (NSUInteger)value : 0;
}

static void AddSpeedHackWriteUnsignedCounter(NSString *path, NSUInteger value)
{
    if (path.length == 0) return;
    [[NSString stringWithFormat:@"%lu", (unsigned long)value]
        writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
}

static void AddSpeedHackEnsureLogDirectories(void)
{
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *directory = AddSpeedHackLogDirectoryPath();
    NSString *archive = AddSpeedHackArchiveDirectoryPath();
    if (directory.length) [fm createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:nil];
    if (archive.length) [fm createDirectoryAtPath:archive withIntermediateDirectories:YES attributes:nil error:nil];
}

static void AddSpeedHackPruneArchives(void)
{
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *archive = AddSpeedHackArchiveDirectoryPath();
    NSArray<NSString *> *files = [fm contentsOfDirectoryAtPath:archive error:nil];
    if (!files) return;

    NSString *escaped = [NSRegularExpression escapedPatternForString:kAddSpeedHackBatchStem];
    NSString *pattern = [NSString stringWithFormat:@"^%@_(\\d+)\\.jsonl$", escaped];
    NSRegularExpression *rx = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:nil];
    NSMutableArray<NSDictionary *> *batches = [NSMutableArray array];

    for (NSString *name in files) {
        NSTextCheckingResult *m = [rx firstMatchInString:name options:0 range:NSMakeRange(0, name.length)];
        if (!m || m.numberOfRanges < 2) continue;
        NSString *n = [name substringWithRange:[m rangeAtIndex:1]];
        [batches addObject:@{@"name":name, @"number":@([n integerValue])}];
    }

    [batches sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return [a[@"number"] compare:b[@"number"]];
    }];

    while (batches.count > 10) {
        NSString *name = batches.firstObject[@"name"];
        [fm removeItemAtPath:[archive stringByAppendingPathComponent:name] error:nil];
        [batches removeObjectAtIndex:0];
    }
}

static BOOL AddSpeedHackArchiveNumberedLogs(void)
{
    AddSpeedHackEnsureLogDirectories();
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *archive = AddSpeedHackArchiveDirectoryPath();
    if (archive.length == 0) return NO;

    NSMutableArray<NSDictionary *> *sources = [NSMutableArray array];
    for (NSUInteger n = 1; n <= 99; n++) {
        NSString *path = AddSpeedHackNumberedLogPath(n);
        if ([fm fileExistsAtPath:path]) [sources addObject:@{@"number":@(n), @"path":path}];
    }
    if (sources.count == 0) return YES;

    NSUInteger batchNumber = AddSpeedHackReadUnsignedCounter(AddSpeedHackBatchCounterPath()) + 1;
    NSString *batchName = [NSString stringWithFormat:@"%@_%03lu.jsonl", kAddSpeedHackBatchStem, (unsigned long)batchNumber];
    NSString *batchPath = [archive stringByAppendingPathComponent:batchName];
    [fm createFileAtPath:batchPath contents:nil attributes:nil];
    NSFileHandle *out = [NSFileHandle fileHandleForWritingAtPath:batchPath];
    if (!out) return NO;

    BOOL ok = YES;
    @try {
        for (NSDictionary *source in sources) {
            NSUInteger number = [source[@"number"] unsignedIntegerValue];
            NSString *path = source[@"path"];
            NSDictionary *boundary = @{
                @"event": @"archived_ad_log_boundary",
                @"version": kAddSpeedHackVersion,
                @"source_log": AddSpeedHackNumberedLogName(number)
            };
            NSData *json = [NSJSONSerialization dataWithJSONObject:boundary options:0 error:nil];
            if (json) {
                [out writeData:json];
                const char nl = '\n';
                [out writeData:[NSData dataWithBytes:&nl length:1]];
            }
            NSData *data = [NSData dataWithContentsOfFile:path];
            if (data.length) {
                [out writeData:data];
                const unsigned char *bytes = data.bytes;
                if (bytes[data.length - 1] != '\n') {
                    const char nl = '\n';
                    [out writeData:[NSData dataWithBytes:&nl length:1]];
                }
            }
        }
        [out closeFile];
    } @catch (__unused NSException *exception) {
        ok = NO;
        @try { [out closeFile]; } @catch (__unused NSException *closeException) {}
    }
    if (!ok) return NO;

    for (NSDictionary *source in sources) [fm removeItemAtPath:source[@"path"] error:nil];
    AddSpeedHackWriteUnsignedCounter(AddSpeedHackBatchCounterPath(), batchNumber);
    AddSpeedHackWriteUnsignedCounter(AddSpeedHackCounterPath(), 0);
    AddSpeedHackPruneArchives();
    return YES;
}

static NSUInteger AddSpeedHackNextLogNumber(void)
{
    AddSpeedHackEnsureLogDirectories();
    NSFileManager *fm = [NSFileManager defaultManager];
    NSUInteger last = AddSpeedHackReadUnsignedCounter(AddSpeedHackCounterPath());

    if (last >= 1 && last <= 99) {
        NSString *lastPath = AddSpeedHackNumberedLogPath(last);
        if (![fm fileExistsAtPath:lastPath]) {
            // Only the immediately previous number may be reused after the user renames it.
            return last;
        }
    }

    if (last >= 99) {
        if (!AddSpeedHackArchiveNumberedLogs()) return 0;
        last = 0;
    }

    NSUInteger next = last + 1;
    AddSpeedHackWriteUnsignedCounter(AddSpeedHackCounterPath(), next);
    return next;
}

static NSString *AddSpeedHackNewLogPath(void)
{
    NSUInteger number = AddSpeedHackNextLogNumber();
    if (number < 1 || number > 99) return nil;
    AddSpeedHackWriteUnsignedCounter(AddSpeedHackCounterPath(), number);
    return AddSpeedHackNumberedLogPath(number);
}

static NSString *gAddSpeedHackActiveLogPath = nil;


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


static NSString *AddSpeedHackNormalizedIdentityURL(NSString *value)
{
    if (value.length == 0) return @"";
    NSURLComponents *components = [NSURLComponents componentsWithString:value];
    if (!components) return value.length > 512 ? [value substringToIndex:512] : value;

    components.query = nil;
    components.fragment = nil;
    NSString *scheme = components.scheme.lowercaseString ?: @"";
    NSString *host = components.host.lowercaseString ?: @"";
    NSString *path = components.percentEncodedPath ?: @"";

    if ([scheme isEqualToString:@"file"]) {
        NSString *last = path.lastPathComponent ?: @"";
        return last.length ? [@"file://" stringByAppendingString:last] : @"file://";
    }
    if (host.length) {
        NSString *base = [NSString stringWithFormat:@"%@://%@%@", scheme.length ? scheme : @"https", host, path];
        return base.length > 512 ? [base substringToIndex:512] : base;
    }
    NSString *fallback = components.string ?: value;
    return fallback.length > 512 ? [fallback substringToIndex:512] : fallback;
}

static NSString *AddSpeedHackAdNetworkCandidate(NSArray<NSString *> *urls)
{
    NSString *joined = [[urls componentsJoinedByString:@" "] lowercaseString];
    if ([joined containsString:@"moloco"]) return @"moloco";
    if ([joined containsString:@"doubleclick"] || [joined containsString:@"googleads"] || [joined containsString:@"googlesyndication"] || [joined containsString:@"admob"]) return @"google";
    if ([joined containsString:@"applovin"]) return @"applovin";
    if ([joined containsString:@"unityads"] || [joined containsString:@"unity3d"]) return @"unity";
    if ([joined containsString:@"ironsource"] || [joined containsString:@"supersonicads"]) return @"ironsource";
    if ([joined containsString:@"mintegral"] || [joined containsString:@"mtgcdn"]) return @"mintegral";
    if ([joined containsString:@"vungle"] || [joined containsString:@"liftoff"]) return @"vungle_liftoff";
    if ([joined containsString:@"pangle"] || [joined containsString:@"pangleglobal"] || [joined containsString:@"bytedance"]) return @"pangle";
    if ([joined containsString:@"inmobi"]) return @"inmobi";
    if ([joined containsString:@"fyber"] || [joined containsString:@"inner-active"] || [joined containsString:@"digitalturbine"]) return @"fyber_digital_turbine";
    if ([joined containsString:@"chartboost"]) return @"chartboost";
    if ([joined containsString:@"facebook"] || [joined containsString:@"audiencenetwork"]) return @"meta_audience_network";
    return @"unknown";
}

static NSArray<NSString *> *AddSpeedHackCreativeIDCandidates(NSArray<NSString *> *urls)
{
    NSMutableOrderedSet<NSString *> *values = [NSMutableOrderedSet orderedSet];
    NSArray<NSString *> *keys = @[@"creative", @"creative_id", @"creativeid", @"crid", @"ad_id", @"adid", @"campaign_id", @"campaignid", @"asset_id", @"assetid"];

    for (NSString *raw in urls) {
        if (![raw isKindOfClass:[NSString class]] || raw.length == 0) continue;
        NSURLComponents *components = [NSURLComponents componentsWithString:raw];
        for (NSURLQueryItem *item in components.queryItems ?: @[]) {
            NSString *name = item.name.lowercaseString;
            if (![keys containsObject:name]) continue;
            NSString *value = item.value ?: @"";
            if (value.length >= 3 && value.length <= 160) [values addObject:value];
        }

        NSError *error = nil;
        NSRegularExpression *uuidRX = [NSRegularExpression regularExpressionWithPattern:@"(?i)(?:^|[^0-9a-f])([0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12})(?:$|[^0-9a-f])" options:0 error:&error];
        if (!error) {
            NSArray<NSTextCheckingResult *> *matches = [uuidRX matchesInString:raw options:0 range:NSMakeRange(0, raw.length)];
            for (NSTextCheckingResult *match in matches) {
                if (match.numberOfRanges < 2) continue;
                NSString *value = [raw substringWithRange:[match rangeAtIndex:1]];
                if (value.length) [values addObject:value];
                if (values.count >= 8) break;
            }
        }
        if (values.count >= 8) break;
    }

    NSArray<NSString *> *array = values.array;
    return array.count > 8 ? [array subarrayWithRange:NSMakeRange(0, 8)] : array;
}

static NSString *AddSpeedHackFNV1a64(NSString *value)
{
    NSData *data = [value dataUsingEncoding:NSUTF8StringEncoding] ?: [NSData data];
    const unsigned char *bytes = data.bytes;
    uint64_t hash = UINT64_C(14695981039346656037);
    for (NSUInteger i = 0; i < data.length; i++) {
        hash ^= (uint64_t)bytes[i];
        hash *= UINT64_C(1099511628211);
    }
    return [NSString stringWithFormat:@"%016llx", (unsigned long long)hash];
}

static NSDictionary *AddSpeedHackIdentityFromSnapshot(NSDictionary *snapshot, NSString *nativeURL)
{
    NSMutableArray<NSString *> *rawURLs = [NSMutableArray array];
    NSString *pageURL = [snapshot[@"page_url"] isKindOfClass:[NSString class]] ? snapshot[@"page_url"] : @"";
    if (pageURL.length) [rawURLs addObject:pageURL];
    if (nativeURL.length) [rawURLs addObject:nativeURL];

    NSMutableArray<NSString *> *videoParts = [NSMutableArray array];
    NSArray *videos = [snapshot[@"videos"] isKindOfClass:[NSArray class]] ? snapshot[@"videos"] : @[];
    for (NSDictionary *video in videos) {
        if (![video isKindOfClass:[NSDictionary class]]) continue;
        NSString *src = [video[@"src"] isKindOfClass:[NSString class]] ? video[@"src"] : @"";
        if (src.length) [rawURLs addObject:src];
        NSString *normalized = AddSpeedHackNormalizedIdentityURL(src);
        NSNumber *duration = [video[@"duration"] isKindOfClass:[NSNumber class]] ? video[@"duration"] : nil;
        NSInteger roundedDuration = duration ? (NSInteger)llround(duration.doubleValue) : -1;
        [videoParts addObject:[NSString stringWithFormat:@"%@|%ld", normalized, (long)roundedDuration]];
    }

    NSMutableArray<NSString *> *iframeParts = [NSMutableArray array];
    NSArray *iframes = [snapshot[@"iframes"] isKindOfClass:[NSArray class]] ? snapshot[@"iframes"] : @[];
    for (NSDictionary *iframe in iframes) {
        if (![iframe isKindOfClass:[NSDictionary class]]) continue;
        NSString *src = [iframe[@"src"] isKindOfClass:[NSString class]] ? iframe[@"src"] : @"";
        NSString *child = [iframe[@"child_url"] isKindOfClass:[NSString class]] ? iframe[@"child_url"] : @"";
        if (src.length) [rawURLs addObject:src];
        if (child.length) [rawURLs addObject:child];
        NSString *part = AddSpeedHackNormalizedIdentityURL(src.length ? src : child);
        if (part.length) [iframeParts addObject:part];
    }

    NSString *network = AddSpeedHackAdNetworkCandidate(rawURLs);
    NSArray<NSString *> *creativeIDs = AddSpeedHackCreativeIDCandidates(rawURLs);
    NSString *normalizedPage = AddSpeedHackNormalizedIdentityURL(pageURL.length ? pageURL : nativeURL);

    [videoParts sortUsingSelector:@selector(compare:)];
    [iframeParts sortUsingSelector:@selector(compare:)];
    NSString *identityMaterial = [NSString stringWithFormat:@"network=%@;page=%@;videos=%@;iframes=%@;creative=%@",
                                  network,
                                  normalizedPage,
                                  [videoParts componentsJoinedByString:@","],
                                  [iframeParts componentsJoinedByString:@","],
                                  [creativeIDs componentsJoinedByString:@","]];
    NSString *fingerprint = AddSpeedHackFNV1a64(identityMaterial);

    NSString *quality = @"low";
    if (videoParts.count > 0 && ![network isEqualToString:@"unknown"]) quality = @"high";
    else if (videoParts.count > 0 || iframeParts.count > 0 || creativeIDs.count > 0) quality = @"medium";

    return @{
        @"ad_fingerprint": fingerprint,
        @"optimization_profile_key": [@"ad_" stringByAppendingString:fingerprint],
        @"ad_network_candidate": network,
        @"fingerprint_quality": quality,
        @"creative_id_candidates": creativeIDs,
        @"fingerprint_page": normalizedPage,
        @"fingerprint_video_parts": videoParts,
        @"fingerprint_iframe_parts": iframeParts
    };
}



static void AddSpeedHackWriteLogToPath(NSDictionary *fields, NSString *path)
{
    if (![fields isKindOfClass:[NSDictionary class]] || path.length == 0) return;

    NSMutableDictionary *record = [NSMutableDictionary dictionaryWithDictionary:fields];
    record[@"timestamp"] = AddSpeedHackTimestamp();
    record[@"version"] = kAddSpeedHackVersion;

    NSString *bundleID = NSBundle.mainBundle.bundleIdentifier;
    if (bundleID.length > 0) record[@"bundle_id"] = bundleID;
    NSString *processName = NSProcessInfo.processInfo.processName;
    if (processName.length > 0) record[@"process"] = processName;

    dispatch_async(AddSpeedHackLogQueue(), ^{
        @autoreleasepool {
            NSData *json = [NSJSONSerialization dataWithJSONObject:record options:0 error:nil];
            if (!json) return;
            NSString *directory = [path stringByDeletingLastPathComponent];
            [[NSFileManager defaultManager] createDirectoryAtPath:directory
                                      withIntermediateDirectories:YES
                                                       attributes:nil
                                                            error:nil];
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

        "function problemTailActive(v){"
        "try{"
        "var tail=Number(window.__ash_problem_tail_seconds||0);"
        "if(!(tail>0))return false;"
        "var d=Number(v.duration||0),t=Number(v.currentTime||0);"
        "return isFinite(d)&&d>0&&isFinite(t)&&(d-t)<=tail;"
        "}catch(e){return false;}"
        "}"

        "function applyVideo(v){"
        "if(!isVideo(v))return;"
        "var target=problemTailActive(v)?1.0:VIDEO_RATE;"
        "try{v.defaultPlaybackRate=target;}catch(e){}"
        "try{"
        "if(Math.abs((v.playbackRate||1)-target)>0.001){"
        "v.playbackRate=target;"
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
        "if(problemTailActive(v)){applyVideo(v);continue;}"
        "var tail=Number(window.__ash_problem_tail_seconds||0);"
        "var safeEnd=Math.max(0,v.duration-0.35);"
        "if(tail>0)safeEnd=Math.min(safeEnd,Math.max(0,v.duration-tail));"
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
        "var target=problemTailActive(v)?1.0:VIDEO_RATE;"
        "if(Math.abs((v.playbackRate||1)-target)>0.001){"
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
        "window.__adspeed_apply_problem_tail=function(){scan(document);};"
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
    "try{"
    "if(!v.__ash_diag){"
    "var now=Date.now();"
    "v.__ash_diag={timeupdate:0,progress:0,ended:0,q25:false,q50:false,q75:false,q95:false,observed_ms:now,play_ms:(!v.paused?now:null),q25_ms:null,q50_ms:null,q75_ms:null,q95_ms:null,ended_ms:null};"
    "v.addEventListener('playing',function(){try{var s=this.__ash_diag;if(s&&s.play_ms===null)s.play_ms=Date.now();}catch(e){}},true);"
    "v.addEventListener('timeupdate',function(){try{var s=this.__ash_diag;if(!s)return;s.timeupdate++;var d=Number(this.duration||0),t=Number(this.currentTime||0);if(d>0&&isFinite(d)){var p=t/d,base=(s.play_ms===null?s.observed_ms:s.play_ms),n=Date.now();if(p>=0.25&&!s.q25){s.q25=true;s.q25_ms=n-base;}if(p>=0.50&&!s.q50){s.q50=true;s.q50_ms=n-base;}if(p>=0.75&&!s.q75){s.q75=true;s.q75_ms=n-base;}if(p>=0.95&&!s.q95){s.q95=true;s.q95_ms=n-base;}}}catch(e){}},true);"
    "v.addEventListener('progress',function(){try{if(this.__ash_diag)this.__ash_diag.progress++;}catch(e){}},true);"
    "v.addEventListener('ended',function(){try{var s=this.__ash_diag;if(!s)return;s.ended++;if(s.ended_ms===null){var base=(s.play_ms===null?s.observed_ms:s.play_ms);s.ended_ms=Date.now()-base;}}catch(e){}},true);"
    "}"
    "}catch(e){}"
    "var ds=null;try{ds=v.__ash_diag||null;}catch(e){}"
    "videos.push({"
    "src:String(v.currentSrc||v.src||''),"
    "duration:(isFinite(v.duration)?Number(v.duration):null),"
    "currentTime:(isFinite(v.currentTime)?Number(v.currentTime):null),"
    "playbackRate:(isFinite(v.playbackRate)?Number(v.playbackRate):null),"
    "ash_tail_active:(function(){try{var tail=Number(window.__ash_problem_tail_seconds||0),d=Number(v.duration||0),t=Number(v.currentTime||0);return tail>0&&d>0&&isFinite(d)&&isFinite(t)&&(d-t)<=tail;}catch(e){return false;}})(),"
    "paused:!!v.paused,"
    "ended:!!v.ended,"
    "diag_timeupdate_count:ds?Number(ds.timeupdate||0):0,"
    "diag_progress_count:ds?Number(ds.progress||0):0,"
    "diag_ended_count:ds?Number(ds.ended||0):0,"
    "diag_q25_reached:ds?!!ds.q25:false,"
    "diag_q50_reached:ds?!!ds.q50:false,"
    "diag_q75_reached:ds?!!ds.q75:false,"
    "diag_q95_reached:ds?!!ds.q95:false,"
    "diag_observed_wall_seconds:ds?((Date.now()-ds.observed_ms)/1000):null,"
    "diag_q25_wall_seconds:(ds&&ds.q25_ms!==null)?(ds.q25_ms/1000):null,"
    "diag_q50_wall_seconds:(ds&&ds.q50_ms!==null)?(ds.q50_ms/1000):null,"
    "diag_q75_wall_seconds:(ds&&ds.q75_ms!==null)?(ds.q75_ms/1000):null,"
    "diag_q95_wall_seconds:(ds&&ds.q95_ms!==null)?(ds.q95_ms/1000):null,"
    "diag_ended_wall_seconds:(ds&&ds.ended_ms!==null)?(ds.ended_ms/1000):null"
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
    "problem_tail_seconds:Number(window.__ash_problem_tail_seconds||0),"
    "endcard_mode:!!window.__adspeed_endcard_mode,"
    "endcard_reason:String(window.__adspeed_endcard_reason||''),"
    "endcard_entered_epoch_ms:window.__adspeed_endcard_entered_ms?Number(window.__adspeed_endcard_entered_ms):null,"
    "video_seek_installed:!!window.__adspeed_seek_timer,"
    "canvas_poke_applied:!!window.__adspeed_canvas_poked"
    "};"
    "}catch(e){return {diagnostic_error:String(e)};}"
    "})();";
}

static const void *kAddSpeedHackWKHandledSurfaceKey = &kAddSpeedHackWKHandledSurfaceKey;
static const void *kAddSpeedHackWKSessionKey = &kAddSpeedHackWKSessionKey;
static const void *kAddSpeedHackWKLogStartedKey = &kAddSpeedHackWKLogStartedKey;
static const void *kAddSpeedHackWKLogPathKey = &kAddSpeedHackWKLogPathKey;
static const void *kAddSpeedHackWKWeakEvidenceKey = &kAddSpeedHackWKWeakEvidenceKey;
static const void *kAddSpeedHackWKParticipantKey = &kAddSpeedHackWKParticipantKey;
static const void *kAddSpeedHackAVLoggedKey = &kAddSpeedHackAVLoggedKey;
static const void *kAddSpeedHackWKLastFingerprintKey = &kAddSpeedHackWKLastFingerprintKey;

// v1.2.5: one parent ad session owns one log file. Individual WKWebViews join it.
static NSString *gAddSpeedHackAdSessionID = nil;
static NSString *gAddSpeedHackAdSessionLogPath = nil;
static NSString *gAddSpeedHackAdSessionConfidence = nil;
static NSUInteger gAddSpeedHackAdSessionWeakSourceCount = 0;
static NSTimeInterval gAddSpeedHackAdSessionLastEvidenceTime = 0;
static NSHashTable<WKWebView *> *gAddSpeedHackAdSessionParticipants = nil;
static const NSTimeInterval kAddSpeedHackAdSessionStaleSeconds = 40.0;
static NSTimeInterval gAddSpeedHackAdSessionStartTime = 0;
static BOOL gAddSpeedHackAdSessionNeedsProblemTail = NO;
static NSString *gAddSpeedHackAdSessionProblemTailReason = nil;
static const double kAddSpeedHackProblemTailSeconds = 20.0;
static const NSTimeInterval kAddSpeedHackSessionRemovalGraceSeconds = 6.0;

static NSTimeInterval AddSpeedHackNow(void)
{
    return [NSDate timeIntervalSinceReferenceDate];
}

static void AddSpeedHackResetAdSessionState(void)
{
    NSString *oldPath = gAddSpeedHackAdSessionLogPath;
    for (WKWebView *webView in gAddSpeedHackAdSessionParticipants.allObjects) {
        objc_setAssociatedObject(webView, kAddSpeedHackWKLogPathKey, nil, OBJC_ASSOCIATION_COPY_NONATOMIC);
        objc_setAssociatedObject(webView, kAddSpeedHackWKLogStartedKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(webView, kAddSpeedHackWKWeakEvidenceKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(webView, kAddSpeedHackWKParticipantKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(webView, kAddSpeedHackWKLastFingerprintKey, nil, OBJC_ASSOCIATION_COPY_NONATOMIC);
    }
    if ([gAddSpeedHackActiveLogPath isEqualToString:oldPath]) gAddSpeedHackActiveLogPath = nil;
    gAddSpeedHackAdSessionID = nil;
    gAddSpeedHackAdSessionLogPath = nil;
    gAddSpeedHackAdSessionConfidence = nil;
    gAddSpeedHackAdSessionWeakSourceCount = 0;
    gAddSpeedHackAdSessionLastEvidenceTime = 0;
    gAddSpeedHackAdSessionStartTime = 0;
    gAddSpeedHackAdSessionNeedsProblemTail = NO;
    gAddSpeedHackAdSessionProblemTailReason = nil;
    gAddSpeedHackAdSessionParticipants = nil;
}

static void AddSpeedHackEndAdSession(NSString *reason)
{
    NSString *path = gAddSpeedHackAdSessionLogPath;
    if (path.length) {
        AddSpeedHackWriteLogToPath(@{
            @"event": @"ad_session_ended",
            @"ad_session_id": gAddSpeedHackAdSessionID ?: @"",
            @"confidence": gAddSpeedHackAdSessionConfidence ?: @"low",
            @"weak_source_count": @(gAddSpeedHackAdSessionWeakSourceCount),
            @"end_reason": reason ?: @"unknown",
            @"real_ad_elapsed_seconds": @(gAddSpeedHackAdSessionStartTime > 0 ? MAX(0, AddSpeedHackNow() - gAddSpeedHackAdSessionStartTime) : 0.0),
            @"problem_tail_active": @(gAddSpeedHackAdSessionNeedsProblemTail),
            @"problem_tail_seconds": @(gAddSpeedHackAdSessionNeedsProblemTail ? kAddSpeedHackProblemTailSeconds : 0.0),
            @"problem_tail_reason": gAddSpeedHackAdSessionProblemTailReason ?: @""
        }, path);
    }
    AddSpeedHackResetAdSessionState();
}

static BOOL AddSpeedHackAdSessionIsStale(void)
{
    if (gAddSpeedHackAdSessionLogPath.length == 0 || gAddSpeedHackAdSessionLastEvidenceTime <= 0) return NO;
    return (AddSpeedHackNow() - gAddSpeedHackAdSessionLastEvidenceTime) > kAddSpeedHackAdSessionStaleSeconds;
}

static NSString *AddSpeedHackEnsureAdSession(WKWebView *webView, BOOL strongEvidence, BOOL weakEvidence, NSString *reason)
{
    if (!strongEvidence && !weakEvidence) return nil;

    if (AddSpeedHackAdSessionIsStale()) AddSpeedHackEndAdSession(@"stale_before_new_evidence");

    BOOL created = NO;
    if (gAddSpeedHackAdSessionLogPath.length == 0) {
        __block NSString *newPath = nil;
        dispatch_sync(AddSpeedHackLogQueue(), ^{ newPath = AddSpeedHackNewLogPath(); });
        if (newPath.length == 0) return nil;

        gAddSpeedHackAdSessionID = NSUUID.UUID.UUIDString;
        gAddSpeedHackAdSessionLogPath = newPath;
        gAddSpeedHackAdSessionConfidence = strongEvidence ? @"high" : @"low";
        gAddSpeedHackAdSessionWeakSourceCount = 0;
        gAddSpeedHackAdSessionStartTime = AddSpeedHackNow();
        gAddSpeedHackAdSessionNeedsProblemTail = NO;
        gAddSpeedHackAdSessionProblemTailReason = nil;
        gAddSpeedHackAdSessionParticipants = [NSHashTable weakObjectsHashTable];
        created = YES;
        gAddSpeedHackActiveLogPath = newPath;
    }

    if (!gAddSpeedHackAdSessionParticipants) gAddSpeedHackAdSessionParticipants = [NSHashTable weakObjectsHashTable];
    if (webView) {
        [gAddSpeedHackAdSessionParticipants addObject:webView];
        objc_setAssociatedObject(webView, kAddSpeedHackWKParticipantKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(webView, kAddSpeedHackWKLogPathKey, gAddSpeedHackAdSessionLogPath, OBJC_ASSOCIATION_COPY_NONATOMIC);
        objc_setAssociatedObject(webView, kAddSpeedHackWKLogStartedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

        if (weakEvidence && ![objc_getAssociatedObject(webView, kAddSpeedHackWKWeakEvidenceKey) boolValue]) {
            objc_setAssociatedObject(webView, kAddSpeedHackWKWeakEvidenceKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            gAddSpeedHackAdSessionWeakSourceCount++;
        }
    }

    NSString *oldConfidence = gAddSpeedHackAdSessionConfidence ?: @"low";
    if (strongEvidence) {
        gAddSpeedHackAdSessionConfidence = @"high";
    } else if (gAddSpeedHackAdSessionWeakSourceCount >= 2 && ![oldConfidence isEqualToString:@"high"]) {
        gAddSpeedHackAdSessionConfidence = @"medium";
    }
    gAddSpeedHackAdSessionLastEvidenceTime = AddSpeedHackNow();

    if (created) {
        AddSpeedHackWriteLogToPath(@{
            @"event": @"ad_session_started",
            @"ad_session_id": gAddSpeedHackAdSessionID ?: @"",
            @"confidence": gAddSpeedHackAdSessionConfidence ?: @"low",
            @"start_reason": reason ?: @"unknown",
            @"state": strongEvidence ? @"confirmed" : @"pending",
            @"legacy_minimum_ad_elapsed_seconds": @0,
            @"real_ad_elapsed_seconds": @0
        }, gAddSpeedHackAdSessionLogPath);
    } else if (![oldConfidence isEqualToString:gAddSpeedHackAdSessionConfidence]) {
        AddSpeedHackWriteLogToPath(@{
            @"event": @"ad_session_confidence_changed",
            @"ad_session_id": gAddSpeedHackAdSessionID ?: @"",
            @"from": oldConfidence,
            @"to": gAddSpeedHackAdSessionConfidence ?: @"low",
            @"reason": reason ?: @"additional_evidence",
            @"weak_source_count": @(gAddSpeedHackAdSessionWeakSourceCount)
        }, gAddSpeedHackAdSessionLogPath);
    }

    return gAddSpeedHackAdSessionLogPath;
}

static NSString *AddSpeedHackLogPathForWebView(WKWebView *webView, BOOL createIfNeeded)
{
    if (!webView) return nil;
    NSString *path = objc_getAssociatedObject(webView, kAddSpeedHackWKLogPathKey);
    if (path.length || !createIfNeeded) return path;
    return gAddSpeedHackAdSessionLogPath;
}

static NSString *AddSpeedHackKnownProblemFamilyFromRecord(NSDictionary *record)
{
    NSArray *parts = [record[@"fingerprint_video_parts"] isKindOfClass:[NSArray class]] ? record[@"fingerprint_video_parts"] : @[];
    for (id item in parts) {
        NSString *part = [item isKindOfClass:[NSString class]] ? [item lowercaseString] : @"";
        if ([part containsString:@"file://oe8f937c_"]) return @"gossip_harbor_family";
        if ([part containsString:@"file://o6b5ee74_"]) return @"meje_kyodan_family";
    }
    return nil;
}

static void AddSpeedHackApplyProblemTailToWebView(WKWebView *webView)
{
    if (!webView || !gAddSpeedHackAdSessionNeedsProblemTail) return;
    NSString *js = [NSString stringWithFormat:
        @"(function(){try{window.__ash_problem_tail_seconds=%0.3f;if(window.__adspeed_apply_problem_tail)window.__adspeed_apply_problem_tail();return true;}catch(e){return false;}})()",
        kAddSpeedHackProblemTailSeconds];
    [webView evaluateJavaScript:js completionHandler:nil];
}

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

            NSDictionary *identity = AddSpeedHackIdentityFromSnapshot(snapshot, nativeURL ?: @"");
            [record addEntriesFromDictionary:identity];

            NSString *problemFamily = AddSpeedHackKnownProblemFamilyFromRecord(record);
            if (problemFamily.length && !gAddSpeedHackAdSessionNeedsProblemTail) {
                gAddSpeedHackAdSessionNeedsProblemTail = YES;
                gAddSpeedHackAdSessionProblemTailReason = problemFamily;
            }
            if (gAddSpeedHackAdSessionNeedsProblemTail) AddSpeedHackApplyProblemTailToWebView(webView);
            record[@"real_ad_elapsed_seconds"] = @(gAddSpeedHackAdSessionStartTime > 0 ? MAX(0, AddSpeedHackNow() - gAddSpeedHackAdSessionStartTime) : 0.0);
            record[@"problem_tail_active"] = @(gAddSpeedHackAdSessionNeedsProblemTail);
            record[@"problem_tail_seconds"] = @(gAddSpeedHackAdSessionNeedsProblemTail ? kAddSpeedHackProblemTailSeconds : 0.0);
            record[@"problem_tail_reason"] = gAddSpeedHackAdSessionProblemTailReason ?: @"";

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

        BOOL iframeOnlyCandidate = [record[@"iframe_only_candidate"] boolValue];
        BOOL strongEvidence = knownSurface;
        BOOL weakEvidence = iframeOnlyCandidate;
        NSString *reason = strongEvidence ? @"handled_html_surface" : (weakEvidence ? @"iframe_only_candidate" : @"none");

        NSString *logPath = AddSpeedHackLogPathForWebView(webView, NO);
        if (strongEvidence || weakEvidence) {
            logPath = AddSpeedHackEnsureAdSession(webView, strongEvidence, weakEvidence, reason);
        }
        BOOL logStarted = (logPath.length > 0);
        if (logStarted) {
            record[@"ad_session_id"] = gAddSpeedHackAdSessionID ?: @"";
            record[@"ad_session_confidence"] = gAddSpeedHackAdSessionConfidence ?: @"low";
            record[@"ad_evidence_strength"] = strongEvidence ? @"strong" : (weakEvidence ? @"weak" : @"none");

            NSString *fingerprint = [record[@"ad_fingerprint"] isKindOfClass:[NSString class]] ? record[@"ad_fingerprint"] : @"";
            NSString *previousFingerprint = objc_getAssociatedObject(webView, kAddSpeedHackWKLastFingerprintKey);
            if (fingerprint.length && ![fingerprint isEqualToString:previousFingerprint]) {
                objc_setAssociatedObject(webView, kAddSpeedHackWKLastFingerprintKey, fingerprint, OBJC_ASSOCIATION_COPY_NONATOMIC);
                AddSpeedHackWriteLogToPath(@{
                    @"event": @"ad_identity_observed",
                    @"ad_session_id": gAddSpeedHackAdSessionID ?: @"",
                    @"ad_fingerprint": fingerprint,
                    @"optimization_profile_key": record[@"optimization_profile_key"] ?: @"",
                    @"ad_network_candidate": record[@"ad_network_candidate"] ?: @"unknown",
                    @"fingerprint_quality": record[@"fingerprint_quality"] ?: @"low",
                    @"creative_id_candidates": record[@"creative_id_candidates"] ?: @[],
                    @"fingerprint_page": record[@"fingerprint_page"] ?: @"",
                    @"fingerprint_video_parts": record[@"fingerprint_video_parts"] ?: @[],
                    @"fingerprint_iframe_parts": record[@"fingerprint_iframe_parts"] ?: @[]
                }, logPath);
            }
            AddSpeedHackWriteLogToPath(record, logPath);
        }

        if (delay >= kProbeDelays[kProbeDelayCount - 1] && isCurrentSession && logStarted) {
            BOOL everSawHandledSurface = [objc_getAssociatedObject(webView, kAddSpeedHackWKHandledSurfaceKey) boolValue];
            AddSpeedHackWriteLogToPath(@{
                @"event": @"wk_coverage_summary",
                @"session_id": sessionID ?: @"",
                @"native_page_url": nativeURL ?: @"",
                @"handled_html_surface_seen": @(everSawHandledSurface),
                @"no_handled_html_surface_observed": @(!everSawHandledSurface),
                @"note": @"Observation only. This is not a reward-success or reward-failure judgment."
            }, logPath);
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

static void ScheduleWKWebViewInjection(WKWebView *webView, BOOL beginNewAd, NSString *rootURL, NSString *loadKind)
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

    NSMutableDictionary *navigationRecord = [@{
        @"event": @"wk_navigation_scheduled",
        @"session_id": sessionID,
        @"native_page_url": webView.URL.absoluteString ?: @"",
        @"load_kind": loadKind ?: @"unknown",
        @"root_boundary_candidate": @NO
    } mutableCopy];
    if (rootURL.length) navigationRecord[@"root_candidate_url"] = rootURL;
    NSString *logPath = AddSpeedHackLogPathForWebView(webView, NO);
    if (logPath.length) AddSpeedHackWriteLogToPath(navigationRecord, logPath);

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

@interface AVPlayer (AdSpeedHackRuntime)
- (void)adspeed_setRate:(float)rate;
- (float)adspeed_rate;
@end

@implementation AVPlayer (AdSpeedHackRuntime)

- (void)adspeed_setRate:(float)rate
{
    if (rate != 0.0f && ![objc_getAssociatedObject(self, kAddSpeedHackAVLoggedKey) boolValue]) {
        objc_setAssociatedObject(self,
                                 kAddSpeedHackAVLoggedKey,
                                 @YES,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        NSString *logPath = AddSpeedHackEnsureAdSession(nil, YES, NO, @"avplayer_activity");
        if (logPath.length) {
            AddSpeedHackWriteLogToPath(@{
                @"event": @"avplayer_acceleration_applied",
                @"ad_session_id": gAddSpeedHackAdSessionID ?: @"",
                @"ad_session_confidence": gAddSpeedHackAdSessionConfidence ?: @"high",
                @"requested_rate": @(rate),
                @"multiplier": @(kAVPlayerMultiplier),
                @"applied_rate": @(rate * kAVPlayerMultiplier)
            }, logPath);
        }
    }

    [self adspeed_setRate:(rate * kAVPlayerMultiplier)];
}

- (float)adspeed_rate
{
    float originalRate = [self adspeed_rate];
    return originalRate * 0.5f;
}
@end

@interface WKWebView (AdSpeedHackRuntime)
- (WKNavigation *)adspeed_loadRequest:(NSURLRequest *)request;
- (WKNavigation *)adspeed_loadHTMLString:(NSString *)string baseURL:(NSURL *)baseURL;
- (WKNavigation *)adspeed_loadData:(NSData *)data MIMEType:(NSString *)MIMEType characterEncodingName:(NSString *)characterEncodingName baseURL:(NSURL *)baseURL;
- (WKNavigation *)adspeed_loadFileURL:(NSURL *)URL allowingReadAccessToURL:(NSURL *)readAccessURL;
- (WKNavigation *)adspeed_reload;
- (WKNavigation *)adspeed_reloadFromOrigin;
- (void)adspeed_removeFromSuperview;
- (void)adspeed_didMoveToWindow;
@end

@implementation WKWebView (AdSpeedHackRuntime)

- (WKNavigation *)adspeed_loadRequest:(NSURLRequest *)request
{
    WKNavigation *navigation = [self adspeed_loadRequest:request];
    ScheduleWKWebViewInjection(self, YES, request.URL.absoluteString, @"loadRequest");
    return navigation;
}

- (WKNavigation *)adspeed_loadHTMLString:(NSString *)string baseURL:(NSURL *)baseURL
{
    WKNavigation *navigation = [self adspeed_loadHTMLString:string baseURL:baseURL];
    ScheduleWKWebViewInjection(self, YES, baseURL.absoluteString, @"loadHTMLString");
    return navigation;
}

- (WKNavigation *)adspeed_loadData:(NSData *)data MIMEType:(NSString *)MIMEType characterEncodingName:(NSString *)characterEncodingName baseURL:(NSURL *)baseURL
{
    WKNavigation *navigation = [self adspeed_loadData:data MIMEType:MIMEType characterEncodingName:characterEncodingName baseURL:baseURL];
    ScheduleWKWebViewInjection(self, YES, baseURL.absoluteString, @"loadData");
    return navigation;
}

- (WKNavigation *)adspeed_loadFileURL:(NSURL *)URL allowingReadAccessToURL:(NSURL *)readAccessURL
{
    WKNavigation *navigation = [self adspeed_loadFileURL:URL allowingReadAccessToURL:readAccessURL];
    ScheduleWKWebViewInjection(self, YES, URL.absoluteString, @"loadFileURL");
    return navigation;
}

- (WKNavigation *)adspeed_reload
{
    WKNavigation *navigation = [self adspeed_reload];
    ScheduleWKWebViewInjection(self, NO, self.URL.absoluteString, @"reload");
    return navigation;
}

- (WKNavigation *)adspeed_reloadFromOrigin
{
    WKNavigation *navigation = [self adspeed_reloadFromOrigin];
    ScheduleWKWebViewInjection(self, NO, self.URL.absoluteString, @"reloadFromOrigin");
    return navigation;
}

- (void)adspeed_removeFromSuperview
{
    BOOL wasParticipant = [objc_getAssociatedObject(self, kAddSpeedHackWKParticipantKey) boolValue];
    NSString *path = objc_getAssociatedObject(self, kAddSpeedHackWKLogPathKey);
    [self adspeed_removeFromSuperview];

    if (wasParticipant && path.length && [path isEqualToString:gAddSpeedHackAdSessionLogPath]) {
        [gAddSpeedHackAdSessionParticipants removeObject:self];
        AddSpeedHackWriteLogToPath(@{
            @"event": @"ad_webview_removed",
            @"ad_session_id": gAddSpeedHackAdSessionID ?: @"",
            @"native_page_url": self.URL.absoluteString ?: @""
        }, path);
        if (gAddSpeedHackAdSessionParticipants.allObjects.count == 0) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kAddSpeedHackSessionRemovalGraceSeconds * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                if (gAddSpeedHackAdSessionParticipants.allObjects.count == 0 && [path isEqualToString:gAddSpeedHackAdSessionLogPath]) {
                    AddSpeedHackEndAdSession(@"last_participating_webview_removed");
                }
            });
        }
    }
}

- (void)adspeed_didMoveToWindow
{
    [self adspeed_didMoveToWindow];
    BOOL wasParticipant = [objc_getAssociatedObject(self, kAddSpeedHackWKParticipantKey) boolValue];
    NSString *path = objc_getAssociatedObject(self, kAddSpeedHackWKLogPathKey);
    if (wasParticipant && self.window == nil && path.length && [path isEqualToString:gAddSpeedHackAdSessionLogPath]) {
        AddSpeedHackWriteLogToPath(@{
            @"event": @"ad_webview_detached_from_window",
            @"ad_session_id": gAddSpeedHackAdSessionID ?: @"",
            @"native_page_url": self.URL.absoluteString ?: @""
        }, path);
    }
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
            SwizzleInstanceMethod(wkWebViewClass, @selector(removeFromSuperview), @selector(adspeed_removeFromSuperview));
            SwizzleInstanceMethod(wkWebViewClass, @selector(didMoveToWindow), @selector(adspeed_didMoveToWindow));
        }
    }
}
