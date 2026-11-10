#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <string.h>

int main(int argc, char *argv[]) {
    setenv("SDL_MAC_BACKGROUND_APP", "1", 1);
    
    const char *home = getenv("HOME");
    char dylib_path[1024];
    if (home) {
        snprintf(dylib_path, sizeof(dylib_path), "%s/.universal-adb-control/helpers/libUniversalControlFrame.dylib", home);
        if (access(dylib_path, R_OK) == 0) {
            setenv("DYLD_INSERT_LIBRARIES", dylib_path, 1);
        }
    }
    
    const char *scrcpy_bin = "/opt/homebrew/bin/scrcpy";
    if (access(scrcpy_bin, X_OK) != 0) {
        scrcpy_bin = "/usr/local/bin/scrcpy";
        if (access(scrcpy_bin, X_OK) != 0) {
            scrcpy_bin = "scrcpy";
        }
    }
    
    execv(scrcpy_bin, argv);
    perror("execv failed");
    return 1;
}
