#!/bin/bash
set -e

# Configuration
REPO_DIR="$HOME/termux-repo"
PACKAGES_DIR="$REPO_DIR/dists/stable/main/binary-aarch64"
TERMUX_PACKAGES_REPO="https://packages-cf.termux.dev/apt/termux-main"
ARCH="aarch64"

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

log "Starting Termux repository build for version 0.119.0-beta.3"

# Create directory structure
log "Creating directory structure..."
mkdir -p "$PACKAGES_DIR"
mkdir -p "$REPO_DIR/dists/stable/main/binary-all"
mkdir -p "$REPO_DIR/dists/stable/main/binary-arm"
mkdir -p "$REPO_DIR/dists/stable/main/binary-i686"

# Install required tools
log "Installing required tools..."
sudo apt-get update
sudo apt-get install -y wget curl gnupg dpkg-dev apt-utils

# Download packages and dependencies
log "Downloading wget, tar and their dependencies..."
cd "$PACKAGES_DIR"

# List of packages to download (wget, tar and common dependencies)
PACKAGES=(
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
    "libiconv"
    "libacl"
    "libattr"
)

# Download each package
for pkg in "${PACKAGES[@]}"; do
    log "Downloading $pkg..."
    # Try to download the latest version
    wget -q --show-progress -r -l1 -np -nd -A "${pkg}_*.deb" "$TERMUX_PACKAGES_REPO/" || log "Warning: Could not download $pkg"
done

# Generate Packages file
log "Generating Packages file..."
cd "$REPO_DIR"
dpkg-scanpackages --arch "$ARCH" "dists/stable/main/binary-$ARCH" /dev/null > "dists/stable/main/binary-$ARCH/Packages"

# Compress Packages file
log "Compressing Packages file..."
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

# Generate checksums for Release file
log "Generating checksums..."
cd "$REPO_DIR/dists/stable"

# MD5Sum
echo "MD5Sum:" >> Release
find main -type f | while read file; do
    echo " $(md5sum "$file" | cut -d' ' -f1) $(stat -c%s "$file") $file" >> Release
done

# SHA256
echo "SHA256:" >> Release
find main -type f | while read file; do
    echo " $(sha256sum "$file" | cut -d' ' -f1) $(stat -c%s "$file") $file" >> Release
done

# Generate GPG key if it doesn't exist
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

# Sign Release file
log "Signing Release file..."
gpg --default-key "$GPG_KEY_ID" -abs -o Release.gpg Release
gpg --default-key "$GPG_KEY_ID" --clearsign -o InRelease Release

# Export public key
log "Exporting public key..."
gpg --armor --export "$GPG_KEY_ID" > "$REPO_DIR/public.key"

# Create repository info file
log "Creating repository info..."
cat > "$REPO_DIR/README.md" <<EOF
# Minimal Termux Repository

This repository contains wget and tar packages for Termux 0.119.0-beta.3.

## Setup Instructions

1. Copy the repository to your device
2. Add the repository to Termux:

\`\`\`bash
# Import GPG key
cat public.key | apt-key add -

# Add repository (adjust path as needed)
echo "deb [trusted=yes] file:///path/to/termux-repo stable main" > \$PREFIX/etc/apt/sources.list.d/local-repo.list

# Update and install
apt update
apt install wget tar
\`\`\`

## Packages Included

- wget
- tar
- All required dependencies

Generated: $(date)
EOF

log "Repository build complete!"
log "Repository location: $REPO_DIR"
log "Public key: $REPO_DIR/public.key"
log ""
log "Package count: $(ls -1 $PACKAGES_DIR/*.deb 2>/dev/null | wc -l)"
log ""
log "To use this repository, copy it to your device and follow the instructions in README.md"
