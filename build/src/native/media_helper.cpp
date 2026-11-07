// Small Haiku helper for the Stardew Valley launcher.
//
//   sdv-media-helper --boot-time   print the boot time (seconds since epoch)
//   sdv-media-helper --restart     restart the media services, like
//                                  Preferences > Media > Restart media services
//
// Why: after some boots the media server hands apps a time source whose shared
// memory isn't mapped, and the first BSoundPlayer/BMediaEventLooper call
// segfaults in BTimeSource::GetTime. Restarting the media services fixes it.

#include <Application.h>
#include <MediaDefs.h>
#include <OS.h>

#include <stdio.h>
#include <string.h>

static int
usage(const char* name)
{
	fprintf(stderr, "usage: %s --boot-time | --restart\n", name);
	return 2;
}

int
main(int argc, char** argv)
{
	if (argc != 2)
		return usage(argv[0]);

	if (strcmp(argv[1], "--boot-time") == 0) {
		// real_time_clock() is seconds since epoch, system_time() is
		// microseconds since boot. Callers allow a few seconds of jitter.
		long long bootTime = (long long)real_time_clock()
			- (long long)(system_time() / 1000000);
		printf("%lld\n", bootTime);
		return 0;
	}

	if (strcmp(argv[1], "--restart") == 0) {
		BApplication app("application/x-vnd.Techniix-sdv-media-helper");

		status_t status = shutdown_media_server(10 * 1000000LL);
		if (status != B_OK)
			fprintf(stderr, "shutdown_media_server: %s (continuing)\n",
				strerror(status));

		status = launch_media_server(30 * 1000000LL);
		if (status != B_OK) {
			fprintf(stderr, "launch_media_server: %s\n", strerror(status));
			return 1;
		}
		return 0;
	}

	return usage(argv[0]);
}
