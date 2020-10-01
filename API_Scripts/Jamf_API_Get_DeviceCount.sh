#!/bin/sh

## This script is designed to report the amount of Macs and iOS Devices on a JAMF
## instance, the total amount of devices on an instance, and the total number of devices 
## across all instances.
## The amount of computers in an instance can be found at the following endpoint:
## /JSSResource/computers/size
## The amount of mobile devices in an instance can be found at the following endpoint:
## /JSSResource/computers/mobile_devices
## This script differentiates between managed and unmanaged devices for licensing purposes

##Any references to the JSS are due to historical reasons but JSS = Jamf Pro Server

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
## JAMF Pro User with privileges to read the corresponding API endpoints
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

## File to output the results
OutputFile=""

## Initialize counter Variables for computers and mobile devices
## All are defined with let just to make sure arithmetic 
## operations don't report any errors.
## Computer and mobile devices count for each instance
let InstanceComputers="0"
let InstanceMobile="0"
## Computer and mobile devices managed/unmanaged count for each instance
let InstanceComputersManged="0"
let InstanceMobileManged="0"
let InstanceComputersUnManaged="0"
let InstanceMobileUnManaged="0"
let InstanceManaged="0"
## Total device count for an instance
let TotalInstance="0"
#
## Total Managed devices across all instances
let TotalManaged="0"
## Total number of computers across all instances
let TotalComputers="0"
## Total number of mobile devices across all instances
let TotalMobile="0"
## Total number of devices across all instances.
let TotalDevices="0"
##Total JAMF Instances in use
let TotalJamfInstances="0"

## ARGV $1 is the list of JAMF instances.
## This instance name file MUST end with one blank lime otherwise errors in processing will occur.
## The file CANNOT contain windows line breaks otherwise sadness will happen.

if [ "$1" == "" ]
then
InstanceList="PATH TO Instance File"
else
InstanceList="$1"
fi

## Use a here block to create an xslt template file that is used to format the XML
## that will be outputted from the JSS to our standards.
## In this case we will be using two.
## One that will be used to return the value of the size value from the computers attribute
## and another that will return the size value from the mobile_devices attribute.
## These values correspond to the amount of devices in each instance. 

## We'll first match the top element of the list of computers returned from the JSS
## which is computers. Then from each child element size we'll select its value.
## Then we create another template to do the same but this time matching mobile_devices 

cat <<EOF > /tmp/JSS_ComputerTemplate.xslt
<?xml version="1.0" encoding="ISO-8859-1"?>
<xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
<xsl:output method="text"/>
<xsl:template match="/computers"> <!-- Start a search -->
			<xsl:for-each select="computer">
            <xsl:value-of select="id"/> <!-- Find the value of a tag -->
            <xsl:text>&#xa;</xsl:text> <!-- Insert a line break into the output -->
</xsl:for-each>
</xsl:template> <!-- Close the template -->
</xsl:stylesheet>
EOF

cat <<EOF > /tmp/JSS_MobileTemplate.xslt
<?xml version="1.0" encoding="ISO-8859-1"?>
<xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
<xsl:output method="text"/>
<xsl:template match="/mobile_devices"> <!-- Start a search -->
            <xsl:for-each select="mobile_device"> 
            <xsl:value-of select="managed"/> <!-- Find the value of a tag -->
            <xsl:text>&#xa;</xsl:text> <!-- Insert a line break into the output -->
</xsl:for-each>
</xsl:template> <!-- Close the template -->
</xsl:stylesheet>
EOF

###To use as a CSV Comment out the following 2 echo statements and uncomment the line after ## CSV HEADER
## Write a header  to our output file.
#echo "JAMF INSTANCE OVERVIEW" >> "$OutputFile"

###Just echo a blank line for readability
#echo "" >> "$OutputFile"

## CSV HEADER
echo "server,total_computers,managed_computers,unmanged_computers,total_mobile_devices,managed_devices,unmanaged_mobile_devices" >> "$OutputFile"

## While loop to read through the JAMF instances in the file specified on the command line.
while read instanceName
do

## Translate the instance name to all lower case to prevent any processing errors in the shell
instanceName=$(echo "$instanceName" | tr '[:upper:]' '[:lower:]')

## Check an instances's header codes to see if it is actually up. If curl returns any header information
## we assume the instance is up if not we assume the instance is down. We use the silent option to suppress
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
## output the full list of computers from the JSS to a file.
## The list of computers can be found at the /computers endpoint 
## We must use accept on the header since we are using a GET request 
## AND we want the JAMF Server to return an XML output.
curl \
-k \
-s \
-u "$apiUser":"$apiPass" \
-H "accept: text/xml" \
"$JSSResource/computers" \
-X GET > /tmp/JSS_ComputerOutput.xml

## We apply the Computer Template we created earlier to the file containing computer information we
## just created in order to only extract the information about the computers we need. 
xsltproc /tmp/JSS_ComputerTemplate.xslt /tmp/JSS_ComputerOutput.xml > /tmp/JSS_ComputerID.txt

## We use a while loop to read through the file we just created looking at each computer record to see if a computer is managed.
## If it is managed we add 1 to the InstancesComputersManaged variable.
## If if is not managed we assume it is unmanaged and add one to the InstancesComputersUnManaged variable.

while read id
do
ComputerManaged=$(curl -X GET -H "accept: text/xml" -s -k -u "$apiUser:$apiPass" "$JSSResource/computers/id/$id" | xmllint --xpath xmllint --xpath '/computer/general/remote_management/managed/text()' - )
if [ "$ComputerManaged" == "true" ]
then
InstanceComputersManged=$((InstanceComputersManged+1))
else
InstanceComputersUnManaged=$((InstanceComputersUnManaged+1))
fi
done < /tmp/JSS_ComputerID.txt

## Using curl with the silent option to suppress extraneous output we'll
## output the full list of mobile devices from the JSS to a file.
## The list of computers can be found at the /mobiledevices endpoint 
## We must use accept on the header since we are using a GET request 
## AND we want the JAMF Server to return an XML output.
curl \
-k \
-s \
-u "$apiUser":"$apiPass" \
-H "accept: text/xml" \
"$JSSResource/mobiledevices" \
-X GET > /tmp/JSS_MobileOutput.xml

## We apply the Mobile Template we created earlier to the file containing mobile device information we
## just created in order to only extract the information about the mobile devices we need. 
xsltproc /tmp/JSS_MobileTemplate.xslt /tmp/JSS_MobileOutput.xml > /tmp/JSS_MobileCount.txt

## We use a while loop to read through the file we just created looking at each mobile device record to see if a computer is managed.
## If it is managed we add 1 to the InstancesMobileManaged variable.
## If if is not managed we assume it is unmanaged and add one to the InstancesMobileUnManaged variable.

while read MobileManaged
do
if [ "$MobileManaged" == "true" ]
then
InstanceMobileManged=$((InstanceMobileManged+1))
else
InstanceMobileUnManaged=$((InstanceMobileUnManaged+1))
fi
done < /tmp/JSS_MobileCount.txt

## Variable Addition
InstanceComputers=$((InstanceComputersManged+InstanceComputersUnManaged))
#
InstanceMobile=$((InstanceMobileManged+InstanceMobileUnManaged))
## Add the total amount of computers and mobile devices found for an instance to get the 
## total number of devices for an instance.
TotalInstance=$(($InstanceComputers+$InstanceMobile))
#
InstanceManaged=$((InstanceComputersManged+InstanceMobileManged))
## Add the number of computers found for an instance to the total number of computers 
## for all instances
TotalComputers=$((TotalComputers+InstanceComputers))
## Add the number of mobile devices found for an instance to the total number of computers 
## for all instances
TotalMobile=$((TotalMobile+InstanceMobile))
#
TotalManaged=$((TotalManaged+InstanceManaged))
## Add 1 to the total number of instances to get an instance count 
TotalJamfInstances=$((TotalJamfInstances+1))

## Write out the Company name as well as the amount of computers, mobile devices, and total devices
## each instance has to our output file as well as a blank line for readability. 
## To use s a CSV comment out the next 6 echo statements and uncomment the line after ## CSV FILE
#echo "$instanceName" >> "$OutputFile"
#echo "$CompanyName: $InstanceComputers Total Computers and $InstanceMobile Total iOS Devices" >> "$OutputFile"
#echo "Managed Computers: $InstanceComputersManged, Unmanaged Computers: $InstanceComputersUnManaged, Managed iOS: $InstanceMobileManged, Unmanaged iOS: $InstanceMobileUnManaged"  >> "$OutputFile"
#echo "$TotalInstance total devices" >> "$OutputFile"
#echo "$InstanceManaged total managed devices" >> "$OutputFile"
#echo "" >> "$OutputFile"

## CSV FILE
echo "$instanceName,$InstanceComputers,$InstanceComputersManged,$InstanceComputersUnManaged,$InstanceMobile,$InstanceMobileManged,$InstanceMobileUnManaged" >> "$OutputFile"

## Clean up temp files and variables after each iteration of the loop.
## While a new file will be created on each iteration it doesn't 
## hurt to be careful and this will handle the last iteration.
## Only reinitialize the instance variables not the overall variables.

rm /tmp/JSS_ComputerOutput.xml
rm /tmp/JSS_MobileOutput.xml
rm /tmp/JSS_ComputerID.txt
rm /tmp/JSS_MobileCount.txt

InstanceComputers="0"
InstanceMobile="0"
InstanceComputersManged="0"
InstanceMobileManged="0"
InstanceComputersUnManaged="0"
InstanceMobileUnManaged="0"
InstanceManaged="0"
TotalInstance="0"

# End instance exists if statement
else
	## If an instance is unavailable we'll write that to our output file.
	echo "$instanceName" >> "$OutputFile"
	echo "Instance is currently unreachable." >> "$OutputFile"
	echo "" >> "$OutputFile"

fi

done < "$InstanceList"

## Write out the total amount of computers found in all instances and the total number of 
## mobile devices found  to our output file with some formatting.
echo "Total Computers: $TotalComputers **** Total iOS Devices: $TotalMobile" >> "$OutputFile"

## Add the total number of computers and mobile devices found to get the total device count
## and store it in TotalDevices
TotalDevices=$(($TotalComputers+TotalMobile))

## Write out the total number of devices found across all instances tp our output file.
echo "Total Number of Devices: $TotalDevices" >> "$OutputFile"

## Write out the total number of managed devices found across all instances tp our output file.
echo "Total Licenses in use (Managed Devices): $TotalManaged" >> "$OutputFile"

## Write out the total number of Instances in use
echo "Across $TotalJamfInstances unique instances" >> "$OutputFile"

## Clean up tmp files for good measure
rm /tmp/JSS*
