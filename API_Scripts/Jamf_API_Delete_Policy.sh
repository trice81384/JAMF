#!/bin/sh

## This script is designed to check if a Policy exists on a Jamf Pro Server and
## if so delete it.
## Policies can be found by id # at the following endpoint:
## /JSSResource/policies/id/#

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

PolicyFound=""
Policyid=""

## ARGV $1 is the name of the Policy we want to delete
## ARGV $2 is the list of JAMF instances.
## This instance name file MUST end with one blank lime otherwise errors in processing will occur.
## The file CANNOT contain windows line breaks otherwise sadness will happen.

if [ "$1" == "" ]
then
PolicyName="POLICY NAME"
else
PolicyName="$1"
fi

if [ "$2" == "" ]
then
InstanceList="PATH TO Instance File"
else
InstanceList="$2"
fi

## Use a here block to create an xslt template file that is used to format the XML
## outputted from the JSS to our standards in this case it will be used to produce
## a list of all the names of the policies in the JSS.
## We'll first match the top element of the list of policies returned from the JSS
## which is policies. Then from each child element (policy)
## we'll select the value of the name and id attributes, place a question make between them and then add a line break. 
## We add a question mark between the name and id values so we have a unique file separator for AWK to act on later
## as policy names typically won't contain this character. 

cat <<EOF > /tmp/JSS_template.xslt
<?xml version="1.0" encoding="ISO-8859-1"?>
<xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
<xsl:output method="text"/>
<xsl:template match="/policies"> <!-- Start a search -->
            <xsl:for-each select="policy"> 
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
## output the full list of policies from the JSS to a file.
## The list of policies can be found at the /policies endpoint 
## We must use accept on the header since we are using a GET request 
## AND we want the JAMF Server to return an XML output.

curl \
-k \
-s \
-u "$apiUser":"$apiPass" \
-H "accept: text/xml" \
"$JSSResource/policies" \
-X GET > /tmp/JSS_output.xml

## Since outputting the list of policies to a file just dumps the raw XML to the file
## it contains information that we might not want such as extraneous XML attributes.
## It also contains no formatting so using xsltproc we apply the template we created earlier
## and then output the formatted XML (which in this case is just the names and id numbers of all the policies)
## to a text file.

xsltproc /tmp/JSS_template.xslt /tmp/JSS_output.xml > /tmp/JSS_PolicyList.txt

## Read in the previous text file line by line to see if it contains the name of the policy
## we want to delete. We check for a positive match one time only to avoid continual iterations of the
## loop to cause negative values to be reported. This is expected behavior but would throw off the results.
## We pull the name of the policy into the PolicySearch variable so as not to directly manipulate the name
## variable (the contents of which we want to use later). If the contents of PolicySearch match the name of the policy
## we want to delete in PolicyName then we set the PolicyFound variable to yes and pull in the ID number for that policy
## from the Policy list we created earlier.
## Since the Policy list we created earlier has the policy's name and id separated by a ? we use the awk statement with a ?
## as a field separator to find either the Policy name (first field) or id (second field). We only search for the id if we find the name
## of the policy we are looking to delete.

while read name
do
PolicySearch=$(echo "$name" | awk -F "\?" '{print $1}')
if [ "$PolicySearch" == "$PolicyName" ]
then
PolicyFound="Yes"
Policyid=$(echo "$name" | awk -F "\?" '{print $2}')
fi
done < /tmp/JSS_PolicyList.txt


## If a positive match is found then it means the policy we want to delete exists.
## So using curl we can DELETE the policy from the instance.
## We have to delete the policy by its ID number which is why we retrieved it in the previous loop.

if [ "$PolicyFound" == "Yes" ]
then
curl \
-s \
-k \
-u "$apiUser":"$apiPass" \
$JSSResource/policies/id/$Policyid \
-X DELETE
## Use printf (more reliable than echo) to insert a mew line after the curl statement for readability because
## bash will prob put the following echo command on the same line as the curl output
printf "\n"
echo "Policy:$PolicyName Deleted for $CompanyName"
echo ""
else
echo "Policy *$PolicyName* not found for $CompanyName" 
echo ""
fi

## Clean up temp files and variables after each iteration of the loop.
## While a new file will be created on each iteration it doesn't 
## hurt to be careful and this will handle the last iteration.

rm /tmp/JSS_PolicyList.txt
rm /tmp/JSS_output.xml
PolicyFound=""

# End instance exists if statement
else
	echo "$instanceName"
	echo "Instance is currently unreachable."
	echo ""

fi

done < "$InstanceList"

rm /tmp/JSS*
