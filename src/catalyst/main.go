package main

import (
	"bytes"
	"embed"
	"flag"
	"fmt"
	"log"
	"os/exec"
	"strings"

	"catalyst/internal/engine"
	"catalyst/internal/patterns"
)

//go:embed templates
var templatesFS embed.FS

// Master versions matching the zero-trust base-images strictly
const (
	ProtobufGenEsVersion    = "2.12.1"
	VitePluginSvelteVersion = "7.2.0"
	TSConfigSvelteVersion   = "5.0.8"
	SvelteVersion           = "5.56.5"
	SvelteCheckVersion      = "4.7.3"
	SveltePreprocessVersion = "6.0.5"
	TypeScriptVersion       = "7.0.2"
	TSLibVersion            = "2.8.1"
	ViteVersion             = "8.1.4"
	ProtobufVersion         = "2.12.1"
	ConnectWebVersion       = "2.1.2"
	KitVersion              = "v0.2.0"
)

// getSystemVersion runs a command and returns the trimmed output
func getSystemVersion(name string, args ...string) string {
	cmd := exec.Command(name, args...)
	var out bytes.Buffer
	cmd.Stdout = &out
	if err := cmd.Run(); err != nil {
		log.Fatalf("failed to get system version for %s: %v", name, err)
	}
	return strings.TrimSpace(out.String())
}

func getDynamicVersions() patterns.Versions {
	goVer := strings.TrimPrefix(getSystemVersion("go", "env", "GOVERSION"), "go")
	nodeVer := strings.TrimPrefix(getSystemVersion("node", "--version"), "v")
	pnpmVer := getSystemVersion("pnpm", "--version")

	return patterns.Versions{
		GoVersion:               goVer,
		NodeVersion:             nodeVer,
		PnpmVersion:             pnpmVer,
		ProtobufGenEsVersion:    ProtobufGenEsVersion,
		VitePluginSvelteVersion: VitePluginSvelteVersion,
		TSConfigSvelteVersion:   TSConfigSvelteVersion,
		SvelteVersion:           SvelteVersion,
		SvelteCheckVersion:      SvelteCheckVersion,
		SveltePreprocessVersion: SveltePreprocessVersion,
		TypeScriptVersion:       TypeScriptVersion,
		TSLibVersion:            TSLibVersion,
		ViteVersion:             ViteVersion,
		ProtobufVersion:         ProtobufVersion,
		ConnectWebVersion:       ConnectWebVersion,
		KitVersion:              KitVersion,
	}
}

func main() {
	patternFlag := flag.String("pattern", "", "The pattern to generate (e.g., external_web, api, internal_admin)")
	nameFlag := flag.String("name", "myapp", "The Go module name")
	dirFlag := flag.String("dir", "./output", "Target directory")
	flag.Parse()

	if *patternFlag == "" {
		log.Fatal("Error: --pattern is required")
	}

	pattern, ok := patterns.Registry[*patternFlag]
	if !ok {
		log.Fatalf("Error: unknown pattern '%s'", *patternFlag)
	}

	data := patterns.TemplateData{
		ProjectName: *nameFlag,
		Features:    pattern.Features,
		Versions:    getDynamicVersions(),
	}

	fmt.Printf("Generating %s in %s...\n", pattern.ID, *dirFlag)

	if err := engine.Generate(*dirFlag, data, pattern, templatesFS); err != nil {
		log.Fatalf("Fatal error generating template: %v", err)
	}

	fmt.Println("Done!")
}
