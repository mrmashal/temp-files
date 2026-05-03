#!/usr/bin/env bash
set -e

BASE="/srv/termux-mini-mirror"
ARCH="aarch64"
REPO="https://packages.termux.dev/apt/termux-main"
PKG_URL="$REPO/dists/stable/main/binary-$ARCH/Packages"

mkdir -p "$BASE/pool"
cd "$BASE"

echo "Downloading Packages index..."
wget -q -O Packages.full "$PKG_URL"

echo "Extracting package metadata..."

get_deps () {
awk -v pkg="$1" '
$1=="Package:" && $2==pkg {found=1}
found && $1=="Depends:" {
  sub("Depends: ","")
  gsub("\\(.*\\)","")
  gsub(",","")
  print
  found=0
}' Packages.full
}

resolve_deps () {

queue=("$@")
resolved=()

while [ ${#queue[@]} -gt 0 ]; do
  pkg=${queue[0]}
  queue=("${queue[@]:1}")

  if [[ " ${resolved[*]} " =~ " $pkg " ]]; then
    continue
  fi

  resolved+=("$pkg")

  deps=$(get_deps "$pkg")

  for d in $deps; do
    queue+=("$d")
  done
done

printf "%s\n" "${resolved[@]}"
}

echo "Resolving dependencies..."

packages=$(resolve_deps wget tar)

echo "$packages" > pkglist.txt

echo "Packages to download:"
cat pkglist.txt

echo "Downloading packages..."

while read pkg; do

url=$(awk -v p="$pkg" -v base="$REPO" '
$1=="Package:" && $2==p {found=1}
found && $1=="Filename:" {
  print base"/"$2
  found=0
}' Packages.full)

if [ -n "$url" ]; then
  echo "Downloading $pkg"
  wget -q -P pool "$url"
fi

done < pkglist.txt

echo "Building Packages index..."

dpkg-scanpackages pool /dev/null > Packages
gzip -f -k Packages

echo "Creating Release file..."

cat > Release <<EOF
Origin: Termux Mini Mirror
Label: Termux Mini Mirror
Suite: stable
Codename: stable
Architectures: $ARCH
Components: main
Description: Minimal Termux mirror containing wget and tar
EOF

echo
echo "Mirror created at: $BASE"
echo
echo "Directory structure:"
tree "$BASE" || ls -R "$BASE"
