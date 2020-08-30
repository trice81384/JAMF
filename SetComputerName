#!/bin/sh

if [ ! -e /etc/ComputerNamed.txt ]
then

#Get the current logged User which is assumed to be the run running Splash Buddy
#We should change this to the Python method

loggedInUser=$(/bin/ls -l /dev/console | /usr/bin/awk '{ print $3 }')
loggedInUID=$(id -u "$loggedInUser")

sleep .5

while [[ "$loggedInUID" -le 500 ]]
do
echo "Current Console user not found."
loggedInUser=$(/bin/ls -l /dev/console | /usr/bin/awk '{ print $3 }')
loggedInUID=$(id -u "$loggedInUser")
done

sleep 1

osascript <<'EOF'
##########!/usr/bin/osascript

# Intialize the ComputerNameLength to false
set ComputerNameLength to false

# Prompt the user to enter a name for the computer which gets stored as text in the variable computer name. Format text box with an icon and a button for the user to click to continue.
set computer_name to text returned of (display dialog "Begining Custom DEP Setup:\n\nEnter Computer Name:" default answer "" with title "Set Computer Name" with icon file "System:Library:CoreServices:CoreTypes.bundle:Contents:Resources:com.apple.imac-unibody-27-no-optical.icns" buttons {"OK"} default button 1)

#Get the count of inputed characters for the computer name.
set Character_Count to count (computer_name)

# If the inputed computer name is greater than 15 characters or blank we keep prompting the user appropriately to re enter the name.
# Once an acceptable name is entered we set the ComputerNameLength variable to true to break out of the while loop.
repeat while ComputerNameLength is false
	if Character_Count is greater than 15 then
		set computer_name to text returned of (display dialog "Computer Name must be less then 15 Characters" default answer "" with title "Computer Name" with icon file "System:Library:CoreServices:CoreTypes.bundle:Contents:Resources:com.apple.imac-unibody-27-no-optical.icns" buttons {"OK"} default button 1)
	else if Character_Count is equal to 0 then
		set computer_name to text returned of (display dialog "Computer Name cannot be blank" default answer "" with title "Computer Name" with icon file "System:Library:CoreServices:CoreTypes.bundle:Contents:Resources:com.apple.imac-unibody-27-no-optical.icns" buttons {"OK"} default button 1)
	else
		set ComputerNameLength to true
	end if
	# Check to see if the computer name contains the word macbook which we will assume means it has a generic name.
	# The positioning of this repeat loop is important inside the name length check. This way it still checks for an invalid length while
	# checking for an invalid name
	repeat while computer_name contains "macbook"
		set computer_name to text returned of (display dialog "Computer Name must not contain the word Macbook" default answer "" with title "Computer Name" with icon file "System:Library:CoreServices:CoreTypes.bundle:Contents:Resources:com.apple.imac-unibody-27-no-optical.icns" buttons {"OK"} default button 1)
	end repeat
	# Check to see if the computer name is set to only imac (all case variations) which we will assume means it has a generic name.
	# We do a check explicitedly for just imac because some computers are actually named with imac in their name.
	# The positioning of this repeat loop is also important inside the name length check. This way it still checks for an invalid length while
	# checking for an invalid name
	repeat while computer_name is equal to "imac"
		set computer_name to text returned of (display dialog "Computer Name must not only be iMac" default answer "" with title "Computer Name" with icon file "System:Library:CoreServices:CoreTypes.bundle:Contents:Resources:com.apple.imac-unibody-27-no-optical.icns" buttons {"OK"} default button 1)
	end repeat
	# We set the character count variable name again so the while loop/if statements
	# can continue if the name is still empty or greater than 15 characters.
	set Character_Count to count (computer_name)
end repeat


# For the do shell script commands we need the full path to the scutil binary which means it should be enclosed in quotes
# so AppleScript interpets the leading / properly. We also have to remember to leave a space after the end of the command because AppleScript
# doesn't insert spaces between the command and the variable automatically.
# We make sure we use the quoted form of the computer_name variable just in case and in order to properly set the name we need to run the scipt with admin privs.

do shell script "/usr/sbin/scutil --set HostName " & quoted form of computer_name with administrator privileges

do shell script "/usr/sbin/scutil --set LocalHostName " & quoted form of computer_name with administrator privileges

do shell script "/usr/sbin/scutil --set ComputerName " & quoted form of computer_name with administrator privileges

do shell script "touch /etc/ComputerNamed.txt" with administrator privileges

do shell script "/usr/local/bin/jamf recon" with administrator privileges
EOF

else
echo "Computer already named via DEP Script"
echo "Removing cached packages if they exist."
## This is to remove the Splash Buddy Package if it downloaded on a previous run as we expect a new one to get installed
## after this script completes so this way there will be no worries about over writing it.
/bin/rm -rf /Library/Application\ Support/JAMF/Waiting\ Room/* &> /dev/null
fi
