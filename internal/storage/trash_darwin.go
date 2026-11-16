package storage

/*
#cgo CFLAGS: -x objective-c -fobjc-arc
#cgo LDFLAGS: -framework Foundation
#import <Foundation/Foundation.h>
#include <stdlib.h>
#include <string.h>

static char* trashPath(const char* path) {
	@autoreleasepool {
		NSURL *url = [NSURL fileURLWithPath:[NSString stringWithUTF8String:path]];
		NSError *err = nil;
		if (![[NSFileManager defaultManager] trashItemAtURL:url resultingItemURL:nil error:&err]) {
			return strdup([[err localizedDescription] UTF8String]);
		}
		return NULL;
	}
}
*/
import "C"

import (
	"errors"
	"unsafe"
)

// trashItem přesune soubor/adresář do Koše; v testech se nahrazuje.
var trashItem = func(path string) error {
	cpath := C.CString(path)
	defer C.free(unsafe.Pointer(cpath))
	if msg := C.trashPath(cpath); msg != nil {
		defer C.free(unsafe.Pointer(msg))
		return errors.New(C.GoString(msg))
	}
	return nil
}
