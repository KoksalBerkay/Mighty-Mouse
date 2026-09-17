#pragma once

#import <Foundation/Foundation.h>

// This is the small ABI surface Mighty Mouse uses at runtime. It is kept as
// application-owned declarations so the vendor SDK headers never need to be
// included in or distributed with this repository.
typedef void *MightyMouseVitureProviderHandle;

typedef void (*MightyMouseViturePoseCallback)(float *pose, double timestamp);
typedef void (*MightyMouseVitureVSyncCallback)(double timestamp);
typedef void (*MightyMouseVitureImuCallback)(float *imu, double timestamp);
typedef void (*MightyMouseVitureCameraCallback)(char *imageLeft0,
                                                 char *imageRight0,
                                                 char *imageLeft1,
                                                 char *imageRight1,
                                                 double timestamp,
                                                 int width,
                                                 int height);

typedef MightyMouseVitureProviderHandle (*MightyMouseVitureCreate)(int productID);
typedef int (*MightyMouseVitureGetDeviceType)(MightyMouseVitureProviderHandle handle);
typedef int (*MightyMouseVitureRegisterCarinaCallbacks)(
    MightyMouseVitureProviderHandle handle,
    MightyMouseViturePoseCallback poseCallback,
    MightyMouseVitureVSyncCallback vsyncCallback,
    MightyMouseVitureImuCallback imuCallback,
    MightyMouseVitureCameraCallback cameraCallback);
typedef int (*MightyMouseVitureInitialize)(MightyMouseVitureProviderHandle handle,
                                            const char *customConfig,
                                            const char *cacheFileDirectory);
typedef int (*MightyMouseVitureStart)(MightyMouseVitureProviderHandle handle);
typedef int (*MightyMouseVitureStop)(MightyMouseVitureProviderHandle handle);
typedef int (*MightyMouseVitureShutdown)(MightyMouseVitureProviderHandle handle);
typedef void (*MightyMouseVitureDestroy)(MightyMouseVitureProviderHandle handle);

struct MightyMouseVitureSDKAPI {
    MightyMouseVitureCreate create;
    MightyMouseVitureGetDeviceType getDeviceType;
    MightyMouseVitureRegisterCarinaCallbacks registerCarinaCallbacks;
    MightyMouseVitureInitialize initialize;
    MightyMouseVitureStart start;
    MightyMouseVitureStop stop;
    MightyMouseVitureShutdown shutdown;
    MightyMouseVitureDestroy destroy;
};

typedef NS_ENUM(NSInteger, MightyMouseVitureSDKStatus) {
    MightyMouseVitureSDKStatusNotInstalled = 0,
    MightyMouseVitureSDKStatusInstalled = 1,
    MightyMouseVitureSDKStatusInvalid = 2,
};

@interface VitureSDKManager : NSObject

+ (instancetype)sharedManager;

@property (nonatomic, readonly) NSURL *installDirectoryURL;
@property (nonatomic, readonly) MightyMouseVitureSDKStatus installationStatus;
@property (nonatomic, readonly, getter=isSDKLoaded) BOOL sdkLoaded;

// Rechecks the app-owned installation directory. Architecture and symbol
// compatibility are verified by dlopen/dlsym when the SDK is loaded.
- (BOOL)refreshInstallationStatus:(NSError **)error;

// Loads the two libraries from installDirectoryURL and resolves only the
// functions used by Mighty Mouse.
- (BOOL)loadSDK:(NSError **)error;
- (void)unloadSDK;

// Installs from a user-selected extracted SDK folder or archive. Only the two
// required dynamic libraries are copied into the app-owned directory.
- (BOOL)installFromURL:(NSURL *)sourceURL error:(NSError **)error;

// Removes only installDirectoryURL. The original source archive/folder is
// never touched. Preferences are removed only when explicitly requested.
- (BOOL)uninstallIncludingPreferences:(BOOL)removePreferences error:(NSError **)error;

- (const MightyMouseVitureSDKAPI *)loadedAPI;

@end

// Convenience bridge for GestureEngine.mm, which only needs the loaded API.
const MightyMouseVitureSDKAPI *MightyMouseVitureLoadedAPI(void);

// The value is part of the runtime ABI used to identify the Luma Ultra
// provider type.
static const int kMightyMouseVitureCarinaDeviceType = 2;
