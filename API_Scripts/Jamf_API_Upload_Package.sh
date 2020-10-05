#!/bin/sh

## This script is designed to check if a Package exists on a Jamf Pro Server and
## if not to upload a new one.
## Package data can be uploaded by id to the following endpoint:
## /JSSResource/packages/id/0
## Actual packages can be uploaded to the following endpoing:
## /dbfileupload

##Any references to the JSS are due to historical reasons but JSS = Jamf Pro Server

### When using the XML downloaded from the JSS we must strip the ID tags from the package
## and any categories associated with the package. We also must make sure any associated
## categories exist in the JSS first.

## Define Global Variables

## apiParms should be a path to a script that exports API user name and password so 
## they don't have to be entered on the command line.
## Script should be in a format like the next 4 lines:
## #!/bin/bash
##
## apiUser=''
## apiPass=''
apiParams=""

## If not using a script or file to set the user name or password define variables to get them from stdin
## JAMF Pro User with privileges to update the corresponding API endpoints
apiUser=""
## Password for the user specified
apiPass="" 

##Get API variables.

## If the file containing the appropriate API Parameters does not exist or has a size
## of zero bytes then prompt the user for the necessary credentials.

if [ ! -s "$apiParams" ]
   then
      read -r -p "Please enter a JAMF API administrator name: " apiUser
      read -r -s -p "Please enter the password for the account: " apiPass
   else
      ## Run the script found specified in apiParms to populate the variables
      ## Use dot notation so it says within the same process
     . "$apiParams"
fi

## ARGV $1 is the list of JAMF instances.
## This instance name file MUST end with one blank lime otherwise errors in processing will occuur.
## The file CANNOT contain windows line breaks otherwise sadness will happen.

if [ "$1" == "" ]
then
InstanceList="PATH TO Instance File"
else
InstanceList="$1"
fi

## The path to a local package we want to upload
PackageLocation=""

## If variable containing the path to the package does exists or does not have a size of 0 bytes
## prompt the user for the local path of the package to upload to the Jamf server
if [ ! -s "$PackageLocation" ]
   then
      read -r -p "Please enter the path to the package you wish to upload: " PackageLocation
fi

## Extract the file name from the package
PackageName=$(basename $PackageLocation)
echo "Uploading $PackageName to Jamf."

## The human readbale name of the package in Jamf
## Would not recommend changing in some environements as this can cause DP resyncs to occur
#DisplayName=""

## Text for the info field for the package
#Info="This package does......&#13;
#Designed to be run....."

## Text for the Notes field for the script
#Notes="Additional Package&#13;
#Information"

## Priority level of the package. A number between 1 and 10.
## If not assigned default is 10
#Priority=""

## The category the package should be assigned to in Jamf
## !! The category must exist on the Jamf server first !!
#Category=""

## Use a here block to Create an xslt template file that is used to format the XML
## outputted from the JSS to our standards in this case it will be used to produce
## a list of all the names of the Packages in the JSS.
## We'll first match the top element of the list of Packages returned from the JSS
## which is packages. Then from each child element (package)
## we'll select the value of the name attribute and then add a line break. 

cat <<EOF > /tmp/JSS_template.xslt
<?xml version="1.0" encoding="ISO-8859-1"?>
<xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
<xsl:output method="text"/>
<xsl:template match="/packages"> <!-- Start a search -->
            <xsl:for-each select="package"> 
            <xsl:value-of select="name"/> <!-- Find the value of a tag -->
            <xsl:text>&#xa;</xsl:text> <!-- Insert a line break into the output -->
</xsl:for-each>
</xsl:template> <!-- Close the template -->
</xsl:stylesheet>
EOF

###Just echo a blank line for readability
echo ""

while read instanceName
do

## Translate the instance name to all lower case to prevent any processing errors in the shell
instanceName=$(echo "$instanceName" | tr '[:upper:]' '[:lower:]')

## Check an instances's header codes to see if it is actually up. If curl returns any header information
## we assume the instance is up if not we assume the instance is down. We use the silent option to express
## any extraneous curl output and pipe the results to only return the first line of the head so it can fit in a variable neatly
InstanceExists=$(curl --silent --head "$instanceName" | head -n 1)

if [ "$InstanceExists" != "" ]
then

JSSResource="$instanceName/JSSResource"

## Strip the company name from the instance using // and - as field separators and
## return the 2 field which in the JSS Instance URL will be the company name.
## This will be used for logging purposes if necessary.
CompanyName=$(echo $JSSResource | awk -F "//|-" '{print $2}')

## Using curl with the silent option to suppress extraneous output we'll
## output the full list of packages from the JSS to a file.
## The list of Packages can be found at the /packages endpoint
## We must use accept on the header since we are using a GET request 
## AND we want the JAMF Server to return an XML output. 

curl \
-k \
-s \
-u "$apiUser":"$apiPass" \
-H "accept: text/xml" \
"$JSSResource/packages" \
-X GET > /tmp/JSS_output.xml

## Since outputting the list of packages to a file just dumps the raw XML to the file
## it contains information that we might not want such as id number and other XML attributes.
## It also contains no formatting so using xsltproc we apply the template we created earlier
## and then output the formatted XML (which in this case is just the names of all the packages)
## to a text file.

xsltproc /tmp/JSS_template.xslt /tmp/JSS_output.xml > /tmp/JSS_packagelist.txt

## Read in the previous text file line by line to see if it contains the name of the package
## we want to add. We check for a positive match one time only to avoid continual iterations of the
## loop to cause negative values to be reported. This is expected behavior but would throw off the results. 

while read name
do
if [ "$name" == "$PackageName" ]
then
PackageFound="Yes"
fi
done < /tmp/JSS_packagelist.txt

## If a positive match is never found then it means the package we want to create does not already exist
## so using curl we can POST a new package to the JSS instance. We send it to the 0 endpoint since this allows
## the JSS to create it at the next available slot. Also since we are sending the curl command the location of an XML
## file in order to create the group we use the -T switch. If we were using just XML data or a variable with XML in
## it we would use the -d switch.

if [ "$PackageFound" != "Yes" ]
then
CurlOutput=$(curl -s -u "$apiUser":"$apiPass" -X POST $instanceName/dbfileupload \
-H "DESTINATION: 0" -H "OBJECT_ID: -1" -H "FILE_TYPE: 0" -H "FILE_NAME: $PackageName" -T "$PackageLocation")

Packageid=$(echo $CurlOutput | awk -F "<id>|</id>" '{print $2}')

if [ "$DisplayName" != "" ]
then
curl \
-s \
-k \
-u "$apiUser":"$apiPass" \
-H "Content-type: text/xml" \
$JSSResource/packages/id/$Packageid \
-d "<package><name>$DisplayName</name></package>" \
-X PUT
fi

if [ "$Info" != "" ]
then
curl \
-s \
-k \
-u "$apiUser":"$apiPass" \
-H "Content-type: text/xml" \
$JSSResource/packages/id/$Packageid \
-d "<package><info>$Info</info></package>" \
-X PUT
fi

if [ "$Notes" != "" ]
then
curl \
-s \
-k \
-u "$apiUser":"$apiPass" \
-H "Content-type: text/xml" \
$JSSResource/packages/id/$Packageid \
-d "<package><notes>$Notes</notes></package>" \
-X PUT
fi

if [ "$Category" != "" ]
then
curl \
-s \
-k \
-u "$apiUser":"$apiPass" \
-H "Content-type: text/xml" \
$JSSResource/packages/id/$Packageid \
-d "<package><category>$Category</category></package>" \
-X PUT
fi

if [ "$Priority" != "" ]
then
curl \
-s \
-k \
-u "$apiUser":"$apiPass" \
-H "Content-type: text/xml" \
$JSSResource/packages/id/$Packageid \
-d "<package><priority>$Priority</priority></package>" \
-X PUT
fi

## Use printf (more reliable than echo) to insert a mew line after the curl statement for readability because
## bash will prob put the following echo command on the same line as the curl output
printf "\n"
echo "Package:$PackageName Created for $CompanyName"
echo ""
else
echo "Package: *$PackageName* already exists for $CompanyName" 
echo ""
fi

## Clean up temp files and variables after each iteration of the loop.
## While a new file will be created on each iteration it doesn't 
## hurt to be careful and this will handle the last iteration.

rm /tmp/JSS_packagelist.txt
rm /tmp/JSS_output.xml
PackageFound=""

# End instance exists if statement
else
	echo "$instanceName"
	echo "Instance is currently unreachable."
	echo ""

fi

done < "$InstanceList"

rm /tmp/JSS*
