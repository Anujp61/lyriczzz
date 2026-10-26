#include <dlfcn.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef void (*SendFn)(long command, const void *userInfo);

static void *open_media_remote(void) {
    const char *paths[] = {
        "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote",
        "/System/Library/PrivateFrameworks/MediaRemote.framework/Versions/Current/MediaRemote",
        NULL
    };
    for (int index = 0; paths[index] != NULL; index++) {
        void *handle = dlopen(paths[index], RTLD_LAZY);
        if (handle) return handle;
    }
    return NULL;
}

int main(int argc, char **argv) {
    if (argc < 2) {
        fprintf(stderr, "usage: playback-helper <command|check>\n");
        return 2;
    }

    void *handle = open_media_remote();
    if (!handle) {
        fprintf(stderr, "dlopen failed: %s\n", dlerror());
        return 3;
    }

    SendFn send = (SendFn)dlsym(handle, "MRMediaRemoteSendCommand");
    if (!send) {
        fprintf(stderr, "MRMediaRemoteSendCommand missing\n");
        return 4;
    }

    if (strcmp(argv[1], "check") == 0) return 0;
    send((long)atoi(argv[1]), NULL);
    return 0;
}
