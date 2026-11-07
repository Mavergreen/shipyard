/* Synthetic stand-in for the SDK's NSArray.h: only the lines a recipe edits, and their neighbours. */
@class NSString;

@interface NSArray<__covariant ObjectType> : NSObject <NSCopying>
- (id)objectAtIndex:(NSUInteger)index;
@end

@interface NSMutableArray<ObjectType> : NSArray<ObjectType>
- (void)addObject:(id)anObject;
@end
