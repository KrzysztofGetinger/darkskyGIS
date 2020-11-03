#!/bin/bash
#====================================================================================
# 	
#	 FILE: projecting_DNB.sh
#
#	USAGE: ./projecting_DNB.sh
#
# DESCRIPTION: projecting VIIRS DNB imagery to a given CRS by EPSG, saving as GTiff
#
#      AUTHOR: Krzysztof Getinger, krzysztof.getinger@gmail.com
#
#====================================================================================

#Usage
PROGRAM=$0

function usage {
	echo -e "usage: $PROGRAM [input] [epsg_code] [output]\n"
	echo "	input - HDF VIIRS DNB input dataset path" 
	echo "	epsg_code - CRS of output GTiff, only EPSG code number, supporting only projected coordinate systems in meters"
	echo -e "	output - GTiff output dataset path\n"
	echo -e "Example:\n"
	echo -e "$ ./projecting_DNB GDNBO-SVDNB_j01_d20190403_t0007122_e0012522_b07103_c20200511165707163969_noac_ops.h5 32634 viirs_dnb_central_europe_20190403.tif\n"
}


if [[ ( $1 == "--help") || ( $1 == "-h" ) || ( $# -eq 0 ) ]];
	then 
	usage
	exit 1
fi	

#====================================================================================



#Assigning arguments to variables 
INPUT_DATASET=$1
OUTPUT_EPSG=$2
OUTPUT_DATA=$3


#Using common linux tools and gdalinfo to get subdatasets' names
export INPUT_DATA=$(gdalinfo $INPUT_DATASET | grep Radiance | grep NAME | \
	awk -F = '{print $2}')
export LATITUDES=$(gdalinfo $INPUT_DATASET | grep Latitude_TC | grep NAME | \
	awk -F = '{print $2}')
export LONGITUDES=$(gdalinfo $INPUT_DATASET | grep Longitude_TC | grep NAME | \
	awk -F = '{print $2}')


#Converting HDF dataset into temporary Geotiff and assinging 0 as ignore-value
gdal_translate -of GTiff -a_nodata 0 $INPUT_DATA dnb_tmpfile.tif

#Converting temporary Geotiff into a temporary virtual raster
gdal_translate -of VRT dnb_tmpfile.tif dnb_tmpfile.vrt

#Removing last line of .vrt file that closes metadata description
sed -i '$ d' dnb_tmpfile.vrt

#Inserting lat and lon information into .vrt file and closing metadata description
echo -e '<Metadata domain="GEOLOCATION">\n
<MDI key="X_DATASET">'$LONGITUDES'</MDI>\n
<MDI key="X_BAND">1</MDI>\n
<MDI key="Y_DATASET">'$LATITUDES'</MDI>\n
<MDI key="Y_BAND">1</MDI>\n
<MDI key="PIXEL_OFFSET">0</MDI>\n
<MDI key="LINE_OFFSET">0</MDI>\n
<MDI key="PIXEL_STEP">1</MDI>\n
<MDI key="LINE_STEP">1</MDI>\n
</Metadata>\n</VRTDataset>' >> dnb_tmpfile.vrt

#Projecting temporary a virtual raster into final dataset with a given CRS
gdalwarp -s_srs EPSG:4326 -t_srs EPSG:$OUTPUT_EPSG -tr 750 750 -r near -geoloc \
	dnb_tmpfile.vrt $OUTPUT_DATA

#Cleaning up temporary files
rm -f dnb_tmpfile.tif
rm -f dnb_tmpfile.vrt
