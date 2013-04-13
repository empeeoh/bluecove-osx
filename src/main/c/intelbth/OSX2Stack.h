//
//  OSX2Stack.h
//  bluecove
//
//  Created by Mathias Kühn on 28.01.13.
//
//

#ifndef __bluecove__OSX2Stack__
#define __bluecove__OSX2Stack__

#include <Foundation/Foundation.h>

// This is the base for all asynchronous operations
// to be defined in the interface
@interface AsyncWorker : NSObject {
    NSString*   _name;
    
    NSString*   stringResult;
    int         intResult;
    bool        booleanResult;
    
    int         error;
}

@property (strong,nonatomic) NSString* stringResult;
@property (readwrite,assign) int intResult;
@property (readwrite,assign) bool booleanResult;

@property (readwrite,assign) int error;

-(id)init:(NSString*)className;

-(void)execute:(id)params;

-(bool)bluetoothAvailable;

@end


#define RUNNABLE(CLASS) \
@interface CLASS : AsyncWorker { \
} \
-(id)init; \
@end \
\
@implementation CLASS \
-(id)init { \
  self = [super init:@#CLASS]; \
  return self; \
} \
-(void)execute:(id)params \

#define WORKER(CLASS) \
    CLASS* worker = [[CLASS alloc] init];

typedef int (^WorkerBlock) (AsyncWorker* worker);

int execSync(NSString* taskName, WorkerBlock block);

void synchronousBTOperation(AsyncWorker* worker);


#endif /* defined(__bluecove__OSX2Stack__) */
