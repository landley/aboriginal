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
<td>
<a href=bootlog-$1.txt>boot log</a></li>
<a href=../bin/cross-compiler-$1.tar.bz2>cross&nbsp;compiler</a><br>
<a href=../bin/native-compiler-$1.tar.bz2>native&nbsp;compiler</a><br>
<a href=../bin/root-filesystem-$1.tar.bz2>root&nbsp;filesystem</a><br>
<a href=../bin/system-image-$1.tar.bz2>system&nbsp;image</a><br>

<hr />
<a href=../bin/busybox-$1>busybox&nbsp;binary</a><br>
<a href=../bin/dropbearmulti-$1>dropbear&nbsp;binary</a><br>
<a href=../bin/strace-$1>strace&nbsp;binary</a><br>
</ul></td>
EOF

  echo '<td>'
  echo '<table bgcolor=#000000><tr><td><font color=#ffffff size=-2><pre>'
  process_text_file "bootlog-$1.txt"
  echo '</pre></font></td></tr></table></td>'
  echo
  echo '</tr></table></td>'
}

# Harvest screenshots from each system image

more/for-each-target.sh '(sleep 20 && echo -n cat "/proc" && sleep 1 && echo /cpuinfo && sleep 2 && echo exit) | more/run-emulator-from-build.sh $TARGET | tee www/screenshots/bootlog-$TARGET.txt'

cd www/screenshots

# Filter out escape sequence (shell asking the current screen size)
sed -i $(echo -e 's/\033\[6n//g;s/\015$//') bootlog-*.txt

# Create html snippet

for i in $(ls bootlog-*.txt | sed 's/bootlog-\(.*\)\.txt/\1/')
do
  wrap_screenshot "$i" > "screenshot-$i.html"
done
