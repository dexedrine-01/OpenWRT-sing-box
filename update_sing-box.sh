#!/bin/sh
# Script for updating sing-box to the latest version with architecture detection

# Configuration
log_file="/var/log/sing-box-update.log"
install_dir="/usr/bin"
temp_dir="/opt/bin"
github_repo="SagerNet/sing-box"
backup_file="${install_dir}/sing-box.old"

# ANSI color codes
RED="\033[1;31m"
GREEN="\033[1;32m"
YELLOW="\033[1;33m"
BLUE="\033[1;34m"
RESET="\033[0m"

# Function for logging and displaying messages
log_msg() {
    local color="$1"
    local message="$2"
    # Using printf to avoid problems with echo -e
    printf "%b\n" "${color}${message}${RESET}" | tee -a "$log_file"
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to create required directories
create_dirs() {
    [ ! -d "$temp_dir" ] && mkdir -p "$temp_dir"
    [ ! -d "$(dirname "$log_file")" ] && mkdir -p "$(dirname "$log_file")"
}

# Function to check available disk space
check_disk_space() {
    local required_space=30000  # Required space in KB (approx 30MB)
    local install_path="${install_dir}"
    local temp_path="${temp_dir}"
    
    # Check space in installation directory
    local available_space_install
    available_space_install=$(df -k "$(dirname "$install_path")" | awk 'NR==2 {print $4}')
    
    # Check space in temporary directory
    local available_space_temp
    available_space_temp=$(df -k "$(dirname "$temp_path")" | awk 'NR==2 {print $4}')
    
    if [ -z "$available_space_install" ] || [ -z "$available_space_temp" ]; then
        log_msg "$YELLOW" "[!] Warning: Unable to check available space"
        return 0
    fi
    
    if [ "$available_space_install" -lt "$required_space" ]; then
        log_msg "$RED" "[✗] Error: Not enough space in $(dirname "$install_path")"
        log_msg "$RED" "    Available: $((available_space_install / 1024)) MB, required minimum: $((required_space / 1024)) MB"
        return 1
    fi
    
    if [ "$available_space_temp" -lt "$required_space" ]; then
        log_msg "$RED" "[✗] Error: Not enough space in temporary directory $(dirname "$temp_path")"
        log_msg "$RED" "    Available: $((available_space_temp / 1024)) MB, required minimum: $((required_space / 1024)) MB"
        return 1
    fi
    
    log_msg "$GREEN" "[✓] Sufficient free space for update"
    return 0
}

# Function to detect system architecture
detect_architecture() {
    arch=$(uname -m)
    case "$arch" in
        "x86_64")
            file="linux-amd64.tar.gz"
            ;;
        "armv7l")
            file="linux-armv7.tar.gz"
            ;;
        "armv6l")
            file="linux-armv6.tar.gz"
            ;;
        "aarch64")
            file="linux-arm64.tar.gz"
            ;;
        "i386"|"i686")
            file="linux-386.tar.gz"
            ;;
        "mips")
            file="linux-mips.tar.gz"
            ;;
        *)
            log_msg "$RED" "[✗] Error: Architecture $arch is not supported"
            exit 1
            ;;
    esac
    
    log_msg "$GREEN" "[✓] Supported architecture: $arch"
    return 0
}

# Function to rollback to the previous version
rollback() {
    log_msg "$YELLOW" "Rolling back to previous version..."
    
    if [ -f "$backup_file" ]; then
        mv "$backup_file" "${install_dir}/sing-box"
        chmod +x "${install_dir}/sing-box"
        
        if service sing-box restart 2>>"$log_file"; then
            log_msg "$GREEN" "[✓] Rollback completed successfully"
        else
            log_msg "$RED" "[✗] Error during rollback and restart of sing-box"
            exit 1
        fi
    else
        log_msg "$RED" "[✗] Previous version not found!"
        log_msg "$RED" "[✗] Manual installation of sing-box required"
        exit 1
    fi
}

# Function to get current sing-box version
get_current_version() {
    local current_version
    if command_exists sing-box; then
        current_version=$(sing-box version 2>/dev/null | head -n 1 | awk '{print $3}')
        if [ -z "$current_version" ]; then
            log_msg "$YELLOW" "[!] Unable to determine current sing-box version"
            current_version="unknown"
        fi
    else
        log_msg "$YELLOW" "[!] sing-box is not installed"
        current_version="not installed"
    fi
    
    echo "$current_version"
}

# Function to get the latest version based on release type
get_latest_version() {
    local version_type="$1"
    local version_url="https://api.github.com/repos/${github_repo}/releases"
    local latest_version=""
    
    case "$version_type" in
        "stable")
            version_url="${version_url}/latest"
            latest_version=$(curl -s "$version_url" | grep '"tag_name":' | cut -d '"' -f 4 | sed 's/v//')
            ;;
        "alpha")
            latest_version=$(curl -s "$version_url" | grep '"tag_name":' | grep -v "beta" | head -n 1 | cut -d '"' -f 4 | sed 's/v//')
            ;;
        "beta")
            latest_version=$(curl -s "$version_url" | grep '"tag_name":' | grep "beta" | head -n 1 | cut -d '"' -f 4 | sed 's/v//')
            ;;
    esac
    
    if [ -z "$latest_version" ]; then
        log_msg "$RED" "[✗] Error: Failed to get information about the latest version"
        exit 1
    fi
    
    echo "$latest_version"
}

# Function to remove old sing-box version
remove_old_version() {
    log_msg "$BLUE" "Removing old sing-box version..."
    
    # Stop service before removing
    if service sing-box stop 2>>"$log_file"; then
        log_msg "$GREEN" "[✓] sing-box service stopped"
    else
        log_msg "$YELLOW" "[!] Warning: Failed to stop sing-box service"
    fi
    
    # Remove old executable
    if [ -f "${install_dir}/sing-box" ]; then
        rm -f "${install_dir}/sing-box"
        log_msg "$GREEN" "[✓] Old sing-box version removed"
    else
        log_msg "$YELLOW" "[!] Warning: Old sing-box version not found"
    fi
}

# Function to check if the system is OpenWRT 24+
is_openwrt_24plus() {
    if [ -f /etc/openwrt_release ]; then
        . /etc/openwrt_release
        if [ -n "$DISTRIB_RELEASE" ]; then
            major=$(echo "$DISTRIB_RELEASE" | cut -d. -f1)
            if [ "$major" -ge 24 ]; then
                return 0
            fi
        fi
    fi
    return 1
}

# Function to get the name of the .ipk file for OpenWRT 24.10 based on architecture and CPU
get_openwrt_ipk_filename() {
    local arch=$(uname -m)
    local arch_list
    arch_list=$(opkg print-architecture 2>/dev/null | awk '{print $2}')
    local latest="${latest_version}"
    local found_file=""
    
    # For debugging, output available architectures
    log_msg "$BLUE" "System architecture: $arch"
    log_msg "$BLUE" "Supported architectures: $(echo "$arch_list" | tr '\n' ' ')"
    
    # Get list of all available release files
    local api_url="https://api.github.com/repos/${github_repo}/releases"
    log_msg "$BLUE" "Getting releases from: $api_url"
    local api_response
    api_response=$(curl -s "$api_url")
    
    # Check if API returned empty response
    if [ -z "$api_response" ]; then
        log_msg "$RED" "Error: GitHub API returned empty response" 
        exit 1
    fi
    
    log_msg "$BLUE" "Extracting .ipk files for version: ${latest}"
    local available_files
    available_files=$(echo "$api_response" | 
                     sed -n "s/.*browser_download_url.*\(sing-box_${latest}_openwrt_[^\"]*\.ipk\).*/\1/p")
    
    if [ -z "$available_files" ]; then
        log_msg "$RED" "[✗] Error: No .ipk files found in release"
        exit 1
    fi
    
    # Try to find a match for our architecture
    case "$arch" in
        "aarch64")
            # For aarch64 try to find matching variant
            for arch_variant in $(echo "$arch_list"); do
                if echo "$arch_variant" | grep -Fq "aarch64"; then
                    # Try direct match first
                    if echo "$available_files" | grep -Fq "sing-box_${latest}_openwrt_${arch_variant}.ipk"; then
                        found_file="sing-box_${latest}_openwrt_${arch_variant}.ipk"
                        break
                    fi
                fi
            done
            
            # If no direct match, try common aarch64 variants
            if [ -z "$found_file" ]; then
                for variant in aarch64_cortex-a53 aarch64_cortex-a72 aarch64_cortex-a76 aarch64_generic; do
                    if echo "$available_files" | grep -Fq "sing-box_${latest}_openwrt_${variant}.ipk"; then
                        found_file="sing-box_${latest}_openwrt_${variant}.ipk"
                        break
                    fi
                done
            fi
            ;;
        "x86_64")
            # Try to find x86_64 variant
            if echo "$available_files" | grep -Fq "sing-box_${latest}_openwrt_x86_64.ipk"; then
                found_file="sing-box_${latest}_openwrt_x86_64.ipk"
            fi
            ;;
        "i386"|"i686")
            # Try to find i386 variant
            for variant in i386_pentium-mmx i386_pentium4; do
                if echo "$available_files" | grep -Fq "sing-box_${latest}_openwrt_${variant}.ipk"; then
                    found_file="sing-box_${latest}_openwrt_${variant}.ipk"
                    break
                fi
            done
            ;;
        "armv7l"|"armv6l"|"arm")
            # Try to find arm variant
            for arch_variant in $(echo "$arch_list"); do
                if echo "$arch_variant" | grep -Fq "arm"; then
                    if echo "$available_files" | grep -Fq "sing-box_${latest}_openwrt_${arch_variant}.ipk"; then
                        found_file="sing-box_${latest}_openwrt_${arch_variant}.ipk"
                        break
                    fi
                fi
            done
            
            # If no direct match, try common arm variants
            if [ -z "$found_file" ]; then
                for variant in arm_cortex-a7_neon-vfpv4 arm_cortex-a9_vfpv3-d16 arm_cortex-a15_neon-vfpv4; do
                    if echo "$available_files" | grep -Fq "sing-box_${latest}_openwrt_${variant}.ipk"; then
                        found_file="sing-box_${latest}_openwrt_${variant}.ipk"
                        break
                    fi
                done
            fi
            ;;
        "mips"|"mipsel")
            # Try to find mips variant
            for arch_variant in $(echo "$arch_list"); do
                if echo "$arch_variant" | grep -Fq "mips"; then
                    if echo "$available_files" | grep -Fq "sing-box_${latest}_openwrt_${arch_variant}.ipk"; then
                        found_file="sing-box_${latest}_openwrt_${arch_variant}.ipk"
                        break
                    fi
                fi
            done
            ;;
        *)
            log_msg "$RED" "[✗] Error: Architecture $arch is not supported for OpenWRT"
            exit 1
            ;;
    esac
    
    # If we found a file, return it
    if [ -n "$found_file" ]; then
        log_msg "$GREEN" "[✓] Found suitable package: $found_file"
        echo "$found_file"
    else
        # If not found, let user select from available options
        log_msg "$YELLOW" "[!] Warning: Could not automatically determine package for your architecture"
        log_msg "$BLUE" "Available packages for your version:"
        
        # Display available packages with numbers
        i=1
        packages=""
        echo "$available_files" | while read -r file; do
            packages="$packages $file"
            echo "  $i) $file"
            i=$((i+1))
        done
        
        # Prompt user to select
        printf "Enter package number to install (1-%d): " $((i-1))
        read -r selection < /dev/tty
        
        # Преобразуем строку packages в позиционные параметры
        set -- $packages
        selected_package=$(eval "echo \${$selection}")
        
        if [ -n "$selected_package" ]; then
            log_msg "$GREEN" "[✓] Selected package: $selected_package"
            echo "$selected_package"
        else
            log_msg "$RED" "[✗] Error: Invalid selection"
            exit 1
        fi
    fi
}

# Function to download and install sing-box with detailed logging using curl
download_and_install() {
    local version_type="$1"
    local version_url="https://api.github.com/repos/${github_repo}/releases"
    local download_url=""

    if is_openwrt_24plus; then
        local ipk_filename
        ipk_filename=$(get_openwrt_ipk_filename)
        
        # Check if filename was successfully obtained
        if [ -z "$ipk_filename" ]; then
            log_msg "$RED" "[✗] Error: Failed to determine .ipk filename"
            exit 1
        fi
        
        download_url=$(curl -s "$version_url" | grep -F "browser_download_url" | grep -F "${ipk_filename}" | cut -d '"' -f 4 | head -n 1)
        if [ -z "$download_url" ]; then
            log_msg "$RED" "[✗] Error: Failed to find download link for $ipk_filename"
            exit 1
        fi
        log_msg "$BLUE" "Download link: $download_url"
        if ! curl -L -o "${temp_dir}/${ipk_filename}" "$download_url" --progress-bar 2>>"$log_file"; then
            log_msg "$RED" "[✗] Error: Failed to download file $ipk_filename"
            exit 1
        fi
        log_msg "$GREEN" "[✓] File $ipk_filename successfully downloaded"
        if [ -f "${temp_dir}/${ipk_filename}" ]; then
            # Local installation with opkg status capture
            opkg_output=$(opkg install --force-reinstall "${temp_dir}/${ipk_filename}" 2>&1)
            # Translate statuses to English and output with prefix
            echo "$opkg_output" | while IFS= read -r line; do
                case "$line" in
                    "Package * has no valid architecture, ignoring.")
                        log_msg "$YELLOW" "[!] Package does not support architecture, skipping."
                        ;;
                    "No packages removed.")
                        log_msg "$YELLOW" "[!] No packages were removed."
                        ;;
                    "Installing sing-box (*) to root..."*)
                        log_msg "$BLUE" "[→] Installing sing-box ($ipk_filename) into system..."
                        ;;
                    "Configuring sing-box.")
                        log_msg "$BLUE" "[→] Configuring sing-box."
                        ;;
                    *)
                        # For everything else, output as is, but with prefix
                        if [ -n "$line" ]; then
                            log_msg "$BLUE" "[i] $line"
                        fi
                        ;;
                esac
            done
        else
            log_msg "$RED" "[✗] Error: .ipk file not found at path ${temp_dir}/${ipk_filename}"
            exit 1
        fi
        return 0
    fi

    # If stable was selected, get the link to the latest release
    case "$version_type" in
        "stable")
            version_url="${version_url}/latest"
            ;;
    esac
    
    # Get link to file for our architecture
    download_url=$(curl -s "$version_url" | grep -F "browser_download_url" | grep -F "$file" | cut -d '"' -f 4 | head -n 1)
    if [ -z "$download_url" ]; then
        log_msg "$RED" "[✗] Error: Failed to find download link for architecture $arch"
        exit 1
    fi

    log_msg "$BLUE" "Download link: $download_url"

    # Get file size
    file_size=$(curl -sI "$download_url" | grep -i "Content-Length" | awk '{print $2}' | tr -d '\r')
    if [ -n "$file_size" ] && [ "$file_size" -gt 0 ] 2>/dev/null; then
        # If received valid size, output
        file_size_mb=$(echo "scale=2; $file_size/1048576" | bc 2>/dev/null || echo "$((file_size / 1048576))")
        log_msg "$BLUE" "File size for download: ${file_size_mb} MB"
    else
        # Otherwise skip size output
        file_size=""
    fi

    # Download file
    local filename
    filename=$(basename "$download_url")
    log_msg "$BLUE" "Starting file download: $filename"

    if command_exists curl; then
        if ! curl -L -o "${temp_dir}/${filename}" "$download_url" --progress-bar 2>>"$log_file"; then
            log_msg "$RED" "[✗] Error: Failed to download file $filename"
            exit 1
        fi
    else
        log_msg "$RED" "[✗] Error: curl is not installed"
        exit 1
    fi
    
    log_msg "$GREEN" "[✓] File $filename successfully downloaded"

    # Check integrity (by size), if Content-Length is not zero
    if [ -f "${temp_dir}/${filename}" ]; then
        downloaded_size=$(wc -c < "${temp_dir}/${filename}")
        if [ -n "$file_size" ] && [ "$file_size" -gt 0 ]; then
            if [ "$downloaded_size" -ne "$file_size" ]; then
                log_msg "$RED" "[✗] Error: Downloaded file size does not match expected"
                log_msg "$RED" "    Expected size: $file_size bytes, actual: $downloaded_size bytes"
                exit 1
            fi
        fi
    else
        log_msg "$RED" "[✗] Error: File was not downloaded"
        exit 1
    fi

    # Unpacking
    log_msg "$BLUE" "Unpacking archive..."
    local folder_name
    folder_name=$(tar -tzf "${temp_dir}/${filename}" 2>>"$log_file" | head -1 | cut -f1 -d"/")
    if [ -z "$folder_name" ]; then
        log_msg "$RED" "[✗] Error: Failed to determine folder name in archive"
        exit 1
    fi
    
    if ! tar -xzf "${temp_dir}/${filename}" -C "$temp_dir" 2>>"$log_file"; then
        log_msg "$RED" "[✗] Error unpacking archive"
        exit 1
    fi

    # Install new version
    log_msg "$BLUE" "Installing new version..."
    if [ ! -f "${temp_dir}/${folder_name}/sing-box" ]; then
        log_msg "$RED" "[✗] Error: sing-box executable not found in unpacked archive"
        exit 1
    fi
    
    cp "${temp_dir}/${folder_name}/sing-box" "${install_dir}/"
    chmod +x "${install_dir}/sing-box"

    # Check that executable is in place
    if [ ! -x "${install_dir}/sing-box" ]; then
        log_msg "$RED" "[✗] Error: Failed to install new sing-box version"
        log_msg "$RED" "[✗] Manual installation of sing-box required"
        exit 1
    fi

    # Clean up temporary files
    log_msg "$BLUE" "Cleaning up temporary files..."
    rm -rf "${temp_dir:?}/${folder_name}" "${temp_dir}/${filename}"
    
    return 0
}

# Function to restart services
restart_services() {
    log_msg "$BLUE" "Restarting services..."
    
    # First restart network
    if ! service network restart 2>>"$log_file"; then
        log_msg "$YELLOW" "[!] Warning: Error restarting network"
        log_msg "$YELLOW" "[!] Manual network restart recommended"
    else
        log_msg "$GREEN" "[✓] Network successfully restarted"
    fi
    
    # Small pause to allow network to come up
    sleep 2
    
    # Then restart sing-box
    if ! service sing-box restart 2>>"$log_file"; then
        log_msg "$RED" "[✗] Error restarting sing-box service"
        return 1
    fi
    
    log_msg "$GREEN" "[✓] sing-box service successfully restarted"
    return 0
}

# Function to check available memory
check_memory() {
    local required_memory=20000  # Required memory in KB (approx 20MB)
    local available_memory=0

    if [ -f "/proc/meminfo" ]; then
        available_memory=$(grep -i 'MemAvailable' /proc/meminfo | awk '{print $2}')
        if [ -z "$available_memory" ]; then
            local mem_free
            local buffers
            local cached
            mem_free=$(grep -i 'MemFree' /proc/meminfo | awk '{print $2}')
            buffers=$(grep -i 'Buffers' /proc/meminfo | awk '{print $2}')
            cached=$(grep -i 'Cached' /proc/meminfo | awk '{print $2}' | head -1)
            if [ -n "$mem_free" ] && [ -n "$buffers" ] && [ -n "$cached" ]; then
                available_memory=$((mem_free + buffers + cached))
            fi
        fi
    fi
    
    # If unable to check via /proc/meminfo, try using free
    if [ -z "$available_memory" ] || [ "$available_memory" -eq 0 ]; then
        if command_exists free; then
            available_memory=$(free | grep -i 'Mem:' | awk '{print $7}')
        fi
    fi
    
    if [ -z "$available_memory" ] || [ "$available_memory" -eq 0 ]; then
        log_msg "$YELLOW" "[!] Warning: Unable to check available memory"
        return 0
    fi
    
    if [ "$available_memory" -lt "$required_memory" ]; then
        log_msg "$RED" "[✗] Error: Not enough RAM for update"
        log_msg "$RED" "    Available: $((available_memory / 1024)) MB, required minimum: $((required_memory / 1024)) MB"
        return 1
    fi
    
    log_msg "$GREEN" "[✓] Sufficient RAM for update"
    return 0
}

# Main function
main() {
    create_dirs
    
    # If rollback parameter, do rollback
    if [ "$1" = "rollback" ]; then
        rollback
        exit 0
    fi
    
    # Determine architecture
    detect_architecture
    
    # Version type selection menu
    printf "Select version type:\n"
    printf "1. Release (stable)\n"
    printf "2. Alpha (alpha)\n"
    printf "3. Beta (beta)\n"
    printf "Enter your choice (1, 2, 3): "
    read choice < /dev/tty
    
    local version_type
    case "$choice" in
        1)
            version_type="stable"
            log_msg "$BLUE" "You selected release version"
            ;;
        2)
            version_type="alpha"
            log_msg "$BLUE" "You selected alpha version"
            ;;
        3)
            version_type="beta"
            log_msg "$BLUE" "You selected beta version"
            ;;
        *)
            log_msg "$RED" "[✗] Error: Invalid choice. Please select 1, 2, or 3."
            exit 1
            ;;
    esac
    
    # Current and latest version
    local current_version
    current_version=$(get_current_version)
    local latest_version
    latest_version=$(get_latest_version "$version_type")
    
    # Check if installation is needed
    if [ "$current_version" = "$latest_version" ]; then
        log_msg "$GREEN" "[✓] Latest version already installed: $current_version"
        exit 0
    fi
    
    log_msg "$BLUE" "Updating from version $current_version to $latest_version"
    
    # Stop service before removal
    if service sing-box stop 2>>"$log_file"; then
        log_msg "$GREEN" "[✓] sing-box service stopped"
    else
        log_msg "$YELLOW" "[!] Warning: Failed to stop sing-box service"
    fi
    
    # Remove old version
    if [ -f "${install_dir}/sing-box" ]; then
        # Create backup before removal
        cp "${install_dir}/sing-box" "${backup_file}"
        rm -f "${install_dir}/sing-box"
        log_msg "$GREEN" "[✓] Old sing-box version removed and backed up"
    else
        log_msg "$YELLOW" "[!] Warning: Old sing-box version not found"
    fi
    
    # Check available space
    if ! check_disk_space; then
        log_msg "$RED" "[✗] Update canceled due to insufficient disk space"
        exit 1
    fi
    
    # Check memory
    if ! check_memory; then
        log_msg "$RED" "[✗] Update canceled due to insufficient memory"
        exit 1
    fi
    
    # Download and install
    download_and_install "$version_type"
    
    # Restart services
    if ! restart_services; then
        log_msg "$RED" "[✗] Error during update. Performing rollback..."
        rollback
        exit 1
    fi
    
    log_msg "$GREEN" "[✓] Update completed successfully to version $latest_version"
    exit 0
}

# Run main function
main "$@"