#!/bin/bash

# Define colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

# Configurable settings
MAX_WIDTH=1280    # Maximum width for images (pixels)
QUALITY=50        # WebP compression quality (0-100)
PARALLEL_JOBS=8   # Number of parallel jobs (half your cores is a good starting point)

# Ensure a PDF file is provided as argument
if [ $# -ne 1 ]; then
    echo "Usage: $0 input.pdf"
    exit 1
fi

# Check if input file exists and is a PDF
if [ ! -f "$1" ] || [[ $(file -b --mime-type "$1") != "application/pdf" ]]; then
    echo -e "${RED}Error: $1 is not a valid PDF file${RESET}"
    exit 1
fi

# Check if GNU parallel is installed
if ! command -v parallel &> /dev/null; then
    echo -e "${RED}Error: GNU parallel is not installed. Please install it first.${RESET}"
    exit 1
fi

# Set up variables
INPUT_PDF="$1"
PDF_DIR=$(dirname "$INPUT_PDF")
BASE_NAME=$(basename "$INPUT_PDF")
TEMP_DIR="${BASE_NAME}.files"
ARCHIVE="${PDF_DIR}/${BASE_NAME%.pdf}.tar"
ORIGINAL_SIZE=$(du -b "$INPUT_PDF" | cut -f1)
ORIGINAL_SIZE_HUMAN=$(numfmt --to=iec-i --suffix=B $ORIGINAL_SIZE)

echo -e "Settings: MAX_WIDTH=${CYAN}$MAX_WIDTH${RESET}, QUALITY=${CYAN}$QUALITY${RESET}, PARALLEL_JOBS=${CYAN}$PARALLEL_JOBS${RESET}"
echo -e "File: ${BOLD}$BASE_NAME${RESET} (${MAGENTA}$ORIGINAL_SIZE_HUMAN${RESET})"
echo -e " - Extracting to \"$TEMP_DIR\""

# Create temporary directory
mkdir -p "$TEMP_DIR"

# Extract images
pdfimages -all "$INPUT_PDF" "$TEMP_DIR/img"

# Count extracted images
NUM_IMAGES=$(find "$TEMP_DIR" -type f | wc -l)
echo -e " - Extracted ${YELLOW}$NUM_IMAGES${RESET} images"

# Check if any images were extracted
if [ $NUM_IMAGES -eq 0 ]; then
    echo -e " - ${RED}No images found in PDF. Nothing to compress.${RESET}"
    rmdir "$TEMP_DIR"
    exit 0
fi

# Create a conversion function to be passed to parallel
convert_image() {
    local img="$1"
    local max_width="$2"
    local quality="$3"
    
    # Skip if not a regular file
    [ -f "$img" ] || return
    
    # Try conversion
    if [ "$max_width" -gt 0 ]; then
        cwebp -q "$quality" -resize "$max_width" 0 "$img" -o "${img}.webp" &>/dev/null
    else
        cwebp -q "$quality" "$img" -o "${img}.webp" &>/dev/null
    fi
    
    # Note: We don't delete the original file if conversion fails
    # This way, we preserve all image data, even formats that can't be converted
}

# Export the function so parallel can see it
export -f convert_image

# Process images in parallel
echo -e " - Processing images in parallel (using ${YELLOW}$PARALLEL_JOBS${RESET} jobs)..."
find "$TEMP_DIR" -type f | parallel -j "$PARALLEL_JOBS" "convert_image {} $MAX_WIDTH $QUALITY"

# Count successful conversions
WEBP_COUNT=$(find "$TEMP_DIR" -name "*.webp" | wc -l)
echo -e " - Successfully converted ${YELLOW}$WEBP_COUNT${RESET} out of ${YELLOW}$NUM_IMAGES${RESET} images to WebP"

# Check if any WebP files were created
if [ $WEBP_COUNT -eq 0 ]; then
    echo -e " - ${RED}No images could be converted to WebP. Keeping original PDF.${RESET}"
    rm -rf "$TEMP_DIR"
    exit 0
fi

# Calculate new size (including both WebP and original files for those that couldn't be converted)
NEW_SIZE=$(du -b "$TEMP_DIR" | cut -f1)
NEW_SIZE_HUMAN=$(numfmt --to=iec-i --suffix=B $NEW_SIZE)
SAVED_BYTES=$((ORIGINAL_SIZE - NEW_SIZE))
SAVED_BYTES_HUMAN=$(numfmt --to=iec-i --suffix=B $SAVED_BYTES)
SAVED_PERCENT=$((SAVED_BYTES * 100 / ORIGINAL_SIZE))

echo -e " - Compression results:"
echo -e "   - Original size: ${MAGENTA}$ORIGINAL_SIZE_HUMAN${RESET}, new size: ${MAGENTA}$NEW_SIZE_HUMAN${RESET}, saved: ${GREEN}$SAVED_BYTES_HUMAN${RESET} (${GREEN}$SAVED_PERCENT%${RESET})"

# Check if NEW_SIZE is very small or zero
if [ $NEW_SIZE -lt 1000 ]; then
    echo -e " - ${RED}Output size suspiciously small (${NEW_SIZE}B). Keeping original PDF.${RESET}"
    rm -rf "$TEMP_DIR"
    exit 0
fi

# Check if savings are worth it (< 25%)
if [ $SAVED_PERCENT -lt 25 ]; then
    echo -e " - ${RED}Space savings less than 25%. Keeping original PDF.${RESET}"
    rm -rf "$TEMP_DIR"
    exit 0
fi

# Create archive
echo -e " - Archiving all images (originals and WebP)"
tar -cf "$ARCHIVE" -C "$TEMP_DIR" .

# Check if archive was created successfully
if [ ! -f "$ARCHIVE" ] || [ ! -s "$ARCHIVE" ]; then
    echo -e " - ${RED}Failed to create archive or archive is empty. Keeping original PDF.${RESET}"
    rm -rf "$TEMP_DIR"
    exit 0
fi

# Clean up
rm -rf "$TEMP_DIR"
rm "$INPUT_PDF"

echo -e " - Replaced \"$BASE_NAME\" with ${GREEN}\"${BASE_NAME%.pdf}.tar\"${RESET}"
echo ""
exit 0