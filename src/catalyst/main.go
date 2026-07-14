package main

import (
	"embed"
	"flag"
	"fmt"
	"hash/fnv"
	"io/fs"
	"os"
	"path/filepath"
	"strings"
)

// ==========================================
// MASTER VERSIONS (V2 Modernized)
// ==========================================
const (
	MasterGoVersion         = "1.26.4"
	MasterSvelteVersion     = "5.38.10"
	MasterViteVersion       = "7.1.5"
	MasterProtobufVersion   = "2.2.3"
	MasterConnectWebVersion = "2.0.0"
	MasterConnectGoVersion  = "1.16.1"
	MasterKitVersion        = "0.1.0"
)

//go:embed templates
var templatesFS embed.FS

func generatePort(appName string) string {
	h := fnv.New32a()
	h.Write([]byte(appName))
	port := 8000 + (h.Sum32() % 1000)
	return fmt.Sprintf("%d", port)
}

func main() {
	initCmd := flag.NewFlagSet("init", flag.ExitOnError)
	initType := initCmd.String("type", "", "Type ('external-web', 'internal-web', 'internal-api', 'contracts')")
	initUI := initCmd.String("ui", "svelte", "Frontend framework ('svelte', 'react', 'vue')")

	if len(os.Args) < 2 {
		fmt.Println("Usage: ceph init --type=<type> <module-name>")
		os.Exit(1)
	}

	if os.Args[1] == "init" {
		initCmd.Parse(os.Args[2:])
		if initCmd.NArg() < 1 {
			fmt.Println("Error: Must specify a module name (e.g., cws-external).")
			os.Exit(1)
		}

		moduleName := initCmd.Arg(0)
		appPort := generatePort(moduleName)

		switch *initType {
		case "external-web", "internal-web":
			fmt.Printf("Scaffolding %s with %s UI for '%s' into current directory...\n", *initType, *initUI, moduleName)

			backendPath := fmt.Sprintf("templates/backends/%s", *initType)
			scaffoldTemplate(backendPath, ".", moduleName, appPort)

			frontendPath := fmt.Sprintf("templates/frontends/%s", *initUI)
			scaffoldTemplate(frontendPath, "./frontend", moduleName, appPort)

			fmt.Println("Done. Run 'make dev' to start.")

		case "internal-api":
			fmt.Printf("Scaffolding headless %s for '%s' into current directory...\n", *initType, moduleName)
			backendPath := fmt.Sprintf("templates/backends/%s", *initType)
			scaffoldTemplate(backendPath, ".", moduleName, appPort)
			fmt.Println("Done.")

		case "contracts":
			fmt.Printf("Scaffolding Contracts Repo '%s' into current directory...\n", moduleName)
			scaffoldTemplate("templates/contracts", ".", moduleName, "")
			fmt.Println("Done.")

		default:
			fmt.Println("Error: Unknown or missing --type.")
			os.Exit(1)
		}
	}
}

func scaffoldTemplate(templatePath string, targetDir string, moduleName string, appPort string) {
	err := fs.WalkDir(templatesFS, templatePath, func(path string, d fs.DirEntry, err error) error {
		if err != nil {
			return err
		}

		relPath, _ := filepath.Rel(templatePath, path)
		destPath := filepath.Join(targetDir, strings.TrimSuffix(relPath, ".tmpl"))

		if d.IsDir() {
			return os.MkdirAll(destPath, 0755)
		}

		data, err := templatesFS.ReadFile(path)
		if err != nil {
			return err
		}

		processed := string(data)
		processed = strings.ReplaceAll(processed, "CEPHLODYNE_APP_NAME", moduleName)
		processed = strings.ReplaceAll(processed, "{{API_PORT}}", appPort)
		processed = strings.ReplaceAll(processed, "{{GO_VERSION}}", MasterGoVersion)
		processed = strings.ReplaceAll(processed, "{{SVELTE_VERSION}}", MasterSvelteVersion)
		processed = strings.ReplaceAll(processed, "{{VITE_VERSION}}", MasterViteVersion)
		processed = strings.ReplaceAll(processed, "{{CONNECT_GO_VERSION}}", MasterConnectGoVersion)
		processed = strings.ReplaceAll(processed, "{{CONNECT_WEB_VERSION}}", MasterConnectWebVersion)
		processed = strings.ReplaceAll(processed, "{{PROTOBUF_VERSION}}", MasterProtobufVersion)
		processed = strings.ReplaceAll(processed, "{{KIT_VERSION}}", MasterKitVersion)

		return os.WriteFile(destPath, []byte(processed), 0644)
	})

	if err != nil {
		fmt.Printf("Error scaffolding template %s: %v\n", templatePath, err)
		os.Exit(1)
	}
}
