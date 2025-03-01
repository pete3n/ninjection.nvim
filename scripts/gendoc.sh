#! /bin/sh
mkdir -p ../doc
nvim --headless -c 'luafile ./mini-doc.lua' -c 'qa!' &&
cat introduction.txt ../doc/ninjection.txt > ../doc/ninjection_final.txt &&
mv ../doc/ninjection_final.txt ../doc/ninjection.txt
pwd
ls -la ../doc
