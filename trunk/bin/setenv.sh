#!/bin/bash

log_debug() {
    local do_log=""
    if [ -n "$MAGIC_LOG_LEVEL" ]; then
        if [ "$MAGIC_LOG_LEVEL" = "DEBUG" ]; then
            do_log=y
        else
            if [ "$MAGIC_LOG_LEVEL" = "INFO" ] || [ "$MAGIC_LOG_LEVEL" = "WARN" ] || [ "$MAGIC_LOG_LEVEL" = "ERROR" ] ; then
                :
            else
                echo "Invalid MAGIC_LOG_LEVEL: [$MAGIC_LOG_LEVEL], unable to continue" >&2
                exit 1
            fi
        fi
    else
        do_log=y
    fi

    if [ -n "$do_log" ]; then
        if [ "`echo -- $* | grep -- '--quiet'`" != "" ]; then
            echo "`date ` $0 ($$) DEBUG: $*"
        fi
    fi
}

print_current_environment() {
    if [ "`echo $ARCHIVE_ROOT | grep ^/home`" ]; then
        log_debug "current environment: $ARCHIVE_ROOT"
    fi
}

_aconsole()
{
    local cur prev opts
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"
    opts=""

    executable=`which aconsole.pl 2>/dev/null`
    if [ -x $executable ]; then
        opts="`$executable --bash-completion-list $prev $cur`"
        if [ "$opts" = "compgen_file" ]; then
            COMPREPLY=( $(compgen -f ${cur}) )
        elif [ "$opts" = "compgen_dir" ]; then
            COMPREPLY=( $(compgen -d ${cur}) )
        else
            COMPREPLY=( $(compgen -W "${opts}" -- ${cur}) )
        fi
    fi

    return 0
}

if [ -n "$SETENV_BASHRC" ]; then
    if [ -e ~/.bashrc ]; then
        . ~/.bashrc
    fi

    complete -F _aconsole aconsole.pl

    unset SETENV_BASHRC

    # set command prompt
    export PS1='env: \u@\h:\w# '
else
    if [ -n "$ARCHIVE_ROOT" ]; then
        print_current_environment
        echo "to switch press CTRL-D and start me again"
        exit 0
    fi

    me=$0
    while [ "`readlink $me`" != "" ]; do
        me="`readlink $me`"
    done

    startpath=`dirname $me`
    startpath=`cd $startpath ; pwd`
    ARCHIVE_ROOT="`echo $startpath | sed "s%/bin%%"`"
    export ARCHIVE_ROOT

    PERL5LIB=$ARCHIVE_ROOT/lib:$PERL5LIB
    export PERL5LIB

    PATH=$ARCHIVE_ROOT/bin:$PATH
    if [ "`echo $PATH | grep /usr/local/bin`" = "" ]; then
        PATH=/usr/local/bin:$PATH
    fi
    export PATH

    export ORACLE_HOME=/home/kohts/instantclient_12_2
    export LD_LIBRARY_PATH=/home/kohts/instantclient_12_2

    print_current_environment

    export SETENV_BASHRC=1
    if [ -n "$*" ]; then
        /bin/bash --rcfile $0 -c "$*"
    else
        /bin/bash --rcfile $0
    fi
fi
