package pdfconv

import "testing"

func TestCleanOCRLine(t *testing.T) {
	tests := []struct {
		name  string
		input string
		want  string
	}{
		{
			name:  "CJK chars with hyphens",
			input: "- 为- 贯- 彻- 落- 实- 集- 团- 公- 司- 工- 作- 会- 议- 部- 署-",
			want:  "为贯彻落实集团公司工作会议部署",
		},
		{
			name:  "spaces between CJK chars",
			input: "为 贯 彻 落 实 集 团 公 司",
			want:  "为贯彻落实集团公司",
		},
		{
			name:  "plain CJK text (no change)",
			input: "集团公司工作会议",
			want:  "集团公司工作会议",
		},
		{
			name:  "single quote removal (model padding)",
			input: "'为'贯'彻'",
			want:  "为贯彻",
		},
		{
			name:  "Latin word hyphen preserved (no spaces)",
			input: "hello-world test",
			want:  "hello-world test",
		},
		{
			name:  "identifier A-1 preserved (no spaces)",
			input: "注: 参见附录A-1内容",
			want:  "注: 参见附录A-1内容",
		},
		// Cases from real OCR output
		{
			name:  "doc number with brackets",
			input: "公司办- 【- 2- 0- 2- 6- 】- 7- 号",
			want:  "公司办【2026】7号",
		},
		{
			name:  "date with year month day",
			input: "- 2- 0- 2- 6- 年- 9- .- 月- 2- 3- 日",
			want:  "2026年9.月23日",
		},
		{
			name:  "AI with hyphens",
			input: "A- I- 赋能比突破",
			want:  "AI赋能比突破",
		},
		{
			name:  "numbered bullet with full-width dot",
			input: "- 1- ．- 降本创效比贡献- ：- 精细",
			want:  "1．降本创效比贡献：精细",
		},
		{
			name:  "parenthesized number",
			input: "- （- 一- ）- 高度重视",
			want:  "（一）高度重视",
		},
		{
			name:  "mixed CJK and punctuation with hyphens",
			input: "为贯彻落实- ，- 深化公司- \"- 五化- \"",
			want:  "为贯彻落实，深化公司\"五化\"",
		},
		{
			name:  "page number",
			input: "- —- 1- —",
			want:  "—1—",
		},
		{
			name:  "person name",
			input: "组长- ：- 张三",
			want:  "组长：张三",
		},
		{
			name:  "trailing date (no CJK involved)",
			input: "- 3",
			want:  "3",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := cleanOCRLine(tt.input)
			if got != tt.want {
				t.Errorf("cleanOCRLine(%q) = %q, want %q", tt.input, got, tt.want)
			}
		})
	}
}