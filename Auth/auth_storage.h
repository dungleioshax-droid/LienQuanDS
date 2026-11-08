#pragma once
#include <string>

#ifdef __OBJC__
#import <Foundation/Foundation.h>
#endif

#include "Xor.h"

namespace auth {

    extern std::string chat_username;
    extern bool has_renamed;

    inline void save_key(const std::string &key) {
#ifdef __OBJC__
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        [defaults setObject:[NSString stringWithUTF8String:key.c_str()] forKey:[NSString stringWithUTF8String:ENCRYPT("VNP_SavedKey")]];
        [defaults synchronize];
#endif
    }

    inline std::string load_key() {
#ifdef __OBJC__
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        NSString *chat_name = [defaults objectForKey:[NSString stringWithUTF8String:ENCRYPT("VNP_ChatName")]];
        if (chat_name) {
            chat_username = std::string([chat_name UTF8String]);
        }
        has_renamed = [defaults boolForKey:[NSString stringWithUTF8String:ENCRYPT("VNP_HasRenamed")]];
        NSString *key = [defaults objectForKey:[NSString stringWithUTF8String:ENCRYPT("VNP_SavedKey")]];
        if (key) return std::string([key UTF8String]);
#endif
        return "";
    }

} // namespace auth
