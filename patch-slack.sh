#!/bin/bash

TMP=$(mktemp -d -t slack-XXXXXXXXXX)
SLACK_RESOURCES_PATH=/usr/lib/slack/resources
SLACK_ELECTRON_ASAR=electron.asar
SLACK_ELECTRON_PATCH_START="START_OF_APPLE_EMOJI_PATCH"
SLACK_ELECTRON_PATCH_END="END_OF_APPLE_EMOJI_PATCH"
SLACK_ELECTRON_PATCH="
//# $SLACK_ELECTRON_PATCH_START
const { session } = require('electron');
app.once('ready', function () {
    const filter = {
        urls: ['https://*.slack-edge.com/production-standard-emoji-assets/10.2/google-*']
    };
    session.defaultSession.webRequest.onBeforeRequest(filter, function(details, callback) {
        const url = details.url.replace('google-', 'apple-');
        callback({ redirectURL: encodeURI(url) });
    });
});
//# $SLACK_ELECTRON_PATCH_END"

print() {
  local bin=$(basename $0)
  echo "[$bin] $1"
}

cleanup() {
  print "removing $TMP"
  rm -rf $TMP
}

cp_workspace() {
  if [ -f "$1.bak" ] || [ -d "$1.bak" ]; then
    print "copying $1.bak"
    cp -rf $1.bak $TMP/$(basename $1)
  else
    print "copying $1"
    cp -rf $1 $TMP
  fi
}

append() {
  $SHELL -c "cat <<EOF >> $2
  $1
EOF" >> /dev/null
}

if [ $EUID -ne 0 ]; then
  print "############################################################"
  print "### 'sudo' is required when running outside dry run mode ###"
  print "############################################################"
  print
  DRY_RUN=true
fi

if [ ! -d $SLACK_RESOURCES_PATH ]; then
  print "slack resources not found"
  exit 1
fi

trap cleanup EXIT
print "creating workspace"
cd $TMP

print "installing dependencies"
yarn add asar >> /dev/null

cp_workspace $SLACK_RESOURCES_PATH/$SLACK_ELECTRON_ASAR

print "unpacking $TMP/$SLACK_ELECTRON_ASAR"
npx asar extract $TMP/$SLACK_ELECTRON_ASAR $TMP/$SLACK_ELECTRON_ASAR.unpacked

print "patching $TMP/$SLACK_ELECTRON_ASAR.unpacked"
append "$SLACK_ELECTRON_PATCH" "$TMP/$SLACK_ELECTRON_ASAR.unpacked/browser/chrome-extension.js" | \
  awk \
  "/$SLACK_ELECTRON_PATCH_START/,/$SLACK_ELECTRON_PATCH_END/" \
  "$TMP/$SLACK_ELECTRON_ASAR.unpacked/browser/chrome-extension.js"

print "packing $TMP/$SLACK_ELECTRON_ASAR.unpacked"
npx asar pack $TMP/$SLACK_ELECTRON_ASAR.unpacked $TMP/$SLACK_ELECTRON_ASAR.modified

if [ ! -z $DRY_RUN ]; then
  exit 0
fi

if [ ! -f $SLACK_RESOURCES_PATH/$SLACK_ELECTRON_ASAR.bak ]; then
  print "backing up $SLACK_ELECTRON_ASAR"
  cp -f $SLACK_RESOURCES_PATH/$SLACK_ELECTRON_ASAR $SLACK_RESOURCES_PATH/$SLACK_ELECTRON_ASAR.bak
fi

print "updating $SLACK_ELECTRON_ASAR"
cp -rf $TMP/$SLACK_ELECTRON_ASAR.modified $SLACK_RESOURCES_PATH/$SLACK_ELECTRON_ASAR
