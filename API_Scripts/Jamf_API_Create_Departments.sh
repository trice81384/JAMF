#!/bin/sh

## This script is designed to check if a Department exists on a JSS and
## if not to upload a new one.
## Departments can be uploaded by id to the following endpoint:
## /JSSResource/departments/id/0

##Any references to the JSS are due to historical reasons but JSS = Jamf Pro Server

### When using the XML downloaded from the JSS we must strip the ID tags from the department
## and any categories associated with the department. We also must make sure any associated
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

## ARGV $1 is the path to the xml file of the Department we want to upload/create
## ARGV $2 is the list of JAMF instances.
## This instance name file MUST end with one blank lime otherwise errors in processing will occuur.
## The file CANNOT contain windows line breaks otherwise sadness will happen.

if [ "$1" == "" ]
then
DepartmentFile="PATH TO XML FILE"
else
DepartmentFile="$1"
fi

if [ "$2" == "" ]
then
InstanceList="PATH TO Instance File"
else
InstanceList="$2"
fi

## Use a here block to Create an xslt template file that is used to format the XML
## outputted from the JSS to our standards in this case it will be used to produce
## a list of all the names of the Departments in the JSS.
## We'll first match the top element of the list of Departments returned from the JSS
## which is departments. Then from each child element (department)
## we'll select the value of the name attribute and then add a line break. 

cat <<EOF > /tmp/JSS_template.xslt
<?xml version="1.0" encoding="ISO-8859-1"?>
<xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
<xsl:output method="text"/>
<xsl:template match="/departments"> <!-- Start a search -->
            <xsl:for-each select="department"> 
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
## output the full list of departments from the JSS to a file.
## The list of Departments can be found at the /departments endpoint
## We must use accept on the header since we are using a GET request 
## AND we want the JAMF Server to return an XML output. 

curl \
-k \
-s \
-u "$apiUser":"$apiPass" \
-H "accept: text/xml" \
"$JSSResource/departments" \
-X GET > /tmp/JSS_output.xml

## Since outputting the list of departments to a file just dumps the raw XML to the file
## it contains information that we might not want such as id number and other XML attributes.
## It also contains no formatting so using xsltproc we apply the template we created earlier
## and then output the formatted XML (which in this case is just the names of all the departments)
## to a text file.

xsltproc /tmp/JSS_template.xslt /tmp/JSS_output.xml > /tmp/JSS_departmentlist.txt

## Read in the previous text file line by line to see if it contains the name of the department
## we want to add. We check for a positive match one time only to avoid continual iterations of the
## loop to cause negative values to be reported. This is expected behavior but would throw off the results. 

while read NewDepartmentName
do
grep -qi -e "$NewDepartmentName" /tmp/JSS_departmentlist.txt
if [ $? == 1 ]
then
curl \
-s \
-k \
-u "$apiUser":"$apiPass" \
-H "content-type: text/xml" \
$JSSResource/departments/id/0 \
-d "<department><name>$NewDepartmentName</name></department>" \
-X POST
printf "\n"
echo "Department:$NewDepartmentName Created for $CompanyName"
echo ""
else
echo "Department: *$NewDepartmentName* already exists for $CompanyName" 
echo ""
fi
done < "$DepartmentFile"

## Clean up temp files and variables after each iteration of the loop.
## While a new file will be created on each iteration it doesn't 
## hurt to be careful and this will handle the last iteration.

rm /tmp/JSS_departmentlist.txt
rm /tmp/JSS_output.xml

# End instance exists if statement
else
	echo "$instanceName"
	echo "Instance is currently unreachable."
	echo ""

fi

done < "$InstanceList"

rm /tmp/JSS*
