#!/bin/bash
set -e

# Configuration
REPO_DIR="$HOME/termux-repo"
PACKAGES_DIR="$REPO_DIR/dists/stable/main/binary-aarch64"
ARCH="aarch64"

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

error_exit() {
    log "ERROR: $1"
    exit 1
}

log "Starting Termux repository build for version 0.119.0-beta.3"

# Create directory structure
log "Creating directory structure..."
mkdir -p "$PACKAGES_DIR"
mkdir -p "$REPO_DIR/dists/stable/main"

# Install required tools
log "Installing required tools..."
sudo apt-get update -qq || error_exit "Failed to update apt"
sudo apt-get install -y wget curl gnupg dpkg-dev apt-utils xz-utils gzip || error_exit "Failed to install required tools"

# Download Termux Packages index
log "Fetching Termux package index..."
TEMP_DIR=$(mktemp -d)
cd "$TEMP_DIR"

INDEX_DOWNLOADED=false
PACKAGES_FILE=""

# Try different URLs and compression formats
declare -a INDEX_URLS=(
    "https://packages-cf.termux.dev/apt/termux-main-21/dists/stable/main/binary-$ARCH/Packages.xz"
    "https://packages-cf.termux.dev/apt/termux-main-21/dists/stable/main/binary-$ARCH/Packages.gz"
    "https://packages-cf.termux.dev/apt/termux-main-21/dists/stable/main/binary-$ARCH/Packages"
    "https://packages.termux.dev/apt/termux-main-21/dists/stable/main/binary-$ARCH/Packages.xz"
    "https://packages.termux.dev/apt/termux-main-21/dists/stable/main/binary-$ARCH/Packages.gz"
)

for url in "${INDEX_URLS[@]}"; do
    log "Trying $url..."
    filename=$(basename "$url")
    
    if wget -q --timeout=10 --tries=2 "$url" -O "$filename" 2>/dev/null; then
        # Decompress if needed
        if [[ "$filename" == *.xz ]]; then
            if xz -d "$filename" 2>/dev/null; then
                PACKAGES_FILE="Packages"
                INDEX_DOWNLOADED=true
                log "✓ Successfully downloaded and decompressed index"
                break
            fi
        elif [[ "$filename" == *.gz ]]; then
            if gunzip "$filename" 2>/dev/null; then
                PACKAGES_FILE="Packages"
                INDEX_DOWNLOADED=true
                log "✓ Successfully downloaded and decompressed index"
                break
            fi
        else
            PACKAGES_FILE="$filename"
            INDEX_DOWNLOADED=true
            log "✓ Successfully downloaded index"
            break
        fi
    fi
done

if [ "$INDEX_DOWNLOADED" = false ]; then
    log "WARNING: Could not download Packages index from any source"
    log "Attempting direct package download method..."
    
    cd "$PACKAGES_DIR"
    
    # Try to download packages directly using multiple URL patterns
    declare -a BASE_URLS=(
        "https://packages-cf.termux.dev/apt/termux-main-21/pool/main"
        "https://packages.termux.dev/apt/termux-main-21/pool/main"
        "https://packages-cf.termux.dev/apt/termux-main/pool/main"
    )
    
    # Core packages needed
    declare -a CORE_PACKAGES=(
        "wget"
        "tar"
        "libandroid-support"
        "libc++"
        "openssl"
        "ca-certificates"
        "zlib"
        "libuuid"
        "pcre2"
        "libidn2"
        "libunistring"
        "libnettle"
        "libgmp"
        "libgnutls"
        "libcrypt"
    )
    
    DOWNLOADED=0
    FAILED=0
    
    for pkg in "${CORE_PACKAGES[@]}"; do
        log "Attempting to download $pkg..."
        pkg_downloaded=false
        
        for base_url in "${BASE_URLS[@]}"; do
            # Try pool structure: pool/main/p/package/
            first_letter="${pkg:0:1}"
            
            # Get list of available versions
            pkg_url="$base_url/$first_letter/$pkg/"
            
            # Try to find any .deb file for this package
            if wget -q --spider "$pkg_url" 2>/dev/null; then
                # Try to download the directory listing and find .deb files
                listing=$(wget -q -O- "$pkg_url" 2>/dev/null || echo "")
                
                if [ -n "$listing" ]; then
                    # Extract .deb filenames from HTML
                    deb_file=$(echo "$listing" | grep -oP "${pkg}_[^\"]+_($ARCH|all)\.deb" | head -1)
                    
                    if [ -n "$deb_file" ]; then
                        full_url="$pkg_url$deb_file"
                        if wget -q --timeout=15 "$full_url" 2>/dev/null; then
                            # Verify it's a valid .deb file
                            if file "$deb_file" | grep -q "Debian binary package"; then
                                log "✓ Downloaded $pkg ($deb_file)"
                                ((DOWNLOADED++))
                                pkg_downloaded=true
                                break
                            else
                                log "✗ Downloaded file is not a valid .deb, removing..."
                                rm -f "$deb_file"
                            fi
                        fi
                    fi
                fi
            fi
        done
        
        if [ "$pkg_downloaded" = false ]; then
            log "✗ Failed to download $pkg from any source"
            ((FAILED++))
        fi
    done
    
    rm -rf "$TEMP_DIR"
    
    log "Summary: Downloaded $DOWNLOADED packages, Failed $FAILED packages"
    
    if [ $DOWNLOADED -eq 0 ]; then
        error_exit "No packages were downloaded. Cannot create repository."
    fi
    
else
    # Index downloaded successfully, parse and download packages
    log "Parsing package index..."
    
    # Function to extract package info
    get_package_info() {
        local pkg_name="$1"
        awk -v pkg="$pkg_name" '
            /^Package:/ { if ($2 == pkg) found=1; else found=0 }
            found && /^Filename:/ { print $2; exit }
        ' "$PACKAGES_FILE"
    }
    
    # List of packages to download
    declare -a PACKAGES=(
        "wget"
        "tar"
        "libandroid-support"
        "libc++"
        "openssl"
        "ca-certificates"
        "zlib"
        "libuuid"
        "pcre2"
        "libidn2"
        "libunistring"
        "libnettle"
        "libgmp"
        "libgnutls"
        "libcrypt"
    )
    
    cd "$PACKAGES_DIR"
    DOWNLOADED=0
    FAILED=0
    
    for pkg in "${PACKAGES[@]}"; do
        log "Processing $pkg..."
        FILENAME=$(get_package_info "$pkg")
        
        if [ -n "$FILENAME" ]; then
            # Try multiple base URLs
            pkg_downloaded=false
            
            for base in "https://packages-cf.termux.dev/apt/termux-main-21" "https://packages.termux.dev/apt/termux-main-21"; do
                FULL_URL="$base/$FILENAME"
                
                if wget -q --timeout=15 --show-progress "$FULL_URL" 2>/dev/null; then
                    deb_file=$(basename "$FILENAME")
                    
                    # Verify it's a valid .deb
                    if file "$deb_file" | grep -q "Debian binary package"; then
                        log "✓ Downloaded $pkg"
                        ((DOWNLOADED++))
                        pkg_downloaded=true
                        break
                    else
                        log "✗ Invalid .deb file, removing..."
                        rm -f "$deb_file"
                    fi
                fi
            done
            
            if [ "$pkg_downloaded" = false ]; then
                log "✗ Failed to download $pkg"
                ((FAILED++))
            fi
        else
            log "✗ Package $pkg not found in index"
            ((FAILED++))
        fi
    done
    
    rm -rf "$TEMP_DIR"
    
    log "Summary: Downloaded $DOWNLOADED packages, Failed $FAILED packages"
    
    if [ $DOWNLOADED -eq 0 ]; then
        error_exit "No packages were downloaded. Cannot create repository."
    fi
fi

# Generate Packages file
log "Generating repository metadata..."
cd "$REPO_DIR"

if ! dpkg-scanpackages --arch "$ARCH" "dists/stable/main/binary-$ARCH" /dev/null > "dists/stable/main/binary-$ARCH/Packages" 2>/dev/null; then
    error_exit "Failed to generate Packages file"
fi

gzip -9c "dists/stable/main/binary-$ARCH/Packages" > "dists/stable/main/binary-$ARCH/Packages.gz"
xz -9c "dists/stable/main/binary-$ARCH/Packages" > "dists/stable/main/binary-$ARCH/Packages.xz"

# Create Release file
log "Creating Release file..."
cat > "$REPO_DIR/dists/stable/Release" <<EOF
Origin: Termux
Label: Termux
Suite: stable
Codename: stable
Version: 0.119.0-beta.3
Architectures: all aarch64 arm i686
Components: main
Description: Minimal Termux repository with wget and tar
Date: $(date -Ru)
EOF

cd "$REPO_DIR/dists/stable"
echo "MD5Sum:" >> Release
find main -type f | while read file; do
    echo " $(md5sum "$file" | cut -d' ' -f1) $(stat -c%s "$file") $file" >> Release
done
echo "SHA256:" >> Release
find main -type f | while read file; do
    echo " $(sha256sum "$file" | cut -d' ' -f1) $(stat -c%s "$file") $file" >> Release
done

# GPG setup
log "Setting up GPG key..."
GPG_KEY_ID="termux-repo@localhost"

if ! gpg --list-keys "$GPG_KEY_ID" &>/dev/null; then
    log "Generating new GPG key..."
    cat > /tmp/gpg-batch <<EOF
%no-protection
Key-Type: RSA
Key-Length: 4096
Name-Real: Termux Repository
Name-Email: termux-repo@localhost
Expire-Date: 0
EOF
    gpg --batch --gen-key /tmp/gpg-batch
    rm /tmp/gpg-batch
fi

log "Signing Release file..."
gpg --default-key "$GPG_KEY_ID" -abs -o Release.gpg Release
gpg --default-key "$GPG_KEY_ID" --clearsign -o InRelease Release
gpg --armor --export "$GPG_KEY_ID" > "$REPO_DIR/public.key"

# Create README
FINAL_COUNT=$(ls -1 "$PACKAGES_DIR"/*.deb 2>/dev/null | wc -l)

cat > "$REPO_DIR/README.md" <<EOF
# Minimal Termux Repository

This repository contains wget and tar packages with dependencies for Termux 0.119.0-beta.3.

## Setup Instructions

1. Copy the repository to your device
2. Add the repository to Termux:

\`\`\`bash
# Import GPG key
cat public.key | apt-key add -

# Add repository
echo "deb [trusted=yes] file:///path/to/termux-repo stable main" > \$PREFIX/etc/apt/sources.list.d/local-repo.list

# Update and install
apt update
apt install wget tar
\`\`\`

## Repository Contents

- Total packages: $FINAL_COUNT
- Architecture: $ARCH
- Generated: $(date)

## Package List

$(ls -1 "$PACKAGES_DIR"/*.deb 2>/dev/null | xargs -n1 basename | sed 's/^/- /')

EOF

log "=========================================="
log "Repository build complete!"
log "=========================================="
log "Repository location: $REPO_DIR"
log "Package count: $FINAL_COUNT"
log "Public key: $REPO_DIR/public.key"
log "=========================================="

exit 0
