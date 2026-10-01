//go:build !noocr

// opencv_bridge.cpp — C wrapper around OpenCV C++ functions needed by the OCR pipeline.
// Go CGO calls these via extern "C" functions. No Go code in this file.
#include <opencv2/core.hpp>
#include <opencv2/imgproc.hpp>
#include <opencv2/geometry/2d.hpp>
#include <cstdint>
#include <cstring>

extern "C" {

// ── Mat lifecycle ──────────────────────────────────────────────────────────

void* cv_mat_create(int rows, int cols, int type) {
    return new cv::Mat(rows, cols, type);
}

void* cv_mat_create_from_rgba(int rows, int cols, const uint8_t* rgba) {
    // Go stores RGBA in memory. OpenCV prefers BGR. Create 4-channel Mat first.
    cv::Mat rgbaMat(rows, cols, CV_8UC4, const_cast<uint8_t*>(rgba));
    cv::Mat* bgr = new cv::Mat();
    cv::cvtColor(rgbaMat, *bgr, cv::COLOR_RGBA2BGR);
    return bgr;
}

void cv_mat_destroy(void* m) {
    delete static_cast<cv::Mat*>(m);
}

int cv_mat_rows(void* m) { return static_cast<cv::Mat*>(m)->rows; }
int cv_mat_cols(void* m) { return static_cast<cv::Mat*>(m)->cols; }
int cv_mat_type(void* m) { return static_cast<cv::Mat*>(m)->type(); }
int cv_mat_channels(void* m) { return static_cast<cv::Mat*>(m)->channels(); }

// ── Color conversion ───────────────────────────────────────────────────────

void* cv_cvt_color(void* src, int code) {
    cv::Mat* dst = new cv::Mat();
    cv::cvtColor(*static_cast<cv::Mat*>(src), *dst, code);
    return dst;
}

// ── Resize ─────────────────────────────────────────────────────────────────

void* cv_resize(void* src, int width, int height, int interpolation) {
    cv::Mat* dst = new cv::Mat();
    cv::resize(*static_cast<cv::Mat*>(src), *dst, cv::Size(width, height), 0.0, 0.0, interpolation);
    return dst;
}

// ── Threshold ──────────────────────────────────────────────────────────────

void* cv_threshold_binary(void* src, double thresh) {
    cv::Mat* dst = new cv::Mat();
    cv::threshold(*static_cast<cv::Mat*>(src), *dst, thresh, 255.0, cv::THRESH_BINARY);
    return dst;
}

// ── Convert float Mat to 8UC1 ──────────────────────────────────────────────

void* cv_convert_8u(void* src) {
    cv::Mat* dst = new cv::Mat();
    static_cast<cv::Mat*>(src)->convertTo(*dst, CV_8UC1);
    return dst;
}

// ── Dilate ─────────────────────────────────────────────────────────────────

void* cv_dilate_2x2(void* src) {
    cv::Mat* dst = new cv::Mat();
    cv::Mat kernel = cv::Mat::ones(2, 2, CV_8UC1);
    cv::dilate(*static_cast<cv::Mat*>(src), *dst, kernel);
    return dst;
}

// ── Find contours ──────────────────────────────────────────────────────────
// Returns count of contours found. contours_out and hierarchy_out must be freed.

struct ContoursResult {
    std::vector<std::vector<cv::Point>> contours;
    std::vector<cv::Vec4i> hierarchy;
};

void* cv_find_contours(void* src) {
    auto* result = new ContoursResult();
    cv::findContours(*static_cast<cv::Mat*>(src), result->contours, result->hierarchy,
                     cv::RETR_LIST, cv::CHAIN_APPROX_SIMPLE);
    return result;
}

int cv_contours_count(void* cr) {
    return static_cast<int>(static_cast<ContoursResult*>(cr)->contours.size());
}

int cv_contour_size(void* cr, int idx) {
    return static_cast<int>(static_cast<ContoursResult*>(cr)->contours[idx].size());
}

void cv_contour_get_point(void* cr, int idx, int pt_idx, int* out_x, int* out_y) {
    auto& pt = static_cast<ContoursResult*>(cr)->contours[idx][pt_idx];
    *out_x = pt.x;
    *out_y = pt.y;
}

void cv_contours_destroy(void* cr) {
    delete static_cast<ContoursResult*>(cr);
}

// ── minAreaRect ────────────────────────────────────────────────────────────
// Returns 4 corner points (order: OpenCV default) via out arrays.

void cv_min_area_rect_from_points(const int* xs, const int* ys, int n,
                                   float* out_xs, float* out_ys) {
    std::vector<cv::Point2f> pts;
    pts.reserve(n);
    for (int i = 0; i < n; i++) {
        pts.emplace_back(static_cast<float>(xs[i]), static_cast<float>(ys[i]));
    }
    cv::RotatedRect rect = cv::minAreaRect(pts);
    cv::Point2f corners[4];
    rect.points(corners);
    for (int i = 0; i < 4; i++) {
        out_xs[i] = corners[i].x;
        out_ys[i] = corners[i].y;
    }
}

// ── Perspective transform ──────────────────────────────────────────────────

void* cv_get_perspective_transform(float src_xs[4], float src_ys[4],
                                   float dst_xs[4], float dst_ys[4]) {
    cv::Point2f src[4], dst[4];
    for (int i = 0; i < 4; i++) {
        src[i] = cv::Point2f(src_xs[i], src_ys[i]);
        dst[i] = cv::Point2f(dst_xs[i], dst_ys[i]);
    }
    cv::Mat* m = new cv::Mat();
    *m = cv::getPerspectiveTransform(src, dst);
    return m;
}

void* cv_warp_perspective(void* src, void* transform, int dst_w, int dst_h, int borderMode) {
    cv::Mat* dst = new cv::Mat(dst_h, dst_w, CV_8UC3);
    cv::warpPerspective(*static_cast<cv::Mat*>(src), *dst,
                        *static_cast<cv::Mat*>(transform),
                        cv::Size(dst_w, dst_h),
                        cv::INTER_CUBIC, borderMode);
    return dst;
}

// ── Mat conversion to/from float ───────────────────────────────────────────

void* cv_mat_to_float(void* src) {
    cv::Mat* dst = new cv::Mat();
    static_cast<cv::Mat*>(src)->convertTo(*dst, CV_32F);
    return dst;
}

// ── Split channels ─────────────────────────────────────────────────────────
// Returns array of 3 Mat*. Caller must cv_mat_destroy each.

void cv_split(void* src, void** ch0, void** ch1, void** ch2) {
    std::vector<cv::Mat> channels;
    cv::split(*static_cast<cv::Mat*>(src), channels);
    *ch0 = new cv::Mat(channels[0]);
    *ch1 = new cv::Mat(channels[1]);
    *ch2 = new cv::Mat(channels[2]);
}

// ── Channel math (in-place) ────────────────────────────────────────────────

void cv_multiply_scalar(void* mat, double s) {
    // *mat = *mat * s
    *static_cast<cv::Mat*>(mat) *= s;
}

void cv_subtract_scalar(void* mat, double s) {
    *static_cast<cv::Mat*>(mat) -= s;
}

void cv_divide_scalar(void* mat, double s) {
    *static_cast<cv::Mat*>(mat) /= s;
}

// ── Mat data extraction ────────────────────────────────────────────────────

void cv_mat_get_float(void* mat, float* out) {
    cv::Mat* m = static_cast<cv::Mat*>(mat);
    // m->data is contiguous
    std::memcpy(out, m->data, m->rows * m->cols * sizeof(float));
}

void cv_mat_get_float_channel(void* mat, int ch, float* out) {
    cv::Mat* m = static_cast<cv::Mat*>(mat);
    int n = m->rows * m->cols;
    int cn = m->channels();
    for (int i = 0; i < n; i++) {
        out[i] = m->at<float>(i * cn + ch);
    }
}

// Not needed — we extract via cv_split
// (kept as alternative for future)

// ── fillPoly + mean (for computeBoxScore) ──────────────────────────────────

double cv_mean_in_polygon(void* probMat,
                          const int* poly_xs, const int* poly_ys, int n,
                          int xmin, int ymin, int xmax, int ymax) {
    cv::Mat* prob = static_cast<cv::Mat*>(probMat);
    int w = xmax - xmin + 1;
    int h = ymax - ymin + 1;
    cv::Mat mask = cv::Mat::zeros(h, w, CV_8UC1);

    std::vector<cv::Point> pts;
    pts.reserve(n);
    for (int i = 0; i < n; i++) {
        pts.emplace_back(poly_xs[i] - xmin, poly_ys[i] - ymin);
    }
    std::vector<std::vector<cv::Point>> polys = {pts};
    cv::fillPoly(mask, polys, cv::Scalar(1.0));

    cv::Mat roi = (*prob)(cv::Range(ymin, ymax + 1), cv::Range(xmin, xmax + 1));
    cv::Scalar mean = cv::mean(roi, mask);
    return mean[0];
}

// ── Rotate 90 CCW ──────────────────────────────────────────────────────────

void* cv_rotate_90_ccw(void* src) {
    cv::Mat* dst = new cv::Mat();
    cv::rotate(*static_cast<cv::Mat*>(src), *dst, cv::ROTATE_90_COUNTERCLOCKWISE);
    return dst;
}

} // extern "C"