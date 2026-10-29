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
	KitVersion = "v0.5.4"
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

// getNpmVersion dynamically queries the Golden NPM Store (or active npm config) for the latest vetted version
func getNpmVersion(pkg, registry string) string {
	args := []string{"view", pkg, "version"}
	if registry != "" && !strings.Contains(registry, "YOUR_PROJECT_ID") {
		args = append(args, "--registry="+registry)
	}
	cmd := exec.Command("npm", args...)
	var out bytes.Buffer
	cmd.Stdout = &out
	if err := cmd.Run(); err != nil {
		return "latest"
	}
	ver := strings.TrimSpace(out.String())
	if ver == "" {
		return "latest"
	}
	return ver
}

func getDynamicVersions(npmRegistry string) patterns.Versions {
	goVer := strings.TrimPrefix(getSystemVersion("go", "env", "GOVERSION"), "go")
	nodeVer := strings.TrimPrefix(getSystemVersion("node", "--version"), "v")
	pnpmVer := getSystemVersion("pnpm", "--version")

	return patterns.Versions{
		GoVersion:               goVer,
		NodeVersion:             nodeVer,
		PnpmVersion:             pnpmVer,
		ProtobufGenEsVersion:    getNpmVersion("@bufbuild/protoc-gen-es", npmRegistry),
		VitePluginSvelteVersion: getNpmVersion("@sveltejs/vite-plugin-svelte", npmRegistry),
		TSConfigSvelteVersion:   getNpmVersion("@tsconfig/svelte", npmRegistry),
		SvelteVersion:           getNpmVersion("svelte", npmRegistry),
		SvelteCheckVersion:      getNpmVersion("svelte-check", npmRegistry),
		SveltePreprocessVersion: getNpmVersion("svelte-preprocess", npmRegistry),
		SolidVersion:            getNpmVersion("solid-js", npmRegistry),
		VitePluginSolidVersion:  getNpmVersion("vite-plugin-solid", npmRegistry),
		TypeScriptVersion:       getNpmVersion("typescript", npmRegistry),
		TSLibVersion:            getNpmVersion("tslib", npmRegistry),
		ViteVersion:             getNpmVersion("vite", npmRegistry),
		ProtobufVersion:         getNpmVersion("@bufbuild/protobuf", npmRegistry),
		ConnectWebVersion:       getNpmVersion("@connectrpc/connect", npmRegistry),
		KitVersion:              KitVersion,
	}
}

func main() {
	patternFlag := flag.String("pattern", "", "The pattern to generate (e.g., external_web, api, internal_admin)")
	nameFlag := flag.String("name", "myapp", "The Go module name")
	dirFlag := flag.String("dir", ".", "Target directory")
	contractsFlag := flag.String("contracts", "../contracts", "Relative path to contracts repo")
	npmFlag := flag.String("npm-registry", "https://us-central1-npm.pkg.dev/YOUR_PROJECT_ID/golden-npm-store/", "The NPM registry URL")
	noRPCFlag := flag.Bool("no-rpc", false, "Disable ConnectRPC generation") // ADDED THIS
	flag.Parse()

	if *patternFlag == "" {
		log.Fatal("Error: --pattern is required")
	}

	npmRegistry := *npmFlag
	if !strings.HasSuffix(npmRegistry, "/") {
		npmRegistry += "/"
	}
	npmAuthPath := strings.TrimPrefix(npmRegistry, "https:")

	pattern, ok := patterns.Registry[*patternFlag]

	if !ok {
		log.Fatalf("fatal error: pattern '%s' not found", *patternFlag)
	}

	if *noRPCFlag {
		pattern.Features.HasConnectRPC = false
	}

	data := patterns.TemplateData{ProjectName: *nameFlag,
		Features:     pattern.Features,
		Versions:     getDynamicVersions(npmRegistry),
		ContractsDir: *contractsFlag,
		NPMRegistry:  npmRegistry,
		NPMAuthPath:  npmAuthPath,
	}

	fmt.Printf("Generating %s in %s...\n", pattern.ID, *dirFlag)

	if err := engine.Generate(*dirFlag, data, pattern, templatesFS); err != nil {
		log.Fatalf("Fatal error generating template: %v", err)
	}

	fmt.Println("Done!")
}
