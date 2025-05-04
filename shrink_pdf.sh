#!/bin/bash

# Configurable settings
MAX_WIDTH=1280    # Maximum width for images (pixels)
QUALITY=25        # WebP compression quality (0-100)

# Ensure a PDF file is provided as argument
if [ $# -ne 1 ]; then
    echo "Usage: $0 input.pdf"
    exit 1
fi

# Check if input file exists and is a PDF
if [ ! -f "$1" ] || [[ $(file -b --mime-type "$1") != "application/pdf" ]]; then
    echo "Error: $1 is not a valid PDF file"
    exit 1
fi

# Set up variables
INPUT_PDF="$1"
BASE_NAME=$(basename "$INPUT_PDF")
TEMP_DIR="${BASE_NAME}.files"
ARCHIVE="${BASE_NAME%.pdf}.tar"
ORIGINAL_SIZE=$(du -b "$INPUT_PDF" | cut -f1)

echo "Processing $INPUT_PDF ($(numfmt --to=iec-i --suffix=B $ORIGINAL_SIZE))"
echo "Using settings: MAX_WIDTH=$MAX_WIDTH, QUALITY=$QUALITY"

# Create temporary directory
mkdir -p "$TEMP_DIR"

# Extract images
echo "Extracting images..."
pdfimages -all "$INPUT_PDF" "$TEMP_DIR/img"

# Check if any images were extracted
if [ ! "$(ls -A $TEMP_DIR)" ]; then
    echo "No images found in PDF. Nothing to compress."
    rmdir "$TEMP_DIR"
    exit 0
fi

# Find maximum width of extracted images
echo "Analyzing image dimensions..."
FOUND_MAX_WIDTH=$(identify -format "%w\n" "$TEMP_DIR"/* 2>/dev/null | sort -n | tail -1)
echo "Maximum image width: $FOUND_MAX_WIDTH pixels"

# Resize images if max width > MAX_WIDTH
if [ $FOUND_MAX_WIDTH -gt $MAX_WIDTH ]; then
    echo "Resizing images to ${MAX_WIDTH}px width..."
    mogrify -resize ${MAX_WIDTH}\> "$TEMP_DIR"/*
fi

# Convert images to WebP with specified quality (silent output)
echo "Converting to WebP format with quality=$QUALITY..."
for img in "$TEMP_DIR"/*; do
    if [[ "$img" != *.webp ]]; then
        cwebp -quiet -q $QUALITY "$img" -o "${img}.webp"
        rm "$img"
    fi
done

# Calculate new size
NEW_SIZE=$(du -b "$TEMP_DIR" | cut -f1)
SAVED_BYTES=$((ORIGINAL_SIZE - NEW_SIZE))
SAVED_PERCENT=$((SAVED_BYTES * 100 / ORIGINAL_SIZE))

echo "Original size: $(numfmt --to=iec-i --suffix=B $ORIGINAL_SIZE)"
echo "New size: $(numfmt --to=iec-i --suffix=B $NEW_SIZE)"
echo "Space saved: $(numfmt --to=iec-i --suffix=B $SAVED_BYTES) ($SAVED_PERCENT%)"

# Check if savings are worth it (< 25%)
if [ $SAVED_PERCENT -lt 25 ]; then
    echo "Space savings less than 25%. Keeping original PDF."
    rm -rf "$TEMP_DIR"
    exit 0
fi

# Create archive
echo "Creating archive of compressed images..."
tar -cf "$ARCHIVE" -C "$TEMP_DIR" .

# Clean up
rm -rf "$TEMP_DIR"
rm "$INPUT_PDF"

echo "Done! Original PDF replaced with $ARCHIVE"
echo "Space saved: $(numfmt --to=iec-i --suffix=B $SAVED_BYTES) ($SAVED_PERCENT%)"
exit 0