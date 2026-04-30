: "${OLD_NAMESPACE:=}"

nl=$(printf '\nx')
nl=${nl%x}

___pop_namespace() {
    v=${OLD_NAMESPACE%%"$nl"*}

    case $OLD_NAMESPACE in
        *"$nl"*)
            OLD_NAMESPACE=${OLD_NAMESPACE#*"$nl"}
            ;;
        *)
            OLD_NAMESPACE=
            ;;
    esac

    printf '%s\n' "$v"
}

___peek_namespace() {
    printf '%s\n' "${OLD_NAMESPACE%%"$nl"*}"
}

___push_namespace() {
    if [ -n "$OLD_NAMESPACE" ]; then
        OLD_NAMESPACE=$1"$nl$OLD_NAMESPACE"
    else
        OLD_NAMESPACE=$1
    fi
}

change_namespace() {
  ___push_namespace "$HECTIC_NAMESPACE"
  export HECTIC_NAMESPACE="$1"
}

restore_namespace() {
  HECTIC_NAMESPACE=$(___pop_namespace)
  export HECTIC_NAMESPACE
}
