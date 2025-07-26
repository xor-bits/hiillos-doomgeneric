#pragma once

#include "stddef.h"

extern void* malloc(size_t size);
extern void* realloc(void* ptr, size_t size);
extern void* calloc(size_t num, size_t size);
extern void* malloc(size_t size);
extern void free(void *);
extern int atoi(const char* str);
extern float atof(const char* str);
extern void exit(int exit_code);
extern int system(const char* command);
