package migrations

import "embed"

// FS contains the SQL migrations compiled into the migration runner image.
//
//go:embed *.sql
var FS embed.FS
