#!/bin/sh

/mnt/build/generic-check.sh

# Create lex wrapper

cat > /usr/bin/lex << 'EOF' &&
#!/bin/sh

exiec /usr/bin/flex -l "$@"
EOF
chmod 755 /usr/bin/lex || exit 1

if [ ! -z "$DOCS" ]
then
  mkdir /usr/share/doc/flex &&
  cp doc/flex.pdf /usr/share/doc/flex
fi
