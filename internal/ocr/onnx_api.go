//go:build !noocr

package ocr

/*
#cgo CFLAGS: -I${SRCDIR}/../../build/deps/onnxruntime/include
#cgo LDFLAGS: -L${SRCDIR}/../../build/deps/onnxruntime/lib -lonnxruntime -Wl,-rpath,'$ORIGIN'

#include <stdlib.h>
#include <stdint.h>
#include <stddef.h>

struct ort_session_t;
typedef struct ort_session_t ort_session_t;

ort_session_t* ort_create_session(const void* modelData, size_t modelSize, char** errMsg);
void ort_destroy_session(ort_session_t* s);
char* ort_run(ort_session_t* s,
    const char* inputName, const float* inputData, const int64_t* inputShape, int inputDims,
    float** outData, int64_t** outShape, int* outDims);
void ort_free_result(float* data, int64_t* shape);
*/
import "C"
import (
	"fmt"
	"unsafe"
)

// ORTSession wraps an ONNX Runtime session and environment.
type ORTSession struct {
	handle    *C.ort_session_t
	inputName string
}

// NewORTSession creates a session from ONNX model bytes.
func NewORTSession(modelBytes []byte, inputName string) (*ORTSession, error) {
	if len(modelBytes) == 0 {
		return nil, fmt.Errorf("empty model bytes")
	}

	var errMsg *C.char
	var modelPtr unsafe.Pointer
	if len(modelBytes) > 0 {
		modelPtr = unsafe.Pointer(&modelBytes[0])
	}

	handle := C.ort_create_session(modelPtr, C.size_t(len(modelBytes)), &errMsg)
	if handle == nil {
		msg := C.GoString(errMsg)
		C.free(unsafe.Pointer(errMsg))
		return nil, fmt.Errorf("create ONNX session: %s", msg)
	}

	return &ORTSession{handle: handle, inputName: inputName}, nil
}

// Run runs inference on the given tensor data and shape, returning output data and shape.
func (s *ORTSession) Run(inputData []float32, shape []int64) ([]float32, []int64, error) {
	if len(shape) == 0 {
		return nil, nil, fmt.Errorf("empty input shape")
	}

	inputShapeC := make([]C.int64_t, len(shape))
	for i, v := range shape {
		inputShapeC[i] = C.int64_t(v)
	}

	inputDataC := make([]C.float, len(inputData))
	for i, v := range inputData {
		inputDataC[i] = C.float(v)
	}

	var dataPtr *C.float
	if len(inputDataC) > 0 {
		dataPtr = &inputDataC[0]
	}
	var shapePtr *C.int64_t
	if len(inputShapeC) > 0 {
		shapePtr = &inputShapeC[0]
	}

	var inputNameC *C.char
	if s.inputName != "" {
		inputNameC = C.CString(s.inputName)
		defer C.free(unsafe.Pointer(inputNameC))
	}

	var outData *C.float
	var outShape *C.int64_t
	var outDims C.int

	errMsg := C.ort_run(
		s.handle,
		inputNameC,
		dataPtr,
		shapePtr,
		C.int(len(shape)),
		&outData,
		&outShape,
		&outDims,
	)
	if errMsg != nil {
		msg := C.GoString(errMsg)
		C.free(unsafe.Pointer(errMsg))
		return nil, nil, fmt.Errorf("ONNX run: %s", msg)
	}

	resultShape := make([]int64, int(outDims))
	totalElements := int64(1)
	for i := 0; i < int(outDims); i++ {
		val := int64(*(*C.int64_t)(unsafe.Pointer(uintptr(unsafe.Pointer(outShape)) + uintptr(i)*unsafe.Sizeof(*outShape))))
		resultShape[i] = val
		totalElements *= val
	}

	resultData := make([]float32, totalElements)
	for i := 0; i < int(totalElements); i++ {
		resultData[i] = float32(*(*C.float)(unsafe.Pointer(uintptr(unsafe.Pointer(outData)) + uintptr(i)*unsafe.Sizeof(*outData))))
	}

	C.ort_free_result(outData, outShape)
	return resultData, resultShape, nil
}

// Release frees the session and environment.
func (s *ORTSession) Release() {
	if s.handle != nil {
		C.ort_destroy_session(s.handle)
		s.handle = nil
	}
}