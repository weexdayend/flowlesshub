package cryptokit

import "testing"

func TestHeaderValidate(t *testing.T) {
	tests := []struct {
		name    string
		header  Header
		wantErr bool
	}{
		{
			name:   "valid envelope metadata",
			header: Header{Algorithm: AlgorithmAES256GCM, KeyID: "tenant-key-1", Version: CurrentHeaderVersion},
		},
		{
			name:    "missing key id",
			header:  Header{Algorithm: AlgorithmAES256GCM, Version: CurrentHeaderVersion},
			wantErr: true,
		},
		{
			name:    "unsupported algorithm",
			header:  Header{Algorithm: "unknown", KeyID: "tenant-key-1", Version: CurrentHeaderVersion},
			wantErr: true,
		},
		{
			name:    "unsupported version",
			header:  Header{Algorithm: AlgorithmAES256GCM, KeyID: "tenant-key-1", Version: CurrentHeaderVersion + 1},
			wantErr: true,
		},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			err := test.header.Validate()
			if (err != nil) != test.wantErr {
				t.Fatalf("Validate() error = %v, wantErr %v", err, test.wantErr)
			}
		})
	}
}
