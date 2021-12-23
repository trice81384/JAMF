# A collection of scripts for use with JAMF Pro

## The API_Scripts folder contains scripts used to manipulate Jamf objects via the api

## The macOS Scripts should are intended to be used as follows:
1. macOSUpgrades_CheckCachedInstaller: Used to stage and validate a macOS installer package on a client computer for future installation.
2. macOSUpgrades: Used to prompt a user to install a cached macOS installer package and force the installation after x number of attempts.
3. macOSUpgrades_SelfService: Allows a user to install a cached macOS installer package from Self Service. Can be used in conjunction with macOSUpgrades or by itself.

### Once running macOSUpgrades and macOSUpgrades_SelfService administrators should stop running or disable macOSUpgrades_CheckCachedInstaller
### These scripts assume the macOS Installer is wrapped in a pkg for initial download/caching. While other packaging methods such as DMGs can be used they will require additional steps in order to be supported by these scripts.
