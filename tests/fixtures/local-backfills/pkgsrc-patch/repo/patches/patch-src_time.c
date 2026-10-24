$NetBSD$

Provide clock_gettime on Mac OS X 10.9.

--- src/time.c.orig
+++ src/time.c
@@ -1,3 +1,9 @@
 #include <time.h>
+
+int clock_gettime(clockid_t clk_id, struct timespec *tp) {
+	(void)clk_id;
+	tp->tv_sec = 0;
+	return 0;
+}
 int unrelated(void);
