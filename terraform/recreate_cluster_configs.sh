#!/bin/bash

mkdir /tmp/cluster 2>/dev/null

for file in $(ls cluster/* | grep -v template)
do
  > /tmp/$file.tmpres
  cat cluster/template | while read line
  do
    echo "$line" | grep -q "="
    if [ $? -eq 0 ];then
      var=$( cat $file | grep ^"$line" | head -1 | awk -F"=" {'print $2'} )
      [[ -z $var ]] && echo "WARNING. Missing $line variable on $file"
      echo "$line$var" >> /tmp/$file.tmpres
    else
      echo "$line" >> /tmp/$file.tmpres
    fi
  done
  diff $file /tmp/$file.tmpres >/dev/null 2>&1
  [[ $? -ne 0 ]] && echo "mv /tmp/$file.tmpres $file" 
done
