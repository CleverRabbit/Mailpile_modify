#!/bin/bash

#
# This script will use Homebrew to build a complete environment for packacing
# mailpile. This script is tested on macOS 10.13.4, with XCode 9.3.
#
set -e

#### CHANGE THESE EXPORTS IF NEEDED ####
####
export BUILD_DIR=~/build
export MAILPILE_BREW_ROOT="$BUILD_DIR/Mailpile.app/Contents/Resources/app"
export PATH="$MAILPILE_BREW_ROOT"/bin:$PATH
export GIT_SSL_NO_VERIFY=1
export HOMEBREW_CC=gcc-4.2
export MACOSX_DEPLOYMENT_TARGET=10.13
export PYTHON_MAJOR_VERSION=2
export PYTHON_VERSION=2.7
export PYTHON_SUBVERSION="14_3"

export SYMLINKS_SRC="https://raw.githubusercontent.com/peturingi/homebrew/06eefcfd0e4cb1e9496c5944cf861a8f7607c69b/Library/Formula/symlinks.rb"

export GUI_O_MAC_TIC_BRANCH="master"
export GUI_O_MAC_TIC_REPO="https://github.com/Mailpile/gui-o-mac-tic.git"
##
## CHANGE THE ABOVE EXPORTS IF NEEDED ##

#### Do not change anything below this line unless you know what you are doing!

# See this mailing list post: http://curl.haxx.se/mail/archive-2013-10/0036.html
export OSX_MAJOR_VERSION="$(sw_vers -productVersion | cut -d . -f 2)"
if [ $(echo "$OSX_MAJOR_VERSION  < 9" | bc) == 1 ]; then
   export CURL_CA_BUNDLE=/usr/share/curl/curl-ca-bundle.crt
fi

# Some of the homebrew build stuff depends on a java compiler.
if ! javac -version&>/dev/null ; then
    echo "This script depends on javac; Please install version 10, or later, of the Java Developer Kit."
	false
fi

# Create AppIcon.appiconset
export ICONSET_DIR=$BUILD_DIR/AppIcon.appiconset
mkdir -p $ICONSET_DIR
export Icon1024="../icons/1024x1024.png"
sips -z 16 16     $Icon1024 --out $ICONSET_DIR/Icon-16.png
sips -z 32 32     $Icon1024 --out $ICONSET_DIR/Icon-32.png
sips -z 32 32     $Icon1024 --out $ICONSET_DIR/Icon-33.png
sips -z 64 64     $Icon1024 --out $ICONSET_DIR/Icon-64.png
sips -z 128 128   $Icon1024 --out $ICONSET_DIR/Icon-128.png
sips -z 256 256   $Icon1024 --out $ICONSET_DIR/Icon-256.png
sips -z 256 256   $Icon1024 --out $ICONSET_DIR/Icon-257.png
sips -z 512 512   $Icon1024 --out $ICONSET_DIR/Icon-512.png
sips -z 512 512   $Icon1024 --out $ICONSET_DIR/Icon-513.png
cp $Icon1024 $ICONSET_DIR/Icon-1024.png

# Build GUI-o-Mac-tic
git clone -b "$GUI_O_MAC_TIC_BRANCH" "$GUI_O_MAC_TIC_REPO" "$BUILD_DIR/gui-o-mac-tic"
cd "$BUILD_DIR/gui-o-mac-tic"
git submodule update --init --recursive
rm src/Assets.xcassets/AppIcon.appiconset/Icon-*.png
mv $ICONSET_DIR/* src/Assets.xcassets/AppIcon.appiconset/
rmdir $ICONSET_DIR
cd ~-
cp configurator.sh "$BUILD_DIR/gui-o-mac-tic/share/configurator.sh"
xcodebuild -project "$BUILD_DIR/gui-o-mac-tic/GUI-o-Mac-tic.xcodeproj" \
	EXECUTABLE_NAME=Mailpile \
	PRODUCT_BUNDLE_IDENTIFIER=is.mailpile.gui-o-mac-tic.mailpile \
	PRODUCT_MODULE_NAME=Mailpile \
	PRODUCT_NAME=Mailpile \
	PROJECT_NAME=Mailpile \
	WRAPPER_NAME=Mailpile.app
mv "$BUILD_DIR/gui-o-mac-tic/build/Release/Mailpile.app" "$BUILD_DIR/"
rm -rf "$BUILD_DIR/gui-o-mac-tic"

#
# Install Mailpile Dependencies from homebrew.
#
mkdir -p $MAILPILE_BREW_ROOT
cd "$MAILPILE_BREW_ROOT"
[ -e bin/brew ] || \
    curl -kL https://github.com/Homebrew/brew/tarball/master \
    | tar xz --strip 1
echo
brew update
brew install gnupg
brew install openssl
brew link --force openssl
brew install libjpeg
brew install python@$PYTHON_MAJOR_VERSION
brew install tor

#
# Install Mailpile Python Dependencies with PIP. 
#
cd ~-
pip install -r ../../requirements.txt --ignore-installed

#
# Install Mailpile
#
pip install ../..
cp -a ../../shared-data "$BUILD_DIR/Mailpile.app/Contents/Resources/app/Cellar/python@2/2.7.14_3/Frameworks/Python.framework/Versions/2.7/share/"
cp -a ../.. "$BUILD_DIR/Mailpile.app/Contents/Resources/app/opt/mailpile"
#install wrapper so mailpile can launch with correcth path and python path
mv "$BUILD_DIR/Mailpile.app/Contents/Resources/app/bin/mailpile" "$BUILD_DIR/Mailpile.app/Contents/Resources/app/bin/mailpile_actual"
cp mailpile "$BUILD_DIR/Mailpile.app/Contents/Resources/app/bin/mailpile"
cd ~- 

#
# Make library paths relative
#
_readlink() {
    FN="$1"
    LN="$(readlink $1)"
    while [ "$LN" != "" -a "$LN" != "$FN" ]; do
        FN="$LN"
        LN="$(readlink $1)"
    done
    echo "$FN"
}
_relpath() {
    TARGET="$1"
    SOURCE="$2"
    cat <<tac |python
import os, sys
source, target = os.path.abspath('$SOURCE').split('/'), '$TARGET'.split('/')
while target and source and target[0] == source[0]:
    target.pop(0)
    source.pop(0)
print '/'.join(['..' for i in source] + target)
tac
}
_fixup_lib_names() {
    bin="$1"
    typ="$2"
    otool -L "$bin" |grep "$MAILPILE_BREW_ROOT" |while read lib JUNK; do
        bin_path="$(_readlink "$bin")"
        new=$(_relpath "$lib" $(dirname "$bin_path"))
        chmod u+w "$bin" "$lib"
        echo install_name_tool -change "$lib" "$typ/$new" "$bin_path"
        install_name_tool -change "$lib" "$typ/$new" "$bin_path"
        install_name_tool -id $(basename "$lib") "$lib"
        chmod u-w "$bin" "$lib"
    done
}
cd "$MAILPILE_BREW_ROOT/bin"
for bin in *; do
    _fixup_lib_names "$bin" "@executable_path"
done

cd "$MAILPILE_BREW_ROOT"
(
    find . -type f -name 'Python'
    find Cellar opt -type f -name '*.dylib'
    find Cellar opt -type f -name '*.so'
) | while read bin; do
    _fixup_lib_names "$bin" "@loader_path"
done


#
# Make symbolic links relative
#
if [ ! -e "$MAILPILE_BREW_ROOT"/bin/symlinks ]; then
	brew install "$SYMLINKS_SRC"
else
    cd "$MAILPILE_BREW_ROOT"
fi
# This needs to run twice... just because
./bin/symlinks -s -c -r "$MAILPILE_BREW_ROOT"
./bin/symlinks -s -c -r "$MAILPILE_BREW_ROOT"

#
# Fix brew's Python to not hardcode the full path
#
cd "$MAILPILE_BREW_ROOT"
for target in /lib/python$PYTHON_VERSION/site-packages/sitecustomize.py \
              /Cellar/python@$PYTHON_MAJOR_VERSION/$PYTHON_VERSION.$PYTHON_SUBVERSION/Frameworks/Python.framework/Versions/$PYTHON_VERSION/lib/python$PYTHON_VERSION/_sysconfigdata.py \
; do
    perl -pi.bak -e \
        "s|'$MAILPILE_BREW_ROOT|__file__.replace('$target', '') + '|g" \
        .$target
done

#
# Fix Python's launcher to avoid the rocket ship icon shows when launching python apps.
#
LSUIELEM="<key>LSUIElement</key><string>1</string>"
perl -pi.bak -e \
    "s|(\\s+)(<key>CFBundleDocumentTypes)|\\1$LSUIELEM\\2|" \
    ./Cellar/python@$PYTHON_MAJOR_VERSION/*/Frame*/Python*/V*/C*/Res*/Python.app/Cont*/Info.plist


#
# Pre-test, slim down: remove *.pyo and *.pyc files
#
cd "$MAILPILE_BREW_ROOT"
find . -name *.pyc -or -name *.pyo -or -name *.a | xargs rm -f

