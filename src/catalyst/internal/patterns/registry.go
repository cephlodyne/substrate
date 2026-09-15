package patterns

// Registry is the master map of all available architectures
var Registry = map[string]Pattern{
	"contracts": {
		ID: "contracts",
		Features: Features{
			IsContractsRepo: true,
		},
	},
	"api": {
		ID: "api",
		Features: Features{
			HasSvelteUI:   false,
			HasConnectRPC: true,
			HasIAPAuth:    false,
		},
	},
	"external_web": {
		ID: "external_web",
		Features: Features{
			HasSvelteUI:   true,
			HasConnectRPC: true,
			HasIAPAuth:    false,
		},
	},
	"internal_admin": {
		ID: "internal_admin",
		Features: Features{
			HasSvelteUI:   true,
			HasConnectRPC: true,
			HasIAPAuth:    true,
		},
	},
	"workspace": {
		ID: "workspace",
		Features: Features{
			IsWorkspace: true,
			HasPostgres: true,
		},
	},
	"external_web_solid": {
		ID: "external_web_solid",
		Features: Features{
			HasSolidUI:    true,
			HasConnectRPC: true,
			HasIAPAuth:    false,
		},
	},
	"internal_admin_solid": {
		ID: "internal_admin_solid",
		Features: Features{
			HasSolidUI:    true,
			HasConnectRPC: true,
			HasIAPAuth:    true,
		},
	},
}
