#/bin/bash

## This script is designed to check if a Script exists on a Jamf Pro Server and
## if not to upload a new one.
## Scripts can be uploaded by id to the following endpoint:
## /JSSResource/scripts/id/0

##Any references to the JSS are due to historical reasons but JSS = Jamf Pro Server

### When using the XML downloaded from the JSS we must strip the ID tags from the script
## and any categories associated with the script. We also must make sure any associated
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

ScriptFound=""

## ARGV $1 the path to the xml file of the Script we want to upload/create
## ARGV $2 is the list of JAMF instances.
## This instance name file MUST end with one blank lime otherwise errors in processing will occuur.
## The file CANNOT contain windows line breaks otherwise sadness will happen.

## ARGV $1
###############################################
## BETTER TO CURL THE XML OF THE EXISTING SCRIPT DIRECTLY FROM THE JAMF SERVER EG:
### curl -k -u "$apiUser":"$apiPass" -H "accept: text/xml" https://your.jamfserver.url/JSSResource/scripts/id/INSERT ID NUMBER
### and pasting it to a new XML file instead of copying the xml from the JAMF api page as doing it this way
### will will contain all the XML escape codes in the script. Without them, the XML file may fail to properly upload.
### Can remove the <?xml version="1.0" encoding="UTF-8"?> from the new file though as well as id references.

if [ "$1" == "" ]
then
ScriptXML="PATH TO XML FILE"
else
ScriptXML="$1"
fi

if [ "$2" == "" ]
then
InstanceList="PATH TO Instance File"
else
InstanceList="$2"
fi

## Search for the actual (Display) name of the script we are going to create by reading in the XML file for the script.
## We first grep for <script> which is the opening tag or first line of the file which will return that line, which contains the name of the 
## script we are looking for. Then using awk with <name> or </name> (which surround the script name) as field separators we extract the second field
## which is the name of the script.

ScriptName=$(cat "$ScriptXML" | grep "<script>" | awk -F "<name>|</name>" '{print $2}')

##*********************************
## Since we are using the RAW XML to add scripts the <script> tag is on the first line.
## If we change to formatted xml we would have to change our awk statement.
#**********************************

## Use a here block to Create an xslt template file that is used to format the XML
## outputted from the JSS to our standards in this case it will be used to produce
## a list of all the names of the Scripts in the JSS.
## We'll first match the top element of the list of Scripts returned from the JSS
## which is scripts. Then from each child element (script)
## we'll select the value of the name attribute and then add a line break. 

cat <<EOF > /tmp/JSS_template.xslt
<?xml version="1.0" encoding="ISO-8859-1"?>
<xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
<xsl:output method="text"/>
<xsl:template match="/scripts"> <!-- Start a search -->
            <xsl:for-each select="script"> 
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
## output the full list of scripts from the JSS to a file.
## The list of scripts can be found at the /scripts endpoint 
## We must use accept on the header since we are using a GET request 
## AND we want the JAMF Server to return an XML output.

curl \
-k \
-s \
-u "$apiUser":"$apiPass" \
-H "accept: text/xml" \
"$JSSResource/scripts" \
-X GET > /tmp/JSS_output.xml

## Since outputting the list of scripts to a file just dumps the raw XML to the file
## it contains information that we might not want such as id number and other XML attributes.
## It also contains no formatting so using xsltproc we apply the template we created earlier
## and then output the formatted XML (which in this case is just the names of all the scripts)
## to a text file.

xsltproc /tmp/JSS_template.xslt /tmp/JSS_output.xml > /tmp/JSS_scriptlist.txt

## Read in the previous text file line by line to see if it contains the name of the script
## we want to add. We check for a positive match one time only to avoid continual iterations of the
## loop to cause negative values to be reported. This is expected behavior but would throw off the results. 

while read name
do
if [ "$name" == "$ScriptName" ]
then
ScriptFound="Yes"
fi
done < /tmp/JSS_scriptlist.txt

## If a positive match is never found then it means the script we want to create does not already exist
## so using curl we can POST a new script to the JSS instance. We send it to the 0 endpoint since this allows
## the JSS to create it at the next available slot. Also since we are send the curl command the location of an XML
## file in order to create the script we use the -T switch. If we were using just XML data or a variable with XML in
## it we would use the -d switch.

if [ "$ScriptFound" != "Yes" ]
then
curl \
-s \
-k \
-u "$apiUser":"$apiPass" \
-H "content-type: text/xml" \
$JSSResource/scripts/id/0 \
-T "$ScriptXML" \
-X POST
## Use printf (more reliable than echo) to insert a mew line after the curl statement for readability because
## bash will prob put the following echo command on the same line as the curl output
printf "\n"
echo "Script:$ScriptName Created for $CompanyName"
echo ""
else
echo "Script already exists for $CompanyName" 
echo ""
fi

## Clean up temp files and variables after each iteration of the loop.
## While a new file will be created on each iteration it doesn't 
## hurt to be careful and this will handle the last iteration.

rm /tmp/JSS_scriptlist.txt
rm /tmp/JSS_output.xml
ScriptFound=""

# End instance exists if statement
else
	echo "$instanceName"
	echo "Instance is currently unreachable."
	echo ""

fi

## Clean up temp files after each iteration of the loop.
## While a new file will be created on each iteration it doesn't 
## hurt to be careful and this will handle the last iteration.


done < "$InstanceList"

rm /tmp/JSS*