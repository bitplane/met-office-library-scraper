#!/bin/bash

# Configurable settings
MIN_SAVINGS_PERCENT=25  # Minimum savings percentage to keep changes

# Ensure a directory is provided as argument
if [ $# -ne 1 ]; then
    echo "Usage: $0 directory_with_pdfs"
    exit 1
fi

# Check if input directory exists
if [ ! -d "$1" ]; then
    echo "Error: $1 is not a valid directory"
    exit 1
fi

# Check if shrink_pdf.sh exists and is executable
if [ ! -x "./shrink_pdf.sh" ]; then
    echo "Error: shrink_pdf.sh is not found or not executable"
    exit 1
fi

# Set up variables
INPUT_DIR="$1"
ORIGINAL_SIZE=$(du -b "$INPUT_DIR" | cut -f1)
TOTAL_FILES=$(find "$INPUT_DIR" -type f -name "*.pdf" | wc -l)
PROCESSED=0
SAVED_TOTAL=0

echo "Processing directory: $INPUT_DIR"
echo "Found $TOTAL_FILES PDF files to process"
echo "Original directory size: $(numfmt --to=iec-i --suffix=B $ORIGINAL_SIZE)"
echo "-------------------------------------------"

# Process each PDF file
find "$INPUT_DIR" -type f -name "*.pdf" -print0 | while IFS= read -r -d $'\0' pdf_file; do
    PROCESSED=$((PROCESSED + 1))
    
    echo "Processing file $PROCESSED/$TOTAL_FILES: \"$(basename "$pdf_file")\""
    
    # Get size before processing
    FILE_SIZE_BEFORE=$(du -b "$pdf_file" | cut -f1)
    DIR_SIZE_BEFORE=$(du -b "$INPUT_DIR" | cut -f1)
    
    # Process the PDF file
    ./shrink_pdf.sh "$pdf_file"
    
    # Get size after processing
    DIR_SIZE_AFTER=$(du -b "$INPUT_DIR" | cut -f1)
    SAVED_BYTES=$((DIR_SIZE_BEFORE - DIR_SIZE_AFTER))
    
    # If the file was processed successfully and removed, it would have a .tar file
    TAR_FILE="${pdf_file%.pdf}.tar"
    if [ -f "$TAR_FILE" ]; then
        SAVED_PERCENT=$((SAVED_BYTES * 100 / FILE_SIZE_BEFORE))
        SAVED_TOTAL=$((SAVED_TOTAL + SAVED_BYTES))
        echo "File saved: $(numfmt --to=iec-i --suffix=B $SAVED_BYTES) ($SAVED_PERCENT%)"
    else
        echo "File unchanged: Savings below threshold of $MIN_SAVINGS_PERCENT%"
    fi
    
    echo "Progress: $PROCESSED/$TOTAL_FILES"
    echo "Total space saved so far: $(numfmt --to=iec-i --suffix=B $SAVED_TOTAL)"
    echo "-------------------------------------------"
done

# Calculate final savings
FINAL_SIZE=$(du -b "$INPUT_DIR" | cut -f1)
TOTAL_SAVED=$((ORIGINAL_SIZE - FINAL_SIZE))
TOTAL_SAVED_PERCENT=$((TOTAL_SAVED * 100 / ORIGINAL_SIZE))

echo "Processing complete!"
echo "Original directory size: $(numfmt --to=iec-i --suffix=B $ORIGINAL_SIZE)"
echo "Final directory size: $(numfmt --to=iec-i --suffix=B $FINAL_SIZE)"
echo "Total space saved: $(numfmt --to=iec-i --suffix=B $TOTAL_SAVED) ($TOTAL_SAVED_PERCENT%)"
exit 0