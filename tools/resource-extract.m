/*
 * mavericks-resource-extract: stage a verified subset of a zip archive's regular files.
 *
 * usage: mavericks-resource-extract --archive ZIP --sha256 HEX --manifest TSV --prefix ARCHIVE_PREFIX
 *            --version-member PATH --expect-version VERSION --outdir FRESH_DIR
 *
 * The manifest's header is "member\tdestination\tkind\tbytes\tsha256"; each line selects the archive
 * member ARCHIVE_PREFIX+member (a regular file; kind "file") and stages it at FRESH_DIR/destination,
 * mode 0644, after checking its size and SHA-256 while streaming it. The archive's own SHA-256 is
 * checked before any member is read. PATH, a property list in the archive, must say VERSION as both
 * CFBundleVersion and CFBundleShortVersionString; it is read, never staged. Nothing in the archive is
 * run, and no link, directory or mode in it is created. FRESH_DIR must not exist, and its parent must
 * be a real directory, not a link; FRESH_DIR appears complete or not at all. Exit 0 staged, 1 refused (the reason on stderr), 2 on a usage error.
 */
#import <Foundation/Foundation.h>
#include <CommonCrypto/CommonDigest.h>
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

/* platform: no pinned SDK ships libarchive's headers, only the library (libarchive 2.8.3 on 10.9,
 *           3.x since); these are the stable libarchive 2/3 declarations of the calls used here,
 *           every one exported by both */
struct archive;
struct archive_entry;
#define ARCHIVE_EOF 1
#define ARCHIVE_OK 0
#define AE_IFMT 0170000
#define AE_IFREG 0100000
struct archive *archive_read_new(void);
int archive_read_support_format_zip(struct archive *);
int archive_read_open_filename(struct archive *, const char *, size_t);
int archive_read_next_header(struct archive *, struct archive_entry **);
ssize_t archive_read_data(struct archive *, void *, size_t);
int archive_read_data_skip(struct archive *);
int archive_read_finish(struct archive *);
const char *archive_error_string(struct archive *);
const char *archive_entry_pathname(struct archive_entry *);
mode_t archive_entry_filetype(struct archive_entry *);
int64_t archive_entry_size(struct archive_entry *);
int archive_entry_size_is_set(struct archive_entry *);

static NSString *gStage;

static void cleanup(void)
{
    if (gStage != nil)
        [[NSFileManager defaultManager] removeItemAtPath:gStage error:NULL];
}

static void die(NSString *format, ...) NS_FORMAT_FUNCTION(1, 2) __attribute__((noreturn));
static void die(NSString *format, ...)
{
    va_list ap;
    va_start(ap, format);
    NSString *m = [[NSString alloc] initWithFormat:format arguments:ap];
    va_end(ap);
    fprintf(stderr, "mavericks-resource-extract: %s\n", [m UTF8String]);
    cleanup();
    exit(1);
}

static int usage(void)
{
    fputs("usage: mavericks-resource-extract --archive ZIP --sha256 HEX --manifest TSV --prefix ARCHIVE_PREFIX "
          "--version-member PATH --expect-version VERSION --outdir FRESH_DIR\n", stderr);
    return 2;
}

static NSString *hex(const unsigned char *d)
{
    NSMutableString *s = [NSMutableString string];
    for (int i = 0; i < CC_SHA256_DIGEST_LENGTH; i++)
        [s appendFormat:@"%02x", d[i]];
    return s;
}

static BOOL plainRelative(NSString *p)
{
    if ([p length] == 0 || [p hasPrefix:@"/"] || [p hasSuffix:@"/"])
        return NO;
    if ([p rangeOfCharacterFromSet:[NSCharacterSet controlCharacterSet]].location != NSNotFound)
        return NO;
    for (NSString *c in [p componentsSeparatedByString:@"/"])
        if ([c length] == 0 || [c isEqualToString:@"."] || [c isEqualToString:@".."])
            return NO;
    return YES;
}

static BOOL isSha256(NSString *s)
{
    if ([s length] != 64)
        return NO;
    NSCharacterSet *notHex = [[NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdef"] invertedSet];
    return [s rangeOfCharacterFromSet:notHex].location == NSNotFound;
}

int main(int argc, char **argv)
{
    @autoreleasepool {
        NSMutableDictionary *a = [NSMutableDictionary dictionary];
        NSSet *known = [NSSet setWithObjects:@"--archive", @"--sha256", @"--manifest", @"--prefix",
                                             @"--version-member", @"--expect-version", @"--outdir", nil];
        for (int i = 1; i < argc; i += 2) {
            NSString *k = [NSString stringWithUTF8String:argv[i]];
            if (i + 1 >= argc || ![known containsObject:k] || a[k] != nil)
                return usage();
            a[k] = [NSString stringWithUTF8String:argv[i + 1]];
        }
        if ([a count] != [known count])
            return usage();
        NSString *archive = a[@"--archive"], *want = a[@"--sha256"], *prefix = a[@"--prefix"];
        NSString *versionMember = a[@"--version-member"], *expect = a[@"--expect-version"];
        NSString *outdir = a[@"--outdir"];
        while ([outdir length] > 1 && [outdir hasSuffix:@"/"])
            outdir = [outdir substringToIndex:[outdir length] - 1];
        if (![outdir hasPrefix:@"/"] || ![archive hasPrefix:@"/"])
            die(@"--archive and --outdir must be absolute paths");
        if (!isSha256(want))
            die(@"--sha256 is not 64 lowercase hex digits");
        if ([prefix length] && ![prefix hasSuffix:@"/"])
            die(@"--prefix '%@' must end in /", prefix);
        if (!plainRelative(versionMember))
            die(@"--version-member '%@' is not a plain relative path", versionMember);

        /* The manifest, checked whole before anything else. */
        NSString *text = [NSString stringWithContentsOfFile:a[@"--manifest"] encoding:NSUTF8StringEncoding error:NULL];
        if (text == nil)
            die(@"cannot read the manifest %@ as UTF-8", a[@"--manifest"]);
        NSMutableArray *lines = [[text componentsSeparatedByString:@"\n"] mutableCopy];
        if ([[lines lastObject] length] == 0)
            [lines removeLastObject];
        if ([lines count] < 2 || ![lines[0] isEqualToString:@"member\tdestination\tkind\tbytes\tsha256"])
            die(@"the manifest's first line must be member, destination, kind, bytes, sha256 (tab-separated), "
                @"followed by at least one member");
        NSMutableDictionary *byMember = [NSMutableDictionary dictionary];
        NSMutableSet *dests = [NSMutableSet set];
        for (NSUInteger n = 1; n < [lines count]; n++) {
            NSArray *f = [lines[n] componentsSeparatedByString:@"\t"];
            if ([f count] != 5)
                die(@"manifest line %lu has %lu fields, want 5", (unsigned long)n + 1, (unsigned long)[f count]);
            NSString *member = f[0], *dest = f[1], *kind = f[2], *bytes = f[3], *sum = f[4];
            if (!plainRelative(member) || !plainRelative(dest))
                die(@"manifest line %lu: '%@' -> '%@' is not a plain relative path", (unsigned long)n + 1, member, dest);
            if (![kind isEqualToString:@"file"])
                die(@"manifest line %lu: kind '%@' is not file", (unsigned long)n + 1, kind);
            NSCharacterSet *notDigit = [[NSCharacterSet decimalDigitCharacterSet] invertedSet];
            if ([bytes length] == 0 || [bytes length] > 15 || [bytes rangeOfCharacterFromSet:notDigit].location != NSNotFound)
                die(@"manifest line %lu: bytes '%@' is not a size", (unsigned long)n + 1, bytes);
            if (!isSha256(sum))
                die(@"manifest line %lu: sha256 is not 64 lowercase hex digits", (unsigned long)n + 1);
            NSString *full = [prefix stringByAppendingString:member];
            if (byMember[full] != nil || [full isEqualToString:versionMember])
                die(@"manifest line %lu selects %@ twice", (unsigned long)n + 1, full);
            for (NSString *d in dests)
                if ([d isEqualToString:dest] || [d hasPrefix:[dest stringByAppendingString:@"/"]]
                    || [dest hasPrefix:[d stringByAppendingString:@"/"]])
                    die(@"manifest line %lu: destination %@ collides with %@", (unsigned long)n + 1, dest, d);
            [dests addObject:dest];
            byMember[full] = @{@"dest": dest, @"bytes": @([bytes longLongValue]), @"sha256": sum};
        }

        /* The output's place: absent, its parent a real directory that we resolve physically. */
        struct stat st;
        if (lstat([outdir fileSystemRepresentation], &st) == 0)
            die(@"%@ already exists; --outdir must be fresh", outdir);
        NSString *parent = [outdir stringByDeletingLastPathComponent];
        if (lstat([parent fileSystemRepresentation], &st) == 0 && S_ISLNK(st.st_mode))
            die(@"%@ is a symbolic link; --outdir's parent must be a real directory", parent);
        char real[PATH_MAX];
        if (realpath([parent fileSystemRepresentation], real) == NULL || stat(real, &st) != 0 || !S_ISDIR(st.st_mode))
            die(@"%@ is not a directory", parent);
        NSString *parentReal = [NSString stringWithUTF8String:real];
        NSString *final = [parentReal stringByAppendingPathComponent:[outdir lastPathComponent]];

        /* The archive's bytes, before any member is read. */
        int fd = open([archive fileSystemRepresentation], O_RDONLY);
        if (fd < 0)
            die(@"cannot open %@: %s", archive, strerror(errno));
        CC_SHA256_CTX ctx;
        CC_SHA256_Init(&ctx);
        unsigned char buf[65536];
        ssize_t r;
        while ((r = read(fd, buf, sizeof buf)) > 0)
            CC_SHA256_Update(&ctx, buf, (CC_LONG)r);
        close(fd);
        if (r < 0)
            die(@"cannot read %@", archive);
        unsigned char digest[CC_SHA256_DIGEST_LENGTH];
        CC_SHA256_Final(digest, &ctx);
        if (![hex(digest) isEqualToString:want])
            die(@"%@ has SHA-256 %@, not the pinned %@; no member was read", archive, hex(digest), want);

        char tmpl[PATH_MAX];
        snprintf(tmpl, sizeof tmpl, "%s/.%s.staging-XXXXXX", [parentReal fileSystemRepresentation],
                 [[outdir lastPathComponent] fileSystemRepresentation]);
        if (mkdtemp(tmpl) == NULL)
            die(@"cannot make a staging directory beside %@: %s", outdir, strerror(errno));
        gStage = [NSString stringWithUTF8String:tmpl];
        chmod(tmpl, 0755);

        struct archive *ar = archive_read_new();
        archive_read_support_format_zip(ar);
        if (archive_read_open_filename(ar, [archive fileSystemRepresentation], 65536) != ARCHIVE_OK)
            die(@"%@ is not a readable zip archive: %s", archive, archive_error_string(ar));
        NSMutableSet *seen = [NSMutableSet set];
        NSMutableSet *staged = [NSMutableSet set];
        BOOL versionOk = NO;
        struct archive_entry *e;
        int rc;
        while ((rc = archive_read_next_header(ar, &e)) == ARCHIVE_OK) {
            const char *raw = archive_entry_pathname(e);
            NSString *name = raw ? [NSString stringWithUTF8String:raw] : nil;
            if (name == nil)
                die(@"the archive has an entry whose name is not UTF-8");
            while ([name hasSuffix:@"/"])
                name = [name substringToIndex:[name length] - 1];
            if ([seen containsObject:name])
                die(@"the archive holds %@ twice", name);
            [seen addObject:name];
            NSDictionary *sel = byMember[name];
            BOOL isVersion = [name isEqualToString:versionMember];
            if (sel == nil && !isVersion) {
                if (archive_read_data_skip(ar) != ARCHIVE_OK)
                    die(@"cannot read past %@: %s", name, archive_error_string(ar));
                continue;
            }
            if ((archive_entry_filetype(e) & AE_IFMT) != AE_IFREG)
                die(@"%@ is selected but is not a regular file in the archive", name);
            long long limit = isVersion ? (1 << 20) : [sel[@"bytes"] longLongValue];
            if (archive_entry_size_is_set(e) && archive_entry_size(e) != limit && !isVersion)
                die(@"%@ is %lld bytes in the archive, the manifest says %lld", name,
                    (long long)archive_entry_size(e), limit);
            int out = -1;
            NSString *dest = nil;
            NSMutableData *versionBytes = isVersion ? [NSMutableData data] : nil;
            if (!isVersion) {
                dest = [gStage stringByAppendingPathComponent:sel[@"dest"]];
                NSString *walk = gStage;
                for (NSString *c in [[sel[@"dest"] stringByDeletingLastPathComponent] pathComponents]) {
                    walk = [walk stringByAppendingPathComponent:c];
                    if (mkdir([walk fileSystemRepresentation], 0755) != 0 && errno != EEXIST)
                        die(@"cannot make %@: %s", walk, strerror(errno));
                    if (lstat([walk fileSystemRepresentation], &st) != 0 || !S_ISDIR(st.st_mode))
                        die(@"%@ is not a directory", walk);
                }
                out = open([dest fileSystemRepresentation], O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0644);
                if (out < 0)
                    die(@"cannot create %@: %s", dest, strerror(errno));
            }
            CC_SHA256_Init(&ctx);
            long long total = 0;
            for (;;) {
                ssize_t got = archive_read_data(ar, buf, sizeof buf);
                if (got < 0)
                    die(@"cannot read %@ from the archive: %s", name, archive_error_string(ar));
                if (got == 0)
                    break;
                total += got;
                if (total > limit)
                    die(@"%@ is longer than the manifest's %lld bytes", name, limit);
                CC_SHA256_Update(&ctx, buf, (CC_LONG)got);
                if (isVersion)
                    [versionBytes appendBytes:buf length:(NSUInteger)got];
                else if (write(out, buf, (size_t)got) != got)
                    die(@"cannot write %@: %s", dest, strerror(errno));
            }
            CC_SHA256_Final(digest, &ctx);
            if (isVersion) {
                NSDictionary *plist = [NSPropertyListSerialization propertyListWithData:versionBytes options:0
                                                                                 format:NULL error:NULL];
                if (![plist isKindOfClass:[NSDictionary class]])
                    die(@"%@ is not a property list", name);
                NSString *v = plist[@"CFBundleVersion"], *sv = plist[@"CFBundleShortVersionString"];
                if (![v isEqual:expect] || ![sv isEqual:expect])
                    die(@"%@ says CFBundleVersion %@ and CFBundleShortVersionString %@, not %@", name, v, sv, expect);
                versionOk = YES;
                continue;
            }
            if (fchmod(out, 0644) != 0 || close(out) != 0)
                die(@"cannot finish %@: %s", dest, strerror(errno));
            if (total != limit)
                die(@"%@ is %lld bytes, the manifest says %lld", name, total, limit);
            if (![hex(digest) isEqualToString:sel[@"sha256"]])
                die(@"%@ has SHA-256 %@, the manifest says %@", name, hex(digest), sel[@"sha256"]);
            [staged addObject:name];
        }
        if (rc != ARCHIVE_EOF)
            die(@"the archive ends early or is damaged: %s", archive_error_string(ar));
        archive_read_finish(ar);
        for (NSString *m in byMember)
            if (![staged containsObject:m])
                die(@"the archive has no %@", m);
        if (!versionOk)
            die(@"the archive has no %@", versionMember);
        if (rename([gStage fileSystemRepresentation], [final fileSystemRepresentation]) != 0)
            die(@"cannot publish %@: %s", final, strerror(errno));
        gStage = nil;
        return 0;
    }
}
