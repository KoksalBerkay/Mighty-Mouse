#import "VitureSDKManager.h"

#include <dlfcn.h>

static NSString *const kVitureSDKErrorDomain = @"com.koksalberkay.mightymouse.viture-sdk";
static NSString *const kCarinaLibraryName = @"libcarina_vio.dylib";
static NSString *const kGlassesLibraryName = @"libglasses.dylib";

static NSError *SDKError(NSString *description) {
    return [NSError errorWithDomain:kVitureSDKErrorDomain
                                code:1
                            userInfo:@{NSLocalizedDescriptionKey: description}];
}

static NSString *LastToolError(NSString *output) {
    NSString *trimmed = [output stringByTrimmingCharactersInSet:
        [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    return trimmed.length > 0 ? trimmed : @"no diagnostic was returned";
}

static BOOL RunTool(NSString *executablePath,
                    NSArray<NSString *> *arguments,
                    NSString **output,
                    NSError **error) {
    NSTask *task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:executablePath];
    task.arguments = arguments;

    NSPipe *pipe = [[NSPipe alloc] init];
    task.standardOutput = pipe;
    task.standardError = pipe;

    @try {
        [task launch];
        [task waitUntilExit];
    } @catch (NSException *exception) {
        if (error) {
            *error = SDKError([NSString stringWithFormat:@"Could not run %@: %@",
                               executablePath,
                               exception.reason ?: @"unknown error"]);
        }
        return NO;
    }

    NSData *data = [[pipe fileHandleForReading] readDataToEndOfFile];
    NSString *toolOutput = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"";
    if (output) *output = toolOutput;
    if (task.terminationStatus != 0) {
        if (error) {
            *error = SDKError([NSString stringWithFormat:@"%@ failed: %@",
                               executablePath,
                               LastToolError(toolOutput)]);
        }
        return NO;
    }
    return YES;
}

static BOOL IsRegularNonSymlinkFile(NSURL *url) {
    NSNumber *isRegular = nil;
    NSNumber *isSymlink = nil;
    if (![url getResourceValue:&isRegular forKey:NSURLIsRegularFileKey error:nil] ||
        ![url getResourceValue:&isSymlink forKey:NSURLIsSymbolicLinkKey error:nil]) {
        return NO;
    }
    return isRegular.boolValue && !isSymlink.boolValue;
}

static BOOL ValidateSDKLibraryFile(NSURL *url, NSError **error) {
    if (!IsRegularNonSymlinkFile(url)) {
        if (error) {
            *error = SDKError([NSString stringWithFormat:
                @"%@ is not a regular, non-symbolic-link file.", url.lastPathComponent]);
        }
        return NO;
    }
    return YES;
}

static NSURL *RequiredLibraryURL(NSURL *directoryURL, NSString *libraryName) {
    NSURL *url = [directoryURL URLByAppendingPathComponent:libraryName isDirectory:NO];
    return IsRegularNonSymlinkFile(url) ? url : nil;
}

static BOOL ValidateInstalledDirectory(NSURL *directoryURL, NSError **error) {
    BOOL isDirectory = NO;
    if (![[NSFileManager defaultManager] fileExistsAtPath:directoryURL.path isDirectory:&isDirectory]) {
        return NO;
    }
    if (!isDirectory) {
        if (error) *error = SDKError(@"The installed SDK path is not a directory.");
        return NO;
    }

    NSURL *carinaURL = RequiredLibraryURL(directoryURL, kCarinaLibraryName);
    NSURL *glassesURL = RequiredLibraryURL(directoryURL, kGlassesLibraryName);
    if (!carinaURL || !glassesURL) {
        if (error) {
            *error = SDKError([NSString stringWithFormat:
                @"The SDK must contain %@ and %@.", kCarinaLibraryName, kGlassesLibraryName]);
        }
        return NO;
    }
    return ValidateSDKLibraryFile(carinaURL, error) &&
           ValidateSDKLibraryFile(glassesURL, error);
}

static NSURL *FindUniqueLibraryInDirectory(NSURL *directoryURL,
                                            NSString *libraryName,
                                            NSError **error) {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSDirectoryEnumerator *enumerator = [fileManager enumeratorAtURL:directoryURL
                                          includingPropertiesForKeys:@[
                                              NSURLIsRegularFileKey,
                                              NSURLIsSymbolicLinkKey]
                                                             options:0
                                                        errorHandler:^BOOL(NSURL *url, NSError *enumerationError) {
        return YES;
    }];

    NSMutableArray<NSURL *> *matches = [NSMutableArray array];
    for (NSURL *candidate in enumerator) {
        if ([candidate.lastPathComponent isEqualToString:libraryName] &&
            IsRegularNonSymlinkFile(candidate)) {
            [matches addObject:candidate];
        }
    }
    if (matches.count != 1) {
        if (error) {
            *error = SDKError([NSString stringWithFormat:
                @"The selected SDK must contain exactly one %@ file; found %lu.",
                libraryName,
                (unsigned long)matches.count]);
        }
        return nil;
    }
    return matches.firstObject;
}

static BOOL ResolveSDKAPI(void *glassesHandle,
                          MightyMouseVitureSDKAPI *api,
                          NSError **error) {
#define RESOLVE_SDK_SYMBOL(field, symbolName) \
    api->field = reinterpret_cast<decltype(api->field)>(dlsym(glassesHandle, symbolName)); \
    if (!api->field) { \
        if (error) *error = SDKError([NSString stringWithFormat:@"The installed SDK is missing %s.", symbolName]); \
        return NO; \
    }

    RESOLVE_SDK_SYMBOL(create, "xr_device_provider_create");
    RESOLVE_SDK_SYMBOL(getDeviceType, "xr_device_provider_get_device_type");
    RESOLVE_SDK_SYMBOL(registerCarinaCallbacks, "xr_device_provider_register_callbacks_carina");
    RESOLVE_SDK_SYMBOL(initialize, "xr_device_provider_initialize");
    RESOLVE_SDK_SYMBOL(start, "xr_device_provider_start");
    RESOLVE_SDK_SYMBOL(stop, "xr_device_provider_stop");
    RESOLVE_SDK_SYMBOL(shutdown, "xr_device_provider_shutdown");
    RESOLVE_SDK_SYMBOL(destroy, "xr_device_provider_destroy");

#undef RESOLVE_SDK_SYMBOL
    return YES;
}

static BOOL OpenSDKAtDirectory(NSURL *directoryURL,
                               MightyMouseVitureSDKAPI *api,
                               void **carinaHandle,
                               void **glassesHandle,
                               NSError **error) {
    NSURL *carinaURL = [directoryURL URLByAppendingPathComponent:kCarinaLibraryName];
    NSURL *glassesURL = [directoryURL URLByAppendingPathComponent:kGlassesLibraryName];

    dlerror();
    void *carina = dlopen(carinaURL.fileSystemRepresentation, RTLD_NOW | RTLD_GLOBAL);
    if (!carina) {
        if (error) *error = SDKError([NSString stringWithFormat:
            @"Could not load %@: %@", kCarinaLibraryName, LastToolError(@(dlerror() ?: "unknown error"))]);
        return NO;
    }

    dlerror();
    void *glasses = dlopen(glassesURL.fileSystemRepresentation, RTLD_NOW | RTLD_GLOBAL);
    if (!glasses) {
        const char *message = dlerror();
        dlclose(carina);
        if (error) *error = SDKError([NSString stringWithFormat:
            @"Could not load %@: %@", kGlassesLibraryName, message ? @(message) : @"unknown error"]);
        return NO;
    }

    MightyMouseVitureSDKAPI resolved = {};
    if (!ResolveSDKAPI(glasses, &resolved, error)) {
        dlclose(glasses);
        dlclose(carina);
        return NO;
    }

    if (api) *api = resolved;
    if (carinaHandle) *carinaHandle = carina;
    if (glassesHandle) *glassesHandle = glasses;
    return YES;
}

static NSURL *TemporaryDirectory(NSString *prefix, NSError **error) {
    NSURL *directory = [[NSURL fileURLWithPath:NSTemporaryDirectory() isDirectory:YES]
        URLByAppendingPathComponent:[NSString stringWithFormat:@"%@-%@", prefix, NSUUID.UUID.UUIDString]
                             isDirectory:YES];
    if (![[NSFileManager defaultManager] createDirectoryAtURL:directory
                                    withIntermediateDirectories:YES
                                                     attributes:nil
                                                          error:error]) {
        return nil;
    }
    return directory;
}

static BOOL ExtractArchive(NSURL *archiveURL, NSURL *destinationURL, NSError **error) {
    NSString *lowercaseName = archiveURL.lastPathComponent.lowercaseString;
    if ([lowercaseName hasSuffix:@".zip"]) {
        return RunTool(@"/usr/bin/ditto",
                       @[@"-x", @"-k", archiveURL.path, destinationURL.path],
                       nil,
                       error);
    }
    if ([lowercaseName hasSuffix:@".tar.gz"] || [lowercaseName hasSuffix:@".tgz"]) {
        return RunTool(@"/usr/bin/tar",
                       @[@"-xzf", archiveURL.path, @"-C", destinationURL.path],
                       nil,
                       error);
    }
    if (error) *error = SDKError(@"Choose a VITURE SDK .zip, .tar.gz, or .tgz archive, or an extracted SDK folder.");
    return NO;
}

@interface VitureSDKManager () {
    NSURL *_installDirectoryURL;
    MightyMouseVitureSDKStatus _installationStatus;
    BOOL _sdkLoaded;
    void *_carinaLibraryHandle;
    void *_glassesLibraryHandle;
    MightyMouseVitureSDKAPI _loadedAPI;
}
@property (nonatomic, readwrite) NSURL *installDirectoryURL;
@property (nonatomic, readwrite) MightyMouseVitureSDKStatus installationStatus;
@property (nonatomic, readwrite, getter=isSDKLoaded) BOOL sdkLoaded;
@end

@implementation VitureSDKManager

+ (instancetype)sharedManager {
    static VitureSDKManager *manager;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        manager = [[self alloc] init];
    });
    return manager;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        NSArray<NSString *> *paths = NSSearchPathForDirectoriesInDomains(
            NSApplicationSupportDirectory, NSUserDomainMask, YES);
        NSURL *applicationSupportURL = [NSURL fileURLWithPath:paths.firstObject isDirectory:YES];
        self.installDirectoryURL = [[applicationSupportURL
            URLByAppendingPathComponent:@"Mighty Mouse" isDirectory:YES]
            URLByAppendingPathComponent:@"VITURE SDK" isDirectory:YES];
        self.installationStatus = MightyMouseVitureSDKStatusNotInstalled;
        self.sdkLoaded = NO;
        _loadedAPI = {};
    }
    return self;
}

- (BOOL)refreshInstallationStatus:(NSError **)error {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    BOOL isDirectory = NO;
    BOOL exists = [fileManager fileExistsAtPath:self.installDirectoryURL.path isDirectory:&isDirectory];
    if (!exists) {
        self.installationStatus = MightyMouseVitureSDKStatusNotInstalled;
        return YES;
    }
    NSError *validationError = nil;
    BOOL valid = isDirectory && ValidateInstalledDirectory(self.installDirectoryURL, &validationError);
    self.installationStatus = valid
        ? MightyMouseVitureSDKStatusInstalled
        : MightyMouseVitureSDKStatusInvalid;
    if (!valid && error) *error = validationError ?: SDKError(@"The installed SDK is invalid.");
    return valid;
}

- (BOOL)loadSDK:(NSError **)error {
    if (self.sdkLoaded) return YES;

    NSError *validationError = nil;
    if (![self refreshInstallationStatus:&validationError]) {
        if (error) *error = validationError ?: SDKError(@"The VITURE SDK is not installed.");
        return NO;
    }

    MightyMouseVitureSDKAPI api = {};
    void *carina = NULL;
    void *glasses = NULL;
    if (!OpenSDKAtDirectory(self.installDirectoryURL, &api, &carina, &glasses, error)) {
        self.installationStatus = MightyMouseVitureSDKStatusInvalid;
        return NO;
    }

    _loadedAPI = api;
    _carinaLibraryHandle = carina;
    _glassesLibraryHandle = glasses;
    self.sdkLoaded = YES;
    return YES;
}

- (void)unloadSDK {
    if (_glassesLibraryHandle) {
        dlclose(_glassesLibraryHandle);
        _glassesLibraryHandle = NULL;
    }
    if (_carinaLibraryHandle) {
        dlclose(_carinaLibraryHandle);
        _carinaLibraryHandle = NULL;
    }
    _loadedAPI = {};
    self.sdkLoaded = NO;
}

- (BOOL)installFromURL:(NSURL *)sourceURL error:(NSError **)error {
    if (self.sdkLoaded) {
        if (error) *error = SDKError(@"Stop Mighty Mouse before replacing the installed SDK.");
        return NO;
    }
    if (!sourceURL.isFileURL || ![[NSFileManager defaultManager] fileExistsAtPath:sourceURL.path]) {
        if (error) *error = SDKError(@"The selected SDK source could not be read.");
        return NO;
    }

    BOOL securityScoped = [sourceURL startAccessingSecurityScopedResource];
    NSError *operationError = nil;
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSURL *sourceDirectory = nil;
    NSURL *temporaryRoot = TemporaryDirectory(@"MightyMouse-SDK", &operationError);
    BOOL installed = NO;
    if (temporaryRoot) {
        do {
            BOOL sourceIsDirectory = NO;
            [fileManager fileExistsAtPath:sourceURL.path isDirectory:&sourceIsDirectory];
            if (sourceIsDirectory) {
                sourceDirectory = sourceURL;
            } else {
                sourceDirectory = [temporaryRoot URLByAppendingPathComponent:@"Extracted" isDirectory:YES];
                if (![fileManager createDirectoryAtURL:sourceDirectory
                             withIntermediateDirectories:YES
                                              attributes:nil
                                                   error:&operationError] ||
                    !ExtractArchive(sourceURL, sourceDirectory, &operationError)) {
                    break;
                }
            }

            NSURL *carinaSource = FindUniqueLibraryInDirectory(sourceDirectory,
                                                                kCarinaLibraryName,
                                                                &operationError);
            NSURL *glassesSource = FindUniqueLibraryInDirectory(sourceDirectory,
                                                                 kGlassesLibraryName,
                                                                 &operationError);
            if (!carinaSource || !glassesSource ||
                !ValidateSDKLibraryFile(carinaSource, &operationError) ||
                !ValidateSDKLibraryFile(glassesSource, &operationError)) {
                break;
            }

            NSURL *stagedInstall = [temporaryRoot URLByAppendingPathComponent:@"VITURE SDK" isDirectory:YES];
            if (![fileManager createDirectoryAtURL:stagedInstall
                          withIntermediateDirectories:YES
                                           attributes:nil
                                                error:&operationError]) {
                break;
            }
            NSURL *stagedCarina = [stagedInstall URLByAppendingPathComponent:kCarinaLibraryName];
            NSURL *stagedGlasses = [stagedInstall URLByAppendingPathComponent:kGlassesLibraryName];
            if (![fileManager copyItemAtURL:carinaSource toURL:stagedCarina error:&operationError] ||
                ![fileManager copyItemAtURL:glassesSource toURL:stagedGlasses error:&operationError] ||
                !ValidateInstalledDirectory(stagedInstall, &operationError)) {
                break;
            }

            // Load the staged pair before touching an existing installation.
            // This catches missing symbols and broken sibling-library
            // resolution early.
            MightyMouseVitureSDKAPI stagedAPI = {};
            void *stagedCarinaHandle = NULL;
            void *stagedGlassesHandle = NULL;
            if (!OpenSDKAtDirectory(stagedInstall, &stagedAPI,
                                    &stagedCarinaHandle, &stagedGlassesHandle,
                                    &operationError)) {
                break;
            }
            dlclose(stagedGlassesHandle);
            dlclose(stagedCarinaHandle);

            NSURL *parentURL = [self.installDirectoryURL URLByDeletingLastPathComponent];
            if (![fileManager createDirectoryAtURL:parentURL
                         withIntermediateDirectories:YES
                                          attributes:nil
                                               error:&operationError]) {
                break;
            }

            NSURL *backupURL = nil;
            if ([fileManager fileExistsAtPath:self.installDirectoryURL.path]) {
                backupURL = [temporaryRoot URLByAppendingPathComponent:@"Previous VITURE SDK" isDirectory:YES];
                if (![fileManager moveItemAtURL:self.installDirectoryURL
                                          toURL:backupURL
                                          error:&operationError]) {
                    break;
                }
            }
            if (![fileManager moveItemAtURL:stagedInstall
                                      toURL:self.installDirectoryURL
                                      error:&operationError]) {
                if (backupURL) [fileManager moveItemAtURL:backupURL toURL:self.installDirectoryURL error:nil];
                break;
            }
            installed = YES;
        } while (false);
    }

    if (securityScoped) [sourceURL stopAccessingSecurityScopedResource];
    if (installed) {
        self.installationStatus = MightyMouseVitureSDKStatusInstalled;
        [fileManager removeItemAtURL:temporaryRoot error:nil];
        return YES;
    }
    if (error) *error = operationError ?: SDKError(@"The VITURE SDK could not be installed.");
    if (temporaryRoot) [[NSFileManager defaultManager] removeItemAtURL:temporaryRoot error:nil];
    return NO;
}

- (BOOL)uninstallIncludingPreferences:(BOOL)removePreferences error:(NSError **)error {
    [self unloadSDK];

    NSFileManager *fileManager = [NSFileManager defaultManager];
    if ([fileManager fileExistsAtPath:self.installDirectoryURL.path] &&
        ![fileManager removeItemAtURL:self.installDirectoryURL error:error]) {
        return NO;
    }
    self.installationStatus = MightyMouseVitureSDKStatusNotInstalled;

    if (removePreferences) {
        NSString *bundleIdentifier = NSBundle.mainBundle.bundleIdentifier ?: @"com.koksalberkay.mightymouse";
        [[NSUserDefaults standardUserDefaults] removePersistentDomainForName:bundleIdentifier];
        [[NSUserDefaults standardUserDefaults] synchronize];
    }
    return YES;
}

- (const MightyMouseVitureSDKAPI *)loadedAPI {
    return self.sdkLoaded ? &_loadedAPI : NULL;
}

@end

const MightyMouseVitureSDKAPI *MightyMouseVitureLoadedAPI(void) {
    return [[VitureSDKManager sharedManager] loadedAPI];
}
