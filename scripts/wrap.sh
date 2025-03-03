#!/bin/bash

set -e  # Exit on any error

# Determine rootdir based on our script location
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
ROOTDIR="$(dirname $DIR)"

# Detect luamin binary, preferably use the local luamin, otherwise default to the global luamin
LUAMIN="${ROOTDIR}/scripts/node_modules/.bin/luamin"
if ! which $LUAMIN 1> /dev/null; then
    LUAMIN="luamin"
fi
if ! which $LUAMIN 1> /dev/null; then
    echo "ERROR: Need luamin in PATH (run \`npm install\` from the scripts/ folder)"; exit 1
fi

# Parse args, or use defaults
MINIFY="${1:-false}"
# We expect this file to be run from the <repo>/scripts directory
LUA_SRC=${2:-$ROOTDIR/src/ArchHUD.lua}
CONF_DST=${3:-$ROOTDIR/ArchHUD.conf}

# Make a fresh work dir
WORK_DIR=${ROOTDIR}/scripts/work
(rm -rf $WORK_DIR/* || true) && mkdir -p $WORK_DIR

# Extract the exports because the minifier will eat them.
grep "\-- \?export:" $LUA_SRC | sed -e 's/^[ \t]*/        /' -e 's/-- export:/--export:/' > $WORK_DIR/ArchHUD.exports

VERSION_NUMBER=`grep "VERSION_NUMBER = .*" $LUA_SRC | sed -E "s/\s*VERSION_NUMBER = (.*)/\1/"`
if [[ "${VERSION_NUMBER}" == "" ]]; then
    echo "ERROR: Failed to detect version number"; exit 1
fi

sed "/-- \?export:/d;/require 'src.slots'/d" $LUA_SRC > $WORK_DIR/ArchHUD.extracted.lua

# Minify the lua
if [[ "$MINIFY" == "true" ]]; then
    echo "Minifying ... "
    # Using stdin pipe to avoid a bug in luamin complaining about "No such file: ``"
    echo "$WORK_DIR/ArchHUD.extracted.lua" | $LUAMIN --file > $WORK_DIR/ArchHUD.min.lua
else
    cp $WORK_DIR/ArchHUD.extracted.lua $WORK_DIR/ArchHUD.min.lua
fi

# Wrap in AutoConf
SLOTS=(
    core:class=CoreUnit
    radar:class=RadarPVPUnit,select=manual
    antigrav:class=AntiGravityGeneratorUnit
    warpdrive:class=WarpDriveUnit
    gyro:class=GyroUnit
    weapon:class=WeaponUnit,select=manual
    dbHud:class=databank,select=manual
    telemeter:class=TelemeterUnit,select=manual
    vBooster:class=VerticalBooster
    hover:class=Hovercraft
    door:class=DoorUnit,select=manual
    switch:class=ManualSwitchUnit,select=manual
    forcefield:class=ForceFieldUnit,select=manual
    atmofueltank:class=AtmoFuelContainer,select=manual
    spacefueltank:class=SpaceFuelContainer,select=manual
    rocketfueltank:class=RocketFuelContainer,select=manual
)

echo "Wrapping ..."
lua ${ROOTDIR}/scripts/wrap.lua --handle-errors --output yaml \
             --name "ArchHud - Archaegeo v$VERSION_NUMBER (Minified)" \
             $WORK_DIR/ArchHUD.min.lua $WORK_DIR/ArchHUD.wrapped.conf \
             --slots ${SLOTS[*]}

# Re-insert the exports
if [[ "$MINIFY" == "true" ]]; then
    sed "/script={}/e cat $WORK_DIR/ArchHUD.exports" $WORK_DIR/ArchHUD.wrapped.conf > $CONF_DST
else
    sed "/script = {}/e cat $WORK_DIR/ArchHUD.exports" $WORK_DIR/ArchHUD.wrapped.conf > $CONF_DST
fi

# Fix up minified L_TEXTs which requires a space after the comma
sed -i -E 's/L_TEXT\(("[^"]*"),("[^"]*")\)/L_TEXT(\1, \2)/g' $CONF_DST

echo "$VERSION_NUMBER" > ${ROOTDIR}/ArchHUD.conf.version

echo "Compiled v$VERSION_NUMBER at ${CONF_DST}"

rm $WORK_DIR/*
