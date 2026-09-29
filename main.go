package main

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"fyne.io/fyne/v2"
	"fyne.io/fyne/v2/app"
	"fyne.io/fyne/v2/container"
	"fyne.io/fyne/v2/dialog"
	"fyne.io/fyne/v2/lang"
	"fyne.io/fyne/v2/storage"
	"fyne.io/fyne/v2/theme"
	"fyne.io/fyne/v2/widget"

	"pdftoword/internal/pdfconv"
	"pdftoword/internal/ocr"
)

type pdfFile struct {
	path string
	name string
}

func main() {
	// 强制使用中文界面
	os.Setenv("LANG", "zh_CN.UTF-8")
	os.Setenv("LC_ALL", "zh_CN.UTF-8")
	lang.AddTranslationsForLocale([]byte(`{}`), fyne.Locale("zh"))

	a := app.NewWithID("com.pdf2docx.app")
	w := a.NewWindow("PDF2Word - PDF转Word工具")

	// --- data ---
	var files []pdfFile
	var converting bool

	// Declare widgets that reference each other in closures
	var fileList *widget.List
	var countLabel *widget.Label
	var convertBtn *widget.Button

	// --- file list ---
	fileList = widget.NewList(
		func() int { return len(files) },
		func() fyne.CanvasObject {
			label := widget.NewLabel("filename.pdf")
			label.Wrapping = fyne.TextWrapBreak
			removeBtn := widget.NewButtonWithIcon("", theme.DeleteIcon(), nil)
			return container.NewBorder(nil, nil, nil, removeBtn, label)
		},
		func(id widget.ListItemID, o fyne.CanvasObject) {
			row := o.(*fyne.Container)
			row.Objects[0].(*widget.Label).SetText(files[id].name)
			removeBtn := row.Objects[1].(*widget.Button)
			removeBtn.OnTapped = func() {
				files = append(files[:id], files[id+1:]...)
				fileList.Refresh()
				updateCountLabel(countLabel, len(files))
				updateConvertBtn(convertBtn, len(files), converting)
			}
		},
	)
	fileListScroll := container.NewScroll(fileList)
	fileListScroll.SetMinSize(fyne.NewSize(0, 200))

	// --- header / controls ---
	countLabel = widget.NewLabel("已选文件: 0 个")
	updateCountLabel(countLabel, 0)

	addBtn := widget.NewButtonWithIcon("添加 PDF 文件", theme.FileIcon(), func() {
		showFilePicker(w, &files, fileList, countLabel, convertBtn, converting)
	})

	clearBtn := widget.NewButtonWithIcon("清空列表", theme.DeleteIcon(), func() {
		files = nil
		fileList.Refresh()
		updateCountLabel(countLabel, 0)
		updateConvertBtn(convertBtn, 0, converting)
	})

	topBar := container.NewBorder(nil, nil, addBtn, clearBtn, countLabel)

	// --- bottom ---
	statusLabel := widget.NewLabel("请添加 PDF 文件")
	statusLabel.Alignment = fyne.TextAlignCenter

	progressBar := widget.NewProgressBar()
	progressBar.Hide()

	outputLabel := widget.NewLabel("")
	outputLabel.Wrapping = fyne.TextWrapBreak

	// --- OCR toggle ---
	baseDir, _ := os.Getwd()
	if exe, err := os.Executable(); err == nil {
		baseDir = filepath.Dir(exe)
	}
	modelsExist := ocr.CheckModels(baseDir)
	var ocrCheck *widget.Check
	var ocrHint *widget.Label

	ocrCheck = widget.NewCheck("生成 OCR 文字版 (.ocr.docx)", func(enabled bool) {
		// stored; read when conversion starts
	})
	if !modelsExist {
		ocrCheck.Disable()
		ocrHint = widget.NewLabel("（未检测到 OCR 模型目录 models/）")
	} else {
		ocrHint = widget.NewLabel("（已检测到 OCR 模型，可开启）")
	}

	ocrRow := container.NewHBox(ocrCheck, ocrHint)

	convertBtn = widget.NewButtonWithIcon("开始转换", theme.MediaPlayIcon(), func() {
		if len(files) == 0 {
			return
		}
		converting = true
		updateConvertBtn(convertBtn, len(files), converting)
		ocrCheck.Disable()

		progressBar.Show()
		progressBar.SetValue(0)
		outputLabel.SetText("")

		go func() {
			var results []string
			total := len(files)
			for i, f := range files {
				statusLabel.SetText(fmt.Sprintf("正在处理 (%d/%d): %s", i+1, total, f.name))
				w.SetTitle(fmt.Sprintf("PDF2Word - 转换中 (%d/%d)", i+1, total))

				baseProgress := float64(i) / float64(total)
				docxPath, err := pdfconv.Convert(f.path, ocrCheck.Checked, func(pct float64) {
					// each file contributes 1/total to overall progress
					overall := baseProgress + pct/float64(total)
					progressBar.SetValue(overall)
				})
				if err != nil {
					dialog.ShowError(fmt.Errorf("转换 %s 失败: %w", f.name, err), w)
					results = append(results, fmt.Sprintf("[失败] %s", f.name))
					progressBar.SetValue(float64(i+1) / float64(total))
				} else {
					results = append(results, fmt.Sprintf("[完成] %s -> %s", f.name, filepath.Base(docxPath)))
					progressBar.SetValue(float64(i+1) / float64(total))
				}
			}

			progressBar.Hide()
			statusLabel.SetText("全部转换完成！")
			outputLabel.SetText(strings.Join(results, "\n"))
			w.SetTitle("PDF2Word - 完成")

			dialog.ShowInformation("批量转换完成",
				fmt.Sprintf("共 %d 个文件:\n\n%s", total, strings.Join(results, "\n")), w)

			converting = false
			updateConvertBtn(convertBtn, len(files), converting)
			if modelsExist {
				ocrCheck.Enable()
			}
		}()
	})
	convertBtn.Disable()

	convertBar := container.NewVBox(
		statusLabel,
		progressBar,
		outputLabel,
		ocrRow,
		convertBtn,
	)

	// --- layout ---
	content := container.NewBorder(
		topBar,
		convertBar,
		nil, nil,
		fileListScroll,
	)

	w.SetContent(content)
	w.Resize(fyne.NewSize(800, 600))
	w.CenterOnScreen()
	w.ShowAndRun()
}

func showFilePicker(w fyne.Window, files *[]pdfFile, fileList *widget.List, countLabel *widget.Label, convertBtn *widget.Button, converting bool) {
	fd := dialog.NewFileOpen(func(reader fyne.URIReadCloser, err error) {
		if err != nil {
			dialog.ShowError(err, w)
			return
		}
		if reader == nil {
			return // cancelled
		}

		pdfPath := reader.URI().Path()
		reader.Close()

		// dedup
		for _, f := range *files {
			if f.path == pdfPath {
				dialog.ShowInformation("重复文件", "该文件已在列表中", w)
				return
			}
		}

		*files = append(*files, pdfFile{path: pdfPath, name: filepath.Base(pdfPath)})
		fileList.Refresh()
		updateCountLabel(countLabel, len(*files))
		updateConvertBtn(convertBtn, len(*files), converting)

		// Scroll to bottom
		fileList.ScrollToBottom()
	}, w)

	fd.SetFilter(storage.NewExtensionFileFilter([]string{".pdf"}))
	fd.Show()
	fd.Resize(fyne.NewSize(800, 600))
}

func updateCountLabel(l *widget.Label, n int) {
	l.SetText(fmt.Sprintf("已选文件: %d 个", n))
}

func updateConvertBtn(btn *widget.Button, n int, converting bool) {
	if converting {
		btn.Disable()
	} else if n == 0 {
		btn.Disable()
	} else {
		btn.Enable()
	}
}