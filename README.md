# Keyva CLI

Command-line interface for managing environment variables. Works with the Keyva iOS/macOS app.

## Installation

### Homebrew (Recommended)

```bash
brew tap seracreativo/keyva
brew install keyva
```

### Manual Installation

```bash
git clone https://github.com/seracreativo/keyva-cli.git
cd keyva-cli
swift build -c release
cp .build/release/keyva /usr/local/bin/
```

## Usage

### Projects

```bash
# List all projects
keyva project list

# Create a new project
keyva project create "MyApp"

# Delete a project
keyva project delete "MyApp"
```

### Environments

```bash
# List environments in a project
keyva env list --project "MyApp"

# Create a new environment
keyva env create "staging" --project "MyApp"

# Delete an environment
keyva env delete "staging" --project "MyApp"
```

### Variables

```bash
# List variables in an environment
keyva var list --project "MyApp" --env "dev"

# Set a variable
keyva var set API_URL "https://api.example.com" --project "MyApp" --env "dev"

# Set a secret variable (stored in Keychain)
keyva var set API_KEY "secret123" --project "MyApp" --env "dev" --secret

# Get a variable value
keyva var get API_KEY --project "MyApp" --env "dev"

# Delete a variable
keyva var delete API_KEY --project "MyApp" --env "dev"
```

### Export

```bash
# Export to stdout
keyva export --project "MyApp" --env "prod" --format env

# Export to file
keyva export --project "MyApp" --env "prod" --format env -o .env

# Export formats: env, json, yaml, xcconfig
keyva export --project "MyApp" --env "prod" --format xcconfig -o Config.xcconfig

# Include secrets in export
keyva export --project "MyApp" --env "prod" --format env --include-secrets
```

## Sync with Keyva App

The CLI shares data with the Keyva iOS/macOS app via iCloud. Changes made in the CLI appear in the app and vice versa.

**Requirements:**
- macOS 14.0 or later
- Signed in to iCloud with the same Apple ID as the Keyva app

## License

MIT
