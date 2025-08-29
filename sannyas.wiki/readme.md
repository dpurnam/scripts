# [sannyas.wiki](https://www.sannyas.wiki) Media Downloader

**Intro**:

Downloads media (audio/image files) from pre-defined or user provided page(s) from sannyas.wiki in to a new folder based on the title of the URL

**Usage**:

Create a local bash script file Simply execute the command below or create a local bash script to do so.

Use this to enter a sannyas.wiki page manually at a prompt
```bash
curl -sL https://raw.githubusercontent.com/dpurnam/scripts/main/sannyas.wiki/media-downloader.sh | bash
```
OR use this to provide a sannyas.wiki page in the command
```bash
curl -sL https://raw.githubusercontent.com/dpurnam/scripts/main/sannyas.wiki/media-downloader.sh | bash -s "https://www.sannyas.wiki/index.php?title=Eagle%27s_Flight"
```
OR use this to provide a file with multiple page URL's (one per line) from sannyas.wiki
```bash
curl -sL https://raw.githubusercontent.com/dpurnam/scripts/main/sannyas.wiki/media-downloader.sh | bash -s "--file" "URLs.txt"
```
