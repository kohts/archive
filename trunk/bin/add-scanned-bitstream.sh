#!/bin/sh

if [ "$1" = "add" ]; then
    add=y
fi

for i in `cat /tmp/1 | sort | awk '{print $1}'` ; do
    p=`cat /tmp/1 | grep "^${i} " | awk '{print $3}' | sed "s%ОФ-%of-%" | sed "s%\/%-%"`
    pat="`echo $p | cut -d"-" -f 1,2`-[0]*?`echo $p | cut -d"-" -f 3`$"
    p=`ls -1 /_gdm/raw-afk | grep -P "$pat"`
    
    if [ -z "$p" ]; then
        continue
    fi
    
    echo aconsole.pl --scan-add-scans $i --from /_gdm/raw-afk/$p
    if [ -n "$add" ]; then
        aconsole.pl --scan-add-scans $i --from /_gdm/raw-afk/$p
        e=$?

        if [ "$e" != "0" ]; then
            echo "exit code [$e]"
            exit $e
        fi
    fi
done

