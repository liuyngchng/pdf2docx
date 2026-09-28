// Command server is a headless HTTP server that converts PDF to DOCX.
//
// Build (static, no CGO):
//
//	CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -ldflags="-s -w" -o pdf2docx-server ./cmd/server/
package main

import (
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"os"
	"path/filepath"
	"time"

	"pdftoword/internal/pdfconv"
)

func main() {
	slogger := slog.New(slog.NewJSONHandler(os.Stderr, &slog.HandlerOptions{
		Level: slogLevel(),
	}))
	slog.SetDefault(slogger)

	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	mux := http.NewServeMux()
	mux.HandleFunc("POST /convert", handleConvert)
	mux.HandleFunc("GET /health", handleHealth)

	srv := &http.Server{
		Addr:         ":" + port,
		Handler:      withLogging(mux),
		ReadTimeout:  60 * time.Second,
		WriteTimeout: 300 * time.Second,
		IdleTimeout:  120 * time.Second,
	}

	slog.Info("server starting", "port", port)
	if err := srv.ListenAndServe(); err != nil {
		slog.Error("server fatal", "error", err)
		os.Exit(1)
	}
}

func slogLevel() slog.Level {
	switch os.Getenv("LOG_LEVEL") {
	case "debug":
		return slog.LevelDebug
	case "warn":
		return slog.LevelWarn
	case "error":
		return slog.LevelError
	default:
		return slog.LevelInfo
	}
}

// ── Middleware ────────────────────────────────────────────────────────────────

func withLogging(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		next.ServeHTTP(w, r)
		slog.Info("request",
			"method", r.Method,
			"path", r.URL.Path,
			"remote", r.RemoteAddr,
			"duration_ms", time.Since(start).Milliseconds(),
		)
	})
}

// ── Handlers ─────────────────────────────────────────────────────────────────

func handleHealth(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	w.Write([]byte(`{"status":"ok"}`))
}

func handleConvert(w http.ResponseWriter, r *http.Request) {
	// Limit upload to 64 MB.
	r.Body = http.MaxBytesReader(w, r.Body, 64<<20)
	if err := r.ParseMultipartForm(32 << 20); err != nil {
		slog.Warn("parse multipart failed", "error", err)
		http.Error(w, fmt.Sprintf("failed to parse form: %v", err), http.StatusBadRequest)
		return
	}
	defer r.MultipartForm.RemoveAll()

	file, header, err := r.FormFile("file")
	if err != nil {
		slog.Warn("missing file field", "error", err)
		http.Error(w, "missing file field", http.StatusBadRequest)
		return
	}
	defer file.Close()

	slog.Info("conversion started",
		"filename", header.Filename,
		"size_bytes", header.Size,
	)

	// Write upload to a temp file.
	pdfTmp, err := os.CreateTemp("", "pdf2docx-*.pdf")
	if err != nil {
		slog.Error("create temp file failed", "error", err)
		http.Error(w, "internal error", http.StatusInternalServerError)
		return
	}
	defer os.Remove(pdfTmp.Name())

	if _, err := io.Copy(pdfTmp, file); err != nil {
		pdfTmp.Close()
		slog.Error("write temp file failed", "error", err)
		http.Error(w, "internal error", http.StatusInternalServerError)
		return
	}
	pdfTmp.Close()

	// Convert.
	convStart := time.Now()
	docxPath, err := pdfconv.Convert(pdfTmp.Name(), func(pct float64) {
		// SSE progress could go here; for now we just log milestones.
	})
	convDuration := time.Since(convStart)

	if err != nil {
		slog.Error("conversion failed",
			"filename", header.Filename,
			"error", err,
			"duration_ms", convDuration.Milliseconds(),
		)
		http.Error(w, fmt.Sprintf("conversion failed: %v", err), http.StatusInternalServerError)
		return
	}
	defer os.Remove(docxPath)

	slog.Info("conversion done",
		"filename", header.Filename,
		"output", filepath.Base(docxPath),
		"duration_ms", convDuration.Milliseconds(),
	)

	// Stream the generated .docx back.
	w.Header().Set("Content-Type", "application/vnd.openxmlformats-officedocument.wordprocessingml.document")
	w.Header().Set("Content-Disposition", fmt.Sprintf(`attachment; filename="%s"`, docxFilename(header.Filename)))

	docxF, err := os.Open(docxPath)
	if err != nil {
		slog.Error("open result failed", "error", err)
		http.Error(w, "internal error", http.StatusInternalServerError)
		return
	}
	defer docxF.Close()

	if _, err := io.Copy(w, docxF); err != nil {
		slog.Warn("stream response interrupted", "error", err)
	}
}

func docxFilename(pdfName string) string {
	ext := filepath.Ext(pdfName)
	return pdfName[:len(pdfName)-len(ext)] + ".docx"
}