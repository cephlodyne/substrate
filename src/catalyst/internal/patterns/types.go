// Package patterns defines the available architectures and template data structures.
package patterns

// Features act as toggles for the text/template logic inside .tmpl files
type Features struct {
	HasSvelteUI   bool
	HasConnectRPC bool
	HasIAPAuth    bool // Triggers kit/auth injection
}

// Components automatically deduces which folders to pull from the embedded FS
func (f Features) Components() []string {
	// The core backend is the baseline for all microservice patterns
	comps := []string{"backends/core"}

	if f.HasConnectRPC {
		comps = append(comps, "contracts/proto")
	}
	if f.HasSvelteUI {
		comps = append(comps, "frontends/svelte")
	}

	return comps
}

// Versions mirrors the centralized constants defined in main.go
// Versions mirrors the centralized constants defined in main.go and local environment
type Versions struct {
	GoVersion               string
	NodeVersion             string
	PnpmVersion             string
	ProtobufGenEsVersion    string
	VitePluginSvelteVersion string
	TSConfigSvelteVersion   string
	SvelteVersion           string
	SvelteCheckVersion      string
	SveltePreprocessVersion string
	TypeScriptVersion       string
	TSLibVersion            string
	ViteVersion             string
	ProtobufVersion         string
	ConnectWebVersion       string
	KitVersion              string
}

// TemplateData is the exact payload passed into tmpl.Execute()
type TemplateData struct {
	ProjectName string
	Features    Features
	Versions    Versions
}

// Pattern defines a specific architecture
type Pattern struct {
	ID       string
	Features Features
}
