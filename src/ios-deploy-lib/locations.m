#import "locations.h"
#import "logging.h"
#include <pwd.h>

CFStringRef copy_device_support_path_x(CFStringRef deviceClass,
                                     CFStringRef build,
                                     CFStringRef version) {
    
    CFStringRef path = NULL;
    CFArrayRef parts = CFStringCreateArrayBySeparatingStrings(NULL, version, CFSTR("."));
    CFMutableArrayRef version_parts = CFArrayCreateMutableCopy(NULL, CFArrayGetCount(parts), parts);
    
    NSLogVerbose(@"Device Class: %@", deviceClass);
    NSLogVerbose(@"build: %@", build);
    
    CFStringRef deviceClassPath_platform;
    CFStringRef deviceClassPath_alt;
    if (CFStringCompare(CFSTR("AppleTV"), deviceClass, 0) == kCFCompareEqualTo) {
        deviceClassPath_platform = CFSTR("Platforms/AppleTVOS.platform/DeviceSupport");
        deviceClassPath_alt = CFSTR("tvOS\\ DeviceSupport");
    } else {
        deviceClassPath_platform = CFSTR("Platforms/iPhoneOS.platform/DeviceSupport");
        deviceClassPath_alt = CFSTR("iOS\\ DeviceSupport");
    }
    while (CFArrayGetCount(version_parts) > 0) {
        version = CFStringCreateByCombiningStrings(NULL, version_parts, CFSTR("."));
        NSLogVerbose(@"version: %@", version);
        if (path == NULL) {
            path = copy_xcode_path_for(deviceClassPath_alt, CFStringCreateWithFormat(NULL, NULL, CFSTR("%@\\ \\(%@\\)"), version, build));
        }
        if (path == NULL) {
            path = copy_xcode_path_for(deviceClassPath_platform, CFStringCreateWithFormat(NULL, NULL, CFSTR("%@\\ \\(%@\\)"), version, build));
        }
        if (path == NULL) {
            path = copy_xcode_path_for(deviceClassPath_platform, CFStringCreateWithFormat(NULL, NULL, CFSTR("%@\\ \\(*\\)"), version));
        }
        if (path == NULL) {
            path = copy_xcode_path_for(deviceClassPath_platform, version);
        }
        if (path == NULL) {
            path = copy_xcode_path_for(CFStringCreateWithFormat(NULL, NULL, CFSTR("%@%@"), deviceClassPath_platform, CFSTR("/Latest")), CFSTR(""));
        }
        CFRelease(version);
        if (path != NULL) {
            break;
        }
        CFArrayRemoveValueAtIndex(version_parts, CFArrayGetCount(version_parts) - 1);
    }
    
    CFRelease(version_parts);
    if (path == NULL)
        on_error(@"Unable to locate DeviceSupport directory. This probably means you don't have Xcode installed, you will need to launch the app manually and logging output will not be shown!");
    
    return path;
}

CFStringRef copy_xcode_path_for(CFStringRef subPath, CFStringRef search) {
    CFStringRef xcodeDevPath = copy_xcode_dev_path();
    CFStringRef path = NULL;
    bool found = false;
    const char* home = get_home();
    CFRange slashLocation;
    
    
    // Try using xcode-select --print-path
    if (!found) {
        path = CFStringCreateWithFormat(NULL, NULL, CFSTR("%@/%@/%@"), xcodeDevPath, subPath, search);
        found = path_exists(path);
    }
    // Try find `xcode-select --print-path` with search as a name pattern
    if (!found) {
        slashLocation = CFStringFind(search, CFSTR("/"), 0);
        if (slashLocation.location == kCFNotFound) {
            path = find_path(CFStringCreateWithFormat(NULL, NULL, CFSTR("%@/%@"), xcodeDevPath, subPath), search, CFSTR("-maxdepth 1"));
        } else {
            path = find_path(CFStringCreateWithFormat(NULL, NULL, CFSTR("%@/%@"), xcodeDevPath, subPath), search, CFSTR(""));
        }
        found = CFStringGetLength(path) > 0 && path_exists(path);
    }
    // If not look in the default xcode location (xcode-select is sometimes wrong)
    if (!found) {
        path = CFStringCreateWithFormat(NULL, NULL, CFSTR("/Applications/Xcode.app/Contents/Developer/%@&%@"), subPath, search);
        found = path_exists(path);
    }
    // If not look in the users home directory, Xcode can store device support stuff there
    if (!found) {
        path = CFStringCreateWithFormat(NULL, NULL, CFSTR("%s/Library/Developer/Xcode/%@/%@"), home, subPath, search);
        found = path_exists(path);
    }
    
    CFRelease(xcodeDevPath);
    
    if (found) {
        return path;
    } else {
        CFRelease(path);
        return NULL;
    }
}

CFStringRef copy_xcode_dev_path() {
    static char xcode_dev_path[256] = { '\0' };
    if (strlen(xcode_dev_path) == 0) {
        FILE *fpipe = NULL;
        char *command = "xcode-select -print-path";
        
        if (!(fpipe = (FILE *)popen(command, "r")))
            on_sys_error(@"Error encountered while opening pipe");
        
        char buffer[256] = { '\0' };
        
        fgets(buffer, sizeof(buffer), fpipe);
        pclose(fpipe);
        
        strtok(buffer, "\n");
        strcpy(xcode_dev_path, buffer);
    }
    return CFStringCreateWithCString(NULL, xcode_dev_path, kCFStringEncodingUTF8);
}

const char *get_home() {
    const char* home = getenv("HOME");
    if (!home) {
        struct passwd *pwd = getpwuid(getuid());
        home = pwd->pw_dir;
    }
    return home;
}

CFStringRef find_path(CFStringRef rootPath, CFStringRef namePattern, CFStringRef expression) {
    FILE *fpipe = NULL;
    CFStringRef cf_command;
    CFRange slashLocation;
    
    slashLocation = CFStringFind(namePattern, CFSTR("/"), 0);
    if (slashLocation.location == kCFNotFound) {
        cf_command = CFStringCreateWithFormat(NULL, NULL, CFSTR("find %@ -name '%@' %@ 2>/dev/null | sort | tail -n 1"), rootPath, namePattern, expression);
    } else {
        cf_command = CFStringCreateWithFormat(NULL, NULL, CFSTR("find %@ -path '%@' %@ 2>/dev/null | sort | tail -n 1"), rootPath, namePattern, expression);
    }
    
    char command[1024] = { '\0' };
    CFStringGetCString(cf_command, command, sizeof(command), kCFStringEncodingUTF8);
    CFRelease(cf_command);
    
    if (!(fpipe = (FILE *)popen(command, "r")))
        on_sys_error(@"Error encountered while opening pipe");
    
    char buffer[256] = { '\0' };
    
    fgets(buffer, sizeof(buffer), fpipe);
    pclose(fpipe);
    
    strtok(buffer, "\n");
    return CFStringCreateWithCString(NULL, buffer, kCFStringEncodingUTF8);
}

Boolean path_exists(CFTypeRef path) {
    if (CFGetTypeID(path) == CFStringGetTypeID()) {
        CFURLRef url = CFURLCreateWithFileSystemPath(NULL, path, kCFURLPOSIXPathStyle, true);
        Boolean result = CFURLResourceIsReachable(url, NULL);
        CFRelease(url);
        return result;
    } else if (CFGetTypeID(path) == CFURLGetTypeID()) {
        return CFURLResourceIsReachable(path, NULL);
    } else {
        return false;
    }
}

