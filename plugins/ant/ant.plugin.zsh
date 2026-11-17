# Default to colored output while preserving user-provided Ant arguments.
if [[ -z ${ANT_ARGS-} ]]; then
  export ANT_ARGS='-logger org.apache.tools.ant.listener.AnsiColorLogger'
else
  export ANT_ARGS
fi
