# gcenv bash completion script
# Installation: source from .bashrc after sourcing gcenv.sh:
#   source ~/.gcenv/completions/gcenv.bash
# Or place in /etc/bash_completion.d/

_gcenv_complete() {
  local cur="${COMP_WORDS[COMP_CWORD]}"
  local prev="${COMP_WORDS[COMP_CWORD-1]}"
  local cmds="init import use deactivate login set-adc list status delete version help"
  local envs
  envs=$(gcloud config configurations list --format='value(name)' 2>/dev/null | tr '\n' ' ')

  if [ "$COMP_CWORD" -eq 1 ]; then
    COMPREPLY=($(compgen -W "$cmds" -- "$cur"))
  elif [ "$COMP_CWORD" -eq 2 ]; then
    case "$prev" in
      use|import|delete|set-adc) COMPREPLY=($(compgen -W "$envs" -- "$cur")) ;;
    esac
  fi
}
complete -F _gcenv_complete gcenv
