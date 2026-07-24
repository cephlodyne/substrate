// Package engine provides the core template execution and file generation logic.
package engine

import (
	"embed"
	"io/fs"
	"os"
	"path/filepath"
	"strings"
	"text/template"

	"catalyst/internal/patterns"
)

// Generate walks the requested components and applies the templates
func Generate(targetDir string, data patterns.TemplateData, pattern patterns.Pattern, templatesFS embed.FS) error {
	for _, component := range pattern.Features.Components() {
		basePath := "templates/" + component

		err := fs.WalkDir(templatesFS, basePath, func(path string, d fs.DirEntry, err error) error {
			if err != nil || d.IsDir() {
				return err
			}

			if !strings.HasSuffix(path, ".tmpl") {
				return nil
			}

			relPath, err := filepath.Rel(basePath, path)
			if err != nil {
				return err
			}

			targetFilePath := strings.TrimSuffix(relPath, ".tmpl")
			fullTargetPath := filepath.Join(targetDir, targetFilePath)

			rawTmpl, err := templatesFS.ReadFile(path)
			if err != nil {
				return err
			}

			tmpl, err := template.New(targetFilePath).Parse(string(rawTmpl))
			if err != nil {
				return err
			}

			if err := os.MkdirAll(filepath.Dir(fullTargetPath), 0755); err != nil {
				return err
			}

			out, err := os.Create(fullTargetPath)
			if err != nil {
				return err
			}

			// Execute the template and explicitly check the file closure
			if err := tmpl.Execute(out, data); err != nil {
				_ = out.Close() // Safely ignore close error if execution already failed
				return err
			}

			return out.Close()
		})

		if err != nil {
			return err
		}
	}
	return nil
}
