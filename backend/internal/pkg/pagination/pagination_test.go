package pagination

import "testing"

func TestNormalize(t *testing.T) {
	tests := []struct {
		name           string
		page           int
		perPage        int
		defaultPerPage int
		wantPage       int
		wantPerPage    int
	}{
		{
			name:           "keeps valid values",
			page:           3,
			perPage:        40,
			defaultPerPage: 20,
			wantPage:       3,
			wantPerPage:    40,
		},
		{
			name:           "clamps page to one",
			page:           0,
			perPage:        40,
			defaultPerPage: 20,
			wantPage:       1,
			wantPerPage:    40,
		},
		{
			name:           "uses endpoint default for missing per page",
			page:           2,
			perPage:        0,
			defaultPerPage: 30,
			wantPage:       2,
			wantPerPage:    30,
		},
		{
			name:           "caps oversized per page instead of resetting to default",
			page:           1,
			perPage:        500,
			defaultPerPage: 20,
			wantPage:       1,
			wantPerPage:    100,
		},
		{
			name:           "repairs invalid default",
			page:           1,
			perPage:        0,
			defaultPerPage: 999,
			wantPage:       1,
			wantPerPage:    20,
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			gotPage, gotPerPage := Normalize(tc.page, tc.perPage, tc.defaultPerPage)
			if gotPage != tc.wantPage || gotPerPage != tc.wantPerPage {
				t.Fatalf("Normalize(%d, %d, %d) = (%d, %d), want (%d, %d)",
					tc.page, tc.perPage, tc.defaultPerPage,
					gotPage, gotPerPage,
					tc.wantPage, tc.wantPerPage)
			}
		})
	}
}
