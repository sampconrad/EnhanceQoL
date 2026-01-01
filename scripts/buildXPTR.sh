#!/bin/bash

# Pfade zu den Verzeichnissen anpassen
ROOT_DIR=$(pwd)/
WOW_ADDON_DIR="/Applications/World of Warcraft/_beta_/Interface/AddOns"

# Verzeichnisse für die Addons
EnhanceQoL_ADDON_DIR="$WOW_ADDON_DIR/EnhanceQoL"
EnhanceQoL_COMBAT_METER_DIR="$WOW_ADDON_DIR/EnhanceQoLCombatMeter"
EnhanceQoL_QUERY_DIR="$WOW_ADDON_DIR/EnhanceQoLQuery"
EnhanceQoL_MYTHIC_PLUS_QUERY_DIR="$WOW_ADDON_DIR/EnhanceQoLMythicPlus"
EnhanceQoL_SHAREDMEDIA_QUERY_DIR="$WOW_ADDON_DIR/EnhanceQoLSharedMedia"
EnhanceQoL_TOOLTIP_QUERY_DIR="$WOW_ADDON_DIR/EnhanceQoLTooltip"
EnhanceQoL_VENDOR_QUERY_DIR="$WOW_ADDON_DIR/EnhanceQoLVendor"

VERSION=$(git describe --tags --always)

# Lösche die bestehenden Addon-Verzeichnisse, wenn sie existieren
rm -rf "$EnhanceQoL_ADDON_DIR"
rm -rf "$EnhanceQoL_COMBAT_METER_DIR"
rm -rf "$EnhanceQoL_QUERY_DIR"
rm -rf "$EnhanceQoL_MYTHIC_PLUS_QUERY_DIR"
rm -rf "$EnhanceQoL_SHAREDMEDIA_QUERY_DIR"
rm -rf "$EnhanceQoL_TOOLTIP_QUERY_DIR"
rm -rf "$EnhanceQoL_VENDOR_QUERY_DIR"

# Erstelle die Addon-Verzeichnisse neu
mkdir -p "$EnhanceQoL_ADDON_DIR"
mkdir -p "$EnhanceQoL_COMBAT_METER_DIR"
mkdir -p "$EnhanceQoL_QUERY_DIR"
mkdir -p "$EnhanceQoL_MYTHIC_PLUS_QUERY_DIR"
mkdir -p "$EnhanceQoL_SHAREDMEDIA_QUERY_DIR"
mkdir -p "$EnhanceQoL_TOOLTIP_QUERY_DIR"
mkdir -p "$EnhanceQoL_VENDOR_QUERY_DIR"

echo "$ROOT_DIR"

# Kopiere die Addon-Dateien
cp -r "$ROOT_DIR/EnhanceQoL/"* "$EnhanceQoL_ADDON_DIR/"
cp -r "$ROOT_DIR/EnhanceQoLCombatMeter/"* "$EnhanceQoL_COMBAT_METER_DIR/"
cp -r "$ROOT_DIR/EnhanceQoLQuery/"* "$EnhanceQoL_QUERY_DIR/"
cp -r "$ROOT_DIR/EnhanceQoLMythicPlus/"* "$EnhanceQoL_MYTHIC_PLUS_QUERY_DIR/"
cp -r "$ROOT_DIR/EnhanceQoLSharedMedia/"* "$EnhanceQoL_SHAREDMEDIA_QUERY_DIR/"
cp -r "$ROOT_DIR/EnhanceQoLTooltip/"* "$EnhanceQoL_TOOLTIP_QUERY_DIR/"
cp -r "$ROOT_DIR/EnhanceQoLVendor/"* "$EnhanceQoL_VENDOR_QUERY_DIR/"

# Version in den .toc-Dateien ersetzen
sed -i '' "s/@project-version@/$VERSION/" "$EnhanceQoL_ADDON_DIR/EnhanceQoL.toc"
sed -i '' "s/@project-version@/$VERSION/" "$EnhanceQoL_COMBAT_METER_DIR/EnhanceQoLCombatMeter.toc"
sed -i '' "s/@project-version@/$VERSION/" "$EnhanceQoL_QUERY_DIR/EnhanceQoLQuery.toc"
sed -i '' "s/@project-version@/$VERSION/" "$EnhanceQoL_MYTHIC_PLUS_QUERY_DIR/EnhanceQoLMythicPlus.toc"
sed -i '' "s/@project-version@/$VERSION/" "$EnhanceQoL_SHAREDMEDIA_QUERY_DIR/EnhanceQoLSharedMedia.toc"
sed -i '' "s/@project-version@/$VERSION/" "$EnhanceQoL_TOOLTIP_QUERY_DIR/EnhanceQoLTooltip.toc"
sed -i '' "s/@project-version@/$VERSION/" "$EnhanceQoL_VENDOR_QUERY_DIR/EnhanceQoLVendor.toc"

echo "Addons wurden nach $WOW_ADDON_DIR kopiert."
