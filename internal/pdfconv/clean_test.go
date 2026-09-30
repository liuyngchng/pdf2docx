package pdfconv

import "testing"

func TestCleanOCRLine(t *testing.T) {
	tests := []struct {
		name  string
		input string
		want  string
	}{
		{
			name:  "artifact hyphens and spaces between CJK chars",
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
			name:  "Latin text with hyphen preserved",
			input: "hello-world test",
			want:  "hello-world test",
		},
		{
			name:  "mixed CJK and latin with legit hyphens",
			input: "注: 参见附录A-1内容",
			want:  "注: 参见附录A-1内容",
		},
		{
			name:  "leading dash before CJK",
			input: "- 第一章",
			want:  "第一章",
		},
		{
			name:  "trailing dash after CJK",
			input: "结束。 -",
			want:  "结束。 -",
		},
		{
			name:  "emoji and CJK mixed",
			input: "⚠️ 注意- 事项-",
			want:  "⚠️ 注意事项",
		},
		{
			name:  "empty after cleaning (no CJK chars, stripped to bare separator)",
			input: "' ' - '",
			want:  "-",
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