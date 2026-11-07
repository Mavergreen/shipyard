/*
 * mavericks-xcode-inputs: list the selected targets' source, header and resource build phases of an
 * Xcode project, resolving every reference through the project's own group tree with Foundation's
 * property-list reader. Nothing in the project is executed.
 *
 * usage: mavericks-xcode-inputs --project ABS.xcodeproj --target NAME [--target NAME...] --output FILE.json
 *
 * Output (schema 1): {"schema":1,"targets":{NAME:{"sources":[{"path","kind"}],"headers":[...],
 * "resources":[...]}}}, paths relative to the project's directory, in phase order with every
 * duplicate kept. kind is source, model, header, file, variant or product (another target's built
 * product a Resources phase copies, by its product name). Any reference this cannot resolve
 * to a regular file or directory inside the project's directory, any record it does not know, and
 * any target it cannot find is an error: nothing is written, exit 1. Exit 2 on a usage error.
 */
#import <Foundation/Foundation.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/stat.h>

static NSString *gError;

static id fail(NSString *format, ...) NS_FORMAT_FUNCTION(1, 2);
static id fail(NSString *format, ...)
{
    if (gError == nil) {
        va_list ap;
        va_start(ap, format);
        gError = [[NSString alloc] initWithFormat:format arguments:ap];
        va_end(ap);
    }
    return nil;
}

@interface Project : NSObject
@property (strong) NSDictionary *objects;
@property (strong) NSString *root;
@property (strong) NSString *rootReal;
@property (strong) NSString *mainGroup;
@property (strong) NSMutableDictionary *parents;
@property (strong) NSMutableDictionary *resolved;
@property (strong) NSMutableSet *products;
@end

@implementation Project

- (NSDictionary *)object:(NSString *)ident
{
    id o = [self.objects objectForKey:ident];
    if (![o isKindOfClass:[NSDictionary class]])
        return fail(@"the project names object %@, which it does not define", ident);
    return o;
}

/* A relative, normalized path below the project directory, or nil. */
- (NSString *)join:(NSString *)base with:(NSString *)path ident:(NSString *)ident
{
    if ([path length] == 0)
        return base;
    if ([path hasPrefix:@"/"])
        return fail(@"%@ has the absolute path %@; only paths inside the project are read", ident, path);
    NSMutableArray *parts = [NSMutableArray arrayWithArray:
        [base length] ? [base componentsSeparatedByString:@"/"] : @[]];
    for (NSString *c in [path componentsSeparatedByString:@"/"]) {
        if ([c length] == 0 || [c isEqualToString:@"."])
            continue;
        if ([c isEqualToString:@".."]) {
            if ([parts count] == 0)
                return fail(@"%@'s path %@ leaves the project directory", ident, path);
            [parts removeLastObject];
            continue;
        }
        [parts addObject:c];
    }
    return [parts componentsJoinedByString:@"/"];
}

- (NSString *)resolve:(NSString *)ident
{
    NSString *done = [self.resolved objectForKey:ident];
    if (done != nil)
        return done;
    NSDictionary *o = [self object:ident];
    if (o == nil)
        return nil;
    NSString *tree = [o objectForKey:@"sourceTree"];
    NSString *path = [o objectForKey:@"path"];
    if (path != nil && ![path isKindOfClass:[NSString class]])
        return fail(@"%@ has a path that is not a string", ident);
    NSString *base;
    if ([ident isEqualToString:self.mainGroup] || [tree isEqualToString:@"SOURCE_ROOT"]) {
        base = @"";
    } else if ([tree isEqualToString:@"<group>"]) {
        NSString *parent = [self.parents objectForKey:ident];
        if (parent == nil)
            return fail(@"%@ is relative to its group but belongs to none", ident);
        base = [self resolve:parent];
        if (base == nil)
            return nil;
    } else {
        return fail(@"%@ has sourceTree %@; only <group> and SOURCE_ROOT are read", ident, tree);
    }
    NSString *r = [self join:base with:path ident:ident];
    if (r != nil)
        [self.resolved setObject:r forKey:ident];
    return r;
}

/* The resolved path, checked to exist and to stay inside the project directory physically. */
- (NSString *)existing:(NSString *)ident
{
    NSString *rel = [self resolve:ident];
    if (rel == nil)
        return nil;
    if ([rel length] == 0)
        return fail(@"%@ resolves to the project directory itself", ident);
    NSString *full = [self.root stringByAppendingPathComponent:rel];
    struct stat st;
    if (lstat([full fileSystemRepresentation], &st) != 0)
        return fail(@"%@ resolves to %@, which does not exist", ident, rel);
    char real[PATH_MAX];
    if (realpath([full fileSystemRepresentation], real) == NULL)
        return fail(@"%@ resolves to %@, which cannot be resolved", ident, rel);
    NSString *r = [NSString stringWithUTF8String:real];
    if (![r hasPrefix:[self.rootReal stringByAppendingString:@"/"]])
        return fail(@"%@ resolves to %@, which leads outside the project directory to %@", ident, rel, r);
    return rel;
}

static NSString *fileType(NSDictionary *o)
{
    NSString *t = [o objectForKey:@"lastKnownFileType"];
    return t ? t : [o objectForKey:@"explicitFileType"];
}

- (BOOL)add:(NSString *)kind ident:(NSString *)ident to:(NSMutableArray *)out
{
    NSString *rel = [self existing:ident];
    if (rel == nil)
        return NO;
    [out addObject:@{@"path": rel, @"kind": kind}];
    return YES;
}

- (BOOL)phase:(NSString *)name file:(NSString *)ref to:(NSMutableArray *)out
{
    NSDictionary *o = [self object:ref];
    if (o == nil)
        return NO;
    NSString *recordType = [o objectForKey:@"isa"];
    NSString *type = fileType(o);
    if ([name isEqualToString:@"sources"]) {
        if ([recordType isEqualToString:@"XCVersionGroup"])
            return [self add:@"model" ident:ref to:out];
        NSSet *code = [NSSet setWithObjects:@"sourcecode.c.objc", @"sourcecode.c.c",
                                            @"sourcecode.cpp.objcpp", @"sourcecode.cpp.cpp", nil];
        if ([recordType isEqualToString:@"PBXFileReference"] && [code containsObject:type])
            return [self add:@"source" ident:ref to:out];
    } else if ([name isEqualToString:@"headers"]) {
        if ([recordType isEqualToString:@"PBXFileReference"] && [type isEqualToString:@"sourcecode.c.h"])
            return [self add:@"header" ident:ref to:out];
    } else {
        if ([recordType isEqualToString:@"PBXFileReference"]
            && [[o objectForKey:@"sourceTree"] isEqualToString:@"BUILT_PRODUCTS_DIR"]) {
            NSString *path = [o objectForKey:@"path"];
            if (![self.products containsObject:ref] || ![path isKindOfClass:[NSString class]]
                || [path length] == 0 || [path rangeOfString:@"/"].location != NSNotFound)
                return fail(@"%@ is a built-products reference that is no target's product", ref), NO;
            [out addObject:@{@"path": path, @"kind": @"product"}];
            return YES;
        }
        if ([recordType isEqualToString:@"PBXFileReference"])
            return [self add:@"file" ident:ref to:out];
        if ([recordType isEqualToString:@"XCVersionGroup"])
            return [self add:@"model" ident:ref to:out];
        if ([recordType isEqualToString:@"PBXVariantGroup"]) {
            for (NSString *child in [o objectForKey:@"children"]) {
                NSDictionary *c = [self object:child];
                if (c == nil)
                    return NO;
                if (![[c objectForKey:@"isa"] isEqualToString:@"PBXFileReference"])
                    return fail(@"variant group %@ holds %@, a %@", ref, child, [c objectForKey:@"isa"]), NO;
                if (![self add:@"variant" ident:child to:out])
                    return NO;
            }
            return YES;
        }
    }
    fail(@"the %@ phase holds %@, a %@ of type %@, which this does not read", name, ref, recordType, type);
    return NO;
}

- (NSDictionary *)target:(NSDictionary *)t name:(NSString *)tname
{
    NSDictionary *phases = @{@"PBXSourcesBuildPhase": @"sources", @"PBXHeadersBuildPhase": @"headers",
                             @"PBXResourcesBuildPhase": @"resources"};
    NSSet *ignored = [NSSet setWithObjects:@"PBXFrameworksBuildPhase", @"PBXCopyFilesBuildPhase",
                                           @"PBXShellScriptBuildPhase", @"PBXRezBuildPhase", nil];
    NSMutableDictionary *out = [NSMutableDictionary dictionary];
    for (NSString *k in [phases allValues])
        [out setObject:[NSMutableArray array] forKey:k];
    for (NSString *p in [t objectForKey:@"buildPhases"]) {
        NSDictionary *phase = [self object:p];
        if (phase == nil)
            return nil;
        NSString *recordType = [phase objectForKey:@"isa"];
        NSString *name = [phases objectForKey:recordType];
        if (name == nil) {
            if ([ignored containsObject:recordType])
                continue;
            return fail(@"target %@ has a %@ (%@), which this does not read", tname, recordType, p);
        }
        for (NSString *bf in [phase objectForKey:@"files"]) {
            NSDictionary *b = [self object:bf];
            if (b == nil)
                return nil;
            if (![[b objectForKey:@"isa"] isEqualToString:@"PBXBuildFile"])
                return fail(@"phase %@ lists %@, a %@, not a PBXBuildFile", p, bf, [b objectForKey:@"isa"]);
            NSString *ref = [b objectForKey:@"fileRef"];
            if (![ref isKindOfClass:[NSString class]])
                return fail(@"build file %@ names no file", bf);
            if (![self phase:name file:ref to:[out objectForKey:name]])
                return nil;
        }
    }
    return out;
}

@end

static NSString *quote(NSString *s)
{
    NSMutableString *r = [NSMutableString stringWithString:@"\""];
    for (NSUInteger i = 0; i < [s length]; i++) {
        unichar c = [s characterAtIndex:i];
        if (c == '"' || c == '\\')
            [r appendFormat:@"\\%C", c];
        else if (c < 0x20)
            [r appendFormat:@"\\u%04x", c];
        else
            [r appendFormat:@"%C", c];
    }
    [r appendString:@"\""];
    return r;
}

static int usage(void)
{
    fputs("usage: mavericks-xcode-inputs --project ABS.xcodeproj --target NAME [--target NAME...] --output FILE.json\n",
          stderr);
    return 2;
}

int main(int argc, char **argv)
{
    @autoreleasepool {
        NSString *projectPath = nil, *output = nil;
        NSMutableArray *names = [NSMutableArray array];
        for (int i = 1; i < argc; i += 2) {
            if (i + 1 >= argc)
                return usage();
            NSString *v = [NSString stringWithUTF8String:argv[i + 1]];
            if (strcmp(argv[i], "--project") == 0)
                projectPath = v;
            else if (strcmp(argv[i], "--target") == 0)
                [names addObject:v];
            else if (strcmp(argv[i], "--output") == 0)
                output = v;
            else
                return usage();
        }
        if (projectPath == nil || output == nil || [names count] == 0 || ![projectPath hasPrefix:@"/"])
            return usage();

        NSDictionary *pbx = nil;
        NSData *data = [NSData dataWithContentsOfFile:[projectPath stringByAppendingPathComponent:@"project.pbxproj"]];
        if (data != nil)
            pbx = [NSPropertyListSerialization propertyListWithData:data options:0 format:NULL error:NULL];
        Project *p = [[Project alloc] init];
        NSDictionary *result = nil;
        if (![pbx isKindOfClass:[NSDictionary class]]) {
            fail(@"%@ has no readable project.pbxproj", projectPath);
        } else {
            p.objects = [pbx objectForKey:@"objects"];
            p.parents = [NSMutableDictionary dictionary];
            p.resolved = [NSMutableDictionary dictionary];
            NSDictionary *proj = [p.objects isKindOfClass:[NSDictionary class]]
                ? [p object:[pbx objectForKey:@"rootObject"]] : fail(@"the project has no objects");
            if (proj != nil && ![[proj objectForKey:@"isa"] isEqualToString:@"PBXProject"])
                proj = fail(@"the root object is a %@, not a PBXProject", [proj objectForKey:@"isa"]);
            if (proj != nil) {
                NSString *dir = [p join:@"" with:[proj objectForKey:@"projectDirPath"] ident:@"projectDirPath"];
                char real[PATH_MAX];
                NSString *projDir = [projectPath stringByDeletingLastPathComponent];
                if (dir != nil)
                    p.root = [dir length] ? [projDir stringByAppendingPathComponent:dir] : projDir;
                if (p.root != nil && realpath([p.root fileSystemRepresentation], real) != NULL)
                    p.rootReal = [NSString stringWithUTF8String:real];
                else
                    fail(@"the project directory %@ cannot be resolved", p.root);
                p.mainGroup = [proj objectForKey:@"mainGroup"];
                p.products = [NSMutableSet set];
                for (NSString *tid in [proj objectForKey:@"targets"]) {
                    NSString *pr = [[p.objects objectForKey:tid] objectForKey:@"productReference"];
                    if ([pr isKindOfClass:[NSString class]])
                        [p.products addObject:pr];
                }
                for (NSString *ident in p.objects) {
                    NSDictionary *o = [p.objects objectForKey:ident];
                    NSString *recordType = [o objectForKey:@"isa"];
                    if (![recordType isEqualToString:@"PBXGroup"] && ![recordType isEqualToString:@"PBXVariantGroup"]
                        && ![recordType isEqualToString:@"XCVersionGroup"])
                        continue;
                    for (NSString *child in [o objectForKey:@"children"]) {
                        NSString *had = [p.parents objectForKey:child];
                        if (had != nil && ![had isEqualToString:ident])
                            fail(@"%@ belongs to two groups, %@ and %@", child, had, ident);
                        [p.parents setObject:ident forKey:child];
                    }
                }
                NSMutableDictionary *targets = [NSMutableDictionary dictionary];
                for (NSString *name in names) {
                    if ([targets objectForKey:name] != nil) {
                        fail(@"target %@ is named twice", name);
                        break;
                    }
                    NSDictionary *found = nil;
                    for (NSString *tid in [proj objectForKey:@"targets"]) {
                        NSDictionary *t = [p object:tid];
                        if ([[t objectForKey:@"name"] isEqualToString:name]) {
                            if (![[t objectForKey:@"isa"] isEqualToString:@"PBXNativeTarget"])
                                fail(@"target %@ is a %@, not a PBXNativeTarget", name, [t objectForKey:@"isa"]);
                            found = t;
                        }
                    }
                    if (found == nil) {
                        fail(@"the project has no target %@", name);
                        break;
                    }
                    NSDictionary *phases = [p target:found name:name];
                    if (phases == nil)
                        break;
                    [targets setObject:phases forKey:name];
                }
                if (gError == nil)
                    result = targets;
            }
        }
        if (gError != nil || result == nil) {
            fprintf(stderr, "mavericks-xcode-inputs: %s\n", [(gError ? gError : @"failed") UTF8String]);
            return 1;
        }

        NSMutableString *json = [NSMutableString stringWithString:@"{\"schema\":1,\"targets\":{"];
        NSArray *sortedNames = [[result allKeys] sortedArrayUsingSelector:@selector(compare:)];
        for (NSUInteger i = 0; i < [sortedNames count]; i++) {
            NSString *name = sortedNames[i];
            [json appendFormat:@"%@\n%@:{", i ? @"," : @"", quote(name)];
            NSArray *order = @[@"headers", @"resources", @"sources"];
            for (NSUInteger k = 0; k < [order count]; k++) {
                [json appendFormat:@"%@%@:[", k ? @"," : @"", quote(order[k])];
                NSArray *entries = [result[name] objectForKey:order[k]];
                for (NSUInteger e = 0; e < [entries count]; e++)
                    [json appendFormat:@"%@\n {\"kind\":%@,\"path\":%@}", e ? @"," : @"",
                        quote(entries[e][@"kind"]), quote(entries[e][@"path"])];
                [json appendString:@"]"];
            }
            [json appendString:@"}"];
        }
        [json appendString:@"}}\n"];
        NSError *err = nil;
        if (![json writeToFile:output atomically:YES encoding:NSUTF8StringEncoding error:&err]) {
            fprintf(stderr, "mavericks-xcode-inputs: cannot write %s: %s\n", [output UTF8String],
                    [[err localizedDescription] UTF8String]);
            return 1;
        }
        return 0;
    }
}
