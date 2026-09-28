package pdfconv

import (
	"bytes"
	"fmt"
	"image"
	"image/jpeg"
	"path/filepath"
	"strings"

	"github.com/gen2brain/go-fitz"
)

// Convert converts a PDF file to a docx file, calling progressFn with
// completion ratio (0.0–1.0) after each page.
func Convert(pdfPath string, progressFn func(float64)) (string, error) {
	doc, err := fitz.New(pdfPath)
	if err != nil {
		return "", fmt.Errorf("open PDF: %w", err)
	}
	defer doc.Close()

	numPages := doc.NumPage()
	if numPages == 0 {
		return "", fmt.Errorf("PDF has no pages")
	}

	const dpi = 150.0
	db := &docxBuilder{}

	for i := 0; i < numPages; i++ {
		img, err := doc.ImageDPI(i, dpi)
		if err != nil {
			return "", fmt.Errorf("render page %d: %w", i+1, err)
		}

		jpgData, w, h, err := encodeJPEG(img)
		if err != nil {
			return "", fmt.Errorf("encode page %d: %w", i+1, err)
		}
		db.add(jpgData, w, h)
		progressFn(float64(i+1) / float64(numPages))
	}

	docxPath := outputPath(pdfPath)
	if err := saveDocx(docxPath, db); err != nil {
		return "", fmt.Errorf("save docx: %w", err)
	}

	return docxPath, nil
}

func encodeJPEG(img *image.RGBA) ([]byte, int, int, error) {
	var buf bytes.Buffer
	if err := jpeg.Encode(&buf, img, &jpeg.Options{Quality: 80}); err != nil {
		return nil, 0, 0, err
	}
	return buf.Bytes(), img.Bounds().Dx(), img.Bounds().Dy(), nil
}

func outputPath(pdfPath string) string {
	dir := filepath.Dir(pdfPath)
	base := filepath.Base(pdfPath)
	name := strings.TrimSuffix(base, filepath.Ext(base))
	return filepath.Join(dir, name+".docx")
}