/*
 * sdv-gamepad: set up a game controller for SDL2 on Haiku.
 *
 * SDL's Haiku joystick backend identifies a controller only by a GUID made
 * from its name, so no Haiku controller matches SDL's built-in controller
 * database and games that use the SDL GameController API (like MonoGame /
 * Stardew Valley) ignore it. This tool records a mapping for the controller
 * and saves it in SDL's gamecontrollerdb format; the launcher points SDL at
 * that file with SDL_GAMECONTROLLERCONFIG_FILE.
 *
 *   sdv-gamepad list             list controllers SDL can see
 *   sdv-gamepad map  DB [index]  record a mapping interactively, save to DB
 *   sdv-gamepad test DB [index]  show live input as the game will see it
 *   sdv-gamepad raw [index]      show raw axis/button/hat values (diagnostics)
 *
 * Plug the controller in before running (Haiku's SDL backend doesn't
 * hot-plug).
 */

#include <SDL2/SDL.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define THRESHOLD 16000
#define STEP_TIMEOUT_MS 10000

static int
init_sdl(void)
{
	/* No window: allow input events without focus. */
	SDL_SetHint(SDL_HINT_JOYSTICK_ALLOW_BACKGROUND_EVENTS, "1");
	if (SDL_Init(SDL_INIT_JOYSTICK | SDL_INIT_GAMECONTROLLER | SDL_INIT_EVENTS) != 0) {
		fprintf(stderr, "SDL_Init failed: %s\n", SDL_GetError());
		return -1;
	}
	return 0;
}

static void
guid_string(int index, char *out, int size)
{
	SDL_JoystickGetGUIDString(SDL_JoystickGetDeviceGUID(index), out, size);
}

static int
cmd_list(void)
{
	int count = SDL_NumJoysticks();
	if (count <= 0) {
		printf("No controllers found. Is it plugged in, and does Haiku's "
			"Joysticks preferences panel see it?\n");
		return 1;
	}
	for (int i = 0; i < count; i++) {
		char guid[64];
		SDL_Joystick *js = SDL_JoystickOpen(i);
		guid_string(i, guid, sizeof(guid));
		printf("[%d] %s\n    GUID %s\n", i, SDL_JoystickNameForIndex(i), guid);
		if (js != NULL) {
			printf("    %d axes, %d buttons, %d hats\n",
				SDL_JoystickNumAxes(js), SDL_JoystickNumButtons(js),
				SDL_JoystickNumHats(js));
			SDL_JoystickClose(js);
		}
		printf("    %s\n", SDL_IsGameController(i)
			? "mapped: games will see it as a gamepad"
			: "NOT mapped: run 'sdv-gamepad map' to set it up");
	}
	return 0;
}

/* ---- interactive mapping ------------------------------------------------ */

enum kind { BUTTON, STICK_AXIS, TRIGGER };

struct step {
	const char *key;    /* SDL mapping field */
	const char *prompt;
	enum kind kind;
};

static const struct step steps[] = {
	{ "a", "Press the BOTTOM face button (A on Xbox layout)", BUTTON },
	{ "b", "Press the RIGHT face button (B)", BUTTON },
	{ "x", "Press the LEFT face button (X)", BUTTON },
	{ "y", "Press the TOP face button (Y)", BUTTON },
	{ "back", "Press BACK / SELECT / View / minus", BUTTON },
	{ "start", "Press START / Menu / plus", BUTTON },
	{ "guide", "Press the HOME / guide button", BUTTON },
	{ "leftshoulder", "Press the LEFT bumper (LB / L1)", BUTTON },
	{ "rightshoulder", "Press the RIGHT bumper (RB / R1)", BUTTON },
	{ "lefttrigger", "Pull the LEFT trigger (LT / L2) all the way", TRIGGER },
	{ "righttrigger", "Pull the RIGHT trigger (RT / R2) all the way", TRIGGER },
	{ "leftstick", "Click the LEFT stick in (L3)", BUTTON },
	{ "rightstick", "Click the RIGHT stick in (R3)", BUTTON },
	{ "dpup", "Press D-pad UP", BUTTON },
	{ "dpdown", "Press D-pad DOWN", BUTTON },
	{ "dpleft", "Press D-pad LEFT", BUTTON },
	{ "dpright", "Press D-pad RIGHT", BUTTON },
	{ "leftx", "Push the LEFT stick fully RIGHT", STICK_AXIS },
	{ "lefty", "Push the LEFT stick fully DOWN", STICK_AXIS },
	{ "rightx", "Push the RIGHT stick fully RIGHT", STICK_AXIS },
	{ "righty", "Push the RIGHT stick fully DOWN", STICK_AXIS },
};

#define MAX_AXES 32

static Sint16 rest[MAX_AXES];

static void
read_rest(SDL_Joystick *js, int naxes)
{
	/* Poll for a while before sampling: the first values can be a stale
	 * snapshot from before the driver's first report (e.g. 0 for triggers
	 * that really rest at -32768). */
	Uint32 start = SDL_GetTicks();
	while (SDL_GetTicks() - start < 700) {
		SDL_JoystickUpdate();
		SDL_Delay(10);
	}
	for (int a = 0; a < naxes && a < MAX_AXES; a++)
		rest[a] = SDL_JoystickGetAxis(js, a);
}

/* Wait until every input is back at rest, so one press isn't counted twice. */
static void
wait_released(SDL_Joystick *js, int naxes, int nbuttons, int nhats)
{
	for (int tries = 0; tries < 300; tries++) {
		int busy = 0;
		SDL_JoystickUpdate();
		for (int b = 0; b < nbuttons; b++)
			busy |= SDL_JoystickGetButton(js, b);
		for (int h = 0; h < nhats; h++)
			busy |= SDL_JoystickGetHat(js, h) != SDL_HAT_CENTERED;
		for (int a = 0; a < naxes && a < MAX_AXES; a++)
			busy |= abs(SDL_JoystickGetAxis(js, a) - rest[a]) > THRESHOLD / 2;
		if (!busy)
			return;
		SDL_Delay(20);
	}
}

/* Returns 1 and fills `out` with an SDL binding (b3, h0.1, a2, +a2, a1~), or
 * 0 on timeout (step skipped). */
static int
capture(SDL_Joystick *js, const struct step *s, int naxes, int nbuttons,
	int nhats, char *out, int size)
{
	Uint32 start = SDL_GetTicks();
	while (SDL_GetTicks() - start < STEP_TIMEOUT_MS) {
		SDL_JoystickUpdate();

		if (s->kind != STICK_AXIS) {
			for (int b = 0; b < nbuttons; b++) {
				if (SDL_JoystickGetButton(js, b)) {
					snprintf(out, size, "b%d", b);
					return 1;
				}
			}
		}
		if (s->kind == BUTTON) {
			for (int h = 0; h < nhats; h++) {
				Uint8 v = SDL_JoystickGetHat(js, h);
				if (v == SDL_HAT_UP || v == SDL_HAT_RIGHT
					|| v == SDL_HAT_DOWN || v == SDL_HAT_LEFT) {
					snprintf(out, size, "h%d.%d", h, v);
					return 1;
				}
			}
		}
		for (int a = 0; a < naxes && a < MAX_AXES; a++) {
			int v = SDL_JoystickGetAxis(js, a);
			int delta = v - rest[a];
			if (abs(delta) < THRESHOLD)
				continue;
			/* Sticks rest centred; an axis resting at an end is a trigger. */
			if (s->kind == STICK_AXIS && abs(rest[a]) > THRESHOLD)
				continue;
			if (s->kind == STICK_AXIS) {
				/* prompts ask for right/down = positive direction */
				snprintf(out, size, delta > 0 ? "a%d" : "a%d~", a);
			} else if (s->kind == TRIGGER) {
				if (rest[a] < -THRESHOLD)
					snprintf(out, size, "a%d", a);      /* full range */
				else
					snprintf(out, size, delta > 0 ? "+a%d" : "-a%d", a);
			} else {
				/* a button reported as a half axis (some D-pads) */
				snprintf(out, size, delta > 0 ? "+a%d" : "-a%d", a);
			}
			return 1;
		}
		SDL_Delay(10);
	}
	return 0;
}

/* Replace (or add) the line for `guid` in the DB file. */
static int
save_mapping(const char *db, const char *guid, const char *line)
{
	char tmp[4096];
	FILE *in = fopen(db, "r");
	snprintf(tmp, sizeof(tmp), "%s.tmp", db);
	FILE *out = fopen(tmp, "w");
	if (out == NULL) {
		perror(tmp);
		if (in != NULL)
			fclose(in);
		return -1;
	}
	if (in != NULL) {
		char buf[4096];
		while (fgets(buf, sizeof(buf), in) != NULL) {
			if (strncmp(buf, guid, strlen(guid)) == 0)
				continue;
			fputs(buf, out);
		}
		fclose(in);
	}
	fprintf(out, "%s\n", line);
	fclose(out);
	if (rename(tmp, db) != 0) {
		perror(db);
		return -1;
	}
	return 0;
}

static int
pick_index(int argc, char **argv)
{
	int count = SDL_NumJoysticks();
	int index = argc > 3 ? atoi(argv[3]) : 0;
	if (count <= 0) {
		fprintf(stderr, "No controllers found. Plug it in and check Haiku's "
			"Joysticks preferences.\n");
		return -1;
	}
	if (index < 0 || index >= count) {
		fprintf(stderr, "No controller %d (found %d). See 'sdv-gamepad list'.\n",
			index, count);
		return -1;
	}
	return index;
}

static int
cmd_map(const char *db, int index)
{
	char guid[64];
	char mapping[2048];
	SDL_Joystick *js = SDL_JoystickOpen(index);
	if (js == NULL) {
		fprintf(stderr, "Can't open controller: %s\n", SDL_GetError());
		return 1;
	}
	int naxes = SDL_JoystickNumAxes(js);
	int nbuttons = SDL_JoystickNumButtons(js);
	int nhats = SDL_JoystickNumHats(js);
	const char *name = SDL_JoystickName(js);
	guid_string(index, guid, sizeof(guid));

	printf("Mapping \"%s\" (%d axes, %d buttons, %d hats).\n", name, naxes,
		nbuttons, nhats);
	printf("Leave the sticks and triggers alone for a second...\n");
	read_rest(js, naxes);
	printf("Follow the prompts. If your controller doesn't have a button, "
		"wait %d seconds to skip it.\n\n", STEP_TIMEOUT_MS / 1000);

	/* Name must not contain commas in the mapping string. */
	char clean[256];
	snprintf(clean, sizeof(clean), "%s", name != NULL ? name : "Controller");
	for (char *c = clean; *c; c++)
		if (*c == ',')
			*c = ' ';

	int len = snprintf(mapping, sizeof(mapping), "%s,%s,", guid, clean);
	int mapped = 0;
	for (size_t i = 0; i < sizeof(steps) / sizeof(steps[0]); i++) {
		char binding[32];
		wait_released(js, naxes, nbuttons, nhats);
		printf("  %-48s ", steps[i].prompt);
		fflush(stdout);
		if (capture(js, &steps[i], naxes, nbuttons, nhats, binding,
				sizeof(binding))) {
			printf("-> %s\n", binding);
			len += snprintf(mapping + len, sizeof(mapping) - len, "%s:%s,",
				steps[i].key, binding);
			mapped++;
		} else {
			printf("-> skipped\n");
			if (mapped == 0 && i == 2) {
				fprintf(stderr, "\nNo input received from the controller at all. "
					"Run './gamepad.sh raw' to see what SDL reads from it.\n");
				SDL_JoystickClose(js);
				return 1;
			}
		}
	}
	snprintf(mapping + len, sizeof(mapping) - len, "platform:Haiku,");
	SDL_JoystickClose(js);

	if (mapped < 8) {
		fprintf(stderr, "\nOnly %d inputs mapped; not saving. Try again.\n", mapped);
		return 1;
	}
	if (save_mapping(db, guid, mapping) != 0)
		return 1;
	printf("\nSaved to %s\n%s\n", db, mapping);
	printf("Check it with: sdv-gamepad test \"%s\" %d\n", db, index);
	return 0;
}

/* Print raw joystick state whenever it changes, for 20 seconds. If nothing
 * changes while pressing buttons, SDL isn't receiving input from the driver. */
static int
cmd_raw(int index)
{
	SDL_Joystick *js = SDL_JoystickOpen(index);
	if (js == NULL) {
		fprintf(stderr, "Can't open controller: %s\n", SDL_GetError());
		return 1;
	}
	int naxes = SDL_JoystickNumAxes(js);
	int nbuttons = SDL_JoystickNumButtons(js);
	int nhats = SDL_JoystickNumHats(js);
	printf("Raw input from \"%s\" (%d axes, %d buttons, %d hats) for 20 seconds.\n"
		"Press buttons and move sticks; a line prints whenever anything changes.\n\n",
		SDL_JoystickName(js), naxes, nbuttons, nhats);

	char last[1024] = "";
	int changes = 0;
	Uint32 start = SDL_GetTicks();
	while (SDL_GetTicks() - start < 20000) {
		char line[1024];
		int len = 0;
		SDL_JoystickUpdate();
		len += snprintf(line + len, sizeof(line) - len, "axes:");
		for (int a = 0; a < naxes && len < (int)sizeof(line) - 16; a++)
			len += snprintf(line + len, sizeof(line) - len, " %6d", SDL_JoystickGetAxis(js, a));
		len += snprintf(line + len, sizeof(line) - len, "  buttons:");
		for (int b = 0; b < nbuttons && len < (int)sizeof(line) - 8; b++)
			if (SDL_JoystickGetButton(js, b))
				len += snprintf(line + len, sizeof(line) - len, " %d", b);
		len += snprintf(line + len, sizeof(line) - len, "  hats:");
		for (int h = 0; h < nhats && len < (int)sizeof(line) - 8; h++)
			len += snprintf(line + len, sizeof(line) - len, " %d", SDL_JoystickGetHat(js, h));
		if (strcmp(line, last) != 0) {
			printf("%s\n", line);
			fflush(stdout);
			snprintf(last, sizeof(last), "%s", line);
			changes++;
		}
		SDL_Delay(20);
	}
	SDL_JoystickClose(js);
	if (changes <= 1)
		printf("\nNothing changed: SDL got no input from the controller. Check that the\n"
			"driver delivers joystick data (Preferences > Joysticks) and that no other\n"
			"app has the controller open.\n");
	return 0;
}

static int
cmd_test(const char *db, int index)
{
	if (SDL_GameControllerAddMappingsFromFile(db) < 0)
		fprintf(stderr, "No mappings loaded from %s: %s\n", db, SDL_GetError());
	if (!SDL_IsGameController(index)) {
		fprintf(stderr, "Controller %d has no mapping yet; run 'sdv-gamepad map' first.\n", index);
		return 1;
	}
	SDL_GameController *gc = SDL_GameControllerOpen(index);
	if (gc == NULL) {
		fprintf(stderr, "Can't open as gamepad: %s\n", SDL_GetError());
		return 1;
	}
	printf("Testing \"%s\" as the game sees it. Press buttons and move sticks;\n"
		"press BACK and START together to finish.\n\n",
		SDL_GameControllerName(gc));

	SDL_Event ev;
	for (;;) {
		while (SDL_PollEvent(&ev)) {
			if (ev.type == SDL_CONTROLLERBUTTONDOWN)
				printf("  button %s\n", SDL_GameControllerGetStringForButton(
					(SDL_GameControllerButton)ev.cbutton.button));
			else if (ev.type == SDL_CONTROLLERAXISMOTION && abs(ev.caxis.value) > THRESHOLD)
				printf("  axis %s = %d\n", SDL_GameControllerGetStringForAxis(
					(SDL_GameControllerAxis)ev.caxis.axis), ev.caxis.value);
		}
		if (SDL_GameControllerGetButton(gc, SDL_CONTROLLER_BUTTON_BACK)
			&& SDL_GameControllerGetButton(gc, SDL_CONTROLLER_BUTTON_START))
			break;
		SDL_Delay(10);
	}
	SDL_GameControllerClose(gc);
	printf("Done.\n");
	return 0;
}

int
main(int argc, char **argv)
{
	if (argc < 2 || ((strcmp(argv[1], "map") == 0 || strcmp(argv[1], "test") == 0)
			&& argc < 3)) {
		fprintf(stderr, "usage: %s list | map DB [index] | test DB [index] | raw [index]\n", argv[0]);
		return 2;
	}
	if (init_sdl() != 0)
		return 1;

	int rc;
	if (strcmp(argv[1], "list") == 0) {
		rc = cmd_list();
	} else if (strcmp(argv[1], "raw") == 0) {
		int count = SDL_NumJoysticks();
		int index = argc > 2 ? atoi(argv[2]) : 0;
		if (index < 0 || index >= count) {
			fprintf(stderr, "No controller %d (found %d).\n", index, count);
			rc = 1;
		} else {
			rc = cmd_raw(index);
		}
	} else {
		int index = pick_index(argc, argv);
		if (index < 0)
			rc = 1;
		else if (strcmp(argv[1], "map") == 0)
			rc = cmd_map(argv[2], index);
		else if (strcmp(argv[1], "test") == 0)
			rc = cmd_test(argv[2], index);
		else {
			fprintf(stderr, "unknown command: %s\n", argv[1]);
			rc = 2;
		}
	}
	SDL_Quit();
	return rc;
}
