package main

import (
	"fmt"
	"path/filepath"
	"time"

	"fyne.io/fyne/v2"
	"fyne.io/fyne/v2/app"
	"fyne.io/fyne/v2/container"
	"fyne.io/fyne/v2/dialog"
	"fyne.io/fyne/v2/layout"
	"fyne.io/fyne/v2/storage"
	"fyne.io/fyne/v2/widget"

	"pdftoword/internal/pdfconv"
)

func main() {
	a := app.NewWithID("com.pdf2docx.app")
	w := a.NewWindow("PDF2Word - PDF转Word工具")

	statusLabel := widget.NewLabel("请选择一个 PDF 文件")
	statusLabel.Alignment = fyne.TextAlignCenter

	progressBar := widget.NewProgressBar()
	progressBar.Hide()

	outputLabel := widget.NewLabel("")
	outputLabel.Alignment = fyne.TextAlignCenter
	outputLabel.Wrapping = fyne.TextWrapBreak

	content := container.NewVBox(
		layout.NewSpacer(),
		statusLabel,
		progressBar,
		outputLabel,
		layout.NewSpacer(),
	)

	w.SetContent(content)
	w.Resize(fyne.NewSize(800, 600))
	w.CenterOnScreen()

	go func() {
		time.Sleep(300 * time.Millisecond)
		showFileDialog(w, statusLabel, progressBar, outputLabel)
	}()

	w.ShowAndRun()
}

func showFileDialog(w fyne.Window, status *widget.Label, progress *widget.ProgressBar, output *widget.Label) {
	fd := dialog.NewFileOpen(func(reader fyne.URIReadCloser, err error) {
		if err != nil {
			dialog.ShowError(err, w)
			return
		}
		if reader == nil {
			status.SetText("未选择文件，窗口即将关闭")
			go func() {
				time.Sleep(2 * time.Second)
				w.Close()
			}()
			return
		}

		pdfPath := reader.URI().Path()
		reader.Close()

		base := filepath.Base(pdfPath)
		status.SetText(fmt.Sprintf("正在处理: %s", base))
		progress.Show()
		progress.SetValue(0)
		output.SetText("")
		w.SetTitle("PDF2Word - 转换中...")

		go func() {
			docxPath, convErr := pdfconv.Convert(pdfPath, func(pct float64) {
				progress.SetValue(pct)
			})

			if convErr != nil {
				dialog.ShowError(convErr, w)
				status.SetText("转换失败")
				progress.Hide()
				w.SetTitle("PDF2Word - PDF转Word工具")
				return
			}

			progress.SetValue(1.0)
			progress.Hide()
			status.SetText("转换完成！")
			output.SetText("输出: " + docxPath)
			w.SetTitle("PDF2Word - 完成")

			dialog.ShowInformation("转换完成",
				fmt.Sprintf("Word文档已生成:\n\n%s", docxPath), w)
		}()
	}, w)

	fd.SetFilter(storage.NewExtensionFileFilter([]string{".pdf"}))
	fd.Show()
	// Resize after Show so the internal dialog is already initialized.
	fd.Resize(fyne.NewSize(800, 600))
}