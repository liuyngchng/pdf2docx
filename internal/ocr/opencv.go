//go:build !noocr

package ocr

/*
#cgo linux pkg-config: opencv4
#cgo linux CXXFLAGS: -std=c++17
#cgo linux LDFLAGS: -Wl,-rpath,'$ORIGIN'
#cgo windows pkg-config: opencv4
#cgo windows CXXFLAGS: -std=c++17

#include <stdint.h>

void* cv_mat_create(int rows, int cols, int type);
void* cv_mat_create_from_rgba(int rows, int cols, const uint8_t* rgba);
void  cv_mat_destroy(void* m);
int   cv_mat_rows(void* m);
int   cv_mat_cols(void* m);
int   cv_mat_type(void* m);

void* cv_cvt_color(void* src, int code);
void* cv_resize(void* src, int width, int height, int interpolation);
void* cv_threshold_binary(void* src, double thresh);
void* cv_convert_8u(void* src);
void* cv_dilate_2x2(void* src);

// Contours
void* cv_find_contours(void* src);
int   cv_contours_count(void* cr);
int   cv_contour_size(void* cr, int idx);
void  cv_contour_get_point(void* cr, int idx, int pt_idx, int* out_x, int* out_y);
void  cv_contours_destroy(void* cr);

// minAreaRect
void  cv_min_area_rect_from_points(const int* xs, const int* ys, int n,
                                   float* out_xs, float* out_ys);

// Perspective
void* cv_get_perspective_transform(float src_xs[4], float src_ys[4],
                                   float dst_xs[4], float dst_ys[4]);
void* cv_warp_perspective(void* src, void* transform, int dst_w, int dst_h, int borderMode);

// Mat conversion
void* cv_mat_to_float(void* src);

// Channel ops
void cv_split(void* src, void** ch0, void** ch1, void** ch2);
void cv_multiply_scalar(void* mat, double s);
void cv_subtract_scalar(void* mat, double s);
void cv_divide_scalar(void* mat, double s);

// Data extraction
void cv_mat_get_float(void* mat, float* out);
void cv_mat_get_float_channel(void* mat, int ch, float* out);

// Box score
double cv_mean_in_polygon(void* probMat,
    const int* poly_xs, const int* poly_ys, int n,
    int xmin, int ymin, int xmax, int ymax);

// Rotate
void* cv_rotate_90_ccw(void* src);
*/
import "C"
import (
	"fmt"
	"image"
	"math"
	"unsafe"
)

// ── Go-side Mat wrapper ────────────────────────────────────────────────────

// Mat wraps an OpenCV cv::Mat managed by the C bridge.
type Mat struct {
	p unsafe.Pointer
}

// NewMatFromRGBA converts a Go image.RGBA to an OpenCV BGR Mat.
func NewMatFromRGBA(img *image.RGBA) *Mat {
	bounds := img.Bounds()
	w := bounds.Dx()
	h := bounds.Dy()
	p := C.cv_mat_create_from_rgba(C.int(h), C.int(w), (*C.uint8_t)(&img.Pix[0]))
	if p == nil {
		return nil
	}
	return &Mat{p: p}
}

// NewMat creates an empty Mat.
func NewMat(rows, cols, cvType int) *Mat {
	p := C.cv_mat_create(C.int(rows), C.int(cols), C.int(cvType))
	if p == nil {
		return nil
	}
	return &Mat{p: p}
}

// Release frees the underlying cv::Mat.
func (m *Mat) Release() {
	if m.p != nil {
		C.cv_mat_destroy(m.p)
		m.p = nil
	}
}

// Rows returns the number of rows.
func (m *Mat) Rows() int { return int(C.cv_mat_rows(m.p)) }

// Cols returns the number of columns.
func (m *Mat) Cols() int { return int(C.cv_mat_cols(m.p)) }

// CvType returns the OpenCV type constant.
func (m *Mat) CvType() int { return int(C.cv_mat_type(m.p)) }

// ── Color conversion ───────────────────────────────────────────────────────

const (
	COLOR_BGR2RGB = 4
	COLOR_BGR2GRAY = 6
)

// CvtColor wraps cv::cvtColor.
func CvtColor(src *Mat, code int) *Mat {
	p := C.cv_cvt_color(src.p, C.int(code))
	return &Mat{p: p}
}

// ── Resize ─────────────────────────────────────────────────────────────────

const (
	INTER_LINEAR = 1
	INTER_CUBIC = 2
)

// Resize wraps cv::resize.
func Resize(src *Mat, width, height int, interpolation int) *Mat {
	p := C.cv_resize(src.p, C.int(width), C.int(height), C.int(interpolation))
	return &Mat{p: p}
}

// ── Threshold ──────────────────────────────────────────────────────────────

// ThresholdBinary wraps cv::threshold with THRESH_BINARY.
func ThresholdBinary(src *Mat, thresh float64) *Mat {
	p := C.cv_threshold_binary(src.p, C.double(thresh))
	return &Mat{p: p}
}

// Convert8U wraps Mat::convertTo(CV_8UC1).
func Convert8U(src *Mat) *Mat {
	p := C.cv_convert_8u(src.p)
	return &Mat{p: p}
}

// ── Dilate ─────────────────────────────────────────────────────────────────

// Dilate2x2 performs dilation with a 2x2 ones kernel.
func Dilate2x2(src *Mat) *Mat {
	p := C.cv_dilate_2x2(src.p)
	return &Mat{p: p}
}

// ── Contours ───────────────────────────────────────────────────────────────

// ContourSet holds the result of findContours.
type ContourSet struct {
	p unsafe.Pointer
}

// Point represents a 2D integer point.
type ContourPoint struct{ X, Y int }

// FindContours finds all contours in a binary image.
func FindContours(src *Mat) *ContourSet {
	p := C.cv_find_contours(src.p)
	return &ContourSet{p: p}
}

// Count returns the number of contours.
func (cs *ContourSet) Count() int {
	return int(C.cv_contours_count(cs.p))
}

// Size returns the number of points in a contour.
func (cs *ContourSet) Size(idx int) int {
	return int(C.cv_contour_size(cs.p, C.int(idx)))
}

// GetPoint returns the i-th point of the idx-th contour.
func (cs *ContourSet) GetPoint(idx, ptIdx int) ContourPoint {
	var x, y C.int
	C.cv_contour_get_point(cs.p, C.int(idx), C.int(ptIdx), &x, &y)
	return ContourPoint{X: int(x), Y: int(y)}
}

// Release frees the contour set.
func (cs *ContourSet) Release() {
	if cs.p != nil {
		C.cv_contours_destroy(cs.p)
		cs.p = nil
	}
}

// ContourToPoints converts a single contour to a Go slice.
func (cs *ContourSet) ContourToPoints(idx int) []ContourPoint {
	n := cs.Size(idx)
	pts := make([]ContourPoint, n)
	for i := 0; i < n; i++ {
		pts[i] = cs.GetPoint(idx, i)
	}
	return pts
}

// ── minAreaRect ────────────────────────────────────────────────────────────

// MinAreaRect returns the 4 corner points of the minimum area bounding rectangle.
func MinAreaRect(pts []ContourPoint) [4]PointF {
	n := len(pts)
	xs := make([]C.int, n)
	ys := make([]C.int, n)
	for i, p := range pts {
		xs[i] = C.int(p.X)
		ys[i] = C.int(p.Y)
	}
	var outXs [4]C.float
	var outYs [4]C.float
	C.cv_min_area_rect_from_points(&xs[0], &ys[0], C.int(n), &outXs[0], &outYs[0])
	var result [4]PointF
	for i := 0; i < 4; i++ {
		result[i] = PointF{X: float64(outXs[i]), Y: float64(outYs[i])}
	}
	return result
}

// ── Perspective transform ──────────────────────────────────────────────────

// GetPerspectiveTransform computes a 3x3 perspective transform matrix.
func GetPerspectiveTransform(src, dst [4]PointF) *Mat {
	var srcXs, srcYs, dstXs, dstYs [4]C.float
	for i := 0; i < 4; i++ {
		srcXs[i] = C.float(src[i].X)
		srcYs[i] = C.float(src[i].Y)
		dstXs[i] = C.float(dst[i].X)
		dstYs[i] = C.float(dst[i].Y)
	}
	p := C.cv_get_perspective_transform(&srcXs[0], &srcYs[0], &dstXs[0], &dstYs[0])
	return &Mat{p: p}
}

const (
	BORDER_REPLICATE = 1
)

// WarpPerspective applies a perspective warp.
func WarpPerspective(src *Mat, transform *Mat, dstW, dstH int, borderMode int) *Mat {
	p := C.cv_warp_perspective(src.p, transform.p, C.int(dstW), C.int(dstH), C.int(borderMode))
	return &Mat{p: p}
}

// ── Mat to float ───────────────────────────────────────────────────────────

// ToFloat converts a Mat to CV_32F.
func ToFloat(src *Mat) *Mat {
	p := C.cv_mat_to_float(src.p)
	return &Mat{p: p}
}

// ── Channel split ──────────────────────────────────────────────────────────

// Split returns the 3 channels of a BGR Mat.
func Split(src *Mat) (ch0, ch1, ch2 *Mat) {
	var c0, c1, c2 unsafe.Pointer
	C.cv_split(src.p, &c0, &c1, &c2)
	return &Mat{p: c0}, &Mat{p: c1}, &Mat{p: c2}
}

// MultiplyScalar multiplies each element by s (in-place).
func MultiplyScalar(m *Mat, s float64) {
	C.cv_multiply_scalar(m.p, C.double(s))
}

// SubtractScalar subtracts s from each element (in-place).
func SubtractScalar(m *Mat, s float64) {
	C.cv_subtract_scalar(m.p, C.double(s))
}

// DivideScalar divides each element by s (in-place).
func DivideScalar(m *Mat, s float64) {
	C.cv_divide_scalar(m.p, C.double(s))
}

// ── Data extraction ────────────────────────────────────────────────────────

// GetFloat extracts the float data from a single-channel float Mat.
func (m *Mat) GetFloat(out []float32) {
	C.cv_mat_get_float(m.p, (*C.float)(&out[0]))
}

// GetFloatChannel extracts data from a specific channel.
func (m *Mat) GetFloatChannel(ch int, out []float32) {
	C.cv_mat_get_float_channel(m.p, C.int(ch), (*C.float)(&out[0]))
}

// ── Box score ──────────────────────────────────────────────────────────────

// MeanInPolygon computes the mean probability in a polygon region.
func MeanInPolygon(probMat *Mat, polyXs, polyYs []int, xmin, ymin, xmax, ymax int) float64 {
	n := len(polyXs)
	xs := make([]C.int, n)
	ys := make([]C.int, n)
	for i := 0; i < n; i++ {
		xs[i] = C.int(polyXs[i])
		ys[i] = C.int(polyYs[i])
	}
	return float64(C.cv_mean_in_polygon(
		probMat.p, &xs[0], &ys[0], C.int(n),
		C.int(xmin), C.int(ymin), C.int(xmax), C.int(ymax),
	))
}

// ── Rotate ─────────────────────────────────────────────────────────────────

// Rotate90CCW rotates a Mat 90 degrees counter-clockwise.
func Rotate90CCW(src *Mat) *Mat {
	p := C.cv_rotate_90_ccw(src.p)
	return &Mat{p: p}
}

func clampInt(v, lo, hi int) int {
	if v < lo {
		return lo
	}
	if v > hi {
		return hi
	}
	return v
}

func minInt(a, b int) int {
	if a < b {
		return a
	}
	return b
}

func maxInt(a, b int) int {
	if a > b {
		return a
	}
	return b
}

func maxFloat64(a, b float64) float64 {
	if a > b {
		return a
	}
	return b
}

func minFloat64(a, b float64) float64 {
	if a < b {
		return a
	}
	return b
}

func roundInt(f float64) int {
	return int(math.Floor(f + 0.5))
}

func ceilInt(f float64) int {
	return int(math.Ceil(f))
}

func hypot(a, b float64) float64 {
	return math.Hypot(a, b)
}

// Orthographic helpers for error messages.
func checkError(err error, msg string) error {
	if err != nil {
		return fmt.Errorf("%s: %w", msg, err)
	}
	return nil
}