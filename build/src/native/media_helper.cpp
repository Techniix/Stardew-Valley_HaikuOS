// Small Haiku helper for the Stardew Valley launcher.
//
//   sdv-media-helper --restart     restart the media services, like
//                                  Preferences > Media > Restart media services
//
// Used by StardewValley.sh to recover from a Haiku media kit race: a node's
// BTimeSource can be released (NODE_SET_TIMESOURCE) while its
// BMediaEventLooper control thread still uses it, crashing in
// BTimeSource::GetTime. Restarting the media services has made it go away.

#include <Application.h>
#include <MediaDefs.h>
#include <OS.h>

#include <stdio.h>
#include <string.h>

static int
usage(const char* name)
{
	fprintf(stderr, "usage: %s --restart\n", name);
	return 2;
}

int
main(int argc, char** argv)
{
	if (argc != 2)
		return usage(argv[0]);

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
