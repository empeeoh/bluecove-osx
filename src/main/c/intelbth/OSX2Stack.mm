//
//  OSX2Stack.cpp
//  bluecove
//
//  Created by Mathias Kühn on 28.01.13.
//
//

#include "OSX2Stack.h"

#include "common.h"
#include "com_intel_bluetooth_BluetoothStackOSX.h"

#import <IOBluetooth/IOBluetooth.h>
#import <Foundation/Foundation.h>

#import <dispatch/dispatch.h>
#import <JavaVM/jni.h> // Java JNI header.

// #define com_intel_bluetooth_BluetoothStackOSX_debug 0L
// #define com_intel_bluetooth_BluetoothStackOSX_ATTR_RETRIEVABLE_MAX 256L
// #define com_intel_bluetooth_BluetoothStackOSX_BLUETOOTH_SOFTWARE_VERSION_2_0_0 20000L

#pragma mark - OSX2Stack 

@interface OSX2Stack : NSObject
{
    
}
@end

#pragma mark - AsyncWorker implementation

@implementation AsyncWorker

@synthesize error;

@synthesize stringResult;
@synthesize intResult;
@synthesize booleanResult;

-(id)init:(NSString *)className
{
    if ((self = [super init]) != nil) {
        _name = className;
    }
    
    return self;
}

-(void)execute:(id)params
{
    self.error = 1000;  // TODO: What is the error code for 'not implemented'
}

-(bool)bluetoothAvailable
{
    return ([IOBluetoothHostController defaultController] == nil);
}

@end

#define BLUETOOTH_AVAILABLE ([IOBluetoothHostController defaultController] == nil)

OSX2Stack* stack = nil;
jint localDeviceSupportedSoftwareVersion = 0;

#pragma mark - JNI Helpers

jstring jstringFromNSString(JNIEnv *env, NSString* string)
{
    return env->NewStringUTF([string UTF8String]);
}

jboolean jbooleanFromBool(bool flag)
{
    return (flag ? JNI_TRUE : JNI_FALSE);
}

int execSync(NSString* taskName, WorkerBlock block)
{
    AsyncWorker* worker = [[AsyncWorker alloc] init:taskName];
    
    return block(worker);
}

#pragma mark - JNI Lifecycle Management

dispatch_queue_t btQueue;

JNIEXPORT jint JNICALL JNI_OnLoad(JavaVM *vm, void *reserved)
{
    btQueue = dispatch_queue_create("org.bluecove.btqueue", 0);
    
    return JNI_VERSION_1_2;
}

JNIEXPORT void JNICALL JNI_OnUnload(JavaVM *vm, void *reserved)
{
    dispatch_release(btQueue);
}


#pragma mark - JNI function

JNIEXPORT jboolean JNICALL Java_com_intel_bluetooth_BluetoothStackOSX_isNativeCodeLoaded
(JNIEnv *env, jobject peer)
{
    return JNI_TRUE;
}

JNIEXPORT jint JNICALL Java_com_intel_bluetooth_BluetoothStackOSX_getLibraryVersion
(JNIEnv *, jobject)
{
    return blueCoveVersion();
}

JNIEXPORT jint JNICALL Java_com_intel_bluetooth_BluetoothStackOSX_detectBluetoothStack
(JNIEnv *env, jobject)
{
    return BLUECOVE_STACK_DETECT_OSX;
}

JNIEXPORT void JNICALL Java_com_intel_bluetooth_BluetoothStackOSX_enableNativeDebug
(JNIEnv *env, jobject, jclass loggerClass, jboolean on)
{
    enableNativeDebug(env, loggerClass, on);
}

JNIEXPORT jboolean JNICALL Java_com_intel_bluetooth_BluetoothStackOSX_initializeImpl
(JNIEnv *env, jobject)
{
    ::stack = [[OSX2Stack alloc] init];
    
    return JNI_TRUE;
}

#pragma mark GetLocalDeviceBluetoothAddress

JNIEXPORT jstring JNICALL Java_com_intel_bluetooth_BluetoothStackOSX_getLocalDeviceBluetoothAddress
(JNIEnv *env, jobject)
{
    Edebug(("getLocalDeviceBluetoothAddress"));
    
    __block NSString* addressAsString;
    
    int result = execSync(@"GetLocalDeviceBluetoothAddress", ^int(AsyncWorker *worker) {

        if (!BLUETOOTH_AVAILABLE) {
            return 1;
        }
        
        IOBluetoothHostController* controller = [IOBluetoothHostController defaultController];
        
        if (controller != nil) {
            addressAsString = [controller addressAsString];
            return 0;
        }

        return 1;
    });
    
    switch (result) {
        case 1:
            throwBluetoothStateException(env, "Bluetooth Device is not available");
            return NULL;
        case 2:
            throwBluetoothStateException(env, "Bluetooth Device is not ready");
            return NULL;
    }
    
    return jstringFromNSString(env, addressAsString);
}


#pragma mark GetLocalDeviceName

RUNNABLE(GetLocalDeviceName)
{
    if (![self bluetoothAvailable]) {
        self.error = 1;
        return;
    }
    
    IOBluetoothHostController* controller = [IOBluetoothHostController defaultController];
    
    if (controller != NULL) {
        self.stringResult = [controller nameAsString];
        return;
    }
    
    self.error = 1;
}
@end

JNIEXPORT jstring JNICALL Java_com_intel_bluetooth_BluetoothStackOSX_getLocalDeviceName
(JNIEnv *env, jobject)
{
    Edebug(("getLocalDeviceName"));
    
    WORKER(GetLocalDeviceName);
    
    synchronousBTOperation(worker);
    
    if (worker.error) {
        return NULL;
    }

    return jstringFromNSString(env, worker.stringResult);
}

#pragma mark GetDeviceClass

RUNNABLE(GetDeviceClass)
{
    if (![self bluetoothAvailable]) {
        self.error = 1;
        return;
    }
    
    IOBluetoothHostController* controller = [IOBluetoothHostController defaultController];
    
    BluetoothClassOfDevice cod = [controller classOfDevice];
    
    self.intResult = cod;
}
@end

JNIEXPORT jint JNICALL Java_com_intel_bluetooth_BluetoothStackOSX_getDeviceClassImpl
(JNIEnv *env, jobject)
{
    Edebug(("getDeviceClassImpl"));
    
    WORKER(GetDeviceClass);
    
    synchronousBTOperation(worker);

    if (worker.error) {
        return -1;
    }

    return (jint)worker.intResult;
}

#pragma mark IsLocalDevicePowerOn

RUNNABLE(IsLocalDevicePowerOn)
{
    if (![self bluetoothAvailable]) {
        self.error = 1;
        self.booleanResult = false;
        return;
    }

    BluetoothHCIPowerState powerState = [[IOBluetoothHostController defaultController] powerState];
    
    self.booleanResult = ((powerState == kBluetoothHCIPowerStateON) ? true : false);
}
@end

JNIEXPORT jboolean JNICALL Java_com_intel_bluetooth_BluetoothStackOSX_isLocalDevicePowerOn
(JNIEnv *env, jobject)
{
    Edebug(("isLocalDevicePowerOn"));
    
    WORKER(IsLocalDevicePowerOn);
    
    synchronousBTOperation(worker);
    
    return jbooleanFromBool(worker.booleanResult);
}

#pragma mark IsLocalDeviceDiscoverable

// Declare this to access the function in the OSX Framework
int IOBluetoothPreferenceGetDiscoverableState();

RUNNABLE(IsLocalDeviceDiscoverable) {
    
    if ([IOBluetoothHostController defaultController] == nil) {
        error = 1;
        self.booleanResult = false;
        return;
    }
    
    Boolean discoverableStatus = IOBluetoothPreferenceGetDiscoverableState();
    
    self.booleanResult = discoverableStatus;
}
@end

JNIEXPORT jboolean JNICALL Java_com_intel_bluetooth_BluetoothStackOSX_getLocalDeviceDiscoverableImpl
(JNIEnv *env, jobject)
{
    Edebug(("getLocalDeviceDiscoverableImpl"));
    
    WORKER(IsLocalDeviceDiscoverable);

    synchronousBTOperation(worker);
    
    return jbooleanFromBool(worker.booleanResult);
}

#pragma mark GetBluetoothHCISupportedFeatures

#pragma mark TODO

RUNNABLE(GetBluetoothHCISupportedFeatures)
{
    BluetoothHCISupportedFeatures features;
    //    if (IOBluetoothLocalDeviceReadSupportedFeatures(&features, NULL, NULL, NULL)) {
    //        error = 1;
    //        return;
    //    }
    self.intResult = features.data[self.intResult];
}
@end

JNIEXPORT jboolean JNICALL Java_com_intel_bluetooth_BluetoothStackOSX_isLocalDeviceFeatureSwitchRoles
(JNIEnv *env, jobject)
{
    Edebug(("isLocalDeviceFeatureParkMode"));
    
    WORKER(GetBluetoothHCISupportedFeatures);
    
    worker.intResult = 7;
    
    synchronousBTOperation(worker);
    
    if (worker.error) {
        return JNI_FALSE;
    }
    
    return jbooleanFromBool(kBluetoothFeatureSwitchRoles & worker.intResult);
}

JNIEXPORT jboolean JNICALL Java_com_intel_bluetooth_BluetoothStackOSX_isLocalDeviceFeatureParkMode
(JNIEnv *env, jobject)
{
    Edebug(("isLocalDeviceFeatureParkMode"));
    
    WORKER(GetBluetoothHCISupportedFeatures);
    
    worker.intResult = 6;
    
    synchronousBTOperation(worker);
    
    if (worker.error) {
        return JNI_FALSE;
    }

    return jbooleanFromBool(kBluetoothFeatureParkMode & worker.intResult);
}

JNIEXPORT jint JNICALL Java_com_intel_bluetooth_BluetoothStackOSX_getLocalDeviceL2CAPMTUMaximum
(JNIEnv *env, jobject) {
    return (jint)kBluetoothL2CAPMTUMaximum;
}

#pragma mark GetLocalDeviceVersion

RUNNABLE(GetLocalDeviceVersion)
{
    NumVersion* btVersion = (NumVersion*)pData[0];
    BluetoothHCIVersionInfo* hciVersion = (BluetoothHCIVersionInfo*)pData[1];
    
    if (IOBluetoothGetVersion(btVersion, hciVersion)) {
        self.error = 1;
    }
}
@end

JNIEXPORT jstring JNICALL Java_com_intel_bluetooth_BluetoothStackOSX_getLocalDeviceSoftwareVersionInfo
(JNIEnv *env, jobject)
{
    Edebug(("getLocalDeviceSoftwareVersionInfo"));
    NumVersion btVersion;
    char swVers[133];
    
    WORKER(GetLocalDeviceVersion);
    
    worker.pointerData[0] = &btVersion;
    
    synchronousBTOperation(worker);
    
    if (worker.error) {
        return NULL;
    }
    
    snprintf(swVers, 133, "%1d.%1d.%1d rev %d", btVersion.majorRev, (btVersion.minorAndBugRev >> 4) & 0x0F,
             btVersion.minorAndBugRev & 0x0F, btVersion.nonRelRev);
    return env->NewStringUTF(swVers);
}

JNIEXPORT jint JNICALL Java_com_intel_bluetooth_BluetoothStackOSX_getLocalDeviceSupportedSoftwareVersion
(JNIEnv *env, jobject) {
    Edebug(("getLocalDeviceSupportedSoftwareVersion"));
    NumVersion btVersion;
    GetLocalDeviceVersion runnable;
    runnable.pData[0] = &btVersion;
    synchronousBTOperation(&runnable);
    if (runnable.error) {
        return 0;
    }
    
    // Define starts with 0 and interprited as Octal constants
    int compiledFor = 0;

    // not Octal since API version 2
    compiledFor = 10803; // BLUETOOTH_VERSION_CURRENT;

    //log_info("compiled for         %d", compiledFor);
    //log_info(" this majorRev       %d", (int)btVersion.majorRev);
    //log_info(" this minorAndBugRev %d", (int)btVersion.minorAndBugRev);
    
    jint v = (100 * ((100 * btVersion.majorRev) + ((btVersion.minorAndBugRev >> 4) & 0x0F))) + (btVersion.minorAndBugRev & 0x0F);
    //log_info(" this                %d", v);
    if (v < compiledFor) {
        localDeviceSupportedSoftwareVersion = v;
    } else {
        localDeviceSupportedSoftwareVersion = compiledFor;
    }
    return localDeviceSupportedSoftwareVersion;
}

JNIEXPORT jint JNICALL Java_com_intel_bluetooth_BluetoothStackOSX_getLocalDeviceManufacturer
(JNIEnv *env, jobject) {
    Edebug(("getLocalDeviceManufacturer"));
    BluetoothHCIVersionInfo hciVersion;
    GetLocalDeviceVersion runnable;
    runnable.pData[1] = &hciVersion;
    synchronousBTOperation(&runnable);
    if (runnable.error) {
        return 0;
    }
    return hciVersion.manufacturerName;
}

JNIEXPORT jstring JNICALL Java_com_intel_bluetooth_BluetoothStackOSX_getLocalDeviceVersion
(JNIEnv *env, jobject) {
    Edebug(("getLocalDeviceVersion"));
    BluetoothHCIVersionInfo hciVersion;
    GetLocalDeviceVersion runnable;
    runnable.pData[1] = &hciVersion;
    synchronousBTOperation(&runnable);
    if (runnable.error) {
        return 0;
    }
    char swVers[133];
    snprintf(swVers, 133, "LMP Version: %d.%d, HCI Version: %d.%d", hciVersion.lmpVersion, hciVersion.lmpSubVersion,
             hciVersion.hciVersion, hciVersion.hciRevision);
    return env->NewStringUTF(swVers);
}



/*
 * Class:     com_intel_bluetooth_BluetoothStackOSX
 * Method:    setLocalDeviceServiceClassesImpl
 * Signature: (I)Z
 */
JNIEXPORT jboolean JNICALL Java_com_intel_bluetooth_BluetoothStackOSX_setLocalDeviceServiceClassesImpl
(JNIEnv *, jobject, jint);

/*
 * Class:     com_intel_bluetooth_BluetoothStackOSX
 * Method:    isLocalDeviceFeatureSwitchRoles
 * Signature: ()Z
 */
JNIEXPORT jboolean JNICALL Java_com_intel_bluetooth_BluetoothStackOSX_isLocalDeviceFeatureSwitchRoles
(JNIEnv *, jobject);


/*
 * Class:     com_intel_bluetooth_BluetoothStackOSX
 * Method:    getLocalDeviceL2CAPMTUMaximum
 * Signature: ()I
 */
JNIEXPORT jint JNICALL Java_com_intel_bluetooth_BluetoothStackOSX_getLocalDeviceL2CAPMTUMaximum
(JNIEnv *, jobject);

/*
 * Class:     com_intel_bluetooth_BluetoothStackOSX
 * Method:    getLocalDeviceSupportedSoftwareVersion
 * Signature: ()I
 */
JNIEXPORT jint JNICALL Java_com_intel_bluetooth_BluetoothStackOSX_getLocalDeviceSupportedSoftwareVersion
(JNIEnv *, jobject);

/*
 * Class:     com_intel_bluetooth_BluetoothStackOSX
 * Method:    getLocalDeviceSoftwareVersionInfo
 * Signature: ()Ljava/lang/String;
 */
JNIEXPORT jstring JNICALL Java_com_intel_bluetooth_BluetoothStackOSX_getLocalDeviceSoftwareVersionInfo
(JNIEnv *, jobject);

/*
 * Class:     com_intel_bluetooth_BluetoothStackOSX
 * Method:    getLocalDeviceManufacturer
 * Signature: ()I
 */
JNIEXPORT jint JNICALL Java_com_intel_bluetooth_BluetoothStackOSX_getLocalDeviceManufacturer
(JNIEnv *, jobject);

/*
 * Class:     com_intel_bluetooth_BluetoothStackOSX
 * Method:    getLocalDeviceVersion
 * Signature: ()Ljava/lang/String;
 */
JNIEXPORT jstring JNICALL Java_com_intel_bluetooth_BluetoothStackOSX_getLocalDeviceVersion
(JNIEnv *, jobject);

/*
 * Class:     com_intel_bluetooth_BluetoothStackOSX
 * Method:    getLocalDeviceDiscoverableImpl
 * Signature: ()Z
 */
JNIEXPORT jboolean JNICALL Java_com_intel_bluetooth_BluetoothStackOSX_getLocalDeviceDiscoverableImpl
(JNIEnv *, jobject);

/*
 * Class:     com_intel_bluetooth_BluetoothStackOSX
 * Method:    getRemoteDeviceFriendlyName
 * Signature: (J)Ljava/lang/String;
 */
JNIEXPORT jstring JNICALL Java_com_intel_bluetooth_BluetoothStackOSX_getRemoteDeviceFriendlyName
(JNIEnv *, jobject, jlong);

/*
 * Class:     com_intel_bluetooth_BluetoothStackOSX
 * Method:    runDeviceInquiryImpl
 * Signature: (Lcom/intel/bluetooth/DeviceInquiryRunnable;Lcom/intel/bluetooth/DeviceInquiryThread;IILjavax/bluetooth/DiscoveryListener;)I
 */
JNIEXPORT jint JNICALL Java_com_intel_bluetooth_BluetoothStackOSX_runDeviceInquiryImpl
(JNIEnv *, jobject, jobject, jobject, jint, jint, jobject);

/*
 * Class:     com_intel_bluetooth_BluetoothStackOSX
 * Method:    deviceInquiryCancelImpl
 * Signature: ()Z
 */
JNIEXPORT jboolean JNICALL Java_com_intel_bluetooth_BluetoothStackOSX_deviceInquiryCancelImpl
(JNIEnv *, jobject);

/*
 * Class:     com_intel_bluetooth_BluetoothStackOSX
 * Method:    runSearchServicesImpl
 * Signature: (JI)I
 */
JNIEXPORT jint JNICALL Java_com_intel_bluetooth_BluetoothStackOSX_runSearchServicesImpl
(JNIEnv *, jobject, jlong, jint);

/*
 * Class:     com_intel_bluetooth_BluetoothStackOSX
 * Method:    cancelServiceSearchImpl
 * Signature: (I)V
 */
JNIEXPORT void JNICALL Java_com_intel_bluetooth_BluetoothStackOSX_cancelServiceSearchImpl
(JNIEnv *, jobject, jint);

/*
 * Class:     com_intel_bluetooth_BluetoothStackOSX
 * Method:    getServiceAttributeImpl
 * Signature: (JJI)[B
 */
JNIEXPORT jbyteArray JNICALL Java_com_intel_bluetooth_BluetoothStackOSX_getServiceAttributeImpl
(JNIEnv *, jobject, jlong, jlong, jint);

/*
 * Class:     com_intel_bluetooth_BluetoothStackOSX
 * Method:    connectionRfOpenClientConnectionImpl
 * Signature: (JIZZI)J
 */
JNIEXPORT jlong JNICALL Java_com_intel_bluetooth_BluetoothStackOSX_connectionRfOpenClientConnectionImpl
(JNIEnv *, jobject, jlong, jint, jboolean, jboolean, jint);

/*
 * Class:     com_intel_bluetooth_BluetoothStackOSX
 * Method:    connectionRfCloseClientConnection
 * Signature: (J)V
 */
JNIEXPORT void JNICALL Java_com_intel_bluetooth_BluetoothStackOSX_connectionRfCloseClientConnection
(JNIEnv *, jobject, jlong);

/*
 * Class:     com_intel_bluetooth_BluetoothStackOSX
 * Method:    rfGetSecurityOpt
 * Signature: (JI)I
 */
JNIEXPORT jint JNICALL Java_com_intel_bluetooth_BluetoothStackOSX_rfGetSecurityOpt
(JNIEnv *, jobject, jlong, jint);

/*
 * Class:     com_intel_bluetooth_BluetoothStackOSX
 * Method:    rfServerCreateImpl
 * Signature: ([BZLjava/lang/String;ZZ)J
 */
JNIEXPORT jlong JNICALL Java_com_intel_bluetooth_BluetoothStackOSX_rfServerCreateImpl
(JNIEnv *, jobject, jbyteArray, jboolean, jstring, jboolean, jboolean);

/*
 * Class:     com_intel_bluetooth_BluetoothStackOSX
 * Method:    rfServerGetChannelID
 * Signature: (J)I
 */
JNIEXPORT jint JNICALL Java_com_intel_bluetooth_BluetoothStackOSX_rfServerGetChannelID
(JNIEnv *, jobject, jlong);

/*
 * Class:     com_intel_bluetooth_BluetoothStackOSX
 * Method:    rfServerCloseImpl
 * Signature: (J)V
 */
JNIEXPORT void JNICALL Java_com_intel_bluetooth_BluetoothStackOSX_rfServerCloseImpl
(JNIEnv *, jobject, jlong);

/*
 * Class:     com_intel_bluetooth_BluetoothStackOSX
 * Method:    rfServerAcceptAndOpenRfServerConnection
 * Signature: (J)J
 */
JNIEXPORT jlong JNICALL Java_com_intel_bluetooth_BluetoothStackOSX_rfServerAcceptAndOpenRfServerConnection
(JNIEnv *, jobject, jlong);

/*
 * Class:     com_intel_bluetooth_BluetoothStackOSX
 * Method:    sdpServiceUpdateServiceRecordPublish
 * Signature: (JC)V
 */
JNIEXPORT void JNICALL Java_com_intel_bluetooth_BluetoothStackOSX_sdpServiceUpdateServiceRecordPublish
(JNIEnv *, jobject, jlong, jchar);

/*
 * Class:     com_intel_bluetooth_BluetoothStackOSX
 * Method:    sdpServiceAddAttribute
 * Signature: (JCIIJ[B)V
 */
JNIEXPORT void JNICALL Java_com_intel_bluetooth_BluetoothStackOSX_sdpServiceAddAttribute
(JNIEnv *, jobject, jlong, jchar, jint, jint, jlong, jbyteArray);

/*
 * Class:     com_intel_bluetooth_BluetoothStackOSX
 * Method:    sdpServiceSequenceAttributeStart
 * Signature: (JCII)V
 */
JNIEXPORT void JNICALL Java_com_intel_bluetooth_BluetoothStackOSX_sdpServiceSequenceAttributeStart
(JNIEnv *, jobject, jlong, jchar, jint, jint);

/*
 * Class:     com_intel_bluetooth_BluetoothStackOSX
 * Method:    sdpServiceSequenceAttributeEnd
 * Signature: (JCI)V
 */
JNIEXPORT void JNICALL Java_com_intel_bluetooth_BluetoothStackOSX_sdpServiceSequenceAttributeEnd
(JNIEnv *, jobject, jlong, jchar, jint);

/*
 * Class:     com_intel_bluetooth_BluetoothStackOSX
 * Method:    connectionRfRead
 * Signature: (J)I
 */
JNIEXPORT jint JNICALL Java_com_intel_bluetooth_BluetoothStackOSX_connectionRfRead__J
(JNIEnv *, jobject, jlong);

/*
 * Class:     com_intel_bluetooth_BluetoothStackOSX
 * Method:    connectionRfRead
 * Signature: (J[BII)I
 */
JNIEXPORT jint JNICALL Java_com_intel_bluetooth_BluetoothStackOSX_connectionRfRead__J_3BII
(JNIEnv *, jobject, jlong, jbyteArray, jint, jint);

/*
 * Class:     com_intel_bluetooth_BluetoothStackOSX
 * Method:    connectionRfReadAvailable
 * Signature: (J)I
 */
JNIEXPORT jint JNICALL Java_com_intel_bluetooth_BluetoothStackOSX_connectionRfReadAvailable
(JNIEnv *, jobject, jlong);

/*
 * Class:     com_intel_bluetooth_BluetoothStackOSX
 * Method:    connectionRfWrite
 * Signature: (J[BII)V
 */
JNIEXPORT void JNICALL Java_com_intel_bluetooth_BluetoothStackOSX_connectionRfWrite
(JNIEnv *, jobject, jlong, jbyteArray, jint, jint);

/*
 * Class:     com_intel_bluetooth_BluetoothStackOSX
 * Method:    getConnectionRfRemoteAddress
 * Signature: (J)J
 */
JNIEXPORT jlong JNICALL Java_com_intel_bluetooth_BluetoothStackOSX_getConnectionRfRemoteAddress
(JNIEnv *, jobject, jlong);

/*
 * Class:     com_intel_bluetooth_BluetoothStackOSX
 * Method:    l2OpenClientConnectionImpl
 * Signature: (JIZZIII)J
 */
JNIEXPORT jlong JNICALL Java_com_intel_bluetooth_BluetoothStackOSX_l2OpenClientConnectionImpl
(JNIEnv *, jobject, jlong, jint, jboolean, jboolean, jint, jint, jint);

/*
 * Class:     com_intel_bluetooth_BluetoothStackOSX
 * Method:    l2CloseClientConnection
 * Signature: (J)V
 */
JNIEXPORT void JNICALL Java_com_intel_bluetooth_BluetoothStackOSX_l2CloseClientConnection
(JNIEnv *, jobject, jlong);

/*
 * Class:     com_intel_bluetooth_BluetoothStackOSX
 * Method:    l2ServerOpenImpl
 * Signature: ([BZZLjava/lang/String;III)J
 */
JNIEXPORT jlong JNICALL Java_com_intel_bluetooth_BluetoothStackOSX_l2ServerOpenImpl
(JNIEnv *, jobject, jbyteArray, jboolean, jboolean, jstring, jint, jint, jint);

/*
 * Class:     com_intel_bluetooth_BluetoothStackOSX
 * Method:    l2ServerPSM
 * Signature: (J)I
 */
JNIEXPORT jint JNICALL Java_com_intel_bluetooth_BluetoothStackOSX_l2ServerPSM
(JNIEnv *, jobject, jlong);

/*
 * Class:     com_intel_bluetooth_BluetoothStackOSX
 * Method:    l2ServerAcceptAndOpenServerConnection
 * Signature: (J)J
 */
JNIEXPORT jlong JNICALL Java_com_intel_bluetooth_BluetoothStackOSX_l2ServerAcceptAndOpenServerConnection
(JNIEnv *, jobject, jlong);

/*
 * Class:     com_intel_bluetooth_BluetoothStackOSX
 * Method:    l2ServerCloseImpl
 * Signature: (J)V
 */
JNIEXPORT void JNICALL Java_com_intel_bluetooth_BluetoothStackOSX_l2ServerCloseImpl
(JNIEnv *, jobject, jlong);

/*
 * Class:     com_intel_bluetooth_BluetoothStackOSX
 * Method:    l2GetSecurityOpt
 * Signature: (JI)I
 */
JNIEXPORT jint JNICALL Java_com_intel_bluetooth_BluetoothStackOSX_l2GetSecurityOpt
(JNIEnv *, jobject, jlong, jint);

/*
 * Class:     com_intel_bluetooth_BluetoothStackOSX
 * Method:    l2Ready
 * Signature: (J)Z
 */
JNIEXPORT jboolean JNICALL Java_com_intel_bluetooth_BluetoothStackOSX_l2Ready
(JNIEnv *, jobject, jlong);

/*
 * Class:     com_intel_bluetooth_BluetoothStackOSX
 * Method:    l2Receive
 * Signature: (J[B)I
 */
JNIEXPORT jint JNICALL Java_com_intel_bluetooth_BluetoothStackOSX_l2Receive
(JNIEnv *, jobject, jlong, jbyteArray);

/*
 * Class:     com_intel_bluetooth_BluetoothStackOSX
 * Method:    l2Send
 * Signature: (J[B)V
 */
JNIEXPORT void JNICALL Java_com_intel_bluetooth_BluetoothStackOSX_l2Send
(JNIEnv *, jobject, jlong, jbyteArray);

/*
 * Class:     com_intel_bluetooth_BluetoothStackOSX
 * Method:    l2GetReceiveMTU
 * Signature: (J)I
 */
JNIEXPORT jint JNICALL Java_com_intel_bluetooth_BluetoothStackOSX_l2GetReceiveMTU
(JNIEnv *, jobject, jlong);

/*
 * Class:     com_intel_bluetooth_BluetoothStackOSX
 * Method:    l2GetTransmitMTU
 * Signature: (J)I
 */
JNIEXPORT jint JNICALL Java_com_intel_bluetooth_BluetoothStackOSX_l2GetTransmitMTU
(JNIEnv *, jobject, jlong);

/*
 * Class:     com_intel_bluetooth_BluetoothStackOSX
 * Method:    l2RemoteAddress
 * Signature: (J)J
 */
JNIEXPORT jlong JNICALL Java_com_intel_bluetooth_BluetoothStackOSX_l2RemoteAddress
(JNIEnv *, jobject, jlong);
