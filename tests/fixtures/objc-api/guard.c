/* Fixture: one program per guard case (-DFORM=N), each sending with literal sel_registerName /
 * objc_getClass producers so every receiver the analyzer can close closes by measurement.
 * Linked against the pinned 10.9 SDK, read as bytes, never executed.
 *   1  a later method (-[NSString containsString:], 10.10) on no list anywhere: unsupported
 *   2  a class outside the reference closure: unresolved
 *   3  a floor method, plus prose that spells a later selector: passes
 *   4  a later method (-[NSWorkspace accessibilityDisplayShouldReduceMotion], 10.10) sent only after
 *      respondsToSelector:, in fixture::guarded (a Rust v0 symbol, crate fixture, disambiguator 1Fx):
 *      unsupported unless a schema-2 guard record reviews it
 * Nothing here names a later API in a denylist: the reference set finds it absent on the floor. */
#include <stdio.h>
#include <objc/runtime.h>
#include <objc/message.h>

typedef void *obj_t;
#define CLS(n) ((obj_t)objc_getClass(n))
#define SEL_(n) sel_registerName(n)
#define SEND0(r, s) ((obj_t (*)(obj_t, SEL))objc_msgSend)((r), SEL_(s))
#define SEND1(r, s, a) ((obj_t (*)(obj_t, SEL, void *))objc_msgSend)((r), SEL_(s), (void *)(a))

#if FORM == 4
#define LATER "accessibilityDisplayShouldReduceMotion"
long guarded(void) __asm__("__RNvCs1Fx_7fixture7guarded");
__attribute__((noinline, used)) long guarded(void) {
    obj_t ws = SEND0(CLS("NSWorkspace"), "sharedWorkspace");
    if (((signed char (*)(obj_t, SEL, SEL))objc_msgSend)(ws, SEL_("respondsToSelector:"), SEL_(LATER)))
        return (long)SEND0(ws, LATER);
    return 0;
}
#endif

int main(int argc, char **argv) {
    (void)argv;
    if (argc < 99) return 0;
#if FORM == 1
    {
        obj_t s = SEND1(CLS("NSString"), "stringWithUTF8String:", "");
        return SEND1(s, "containsString:", s) != 0;
    }
#elif FORM == 2
    return SEND0(CLS("AVPlayer"), "new") != 0;
#elif FORM == 3
    /* The old raw-string scan failed this line: the selector is prose, never sent. */
    puts("labelColor");
    return SEND0(CLS("NSColor"), "blackColor") != 0;
#elif FORM == 4
    return (int)guarded();
#else
#error FORM
#endif
}
