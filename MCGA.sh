#!/bin/bash
# Scripted by Mickaël Saavedra - 2019
# uses packages pwgen, jq and lastpass-cli

# to-do: 
# - offer choice to create additional users in the same group once first one done -> done
# - check if maximum user count has been reached every time when creating new user (/rest/license/1.0/license/remainingSeats) -> done
# - consider that the group entered when creating a new user doesn't exist yet and prompt to create it -> done
# - check if username entered is available and if it is, exit to the menu (such cases are better off being handled manually) -> done
# - automatically set correct permissions group<->space upon group creation -> done
# - when adding new group to a space, add check to verify that space entered exists -> done
# - reformat how spaces are displayed (maybe like 5 on one line like [space1] | [space2] ...) -> done
# - when asking what existing group to choose, offer an input to list them all -> done
# - when asking what existing space to choose, offer an input to list them all -> done
# - offer a summary of all new users created to X group at the end (one per line) -> done
# - make sure that checks for username, group & space are case insensitive -> done
# - make sure that when entering a space, the scripts returns it if it doesn't exist and asks for confirmation to create it -> done
# - sanitization of user input (low priority)
# - integrate with lastpassi-cli (create new secure note and share summary of created users automatically)

# Problems:
# - if I successfully create a user, then type the username of an existing user and then go back to creating more users, 
#   the summary array doesn't contain whatever came before the existing username error -> fixed

serverURL=http://localhost:8090
choice=0

remainingSeats()
{
	printf "$(curl -s -u "$confluenceUsername":"$confluencePassword" "$serverURL/rest/license/1.0/license/remainingSeats" | jq -r '.count')"
}

lastPassLogin()
{
	if [[ $(lpass login "$1") == *"Success:"* ]]
	then
		result=true
	else
		result=false
	fi
	printf "$result"
}

createSecureNote()
{
	secureNoteTitle="Confluence $(date +%Y-%m-%d) | Space: $whatSpace"
	for line in "${summary[@]}"; do
    	printf "$line\n"
	done | $(lpass add Grips --non-interactive --sync=now --notes)
}

listSpaces()
{
	readarray -t spaces < <(curl -s -u "$confluenceUsername":"$confluencePassword" "$serverURL/rest/api/space?limit=2000" | jq -r '.results[].name')
	for (( space=0; space<${#spaces[@]}; space++ ))
	do
		if (( ("$space" % 5 == 0 && "$space" != 0) || "$space" == ${#spaces[@]} - 1 ))
		then
			printf "[${spaces[$space]}]\n" 
		else
			printf "[${spaces[$space]}] | " 
		fi
	done	
}

listGroups()
{
	readarray -t existingGroups < <(curl -s -u "$confluenceUsername":"$confluencePassword" "$serverURL/rest/api/group" | jq -r '.results[].name')	
	for (( group=0; group<${#existingGroups[@]}; group++ )) 
	do
		if (( ("$group" % 5 == 0 && "$group" != 0) || "$group" == ${#existingGroups[@]} - 1 ))
		then
			printf "[${existingGroups[$group]}]\n" 
		else
			printf "[${existingGroups[$group]}] | " 
		fi
	done
}

createSpace()
{
	readarray -t keys < <(curl -s -u "$confluenceUsername":"$confluencePassword" "$serverURL/rest/api/space?limit=2000" | jq -r '.results[].key')
	printf "\n"
	read -p "Please enter a key for that space: " enteredKey
	for (( key=0; key<${#keys[@]}; key++ )) 
	do
		if [ "${keys[$key]}" == "$enteredKey" ]
		then
			keyExists=true
		fi
	done
		
	while [ "$keyExists" = true ]
	do
		keyExists=false
		read -p "Please enter another key for that space, as the one entered is already used: " enteredKey
		for (( l=0; l<${#keys[@]}; l++ )) 
		do
			if [ "${keys[$l]}" == "$enteredKey" ]
			then
				keyExists=true
			fi
		done
	done

	if [ "$keyExists" != true ]
	then
		createSpace=$(curl -s -u "$confluenceUsername":"$confluencePassword" -X POST -H 'Content-Type: application/json' -d' { "key":"'$enteredKey'", "name":"'"$1"'", "type":"global"}' "$serverURL/rest/api/space")
		printf "\nThe space '$1' has been created.\n"
	fi
}

createGroup()
{
	createGroup=$(curl -s -u "$confluenceUsername":"$confluencePassword" -X POST -H 'Content-Type: application/json' -d' {"jsonrpc" : "2.0", "method" : "addGroup", "params" : ["'"$1"'"]}' $serverURL/rpc/json-rpc/confluenceservice-v2)	
}

createUser()
{
	# Initalization of variables
	additionalUsers=y
	differentGroup=y
	differentSpace=y
	groupExists=false
	userExists=false
	spaceExists=false
	declare -a summary
	# End of initialization

	while [[ (( "$additionalUsers" == "y" || "$additionalUsers" == "Y" )) && $(remainingSeats) > 0 && "$userExists" = false ]]
	do
		printf "\n$(remainingSeats) seats left.\n\n"
		read -p "Please enter the full name: " fullname
		read -p "Please enter the username: " username
		username=${username,,}
		# Start of username checking #
		if [ $(userExists "$username") = true ]
		then
			printf "\n"
			read -p "This username already exists, best to go look on the web interface for this one. Do you want to create a different user? [y/n] " differentUser
			unset username
			if [[ "$differentUser" == "y" || "$differentUser" == "Y" ]]
			then
				unset fullname
				userExists=false
				continue
			else
				if [ ! ${#summary[@]} -eq 0 ]
				then
					printf "\nSummary of users created:\n"
					echo "---------------------------"
					printf "\n"
					for (( account=0; account<${#summary[@]}; account++ ))
					do
						printf "${summary[$account]}\n"
					done
					printf "\n"
				fi
				menu
			fi
			# End of username checking #
		else
			read -p "Please enter the e-mail address: " email

			# Start of group checking #
			while [[ "$enteredGroup" == "<list>" || "$enteredGroup" == "" || "$differentGroup" == "y" || "$differentGroup" == "Y" ]]
			do
				read -p "Please enter the group to add the user to (type <list> to list current groups): " enteredGroup
				enteredGroup=${enteredGroup,,}
			
				if [ "$enteredGroup" == "<list>" ]
				then
					printf "\n"
					listGroups
					printf "\n"
					continue
				fi

				if [[ $(groupExists "$enteredGroup") = false && "$enteredGroup" != "<list>" ]]
				then
					printf "\n"
					read -p "This group does not yet exist. Would you like to create it? [Y/n] " groupCreation
					if [[ "$groupCreation" == "y" || "$groupCreation" == "Y"  || "$groupCreation" == "" ]]
					then
						createGroup "$enteredGroup"
						break
					else
						printf "\n"
						read -p "Ok. Do you want to try with a different group? [y/n] " differentGroup
						if [[ "$differentGroup" == "y" || "$differentGroup" == "Y" ]]
						then
							printf "\n"
							continue
						else
							printf "\nExiting to menu.\n"
							menu
						fi
					fi
				else
					break
				fi
			done
			# End of group checking #

			# Start of space checking #
			while [[ "$whatSpace" == "<list>" || "$whatSpace" == "" || "$differentSpace" == "y" || "$differentSpace" == "Y" ]]
			do
				read -p "Please enter the space to add the group $enteredGroup to (type <list> to list current spaces): " whatSpace
			
				if [ "$whatSpace" == "<list>" ]
				then
					printf "\n"
					listSpaces
					printf "\n"
					continue
				fi

				if [[ $(spaceExists "$whatSpace") = false && "$whatSpace" != "<list>" ]]
				then
					printf "\n"
					read -p "This space does not yet exist. Would you like to create it? [Y/n] " spaceCreation
					if [[ "$spaceCreation" == "y" || "$spaceCreation" == "Y"  || "$spaceCreation" == "" ]]
					then
						createSpace "$whatSpace"
						break
					else
						printf "\n"
						read -p "Ok. Do you want to try with a different space? [y/n] " differentSpace
						if [[ "$differentSpace" == "y" || "$differentSpace" == "Y" ]]
						then
							printf "\n"
							continue
						else
							printf "\nExiting to menu.\n"
							menu
						fi
					fi
				else
					break
				fi
			done
			# End of space checking #

			password=$(pwgen -s -1 16)
			createUser=$(curl -s -u "$confluenceUsername":"$confluencePassword" -X POST -H 'Content-Type: application/json' -d' {"jsonrpc" : "2.0", "method" : "addUser", "params" : [{"email":"'"$email"'","fullname":"'"$fullname"'","name":"'"$username"'"}, "'"$password"'"], "id" : 0}' $serverURL/rpc/json-rpc/confluenceservice-v2)
			addToGroup=$(curl -s -u "$confluenceUsername":"$confluencePassword" -X POST -H 'Content-Type: application/json' -d' {"jsonrpc" : "2.0", "method" : "addUserToGroup", "params" : ["'"$username"'", "'"$enteredGroup"'"]}' $serverURL/rpc/json-rpc/confluenceservice-v2)
			# Setting correct permissons group<>space #
			curl -s -u "$confluenceUsername":"$confluencePassword" -X POST -H 'Content-Type: application/json' -d' {"jsonrpc" : "2.0", "method" : "addPermissionToSpace", "params" : ["EDITBLOG", "'"$enteredGroup"'", "'"$enteredKey"'"]}' $serverURL/rpc/json-rpc/confluenceservice-v2
			curl -s -u "$confluenceUsername":"$confluencePassword" -X POST -H 'Content-Type: application/json' -d' {"jsonrpc" : "2.0", "method" : "addPermissionToSpace", "params" : ["COMMENT", "'"$enteredGroup"'", "'"$enteredKey"'"]}' $serverURL/rpc/json-rpc/confluenceservice-v2
			curl -s -u "$confluenceUsername":"$confluencePassword" -X POST -H 'Content-Type: application/json' -d' {"jsonrpc" : "2.0", "method" : "addPermissionToSpace", "params" : ["CREATEATTACHMENT", "'"$enteredGroup"'", "'"$enteredKey"'"]}' $serverURL/rpc/json-rpc/confluenceservice-v2
			curl -s -u "$confluenceUsername":"$confluencePassword" -X POST -H 'Content-Type: application/json' -d' {"jsonrpc" : "2.0", "method" : "addPermissionToSpace", "params" : ["EDITSPACE", "'"$enteredGroup"'", "'"$enteredKey"'"]}' $serverURL/rpc/json-rpc/confluenceservice-v2
			curl -s -u "$confluenceUsername":"$confluencePassword" -X POST -H 'Content-Type: application/json' -d' {"jsonrpc" : "2.0", "method" : "addPermissionToSpace", "params" : ["VIEWSPACE", "'"$enteredGroup"'", "'"$enteredKey"'"]}' $serverURL/rpc/json-rpc/confluenceservice-v2
			# End of permissions setting #
			printf "\nfull name: '$fullname' | email address: '$email' | login: '$username' | password: '$password'\n\n"
			summary+=("full name: '$fullname' | email address: '$email' | login: '$username' | password: '$password'")
			read -p "Would you like to create additional users and add them to this group? [N/y] " additionalUsers

			unset fullname
			unset username
			unset password
			unset email
			unset enteredGroup
			unset enteredKey
			if [[ "$additionalUsers" == "" || "$additionalUsers" == "n" || "$additionalUsers" == "N" ]]
			then
				printf "\nSummary of users created:\n"
				echo "---------------------------"
				printf "\n"
				for (( account=0; account<${#summary[@]}; account++ ))
				do
						printf "${summary[$account]}\n"
				done
				printf "\n"
				read -p "Please enter your LastPass email address to login and create the Secure Note: " lastPassEmail
				if [ $(lastPassLogin "$lastPassEmail") = true ]
				then
					createSecureNote
					unset whatSpace
				else
					printf "Login failed."
				fi 
				unset lastPassEmail
				menu
			fi
		fi
	done
	printf "You have reached the maximum user count. Create a ticket!"
}

userExists()
{
	userExists=false
	userCheck=$(curl -s -u "$confluenceUsername":"$confluencePassword" "$serverURL/rest/api/user?username=$1" | jq -r '.username')
	if [ "$userCheck" = "${1,,}" ] # only works with bash > v4, used to basically ignore case
	then
		userExists=true
	fi
	printf $userExists
}

spaceExists() # returns true or false depending on whether the space entered as $1 already exists or not
{
	spaceExists=false
	readarray -t spaces < <(curl -s -u "$confluenceUsername":"$confluencePassword" "$serverURL/rest/api/space?limit=2000" | jq -r '.results[].name')
	for (( space=0; space<${#spaces[@]}; space++ )) 
	do
		if [ "${spaces[$space],,}" = "${1,,}" ] # only works with bash > v4, used to basically ignore case
		then
			spaceExists=true
		fi
	done
	printf $spaceExists
}

groupExists()
{
	groupExists=false
	groupCheck=$(curl -s -u "$confluenceUsername":"$confluencePassword" "$serverURL/rest/api/group/$1" | jq -r '.name')
	if [ "$groupCheck" = "${1,,}" ] # only works with bash > v4, used to basically ignore case
	then
		groupExists=true
	fi
	printf $groupExists
}

menu()
{
	while [ $choice != 4 ]
	do
		printf "\nHere are your options:\n\n"
		echo "1) List current spaces"
		echo "2) Create a new space"
		echo "3) Create new user(s)"
		echo "4) Quit"
		printf "\n"
		read -p "Choice: " choice

		if (( $choice == 1 )) 
		then
			printf "\nHere's the list of the current spaces:\n\n"
			listSpaces
		fi

		if (( $choice == 2 )) 
		then
			anotherSpace=y
			printf "\n"
			readarray -t spaces < <(curl -s -u "$confluenceUsername":"$confluencePassword" "$serverURL/rest/api/space?limit=2000" | jq -r '.results[].name')
			readarray -t keys < <(curl -s -u "$confluenceUsername":"$confluencePassword" "$serverURL/rest/api/space?limit=2000" | jq -r '.results[].key')
			read -p "What is the name of the space you would like to create? " enteredSpace
			while [ $(spaceExists "$enteredSpace") = true ]
			do
				printf "\n"
				read -p "The space already exists. Do you want to create another space? [Y/n] " anotherSpace
				if [[ "$anotherSpace" == "" || "$anotherSpace" == "Y" || "$anotherSpace" == "Y" ]]
				then
					read -p "What is the name of the space you would like to create? " enteredSpace
				else
					printf "\nExiting to menu.\n"
					menu
				fi
			done
			if [ $(spaceExists "$enteredSpace") = false ]
			then
				createSpace "$enteredSpace"	
			fi
		fi

		if (( $choice == 3 ))
		then
			createUser
		fi
	done

	if (( $choice == 4 ))
	then 
		printf "Servus!\n"
		exit
	fi
}

statusCode()
{
	username=$1
	password=$2
	response=$(curl -s -u $username:$password --write-out %{http_code} --silent --output /dev/null "$serverURL")
	if (( $response == "200" ))
	then
		return 1
	else
		return 0
	fi
}

login()
{
	statusCode $1 $2
	status=$?
	if [[ $status == "1" ]]
	then
		printf "Login successful."
	else
		printf "Login failed."
	fi
}

read -p "Please authenticate with your confluence username: " confluenceUsername
read -s -p "Please enter your confluence password: " confluencePassword

while [ "$(login $confluenceUsername $confluencePassword)" != "Login successful." ]
do
	printf "\n"
	read -p "Incorrect credentials. Please re-enter your username: " confluenceUsername
	read -s -p "Please re-enter your password: " confluencePassword
	printf "\n"
	clear
done

menu


