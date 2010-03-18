#!/bin/bash

# Take 80x25 screen shot from the end of a text file, and excape it for html.

process_text_file()
{
  X=0

  # Break into 80 line chunks, substituting &, < and >
  sed -e 's/\(................................................................................\)/\1\n/g' "$1" | \
  tail -n 25 | while read i
  do
    echo -n "$i" | sed -e 's@\&@\&amp;@g' -e 's@<@\&lt;@g' -e 's@>@\&gt;@g'

    # If the first line is shorter than 80 characters, pad it.
    if [ $X -eq 0 ]
    then
      X=${#i}
      while [ $X -lt 80 ]
      do
        echo -n '&nbsp;'
        X=$[$X+1]
      done
    fi
    echo
  done
}

wrap_screenshot()
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
  process_text_file "screenshot-$1.txt"
  echo '</pre></font></td></tr></table></td>'
  echo
  echo '</tr></table></td>'
}

for i in $(ls screenshot-*.txt | sed 's/screenshot-\(.*\)\.txt/\1/')
do
  wrap_screenshot "$i" > "screenshot-$i.html"
done
