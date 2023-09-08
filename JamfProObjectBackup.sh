#!/bin/bash

##Capture the script information to use for logging purposes.
echo $$ > /tmp/JSS_Backup.pid
ScriptPID=$(cat /tmp/JSS_Backup.pid) 
ScriptName=$(basename "$0")

## Define Global Variables
## Any references to the JSS are due to historical reasons but JSS = Jamf Pro Server
## The order of variable assignments is important

##Unset the GetInfoFlag so the getJamfInformation function runs 
unset GetInfoFlag

## Objects in a Jamf Pro Server available for download
JSSAllObjectArray+=("scripts" "policies" "computer_groups" "advanced_computer_searches" "os_x_configuration_profiles" "computer_extension_attributes" "restricted_software" "accounts" "categories" "departments")

# How many days to keep object backups
DaysOlderThan="30"

## Location of a singular Jamf instance or file containing multiple instances
InstanceList=""

## Path to folder where backup items will be stored
BackupFolder=""

## If defining a user name and password in the script (not recommended) do so here
## and uncomment the following 2 lines (this will override any environmental variables):
apiUser=''
apiPass=''

## JAMF Pro User with privileges to update the corresponding API endpoints. Setting any empty variables to null will be important later.
apiUser=${apiUser:-null}
## Password for the user specified
apiPass=${apiPass:-null}

##If using the apiParams file to set the credentials create a script like the below.
## The apiParms will then export API user name and password so they don't have to be entered on the command line.
## Script should be in a format like the next 4 lines (without the comments):
## #!/bin/bash
##
## apiUser=''
## apiPass=''

## Then uncomment the below line and enter a path to the file as the value. This will override any previous credentials set or exported.
#apiParams=""

ScriptLogging(){
## Function to provide logging of the script's actions either to the console or the log file specified.
## Developed by Rich Trouton https://github.com/rtrouton
    local LogStamp=$(date +%Y-%m-%d\ %H:%M:%S)
    if [[ -n "$2" ]]
    then
      LOG="$2"
    else
      LOG="PATH TO LOG FILE HERE"
    fi
    
    ## To output to a log file append ' >> $LOG' to the below echo statement 
    echo "$LogStamp [$ScriptName]:" " $1"
}
ScriptLogging "Jamf Backup running with PID: $ScriptPID"

getJamfInformation(){

## Check to see if the information gathering function has already run and if so skip it
if [[ "$GetInfoFlag" == "set" ]]
then
return
fi

##Get API credential variables.
if [[ -s "$apiParams" ]]
   then
   ScriptLogging "API user name and password file found. Sourcing."
    ## Run the script found for apiParms to populate the variables
    ## Use dot notation so it says within the same process
    . "$apiParams"
elif [[ "$apiUser" == "null" ]] && [[ "$apiPass" == "null" ]]
   then
    ScriptLogging "Jamf API credentials not found. Prompting user."
    read -r -p "Please enter a Jamf API account name: " apiUser
    read -r -s -p "Please enter the password for the account: " apiPass
elif [[ "$apiUser" == "null" ]]
   then
    ScriptLogging "Jamf API user not found. Prompting."
    read -r -p "Please enter a JAMF API account name: " apiUser
elif [[ "$apiPass" == "null" ]]
   then
    ScriptLogging "Jamf API password not found. Prompting."
    read -r -p "Please enter a password for the JAMF API account: " apiPass
else
    ScriptLogging "API Credentials found. Continuing."
fi

## If the InstanceList variable is empty prompt for an instance of list of instances
if [[ -z "$InstanceList" ]]
then
ScriptLogging "No Jamf Instances specified to backup. Prompting."
read -r -p "Please enter a Jamf URL beginning with https:// or a file containing a list of instances to backup: " InstanceList
fi

## If the BackupFolder variable is empty prompt for a location to store backup files
if [[ -z "$BackupFolder" ]]
then
ScriptLogging "No backup location specified. Prompting."
read -r -p "Please enter location to store backup items from Jamf: " BackupFolder
fi

## Cleanup file paths dragged in from the terminal by removing any \ escape characters.
InstanceList=$(echo "$InstanceList" | awk '{gsub(/\\/,""); print $0}')
BackupFolder=$(echo "$BackupFolder" | awk '{gsub(/\\/,""); print $0}')

# Create a local temporary folder in the backup folder the script is using
BackupFolderTemp="$BackupFolder"/.tmp
if [[ ! -d "$BackupFolderTemp" ]]
then
mkdir -p "$BackupFolderTemp"
fi

##Cleanup any old instances if lying around so they don't geyt added to the instance file on the next script run
if [[ -e "$BackupFolderTemp"/JSS_instances.txt ]]
then
rm -rf "$BackupFolderTemp"/JSS_instances.txt
fi

## Write out any inputted instances to a file so the loops in the script process consistently.
if [[ ! -f "$InstanceList" ]]
then
ScriptLogging "Writing out instance list to $BackupFolderTemp/JSS_instances.txt."
printf "$InstanceList" '%s\n' >> "$BackupFolderTemp"/JSS_instances.txt
InstanceList="$BackupFolderTemp"/JSS_instances.txt
fi

##Set the get info flag so this function only runs once
GetInfoFlag="set"
}

createBackupFolder(){
DownloadType="$1"

# The folder where the script is running from. 
BackupScriptFolder=$(dirname "$0")
# The date the script started running
ScriptDate=$(date +%m-%d-%Y)

#Folders for the downloaded objects to go to.
if [[ -z "$BackupFolder" ]]
then
ObjectFolder="$BackupScriptFolder/$ScriptDate/$DomainName/$ObjectType/$DownloadType"
else
ObjectFolder="$BackupFolder/$ScriptDate/$DomainName/$ObjectType/$DownloadType"
fi

##Temporary Folder for storing cache and other temp files for a particular object
##Variable expansion removes the last folder in the variable path (to remove more keep adding /*)
TempFolder=${ObjectFolder%/*}/.tmp

##Create the folders needed to store the downloaded objects
ScriptLogging "Creating Backup Folder: $ObjectFolder"
mkdir -p "$ObjectFolder"
mkdir -p "$TempFolder"

if [[ "$ContentPrompt" == "y" ]]
then
mkdir -p "$ObjectFolder"/"$ObjectType"_Contents_NotEncoded
ScriptLogging "$(echo $ObjectType | tr '[:lower:]' '[:upper:]') Contents [CODE] selected for download."
else
ScriptLogging "Contents [CODE ONLY] Not selected for download."
fi
}

## Function to generate an auth token on those instances running 10.35 or higher
makeAuthHeader(){
local APIUser="$1"
local APIPass="$2"
local JSS_URL="$instanceName"

## Warn if APIUser or APIPass has no value
if [[ -z "$APIUser" ]]
then
ScriptLogging "WARNING: NO API User was specified"> /dev/stderr
elif [[ -z "$APIPass" ]]
then
ScriptLogging "WARNING: NO API Password was specified"> /dev/stderr
elif [[ -z "$instanceName" ]]
then
ScriptLogging "WARNING: NO Instances found to backup"> /dev/stderr
fi

## Get Jamf version from the URL using = and - as field delimiters. This allows us to get the major.minor version without any extraneous info.
JSSVersion=$(curl -s "$JSS_URL"/JSSCheckConnection | awk -F "-" '{print $1}'  )

## Do to limitations of string comparison we'll have to strip off the major version of Jamf to first check if the version is below 9 since if we
## were to check full versions only with this method 10 would always be less than 9. Using this method the major version check must ALWAYS be performed
## first. Since we only care about versions 9 or less we can get away using this one major version comparison. Any versions 10 and above will then now
## compare their versions correctly.
JSSMajorVersion=$(echo $JSSVersion | awk -F . '{print $1}')

## If the major version of Jamf is below 9 exit otherwise if the full version of Jamf is 10.0 or above but less than 10.35 use a different method of basic authentication.
if echo "$JSSMajorVersion 9" | awk '{exit $1<=$2?0:1}'
then
  ScriptLogging "Jamf Version 9 or lower detected exiting. "
elif echo "$JSSVersion 10.35" | awk '{exit $1<$2?0:1}'
then
  ScriptLogging "Executing api authorization function for Jamf 10 to 10.34"
  ## If the current version of Jamf is less than 10.35.0 BUT it is greater than or equal to 10.0 then use Basic Auth with base 64 encoded credentials
  ## and then echo them out with the authorization type so the API call can add this information to its headers.
  apiAuth=$(echo "Authorization: Basic $(echo -n ${APIUser}:${APIPass} | base64)")
elif echo "$JSSVersion 10.35" | awk '{exit $1>=$2?0:1}'
then
  ScriptLogging "Executing api token authorization function for Jamf 10.35 or higher."

  ## First check to see if the current token's expiration date exists and is valid so we don't generate a new one unnecessarily.
  ## Get the current time in epoch form
  CurrentDateEpoch=$(date "+%s")
  
  ## If the current date is greater than or equal to the time of token expiration we must generate a new token.
  ## Checking for greater than as opposed to less than will also allow the check to work correctly if $TokenExpirationEpoch has invalid or no data
  ## since then the equation would evaluate to true. This keeps the code cleaner and more compact (except for these comments).
  ## We'll also make sure we use mathematical comparison to avoid string comparison pitfalls.
  ## If the instance passed in (instanceName) is not the same as the instance from the last instance passed in (current_JSS_URL) also generate a new token
  if (( CurrentDateEpoch >= TokenExpirationEpoch )) || [[ "$current_JSS_URL" != "$instanceName" ]]
  then
    ScriptLogging "There is currently not a valid API token. Generating a new one."
    ## Invalidate any current tokens just in case
    Token=$(curl -s -H "$apiAuth" "${JSS_URL}/api/v1/auth/invalidate-token" -X POST)
    ## Generate a new token
    Encoded_Credentials=$(printf "${APIUser}:${APIPass}" | iconv -t ISO-8859-1 | base64 -i -)
    Token=$(curl -k -s -H "Authorization: Basic $Encoded_Credentials" -H "accept: application/json" "${JSS_URL}/api/v1/auth/token" -X POST)

    ## Currently the API Bearer token is issued based on the server time zone while the current date is determined on the client side.
    ## Therefore unless the server and client are adjusted to be in the same time zone getting the token expiration epoch and then using this formula
    ## TimeDifference=$(( (CurrentDateEpoch - TokenExpiryEpoch) / 60 )) to find the time difference in minutes and then checking if that difference is greater
    ## then 30 will not work but could be used if the time zone differences were accounted for. In which case you could get the appropriate values like so:
    ## TokenExpiry=$(echo $Token | awk -F \" '{print $8}') or in zsh TokenExpiry=$(echo $Token | awk -F \" '/expires/{print $4}')
    ## TokenExpiryEpoch=$(date -jf "%Y-%m-%dT%H:%M:%SZ" "${TokenExpiry%%.*}Z" "+%s")

    ## However an easy work around is to get the time when the token is created and add 29 minutes (in seconds) to it which will give us the time of token expiration in epoch form.
    ## Even though bearer tokens expire in 30 mins will play it safe a subtract a minute to account for a less than accurate time comparison and potential delays in the script.
    ## This can also be moved to the Jamf API endpoint to check if the token is still valid, but this way reduces API calls.
    TokenExpirationEpoch=$(date -v+"1740"S "+%s")
    
    ## Once a token is generated the actual token must also be extracted from the API response.
    AuthToken=$(echo $Token | awk -F \" '/token/{print $4}')
    ## Set the instance passed in to the current Jamf Instance being used
    current_JSS_URL="$instanceName"
    ## Warn if the authorization token was not captured.
    if [[ -z "$AuthToken" ]]
    then
     ScriptLogging "WARNING: Authorization Token has no value."
     ScriptLogging "WARNING: API calls will not execute for this $current_JSS_URL"
     continue
    else
      apiAuth=$(echo "Authorization: Bearer $AuthToken")
    fi
    ## Explicitly set the token value so that data is not visible anymore
    Token=""
  else
    ScriptLogging "Current API Token still valid not renewing."
  fi
else
  ScriptLogging "No JSS Version detected"
fi
}

downloadJSONObjects(){

for instanceName in $(cat $InstanceList)
do
  instanceName=$(echo "$instanceName" | tr '[:upper:]' '[:lower:]')
  ## Check an instances's header codes to see if it is actually up. If curl returns any header information
  ## we assume the instance is up if not we assume the instance is down. We use the silent option to express
  ## any extraneous curl output and pipe the results to only return the first line of the head so it can fit in a variable neatly
  InstanceExists=$(curl --silent "$instanceName/healthCheck.html")

  if [[ "$InstanceExists" == "[]" ]]
  then
   ##Add the API prefix the the entered instance(s)
   DomainName=$(echo $instanceName | awk -F "//" '{print $2}')
   JamfClassicAPIURL="$instanceName/JSSResource"
   ScriptLogging "Backing up objects from $instanceName in JSON format."

   for ObjectTypeName in "${JSSObjectArray[@]}"
   do 
    #Some Jamf API records include an underscore which we pass in as the name above BUT the associated api endpoint does not have
    #an underscore nor do we want it for certain naming conventions so we remove it.
    ObjectType=$(echo "$ObjectTypeName" | sed -e 's/_//g')
    ScriptLogging "$(echo $ObjectTypeName | tr '[:lower:]' '[:upper:]') now backing up in JSON format."

    ## Reset the content warning flag so we can warn (only once) if an object does not have separate content available for download
    ContentWarningFlag="on"

    #Run the API Authorization Header function to either get or check for a valid token
    makeAuthHeader "$apiUser" "$apiPass"
    if [[ -z "$AuthToken" ]]
    then
     continue
    fi

    ## Create the backup folders
    createBackupFolder json

    ## Get the total number of objects to download
    ObjectSize=$(curl -s -H "$apiAuth" -X GET "$JamfClassicAPIURL/$ObjectType" -H "accept: text/xml" | xmllint --xpath  "$ObjectTypeName/size/text()" -)

    ##Get the object names and id numbers
    if [[ "$ObjectTypeName" == "accounts" ]]
    then
      curl -s -H "$apiAuth"  -X GET "$JamfClassicAPIURL/accounts" -H "accept: application/json" > "$TempFolder"/JSS_"$ObjectType"_TEMP.txt 2>/dev/null
      jq -r ".accounts.users[] | .name + \"_API_SEPARATOR_\" + (.id|tostring) + \"_API_SEPARATOR_\" + \"userid\"" "$TempFolder"/JSS_"$ObjectType"_TEMP.txt > "$TempFolder"/JSS_"$ObjectType".txt 2>/dev/null
      jq -r ".accounts.groups[] | .name + \"_API_SEPARATOR_\" + (.id|tostring) + \"_API_SEPARATOR_\" + \"groupid\"" "$TempFolder"/JSS_"$ObjectType"_TEMP.txt >> "$TempFolder"/JSS_"$ObjectType".txt 2>/dev/null
    else
      curl -s -H "$apiAuth" -X GET "$JamfClassicAPIURL/$ObjectType" -H "accept: application/json" | jq -r ".$ObjectTypeName[] | .name + \"_API_SEPARATOR_\" + (.id|tostring)" > "$TempFolder"/JSS_"$ObjectType".txt 2>/dev/null
    fi
    ScriptLogging "Cleaning up and formatting JSON files for: $(echo $ObjectType | tr '[:lower:]' '[:upper:]')"
    while read row
    do
     ObjectName=$(echo "$row" | awk -F "_API_SEPARATOR_" '{gsub(/\//,"|");gsub(/\:/,"-"); print $1}')
     Objectid=$(echo "$row" | awk -F "_API_SEPARATOR_" '{print $2}')
     AccountType=$(echo "$row" | awk -F "_API_SEPARATOR_" '{print $3}')

     #https://www.ditig.com/jq-recipes
     if [[ "$ObjectTypeName" == "computer_groups" ]]
     then
       curl -s -H "$apiAuth" -H "accept: application/json" -X GET "$JamfClassicAPIURL/$ObjectType/id/$Objectid" | jq '(.. | select(type == "object")) |= (if .is_smart|tostring == "true" then del(.computers[]) else . end) | del(..|nulls)' > "$TempFolder"/"$ObjectName"-"$Objectid".json 2>/dev/null
     elif [[ "$ObjectTypeName" == "advanced_computer_searches" ]]
     then
       curl -s -H "$apiAuth" -H "accept: application/json" -X GET "$JamfClassicAPIURL/$ObjectType/id/$Objectid" | jq '(.. | select(type == "object")) |= (if .advanced_computer_search != "" then del(.computers) else . end) | del(..|nulls)' > "$TempFolder"/"$ObjectName"-"$Objectid".json 2>/dev/null
     elif [[ "$ObjectTypeName" == "accounts" ]]
     then
       #Delete the id key value pair anywhere only from 3 places in the accounts json file so we preserve the id of the LDAP server if it exists. Also delete the hashed password from accounts
       curl -s -H "$apiAuth" -H "accept: application/json" -X GET "$JamfClassicAPIURL/accounts/$AccountType/$Objectid" | jq 'del( .account.id, .group.id, .group.site.id, .account.password_sha256 )' > "$ObjectFolder"/"$ObjectName"-"$Objectid".json
     else
       curl -s -H "$apiAuth" -H "accept: application/json" -X GET "$JamfClassicAPIURL/$ObjectType/id/$Objectid" > "$TempFolder"/"$ObjectName"-"$Objectid".json 2>/dev/null
     fi

     #Delete the id key value pair in the json file
     if [[ "$ObjectTypeName" != "accounts" ]]
     then
       #Delete the id key value pair anywhere in the json file
       jq '(.. | select(type == "object")) |= del (.id)' "$TempFolder"/"$ObjectName"-"$Objectid".json > "$ObjectFolder"/"$ObjectName"-"$Objectid".json
     fi

     ## Download just the code without the json data and store it separately. This could prob be cleaner.
     if [[ "$ContentPrompt" == "y" ]]
     then
       if [[ "$ObjectTypeName" == "computer_extension_attributes" ]]
       then 
         DownloadPath=".computer_extension_attribute.input_type.script"
         curl -s -H "$apiAuth" -H "accept: application/json" -X GET "$JamfClassicAPIURL/$ObjectType/id/$Objectid"  |  jq -r "$DownloadPath" > "$ObjectFolder"/"$ObjectType"_Contents_NotEncoded/"$ObjectName"-"$Objectid".sh
       elif [[ "$ObjectTypeName" == "scripts" ]]
       then
         DownloadPath=".script.script_contents"
         curl -s -H "$apiAuth" -H "accept: application/json" -X GET "$JamfClassicAPIURL/$ObjectType/id/$Objectid"  |  jq -r "$DownloadPath" > "$ObjectFolder"/"$ObjectType"_Contents_NotEncoded/"$ObjectName"-"$Objectid".sh
         elif [[ "$ContentWarningFlag" == "on" ]]
       then
         ScriptLogging "$(echo $ObjectType | tr '[:lower:]' '[:upper:]') does not have separate content available for download."
         ContentWarningFlag="off"
       fi
     fi
    ## End the individual object download while loop
    done < "$TempFolder"/JSS_"$ObjectType".txt

   ## Object Temporary folder cleanup
   rm -rf "$TempFolder"

   ## End object download for loop
   done

  else 
    ScriptLogging "$instanceName is currently unreachable."
    continue
  fi
## End instance check for loop
done

}

downloadXMLObjects(){

## Use a here doc to Create an xslt template file that is used to format the XMLoutputed from the JSS.
cat <<EOF > "$BackupFolderTemp"/JSS_template.xslt
<?xml version="1.0" encoding="ISO-8859-1"?>
<xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
<xsl:output method="text"/>
<xsl:template match="@* | node()"><!--Start a Search -->
            <xsl:for-each select="//*"> <!--//* allows us transverse the entire xml tree until we get to the speicifed element-->
            <xsl:if test="name[text()!='']">
            <xsl:value-of select="name"/> <!-- Find the value of a tag -->
            <xsl:text>_API_SEPARATOR_</xsl:text> <!-- Insert a ? into the output -->
            <xsl:value-of select="id"/> <!-- Find the value of a tag -->
               <xsl:choose> <!-- start choose (if/else) statement -->
                <xsl:when test="name() = 'user'"> <!-- Get the name of tag IF it matches user -->
                 <xsl:text>_API_SEPARATOR_</xsl:text> <!-- Insert a ? into the output -->
                 <xsl:text>userid</xsl:text> <!-- Insert a ? into the output -->
                 </xsl:when>
                 <xsl:when test="name() = 'group'">
                 <xsl:text>_API_SEPARATOR_</xsl:text> <!-- Insert a ? into the output -->
                 <xsl:text>groupid</xsl:text> <!-- Insert a ? into the output -->
                </xsl:when>
               </xsl:choose>
            <xsl:text>&#xa;</xsl:text> <!-- Insert a line break into the output -->
            </xsl:if> <!-- Close the first if statement -->
            </xsl:for-each> <!-- Close the for each statement statement -->
</xsl:template> <!-- Close the template -->
</xsl:stylesheet>
EOF


cat <<EOF > "$BackupFolderTemp"/JSS_template2.xslt
<?xml version="1.0" encoding="ISO-8859-1"?>
<xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
<xsl:output omit-xml-declaration="yes" indent="yes"/> <!-- Maintain the xml indentation after any edits -->
<xsl:strip-space elements="*"/> <!-- Remove any white space (blank lines) around deleted elements -->
<xsl:template match="@* | node()"> <!-- This template looks at all the nodes in the file and applies the idivdual statements below -->
  <xsl:copy>
    <xsl:apply-templates select="@* | node()"/>
  </xsl:copy>
</xsl:template>

    <xsl:template match="advanced_computer_search/computers"/>
    <xsl:template match="*[is_smart='true']/computers"/> <!-- If the is_smart element has a value of true remove the computers node -->
    <xsl:template match="id"/> <!-- Each line is a node in the xml file to delete -->
    <xsl:template match="password_sha256"/>
</xsl:stylesheet>
EOF

for instanceName in $(cat $InstanceList)
do
  instanceName=$(echo "$instanceName" | tr '[:upper:]' '[:lower:]')
  ## Check an instances's header codes to see if it is actually up. If curl returns any header information
  ## we assume the instance is up if not we assume the instance is down. We use the silent option to express
  ## any extraneous curl output and pipe the results to only return the first line of the head so it can fit in a variable neatly
  InstanceExists=$(curl --silent "$instanceName/healthCheck.html")

  if [[ "$InstanceExists" == "[]" ]]
  then
    ##Add the API prefix the the entered instance(s)
    DomainName=$(echo $instanceName | awk -F "//" '{print $2}')
    JamfClassicAPIURL="$instanceName/JSSResource"
    ScriptLogging "Backing up objects from $instanceName in XML format."

    for ObjectTypeName in "${JSSObjectArray[@]}"
    do 
     #Some Jamf API records include an underscore which we pass in as the name above BUT the associated api endpoint does not have
     #an underscore nor do we want it for certain naming conventions so we remove it.
     ObjectType=$(echo "$ObjectTypeName" | sed -e 's/_//g')
     ScriptLogging "$(echo $ObjectTypeName | tr '[:lower:]' '[:upper:]') now backing up in XML format."

     ## Reset the content warning flag so we can warn (only once) if an object does not have separate content available for download
     ContentWarningFlag="on"

    #Run the API Authorization Header function to either get or check for a valid token
    makeAuthHeader "$apiUser" "$apiPass"
    if [[ -z "$AuthToken" ]]
    then
     continue
    fi

     ## Create the backup folders
     createBackupFolder xml

     ## Get the total number of objects to download
     ObjectSize=$(curl -s -H "$apiAuth" -X GET "$JamfClassicAPIURL/$ObjectType" -H "accept: text/xml" | xmllint --xpath  "$ObjectTypeName/size/text()" - 2>/dev/null)

     ## Get the object names and id numbers
     curl -s -H "$apiAuth" -H "accept: text/xml"  "$JamfClassicAPIURL/$ObjectType" -X GET > "$TempFolder"/JSS_"$ObjectType".xml 2>/dev/null

     ## Apply the second XSLT template which deletes unnecessary objects in the XML
     ScriptLogging "Cleaning up and formatting XML files for: $(echo $ObjectType | tr '[:lower:]' '[:upper:]')"
     xsltproc "$BackupFolderTemp"/JSS_template.xslt "$TempFolder"/JSS_"$ObjectType".xml > "$TempFolder"/JSS_"$ObjectType".txt 2>/dev/null

     while read row
     do
      ObjectName=$(echo "$row" | awk -F "_API_SEPARATOR_" '{gsub(/\//,"|");gsub(/\:/,"-"); print $1}')
      Objectid=$(echo "$row" | awk -F "_API_SEPARATOR_" '{print $2}')
      AccountType=$(echo "$row" | awk -F "_API_SEPARATOR_" '{print $3}')

      if [[ -z "$AccountType" ]]
      then
        curl -s -H "$apiAuth" -H "accept: text/xml" -X GET "$JamfClassicAPIURL/$ObjectType/id/$Objectid" > "$TempFolder"/"$ObjectName"-"$Objectid".xml
      else
        curl -s -H "$apiAuth" -H "accept: text/xml" -X GET "$JamfClassicAPIURL/$ObjectType/$AccountType/$Objectid" > "$TempFolder"/"$ObjectName"-"$Objectid".xml
      fi

      ##Remove any elements (as specified by template2) from the XML files and copy the resulting and final XML to a new file.
      xsltproc "$BackupFolderTemp"/JSS_template2.xslt "$TempFolder"/"$ObjectName"-"$Objectid".xml > "$ObjectFolder"/"$ObjectName"-"$Objectid".xml 2>/dev/null

      ## Download just the code without the json data and store it separately. This could prob be cleaner.

      if [[ "$ContentPrompt" == "y" ]]
      then
        if [[ "$ObjectTypeName" == "computer_extension_attributes" ]]
        then 
          DownloadPath="string(/computer_extension_attribute/input_type/script)"
          curl -s -H "$apiAuth" -H "accept: text/xml" -X GET "$JamfClassicAPIURL/$ObjectType/id/$Objectid"  | xmllint --xpath "$DownloadPath" - > "$ObjectFolder"/"$ObjectType"_Contents_NotEncoded/"$ObjectName"-"$Objectid".sh
        elif [[ "$ObjectTypeName" == "scripts" ]]
        then
          DownloadPath="string(/script/script_contents)"
          curl -s -H "$apiAuth" -H "accept: text/xml" -X GET "$JamfClassicAPIURL/$ObjectType/id/$Objectid"  | xmllint --xpath "$DownloadPath" - > "$ObjectFolder"/"$ObjectType"_Contents_NotEncoded/"$ObjectName"-"$Objectid".sh
        elif [[ "$ContentWarningFlag" == "on" ]]
        then
          ScriptLogging "$(echo $ObjectType | tr '[:lower:]' '[:upper:]') does not have separate content available for download."
          ContentWarningFlag="off"
        fi
      fi
     ## End the individual object download while loop
     done < "$TempFolder"/JSS_"$ObjectType".txt

     ## Object Temporary folder cleanup
     rm -rf "$TempFolder"

    ## End object download for loop
    done

  else 
    ScriptLogging "$instanceName is currently unreachable."
    continue
  fi
## End instance check for loop
done
}

## This function prints out the how to use the script and its associated options. Will be displayed on error or if no options are specified.
usage(){  
echo ""
echo "    Example usage: /path/to/script.sh -c -x scripts computer_groups"
echo "    Downloads all the scripts and computer groups from Jamf Pro as well as the contents (actual script) associated with the script objects."
echo ""
echo "    A folder to backup objects to, a Jamf URL (or multiple URLs), and a Jamf API user name and password must be defined"
echo "    within the script or as environmental variables otherwise the script will prompt for these items when run."
echo ""
echo "    Available options: -c -a -x -j -h"
echo "    -c: When selected downloads the script content for available objects such as scripts and computer extension attributes."
echo "        This content is downloaded to an additional folder inside the associated object folder."
echo "    -a: Download all available objects from Jamf Pro. Must be followed by -x or -j (or both)"
echo "    -x: Download specified objects from your Jamf servers in XML format."
echo "    -j: Download specified objects from your Jamf servers in JSON format."
echo "    -h: displays this message"
echo ""
echo "    -x and -j must be followed by which object is to be downloaded. Multiple objects may be specified on the command line."
echo "    Available objects to download from Jamf are \"$(for i in "${JSSAllObjectArray[@]}"; do printf "$i " ; done)\""
echo ""
echo "    ** Options -c and -a must be specified before any other option. Both only need to be only specified once** "
echo "    -x and -j may be specified in the same run of the script but each must be followed by an object or objects to download."
echo ""
echo "    Certain options may be strung together. For example \"-cax\" will download all objects and their associated content in XML format."
echo ""
echo "    All downloaded object files are named with their name in Jamf as well as their object ID. All files are placed in folders based on the"
echo "    date they were downloaded, the server they were downloaded from, their object type, and format."
echo ""
}

## Used to handle options that might not have arguments when combined with other options (such as when download all is selected)
## https://stackoverflow.com/questions/11517139/optional-option-argument-with-getopts/57295993#57295993
## https://stackoverflow.com/questions/7529856/retrieving-multiple-arguments-for-a-single-option-using-getopts-in-bash
getopts_get_optional_argument() {
  #Start with a blank JSS Object Array
  unset JSSObjectArray
  ## Keep reading in arguments to script options until another option is found or there are no more arguments.
  until [[ $(eval "echo \${$OPTIND}") =~ ^-.* ]] || [ -z $(eval "echo \${$OPTIND}") ]
  do
    JSSObjectArray+=($(eval "echo \${$OPTIND}"))
    OPTIND=$((OPTIND + 1))
  done     
}

## Set the no arguments value to true. If an argument is passed to getopts it will not only run the functions/options in the while loop
## but it will later set this value to false which will case the usage function to run instead of any code inside the getopts while loop.
no_arguments="true"

while getopts "jxcah" opt; do
## Run this function before any functions or options associated with arguments, which will prompt the user to enter their Jamf information if not found.
## Having this function here means it won't run if there is an error sending options to the script.
## Then set a flag so this function only runs once per script.
    case $opt in 
        c)
            ## User has selected to download associated content with an object
            ContentPrompt="y"
            ContentWarningFlag="on"
            ;;
        a)
            ## User has selected to download all objects in a Jamf instance.
            DownloadAll="yes"
            ScriptLogging "All available objects selected for download."
            ;;
        j)
            ## Run the function to check for multiple arguments, download objcts as JSON and if no arguments found (the array is empty) for JSON download display an error
            getopts_get_optional_argument $@
            if [[ "$DownloadAll" == "yes" ]]
            then
              ScriptLogging "Downloading all objects in JSON format."
              JSSObjectArray=(${JSSAllObjectArray[@]})
            elif [[ -z "${JSSObjectArray[@]}" ]]
            then
            ScriptLogging "-j requires at least one argument from: \"$(for i in "${JSSAllObjectArray[@]}"; do printf "$i " ; done)\""
            exit 0
            fi
            getJamfInformation
            downloadJSONObjects
            ;;
        x)
            ## Run the function to check for multiple arguments, download objcts as JSON and if no arguments found (the array is empty) for JSON download display an error
            getopts_get_optional_argument $@
            if [[ "$DownloadAll" == "yes" ]] 
            then
              ScriptLogging "Downloading all objects in XML format."
              JSSObjectArray=(${JSSAllObjectArray[@]})
            elif [[ -z "${JSSObjectArray[@]}" ]]
            then
            ScriptLogging "-x requires at least one argument from: \"$(for i in "${JSSAllObjectArray[@]}"; do printf "$i " ; done)\""
            exit 0
            fi 
            getJamfInformation
            downloadXMLObjects
            ;;
        h)
           ## Run the help function
           usage
           exit 0
           ;;
        \?)
            ScriptLogging "Invalid Function Argument."
            usage
            exit 0
            ;;
        *)
            ## Displays a message if no argument specified for certain functions
            ScriptLogging "This option requires at least one argument from: \"$(for i in "${JSSAllObjectArray[@]}"; do printf "$i " ; done)\""
            exit 0
            ;;
    esac
no_arguments="false"   
done

## No options were passed to the script so we display the usage function
if [[ "$no_arguments" == "true" ]]
then 
echo ""
echo "This script requires an option."
usage
else
## If no_arguments has been set to false that means the code inside the getopts while loop has run which means removing old folders and temp items can be run
## Remove old backup folders
ScriptLogging "Removing folders older than $DaysOlderThan Days"
find "$BackupFolder"/ -type d -mtime +"$DaysOlderThan" -exec rm -rf {} \; 

## Invalidate any current api tokens just in case
Token=$(curl -s -H "$apiAuth" "${JSS_URL}/api/v1/auth/invalidate-token" -X POST)
AuthToken=""

## Clean up Temp files
rm -rf "$BackupFolderTemp"
rm -rf /tmp/JSS*
fi