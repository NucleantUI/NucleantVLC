/*
 * libvlc_smoke.c — build-deps.yml's check of a platform's libvlc archive,
 * for platforms the package does not build on yet.
 *
 * Plays a file through libvlc's memory output, the way NucleantVLC does,
 * and passes once frames came out and the file played to its end. It needs
 * the plugins (demuxer, decoder, memory output) to be found and loaded, not
 * just the library itself.
 *
 *     libvlc_smoke <file>
 */

#include <stdio.h>
#include <stdlib.h>

#ifdef _MSC_VER
/* libvlc's headers use ssize_t, which MSVC's C library does not define. */
#include <BaseTsd.h>
typedef SSIZE_T ssize_t;
#endif

#include <vlc/vlc.h>

#ifdef _WIN32
#include <windows.h>
static void sleep_ms(unsigned ms) { Sleep(ms); }
#else
#include <unistd.h>
static void sleep_ms(unsigned ms) { usleep(ms * 1000); }
#endif

enum { WIDTH = 64, HEIGHT = 36 };

static unsigned char pixels[WIDTH * HEIGHT * 4];
static volatile int frames;

static void *lock(void *opaque, void **planes)
{
    (void)opaque;
    planes[0] = pixels;
    return NULL;
}

static void unlock(void *opaque, void *picture, void *const *planes)
{
    (void)opaque; (void)picture; (void)planes;
}

static void display(void *opaque, void *picture)
{
    (void)opaque; (void)picture;
    frames++;
}

int main(int argc, char **argv)
{
    if (argc != 2) {
        fprintf(stderr, "usage: %s <file>\n", argv[0]);
        return 2;
    }

    const char *const options[] = { "--no-audio", "--no-video-title-show" };
    libvlc_instance_t *vlc = libvlc_new(sizeof options / sizeof *options, options);
    if (vlc == NULL) {
        fprintf(stderr, "libvlc_new failed: %s\n", libvlc_errmsg());
        return 1;
    }
    printf("libvlc %s\n", libvlc_get_version());

    libvlc_media_t *media = libvlc_media_new_path(vlc, argv[1]);
    libvlc_media_player_t *player = libvlc_media_player_new_from_media(media);
    libvlc_media_release(media);
    libvlc_video_set_callbacks(player, lock, unlock, display, NULL);
    libvlc_video_set_format(player, "RV32", WIDTH, HEIGHT, WIDTH * 4);
    libvlc_media_player_play(player);

    libvlc_state_t state = libvlc_NothingSpecial;
    for (int waited = 0; waited < 20000; waited += 50) {
        state = libvlc_media_player_get_state(player);
        if (state == libvlc_Ended || state == libvlc_Error)
            break;
        sleep_ms(50);
    }

    libvlc_media_player_stop(player);
    libvlc_media_player_release(player);
    libvlc_release(vlc);

    printf("%d frames, %s\n", frames,
           state == libvlc_Ended ? "played to the end" :
           state == libvlc_Error ? "stopped on an error" : "still playing after 20 s");
    return frames > 0 && state == libvlc_Ended ? 0 : 1;
}
