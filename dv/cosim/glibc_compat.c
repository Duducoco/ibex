// Compatibility stub for __libc_single_threaded (glibc 2.32+).
// CentOS 7 ships glibc 2.17 which lacks this symbol.
// Setting to 0 (multi-threaded) is the safe conservative choice.
char __libc_single_threaded = 0;
