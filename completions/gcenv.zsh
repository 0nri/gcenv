#compdef gcenv
# gcenv zsh completion script
# Installation: place in a directory on $fpath (e.g., /usr/local/share/zsh/site-functions/)
# or add to .zshrc after sourcing gcenv.sh:
#   autoload -Uz compinit && compinit
#   fpath=(~/.gcenv/completions $fpath)

_gcenv() {
  local -a cmds envs
  cmds=(
    'init:Create config + authenticate + capture ADC'
    'import:Snapshot current gcloud state'
    'use:Activate environment in this shell'
    'deactivate:Return to system default gcloud state'
    'login:Re-authenticate the active environment'
    'set-adc:Point environment at a service account key file'
    'list:Show environments and ADC status'
    'status:Show active environment details'
    'delete:Remove environment and its ADC'
    'version:Print gcenv version'
    'help:Show usage'
  )
  envs=(${(f)"$(gcloud config configurations list --format='value(name)' 2>/dev/null)"})

  case $CURRENT in
    2) _describe 'command' cmds ;;
    3) case $words[2] in
         use|import|delete|set-adc) _describe 'environment' envs ;;
       esac ;;
  esac
}
_gcenv "$@"
