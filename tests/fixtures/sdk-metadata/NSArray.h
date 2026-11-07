/* Synthetic stand-in for the SDK's NSArray.h: only the lines a recipe edits, and their neighbours. */
@class NSString;

@interface NSArray : NSObject <NSCopying>
- (id)objectAtIndex:(NSUInteger)index;
@end

@interface NSMutableArray : NSArray
- (void)addObject:(id)anObject;
@end
