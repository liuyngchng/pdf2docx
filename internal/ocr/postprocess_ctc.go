package ocr

// CTCDecode decodes CTC output using greedy search with blank index 0.
// Mirrors PaddleOCR CTCDecoder.
func CTCDecode(output []float32, shape []int64, characterList []string) []TextLine {
	batchSize := int(shape[0])
	timeSteps := int(shape[1])
	numClasses := int(shape[2])

	results := make([]TextLine, 0, batchSize)
	for b := 0; b < batchSize; b++ {
		baseOffset := b * timeSteps * numClasses

		// Argmax per timestep
		indices := make([]int, timeSteps)
		probs := make([]float32, timeSteps)
		for t := 0; t < timeSteps; t++ {
			offset := baseOffset + t*numClasses
			maxIdx := 0
			maxVal := output[offset]
			for c := 1; c < numClasses; c++ {
				v := output[offset+c]
				if v > maxVal {
					maxVal = v
					maxIdx = c
				}
			}
			indices[t] = maxIdx
			probs[t] = maxVal
		}

		// CTC merge: remove consecutive duplicates and blank (index 0)
		var keptProbs []float32
		var sb []byte
		prevIdx := -1
		for t := 0; t < timeSteps; t++ {
			idx := indices[t]
			if idx != 0 && idx != prevIdx {
				charIdx := idx - 1
				if charIdx >= 0 && charIdx < len(characterList) {
					sb = append(sb, []byte(characterList[charIdx])...)
					keptProbs = append(keptProbs, probs[t])
				}
			}
			prevIdx = idx
		}

		confidence := float32(0)
		if len(keptProbs) > 0 {
			var sum float32
			for _, p := range keptProbs {
				sum += p
			}
			confidence = sum / float32(len(keptProbs))
		}
		results = append(results, TextLine{Text: string(sb), Confidence: confidence})
	}
	return results
}