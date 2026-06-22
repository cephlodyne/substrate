package main

import (
	"bufio"
	"bytes"
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"os/exec"
	"strings"
)

type Message struct {
	OSV *struct {
		ID      string `json:"id"`
		Summary string `json:"summary"`
		Details string `json:"details"`
	} `json:"osv"`
	Finding *struct {
		OSV          string `json:"osv"`
		FixedVersion string `json:"fixed_version"`
		Trace        []struct {
			Module string `json:"module"`
		} `json:"trace"`
	} `json:"finding"`
}

type OSVReport struct {
	Summary string
	Details string
}

// ModFix aggregates all vulnerabilities for a single module
type ModFix struct {
	FixedVersion string
	VulnIDs      map[string]bool
}

func main() {
	showDesc := flag.Bool("desc", false, "Show detailed vulnerability descriptions")
	flag.Parse()

	fmt.Println("🔍 Running govulncheck... (this may take a moment)")
	cmd := exec.Command("govulncheck", "-json", "./...")
	out, _ := cmd.Output()

	reports := make(map[string]OSVReport)
	modulesToFix := make(map[string]*ModFix)

	decoder := json.NewDecoder(bytes.NewReader(out))
	for {
		var msg Message
		if err := decoder.Decode(&msg); err != nil {
			break
		}

		if msg.OSV != nil {
			reports[msg.OSV.ID] = OSVReport{
				Summary: msg.OSV.Summary,
				Details: msg.OSV.Details,
			}
		}

		if msg.Finding != nil && len(msg.Finding.Trace) > 0 {
			mod := msg.Finding.Trace[0].Module
			if mod != "" && mod != "stdlib" {
				if modulesToFix[mod] == nil {
					modulesToFix[mod] = &ModFix{
						FixedVersion: msg.Finding.FixedVersion,
						VulnIDs:      make(map[string]bool),
					}
				}
				// Ensure we capture a fixed version if the first finding lacked one
				if modulesToFix[mod].FixedVersion == "" && msg.Finding.FixedVersion != "" {
					modulesToFix[mod].FixedVersion = msg.Finding.FixedVersion
				}
				modulesToFix[mod].VulnIDs[msg.Finding.OSV] = true
			}
		}
	}

	if len(modulesToFix) == 0 {
		fmt.Println("✅ No third-party vulnerabilities found! Your fortress is secure.")
		return
	}

	var mods []string
	for m := range modulesToFix {
		mods = append(mods, m)
	}

	fmt.Printf("\n⚠️  Found %d vulnerable modules:\n", len(mods))
	fmt.Println(strings.Repeat("-", 80))

	for i, m := range mods {
		fix := modulesToFix[m]

		if !*showDesc {
			// Clean, aggregated output
			fmt.Printf("[%d] %s (Fixes %d vulnerabilities -> update to %s)\n", i+1, m, len(fix.VulnIDs), fix.FixedVersion)
		} else {
			// Verbose output with full CVE descriptions
			fmt.Printf("[%d] %s (Update to %s)\n", i+1, m, fix.FixedVersion)
			for osvID := range fix.VulnIDs {
				fmt.Printf("    ↳ %s\n", osvID)
				rep := reports[osvID]
				if rep.Summary != "" {
					fmt.Printf("      Summary: %s\n", rep.Summary)
				}
				if rep.Details != "" {
					desc := strings.ReplaceAll(rep.Details, "\n", "\n      ")
					fmt.Printf("      Details: %s\n", desc)
				}
				fmt.Println()
			}
		}
	}
	fmt.Println(strings.Repeat("-", 80))

	if !*showDesc {
		fmt.Println("💡 Tip: Run 'govulnfix -desc' to see full vulnerability descriptions.")
	}

	fmt.Print("\nEnter numbers to fix (e.g., '1,3'), 'all' to fix all, or 'q' to quit: ")
	reader := bufio.NewReader(os.Stdin)
	input, _ := reader.ReadString('\n')
	input = strings.TrimSpace(input)

	if input == "q" || input == "" {
		fmt.Println("Aborted.")
		return
	}

	var selectedMods []string
	if input == "all" {
		selectedMods = mods
	} else {
		parts := strings.Split(input, ",")
		for _, p := range parts {
			var idx int
			fmt.Sscanf(strings.TrimSpace(p), "%d", &idx)
			if idx > 0 && idx <= len(mods) {
				selectedMods = append(selectedMods, mods[idx-1])
			}
		}
	}

	if len(selectedMods) == 0 {
		fmt.Println("No valid selection made. Aborting.")
		return
	}

	fmt.Println("\n🚀 Upgrading selected modules...")
	args := []string{"get"}
	for _, m := range selectedMods {
		args = append(args, m+"@latest")
	}
	runCmd("go", args...)

	fmt.Println("\n🧹 Cleaning up tracking files (go mod tidy)...")
	runCmd("go", "mod", "tidy")

	fmt.Println("\n📦 Rebuilding vendor fortress (go mod vendor)...")
	runCmd("go", "mod", "vendor")

	fmt.Println("\n✅ All done! Vulnerabilities patched and vendored.")
}

func runCmd(name string, args ...string) {
	cmd := exec.Command(name, args...)
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	if err := cmd.Run(); err != nil {
		fmt.Printf("❌ Error running %s: %v\n", name, err)
	}
}
