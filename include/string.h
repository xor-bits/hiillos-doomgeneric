#pragma once

#include "stddef.h"

extern void* memset(void* ptr, int val, size_t num);
extern void* memcpy(void* dst, const void* src, size_t num);
extern void* memmove(void* dst, const void* src, size_t num);
extern size_t strlen(const char* str);
extern int strcmp(const char* lhs, const char* rhs);
extern char* strncpy(char* dst, const char* src, size_t num);
extern int strncmp(const char* lhs, const char* rhs, size_t num);
extern const char* strstr(const char* src, const char* substr);
extern char* strdup(const char* src);
extern char* strchr(char* str, int ch);
extern char* strrchr(char* str, int ch);
