package patterns

// Registry is the master map of all available architectures
var Registry = map[string]Pattern{
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
}
