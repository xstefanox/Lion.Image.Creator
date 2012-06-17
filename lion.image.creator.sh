#!/bin/bash

###############
## CONSTANTS ##
###############

declare -r TMP_IMAGE_PATH="${HOME}/Desktop/lion.tmp.dmg"
declare -r FINAL_IMAGE_PATH="${HOME}/Desktop/mac_osx_10.7_lion.dmg"
declare -r COMPRESSION_LEVEL=9
declare -r ISO_IMAGE_BYTE_SIZE_DVD_R_SL=4707319808
declare -r ISO_IMAGE_BYTE_SIZE_DVD_R_PLUS_SL=4700372992
declare -r ISO_IMAGE_BYTE_SIZE_DVD_R_DL=8543666176
declare -r ISO_IMAGE_BYTE_SIZE_DVD_R_PLUS_DL=8547991552
declare -r DMG_SECTOR_BYTE_SIZE=512

##############
## DEFAULTS ##
##############

# set the combo size to empty; it will be overwritten if needed
combo_size=0

###############
## FUNCTIONS ##
###############

function usage()
{
    echo "Usage: $(basename $0) -p installer_path [ -c combo_update_path ]"
}

function error()
{
    echo "! $@"
}

function info()
{
    echo "# $@"
}

##########################
## COMMAND LINE PARSING ##
##########################

# show usage if no arguments given
if [[ -z $* ]]
then
    usage
    exit 1
fi

# parse arguments
while getopts "p:c:" opt
do
    case $opt in
        p) installer_path=$OPTARG ;;
        c) combo_path=$OPTARG ;;
        \?) exit 1 ;;
    esac
done

#####################
## ARGUMENTS CHECK ##
#####################

# check if the installer exists
if [[ -z "$installer_path" ]]
then
    error "Installer path is needed"
    usage
    exit 1
fi

# check if the installer is a directory
if [[ ! -d "$installer_path" ]]
then
    error "Invalid installer path"
    exit 1
fi

# if the combo path is defined
if [[ -n "$combo_path" ]]
then
    # check if the combo exists
    if [[ ! -f "$combo_path" ]]
    then
        error "Update '$combo_path' not found"
        exit 1
    fi
    
    # read the combo size
    combo_size=$(stat -f %z "$combo_path")
fi

###############
## EXECUTION ##
###############

info "Creating installer image ..."

# open the package containing the real installer
hdiutil attach -noverify -noautoopen -quiet "${installer_path}/Contents/SharedSupport/InstallESD.dmg"

# convert the base system package into a writable image
hdiutil convert -quiet "/Volumes/Mac OS X Install ESD/BaseSystem.dmg" -format UDRW -o "${TMP_IMAGE_PATH}"

# calculate the space needed for the installer and the packages
size=$(($(BLOCKSIZE=$DMG_SECTOR_BYTE_SIZE du -s "/Volumes/Mac OS X Install ESD/Packages" | sed 's:\([[:digit:]]*\).*:\1:') * $DMG_SECTOR_BYTE_SIZE + $(stat -f %z "${TMP_IMAGE_PATH}") + $combo_size))

# show a warning if the image is too big for a common DVD
[[ $size -gt $ISO_IMAGE_BYTE_SIZE_DVD_R_PLUS_SL ]] && echo "! Warning: the image size will not fit on a DVD+R SL"
[[ $size -gt $ISO_IMAGE_BYTE_SIZE_DVD_R_SL ]] && echo "! Warning: the image size will not fit on a DVD-R SL"
[[ $size -gt $ISO_IMAGE_BYTE_SIZE_DVD_R_DL ]] && echo "! Warning: the image size will not fit on a DVD-R DL"
[[ $size -gt $ISO_IMAGE_BYTE_SIZE_DVD_R_PLUS_DL ]] && echo "! Warning: the image size will not fit on a DVD+R DL"

# enlarge it to contain the packages
hdiutil resize -sectors $(($size / $DMG_SECTOR_BYTE_SIZE)) "${TMP_IMAGE_PATH}"

# mount the resulting image
hdiutil attach -noverify -noautoopen -quiet "${TMP_IMAGE_PATH}"

info "Copying packages ..."

# remove the packages symlink which is pointing to the OS filesystem
rm "/Volumes/Mac OS X Base System/System/Installation/Packages"

# copy the packages contained into the original installer into the final image
cp -r "/Volumes/Mac OS X Install ESD/Packages" "/Volumes/Mac OS X Base System/System/Installation" || exit 1

# copy the combo if needed
if [[ -n "$combo_path" ]]
then
    info "Copying combo update ..."
    cp -r "$combo_path" "/Volumes/Mac OS X Base System" || exit 1
fi

# eject our image
hdiutil eject -quiet "/Volumes/Mac OS X Base System"

# eject the original installer
hdiutil eject -quiet "/Volumes/Mac OS X Install ESD"

info "Compressing image ..."

# convert our installer image into a read-only image ready to be burned
hdiutil convert -quiet "${TMP_IMAGE_PATH}" -format UDZO -imagekey zlib-level="${COMPRESSION_LEVEL}" -o "${FINAL_IMAGE_PATH}"

# remove the temporary image
rm "${TMP_IMAGE_PATH}"

info "Done."
