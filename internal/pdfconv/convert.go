package pdfconv

import (
	"bytes"
	"fmt"
	"image"
	"image/jpeg"
	"os"
	"path/filepath"
	"regexp"
	"strings"

	"pdftoword/internal/ocr"

	"github.com/gen2brain/go-fitz"
)

// Convert converts a PDF file to docx file(s), calling progressFn with
// completion ratio (0.0–1.0) after each page.
// If enableOCR is true and models are available, also produces name.ocr.docx.
func Convert(pdfPath string, enableOCR bool, progressFn func(float64)) (string, error) {
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

	// OCR setup
	var ocrEngine *ocr.Engine
	var ocrDB *textDocxBuilder
	baseDir, _ := os.Getwd() // fallback
	if exe, err := os.Executable(); err == nil {
		baseDir = filepath.Dir(exe)
	}
	if enableOCR && ocr.CheckModels(baseDir) {
		var loadErr error
		ocrEngine, loadErr = ocr.NewEngineWithConfig(ocr.ModelsDir(baseDir), ocr.DefaultConfig())
		if loadErr != nil {
			// Log but continue — screenshot version still works
			fmt.Fprintf(os.Stderr, "OCR engine load failed: %v\n", loadErr)
			ocrEngine = nil
		} else {
			ocrDB = &textDocxBuilder{}
			defer ocrEngine.Release()
		}
	}

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

		// OCR on this page
		if ocrEngine != nil {
			ocrTexts := runOCRPage(ocrEngine, img)
			ocrDB.addPage(ocrTexts)
		}

		progressFn(float64(i+1) / float64(numPages))
	}

	// Save screenshot DOCX
	docxPath := outputPath(pdfPath)
	if err := saveDocx(docxPath, db); err != nil {
		return "", fmt.Errorf("save docx: %w", err)
	}

	// Save OCR text DOCX
	if ocrDB != nil {
		ocrPath := ocrOutputPath(pdfPath)
		if err := saveTextDocx(ocrPath, ocrDB); err != nil {
			fmt.Fprintf(os.Stderr, "OCR docx save failed: %v\n", err)
		}
	}

	return docxPath, nil
}

func runOCRPage(engine *ocr.Engine, img *image.RGBA) []string {
	mat := ocr.NewMatFromRGBA(img)
	if mat == nil {
		return nil
	}
	defer mat.Release()

	pageText, err := engine.Recognize(mat)
	if err != nil {
		fmt.Fprintf(os.Stderr, "OCR page failed: %v\n", err)
		return nil
	}

	// Clean and merge recognized text lines.
	// Strip ' characters (model delimiter/padding character in PP-OCR).
	// Join adjacent text lines on the same row into single paragraphs.
	var cleaned []string
	for _, l := range pageText.Lines {
		t := strings.ReplaceAll(l.Text, "'", "")
		t = strings.TrimSpace(t)
		if t == "" {
			continue
		}
		cleaned = append(cleaned, t)
	}
	return cleaned
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

func ocrOutputPath(pdfPath string) string {
	dir := filepath.Dir(pdfPath)
	base := filepath.Base(pdfPath)
	name := strings.TrimSuffix(base, filepath.Ext(base))
	return filepath.Join(dir, name+".ocr.docx")
}