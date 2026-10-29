/*
 * C oracle for the Luau port: runs ioquake3's collision model and
 * OpenArena's bg_pmove/bg_slidemove/bg_misc natively and logs inputs and
 * outputs bit for bit, so tests/oracle/*.luau can replay the same inputs
 * through the port and diff the results. GPL-2.0.
 *
 *   oracle <map.bsp> patches <out>
 *   oracle <map.bsp> traces <count> <seed> <out>
 *   oracle <map.bsp> pmove <scenarios> <frames> <seed> <out>
 *
 * Floats are written as the hex of their IEEE bits.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>
#include <math.h>
#include "q_shared.h"
#include "bg_public.h"
#include "bg_local.h"

/* collision model entry points (ioquake3 cm_public.h) */
void CM_LoadMap(const char *name, qboolean clientload, int *checksum);
int CM_NumInlineModels(void);
char *CM_EntityString(void);
clipHandle_t CM_InlineModel(int index);
void CM_ModelBounds(clipHandle_t model, vec3_t mins, vec3_t maxs);
void CM_BoxTrace(trace_t *results, const vec3_t start, const vec3_t end, vec3_t mins, vec3_t maxs,
	clipHandle_t model, int brushmask, int capsule);
void CM_TransformedBoxTrace(trace_t *results, const vec3_t start, const vec3_t end, vec3_t mins, vec3_t maxs,
	clipHandle_t model, int brushmask, const vec3_t origin, const vec3_t angles, int capsule);
int CM_PointContents(const vec3_t p, clipHandle_t model);
int CM_TransformedPointContents(const vec3_t p, clipHandle_t model, const vec3_t origin, const vec3_t angles);
clipHandle_t CM_TempBoxModel(const vec3_t mins, const vec3_t maxs, int capsule);
void oracle_dump_patches(FILE *out);
int oracle_water_points(vec3_t *out, int max);
int oracle_num_patches(void);
int oracle_patch_point(int which, vec3_t out);

/* engine/game glue bg_* expects */
vmCvar_t cg_enableQ;
/* the engine's qsnapvectorsse: cvtps2dq + cvtdq2ps (round to nearest even
 * through an int, so -0.3 snaps to +0, not rintf's -0) */
void trap_SnapVector(float *v) { v[0] = (float)(int)rintf(v[0]); v[1] = (float)(int)rintf(v[1]); v[2] = (float)(int)rintf(v[2]); }
int trap_FS_FOpenFile(const char *qpath, fileHandle_t *f, fsMode_t mode) { *f = 0; return -1; }
void trap_FS_Read(void *buffer, int len, fileHandle_t f) {}
void trap_FS_FCloseFile(fileHandle_t f) {}
void QDECL Com_Error(int level, const char *error, ...) {
	va_list ap;
	va_start(ap, error);
	vfprintf(stderr, error, ap);
	va_end(ap);
	fprintf(stderr, "\n");
	exit(1);
}
void QDECL Com_Printf(const char *msg, ...) {}

static FILE *out;
static unsigned rng = 1;
static unsigned xr(void) { rng ^= rng << 13; rng ^= rng >> 17; rng ^= rng << 5; return rng; }
static float fr(void) { return (xr() & 0xffffff) / (float)0x1000000; } /* [0,1) */
static float crand(void) { return fr() * 2 - 1; }
static int ir(int n) { return (int)(xr() % (unsigned)n); }

static unsigned fb(float v) { unsigned u; memcpy(&u, &v, 4); return u; }
static void pf(float v) { fprintf(out, " %08x", fb(v)); }
static void pv(const vec3_t v) { pf(v[0]); pf(v[1]); pf(v[2]); }
static void pi(int v) { fprintf(out, " %d", v); }

/* ------------------------------------------------------------------ entities */

#define MAX_ENTS 2048
typedef struct {
	char classname[64], model[16], target[64], targetname[64];
	vec3_t origin, angles;
	int hasOrigin;
} ent_t;
static ent_t ents[MAX_ENTS];
static int numEnts;

static void parse_entities(void) {
	char *p = CM_EntityString();
	char *tok;
	numEnts = 0;
	while (1) {
		tok = COM_Parse(&p);
		if (!p || tok[0] != '{') break;
		ent_t *e = &ents[numEnts];
		memset(e, 0, sizeof(*e));
		while (1) {
			char key[64];
			tok = COM_Parse(&p);
			if (tok[0] == '}' || !p) break;
			Q_strncpyz(key, tok, sizeof(key));
			tok = COM_Parse(&p);
			if (!Q_stricmp(key, "classname")) Q_strncpyz(e->classname, tok, sizeof(e->classname));
			else if (!Q_stricmp(key, "model")) Q_strncpyz(e->model, tok, sizeof(e->model));
			else if (!Q_stricmp(key, "target")) Q_strncpyz(e->target, tok, sizeof(e->target));
			else if (!Q_stricmp(key, "targetname")) Q_strncpyz(e->targetname, tok, sizeof(e->targetname));
			else if (!Q_stricmp(key, "origin")) { sscanf(tok, "%f %f %f", &e->origin[0], &e->origin[1], &e->origin[2]); e->hasOrigin = 1; }
			else if (!Q_stricmp(key, "angle")) { e->angles[1] = atof(tok); }
			else if (!Q_stricmp(key, "angles")) { sscanf(tok, "%f %f %f", &e->angles[0], &e->angles[1], &e->angles[2]); }
		}
		if (numEnts < MAX_ENTS - 1) numEnts++;
	}
}

static ent_t *find_target(const char *name) {
	int i;
	for (i = 0; i < numEnts; i++) if (ents[i].targetname[0] && !strcmp(ents[i].targetname, name)) return &ents[i];
	return NULL;
}

/* trigger_push / trigger_teleport stand-ins: velocity from AimAtTarget,
 * destination from TeleportPlayer's target */
#define MAX_TRIGGERS 64
typedef struct {
	int type; /* 0 push, 1 teleport */
	int model, entnum;
	vec3_t vec;    /* push: origin2 velocity; teleport: dest origin */
	vec3_t angles; /* teleport: dest angles */
	vec3_t center;
} trigger_t;
static trigger_t triggers[MAX_TRIGGERS];
static int numTriggers;

static void find_triggers(void) {
	int i;
	numTriggers = 0;
	for (i = 0; i < numEnts && numTriggers < MAX_TRIGGERS; i++) {
		ent_t *e = &ents[i];
		trigger_t *t = &triggers[numTriggers];
		vec3_t mins, maxs, origin;
		ent_t *dest;
		int push = !strcmp(e->classname, "trigger_push"), tele = !strcmp(e->classname, "trigger_teleport");
		if ((!push && !tele) || e->model[0] != '*' || !e->target[0]) continue;
		dest = find_target(e->target);
		if (!dest) continue;
		t->model = CM_InlineModel(atoi(e->model + 1));
		t->entnum = 64 + i;
		CM_ModelBounds(t->model, mins, maxs);
		VectorAdd(mins, maxs, origin);
		VectorScale(origin, 0.5, origin);
		VectorCopy(origin, t->center);
		if (push) {
			/* AimAtTarget with g_gravity 800 */
			float height, gravity, time, forward, dist;
			height = dest->origin[2] - origin[2];
			gravity = 800;
			time = sqrt(height / (.5 * gravity));
			if (!time) continue;
			VectorSubtract(dest->origin, origin, t->vec);
			t->vec[2] = 0;
			dist = VectorNormalize(t->vec);
			forward = dist / time;
			VectorScale(t->vec, forward, t->vec);
			t->vec[2] = time * gravity;
			t->type = 0;
		} else {
			VectorCopy(dest->origin, t->vec);
			VectorCopy(dest->angles, t->angles);
			t->type = 1;
		}
		numTriggers++;
	}
}

/* -------------------------------------------------------------------- traces */

static void log_trace(const trace_t *t) {
	pi(t->allsolid); pi(t->startsolid); pf(t->fraction); pv(t->endpos);
	pv(t->plane.normal); pf(t->plane.dist); pi(t->plane.type); pi(t->plane.signbits);
	pi(t->surfaceFlags); pi(t->contents);
}

static void random_point_near(vec3_t p, vec3_t wmins, vec3_t wmaxs) {
	int i;
	if (numEnts > 1 && ir(4)) {
		ent_t *e;
		do e = &ents[ir(numEnts)]; while (!e->hasOrigin && ir(8));
		for (i = 0; i < 3; i++) p[i] = e->origin[i] + crand() * 160;
	} else {
		for (i = 0; i < 3; i++) p[i] = wmins[i] + fr() * (wmaxs[i] - wmins[i]);
	}
}

static void run_traces(int count) {
	vec3_t wmins, wmaxs;
	int n, i, nmodels = CM_NumInlineModels();
	CM_ModelBounds(0, wmins, wmaxs);
	for (n = 0; n < count; n++) {
		vec3_t start, end, mins, maxs, origin = {0, 0, 0}, angles = {0, 0, 0};
		int kind = ir(10), model = 0, capsule = 0, mask = MASK_PLAYERSOLID;
		trace_t tr;
		random_point_near(start, wmins, wmaxs);
		if (ir(3)) {
			float len = fr() * fr() * 600;
			for (i = 0; i < 3; i++) end[i] = start[i] + crand() * len;
			if (!ir(4)) { end[0] = start[0]; end[1] = start[1]; end[2] = start[2] - len; } /* ground probe */
		} else {
			random_point_near(end, wmins, wmaxs);
		}
		switch (ir(4)) {
		case 0: mask = MASK_PLAYERSOLID; break;
		case 1: mask = MASK_SHOT; break;
		case 2: mask = CONTENTS_SOLID | CONTENTS_WATER | CONTENTS_SLIME | CONTENTS_LAVA; break;
		default: mask = -1; break;
		}
		VectorClear(mins); VectorClear(maxs);
		if (kind == 0) {
			/* point trace */
		} else if (kind == 1 || kind == 4 || kind == 5) {
			VectorSet(mins, -15, -15, -24); VectorSet(maxs, 15, 15, ir(2) ? 32 : 16);
		} else if (kind == 2) {
			for (i = 0; i < 3; i++) { mins[i] = -fr() * 40; maxs[i] = fr() * 40; }
		} else {
			VectorSet(mins, -15, -15, -24); VectorSet(maxs, 15, 15, 32);
		}
		if (kind == 4) VectorCopy(start, end);           /* position test */
		if (kind == 5) capsule = 1;                      /* capsule sweep */
		if (kind >= 6 && kind <= 7 && nmodels > 1) {      /* moving/rotating bmodel */
			model = CM_InlineModel(1 + ir(nmodels - 1));
			vec3_t bmins, bmaxs;
			CM_ModelBounds(model, bmins, bmaxs);
			for (i = 0; i < 3; i++) {
				origin[i] = ir(2) ? 0 : crand() * 64;
				start[i] = (bmins[i] + bmaxs[i]) * 0.5f + origin[i] + crand() * 200;
				end[i] = start[i] + crand() * 300;
			}
			if (kind == 7) for (i = 0; i < 3; i++) angles[i] = ir(3) ? crand() * 180 : 0;
			if (!ir(5)) VectorCopy(start, end);
		}
		if (kind == 8) {                                 /* clip against an entity box */
			vec3_t emins = {-15, -15, -24}, emaxs = {15, 15, 32};
			model = CM_TempBoxModel(emins, emaxs, 0);
			for (i = 0; i < 3; i++) { origin[i] = start[i] + crand() * 80; end[i] = origin[i] + crand() * 80; }
		}
		fprintf(out, "T"); pi(kind); pv(start); pv(end); pv(mins); pv(maxs); pi(model); pi(mask); pi(capsule);
		pv(origin); pv(angles);
		if (kind == 8) {
			vec3_t emins = {-15, -15, -24}, emaxs = {15, 15, 32};
			model = CM_TempBoxModel(emins, emaxs, 0);
		}
		if (model) CM_TransformedBoxTrace(&tr, start, end, mins, maxs, model, mask, origin, angles, capsule);
		else CM_BoxTrace(&tr, start, end, mins, maxs, 0, mask, capsule);
		fprintf(out, " |");
		log_trace(&tr);
		/* point contents at both ends */
		pi(model ? CM_TransformedPointContents(start, model, origin, angles) : CM_PointContents(start, 0));
		pi(CM_PointContents(end, 0));
		fprintf(out, "\n");
	}
}

/* --------------------------------------------------------------------- pmove */

static void pm_trace(trace_t *results, const vec3_t start, const vec3_t mins, const vec3_t maxs,
	const vec3_t end, int passEntityNum, int contentMask) {
	CM_BoxTrace(results, start, end, (float *)mins, (float *)maxs, 0, contentMask, 0);
	results->entityNum = results->fraction != 1.0 ? ENTITYNUM_WORLD : ENTITYNUM_NONE;
}
static int pm_pointcontents(const vec3_t p, int passEntityNum) { return CM_PointContents(p, 0); }

static void log_ps(const playerState_t *ps) {
	int i;
	pi(ps->commandTime); pi(ps->pm_type); pi(ps->bobCycle); pi(ps->pm_flags); pi(ps->pm_time);
	pv(ps->origin); pv(ps->velocity);
	pi(ps->weaponTime); pi(ps->gravity); pi(ps->speed);
	for (i = 0; i < 3; i++) pi(ps->delta_angles[i]);
	pi(ps->groundEntityNum); pi(ps->legsTimer); pi(ps->legsAnim); pi(ps->torsoTimer); pi(ps->torsoAnim);
	pi(ps->movementDir); pv(ps->grapplePoint); pi(ps->eFlags); pi(ps->eventSequence);
	for (i = 0; i < MAX_PS_EVENTS; i++) { pi(ps->events[i]); pi(ps->eventParms[i]); }
	pi(ps->externalEvent); pi(ps->externalEventParm); pi(ps->externalEventTime);
	pi(ps->clientNum); pi(ps->weapon); pi(ps->weaponstate); pv(ps->viewangles); pi(ps->viewheight);
	pi(ps->damageEvent); pi(ps->damageYaw); pi(ps->damagePitch); pi(ps->damageCount);
	for (i = 0; i < MAX_STATS; i++) pi(ps->stats[i]);
	for (i = 0; i < MAX_PERSISTANT; i++) pi(ps->persistant[i]);
	for (i = 0; i < MAX_POWERUPS; i++) pi(ps->powerups[i]);
	for (i = 0; i < MAX_WEAPONS; i++) pi(ps->ammo[i]);
	pi(ps->generic1); pi(ps->loopSound); pi(ps->jumppad_ent);
	pi(ps->ping); pi(ps->pmove_framecount); pi(ps->jumppad_frame); pi(ps->entityEventSequence);
}

static void log_cmd(const usercmd_t *c) {
	pi(c->serverTime); pi(c->angles[0]); pi(c->angles[1]); pi(c->angles[2]);
	pi(c->buttons); pi(c->weapon); pi(c->forwardmove); pi(c->rightmove); pi(c->upmove);
}

static void apply_triggers(playerState_t *ps, const pmove_t *pm, const usercmd_t *cmd) {
	int i;
	for (i = 0; i < numTriggers; i++) {
		trigger_t *t = &triggers[i];
		vec3_t mins, maxs;
		trace_t tr;
		VectorAdd(ps->origin, pm->mins, mins);
		VectorAdd(ps->origin, pm->maxs, maxs);
		CM_TransformedBoxTrace(&tr, vec3_origin, vec3_origin, mins, maxs, t->model, -1, vec3_origin, vec3_origin, 0);
		if (!tr.startsolid) continue;
		if (t->type == 0) {
			entityState_t es;
			memset(&es, 0, sizeof(es));
			es.number = t->entnum;
			VectorCopy(t->vec, es.origin2);
			BG_TouchJumpPad(ps, &es);
		} else {
			int j;
			VectorCopy(t->vec, ps->origin);
			ps->origin[2] += 1;
			AngleVectors(t->angles, ps->velocity, NULL, NULL);
			VectorScale(ps->velocity, 400, ps->velocity);
			ps->pm_time = 160;
			ps->pm_flags |= PMF_TIME_KNOCKBACK;
			for (j = 0; j < 3; j++) ps->delta_angles[j] = ANGLE2SHORT(t->angles[j]) - cmd->angles[j];
			VectorCopy(t->angles, ps->viewangles);
			ps->eFlags ^= EF_TELEPORT_BIT;
		}
	}
}

static int spawn_points(vec3_t *pts, int max) {
	int i, n = 0;
	for (i = 0; i < numEnts && n < max; i++) {
		if (!strncmp(ents[i].classname, "info_player", 11) || !strncmp(ents[i].classname, "team_CTF_", 9)) {
			VectorCopy(ents[i].origin, pts[n]);
			pts[n][2] += 9;
			n++;
		}
	}
	return n;
}

static void pick_target(vec3_t target, vec3_t *water, int nwater) {
	int k = ir(5);
	if (k == 0 && numTriggers) {
		VectorCopy(triggers[ir(numTriggers)].center, target);
	} else if (k == 1 && nwater) {
		VectorCopy(water[ir(nwater)], target);
	} else if (k == 2 && oracle_num_patches()) {
		oracle_patch_point(ir(oracle_num_patches()), target);
	} else {
		ent_t *e;
		do e = &ents[ir(numEnts)]; while (!e->hasOrigin);
		VectorCopy(e->origin, target);
	}
}

static void run_pmove(int scenarios, int frames) {
	vec3_t spawns[256], water[64];
	int nspawns, nwater, s, i;
	nspawns = spawn_points(spawns, 256);
	nwater = oracle_water_points(water, 64);
	if (!nspawns) Com_Error(0, "no spawn points");

	fprintf(out, "H %d\n", numTriggers);
	for (i = 0; i < numTriggers; i++) {
		fprintf(out, "G"); pi(triggers[i].type); pi(triggers[i].model); pi(triggers[i].entnum);
		pv(triggers[i].vec); pv(triggers[i].angles); fprintf(out, "\n");
	}

	for (s = 0; s < scenarios; s++) {
		playerState_t ps;
		usercmd_t cmd;
		pmove_t pm;
		int kind = s % 5, f, hold = 0, strafeDir = 1, stuck = 0, pflags, pfloat, nobunny;
		float yaw, pitch = 0;
		vec3_t target;

		memset(&ps, 0, sizeof(ps));
		memset(&cmd, 0, sizeof(cmd));
		VectorCopy(spawns[ir(nspawns)], ps.origin);
		ps.gravity = 800;
		ps.speed = 320;
		ps.clientNum = s % 64;
		ps.groundEntityNum = ENTITYNUM_NONE;
		ps.stats[STAT_HEALTH] = 100;
		ps.stats[STAT_MAX_HEALTH] = 100;
		ps.stats[STAT_WEAPONS] = (1 << WP_GAUNTLET) | (1 << WP_MACHINEGUN) | (1 << WP_SHOTGUN) | (1 << WP_ROCKET_LAUNCHER) | (1 << WP_RAILGUN) | (1 << WP_LIGHTNING) | (1 << WP_PLASMAGUN);
		for (i = 1; i < WP_NUM_WEAPONS; i++) ps.ammo[i] = ir(3) ? 50 : 0;
		ps.ammo[WP_GAUNTLET] = -1;
		ps.weapon = WP_MACHINEGUN;
		ps.weaponstate = WEAPON_READY;
		ps.commandTime = 1000 + ir(1000);
		ps.pm_flags = ir(2) ? PMF_RESPAWNED : 0;
		yaw = fr() * 360;
		pflags = 0;
		nobunny = !ir(5);
		if (nobunny) pflags |= DF_NO_BUNNY;
		if (!ir(4)) pflags |= DF_INSTANT_WEAPON_CHANGE;
		if (!ir(4)) pflags |= DF_FAST_WATER_MOVE;
		pfloat = !ir(3);
		/* special movement states */
		switch (ir(12)) {
		case 0: ps.powerups[PW_FLIGHT] = 999999; break;
		case 1: ps.pm_type = PM_SPECTATOR; break;
		case 2: ps.pm_type = PM_NOCLIP; break;
		case 3: ps.speed = 416; ps.powerups[PW_HASTE] = 999999; break;
		case 4: ps.stats[STAT_HEALTH] = 0; ps.pm_type = PM_DEAD; break;
		case 5: ps.powerups[PW_INVULNERABILITY] = 999999; if (ir(2)) ps.pm_flags |= PMF_INVULEXPAND; break;
		case 6: ps.pm_flags |= PMF_GRAPPLE_PULL; VectorCopy(ps.origin, ps.grapplePoint); ps.grapplePoint[0] += crand() * 500; ps.grapplePoint[2] += 200; break;
		default: break;
		}
		pick_target(target, water, nwater);
		fprintf(out, "S %d %d %d %d\n", s, kind, pflags, pfloat);

		for (f = 0; f < frames; f++) {
			playerState_t in;
			int msec, r = ir(100);
			/* client frame times, with the occasional hitch to exercise Pmove's chopping */
			msec = r < 70 ? 8 + ir(26) : r < 85 ? 1 + ir(7) : r < 97 ? 34 + ir(40) : 70 + ir(200);
			cmd.serverTime = ps.commandTime + msec;

			if (kind == 0) {
				/* strafe jumping */
				if (--hold <= 0) { strafeDir = -strafeDir; hold = 25 + ir(40); }
				cmd.forwardmove = 127;
				cmd.rightmove = 127 * strafeDir;
				yaw += strafeDir * -(1.0f + fr() * 2.5f);
				cmd.upmove = ps.groundEntityNum != ENTITYNUM_NONE ? 127 : 0;
				if (!ir(150)) yaw += crand() * 90;
			} else if (kind == 1) {
				/* random input held for a while */
				if (--hold <= 0) {
					int mv[] = {-127, -64, 0, 0, 64, 127, 127};
					hold = 5 + ir(40);
					cmd.forwardmove = mv[ir(7)];
					cmd.rightmove = mv[ir(7)];
					cmd.upmove = ir(4) == 0 ? -127 : ir(3) == 0 ? 127 : 0;
					cmd.buttons = 0;
					if (!ir(3)) cmd.buttons |= BUTTON_ATTACK;
					if (!ir(6)) cmd.buttons |= BUTTON_WALKING;
					if (!ir(15)) cmd.buttons |= BUTTON_GESTURE << ir(4);
					if (!ir(25)) cmd.buttons |= BUTTON_TALK;
					if (!ir(10)) cmd.buttons |= BUTTON_USE_HOLDABLE;
					cmd.weapon = ir(4) ? ps.weapon : ir(WP_NUM_WEAPONS);
					pitch = crand() * 80;
				}
				yaw += crand() * 4;
			} else {
				/* steer toward a jump pad, teleporter, water, patch or entity */
				vec3_t d;
				float want, hspeed;
				VectorSubtract(target, ps.origin, d);
				if (VectorLength(d) < 48 || --hold < -400) { pick_target(target, water, nwater); hold = 0; }
				want = atan2(d[1], d[0]) * 180 / M_PI;
				yaw += AngleSubtract(want, yaw) * 0.2f;
				pitch = d[2] < -64 ? 40 : d[2] > 64 ? -40 : 0;
				cmd.forwardmove = 127;
				cmd.rightmove = kind == 3 ? (ir(2) ? 127 : -127) : 0;
				if (kind == 4 && VectorLength(d) < 48 && numTriggers) VectorCopy(triggers[ir(numTriggers)].center, target);
				hspeed = sqrt(ps.velocity[0] * ps.velocity[0] + ps.velocity[1] * ps.velocity[1]);
				stuck = hspeed < 60 ? stuck + 1 : 0;
				cmd.upmove = (stuck > 5 && !ir(3)) || (d[2] > 40 && !ir(2)) ? 127 : (ir(40) ? 0 : -127);
				cmd.buttons = ir(3) ? 0 : BUTTON_ATTACK;
			}
			cmd.angles[YAW] = ANGLE2SHORT(yaw) - ps.delta_angles[YAW];
			cmd.angles[PITCH] = ANGLE2SHORT(pitch) - ps.delta_angles[PITCH];
			cmd.angles[ROLL] = 0;
			if (kind != 1) cmd.weapon = ps.weapon;

			memset(&pm, 0, sizeof(pm));
			pm.ps = &ps;
			pm.cmd = cmd;
			pm.tracemask = ps.pm_type == PM_DEAD ? MASK_PLAYERSOLID & ~CONTENTS_BODY : MASK_PLAYERSOLID;
			if (ps.pm_type == PM_SPECTATOR) pm.tracemask = MASK_PLAYERSOLID & ~CONTENTS_BODY;
			pm.trace = pm_trace;
			pm.pointcontents = pm_pointcontents;
			pm.debugLevel = 0;
			pm.noFootsteps = 0;
			pm.pmove_fixed = 0;
			pm.pmove_msec = 8;
			pm.pmove_float = pfloat;
			pm.pmove_flags = pflags;

			in = ps;
			fprintf(out, "I"); pi(f); log_ps(&in); log_cmd(&cmd);
			pi(pm.tracemask); pi(pm.pmove_fixed); pi(pm.pmove_msec); pi(pm.pmove_float); pi(pm.pmove_flags);
			fprintf(out, "\n");

			Pmove(&pm);

			fprintf(out, "O"); log_ps(&ps);
			pi(pm.numtouch);
			for (i = 0; i < pm.numtouch; i++) pi(pm.touchents[i]);
			pv(pm.mins); pv(pm.maxs); pi(pm.watertype); pi(pm.waterlevel); pf(pm.xyspeed);
			fprintf(out, "\n");

			apply_triggers(&ps, &pm, &cmd);
			fprintf(out, "A"); log_ps(&ps); fprintf(out, "\n");

			/* kind 4: hop onto a jump pad / teleporter trigger every 150 frames */
			if (kind == 4 && numTriggers && f % 150 == 0) {
				trigger_t *t = &triggers[ir(numTriggers)];
				VectorCopy(t->center, ps.origin);
				VectorClear(ps.velocity);
				ps.eFlags ^= EF_TELEPORT_BIT;
				VectorCopy(triggers[ir(numTriggers)].center, target);
				fprintf(out, "R"); log_ps(&ps); fprintf(out, "\n");
			} else
			/* respawn when stuck in the void or dead for good */
			if (ps.origin[2] < -20000 || (ps.pm_type == PM_NORMAL && f % 600 == 599 && !ir(3))) {
				VectorCopy(spawns[ir(nspawns)], ps.origin);
				VectorClear(ps.velocity);
				ps.eFlags ^= EF_TELEPORT_BIT;
				fprintf(out, "R"); log_ps(&ps); fprintf(out, "\n");
			}
		}
	}
}

int main(int argc, char **argv) {
	int checksum;
	if (argc < 4) {
		fprintf(stderr, "usage: oracle <map.bsp> patches|traces|pmove ...\n");
		return 1;
	}
	CM_LoadMap(argv[1], qfalse, &checksum);
	parse_entities();
	find_triggers();
	if (!strcmp(argv[2], "patches")) {
		out = fopen(argv[3], "w");
		oracle_dump_patches(out);
	} else if (!strcmp(argv[2], "traces") && argc >= 6) {
		rng = (unsigned)atoi(argv[4]) * 2654435761u + 1;
		out = fopen(argv[5], "w");
		run_traces(atoi(argv[3]));
	} else if (!strcmp(argv[2], "pmove") && argc >= 7) {
		rng = (unsigned)atoi(argv[5]) * 2654435761u + 1;
		out = fopen(argv[6], "w");
		run_pmove(atoi(argv[3]), atoi(argv[4]));
	} else {
		fprintf(stderr, "bad arguments\n");
		return 1;
	}
	fclose(out);
	return 0;
}
