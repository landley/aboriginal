#!/bin/bash

escape_screenshot()
{
  echo '</center></td></tr><tr>'

  cat << EOF
<td><ul>
<li><a href=screenshot-$1.txt>screenshot</a></li>
<li><a href=cross-compiler-$1.tar.bz2>cross compiler</a></li>
<li><a href=native-compiler-$1.tar.bz2>native compiler</a></li>
<li><a href=root-filesystem-$1.tar.bz2>root filesystem</a></li>
<li><a href=system-image-$1.tar.bz2>system image</a></li>

<hr />

<li><a href=busybox-$1>busybox binary</a></li>
<li><a href=dropbearmulti-$1>dropbear binary</a></li>
<li><a href=strace-$1>strace binary</a></li>
</ul></td>
EOF


  echo '<td>'
  echo '<table bgcolor=#000000><tr><td><font color=#ffffff size=-2><pre>'

  i=0
  while [ $i -lt 80 ]
  do
    echo -n '&nbsp;'
    i=$[$i+1]
  done
  echo
  sed -e 's/\(................................................................................\)/\1\n/g' \
      -e 's@\&@\&amp;@g' -e 's@<@\&lt;@g' -e 's@>@\&gt;@g' \
      "screenshot-$1.txt" | tail -n 25

  echo '</pre></font></td></tr></table></td>'
  echo
  echo '</tr></table></td>'
}

process_screenshot()
{
  escape_screenshot "$1" > "screenshot-$1.html"
}

for i in *.txt
do
  process_screenshot "$(echo "$i" | sed 's/screenshot-\(.*\)\.txt/\1/')"
done
