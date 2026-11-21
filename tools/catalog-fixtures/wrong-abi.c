/* Deliberately incompatible scalar bootstrap only. Never shipped to users. */
#ifdef _WIN32
# define EXPORT __declspec(dllexport)
#else
# define EXPORT __attribute__((visibility("default")))
#endif
EXPORT int sk_version_get_milestone(void) { return 999; }
EXPORT int sk_version_get_increment(void) { return 0; }
