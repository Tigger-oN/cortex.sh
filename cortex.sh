#!/bin/sh
# 
# A manager for Gemini CLI. The objectives for the shell script is to:
# - List and manage a number of persona's or Gemini.md files
# - Display an overview of "game state" for each persona, like when
#   was the last save.
# - An option to edit or preview the persona and the game state files.
# - Each persona also has a possible "storage" and "wip" space 
#   which is used for misc files, docs any anything else related to the
#   persona.
#
# Sample structure for ~/.cortex.sh/persona
# /My_Amazing_Friend          <= The base directory. Gemini will start here.
#   + My_Amazing_Friend.md    <= The Gemini.md / System Instructions file. This
#   							 script will read the "SYSTEM INSTRUCTION" line
#								 as the title for the persona. For Gemini CLI, 
#								 this is a context file that provides
#								 persistent, project-specific instructions and
#								 context to the Gemini model.
#   + persona.rc              <= Options to pass to gemini when starting.
#                                NOT CURRENTLY USED. Will see if needed.
#   + /store				  <= A storage space for persona related files.
#   + /wip                    <= A "working" directory. 
# /Shell_Script_Guru          <= Another directory for a different persona.

# A simple version number to keep track of possible changes.
VERSION="20251202"

# Everything is kept local to the current user. This makes sense as the user
# needs to be authorised to use Gemini CLI. BASE is a directory where
# everything is stored.
BASE="${HOME}/.cortext.sh"
# There are a few options that can be customised. All keep in here.
BASE_RC="${HOME}/.cortext.sh/cortext.sh.rc"

# Horizontal rule
HR="---------------------------------------------------------------------"

# This will be set to the selected persona.md file.
PERSONA=""

# Persona location. Each persona will have a directory that holds the key files
# and any storage space for saved data.
PERSONA_BASE="${BASE}/persona"

# The selected persona RC could be used to override any defaults from main RC. 
# CURRENTLY NOT USED.
#PERSONA_RC=""

# We need an editor for a few things. This is set in the main RC.
PERSONA_EDITOR=""

usage () {
	app="${0##*/}"
	out="
Manage a group of persona (system instructions) for Gemin CLI.

Usage: ${app} [ -hv | persona ]

 -h      : Show this help and exit.
 -v      : Display some system details such as the number of persona 
           files and the version number of this script. Then exit.
 persona : Jump straight to loading this persona. Can be part of a 
           persona name, or the full name. If only part of a name is 
           used and there is a match for more than one persona, each 
           match will be shown.

By default a list of personas will be displayed with the option to make
a new one, load, edit or remove any existing personas.

Passing part of an existing persona name will load Gemini CLI with that 
persona, bypassing any editing options.

Version:   ${VERSION}

"
	printf "%s\n" "${out}"
	exit 0
}

# A quit option where there is no issue
quit () {
	if [ -n "${1}" ]
	then
		printf "\n%s\n\n" "${1}"
	else
		printf "\nCancelling as requested\n\n"
	fi
	exit 0
}
# Generic error
invalidOpt () {
	if [ -n "${1}" ]
	then
		printf "\n%s\n\n" "${1}"
	else
		printf "\nInvalid option. Assuming cancellation requested.\n\n"
	fi
	exit 1
}
# Check if ${1} is a number.
isNumber () {
	case "${1}" in
		''|*[!0-9]*) printf "no\n";;
		*) printf "yes\n";;
	esac
}
# Make sure the environment is setup
sysCheck () {
	ERR=""
	printf "\nChecking the basics.\n"

	# Gemini relies on node.js which relies on the nvm environment set-up.
	# We can try to detect this, but it is not an error if missing.
	if [ -z "${NVM_DIR}" -a -d "${HOME}/.nvm" ]
	then
		# Set NVM directory environment variable
		export NVM_DIR="${HOME}/.nvm"
	fi

	# Check if nvm.sh exists and source it if it does
	# This is more of a safety check. For most people this should be redunant.
	# For people not running bash, it could be needed.
	[ -s "${NVM_DIR}/nvm.sh" ] && \. "${NVM_DIR}/nvm.sh"

	# Make sure gemini can be started
	if ! command -v gemini > /dev/null 2>&1
	then
		ERR="${ERR}
 - Unable to locate \"gemini\" in your path. Have you installed it?
   If \"yes\" then there could be a path or environment issue. Try again
   after typing the following (this is only a guess):

    bash
    source ~/.profile
"
	fi
	# We also need to be able to confirm that Gemini has been logged in
	# previously. On a headless system, this could be a difficult task. It will
	# be up to the user to fix this if there is an issue, but we might be able
	# to do a basic check.
	if [ ! -d "${HOME}/.gemini" ]
	then
		ERR="${ERR}
 - Highly possible you have never started Gemini CLI previously. You
   will need to start Gemini CLI at least once, and login successfully
   before using cortex.sh
"
	else
		if [ -f "${HOME}/.gemini/google_accounts.json" ] || [ -n "${GEMINI_API_KEY}" ]
		then
			# Strong chance member has used and logged in to Gemini CLI
			:
		else
			ERR="${ERR}
 - Unable to location a Gemini CLI Authentication file or exported API
   Key. Please make sure you can start and run Gemini CLI, then restart
   cortex.sh.
"
		fi
	fi

	# Go no further on an error.
	if [ -n "${ERR}" ]
	then
		printf "\nError:\n%s\n\n" "${ERR}" >&2
		exit 1
	fi
	# And we need a persona directory.
	if [ ! -d "${PERSONA_BASE}" ]
	then
		printf "\nMaking a home base for personas.\n"
		mkdir -p "${PERSONA_BASE}"
		if [ ${?} -eq 0 ]
		then
			printf "\nIf you have any pre-existing personas you can now place them in:\n\n   %s\n" "${PERSONA_BASE}"
		else
			printf "\nIssue creating the home base. Was trying to make this directory:\n\n   %s\n" "${PERSONA_BASE}" >&2
			exit 1
		fi
	fi
	# There are a few options that can be, stored in an RC
	if [ ! -f "${BASE_RC}" ]
	then
		# Write a blank
		out="# The cortext.sh.rc can be used to override a few options. They are:
#
# Your text editor of choice. A full path to the editor.
# PERSONA_EDITOR=\"/path/to/editor\"
#
# The \"home\" for your personas. Default: ~/.cortext.sh/persona
# PERSONA_BASE=\"\"
"
		printf "%s" "${out}" > "${BASE_RC}"
	fi
}

# Need to have an editor for a number of functions. Options to check for are:
# Common: vi, vim, emacs, nano, pico
# Trending: helix, kakoune, nvim, micro, tilde
# Custom? Guess should offer up an option to add something else too.
editorCheck () {
	printf "\nChecking for a text editor.\n"
	if [ -n "${PERSONA_EDITOR}" ]
	then
		if [ -f "${PERSONA_EDITOR}" ]
		then
			printf "\nEditor found: %s\n" "${PERSONA_EDITOR##*/}"
			return 0
		else
			printf "\nUnable to locate the requested editor. Was looking for:\n\n  %s\n\nWill look for a default editor.\n" "${PERSONA_EDITOR}"
			PERSONA_EDITOR=""
		fi
	fi
	# Need to pick one.
	ed_test="vi vim emacs nano pico helix kakoune neovim nvim micro tilde"
	ed_list=""
	for e in ${ed_test}
	do
		a="$(command -v "${e}")"
		if [ -n "${a}" ]
		then
			ed_list="${ed_list}${a}
"
		fi
	done
	# let's hope we have at least one to pick from
	if [ -z "${ed_list}" ]
	then
		printf "\nIssue: Unable to locate a text editor. You will need to edit the run\ncommand file and set a text editor manually. The RC file is located:\n  %s\n\n" "${BASE_RC}" >&2
		exit 1
	fi
	# If there is only a single option we still offer the option to see a custom path.
	printf "\nSelect a text editor for updating files.\n\n"
	# Loop the list and offer an option to set a custom one.
	count=1
	IFS="
"
	for e in ${ed_list}
	do
		printf " %2d) %s\n" ${count} "${e##*/}"
		count=$((count + 1))
	done
	unset IFS
	printf "\n%s\nUse [number] | [O]ther | [C]ancel " "${HR}"
	read ans
	if [ "$(isNumber "${ans}")" = "yes" ]
	then
		if [ ${ans} -gt 0 -a ${ans} -lt ${count} ]
		then
			# Need to select an editor
			count=1
			IFS="
"
			for e in ${ed_list}
			do
				if [ ${count} -eq ${ans} ]
				then
					PERSONA_EDITOR="${e}"
					break
				fi
				count=$((count + 1))
			done
			unset IFS
		fi
		if [ -z "${PERSONA_EDITOR}" ]
		then
			printf "\nInvalid editor option. Try again? [Y/n] "
			read ans
			if [ -z "${ans}" -o "${ans}" = "y" -o "${ans}" = "Y" ]
			then
				editorCheck
				return 0
			else
				quit
			fi
		else
			# We have an editor, save it to the RC.
			$(grep -q "PERSONA_EDITOR=" "${BASE_RC}")
			if [ ${?} -eq 0 ]
			then
				# Found, edit existing
				tmp="$(sed "s#.*PERSONA_EDITOR=\".*\"#PERSONA_EDITOR=\"${PERSONA_EDITOR}\"#" "${BASE_RC}")"
				printf "%s\n" "$tmp" > "${BASE_RC}"
			else
				# Missing, add a line
				printf "\n#\n# Your text editor of choice. A full path to the editor.\nPERSONA_EDITOR=\"%s\"\n" "${PERSONA_EDITOR}" >> "${BASE_RC}"
			fi
		fi
	elif [ "${ans}" = "o" -o "${ans}" = "O" ]
	then
		printf "\nYou will need to set the PERSONA_EDITOR value to the full path of the\ntext editor you want use in the run command file. The RC file is\nlocated:\n\n  %s\n\n" "${BASE_RC}"
		exit 0
	elif [ "${ans}" = "c" -o "${ans}" = "C" -o "${ans}" = "q" -o "${ans}" = "Q" ]
	then
		quit
	else
		quit "Invaild request. Canceling as that is the safe option."
	fi
}

# Checks for a persona .md file and extracts the title, or will use the
# directory name.
# ${1} : The persona directory base to check
utilGetTitle () {
	t=""
	if [ -n "${1}" -a -d "${1}" ]
	then
		md=${1##*/}
		if [ -f "${1}/${md}.md" ]
		then
			t="$(sed 's/^# SYSTEM INSTRUCTION: \(.*\) Persona$/\1/; q' "${1}/${md}.md")"
			if [ -z "${t}" ]
			then
				t="$(head -n 1 "${1}/${md}.md" | sed 's/^# *//')"
			fi
		fi
	else
		printf "System issue: utilGetTitle requested without a valid directory.\n\n"
		exit 1
	fi
	if [ -z "${t}" ]
	then
		# Get the title from the directory name
		t="$(printf "%s" "${1##*/}" | sed "s/_/ /g")"
	fi
	printf "%s\n" "${t}"
}

personaList () {
	searchMode=1
	if [ -n "${1}" ]
	then
		searchMode=0
		PERSONA_LIST="$(LC_ALL=C find "${PERSONA_BASE}" -mindepth 1 -maxdepth 1 -type d -iname "*${1}*" -print 2>/dev/null | sort)"
		if [ -z "${PERSONA_LIST}" ]
		then
			printf "\nNo existing persona found for the search option:\n\n  %s\n\nWhat do you want to do now?\n%s\n[L]ist all (default) | [C]ancel " "${1}" "${HR}"
			read ans
			if [ -z "${ans}" -o "${ans}" = "l" -o "${ans}" = "L" -o "${ans}" = "a" -o "${ans}" = "A" ]
			then
				personaList
				return 0
			elif [ "${ans}" = "c" -o "${ans}" = "C" -o "${ans}" = "q" -o "${ans}" = "Q" ]
			then
				quit
			else
				invalidOpt
			fi
		fi
	else
		PERSONA_LIST="$(LC_ALL=C find "${PERSONA_BASE}" -mindepth 1 -maxdepth 1 -type d -print 2>/dev/null | sort)"
	fi
	
	# Do we have any?
	pCount=$(printf "%s\n" "${PERSONA_LIST}" | wc -l)
	if [ ${searchMode} -eq 0 -a ${pCount} -eq 1 ]
	then
		# Jump straight to the requested
		PERSONA="${PERSONA_LIST}"
		personaLoad
	elif [ -n "${PERSONA_LIST}" ]
	then
		personaLoop
	else
		printf "\nUnable to locate any existing persona's.\n"
		personaNew
	fi
}

# For the following calls (load, edit, delete, view) PERSONA must be set to a
# selected persona.md before being called.
personaLoad () {
	printf "\nGetting everything ready to start.\n"
	cd "${PERSONA}"
	# Set the environment
	export GEMINI_SYSTEM_MD="${PERSONA}/${PERSONA##*/}.md"

	# An optional starting point
	printf "\nYour (optional) opening prompt is: [Ctrl+c to cancel]\n\n"
	read ans
	printf "\nStarting Gemini CLI. This can take a moment.\n"
	if [ -n "${ans}" ]
	then
		gemini --prompt-interactive "${ans}"
	else
		gemini
	fi
	exit
}
personaEdit () {
	printf "\nStarting an editor.\n"
	"${PERSONA_EDITOR}" "${PERSONA}/${PERSONA##*/}.md"
	printf "\nWhat to do now?\n%s\n[R]un the persona (default) | [L]ist persona's | [C]ancel " "${HR}"
	read ans
	if [ -z "${ans}" -o "${ans}" = "r" -o "${ans}" = "R" ]
	then
		personaLoad
	elif [ "${ans}" = "l" -o "${ans}" = "L" ]
	then
		personaList
	elif [ "${ans}" = "c" -o "${ans}" = "C" -o "${ans}" = "q" -o "${ans}" = "Q" ]
	then
		quit
	else
		invalidOpt
	fi
}
personaDelete () {
	printf "\nIMPORTANT: A deleted persona can not be restored.\n\nThe following directory and all files within will be removed:\n\n %s\n\nDo you really want to remove the persona? [y/n] " "${PERSONA}"
	read ans
	if [ "${ans}" = "y" -o "${ans}" = "Y" ]
	then
		printf "\nRemoving the persona\n"
		rm -rf "${PERSONA}"
	elif [ "${ans}" = "n" -o "${ans}" = "N" ]
	then
		printf "\nAs requested, no files have been removed.\n"
	else
		quit "No action performed as the option was invalid."
	fi
	printf "\nWhat to do now?\n%s\n[L]ist persona's (default) | [C]ancel " "${HR}"
	read ans
	if [ -z "${ans}" -o "${ans}" = "l" -o "${ans}" = "L" -o "${ans}" = "a" -o "${ans}" = "A" ]
	then
		personaList
	elif [ "${ans}" = "c" -o "${ans}" = "C" -o "${ans}" = "q" -o "${ans}" = "Q" ]
	then
		quit
	else
		invalidOpt
	fi
}
personaView () {
	# View is an interesting option. Unsure how to use it yet :)
	printf "\nChecking for any files or details.\n"
	listDir="$(find "${PERSONA}" -mindepth 1 -type d | sed "s#${PERSONA}/##")"
	listFile="$(find "${PERSONA}" -maxdepth 1 -type f | sed "s#${PERSONA}/##")"

	printf "\n%s\n" "$(utilGetTitle "${PERSONA}")"

	if [ -n "${listFile}" ]
	then
		printf "\nBase level files:\n"
		printf " - %s\n" ${listFile}
	else
		printf "\nNo base level files.\n"
	fi
	if [ -z "${listDir}" ]
	then
		printf "\nNo base level directories.\n"
	else
		printf "\nBase level directories and contents.\n"
		IFS="
"
		for d in ${listDir}
		do
			printf " - %s/\n" "${d}"
			listFile="$(find "${PERSONA}/${d}" -mindepth 1 | sed "s#${PERSONA}/${d}/##")"
			if [ -n "${listFile}" ]
			then
				printf "   - %s\n" ${listFile}
			else
				printf "   - <empty>\n"
			fi
		done
		unset IFS
	fi
	# What's next
	printf "\nWhat to do now?\n%s\n[R]un the persona (default) | [L]ist persona's | [C]ancel " "${HR}"
	read ans
	if [ -z "${ans}" -o "${ans}" = "r" -o "${ans}" = "R" ]
	then
		personaLoad
	elif [ "${ans}" = "l" -o "${ans}" = "L" ]
	then
		personaList
	elif [ "${ans}" = "c" -o "${ans}" = "C" -o "${ans}" = "q" -o "${ans}" = "Q" ]
	then
		quit
	else
		invalidOpt
	fi
}
# Create a new persona
personaNew () {
	printf "\nCreating a new persona.\n\nWhat do you want to call this persona?\n\n"
	read ans
	if [ -z "${ans}" ]
	then
		quit "No persona title given. Assuming cancellation."
	else
		# Need a file safe name
		pName="${ans}"
		fName="$(printf "%s\n" "${pName}" | sed 's/ /_/g' | tr -cd '0-9a-zA-Z_-')"
		#printf "\nfName:[%s]\nans:[%s]\n" "${fName}" "${ans}"
		# Make the directory structure
		mkdir -p "${PERSONA_BASE}/${fName}/store" "${PERSONA_BASE}/${fName}/wip"
		if [ ${?} -ne 0 ]
		then
			printf "\nUnable to make the persona directory. Best guess: do not have write\npermission. Can you check this?\n\n" >&2
			exit 1
		fi

# Changes
		printf "\nA blank space has been created. You can now use a text editor to make\na persona file by hand or ask Gemini CLI to give you a hand with it.\n\nWhat would you like to do?\n%s\n[E]dit by hand (default) | [G]emini can help | [C]ancel " "${HR}"
		read ans
		if [ -z "${ans}" -o "${ans}" = "e" -o "${ans}" = "E" ]
		then
			# Add a blank .md
			# A default blank template for a new persona
			persona_blank="# SYSTEM INSTRUCTION: <cortex.sh Blank> Persona

<Anything between '<' and '>' should be replace by you using standard Markdown syntax. This is where you write what skills your want Gemini to focus on. For example: You are a **POSIX compliant** **shell script master** that will share your knowledge. You are aware of all shell script languages.>

## <SAMPLE FOCUS>

<1. When possible offer suggestions that can run in the **/bin/sh** environment.
2. **Performance** and **maintainability** are the top priorities.
3. **printf** should be used instead of "echo" when possible.
4. Use a **concise explanation** of why sample code works or fails.>

## <TONE AND LANGUAGE>

<1. All responses will be in **Australian English**.
2. Where possible include **light humour** with **slight surreal aspects**.>

## <ANYTHING ELSE>

<1. Use plan, concise language to explain what you want. 
2. Add what you need and edit to improve.>
"
			printf "%s\n" "${persona_blank}" | sed "s/<cortex.sh Blank>/${pName}/" > "${PERSONA_BASE}/${fName}/${fName}.md"
			"${PERSONA_EDITOR}" "${PERSONA_BASE}/${fName}/${fName}.md"

		elif [ "${ans}" = "g" -o "${ans}" = "G" ]
		then
			printf "# SYSTEM INSTRUCTION: %s Persona\n" "${pName}" > "${PERSONA_BASE}/${fName}/${fName}.md"
			cd "${PERSONA_BASE}/${fName}"
			printf "\nStarting Gemini CLI. This can take a moment.\n"
			gemini --prompt-interactive "You are a Gemini CLI wizard, happy to help. You will help me create a custom GEMINI.md file and you will ask a few key questions to make sure my needs are met. Once we are happy with the options, offer to amend the details to the existing file '${fName}.md'. At the moment, all I have is a single line in this file. It is important that this first line remains unchanged, but everything else can change. What kind of details do you need from me to get started?"
		elif [ "${ans}" = "c" -o "${ans}" = "C" -o "${ans}" = "q" -o "${ans}" = "Q" ]
		then
			rm -rf "${PERSONA_BASE}/${fName}"
			quit
		else
			rm -rf "${PERSONA_BASE}/${fName}"
			invalidOpt
		fi

		if [ -f "${PERSONA_BASE}/${fName}/${fName}.md" ]
		then
			printf "\nThe persona file has been saved.\nWhat is next?\n%s\n[R]un Gemini with the new persona (default) | [C]ancel "
			read ans
			if [ -z "${ans}" -o "${ans}" = "r" -o "${ans}" = "R" -o "${ans}" = "g" -o "${ans}" = "G" ]
			then
				PERSONA="${PERSONA_BASE}/${fName}/${fName}.md"
				personaLoad
			elif [ "${ans}" = "c" -o "${ans}" = "C" -o "${ans}" = "q" -o "${ans}" = "Q" ]
			then
				quit
			else
				invalidOpt
			fi
		else
			# A missing persona file.
			printf "\nWas expecting to locate a persona file, but it is missing.\n\nPossible there is a write permission issue, or the file was removed\n(somehow) after it was made.\n\nEither way, we can not continue.\n\n" >&2
			exit 1
		fi
	fi
}

# Show the PERSONA_LIST and the options for that list.
personaLoop () {
	# Display a list with options.
	printf "\nFound the following persona(s)\n\n"
	# We grab the first line of the persona and present that instead of
	# the file name.
	# NOTE: This expects the first line to be populated with a known
	# Markdown title.
	count=1
	IFS="
"
	for p in ${PERSONA_LIST}
	do
		printf " %2d) %s\n" ${count} "$(utilGetTitle "${p}")"
		count=$((count + 1))
	done
	unset IFS
	printf "\n%s\nUse [number] | [N]ew | [E]dit | [D]elete | [V]iew | [C]ancel " "${HR}" 
	read ans
	mode="load"
	if [ "$(isNumber "${ans}")" = "yes" ]
	then
		personaSet ${ans}
	elif [ "${ans}" = "n" -o "${ans}" = "N" ]
	then
		personaNew
		return 0
	elif [ "${ans}" = "e" -o "${ans}" = "E" ]
	then
		#mode="edit"
		personaOption "edit"
	elif [ "${ans}" = "d" -o "${ans}" = "D" ]
	then
		#mode="delete"
		personaOption "delete"
	elif [ "${ans}" = "v" -o "${ans}" = "V" ]
	then
		#mode="view"
		personaOption "view"
	elif [ "${ans}" = "c" -o "${ans}" = "C" -o "${ans}" = "q" -o "${ans}" = "Q" ]
	then
		quit
	else
		invalidOpt
	fi
	if [ -z "${PERSONA}" ]
	then
		printf "\nInvalid persona number. Try again? [Y/n] "
		read ans
		if [ -z "${ans}" -o "${ans}" = "y" -o "${ans}" = "Y" ]
		then
			personaLoop
			return 0
		else
			quit
		fi
	else
		if [ "${mode}" = "load" ]
		then
			personaLoad
		elif [ "${mode}" = "edit" ]
		then
			personaEdit
		elif [ "${mode}" = "delete" ]
		then
			personaDelete
		elif [ "${mode}" = "view" ]
		then
			personaView
		fi
	fi
}

# We accept $1 as edit, delete, view
personaOption () {
	mode="${1}"
	if [ "${mode}" = "edit" -o "${mode}" = "delete" -o "${mode}" = "view" ]
	then
		printf "\nWhich persona do you want to %s? [number] | [B]ack " "${mode}"
		read ans
		if [ "$(isNumber "${ans}")" = "yes" ]
		then
			personaSet ${ans}
			return "${?}"
		else
			# Head back and redo the options.
			personaLoop
			return
		fi
	else
		invalidOpt
	fi
}

# Set PERSONA to the choice value ($1) from PERSONA_LIST
# $1 should be already checked to be a number before calling this function.
# return 0 when PERSONA has been set, 1 otherwise.
personaSet () {
	want=${1}
	if [ -z "${PERSONA_LIST}" -o -z "${want}" ]
	then
		quit "Invaild call to personaSet."
	fi
	count=1
	IFS="
"
	for p in ${PERSONA_LIST}
	do
		md=${p##*/}
		if [ -f "${p}/${md}.md" ]
		then
			if [ ${count} -eq ${want} ]
			then
				PERSONA="${p}"
				break
			fi
			count=$((count + 1))
		fi
	done
	unset IFS
	if [ -n "${PERSONA}" ]
	then
		return 0
	else
		return 1
	fi
}

# If there is an RC, pull it in.
if [ -f "${BASE_RC}" ]
then
	. "${BASE_RC}"
fi

# Start main logic.
# System check
sysCheck
editorCheck

while getopts hv o
do
	case $o in
		h)
			usage;;
		v)
			printf "\nNOT DONE\n\n"
			exit;;
		\?)
			usage;;
	esac	
done

# This will make any extra args be starting at ${1}
shift $((OPTIND - 1))

# Get the list of persona's
personaList "${1}"


