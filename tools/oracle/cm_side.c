/*
 * Engine stubs and dump helpers for the C oracle, compiled against
 * ioquake3's headers next to its collision model (GPL-2.0).
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "cm_local.h"
#include "cm_patch.h"

void *Hunk_Alloc(int size, ha_pref preference) { return calloc(1, size); }
void *Z_Malloc(int size) { return calloc(1, size); }
void Z_Free(void *ptr) { free(ptr); }
void BotDrawDebugPolygons(void (*drawPoly)(int color, int numPoints, float *points), int value) {}
unsigned Com_BlockChecksum(const void *buffer, int length) { return 0; }
void Com_DPrintf(const char *fmt, ...) {}

static cvar_t cvars[16];
static int numCvars;
cvar_t *Cvar_Get(const char *name, const char *value, int flags) {
	int i;
	for (i = 0; i < numCvars; i++) {
		if (!strcmp(cvars[i].name, name)) return &cvars[i];
	}
	cvars[numCvars].name = strdup(name);
	cvars[numCvars].string = strdup(value);
	cvars[numCvars].value = atof(value);
	cvars[numCvars].integer = atoi(value);
	return &cvars[numCvars++];
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

static unsigned fbits(float v) { unsigned u; memcpy(&u, &v, 4); return u; }

/* every patch's generated collision data, in surface order */
void oracle_dump_patches(FILE *out) {
	int i, j, k;
	for (i = 0; i < cm.numSurfaces; i++) {
		const patchCollide_t *pc;
		if (!cm.surfaces[i]) continue;
		pc = cm.surfaces[i]->pc;
		fprintf(out, "P %d %d %d", i, pc->numPlanes, pc->numFacets);
		for (j = 0; j < 2; j++)
			for (k = 0; k < 3; k++) fprintf(out, " %08x", fbits(pc->bounds[j][k]));
		fprintf(out, "\n");
		for (j = 0; j < pc->numPlanes; j++) {
			fprintf(out, "p %08x %08x %08x %08x %d\n", fbits(pc->planes[j].plane[0]), fbits(pc->planes[j].plane[1]),
				fbits(pc->planes[j].plane[2]), fbits(pc->planes[j].plane[3]), pc->planes[j].signbits);
		}
		for (j = 0; j < pc->numFacets; j++) {
			const facet_t *fc = &pc->facets[j];
			fprintf(out, "f %d %d", fc->surfacePlane, fc->numBorders);
			for (k = 0; k < fc->numBorders; k++)
				fprintf(out, " %d:%d:%d", fc->borderPlanes[k], fc->borderInward[k] ? 1 : 0, fc->borderNoAdjust[k] ? 1 : 0);
			fprintf(out, "\n");
		}
	}
}

/* points inside water brushes, for steering the movement scenarios */
int oracle_water_points(vec3_t *out, int max) {
	int i, n = 0;
	for (i = 0; i < cm.numBrushes && n < max; i++) {
		cbrush_t *b = &cm.brushes[i];
		if (!(b->contents & (CONTENTS_WATER | CONTENTS_SLIME))) continue;
		if (b->bounds[1][0] - b->bounds[0][0] < 40 || b->bounds[1][1] - b->bounds[0][1] < 40) continue;
		out[n][0] = (b->bounds[0][0] + b->bounds[1][0]) * 0.5f;
		out[n][1] = (b->bounds[0][1] + b->bounds[1][1]) * 0.5f;
		out[n][2] = b->bounds[1][2];
		n++;
	}
	return n;
}

int oracle_num_patches(void) {
	int i, n = 0;
	for (i = 0; i < cm.numSurfaces; i++) if (cm.surfaces[i]) n++;
	return n;
}

/* a point on top of a random patch's bounds, for steering onto curves */
int oracle_patch_point(int which, vec3_t out) {
	int i, n = 0;
	for (i = 0; i < cm.numSurfaces; i++) {
		if (!cm.surfaces[i]) continue;
		if (n++ == which) {
			const patchCollide_t *pc = cm.surfaces[i]->pc;
			out[0] = (pc->bounds[0][0] + pc->bounds[1][0]) * 0.5f;
			out[1] = (pc->bounds[0][1] + pc->bounds[1][1]) * 0.5f;
			out[2] = pc->bounds[1][2];
			return 1;
		}
	}
	return 0;
}
