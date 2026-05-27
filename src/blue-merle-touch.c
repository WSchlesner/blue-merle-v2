/*
 * blue-merle-touch — intercepts long-press on the clock area of the GL-E5800
 * touchscreen and triggers blue-merle sim-swap.
 *
 * Reads /dev/input/event0 non-exclusively alongside gl_screen.
 * Does NOT grab the device — gl_screen continues to function normally.
 *
 * Clock region (evdev coordinates, confirmed on device):
 *   X: 0–80, Y: 0–30  (screen is 240×320, Y=0=top)
 * Confirmed tap point: X=28, Y=15
 */

#include <fcntl.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <syslog.h>
#include <sys/time.h>
#include <time.h>
#include <unistd.h>
#include <linux/input.h>

#define EVENT_DEVICE   "/dev/input/event0"
#define STAGE_FILE     "/tmp/blue-merle-sim-swap.stage"
#define SIM_SWAP_CMD   "/usr/bin/blue-merle"
#define HOLD_MS        2000   /* hold duration required to trigger (milliseconds) */
#define COOLDOWN_SECS  10

/* Clock region (top-left status bar) — confirmed via live evdev capture, tap at X=28 Y=15 */
#define X_MIN    0
#define X_MAX   80
#define Y_MIN    0
#define Y_MAX   30

static int in_region(int x, int y)
{
    return x >= X_MIN && x <= X_MAX && y >= Y_MIN && y <= Y_MAX;
}

int main(void)
{
    openlog("blue-merle-touch", LOG_PID, LOG_DAEMON);

    /* Ignore SIGCHLD so forked children are reaped automatically */
    signal(SIGCHLD, SIG_IGN);

    int fd = open(EVENT_DEVICE, O_RDONLY);
    if (fd < 0) {
        syslog(LOG_ERR, "cannot open %s: check /proc/gl-hw-info/screen", EVENT_DEVICE);
        return 1;
    }

    syslog(LOG_INFO, "watching %s — clock region X:%d-%d Y:%d-%d",
           EVENT_DEVICE, X_MIN, X_MAX, Y_MIN, Y_MAX);

    struct input_event ev;
    int cur_x = -1, cur_y = -1;
    int press_x = -1, press_y = -1;
    struct timeval press_time = {0, 0};
    time_t last_trigger = 0;

    while (read(fd, &ev, sizeof(ev)) == sizeof(ev)) {
        if (ev.type == EV_ABS) {
            if (ev.code == ABS_MT_POSITION_X)
                cur_x = ev.value;
            else if (ev.code == ABS_MT_POSITION_Y)
                cur_y = ev.value;
        } else if (ev.type == EV_KEY && ev.code == BTN_TOUCH) {
            if (ev.value == 1) {
                /* Finger down — record position and time */
                press_x = cur_x;
                press_y = cur_y;
                press_time = ev.time;
            } else if (ev.value == 0 && press_x >= 0) {
                /* Finger up — check position, hold duration, cooldown */
                long hold_ms = (ev.time.tv_sec  - press_time.tv_sec)  * 1000 +
                               (ev.time.tv_usec - press_time.tv_usec) / 1000;

                time_t now = time(NULL);
                int in_zone  = in_region(press_x, press_y) && in_region(cur_x, cur_y);
                int held     = hold_ms >= HOLD_MS;
                int cooled   = (now - last_trigger) >= COOLDOWN_SECS;
                int idle     = access(STAGE_FILE, F_OK) != 0;

                if (in_zone && held && cooled && idle) {
                    syslog(LOG_NOTICE,
                           "clock long-press (%ldms at %d,%d) — triggering sim-swap",
                           hold_ms, cur_x, cur_y);
                    last_trigger = now;

                    pid_t pid = fork();
                    if (pid == 0) {
                        setsid();
                        execl(SIM_SWAP_CMD, "blue-merle", "sim-swap", NULL);
                        syslog(LOG_ERR, "execl failed");
                        _exit(1);
                    } else if (pid < 0) {
                        syslog(LOG_ERR, "fork failed");
                    }
                } else if (in_zone && !held) {
                    syslog(LOG_INFO,
                           "clock tap ignored — hold for %dms to trigger (held %ldms)",
                           HOLD_MS, hold_ms);
                } else if (in_zone && !cooled) {
                    syslog(LOG_NOTICE, "long-press in region but cooldown active");
                } else if (in_zone && !idle) {
                    syslog(LOG_NOTICE, "long-press in region but sim-swap already in progress");
                }

                press_x = -1;
                press_y = -1;
            }
        }
    }

    syslog(LOG_WARNING, "read loop ended — %s closed or error", EVENT_DEVICE);
    close(fd);
    return 0;
}
