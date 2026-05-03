#!/bin/bash
set -e

# Configuration
REPO_DIR="$(pwd)/termux-custom-repo"
ARCH="aarch64"
DIST="stable"
COMP="main"
TERMUX_MIRROR="https://packages.termux.dev/apt/termux-main"
GPG_EMAIL="termux-repo@localhost"
GPG_PASS="termux123"

# List of packages to include (wget, tar, and their common dependencies for aarch64)
# Note: Dependency chains in Termux can update. This covers the standard required libraries.
PACKAGES=(
    "wget"
    "tar"
    "openssl"
    "libidn2"
    "libunistring"
    "pcre2"
    "zlib"
    "ca-certificates"
    "libiconv"
    "xz-utils"
    "liblzma"
    "libandroid-support"
    "resolv-conf"
)

log() {
    echo -e "\e[1;32m[*]\e[0m $1"
}

log "Installing required host packages on Ubuntu 22.04..."
sudo apt-get update -y
sudo apt-get install -y curl apt-utils dpkg-dev gnupg

log "Setting up repository directory structure..."
POOL_DIR="$REPO_DIR/pool/$COMP"
DISTS_DIR="$REPO_DIR/dists/$DIST/$COMP/binary-$ARCH"

mkdir -p "$POOL_DIR"
mkdir -p "$DISTS_DIR"

log "Downloading official Termux Packages list to resolve package paths..."
curl -sL "$TERMUX_MIRROR/dists/stable/main/binary-$ARCH/Packages" -o /tmp/termux_Packages

log "Downloading packages and dependencies..."
for pkg in "${PACKAGES[@]}"; do
    # Extract the file path for the package from the Packages file
    PKG_PATH=$(awk -v pkg="Package: $pkg\$" '$0 == pkg {f=1} f && /^Filename:/ {print $2; exit}' /tmp/termux_Packages)
    
    if [ -z "$PKG_PATH" ]; then
        echo "Warning: Path for $pkg not found. It might be integrated into another package or renamed."
        continue
    fi

    FILE_NAME=$(basename "$PKG_PATH")
    if [ ! -f "$POOL_DIR/$FILE_NAME" ]; then
        log " -> Downloading $pkg..."
        curl -sL "$TERMUX_MIRROR/$PKG_PATH" -o "$POOL_DIR/$FILE_NAME"
    else
        log " -> $pkg already downloaded."
    fi
done

log "Creating apt-ftparchive configuration..."
cat <<EOF > /tmp/apt-ftparchive.conf
APT::FTPArchive::Release {
  Origin "Custom Termux Repo";
  Label "Custom Termux Repo";
  Suite "$DIST";
  Codename "$DIST";
  Architectures "$ARCH";
  Components "$COMP";
  Description "Minimal repository containing wget and tar";
};
EOF

log "Generating Packages and Packages.gz..."
cd "$REPO_DIR"
apt-ftparchive packages "pool/$COMP" > "$DISTS_DIR/Packages"
gzip -k -f "$DISTS_DIR/Packages"

log "Generating Release file..."
cd "$REPO_DIR/dists/$DIST"
apt-ftparchive -c /tmp/apt-ftparchive.conf release . > Release

log "Setting up GPG for repository signing..."
export GNUPGHOME="/tmp/termux-repo-gnupg"
rm -rf "$GNUPGHOME"
mkdir -p "$GNUPGHOME"
chmod 700 "$GNUPGHOME"

cat <<EOF > /tmp/gpg-batch
%echo Generating basic GPG key for the repository
Key-Type: RSA
Key-Length: 2048
Subkey-Type: RSA
Subkey-Length: 2048
Name-Real: Custom Termux Repo
Name-Email: $GPG_EMAIL
Expire-Date: 0
Passphrase: $GPG_PASS
%commit
%echo done
EOF

gpg --batch --generate-key /tmp/gpg-batch

log "Signing Release files..."
# Create Release.gpg (detached signature)
gpg --batch --yes --pinentry-mode loopback --passphrase "$GPG_PASS" --detach-sign --armor --output Release.gpg Release
# Create InRelease (clearsigned)
gpg --batch --yes --pinentry-mode loopback --passphrase "$GPG_PASS" --clearsign --output InRelease Release

log "Exporting Public Key for Termux clients..."
gpg --armor --export "$GPG_EMAIL" > "$REPO_DIR/termux-repo.pub"

log "Repository build complete!"
log "To serve it locally, run: python3 -m http.server 8080 --directory $REPO_DIR"
log "In Termux, add the repository and key using:"
log "  curl -O http://<YOUR_UBUNTU_IP>:8080/termux-repo.pub"
log "  apt-key add termux-repo.pub"
log "  echo \"deb [trusted=yes] http://<YOUR_UBUNTU_IP>:8080 stable main\" > \$PREFIX/etc/apt/sources.list.d/custom.list"
log "  apt update"
