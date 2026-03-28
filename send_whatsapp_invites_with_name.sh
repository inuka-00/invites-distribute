#!/bin/bash
# ─────────────────────────────────────────────
#  WhatsApp Invitation Image Sender (Single Target Number)
# ─────────────────────────────────────────────

# CONFIG
ACCESS_TOKEN="" # Paste your full token here
PHONE_NUMBER_ID="1052688234585383"
TO_PHONE_NUMBER="94770080075"         # ALL messages will go to this number
IMAGES_FOLDER="./invites_kasu_friends"
NAMES_FILE="./names_kasu_friends.txt"              # Format: One name per line
DELAY_BETWEEN_MESSAGES=2
RETRY_DELAY=5

# Safely assign multi-line text with emojis and apostrophes to a variable
read -r -d '' CAPTION_TEMPLATE << 'EOF'
Hi {name}, We are getting married! 💕

We are honored to invite you to be by our side as we begin this new chapter together.

✨ 13th May 2026
✨ 9.00 a.m. Onwards
✨ At The Kingsbury

Please RSVP by 20th April 2026.
We can't wait to celebrate with you!

— Kasuni & Inuka  ✨
EOF

# ─────────────────────────────────────────────
#  VALIDATE
# ─────────────────────────────────────────────

if [[ "$ACCESS_TOKEN" == "YOUR_ACCESS_TOKEN_HERE" ]] || [[ -z "$ACCESS_TOKEN" ]]; then
  echo "❌  Please fill in ACCESS_TOKEN in the CONFIG section."
  exit 1
fi

if ! command -v jq &>/dev/null; then
  echo "❌  'jq' is required. Install it with: sudo apt install jq"
  exit 1
fi

if [[ ! -d "$IMAGES_FOLDER" ]]; then
  echo "❌  Folder '$IMAGES_FOLDER' not found."
  exit 1
fi

if [[ ! -f "$NAMES_FILE" ]]; then
  echo "❌  Names file '$NAMES_FILE' not found."
  exit 1
fi

# ─────────────────────────────────────────────
#  FUNCTIONS
# ─────────────────────────────────────────────

upload_image() {
  local image_path="$1"
  local filename
  filename=$(basename "$image_path")

  local response
  response=$(curl -s -X POST \
    "https://graph.facebook.com/v25.0/${PHONE_NUMBER_ID}/media" \
    -H "Authorization: Bearer ${ACCESS_TOKEN}" \
    -F "messaging_product=whatsapp" \
    -F "type=image/jpeg" \
    -F "file=@${image_path};type=image/jpeg")

  local media_id
  media_id=$(echo "$response" | jq -r '.id // empty')

  if [[ -n "$media_id" ]]; then
    echo "  ✓ Uploaded '$filename' → media_id: $media_id" >&2
    echo "$media_id"
  else
    echo "  ✗ Upload failed for '$filename': $response" >&2
    echo ""
  fi
}

send_image_message() {
  local media_id="$1"
  local name="$2"

  # Safely replace {name} using bash built-in string replacement
  local caption="${CAPTION_TEMPLATE//\{name\}/$name}"

  local payload
  payload=$(jq -n \
    --arg to "$TO_PHONE_NUMBER" \
    --arg id "$media_id" \
    --arg caption "$caption" \
    '{
      messaging_product: "whatsapp",
      to: $to,
      type: "image",
      recipient_type: "individual",
      image: { id: $id, caption: $caption }
    }')

  local response
  response=$(curl -s -X POST \
    "https://graph.facebook.com/v25.0/${PHONE_NUMBER_ID}/messages" \
    -H "Authorization: Bearer ${ACCESS_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "$payload")

  local msg_id
  msg_id=$(echo "$response" | jq -r '.messages[0].id // empty')

  if [[ -n "$msg_id" ]]; then
    echo "  ✓ Message sent for $name (to $TO_PHONE_NUMBER)"
    return 0
  else
    echo "  ✗ Send failed for $name: $response"
    return 1
  fi
}

process_image() {
  local image_path="$1"
  local name="$2"
  local attempt="${3:-1}"
  local filename
  filename=$(basename "$image_path")

  if [[ "$attempt" -gt 1 ]]; then
    echo "  [Retry] $filename for $name"
  fi

  local media_id
  media_id=$(upload_image "$image_path")

  if [[ -z "$media_id" ]]; then
    if [[ "$attempt" -eq 1 ]]; then
      echo "  ↻ Retrying in ${RETRY_DELAY}s…"
      sleep "$RETRY_DELAY"
      process_image "$image_path" "$name" 2
      return $?
    fi
    return 1
  fi

  if ! send_image_message "$media_id" "$name"; then
    if [[ "$attempt" -eq 1 ]]; then
      echo "  ↻ Retrying in ${RETRY_DELAY}s…"
      sleep "$RETRY_DELAY"
      process_image "$image_path" "$name" 2
      return $?
    fi
    return 1
  fi

  return 0
}

# ─────────────────────────────────────────────
#  MAIN
# ─────────────────────────────────────────────

# Expand all jpg/jpeg files into an array
shopt -s nullglob
# Assuming you renamed 1.jpg to 01.jpg, 2.jpg to 02.jpg, etc.
existing_images=("$IMAGES_FOLDER"/*.jpg "$IMAGES_FOLDER"/*.jpeg)
shopt -u nullglob

if [[ ${#existing_images[@]} -eq 0 ]]; then
  echo "❌  No JPEG images found in '$IMAGES_FOLDER'."
  exit 1
fi

# Read names from file safely
mapfile -t names < <(tr -d '\r' < "$NAMES_FILE")

# Remove any empty lines that might have been loaded
for i in "${!names[@]}"; do
  [[ -z "${names[i]}" ]] && unset "names[i]"
done
# Re-index array just in case empty lines messed up the numbering
names=("${names[@]}") 

total_names=${#names[@]}
total_images=${#existing_images[@]}

echo "📂  Found $total_images image(s) in '$IMAGES_FOLDER'"
echo "📋  Found $total_names name(s) in '$NAMES_FILE'"
echo "📱  Routing ALL messages to: $TO_PHONE_NUMBER"
echo "──────────────────────────────────────────────────"

if [[ $total_names -ne $total_images ]]; then
  echo "⚠️   WARNING: The number of names ($total_names) does not match the number of images ($total_images)."
  echo "    The script will map them 1-to-1 until it runs out of either names or images."
  echo "──────────────────────────────────────────────────"
fi

sent=0
failed=()
current_message=0
# Loop based on the number of names
for i in "${!names[@]}"; do
  name="${names[$i]}"
  image_path="${existing_images[$i]}"
  
  # If we run out of images before we run out of names, stop.
  if [[ -z "$image_path" ]]; then
    echo "⚠️  Ran out of images! Skipping remaining names."
    break
  fi

  filename=$(basename "$image_path")
  ((current_message++))

  echo "👤  [$current_message] Preparing invite for: $name"
  echo "   ↳ Using image: $filename"

  if process_image "$image_path" "$name"; then
    ((sent++))
  else
    failed+=("$filename (for $name)")
  fi

  if [[ $current_message -lt $total_names ]] && [[ -n "${existing_images[$i+1]}" ]]; then
    sleep "$DELAY_BETWEEN_MESSAGES"
  fi
  echo ""
done

echo "──────────────────────────────────────────────────"
echo "✅  Sent:   $sent/$current_message (All to $TO_PHONE_NUMBER)"

if [[ ${#failed[@]} -gt 0 ]]; then
  echo "❌  Failed: ${#failed[@]}"
  for f in "${failed[@]}"; do
    echo "     • $f"
  done
else
  echo "🎉  All matched invitations sent successfully!"
fi