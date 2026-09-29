//go:build !noocr

package ocr

import "math"

// RecPreprocessResult holds the preprocessed tensor for recognition.
type RecPreprocessResult struct {
	TensorData []float32
	Shape      []int64 // [N, 3, 48, maxW]
}

const (
	recFixedHeight = 48
	recMaxImgW     = 3200
)

// RecPreprocessBatch mirrors RecPreprocessor.preprocessBatch (Kotlin).
// Converts crops from BGR→RGB, resizes to fixed height 48, normalizes to [-1, 1].
func RecPreprocessBatch(crops []*Mat) (*RecPreprocessResult, error) {
	// Step 1: BGR→RGB, resize to height=48
	var resizedMats []*Mat
	for _, crop := range crops {
		rgb := CvtColor(crop, COLOR_BGR2RGB)
		h := rgb.Rows()
		w := rgb.Cols()
		aspectRatio := 1.0
		if h > 0 {
			aspectRatio = float64(w) / float64(h)
		}
		newW := int(math.Ceil(float64(recFixedHeight) * aspectRatio))
		if newW > recMaxImgW {
			newW = recMaxImgW
		}
		if newW < 1 {
			newW = 1
		}
		dst := Resize(rgb, newW, recFixedHeight, INTER_LINEAR)
		rgb.Release()
		resizedMats = append(resizedMats, dst)
	}

	// Step 2: Convert to float, normalize: (x/255 - 0.5) / 0.5 = x/127.5 - 1
	maxW := 0
	var floatMats []*Mat
	for _, mat := range resizedMats {
		fm := ToFloat(mat)
		// Use 3-channel scalar: divide by 127.5, subtract 1
		DivideScalar(fm, 127.5)
		SubtractScalar(fm, 1.0)

		floatMats = append(floatMats, fm)
		if mat.Cols() > maxW {
			maxW = mat.Cols()
		}
		mat.Release()
	}
	resizedMats = nil

	// Step 3: Pad to maxW
	n := len(floatMats)
	for i, mat := range floatMats {
		if mat.Cols() < maxW {
			// Create padded mat - we need to build one manually
			// Since we don't have a pad function in the bridge, we create a larger mat
			// and use ROI copy... Actually this is complex. Let's handle it differently.
			// We'll just create zero-mat and copy via the available functions.
			// For now, we handle padding in Go by adjusting the tensor data directly.
			_ = i
		}
	}

	// Build tensor: [N, 3, 48, maxW]
	// For each sample, we pack as [R_plane, G_plane, B_plane] with padding
	channelSize := recFixedHeight * maxW
	tensorData := make([]float32, n*3*channelSize)

	for b := 0; b < n; b++ {
		mat := floatMats[b]
		matH := mat.Rows()  // should be 48
		matW := mat.Cols()

		ch0, ch1, ch2 := Split(mat)
		bufR := make([]float32, matH*matW)
		bufG := make([]float32, matH*matW)
		bufB := make([]float32, matH*matW)
		ch0.GetFloat(bufR)
		ch1.GetFloat(bufG)
		ch2.GetFloat(bufB)
		ch0.Release()
		ch1.Release()
		ch2.Release()

		// Copy with padding (fill rest with 0, which is what default Scalar(0) padding gives)
		baseR := (b * 3) * channelSize
		baseG := (b*3 + 1) * channelSize
		baseB := (b*3 + 2) * channelSize

		for row := 0; row < recFixedHeight; row++ {
			for col := 0; col < maxW; col++ {
				idxFlat := row*maxW + col
				if col < matW && row < matH {
					srcIdx := row*matW + col
					tensorData[baseR+idxFlat] = bufR[srcIdx]
					tensorData[baseG+idxFlat] = bufG[srcIdx]
					tensorData[baseB+idxFlat] = bufB[srcIdx]
				}
				// else: leave as 0 (padding)
			}
		}
		mat.Release()
	}

	return &RecPreprocessResult{
		TensorData: tensorData,
		Shape:      []int64{int64(n), 3, int64(recFixedHeight), int64(maxW)},
	}, nil
}