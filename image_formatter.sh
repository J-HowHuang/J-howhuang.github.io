#!/usr/bin/env bash

# Check if an input file was provided
if [ -z "$1" ]; then
    echo "Usage: $0 <markdown_file>"
    exit 1
fi

# Check if the file exists
if [ ! -f "$1" ]; then
    echo "Error: File '$1' not found."
    exit 1
fi

# Use Python to read, convert, and overwrite the file in-place
python3 - "$1" << 'EOF'
import sys
import re

file_path = sys.argv[1]

# Read the entire content first
with open(file_path, 'r', encoding='utf-8') as f:
    content = f.read()

def sanitize_path(img_path):
    """Ensures the path starts with a single '/' relative to execution root."""
    cleaned = img_path.strip()
    cleaned = re.sub(r'^[./]+', '', cleaned)
    return f"/{cleaned}"

# Match markdown images and the immediate next line if it's text
immediate_pattern = r'!\[(.*?)\]\((.*?)\)\n([^\n]+)'

def replace_with_caption(match):
    alt_text = match.group(1).strip()
    img_src = sanitize_path(match.group(2))
    caption_text = match.group(3).strip()
    
    # Don't accidentally consume another image markdown as a caption
    if re.match(r'!\[.*?\]\(.*?\)', caption_text):
        return f'<figure class="align-center">\n  <img src="{img_src}" alt="{alt_text}">\n</figure>\n{caption_text}'
        
    return (
        f'<figure class="align-center">\n'
        f'  <img src="{img_src}" alt="{alt_text}">\n'
        f'  <figcaption>{caption_text}</figcaption>\n'
        f'</figure>'
    )

# Pass 1: Convert images with immediate captions
processed = re.sub(immediate_pattern, replace_with_caption, content)

# Pass 2: Convert remaining standalone images
standalone_pattern = r'!\[(.*?)\]\((.*?)\)'

def replace_standalone(match):
    alt_text = match.group(1).strip()
    img_src = sanitize_path(match.group(2))
    return f'<figure class="align-center">\n  <img src="{img_src}" alt="{alt_text}">\n</figure>'

final_output = re.sub(standalone_pattern, replace_standalone, processed)

# Overwrite the original file with the final result
with open(file_path, 'w', encoding='utf-8') as f:
    f.write(final_output)

print(f"Successfully updated '{file_path}' in-place.")
