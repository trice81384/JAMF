#!/bin/sh

## This script is designed to report the Company,Computer Name,Serial Number,and UUID
## of all the computers in a Jamf Pro Server instance across all instances.
## All of this information can be found within the computer endpoint:
## /JSSResource/computer/

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

#File to output the search results
OutputFile=""

## ARGV $1
## Path to a text file containing all the instances we want to collect information for.
## This must be a plain text file ending in a blank line and not using Windows style line
## breaks otherwise sadness will occur.

if [ "$1" == "" ]
then
InstanceList="PATH TO Instance File"
else
InstanceList="$1"
fi

## Use a here block to Create an xslt template file that is used to format the XML
## outputted from the JSS to our standards in this case it will be used to produce
## a list of all the names of the Computers in the JSS.
## We'll first match the top element of the list of Computers returned from the JSS
## which is computers Then from each child element (computer)
## we'll select the value of the name and id attributes, place a question make between them and then add a line break. 
## We add a question mark between the name and id values so we have a unique file separator for AWK to act on later
## as computer names typically won't contain this character. 

cat <<EOF > /tmp/JSS_ComputerTemplate.xslt
<?xml version="1.0" encoding="ISO-8859-1"?>
<xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
<xsl:output method="text"/>
<xsl:template match="/computers"> <!-- Start a search -->
			<xsl:for-each select="computer">
			 <xsl:value-of select="name"/> <!-- Find the value of a tag -->
			 <xsl:text>?</xsl:text> <!-- Insert a ? into the output -->
            <xsl:value-of select="id"/> <!-- Find the value of a tag -->
            <xsl:text>&#xa;</xsl:text> <!-- Insert a line break into the output -->
</xsl:for-each>
</xsl:template> <!-- Close the template -->
</xsl:stylesheet>
EOF

## CSV HEADER
echo "Company,Computer Name,Serial Number,UUID" >> "$OutputFile"

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
## just created in order to only extract the computer names and computer ids separated by a ? and 
## write that list to a file.

xsltproc /tmp/JSS_ComputerTemplate.xslt /tmp/JSS_ComputerOutput.xml > /tmp/JSS_ComputerList.txt

## Read thorough the file and put the computer name and computer id into 2 separate variables.
## We use a text file and awk here instead of just xpath because xpath will output incorrect data if the
## computer name has a special character in it particularly an apostrophe which is quite common.
## We do use xpath through the get the IP address for the id captured
## If an IP address is not found we indicate that.

while read computer
do
ComputerName=$(echo "$computer" | awk -F "\?" '{print $1}')
id=$(echo "$computer" | awk -F "\?" '{print $2}')
SerialNumber=$(curl -X GET -H "accept: text/xml" -s -k -u "$electricAPIUser:$electricAPIPass" "$JSSResource/computers/id/$id" | xmllint --xpath xmllint --xpath '/computer/general/serial_number/text()' - )
UUID=$(curl -X GET -H "accept: text/xml" -s -k -u "$electricAPIUser:$electricAPIPass" "$JSSResource/computers/id/$id" | xmllint --xpath xmllint --xpath '/computer/general/udid/text()' - )

if [ "$SerialNumber" == "" ]
then
SerialNumber="NO SERIAL NUMBER RECORDED"
fi

if [ "$UUID" == "" ]
then
SerialNumber="NO UUID RECORDED"
fi

## Write out the Company name as well as the computer name and it's external IP
echo "$CompanyName,$ComputerName,$SerialNumber,$UUID" >> "$OutputFile"
done < /tmp/JSS_ComputerList.txt

## Clean up temp files and variables after each iteration of the loop.
## While a new file will be created on each iteration it doesn't 
## hurt to be careful and this will handle the last iteration.
## Only reinitialize the instance variables not the overall variables.
rm /tmp/JSS_ComputerOutput.xml
rm /tmp/JSS_ComputerList.txt

# End instance exists if statement
else
	## If an instance is unavailable we'll write that to our output file.
	echo "$instanceName" >> "$OutputFile"
	echo "Instance is currently unreachable." >> "$OutputFile"
	echo "" >> "$OutputFile"

fi

done < "$InstanceList"

## Clean up tmp files for good measure
rm /tmp/JSS*
