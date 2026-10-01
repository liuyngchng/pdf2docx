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
	mode := pdfconv.ModeImage
	var pdfPath string

	for _, arg := range os.Args[1:] {
		switch arg {
		case "--ocr":
			// Backward compatible alias for --mode text.
			mode = pdfconv.ModeText
		case "--mode":
			// Consumed below via positional check.
		default:
			pdfPath = arg
		}
	}

	// Check for --mode <value> in args.
	for i := 1; i < len(os.Args); i++ {
		if os.Args[i] == "--mode" && i+1 < len(os.Args) {
			switch os.Args[i+1] {
			case "image":
				mode = pdfconv.ModeImage
			case "text":
				mode = pdfconv.ModeText
			default:
				fmt.Fprintf(os.Stderr, "Unknown mode: %s (valid: image, text)\n", os.Args[i+1])
				os.Exit(1)
			}
			break
		}
	}

	if pdfPath == "" {
		fmt.Fprintf(os.Stderr, "Usage: pdftoword-cli [--mode image|text] [--ocr] <pdf_file>\n")
		os.Exit(1)
	}

	modeLabel := "image"
	if mode == pdfconv.ModeText {
		modeLabel = "text"
	}
	fmt.Printf("Converting: %s (mode: %s)\n", pdfPath, modeLabel)

	docxPath, err := pdfconv.Convert(pdfPath, mode, func(pct float64) {
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