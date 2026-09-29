//go:build !noocr

package ocr

import (
	"math"
)

// DBPostProcessor mirrors the PaddleOCR DBPostProcessor (Kotlin).
// It runs threshold → findContours → minAreaRect → unclip → box filtering.
type DBPostProcessor struct {
	Thresh       float64
	BoxThresh    float64
	UnclipRatio  float64
	MaxCandidates int
	UseDilation  bool
}

// DefaultDBConfig returns the default PaddleOCR DB postprocessing config.
func DefaultDBConfig() DBPostProcessor {
	return DBPostProcessor{
		Thresh:       0.3,
		BoxThresh:    0.6,
		UnclipRatio:  1.5,
		MaxCandidates: 3000,
		UseDilation:  false,
	}
}

// Process runs DB postprocessing on the detection model output.
// Uses pure-Go implementation: threshold → connected components → minAreaRect via CGO → unclip.
func (cfg DBPostProcessor) Process(pred []float32, predShape []int64, originalW, originalH int) ([]OCRBox, error) {
	pH := int(predShape[2])
	pW := int(predShape[3])
	scaleX := float64(originalW) / float64(pW)
	scaleY := float64(originalH) / float64(pH)

	boxes := cfg.processGo(pred, pH, pW, scaleX, scaleY, originalW, originalH)
	return boxes, nil
}

// processGo implements DB postprocessing in pure Go (threshold → find components → boxes).
func (cfg DBPostProcessor) processGo(pred []float32, pH, pW int, scaleX, scaleY float64, originalW, originalH int) []OCRBox {
	// Step 1: Threshold → binary
	binary := make([]bool, pH*pW)
	for i, v := range pred {
		binary[i] = v >= float32(cfg.Thresh)
	}

	// Step 2: Dilation (if enabled)
	if cfg.UseDilation {
		binary = dilateMask(binary, pH, pW)
	}

	// Step 3: Connected components via flood fill
	type blob struct {
		pixels []int // flat indices
		minX, minY, maxX, maxY int
	}
	var blobs []blob
	visited := make([]bool, len(binary))

	for y := 0; y < pH; y++ {
		for x := 0; x < pW; x++ {
			idx := y*pW + x
			if !binary[idx] || visited[idx] {
				continue
			}
			// Flood fill 8-connected
			stack := []int{idx}
			visited[idx] = true
			b := blob{
				minX: x, maxX: x,
				minY: y, maxY: y,
			}
			for len(stack) > 0 {
				cur := stack[len(stack)-1]
				stack = stack[:len(stack)-1]
				cy := cur / pW
				cx := cur % pW
				b.pixels = append(b.pixels, cur)
				if cx < b.minX { b.minX = cx }
				if cx > b.maxX { b.maxX = cx }
				if cy < b.minY { b.minY = cy }
				if cy > b.maxY { b.maxY = cy }

				// 8 neighbors
				for dy := -1; dy <= 1; dy++ {
					for dx := -1; dx <= 1; dx++ {
						if dy == 0 && dx == 0 { continue }
						nx, ny := cx+dx, cy+dy
						if nx < 0 || nx >= pW || ny < 0 || ny >= pH { continue }
						nidx := ny*pW + nx
						if binary[nidx] && !visited[nidx] {
							visited[nidx] = true
							stack = append(stack, nidx)
						}
					}
				}
			}
			blobs = append(blobs, b)
		}
	}

	// Step 4: For each blob, compute minAreaRect (via OpenCV), score, unclip
	var boxes []OCRBox
	count := 0
	for _, b := range blobs {
		if count >= cfg.MaxCandidates {
			break
		}
		// Compute contour from blob pixels
		contour := blobToBorder(b.pixels, pH, pW)
		if len(contour) < 3 {
			continue
		}

		// minAreaRect via OpenCV
		rectPts := MinAreaRect(contour)
		sside := minFloat64(
			hypot(float64(rectPts[1].X-rectPts[0].X), float64(rectPts[1].Y-rectPts[0].Y)),
			hypot(float64(rectPts[3].X-rectPts[0].X), float64(rectPts[3].Y-rectPts[0].Y)),
		)
		if sside < 3 {
			continue
		}

		// Order points
		ordered := orderMinAreaRectPoints(rectPts)

		// Score
		score := cfg.computeBoxScoreFast(pred, pH, pW, ordered)
		if score < float32(cfg.BoxThresh) {
			continue
		}

		// Unclip
		expandedPts := unclip(ordered, cfg.UnclipRatio)
		expandedIdx := make([]ContourPoint, len(expandedPts))
		for i, p := range expandedPts {
			expandedIdx[i] = ContourPoint{roundInt(p.X), roundInt(p.Y)}
		}
		expandedRect := MinAreaRect(expandedIdx)
		sside2 := minFloat64(
			hypot(float64(expandedRect[1].X-expandedRect[0].X), float64(expandedRect[1].Y-expandedRect[0].Y)),
			hypot(float64(expandedRect[3].X-expandedRect[0].X), float64(expandedRect[3].Y-expandedRect[0].Y)),
		)
		if sside2 < 5 {
			continue
		}

		eOrdered := orderMinAreaRectPoints(expandedRect)
		var scaled [4]PointF
		for i := 0; i < 4; i++ {
			scaled[i] = PointF{
				X: clampFloat(eOrdered[i].X*scaleX, 0, float64(originalW)),
				Y: clampFloat(eOrdered[i].Y*scaleY, 0, float64(originalH)),
			}
		}

		// Box dimension check
		boxW := hypot(scaled[1].X-scaled[0].X, scaled[1].Y-scaled[0].Y)
		boxH := hypot(scaled[3].X-scaled[0].X, scaled[3].Y-scaled[0].Y)
		if boxW <= 3 || boxH <= 3 {
			continue
		}

		boxes = append(boxes, OCRBox{Points: scaled})
		count++
	}

	return boxes
}

// orderMinAreaRectPoints orders 4 rect points to [top-left, top-right, bottom-right, bottom-left].
func orderMinAreaRectPoints(pts [4]PointF) [4]PointF {
	// Sort by X
	sorted := [4]PointF{pts[0], pts[1], pts[2], pts[3]}
	for i := 0; i < 3; i++ {
		for j := i + 1; j < 4; j++ {
			if sorted[j].X < sorted[i].X {
				sorted[i], sorted[j] = sorted[j], sorted[i]
			}
		}
	}
	var tl, bl PointF
	if sorted[1].Y > sorted[0].Y {
		tl = sorted[0]
		bl = sorted[1]
	} else {
		tl = sorted[1]
		bl = sorted[0]
	}
	var tr, br PointF
	if sorted[3].Y > sorted[2].Y {
		tr = sorted[2]
		br = sorted[3]
	} else {
		tr = sorted[3]
		br = sorted[2]
	}
	return [4]PointF{tl, tr, br, bl}
}

func clampFloat(v, lo, hi float64) float64 {
	if v < lo { return lo }
	if v > hi { return hi }
	return v
}

// computeBoxScoreFast computes the mean probability inside a polygon (fast mode).
func (cfg DBPostProcessor) computeBoxScoreFast(pred []float32, pH, pW int, pts [4]PointF) float32 {
	// Compute bounding box of the polygon
	xmin := int(math.Floor(minFloat64(minFloat64(pts[0].X, pts[1].X), minFloat64(pts[2].X, pts[3].X))))
	xmax := int(math.Ceil(maxFloat64(maxFloat64(pts[0].X, pts[1].X), maxFloat64(pts[2].X, pts[3].X))))
	ymin := int(math.Floor(minFloat64(minFloat64(pts[0].Y, pts[1].Y), minFloat64(pts[2].Y, pts[3].Y))))
	ymax := int(math.Ceil(maxFloat64(maxFloat64(pts[0].Y, pts[1].Y), maxFloat64(pts[2].Y, pts[3].Y))))

	xmin = clampInt(xmin, 0, pW-1)
	xmax = clampInt(xmax, 0, pW-1)
	ymin = clampInt(ymin, 0, pH-1)
	ymax = clampInt(ymax, 0, pH-1)

	// Use point-in-polygon test within the bounding box
	var sum float32
	count := 0
	for y := ymin; y <= ymax; y++ {
		for x := xmin; x <= xmax; x++ {
			if pointInPolygon(float64(x), float64(y), pts) {
				sum += pred[y*pW+x]
				count++
			}
		}
	}
	if count == 0 {
		return 0
	}
	return sum / float32(count)
}

func pointInPolygon(x, y float64, poly [4]PointF) bool {
	inside := false
	n := len(poly)
	for i, j := 0, n-1; i < n; j, i = i, i+1 {
		if ((poly[i].Y > y) != (poly[j].Y > y)) &&
			(x < (poly[j].X-poly[i].X)*(y-poly[i].Y)/(poly[j].Y-poly[i].Y)+poly[i].X) {
			inside = !inside
		}
	}
	return inside
}

// blobToBorder extracts border pixels from a blob (connected component).
func blobToBorder(pixels []int, h, w int) []ContourPoint {
	// Build a set for quick lookup
	set := make(map[int]bool)
	minX, minY := w, h
	maxX, maxY := 0, 0
	for _, idx := range pixels {
		set[idx] = true
		cy := idx / w
		cx := idx % w
		if cx < minX { minX = cx }
		if cx > maxX { maxX = cx }
		if cy < minY { minY = cy }
		if cy > maxY { maxY = cy }
	}

	// Find border pixels
	var border []ContourPoint
	for _, idx := range pixels {
		cy := idx / w
		cx := idx % w
		isBorder := false
		for dy := -1; dy <= 1; dy++ {
			for dx := -1; dx <= 1; dx++ {
				if dy == 0 && dx == 0 { continue }
				nx, ny := cx+dx, cy+dy
				if nx < 0 || nx >= w || ny < 0 || ny >= h {
					isBorder = true
					break
				}
				if !set[ny*w+nx] {
					isBorder = true
					break
				}
			}
			if isBorder { break }
		}
		if isBorder {
			border = append(border, ContourPoint{X: cx, Y: cy})
		}
	}
	return border
}

// dilateMask performs a 2x2 dilation on the binary mask.
func dilateMask(binary []bool, h, w int) []bool {
	result := make([]bool, len(binary))
	copy(result, binary)
	for y := 0; y < h; y++ {
		for x := 0; x < w; x++ {
			if binary[y*w+x] {
				for dy := 0; dy <= 1 && y+dy < h; dy++ {
					for dx := 0; dx <= 1 && x+dx < w; dx++ {
						result[(y+dy)*w+(x+dx)] = true
					}
				}
			}
		}
	}
	return result
}

// unclip expands a polygon outward by a distance proportional to area/perimeter.
func unclip(pts [4]PointF, unclipRatio float64) []PointF {
	// Convert to points
	points := []PointF{pts[0], pts[1], pts[2], pts[3]}
	if len(points) < 3 {
		return points
	}

	signedArea := polygonArea(points)
	area := math.Abs(signedArea)
	perimeter := polygonPerimeter(points)
	if area <= 1e-6 || perimeter <= 1e-6 {
		return points
	}

	distance := area * unclipRatio / perimeter
	if distance <= 1e-6 {
		return points
	}

	clockwise := signedArea > 0

	// Compute normals
	normals := make([]PointF, len(points))
	for i := 0; i < len(points); i++ {
		start := points[i]
		end := points[(i+1)%len(points)]
		dx := end.X - start.X
		dy := end.Y - start.Y
		length := math.Hypot(dx, dy)
		if length <= 1e-6 {
			return points
		}
		if clockwise {
			normals[i] = PointF{dy / length, -dx / length}
		} else {
			normals[i] = PointF{-dy / length, dx / length}
		}
	}

	// Expand with round joins
	var expanded []PointF
	for i := range points {
		prevN := normals[(i-1+len(normals))%len(normals)]
		curN := normals[i]
		appendRoundJoin(&expanded, points[i], prevN, curN, distance, clockwise)
	}
	if len(expanded) < 3 {
		return points
	}
	return expanded
}

func polygonArea(pts []PointF) float64 {
	sum := 0.0
	n := len(pts)
	for i := 0; i < n; i++ {
		p1 := pts[i]
		p2 := pts[(i+1)%n]
		sum += p1.X*p2.Y - p2.X*p1.Y
	}
	return sum / 2.0
}

func polygonPerimeter(pts []PointF) float64 {
	length := 0.0
	n := len(pts)
	for i := 0; i < n; i++ {
		p1 := pts[i]
		p2 := pts[(i+1)%n]
		length += math.Hypot(p2.X-p1.X, p2.Y-p1.Y)
	}
	return length
}

func appendRoundJoin(output *[]PointF, center, fromNormal, toNormal PointF, distance float64, clockwise bool) {
	startAngle := math.Atan2(fromNormal.Y, fromNormal.X)
	endAngle := math.Atan2(toNormal.Y, toNormal.X)

	if clockwise {
		for endAngle < startAngle {
			endAngle += 2 * math.Pi
		}
	} else {
		for endAngle > startAngle {
			endAngle -= 2 * math.Pi
		}
	}

	sweep := endAngle - startAngle
	stepAngle := arcStepAngle(distance)
	steps := int(math.Ceil(math.Abs(sweep) / stepAngle))
	if steps < 1 {
		steps = 1
	}

	for step := 0; step <= steps; step++ {
		angle := startAngle + sweep*float64(step)/float64(steps)
		pt := PointF{
			X: center.X + math.Cos(angle)*distance,
			Y: center.Y + math.Sin(angle)*distance,
		}
		// Dedup with last
		if len(*output) > 0 {
			last := (*output)[len(*output)-1]
			if math.Hypot(pt.X-last.X, pt.Y-last.Y) <= 1e-6 {
				continue
			}
		}
		*output = append(*output, pt)
	}
}

func arcStepAngle(distance float64) float64 {
	ratio := 1.0 - 0.25/distance
	if ratio < -1.0 { ratio = -1.0 }
	if ratio > 1.0 { ratio = 1.0 }
	step := 2.0 * math.Acos(ratio)
	if step > 1e-6 {
		return step
	}
	return math.Pi / 8.0
}