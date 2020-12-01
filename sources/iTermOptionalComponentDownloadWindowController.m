//
//  iTermOptionalComponentDownloadWindowController.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/27/18.
//

#import "iTermOptionalComponentDownloadWindowController.h"

#import "NSArray+iTerm.h"
#import "NSObject+iTerm.h"
#import "NSStringITerm.h"

@import Sparkle;

// SEE ALSO iTermWebSocketConnectionMinimumPythonLibraryVersion
// NOTE: This does not affect full-environment scripts.
// Increasing this makes everyone download a new version.
const int iTermMinimumPythonEnvironmentVersion = 70;

@protocol iTermOptionalComponentDownloadPhaseDelegate<NSObject>
- (void)optionalComponentDownloadPhaseDidComplete:(iTermOptionalComponentDownloadPhase *)sender;
- (void)optionalComponentDownloadPhase:(iTermOptionalComponentDownloadPhase *)sender
    didProgressToBytes:(double)bytesWritten
    ofTotal:(double)totalBytes;
@end

@interface iTermOptionalComponentDownloadPhase()<NSURLSessionDownloadDelegate>
@property (nonatomic, weak) id<iTermOptionalComponentDownloadPhaseDelegate> delegate;
@property (atomic) BOOL downloading;
@property (nonatomic, strong) NSURLSessionDownloadTask *task;
@property (nonatomic, strong) NSURLSession *urlSession;
@end

@implementation iTermOptionalComponentDownloadPhase {
    NSInteger _continuationsLeft;
}

- (instancetype)initWithURL:(NSURL *)url
    title:(NSString *)title
    nextPhaseFactory:(iTermOptionalComponentDownloadPhase *(^)(iTermOptionalComponentDownloadPhase *))nextPhaseFactory {
    self = [super init];
    if (self) {
        _url = [url copy];
        _title = [title copy];
        _nextPhaseFactory = [nextPhaseFactory copy];
        _continuationsLeft = 10;
    }
    return self;
}

- (BOOL)progressIsDeterminant {
    return YES;
}

- (NSString *)progressString {
    return @"Connecting…";
}

- (BOOL)buttonEnabled {
    return YES;
}

- (void)download {
    assert(!_urlSession);
    assert(!_task);

    self.downloading = YES;
    NSURLSessionConfiguration *sessionConfig = [NSURLSessionConfiguration defaultSessionConfiguration];
    _urlSession = [NSURLSession sessionWithConfiguration:sessionConfig
                                delegate:self
                                delegateQueue:nil];
    _task = [_urlSession downloadTaskWithURL:_url];
    [_task resume];
}

- (void)cancel {
    const BOOL wasDownloading = self.downloading;
    self.downloading = NO;
    [_task cancel];
    _urlSession = nil;
    _task = nil;
    if (wasDownloading) {
        // -999 is the magic number meaning canceled
        _error = [NSError errorWithDomain:@"com.iterm2" code:-999 userInfo:nil];
        [self.delegate optionalComponentDownloadPhaseDidComplete:self];
    }
}

#pragma mark - NSURLSessionDownloadDelegate

- (void)URLSession:(NSURLSession *)session
    downloadTask:(NSURLSessionDownloadTask *)downloadTask
    didWriteData:(int64_t)bytesWritten
    totalBytesWritten:(int64_t)totalBytesWritten
    totalBytesExpectedToWrite:(int64_t)totalBytesExpectedToWrite {
    dispatch_async(dispatch_get_main_queue(), ^ {
        if (self.downloading) {
            // Was not canceled
            [self.delegate optionalComponentDownloadPhase:self didProgressToBytes:totalBytesWritten ofTotal:downloadTask.countOfBytesExpectedToReceive];
        }
    });
}

- (void)URLSession:(NSURLSession *)session
    downloadTask:(NSURLSessionDownloadTask *)downloadTask
    didFinishDownloadingToURL:(NSURL *)location {
    _stream = [NSInputStream inputStreamWithURL:location];
    [_stream open];
}

- (void)URLSession:(NSURLSession *)session
    task:(NSURLSessionTask *)task
    didCompleteWithError:(nullable NSError *)error {
    if ([error.domain isEqualToString:NSURLErrorDomain] &&
            error.code == kCFURLErrorNetworkConnectionLost &&
            _continuationsLeft > 0) {
        // There seems to be a bug in Big Sur. There's a spurious "The network connection was lost"
        // error. I get it every once in a while, and a user reported it in issue 9236. This attempts
        // to work around it.
        // I made a wireshark trace and I can see that the client sends a FIN long before the
        // download is complete. Turning on CFNETWORK_DIAGNOSTICS doesn't help; at level 1 we get
        // "failed strict content length check" which suggests the connection was closed before the
        // whole content was recevied. At level 2 and higher it is very slow and the bug doesn't
        // reproduce.
        // This is an attempt to route around the damage. I was able to reproduce the problem and
        // verify that this fixes it.
        NSData *resumeData = [error.userInfo objectForKey:NSURLSessionDownloadTaskResumeData];
        if (resumeData.length > 0) {
            _continuationsLeft -= 1;
            NSURLSessionConfiguration *sessionConfig = [NSURLSessionConfiguration defaultSessionConfiguration];
            _urlSession = [NSURLSession sessionWithConfiguration:sessionConfig
                                        delegate:self
                                        delegateQueue:nil];
            _task = [_urlSession downloadTaskWithResumeData:resumeData];
            [_task resume];
            return;
        }
    }
    if (!error) {
        int statusCode = [[NSHTTPURLResponse castFrom:task.response] statusCode];
        if (statusCode != 200 && statusCode != 206) {
            error = [NSError errorWithDomain:@"com.iterm2" code:1 userInfo:@ { NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Server returned status code %@: %@", @(statusCode), [NSHTTPURLResponse localizedStringForStatusCode:statusCode] ] }];
        }
    }
    dispatch_async(dispatch_get_main_queue(), ^ {
        if (!self.downloading) {
            // Was canceled
            return;
        }
        self.downloading = NO;
        self->_urlSession = nil;
        self->_task = nil;
        self->_error = error;
        [self.delegate optionalComponentDownloadPhaseDidComplete:self];
    });
}

@end

@implementation iTermDownloadableComponentInfo

- (instancetype)initWithURL:(NSURL *)url
    size:(NSInteger)size
    signature:(NSString *)signature
    isSitePackagesOnly:(BOOL)isSitePackagesOnly {
    if (!url || size == 0 || signature.length == 0) {
        return nil;
    }
    self = [super init];
    if (self) {
        _URL = url;
        _size = size;
        _signature = [signature copy];
        _isSitePackagesOnly = isSitePackagesOnly;
    }
    return self;
}

@end

@implementation iTermManifestDownloadPhase

- (instancetype)initWithURL:(NSURL *)url
    requestedPythonVersion:(NSString *)requestedPythonVersion
    nextPhaseFactory:(iTermOptionalComponentDownloadPhase *(^)(iTermOptionalComponentDownloadPhase *))nextPhaseFactory {
    self = [super initWithURL:url title:@"Finding latest version…" nextPhaseFactory:nextPhaseFactory];
    if (self) {
        _requestedPythonVersion = [requestedPythonVersion copy];
    }
    return self;
}

- (iTermDownloadableComponentInfo *)infoGivenExistingFullComponent:(NSNumber *)existingFullComponent {
    if (!_sitePackagesComponent || !existingFullComponent) {
        return _fullComponent;
    }
    const NSInteger previousVersion = existingFullComponent.integerValue;
    if (previousVersion >= _sitePackagesDependencies.location &&
            previousVersion < NSMaxRange(_sitePackagesDependencies)) {
        return _sitePackagesComponent;
    }
    return _fullComponent;
}

- (BOOL)iTermVersionAtLeast:(NSString *)minVersion
    atMost:(NSString *)maxVersion {
    NSString *version = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleShortVersionString"];
    if (!version) {
        return NO;
    }
    if ([version isEqual:@"unknown"] || [version containsString:@".git."]) {
        // Assume it's the top of master because there's no ordering on git commit numbers
        return YES;
    }
    id<SUVersionComparison> comparator = [SUStandardVersionComparator defaultComparator];
    NSComparisonResult result;
    if (minVersion) {
        result = [comparator compareVersion:version toVersion:minVersion];
        if (result == NSOrderedAscending) {
            return NO;
        }
    }

    if (maxVersion) {
        result = [comparator compareVersion:version toVersion:maxVersion];
        if (result == NSOrderedDescending) {
            return NO;
        }
    }

    return YES;
}

- (NSDictionary *)parsedManifestFromInputStream:(NSInputStream *)stream {
    id obj = [NSJSONSerialization JSONObjectWithStream:stream options:0 error:nil];
    NSArray *array = [NSArray castFrom:obj];
    if (!array) {
        return nil;
    }

    const NSUInteger requestedPartCount = [[self.requestedPythonVersion componentsSeparatedByString:@"."] count];
    int bestVersion = -1;
    NSDictionary *bestDict = nil;
    for (id element in array) {
        NSDictionary *dict = [NSDictionary castFrom:element];
        if (!dict) {
            continue;
        }
        if (self.requestedPythonVersion) {
            NSArray<NSString *> *pythonVersions = dict[@"python_versions"];
            if (requestedPartCount == 3) {
                if (![pythonVersions containsObject:self.requestedPythonVersion]) {
                    continue;
                }
            } else if (requestedPartCount == 2) {
                NSArray<NSString *> *twoPartPythonVersions = [pythonVersions mapWithBlock:^id(NSString *possiblyThreePartVersion) {
                                   NSArray<NSString *> *parts = [possiblyThreePartVersion componentsSeparatedByString:@"."];
                                   if (parts.count != 3) {
                        return nil;
                    }
                    return [[parts subarrayToIndex:2] componentsJoinedByString:@"."];
                }];
                if (![twoPartPythonVersions containsObject:self.requestedPythonVersion]) {
                    continue;
                }
            }
        }
        if (dict[@"url"] && dict[@"signature"] && dict[@"version"]) {
            int version = [dict[@"version"] intValue];
            if (version > bestVersion) {
                NSString *minimumTermVersion = dict[@"minimum_iterm_version"];
                NSString *maximumTermVersion = dict[@"maximum_iterm_version"];
                if ([self iTermVersionAtLeast:minimumTermVersion atMost:maximumTermVersion]) {
                    bestVersion = version;
                    bestDict = dict;
                }
            }
        }
    }
    return bestDict;
}

- (void)URLSession:(NSURLSession *)session
    task:(NSURLSessionTask *)task
    didCompleteWithError:(nullable NSError *)error {
    if (!error) {
        dispatch_async(dispatch_get_main_queue(), ^ {
            NSDictionary *dict = [self parsedManifestFromInputStream:self.stream];
            NSError *innerError = nil;
            const int version = [dict[@"version"] intValue];
            if (version < iTermMinimumPythonEnvironmentVersion) {
innerError = [NSError errorWithDomain:@"com.iterm2" code:3 userInfo:@ { NSLocalizedDescriptionKey: @"☹️ No usable version found." }];
            } else if (dict) {
                self->_fullComponent =
                    [[iTermDownloadableComponentInfo alloc] initWithURL:[NSURL URLWithString:dict[@"url"]]
                                                            size:dict[@"size"] ? [dict[@"size"] integerValue] : 30 * 1000 * 1000
                                                            signature:dict[@"signature"]
                                                            isSitePackagesOnly:NO];
                self->_sitePackagesComponent =
                    [[iTermDownloadableComponentInfo alloc] initWithURL:[NSURL URLWithString:dict[@"site-packages-url"]]
                                                            size:[dict[@"site-packages-size"] integerValue]
                                                            signature:dict[@"site-packages-signature"]
                                                            isSitePackagesOnly:YES];
                const NSInteger fullMin = [dict[@"site-packages-full-min"] integerValue];
                const NSInteger fullMax = [dict[@"site-packages-full-max"] integerValue];
                if (fullMin && fullMax && fullMax >= fullMin) {
                    self->_sitePackagesDependencies = NSMakeRange(fullMin, fullMax - fullMin + 1);
                } else {
                    self->_sitePackagesDependencies = NSMakeRange(NSNotFound, 0);
                }

                self->_version = version;
                self->_pythonVersionsInArchive = [dict[@"python_versions"] copy];
            } else {
                innerError = [NSError errorWithDomain:@"com.iterm2" code:2 userInfo:@ { NSLocalizedDescriptionKey: @"☹️ Malformed manifest." }];
            }
            [super URLSession:session task:task didCompleteWithError:innerError];
        });
    } else {
        [super URLSession:session task:task didCompleteWithError:error];
    }
}

@end

@implementation iTermPayloadDownloadPhase

- (instancetype)initWithURL:(NSURL *)url
    version:(int)version
    expectedSignature:(NSString *)expectedSignature
    requestedPythonVersion:(NSString *)requestedPythonVersion
    expectedVersions:(NSArray<NSString *> *)expectedVersions
    nextPhaseFactory:(iTermOptionalComponentDownloadPhase *(^)(iTermOptionalComponentDownloadPhase *))nextPhaseFactory {
    self = [super initWithURL:url title:@"Downloading Python runtime…" nextPhaseFactory:nextPhaseFactory];
    if (self) {
        _version = version;
        _expectedSignature = [expectedSignature copy];
        _requestedPythonVersion = [requestedPythonVersion copy];
        _expectedVersions = [expectedVersions copy];
    }
    return self;
}

@end

@implementation iTermInstallingPhase

- (void)download {
}

- (BOOL)progressIsDeterminant {
    return NO;
}

- (NSString *)progressString {
    return @"Installing…";
}

- (BOOL)buttonEnabled {
    return NO;
}

@end

@interface iTermOptionalComponentDownloadWindowController ()<iTermOptionalComponentDownloadPhaseDelegate>

@end

@implementation iTermOptionalComponentDownloadWindowController {
    IBOutlet NSTextField *_titleLabel;
    IBOutlet NSTextField *_progressLabel;
    IBOutlet NSProgressIndicator *_progressIndicator;
    IBOutlet NSButton *_button;
    IBOutlet NSProgressIndicator *_installIndicator;
    iTermOptionalComponentDownloadPhase *_firstPhase;
    BOOL _showingMessage;
}

- (void)windowDidLoad {
    [super windowDidLoad];

    _titleLabel.stringValue = @"Initializing…";
    _progressLabel.stringValue = [NSString stringWithFormat:@""];
}

- (void)beginPhase:(iTermOptionalComponentDownloadPhase *)phase {
    const BOOL determinant = phase.progressIsDeterminant;
    _progressIndicator.hidden = !determinant;
    _installIndicator.hidden = determinant;
    if (!determinant) {
        [_installIndicator startAnimation:nil];
    } else {
        [_installIndicator stopAnimation:nil];
    }

    _showingMessage = NO;
    assert(!_currentPhase.downloading);
    if (!_currentPhase) {
        _firstPhase = phase;
    }
    _currentPhase = phase;
    _titleLabel.stringValue = phase.title;
    phase.delegate = self;
    [phase download];
    _progressLabel.stringValue = phase.progressString;
    _button.enabled = phase.buttonEnabled;
    _button.title = @"Cancel";
}

- (void)showMessage:(NSString *)message {
    _showingMessage = YES;
    _titleLabel.stringValue = message;
    _progressLabel.stringValue = @"";
    _button.enabled = YES;
    _button.title = @"OK";
}

- (IBAction)button:(id)sender {
    if (_showingMessage) {
        [self.window close];
    } else if (_currentPhase.downloading) {
        [_currentPhase cancel];
    } else {
        [self beginPhase:_firstPhase];
    }
}

- (void)downloadDidFailWithError:(NSError *)error {
    _button.enabled = YES;
    _button.title = @"Try Again";
    if (error.code == -999 && [error.domain isEqualToString:@"com.iterm2"]) {
        _progressLabel.stringValue = @"Canceled";
        _titleLabel.stringValue = @"";
    } else {
        _progressLabel.stringValue = error.localizedDescription;
        _titleLabel.stringValue = @"Download Failed";
    }
    _progressIndicator.doubleValue = 0;
    iTermOptionalComponentDownloadPhase *phase = _currentPhase;
    _currentPhase = nil;
    self.completion(phase);
}

#pragma mark - iTermOptionalComponentDownloadPhaseDelegate

- (void)optionalComponentDownloadPhaseDidComplete:(iTermOptionalComponentDownloadPhase *)sender {
    if (sender.error) {
        [self downloadDidFailWithError:sender.error];
        return;
    }
    iTermOptionalComponentDownloadPhase *nextPhase = sender.nextPhaseFactory ? sender.nextPhaseFactory(_currentPhase) : nil;
    if (nextPhase) {
        [self beginPhase:nextPhase];
        return;
    }
    iTermOptionalComponentDownloadPhase *phase = _currentPhase;
    _currentPhase = nil;
    self.completion(phase);
}

- (void)optionalComponentDownloadPhase:(iTermOptionalComponentDownloadPhase *)sender
    didProgressToBytes:(double)bytesWritten
    ofTotal:(double)totalBytes {
    self->_progressIndicator.doubleValue = bytesWritten / totalBytes;
    self->_progressLabel.stringValue = [NSString stringWithFormat:@"%@ of %@",
                                                 [NSString it_formatBytes:bytesWritten],
                                                 [NSString it_formatBytes:totalBytes]];
}

@end
