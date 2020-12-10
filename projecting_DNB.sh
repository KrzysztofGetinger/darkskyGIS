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

#Declaring the number of mandatory args
margs=3

function example {
	echo -e "Projecting DNB example:\n"
	echo -e "$ ./projecting_DNB [options] -in GDNBO-SVDNB_j01_d20190403_t0007122_e0012522_b07103_c20200511165707163969_noac_ops.h5 -e 32634 -out viirs_dnb_central_europe_20190403.tif\n"
}

#Usage
PROGRAM=$0

function usage {
	echo -e "usage: $PROGRAM [input] [epsg_code] [output]\n"
	echo "	-in|--input; input file - HDF VIIRS DNB input dataset path" 
	echo "	-e|--epsg; epsg_code - CRS of output GTiff, only EPSG code number, supporting only projected coordinate systems in meters"
	echo -e "-out|--output; output file - GTiff output dataset path\n"
	echo -e "-t|--twilight_mask; use twilight mask; masks out pixels lighted indirectly by the Sun under the horizon\n"
	echo -e "Example:\n"
	echo -e "$ ./projecting_DNB -in GDNBO-SVDNB_j01_d20190403_t0007122_e0012522_b07103_c20200511165707163969_noac_ops.h5 -e 32634 -out viirs_dnb_central_europe_20190403.tif\n"
}

function margs_precheck {
	if [ $2 ] && [ $1 -lt $margs ]; then
		if [ $2 == "--help" ] || [ $2 == "-h" ]; then
			usage
			exit
		else
	    	example
			    	exit 1 # error
		fi
	fi
}


function margs_check {
	if [ $# -lt $margs ]; then
	  	example
	    exit 1 # error
	fi
}

margs_precheck $# $1

#Declaring arguments
infile=
outfile=
epsg=
twilight_mask="false"

# Args while-loop
while [ "$1" != "" ];
do
   case $1 in
   -in  | --input )  shift
                     infile=$1
  	           		  ;;
   -out  | --output )  shift
   		     outfile=$1
			          ;;
   -e  | --epsg  )  shift
	   	      epsg=$1
                          	  ;;
   -t  | --twilight_mask  ) twilight_mask="true"
                          ;;
   -h   | --help )        usage
                          exit
                          ;;
   *)                     
                          echo "$script: illegal option $1"
                          example
						  
				 exit 1 # error
                          ;;
    esac
    shift
done

# Pass here your mandatory args for check
margs_check $infile $outfile $epsg 

#====================================================================================

#Assigning arguments to variables 
INPUT_DATASET=$infile
OUTPUT_EPSG=$epsg
OUTPUT_DATA=$outfile

#Using common linux tools and gdalinfo to get subdatasets' names
export INPUT_DATA=$(gdalinfo $INPUT_DATASET | grep Radiance | grep NAME | \
	awk -F = '{print $2}')
export LATITUDES=$(gdalinfo $INPUT_DATASET | grep Latitude_TC | grep NAME | \
	awk -F = '{print $2}')
export LONGITUDES=$(gdalinfo $INPUT_DATASET | grep Longitude_TC | grep NAME | \
	awk -F = '{print $2}')

#Converting HDF Radiance subdataset into temporary Geotiff and assinging 0 as ignore-value
gdal_translate -of GTiff -a_nodata 0 $INPUT_DATA dnb_tmpfile.tif

#Masking out pixels lighted indirectly by the Sun under the horizon if wanted
if [ $twilight_mask == "true" ] ; then
       	echo "Using twilight mask"
	#Adding solar zenith data
	export SOLAR_ZENITH=$(gdalinfo $INPUT_DATASET | grep SolarZenith | grep NAME | \
        								awk -F  = '{print $2}')	
	gdal_translate -of GTiff -a_nodata 0 $SOLAR_ZENITH solar_tmpfile.tif
	gdal_calc.py -A solar_tmpfile.tif --calc="A>=108" --format=GTiff --outfile=solar_mask.tif --quiet
	gdal_calc.py -A solar_mask.tif -B dnb_tmpfile.tif --calc="A*B" --format=GTiff --outfile=dnb_tmpfile.tif --quiet --overwrite
fi

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
