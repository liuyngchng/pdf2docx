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

	"pdftoword/internal/ocr"
	"pdftoword/internal/pdfconv"
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

	// 自定义主题：加大文件选择对话框中"取消"和"打开"按钮之间的间距
	customTheme := &spacedTheme{Theme: theme.DefaultTheme()}

	a := app.NewWithID("com.pdf2docx.app")
	a.Settings().SetTheme(customTheme)
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
				fyne.Do(func() {
					statusLabel.SetText(fmt.Sprintf("正在处理 (%d/%d): %s", i+1, total, f.name))
					w.SetTitle(fmt.Sprintf("PDF2Word - 转换中 (%d/%d)", i+1, total))
				})

				baseProgress := float64(i) / float64(total)
				mode := pdfconv.ModeImage
				if ocrCheck.Checked {
					mode = pdfconv.ModeText
				}
				_, err := pdfconv.Convert(f.path, mode, func(pct float64) {
					// each file contributes 1/total to overall progress
					overall := baseProgress + pct/float64(total)
					fyne.Do(func() {
						progressBar.SetValue(overall)
					})
				})
				fyne.Do(func() {
					if err != nil {
						dialog.ShowError(fmt.Errorf("转换 %s 失败: %w", f.name, err), w)
						results = append(results, fmt.Sprintf("[失败] %s", f.name))
						progressBar.SetValue(float64(i+1) / float64(total))
					} else {
						results = append(results, "✓ "+truncateName(f.name, 30))
						progressBar.SetValue(float64(i+1) / float64(total))
					}
				})
			}

			fyne.Do(func() {
				progressBar.Hide()
				statusLabel.SetText("全部转换完成！")
				outputLabel.SetText(strings.Join(results, "\n"))
				w.SetTitle("PDF2Word - 完成")

				msgLabel := widget.NewLabel(fmt.Sprintf("共 %d 个文件:\n\n%s", total, strings.Join(results, "\n")))
				msgLabel.Alignment = fyne.TextAlignLeading
				d := dialog.NewCustom("批量转换完成", "确定", msgLabel, w)
				d.Show()

				converting = false
				updateConvertBtn(convertBtn, len(files), converting)
				if modelsExist {
					ocrCheck.Enable()
				}
			})
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

		// OnClosed may fire from a non-UI goroutine; ensure widget
		// updates happen on the Fyne canvas goroutine.
		fyne.Do(func() {
			fileList.Refresh()
			updateCountLabel(countLabel, len(*files))
			updateConvertBtn(convertBtn, len(*files), converting)

			// Scroll to bottom
			fileList.ScrollToBottom()
		})
	}, w)

	fd.SetFilter(storage.NewExtensionFileFilter([]string{".pdf"}))
	fd.Show()
	fd.Resize(fyne.NewSize(800, 600))
}

func truncateName(name string, maxChars int) string {
	ext := filepath.Ext(name)
	base := strings.TrimSuffix(name, ext)

	runes := []rune(base)
	extRunes := []rune(ext)

	if len(runes)+len(extRunes) <= maxChars {
		return name
	}

	// Reserve space for "..." and extension
	keep := maxChars - 3 - len(extRunes)
	if keep < 1 {
		keep = 1
	}
	return string(runes[:keep]) + "..." + ext
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

// spacedTheme 在默认主题基础上，加大元素之间的 Padding 间距。
// Fyne 的文件选择对话框用 GridWithRows 排布"取消"和"打开"按钮，
// 按钮间距取自 theme.Padding()，覆盖该值即可加大两个按钮之间的距离。
type spacedTheme struct {
	fyne.Theme
}

func (t *spacedTheme) Size(name fyne.ThemeSizeName) float32 {
	if name == theme.SizeNamePadding {
		return 16 // 默认 4，加大到 16
	}
	return t.Theme.Size(name)
}
