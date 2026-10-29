/*
 * C oracle for the bot port: ioquake3's botlib compiled natively with a
 * minimal botlib import (traces and point contents from ioquake3's
 * collision model), loading a real .bsp + .aas. It writes the inputs and
 * outputs of AAS queries bit for bit, so tests/bots/oracle_*.luau can
 * replay the same inputs through the Luau port and diff. GPL-2.0.
 *
 *   oracle-bots <map.bsp> <map.aas> info
 *   oracle-bots <map.bsp> <map.aas> reach
 *   oracle-bots <map.bsp> <map.aas> areas <count> <seed>
 *   oracle-bots <map.bsp> <map.aas> travel <count> <seed>
 *   oracle-bots <map.bsp> <map.aas> trace <count> <seed>
 *   oracle-bots <map.bsp> <map.aas> predict <count> <seed>
 *
 * Floats are printed as the hex of their IEEE bits.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>
#include "q_shared.h"
#include "qcommon.h"
#include "cm_public.h"
#include "l_memory.h"
#include "l_libvar.h"
#include "l_utils.h"
#include "l_script.h"
#include "l_precomp.h"
#include "l_struct.h"
#include "aasfile.h"
#include "botlib.h"
#include "be_aas.h"
#include "be_aas_funcs.h"
#include "be_interface.h"
#include "be_aas_def.h"

extern aas_t aasworld;
aas_trace_t AAS_TraceClientBBox(vec3_t start, vec3_t end, int presencetype, int passent);
int AAS_AreaRouteToGoalArea(int areanum, vec3_t origin, int goalareanum, int travelflags, int *traveltime, int *reachnum);

static const char *aaspath;
static botlib_export_t *be;

/* ---- engine glue the collision model and q_shared need ---- */
void QDECL Com_Printf(const char *fmt, ...) {}
void QDECL Com_DPrintf(const char *fmt, ...) {}
void QDECL Com_Error(int level, const char *fmt, ...) {
	va_list ap;
	va_start(ap, fmt);
	vfprintf(stderr, fmt, ap);
	va_end(ap);
	exit(1);
}
void *Hunk_Alloc(int size, ha_pref preference) { return calloc(1, size); }
void *Z_Malloc(int size) { return calloc(1, size); }
void Z_Free(void *ptr) { free(ptr); }
void BotDrawDebugPolygons(void (*drawPoly)(int color, int numPoints, float *points), int value) {}
cvar_t *Cvar_Get(const char *name, const char *value, int flags) {
	cvar_t *c = calloc(1, sizeof(*c));
	c->name = strdup(name);
	c->string = strdup(value);
	c->value = atof(value);
	c->integer = atoi(value);
	return c;
}
long FS_ReadFile(const char *qpath, void **buffer) {
	FILE *f = fopen(qpath, "rb");
	long len;
	if (!f) { *buffer = NULL; return -1; }
	fseek(f, 0, SEEK_END);
	len = ftell(f);
	fseek(f, 0, SEEK_SET);
	*buffer = malloc(len + 1);
	if (fread(*buffer, 1, len, f) != (size_t)len) { fclose(f); *buffer = NULL; return -1; }
	fclose(f);
	return len;
}
void FS_FreeFile(void *buffer) { free(buffer); }
char *Cvar_VariableString(const char *var_name) { return ""; }
char *FS_BuildOSPath(const char *base, const char *game, const char *qpath) { return "/dev/null"; }

/* ---- botlib import ---- */
static void QDECL BI_Print(int type, char *fmt, ...) {
	va_list ap;
	va_start(ap, fmt);
	vfprintf(stderr, fmt, ap);
	va_end(ap);
}
static void BI_Trace(bsp_trace_t *bt, vec3_t start, vec3_t mins, vec3_t maxs, vec3_t end, int passent, int contentmask) {
	trace_t t;
	CM_BoxTrace(&t, start, end, mins, maxs, 0, contentmask, qfalse);
	bt->allsolid = t.allsolid;
	bt->startsolid = t.startsolid;
	bt->fraction = t.fraction;
	VectorCopy(t.endpos, bt->endpos);
	bt->plane.dist = t.plane.dist;
	VectorCopy(t.plane.normal, bt->plane.normal);
	bt->plane.signbits = t.plane.signbits;
	bt->plane.type = t.plane.type;
	bt->surface.value = 0;
	bt->surface.flags = t.surfaceFlags;
	bt->ent = t.fraction < 1.0f ? ENTITYNUM_WORLD : ENTITYNUM_NONE;
	bt->exp_dist = 0;
	bt->sidenum = 0;
	bt->contents = 0;
}
static void BI_EntityTrace(bsp_trace_t *bt, vec3_t start, vec3_t mins, vec3_t maxs, vec3_t end, int entnum, int contentmask) {
	memset(bt, 0, sizeof(*bt));
	bt->fraction = 1;
	VectorCopy(end, bt->endpos);
	bt->ent = ENTITYNUM_NONE;
}
static int BI_PointContents(vec3_t p) { return CM_PointContents(p, 0); }
static int BI_inPVS(vec3_t p1, vec3_t p2) { return 1; }
static char *BI_BSPEntityData(void) { return CM_EntityString(); }
static void BI_BSPModelMinsMaxsOrigin(int modelnum, vec3_t angles, vec3_t outmins, vec3_t outmaxs, vec3_t origin) {
	vec3_t mins, maxs;
	int i;
	CM_ModelBounds(CM_InlineModel(modelnum), mins, maxs);
	if (angles[0] || angles[1] || angles[2]) {
		float max = RadiusFromBounds(mins, maxs);
		for (i = 0; i < 3; i++) { mins[i] = -max; maxs[i] = max; }
	}
	if (outmins) VectorCopy(mins, outmins);
	if (outmaxs) VectorCopy(maxs, outmaxs);
	if (origin) VectorClear(origin);
}
static void BI_BotClientCommand(int client, char *command) {}
static void *BI_GetMemory(int size) { return malloc(size); }
static void BI_FreeMemory(void *p) { free(p); }
static int BI_AvailableMemory(void) { return 256 * 1024 * 1024; }
static void *BI_HunkAlloc(int size) { return calloc(1, size); }
static FILE *files[64];
static int BI_FS_FOpenFile(const char *qpath, fileHandle_t *f, fsMode_t mode) {
	const char *path = qpath;
	int i;
	FILE *fp;
	long len;
	if (strlen(qpath) > 4 && !strcmp(qpath + strlen(qpath) - 4, ".aas")) path = aaspath;
	fp = fopen(path, mode == FS_READ ? "rb" : "wb");
	if (!fp) { *f = 0; return -1; }
	for (i = 1; i < 64 && files[i]; i++);
	files[i] = fp;
	*f = i;
	fseek(fp, 0, SEEK_END);
	len = ftell(fp);
	fseek(fp, 0, SEEK_SET);
	return len;
}
static int BI_FS_Read(void *buffer, int len, fileHandle_t f) { return fread(buffer, 1, len, files[f]); }
static int BI_FS_Write(const void *buffer, int len, fileHandle_t f) { return fwrite(buffer, 1, len, files[f]); }
static void BI_FS_FCloseFile(fileHandle_t f) { fclose(files[f]); files[f] = NULL; }
static int BI_FS_Seek(fileHandle_t f, long offset, int origin) { return fseek(files[f], offset, SEEK_SET); }
static int BI_DebugLineCreate(void) { return 0; }
static void BI_DebugLineDelete(int line) {}
static void BI_DebugLineShow(int line, vec3_t start, vec3_t end, int color) {}
static int BI_DebugPolygonCreate(int color, int numPoints, vec3_t *points) { return 0; }
static void BI_DebugPolygonDelete(int id) {}

/* ---- helpers ---- */
static unsigned fb(float v) { unsigned u; memcpy(&u, &v, 4); return u; }
static unsigned rngstate;
static unsigned rnd(void) { rngstate = rngstate * 1103515245u + 12345u; return (rngstate >> 8) & 0xffffff; }
static float rndf(void) { return (float)rnd() / (float)0x1000000; }	/* [0,1) */
static int rndi(int n) { return rnd() % n; }
static void pv(FILE *o, const float *v) { fprintf(o, " %08x %08x %08x", fb(v[0]), fb(v[1]), fb(v[2])); }
/* a point in an area's box grown by 16 units, or anywhere in the world box */
static void rndpoint(vec3_t p) {
	int i;
	if (rndi(4) == 0) {
		aas_area_t *w = &aasworld.areas[1];
		vec3_t mins, maxs;
		VectorCopy(w->mins, mins); VectorCopy(w->maxs, maxs);
		for (i = 1; i < aasworld.numareas; i++) {
			AddPointToBounds(aasworld.areas[i].mins, mins, maxs);
			AddPointToBounds(aasworld.areas[i].maxs, mins, maxs);
		}
		for (i = 0; i < 3; i++) p[i] = mins[i] + rndf() * (maxs[i] - mins[i]);
	} else {
		aas_area_t *a = &aasworld.areas[1 + rndi(aasworld.numareas - 1)];
		for (i = 0; i < 3; i++) p[i] = a->mins[i] - 16 + rndf() * (a->maxs[i] - a->mins[i] + 32);
	}
}
static int rndreacharea(void) {
	int i, a;
	for (i = 0; i < 1000; i++) {
		a = 1 + rndi(aasworld.numareas - 1);
		if (AAS_AreaReachability(a)) return a;
	}
	return 1;
}

int main(int argc, char **argv) {
	botlib_import_t bi;
	int checksum, i, j, n;
	char buf[64], mapname[MAX_QPATH];
	const char *cmd;
	FILE *o = stdout;

	if (argc < 4) { fprintf(stderr, "usage: oracle-bots <map.bsp> <map.aas> <command> ...\n"); return 2; }
	aaspath = argv[2];
	cmd = argv[3];
	CM_LoadMap(argv[1], qfalse, &checksum);

	memset(&bi, 0, sizeof(bi));
	bi.Print = BI_Print; bi.Trace = BI_Trace; bi.EntityTrace = BI_EntityTrace;
	bi.PointContents = BI_PointContents; bi.inPVS = BI_inPVS; bi.BSPEntityData = BI_BSPEntityData;
	bi.BSPModelMinsMaxsOrigin = BI_BSPModelMinsMaxsOrigin; bi.BotClientCommand = BI_BotClientCommand;
	bi.GetMemory = BI_GetMemory; bi.FreeMemory = BI_FreeMemory; bi.AvailableMemory = BI_AvailableMemory;
	bi.HunkAlloc = BI_HunkAlloc; bi.FS_FOpenFile = BI_FS_FOpenFile; bi.FS_Read = BI_FS_Read;
	bi.FS_Write = BI_FS_Write; bi.FS_FCloseFile = BI_FS_FCloseFile; bi.FS_Seek = BI_FS_Seek;
	bi.DebugLineCreate = BI_DebugLineCreate; bi.DebugLineDelete = BI_DebugLineDelete;
	bi.DebugLineShow = BI_DebugLineShow; bi.DebugPolygonCreate = BI_DebugPolygonCreate;
	bi.DebugPolygonDelete = BI_DebugPolygonDelete;
	be = GetBotLibAPI(BOTLIB_API_VERSION, &bi);
	if (!be) { fprintf(stderr, "GetBotLibAPI failed\n"); return 1; }
	Com_sprintf(buf, sizeof(buf), "%i", checksum);
	be->BotLibVarSet("sv_mapChecksum", buf);
	be->BotLibVarSet("maxclients", "64");
	be->BotLibVarSet("maxentities", "1024");
	if (be->BotLibSetup() != BLERR_NOERROR) { fprintf(stderr, "BotLibSetup failed\n"); return 1; }
	COM_StripExtension(COM_SkipPath(argv[1]), mapname, sizeof(mapname));
	if (be->BotLibLoadMap(mapname) != BLERR_NOERROR) { fprintf(stderr, "BotLibLoadMap failed\n"); return 1; }
	for (i = 0; i < 10 && !be->aas.AAS_Initialized(); i++) be->BotLibStartFrame((float)i * 0.1f);
	if (!be->aas.AAS_Initialized()) { fprintf(stderr, "AAS not initialized\n"); return 1; }

	if (!strcmp(cmd, "info")) {
		fprintf(o, "I %d %d %d %d %d %d\n", checksum, aasworld.numareas, aasworld.reachabilitysize,
			aasworld.numclusters, aasworld.numportals, aasworld.numreachabilityareas);
		return 0;
	}
	if (!strcmp(cmd, "reach")) {
		for (i = 0; i < aasworld.reachabilitysize; i++) {
			aas_reachability_t *r = &aasworld.reachability[i];
			fprintf(o, "R %d %d %d %d", i, r->areanum, r->facenum, r->edgenum);
			pv(o, r->start); pv(o, r->end);
			fprintf(o, " %d %d\n", r->traveltype, r->traveltime);
		}
		return 0;
	}
	if (argc < 6) { fprintf(stderr, "%s needs <count> <seed>\n", cmd); return 2; }
	n = atoi(argv[4]);
	rngstate = (unsigned)atoi(argv[5]);
	if (!strcmp(cmd, "areas")) {
		for (i = 0; i < n; i++) {
			vec3_t p;
			rndpoint(p);
			fprintf(o, "A"); pv(o, p);
			fprintf(o, " %d\n", AAS_PointAreaNum(p));
		}
		return 0;
	}
	if (!strcmp(cmd, "travel")) {
		static const int tfls[] = { TFL_DEFAULT, TFL_DEFAULT & ~TFL_JUMPPAD, TFL_WALK | TFL_AIR, TFL_DEFAULT | TFL_ROCKETJUMP };
		for (i = 0; i < n; i++) {
			int a = rndreacharea(), g = rndi(5) ? rndreacharea() : 1 + rndi(aasworld.numareas - 1);
			int tfl = tfls[rndi(4)], tt = 0, rn = 0, ok;
			vec3_t org;
			VectorCopy(aasworld.areas[a].center, org);
			ok = AAS_AreaRouteToGoalArea(a, org, g, tfl, &tt, &rn);
			fprintf(o, "T %d %d %d", a, g, tfl); pv(o, org);
			fprintf(o, " %d %d %d %d\n", ok, tt, rn, AAS_AreaTravelTimeToGoalArea(a, org, g, tfl));
		}
		return 0;
	}
	if (!strcmp(cmd, "trace")) {
		for (i = 0; i < n; i++) {
			vec3_t s, e;
			int pres = rndi(3) ? PRESENCE_NORMAL : PRESENCE_CROUCH;
			aas_trace_t t;
			rndpoint(s);
			if (rndi(2)) { VectorCopy(aasworld.areas[1 + rndi(aasworld.numareas - 1)].center, e); }
			else rndpoint(e);
			t = AAS_TraceClientBBox(s, e, pres, -1);
			fprintf(o, "C %d", pres); pv(o, s); pv(o, e);
			fprintf(o, " %d %08x", t.startsolid, fb(t.fraction)); pv(o, t.endpos);
			fprintf(o, " %d %d %d %d\n", t.ent, t.lastarea, t.area, t.planenum);
		}
		return 0;
	}
	if (!strcmp(cmd, "predict")) {
		for (i = 0; i < n; i++) {
			aas_clientmove_t m;
			vec3_t org, vel, cmdmove;
			int a = rndreacharea(), frames = 5 + rndi(40), cmdframes = rndi(frames + 1);
			int onground = rndi(4) != 0, stop = rndi(2) ? SE_HITGROUND | SE_ENTERWATER | SE_GAP : SE_NONE;
			VectorCopy(aasworld.areas[a].center, org);
			for (j = 0; j < 3; j++) { vel[j] = (rndf() - 0.5f) * 600; cmdmove[j] = (rndf() - 0.5f) * 800; }
			if (rndi(3) == 0) cmdmove[2] = 0;
			memset(&m, 0, sizeof(m));
			AAS_PredictClientMovement(&m, -1, org, PRESENCE_NORMAL, onground, vel, cmdmove, cmdframes, frames,
				0.1f, stop, 0, qfalse);
			fprintf(o, "P"); pv(o, org); pv(o, vel); pv(o, cmdmove);
			fprintf(o, " %d %d %d %d", onground, cmdframes, frames, stop);
			pv(o, m.endpos); fprintf(o, " %d", m.endarea); pv(o, m.velocity);
			fprintf(o, " %d %d %d %08x %d\n", m.presencetype, m.stopevent, m.endcontents, fb(m.time), m.frames);
		}
		return 0;
	}
	fprintf(stderr, "unknown command %s\n", cmd);
	return 2;
}
