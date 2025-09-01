#!/bin/bash

# A bash script to download audio files and images from a sannyas.wiki page,

# Usage Instructions:
# To run the script without any arguments:
# bash <(curl -sL https://raw.githubusercontent.com/dpurnam/scripts/main/sannyas.wiki/media-downloader.sh)
#
# To run the script with a single URL argument:
# bash <(curl -sL https://raw.githubusercontent.com/dpurnam/scripts/main/sannyas.wiki/media-downloader.sh) "https://www.sannyas.wiki/index.php?title=Eagle%27s_Flight"
#
# To run the script with the --file argument and a file name:
# bash <(curl -sL https://raw.githubusercontent.com/dpurnam/scripts/main/sannyas.wiki/media-downloader.sh) --file "URLs.txt"

# ANSI color codes
RED='\e[31m'
GREEN='\e[32m'
YELLOW='\e[93m'
BOLD='\e[1m'
ITALIC='\e[3m'
NC='\e[0m' # No Color

# Function to clean up temporary files
cleanup() {
    rm "temp_source.html" "direct_audio_urls.txt" "image_filenames.txt" 2>/dev/null
}

# Function to download audio files from a temporary file list
download_audio_files() {
    local dir_name="$1"
    if [ -s direct_audio_urls.txt ]; then
        echo ""
        echo -e "🔍🎵 ${YELLOW}Found the following direct audio URLs to download${NC}:"
        echo -e "${BOLD}-------------------------------------${NC}"
        cat direct_audio_urls.txt
        echo -e "${BOLD}-------------------------------------${NC}"
        echo ""
        echo -e "${YELLOW}Starting 🎵 audio downloads with wget...${NC}"
        echo -e "${BOLD}-------------------------------------${NC}"
        while IFS= read -r download_url; do
            filename=$(basename "$download_url" | sed 's/%20/ /g; s/%2C/,/g; s/%28/(/g; s/%29/)/g')
            echo "⬇️🎵 Downloading: $download_url"
            wget -q --show-progress -O "$dir_name/$filename" "$download_url"
            if [ $? -ne 0 ]; then
                echo -e "Warning: Failed to download ${RED}$filename${NC}. Skipping..."
                echo ""
            else
                echo -e "✅🎵 Successfully downloaded ${GREEN}$filename${NC}."
                echo ""
            fi
        done < direct_audio_urls.txt
        echo -e "${BOLD}-------------------------------------${NC}"
    fi
}

# Function to download image files from a temporary file list
download_image_files() {
    local dir_name="$1"
    if [ -s image_filenames.txt ]; then
        echo ""
        echo -e "🔍 ${YELLOW}Found the following 🖼  image file arguments to process${NC}:"
        echo -e "${BOLD}-------------------------------------${NC}"
        cat image_filenames.txt
        echo -e "${BOLD}-------------------------------------${NC}"
        echo ""
        echo -e "${YELLOW}Starting 🖼  image downloads with wget...${NC}"
        echo -e "${BOLD}-------------------------------------${NC}"
        while IFS= read -r filename; do
            # [cite_start]Construct the Browse URL using the extracted filename, WITH the 'File:' prefix[cite: 9, 10, 11].
            browse_url="https://www.sannyas.wiki/index.php?title=${filename}"
            echo -e "🔁🖼  Processing image file's browse URL: ${YELLOW}$browse_url${NC}"
            # [cite_start]Fetch the browse URL and extract the actual download URL[cite: 12, 13].
            actual_path=$(wget -q -O - "$browse_url" | grep -oE 'div class="fullMedia".*href="([^"]*images/[^"]*\.(jpg|jpeg|png|gif|pdf))"' | sed 's/.*href="//;s/"//')

            if [ -z "$actual_path" ]; then
                echo -e "Warning: Could not find actual download path for ${RED}$filename${NC}. Skipping..."
                continue
            fi

            # [cite_start]Construct the final, absolute Download URL[cite: 14].
            download_url="https://www.sannyas.wiki${actual_path}"

            # Extract the clean filename from the actual download URL.
            filename_clean=$(basename "$download_url" | sed 's/%20/ /g; s/%2C/,/g')

            echo "⬇️🖼  Downloading: $download_url"

            # [cite_start]Download the file into the correct directory using wget[cite: 14].
            wget -q --show-progress -O "$dir_name/$filename_clean" "$download_url"
            if [ $? -ne 0 ]; then
                echo -e "Warning: Failed to download ${RED}$filename_clean${NC}. Skipping..."
                echo ""
            else
                echo -e "✅🖼  Successfully downloaded ${GREEN}$filename_clean${NC}."
                echo ""
            fi
        done < image_filenames.txt
        echo -e "${BOLD}-------------------------------------${NC}"
    fi
}

# Main function to handle the entire process for a given URL
process_url() {
    local page_url="$1"

    echo ""
    echo -e ">>>>>>>>>>>>>>>>>> 🔁 ${BOLD}Processing URL: ${YELLOW}$page_url${NC} <<<<<<<<<<<<<<<<<<"
    echo ""

    # [cite_start]Step 2: Extract the title for the directory name and create it[cite: 24, 25, 26].
    page_title=$(echo "$page_url" | sed 's/.*title=\([^&]*\).*/\1/' | sed 's/ /_/g')
    dir_name="${page_title}"

    mkdir -p "$dir_name"
    if [ $? -ne 0 ]; then
        echo -e "Error: Failed to create directory 📂 ${RED}'$dir_name'${NC}."
        exit 1
    fi

    echo -e "⬇️🎵🖼  Downloading audio and image files into directory: 📂 ${GREEN}${BOLD}$dir_name${NC}"

    # [cite_start]Step 3: Fetch the main page content to find all file links[cite: 27].
    local temp_source="temp_source.html"
    wget -q -O "$temp_source" "$page_url"

    # Check if wget was successful
    if [ $? -ne 0 ]; then
        echo -e "⛓️‍💥 ${RED}Error: Failed to fetch the URL. Please check the URL and your internet connection.${NC}"
        rm "$temp_source" 2>/dev/null
        exit 1
    fi

    echo -e "🔧 ${YELLOW}Extracting 🎵 audio and 🖼  image file links from the main page...${NC}"

    # [cite_start]Step 4: Extract direct download URLs for audio files from the 'src' attribute[cite: 28].
    # [cite_start]This is a one-step process for audio files, as you identified[cite: 5, 6].
    grep -oE 'src="(https:\/\/www\.sannyas\.wiki//images/[^"]*\.(mp3|flac))"' "$temp_source" | sed 's/src="//;s/"//' | sort -u > direct_audio_urls.txt

    # [cite_start]Step 5: Extract file names from the 'a href' tags for images[cite: 9, 29].
    grep -oE 'href="[^"]*title=File:([^"]*\.(jpg|jpeg|png|gif|pdf))"' "$temp_source" | sed 's/href="[^"]*title=//;s/"//' | sort -u > image_filenames.txt

    # [cite_start]Step 6: Process the extracted links[cite: 30, 34].
    download_audio_files "$dir_name"
    download_image_files "$dir_name"

    # [cite_start]Final check for files[cite: 45, 46, 47, 48].
    if [ ! -s direct_audio_urls.txt ] && [ ! -s image_filenames.txt ]; then
        echo -e ""
        echo -e ">>>>>>>>>>>>>>>>>> ${RED}👎🏻🎵🖼  No audio or image files found on the page for ${BOLD}$dir_name${NC}. <<<<<<<<<<<<<<<<<<"
        rmdir "$dir_name" 2>/dev/null
        exit 0
    elif [ -s direct_audio_urls.txt ] && [ ! -s image_filenames.txt ]; then
        echo -e ""
        echo -e ">>>>>>>>>>>>>>>>>> ${GREEN}👍🏻🎵 All audio files were downloaded successfully for ${BOLD}$dir_name. ${NC}${RED}No 🖼  image files found!${NC} <<<<<<<<<<<<<<<<<<"
    elif [ ! -s direct_audio_urls.txt ] && [ -s image_filenames.txt ]; then
        echo -e ""
        echo -e ">>>>>>>>>>>>>>>>>> ${GREEN}👍🏻🖼  All image files were downloaded successfully for ${BOLD}$dir_name. ${NC}${RED}No 🎵 audio files found!${NC} <<<<<<<<<<<<<<<<<<"
    else
        echo -e ""
        echo -e ">>>>>>>>>>>>>>>>>> ${GREEN}👍🏻🎵🖼  All audio and image files were downloaded successfully for ${BOLD}$dir_name.${NC} <<<<<<<<<<<<<<<<<<"
    fi
    echo ""
}

# [cite_start]Step 1: Get the Target URL from the user or command-line[cite: 17, 18, 19, 20, 21].
main() {
    # Set up trap to clean up temporary files on script exit
    trap cleanup EXIT
    
    local page_urls
    if [ "$1" == "--file" ] && [ -n "$2" ]; then
        if [ -f "$2" ]; then
            readarray -t page_urls < "$2"
        else
            echo -e "📝 ${RED}Error: File '$2' not found.${NC}"
            exit 1
        fi
    elif [ -n "$1" ]; then
        page_urls=("$1")
    else
        read -p "🔗 Enter the sannyas.wiki URL to download from: " page_url < /dev/tty
        if [ -n "$page_url" ]; then
            page_urls=("$page_url")
        else
            echo -e "🔗 ${RED}Error: URL cannot be empty.${NC}"
            exit 1
        fi
    fi

    for page_url in "${page_urls[@]}"; do
        process_url "$page_url"
    done
}

# Call the main function with all script arguments
echo ""
echo -e "${BOLD}========================================>> Sannyas.wiki Media Downloader ===============================================>>${NC}"
main "$@"
echo -e "${BOLD}<<======================================== Sannyas.wiki Media Downloader <<===============================================${NC}"
echo ""
