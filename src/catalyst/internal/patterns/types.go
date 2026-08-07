// Package patterns defines the available architectures and template data structures.
package patterns

// Features act as toggles for the text/template logic inside .tmpl files
type Features struct {
	HasSvelteUI     bool
	HasConnectRPC   bool
	HasIAPAuth      bool // Triggers kit/auth injection
	IsContractsRepo bool
}

// Components automatically deduces which folders to pull from the embedded FS
func (f Features) Components() []string {
	// If it's a contracts repo, ONLY scaffold the contracts
	if f.IsContractsRepo {
		return []string{"contracts/proto"}
	}

	// Otherwise, scaffold the backend and frontend
	comps := []string{"backends/core"}
	if f.HasSvelteUI {
		comps = append(comps, "frontends/svelte")
	}
	return comps
}

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
	ProjectName  string
	Features     Features
	Versions     Versions
	ContractsDir string
}

// Pattern defines a specific architecture
type Pattern struct {
	ID       string
	Features Features
}
