#!/bin/sh

# Goal is to make a script to create AppImages for applications packed into a
# tarball or zip with minimal modification per app

# Variables
[ -z "$TMPDIR" ] && TMPDIR='/tmp'
[ -z "$ARCH" ]   && ARCH=$(uname -m)

goDl=$(curl https://go.dev/dl/ -s | grep 'linux-amd64' | grep '<td class' | head -n1 | cut -d'"' -f6)
appUrl="https://go.dev/$goDl"
aiVersion=$(echo "$goDl" | sed -e 's/\/dl\/go//' -e 's/\.lin.*//')
appId='dev.go'
appName="Go"
appImageName=$(echo $appName | tr ' ' '_')"-$aiVersion-$ARCH.AppImage"
appBinName="go"
tempDir="$TMPDIR/.buildApp_$appName.$RANDOM"
startDir="$PWD"
iconUrl='https://go.dev/images/go-logo-blue.svg'
comp='gzip'

# Define what should be in the desktop entry
entry="[Desktop Entry]
Version=1.0
Type=Application
Name=$appName
Comment=Golang $aiVersion compiler
Exec=$appBinName
Icon=$appId
Terminal=true
Categories=Development;Building;
X-AppImage-Version=
[X-App Permissions]
Level=3
"

appStream='<?xml version="1.0" encoding="UTF-8"?>
<component type="console-application">
  <id>dev.go</id>

  <name>Go</name>
  <summary>Golang compiler</summary>

  <metadata_license>FSFAP</metadata_license>
  <project_license>BSD-3-Clause</project_license>

  <description>
    <p>
Go is an open source programming language which is easy to learn and get started with, has built-in concurrency and a robust standard library.
    </p>
  </description>

  <categories>
    <category>Development</category>
    <category>Building</category>
  </categories>

  <provides>
    <binary>go</binary>
  </provides>
</component>'

printErr() {
	echo -e "FATAL: $@"
	echo 'Log:'
	cat "$tempDir/out.log"
	rm "$tempDir/out.log"
	exit 1
}

# Create and move to working directory
mkdir -p "$tempDir/AppDir/usr/bin" \
         "$tempDir/AppDir/usr/share/icons/hicolor/scalable/apps"

if [ ! $? = 0  ]; then
	printErr 'Failed to create temporary directory.'
fi

cd "$tempDir"
echo "Working directory: $tempDir"

echo "Downloading and extracting $appName..."
wget "$appUrl" -O - 2> "$tempDir/out.log" | tar -xz -C 'AppDir/usr' --strip 1
if [ ! $? = 0 ]; then
	printErr "Failed to download '$appName' (make sure you're connected to the internet)"
fi
chmod +x "AppDir/usr/bin/$appBinName"

# Remove stuff not needed for runnung
rm -r "AppDir/usr/test" "AppDir/usr/doc" "AppDir/usr/pkg/linux"*
strip -s "AppDir/usr/bin/"* "AppDir/usr/pkg/tool/"*/*

# Download the icon
wget "$iconUrl" -O "AppDir/usr/share/icons/hicolor/scalable/apps/$appId.svg" &> "$tempDir/out.log"
if [ ! $? = 0 ]; then
	printErr "Failed to download '$appId.svg' (make sure you're connected to the internet)"
fi

# Create desktop entry and link up executable and icons
echo "$entry" > "AppDir/$appId.desktop"
ln -s "./usr/bin/$appBinName" 'AppDir/AppRun'
ln -s "./usr/share/icons/hicolor/scalable/apps/$appId.svg" "AppDir/$appId.svg"

# Check if user has AppImageTool (under the names of `appimagetool.AppImage`
# and `appimagetool-x86_64.AppImage`) if not, download it
echo 'Checking if AppImageTool is installed...'
if command -v 'mkappimage.AppImage'; then
	aitool() {
		'mkappimage.AppImage' "$@"
	}
elif command -v "mkappimage-$ARCH.AppImage"; then
	aitool() {
		"mkappimage-$ARCH.AppImage" "$@"
	}
elif command -v "$PWD/mkappimage"; then
	aitool() {
		"$PWD/mkappimage" "$@"
	}
elif command -v 'mkappimage'; then
	aitool() {
		'mkappimage' "$@"
	}
elif command -v 'appimagetool'; then
	aitool() {
		'appimagetool' "$@"
	}
else
	# Hacky one-liner to get the URL to download the latest mkappimage
	mkAppImageUrl=$(curl -q https://api.github.com/repos/probonopd/go-appimage/releases | grep $(uname -m) | grep mkappimage | grep browser_download_url | cut -d'"' -f4 | head -n1)
	echo 'Downloading `mkappimage`'
	wget "$mkAppImageUrl" -O 'mkappimage'
	chmod +x 'mkappimage'
	aitool() {
		"$PWD/mkappimage" "$@"
    }
fi


# Use the found mkappimage command to build our AppImage with update information
echo "Building $appImageName..."
export ARCH="$ARCH"
export VERSION="$aiVersion"

aitool --comp="$comp" -u \
	"gh-releases-zsync|mgord9518|go.AppImage|continuous|go-*$ARCH.AppImage.zsync" \
	'AppDir/'

if [ ! $? = 0 ]; then
	printErr "failed to build '$appImageName'"
fi

# Experimental shImg build
# Build SquashFS image
# Download mkDwarFS and build image
wget https://github.com/mhx/dwarfs/releases/download/v0.5.6/dwarfs-0.5.6-Linux.tar.xz -O - | tar -xOJ 'dwarfs-0.5.6-Linux/bin/mkdwarfs' --strip=2 > mkdwarfs
./mkdwarfs -i AppDir -o sfs -l6 -B4 --set-owner 0 --set-group 0

#mksquashfs AppDir sfs -root-owned -no-exports -noI -b 1M -comp zstd -Xcompression-level 22 -nopad
[ $? -ne 0 ] && exit $?

# Download shImg runtime
wget "https://github.com/mgord9518/shappimage/releases/download/continuous/runtime_dwarf-static-x86_64-aarch64"
[ $? -ne 0 ] && exit $?

cat runtime_dwarf-static-x86_64-aarch64 sfs > $(echo $appName | tr ' ' '_')"-$aiVersion-$ARCH.shImg"
chmod +x $(echo $appName | tr ' ' '_')"-$aiVersion-$ARCH.shImg"

# Append desktop integration info
#wget 'https://raw.githubusercontent.com/mgord9518/shappimage/main/add_integration.sh'
#[ $? -ne 0 ] && exit $?
#sh add_integration.sh ./$(echo $appName | tr ' ' '_')"-$aiVersion-$ARCH.shImg" "gh-releases-zsync|mgord9518|go.AppImage|continuous|go-*-x86_64.shImg.zsync"

# Take the newly created AppImage and move it into the starting directory
if [ -f "$startDir/$appImageName" ]; then
	echo 'AppImage already exists; overwriting...'
	rm "$startDir/$appImageName"
fi

# Move completed AppImage and zsync file to start directory
mv $(echo $appName | tr ' ' '_')*"-$ARCH.AppImage" "$startDir"
mv $(echo $appName | tr ' ' '_')*"-$ARCH.AppImage.zsync" "$startDir"
mv $(echo $appName | tr ' ' '_')*"-$ARCH.shImg" "$startDir"

# Remove all temporary files
echo 'Cleaning up...'
rm -rf "$tempDir"

echo 'DONE!'
