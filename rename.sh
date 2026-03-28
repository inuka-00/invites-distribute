#!/bin/bash
# ─────────────────────────────────────────────
#  Single-Character Filename Pader
# ─────────────────────────────────────────────

# Change this to your actual images folder path
TARGET_DIR="./invites_kasu_friends"

if [[ ! -d "$TARGET_DIR" ]]; then
  echo "❌  Folder '$TARGET_DIR' not found."
  exit 1
fi

echo "📂  Scanning '$TARGET_DIR' for single-character filenames..."
echo "──────────────────────────────────────────────────"

renamed_count=0

# Loop through all files in the target directory
for filepath in "$TARGET_DIR"/*; do
  
  # Skip if it's a directory or doesn't exist
  [[ -f "$filepath" ]] || continue

  # Extract the directory, full filename, base name, and extension
  dir=$(dirname "$filepath")
  filename=$(basename "$filepath")
  extension="${filename##*.}"
  basename="${filename%.*}"

  # Check if the base name (the part before the dot) is exactly 1 character long
  if [[ ${#basename} -eq 1 ]]; then
    new_filename="0${basename}.${extension}"
    new_filepath="${dir}/${new_filename}"
    
    # Rename the file
    mv "$filepath" "$new_filepath"
    echo "  ✓ Renamed: $filename  →  $new_filename"
    ((renamed_count++))
  fi
done

echo "──────────────────────────────────────────────────"
if [[ $renamed_count -gt 0 ]]; then
  echo "🎉  Done! Successfully padded $renamed_count file(s) with zeros."
else
  echo "✨  No single-character filenames found. Everything looks good!"
fi