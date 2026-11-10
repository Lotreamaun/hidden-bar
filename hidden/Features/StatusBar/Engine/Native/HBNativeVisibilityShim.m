//
//  HBNativeVisibilityShim.m
//  Hidden Bar
//
//  Copyright © 2026 Dwarves Foundation. All rights reserved.
//

#import "HBNativeVisibilityShim.h"

static NSString *const HBNativeVisibilityErrorDomain = @"HBNativeVisibility";

static NSError *HBNativeVisibilityError(NSString *reason) {
    return [NSError errorWithDomain:HBNativeVisibilityErrorDomain
                               code:1
                           userInfo:@{NSLocalizedDescriptionKey: reason}];
}

#if HIDDENBAR_NATIVE_VISIBILITY

#import <dlfcn.h>
#import <objc/message.h>
#include <stdint.h>

// MenuBarClientCore is the private framework behind macOS 27's assessment
// (exam lockdown) mode, which can restrict the menu bar to an allow-list. It is
// resolved at runtime so a macOS release that changes or removes it turns into
// "unavailable" rather than a launch failure. Names are spelled out on purpose.
static NSString *const HBFrameworkPath = @"/System/Library/PrivateFrameworks/MenuBarClientCore.framework/MenuBarClientCore";
static NSString *const HBConfigurationClassName = @"MBAssessmentModeConfiguration";
static NSString *const HBAssertionClassName = @"MBAssessmentModeAssertion";

// The supported system-item identities are the cases of the framework's Swift
// RawRepresentable enum. Its synthesized allCases getter is the only complete
// list; the unrestricted configuration returns an empty allow-list instead.
static NSString *const HBSystemItemIdentifierAllCases =
    @"$s17MenuBarClientCore22MBSystemItemIdentifierO8allCasesSayACGvgZ";

static SEL HBConfigurationInit(void) { return @selector(initWithAllowedSystemItems:allowedBundleIdentifiers:); }
static SEL HBActivate(void) { return @selector(activateWithConfiguration:completionHandler:); }
static SEL HBInvalidate(void) { return @selector(invalidate); }

// Swift Array storage is a single pointer: a two-word heap header, then count
// and capacity, then one word per trivial element. The enum is Int-backed.
static NSArray<NSNumber *> *HBSystemItemsFromSwiftArray(void *storagePointer) {
    if (storagePointer == NULL) {
        return nil;
    }
    uintptr_t *storage = (uintptr_t *)storagePointer;
    int64_t count = (int64_t)storage[2];
    if (count <= 0 || count > 256) {
        return nil;
    }
    int64_t *elements = (int64_t *)&storage[4];
    NSMutableArray<NSNumber *> *items = [NSMutableArray arrayWithCapacity:(NSUInteger)count];
    for (int64_t index = 0; index < count; index++) {
        [items addObject:@(elements[index])];
    }
    return items;
}

extern void swift_release(void *object);

BOOL HBNativeVisibilityIsAvailable(void) {
    if (!dlopen(HBFrameworkPath.fileSystemRepresentation, RTLD_NOW | RTLD_LOCAL)) {
        return NO;
    }
    Class configuration = NSClassFromString(HBConfigurationClassName);
    Class assertion = NSClassFromString(HBAssertionClassName);
    return configuration && assertion
        && [configuration instancesRespondToSelector:HBConfigurationInit()]
        && [assertion instancesRespondToSelector:HBActivate()]
        && [assertion instancesRespondToSelector:HBInvalidate()];
}

NSArray<NSNumber *> * HBNativeVisibilitySupportedSystemItems(void) {
    if (!HBNativeVisibilityIsAvailable()) {
        return nil;
    }
    void *handle = dlopen(HBFrameworkPath.fileSystemRepresentation, RTLD_NOW | RTLD_LOCAL);
    if (!handle) {
        return nil;
    }
    void *(*allCases)(void) = (void *(*)(void))dlsym(handle, HBSystemItemIdentifierAllCases.UTF8String);
    if (!allCases) {
        NSLog(@"NativeVisibility: could not find the supported system-item list");
        dlclose(handle);
        return nil;
    }
    void *array = NULL;
    @try {
        array = allCases();
    } @catch (NSException *exception) {
        NSLog(@"NativeVisibility: could not obtain supported system items: %@: %@", exception.name, exception.reason);
        dlclose(handle);
        return nil;
    }
    NSArray<NSNumber *> *items = HBSystemItemsFromSwiftArray(array);
    if (array != NULL) {
        swift_release(array);
    }
    dlclose(handle);
    return items;
}

void HBNativeVisibilityActivate(NSArray<NSNumber *> *allowedSystemItems,
                                NSArray<NSString *> *allowedBundleIdentifiers,
                                void (^completion)(id _Nullable assertion, NSError * _Nullable error)) {
    void (^finish)(id, NSError *) = ^(id assertion, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{ completion(assertion, error); });
    };
    if (!HBNativeVisibilityIsAvailable()) {
        finish(nil, HBNativeVisibilityError(@"MenuBarClientCore is unavailable on this macOS"));
        return;
    }
    @try {
        // Both lists must be NSArrays: the framework indexes into them, and an
        // NSSet raises -objectAtIndex: unrecognized.
        id configuration = ((id (*)(id, SEL, NSArray *, NSArray *))objc_msgSend)(
            [NSClassFromString(HBConfigurationClassName) alloc], HBConfigurationInit(),
            [allowedSystemItems copy], [allowedBundleIdentifiers copy]);
        id assertion = [[NSClassFromString(HBAssertionClassName) alloc] init];
        if (!configuration || !assertion) {
            finish(nil, HBNativeVisibilityError(@"Could not create the visibility configuration"));
            return;
        }
        ((void (*)(id, SEL, id, void (^)(NSError *)))objc_msgSend)(
            assertion, HBActivate(), configuration, ^(NSError *error) {
                finish(error ? nil : assertion, error);
            });
    } @catch (NSException *exception) {
        finish(nil, HBNativeVisibilityError([NSString stringWithFormat:@"%@: %@", exception.name, exception.reason]));
    }
}

void HBNativeVisibilityInvalidate(id assertion) {
    @try {
        if ([assertion respondsToSelector:HBInvalidate()]) {
            ((void (*)(id, SEL))objc_msgSend)(assertion, HBInvalidate());
        }
    } @catch (NSException *exception) {
        NSLog(@"NativeVisibility: invalidate raised %@: %@", exception.name, exception.reason);
    }
}

#else

BOOL HBNativeVisibilityIsAvailable(void) {
    return NO;
}

NSArray<NSNumber *> * HBNativeVisibilitySupportedSystemItems(void) {
    return nil;
}

void HBNativeVisibilityActivate(NSArray<NSNumber *> *allowedSystemItems,
                                NSArray<NSString *> *allowedBundleIdentifiers,
                                void (^completion)(id _Nullable assertion, NSError * _Nullable error)) {
    dispatch_async(dispatch_get_main_queue(), ^{
        completion(nil, HBNativeVisibilityError(@"Native visibility is not part of this build"));
    });
}

void HBNativeVisibilityInvalidate(id assertion) {
}

#endif
