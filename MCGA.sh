#!/bin/bash
# Scripted by Mickaël Saavedra - 2019
# uses packages pwgen, jq and maybe lastpass-cli

# to-do: 
# - offer choice to create additional users in the same group once first one done -> done
# - check if maximum user count has been reached every time when creating new user (/rest/license/1.0/license/remainingSeats) -> done
# - offer a summary of all new users created to X group at the end (one per line)
# - consider that the group entered when creating a new user doesn't exist yet and prompt to create it
# - sanitization of user input

serverURL=http://localhost:8090
choice=0

remainingSeats()
{
	printf "$(curl -s -u "$confluenceUsername":"$confluencePassword" "$serverURL/rest/license/1.0/license/remainingSeats" | jq -r '.count')"
}

createUser()
{
	while (( $(remainingSeats) > 0 ))
	do
		printf "\n$(remainingSeats) seats left.\n\n"
		additionalUsers=y
		while [[ "$additionalUsers" == "y" || "$additionalUsers" == "Y" ]]
		do
			read -p "Please enter the full name: " fullname
			read -p "Please enter the username: " username
			read -p "Please enter the e-mail address: " email
			read -p "Please enter the group to add the user to: " group
			#while [ ] # execute loop if group doesn't yet exist
			#do
			#done
			password=$(pwgen -s -1 16)
			createUser=$(curl -s -u "$confluenceUsername":"$confluencePassword" -X POST -H 'Content-Type: application/json' -d' {"jsonrpc" : "2.0", "method" : "addUser", "params" : [{"email":"'"$email"'","fullname":"'"$fullname"'","name":"'"$username"'"}, "'"$password"'"], "id" : 0}' http://localhost:8090/rpc/json-rpc/confluenceservice-v2)
			addToGroup=$(curl -s -u "$confluenceUsername":"$confluencePassword" -X POST -H 'Content-Type: application/json' -d' {"jsonrpc" : "2.0", "method" : "addUserToGroup", "params" : ["'"$username"'", "'"$group"'"]}' http://localhost:8090/rpc/json-rpc/confluenceservice-v2)
			printf "User '$username' has been created with the password '$password' and added to the group '$group'.\n\n"
			read -p "Would you like to create additional users and add them to this group? [N/y] " additionalUsers
		done
	done
	printf "You have reached the maximum user count. Create a ticket!"
}

createSpace()
{
	printf "\n"
	readarray -t spaces < <(curl -s -u "$confluenceUsername":"$confluencePassword" "$serverURL/rest/api/space?limit=2000" | jq -r '.results[].name')
	readarray -t keys < <(curl -s -u "$confluenceUsername":"$confluencePassword" "$serverURL/rest/api/space?limit=2000" | jq -r '.results[].key')
	read -p "What is the name of the space you would like to create? " enteredSpace

	for (( k=0; k<${#spaces[@]}; k++ )) 
	do
		if [ "${spaces[$k]}" == "$enteredSpace" ]
		then
			exists=true
		fi
	done

	if [ "$exists" = true ]
	then
		printf "\nThe space '$enteredSpace' already exists.\n\n"
		exists=false
	else
		printf "\n"
		read -p "Please enter a key for that space: " enteredKey
		for (( l=0; l<${#keys[@]}; l++ )) 
		do
			if [ "${keys[$l]}" == "$enteredKey" ]
			then
				keyExists=true
			fi
		done
		while [ keyExists=true ] #buggy, to be looked at
		do
			keyExists=false
			read -p "Please enter another key for that space, as it's already being used: " enteredKey
		done
		createSpace=$(curl -s -u "$confluenceUsername":"$confluencePassword" -X POST -H 'Content-Type: application/json' -d' { "key":"'$spaceKey'", "name":"'"$enteredSpace"'",
"type":"global"}' "$serverURL/rest/api/space")
		printf "\nThe space "'"$enteredSpace"'" has been created.\n"
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
		readarray -t spaces < <(curl -s -u "$confluenceUsername":"$confluencePassword" "$serverURL/rest/api/space?limit=2000" | jq -r '.results[].name')

		for (( j=0; j<${#spaces[@]}; j++ )) 
		do
			echo "- ${spaces[$j]}"
		done
	fi

	if (( $choice == 2 )) 
	then
		createSpace
	fi

	if (( $choice == 3 )) # need to sanitize the inputs and make use of pwgen
	then
		createUser
	fi
done

if (( $choice == 4 ))
then 
	exit
fi
