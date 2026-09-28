// Command cli is a headless PDF → Word converter used for testing and
// validating the pure-Go rendering pipeline without the Fyne GUI.
//
// Build (no CGO, no external deps):
//
//	CGO_ENABLED=0 go build -o pdftoword-cli ./cmd/cli/
package main

import (
	"fmt"
	"os"

	"pdftoword/internal/pdfconv"
)

func main() {
	if len(os.Args) < 2 {
		fmt.Fprintf(os.Stderr, "Usage: pdftoword-cli <pdf_file>\n")
		os.Exit(1)
	}

	pdfPath := os.Args[1]
	fmt.Printf("Converting: %s\n", pdfPath)

	docxPath, err := pdfconv.Convert(pdfPath, func(pct float64) {
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