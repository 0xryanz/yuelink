// protect_android.c — JNI bridge for VpnService.protect(fd) on Android.
//
// When mihomo creates an outbound socket (to proxy servers, DNS, etc.),
// it must be "protected" so Android doesn't route it back through the
// VPN TUN interface (routing loop). VpnService.protect(fd) marks the
// socket to bypass VPN routing.

#ifdef __ANDROID__

#include <jni.h>
#include <pthread.h>
#include <stdlib.h>

static JavaVM*   g_vm            = NULL;
static jobject   g_vpnService    = NULL;
static jmethodID g_protectMethod = NULL;

// Guards access to g_vpnService / g_protectMethod. protect_fd() runs from
// arbitrary mihomo goroutines (one per outbound socket) while stopTunnel()
// on the Android main thread triggers clear_vpn_service(). Without this
// lock, a goroutine could read g_vpnService != NULL, then have the main
// thread DeleteGlobalRef + NULL it out before CallBooleanMethod uses the
// (now freed) reference — instant SIGSEGV.
static pthread_mutex_t g_mu = PTHREAD_MUTEX_INITIALIZER;

// Called from Go (via exported JNI function) when VPN service starts.
void store_vpn_service(JNIEnv* env, jobject vpnService) {
    // Get JavaVM reference (needed to attach Go threads later)
    (*env)->GetJavaVM(env, &g_vm);

    // Cache protect(int) method ID before taking the lock — GetObjectClass
    // / GetMethodID are safe without mutex (they don't touch g_vpnService).
    jclass cls = (*env)->GetObjectClass(env, vpnService);
    jmethodID mid = (*env)->GetMethodID(env, cls, "protect", "(I)Z");
    (*env)->DeleteLocalRef(env, cls);
    jobject newRef = (*env)->NewGlobalRef(env, vpnService);

    pthread_mutex_lock(&g_mu);
    jobject oldRef = g_vpnService;
    g_vpnService = newRef;
    g_protectMethod = mid;
    pthread_mutex_unlock(&g_mu);

    if (oldRef != NULL) {
        (*env)->DeleteGlobalRef(env, oldRef);
    }
}

// Called from Go (via DefaultSocketHook) for each outbound socket.
int protect_fd(int fd) {
    pthread_mutex_lock(&g_mu);
    JavaVM* vm = g_vm;
    jobject svc = g_vpnService;
    jmethodID mid = g_protectMethod;

    if (vm == NULL || svc == NULL || mid == NULL) {
        pthread_mutex_unlock(&g_mu);
        return 0;
    }

    JNIEnv* env = NULL;
    int need_detach = 0;

    jint status = (*vm)->GetEnv(vm, (void**)&env, JNI_VERSION_1_6);
    if (status == JNI_EDETACHED) {
        if ((*vm)->AttachCurrentThread(vm, &env, NULL) != JNI_OK) {
            pthread_mutex_unlock(&g_mu);
            return 0;
        }
        need_detach = 1;
    } else if (status != JNI_OK) {
        pthread_mutex_unlock(&g_mu);
        return 0;
    }

    // Hold the lock across CallBooleanMethod — protect() is a cheap
    // Java method call (no blocking IO), so the critical section stays
    // microsecond-short and the lock can't meaningfully throttle
    // socket creation throughput.
    jboolean ok = (*env)->CallBooleanMethod(env, svc, mid, (jint)fd);

    pthread_mutex_unlock(&g_mu);

    if (need_detach) {
        (*vm)->DetachCurrentThread(vm);
    }

    return ok ? 1 : 0;
}

// Called from Go when VPN stops — release global reference.
void clear_vpn_service(JNIEnv* env) {
    pthread_mutex_lock(&g_mu);
    jobject oldRef = g_vpnService;
    g_vpnService = NULL;
    g_protectMethod = NULL;
    pthread_mutex_unlock(&g_mu);

    if (oldRef != NULL) {
        (*env)->DeleteGlobalRef(env, oldRef);
    }
}

// JNI entry point: called by YueLinkVpnService.nativeStartProtect(this)
JNIEXPORT void JNICALL
Java_com_yueto_yuelink_YueLinkVpnService_nativeStartProtect(
    JNIEnv* env, jclass clazz, jobject vpnService) {
    store_vpn_service(env, vpnService);
}

// JNI entry point: called by YueLinkVpnService.nativeStopProtect()
JNIEXPORT void JNICALL
Java_com_yueto_yuelink_YueLinkVpnService_nativeStopProtect(
    JNIEnv* env, jclass clazz) {
    clear_vpn_service(env);
}

// JNI entry point: called when network DNS changes.
// dnsList is a comma-separated string of DNS server IPs.
// Implemented in Go (protect_android.go) via notifyDnsChangedFromC.
extern void notifyDnsChangedFromC(const char* dnsList);

JNIEXPORT void JNICALL
Java_com_yueto_yuelink_YueLinkVpnService_nativeNotifyDnsChanged(
    JNIEnv* env, jclass clazz, jstring dnsList) {
    const char* str = (*env)->GetStringUTFChars(env, dnsList, NULL);
    if (str != NULL) {
        notifyDnsChangedFromC(str);
        (*env)->ReleaseStringUTFChars(env, dnsList, str);
    }
}

#endif
