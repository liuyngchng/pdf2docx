// Command cli is a headless PDF → Word converter used for testing and
// validating the pure-Go rendering pipeline without the Fyne GUI.
//
// Build (requires CGO for OCR support):
//
//	CGO_ENABLED=1 go build -o pdftoword-cli ./cmd/cli/
//
// Or without OCR:
//
//	CGO_ENABLED=0 go build -tags noocr -o pdftoword-cli ./cmd/cli/
package main

import (
	"fmt"
	"os"

	"pdftoword/internal/pdfconv"
)

func main() {
	if len(os.Args) < 2 {
		fmt.Fprintf(os.Stderr, "Usage: pdftoword-cli [--ocr] <pdf_file>\n")
		os.Exit(1)
	}

	enableOCR := false
	var pdfPath string
	for _, arg := range os.Args[1:] {
		if arg == "--ocr" {
			enableOCR = true
		} else {
			pdfPath = arg
		}
	}
	if pdfPath == "" {
		fmt.Fprintf(os.Stderr, "Usage: pdftoword-cli [--ocr] <pdf_file>\n")
		os.Exit(1)
	}

	fmt.Printf("Converting: %s (OCR: %v)\n", pdfPath, enableOCR)

	docxPath, err := pdfconv.Convert(pdfPath, enableOCR, func(pct float64) {
		const barWidth = 40
		filled := int(pct * float64(barWidth))
		bar := ""
		for i := 0; i < barWidth; i++ {
			if i < filled {
				bar += "="
			} else {
				bar += "-"
			}
		}
		fmt.Printf("\r[%s] %.0f%%", bar, pct*100)
	})
	fmt.Println()

	if err != nil {
		fmt.Fprintf(os.Stderr, "ERROR: %v\n", err)
		os.Exit(1)
	}

	fmt.Printf("Done: %s\n", docxPath)
}