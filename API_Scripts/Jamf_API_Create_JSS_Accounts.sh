#/bin/bash

## This script is designed to check if a JSS User Account exists on a Jamf Pro Server and
## if not to upload a new one.
## User Accounts can be uploaded by id to the following endpoint:
## /JSSResource/accounts/userid/0
## ################################################# ##
## THIS SCRIPT WILL NOT CREATE A VALID PASSWORD HASH ##
## THIS IS A LIMITATION OF THE CLASSIC JAMF PRO API  ##
## ################################################# ##

## Any references to the JSS are due to historical reasons but JSS = Jamf Pro Server

### When using the XML downloaded from the JSS we must strip the ID tags from the account
## and any categories associated with the account. We also must make sure any associated
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

## ARGV $1 is the path to the XML file of the Account we want to upload/create
## ARGV $2 is the list of JAMF instances.
## This instance name file MUST end with one blank lime otherwise errors in processing will occuur.
## The file CANNOT contain windows line breaks otherwise sadness will happen.

## ARGV $1
###############################################
### BETTER TO CURL THE XML OF THE EXISTING ACCOUNT DIRECTLY FROM THE JAMF SERVER TO DEAL WITH SPECIAL CHARACTERS EG:
### curl -k -u "$apiUser":"$apiPass" -H "accept: text/xml" https://your.jamfserver.url/JSSResource/accounts/userid/id/INSERT ID NUMBER
### and pasting it tp a new XML file instead of copying the xml from the JAMF api page as doing it this way
### will will contain all the XML escape codes in the account. Without them, the XML file may fail to properly upload.
### Can remove the <?xml version="1.0" encoding="UTF-8"?> from the new file though as well as id references.

if [ "$1" == "" ]
then
accountXML="PATH TO XML FILE"
else
accountXML="$1"
fi

if [ "$2" == "" ]
then
InstanceList="PATH TO Instance File"
else
InstanceList="$2"
fi

### Search for the actual (Display) name of the account we are going to create by reading in the XML file for the account.
### We first grep for <account> which is the opening tag or first line of the file which will return that line, which contains the name of the 
### account we are looking for.
### Then working on the line returned we use awk with <name> or </name> as the field separators which will return only the data between those 
### tags which corresponds to the account's name. Since in this case awk will find any data on the first line and
### return a blank line below it we use NR==1 to tell awk to only return the 1st line and just the second field from
### the returned data which is guaranteed to be the entire account name.
### In case there's any white space we use sub and a regular expression (^ ) to replace it with nothing ""
### Since we are using raw XML we use NR==1 if we switch to formatted XML it would be NR==2

accountName=$(cat "$accountXML" | grep -A 1 "<account>" | awk -F "<name>|</name>" 'NR==2{sub(/^ /,"");print $2}')

## Use a here block to Create an xslt template file that is used to format the XML
## outputted from the JSS to our standards in this case it will be used to produce
## a list of all the names of the Accounts in the JSS.
## We'll first match the top element of the list of JSS User Accounts returned from the JSS
## which is accounts. Then from each child element (users)
## we need to find its child element (user) which we can do in one line with users/user
## and then we'll select the value of the name attribute and then add a line break. 

cat <<EOF > /tmp/JSS_template.xslt
<?xml version="1.0" encoding="ISO-8859-1"?>
<xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
<xsl:output method="text"/>
<xsl:template match="/accounts"> <!-- Start a search -->
            <xsl:for-each select="users/user"> 
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
## output the full list of accounts from the JSS to a file.
## The list of Extension attributes can be found at the /accounts endpoint 
## We must use accept on the header since we are using a GET request 
## AND we want the JAMF Server to return an XML output.

curl \
-k \
-s \
-u "$apiUser":"$apiPass" \
-H "accept: text/xml" \
"$JSSResource/accounts" \
-X GET > /tmp/JSS_output.xml

## Since outputting the list of accounts to a file just dumps the raw XML to the file
## it contains information that we might not want such as id number and other XML attributes.
## It also contains no formatting so using xsltproc we apply the template we created earlier
## and then output the formatted XML (which in this case is just the names of all the categories)
## to a text file.

xsltproc /tmp/JSS_template.xslt /tmp/JSS_output.xml > /tmp/JSS_Accountlist.txt

## Read in the previous text file line by line to see if it contains the name of the account
## we want to add. We check for a positive match one time only to avoid continual iterations of the
## loop to cause negative values to be reported. This is expected behavior but would throw off the results. 

while read name
do
if [ "$name" == "$accountName" ]
then
accountFound="Yes"
fi
done < /tmp/JSS_Accountlist.txt

## If a positive match is never found then it means the account we want to create does not already exist
## so using curl we can POST a new account to the JSS instance. We send it to the 0 endpoint since this allows
## the JSS to create it at the next available slot. Also since we are send the curl command the location of an XML
## file in order to create the group we use the -T switch. If we were using just XML data or a variable with XML in
## it we would use the -d switch.

if [ "$accountFound" != "Yes" ]
then
curl \
-s \
-k \
-u "$apiUser":"$apiPass" \
-H "content-type: text/xml" \
$JSSResource/accounts/userid/0 \
-T "$accountXML" \
-X POST
## Use printf (more reliable than echo) to insert a mew line after the curl statement for readability because
## bash will prob put the following echo command on the same line as the curl output
printf "\n"
echo "Account:$accountName Created for $CompanyName"
echo ""
else
echo "Account *$accountName* already exists for $CompanyName" 
echo ""
fi

## Clean up temp files and variables after each iteration of the loop.
## While a new file will be created on each iteration it doesn't 
## hurt to be careful and this will handle the last iteration.

rm /tmp/JSS_Accountlist.txt
rm /tmp/JSS_output.xml
accountFound=""

# End instance exists if statement
else
	echo "$instanceName"
	echo "Instance is currently unreachable."
	echo ""

fi

done < "$InstanceList"

rm /tmp/JSS*