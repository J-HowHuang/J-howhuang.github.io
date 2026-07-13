#!/usr/bin/env bash

set +e

TARGET_DIR="${1:-.}"
WORKING_DIR="$(pwd)"

echo "================================================================="
echo "Working Directory (Base for Image Paths): $WORKING_DIR"
echo "Markdown Search Directory: $(cd "$TARGET_DIR" && pwd)"
echo "================================================================="

echo -e "\n[DEBUG] Scanning Markdown files for image references...\n"

find "$TARGET_DIR" -type f -name "*.md" | while read -r md_file; do
    echo "--------------------------------------------------------"
    echo "[FILE] Processing markdown: $md_file"
    echo "--------------------------------------------------------"
    
    line_num=0
    while read -r line; do
        ((line_num++))
        
        # Look for lines containing common image extensions
        if [[ "$line" =~ \.(png|PNG|jpg|JPG|jpeg|JPEG) ]]; then
            echo "  [LINE $line_num] Found potential image reference: '$line'"
            
            # Match standard markdown or HTML image syntax for PNG or JPG
            match=$(echo "$line" | grep -o -E '(\!\[.*\]\([^)]+\.(png|PNG|jpg|jpeg|JPG|JPEG)\)|<img[^>]+src=["'\''][^"'\'']+\.(png|PNG|jpg|jpeg|JPG|JPEG)["'\''])' || true)
            
            if [ -z "$match" ]; then
                echo "    [DEBUG] Text did NOT match the strict regex pattern."
                continue
            fi
            
            echo "    [MATCHED REGEX] Entire string caught: '$match'"
            
            # Extract raw path string
            if [[ "$match" =~ \<img ]]; then
                img_rel_path=$(echo "$match" | sed -E 's/.*src=["'\'']([^"'\'']+\.(png|PNG|jpg|jpeg|JPG|JPEG))["'\''].*/\1/')
                echo "    [SYNTAX] HTML <img> tag detected."
            else
                img_rel_path=$(echo "$match" | sed -E 's/\!\[.*\]\((.*)\)/\1/')
                echo "    [SYNTAX] Standard Markdown ![]() detected."
            fi
            
            echo "    [EXTRACTED PATH] Extracted raw path: '$img_rel_path'"
            
            # Strip leading slash if present
            clean_rel_path="${img_rel_path#/}"
            img_abs_path="$WORKING_DIR/$clean_rel_path"
            
            # -----------------------------------------------------------------
            # PHASE 1: Handle PNG Conversion if applicable
            # -----------------------------------------------------------------
            if [[ "$img_rel_path" =~ \.(png|PNG)$ ]]; then
                echo "    [PROCESS] Target is a PNG. Converting to JPG first..."
                
                if [ -f "$img_abs_path" ]; then
                    jpg_abs_path="${img_abs_path%.*}.jpg"
                    jpg_rel_path="${img_rel_path%.*}.jpg"
                    
                    if convert "$img_abs_path" -background white -alpha remove -alpha off -quality 85 "$jpg_abs_path" 2>/dev/null; then
                        echo "      [SUCCESS] Converted PNG -> $jpg_abs_path"
                        rm "$img_abs_path"
                        
                        # Update the markdown file link
                        if sed --version >/dev/null 2>&1; then
                            sed -i "s|$img_rel_path|$jpg_rel_path|g" "$md_file"
                        else
                            sed -i "" "s|$img_rel_path|$jpg_rel_path|g" "$md_file"
                        fi
                        echo "      [REPLACE] Updated link to .jpg in markdown."
                        
                        # Point our path variables to the newly created JPG for Phase 2
                        img_abs_path="$jpg_abs_path"
                    else
                        echo "      [ERROR] ImageMagick 'convert' failed. Skipping resizing step."
                        continue
                    fi
                else
                    echo "      [NOT FOUND] PNG file does not exist at: $img_abs_path"
                    continue
                fi
            fi
            
            # -----------------------------------------------------------------
            # PHASE 2: Intelligent Resizing (Only tracks files parsed from MD)
            # -----------------------------------------------------------------
            if [ -f "$img_abs_path" ]; then
                echo "    [PROCESS] Checking dimensions for resizing: $img_abs_path"
                dimensions=$(identify -format "%w %h" "$img_abs_path" 2>/dev/null)
                
                if [ -n "$dimensions" ]; then
                    width=$(echo "$dimensions" | cut -d' ' -f1)
                    height=$(echo "$dimensions" | cut -d' ' -f2)

                    if [ "$width" -ge "$height" ]; then
                        max_w=1920; max_h=1080
                    else
                        max_w=1080; max_h=1920
                    fi

                    if [ "$width" -gt "$max_w" ] || [ "$height" -gt "$max_h" ]; then
                        if mogrify -resize "${max_w}x${max_h}>" -quality 85 "$img_abs_path" 2>&1; then
                            echo "      [RESIZE] Done! Resized ($width x $height) down to fit ${max_w}x${max_h}"
                        else
                            echo "      [RESIZE ERROR] Failed modifying $img_abs_path"
                        fi
                    else
                        echo "      [SKIP] Image is already within limits ($width x $height)."
                    fi
                fi
            else
                echo "    [NOT FOUND] JPG target does not exist at: $img_abs_path"
            fi
            
        fi
    done < "$md_file"
done

echo "Done!"