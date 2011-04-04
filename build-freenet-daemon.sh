#!/bin/sh

PACKAGE=freenet-daemon
FREENET_VERSION_RELEASED=0.7.5

USAGE="Usage: $0 [-c|-u|-o|-S|-h] [--] [BRANCH]"
BOPT_CLEAN_ONLY=false
BOPT_UPDATE=false
BOPT_ORIG_ONLY=false
BOPT_DPKG=""

while getopts cuoSh o; do
	case $o in
	c ) BOPT_CLEAN_ONLY=true;;
	u ) BOPT_UPDATE=true;;
	o ) BOPT_ORIG_ONLY=true;;
	S ) BOPT_DPKG="$BOPT_DPKG -S";;
	h )
		cat <<-EOF
		$USAGE

		Build Freenet from fred-BRANCH and contrib-BRANCH into the freenet-daemon
		debian package.

		  -h            This help text.
		  -c            Clean previous build products only.
		  -o            Only build original source tarball, no debian packages.
		  -S            Build debian source packages, but no binaries.
		  -u            Update (git-pull) repositories before building.
		EOF
		exit 1
		;;
	\? ) echo $USAGE; exit 1;;
	esac
done
shift `expr $OPTIND - 1`

log() {
	case $1 in 0 ) PREFIX="";; 1 ) PREFIX="- ";; esac
	shift
	echo "$PREFIX$@"
}

FREENET_BRANCH="$1"
if [ -z "$FREENET_BRANCH" ]; then FREENET_BRANCH=official; fi
REPO_FRED=${PACKAGE}/fred-${FREENET_BRANCH}
REPO_EXT=${PACKAGE}/contrib-${FREENET_BRANCH}
if ! [ -d ${REPO_FRED} ]; then echo "not a directory: ${REPO_FRED}"; echo "$USAGE"; exit 1; fi
if ! [ -d ${REPO_EXT} ]; then echo "not a directory: ${REPO_EXT}"; echo "$USAGE"; exit 1; fi

GIT_DESCRIBED="$(cd ${REPO_FRED} && git describe --always --abbrev=4 && cd ..)"
GIT_DESCRIBED_EXT="$(cd ${REPO_EXT} && git describe --always --abbrev=4 && cd ..)"
DEB_VERSION=${FREENET_VERSION_RELEASED}+${GIT_DESCRIBED}
DEB_REVISION="$(cd ${PACKAGE} && dpkg-parsechangelog | grep Version | cut -d- -f2)"

BUILD_DIR="freenet-daemon-${DEB_VERSION}"
DIST_DIR="freenet-daemon-${FREENET_BRANCH}-dist"

log 0 "building freenet-daemon in $BUILD_DIR/"
log 0 "packages will be saved to $DIST_DIR/"

#PS4="\[\033[01;34m\]\w\[\033[00m\]\$ "
#set -x

log 1 "cleaning previous build products..."
rm -rf "$BUILD_DIR"
rm -rf "$DIST_DIR"
rm -f *.orig.tar.bz2 *.tmpl.tar.gz
rm -f *.changes *.deb *.dsc *.debian.tar.gz
if $BOPT_CLEAN_ONLY; then exit; fi
mkdir "$BUILD_DIR" || exit 1
mkdir "$DIST_DIR" || exit 1

if $BOPT_UPDATE; then
	log 1 "updating repos..."
	cd ${REPO_FRED} && git pull origin && cd ..
	cd ${REPO_EXT} && git pull origin && cd ..
fi

log 1 "copying and editing source files..."
log 1 "- note that this step will be *much* quicker if you \`git clean\` and \`ant clean-all\` beforehand"
cp -aH ${REPO_FRED} ${REPO_EXT} "$BUILD_DIR" || exit 1
cd "$BUILD_DIR"
# remove cruft
for path in fred-${FREENET_BRANCH} contrib-${FREENET_BRANCH}; do
	cd "$path"
	git clean -qfdx
	find . -name .git -o -name .gitignore -o -name .cvsignore | xargs rm -rf
	cd ..
done
cd ..

log 1 "making original source archives..."
tar cfj freenet-daemon_${DEB_VERSION}.orig.tar.bz2 "$BUILD_DIR" || exit 1
cp freenet-daemon_${DEB_VERSION}.orig.tar.bz2 "$DIST_DIR" || exit 1
tar cfz debian.freenet-daemon.tmpl.tar.gz ${PACKAGE}/debian || exit 1
cp debian.freenet-daemon.tmpl.tar.gz "$DIST_DIR" || exit 1

log 1 "copying and editing debian packaging files..."
cp -a ${PACKAGE}/debian "$BUILD_DIR"/debian || exit 1
cd "$BUILD_DIR"/debian
# update seednodes
rm -rf seednodes.fref && wget -q -O seednodes.fref http://downloads.freenetproject.org/alpha/opennet/seednodes.fref || exit 1
# substitute variables
ls -1 copyright freenet-daemon.docs rules | xargs sed -i \
	-e 's/@REVISION@/'${GIT_DESCRIBED}'/g' \
	-e 's/@EXTREVISION@/'${GIT_DESCRIBED_EXT}'/g' \
	-e 's/@RELEASE@/'${FREENET_BRANCH}'/g' || exit 1
cd ../..

if $BOPT_ORIG_ONLY; then exit; fi

log 1 "building debian packages..."
cd "$BUILD_DIR"
dch -v ${DEB_VERSION}-${DEB_REVISION} "GIT SNAPSHOT RELEASE! TEST PURPOSE ONLY!" && dpkg-buildpackage -rfakeroot $BOPT_DPKG
cd ..

log 1 "saving built packages..."
mv *.changes *.deb *.dsc *.debian.tar.gz "$DIST_DIR"
cd "$DIST_DIR"
dpkg-scanpackages . /dev/null > Packages
gzip -9 Packages
dpkg-scansources . /dev/null > Sources
gzip -9 Sources
cd ..