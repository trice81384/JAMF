#/bin/bash

## This script is designed to check if a Script exists on a Jamf Pro Server and
## update it and its associated data.

##Any references to the JSS are due to historical reasons but JSS = Jamf Pro Server

### When using the XML downloaded from the JSS we must strip the ID tags from the policy
## and any categories associated with the policy. We also must make sure any associated
## categories exist in the JSS first.

## Define Global Variables

## Path to the RAW contents of the script we want to update. This script must be XML encoded in order to be updated correctly.
ScriptContents=$(cat /PATH TO FILE)

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
Scriptid=""

## The human readbale name of the script in Jamf
#DisplayName=""

## Text for the info field for thr script
#Info="This script does......&#13;
#Parameters 4, 5, and 6 do......&#13;
#Designed to be run....."

## Text for the Notes field for thr script
#Notes="Additional Script&#13;
#Information"

## Any defined script paramters
#Parameters="<parameter4>PARAMETER NAME</parameter4><parameter5>PARAMETER NAME</parameter5><parameter6>PARAMETER NAME</parameter6>"

## ARGV $1 is the name of the Script we want to update
## ARGV $2 is the list of JAMF instances.
## This instance name file MUST end with one blank lime otherwise errors in processing will occur.
## The file CANNOT contain windows line breaks otherwise sadness will happen.

if [ "$1" == "" ]
then
ScriptName="SCRIPT NAME"
else
ScriptName="$1"
fi

if [ "$2" == "" ]
then
InstanceList="PATH TO Instance File"
else
InstanceList="$2"
fi

## Use a here block to Create an xslt template file that is used to format the XML
## outputted from the JSS to our standards in this case it will be used to produce
## a list of all the names of the Scripts in the JSS.
## We'll first match the top element of the list of Scripts returned from the JSS
## which is scripts. Then from each child element (script)
## we'll select the value of the name and id attributes, place a question mark between them and then add a line break. 
## We add a question mark between the name and id values so we have a unique file separator for AWK to act on later
## as Script names typically won't contain this character. 

cat <<EOF > /tmp/JSS_template.xslt
<?xml version="1.0" encoding="ISO-8859-1"?>
<xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
<xsl:output method="text"/>
<xsl:template match="/scripts"> <!-- Start a search -->
            <xsl:for-each select="script"> 
            <xsl:value-of select="name"/> <!-- Find the value of a tag -->
            <xsl:text>?</xsl:text> <!-- Insert a ? into the output -->
            <xsl:value-of select="id"/> <!-- Find the value of a tag -->
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
## output the full list of Scripts from the JSS to a file.
## The list of Scripts can be found at the /scripts endpoint 
## We must use accept on the header since we are using a GET request 
## AND we want the JAMF Server to return an XML output.

curl \
-k \
-s \
-u "$apiUser":"$apiPass" \
-H "accept: text/xml" \
"$JSSResource/scripts" \
-X GET > /tmp/JSS_output.xml

## Since outputting the list of Scripts to a file just dumps the raw XML to the file
## it contains information that we might not want such as extraneous XML attributes.
## It also contains no formatting so using xsltproc we apply the template we created earlier
## and then output the formatted XML (which in this case is just the names and id numbers of all the Scripts)
## to a text file.

xsltproc /tmp/JSS_template.xslt /tmp/JSS_output.xml > /tmp/JSS_Scriptlist.txt

## Read in the previous text file line by line to see if it contains the name of the Script
## we want to delete. We check for a positive match one time only to avoid continual iterations of the
## loop to cause negative values to be reported. This is expected behavior but would throw off the results.
## We pull the name of the Script into the ScriptSearch variable so as not to directly manipulate the name
## variable (the contents of which we want to use later). If the contents of ScriptSearch match the name of the 
## Script we want to delete in ScriptName then we set the ScriptFound variable to yes and pull in the ID number
## for that Script from the Script list we created earlier.
## Since the Script list we created earlier has the Script name and id separated by a ? we use the awk statement with a ?
## as a field separator to find either the Script name (first field) or id (second field).
## We only search for the id if we find the name of the Script are looking to delete.

while read name
do
ScriptSearch=$(echo "$name" | awk -F "\?" '{print $1}')
if [ "$ScriptSearch" == "$ScriptName" ]
then
ScriptFound="Yes"
Scriptid=$(echo "$name" | awk -F "\?" '{print $2}')
fi
done < /tmp/JSS_Scriptlist.txt


## If a positive match is found then it means the Script we want to modify exists.
## Using curl we put the contents of the variable we read earlier into the correct spot in the XML.

if [ "$ScriptFound" == "Yes" ]
then
curl \
-s \
-k \
-u "$apiUser":"$apiPass" \
-H "Content-type: text/xml" \
$JSSResource/scripts/id/$Scriptid \
-d "<script><script_contents>$ScriptContents</script_contents></script>" \
-X PUT

##Not necessary to upload the encoding as JAMF will generate a new value. Keep here just in case.

#curl \
#-s \
#-k \
#-u "$apiUser":"$apiPass" \
#-H "Content-type: text/xml" \
#$JSSResource/scripts/id/$Scriptid \
#-d "<script><script_contents_encoded>$ScriptContentsEncoded</script_contents_encoded></script>" \
#-X PUT

if [ "$DisplayName" != "" ]
then
curl \
-s \
-k \
-u "$apiUser":"$apiPass" \
-H "Content-type: text/xml" \
$JSSResource/scripts/id/$Scriptid \
-d "<script><name>$DisplayName</name></script>" \
-X PUT
fi

if [ "$Notes" != "" ]
then
curl \
-s \
-k \
-u "$apiUser":"$apiPass" \
-H "Content-type: text/xml" \
$JSSResource/scripts/id/$Scriptid \
-d "<script><notes>$Notes</notes></script>" \
-X PUT
fi

if [ "$Info" != "" ]
then
curl \
-s \
-k \
-u "$apiUser":"$apiPass" \
-H "Content-type: text/xml" \
$JSSResource/scripts/id/$Scriptid \
-d "<script><info>$Info</info></script>" \
-X PUT
fi

if [ "$Parameters" != "" ]
then
curl \
-s \
-k \
-u "$apiUser":"$apiPass" \
-H "Content-type: text/xml" \
$JSSResource/scripts/id/$Scriptid \
-d "<script><parameters>$Parameters</parameters></script>" \
-X PUT
fi


## Use printf (more reliable than echo) to insert a mew line after the curl statement for readability because
## bash will prob put the following echo command on the same line as the curl output
printf "\n"
echo "Script:$ScriptName Updated for $CompanyName"
echo ""
else
echo "Script *$ScriptName* not found for $CompanyName" 
echo ""
fi

## Clean up temp files and variables after each iteration of the loop.
## While a new file will be created on each iteration it doesn't 
## hurt to be careful and this will handle the last iteration.

rm /tmp/JSS_Scriptlist.txt
rm /tmp/JSS_output.xml
ScriptFound=""

# End instance exists if statement
else
	echo "$instanceName"
	echo "Instance is currently unreachable."
	echo ""

fi

done < "$InstanceList"

rm /tmp/JSS*