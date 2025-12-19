# Keyva CLI

Command-line interface for managing environment variables. Works with the Keyva iOS/macOS app.

## Installation

```bash
curl -fsSL https://raw.githubusercontent.com/seracreativo/keyva-cli/main/install.sh | bash
```

That's it! The CLI installs to `/usr/local/bin/keyva`.

## Update

```bash
keyva update
```

The CLI checks GitHub for the latest version and updates itself.

## Quick Start

```bash
# Interactive mode (recommended for first time)
keyva

# Link current directory to a project
keyva link MyProject

# Export variables to .env
keyva pull prod
```

## Usage

### Interactive Mode

```bash
keyva
```

Launches a guided menu for all operations.

### Projects

```bash
keyva project list                    # List all projects
keyva project create "MyApp"          # Create a new project
keyva project delete "MyApp"          # Delete a project
```

### Environments

```bash
keyva env list --project "MyApp"              # List environments
keyva env create "staging" --project "MyApp"  # Create environment
keyva env delete "staging" --project "MyApp"  # Delete environment
```

### Variables

```bash
# List variables
keyva var list --project "MyApp" --env "dev"

# Set a variable
keyva var set API_URL "https://api.example.com" --project "MyApp" --env "dev"

# Set a secret (stored securely)
keyva var set API_KEY "secret123" --project "MyApp" --env "dev" --secret

# Get a variable value
keyva var get API_KEY --project "MyApp" --env "dev"
```

### Export

```bash
# Quick export (requires linked directory)
keyva pull prod                       # Exports to .env
keyva pull dev --secrets              # Include secrets

# Full export options
keyva export prod --format json       # Export as JSON
keyva export prod --format yaml       # Export as YAML
keyva export prod --format xcconfig   # Export for Xcode
keyva export prod --stdout            # Print to terminal
```

### Link Directory

```bash
# Link current directory to a project
keyva link MyProject

# Now you can use short commands
keyva pull prod                       # No need to specify project
keyva var list --env dev              # Project is inferred

# Show current link
keyva link show

# Remove link
keyva link remove
```

### Diagnostics

```bash
keyva diag           # Show status
keyva diag --verbose # Show technical details
```

## Sync with Keyva App

The CLI shares data with the Keyva iOS/macOS app via the shared App Group container. Changes appear instantly in both.

**Requirements:**
- macOS 14.0 or later
- Keyva app installed and opened at least once

## License

MIT
