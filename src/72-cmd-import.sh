# shellcheck shell=bash
#
# hosts import - merge entries from another file.

declare -a IMPORT_RAW=()
declare -a IMPORT_IP=()
declare -a IMPORT_FAMILY=()
declare -a IMPORT_NAMES=()
IMPORT_VERDICT=''

cmd_import() {
  local source='' target
  local -a positional=()
  local -i added=0 skipped=0 present=0

  while (($#)); do
    case $1 in
      -h | --help)
        help_import
        return "$EX_OK"
        ;;
      --)
        shift
        positional+=("$@")
        break
        ;;
      -)
        # A lone dash is the usual way of naming standard input, not an option.
        positional+=("$1")
        shift
        ;;
      -*)
        die_usage 'import ' "unknown option for 'import': $1"
        ;;
      *)
        positional+=("$1")
        shift
        ;;
    esac
  done

  if ((${#positional[@]} > 1)); then
    die_usage 'import ' 'import reads one file, or standard input'
  fi
  source=${positional[0]:-'-'}

  resolve_path "$OPT_FILE" || die "$EX_ERROR" "cannot resolve $OPT_FILE"
  target=$RESOLVED_PATH

  _import_read_source "$source"

  hostsfile_load "$target"
  edit_reset

  local -i i
  for ((i = 0; i < ${#IMPORT_RAW[@]}; i++)); do
    _import_verdict "$i"
    case $IMPORT_VERDICT in
      present)
        present=$((present + 1))
        ;;
      clash)
        warn "${IMPORT_NAMES[i]} overlaps what is already there; line skipped"
        skipped=$((skipped + 1))
        ;;
      *)
        edit_append "${IMPORT_RAW[i]}"
        added=$((added + 1))
        ;;
    esac
  done

  info "$added added, $present already there, $skipped skipped"

  edit_commit "$target" "import $added entry(ies)"
}

# Read the source, refusing it whole if any of it is wrong.
#
# Importing half of a broken file leaves a machine in a state nobody can
# explain later, so the source is checked before a single line is written.
_import_read_source() {
  local source=$1 scratch=''
  local -i i errors=0

  if [[ $source == '-' ]]; then
    scratch=$(mktemp) || die "$EX_ERROR" 'cannot create a temporary file'
    ATOMIC_SCRATCH=$scratch
    trap atomic_cleanup EXIT
    cat >"$scratch"
    source=$scratch
  fi

  hostsfile_load "$source"

  _ck_rule=()
  _ck_severity=()
  _ck_line=()
  _ck_related=()
  _ck_subject=()
  _ck_message=()
  _check_scan

  for ((i = 0; i < ${#_ck_rule[@]}; i++)); do
    [[ ${_ck_severity[i]} == 'error' ]] || continue
    errors=$((errors + 1))
    err "$source:${_ck_line[i]}: ${_ck_rule[i]}: ${_ck_message[i]}"
  done

  if ((errors > 0)); then
    die "$EX_VALIDATION" \
      "$source has $errors error(s); run '$PROGRAM_NAME --file $source check'"
  fi

  # Only the active entries are taken. A commented out line in someone else's
  # file is a note to themselves, not something to carry over.
  IMPORT_RAW=()
  IMPORT_IP=()
  IMPORT_FAMILY=()
  IMPORT_NAMES=()

  for ((i = 0; i < _hf_count; i++)); do
    [[ ${_hf_kind[i]} == 'entry' ]] || continue
    ((_hf_enabled[i])) || continue
    IMPORT_RAW+=("${_hf_raw[i]}")
    IMPORT_IP+=("${_hf_ip[i]}")
    IMPORT_FAMILY+=("${_hf_family[i]}")
    IMPORT_NAMES+=("${_hf_names[i]}")
  done

  if [[ -n $scratch ]]; then
    atomic_cleanup
    trap - EXIT
  fi

  info "read ${#IMPORT_RAW[@]} entry(ies) from $source"
}

# Say what should happen to one imported entry, in IMPORT_VERDICT.
#
# An entry is taken or left as a whole: a line half imported, with some of its
# names kept and some dropped, is not something the file can express, and
# adding it anyway would leave a name on two lines at once. So an entry whose
# names are all already pointing at the same address counts as present, one
# whose names are entirely unknown in that family counts as new, and anything
# in between is left alone and reported.
_import_verdict() {
  local -i i=$1
  local address=${IMPORT_IP[i]} family=${IMPORT_FAMILY[i]}
  local name
  local -a names=() candidates=()
  local -i index known=0 matching=0 total=0

  split_on_whitespace "${IMPORT_NAMES[i]}"
  names=("${FIELDS[@]}")

  for name in "${names[@]}"; do
    total=$((total + 1))
    split_on_whitespace "${_hf_by_name[${name,,}]:-}"
    candidates=("${FIELDS[@]}")

    for index in "${candidates[@]}"; do
      [[ ${_hf_family[index]} == "$family" ]] || continue
      known=$((known + 1))
      if ((_hf_enabled[index])) && [[ ${_hf_ip[index]} == "$address" ]]; then
        matching=$((matching + 1))
      fi
      break
    done
  done

  if ((known == 0)); then
    IMPORT_VERDICT='new'
  elif ((matching == total)); then
    IMPORT_VERDICT='present'
  else
    IMPORT_VERDICT='clash'
  fi

  return 0
}
