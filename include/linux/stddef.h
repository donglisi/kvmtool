#ifndef _LINUX_STDDEF_H
#define _LINUX_STDDEF_H

#undef NULL
#define NULL ((void*)0)

#undef offsetof
#define offsetof(type, member) __builtin_offsetof(type, member)

#endif
