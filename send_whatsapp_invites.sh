#!/bin/bash
# ─────────────────────────────────────────────
#  WhatsApp Invitation Image Sender
# ─────────────────────────────────────────────

# CONFIG
ACCESS_TOKEN=""
PHONE_NUMBER_ID="1052688234585383"
TO_PHONE_NUMBER="94770080075"
IMAGES_FOLDER="./invites_amma_4"
DELAY_BETWEEN_MESSAGES=2
RETRY_DELAY=5

# Caption in a separate file to avoid shell quoting issues
CAPTION_FILE="/tmp/whatsapp_caption.txt"
cat > "$CAPTION_FILE" << 'CAPTION'
The start of our _*Forever*_. 💕

We are honored to invite you to be by our side as we begin this new chapter together.

✨ 13th May 2026
✨ 9.00 a.m. Onwards
✨ At The Kingsbury

Please RSVP by 20th April 2026.
We can't wait to celebrate with you!

— Kasuni & Inuka  ✨
CAPTION

# ─────────────────────────────────────────────
#  VALIDATE
# ─────────────────────────────────────────────

if [[ "$ACCESS_TOKEN" == "YOUR_ACCESS_TOKEN_HERE" ]]; then
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

  local payload
  payload=$(jq -n \
    --arg to "$TO_PHONE_NUMBER" \
    --arg id "$media_id" \
    --rawfile caption "$CAPTION_FILE" \
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
    echo "  ✓ Message sent (id: $msg_id)"
    return 0
  else
    echo "  ✗ Send failed: $response"
    return 1
  fi
}

process_image() {
  local image_path="$1"
  local attempt="${2:-1}"
  local filename
  filename=$(basename "$image_path")

  if [[ "$attempt" -gt 1 ]]; then
    echo "  [Retry] $filename"
  fi

  local media_id
  media_id=$(upload_image "$image_path")

  if [[ -z "$media_id" ]]; then
    if [[ "$attempt" -eq 1 ]]; then
      echo "  ↻ Retrying in ${RETRY_DELAY}s…"
      sleep "$RETRY_DELAY"
      process_image "$image_path" 2
      return $?
    fi
    return 1
  fi

  if ! send_image_message "$media_id"; then
    if [[ "$attempt" -eq 1 ]]; then
      echo "  ↻ Retrying in ${RETRY_DELAY}s…"
      sleep "$RETRY_DELAY"
      process_image "$image_path" 2
      return $?
    fi
    return 1
  fi

  return 0
}

# ─────────────────────────────────────────────
#  MAIN
# ─────────────────────────────────────────────

images=("$IMAGES_FOLDER"/*.jpg "$IMAGES_FOLDER"/*.jpeg)

existing_images=()
for img in "${images[@]}"; do
  [[ -f "$img" ]] && existing_images+=("$img")
done

if [[ ${#existing_images[@]} -eq 0 ]]; then
  echo "❌  No JPEG images found in '$IMAGES_FOLDER'."
  exit 1
fi

echo "📂  Found ${#existing_images[@]} image(s) in '$IMAGES_FOLDER'"
echo "📱  Sending to: $TO_PHONE_NUMBER"
echo "──────────────────────────────────────────────────"

sent=0
failed=()
total=${#existing_images[@]}

for i in "${!existing_images[@]}"; do
  image_path="${existing_images[$i]}"
  filename=$(basename "$image_path")
  num=$((i + 1))

  echo ""
  echo "[$num/$total] $filename"

  if process_image "$image_path"; then
    ((sent++))
  else
    failed+=("$filename")
  fi

  if [[ $num -lt $total ]]; then
    sleep "$DELAY_BETWEEN_MESSAGES"
  fi
done

echo ""
echo "──────────────────────────────────────────────────"
echo "✅  Sent:   $sent/$total"

if [[ ${#failed[@]} -gt 0 ]]; then
  echo "❌  Failed: ${#failed[@]}"
  for f in "${failed[@]}"; do
    echo "     • $f"
  done
else
  echo "🎉  All invitations sent successfully!"
fi

# Cleanup
rm -f "$CAPTION_FILE"