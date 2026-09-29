package ocr

import "math"

// SortBoxesInReadingOrder sorts OCR boxes from top-to-bottom, left-to-right.
// Mirrors PaddleOCR BoxSorter with ROW_THRESHOLD_Y=10.
func SortBoxesInReadingOrder(boxes []OCRBox) []OCRBox {
	if len(boxes) <= 1 {
		return boxes
	}

	list := make([]OCRBox, len(boxes))
	copy(list, boxes)

	// Sort by Y then X
	for i := 0; i < len(list); i++ {
		for j := i + 1; j < len(list); j++ {
			if list[j].Points[0].Y < list[i].Points[0].Y ||
				(list[j].Points[0].Y == list[i].Points[0].Y && list[j].Points[0].X < list[i].Points[0].X) {
				list[i], list[j] = list[j], list[i]
			}
		}
	}

	// Bubble swap within same row band (10px threshold)
	for i := 0; i < len(list)-1; i++ {
		j := i
		for j >= 0 {
			next := list[j+1]
			curr := list[j]
			if math.Abs(next.Points[0].Y-curr.Points[0].Y) < 10 &&
				next.Points[0].X < curr.Points[0].X {
				list[j] = next
				list[j+1] = curr
				j--
			} else {
				break
			}
		}
	}
	return list
}