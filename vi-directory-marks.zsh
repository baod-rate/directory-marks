function vi-dir-marks::mark(){
	emulate -L zsh
	local delay
	zstyle -s ':plugin:vi-directory-marks' sync-delay delay || delay=30

	local REPLY
	[[ -n ${REPLY:=$1} ]] || read -k1
	dir_marks[$REPLY]=${${2:a}:-$PWD}
	# schedule cache writeout
	if [[ $REPLY = [[:upper:]] && ! ${(M)zsh_scheduled_events:#*vi-dir-marks::sync} ]]; then
		add-zsh-hook zshexit vi-dir-marks::sync
		sched +$delay vi-dir-marks::sync
	fi
}

function vi-dir-marks::jump(){
	emulate -L zsh

	local REPLY
	[[ -n ${REPLY:=${1[1]}} ]] || read -k1
	if [[ -n $dir_marks[$REPLY] ]] && cd ${dir_marks[$REPLY]#*:} &>/dev/null; then
		for f (chpwd $chpwd_functions precmd $precmd_functions)
			(($+functions[$f])) && $f &>/dev/null
		zle .reset-prompt
		zle -R
	fi
}

function vi-dir-marks::sync(){
	emulate -L zsh
	local marks_file
	zstyle -s ':plugin:vi-directory-marks' marks-file marks_file ||
		marks_file="${XDG_STATE_HOME:-${XDG_DATA_HOME:-$HOME/.local/data}}/zsh/vi-dir-marks.cache"

	local -i fd period
	if [[ $1 != noflock ]] {
		if { zstyle -s ':plugin:vi-directory-marks' period period && [[ ! ${(M)zsh_scheduled_events:#*vi-dir-marks::sync periodic} ]] } {
			sched +$period vi-dir-marks::sync periodic
		}

		if { zsystem supports flock } {
			[[ -d ${marks_file:h} ]] || mkdir -p ${marks_file:h} || return
			[[ -e $marks_file ]] || touch $marks_file || return
			zsystem flock -f fd $marks_file || return
			{
				vi-dir-marks::sync noflock
				return
			} always {
				zsystem flock -u fd
			}
		}
	}

	# read global marks from file; retaining ones in current shell
	typeset -Ag dir_marks
	local file_marks
	[[ -r $marks_file ]] &&
		file_marks="$(<$marks_file)" &&
		[[ -n "$file_marks" ]] &&
		dir_marks=("${(@fQ)file_marks}" "${(@kv)dir_marks}")

	# write out new global marks
	if (($#dir_marks)) {
		dir_marks=("${(@kv)dir_marks[(R)?*]}")
		[[ -d ${marks_file:h} ]] || mkdir -p ${marks_file:h}
		printf '%q\n' "${(@kv)dir_marks[(I)[[:upper:]]]}" >| $marks_file
		zcompile $marks_file
	}

	add-zsh-hook -d zshexit vi-dir-marks::sync
}

function vi-dir-marks::delete(){
	emulate -L zsh
	local mark=${1:?}
	dir_marks[$mark]=''
	vi-dir-marks::sync
	unset "dir_marks[$mark]"
}

function vi-dir-marks::list(){
	emulate -L zsh
	print -raC2 "${(@kv)dir_marks}"
	if (($+WIDGET)); then
		zle .reset-prompt
		zle -R
	fi
}

(){
	emulate -L zsh

	typeset -gA dir_marks

	autoload add-zsh-hook
	zmodload zsh/datetime
	zmodload zsh/sched
	zmodload zsh/system

	zle -N mark-dir vi-dir-marks::mark
	zle -N jump-dir vi-dir-marks::jump
	zle -N marks    vi-dir-marks::list

	bindkey -M vicmd 'm' mark-dir "'" jump-dir '`' jump-dir

	vi-dir-marks::sync noflock

	local period
	if { zstyle -s ':plugin:vi-directory-marks' period period && [[ ! ${(M)zsh_scheduled_events:#*vi-dir-marks::sync periodic} ]] } {
		sched +${period} vi-dir-marks::sync periodic
	}
}
