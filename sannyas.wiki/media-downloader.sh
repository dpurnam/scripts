#!/bin/bash

# A bash script to download audio files and images from a sannyas.wiki page,

# Usage Instructions:
# Create a local bash script file Simply execute the command below or create a local bash script to do so
# curl -sL https://raw.githubusercontent.com/dpurnam/scripts/main/sannyas.wiki/media-downloader.sh | bash
# curl -sL https://raw.githubusercontent.com/dpurnam/scripts/main/sannyas.wiki/media-downloader.sh | bash -s "https://www.sannyas.wiki/index.php?title=Eagle%27s_Flight"
# curl -sL https://raw.githubusercontent.com/dpurnam/scripts/main/sannyas.wiki/media-downloader.sh | bash -s -- --file URLs.txt


# ANSI color codes
RED='\e[31m'
GREEN='\e[32m'
YELLOW='\e[93m'
BOLD='\e[1m'
ITALIC='\e[3m'
NC='\e[0m' # No Color

# Step 1: Get the Target URL from the user or command-line
if [ "$1" == "--file" ] && [ -n "$2" ]; then
    # Scenario: User provided a file with a list of URLs
    if [ -f "$2" ]; then
        readarray -t page_urls < "$2"
    else
        echo -e "${RED}Error: File '$2' not found.${NC}"
        exit 1
    fi
elif [ -n "$1" ]; then
    # Scenario: User provided a single URL
    page_urls=("$1")
else
    # Scenario: No arguments, prompt the user for a single URL
    read -p "Enter the sannyas.wiki URL to download from: " page_url  < /dev/tty
    if [ -n "$page_url" ]; then
        page_urls=("$page_url")
    else
        echo -e "${RED}Error: URL cannot be empty.${NC}"
        exit 1
    fi
fi

#if [ -z "$1" ]; then
#    read -p "Enter the sannyas.wiki URL to download from: " page_url
#else
#    page_url="$1"
#fi
#
## Exit if no URL is provided
#if [ -z "$page_url" ]; then
#    echo "Error: URL cannot be empty."
#    exit 1
#fi

for page_url in "${page_urls[@]}"; do
    echo ""
    echo -e "${BOLD}Processing URL: ${YELLOW}$page_url${NC}"

    # Step 2: Extract the title for the directory name and create it
    page_title=$(echo "$page_url" | sed 's/.*title=\([^&]*\).*/\1/' | sed 's/ /_/g')
    dir_name="${page_title}"

    mkdir -p "$dir_name"
    if [ $? -ne 0 ]; then
        echo "Error: Failed to create directory '$dir_name'."
        exit 1
    fi

    echo -e "Downloading files and images into directory: ${GREEN}${BOLD}$dir_name${NC}"

    # Step 3: Fetch the main page content to find all file links
    temp_source="temp_source.html"
    wget -q -O "$temp_source" "$page_url"

    # Check if wget was successful
    if [ $? -ne 0 ]; then
        echo -e "${RED}Error: Failed to fetch the URL. Please check the URL and your internet connection.${NC}"
        rm "$temp_source" 2>/dev/null
        exit 1
    fi

    echo -e "${YELLOW}Extracting file and image links from the main page...${NC}"

    # Step 4: Extract direct download URLs for audio files from the 'src' attribute
    # This is a one-step process for audio files, as you identified.
    grep -oE 'src="(https:\/\/www\.sannyas\.wiki//images/[^"]*\.(mp3|flac))"' "$temp_source" | sed 's/src="//;s/"//' | sort -u > direct_audio_urls.txt

    # Step 5: Extract file names from the 'a href' tags for images
    # This is the first step of the two-step process for images.
    grep -oE 'href="[^"]*title=File:([^"]*\.(jpg|jpeg|png|gif|pdf))"' "$temp_source" | sed 's/href="[^"]*title=//;s/"//' | sort -u > image_filenames.txt

    # Step 6: Process the extracted links

    # Process Audio Files
    if [ -s direct_audio_urls.txt ]; then
        echo ""
        echo "Found the following direct audio URLs to download:"
        cat direct_audio_urls.txt
        echo -e "${BOLD}-------------------------------------${NC}"
        echo -e "${YELLOW}Starting audio downloads with wget...${NC}"
        while IFS= read -r download_url; do
            filename=$(basename "$download_url" | sed 's/%20/ /g; s/%2C/,/g; s/%28/(/g; s/%29/)/g')
            echo "Downloading: $download_url"
            wget -q --show-progress -O "$dir_name/$filename" "$download_url"
            if [ $? -ne 0 ]; then
                echo -e "Warning: Failed to download ${RED}${BOLD}$filename${NC}. Skipping..."
            else
                echo -e "Successfully downloaded ${GREEN}${BOLD}$filename${NC}."
            fi
        done < direct_audio_urls.txt
    fi

    # Process Image Files
    if [ -s image_filenames.txt ]; then
        echo ""
        echo -e "${YELLOW}Found the following image file arguments to process${NC}:"
        cat image_filenames.txt
        echo -e "${BOLD}-------------------------------------${NC}"
        echo -e "${YELLOW}Starting image downloads with wget...${NC}"
        while IFS= read -r filename; do
            # [cite_start]Construct the Browse URL using the extracted filename, WITH the 'File:' prefix[cite: 9, 10, 11].
            browse_url="https://www.sannyas.wiki/index.php?title=${filename}"
            echo -e "Processing browse URL: ${YELLOW}$browse_url${NC}"

            # Fetch the browse URL and extract the actual download URL.
            # This is the key fix. The regex is now much more specific to avoid capturing multiple links.
            actual_path=$(wget -q -O - "$browse_url" | grep -oE 'div class="fullMedia".*href="([^"]*images/[^"]*\.(jpg|jpeg|png|gif|pdf))"' | sed 's/.*href="//;s/"//')

            if [ -z "$actual_path" ]; then
                echo -e "Warning: Could not find actual download path for ${RED}${BOLD}$filename${NC}. Skipping..."
                continue
            fi

            # Construct the final, absolute Download URL.
            download_url="https://www.sannyas.wiki${actual_path}"

            # Extract the clean filename from the actual download URL.
            filename_clean=$(basename "$download_url" | sed 's/%20/ /g; s/%2C/,/g')

            echo -e "Downloading: ${YELLOW}$download_url${NC}"

            # Download the file into the correct directory using wget.
            wget -q --show-progress -O "$dir_name/$filename_clean" "$download_url"
            if [ $? -ne 0 ]; then
                echo -e "Warning: Failed to download ${RED}${BOLD}$filename_clean${NC}. Skipping..."
            else
                echo -e "Successfully downloaded ${GREEN}${BOLD}$filename_clean${NC}."
            fi
        done < image_filenames.txt
    fi

    # Final check for files and clean up
    if [ ! -s direct_audio_urls.txt ] && [ ! -s image_filenames.txt ]; then
        echo -e "${RED}No files or images found on the page for ${BOLD}$dir_name${NC}."
        rmdir "$dir_name" 2>/dev/null
        exit 0
    elif [ -s direct_audio_urls.txt ] && [ ! -s image_filenames.txt ]; then
        echo -e "${BOLD}-------------------------------------${NC}"
        echo -e "${GREEN}Download process complete! All audio files were downloaded successfully for ${BOLD}$dir_name.${NC}${YELLOW}No image files found!${NC}"
    elif [ ! -s direct_audio_urls.txt ] && [ -s image_filenames.txt ]; then
        echo -e "${BOLD}-------------------------------------${NC}"
        echo -e "${GREEN}Download process complete! All image files were downloaded successfully for ${BOLD}$dir_name.${NC}${YELLOW}No audio files found!${NC}"
    else
        echo -e "${BOLD}-------------------------------------${NC}"
        echo -e "${GREEN}Download process complete! All files (audio and images) were downloaded successfully for ${BOLD}$dir_name.${NC}"
    fi
    echo ""
done
# Clean up temporary files
rm "$temp_source" direct_audio_urls.txt image_filenames.txt 2>/dev/null
